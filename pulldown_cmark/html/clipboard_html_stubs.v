// Copyright 2015 Google Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

module html

import pulldown_cmark
import strings

// STUB: pulldown-cmark::html::push_html consumes typed events and appends HTML
// to its mutable String. V's String cannot be a mutable argument, so a mutable
// strings.Builder preserves appending to the caller's buffer. The generic
// iterator replaces Rust's Iterator trait.
pub fn push_html[I](mut output strings.Builder, mut events I) {
	mut writer := ClipboardHtmlWriter{ output: &output }
	for {
		event := events.next() or { break }
		match event.kind {
			.start {
				if event.tag.kind == .image {
					writer.write_literal('<img src="')
					writer.write_href(event.tag.dest_url.as_str())
					writer.write_literal('" alt="')
					mut depth := 0
					for {
						raw := events.next() or { break }
						match raw.kind {
							.start { depth++ }
							.end {
								if depth == 0 {
									break
								}
								depth--
							}
							.text, .code, .inline_html {
								writer.write_escaped(raw.text.as_str(), true)
							}
							.soft_break, .hard_break, .rule { writer.write_literal(' ') }
							.footnote_reference {
								writer.write_literal('[${writer.footnote_number(raw.text.as_str())}]')
							}
							.task_list_marker {
								writer.write_literal(if raw.checked { '[x]' } else { '[ ]' })
							}
							.html {}
						}
					}
					if event.tag.title.as_str().len > 0 {
						writer.write_literal('" title="')
						writer.write_escaped(event.tag.title.as_str(), true)
					}
					writer.write_literal('" />')
				} else {
					writer.start_tag(&event.tag)
				}
			}
			.end { writer.end_tag(event.tag_end) }
			.text {
				if !writer.in_non_writing_block { writer.write_escaped(event.text.as_str(), false) }
			}
			.code {
				writer.write_literal('<code>')
				writer.write_escaped(event.text.as_str(), false)
				writer.write_literal('</code>')
			}
			.html, .inline_html { writer.write(event.text.as_str()) }
			.soft_break { writer.write_literal('\n') }
			.hard_break { writer.write_literal('<br />\n') }
			.rule { writer.block_start('<hr />\n') }
			.footnote_reference {
				writer.write_literal('<sup class="footnote-reference"><a href="#')
				writer.write_escaped(event.text.as_str(), true)
				writer.write_literal('">${writer.footnote_number(event.text.as_str())}</a></sup>')
			}
			.task_list_marker {
				writer.write_literal(if event.checked {
					'<input disabled="" type="checkbox" checked=""/>\n'
				} else {
					'<input disabled="" type="checkbox"/>\n'
				})
			}
		}
	}
}

// STUB: pulldown-cmark HTML writer state preserves newlines, table alignments,
// footnote ordering, and non-writing metadata blocks.
struct ClipboardHtmlWriter {
mut:
	output               &strings.Builder = unsafe { nil }
	end_newline          bool             = true
	in_non_writing_block bool
	table_head           bool = true
	alignments           []pulldown_cmark.Alignment
	cell_index           int
	numbers              map[string]int
}

// STUB: pulldown-cmark HtmlWriter::write tracks whether the last write ended a line.
fn (mut writer ClipboardHtmlWriter) write(text &string) {
	writer.output.write_string(*text)
	if text.len > 0 {
		writer.end_newline = text.ends_with('\n')
	}
}

// STUB: V adapter for temporary owned HTML snippets, immediately borrowed by write.
fn (mut writer ClipboardHtmlWriter) write_literal(text string) {
	writer.write(&text)
}

// STUB: block starts get exactly one preceding newline when required by pulldown-cmark.
fn (mut writer ClipboardHtmlWriter) block_start(text string) {
	if !writer.end_newline { writer.write_literal('\n') }
	writer.write(&text)
}

// STUB: pulldown-cmark escape_html/escape_html_body_text differ only in quotes.
fn (mut writer ClipboardHtmlWriter) write_escaped(text &string, attribute bool) {
	for byte in *text {
		match byte {
			`&` { writer.output.write_string('&amp;') }
			`<` { writer.output.write_string('&lt;') }
			`>` { writer.output.write_string('&gt;') }
			`"` {
				if attribute {
					writer.output.write_string('&quot;')
				} else {
					writer.output.write_u8(byte)
				}
			}
			`'` {
				if attribute {
					writer.output.write_string('&#39;')
				} else {
					writer.output.write_u8(byte)
				}
			}
			else { writer.output.write_u8(byte) }
		}
	}
	writer.end_newline = text.ends_with('\n')
}

// STUB: pulldown-cmark href escaping preserves URI punctuation and percent
// encodes other bytes; ampersands/apostrophes are escaped for an HTML attribute.
fn (mut writer ClipboardHtmlWriter) write_href(text &string) {
	for byte in *text {
		if byte == `&` {
			writer.output.write_string('&amp;')
		} else if byte == `'` {
			writer.output.write_string('&#x27;')
		} else if (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0` && byte <= `9`) || byte in [
			`!`,
			`#`,
			`$`,
			`%`,
			`(`,
			`)`,
			`*`,
			`+`,
			`,`,
			`-`,
			`.`,
			`/`,
			`:`,
			`;`,
			`=`,
			`?`,
			`@`,
			`^`,
			`_`,
			`~`,
		] {
			writer.output.write_u8(byte)
		} else {
			writer.output.write_string('%${byte:02X}')
		}
	}
	writer.end_newline = text.ends_with('\n')
}

// STUB: HTML footnote labels assign numbers in first-seen order.
fn (mut writer ClipboardHtmlWriter) footnote_number(name &string) int {
	if number := writer.numbers[*name] {
		return number
	}
	number := writer.numbers.len + 1
	writer.numbers[name.clone()] = number
	return number
}

// STUB: pulldown-cmark HtmlWriter::start_tag preserves tag payloads and ordering.
fn (mut writer ClipboardHtmlWriter) start_tag(tag &pulldown_cmark.Tag) {
	match tag.kind {
		.html_block {}
		.paragraph { writer.block_start('<p>') }
		.heading {
			writer.block_start('<h${int(tag.level)}')
			if tag.id.present {
				writer.write_literal(' id="')
				writer.write_escaped(tag.id.value.as_str(), true)
				writer.write_literal('"')
			}
			if tag.classes.len > 0 {
				writer.write_literal(' class="')
				for index in 0 .. tag.classes.len {
					if index > 0 { writer.write_literal(' ') }
					writer.write_escaped(tag.classes[index].as_str(), true)
				}
				writer.write_literal('"')
			}
			for index in 0 .. tag.attrs.len {
				attribute := &tag.attrs[index]
				writer.write_literal(' ')
				writer.write_escaped(attribute.name.as_str(), true)
				writer.write_literal('="')
				if attribute.value.present {
					writer.write_escaped(attribute.value.value.as_str(), true)
				}
				writer.write_literal('"')
			}
			writer.write_literal('>')
		}
		.table {
			writer.alignments = tag.alignments.clone()
			writer.write_literal('<table>')
		}
		.table_head {
			writer.table_head = true
			writer.cell_index = 0
			writer.write_literal('<thead><tr>')
		}
		.table_row {
			writer.cell_index = 0
			writer.write_literal('<tr>')
		}
		.table_cell {
			writer.write_literal(if writer.table_head { '<th' } else { '<td' })
			alignment := if writer.cell_index < writer.alignments.len {
				writer.alignments[writer.cell_index]
			} else {
				pulldown_cmark.Alignment.none
			}
			writer.write_literal(match alignment {
				.left { ' style="text-align: left">' }
				.center { ' style="text-align: center">' }
				.right { ' style="text-align: right">' }
				.none { '>' }
			})
		}
		.block_quote { writer.block_start('<blockquote>\n') }
		.code_block {
			writer.block_start('<pre><code')
			if tag.code_block.kind == .fenced {
				info := tag.code_block.language.as_str()
				end := info.index(' ') or { info.len }
				language := (*info)[..end]
				if language.len > 0 {
					writer.write_literal(' class="language-')
					writer.write_escaped(&language, true)
					writer.write_literal('"')
				}
			}
			writer.write_literal('>')
		}
		.list {
			if start := tag.list_start {
				writer.block_start(if start == 1 { '<ol>\n' } else { '<ol start="${start}">\n' })
			} else {
				writer.block_start('<ul>\n')
			}
		}
		.item { writer.block_start('<li>') }
		.emphasis { writer.write_literal('<em>') }
		.strong { writer.write_literal('<strong>') }
		.strikethrough { writer.write_literal('<del>') }
		.link {
			writer.write_literal('<a href="')
			if tag.link_type == .email { writer.write_literal('mailto:') }
			writer.write_href(tag.dest_url.as_str())
			if tag.title.as_str().len > 0 {
				writer.write_literal('" title="')
				writer.write_escaped(tag.title.as_str(), true)
			}
			writer.write_literal('">')
		}
		.image { panic('image start must consume its alt events in push_html') }
		.footnote_definition {
			writer.block_start('<div class="footnote-definition" id="')
			writer.write_escaped(tag.footnote_label.as_str(), true)
			writer.write_literal('"><sup class="footnote-definition-label">${writer.footnote_number(tag.footnote_label.as_str())}</sup>')
		}
		.metadata_block { writer.in_non_writing_block = true }
	}
}

// STUB: pulldown-cmark HtmlWriter::end_tag retains ordered-list and heading data.
fn (mut writer ClipboardHtmlWriter) end_tag(tag pulldown_cmark.TagEnd) {
	match tag.kind {
		.html_block, .image {}
		.paragraph { writer.write_literal('</p>\n') }
		.heading { writer.write_literal('</h${int(tag.level)}>\n') }
		.table { writer.write_literal('</tbody></table>\n') }
		.table_head {
			writer.write_literal('</tr></thead><tbody>\n')
			writer.table_head = false
		}
		.table_row { writer.write_literal('</tr>\n') }
		.table_cell {
			writer.write_literal(if writer.table_head { '</th>' } else { '</td>' })
			writer.cell_index++
		}
		.block_quote { writer.write_literal('</blockquote>\n') }
		.code_block { writer.write_literal('</code></pre>\n') }
		.list { writer.write_literal(if tag.ordered { '</ol>\n' } else { '</ul>\n' }) }
		.item { writer.write_literal('</li>\n') }
		.emphasis { writer.write_literal('</em>') }
		.strong { writer.write_literal('</strong>') }
		.strikethrough { writer.write_literal('</del>') }
		.link { writer.write_literal('</a>') }
		.footnote_definition { writer.write_literal('</div>\n') }
		.metadata_block { writer.in_non_writing_block = false }
	}
}
