#import "VCServerSocket.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

@implementation VCServerSocket {
    CFSocketRef _listenSocket;
    NSMutableSet *_clients;
    NSThread *_thread;
    CFRunLoopRef _runLoop;
    VCServerSocketDataBlock _callback;
    uint16_t _port;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _clients = [NSMutableSet new];
    }
    return self;
}

- (CFRunLoopRef)cfRunLoop {
    return _runLoop;
}

static void socketAcceptCallback(CFSocketRef s, CFSocketCallBackType type,
                                  CFDataRef address, const void *data, void *info) {
    if (type != kCFSocketAcceptCallBack) return;
    VCServerSocket *self = (__bridge VCServerSocket *)info;
    int fd = *(const int *)data;

    int flag = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &flag, sizeof(flag));

    @synchronized(self->_clients) {
        [self->_clients addObject:@(fd)];
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint8_t buf[4096];
        while (1) {
            ssize_t n = recv(fd, buf, sizeof(buf), 0);
            if (n <= 0) {
                if (self->_callback) self->_callback(fd, nil);
                @synchronized(self->_clients) {
                    [self->_clients removeObject:@(fd)];
                }
                close(fd);
                return;
            }
            NSData *chunk = [NSData dataWithBytes:buf length:(NSUInteger)n];
            if (self->_callback) self->_callback(fd, chunk);
        }
    });
}

- (BOOL)create:(uint16_t)port callback:(VCServerSocketDataBlock)callback {
    _port = port;
    _callback = [callback copy];

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) return NO;

    int reuse = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sockfd);
        return NO;
    }
    if (listen(sockfd, 5) < 0) {
        close(sockfd);
        return NO;
    }

    CFSocketContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
    _listenSocket = CFSocketCreateWithNative(kCFAllocatorDefault, sockfd,
                                              kCFSocketAcceptCallBack,
                                              socketAcceptCallback, &ctx);
    if (!_listenSocket) {
        close(sockfd);
        return NO;
    }

    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
    _thread.name = @"VCServerSocket";
    _thread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_thread start];
    return YES;
}

- (void)run {
    @autoreleasepool {
        _runLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _listenSocket, 0);
        CFRunLoopAddSource(_runLoop, source, kCFRunLoopCommonModes);
        CFRelease(source);
        CFRunLoopRun();
    }
}

- (void)sendAll:(NSData *)data {
    if (!data.length) return;
    NSSet *snapshot;
    @synchronized(_clients) {
        snapshot = [_clients copy];
    }
    const uint8_t *bytes = data.bytes;
    size_t len = data.length;
    for (NSNumber *fdNum in snapshot) {
        int fd = fdNum.intValue;
        size_t sentTotal = 0;
        while (sentTotal < len) {
            ssize_t sent = send(fd, bytes + sentTotal, len - sentTotal, 0);
            if (sent <= 0) break;
            sentTotal += (size_t)sent;
        }
    }
}

- (void)close:(int)socketHandle {
    @synchronized(_clients) {
        [_clients removeObject:@(socketHandle)];
    }
    close(socketHandle);
}

@end
