module mention_codec

import codex_utils_plugins.mention_syntax

fn linked(sigil rune, mention string, path string) LinkedMention {
	return LinkedMention{
		sigil:   sigil
		mention: mention
		path:    path
	}
}

fn test_parse_linked_mentions_preserves_byte_offsets_and_trims_paths() {
	prefix := 'before 🦀 '
	for sigil in [mention_syntax.tool_mention_sigil, mention_syntax.plugin_text_mention_sigil] {
		text := '${prefix}[${sigil}tool_1-name] \n\t( skill://路径/SKILL.md ) trailing'
		parsed := parse_linked_tool_mention(&text, prefix.len, sigil) or {
			panic('expected linked mention for ${sigil}')
		}
		assert parsed == LinkedToolMention{
			name: 'tool_1-name'
			path: 'skill://路径/SKILL.md'
			end:  text.len - ' trailing'.len
		}
	}
}

fn test_parse_linked_mentions_rejects_malformed_links() {
	for text in [
		'[',
		'[$',
		'[\$](app://tool)',
		'[\$tool.name](app://tool)',
		'[\$tool(app://tool)',
		'[\$tool]app://tool)',
		'[\$tool](app://tool',
		'[\$tool]()',
		'[\$tool]( \t )',
		'[@tool](app://tool)',
	] {
		start := 0
		assert parse_linked_tool_mention(&text, start, mention_syntax.tool_mention_sigil) == none, text
	}
}

fn test_decode_history_mentions_restores_visible_tokens() {
	at_mentions_enabled := true
	text := 'Use [\$figma](app://figma-1), [\$sample](plugin://sample@test), and [\$figma](/tmp/figma/SKILL.md).'
	decoded := decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)
	assert decoded.text == 'Use \$figma, \$sample, and \$figma.'
	assert decoded.mentions == [
		linked(`$`, 'figma', 'app://figma-1'),
		linked(`$`, 'sample', 'plugin://sample@test'),
		linked(`$`, 'figma', '/tmp/figma/SKILL.md'),
	]
}

fn test_decode_history_mentions_restores_plugin_links_with_at_sigil() {
	at_mentions_enabled := true
	text := 'Use [@sample](plugin://sample@test) and [\$figma](app://figma-1).'
	decoded := decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)
	assert decoded.text == 'Use @sample and \$figma.'
	assert decoded.mentions == [
		linked(`@`, 'sample', 'plugin://sample@test'),
		linked(`$`, 'figma', 'app://figma-1'),
	]
}

fn test_decode_history_mentions_without_at_mentions_uses_legacy_plugin_fallback() {
	at_mentions_enabled := false
	text := 'Use [@sample](plugin://sample@test) and [\$figma](app://figma-1).'
	decoded := decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)
	assert decoded.text == 'Use \$sample and \$figma.'
	assert decoded.mentions == [
		linked(`$`, 'sample', 'plugin://sample@test'),
		linked(`$`, 'figma', 'app://figma-1'),
	]
}

fn test_decode_history_mentions_without_at_mentions_ignores_at_non_plugin_paths() {
	at_mentions_enabled := false
	text := 'Use [@figma](app://figma-1).'
	decoded := decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)

	assert decoded.text == 'Use [@figma](app://figma-1).'
	assert decoded.mentions == []LinkedMention{}
}

fn test_decode_history_mentions_restores_at_sigil_for_tool_paths() {
	at_mentions_enabled := true
	text := 'Use [@figma](app://figma-1).'
	decoded := decode_history_mentions_with_at_mentions(&text, at_mentions_enabled)

	assert decoded.text == 'Use @figma.'
	assert decoded.mentions == [linked(`@`, 'figma', 'app://figma-1')]
}

fn test_encode_history_mentions_links_bound_mentions_in_order() {
	text := '\$figma then \$sample then \$figma then \$other'
	mentions := [
		linked(`$`, 'figma', 'app://figma-app'),
		linked(`$`, 'sample', 'plugin://sample@test'),
		linked(`$`, 'figma', '/tmp/figma/SKILL.md'),
	]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == '[\$figma](app://figma-app) then [\$sample](plugin://sample@test) then [\$figma](/tmp/figma/SKILL.md) then \$other'
}

fn test_encode_history_mentions_links_dollar_mentions_after_punctuation() {
	text := '(\$figma)'
	mentions := [linked(`$`, 'figma', 'app://figma')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == '([\$figma](app://figma))'
}

fn test_encode_history_mentions_links_dollar_mentions_with_path_like_suffixes() {
	mention := linked(`$`, 'figma', 'app://figma')
	mentions := [mention]

	slash_suffix := '\$figma/docs'
	assert encode_history_mentions(&slash_suffix, &mentions) == '[\$figma](app://figma)/docs'
	dot_suffix := '\$figma.suffix'
	assert encode_history_mentions(&dot_suffix, &mentions) == '[\$figma](app://figma).suffix'
	backslash_suffix := '\$figma\\docs'
	assert encode_history_mentions(&backslash_suffix, &mentions) == '[\$figma](app://figma)\\docs'
}

fn test_encode_history_mentions_preserves_at_sigils() {
	text := '@figma then @sample then \$other'
	mentions := [
		linked(`@`, 'figma', '/tmp/figma/SKILL.md'),
		linked(`@`, 'sample', 'plugin://sample@test'),
	]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == '[@figma](/tmp/figma/SKILL.md) then [@sample](plugin://sample@test) then \$other'
}

fn test_encode_history_mentions_links_both_sigils_for_same_name() {
	text := '@figma then \$figma'
	mentions := [
		linked(`@`, 'figma', 'plugin://figma@test'),
		linked(`$`, 'figma', 'app://figma'),
	]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == '[@figma](plugin://figma@test) then [\$figma](app://figma)'
}

fn test_encode_history_mentions_does_not_let_at_token_steal_later_tool_binding() {
	text := '@figma then \$figma'
	mentions := [linked(`$`, 'figma', 'app://figma-app')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == '@figma then [\$figma](app://figma-app)'
}

fn test_encode_history_mentions_links_at_mentions_after_unicode_whitespace() {
	// Fix coverage: full-width space should remain a valid plaintext boundary for `@` links.
	text := 'foo　@sample'
	mentions := [linked(`@`, 'sample', 'plugin://sample@test')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == 'foo　[@sample](plugin://sample@test)'
}

fn test_encode_history_mentions_links_sentence_ending_at_mentions() {
	text := 'Please ask @figma.'
	mentions := [linked(`@`, 'figma', '/tmp/figma/SKILL.md')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == 'Please ask [@figma](/tmp/figma/SKILL.md).'
}

fn test_encode_history_mentions_links_parenthesized_at_mentions() {
	text := 'Please ask (@figma)'
	mentions := [linked(`@`, 'figma', 'plugin://figma@test')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == 'Please ask ([@figma](plugin://figma@test))'
}

fn test_encode_history_mentions_skips_embedded_at_substrings() {
	text := 'foo@sample.com npx @sample/pkg then @sample'
	mentions := [linked(`@`, 'sample', 'plugin://sample@test')]
	encoded := encode_history_mentions(&text, &mentions)
	assert encoded == 'foo@sample.com npx @sample/pkg then [@sample](plugin://sample@test)'
}

// V-specific ownership coverage: borrowed text and mention inputs stay usable after repeated
// encode/decode calls.
fn test_borrowed_inputs_remain_owned_by_caller() {
	mut text := 'Use \$figma now'
	$if ownership ? {
		text = 'Use \$figma now'.to_owned()
	}
	mentions := [linked(`$`, 'figma', 'app://figma')]
	first := encode_history_mentions(&text, &mentions)
	second := encode_history_mentions(&text, &mentions)
	assert first == second
	assert first == 'Use [\$figma](app://figma) now'
	decoded := decode_history_mentions_with_at_mentions(&first, false)
	assert decoded.text == text
	assert decoded.mentions == mentions
	assert is_common_env_var(&text) == false
	assert text == 'Use \$figma now'
}
