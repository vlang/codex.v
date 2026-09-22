module thread_id

// STUB: ThreadId is UUID-backed in protocol/src/thread_id.rs. The translated protocol currently
// retains its canonical string form until that source owner is ported.
pub struct ThreadId {
pub:
	value string
}

// STUB: from_string mirrors ThreadId::from_string in protocol/src/thread_id.rs and will use
// uuid::Uuid::parse_str once the UUID dependency is translated.
pub fn from_string(value &string) !ThreadId {
	if !is_canonical_uuid(value) {
		return error('invalid UUID `${*value}`')
	}
	return ThreadId{
		value: value.clone()
	}
}

// STUB: is_canonical_uuid supplies UUID validation for the temporary string-backed ThreadId.
fn is_canonical_uuid(value &string) bool {
	if value.len != 36 {
		return false
	}
	for index, character in value.bytes() {
		if index == 8 || index == 13 || index == 18 || index == 23 {
			if character != `-` {
				return false
			}
		} else if !((character >= `0` && character <= `9`)
			|| (character >= `a` && character <= `f`) || (character >= `A` && character <= `F`)) {
			return false
		}
	}
	return true
}

// STUB: Display formatting belongs to protocol/src/thread_id.rs.
pub fn (id &ThreadId) str() string {
	return id.value
}
