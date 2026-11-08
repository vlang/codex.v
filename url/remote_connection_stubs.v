module url

import strings

// STUB: url::Url from url 2.5.8. This source-shaped boundary implements absolute
// URL parsing and the component setters used by remote_connection. International
// special-scheme domain names require the untranslated IDNA/UTS #46 dependency;
// they fail explicitly here rather than exposing an incorrectly normalized URL.
pub struct Url {
mut:
	scheme       string
	authority    bool
	host         string
	username     string
	password     string
	path         string
	opaque       bool
	has_query    bool
	query        string
	has_fragment bool
	fragment     string
}

// STUB: safe Copy-equivalent representation of url's Option<&str> arguments.
pub struct BorrowedString {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

// STUB: url::Url::parse's absolute URL boundary. Relative URLs have no base and
// fail; special schemes normalize hosts, ports, separators, and dot segments.
pub fn Url.parse(raw &string) !Url {
	mut start := 0
	mut end := raw.len
	for start < end && (*raw)[start] <= 0x20 {
		start++
	}
	for end > start && (*raw)[end - 1] <= 0x20 {
		end--
	}
	mut cleaned := strings.new_builder(end - start)
	for index in start .. end {
		b := (*raw)[index]
		if b !in [`\t`, `\r`, `\n`] { cleaned.write_u8(b) }
	}
	input := cleaned.str()
	colon := input.index(':') or { return error('relative URL without a base') }
	if colon == 0 || !url_ascii_letter(input[0]) {
		return error('relative URL without a base')
	}
	for b in input[..colon] {
		if !url_ascii_letter(b) && !(b >= `0` && b <= `9`) && b !in [`+`, `-`, `.`] {
			return error('relative URL without a base')
		}
	}
	scheme := input[..colon].to_lower_ascii()
	special := scheme in ['http', 'https', 'ws', 'wss', 'ftp', 'file']
	fragment_start := input.index_after('#', colon + 1) or { input.len }
	query_start := input.index_after('?', colon + 1) or { input.len }
	content_end := if query_start < fragment_start { query_start } else { fragment_start }
	content := input[colon + 1..content_end]
	mut result := Url{
		scheme:       scheme
		has_query:    query_start < fragment_start
		query:        if query_start < fragment_start {
			url_encode(&input[query_start + 1..fragment_start], .query, special)
		} else {
			''.clone()
		}
		has_fragment: fragment_start < input.len
		fragment:     if fragment_start < input.len {
			url_encode(&input[fragment_start + 1..], .fragment, false)
		} else {
			''.clone()
		}
	}
	if !special && !content.starts_with('/') {
		result.opaque = true
		result.path = url_encode(&content, .opaque, false)
		return result
	}
	mut authority_start := 0
	if special && scheme != 'file' {
		for authority_start < content.len && content[authority_start] in [`/`, `\\`] {
			authority_start++
		}
		result.authority = true
	} else if content.starts_with('//') || (scheme == 'file' && content.len >= 2 && content[0] in [
		`/`,
		`\\`,
	] && content[1] in [`/`, `\\`]) {
		authority_start = 2
		result.authority = true
	}
	if result.authority {
		mut authority_end := authority_start
		for authority_end < content.len && content[authority_end] != `/` && !(special && content[authority_end] == `\\`) {
			authority_end++
		}
		authority := content[authority_start..authority_end]
		// STUB: url's file-host state moves drive-shaped authorities into the
		// path rather than treating their colon as a forbidden file URL port.
		if scheme == 'file' && authority.len == 2 && url_ascii_letter(authority[0])
			&& authority[1] in [`:`, `|`] {
			drive_path := '/${content[authority_start..]}'
			result.path = url_path(&drive_path, true, true)
			return result
		}
		mut host_start := 0
		at := authority.last_index_u8(`@`)
		if at >= 0 {
			if scheme == 'file' {
				return error('invalid domain character')
			}
			userinfo := authority[..at]
			password_separator := userinfo.index(':') or { userinfo.len }
			result.username = url_encode(&userinfo[..password_separator], .userinfo, false)
			if password_separator < userinfo.len {
				result.password = url_encode(&userinfo[password_separator + 1..], .userinfo, false)
			}
			host_start = at + 1
		}
		host_and_port := authority[host_start..]
		mut port_start := host_and_port.len
		if host_and_port.starts_with('[') {
			close := host_and_port.index(']') or { return error('invalid IPv6 address') }
			if close + 1 < host_and_port.len {
				if host_and_port[close + 1] != `:` {
					return error('invalid IPv6 address')
				}
				port_start = close + 1
			}
		} else {
			port_start = host_and_port.index(':') or { host_and_port.len }
		}
		raw_host := host_and_port[..port_start]
		result.host = url_host(&raw_host, special, scheme == 'file')!
		if scheme == 'file' && result.host == 'localhost' {
			result.host = ''.clone()
		}
		if port_start < host_and_port.len {
			if scheme == 'file' {
				return error('invalid domain character')
			}
			raw_port := host_and_port[port_start + 1..]
			if raw_port.len > 0 {
				mut port := u32(0)
				for b in raw_port {
					if b < `0` || b > `9` {
						return error('invalid port number')
					}
					port = port * 10 + u32(b - `0`)
					if port > 65535 {
						return error('invalid port number')
					}
				}
				default_port := match scheme {
					'http', 'ws' { 80 }
					'https', 'wss' { 443 }
					'ftp' { 21 }
					else { -1 }
				}
				if int(port) != default_port {
					result.host += ':${port}'
				}
			}
		}
		raw_path := content[authority_end..]
		result.path = url_path(&raw_path, special, scheme == 'file')
		// STUB: a normalized first Windows drive segment clears a file host.
		if scheme == 'file' && result.path.len >= 3 && result.path[0] == `/`
			&& url_ascii_letter(result.path[1]) && result.path[2] == `:`
			&& (result.path.len == 3 || result.path[3] == `/`) {
			result.host = ''.clone()
		}
	} else {
		result.path = url_path(&content, special, scheme == 'file')
		if scheme == 'file' {
			result.authority = true
		}
	}
	return result
}

// STUB: url::Url::set_username preserves the Result<(), ()> failure boundary.
pub fn (mut value Url) set_username(username &string) ! {
	if !value.authority || value.host.len == 0 || value.scheme == 'file' {
		return error('URL cannot have credentials')
	}
	value.username = url_encode(username, .userinfo, false)
}

// STUB: url::Url::set_password preserves a shared optional string and errors.
pub fn (mut value Url) set_password(password BorrowedString) ! {
	if !value.authority || value.host.len == 0 || value.scheme == 'file' {
		return error('URL cannot have credentials')
	}
	value.password = if password.has_value {
		url_encode(password.value, .userinfo, false)
	} else {
		''.clone()
	}
}

// STUB: url::Url::set_query stores the owned encoding of the borrowed component.
pub fn (mut value Url) set_query(query BorrowedString) {
	value.has_query = query.has_value
	value.query = if query.has_value {
		url_encode(query.value, .query, value.scheme in ['http', 'https', 'ws', 'wss', 'ftp', 'file'])
	} else {
		''.clone()
	}
}

// STUB: url::Url::set_fragment stores the owned encoding of the borrowed component.
pub fn (mut value Url) set_fragment(fragment BorrowedString) {
	value.has_fragment = fragment.has_value
	value.fragment = if fragment.has_value {
		url_encode(fragment.value, .fragment, false)
	} else {
		''.clone()
	}
}

// STUB: Url's Display/ToString owned serialization boundary from url 2.5.8.
pub fn (value &Url) to_string() string {
	mut out := strings.new_builder(value.scheme.len + value.host.len + value.path.len + 16)
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
	if value.has_query {
		out.write_u8(`?`)
		out.write_string(value.query)
	}
	if value.has_fragment {
		out.write_u8(`#`)
		out.write_string(value.fragment)
	}
	return out.str()
}

// STUB: URL parser scheme ASCII-letter predicate from url 2.5.8.
fn url_ascii_letter(b u8) bool {
	return (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`)
}

// STUB: WHATWG component encode sets used by url's parser and setters.
enum UrlEncodeSet {
	opaque
	path
	userinfo
	query
	fragment
}

// STUB: UTF-8 percent encoding preserves literal percent escapes as url does.
fn url_encode(input &string, set UrlEncodeSet, special bool) string {
	mut out := strings.new_builder(input.len)
	for b in *input {
		encode := b <= 0x1f || b >= 0x7f || (set != .opaque && b in [` `, `"`, `<`, `>`]) || (set in [
			.path,
			.userinfo,
			.fragment,
		] && b == 0x60) || (set in [.path, .userinfo] && b in [`#`, `?`, `{`, `}`]) || (set == .userinfo && b in [
			`/`,
			`:`,
			`;`,
			`=`,
			`@`,
			`[`,
			`\\`,
			`]`,
			`^`,
			`|`,
		]) || (set == .query && (b == `#` || (special && b == `'`)))
		if encode { out.write_string('%${b:02X}') } else { out.write_u8(b) }
	}
	return out.str()
}

// STUB: hierarchy path normalization and percent encoding from url's parser.
fn url_path(raw &string, special bool, file bool) string {
	normalized := if special { raw.replace('\\', '/') } else { raw.clone() }
	if normalized.len == 0 {
		return if special { '/'.clone() } else { ''.clone() }
	}
	mut segments := []string{}
	pieces := normalized.split('/')
	for index in 0 .. pieces.len {
		piece := &pieces[index]
		lower := piece.to_lower_ascii()
		if lower in ['.', '%2e'] {
			if index == pieces.len - 1 { segments << ''.clone() }
		} else if lower in ['..', '.%2e', '%2e.', '%2e%2e'] {
			// STUB: url's shorten_path cannot cross a Windows drive root.
			root_drive := file && segments.len == 2 && segments[1].len == 2
				&& url_ascii_letter(segments[1][0]) && segments[1][1] == `:`
			if segments.len > 1 && !root_drive { segments.delete_last() }
			if index == pieces.len - 1 { segments << ''.clone() }
		} else {
			if file && index == 1 && piece.len == 2 && url_ascii_letter((*piece)[0]) && (*piece)[1] == `|` {
				segments << '${(*piece)[0].ascii_str()}:'
			} else {
				segments << url_encode(piece, .path, special)
			}
		}
	}
	joined := segments.join('/')
	return if special && !joined.starts_with('/') { '/${joined}' } else { joined }
}

// STUB: ASCII host normalization, numeric IPv4 forms, and validated IPv6 from
// url::Host. Full IDNA/UTS #46 is deliberately left to its untranslated owner.
fn url_host(raw &string, special bool, file bool) !string {
	if raw.starts_with('[') {
		if !raw.ends_with(']') {
			return error('invalid IPv6 address')
		}
		inner := (*raw)[1..raw.len - 1]
		canonical := url_ipv6(&inner)!
		return '[${canonical}]'
	}
	mut decoded := strings.new_builder(raw.len)
	mut index := 0
	for index < raw.len {
		if special && (*raw)[index] == `%` && index + 2 < raw.len {
			a := url_hex((*raw)[index + 1])
			b := url_hex((*raw)[index + 2])
			if a >= 0 && b >= 0 {
				decoded.write_u8(u8(a * 16 + b))
				index += 3
				continue
			}
		}
		decoded.write_u8((*raw)[index])
		index++
	}
	host := decoded.str()
	for host_index in 0 .. host.len {
		b := host[host_index]
		if b <= 0x20 || b == 0x7f || b in [`#`, `/`, `:`, `<`, `>`, `?`, `@`, `[`, `\\`, `]`, `^`,
			`|`] || (special && b == `%`) {
			return error('invalid domain character')
		}
		if special && b >= 0x80 {
			return error('international domain names require untranslated IDNA support')
		}
	}
	if special && host.len == 0 && !file {
		return error('empty host')
	}
	if !special {
		return url_encode(&host, .opaque, false)
	}
	lower := host.to_lower_ascii()
	parts := lower.split('.')
	// URL removes one final empty component, preserving multiple trailing dots.
	count := if lower.ends_with('.') { parts.len - 1 } else { parts.len }
	if count > 0 {
		last := &parts[count - 1]
		mut decimal := last.len > 0
		for b in *last {
			if b < `0` || b > `9` {
				decimal = false
			}
		}
		mut hexadecimal := last.starts_with('0x')
		if hexadecimal {
			for hex_index in 2 .. last.len {
				if url_hex((*last)[hex_index]) < 0 {
					hexadecimal = false
				}
			}
		}
		if decimal || hexadecimal {
			return url_ipv4(&parts, count)!
		}
	}
	return lower
}

// STUB: url 2.5.8 host.rs::parse_ipv6addr, including compressed addresses and
// strict decimal IPv4 tails. V's net parser currently rejects valid full-form
// addresses under ownership; parse the borrowed bytes without moving slices.
fn url_ipv6(input &string) !string {
	length := input.len
	if length < 2 {
		return error('invalid IPv6 address')
	}
	mut pieces := [8]u16{}
	mut piece_pointer := 0
	mut compress_pointer := -1
	mut position := 0
	mut is_ipv4 := false
	if (*input)[0] == `:` {
		if (*input)[1] != `:` {
			return error('invalid IPv6 address')
		}
		position = 2
		piece_pointer = 1
		compress_pointer = 1
	}
	for position < length {
		if piece_pointer == 8 {
			return error('invalid IPv6 address')
		}
		if (*input)[position] == `:` {
			if compress_pointer != -1 {
				return error('invalid IPv6 address')
			}
			position++
			piece_pointer++
			compress_pointer = piece_pointer
			continue
		}
		start := position
		end := if start + 4 < length { start + 4 } else { length }
		mut value := u16(0)
		for position < end {
			digit := url_hex((*input)[position])
			if digit < 0 {
				break
			}
			value = value * 16 + u16(digit)
			position++
		}
		if position < length {
			separator := (*input)[position]
			if separator == `.` {
				if position == start || piece_pointer > 6 {
					return error('invalid IPv6 address')
				}
				position = start
				is_ipv4 = true
			} else if separator == `:` {
				position++
				if position == length {
					return error('invalid IPv6 address')
				}
			} else {
				return error('invalid IPv6 address')
			}
		}
		if is_ipv4 {
			break
		}
		pieces[piece_pointer] = value
		piece_pointer++
	}
	if is_ipv4 {
		mut numbers_seen := 0
		for position < length {
			if numbers_seen > 0 {
				if numbers_seen < 4 && (*input)[position] == `.` {
					position++
				} else {
					return error('invalid IPv6 address')
				}
			}
			mut ipv4_piece := -1
			for position < length && (*input)[position] >= `0` && (*input)[position] <= `9` {
				digit := int((*input)[position] - `0`)
				if ipv4_piece == -1 {
					ipv4_piece = digit
				} else if ipv4_piece == 0 {
					return error('invalid IPv6 address') // No leading zero.
				} else {
					ipv4_piece = ipv4_piece * 10 + digit
					if ipv4_piece > 255 {
						return error('invalid IPv6 address')
					}
				}
				position++
			}
			if ipv4_piece == -1 {
				return error('invalid IPv6 address')
			}
			pieces[piece_pointer] = pieces[piece_pointer] * 256 + u16(ipv4_piece)
			numbers_seen++
			if numbers_seen == 2 || numbers_seen == 4 { piece_pointer++ }
		}
		if numbers_seen != 4 {
			return error('invalid IPv6 address')
		}
	}
	if compress_pointer != -1 {
		mut swaps := piece_pointer - compress_pointer
		piece_pointer = 7
		for swaps > 0 {
			other := compress_pointer + swaps - 1
			temporary := pieces[piece_pointer]
			pieces[piece_pointer] = pieces[other]
			pieces[other] = temporary
			swaps--
			piece_pointer--
		}
	} else if piece_pointer != 8 {
		return error('invalid IPv6 address')
	}
	return url_ipv6_display(pieces)
}

// STUB: URL's IPv6 serializer compresses the first longest zero run and uses
// hexadecimal groups even for IPv4-mapped tails, as Rust's url::Host does.
fn url_ipv6_display(pieces [8]u16) string {
	mut best_start := -1
	mut best_length := 1
	mut run_start := 0
	mut run_length := 0
	for index in 0 .. 8 {
		if pieces[index] == 0 {
			if run_length == 0 {
				run_start = index
			}
			run_length++
			if run_length > best_length {
				best_start = run_start
				best_length = run_length
			}
		} else {
			run_length = 0
		}
	}
	mut output := strings.new_builder(39)
	mut index := 0
	for index < 8 {
		if index == best_start {
			output.write_string('::')
			index += best_length
			continue
		}
		if index > 0 && (best_start == -1 || index != best_start + best_length) {
			output.write_u8(`:`)
		}
		output.write_string(pieces[index].hex())
		index++
	}
	return output.str()
}

// STUB: URL parser hexadecimal digit decoding.
fn url_hex(b u8) int {
	if b >= `0` && b <= `9` {
		return int(b - `0`)
	}
	if b >= `a` && b <= `f` {
		return int(b - `a`) + 10
	}
	if b >= `A` && b <= `F` {
		return int(b - `A`) + 10
	}
	return -1
}

// STUB: url::Host's WHATWG numeric IPv4 parser, including octal and hex pieces.
fn url_ipv4(parts &[]string, count int) !string {
	if count > 4 || count == 0 {
		return error('invalid IPv4 address')
	}
	mut numbers := []u64{}
	for index in 0 .. count {
		piece := &(*parts)[index]
		if piece.len == 0 {
			return error('invalid IPv4 address')
		}
		mut start := 0
		mut radix := 10
		if piece.starts_with('0x') {
			start = 2
			radix = 16
		} else if piece.len > 1 && (*piece)[0] == `0` {
			start = 1
			radix = 8
		}
		mut value := u64(0)
		for byte_index in start .. piece.len {
			digit := url_hex((*piece)[byte_index])
			if digit < 0 || digit >= radix {
				return error('invalid IPv4 address')
			}
			value = value * u64(radix) + u64(digit)
			if value > 0xffffffff {
				return error('invalid IPv4 address')
			}
		}
		if index < count - 1 && value > 255 {
			return error('invalid IPv4 address')
		}
		numbers << value
	}
	last := numbers[numbers.len - 1]
	if last >= (u64(1) << (8 * (5 - numbers.len))) {
		return error('invalid IPv4 address')
	}
	mut address := last
	for index in 0 .. numbers.len - 1 {
		address += numbers[index] << (8 * (3 - index))
	}
	return '${(address >> 24) & 255}.${(address >> 16) & 255}.${(address >> 8) & 255}.${address & 255}'
}
