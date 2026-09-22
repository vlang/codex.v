module user_input

// Conservative cap so one user message cannot monopolize a large context window.
pub const max_user_input_text_chars = 1 << 20

// STUB: codex_protocol::user_input::ByteRange. Its source owner is protocol/src/user_input.rs.
pub struct ByteRange {
pub:
	// Start byte offset (inclusive) within the UTF-8 text buffer.
	start int
	// End byte offset (exclusive) within the UTF-8 text buffer.
	end int
}

// STUB: codex_protocol::user_input::TextElement. Its source owner is protocol/src/user_input.rs.
pub struct TextElement {
pub:
	// Byte range in the parent `text` buffer that this element occupies.
	byte_range ByteRange
mut:
	// Optional human-readable placeholder for the element, displayed in the UI.
	placeholder ?string
}

// STUB: codex_protocol::user_input::TextElement::new.
pub fn TextElement.new(byte_range ByteRange, placeholder ?string) TextElement {
	return TextElement{ byte_range: byte_range, placeholder: placeholder }
}

// Returns a copy of this element with a remapped byte range.
//
// The placeholder is preserved as-is; callers must ensure the new range
// still refers to the same logical element (and same placeholder)
// within the new text.
// STUB: codex_protocol::user_input::TextElement::map_range.
pub fn (element &TextElement) map_range(mapper fn (ByteRange) ByteRange) TextElement {
	return TextElement.new(mapper(element.byte_range), element.placeholder)
}

// STUB: codex_protocol::user_input::TextElement::set_placeholder.
pub fn (mut element TextElement) set_placeholder(placeholder ?string) {
	element.placeholder = placeholder
}

// Returns the stored placeholder without falling back to the text buffer.
//
// This must only be used inside equivalent protocol-type conversions where the source text is
// unavailable. Prefer `placeholder_text(text)` everywhere else.
// STUB: codex_protocol::user_input::TextElement::_placeholder_for_conversion_only. V returns an
// owned optional string because it has no borrowed string-slice return.
pub fn (element &TextElement) not_hidden_placeholder_for_conversion_only() ?string {
	if placeholder := element.placeholder {
		return placeholder.clone()
	}
	return none
}

// STUB: codex_protocol::user_input::TextElement::placeholder. V returns an owned optional string
// because it has no borrowed string-slice return equivalent to Rust's `Option<&str>`.
pub fn (element &TextElement) placeholder_text(text &string) ?string {
	if placeholder := element.placeholder {
		return placeholder.clone()
	}
	if element.byte_range.start < 0 || element.byte_range.end < element.byte_range.start
		|| element.byte_range.end > text.len {
		return none
	}
	return (*text)[element.byte_range.start..element.byte_range.end].clone()
}

// STUB: exact Rust method-name facade for codex_protocol::user_input::TextElement::placeholder.
pub fn (element &TextElement) placeholder(text &string) ?string {
	return element.placeholder_text(text)
}
