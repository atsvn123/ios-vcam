#import <Foundation/Foundation.h>
#import "VCRTMPServer.h"
#import "VCH264Decoder.h"
#import "VCBridge.h"
#include "RTMP/TCPServer.h"
#include "RTMP/DataLayer.h"
#include "RTMP/librtmp/RTMPEndpoint.h"
#include "RTMP/librtmp/RTMPServerSession.h"
#include <memory>
#include <mutex>
#include <atomic>
#include <stdexcept>
#include <unistd.h>

using libvcam::DataLayer;
using libvcam::TCPServer;
using librtmp::H264Frame;
using librtmp::RTMPEndpoint;
using librtmp::RTMPServerSession;

static std::mutex g_rtmpMutex;
static std::shared_ptr<TCPServer> g_tcpServer;
static NSString *g_bindError;
static std::atomic<bool> g_rtmpWantsRunning(false);

@implementation VCRTMPServer (CXXBridge)

+ (BOOL)createActiveTCPServer {
    std::lock_guard<std::mutex> guard(g_rtmpMutex);
    if (g_tcpServer) return YES;
    try {
        g_tcpServer = std::make_shared<TCPServer>(RTMP_PORT);
        g_rtmpWantsRunning.store(true);
        g_bindError = nil;
        return YES;
    } catch (const std::exception &e) {
        g_bindError = [NSString stringWithUTF8String:e.what()];
        return NO;
    }
}

+ (NSString *)lastBindError {
    std::lock_guard<std::mutex> guard(g_rtmpMutex);
    return g_bindError;
}

+ (void)destroyActiveTCPServer {
    std::lock_guard<std::mutex> guard(g_rtmpMutex);
    g_rtmpWantsRunning.store(false);
    if (g_tcpServer) g_tcpServer->destroy();
    g_tcpServer.reset();
}

+ (void)runRTMPAcceptLoop:(VCRTMPServer *)server {
    for (;;) {
        std::shared_ptr<TCPServer> listener;
        {
            std::lock_guard<std::mutex> guard(g_rtmpMutex);
            if (!g_rtmpWantsRunning.load() || !server.userWantsRunning || !g_tcpServer) break;
            listener = g_tcpServer;
        }

        int clientFd = -1;
        bool accepted = false;
        try {
            clientFd = listener->accept();
            accepted = true;
            DataLayer layer(clientFd);
            RTMPEndpoint endpoint(&layer);
            endpoint.doHandshake();
            RTMPServerSession session(&endpoint);
            while (g_rtmpWantsRunning.load() && server.userWantsRunning && VCamIsEnabled()) {
                H264Frame frame = session.GetRTMPMessage();
                if (!server.deliversFrames) continue;
                if (frame.isSequenceHeader) {
                    if (frame.sps.empty() || frame.pps.empty()) continue;
                    server.hasSequenceHeader = [(VCH264Decoder *)server.h264Decoder
                        initDecoder:frame.sps.data() spsSize:frame.sps.size()
                        pps:frame.pps.data() ppsSize:frame.pps.size()];
                } else if (!frame.nalu.empty() && server.hasSequenceHeader) {
                    int64_t presentationTimestamp = (int64_t)frame.timestamp +
                        (int64_t)(int32_t)frame.compositionTime;
                    if (presentationTimestamp < 0) presentationTimestamp = 0;
                    [(VCH264Decoder *)server.h264Decoder decode:frame.nalu.data()
                        size:frame.nalu.size() pts:(int32_t)presentationTimestamp];
                }
            }
            layer.close();
        } catch (const std::exception &e) {
            if (server.userWantsRunning && VCamIsEnabled() && accepted) {
                NSLog(@"[VCam] RTMP client ended: %s", e.what());
            }
        }
        if (accepted) listener->forgetClient(clientFd);
        if (server.userWantsRunning && VCamIsEnabled() && accepted) usleep(100000);
    }
}

@end
