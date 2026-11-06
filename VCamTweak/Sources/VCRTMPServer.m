#import "VCRTMPServer.h"
#import "VCH264Decoder.h"
#import "VCLiveEngine.h"
#import "VCBridge.h"

@interface VCRTMPServer ()
@property (nonatomic, strong, readwrite) VCH264Decoder *h264Decoder;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, strong) NSThread *rtmpThread;
@end

@implementation VCRTMPServer

+ (instancetype)sharedInstance {
    static VCRTMPServer *server;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ server = [[VCRTMPServer alloc] init]; });
    return server;
}

- (void)startServerLoop {
    @synchronized (self) {
        if (!VCamIsEnabled()) {
            self.deliversFrames = NO;
            return;
        }
        if (!self.h264Decoder) {
            self.h264Decoder = [VCH264Decoder new];
            self.h264Decoder.delegate = (id<VCH264DecoderDelegate>)self;
            self.hasSequenceHeader = NO;
        }
        self.deliversFrames = YES;
        self.userWantsRunning = YES;

        if (![VCRTMPServer createActiveTCPServer]) {
            self.isRunning = NO;
            NSLog(@"[VCam] RTMP bind failed: %@", [VCRTMPServer lastBindError]);
            return;
        }
        NSThread *thread = self.rtmpThread;
        if (thread && !thread.finished && !thread.cancelled) {
            self.isRunning = YES;
            return;
        }
        self.isRunning = YES;
        self.rtmpThread = [[NSThread alloc] initWithTarget:self
                                                  selector:@selector(handleRTMP)
                                                    object:nil];
        [self.rtmpThread start];
    }
}

- (void)stopDecoding {
    @synchronized (self) {
        self.deliversFrames = NO;
    }
}

- (void)pauseServerLoop {
    [self stopDecoding];
}

- (void)stopServer {
    NSThread *thread;
    VCH264Decoder *decoder;
    BOOL calledFromRTMPThread;
    @synchronized (self) {
        self.userWantsRunning = NO;
        self.isRunning = NO;
        self.deliversFrames = NO;
        thread = self.rtmpThread;
        decoder = self.h264Decoder;
        calledFromRTMPThread = thread && thread == [NSThread currentThread];
    }
    [VCRTMPServer destroyActiveTCPServer];
    if (thread && !calledFromRTMPThread) {
        for (NSUInteger i = 0; i < 100 && !thread.finished; i++) usleep(50000);
    }
    @synchronized (self) {
        // Keep decoder and thread retained if socket shutdown did not finish
        // worker yet. This prevents teardown racing decode/init on old worker.
        if (thread && !calledFromRTMPThread && !thread.finished) return;
        self.rtmpThread = nil;
        self.h264Decoder = nil;
    }
    // WaitForAsynchronousFrames may invoke outputFrame:, which takes the same
    // lock. Teardown must happen after releasing it to avoid deadlock.
    if (!calledFromRTMPThread) [decoder endDecode];
}

- (void)handleRTMP {
    @autoreleasepool {
        [VCRTMPServer runRTMPAcceptLoop:self];
        @synchronized (self) {
            self.isRunning = NO;
        }
    }
}

- (void)outputFrame:(void *)frameData
presentationTimeStamp:(int64_t)pts
presentationDuration:(int64_t)duration {
    if (!frameData || !VCamIsEnabled()) return;
    @synchronized (self) {
        if (!self.deliversFrames) return;
        [[VCLiveEngine sharedInstance] setYUVSampleBuffer:(CMSampleBufferRef)frameData];
        id<VCRTMPServerDelegate> delegate = self.delegate;
        if (delegate && [delegate respondsToSelector:@selector(rtmpServerDidConnect)]) {
            /* Delegate is notified by session lifecycle, not per frame. */
        }
    }
}

- (void)dealloc {
    [self stopServer];
}

@end
