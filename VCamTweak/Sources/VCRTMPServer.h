#import <Foundation/Foundation.h>

@protocol VCRTMPServerDelegate <NSObject>
@optional
- (void)rtmpServerDidConnect;
- (void)rtmpServerDidDisconnect;
- (void)rtmpServerReceivedVideoData:(const uint8_t *)data length:(size_t)length pts:(int32_t)pts;
@end

@interface VCRTMPServer : NSObject

@property (nonatomic, weak) id<VCRTMPServerDelegate> delegate;

+ (BOOL)createActiveTCPServer;
+ (NSString *)lastBindError;
- (void)startServerLoop;
- (void)stopServer;
- (void)stopDecoding;

@end
