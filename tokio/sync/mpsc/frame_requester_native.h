#ifndef CODEX_FRAME_REQUESTER_NATIVE_H
#define CODEX_FRAME_REQUESTER_NATIVE_H

#include <stdint.h>
#include <stdlib.h>
#include <errno.h>

#ifdef _WIN32
#include <windows.h>

// STUB: Tokio task wake boundary; native relative waits are independent of wall-clock changes.
typedef struct CodexFrameWake {
    CRITICAL_SECTION mutex;
    CONDITION_VARIABLE condition;
    uint64_t pending;
} CodexFrameWake;

// STUB: initialize the scheduler's native wake state.
static void codex_frame_wake_init(CodexFrameWake *wake) {
    InitializeCriticalSection(&wake->mutex);
    InitializeConditionVariable(&wake->condition);
    wake->pending = 0;
}

// STUB: Tokio releases its task wake resources after the last channel handle and receive
// operation finish. The shared channel guarantees no thread can post or wait afterward.
static void codex_frame_wake_destroy(CodexFrameWake *wake) {
    DeleteCriticalSection(&wake->mutex);
}

// STUB: notify a parked scheduler without losing notifications sent before it parks.
static void codex_frame_wake_post(CodexFrameWake *wake) {
    EnterCriticalSection(&wake->mutex);
    ++wake->pending;
    WakeConditionVariable(&wake->condition);
    LeaveCriticalSection(&wake->mutex);
}

// STUB: wait for a notification or a relative monotonic timeout; negative means indefinite.
static void codex_frame_wake_wait(CodexFrameWake *wake, int64_t nanos) {
    EnterCriticalSection(&wake->mutex);
    if (nanos < 0) {
        while (wake->pending == 0) {
            if (!SleepConditionVariableCS(&wake->condition, &wake->mutex, INFINITE)) abort();
        }
    } else if (wake->pending == 0) {
        uint64_t millis = (uint64_t)nanos / 1000000 + ((uint64_t)nanos % 1000000 != 0);
        DWORD timeout = millis >= INFINITE ? INFINITE - 1 : (DWORD)millis;
        if (!SleepConditionVariableCS(&wake->condition, &wake->mutex, timeout) &&
            GetLastError() != ERROR_TIMEOUT) abort();
    }
    if (wake->pending > 0) --wake->pending;
    LeaveCriticalSection(&wake->mutex);
}
#else
#include <pthread.h>
#include <time.h>

// STUB: a native wake state for Tokio's parked scheduler task.
typedef struct CodexFrameWake {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    uint64_t pending;
} CodexFrameWake;

// STUB: use monotonic POSIX condition deadlines; Apple supplies a relative-wait API instead.
static void codex_frame_wake_init(CodexFrameWake *wake) {
    if (pthread_mutex_init(&wake->mutex, NULL) != 0) abort();
#ifdef __APPLE__
    if (pthread_cond_init(&wake->condition, NULL) != 0) abort();
#else
    pthread_condattr_t attributes;
    if (pthread_condattr_init(&attributes) != 0) abort();
    if (pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC) != 0) abort();
    if (pthread_cond_init(&wake->condition, &attributes) != 0) abort();
    if (pthread_condattr_destroy(&attributes) != 0) abort();
#endif
    wake->pending = 0;
}

// STUB: release the native task wake only after every post/wait operation has finished.
// Freeing the GC-backed storage alone does not release pthread synchronization resources.
static void codex_frame_wake_destroy(CodexFrameWake *wake) {
    if (pthread_cond_destroy(&wake->condition) != 0) abort();
    if (pthread_mutex_destroy(&wake->mutex) != 0) abort();
}

// STUB: notify a parked scheduler, retaining notifications posted before the wait.
static void codex_frame_wake_post(CodexFrameWake *wake) {
    if (pthread_mutex_lock(&wake->mutex) != 0) abort();
    ++wake->pending;
    if (pthread_cond_signal(&wake->condition) != 0) abort();
    if (pthread_mutex_unlock(&wake->mutex) != 0) abort();
}

// STUB: wait on a monotonic deadline or indefinitely. Spurious wakes return to the
// V selector, which rechecks requests, channel closure, and the original full-width Instant.
static void codex_frame_wake_wait(CodexFrameWake *wake, int64_t nanos) {
    if (pthread_mutex_lock(&wake->mutex) != 0) abort();
    if (nanos < 0) {
        while (wake->pending == 0) {
            if (pthread_cond_wait(&wake->condition, &wake->mutex) != 0) abort();
        }
    } else if (wake->pending == 0) {
        struct timespec target;
        int result;
#ifdef __APPLE__
        target.tv_sec = nanos / 1000000000;
        target.tv_nsec = nanos % 1000000000;
        result = pthread_cond_timedwait_relative_np(&wake->condition, &wake->mutex, &target);
#else
        if (clock_gettime(CLOCK_MONOTONIC, &target) != 0) abort();
        target.tv_sec += nanos / 1000000000;
        target.tv_nsec += nanos % 1000000000;
        if (target.tv_nsec >= 1000000000) {
            ++target.tv_sec;
            target.tv_nsec -= 1000000000;
        }
        result = pthread_cond_timedwait(&wake->condition, &wake->mutex, &target);
#endif
        if (result != 0 && result != ETIMEDOUT) abort();
    }
    if (wake->pending > 0) --wake->pending;
    if (pthread_mutex_unlock(&wake->mutex) != 0) abort();
}
#endif

#endif
