#ifndef CODEX_SIZE_MONITOR_NATIVE_H
#define CODEX_SIZE_MONITOR_NATIVE_H
#include <stdint.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
typedef struct CodexSizeMonitorWorker {
    CRITICAL_SECTION mutex;
    CONDITION_VARIABLE condition;
    int permit;
    void *context;
    void *(*run)(void *);
} CodexSizeMonitorWorker;
static int codex_size_monitor_init(CodexSizeMonitorWorker *worker) {
    InitializeCriticalSection(&worker->mutex);
    InitializeConditionVariable(&worker->condition);
    worker->permit = 0;
    return 0;
}
static DWORD WINAPI codex_size_monitor_windows_thread(void *context) {
    CodexSizeMonitorWorker *worker = context;
    worker->run(worker->context);
    return 0;
}
static int codex_size_monitor_start(CodexSizeMonitorWorker *worker, void *(*run)(void *), void *context) {
    worker->run = run;
    worker->context = context;
    HANDLE thread = CreateThread(NULL, 0, codex_size_monitor_windows_thread, worker, 0, NULL);
    if (!thread) return (int)GetLastError();
    CloseHandle(thread);
    return 0;
}
static void codex_size_monitor_unpark(CodexSizeMonitorWorker *worker) {
    EnterCriticalSection(&worker->mutex);
    worker->permit = 1;
    WakeConditionVariable(&worker->condition);
    LeaveCriticalSection(&worker->mutex);
}
static void codex_size_monitor_park(CodexSizeMonitorWorker *worker, int64_t nanos) {
    EnterCriticalSection(&worker->mutex);
    if (!worker->permit) SleepConditionVariableCS(&worker->condition, &worker->mutex, (DWORD)((nanos + 999999) / 1000000));
    worker->permit = 0;
    LeaveCriticalSection(&worker->mutex);
}
static void codex_size_monitor_destroy(CodexSizeMonitorWorker *worker) { DeleteCriticalSection(&worker->mutex); }
#else
#include <pthread.h>
#include <time.h>
#include <stdlib.h>
// V's Boehm build redirects pthread_create through its registered thread entry.
typedef struct CodexSizeMonitorWorker {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    int permit;
    void *context;
    void *(*run)(void *);
} CodexSizeMonitorWorker;
static int codex_size_monitor_init(CodexSizeMonitorWorker *worker) {
    int result = pthread_mutex_init(&worker->mutex, NULL);
    if (result) return result;
#ifdef __APPLE__
    result = pthread_cond_init(&worker->condition, NULL);
#else
    pthread_condattr_t attributes;
    result = pthread_condattr_init(&attributes);
    if (!result) {
        result = pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
        if (!result) result = pthread_cond_init(&worker->condition, &attributes);
        pthread_condattr_destroy(&attributes);
    }
#endif
    if (result) { pthread_mutex_destroy(&worker->mutex); return result; }
    worker->permit = 0;
    return 0;
}
static void *codex_size_monitor_thread(void *context) {
    CodexSizeMonitorWorker *worker = context;
#ifdef __APPLE__
    pthread_setname_np("codex-terminal-size");
#elif defined(__linux__)
    // Linux truncates thread names to 15 bytes, as std::thread::Builder does.
    pthread_setname_np(pthread_self(), "codex-terminal-");
#endif
    return worker->run(worker->context);
}
static int codex_size_monitor_start(CodexSizeMonitorWorker *worker, void *(*run)(void *), void *context) {
    worker->run = run;
    worker->context = context;
    pthread_attr_t attributes;
    int result = pthread_attr_init(&attributes);
    if (result) return result;
    result = pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    if (!result) result = pthread_create(&thread, &attributes, codex_size_monitor_thread, worker);
    pthread_attr_destroy(&attributes);
    return result;
}
static void codex_size_monitor_unpark(CodexSizeMonitorWorker *worker) {
    if (pthread_mutex_lock(&worker->mutex)) abort();
    worker->permit = 1;
    if (pthread_cond_signal(&worker->condition)) abort();
    if (pthread_mutex_unlock(&worker->mutex)) abort();
}
static void codex_size_monitor_park(CodexSizeMonitorWorker *worker, int64_t nanos) {
    if (pthread_mutex_lock(&worker->mutex)) abort();
    if (!worker->permit) {
        struct timespec deadline;
#ifdef __APPLE__
        deadline.tv_sec = nanos / 1000000000;
        deadline.tv_nsec = nanos % 1000000000;
        int result = pthread_cond_timedwait_relative_np(&worker->condition, &worker->mutex, &deadline);
#else
        if (clock_gettime(CLOCK_MONOTONIC, &deadline)) abort();
        deadline.tv_sec += nanos / 1000000000;
        deadline.tv_nsec += nanos % 1000000000;
        if (deadline.tv_nsec >= 1000000000) { ++deadline.tv_sec; deadline.tv_nsec -= 1000000000; }
        int result = pthread_cond_timedwait(&worker->condition, &worker->mutex, &deadline);
#endif
        if (result && result != ETIMEDOUT) abort();
    }
    worker->permit = 0;
    if (pthread_mutex_unlock(&worker->mutex)) abort();
}
static void codex_size_monitor_destroy(CodexSizeMonitorWorker *worker) {
    if (pthread_cond_destroy(&worker->condition)) abort();
    if (pthread_mutex_destroy(&worker->mutex)) abort();
}
#endif
#endif
