// STUB: Native std::fs::metadata and Path::try_exists boundary used by startup preflight.
#ifndef CODEX_STARTUP_PREFLIGHT_STAT_H
#define CODEX_STARTUP_PREFLIGHT_STAT_H
#include <stdint.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
// STUB: Follow Windows reparse points and preserve native errors, including dangling links.
static int32_t codex_preflight_stat(const char *path, int32_t *directory, int32_t *kind) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) { *kind = 2; return (int32_t)GetLastError(); }
    wchar_t *wide = malloc((size_t)count * sizeof(wchar_t));
    if (!wide) { *kind = 0; return ERROR_NOT_ENOUGH_MEMORY; }
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, count);
    HANDLE file = CreateFileW(wide, FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS, NULL);
    free(wide);
    DWORD error = file == INVALID_HANDLE_VALUE ? GetLastError() : 0;
    if (!error) {
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(file, &info)) error = GetLastError();
        else *directory = (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        CloseHandle(file);
    }
    *kind = error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 1 :
            error == ERROR_ACCESS_DENIED ? 3 : 0;
    return (int32_t)error;
}
#else
#include <sys/stat.h>
// STUB: stat follows symlinks; only ENOENT is NotFound, while ENOTDIR remains ambiguous.
static int32_t codex_preflight_stat(const char *path, int32_t *directory, int32_t *kind) {
    struct stat info;
    if (stat(path, &info) == 0) { *directory = S_ISDIR(info.st_mode); *kind = 0; return 0; }
    int code = errno;
    *kind = code == ENOENT ? 1 : code == EINVAL ? 2 : code == EACCES || code == EPERM ? 3 : 0;
    return (int32_t)code;
}
#endif
#endif
