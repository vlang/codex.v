module eyre

// STUB: eyre::Report alternate Display prints the full context/cause chain,
// unlike ordinary Display, which intentionally reports only the outer context.
pub fn alternate_display(failure &IError) string {
	if failure is Report {
		if failure.is_root { return alternate_display(&failure.source) }
		return '${failure.context}: ${alternate_display(&failure.source)}'
	}
	return failure.msg()
}
