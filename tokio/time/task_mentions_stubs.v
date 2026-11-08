module time

// STUB: tokio::time::timeout awaited to completion. Rust yields
// `Result<F::Output, Elapsed>`; V cannot nest the operation's own result inside another result,
// so an elapsed deadline and an operation error both surface as the returned error.
// A timed channel wait enforces the caller's deadline. V cannot cancel a running
// worker as Tokio cancels a dropped future: a timed-out operation may still finish,
// and its buffered completion avoids blocking that worker after the caller returns.
// `duration_nanos` is nanoseconds because this module cannot import V's own `time` module.
pub fn timeout[T](duration_nanos i64, operation fn () !T) !T {
	completions := chan TimeoutCompletion[T]{cap: 1}
	spawn run_timed_operation[T](operation, completions)
	select {
		completion := <-completions {
			if completion.succeeded {
				return completion.value
			}
			return completion.operation_error
		}
		duration_nanos {
			return error('operation timed out')
		}
	}
	return error('operation timed out')
}
