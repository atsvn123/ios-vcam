// TCPServer.cpp
// Listens on all interfaces at <port> and accepts one connection at a time.
// The RTMP server (port 1935) processes one client sequentially — a new accept()
// only starts after the previous session's C++ objects are destroyed.

#include "TCPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdexcept>
namespace libvcam {

TCPServer::TCPServer(uint16_t port) : _listenFd(-1), _destroyed(false), _clientFd(-1) {
    _listenFd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (_listenFd < 0) {
        char em[64]; snprintf(em, sizeof(em), "socket() failed errno=%d", errno);
        throw std::runtime_error(em);
    }

    int yes = 1;
    ::setsockopt(_listenFd, SOL_SOCKET, SO_REUSEADDR,  &yes, (socklen_t)sizeof(yes));
    // IDA 0xA6DD8: second setsockopt with option 0x200 = SO_REUSEPORT (macOS/iOS)
    ::setsockopt(_listenFd, SOL_SOCKET, SO_REUSEPORT,  &yes, (socklen_t)sizeof(yes));

    struct sockaddr_in addr;
    ::memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(port);
    // Accept RTMP from LAN clients (OBS can connect to the phone's Wi-Fi address).
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (::bind(_listenFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        int e = errno;
        ::close(_listenFd);
        _listenFd.store(-1);
        _destroyed.store(true);
        char em[64]; snprintf(em, sizeof(em), "bind(%d) failed errno=%d(%s)", (int)port, e, strerror(e));
        throw std::runtime_error(em);
    }

    // IDA 0xA6E10: listen backlog = 128
    if (::listen(_listenFd, 128) < 0) {
        int e = errno;
        ::close(_listenFd);
        _listenFd.store(-1);
        _destroyed.store(true);
        char em[64]; snprintf(em, sizeof(em), "listen(%d) failed errno=%d(%s)", (int)port, e, strerror(e));
        throw std::runtime_error(em);
    }
}

TCPServer::~TCPServer() {
    destroy();
}

int TCPServer::accept() {
    int listenFd = _listenFd.load();
    if (listenFd < 0 || _destroyed.load())
        throw std::runtime_error("TCPServer: listener closed");
    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);
    ::memset(&clientAddr, 0, sizeof(clientAddr));

    int clientFd = ::accept(listenFd, (struct sockaddr *)&clientAddr, &addrLen);
    if (clientFd < 0)
        throw std::runtime_error("TCPServer: accept() failed");
    if (_destroyed.load()) {
        ::close(clientFd);
        throw std::runtime_error("TCPServer: listener closed");
    }
    int noClient = -1;
    if (!_clientFd.compare_exchange_strong(noClient, clientFd)) {
        ::close(clientFd);
        throw std::runtime_error("TCPServer: client already active");
    }
    if (_destroyed.load()) {
        int expected = clientFd;
        if (_clientFd.compare_exchange_strong(expected, -1)) ::close(clientFd);
        throw std::runtime_error("TCPServer: listener closed");
    }
    return clientFd;
}

void TCPServer::destroy() {
    if (_destroyed.exchange(true)) return;
    int fd = _listenFd.exchange(-1);
    if (fd >= 0) {
        ::shutdown(fd, SHUT_RDWR);
        ::close(fd);
    }
    int clientFd = _clientFd.load();
    if (clientFd >= 0) ::shutdown(clientFd, SHUT_RDWR);
}

void TCPServer::forgetClient(int clientFd) {
    if (clientFd < 0) return;
    int expected = clientFd;
    _clientFd.compare_exchange_strong(expected, -1);
}

} // namespace libvcam
