#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@protocol VCRTMPServerDelegate <NSObject>
@optional
- (void)rtmpServerDidConnect;
- (void)rtmpServerDidDisconnect;
@end

@interface VCRTMPServer : NSObject

+ (instancetype)sharedInstance;
@property (nonatomic, weak) id<VCRTMPServerDelegate> delegate;
@property (nonatomic, strong, readonly) id h264Decoder;
@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign) BOOL userWantsRunning;
@property (nonatomic, assign) BOOL deliversFrames;
@property (nonatomic, assign) BOOL hasSequenceHeader;

+ (BOOL)createActiveTCPServer;
+ (NSString *)lastBindError;
+ (void)destroyActiveTCPServer;
+ (void)runRTMPAcceptLoop:(VCRTMPServer *)server;
- (void)startServerLoop;
- (void)stopServer;
- (void)stopDecoding;
- (void)pauseServerLoop;
- (void)outputFrame:(void *)frameData
presentationTimeStamp:(int64_t)pts
presentationDuration:(int64_t)duration;

@end

#define RTMP_PORT 1935
