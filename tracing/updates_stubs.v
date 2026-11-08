module tracing

// STUB: tracing::error!("Failed to update version: {e}") preserves the source
// error context at the untranslated subscriber boundary.
pub fn error_update_version(failure &IError) {
	_ = failure
}
