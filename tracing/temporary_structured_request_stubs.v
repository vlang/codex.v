module tracing

// STUB: tracing::debug!(%error, message) retains the borrowed typed RPC failure
// separately from the event text. The tracing subscriber is untranslated.
pub fn debug_temporary_structured_unsubscribe_failure(failure &IError, message &string) {
	_ = failure
	_ = message
}
