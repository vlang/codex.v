module tracing

// STUB: tracing::Span retains the request instrumentation context attached to spawned work.
pub struct Span {
pub:
	name string
}

// STUB: InstrumentedTask represents Future::instrument at the V task boundary.
pub struct InstrumentedTask {
pub:
	run_task fn () = unsafe { nil }
}

// STUB: tracing::Instrument::instrument attaches a span to one background task.
pub fn instrument_task(task fn (), span Span) InstrumentedTask {
	_ = span
	return InstrumentedTask{ run_task: task }
}

// STUB: executes the instrumented task when its task tracker schedules it.
pub fn (task &InstrumentedTask) run() {
	task.run_task()
}

// STUB: Rust tracing records the dynamic callable count on the thread-start creation span.
pub fn record_thread_start_create_dynamic_tool_count(dynamic_tool_count int) {
	_ = dynamic_tool_count
}

// STUB: records a warning at the tracing subscriber boundary.
pub fn warn(message &string) {
	_ = message
}
