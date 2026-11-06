// RTMPServerSession.cpp
// Reconstructed from RTMPServerSession::HandleAMF (0xA0B44).
// FMS version string "3,5,3,824" confirmed from binary strings.

#include "RTMPServerSession.h"
#include "AMF.h"
#include <string.h>
#include <stdexcept>

namespace librtmp {

RTMPServerSession::RTMPServerSession(RTMPEndpoint *endpoint)
    : _endpoint(endpoint), _streamId(1), _publishing(false),
      _naluLengthSize(4), _txId(0), _bytesReceived(0), _lastAckSent(0),
      _ackWindowSize(2500000)
{
    // On connect, send server-side window ack + peer bandwidth + chunk size
    sendWindowAckSize(2500000);
    sendSetPeerBandwidth(2500000, 2);  // 2 = dynamic
    sendSetChunkSize(4096);
}

RTMPServerSession::~RTMPServerSession() {}

// ─── Main loop ────────────────────────────────────────────────────────────────

H264Frame RTMPServerSession::GetRTMPMessage() {
    for (;;) {
        RTMPMessage msg = _endpoint->readMessage();
        uint32_t messageBytes = (uint32_t)msg.payload.size();
        _bytesReceived += messageBytes;
        if (_ackWindowSize > 0 &&
            _bytesReceived - _lastAckSent >= _ackWindowSize) {
            sendAck(_bytesReceived);
            _lastAckSent = _bytesReceived;
        }

        H264Frame frame;
        bool gotFrame = false;

        switch (msg.type) {
        case RTMP_MSG_COMMAND_AMF0:
        case RTMP_MSG_DATA_AMF0:
            handleAMF(msg);
            break;

        case RTMP_MSG_VIDEO:
            handleVideo(msg, frame, gotFrame);
            if (gotFrame) return frame;
            break;

        case RTMP_MSG_WINDOW_ACK_SIZE:
            handleWindowAckSize(msg);
            break;

        case RTMP_MSG_USER_CONTROL:
            handleUserControl(msg);
            break;

        case RTMP_MSG_ACKNOWLEDGEMENT:
            // ACK from client — ignore
            break;

        case RTMP_MSG_SET_CHUNK_SIZE:
            // Handled in RTMPEndpoint::readMessage transparently
            break;

        case RTMP_MSG_AUDIO:
            // Audio — discard (virtual camera only cares about video)
            break;

        default:
            break;
        }
    }
}

// ─── AMF command handling ─────────────────────────────────────────────────────
// Mirrors RTMPServerSession::HandleAMF (0xA0B44)

void RTMPServerSession::handleAMF(const RTMPMessage &msg) {
    if (msg.payload.empty()) return;

    try {
    AMFDecoder dec(msg.payload.data(), msg.payload.size());
    if (dec.empty()) return;

    AMFValue cmdVal = dec.decode();
    if (cmdVal.type != AMF0_STRING) return;
    const std::string &cmd = cmdVal.str;

    double txId = 0;
    if (!dec.empty()) {
        AMFValue txVal = dec.decode();
        if (txVal.type == AMF0_NUMBER) txId = txVal.number;
    }

    // ── connect ─────────────────────────────────────────────────────────────
    if (cmd == "connect") {
        // Acknowledge connection (see IDA 0xA0B44 → NetConnection.Connect.Success)
        sendConnectResult(txId);
        sendUserControl(RTMP_UCM_STREAM_BEGIN, 0);
    }
    // ── createStream ────────────────────────────────────────────────────────
    else if (cmd == "createStream") {
        sendCreateStreamResult(txId);
    }
    // ── publish ─────────────────────────────────────────────────────────────
    else if (cmd == "publish") {
        _publishing = true;
        sendUserControl(RTMP_UCM_STREAM_BEGIN, _streamId);
        sendPublishStart();
    }
    // ── @setDataFrame / onMetaData ───────────────────────────────────────────
    // (binary 0xA0B44: reads "videocodecid" field, checks for "avc1")
    else if (cmd == "@setDataFrame" || cmd == "onMetaData") {
        // Consume the metadata object — the video codec ID tells us AVC is used.
        // We don't need to act on this; the sequence header in the first video
        // message will provide the SPS/PPS.
    }
    // ── FCPublish / releaseStream / deleteStream ─────────────────────────────
    else if (cmd == "FCPublish" || cmd == "releaseStream" || cmd == "deleteStream") {
        // No-op responses needed by some encoders
        if (txId > 0) {
            AMFEncoder enc;
            enc.encodeString("_result");
            enc.encodeNumber(txId);
            enc.encodeNull();
            enc.encodeNull();
            std::vector<uint8_t> buf = enc.take();
            _endpoint->sendMessage(RTMP_MSG_COMMAND_AMF0, 0, 0, buf, 3);
        }
    }
    // ── ping / closeStream — ignore ──────────────────────────────────────────
    } catch (const std::exception &) {
        // Ignore malformed or unsupported AMF commands and keep the RTMP session alive.
    }
}

// ─── Video message handling ───────────────────────────────────────────────────
// Parses AVC video messages and extracts SPS/PPS or NAL units.
// NAL detection: IDA 0xA2CA0 checks data[0] & 0xFF == 0xe1 (numSPS in AVCC record)
// or data[0] == 0x67 (SPS NAL type).

void RTMPServerSession::handleVideo(const RTMPMessage &msg, H264Frame &frame, bool &gotFrame) {
    gotFrame = false;
    const std::vector<uint8_t> &p = msg.payload;
    if (p.size() < 5) return;

    uint8_t frameType = (p[0] >> 4) & 0x0F;  // 1=keyframe, 2=inter
    uint8_t codecId   = p[0] & 0x0F;         // 7=AVC
    if (codecId != 7) return;                 // only AVC

    uint8_t avcPacketType = p[1];             // 0=sequence header, 1=NALU, 2=EOS
    uint32_t ctsRaw = ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 8) | p[4];
    int32_t cts = (ctsRaw & 0x00800000) ? (int32_t)(ctsRaw | 0xFF000000) : (int32_t)ctsRaw;

    frame.isKeyframe        = (frameType == 1);
    frame.compositionTime   = cts;
    frame.timestamp         = msg.timestamp;

    if (avcPacketType == 0) {
        // ── AVC sequence header (AVCC record) ────────────────────────────────
        // Layout: configVersion(1) avcProfile(1) profileCompat(1) avcLevel(1)
        //         naluLenMinusOne(1) numSPS(1) spsLen(2) SPS ... numPPS(1) ppsLen(2) PPS ...
        frame.isSequenceHeader = true;
        if (p.size() < 11) return;

        size_t off = 5; // skip frame/codec/packetType/cts
        off += 4;       // configVersion + profile + compat + level
        if (off >= p.size()) return;
        uint8_t naluLengthSize = (p[off++] & 0x03) + 1;
        if (naluLengthSize != 1 && naluLengthSize != 2 && naluLengthSize != 4) return;
        _naluLengthSize = naluLengthSize;

        uint8_t numSPS = p[off++] & 0x1F; // lower 5 bits
        if (numSPS == 0) return;
        for (int i = 0; i < numSPS && off + 2 <= p.size(); i++) {
            uint16_t spsLen = ((uint16_t)p[off] << 8) | p[off+1];
            off += 2;
            if (off + spsLen > p.size()) return;
            frame.sps.assign(p.begin() + off, p.begin() + off + spsLen);
            off += spsLen;
        }
        if (off >= p.size() || frame.sps.empty()) return;
        uint8_t numPPS = p[off++];
        if (numPPS == 0) return;
        for (int i = 0; i < numPPS && off + 2 <= p.size(); i++) {
            uint16_t ppsLen = ((uint16_t)p[off] << 8) | p[off+1];
            off += 2;
            if (off + ppsLen > p.size()) return;
            frame.pps.assign(p.begin() + off, p.begin() + off + ppsLen);
            off += ppsLen;
        }
        gotFrame = true;

    } else if (avcPacketType == 1) {
        // ── AVC NAL units — keep AVCC format: [4-byte-BE-len][NALU][...] ────
        // The original binary passes this data directly to
        // CMBlockBufferCreateWithMemoryBlock without any prefix manipulation.
        frame.isSequenceHeader = false;
        size_t off = 5;
        const size_t lengthBytes = _naluLengthSize;
        while (off + lengthBytes <= p.size()) {
            uint32_t naluLen = 0;
            for (size_t i = 0; i < lengthBytes; i++)
                naluLen = (naluLen << 8) | p[off + i];
            if (naluLen == 0) { off += lengthBytes; continue; }
            if (off + lengthBytes + naluLen > p.size()) {
                frame.nalu.clear();
                return;
            }
            // Normalize to 4-byte AVCC prefixes for VideoToolbox.
            size_t prevSize = frame.nalu.size();
            frame.nalu.resize(prevSize + 4 + naluLen);
            frame.nalu[prevSize + 0] = (naluLen >> 24) & 0xFF;
            frame.nalu[prevSize + 1] = (naluLen >> 16) & 0xFF;
            frame.nalu[prevSize + 2] = (naluLen >> 8) & 0xFF;
            frame.nalu[prevSize + 3] = naluLen & 0xFF;
            memcpy(&frame.nalu[prevSize + 4], &p[off + lengthBytes], naluLen);
            off += lengthBytes + naluLen;
        }
        if (off != p.size()) {
            frame.nalu.clear();
            return;
        }
        if (!frame.nalu.empty()) gotFrame = true;
    }
    // avcPacketType == 2 (EOS) → ignore
}

// ─── Control message helpers ──────────────────────────────────────────────────

void RTMPServerSession::handleWindowAckSize(const RTMPMessage &msg) {
    if (msg.payload.size() < 4) return;
    _ackWindowSize = ((uint32_t)msg.payload[0] << 24) |
                     ((uint32_t)msg.payload[1] << 16) |
                     ((uint32_t)msg.payload[2] << 8) |
                     msg.payload[3];
}

void RTMPServerSession::handleUserControl(const RTMPMessage &msg) {
    (void)msg; // handled by endpoint or ignored
}

// ─── Response builders ────────────────────────────────────────────────────────

void RTMPServerSession::sendConnectResult(double txId) {
    AMFEncoder enc;
    enc.encodeString("_result");
    enc.encodeNumber(txId);

    // Properties object
    enc.beginObject();
      enc.encodeKey("fmsVer");    enc.encodeString("FMS/3,5,3,824");
      enc.encodeKey("capabilities"); enc.encodeNumber(31);
      enc.encodeKey("mode");      enc.encodeNumber(1);
    enc.endObject();

    // Info object
    enc.beginObject();
      enc.encodeKey("level");       enc.encodeString("status");
      enc.encodeKey("code");        enc.encodeString("NetConnection.Connect.Success");
      enc.encodeKey("description"); enc.encodeString("Connection succeeded.");
      enc.encodeKey("data");
        enc.beginObject();
          enc.encodeKey("version"); enc.encodeString("3,5,3,824");
        enc.endObject();
      enc.encodeKey("clientid");  enc.encodeNumber(1);
      enc.encodeKey("objectEncoding"); enc.encodeNumber(0);
    enc.endObject();

    std::vector<uint8_t> buf = enc.take();
    _endpoint->sendMessage(RTMP_MSG_COMMAND_AMF0, 0, 0, buf, 3);
}

void RTMPServerSession::sendCreateStreamResult(double txId) {
    AMFEncoder enc;
    enc.encodeString("_result");
    enc.encodeNumber(txId);
    enc.encodeNull();
    enc.encodeNumber((double)_streamId);
    std::vector<uint8_t> buf = enc.take();
    _endpoint->sendMessage(RTMP_MSG_COMMAND_AMF0, 0, 0, buf, 3);
}

void RTMPServerSession::sendPublishStart() {
    AMFEncoder enc;
    enc.encodeString("onStatus");
    enc.encodeNumber(0); // txId=0 for notifications
    enc.encodeNull();
    enc.beginObject();
      enc.encodeKey("level");       enc.encodeString("status");
      enc.encodeKey("code");        enc.encodeString("NetStream.Publish.Start");
      enc.encodeKey("description"); enc.encodeString("Publishing.");
    enc.endObject();
    std::vector<uint8_t> buf = enc.take();
    _endpoint->sendMessage(RTMP_MSG_COMMAND_AMF0, _streamId, 0, buf, 5);
}

void RTMPServerSession::sendWindowAckSize(uint32_t size) {
    uint8_t b[4];
    b[0] = (size >> 24) & 0xFF; b[1] = (size >> 16) & 0xFF;
    b[2] = (size >>  8) & 0xFF; b[3] = size & 0xFF;
    _endpoint->sendControl(RTMP_MSG_WINDOW_ACK_SIZE, std::vector<uint8_t>(b, b+4));
}

void RTMPServerSession::sendSetPeerBandwidth(uint32_t size, uint8_t limitType) {
    uint8_t b[5];
    b[0] = (size >> 24) & 0xFF; b[1] = (size >> 16) & 0xFF;
    b[2] = (size >>  8) & 0xFF; b[3] = size & 0xFF;
    b[4] = limitType;
    _endpoint->sendControl(RTMP_MSG_SET_PEER_BANDWIDTH, std::vector<uint8_t>(b, b+5));
}

void RTMPServerSession::sendUserControl(uint16_t eventType, uint32_t eventData) {
    uint8_t b[6];
    b[0] = (eventType >> 8) & 0xFF; b[1] = eventType & 0xFF;
    b[2] = (eventData >> 24) & 0xFF; b[3] = (eventData >> 16) & 0xFF;
    b[4] = (eventData >>  8) & 0xFF; b[5] = eventData & 0xFF;
    _endpoint->sendControl(RTMP_MSG_USER_CONTROL, std::vector<uint8_t>(b, b+6));
}

void RTMPServerSession::sendSetChunkSize(uint32_t size) {
    uint8_t b[4];
    b[0] = (size >> 24) & 0xFF; b[1] = (size >> 16) & 0xFF;
    b[2] = (size >>  8) & 0xFF; b[3] = size & 0xFF;
    _endpoint->sendControl(RTMP_MSG_SET_CHUNK_SIZE, std::vector<uint8_t>(b, b+4));
}

void RTMPServerSession::sendAck(uint32_t seqNum) {
    uint8_t b[4];
    b[0] = (seqNum >> 24) & 0xFF; b[1] = (seqNum >> 16) & 0xFF;
    b[2] = (seqNum >>  8) & 0xFF; b[3] = seqNum & 0xFF;
    _endpoint->sendControl(RTMP_MSG_ACKNOWLEDGEMENT, std::vector<uint8_t>(b, b+4));
}

} // namespace librtmp
