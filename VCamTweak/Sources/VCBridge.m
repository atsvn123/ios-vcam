#import "VCBridge.h"
#import "VCServerSocket.h"
#import "VCLiveEngine.h"
#import "VCRTMPServer.h"
#include <string.h>

static VCBridge *s_sharedBridge = nil;
static volatile int s_vcamEnabled = 1;
volatile uint8_t g_done = 0;
double g_lastResolutionUpdate = 0.0;

BOOL VCamIsEnabled(void) {
    return __atomic_load_n(&s_vcamEnabled, __ATOMIC_ACQUIRE) != 0;
}

@implementation VCBridge {
    VCServerSocket *_serverSocket;
    NSMutableDictionary *_mapTable;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_sharedBridge = [[VCBridge alloc] init];
    });
    return s_sharedBridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverSocket = [VCServerSocket new];
        _mapTable = [[NSMutableDictionary alloc] initWithCapacity:4];
    }
    return self;
}

- (void)listen {
    BOOL success = NO;
    do {
        __weak VCBridge *weakSelf = self;
        success = [_serverSocket create:22222 callback:^(int fd, NSData *data) {
            VCBridge *strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized(strongSelf) {
                if (!data) {
                    [strongSelf remove:fd];
                    return;
                }
                NSNumber *key = @(fd);
                NSMutableData *buf = strongSelf->_mapTable[key];
                if (!buf) {
                    buf = [NSMutableData dataWithCapacity:256];
                    strongSelf->_mapTable[key] = buf;
                }
                [buf appendData:data];
                [strongSelf parse:buf socketHandle:fd];
            }
        }];
        usleep(10000);
    } while (!success);
}

- (void)remove:(int)socketHandle {
    [_mapTable removeObjectForKey:@(socketHandle)];
    [_serverSocket close:socketHandle];
}

- (void)setResolution:(unsigned int)width height:(unsigned int)height {
    if (_cameraWidth == width && _cameraHeight == height) return;
    _cameraWidth = width;
    _cameraHeight = height;
    int32_t code = 1007, w = (int32_t)width, h = (int32_t)height;
    NSMutableData *d = [NSMutableData dataWithCapacity:12];
    [d appendBytes:&code length:4];
    [d appendBytes:&w    length:4];
    [d appendBytes:&h    length:4];
    [_serverSocket sendAll:d];
}

- (void)parse:(NSMutableData *)buffer socketHandle:(int)socketHandle {
    if (!VCamIsEnabled()) {
        [buffer setLength:0];
        [[VCRTMPServer sharedInstance] stopServer];
        return;
    }
    while (buffer.length >= 4) {
        const uint8_t *bytes = (const uint8_t *)buffer.bytes;
        int32_t code;
        memcpy(&code, bytes, 4);

        if (code == 1000) {
            // LIVE ON (RTMP): set live state, start RTMP server
            [buffer replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
            [[VCLiveEngine sharedInstance] setMediaType:0];
            [[VCLiveEngine sharedInstance] setLiveUserIntent:YES];
            [[VCLiveEngine sharedInstance] setLive:YES];
            [[VCRTMPServer sharedInstance] startServerLoop];
        }
        else if (code == 1001) {
            // LIVE OFF
            [buffer replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
            [[VCLiveEngine sharedInstance] setLiveUserIntent:NO];
            [[VCLiveEngine sharedInstance] setLive:NO];
            [[VCRTMPServer sharedInstance] pauseServerLoop];
        }
        else if (code == 1020) {
            // Media source type: 0=RTMP, 1=Image, 2=Video
            if (buffer.length < 8) break;
            int32_t type;
            memcpy(&type, bytes + 4, 4);
            [buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            NSLog(@"[VCam] IPC source type=%d", (int)type);
            [[VCLiveEngine sharedInstance] setMediaType:(int)type];
            if (type != 0) [[VCRTMPServer sharedInstance] stopServer];
        }
        else if (code == 1022) {
            // Media file path: code(4) + pathLen(4) + path(UTF-8)
            if (buffer.length < 8) break;
            int32_t pathLen;
            memcpy(&pathLen, bytes + 4, 4);
            if (pathLen < 0 || pathLen > 4096) {
                [self remove:socketHandle]; return;
            }
            NSUInteger totalLen = (NSUInteger)(8 + pathLen);
            if (buffer.length < totalLen) break;
            NSString *path = [[NSString alloc] initWithBytes:(bytes + 8)
                                                      length:(NSUInteger)pathLen
                                                    encoding:NSUTF8StringEncoding];
            [buffer replaceBytesInRange:NSMakeRange(0, totalLen) withBytes:NULL length:0];
            if (path) {
                NSLog(@"[VCam] IPC media path=%@", path);
                [[VCLiveEngine sharedInstance] setMediaPath:path];
            }
        }
        else if (code == 1023) {
            // Media live state: 0=off, 1=on (Image/Video without RTMP)
            if (buffer.length < 8) break;
            int32_t live;
            memcpy(&live, bytes + 4, 4);
            [buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            BOOL on = (live == 1);
            NSLog(@"[VCam] IPC media live=%d", on);
            [[VCLiveEngine sharedInstance] setLiveUserIntent:on];
            [[VCLiveEngine sharedInstance] setLive:on];
            if (!on) [[VCRTMPServer sharedInstance] pauseServerLoop];
        }
        else if (code == 1025) {
            // Media fit: 0=Letterbox, 1=Trim
            if (buffer.length < 8) break;
            int32_t mode;
            memcpy(&mode, bytes + 4, 4);
            [buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            [[VCLiveEngine sharedInstance] setMediaFitMode:(int)mode];
        }
        else if (code == 1027) {
            // Performance FPS cap
            if (buffer.length < 8) break;
            int32_t fps;
            memcpy(&fps, bytes + 4, 4);
            [buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            [[VCLiveEngine sharedInstance] setPerformanceFPS:(int)fps];
        }
        else if (code == 1029) {
            // Camera target: 0=both, 1=rear, 2=front
            if (buffer.length < 8) break;
            int32_t target;
            memcpy(&target, bytes + 4, 4);
            [buffer replaceBytesInRange:NSMakeRange(0, 8) withBytes:NULL length:0];
            if (target < 0 || target > 2) target = 0;
            [[VCLiveEngine sharedInstance] setCameraTarget:(int)target];
        }
        else {
            [self remove:socketHandle];
            return;
        }
    }
}

@end
