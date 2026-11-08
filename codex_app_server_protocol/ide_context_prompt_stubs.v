module codex_app_server_protocol

// STUB: app-server-protocol/src/protocol/v2/turn.rs::TextElement::placeholder
// returns Option<&str>. V cannot return a borrowed string slice or safely borrow
// an owning optional string directly; this wrapper retains the element owner.
pub struct BorrowedTextElementPlaceholder {
	element &TextElement
}

// STUB: TextElement::placeholder borrows the element without copying its text.
pub fn (element &TextElement) placeholder() BorrowedTextElementPlaceholder {
	return BorrowedTextElementPlaceholder{ element: element }
}

// STUB: Option<&str>::map(str::to_string) at the IDE prompt call site. Only this
// conversion produces an owned string, matching the source's allocation boundary.
pub fn (placeholder &BorrowedTextElementPlaceholder) to_owned() ?string {
	if value := placeholder.element.placeholder {
		return value.clone()
	}
	return none
}
