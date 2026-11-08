module clipboard_html

import codex_tui.markdown as markdown_module
import codex_tui.terminal_hyperlinks
import pulldown_cmark

fn test_markdown_clipboard_preserves_rich_formatting() {
	markdown := '# Findings\n\nRead [the source](https://example.com/source?q=1&v=2).\n\n' +
		'- **Bold**, *italic*, ~~removed~~, and `inline <code>`\n\n' +
		'> A quoted finding.\n\n' +
		'```rust\nfn main() { println!("<hello>"); }\n```\n\n' +
		'| Item | Result |\n| --- | --- |\n| Copy | Formatted |\n'
	assert render_markdown(&markdown) == $embed_file('snapshots/markdown_clipboard_preserves_rich_formatting.html').to_string()
}

fn test_markdown_clipboard_preserves_local_link_destinations() {
	markdown := r'[parser](/repo/src/parser.rs:42)

[**Windows parser**](C:\repo\src\parser.rs:42:7)

[`relative parser`](../src/parser.rs#L42-L48)

[file URL](file:///repo/src/parser.rs#L42)

[escaped path](/repo/a&amp;b/&lt;parser&gt;.rs:42)

[Unicode path](</repo/my project/解析.rs:42>)

[![diagram](https://example.com/diagram.png)](/repo/diagram.rs:7)

[web link](https://example.com/source) and [another file](src/lib.rs:9)
'
	assert render_markdown(&markdown) == $embed_file('snapshots/markdown_clipboard_preserves_local_link_destinations.html').to_string()
}

fn test_markdown_clipboard_images_are_inert() {
	markdown := '![tracking pixel](https://example.com/pixel)\n\n' +
		'[![**Preview** & details](https://example.com/image.png)](https://example.com/page)'
	assert render_markdown(&markdown) == '<p>tracking pixel</p>\n' +
		'<p><a href="https://example.com/page"><strong>Preview</strong> &amp; details</a></p>\n'
}

fn test_markdown_clipboard_escapes_raw_html_and_rejects_unsafe_destinations() {
	markdown := '<script>alert(1)</script>\n\nHello <img src=x onerror=alert(1)>!'
	assert render_markdown(&markdown) == '&lt;script&gt;alert(1)&lt;/script&gt;\n<p>Hello &lt;img src=x onerror=alert(1)&gt;!</p>\n'
	for pair in [
		['javascript:alert(1)', 'javascript:alert(1)'],
		['JaVaScRiPt:alert(1)', 'JaVaScRiPt:alert(1)'],
		['jav&#x61;script:alert(1)', 'javascript:alert(1)'],
		['data:text/html,unsafe', 'data:text/html,unsafe'],
		['javascript:alert(&quot;&lt;&gt;&amp;&quot;)', 'javascript:alert("&lt;&gt;&amp;")'],
	] {
		input := '[link](${pair[0]}) ![image](${pair[0]})'
		assert render_markdown(&input) == '<p>link (${pair[1]}) image</p>\n'
	}
}

fn test_markdown_clipboard_unwraps_table_fences_like_the_tui() {
	table := '| Item | Result |\n| --- | --- |\n| Copy | Formatted |\n'
	fenced := '```markdown\n${table}```'
	assert render_markdown(&fenced) == render_markdown(&table)
}

fn clipboard_owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_repeated_borrowed_render_keeps_heap_input_reusable() {
	input := clipboard_owned('[**owned**](https://example.com?q=1&x=2) ![alt *em*](https://example.com/image)')
	expected := '<p><a href="https://example.com?q=1&amp;x=2"><strong>owned</strong></a> alt <em>em</em></p>\n'
	assert render_markdown(&input) == expected
	assert render_markdown(&input) == expected
	assert input.contains('![alt *em*]')
}

fn test_reference_links_autolinks_and_entities_preserve_policy() {
	input := '[good][safe] and [bad][unsafe] <https://example.com/a?q=1&v=2> <a@example.com>\n\n' +
		'[safe]: https://example.com/page "a &quot; title"\n[unsafe]: javascript:alert(1)\n'
	assert render_markdown(&input) == '<p><a href="https://example.com/page" title="a &quot; title">good</a> and bad (javascript:alert(1)) <a href="https://example.com/a?q=1&amp;v=2">https://example.com/a?q=1&amp;v=2</a> a@example.com (mailto:a@example.com)</p>\n'
	entities := '&NotEqualTilde; &#x1F600; &#0; &#xD800; &unknown;'
	assert render_markdown(&entities) == '<p>≂̸ 😀 � � &amp;unknown;</p>\n'
}

fn test_href_byte_escaping_and_escaped_entity_boundaries() {
	input := r'[literal](https://example.com/\&amp; "literal \&amp;") [IPv6](https://[::1]/a^b) [Unicode](https://example.com/解析)'
	assert render_markdown(&input) == '<p><a href="https://example.com/&amp;amp;" title="literal &amp;amp;">literal</a> <a href="https://%5B::1%5D/a^b">IPv6</a> <a href="https://example.com/%E8%A7%A3%E6%9E%90">Unicode</a></p>\n'
	numerics := r'[long](https://example.com/&#000000065;) &#000000065; &#x000000061;'
	assert render_markdown(&numerics) == '<p><a href="https://example.com/&amp;#000000065;">long</a> &amp;#000000065; &amp;#x000000061;</p>\n'
}

fn test_nested_blocks_table_alignment_and_breaks() {
	input := '3. one\n4. **two**\n\n> quote\n>\n> - nested\n\nA  \nB\nC\n\n---\n\n| Left | Mid | Right |\n| :--- | :---: | ---: |\n| a | b | c |\n'
	assert render_markdown(&input) == '<ol start="3">\n<li>one</li>\n<li><strong>two</strong></li>\n</ol>\n<blockquote>\n<p>quote</p>\n<ul>\n<li>nested</li>\n</ul>\n</blockquote>\n<p>A<br />\nB\nC</p>\n<hr />\n<table><thead><tr><th style="text-align: left">Left</th><th style="text-align: center">Mid</th><th style="text-align: right">Right</th></tr></thead><tbody>\n<tr><td style="text-align: left">a</td><td style="text-align: center">b</td><td style="text-align: right">c</td></tr>\n</tbody></table>\n'
}

fn test_web_policy_limits_original_bytes_and_removes_controls() {
	owner := clipboard_owned('HtTpS://example.com/a\u001b?x=1\u0085&y=2')
	assert terminal_hyperlinks.web_destination(&owner) or { panic('missing web destination') } == 'HtTpS://example.com/a?x=1&y=2'
	assert terminal_hyperlinks.web_destination(&owner) or { panic('missing web destination') } == 'HtTpS://example.com/a?x=1&y=2'
	assert owner.contains('\u001b')
	too_long := 'https://example.com/' + '\u001b'.repeat(8192)
	assert terminal_hyperlinks.web_destination(&too_long) == none
	for invalid in ['file:///repo/a', 'javascript:alert(1)', 'http://', 'https://bad host/'] {
		assert terminal_hyperlinks.web_destination(&invalid) == none
	}
}

fn test_fence_unwrapper_keeps_non_tables_partial_fences_and_source_lines() {
	for input in [
		'```markdown\n**bold**\n```\n',
		'```markdown\n| A | B |\n\n| --- | --- |\n```\n',
		'```markdown\n| A | B |\n| --- | --- |\n',
		'```rust\n| A | B |\n| --- | --- |\n```\n',
		'```markdown\n> | A | B |\n> | --- | --- |\n```\n',
		'    ```markdown\n| A | B |\n| --- | --- |\n    ```\n',
	] {
		assert markdown_module.unwrap_markdown_fences(&input) == input
	}
	quoted := clipboard_owned('> ~~~MD\r\n> | A | B |\r\n> | --- | --- |\r\n> | 1 | 2 |\r\n> ~~~~\r\n')
	expected := '> | A | B |\r\n> | --- | --- |\r\n> | 1 | 2 |\r\n'
	assert markdown_module.unwrap_markdown_fences(&quoted) == expected
	assert markdown_module.unwrap_markdown_fences(&quoted) == expected
	assert quoted.starts_with('> ~~~MD')
}

fn test_parser_emits_typed_events_and_borrows_source_repeatedly() {
	owner := clipboard_owned('[label](https://example.com "title") ![alt](x)\n\n| A | B |\n| --- | ---: |\n| 1 | 2 |\n')
	mut parser := pulldown_cmark.Parser.new_ext(&owner, .enable_tables)
	mut kinds := []pulldown_cmark.TagKind{}
	mut links := 0
	mut images := 0
	for {
		event := parser.next() or { break }
		if event.kind == .start {
			kinds << event.tag.kind
			if event.tag.kind == .link {
				links++
				assert *event.tag.dest_url.as_str() == 'https://example.com'
				assert *event.tag.title.as_str() == 'title'
			}
			if event.tag.kind == .image {
				images++
				assert *event.tag.dest_url.as_str() == 'x'
			}
			if event.tag.kind == .table {
				assert event.tag.alignments == [pulldown_cmark.Alignment.none, .right]
			}
		}
	}
	assert links == 1 && images == 1
	assert pulldown_cmark.TagKind.table_head in kinds && pulldown_cmark.TagKind.table_cell in kinds
	mut again := pulldown_cmark.Parser.new_ext(&owner, .enable_tables)
	assert (again.next() or { panic('missing first event') }).kind == .start
	assert owner.contains('[label]')
}
