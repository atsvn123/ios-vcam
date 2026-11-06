#import "VCClientSocket.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

NSNotificationName const VCClientSocketDidConnectNotification = @"VCClientSocketDidConnectNotification";
NSNotificationName const VCClientSocketCameraResolutionNotification = @"VCClientSocketCameraResolutionNotification";

@implementation VCClientSocket {
    int _fd;
    dispatch_queue_t _queue;
    NSString *_host;
    uint16_t _port;
    BOOL _wantConnect;
    NSTimeInterval _retryDelay;
    NSMutableData *_incomingBuffer;
}

static const NSTimeInterval kMinRetry = 0.5;
static const NSTimeInterval kMaxRetry = 8.0;

- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _queue = dispatch_queue_create("com.vcam.client", DISPATCH_QUEUE_SERIAL);
        _retryDelay = kMinRetry;
    }
    return self;
}

- (BOOL)isConnected {
    return _fd >= 0;
}

- (void)connectToHost:(NSString *)host port:(uint16_t)port {
    dispatch_async(_queue, ^{
        self->_host = [host copy];
        self->_port = port;
        self->_wantConnect = YES;
        self->_retryDelay = kMinRetry;
        [self _attemptConnect];
    });
}

- (void)_attemptConnect {
    if (_fd >= 0 || !_wantConnect) return;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        [self _scheduleReconnect];
        return;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(_port);
    inet_pton(AF_INET, _host.UTF8String, &addr.sin_addr);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        [self _scheduleReconnect];
        return;
    }

    int flag = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &flag, sizeof(flag));
    _fd = fd;
    _retryDelay = kMinRetry;

    [self _startReadLoop:fd];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:VCClientSocketDidConnectNotification
                          object:self];
    });
}

- (void)_scheduleReconnect {
    if (!_wantConnect) return;
    NSTimeInterval delay = _retryDelay;
    _retryDelay = MIN(_retryDelay * 2, kMaxRetry);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   _queue, ^{
        [self _attemptConnect];
    });
}

- (void)_startReadLoop:(int)fd {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint8_t buf[256];
        while (1) {
            ssize_t n = recv(fd, buf, sizeof(buf), 0);
            if (n <= 0) break;
            NSData *chunk = [[NSData alloc] initWithBytes:buf length:(NSUInteger)n];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _handleIncoming:chunk];
            });
        }
        dispatch_async(self->_queue, ^{
            if (self->_fd == fd) {
                close(self->_fd);
                self->_fd = -1;
                [self _scheduleReconnect];
            }
        });
    });
}

- (void)_handleIncoming:(NSData *)chunk {
    if (!_incomingBuffer) _incomingBuffer = [NSMutableData data];
    [_incomingBuffer appendData:chunk];
    while (_incomingBuffer.length >= 4) {
        const uint8_t *bytes = (const uint8_t *)_incomingBuffer.bytes;
        int32_t code;
        memcpy(&code, bytes, 4);
        if (code == 1007) {
            if (_incomingBuffer.length < 12) break;
            int32_t w, h;
            memcpy(&w, bytes + 4, 4);
            memcpy(&h, bytes + 8, 4);
            [_incomingBuffer replaceBytesInRange:NSMakeRange(0, 12) withBytes:NULL length:0];
            NSDictionary *info = @{ @"width": @(w), @"height": @(h) };
            [[NSNotificationCenter defaultCenter]
                postNotificationName:VCClientSocketCameraResolutionNotification
                              object:self
                            userInfo:info];
        } else {
            [_incomingBuffer setLength:0];
            break;
        }
    }
}

- (void)disconnect {
    dispatch_async(_queue, ^{
        self->_wantConnect = NO;
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
        const uint8_t *bytes = data.bytes;
        size_t remaining = data.length;
        while (remaining > 0) {
            ssize_t sent = send(self->_fd, bytes, remaining, 0);
            if (sent <= 0) {
                close(self->_fd);
                self->_fd = -1;
                [self _scheduleReconnect];
                return;
            }
            bytes += sent;
            remaining -= (size_t)sent;
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
