module std_iter

// STUB: borrowed Option<&T> view for std::iter::Peekable::peek. The pointer is valid only until
// the next mutable iterator operation, matching Rust's borrow. It is never an owned optional T.
pub struct BorrowedItem[T] {
pub:
	present bool
	value   &T = unsafe { nil }
}

// STUB: storage for std::iter::Peekable's owned cached item. V ownership C generation can free
// nested extracted arrays when an inline cache is reset or refilled. A fresh heap slot preserves
// Rust's move boundary without cloning; this adds one allocation per populated peek cache.
@[heap]
struct CacheSlot[T] {
	value T
}

// STUB: std::iter::Peekable's lazy one-item cache. I must implement next() ?T; no input is
// collected eagerly and an observed None is cached only until next(), as in Rust's Peekable.
pub struct Peekable[I, T] {
mut:
	iter    I
	peeked  bool
	present bool
	value   &CacheSlot[T] = unsafe { nil }
}

// STUB: std::iter::Iterator::peekable consumes the original iterator without pulling an item.
pub fn peekable[I, T](iter I) Peekable[I, T] {
	return Peekable[I, T]{ iter: iter }
}

// STUB: std::iter::Peekable::next moves the cached item, or calls the underlying next directly.
pub fn (mut iter Peekable[I, T]) next[I, T]() ?T {
	if !iter.peeked {
		return iter.iter.next()
	}
	iter.peeked = false
	if !iter.present {
		return none
	}
	iter.present = false
	value := iter.value
	iter.value = unsafe { nil }
	return value.value
}

// STUB: std::iter::Peekable::peek calls next at most once until the cached item is consumed.
pub fn (mut iter Peekable[I, T]) peek[I, T]() BorrowedItem[T] {
	if !iter.peeked {
		iter.peeked = true
		if value := iter.iter.next() {
			iter.value = &CacheSlot[T]{ value: value }
			iter.present = true
		} else {
			iter.present = false
		}
	}
	if !iter.present {
		return BorrowedItem[T]{}
	}
	return BorrowedItem[T]{ present: true, value: &iter.value.value }
}
