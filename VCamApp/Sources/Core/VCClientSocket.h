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

// Streams a file to the tweak in chunks. The tweak runs in mediaserverd and
// cannot read this app's sandbox, so the bytes must travel over the socket.
- (void)sendFileAtPath:(NSString *)path type:(int32_t)type;

// Per-camera orientation tuning.
- (void)sendCameraRotationOffset:(int32_t)degrees position:(int32_t)position;
- (void)sendCameraMirror:(BOOL)mirror hasOverride:(BOOL)hasOverride position:(int32_t)position;

@end
