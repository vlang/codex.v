// STUB: native std::process::Command::output boundary for keyboard_modes.rs.
#ifndef CODEX_KEYBOARD_MODES_PROCESS_H
#define CODEX_KEYBOARD_MODES_PROCESS_H
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>

// STUB: grows the captured stdout buffer without changing its bytes.
static int codex_keyboard_append(unsigned char **bytes, size_t *length,
                                 const unsigned char *block, size_t count) {
    if (count > SIZE_MAX - *length - 1) return ENOMEM;
    unsigned char *grown = realloc(*bytes, *length + count + 1);
    if (!grown) return ENOMEM;
    memcpy(grown + *length, block, count);
    *length += count;
    grown[*length] = 0;
    *bytes = grown;
    return 0;
}

#ifdef _WIN32
#include <windows.h>

// STUB: converts the V UTF-8 native Windows path adapter to UTF-16 for WinAPI.
static wchar_t *codex_keyboard_wide(const char *text) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (!count) return NULL;
    wchar_t *wide = malloc((size_t)count * sizeof(wchar_t));
    if (!wide) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, count)) {
        free(wide); return NULL;
    }
    return wide;
}

// STUB: CreateProcess command-line quoting matches the Microsoft CRT argv parser.
static char *codex_keyboard_windows_argv(char **argv) {
    size_t capacity = 1;
    for (size_t i = 0; argv[i]; ++i) {
        size_t n = strlen(argv[i]);
        if (n > (SIZE_MAX - capacity - 4) / 2) return NULL;
        capacity += 2 * n + 4;
    }
    char *line = malloc(capacity);
    if (!line) return NULL;
    size_t offset = 0;
    for (size_t i = 0; argv[i]; ++i) {
        if (i) line[offset++] = ' ';
        line[offset++] = '"';
        size_t slashes = 0;
        for (const char *p = argv[i]; ; ++p) {
            if (*p == '\\') { ++slashes; continue; }
            if (!*p || *p == '"') {
                for (size_t j = 0; j < slashes * 2 + (*p == '"'); ++j)
                    line[offset++] = '\\';
                slashes = 0;
                if (!*p) break;
            } else {
                for (size_t j = 0; j < slashes; ++j) line[offset++] = '\\';
                slashes = 0;
            }
            line[offset++] = *p;
        }
        line[offset++] = '"';
    }
    line[offset] = 0;
    return line;
}

// STUB: runs an automatic helper directly with Windows null handles and a stdout pipe.
static int32_t codex_keyboard_process_output(const char *executable, char **argv,
        char **envp, int stdin_null, int stderr_null, unsigned char **bytes,
        size_t *length, int32_t *exit_code) {
    int32_t error = 0;
    char *line = codex_keyboard_windows_argv(argv);
    wchar_t *application = codex_keyboard_wide(executable);
    wchar_t *arguments = line ? codex_keyboard_wide(line) : NULL;
    free(line);
    if (!application || !arguments) {
        error = (int32_t)GetLastError();
        free(application); free(arguments);
        return error ? error : ERROR_NOT_ENOUGH_MEMORY;
    }
    size_t units = 1;
    for (size_t i = 0; envp[i]; ++i) {
        int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, envp[i], -1, NULL, 0);
        if (!count) { error = (int32_t)GetLastError(); goto strings_done; }
        units += (size_t)count;
    }
    wchar_t *environment = calloc(units + 1, sizeof(wchar_t));
    if (!environment) { error = ERROR_NOT_ENOUGH_MEMORY; goto strings_done; }
    size_t offset = 0;
    for (size_t i = 0; envp[i]; ++i) {
        int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, envp[i], -1,
                                      environment + offset, (int)(units - offset));
        offset += (size_t)count;
    }
    SECURITY_ATTRIBUTES security = { sizeof(security), NULL, TRUE };
    HANDLE reader = NULL, writer = NULL, null_handle = INVALID_HANDLE_VALUE;
    if (!CreatePipe(&reader, &writer, &security, 0) ||
        !SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0)) {
        error = (int32_t)GetLastError(); goto handles_done;
    }
    if (stdin_null || stderr_null) {
        null_handle = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
        if (null_handle == INVALID_HANDLE_VALUE) {
            error = (int32_t)GetLastError(); goto handles_done;
        }
    }
    STARTUPINFOW startup = { 0 };
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = stdin_null ? null_handle : GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = writer;
    startup.hStdError = stderr_null ? null_handle : GetStdHandle(STD_ERROR_HANDLE);
    PROCESS_INFORMATION process = { 0 };
    if (!CreateProcessW(application, arguments, NULL, NULL, TRUE,
                        CREATE_UNICODE_ENVIRONMENT, environment, NULL, &startup, &process)) {
        error = (int32_t)GetLastError(); goto handles_done;
    }
    CloseHandle(writer); writer = NULL;
    unsigned char block[4096];
    for (;;) {
        DWORD count = 0;
        if (!ReadFile(reader, block, sizeof(block), &count, NULL)) {
            if (GetLastError() != ERROR_BROKEN_PIPE) error = (int32_t)GetLastError();
            break;
        }
        if (!count) break;
        if (!error) error = codex_keyboard_append(bytes, length, block, count);
    }
    if (WaitForSingleObject(process.hProcess, INFINITE) == WAIT_FAILED && !error)
        error = (int32_t)GetLastError();
    DWORD status = 0;
    if (!GetExitCodeProcess(process.hProcess, &status) && !error)
        error = (int32_t)GetLastError();
    *exit_code = (int32_t)status;
    CloseHandle(process.hThread); CloseHandle(process.hProcess);
handles_done:
    if (reader) CloseHandle(reader);
    if (writer) CloseHandle(writer);
    if (null_handle != INVALID_HANDLE_VALUE) CloseHandle(null_handle);
    free(environment);
strings_done:
    free(application); free(arguments);
    return error;
}
#else
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

// STUB: reports a failed pre-exec syscall without allocation in the forked child.
static void codex_keyboard_spawn_error(int descriptor, int code) {
    const unsigned char *data = (const unsigned char *)&code;
    size_t offset = 0;
    while (offset < sizeof(code)) {
        ssize_t count = write(descriptor, data + offset, sizeof(code) - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    _exit(127);
}

// STUB: runs an automatic helper directly with Unix null fds and a stdout pipe.
static int32_t codex_keyboard_process_output(const char *executable, char **argv,
        char **envp, int stdin_null, int stderr_null, unsigned char **bytes,
        size_t *length, int32_t *exit_code) {
    int output[2], errors[2], null_descriptor = -1;
    if (pipe(output) != 0) return errno;
    if (pipe(errors) != 0) {
        int code = errno; close(output[0]); close(output[1]); return code;
    }
    if (fcntl(errors[1], F_SETFD, FD_CLOEXEC) == -1) {
        int code = errno;
        close(output[0]); close(output[1]); close(errors[0]); close(errors[1]);
        return code;
    }
    if (stdin_null || stderr_null) {
        null_descriptor = open("/dev/null", O_RDWR);
        if (null_descriptor == -1) {
            int code = errno;
            close(output[0]); close(output[1]); close(errors[0]); close(errors[1]);
            return code;
        }
    }
    pid_t child = fork();
    if (child == -1) {
        int code = errno;
        close(output[0]); close(output[1]); close(errors[0]); close(errors[1]);
        if (null_descriptor != -1) close(null_descriptor);
        return code;
    }
    if (!child) {
        close(output[0]); close(errors[0]);
        if (dup2(output[1], STDOUT_FILENO) == -1 ||
            (stdin_null && dup2(null_descriptor, STDIN_FILENO) == -1) ||
            (stderr_null && dup2(null_descriptor, STDERR_FILENO) == -1))
            codex_keyboard_spawn_error(errors[1], errno);
        close(output[1]);
        if (null_descriptor > STDERR_FILENO) close(null_descriptor);
        execve(executable, argv, envp);
        codex_keyboard_spawn_error(errors[1], errno);
    }
    close(output[1]); close(errors[1]);
    if (null_descriptor != -1) close(null_descriptor);
    int spawn_error = 0, error = 0;
    ssize_t count;
    do { count = read(errors[0], &spawn_error, sizeof(spawn_error)); }
    while (count == -1 && errno == EINTR);
    if (count == -1) error = errno;
    close(errors[0]);
    unsigned char block[4096];
    for (;;) {
        count = read(output[0], block, sizeof(block));
        if (count == -1 && errno == EINTR) continue;
        if (count == -1) { if (!error) error = errno; break; }
        if (!count) break;
        if (!error) error = codex_keyboard_append(bytes, length, block, (size_t)count);
    }
    close(output[0]);
    int status = 0;
    pid_t waited;
    do { waited = waitpid(child, &status, 0); } while (waited == -1 && errno == EINTR);
    if (waited == -1 && !error) error = errno;
    *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    return spawn_error ? spawn_error : error;
}
#endif
#endif
