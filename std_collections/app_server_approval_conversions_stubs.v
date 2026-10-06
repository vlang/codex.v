module std_collections

// STUB: std::collections::HashMap<K, V> for source-observed path-keyed maps.
// V's built-in maps cannot key by PathBuf. Linear entries preserve borrowed
// key equality and overwrite an equal key's value while retaining its first key.
// Hash-table storage and randomized iteration remain untranslated.
pub struct HashMap[K, V] {
mut:
	entries []HashMapEntry[K, V]
}

// STUB: Owned key/value storage for the untranslated HashMap implementation.
pub struct HashMapEntry[K, V] {
pub mut:
	key   K
	value V
}

// STUB: Borrowed HashMap::get result. A tagged wrapper avoids V's ?&T C-generation
// limitation and owns no payload; the map must outlive the borrowed value.
pub struct HashMapValue[V] {
pub:
	has_value bool
	value     &V = unsafe { nil }
}

// STUB: std::collections::HashMap::insert consumes both inputs and returns the
// replaced owned value. Equal keys preserve the original key's native spelling.
// V's ownership backend drops an owning sum-type field on assignment even after
// moving it out. Remove/reinsert the whole row to transfer that payload safely.
pub fn (mut values HashMap[K, V]) insert[K, V](key K, value V) ?V {
	for index in 0 .. values.entries.len {
		if values.entries[index].key.equals(&key) {
			previous := values.entries[index]
			values.entries.delete(index)
			values.entries.insert(index, HashMapEntry[K, V]{ key: previous.key, value: value })
			return previous.value
		}
	}
	values.entries << HashMapEntry[K, V]{ key: key, value: value }
	return none
}

// STUB: std::collections::HashMap::len borrows the map.
pub fn (values &HashMap[K, V]) len[K, V]() int {
	return values.entries.len
}

// STUB: std::collections::HashMap::get borrows both map and lookup key.
pub fn (values &HashMap[K, V]) get[K, V](key &K) HashMapValue[V] {
	for index in 0 .. values.entries.len {
		if values.entries[index].key.equals(key) {
			return HashMapValue[V]{ has_value: true, value: &values.entries[index].value }
		}
	}
	return HashMapValue[V]{}
}

// STUB: std::collections::HashMap::keys borrows the native keys. V materializes
// the iterator as an array of references without cloning owned path bytes.
pub fn (values &HashMap[K, V]) keys[K, V]() []&K {
	mut result := []&K{cap: values.entries.len}
	for index in 0 .. values.entries.len {
		result << &values.entries[index].key
	}
	return result
}

// STUB: std::collections::HashMap's derived PartialEq compares key/value pairs
// without making the untranslated hash-table's iteration order observable.
pub fn (values &HashMap[K, V]) equals[K, V](other &HashMap[K, V]) bool {
	if values.entries.len != other.entries.len {
		return false
	}
	for index in 0 .. values.entries.len {
		entry := &values.entries[index]
		matched := other.get(&entry.key)
		if !matched.has_value || !entry.value.equals(matched.value) {
			return false
		}
	}
	return true
}
