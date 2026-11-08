#ifndef CODEX_TERMINAL_STDERR_TEST_NATIVE_H
#define CODEX_TERMINAL_STDERR_TEST_NATIVE_H

#include <poll.h>
#include <util.h>
#include <unistd.h>

typedef struct CodexStderrTestPty {
    int master;
    int slave;
} CodexStderrTestPty;

static CodexStderrTestPty codex_stderr_test_open_pty(void) {
    CodexStderrTestPty pair = {-1, -1};
    if (openpty(&pair.master, &pair.slave, NULL, NULL, NULL) != 0) {
        pair.master = -1;
        pair.slave = -1;
    }
    return pair;
}

static ssize_t codex_stderr_test_pty_read(int master, unsigned char *bytes,
                                         size_t length, int timeout_ms) {
    struct pollfd descriptor = {master, POLLIN, 0};
    int ready = poll(&descriptor, 1, timeout_ms);
    if (ready <= 0) {
        return ready;
    }
    return read(master, bytes, length);
}

#endif
