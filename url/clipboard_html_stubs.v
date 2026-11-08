module url

// STUB: url::Url::scheme borrows the parsed scheme; the URL owner outlives it.
pub fn (value &Url) scheme() &string {
	return &value.scheme
}

// STUB: url::Url::host_str. V cannot return a borrowed string slice; return an
// owned host copied from the borrowed URL, excluding a separately stored port.
pub fn (value &Url) host_str() ?string {
	if !value.authority || value.host.len == 0 {
		return none
	}
	if value.host.starts_with('[') {
		end := value.host.index(']') or { return none }
		return value.host[..end + 1].clone()
	}
	end := value.host.index(':') or { value.host.len }
	return value.host[..end].clone()
}
