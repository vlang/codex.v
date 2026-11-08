// Copyright 2015 Nicholas Allegra (comex).
// Licensed under Apache-2.0 or MIT; see LICENSE-APACHE and LICENSE-MIT.

module shlex

import strings

// STUB: shlex 1.3.0 QuoteError's observed Nul variant; other Quoter APIs remain untranslated.
pub enum QuoteErrorKind {
	nul
}

// STUB: shlex::QuoteError as a tagged V IError, retaining the typed failure shape.
pub struct QuoteError {
pub:
	kind QuoteErrorKind
}

// STUB: shlex::QuoteError::fmt for the default quoter's Nul case.
pub fn (err QuoteError) msg() string {
	return 'cannot shell-quote string containing nul byte'
}

// STUB: V IError's required code; the Rust error has no numeric code.
pub fn (err QuoteError) code() int {
	return 0
}

// STUB: shlex::try_join's default quoter behavior, pinned to 1.3.0. A borrowed
// string array replaces the Rust iterator of &str; no argument owners are moved.
pub fn try_join(words &[]string) !string {
	mut output := strings.new_builder(0)
	for index in 0 .. words.len {
		word := &(*words)[index]
		if index > 0 {
			output.write_u8(` `)
		}
		if word.len == 0 {
			output.write_string("''")
			continue
		}
		if (*word).contains_u8(0) {
			return QuoteError{ kind: .nul }
		}
		mut start := 0
		for start < word.len {
			end, strategy := quoting_strategy(word, start)
			if strategy == 1 {
				output.write_string((*word)[start..end])
			} else if strategy == 2 {
				output.write_u8(`'`)
				output.write_string((*word)[start..end])
				output.write_u8(`'`)
			} else {
				output.write_u8(`"`)
				for byte_index in start .. end {
					character := (*word)[byte_index]
					if character in [`$`, `\u0060`, `"`, `\\`] {
						output.write_u8(`\\`)
					}
					output.write_u8(character)
				}
				output.write_u8(`"`)
			}
			start = end
		}
	}
	return output.str()
}

// STUB: shlex::bytes::quoting_strategy, including Fish backslashes and the Bash
// caret workaround. Masks select unquoted, single-quoted, then double-quoted.
fn quoting_strategy(word &string, start int) (int, int) {
	mut previous_ok := 7
	mut index := start
	if (*word)[start] == `^` {
		previous_ok = 2
		index++
	}
	for index < word.len {
		character := (*word)[index]
		mut current_ok := previous_ok
		if character >= 0x80 || !unquoted_ok(character) {
			current_ok &= ~1
		}
		if character in [`'`, `^`, `\\`] {
			current_ok &= ~2
		}
		if character in [`\u0060`, `$`, `!`, `^`] {
			current_ok &= ~4
		}
		if current_ok == 0 {
			break
		}
		previous_ok = current_ok
		index++
	}
	strategy := if previous_ok & 1 != 0 {
		1
	} else if previous_ok & 2 != 0 {
		2
	} else {
		4
	}
	return index, strategy
}

// STUB: shlex::bytes::unquoted_ok's exact ASCII whitelist.
fn unquoted_ok(character u8) bool {
	return character.is_alnum() || character in [`+`, `-`, `.`, `/`, `:`, `@`, `]`, `_`]
}

// STUB: shlex::split's POSIX lexer, pinned to 1.3.0; quotes, escaping, comments,
// newline continuation, NUL acceptance, and malformed-input None are preserved.
pub fn split(command &string) ?[]string {
	mut parts := []string{}
	mut index := 0
	for index < command.len {
		for index < command.len {
			character := (*command)[index]
			if character in [` `, `\t`, `\n`] {
				index++
			} else if character == `#` {
				for index < command.len && (*command)[index] != `\n` {
					index++
				}
			} else {
				break
			}
		}
		if index == command.len {
			break
		}
		mut word := strings.new_builder(0)
		for index < command.len {
			character := (*command)[index]
			index++
			if character in [` `, `\t`, `\n`] {
				break
			}
			if character == `\\` {
				if index == command.len {
					return none
				}
				if (*command)[index] != `\n` {
					word.write_u8((*command)[index])
				}
				index++
			} else if character == `'` {
				for index < command.len && (*command)[index] != `'` {
					word.write_u8((*command)[index])
					index++
				}
				if index == command.len {
					return none
				}
				index++
			} else if character == `"` {
				mut closed := false
				for index < command.len {
					quoted := (*command)[index]
					index++
					if quoted == `"` {
						closed = true
						break
					}
					if quoted == `\\` {
						if index == command.len {
							return none
						}
						escaped := (*command)[index]
						index++
						if escaped in [`$`, `\u0060`, `"`, `\\`] {
							word.write_u8(escaped)
						} else if escaped != `\n` {
							word.write_u8(`\\`)
							word.write_u8(escaped)
						}
					} else {
						word.write_u8(quoted)
					}
				}
				if !closed {
					return none
				}
			} else {
				word.write_u8(character)
			}
		}
		parts << word.str()
	}
	return parts
}
