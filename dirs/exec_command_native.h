// Copyright (c) 2018-2019 dirs-rs contributors.
// Licensed under Apache-2.0 or MIT; see LICENSE-APACHE and LICENSE-MIT.
#ifndef CODEX_EXEC_COMMAND_NATIVE_HOME_H
#define CODEX_EXEC_COMMAND_NATIVE_HOME_H
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#include <shlobj.h>
#else
#include <unistd.h>
#include <pwd.h>
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#endif

// STUB: dirs-sys 0.5.0's native home-directory lookup boundary. The V wrapper
// handles HOME first on Unix; the rest of dirs-sys is untranslated.
static char *codex_exec_command_native_home(void) {
#if defined(_WIN32)
    const GUID profile = {0x5e6c858f, 0x0e22, 0x4760,
                          {0x9a, 0xfe, 0xea, 0x33, 0x17, 0xb6, 0x71, 0x73}};
    PWSTR native = NULL;
    if (SHGetKnownFolderPath(&profile, 0, NULL, &native) != S_OK || native == NULL)
        return NULL;
    int size = WideCharToMultiByte(CP_UTF8, 0, native, -1, NULL, 0, NULL, NULL);
    char *result = size > 1 ? (char *)malloc((size_t)size) : NULL;
    if (result != NULL && !WideCharToMultiByte(CP_UTF8, 0, native, -1,
                                             result, size, NULL, NULL)) {
        free(result);
        result = NULL;
    }
    CoTaskMemFree(native);
    return result;
#elif defined(__ANDROID__) || defined(__EMSCRIPTEN__) || \
      (defined(__APPLE__) && TARGET_OS_IPHONE)
    return NULL;
#else
    long suggested = sysconf(_SC_GETPW_R_SIZE_MAX);
    size_t length = suggested < 0 ? 512 : (size_t)suggested;
    char *buffer = (char *)malloc(length);
    if (buffer == NULL)
        return NULL;
    struct passwd entry;
    memset(&entry, 0, sizeof(entry));
    struct passwd *found = NULL;
    char *result = NULL;
    if (getpwuid_r(getuid(), &entry, buffer, length, &found) == 0 &&
        found != NULL && entry.pw_dir != NULL && entry.pw_dir[0] != '\0') {
        size_t size = strlen(entry.pw_dir) + 1;
        result = (char *)malloc(size);
        if (result != NULL)
            memcpy(result, entry.pw_dir, size);
    }
    free(buffer);
    return result;
#endif
}

// STUB: Release the temporary malloc allocation after copying into an owned V path.
static void codex_exec_command_free_native_home(char *home) { free(home); }
#endif
