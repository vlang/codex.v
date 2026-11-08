module http

// STUB: http::HeaderValue owns the validated HTTP header bytes.
pub struct HeaderValue {
pub:
	value string
}

// STUB: http::HeaderValue::from_static borrows immutable source header text.
pub fn HeaderValue.from_static(value &string) HeaderValue {
	return HeaderValue{ value: value.clone() }
}

// STUB: http::HeaderMap's observed owned header entries. The complete HTTP
// header collection and login's environment-dependent defaults are untranslated.
pub struct HeaderMap {
pub:
	values             map[string]string
	unavailable_reason string
}

// STUB: HeaderMap clone at the external fixture's owned result boundary.
pub fn (headers &HeaderMap) clone() HeaderMap {
	return HeaderMap{ values: headers.values.clone(), unavailable_reason: headers.unavailable_reason.clone() }
}
