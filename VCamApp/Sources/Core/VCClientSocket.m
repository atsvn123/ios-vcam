#import "VCClientSocket.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

@implementation VCClientSocket {
    int _fd;
    dispatch_queue_t _queue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _queue = dispatch_queue_create("com.vcam.client", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isConnected {
    return _fd >= 0;
}

- (void)connectToHost:(NSString *)host port:(uint16_t)port {
    dispatch_async(_queue, ^{
        if (self->_fd >= 0) return;

        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return;

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);
        inet_pton(AF_INET, host.UTF8String, &addr.sin_addr);

        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            close(fd);
            // Retry after 1 second
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                           self->_queue, ^{
                [self connectToHost:host port:port];
            });
            return;
        }

        int flag = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &flag, sizeof(flag));
        self->_fd = fd;
    });
}

- (void)disconnect {
    dispatch_async(_queue, ^{
        if (self->_fd >= 0) {
            close(self->_fd);
            self->_fd = -1;
        }
    });
}

- (void)sendData:(NSData *)data {
    if (!data.length) return;
    dispatch_async(_queue, ^{
        if (self->_fd < 0) return;
        ssize_t sent = send(self->_fd, data.bytes, data.length, 0);
        if (sent < 0) {
            close(self->_fd);
            self->_fd = -1;
        }
    });
}

- (void)sendInt32:(int32_t)code {
    NSMutableData *d = [NSMutableData dataWithCapacity:4];
    [d appendBytes:&code length:4];
    [self sendData:d];
}

- (void)sendInt32:(int32_t)code value:(int32_t)value {
    NSMutableData *d = [NSMutableData dataWithCapacity:8];
    [d appendBytes:&code length:4];
    [d appendBytes:&value length:4];
    [self sendData:d];
}

- (void)sendInt32:(int32_t)code float:(float)value {
    NSMutableData *d = [NSMutableData dataWithCapacity:8];
    [d appendBytes:&code length:4];
    [d appendBytes:&value length:4];
    [self sendData:d];
}

- (void)sendInt32:(int32_t)code string:(NSString *)string {
    const char *utf8 = string.UTF8String ?: "";
    int32_t len = (int32_t)strlen(utf8);
    NSMutableData *d = [NSMutableData dataWithCapacity:(NSUInteger)(8 + len)];
    [d appendBytes:&code length:4];
    [d appendBytes:&len length:4];
    if (len > 0) [d appendBytes:utf8 length:(NSUInteger)len];
    [self sendData:d];
}

@end
