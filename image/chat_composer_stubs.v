module image

import os

// STUB: image::image_dimensions. The eventual image crate port owns full decoding; this boundary
// validates supported container signatures and returns dimensions for PNG/GIF headers so a mere
// filename extension can never attach arbitrary data.
pub fn image_dimensions(path &string) !(u32, u32) {
	bytes := os.read_bytes(*path)!
	if bytes.len >= 24 && bytes[..8] == [u8(0x89), `P`, `N`, `G`, 0x0d, 0x0a, 0x1a, 0x0a] {
		width := read_be_u32(bytes, 16)
		height := read_be_u32(bytes, 20)
		if width > 0 && height > 0 {
			return width, height
		}
	}
	if bytes.len >= 10 && (bytes[..6].bytestr() == 'GIF87a' || bytes[..6].bytestr() == 'GIF89a') {
		width := u32(bytes[6]) | (u32(bytes[7]) << 8)
		height := u32(bytes[8]) | (u32(bytes[9]) << 8)
		if width > 0 && height > 0 {
			return width, height
		}
	}
	return error('unsupported or invalid image')
}

// STUB: private helper owned by `image`; reads a PNG big-endian dimension field.
fn read_be_u32(bytes []u8, index int) u32 {
	return (u32(bytes[index]) << 24) | (u32(bytes[index + 1]) << 16) | (u32(bytes[index + 2]) << 8) | u32(bytes[index + 3])
}
