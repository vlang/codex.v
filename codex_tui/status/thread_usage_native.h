#ifndef CODEX_STATUS_THREAD_USAGE_NATIVE_H
#define CODEX_STATUS_THREAD_USAGE_NATIVE_H
#include <stdint.h>

/* V has no AtomicBool field type. This aligned u32 is accessed atomically
 * throughout its lifetime, with Rust's Ordering::Relaxed on GCC/Clang/TinyCC.
 * MSVC interlocked operations supply stronger ordering, also valid for Relaxed. */
#if defined(_MSC_VER)
#include <intrin.h>
static inline void codex_status_thread_usage_store(uint32_t *value) {
    _InterlockedExchange((volatile long *)value, 1);
}
static inline uint32_t codex_status_thread_usage_load(const uint32_t *value) {
    return (uint32_t)_InterlockedCompareExchange((volatile long *)value, 0, 0);
}
#elif defined(__TINYC__)
extern void __atomic_store_4(unsigned int *, unsigned int, int);
extern unsigned int __atomic_load_4(unsigned int *, int);
static inline void codex_status_thread_usage_store(uint32_t *value) {
    __atomic_store_4((unsigned int *)value, /* val */ 1, 0);
}
static inline uint32_t codex_status_thread_usage_load(const uint32_t *value) {
    return __atomic_load_4((unsigned int *)value, 0);
}
#else
static inline void codex_status_thread_usage_store(uint32_t *value) {
    __atomic_store_n(value, /* val */ 1, __ATOMIC_RELAXED);
}
static inline uint32_t codex_status_thread_usage_load(const uint32_t *value) {
    return __atomic_load_n(value, __ATOMIC_RELAXED);
}
#endif
#endif
