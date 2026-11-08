module uuid

import crypto.rand
import encoding.hex

// STUB: uuid::Uuid, retaining its allocation-free 128-bit representation.
pub struct Uuid {
	bytes [16]u8
}

// STUB: uuid::Uuid::new_v4. The OS entropy source preserves Rust's random UUID
// generation, including its panic when randomness cannot be obtained.
pub fn Uuid.new_v4() Uuid {
	mut bytes := rand.bytes(16) or { panic('could not obtain UUID randomness: ${err}') }
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	mut fixed := [16]u8{}
	for index in 0 .. 16 {
		fixed[index] = bytes[index]
	}
	return Uuid{ bytes: fixed }
}

// STUB: uuid::Uuid's Display operation, lower-case hyphenated UUID formatting.
pub fn (value Uuid) str() string {
	encoded := hex.encode(value.bytes[..])
	return '${encoded[..8]}-${encoded[8..12]}-${encoded[12..16]}-${encoded[16..20]}-${encoded[20..]}'
}
