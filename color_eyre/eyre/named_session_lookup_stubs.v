module eyre

// STUB: eyre::Report stores contextual errors without losing the original typed
// cause. Display prints the outer context as Rust Report::to_string does.
pub struct Report {
pub:
	context string
	source  IError
	// STUB: Report::new's message is the root cause's Display, whereas wrap_err
	// adds a separate context. Alternate Display must not duplicate a root message.
	is_root bool
}

// STUB: color_eyre::eyre::WrapErr wraps a consumed error with owned context text.
pub fn wrap_err(failure IError, context string) IError {
	return Report{ context: context, source: failure }
}

// STUB: Report's Display operation reports the outermost attached context.
pub fn (report &Report) msg() string {
	return report.context.clone()
}

// STUB: V's IError compatibility delegates the numeric code to the typed cause.
pub fn (report &Report) code() int {
	return report.source.code()
}

// STUB: borrow the original typed cause through Report's context chain, allowing
// V interface narrowing to replace Rust's downcast_ref::<TypedRequestError>().
pub fn root_cause(failure &IError) &IError {
	if failure is Report {
		return root_cause(&failure.source)
	}
	return failure
}
