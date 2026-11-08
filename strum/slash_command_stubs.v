module strum

// STUB: strum::ParseError discriminants observed by SlashCommand's derived EnumString parser.
pub enum ParseErrorKind {
	variant_not_found
}

// STUB: strum::ParseError. V represents the Rust error enum as a tagged IError implementation.
pub struct ParseError {
pub:
	kind ParseErrorKind
}

// STUB: strum::ParseError's Display implementation for its VariantNotFound case.
pub fn (err ParseError) msg() string {
	return 'Matching variant not found'
}

// STUB: V IError's required code; strum::ParseError has no numeric error code.
pub fn (err ParseError) code() int {
	return 0
}
