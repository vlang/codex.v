module time

// STUB: tokio::time::error::Elapsed, distinct from the operation's own error.
pub struct Elapsed {}

// STUB: Elapsed's error formatting.
pub fn (elapsed Elapsed) msg() string {
	return 'operation timed out'
}

// STUB: V IError compatibility for Tokio's distinct elapsed variant.
pub fn (elapsed Elapsed) code() int {
	return 0
}

// STUB: execute an owned future payload once; unlike captured V closure data,
// its owned strings, structs, and receiver move into the worker without cloning.
fn run_owned_timed_operation[T, P](payload P, operation fn (P) !T, completions chan TimeoutCompletion[T]) {
	value := operation(payload) or {
		completions <- TimeoutCompletion[T]{ operation_error: err }
		return
	}
	completions <- TimeoutCompletion[T]{ succeeded: true, value: value }
}

// STUB: Tokio timeout for a future with owned captures. The deadline covers the
// complete operation, and elapsed remains distinguishable from transport/server
// errors. V cannot cancel a worker: its shared handle lease keeps borrowed state
// alive and buffered completion allows a late worker to release owned captures.
pub fn timeout_owned[T, P](duration_nanos i64, payload P, operation fn (P) !T) !T {
	completions := chan TimeoutCompletion[T]{cap: 1}
	spawn run_owned_timed_operation[T, P](payload, operation, completions)
	select {
		completion := <-completions {
			if completion.succeeded {
				return completion.value
			}
			return completion.operation_error
		}
		duration_nanos {
			return Elapsed{}
		}
	}
	return Elapsed{}
}
