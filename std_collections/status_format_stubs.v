module std_collections

// STUB: std::collections::BTreeSet<T>. A sorted V array supplies the set's
// ordered membership and owned insertion; Rust's balanced-tree storage is not
// translated. Only the source-observed contains/insert operations are provided.
pub struct BTreeSet[T] {
mut:
	values []T
}

// STUB: std::collections::BTreeSet::contains, borrowing the lookup key.
pub fn (set &BTreeSet[T]) contains[T](value &T) bool {
	mut lo := 0
	mut hi := set.values.len
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if set.values[mid] < *value {
			lo = mid + 1
		} else if set.values[mid] > *value {
			hi = mid
		} else {
			return true
		}
	}
	return false
}

// STUB: std::collections::BTreeSet::insert, consuming the owned key, returning
// whether insertion took place. An equal existing key retains its identity.
pub fn (mut set BTreeSet[T]) insert[T](value T) bool {
	mut lo := 0
	mut hi := set.values.len
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if set.values[mid] < value {
			lo = mid + 1
		} else if set.values[mid] > value {
			hi = mid
		} else {
			return false
		}
	}
	set.values.insert(lo, value)
	return true
}
