// STUB: source-shaped trusted Windows installation root discovery for path-utils.
#ifndef CODEX_KEYBOARD_MODES_PATH_H
#define CODEX_KEYBOARD_MODES_PATH_H
#include <stdlib.h>
#include <stdint.h>
// STUB: retrieve one of the Rust owner's three trusted KnownFolder identifiers.
static HRESULT codex_keyboard_known_folder(int32_t index, wchar_t **path) {
    const KNOWNFOLDERID *ids[] = { &FOLDERID_ProgramFiles, &FOLDERID_ProgramFilesX86,
                                  &FOLDERID_System };
    return SHGetKnownFolderPath(ids[index], KF_FLAG_DEFAULT_PATH, NULL, path);
}

// STUB: fallible Windows canonicalization follows symlinks before trust checking.
static wchar_t *codex_keyboard_canonical_windows(const wchar_t *path) {
    HANDLE file = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                             NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (file == INVALID_HANDLE_VALUE) return NULL;
    DWORD count = GetFinalPathNameByHandleW(file, NULL, 0, FILE_NAME_NORMALIZED);
    wchar_t *canonical = count ? calloc((size_t)count + 1, sizeof(wchar_t)) : NULL;
    DWORD written = canonical ? GetFinalPathNameByHandleW(file, canonical, count + 1,
                                                         FILE_NAME_NORMALIZED) : 0;
    CloseHandle(file);
    if (!written || written > count) { free(canonical); return NULL; }
    return canonical;
}
#endif
