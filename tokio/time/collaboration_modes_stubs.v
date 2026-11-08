module time

// STUB: Tokio future completion storage for the V worker-backed timeout adapter.
struct TimeoutCompletion[T] {
	succeeded       bool
	value           T
	operation_error IError = error('uninitialized operation completion')
}

// STUB: polls a future-equivalent synchronous operation on a V worker. Native
// cancellation is unavailable; the buffered sender can finish after a deadline.
fn run_timed_operation[T](operation fn () !T, completions chan TimeoutCompletion[T]) {
	value := operation() or {
		completions <- TimeoutCompletion[T]{ operation_error: err }
		return
	}
	completions <- TimeoutCompletion[T]{ succeeded: true, value: value }
}
