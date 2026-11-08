#ifndef CODEX_CROSSTERM_WINDOW_SIZE_NATIVE_H
#define CODEX_CROSSTERM_WINDOW_SIZE_NATIVE_H
#include <stdint.h>
#include <errno.h>
#include <string.h>
// STUB: crossterm::terminal::WindowSize's Copy native output.
typedef struct CodexWindowSize { uint16_t rows, columns, width, height; } CodexWindowSize;
#ifdef _WIN32
// STUB: the Windows owner is untranslated; SizeMonitor::start excludes this platform.
static int codex_window_size(CodexWindowSize *out) { (void)out; return ENOSYS; }
#else
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
// STUB: pinned Crossterm Unix window_size. /dev/tty has precedence over stdout;
// an open failure alone selects stdout. A failed tty ioctl is never retried on stdout.
static int codex_window_size(CodexWindowSize *out) {
    struct winsize size = {0, 0, 0, 0};
    int owned = open("/dev/tty", O_RDONLY);
    int fd = owned >= 0 ? owned : STDOUT_FILENO;
    int result = ioctl(fd, TIOCGWINSZ, &size);
    int saved_error = result == -1 ? errno : 0;
    if (owned >= 0) close(owned);
    if (saved_error) return saved_error;
    out->rows = size.ws_row;
    out->columns = size.ws_col;
    out->width = size.ws_xpixel;
    out->height = size.ws_ypixel;
    return 0;
}
#endif
// STUB: io::Error::last_os_error's diagnostic text; V copies it into the error owner.
static const char *codex_window_size_error(int code) { return strerror(code); }
#endif
