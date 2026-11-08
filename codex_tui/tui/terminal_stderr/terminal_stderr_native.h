#ifndef CODEX_TERMINAL_STDERR_NATIVE_H
#define CODEX_TERMINAL_STDERR_NATIVE_H

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int codex_terminal_stderr_same_terminal(void) {
    if (!isatty(STDOUT_FILENO) || !isatty(STDERR_FILENO)) {
        return 0;
    }
    struct stat stdout_stat;
    struct stat stderr_stat;
    // SAFETY: both output pointers reference valid storage for libc to initialize.
    if (fstat(STDOUT_FILENO, &stdout_stat) != 0 ||
        fstat(STDERR_FILENO, &stderr_stat) != 0) {
        return 0;
    }
    // SAFETY: both fstat calls above returned successfully.
    return stdout_stat.st_dev == stderr_stat.st_dev &&
           stdout_stat.st_ino == stderr_stat.st_ino;
}

static int codex_terminal_stderr_open_devnull(void) {
    return open("/dev/null", O_WRONLY | O_CLOEXEC);
}

static int codex_terminal_stderr_errno(void) {
    return errno;
}

#endif
