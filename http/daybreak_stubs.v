module http

// STUB: http::StatusCode's observed Copy value from reqwest::Response::status.
pub struct StatusCode {
	value int
}

// STUB: checked status construction belongs to the HTTP response transport.
pub fn StatusCode.from_response(value int) StatusCode {
	return StatusCode{ value: value }
}

// STUB: http::StatusCode::is_success accepts the complete 200..300 range.
pub fn (status StatusCode) is_success() bool {
	return status.value >= 200 && status.value < 300
}
