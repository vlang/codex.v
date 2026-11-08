module prompt_args

fn test_rejects_missing_prefix_or_empty_name() {
	for line in ['', '/', 'name arg', ' /name arg', '\n/name', '／name', '/ ', '/\targ', '/\u3000arg'] {
		if _name, _rest, _offset := parse_slash_name(&line) {
			assert false, 'unexpected slash command in ${line}'
		}
	}
}

fn test_name_without_arguments_ends_at_original_byte_length() {
	for line in ['/name', '/部署', '/𐐀', '//'] {
		name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
		assert name == line[1..]
		assert rest == ''
		assert offset == usize(line.len)
	}
}

fn test_ascii_whitespace_separates_name_and_trims_argument_start() {
	for separator in [' ', '\t', '\n', '\r', '\v', '\f'] {
		line := '/name${separator}${separator}argument \t'
		name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
		assert name == 'name'
		assert rest == 'argument \t'
		assert offset == usize(5 + separator.len * 2)
		assert line[int(offset)..] == rest
	}
}

fn test_every_unicode_white_space_separator_and_empty_name() {
	// This is the Unicode White_Space property used by Rust char::is_whitespace.
	for separator in ['\u0009', '\u000a', '\u000b', '\u000c', '\u000d', '\u0020', '\u0085', '\u00a0',
		'\u1680', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004', '\u2005', '\u2006', '\u2007',
		'\u2008', '\u2009', '\u200a', '\u2028', '\u2029', '\u202f', '\u205f', '\u3000'] {
		line := '/部署${separator}${separator}𐐀参数'
		name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
		assert name == '部署'
		assert rest == '𐐀参数'
		assert offset == usize(7 + separator.len * 2)
		assert line[int(offset)..] == rest
		invalid := '/${separator}name'
		if _name, _rest, _offset := parse_slash_name(&invalid) {
			assert false, 'whitespace cannot start the command name'
		}
	}
}

fn test_mixed_unicode_whitespace_uses_byte_offsets() {
	line := '/部署\u0085\u00a0\u1680\u2000\u2028\u202f\u205f\u3000𐐀参数 \t'
	name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
	assert name == '部署'
	assert rest == '𐐀参数 \t'
	assert offset == usize(29)
	assert line[int(offset)..] == rest
}

fn test_only_whitespace_after_name_returns_empty_rest_at_line_end() {
	line := '/name \t\n\r\v\f\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'
	name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
	assert name == 'name'
	assert rest == ''
	assert offset == usize(line.len)
}

fn test_argument_content_keeps_newlines_and_trailing_whitespace() {
	line := '/name\n\tfirst\nsecond\u2028third\u3000 \t\n'
	name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
	assert name == 'name'
	assert rest == 'first\nsecond\u2028third\u3000 \t\n'
	assert offset == usize(7)
	assert line[int(offset)..] == rest
}

fn test_zero_width_and_bom_characters_are_not_whitespace() {
	for non_whitespace in ['\u180e', '\u200b', '\ufeff'] {
		line := '/name${non_whitespace}part ${non_whitespace}argument'
		name, rest, offset := parse_slash_name(&line) or { panic('expected a slash command') }
		assert name == 'name${non_whitespace}part'
		assert rest == '${non_whitespace}argument'
		assert offset == usize(10 + non_whitespace.len)
		assert line[int(offset)..] == rest
	}
}

fn test_borrowed_heap_owner_remains_reusable() {
	mut line := '/部署\u202f\u3000argument\n next \t'
	$if ownership ? {
		line = '/部署\u202f\u3000argument\n next \t'.to_owned()
	}
	first_name, first_rest, first_offset := parse_slash_name(&line) or {
		panic('expected a slash command')
	}
	second_name, second_rest, second_offset := parse_slash_name(&line) or {
		panic('expected the same slash command again')
	}
	assert first_name == '部署'
	assert second_name == first_name
	assert first_rest == 'argument\n next \t'
	assert second_rest == first_rest
	assert first_offset == usize(13)
	assert second_offset == first_offset
	assert line == '/部署\u202f\u3000argument\n next \t'
	assert line[int(first_offset)..] == first_rest
}
