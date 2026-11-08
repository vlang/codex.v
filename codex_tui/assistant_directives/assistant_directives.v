// Parse structured annotations embedded in assistant-authored Markdown.
//
// For example, `::git-create-pr{cwd="/repo" isDraft=true}` becomes the name
// `git-create-pr` and the attributes `cwd` = `/repo` and `isDraft` = `true`.
// A review annotation such as `::code-comment{body="Keep \"x}\" literal."}`
// can contain quotes and braces within its quoted value. Consumers choose
// the quote-escaping rules and interpret the attributes; this module also
// retains the exact directive source, excluding any trailing Markdown.
// Scanners can share a byte-work budget across unsuccessful parse attempts.
module assistant_directives

// An assistant annotation and its complete, unmodified source representation.
// V has no borrowed string-slice or Cow string return: names, keys, attribute values,
// and raw source become owned strings copied from the borrowed input on success.
// Attributes are inserted in sorted key order, preserving BTreeMap iteration order.
pub struct AssistantDirective {
pub:
	name       string
	attributes map[string]string
	raw        string
}

// Git receipts preserve backslashes; review comments allow escaped quote delimiters.
pub enum QuoteEscaping {
	literal
	backslash
}

// V cannot safely pass a mutable scalar alias, so a one-field wrapper retains
// the caller-owned Rust &mut usize budget without unsafe pointer arithmetic.
pub struct ScanBudget {
pub mut:
	remaining usize
}

// Parse one inline, leaf, or container marker from the beginning of `source`.
pub fn parse_assistant_directive(source &string, escaping QuoteEscaping) ?AssistantDirective {
	mut remaining := ScanBudget{ remaining: ~usize(0) }
	return parse_assistant_directive_with_budget(source, escaping, mut remaining)
}

// Parse with a shared byte-scanning budget for callers that retry at multiple offsets.
//
// Charge inspected source, not the whole supplied suffix. A scan may finish its current token
// before exhausting the budget; subsequent attempts return immediately. This bounds repeated
// malformed candidates without imposing a fixed size or count limit on valid directives.
pub fn parse_assistant_directive_with_budget(source &string, escaping QuoteEscaping, mut remaining ScanBudget) ?AssistantDirective {
	spend_scan_budget(mut remaining, /*scanned*/
		1) or { return none }
	// `::git-create-pr{...}` starts with a one-to-three-colon marker and a name;
	// require `{` immediately after the name so `::git-create-pr prose` is not parsed.
	mut position := 0
	for position < source.len && (*source)[position] == `:` {
		position++
	}
	spend_scan_budget(mut remaining, usize(position)) or { return none }
	if position < 1 || position > 3 {
		return none
	}
	name_start := position
	for position < source.len && is_name_byte((*source)[position]) {
		position++
	}
	spend_scan_budget(mut remaining, usize(position - name_start + 1)) or { return none }
	name_end := position
	if position >= source.len || (*source)[position] != `{` {
		return none
	}
	position++
	if name_start == name_end || !(*source)[name_start].is_letter() {
		return none
	}

	mut attributes := map[string]string{}
	for {
		position = trim_attribute_space(source, position, mut remaining) or { return none }
		if position < source.len && (*source)[position] == `}` {
			// In `::git-push{cwd="/repo"} done`, retain the directive but not ` done`.
			mut keys := attributes.keys()
			keys.sort()
			mut ordered_attributes := map[string]string{}
			// V maps offer no safe per-entry move into a reordered map. Copy each
			// owned value here so sorted iteration does not share temporary storage.
			for key in keys {
				ordered_attributes[key] = attributes[key].clone()
			}
			return AssistantDirective{
				name:       (*source)[name_start..name_end].clone()
				attributes: ordered_attributes
				raw:        (*source)[..position + 1].clone()
			}
		}
		// For `cwd = "/repo" isDraft=true}`, split off `cwd` and leave the next
		// attribute for the next iteration after consuming this value.
		key_start := position
		for position < source.len && is_name_byte((*source)[position]) {
			position++
		}
		spend_scan_budget(mut remaining, usize(position - key_start + 1)) or { return none }
		key := (*source)[key_start..position].clone()
		// Reject malformed keys and duplicates before scanning a potentially long value.
		if key.len == 0 || key in attributes {
			return none
		}
		position = trim_attribute_space(source, position, mut remaining) or { return none }
		if position >= source.len || (*source)[position] != `=` {
			return none
		}
		position = trim_attribute_space(source, position + 1, mut remaining) or { return none }
		mut value := ''
		if position < source.len && (*source)[position] in [`"`, `'`] {
			delimiter := (*source)[position]
			// In `body="Keep \"x}\" literal."`, only the matching unescaped quote
			// ends the value, not the embedded `}`. Single-quoted values work too.
			position++
			quoted_start := position
			mut end := -1
			for position < source.len {
				character := (*source)[position]
				// Rust char_indices advances one Unicode scalar and charges its UTF-8 width.
				character_width := if character < 0x80 {
					1
				} else if character < 0xe0 {
					2
				} else if character < 0xf0 {
					3
				} else {
					4
				}
				spend_scan_budget(mut remaining, usize(character_width)) or { return none }
				if character == delimiter {
					end = position
					break
				}
				if character in [`\n`, `\r`] {
					return none
				}
				if character == `\\` && escaping == .backslash && position + 1 < source.len && (*source)[position + 1] == delimiter {
					// Backslash mode consumes `\"` as a literal quote. Literal
					// mode instead lets the quote close `cwd="/repo\"`.
					position++
					spend_scan_budget(mut remaining, /*scanned*/
						1) or { return none }
				}
				position += character_width
			}
			if end < 0 {
				return none
			}
			quoted_value := (*source)[quoted_start..end]
			position = end + 1
			escaped := '\\' + delimiter.ascii_str()
			value = if escaping == .backslash && quoted_value.contains(escaped) {
				quoted_value.replace(escaped, delimiter.ascii_str())
			} else {
				quoted_value.clone()
			}
		} else {
			// Unquoted `isDraft=true` ends at whitespace or `}`, not at a quote.
			value_start := position
			for position < source.len && (*source)[position] !in [` `, `\t`, `}`, `\n`, `\r`] {
				position++
			}
			spend_scan_budget(mut remaining, usize(position - value_start + 1)) or { return none }
			if position == value_start {
				return none
			}
			value = (*source)[value_start..position].clone()
		}
		attributes[key] = value
	}
	return none
}

// An offset into the borrowed source represents Rust's borrowed suffix return,
// avoiding allocation of an unread suffix for each whitespace trim.
fn trim_attribute_space(source &string, start int, mut remaining ScanBudget) ?int {
	mut position := start
	for position < source.len && (*source)[position] in [` `, `\t`] {
		position++
	}
	spend_scan_budget(mut remaining, usize(position - start + 1)) or { return none }
	return position
}

fn spend_scan_budget(mut remaining ScanBudget, scanned usize) ? {
	available := remaining.remaining
	remaining.remaining = if remaining.remaining >= scanned {
		remaining.remaining - scanned
	} else {
		0
	}
	if scanned > available {
		return none
	}
}

fn is_name_byte(byte u8) bool {
	return byte.is_alnum() || byte in [`_`, `-`]
}
