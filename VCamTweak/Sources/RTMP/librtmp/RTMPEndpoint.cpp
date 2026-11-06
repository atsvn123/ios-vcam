// RTMPEndpoint.cpp
// RTMP chunk-layer implementation.
// Protocol reference: Adobe RTMP specification rev 2012-12-21

#include "RTMPEndpoint.h"
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <stdexcept>

namespace librtmp {

static const uint32_t DEFAULT_IN_CHUNK_SIZE  = 128;
static const uint32_t DEFAULT_OUT_CHUNK_SIZE = 4096;
static const uint32_t HANDSHAKE_SIZE         = 1536;

RTMPEndpoint::RTMPEndpoint(libvcam::DataLayer *layer)
    : _layer(layer),
      _inChunkSize(DEFAULT_IN_CHUNK_SIZE),
      _outChunkSize(DEFAULT_OUT_CHUNK_SIZE),
      _lastHeaderCsId(-1) {}

RTMPEndpoint::~RTMPEndpoint() {}

// ─── Handshake ────────────────────────────────────────────────────────────────
// Server-side: recv C0+C1, send S0+S1+S2, recv C2
void RTMPEndpoint::doHandshake() {
    // --- C0 ---
    uint8_t c0 = _layer->readU8();
    if (c0 != 0x03)
        throw std::runtime_error("RTMP: unsupported or encrypted handshake version");

    // --- C1 ---
    uint8_t c1[HANDSHAKE_SIZE];
    _layer->readExact(c1, HANDSHAKE_SIZE);

    // --- S0 ---
    _layer->writeU8(0x03);

    // --- S1 --- (timestamp + zeros + random)
    uint8_t s1[HANDSHAKE_SIZE];
    memset(s1, 0, HANDSHAKE_SIZE);
    uint32_t now = (uint32_t)time(NULL);
    s1[0] = (now >> 24) & 0xFF;
    s1[1] = (now >> 16) & 0xFF;
    s1[2] = (now >>  8) & 0xFF;
    s1[3] = now & 0xFF;
    // bytes 4-7 = zeros (server version)
    // bytes 8..HANDSHAKE_SIZE-1 = pseudo-random
    for (int i = 8; i < (int)HANDSHAKE_SIZE; i++)
        s1[i] = (uint8_t)(i & 0xFF);

    _layer->writeExact(s1, HANDSHAKE_SIZE);

    // --- S2 --- (echo of C1: C1's time, our time, C1's random body)
    uint8_t s2[HANDSHAKE_SIZE];
    memcpy(s2, c1, 4);        // client time
    s2[4] = (now >> 24) & 0xFF; // our time
    s2[5] = (now >> 16) & 0xFF;
    s2[6] = (now >>  8) & 0xFF;
    s2[7] = now & 0xFF;
    memcpy(s2 + 8, c1 + 8, HANDSHAKE_SIZE - 8);
    _layer->writeExact(s2, HANDSHAKE_SIZE);

    // --- C2 --- (echo of S1 — we validate loosely: just consume)
    uint8_t c2[HANDSHAKE_SIZE];
    _layer->readExact(c2, HANDSHAKE_SIZE);
    (void)c2;
}

// ─── Chunk reading ────────────────────────────────────────────────────────────

// Read basic header byte(s). Returns chunk stream ID; sets *fmtOut = fmt field.
int RTMPEndpoint::readBasicHeader(uint8_t *fmtOut) {
    uint8_t b = _layer->readU8();
    *fmtOut   = (b >> 6) & 0x03;
    int csId  = b & 0x3F;

    if (csId == 0) {
        // 2-byte basic header
        csId = _layer->readU8() + 64;
    } else if (csId == 1) {
        // 3-byte basic header (big-endian 16-bit)
        uint8_t b1 = _layer->readU8();
        uint8_t b2 = _layer->readU8();
        csId = ((int)b2 << 8 | b1) + 64;
    }
    return csId;
}

uint32_t RTMPEndpoint::read3BytesBE() {
    uint8_t b[3];
    _layer->readExact(b, 3);
    return ((uint32_t)b[0] << 16) | ((uint32_t)b[1] << 8) | b[2];
}

// 4-byte LITTLE-endian (stream ID field in type-0 headers)
uint32_t RTMPEndpoint::read4BytesLE() {
    uint8_t b[4];
    _layer->readExact(b, 4);
    return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

void RTMPEndpoint::readChunkHeader(int csId, uint8_t fmt, ChunkStreamState &cs) {
    (void)csId;
    if (fmt == 0) {
        // Full header: timestamp(3) + length(3) + type(1) + stream_id(4 LE)
        uint32_t ts  = read3BytesBE();
        cs.length    = read3BytesBE();
        if (cs.length > 16 * 1024 * 1024) throw std::runtime_error("RTMP message too large");
        cs.type      = _layer->readU8();
        cs.streamId  = read4BytesLE();
        cs.extendedTimestamp = (ts == 0xFFFFFF);
        if (cs.extendedTimestamp) {
            uint8_t ext[4]; _layer->readExact(ext, 4);
            ts = ((uint32_t)ext[0]<<24)|((uint32_t)ext[1]<<16)|((uint32_t)ext[2]<<8)|ext[3];
            cs.extendedTimestampValue = ts;
        } else {
            cs.extendedTimestampValue = 0;
        }
        cs.timestamp = ts;
        cs.delta = 0;
        cs.hasHeader = true;
        cs.partialPayload.clear();
        cs.bytesReceived = 0;

    } else if (fmt == 1) {
        // delta(3) + length(3) + type(1)  — stream_id same as before
        uint32_t d  = read3BytesBE();
        cs.length   = read3BytesBE();
        if (cs.length > 16 * 1024 * 1024) throw std::runtime_error("RTMP message too large");
        cs.type     = _layer->readU8();
        cs.extendedTimestamp = (d == 0xFFFFFF);
        if (cs.extendedTimestamp) {
            uint8_t ext[4]; _layer->readExact(ext, 4);
            d = ((uint32_t)ext[0]<<24)|((uint32_t)ext[1]<<16)|((uint32_t)ext[2]<<8)|ext[3];
            cs.extendedTimestampValue = d;
        } else {
            cs.extendedTimestampValue = 0;
        }
        cs.delta = d;
        cs.timestamp += d;
        cs.hasHeader = true;
        cs.partialPayload.clear();
        cs.bytesReceived = 0;

    } else if (fmt == 2) {
        // delta(3) only — length, type, stream_id same as before
        uint32_t d  = read3BytesBE();
        cs.extendedTimestamp = (d == 0xFFFFFF);
        if (cs.extendedTimestamp) {
            uint8_t ext[4]; _layer->readExact(ext, 4);
            d = ((uint32_t)ext[0]<<24)|((uint32_t)ext[1]<<16)|((uint32_t)ext[2]<<8)|ext[3];
            cs.extendedTimestampValue = d;
        } else {
            cs.extendedTimestampValue = 0;
        }
        cs.delta = d;
        cs.timestamp += d;
        cs.hasHeader = true;
        cs.partialPayload.clear();
        cs.bytesReceived = 0;

    } else {
        // fmt == 3: continuation chunk or a new message using previous header.
        if (!cs.hasHeader) throw std::runtime_error("RTMP compressed header without prior message");
        // An extended timestamp is repeated on every fmt=3 chunk. Consume it
        // even for continuation chunks so payload remains aligned.
        if (cs.extendedTimestamp) {
            uint8_t ext[4];
            _layer->readExact(ext, 4);
        }
        if (cs.bytesReceived == 0) {
            cs.timestamp += cs.delta;
            cs.partialPayload.clear();
        }
    }
}

RTMPMessage RTMPEndpoint::readMessage() {
    for (;;) {
        uint8_t fmt;
        int csId = readBasicHeader(&fmt);
        if (fmt != 0 && _csState.find(csId) == _csState.end())
            throw std::runtime_error("RTMP compressed header without stream state");

        ChunkStreamState &cs = _csState[csId];
        _lastHeaderCsId = csId;
        readChunkHeader(csId, fmt, cs);

        // How many bytes to read for this chunk?
        uint32_t remaining = cs.length - cs.bytesReceived;
        uint32_t toRead    = (remaining < _inChunkSize) ? remaining : _inChunkSize;

        size_t oldSize = cs.partialPayload.size();
        cs.partialPayload.resize(oldSize + toRead);
        _layer->readExact(&cs.partialPayload[oldSize], toRead);
        cs.bytesReceived += toRead;

        if (cs.bytesReceived >= cs.length) {
            // Message complete — assemble and return
            RTMPMessage msg;
            msg.type      = cs.type;
            msg.streamId  = cs.streamId;
            msg.timestamp = cs.timestamp;
            msg.payload   = cs.partialPayload;

            // Reset accumulator for next message on this CS
            cs.partialPayload.clear();
            cs.bytesReceived = 0;

            // Handle Set Chunk Size inline (control — must update _inChunkSize)
            if (msg.type == RTMP_MSG_SET_CHUNK_SIZE && msg.payload.size() >= 4) {
                uint32_t newChunkSize = ((uint32_t)msg.payload[0] << 24) |
                                        ((uint32_t)msg.payload[1] << 16) |
                                        ((uint32_t)msg.payload[2] <<  8) |
                                         msg.payload[3];
                newChunkSize &= 0x7FFFFFFF; // MSB must be 0
                if (newChunkSize == 0 || newChunkSize > 1024 * 1024)
                    throw std::runtime_error("RTMP invalid chunk size");
                _inChunkSize = newChunkSize;
                continue; // transparent — don't return to caller
            }

            return msg;
        }
        // Message not yet complete — loop and read next chunk
    }
}

// ─── Chunk writing ────────────────────────────────────────────────────────────

void RTMPEndpoint::sendMessage(uint8_t type, uint32_t streamId, uint32_t timestamp,
                                const std::vector<uint8_t> &payload, int csId)
{
    if (payload.size() > 0xFFFFFF)
        throw std::runtime_error("RTMP message too large to encode");
    if (csId < 2 || csId > 63)
        throw std::runtime_error("RTMP unsupported chunk stream id");

    const uint8_t *p = payload.data();
    size_t rem = payload.size();
    bool first = true;
    const bool extended = timestamp >= 0xFFFFFF;

    while (first || rem > 0) {
        size_t toWrite = (rem < _outChunkSize) ? rem : _outChunkSize;

        if (first) {
            // fmt=0 (full header) for the first chunk.
            uint8_t hdr[12];
            hdr[0] = (uint8_t)(csId & 0x3F);
            uint32_t wireTimestamp = extended ? 0xFFFFFF : timestamp;
            hdr[1] = (wireTimestamp >> 16) & 0xFF;
            hdr[2] = (wireTimestamp >> 8) & 0xFF;
            hdr[3] = wireTimestamp & 0xFF;
            uint32_t length = (uint32_t)payload.size();
            hdr[4] = (length >> 16) & 0xFF;
            hdr[5] = (length >> 8) & 0xFF;
            hdr[6] = length & 0xFF;
            hdr[7] = type;
            hdr[8] = (streamId >> 0) & 0xFF;
            hdr[9] = (streamId >> 8) & 0xFF;
            hdr[10] = (streamId >> 16) & 0xFF;
            hdr[11] = (streamId >> 24) & 0xFF;
            _layer->writeExact(hdr, sizeof(hdr));
            if (extended) {
                uint8_t ext[4] = {(uint8_t)(timestamp >> 24), (uint8_t)(timestamp >> 16),
                                  (uint8_t)(timestamp >> 8), (uint8_t)timestamp};
                _layer->writeExact(ext, sizeof(ext));
            }
            first = false;
        } else {
            // fmt=3 (no header) for continuation chunks.
            uint8_t b = (uint8_t)(0xC0 | (csId & 0x3F));
            _layer->writeU8(b);
            if (extended) {
                uint8_t ext[4] = {(uint8_t)(timestamp >> 24), (uint8_t)(timestamp >> 16),
                                  (uint8_t)(timestamp >> 8), (uint8_t)timestamp};
                _layer->writeExact(ext, sizeof(ext));
            }
        }

        if (toWrite > 0) _layer->writeExact(p, toWrite);
        p += toWrite;
        rem -= toWrite;
    }
}

void RTMPEndpoint::sendControl(uint8_t type, const std::vector<uint8_t> &payload) {
    sendMessage(type, 0, 0, payload, 2);
}

} // namespace librtmp
