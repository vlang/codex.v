module terminal_hyperlinks

import strings
import url

// STUB: terminal_hyperlinks.rs::web_destination's complete validation policy,
// reusing the canonical URL owner. Full terminal hyperlink rendering is pending.
// International domains still require the canonical URL stub's untranslated
// IDNA support, so those destinations remain visible without a clickable link.
pub fn web_destination(destination &string) ?string {
	safe_destination := clipboard_sanitized_destination(destination) or { return none }
	parsed := url.Url.parse(&safe_destination) or { return none }
	if *parsed.scheme() !in ['http', 'https'] {
		return none
	}
	parsed.host_str() or { return none }
	return safe_destination
}

// STUB: terminal_hyperlinks.rs::sanitized_destination limits the ORIGINAL byte
// length before removing every Unicode Control (C0/C1) scalar, preserving order.
fn clipboard_sanitized_destination(destination &string) ?string {
	if destination.len > 8 * 1024 {
		return none
	}
	mut out := strings.new_builder(destination.len)
	for ch in destination.runes_iterator() {
		if ch <= 0x1f || (ch >= 0x7f && ch <= 0x9f) {
			continue
		}
		out.write_string(ch.str())
	}
	return out.str()
}
