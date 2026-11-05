// VCRTMPServer.m — Stub implementation
// Full RTMP server (port 1935, H264 decode) will be ported from old project's
// C++ library (AMF.cpp, RTMPEndpoint.cpp, RTMPServerSession.cpp, TCPServer.cpp)

#import "VCRTMPServer.h"

@implementation VCRTMPServer

+ (BOOL)createActiveTCPServer {
    // TODO: bind port 1935, RTMP handshake, publish protocol
    return NO;
}

+ (NSString *)lastBindError {
    return @"RTMP server not yet ported";
}

- (void)startServerLoop {
    // TODO: accept connection, parse RTMP chunks, extract H264 NALUs
}

- (void)stopServer {
    // TODO: close socket, stop decode, release resources
}

- (void)stopDecoding {
    // TODO: flush H264 decoder
}

@end
