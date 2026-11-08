#ifndef CODEX_INPUT_BOUNDARY_NATIVE_H
#define CODEX_INPUT_BOUNDARY_NATIVE_H

#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef struct CodexInputBoundaryReading {
    int readable;
    int error_type;
    int error_kind;
    uint32_t error_code;
    uint16_t events;
    char message[1024];
} CodexInputBoundaryReading;

#ifdef _WIN32
#include <windows.h>

// Check the same Windows console input queue consumed by Crossterm.
static CodexInputBoundaryReading codex_input_boundary_terminal_readable(void) {
    CodexInputBoundaryReading result = {0};
    HANDLE handle = GetStdHandle(STD_INPUT_HANDLE);
    if (handle == INVALID_HANDLE_VALUE || handle == NULL) {
        result.error_type = 2;
        return result;
    }
    DWORD pending = 0;
    if (GetNumberOfConsoleInputEvents(handle, &pending) == 0) {
        DWORD error = GetLastError();
        result.error_type = 3;
        result.error_code = error;
        if (error == ERROR_OPERATION_ABORTED) result.error_kind = 1;
        else if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) result.error_kind = 2;
        else if (error == ERROR_ACCESS_DENIED) result.error_kind = 3;
        else if (error == ERROR_INVALID_PARAMETER) result.error_kind = 5;
        else if (error == ERROR_BROKEN_PIPE) result.error_kind = 6;
        WCHAR wide[1024] = {0};
        DWORD length = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                     NULL, error, 0, wide, 1024, NULL);
        while (length > 0 && (wide[length - 1] == L'\r' || wide[length - 1] == L'\n')) length--;
        int converted = WideCharToMultiByte(CP_UTF8, 0, wide, (int)length,
                                           result.message, sizeof(result.message) - 1, NULL, NULL);
        if (converted <= 0) snprintf(result.message, sizeof(result.message), "OS Error %lu", (unsigned long)error);
        return result;
    }
    result.readable = pending != 0;
    return result;
}
#elif defined(__unix__) || defined(__APPLE__)
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

static CodexInputBoundaryReading codex_input_boundary_last_os_error(void) {
    int error = errno;
    CodexInputBoundaryReading result = {0};
    result.error_type = 3;
    result.error_code = (uint32_t)error;
    if (error == EINTR) result.error_kind = 1;
    else if (error == ENOENT) result.error_kind = 2;
    else if (error == EACCES || error == EPERM) result.error_kind = 3;
    else if (error == EAGAIN) result.error_kind = 4;
    else if (error == EINVAL) result.error_kind = 5;
    else if (error == EPIPE) result.error_kind = 6;
    // strerror_r writes into storage owned by this result instead of shared libc storage.
#if defined(__GLIBC__) && defined(_GNU_SOURCE)
    char *message = strerror_r(error, result.message, sizeof(result.message));
    if (message != result.message) snprintf(result.message, sizeof(result.message), "%s", message);
#else
    if (strerror_r(error, result.message, sizeof(result.message)) != 0) {
        snprintf(result.message, sizeof(result.message), "Unknown error %d", error);
    }
#endif
    return result;
}

static CodexInputBoundaryReading codex_input_boundary_read_poll_events(int polled, uint16_t events) {
    if (polled < 0) return codex_input_boundary_last_os_error();
    CodexInputBoundaryReading result = {0};
    result.events = events;
    if (events & (POLLERR | POLLHUP | POLLNVAL)) {
        result.error_type = 1;
        return result;
    }
    result.readable = polled > 0 && (events & POLLIN) != 0;
    return result;
}

static CodexInputBoundaryReading codex_input_boundary_poll_descriptor(int descriptor) {
    struct pollfd fd = { descriptor, POLLIN, 0 };
    // Safety: `fd` is valid for the duration of this zero-timeout poll.
    int polled = poll(&fd, /*nfds*/ 1, /*timeout*/ 0);
    return codex_input_boundary_read_poll_events(polled, (uint16_t)fd.revents);
}

// std::fs::File::open creates a read-only, close-on-exec descriptor. Existing stdin flags
// are untouched; the fallback only changes the newly created, locally owned descriptor.
static int codex_input_boundary_open_readonly(const char *path) {
    int flags = O_RDONLY;
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    int descriptor = open(path, flags);
#ifndef O_CLOEXEC
    if (descriptor >= 0) {
        int descriptor_flags = fcntl(descriptor, F_GETFD);
        if (descriptor_flags < 0 || fcntl(descriptor, F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) {
            int error = errno;
            close(descriptor);
            errno = error;
            return -1;
        }
    }
#endif
    return descriptor;
}

// Check Crossterm's terminal input source without consuming input or changing descriptor flags.
static CodexInputBoundaryReading codex_input_boundary_terminal_readable(void) {
    int owned_descriptor = -1;
    int descriptor = STDIN_FILENO;
    if (!isatty(STDIN_FILENO)) {
        owned_descriptor = codex_input_boundary_open_readonly("/dev/tty");
        if (owned_descriptor < 0) return codex_input_boundary_last_os_error();
        descriptor = owned_descriptor;
    }
    CodexInputBoundaryReading result = codex_input_boundary_poll_descriptor(descriptor);
    if (owned_descriptor >= 0) close(owned_descriptor);
    return result;
}
#else
// Rust does not query native input on other platforms. Keep this uncalled ABI available
// so the private V adapter can compile there without assuming POSIX headers exist.
static CodexInputBoundaryReading codex_input_boundary_terminal_readable(void) {
    CodexInputBoundaryReading result = {0};
    return result;
}
#endif
#endif
