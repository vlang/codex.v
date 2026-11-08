module size_monitor

import ratatui.layout

// Safe owned/borrowed views of Option<SizeMonitor> avoid V's unreliable &?T and ?&T
// representations for resource-bearing values. The borrowing view never drops its owner.
pub struct SizeMonitorOption {
	present bool
	monitor SizeMonitor
}

pub struct SizeMonitorRef {
pub:
	is_some bool
	value   &SizeMonitor = unsafe { nil }
}

pub fn SizeMonitorOption.some(monitor SizeMonitor) SizeMonitorOption {
	// Store the moved owner by value. A pointer to a moved local would be a borrow;
	// V ownership would correctly Drop that local before this wrapper could use it.
	return SizeMonitorOption{ present: true, monitor: monitor }
}

pub fn (option &SizeMonitorOption) as_ref() SizeMonitorRef {
	if option.present {
		return SizeMonitorRef{ is_some: true, value: &option.monitor }
	}
	return SizeMonitorRef{}
}

pub fn (option &SizeMonitorOption) close() {
	if option.present { option.monitor.close() }
}

pub fn SizeMonitorOption.fixture(size layout.Size) SizeMonitorOption {
	return SizeMonitorOption{ present: true, monitor: SizeMonitor{ state: &State{ size: size, record_observations: true } } }
}

pub fn (monitor &SizeMonitor) fixture_observations() []layout.Size {
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		return state.observations.clone()
	}
}

pub fn (monitor &SizeMonitor) fixture_unpark() {
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		if !state.stopped { monitor.worker.unpark() }
	}
}

// The original test clones Arc<State> and inspects it after dropping the broker.
// This handle preserves that shared identity without exposing unlocked mutable fields.
pub struct SizeMonitorStateView {
	state &State
}

pub struct SizeMonitorSnapshot {
pub:
	size       layout.Size
	generation u64
	pending    ?layout.Size
	active     bool
	stopped    bool
}

pub fn (monitor &SizeMonitor) fixture_state() SizeMonitorStateView {
	return SizeMonitorStateView{ state: monitor.state }
}

pub fn (view &SizeMonitorStateView) snapshot() SizeMonitorSnapshot {
	unsafe {
		mut state := view.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		return SizeMonitorSnapshot{ size: state.size, generation: state.generation, pending: state.pending, active: state.active, stopped: state.stopped }
	}
}
