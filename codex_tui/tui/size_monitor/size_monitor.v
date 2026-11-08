// Recovers lost tmux resize notifications without querying geometry on the UI thread.
//
// One worker belongs to the event broker, including across nested screens. Queries never
// hold the shared lock. Pauses and newer geometry invalidate both in-flight and queued
// samples. Dropping the monitor wakes the worker without joining a possibly blocked OS call;
// that single in-flight call may finish later, but cannot publish or start another query.
module size_monitor

import codex_terminal_detection
import crossterm.terminal
import ratatui.layout
import sync
import time
import tracing
import tokio.sync.broadcast

// Public across the V module split so the original parent-level tests reuse the deadline.
pub const check_interval = 500 * time.millisecond

// V's GC build has no scope destructor; callers close explicitly there. The ownership
// checker recognizes this Drop contract and invokes the idempotent hook automatically.
interface Drop {
mut:
	drop()
}

@[heap]
struct State {
mut:
	mutex      &sync.Mutex = sync.new_mutex()
	size       layout.Size
	generation u64
	pending    ?layout.Size
	active     bool = true
	stopped    bool
	// Existing screen-size tests record observe calls only in their explicit fixture.
	record_observations bool
	observations        []layout.Size
}

pub struct SizeMonitor implements Drop {
	state  &State = unsafe { nil }
	worker MonitorWorker
}

// An owned typed callable adapts Rust's FnMut + Send + 'static closure. finish releases
// its captures when the detached worker exits, just as dropping the Rust closure does.
pub interface SizeQuery {
mut:
	query() !layout.Size
	finish()
}

struct WindowSizeQuery {}

fn (mut query WindowSizeQuery) query() !layout.Size {
	// Unlike terminal::size(), window_size() has no tput subprocess fallback.
	size := terminal.window_size()!
	return layout.Size.new(size.columns, size.rows)
}

fn (mut query WindowSizeQuery) finish() {}

pub fn SizeMonitor.start(terminal_info &codex_terminal_detection.TerminalInfo, size layout.Size, draw_tx broadcast.DrawSender) ?SizeMonitor {
	// V's unix also includes Plan 9; Rust cfg!(unix) excludes that platform.
	$if !unix || plan9 {
		draw_tx.close()
		return none
	} $else {
		if mux := terminal_info.multiplexer {
			if mux.kind != .tmux {
				draw_tx.close()
				return none
			}
		} else {
			draw_tx.close()
			return none
		}
		return SizeMonitor.spawn(size, draw_tx, WindowSizeQuery{}) or {
			tracing.warn_start_size_monitor(&err)
			return none
		}
	}
}

// Rust's private spawn is public across the V module split so the original parent-level
// event-stream integration tests can supply their owned blocking query callable.
pub fn SizeMonitor.spawn(size layout.Size, draw_tx broadcast.DrawSender, query SizeQuery) !SizeMonitor {
	state := &State{ size: size }
	worker := MonitorWorker.new() or {
		draw_tx.close()
		mut failed_query := query
		failed_query.finish()
		return err
	}
	// The shared pointer plays Arc::clone's role: the detached worker retains the state
	// after the owning monitor is dropped. No worker query holds the state's mutex.
	context := &WorkerContext{ state: state, worker: worker, draw_tx: draw_tx, query: query }
	worker.start(context) or {
		context.draw_tx.close()
		unsafe {
			mut failed_context := context
			failed_context.query.finish()
		}
		worker.destroy()
		return err
	}
	return SizeMonitor{ state: state, worker: worker }
}

@[heap]
struct WorkerContext {
	state   &State
	worker  MonitorWorker
	draw_tx broadcast.DrawSender
mut:
	query SizeQuery
}

fn run_size_monitor(context voidptr) voidptr {
	unsafe {
		mut shared := &WorkerContext(context)
		defer {
			shared.draw_tx.close()
			shared.query.finish()
			shared.worker.destroy()
		}
		for {
			shared.worker.park_timeout(i64(check_interval))
			mut state := shared.state
			state.mutex.lock()
			if state.stopped {
				state.mutex.unlock()
				break
			}
			if !state.active {
				state.mutex.unlock()
				continue
			}
			generation := state.generation
			state.mutex.unlock()
			sampled := shared.query.query() or { layout.Size{} }
			state.mutex.lock()
			if state.stopped {
				state.mutex.unlock()
				break
			}
			if state.generation != generation {
				state.mutex.unlock()
				continue
			}
			state.pending = if sampled.width > 0 && sampled.height > 0 && sampled != state.size {
				?layout.Size(sampled)
			} else {
				none
			}
			should_draw := state.pending != none
			state.mutex.unlock()
			if should_draw {
				shared.draw_tx.send(broadcast.Draw{}) or {}
			}
		}
	}
	return unsafe { nil }
}

pub fn (monitor &SizeMonitor) observe(size layout.Size) {
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		state.size = size
		// V unsigned addition has the same wrapping behavior as Rust wrapping_add.
		state.generation++
		state.pending = none
		if state.record_observations { state.observations << size }
	}
}

pub fn (monitor &SizeMonitor) set_active(active bool) {
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		state.active = active
		state.generation++
		state.pending = none
	}
}

pub fn (monitor &SizeMonitor) take_resize() ?layout.Size {
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		pending := state.pending
		state.pending = none
		size := pending or { return none }
		state.size = size
		state.generation++
		tracing.debug_recovered_terminal_size(size)
		return size
	}
}

// Drop only marks stopped and unparks; it never joins an in-flight OS query. The wake
// storage is destroyed by the last worker action after stopped prevents future unparks.
pub fn (monitor &SizeMonitor) close() {
	// The tagged optional wrapper's absent storage is an allocation-free empty value.
	if monitor.state == unsafe { nil } {
		return
	}
	unsafe {
		mut state := monitor.state
		state.mutex.lock()
		defer { state.mutex.unlock() }
		if !state.stopped {
			state.stopped = true
			monitor.worker.unpark()
		}
	}
}

pub fn (mut monitor SizeMonitor) drop() {
	monitor.close()
}

// Rust recovers poisoned mutexes. V panics abort rather than unwind across a held mutex,
// so a poisoned mutex cannot be observed by this implementation.
