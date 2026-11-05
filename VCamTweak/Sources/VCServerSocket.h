#import <Foundation/Foundation.h>

typedef void (^VCServerSocketDataBlock)(int socketHandle, NSData *data);

@interface VCServerSocket : NSObject

- (CFRunLoopRef)cfRunLoop;
- (BOOL)create:(uint16_t)port callback:(VCServerSocketDataBlock)callback;
- (void)sendAll:(NSData *)data;
- (void)close:(int)socketHandle;

@end
