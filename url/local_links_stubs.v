module url

import strings

// STUB: url::Position's currently observed URL slicing boundary.
pub enum Position {
	after_path
}

// STUB: Index<RangeTo<Position>> from url::Url. V has no borrowed substring
// return; this copies the canonical URL prefix ending immediately after its path.
pub fn (value &Url) prefix(position Position) string {
	match position {
		.after_path {
			mut out := strings.new_builder(value.scheme.len + value.host.len + value.path.len + 3)
			out.write_string(value.scheme)
			out.write_u8(`:`)
			if value.authority {
				out.write_string('//')
				if value.username.len > 0 || value.password.len > 0 {
					out.write_string(value.username)
					if value.password.len > 0 {
						out.write_u8(`:`)
						out.write_string(value.password)
					}
					out.write_u8(`@`)
				}
				out.write_string(value.host)
			}
			out.write_string(value.path)
			return out.str()
		}
	}
}

// STUB: url::Url::fragment returns the existing Copy-equivalent Option<&str>
// wrapper, keeping the fragment owned by and borrowed from the original URL.
pub fn (value &Url) fragment() BorrowedString {
	return BorrowedString{ has_value: value.has_fragment, value: &value.fragment }
}
