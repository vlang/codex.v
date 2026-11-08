module tracing

import codex_tui.streaming.table_holdback
import math.unsigned

// STUB: tracing::trace! metadata for the source's incremental table scanner.
// Keep byte/line counts, the complete typed state, and Rust's full u128 elapsed
// microseconds so a future tracing subscriber can record every original field.
pub struct TableHoldbackIncrementalScan {
pub:
	bytes      usize
	lines      usize
	state      table_holdback.TableHoldbackState
	elapsed_us unsigned.Uint128
}

// STUB: the tracing subscriber for "table holdback incremental scan" is not yet
// translated. The typed event boundary preserves metadata without inventing a
// logging destination or reducing the state/elapsed values to strings.
pub fn trace_table_holdback_incremental_scan(event TableHoldbackIncrementalScan) {
	_ = event
}
