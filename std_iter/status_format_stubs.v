module std_iter

// STUB: std::vec::IntoIter<T>, specialized to a contiguous V array. The array is
// consumed at IntoIterator's boundary; next moves each value without cloning it.
pub struct ArrayIntoIter[T] {
mut:
	items []T
}

// STUB: std::vec::IntoIter<T>::next, returning the next owned item.
pub fn (mut iter ArrayIntoIter[T]) next[T]() ?T {
	if iter.items.len == 0 {
		return none
	}
	return iter.items.pop()
}

// STUB: Vec<T>'s IntoIterator boundary. V arrays cannot receive external generic
// methods, so this wrapper supplies the source-shaped into_iter operation.
pub struct IntoArray[T] {
	items []T
}

// STUB: Wrap an owned V array for Rust Vec<T>::into_iter without copying items.
pub fn owned_array[T](items []T) IntoArray[T] {
	return IntoArray[T]{ items: items }
}

// STUB: Vec<T>::into_iter, consuming the original collection.
pub fn (items IntoArray[T]) into_iter[T]() ArrayIntoIter[T] {
	// V's array value iteration clones owning elements, and indexed moves are
	// rejected across iterations. Reverse in place and pop to preserve Rust's
	// forward traversal without changing the allocation of an owned item.
	mut iter := ArrayIntoIter[T]{ items: items.items }
	iter.items.reverse_in_place()
	return iter
}

// STUB: shared item from std::slice::Iter<T>. V's optional generic reference
// representation is unreliable, so a typed wrapper carries the non-owning item.
pub struct SliceItem[T] {
	value &T
}

// STUB: AsRef<str> on a borrowed slice item, preserving the original item's
// string reference rather than allocating an owned string.
pub fn (item &SliceItem[T]) as_ref[T]() &string {
	$if T is string {
		return item.value
	} $else $if T is &string {
		return *item.value
	} $else {
		return item.value.as_ref()
	}
}

// STUB: std::slice::Iter<T>, whose items are shared references into its owner.
// V rejects reference-to-array fields, so the iterator owns an array of views;
// allocating the views does not copy or consume the original items.
pub struct SliceIter[T] {
	items []SliceItem[T]
mut:
	index int
}

// STUB: std::slice::Iter<T>::next. The returned reference remains owned by the
// original slice, which must outlive the iterator as in Rust.
pub fn (mut iter SliceIter[T]) next[T]() ?SliceItem[T] {
	if iter.index >= iter.items.len {
		return none
	}
	index := iter.index
	iter.index++
	return iter.items[index]
}

// STUB: &[T]'s IntoIterator boundary, borrowing the original V array.
pub struct IntoSlice[T] {
	items []SliceItem[T]
}

// STUB: Wrap a borrowed V array for Rust &[T]::into_iter without cloning it.
pub fn borrowed_slice[T](items &[]T) IntoSlice[T] {
	mut views := []SliceItem[T]{cap: items.len}
	for index in 0 .. items.len {
		views << SliceItem[T]{ value: &items[index] }
	}
	return IntoSlice[T]{ items: views }
}

// STUB: &[T]::into_iter, consuming the view and preserving its shared owner.
pub fn (items IntoSlice[T]) into_iter[T]() SliceIter[T] {
	return SliceIter[T]{ items: items.items }
}
