#ifndef CODEX_WINDOW_SIZE_TEST_NATIVE_H
#define CODEX_WINDOW_SIZE_TEST_NATIVE_H
#include "size_monitor_native.h"
#ifndef _WIN32
#include <sys/wait.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
// STUB: fixture process isolates controlling-terminal/stdout changes from the test runner.
// It invokes the same native adapter called by window_size(), with real PTY ioctls.
static int codex_test_window_size(int mode, CodexWindowSize *sampled, int *error_code) {
    int channel[2];
    if (pipe(channel)) return errno;
    pid_t child = fork();
    if (child < 0) { int error = errno; close(channel[0]); close(channel[1]); return error; }
    if (child == 0) {
        close(channel[0]);
        if (setsid() < 0) _exit(10);
        int master, slave;
        struct winsize size = {37, 91, 640, 480};
        if (openpty(&master, &slave, NULL, NULL, &size)) _exit(11);
        if (mode == 1) {
            if (ioctl(slave, TIOCSCTTY, 0)) _exit(12);
            int second_master, second_slave;
            struct winsize other = {9, 19, 200, 100};
            if (openpty(&second_master, &second_slave, NULL, NULL, &other)) _exit(13);
            if (dup2(second_slave, STDOUT_FILENO) < 0) _exit(14);
        } else if (mode == 2) {
            close(STDOUT_FILENO);
        } else if (dup2(slave, STDOUT_FILENO) < 0) _exit(15);
        struct { int error; CodexWindowSize geometry; } result;
        memset(&result, 0, sizeof(result));
        result.error = codex_window_size(&result.geometry);
        if (write(channel[1], &result, sizeof(result)) != sizeof(result)) _exit(16);
        _exit(0);
    }
    close(channel[1]);
    struct { int error; CodexWindowSize geometry; } result;
    size_t received = 0;
    while (received < sizeof(result)) {
        ssize_t count = read(channel[0], ((char *)&result) + received, sizeof(result) - received);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        received += (size_t)count;
    }
    close(channel[0]);
    int status;
    while (waitpid(child, &status, 0) < 0) { if (errno != EINTR) return errno; }
    if (!WIFEXITED(status) || WEXITSTATUS(status) || received != sizeof(result)) return EIO;
    *sampled = result.geometry;
    *error_code = result.error;
    return 0;
}
#endif
#endif
