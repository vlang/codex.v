module eyre

// STUB: eyre::Report::new owns the original typed error. Preserve its display
// text before consuming the cause, so source downcasts survive every context.
pub fn Report.new(source IError) Report {
	message := source.msg()
	return Report{ context: message, source: source, is_root: true }
}
