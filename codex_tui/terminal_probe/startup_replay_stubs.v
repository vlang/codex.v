module terminal_probe

import codex_tui.color
import encoding.utf8

// STUB: terminal_probe.rs osc_payload_end's borrowed tuple result. Native probing is
// untranslated; these parser helpers provide its exact color-response boundary.
pub struct OscPayloadEnd {
pub:
	offset int
	length int
}

// STUB: terminal_probe.rs::osc_payload_end locates the first BEL or complete ST terminator.
pub fn osc_payload_end(buffer &[]u8) ?OscPayloadEnd {
	mut index := 0
	for index < buffer.len {
		if buffer[index] == 0x07 {
			return OscPayloadEnd{ offset: index, length: 1 }
		}
		if buffer[index] == 0x1b && index + 1 < buffer.len && buffer[index + 1] == `\\` {
			return OscPayloadEnd{ offset: index, length: 2 }
		}
		index++
	}
	return none
}

// STUB: terminal_probe.rs::parse_osc_color keeps slot matching, UTF-8 rejection, and
// RGB/RGBA validation. V's temporary string owns its bytes because V has no borrowed
// Rust str view; the caller's byte buffer remains borrowed throughout.
pub fn parse_osc_color(buffer &[]u8, slot u8) ?color.Rgb {
	prefix := '\x1b]${slot};'.bytes()
	if buffer.len < prefix.len {
		return none
	}
	mut start := -1
	for index in 0 .. buffer.len - prefix.len + 1 {
		mut matches := true
		for offset in 0 .. prefix.len {
			if buffer[index + offset] != prefix[offset] {
				matches = false
				break
			}
		}
		if matches {
			start = index + prefix.len
			break
		}
	}
	if start < 0 {
		return none
	}
	// SAFETY: start follows a complete prefix inside buffer. Both views remain shared and
	// local until the payload is copied into its temporary owned string.
	rest := unsafe { (*buffer)[start..] }
	terminator := osc_payload_end(&rest) or { return none }
	payload_bytes := unsafe { rest[..terminator.offset] }
	if !utf8.validate(payload_bytes.data, payload_bytes.len) {
		return none
	}
	payload := payload_bytes.bytestr()
	return parse_osc_rgb(&payload)
}

// STUB: terminal_probe.rs::parse_osc_rgb. Temporary split strings adapt Rust's
// borrowed str iterator; Unicode trim uses exactly Rust char::is_whitespace.
fn parse_osc_rgb(payload &string) ?color.Rgb {
	trimmed := payload.trim('\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
	colon := trimmed.index(':') or { return none }
	prefix := trimmed[..colon]
	is_rgba := prefix.to_lower() == 'rgba'
	if !is_rgba && prefix.to_lower() != 'rgb' {
		return none
	}
	parts := trimmed[colon + 1..].split('/')
	if parts.len != if is_rgba { 4 } else { 3 } {
		return none
	}
	r := parse_osc_component(&parts[0]) or { return none }
	g := parse_osc_component(&parts[1]) or { return none }
	b := parse_osc_component(&parts[2]) or { return none }
	if is_rgba {
		_ = parse_osc_component(&parts[3]) or { return none }
	}
	return color.Rgb{ r: r, g: g, b: b }
}

// STUB: terminal_probe.rs::parse_osc_component implements u16::from_str_radix(16),
// including its optional leading plus, then scales using the complete source length.
fn parse_osc_component(component &string) ?u8 {
	if component.len < 1 || component.len > 4 {
		return none
	}
	start := if (*component)[0] == `+` { 1 } else { 0 }
	if start == component.len {
		return none
	}
	mut value := u32(0)
	for index in start .. component.len {
		byte := (*component)[index]
		digit := match byte {
			`0`...`9` { u32(byte - `0`) }
			`a`...`f` { u32(byte - `a` + 10) }
			`A`...`F` { u32(byte - `A` + 10) }
			else { return none }
		}
		value = value * 16 + digit
	}
	maximum := (u32(1) << u32(component.len * 4)) - 1
	return u8(value * 255 / maximum)
}
