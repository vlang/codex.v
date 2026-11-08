#ifndef CODEX_FRAME_RATE_LIMITER_NATIVE_H
#define CODEX_FRAME_RATE_LIMITER_NATIVE_H

#include <stdint.h>

// STUB: component-shaped native boundary for std::time::Instant's monotonic clock.
typedef struct CodexFrameMonotonicReading {
    int64_t unix_seconds;
    uint32_t unix_nanos;
    uint64_t windows_ticks;
    uint64_t windows_frequency;
    uint8_t ok;
} CodexFrameMonotonicReading;

#ifdef _WIN32
#include <windows.h>

// STUB: std::time::Instant::now uses QueryPerformanceCounter on Windows.
static CodexFrameMonotonicReading codex_frame_monotonic_read(void) {
    LARGE_INTEGER ticks, frequency;
    CodexFrameMonotonicReading result = {0};
    if (!QueryPerformanceCounter(&ticks) || !QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
        return result;
    }
    result.windows_ticks = (uint64_t)ticks.QuadPart;
    result.windows_frequency = (uint64_t)frequency.QuadPart;
    result.ok = 1;
    return result;
}
#else
#include <time.h>

// STUB: std::time::Instant::now uses CLOCK_UPTIME_RAW on Apple and CLOCK_MONOTONIC elsewhere.
static CodexFrameMonotonicReading codex_frame_monotonic_read(void) {
    struct timespec value;
    CodexFrameMonotonicReading result = {0};
#ifdef __APPLE__
    const clockid_t clock_id = CLOCK_UPTIME_RAW;
#else
    const clockid_t clock_id = CLOCK_MONOTONIC;
#endif
    if (clock_gettime(clock_id, &value) != 0 || value.tv_nsec < 0 || value.tv_nsec >= 1000000000) {
        return result;
    }
    result.unix_seconds = (int64_t)value.tv_sec;
    result.unix_nanos = (uint32_t)value.tv_nsec;
    result.ok = 1;
    return result;
}
#endif
#endif
