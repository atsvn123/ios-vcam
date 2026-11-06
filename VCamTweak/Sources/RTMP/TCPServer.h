// TCPServer.h
// POSIX TCP server used by RTMPServer on port 1935.
// Reconstructed from the C++ TCPServer class in vcamera.dylib (called at 0xA2A24).

#pragma once
#include <stdint.h>
#include <stdexcept>
#include <atomic>

namespace libvcam {

class TCPServer {
public:
    explicit TCPServer(uint16_t port);
    ~TCPServer();

    // Blocks until a client connects. Returns connected fd. Throws on error.
    int accept();

    void destroy();
    void forgetClient(int clientFd);

private:
    std::atomic<int> _listenFd;
    std::atomic<bool> _destroyed;
    std::atomic<int> _clientFd;
};

} // namespace libvcam
