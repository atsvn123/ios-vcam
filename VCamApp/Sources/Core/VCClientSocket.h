#import <Foundation/Foundation.h>

extern NSNotificationName const VCClientSocketDidConnectNotification;
extern NSNotificationName const VCClientSocketCameraResolutionNotification; // userInfo: @{@"width":@(w), @"height":@(h)}

@interface VCClientSocket : NSObject

@property (nonatomic, readonly) BOOL isConnected;

- (void)connectToHost:(NSString *)host port:(uint16_t)port;
- (void)disconnect;
- (void)sendData:(NSData *)data;

- (void)sendInt32:(int32_t)code;
- (void)sendInt32:(int32_t)code value:(int32_t)value;
- (void)sendInt32:(int32_t)code float:(float)value;
- (void)sendInt32:(int32_t)code string:(NSString *)string;

@end
