module atomic

import sync

// STUB: shared Arc<AtomicBool> storage. Only the allocation and relaxed value access
// needed by the untranslated event-stream boundary are provided, with a native mutex.
@[heap]
struct SharedBoolCell {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	value bool
}

// STUB: owned Arc<AtomicBool> handle; its borrowed APIs retain shared identity.
pub struct SharedAtomicBool {
	cell &SharedBoolCell = unsafe { nil }
}

// STUB: Arc::new(AtomicBool::new(v))'s combined owned construction boundary.
pub fn SharedAtomicBool.new(v bool) SharedAtomicBool {
	return SharedAtomicBool{ cell: &SharedBoolCell{ value: v } }
}

// STUB: Arc::clone retains the same atomic owner rather than copying its current value.
pub fn (owner &SharedAtomicBool) clone() SharedAtomicBool {
	return SharedAtomicBool{ cell: owner.cell }
}

// STUB: AtomicBool::load(Ordering::Relaxed), synchronized at this native fixture boundary.
pub fn (owner &SharedAtomicBool) load() bool {
	unsafe {
		mut cell := owner.cell
		cell.mutex.lock()
		defer { cell.mutex.unlock() }
		return cell.value
	}
}

// STUB: AtomicBool::store(value, Ordering::Relaxed), retaining shared handle identity.
pub fn (owner &SharedAtomicBool) store(value bool) {
	unsafe {
		mut cell := owner.cell
		cell.mutex.lock()
		defer { cell.mutex.unlock() }
		cell.value = value
	}
}
