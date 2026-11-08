module bottom_pane

import codex_tui.slash_command
import os
import time
import codex_app_server_protocol.skill_metadata
import codex_connectors
import codex_file_search
import codex_plugin
import codex_protocol.openai_models
import codex_protocol.user_input
import codex_tui.app_event
import codex_tui.app_event_sender
import codex_tui.color
import codex_tui.key_hint
import codex_tui.keymap as tui_keymap
import codex_tui.terminal_palette
import codex_tui.terminal_probe
import codex_tui.task_mentions
import codex_config.types as config_types
import crossterm.event as terminal_event
import ratatui.buffer as rat_buffer
import ratatui.layout as rat_layout
import ratatui.style as rat_style
import ratatui.text as rat_text

// Rust's tests construct owned String values. This helper keeps that boundary visible to V's
// optional ownership checker while remaining compatible with the normal compiler mode.
fn owned_composer_test_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn new_test_composer() ChatComposer {
	return ChatComposer.new(true, app_event_sender.AppEventSender{}, false, owned_composer_test_string('Ask Codex to do anything'), false)
}

fn new_test_composer_with_enhanced_keys() ChatComposer {
	return ChatComposer.new(true, app_event_sender.AppEventSender{}, true, owned_composer_test_string('Ask Codex to do anything'), false)
}

fn app_event_history_message(event &app_event.AppEvent) string {
	if cell := event.history_cell {
		return cell.message.clone()
	}
	return ''
}

fn composer_test_key(kind terminal_event.KeyCodeKind) terminal_event.KeyEvent {
	return terminal_event.KeyEvent.new(terminal_event.KeyCode{ kind: kind }, terminal_event.KeyModifiers{})
}

fn composer_test_char(ch rune) terminal_event.KeyEvent {
	return terminal_event.KeyEvent.new(terminal_event.KeyCode{ kind: .char_key, ch: ch }, terminal_event.KeyModifiers{})
}

// Rust's table-driven token tests use an Option<String>. Keeping the expectation as an
// explicit `has_value` flag avoids turning an absent value into an empty query: `@` is the
// one case where an empty query is a real, present result.
fn assert_current_at_token_case(input string, cursor int, has_value bool, expected string) {
	mut textarea := TextArea.new()
	textarea.insert_str(&input)
	textarea.set_cursor(cursor)
	result := ChatComposer.current_at_token(&textarea)
	if has_value {
		actual := result or { panic('expected an @ token for ${input} at ${cursor}') }
		assert actual == expected
	} else {
		assert result == none, 'unexpected @ token for ${input} at ${cursor}'
	}
}

// Ownership regression: both current-text accessors and token parsers borrow their owners. The
// same allocation is borrowed repeatedly and used afterward, proving that no read API consumes it.
fn test_ownership_borrowed_composer_reads_preserve_owner() {
	mut composer := new_test_composer()
	owner := owned_composer_test_string('hello @agent')
	composer.insert_str(&owner)
	assert composer.current_text() == owner
	assert composer.current_text_with_pending() == owner
	assert owner == 'hello @agent'
	first := ChatComposer.current_at_token(&composer.draft.textarea) or { panic('mention missing') }
	second := ChatComposer.current_at_token(&composer.draft.textarea) or { panic('mention missing') }
	assert first == 'agent'
	assert second == 'agent'
	assert owner.len == 12
}

// Ownership regression for the optional Copy-equivalent effort adaptation: callers retain and can
// reuse the enum after both the baseline and transition APIs inspect it.
fn test_ownership_reasoning_effort_value_remains_reusable() {
	mut composer := new_test_composer()
	effort := openai_models.ReasoningEffort.max
	composer.set_active_reasoning_effort_baseline(effort)
	assert effort == .max
	assert !composer.set_active_reasoning_effort(effort, true)
	assert effort == .max
}

// V adaptation of Rust's generic snapshot helper. The target-specific ratatui boundary stores
// logical rows rather than insta terminal cells, while preserving source width/dynamic-height setup.
fn snapshot_composer_state_with_width(_name &string, width u16, enhanced_keys_supported bool,
	setup fn (mut ChatComposer)) []string {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{}, enhanced_keys_supported, owned_composer_test_string('Ask Codex to do anything'), /* disable_paste_burst */
		false)
	setup(mut composer)
	props := composer.footer_props()
	footer_lines := footer_height(&props)
	footer_spacing := ChatComposer.footer_spacing(footer_lines)
	height := footer_lines + footer_spacing + 8
	area := rat_layout.Rect{ width: width, height: height }
	mut buffer := rat_buffer.Buffer{}
	composer.render(area, mut buffer)
	return composer_buffer_rows(&buffer, area)
}

fn snapshot_composer_state(name &string, enhanced_keys_supported bool,
	setup fn (mut ChatComposer)) []string {
	return snapshot_composer_state_with_width(name, /* width */
		100, enhanced_keys_supported, setup)
}

// The Rust snapshots compare the complete fixed-size terminal buffer, including blank cells.
// The target-specific ratatui shim stores only written cells, so materialize the same logical rows
// without weakening the assertion to a list of strings emitted during rendering.
fn composer_buffer_rows(buffer &rat_buffer.Buffer, area rat_layout.Rect) []string {
	mut rows := []string{cap: int(area.height)}
	for row in 0 .. int(area.height) {
		mut runes := []rune{len: int(area.width), init: ` `}
		for cell in buffer.cells {
			if int(cell.y) != int(area.y) + row || cell.x < area.x || cell.x >= area.x + area.width {
				continue
			}
			symbol := cell.symbol.runes()
			if symbol.len > 0 {
				runes[int(cell.x - area.x)] = symbol[0]
			}
		}
		rows << runes.string()
	}
	return rows
}

fn composer_buffer_style_at(buffer &rat_buffer.Buffer, x u16, y u16) rat_style.Style {
	for cell in buffer.cells {
		if cell.x == x && cell.y == y {
			return cell.style
		}
	}
	return rat_style.Style{}
}

fn composer_buffer_cell(buffer &rat_buffer.Buffer, x u16, y u16) rat_buffer.Cell {
	for cell in buffer.cells {
		if cell.x == x && cell.y == y {
			return cell
		}
	}
	return rat_buffer.Cell{ x: x, y: y, symbol: ' ' }
}

// The translated copies of Rust's checked-in insta files are the exact row oracle while the
// terminal backend remains an external stub. They preserve every blank fixed-size terminal cell.
fn rust_chat_composer_snapshot_rows(name &string) []string {
	path := os.join_path(os.dir(@FILE), 'snapshots', 'codex_tui__bottom_pane__chat_composer__tests__${*name}.snap')
	contents := os.read_file(path) or { panic('read Rust snapshot ${path}: ${err}') }
	mut sections := contents.split('\n---\n')
	if sections.len < 2 {
		panic('malformed Rust snapshot ${path}')
	}
	body := sections.last()
	mut rows := []string{}
	for line in body.split_into_lines() {
		if line.len >= 2 && line.starts_with('"') && line.ends_with('"') {
			rows << line[1..line.len - 1].replace('\\"', '"').replace('\\\\', '\\')
		}
	}
	return rows
}

fn assert_composer_snapshot(name string, composer &ChatComposer, width u16) {
	props := composer.footer_props()
	height := footer_height(&props) + ChatComposer.footer_spacing(footer_height(&props)) + 8
	area := rat_layout.Rect{ width: width, height: height }
	mut buffer := rat_buffer.Buffer{}
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == rust_chat_composer_snapshot_rows(&name), name
}

fn plugin_mention_foreground_color(composer &ChatComposer) ?rat_style.Color {
	highlights := composer.plugin_at_mention_highlights()
	if highlights.len > 0 {
		return highlights[0].style.fg
	}
	return none
}

// Mirrors Rust's `Some(Color::...)` expectations for `Style::fg`, which is an optional color.
fn some_color(kind rat_style.ColorKind) ?rat_style.Color {
	return rat_style.Color{
		kind: kind
	}
}

fn setup_collab_footer(mut composer ChatComposer, context_percent i64,
	indicator ?CollaborationModeIndicator) {
	composer.set_collaboration_modes_enabled(true)
	composer.set_collaboration_mode_indicator(indicator)
	composer.set_context_window(context_percent, none)
}

// Rust helper `test_skill_metadata`; prefixed because V reserves test_* functions for zero-arg
// test entry points.
fn rust_test_skill_metadata(name &string) skill_metadata.SkillMetadata {
	return skill_metadata.SkillMetadata{
		name:        name.clone()
		description: 'Example skill used in tests.'
		path:        '/tmp/${*name}/SKILL.md'
		enabled:     true
	}
}

// Rust helper `test_skill_binding`; see rust_test_skill_metadata for the V test-name adaptation.
fn rust_test_skill_binding(name &string) MentionBinding {
	return MentionBinding{ sigil: `$`, mention: name.clone(), path: '/tmp/${*name}/SKILL.md' }
}

// Rust helper `test_plugin_binding`.
fn rust_test_plugin_binding(name &string) MentionBinding {
	return MentionBinding{ sigil: `@`, mention: name.clone(), path: 'plugin://${*name}@test' }
}

// Rust helper `test_plugin_summary`.
fn rust_test_plugin_summary(name &string, description &string) codex_plugin.PluginCapabilitySummary {
	return codex_plugin.PluginCapabilitySummary{
		config_name:      '${*name}@test'
		display_name:     name.clone()
		description:      description.clone()
		mcp_server_names: [name.clone()]
	}
}

fn configure_partially_bound_skill_mentions(mut composer ChatComposer) {
	name := 'unbound-skill'
	bound := 'bound-skill'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content_with_mention_bindings('\$unbound-skill  \$bound-skill continue', [], [], [
		rust_test_skill_binding(&bound),
	])
	composer.set_current_cursor('\$unbound-skill  '.len)
	composer.sync_popups()
}

fn configure_bound_skill_left_of_unbound_skill(mut composer ChatComposer) {
	name := 'unbound-skill'
	bound := 'bound-skill'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content_with_mention_bindings('\$bound-skill\$unbound-skill', [], [], [
		rust_test_skill_binding(&bound),
	])
	composer.set_current_cursor('\$bound-skill'.len)
	composer.sync_popups()
}

fn configure_skill_target_between_bound_mentions(mut composer ChatComposer) {
	name := 'other'
	one := 'bound1'
	two := 'bound2'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content_with_mention_bindings('\$bound1 \$oth \$bound2', [], [], [
		rust_test_skill_binding(&one),
		rust_test_skill_binding(&two),
	])
	empty := ''
	composer.draft.textarea.replace_range('\$bound1'.len, '\$bound1 '.len, &empty)
	composer.draft.textarea.replace_range('\$bound1\$oth'.len, '\$bound1\$oth '.len, &empty)
	composer.set_current_cursor('\$bound1\$o'.len)
	composer.sync_popups()
}

fn configure_skill_mention_with_trailing_space(mut composer ChatComposer) {
	name := 'figma'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$figma ', [], [])
	composer.set_current_cursor('\$figma '.len)
	composer.sync_popups()
}

fn configure_bound_plugin_left_of_unbound_plugin(mut composer ChatComposer) {
	other := 'other'
	sample := 'sample'
	description := 'Plugin used to test adjacent mention targeting.'
	composer.set_mentions_v2_enabled(true)
	composer.set_plugin_mentions([rust_test_plugin_summary(&other, &description)])
	composer.set_text_content_with_mention_bindings('@sample@other', [], [], [
		rust_test_plugin_binding(&sample),
	])
	composer.set_current_cursor('@sample'.len)
	composer.sync_popups()
}

fn configure_unbound_plugin_left_of_bound_plugin(mut composer ChatComposer) {
	left := 'left'
	bound := 'bound'
	description := 'Plugin used to test bound mention fallback.'
	composer.set_mentions_v2_enabled(true)
	composer.set_plugin_mentions([rust_test_plugin_summary(&left, &description)])
	composer.set_text_content_with_mention_bindings('@left  @bound', [], [], [
		rust_test_plugin_binding(&bound),
	])
	composer.set_current_cursor('@left '.len)
	composer.sync_popups()
}

fn configure_plugin_target_between_bound_mentions(mut composer ChatComposer) {
	other := 'other'
	one := 'bound1'
	two := 'bound2'
	description := 'Plugin used to test middle mention targeting.'
	composer.set_mentions_v2_enabled(true)
	composer.set_plugin_mentions([rust_test_plugin_summary(&other, &description)])
	composer.set_text_content_with_mention_bindings('@bound1 @oth @bound2', [], [], [
		rust_test_plugin_binding(&one),
		rust_test_plugin_binding(&two),
	])
	empty := ''
	composer.draft.textarea.replace_range('@bound1'.len, '@bound1 '.len, &empty)
	composer.draft.textarea.replace_range('@bound1@oth'.len, '@bound1@oth '.len, &empty)
	composer.set_current_cursor('@bound1@o'.len)
	composer.sync_popups()
}

fn assert_typed_skill_prefix_starts_new_mention(inserted &string) {
	mut composer := new_test_composer()
	name := 'rustdoc'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$simplify-code', [], [])
	composer.set_current_cursor(0)
	composer.insert_str(inserted)
	composer.handle_key_event(composer_test_key(.enter))
	assert composer.current_text() == '\$rustdoc \$simplify-code'
	assert composer.mention_bindings() == [rust_test_skill_binding(&name)]
}

fn flush_after_paste_burst(mut composer ChatComposer) bool {
	return composer.handle_paste_burst_flush(time.now().unix_milli() + PasteBurst.recommended_active_flush_delay())
}

// Test helper: simulate human typing with a brief delay and flush the paste-burst buffer
fn type_chars_humanlike(mut composer ChatComposer, chars &[]rune) {
	mut now_ms := time.now().unix_milli()
	for ch in *chars {
		composer.handle_input_basic_with_time(composer_test_char(ch), now_ms)
		now_ms += ChatComposer.recommended_paste_flush_delay()
		composer.handle_paste_burst_flush(now_ms)
	}
}

fn assert_queued_slash(input &string) {
	mut composer := new_test_composer()
	composer.set_task_running(true)
	composer.draft.textarea.set_text_clearing_elements(input)
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .queued
	assert result.text == *input
	assert result.text_elements.len == 0
	assert result.action == .parse_slash
	assert composer.draft.textarea.is_empty()
	assert composer.app_event_tx.events.len == 0, 'queueing should not report slash errors'
}

fn assert_queued_shell(input &string, expected_text &string) {
	mut composer := new_test_composer()
	composer.set_task_running(true)
	composer.draft.textarea.set_text_clearing_elements(input)
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .queued
	assert result.text == *expected_text
	assert result.text_elements.len == 0
	assert result.action == .run_shell
	assert composer.draft.textarea.is_empty()
	assert composer.app_event_tx.events.len == 0, 'queueing should not show shell help immediately'
}

fn complete_file(mut composer ChatComposer, text &string, cursor int, query &string,
	selected_path string) {
	composer.set_text_content(text.clone(), [], [])
	composer.set_current_cursor(cursor)
	composer.sync_popups()
	composer.on_file_search_result(query.clone(), [codex_file_search.FileMatch{
		score: 1
		path:  selected_path
		root:  '/tmp'
	}])
	composer.handle_key_event(composer_test_key(.tab))
}

fn test_shortcut_footer_displays_configured_chords() {
	mut config := config_types.TuiKeymap{}
	config.global.open_external_editor = config_types.KeybindingsSpec.from_one(config_types.KeybindingSpec{
		value: 'ctrl-g ctrl-g'
	})
	config.editor.insert_newline = config_types.KeybindingsSpec.from_one(config_types.KeybindingSpec{
		value: 'ctrl-x enter'
	})
	keymap := tui_keymap.RuntimeKeymap.from_config(&config) or {
		panic('valid composer chords')
	}
	external := key_hint.ShortcutHint.chord(key_hint.ctrl(terminal_event.KeyCode{
		kind: .char_key
		ch:   `g`
	}), key_hint.ctrl(terminal_event.KeyCode{ kind: .char_key, ch: `g` }))
	newline := key_hint.ShortcutHint.chord(key_hint.ctrl(terminal_event.KeyCode{
		kind: .char_key
		ch:   `x`
	}), key_hint.plain(terminal_event.KeyCode{ kind: .enter }))
	mut composer := new_test_composer()
	composer.set_keymap_bindings(&keymap)
	composer.footer.mode = .shortcut_overlay
	hints := composer.footer_props().key_hints
	assert hints.external_editor or { panic('external editor hint') } == external
	assert hints.insert_newline or { panic('newline hint') } == newline
	assert_composer_snapshot('footer_mode_configured_key_chords', &composer, 100)
}

fn test_parent_owned_thread_allows_bare_navigation_commands() {
	for input, expected in {
		'/agents':    slash_command.SlashCommand.agents
		'/subagents': slash_command.SlashCommand.multi_agents
		'/side':      slash_command.SlashCommand.side
		'/btw':       slash_command.SlashCommand.btw
		'/diff ':     slash_command.SlashCommand.diff
	} {
		mut composer := new_test_composer()
		composer.set_parent_owned_thread()
		composer.set_text_content(input, [], [])
		result, _ := composer.handle_submission( /* should_queue */
		false)
		assert result.kind == .command
		assert result.command == expected
	}
}

fn test_parent_owned_thread_allows_safe_command_selected_from_prefix() {
	mut composer := new_test_composer()
	composer.set_parent_owned_thread()
	type_chars_humanlike(mut composer, &[`/`, `a`, `g`])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command == .agents
}

fn test_parent_owned_thread_placeholder_snapshot() {
	mut composer := new_test_composer()
	composer.set_parent_owned_thread()
	assert composer.blocks_direct_input
	assert composer.placeholder_text == 'Viewing sub-agent — direct input is disabled'
	assert_composer_snapshot('parent_owned_thread_placeholder', &composer, 100)
}

fn test_light_terminal_palette_renders_light_composer_snapshot() {
	colors := terminal_probe.DefaultColors{
		fg: color.Rgb{0x55, 0x57, 0x53}
		bg: color.Rgb{0xff, 0xff, 0xff}
	}

	area := rat_layout.Rect{ x: 0, y: 0, width: 48, height: 6 }
	// Rust asserts inside the closure; V generics cannot return `void`, so the closure returns the
	// rendered buffer and the assertions run immediately after the palette override is restored.
	buffer := terminal_palette.with_test_default_colors(colors, fn [area] () rat_buffer.Buffer {
		composer := new_test_composer()
		mut buffer := rat_buffer.Buffer{}
		composer.render(area, mut buffer)
		return buffer
	})

	background := terminal_palette.rgb_color(color.Rgb{244, 244, 244})
	assert composer_buffer_style_at(&buffer, 0, 1).bg == ?rat_style.Color(background)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                ',
		'› Ask Codex to do anything                      ',
		'                                                ',
		'                                                ',
		'                                                ',
		'  ? for shortcuts            100% context left  ',
	]
	plain_background := rat_style.Style.default().bg(background)
	// Match all ten style transitions recorded by the Rust ratatui Buffer debug snapshot.
	assert composer_buffer_style_at(&buffer, 0, 0) == plain_background
	assert composer_buffer_style_at(&buffer, 0, 1) == plain_background.bold()
	assert composer_buffer_style_at(&buffer, 1, 1) == plain_background
	assert composer_buffer_style_at(&buffer, 2, 1) == plain_background.dim()
	assert composer_buffer_style_at(&buffer, 26, 1) == plain_background
	assert composer_buffer_style_at(&buffer, 0, 5) == rat_style.Style.default()
	assert composer_buffer_style_at(&buffer, 2, 5) == rat_style.Style.default().dim()
	assert composer_buffer_style_at(&buffer, 17, 5) == rat_style.Style.default()
	assert composer_buffer_style_at(&buffer, 29, 5) == rat_style.Style.default().dim()
	assert composer_buffer_style_at(&buffer, 46, 5) == rat_style.Style.default()
}

fn test_footer_hint_row_is_separated_from_composer() {
	composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	area := rat_layout.Rect{ width: 40, height: 6 }
	mut buffer := rat_buffer.Buffer{}
	composer.render(area, mut buffer)
	rows := composer_buffer_rows(&buffer, area)
	mut hint_row := -1
	for index, row in rows {
		if row.contains('? for shortcuts') {
			hint_row = index
			break
		}
	}
	assert hint_row == int(area.height) - 1
	assert hint_row > 0
	assert rows[hint_row - 1].trim_space() == '', 'expected blank spacing row above hints but saw: ${rows[hint_row - 1]}'
}

fn test_footer_flash_overrides_footer_hint_override() {
	mut composer := new_test_composer()
	composer.set_footer_hint_override([['K', 'label']])
	flash_text := 'FLASH'
	composer.show_footer_flash(line_from_string(&flash_text), 10_000)
	mut buffer := rat_buffer.Buffer{}
	composer.render(rat_layout.Rect{ width: 60, height: 6 }, mut buffer)
	assert buffer.lines.any(it.contains('FLASH'))
	assert buffer.lines.all(!it.contains('K label'))
}

fn test_footer_flash_expires_and_falls_back_to_hint_override() {
	mut composer := new_test_composer()
	composer.set_footer_hint_override([['K', 'label']])
	flash_text := 'FLASH'
	composer.show_footer_flash(line_from_string(&flash_text), 10_000)
	flash := composer.footer.flash or { panic('footer flash') }
	composer.footer.flash = FooterFlash{
		line:       flash.line
		expires_at: time.now().unix_milli() - 1
	}
	mut buffer := rat_buffer.Buffer{}
	composer.render(rat_layout.Rect{ width: 60, height: 6 }, mut buffer)
	assert buffer.lines.any(it.contains('K label'))
	assert buffer.lines.all(!it.contains('FLASH'))
}

fn test_footer_mode_snapshots() {
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_esc_backtrack_hint(true)
		composer.handle_key_event(composer_test_char(`?`))
		assert_composer_snapshot('footer_mode_shortcut_overlay', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_queue_submissions(true)
		composer.handle_key_event(composer_test_char(`?`))
		assert_composer_snapshot('footer_mode_shortcut_overlay_queue_submissions', &composer, 100)
	}
	ctrl_c := key_hint.ctrl(terminal_event.KeyCode{ kind: .char_key, ch: `c` })
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.show_quit_shortcut_hint(ctrl_c, true)
		assert_composer_snapshot('footer_mode_ctrl_c_quit', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_task_running(true)
		composer.show_quit_shortcut_hint(ctrl_c, true)
		assert_composer_snapshot('footer_mode_ctrl_c_interrupt', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.show_quit_shortcut_hint(ctrl_c, true)
		composer.handle_key_event(composer_test_key(.escape))
		assert_composer_snapshot('footer_mode_ctrl_c_then_esc_hint', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.handle_key_event(composer_test_char(`?`))
		composer.handle_key_event(composer_test_key(.escape))
		assert_composer_snapshot('footer_mode_esc_hint_from_overlay', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_esc_backtrack_hint(true)
		composer.handle_key_event(composer_test_key(.escape))
		assert_composer_snapshot('footer_mode_esc_hint_backtrack', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.handle_key_event(composer_test_char(`?`))
		composer.set_esc_backtrack_hint(true)
		assert_composer_snapshot('footer_mode_overlay_then_external_esc_hint', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		type_chars_humanlike(mut composer, &[`h`])
		assert_composer_snapshot('footer_mode_hidden_while_typing', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.history.record_local_submission(HistoryEntry.new('cargo test'))
		composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   `r`
		}, terminal_event.KeyModifiers{ control: true }))
		composer.handle_key_event(composer_test_char(`c`))
		assert_composer_snapshot('footer_mode_history_search', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_text_content('draft', [], [])
		composer.begin_history_search()
		for ch in [`g`, `i`, `t`] {
			composer.handle_key_event(composer_test_char(ch))
		}
		composer.apply_history_search_result(HistorySearchResult{ kind: .pending })
		composer.apply_history_search_result(HistorySearchResult{ kind: .unavailable })
		assert_composer_snapshot('footer_mode_history_search_unavailable', &composer, 100)
	}
	status := 'gpt-5.4 high fast · ~/code/codex-1 · Context 0% used'
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_status_line_enabled(true)
		composer.set_status_line(line_from_string(&status))
		composer.set_text_content('!git status', [], [])
		assert_composer_snapshot('footer_mode_shell_command_absorbs_bang', &composer, 100)
	}
	{
		mut composer := new_test_composer_with_enhanced_keys()
		composer.set_status_line_enabled(true)
		composer.set_status_line(line_from_string(&status))
		composer.set_text_content('!', [], [])
		composer.handle_key_event(composer_test_key(.escape))
		assert_composer_snapshot('footer_mode_shell_command_escape_exits_empty_mode', &composer, 100)
	}
}

fn test_shell_command_cursor_uses_absorbed_prefix() {
	mut composer := ChatComposer.new(true, app_event_sender.AppEventSender{}, true, owned_composer_test_string('Ask Codex to do anything'), false)
	area := rat_layout.Rect{ width: 40, height: 5 }
	composer.set_text_content('!git', [], [])
	composer.move_cursor_to_end()
	position := composer.cursor_pos(area) or { panic('cursor must be visible') }
	assert position == CursorPosition{ x: 5, y: 1 }
	composer.set_text_content('! git', [], [])
	composer.move_cursor_to_end()
	spaced_position := composer.cursor_pos(area) or { panic('cursor must be visible') }
	assert spaced_position == CursorPosition{ x: 6, y: 1 }
}

fn test_shell_command_uses_shell_accent_style() {
	mut composer := new_test_composer_with_enhanced_keys()
	composer.set_status_line_enabled(true)
	status := 'gpt-5.4 high fast · ~/code/codex-1 · Context 0% used'
	composer.set_status_line(line_from_string(&status))
	composer.set_text_content('!git status', [], [])
	area := rat_layout.Rect{ width: 100, height: 9 }
	mut buffer := rat_buffer.Buffer{}
	composer.render(area, mut buffer)
	assert composer_buffer_cell(&buffer, 0, 1).symbol == '!'
	assert composer_buffer_cell(&buffer, 0, 1).style.fg == some_color(.light_red)
	footer_y := area.height - 1
	footer_text := composer_buffer_rows(&buffer, area)[int(footer_y)]
	shell_label_x := footer_text.index('Shell mode') or { panic('expected shell mode footer label') }
	assert composer_buffer_cell(&buffer, u16(shell_label_x), footer_y).style.fg == some_color(.light_red)
}

fn test_plugin_at_mentions_use_plugin_accent_style() {
	mut composer := new_test_composer()
	plugin_name := 'sample'
	composer.set_text_content_with_mention_bindings('@sample plugin', [], [], [
		rust_test_plugin_binding(&plugin_name),
	])
	highlights := composer.plugin_at_mention_highlights()
	assert highlights.len == 1
	assert highlights[0].start == 0
	assert highlights[0].end == '@sample'.len
	assert highlights[0].style.fg == some_color(.magenta)
}

fn test_plugin_at_mentions_render_with_plugin_accent_snapshot() {
	mut composer := new_test_composer()
	plugin_name := 'sample'
	composer.set_text_content_with_mention_bindings('@sample plugin', [], [], [
		rust_test_plugin_binding(&plugin_name),
	])
	assert composer.plugin_at_mention_highlights().map(it.style.fg) == [
		some_color(.magenta),
	]
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 40, height: 5 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area)[1].trim_right(' ') == '› @sample plugin'
	magenta := buffer.cells.filter(it.y == 1 && it.style.fg == some_color(.magenta))
	assert magenta.len == 7
	assert magenta.map(it.symbol).join('') == '@sample'
}

fn test_recalled_plugin_at_mentions_keep_plugin_accent_style() {
	mut composer := new_test_composer()
	plugin_name := 'sample'
	composer.set_text_content_with_mention_bindings('@sample plugin', [], [], [
		rust_test_plugin_binding(&plugin_name),
	])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	composer.set_text_content('', [], [])
	_, redraw := composer.handle_key_event(composer_test_key(.up))
	assert redraw
	assert composer.current_text() == '@sample plugin'
	assert composer.plugin_at_mention_highlights().map(it.style.fg) == [
		some_color(.magenta),
	]
}

fn test_status_line_hyperlink_marks_pr_number_cells() {
	mut composer := new_test_composer()
	url := 'https://github.com/openai/codex/pull/20252'
	composer.set_status_line_enabled(true)
	status := 'PR #20252'
	composer.set_status_line(rat_text.Line{
		spans: [rat_text.Span{
			text:  status
			style: rat_style.Style.default().cyan().underlined()
		}]
	})
	composer.set_status_line_hyperlink(url)
	mut buffer := rat_buffer.Buffer{}
	composer.render(rat_layout.Rect{ width: 40, height: 6 }, mut buffer)
	status_link := composer.footer.status_line_hyperlink_url or { panic('status link') }
	assert status_link == url
	assert buffer.lines.any(it.contains('PR #20252'))
	marked_cells := buffer.cells.filter((it.hyperlink or { '' }) == url)
	assert marked_cells.len == 'PR #20252'.bytes().filter(!it.is_space()).len
	assert marked_cells.len == 8
	assert marked_cells.all(it.style.fg == some_color(.cyan) && it.style.add_modifier.has(.underlined))
}

fn test_esc_exits_empty_shell_mode() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`!`])
	assert composer.draft.is_bash_mode
	assert composer.current_text() == '!'
	result, redraw := composer.handle_key_event(composer_test_key(.escape))
	assert result.kind == .no_result
	assert redraw
	assert !composer.draft.is_bash_mode
	assert composer.current_text() == ''
}

fn test_esc_keeps_shell_mode_when_paste_burst_flushes_pending_text() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`!`])
	composer.handle_key_event(composer_test_char(`g`))
	assert composer.draft.paste_burst.is_active()
	assert composer.current_text() == '!'
	result, redraw := composer.handle_key_event(composer_test_key(.escape))
	assert result.kind == .no_result
	assert redraw
	assert composer.draft.is_bash_mode
	assert composer.current_text() == '!g'
}

fn test_footer_collapse_snapshots() {
	// Empty textarea, agent idle: shortcuts hint can show, and cycle hint is hidden.
	for name, width in {
		'footer_collapse_empty_full':                       u16(120)
		'footer_collapse_empty_mode_cycle_with_context':    u16(60)
		'footer_collapse_empty_mode_cycle_without_context': u16(44)
		'footer_collapse_empty_mode_only':                  u16(26)
	} {
		mut composer := new_test_composer_with_enhanced_keys()
		setup_collab_footer(mut composer, 100, none)
		assert_composer_snapshot(name, &composer, width)
	}

	// Empty textarea, plan mode idle: shortcuts hint and cycle hint are available.
	for name, width in {
		'footer_collapse_plan_empty_full':                       u16(120)
		'footer_collapse_plan_empty_mode_cycle_with_context':    u16(60)
		'footer_collapse_plan_empty_mode_cycle_without_context': u16(44)
		'footer_collapse_plan_empty_mode_only':                  u16(26)
	} {
		mut composer := new_test_composer_with_enhanced_keys()
		setup_collab_footer(mut composer, 100, CollaborationModeIndicator.plan)
		assert_composer_snapshot(name, &composer, width)
	}

	// Textarea has content, agent running: queue hint is shown.
	for name, width in {
		'footer_collapse_queue_full':                    u16(120)
		'footer_collapse_queue_short_with_context':      u16(50)
		'footer_collapse_queue_message_without_context': u16(40)
		'footer_collapse_queue_short_without_context':   u16(30)
		'footer_collapse_queue_mode_only':               u16(20)
	} {
		mut composer := new_test_composer_with_enhanced_keys()
		setup_collab_footer(mut composer, 98, none)
		composer.set_task_running(true)
		composer.set_text_content('Test', [], [])
		assert_composer_snapshot(name, &composer, width)
	}

	// Textarea has content, plan mode active, agent running: queue hint + mode.
	for name, width in {
		'footer_collapse_plan_queue_full':                    u16(120)
		'footer_collapse_plan_queue_short_with_context':      u16(50)
		'footer_collapse_plan_queue_message_without_context': u16(40)
		'footer_collapse_plan_queue_short_without_context':   u16(30)
		'footer_collapse_plan_queue_mode_only':               u16(20)
	} {
		mut composer := new_test_composer_with_enhanced_keys()
		setup_collab_footer(mut composer, 98, CollaborationModeIndicator.plan)
		composer.set_task_running(true)
		composer.set_text_content('Test', [], [])
		assert_composer_snapshot(name, &composer, width)
	}
}

fn test_esc_hint_stays_hidden_with_draft_content() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`d`])
	assert !composer.is_empty()
	assert composer.current_text() == 'd'
	assert composer.footer.mode == .composer_empty
	assert composer.popups.active.kind == .none
	composer.handle_key_event(composer_test_key(.escape))
	assert composer.footer.mode == .composer_empty
	assert !composer.footer.esc_backtrack_hint
}

fn test_empty_vim_insert_escape_enters_normal_without_esc_hint() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	assert composer.is_empty()
	insert_span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert insert_span.text == 'Vim: Insert'
	assert insert_span.style.fg == some_color(.green)
	result, redraw := composer.handle_key_event(composer_test_key(.escape))
	assert result.kind == .no_result
	assert redraw
	assert composer.is_empty()
	normal_span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert normal_span.text == 'Vim: Normal'
	assert normal_span.style.fg == some_color(.magenta)
	assert composer.footer.mode == .composer_empty
	assert !composer.footer.esc_backtrack_hint
	composer.handle_key_event(composer_test_char(`R`))
	replace_span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert replace_span.text == 'Vim: Replace'
	assert replace_span.style.fg == some_color(.cyan)
	composer.handle_paste('x'.repeat(large_paste_char_threshold + 1))
	assert_composer_snapshot('vim_replace_mode', &composer, 100)
	ok := 'ok'
	composer.insert_str(&ok)
	submitted, _ := composer.handle_key_event(composer_test_key(.enter))
	assert submitted.kind == .submitted
	assert composer.current_text() == ''
	composer.handle_key_event(composer_test_key(.escape))
	final_span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert final_span.text == 'Vim: Normal'
	assert final_span.style.fg == some_color(.magenta)
}

fn test_slash_opens_command_popup_in_vim_insert_mode() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		true)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	result, redraw := composer.handle_key_event(composer_test_char(`/`))
	assert result.kind == .no_result
	assert redraw
	assert composer.draft.textarea.text() == '/'
	assert composer.draft.textarea.cursor() == '/'.len
	assert composer.popups.active.kind == .command
	span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert span.text == 'Vim: Insert'
	assert span.style.fg == some_color(.green)
}

fn test_slash_command_dispatches_after_vim_insert_slash() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		true)
	composer.set_vim_enabled( /* enabled */
	true)
	for ch in [`i`, `/`, `d`, `i`, `f`, `f`] {
		composer.handle_key_event(composer_test_char(ch))
	}
	assert composer.draft.textarea.text() == '/diff'
	assert composer.popups.active.kind == .command
	result, redraw := composer.handle_key_event(composer_test_key(.enter))
	assert redraw
	assert composer.is_empty()
	span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert span.text == 'Vim: Insert'
	assert span.style.fg == some_color(.green)
	assert result.kind == .command
	assert result.command == .diff
}

fn test_inline_slash_command_dispatch_resets_vim_mode_to_insert() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		true)
	composer.set_collaboration_modes_enabled( /* enabled */
	true)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('/plan investigate this', [], [])
	composer.popups.active = ActivePopup{}
	result, redraw := composer.handle_key_event(composer_test_key(.enter))
	assert redraw
	span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert span.text == 'Vim: Insert'
	assert span.style.fg == some_color(.green)
	assert result.kind == .command_with_args
	assert result.command == .plan
	assert result.text == 'investigate this'
	assert result.text_elements.len == 0
	composer.prepare_inline_args_submission( /* record_history */
	false) or {
		panic('inline args should prepare')
	}
	for key in [composer_test_char(`x`), composer_test_key(.escape), composer_test_char(`.`)] {
		composer.handle_key_event(key)
	}
	assert composer.current_text() == 'xx'
}

fn test_bang_enters_shell_mode_in_vim_normal_mode() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		true)
	composer.set_vim_enabled( /* enabled */
	true)
	result, redraw := composer.handle_key_event(composer_test_char(`!`))
	assert result.kind == .no_result
	assert redraw
	assert composer.draft.is_bash_mode
	assert composer.current_text() == '!'
	assert composer.draft.textarea.text() == ''
	span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert span.text == 'Vim: Insert'
	assert span.style.fg == some_color(.green)
}

fn test_shell_command_can_be_typed_after_vim_normal_bang() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		true)
	composer.set_vim_enabled( /* enabled */
	true)
	for ch in [`!`, `e`, `c`, `h`, `o`] {
		composer.handle_key_event(composer_test_char(ch))
	}
	assert composer.draft.is_bash_mode
	assert composer.current_text() == '!echo'
	assert composer.draft.textarea.text() == 'echo'
	assert composer.popups.active.kind == .none
}

fn test_base_footer_mode_tracks_empty_state_after_quit_hint_expires() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`d`])
	composer.show_quit_shortcut_hint(key_hint.ctrl(terminal_event.KeyCode{
		kind: .char_key
		ch:   `c`
	}), /* has_focus */
		true)
	composer.footer.quit_shortcut_expires_at = time.now().unix_milli() - 1000
	assert composer.footer_mode() == .composer_has_draft
	composer.set_text_content('', [], [])
	assert composer.footer_mode() == .composer_empty
}

fn test_clear_for_ctrl_c_records_cleared_draft() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('draft text', [], [])
	cleared := composer.clear_for_ctrl_c() or { panic('draft should clear') }
	assert cleared == 'draft text'
	assert composer.is_empty()
	entry := composer.history.navigate_up(&composer.app_event_tx) or { panic('expected history entry') }
	assert entry.text == 'draft text'
	assert entry.text_elements.len == 0
}

fn test_clear_for_ctrl_c_preserves_pending_paste_history_entry() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	large := 'x'.repeat(large_paste_char_threshold + 5)
	char_count := large.runes().len
	placeholder := '[Pasted Content ${char_count} chars]'
	composer.handle_paste(large.clone())
	assert composer.draft.textarea.text() == placeholder
	assert composer.draft.pending_pastes == [PendingPaste{
		placeholder: placeholder.clone()
		actual:      large.clone()
	}]
	composer.clear_for_ctrl_c()
	assert composer.is_empty()
	history_entry := composer.history.navigate_up(&composer.app_event_tx) or {
		panic('expected history entry')
	}
	assert history_entry.text == placeholder
	assert history_entry.text_elements == [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   placeholder.len
	}, placeholder.clone())]
	assert history_entry.local_image_paths.len == 0
	assert history_entry.pending_pastes == [PendingPaste{
		placeholder: placeholder.clone()
		actual:      large.clone()
	}]
	composer.apply_history_entry(history_entry)
	assert composer.draft.textarea.text() == placeholder
	assert composer.draft.pending_pastes == [PendingPaste{
		placeholder: placeholder.clone()
		actual:      large.clone()
	}]
	assert composer.draft.textarea.element_payloads() == [placeholder.clone()]
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == large
	assert result.text_elements.len == 0
}

fn test_large_paste_numbering_reuses_after_ctrl_c_clear() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	paste := 'x'.repeat(large_paste_char_threshold + 4)
	base := '[Pasted Content ${paste.runes().len} chars]'
	composer.handle_paste(paste.clone())
	assert composer.draft.textarea.text() == base
	assert composer.draft.pending_pastes.len == 1
	cleared := composer.clear_for_ctrl_c() or { panic('paste placeholder should clear') }
	assert cleared == base
	assert composer.draft.textarea.text().len == 0
	assert composer.draft.pending_pastes.len == 0
	composer.handle_paste(paste)
	assert composer.draft.textarea.text() == base
	assert composer.draft.pending_pastes.len == 1
	assert composer.draft.pending_pastes[0].placeholder == base
}

fn test_vim_mode_resets_to_insert_after_submission() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_steer_enabled( /* enabled */
	true)
	composer.set_vim_enabled( /* enabled */
	true)
	assert composer.draft.textarea.is_vim_enabled()
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Normal'
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('h', [], [])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert composer.draft.textarea.is_vim_enabled()
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Insert'
	assert composer.is_empty()
	assert result.kind == .submitted
	assert result.text == 'h'
}

fn test_vim_mode_resets_to_insert_after_queued_submission() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_steer_enabled( /* enabled */
	true)
	composer.set_task_running( /* running */
	true)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('queued', [], [])
	result, _ := composer.handle_submission( /* should_queue */
	true)
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Insert'
	assert composer.is_empty()
	assert result.kind == .queued
	assert result.text == 'queued'
}

fn test_vim_mode_stays_insert_after_suppressed_submission() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_steer_enabled( /* enabled */
	true)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('/not-a-command', [], [])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == '/not-a-command'
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Insert'
}

fn test_esc_switches_vim_insert_to_normal() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('hey', [], [])
	composer.draft.textarea.set_cursor(composer.draft.textarea.text().len)
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Insert'
	assert composer.draft.textarea.cursor() == 'hey'.len
	composer.handle_key_event(composer_test_key(.escape))
	assert (composer.vim_mode_indicator_span() or { panic('missing Vim mode') }).text == 'Vim: Normal'
	assert composer.draft.textarea.cursor() == 'he'.len
}

fn test_vim_insert_uses_bar_cursor_style() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		true, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	area := rat_layout.Rect{ width: 80, height: 10 }
	assert composer.cursor_style(area) == .default_user_shape
	composer.set_vim_enabled( /* enabled */
	true)
	assert composer.cursor_style(area) == .default_user_shape
	composer.handle_key_event(composer_test_char(`i`))
	composer.set_text_content('hey', [], [])
	assert composer.cursor_style(area) == .steady_bar
	composer.handle_key_event(composer_test_key(.escape))
	assert composer.cursor_style(area) == .default_user_shape
	composer.handle_key_event(composer_test_char(`R`))
	assert composer.cursor_style(area) == .default_user_shape
}

fn test_clear_for_ctrl_c_preserves_image_draft_state() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	path := 'example.png'
	composer.attach_image(path.clone())
	placeholder := '[Image #${ /* label_number */1}]'
	composer.clear_for_ctrl_c()
	assert composer.is_empty()
	history_entry := composer.history.navigate_up(&composer.app_event_tx) or {
		panic('expected history entry')
	}
	assert history_entry.text == placeholder
	assert history_entry.text_elements == [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   placeholder.len
	}, placeholder.clone())]
	assert history_entry.local_image_paths == [path.clone()]
	composer.apply_history_entry(history_entry)
	assert composer.draft.textarea.text() == placeholder
	assert composer.local_image_paths() == [path]
	assert composer.draft.textarea.element_payloads() == [placeholder]
}

fn test_clear_for_ctrl_c_preserves_remote_offset_image_labels() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	remote_image_url := 'https://example.com/one.png'
	composer.set_remote_image_urls([remote_image_url.clone()])
	text := '[Image #2] draft'
	local_image_path := '/tmp/local-draft.png'
	composer.set_text_content(text.clone(), [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   '[Image #2]'.len
	}, '[Image #2]')], [local_image_path.clone()])
	expected_text := composer.current_text()
	expected_elements := composer.text_elements()
	assert expected_text == '[Image #2] draft'
	assert expected_elements[0].placeholder_text(&expected_text) or { '' } == '[Image #2]'
	cleared := composer.clear_for_ctrl_c() or { panic('expected draft to clear') }
	assert cleared == expected_text
	history_entry := composer.history.navigate_up(&composer.app_event_tx) or {
		panic('expected history entry')
	}
	assert history_entry.text == expected_text
	assert history_entry.text_elements == expected_elements
	assert history_entry.local_image_paths == [local_image_path]
	assert history_entry.remote_image_urls == [remote_image_url]
}

fn test_apply_history_entry_preserves_local_placeholders_after_remote_prefix() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	remote_image_url := 'https://example.com/one.png'
	local_image_path := '/tmp/local-draft.png'
	composer.apply_history_entry(HistoryEntry{
		text:              '[Image #2] draft'
		text_elements:     [user_input.TextElement.new(user_input.ByteRange{
			start: 0
			end:   '[Image #2]'.len
		}, '[Image #2]')]
		local_image_paths: [local_image_path.clone()]
		remote_image_urls: [remote_image_url.clone()]
	})
	restored_text := composer.current_text()
	assert restored_text == '[Image #2] draft'
	restored_elements := composer.text_elements()
	assert restored_elements.len == 1
	assert restored_elements[0].placeholder_text(&restored_text) or { '' } == '[Image #2]'
	assert composer.local_image_paths() == [local_image_path]
	assert composer.remote_image_urls() == [remote_image_url]
}

// Behavior: `?` toggles the shortcut overlay only when the composer is otherwise empty. After
// any typing has occurred, `?` should be inserted as a literal character.
fn test_question_mark_only_toggles_on_first_char() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	result, redraw := composer.handle_key_event(composer_test_char(`?`))
	assert result.kind == .no_result
	assert redraw, 'toggling overlay should request redraw'
	assert composer.footer.mode == .shortcut_overlay
	// Toggle back to prompt mode so subsequent typing captures characters.
	composer.handle_key_event(composer_test_char(`?`))
	assert composer.footer.mode == .composer_empty
	type_chars_humanlike(mut composer, &[`h`])
	assert composer.draft.textarea.text() == 'h'
	assert composer.footer_mode() == .composer_has_draft
	result2, redraw2 := composer.handle_key_event(composer_test_char(`?`))
	assert result2.kind == .no_result
	assert redraw2, 'typing should still mark the view dirty'
	flush_after_paste_burst(mut composer)
	assert composer.draft.textarea.text() == 'h?'
	assert composer.footer.mode == .composer_empty
	assert composer.footer_mode() == .composer_has_draft
}

fn test_shift_question_mark_toggles_shortcut_overlay_when_empty() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_steer_enabled(true)
	result, redraw := composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `?`
	}, terminal_event.KeyModifiers{ shift: true }))
	assert result.kind == .no_result
	assert redraw, 'toggling overlay should request redraw'
	assert composer.footer.mode == .shortcut_overlay
}

// Behavior: while a paste-like burst is being captured, `?` must not toggle the shortcut
// overlay; it should be treated as part of the pasted content.
fn test_question_mark_does_not_toggle_during_paste_burst() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Force an active paste burst so this test doesn't depend on tight timing.
	now_ms := time.now().unix_milli()
	composer.draft.paste_burst.begin_with_retro_grabbed('', now_ms)
	for ch in [`h`, `i`, `?`, `t`, `h`, `e`, `r`, `e`] {
		composer.handle_input_basic_with_time(composer_test_char(ch), now_ms)
	}
	assert composer.is_in_paste_burst()
	assert composer.draft.textarea.text() == ''
	flush_after_paste_burst(mut composer)
	assert composer.draft.textarea.text() == 'hi?there'
	assert composer.footer.mode != .shortcut_overlay
}

fn test_set_connector_mentions_refreshes_open_mention_popup() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_connectors_enabled( /* enabled */
	true)
	composer.set_text_content('\$', [], [])
	assert composer.popups.active.kind == .none
	composer.set_connector_mentions(app_event.ConnectorsSnapshot{
		connectors: [codex_connectors.AppInfo{
			id:            'connector_1'
			name:          'Notion'
			description:   'Workspace docs'
			is_accessible: true
			is_enabled:    true
		}]
	})
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected connector mention') }
	assert mention.insert_text == '\$notion'
	assert (mention.path or { panic('expected connector path') }) == 'app://connector_1'
}

fn test_set_connector_mentions_skips_disabled_connectors() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_connectors_enabled( /* enabled */
	true)
	composer.set_text_content('\$', [], [])
	assert composer.popups.active.kind == .none
	composer.set_connector_mentions(app_event.ConnectorsSnapshot{
		connectors: [codex_connectors.AppInfo{
			id:            'connector_1'
			name:          'Notion'
			description:   'Workspace docs'
			is_accessible: true
			is_enabled:    false
		}]
	})
	assert composer.popups.active.kind == .none, 'disabled connectors should not appear in the mention popup'
}

fn test_set_plugin_mentions_refreshes_open_mention_popup() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('\$', [], [])
	assert composer.popups.active.kind == .none
	composer.set_plugin_mentions([codex_plugin.PluginCapabilitySummary{
		config_name:      'sample@test'
		display_name:     'Sample Plugin'
		has_skills:       true
		mcp_server_names: ['sample']
	}])
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected plugin mention') }
	assert mention.insert_text == '\$sample'
	assert (mention.path or { panic('expected plugin path') }) == 'plugin://sample@test'
}

fn test_skill_popup_targets_unbound_mention_left_of_bound_mention() {
	mut composer := new_test_composer()
	configure_partially_bound_skill_mentions(mut composer)
	target := composer.current_mention_target() or { panic('missing target: ${composer.current_text()} cursor=${composer.current_cursor()} elements=${composer.draft.textarea.text_elements()}') }
	assert target.query == 'unbound-skill', '${target}'
	composer.handle_key_event(composer_test_key(.enter))
	assert composer.current_text() == '\$unbound-skill  \$bound-skill continue', '${composer.current_text()}'
	unbound := 'unbound-skill'
	bound := 'bound-skill'
	assert composer.mention_bindings() == [rust_test_skill_binding(&unbound),
		rust_test_skill_binding(&bound)], '${composer.mention_bindings()}'
	inserted := 'foo'
	composer.insert_str(&inserted)
	assert composer.current_text() == '\$unbound-skill foo \$bound-skill continue'
}

fn test_skill_popup_targets_unbound_mention_left_of_bound_mention_snapshot() {
	mut composer := new_test_composer()
	configure_partially_bound_skill_mentions(mut composer)
	assert composer.popups.active.kind == .skill, '${composer.popups.active} target=${composer.current_mention_target()}'
	assert composer.current_text() == '\$unbound-skill  \$bound-skill continue'
	assert_composer_snapshot('skill_popup_targets_unbound_mention_left_of_bound_mention', &composer, 100)
}

fn test_skill_popup_targets_unbound_mention_right_of_adjacent_bound_mention_snapshot() {
	mut composer := new_test_composer()
	configure_bound_skill_left_of_unbound_skill(mut composer)
	assert composer.popups.active.kind == .skill, '${composer.popups.active}'
	assert composer.current_text() == '\$bound-skill\$unbound-skill'
	assert_composer_snapshot('skill_popup_targets_unbound_mention_right_of_adjacent_bound_mention', &composer, 100)
}

fn test_skill_popup_falls_back_from_bound_skill_with_path_suffix_snapshot() {
	mut composer := new_test_composer()
	left := 'left'
	bound := 'bound'
	composer.set_skill_mentions([rust_test_skill_metadata(&left)])
	composer.set_text_content_with_mention_bindings('\$left  \$bound/path', [], [], [
		rust_test_skill_binding(&bound),
	])
	composer.draft.textarea.set_cursor('\$left  '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill, '${composer.popups.active}'
	mention := composer.popups.active.skill.selected_mention() or { panic('expected left skill') }
	assert mention.insert_text == '\$left'
	assert_composer_snapshot('skill_popup_falls_back_from_bound_skill_with_path_suffix', &composer, 100)
}

fn test_skill_popup_closes_after_trailing_space_snapshot() {
	mut composer := new_test_composer()
	configure_skill_mention_with_trailing_space(mut composer)
	assert composer.current_text() == '\$figma '
	assert composer.popups.active.kind == .none, '${composer.popups.active}'
	assert_composer_snapshot('skill_popup_closes_after_trailing_space', &composer, 100)
}

fn test_unified_mention_popup_falls_back_from_bound_plugin_on_right_snapshot() {
	mut composer := new_test_composer()
	configure_unbound_plugin_left_of_bound_plugin(mut composer)
	assert composer.popups.active.kind == .mention_v2
	mention := composer.popups.active.mention_v2.selected() or { panic('expected unbound plugin') }
	assert mention.insert_text == '@left'
	assert_composer_snapshot('unified_mention_popup_falls_back_from_bound_plugin_on_right', &composer, 100)
}

fn test_adjacent_plugin_completion_inserts_separator_snapshot() {
	mut composer := new_test_composer()
	configure_bound_plugin_left_of_unbound_plugin(mut composer)
	composer.handle_key_event(composer_test_key(.enter))
	assert composer.current_text() == '@sample @other '
	assert_composer_snapshot('adjacent_plugin_completion_inserts_separator', &composer, 100)
}

fn test_skill_completion_replaces_only_middle_adjacent_target() {
	mut composer := new_test_composer()
	configure_skill_target_between_bound_mentions(mut composer)
	composer.handle_key_event(composer_test_key(.enter))
	assert composer.current_text() == '\$bound1 \$other \$bound2'
	one := 'bound1'
	other := 'other'
	two := 'bound2'
	assert composer.mention_bindings() == [rust_test_skill_binding(&one),
		rust_test_skill_binding(&other), rust_test_skill_binding(&two)]
}

fn test_unified_completion_replaces_only_middle_adjacent_target() {
	mut composer := new_test_composer()
	configure_plugin_target_between_bound_mentions(mut composer)
	composer.handle_key_event(composer_test_key(.enter))
	assert composer.current_text() == '@bound1 @other @bound2'
	one := 'bound1'
	other := 'other'
	two := 'bound2'
	assert composer.mention_bindings() == [rust_test_plugin_binding(&one),
		rust_test_plugin_binding(&other), rust_test_plugin_binding(&two)]
}

fn test_skill_popup_falls_back_from_shell_variable_to_skill_on_right() {
	mut composer := new_test_composer()
	name := 'rustdoc'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$HOME  \$rustdoc', [], [])
	composer.draft.textarea.set_cursor('\$HOME '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected rustdoc selection') }
	assert mention.insert_text == '\$rustdoc'
}

fn test_file_popup_ignores_shell_positional_parameter_snapshot() {
	mut composer := new_test_composer()
	name := 'available'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('@src  \$1_suffix', [], [])
	composer.draft.textarea.set_cursor('@src '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
	assert_composer_snapshot('file_popup_ignores_shell_positional_parameter', &composer, 100)
}

fn test_file_popup_ignores_bare_shell_parameter_with_matching_skill_snapshot() {
	mut composer := new_test_composer()
	name := '_tool'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('@src  \$_', [], [])
	composer.draft.textarea.set_cursor('@src '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
	assert_composer_snapshot('file_popup_ignores_bare_shell_parameter_with_matching_skill', &composer, 100)
}

fn test_file_popup_ignores_definite_shell_parameters_with_matching_skills() {
	for query, skill_name in {
		'12': '12factor'
		'-':  '-tool'
	} {
		mut composer := new_test_composer()
		composer.set_skill_mentions([rust_test_skill_metadata(&skill_name)])
		composer.set_text_content('@src  \$${query}', [], [])
		composer.draft.textarea.set_cursor('@src '.len)
		composer.sync_popups()
		assert composer.popups.active.kind == .file
	}
}

fn test_skill_popup_accepts_loaded_hyphen_leading_skill_name() {
	mut composer := new_test_composer()
	name := '-tool'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$-t', [], [])
	composer.draft.textarea.set_cursor('\$-t'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected -tool selection') }
	assert mention.insert_text == '\$-tool'
}

fn test_file_popup_ignores_unbindable_qualified_skill_snapshot() {
	mut composer := new_test_composer()
	name := '1plugin:deploy'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('@src  \$1plugin:d', [], [])
	composer.draft.textarea.set_cursor('@src '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
	assert_composer_snapshot('file_popup_ignores_unbindable_qualified_skill', &composer, 100)
}

fn test_skill_popup_preserves_normal_target_after_ambiguous_probe_snapshot() {
	mut composer := new_test_composer()
	name := 'plugin:deploy'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$1x  \$plugin:d', [], [])
	composer.draft.textarea.set_cursor('\$1x '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected qualified skill selection') }
	assert mention.insert_text == '\$plugin:deploy'
	assert_composer_snapshot('skill_popup_preserves_normal_target_after_ambiguous_probe', &composer, 100)
}

fn test_mention_target_prebuilds_catalog_only_for_ambiguous_query() {
	mut composer := new_test_composer()
	name := '1password'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$normal', [], [])
	composer.draft.textarea.set_cursor('\$normal'.len)
	normal := composer.current_mention_target() or { panic('expected normal mention target') }
	assert normal.prebuilt_mentions == none
	composer.set_text_content('\$1p', [], [])
	composer.draft.textarea.set_cursor('\$1p'.len)
	ambiguous := composer.current_mention_target() or { panic('expected ambiguous mention target') }
	mentions := ambiguous.prebuilt_mentions or { panic('expected prebuilt ambiguous catalog') }
	assert mentions.map(it.display_name) == ['1password']
}

fn test_skill_popup_accepts_digit_leading_skill_snapshot() {
	mut composer := new_test_composer()
	name := '1password'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$1p', [], [])
	composer.draft.textarea.set_cursor('\$1p'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	assert_composer_snapshot('skill_popup_accepts_digit_leading_skill', &composer, 100)
}

fn test_skill_popup_does_not_fuzzy_match_shell_variable_snapshot() {
	mut composer := new_test_composer()
	name := 'home'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$HOME', [], [])
	composer.draft.textarea.set_cursor('\$HOME'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .none
	assert_composer_snapshot('skill_popup_does_not_fuzzy_match_shell_variable', &composer, 100)
}

fn test_skill_popup_preserves_loaded_shell_like_skill_at_separator() {
	mut composer := new_test_composer()
	one := '1password'
	two := 'rustdoc'
	composer.set_skill_mentions([rust_test_skill_metadata(&one), rust_test_skill_metadata(&two)])
	composer.set_text_content('\$1p  \$rustdoc', [], [])
	composer.draft.textarea.set_cursor('\$1p '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected 1password selection') }
	assert mention.insert_text == '\$1password'
}

fn test_skill_popup_accepts_lowercase_skill_named_like_env_var() {
	mut composer := new_test_composer()
	name := 'home'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$home', [], [])
	composer.draft.textarea.set_cursor('\$home'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected home skill selection') }
	assert mention.insert_text == '\$home'
}

fn test_legacy_file_popup_falls_back_when_right_skill_is_unavailable() {
	mut composer := new_test_composer()
	composer.set_text_content('@src  \$missing', [], [])
	composer.draft.textarea.set_cursor('@src '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
}

fn test_unified_popup_falls_back_when_right_skill_is_unavailable() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	composer.set_text_content('@src  \$missing', [], [])
	composer.draft.textarea.set_cursor('@src '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .mention_v2
}

fn test_skill_popup_falls_back_when_right_at_mention_is_bound() {
	mut composer := new_test_composer()
	name := 'old'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content_with_mention_bindings('\$old  @bound', [], [], [MentionBinding{
		sigil:   `@`
		mention: 'bound'
		path:    'plugin://bound@test'
	}])
	composer.draft.textarea.set_cursor('\$old '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected old skill selection') }
	assert mention.insert_text == '\$old'
}

fn test_legacy_popup_prefers_right_at_token_over_left_skill() {
	mut composer := new_test_composer()
	name := 'old'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$old  @new', [], [])
	composer.draft.textarea.set_cursor('\$old  '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
}

fn test_unified_popup_prefers_right_skill_over_left_at_token() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	name := 'new'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('@old  \$new', [], [])
	composer.draft.textarea.set_cursor('@old  '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .skill
}

fn test_skill_popup_closes_at_plain_text_after_whitespace() {
	mut composer := new_test_composer()
	name := 'old'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$old word', [], [])
	composer.draft.textarea.set_cursor('\$old '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .none
}

fn test_skill_popup_closes_between_spaces_before_plain_text_snapshot() {
	mut composer := new_test_composer()
	name := 'old'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	composer.set_text_content('\$old  word', [], [])
	composer.draft.textarea.set_cursor('\$old '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .none
	assert_composer_snapshot('skill_popup_closes_between_spaces_before_plain_text', &composer, 100)
}

fn test_typing_empty_skill_prefix_before_existing_skill_starts_new_mention() {
	inserted := '\$'
	assert_typed_skill_prefix_starts_new_mention(&inserted)
}

fn test_typing_partial_skill_prefix_before_existing_skill_starts_new_mention() {
	inserted := '\$r'
	assert_typed_skill_prefix_starts_new_mention(&inserted)
}

fn test_set_skill_mentions_refreshes_open_mention_popup() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('\$', [], [])
	assert composer.popups.active.kind == .none
	composer.set_skill_mentions([skill_metadata.SkillMetadata{
		name:        'codex'
		description: 'Primary personal Codex repo skill.'
		path:        '/tmp/skill/SKILL.md'
		enabled:     true
	}])
	assert composer.popups.active.kind == .skill
	mention := composer.popups.active.skill.selected_mention() or { panic('expected skill mention') }
	assert mention.insert_text == '\$codex'
	assert (mention.path or { panic('expected skill path') }) == '/tmp/skill/SKILL.md'
}

fn test_mention_items_keep_direct_skills_and_apps_with_unified_mentions() {
	mut composer := ChatComposer.new(true, app_event_sender.AppEventSender{}, false, owned_composer_test_string('Ask Codex to do anything'), false)
	composer.set_connectors_enabled(true)
	composer.set_text_content('\$goog', [], [])
	composer.set_skill_mentions([skill_metadata.SkillMetadata{
		name:        'google-calendar:availability'
		description: 'Find availability and plan event changes'
		interface:   skill_metadata.SkillInterface{ display_name: 'Google Calendar' }
		path:        '/tmp/repo/google-calendar/SKILL.md'
		scope:       .repo
		enabled:     true
		plugin_id:   'google-calendar@debug'
	}])
	composer.set_plugin_mentions([codex_plugin.PluginCapabilitySummary{
		config_name:       'google-calendar@debug'
		display_name:      'Google Calendar'
		description:       'Connect Google Calendar for scheduling, availability, and event management.'
		has_skills:        true
		mcp_server_names:  ['google-calendar']
		app_connector_ids: ['google_calendar']
	}])
	composer.set_connector_mentions(app_event.ConnectorsSnapshot{
		connectors: [codex_connectors.AppInfo{
			id:            'google_calendar'
			name:          'Google Calendar'
			description:   'Look up events and availability'
			is_accessible: true
			is_enabled:    true
		}]
	})
	mentions := composer.mention_items()
	assert mentions.len == 3
	assert mentions[0].category_tag or { '' } == '[Skill]'
	assert mentions[0].path or { '' } == '/tmp/repo/google-calendar/SKILL.md'
	assert mentions[0].display_name == 'Google Calendar'
	assert mentions[1].category_tag or { '' } == '[Plugin]'
	assert mentions[1].path or { '' } == 'plugin://google-calendar@debug'
	assert mentions[2].category_tag or { '' } == '[App]'
	assert mentions[2].path or { '' } == 'app://google_calendar'
	composer.set_mentions_v2_enabled(true)
	unified := composer.mention_items()
	assert unified.map([it.insert_text, it.path or { '' }]) == [
		['\$google-calendar:availability', '/tmp/repo/google-calendar/SKILL.md'],
		['\$google-calendar', 'app://google_calendar'],
	]
}

fn test_plugin_mention_popup_snapshot() {
	mut composer := new_test_composer()
	composer.set_text_content('\$sa', [], [])
	name := 'sample'
	description := 'Plugin that includes the Figma MCP server and Skills for common workflows'
	plugin := codex_plugin.PluginCapabilitySummary{
		...rust_test_plugin_summary(&name, &description)
		display_name: 'Sample Plugin'
	}
	composer.set_plugin_mentions([plugin])
	assert composer.popups.active.kind == .skill
	selected := composer.popups.active.skill.selected_mention() or { panic('selected plugin') }
	assert selected.insert_text == '\$sample'
	assert_composer_snapshot('plugin_mention_popup', &composer, 100)
}

fn test_default_unified_mention_popup_snapshot() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled(true)
	mut skills := []skill_metadata.SkillMetadata{}
	for name, plugin_id in {
		'sample-tools:search': 'sample@test'
		'sample:summarize':    'sample@test'
		'sample:notes':        ''
		'sample:other':        'sample@other-marketplace'
	} {
		mut skill := rust_test_skill_metadata(&name)
		if plugin_id.len > 0 {
			skill = skill_metadata.SkillMetadata{ ...skill, plugin_id: plugin_id }
		}
		skills << skill
	}
	composer.set_skill_mentions(skills)
	composer.set_text_content('@sa', [], [])
	composer.set_plugin_mentions([codex_plugin.PluginCapabilitySummary{
		config_name:      'sample@test'
		display_name:     'Sample Plugin'
		plugin_namespace: 'sample'
		description:      'Plugin with skills and an MCP server'
		has_skills:       true
		mcp_server_names: ['sample']
	}])
	assert composer.popups.active.kind == .mention_v2
	assert composer.popups.active.mention_v2.items.any(it.path or { '' } == 'plugin://sample@test')
	assert_composer_snapshot('default_unified_mention_popup', &composer, 100)
}

fn test_task_mention_popup_and_selected_composer_snapshots() {
	for selected in [false, true] {
		mut composer := new_test_composer()
		composer.set_mentions_v2_enabled(true)
		composer.set_task_mentions_enabled(true)
		query := 'migr'
		composer.set_text_content('@${query}', [], [])
		composer.on_task_search_result(&query, [
			task_mentions.TaskMention{
				thread_id: 'task-123'
				title:     'Review database migration'
				cwd:       '/workspace/project'
				snippet:   'database migration'
			},
			task_mentions.TaskMention{
				thread_id: 'task-456'
				title:     'migration'
				cwd:       '/another/project'
				snippet:   'migration'
			},
		])
		assert composer.popups.active.kind == .mention_v2
		assert composer.popups.active.mention_v2.items.len == 2
		if selected {
			composer.handle_key_event(composer_test_key(.enter))
			bindings := composer.mention_bindings()
			assert bindings.len == 1
			assert bindings[0].mention == 'Review database migration'
			assert bindings[0].path == 'thread://task-123'
			assert (composer.task_mentions or { []task_mentions.TaskMention{} }).len == 0
			area := rat_layout.Rect{ width: 40, height: 5 }
			mut buffer := rat_buffer.Buffer{}
			composer.render(area, mut buffer)
			assert composer_buffer_cell(&buffer, 2, 1).style.fg == some_color(.cyan)
		}
		assert_composer_snapshot(if selected {
			'task_mention_selected_composer'
		} else {
			'task_mention_popup'
		}, &composer, 100)
	}
}

fn test_task_mention_titles_are_normalized_and_bounded_before_insertion() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled(true)
	composer.set_task_mentions_enabled(true)
	query := 'task'
	composer.set_text_content('@${query}', [], [])
	title := 'task\n\t${'a'.repeat(154)}é${'é'.repeat(200)}'
	composer.on_task_search_result(&query, [task_mentions.TaskMention{
		thread_id: 'task-123'
		title:     title
		cwd:       '/workspace/project'
	}])
	composer.handle_key_event(composer_test_key(.enter))
	bindings := composer.mention_bindings()
	assert bindings.len == 1
	assert bindings[0].mention == 'task ${'a'.repeat(154)}é'
	assert bindings[0].path == 'thread://task-123'
	assert bindings[0].mention.runes().len == 160
	popup_text := '@task'
	composer.draft.textarea.set_text_clearing_elements(&popup_text)
	composer.sync_popups()
	composer.on_task_search_result(&query, [task_mentions.TaskMention{
		thread_id: 'task-123'
		title:     title
		cwd:       '/workspace/project'
	}])
	assert composer.popups.active.kind == .mention_v2
	assert composer.popups.active.mention_v2.selected() != none
	history := HistoryEntry.new('[@sample](plugin://sample@test) @sample [@sample](thread://task-123)x')
	composer.set_text_content_with_mention_bindings(history.text, history.text_elements, [], history.mention_bindings)
	restored := composer.mention_bindings()
	assert restored == [MentionBinding{
		sigil:   `@`
		mention: 'sample'
		path:    'plugin://sample@test'
	}, MentionBinding{
		sigil:   `@`
		mention: 'sample'
		path:    'thread://task-123'
	}]
	snapshots := composer.draft.textarea.text_element_snapshots()
	assert snapshots[1].start == '@sample @sample '.len
}

fn test_bare_unified_mention_resets_an_inherited_file_search() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	at := '@'
	composer.insert_str(&at)
	assert composer.app_event_tx.events.last().kind == .start_file_search
	assert composer.app_event_tx.events.last().file_search_query == ''
	s := 's'
	composer.insert_str(&s)
	assert composer.app_event_tx.events.last().kind == .start_file_search
	assert composer.app_event_tx.events.last().file_search_query == 's'
}

fn test_reopening_identical_unified_mention_restarts_file_search() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	composer.set_text_content('@foo @foo', [], [])
	composer.draft.textarea.set_cursor('@f'.len)
	composer.sync_popups()
	assert composer.app_event_tx.events.filter(it.kind == .start_file_search).map(it.file_search_query) == ['',
		'foo']
	composer.on_file_search_result('foo', [])
	composer.handle_key_event(composer_test_key(.escape))
	assert composer.popups.active.kind == .none
	composer.app_event_tx.events.clear()
	composer.draft.textarea.set_cursor('@foo @foo'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .mention_v2
	assert composer.app_event_tx.events.filter(it.kind == .start_file_search).map(it.file_search_query) == ['',
		'foo']
}

fn test_restored_unified_mention_restarts_file_search() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	composer.app_event_tx.events.clear()
	composer.set_text_content('@foo', [], [])
	assert composer.popups.active.kind == .mention_v2
	assert composer.app_event_tx.events.filter(it.kind == .start_file_search).map(it.file_search_query) == ['',
		'foo']
}

fn test_mention_popup_type_prefixes_snapshot() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled(true)
	composer.set_connectors_enabled(true)
	composer.set_text_content('\$goog', [], [])
	composer.set_skill_mentions([skill_metadata.SkillMetadata{
		name:        'google-calendar-skill'
		description: 'Find availability and plan event changes'
		interface:   skill_metadata.SkillInterface{ display_name: 'Google Calendar' }
		path:        '/tmp/repo/google-calendar/SKILL.md'
		scope:       .repo
		enabled:     true
	}])
	composer.set_plugin_mentions([codex_plugin.PluginCapabilitySummary{
		config_name:  'google-calendar@debug'
		display_name: 'Google Calendar'
		description:  'Connect Google Calendar'
	}])
	composer.set_connector_mentions(app_event.ConnectorsSnapshot{
		connectors: [codex_connectors.AppInfo{
			id:            'google_calendar'
			name:          'Google Calendar'
			description:   'Look up events and availability'
			is_accessible: true
			is_enabled:    true
		}]
	})
	items := composer.mention_items()
	assert items.map(it.category_tag or { '' }) == ['[Skill]', '[App]']
	assert_composer_snapshot('mention_popup_type_prefixes', &composer, 72)
}

fn test_set_connector_mentions_excludes_disabled_apps_from_mention_popup() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_connectors_enabled( /* enabled */
	true)
	composer.set_text_content('\$', [], [])
	composer.set_connector_mentions(app_event.ConnectorsSnapshot{
		connectors: [codex_connectors.AppInfo{
			id:            'connector_1'
			name:          'Notion'
			description:   'Workspace docs'
			is_accessible: true
			is_enabled:    false
		}]
	})
	assert composer.popups.active.kind == .none
}

fn test_shortcut_overlay_persists_while_task_running() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.handle_key_event(composer_test_char(`?`))
	assert composer.footer.mode == .shortcut_overlay
	composer.set_task_running( /* running */
	true)
	assert composer.footer.mode == .shortcut_overlay
	assert composer.footer_mode() == .shortcut_overlay
}

fn test_current_at_token_basic_cases() {
	// Valid @ tokens
	assert_current_at_token_case('@hello', 3, true, 'hello')
	assert_current_at_token_case('@file.txt', 4, true, 'file.txt')
	assert_current_at_token_case('hello @world test', 8, true, 'world')
	assert_current_at_token_case('@test123', 5, true, 'test123')
	// Unicode examples
	assert_current_at_token_case('@İstanbul', 3, true, 'İstanbul')
	assert_current_at_token_case('@testЙЦУ.rs', 8, true, 'testЙЦУ.rs')
	assert_current_at_token_case('@诶', 2, true, '诶')
	assert_current_at_token_case('@👍', 2, true, '👍')
	// Invalid cases (should return None)
	assert_current_at_token_case('hello', 2, false, '')
	assert_current_at_token_case('@', 1, true, '')
	assert_current_at_token_case('@ hello', 2, false, '')
	assert_current_at_token_case('test @ world', 6, false, '')
}

fn test_current_at_token_cursor_positions() {
	// Different cursor positions within a token
	assert_current_at_token_case('@test', 0, true, 'test')
	assert_current_at_token_case('@test', 1, true, 'test')
	assert_current_at_token_case('@test', 5, true, 'test')
	// Multiple tokens - cursor determines which token
	assert_current_at_token_case('@file1 @file2', 0, true, 'file1')
	assert_current_at_token_case('@file1 @file2', 8, true, 'file2')
	// Edge cases
	assert_current_at_token_case('@', 0, true, '')
	assert_current_at_token_case('@a', 2, true, 'a')
	assert_current_at_token_case('', 0, false, '')
}

fn test_current_at_token_whitespace_boundaries() {
	// Space boundaries
	assert_current_at_token_case('aaa@aaa', 4, false, '')
	assert_current_at_token_case('aaa @aaa', 5, true, 'aaa')
	assert_current_at_token_case('test @file.txt', 7, true, 'file.txt')
	// Full-width space boundaries
	assert_current_at_token_case('test　@İstanbul', 8, true, 'İstanbul')
	assert_current_at_token_case('@ЙЦУ　@诶', 10, true, '诶')
	// Tab and newline boundaries
	assert_current_at_token_case('test\t@file', 6, true, 'file')
}

fn test_current_at_token_tracks_tokens_with_second_at() {
	input := 'npx -y @kaeawc/auto-mobile@latest'
	token_start := input.index('@kaeawc') or { panic('scoped npm package must be present') }
	version_at := input.last_index('@latest') or { panic('version suffix must be present') }
	for cursor in [token_start, token_start + 8, version_at, input.len] {
		assert_current_at_token_case(input, cursor, true, 'kaeawc/auto-mobile@latest')
	}
}

fn test_current_at_token_allows_file_queries_with_second_at() {
	input := '@icons/icon@2x.png'
	version_at := input.last_index('@2x') or { panic('second @ must be present') }
	for cursor in [0, 8, version_at, input.len] {
		mut textarea := TextArea.new()
		textarea.insert_str(&input)
		textarea.set_cursor(cursor)
		result := ChatComposer.current_at_token(&textarea)
		assert result != none
	}
}

fn test_current_at_token_ignores_mid_word_at() {
	input := 'foo@bar'
	at_pos := input.index('@') or { panic('@ must be present') }
	assert_current_at_token_case(input, at_pos, false, '')
	assert_current_at_token_case(input, input.len, false, '')
}

fn test_set_text_content_rebinds_at_sigiled_mentions() {
	mut composer := new_test_composer()
	bindings := [
		MentionBinding{ sigil: `@`, mention: 'figma', path: '/tmp/user/figma/SKILL.md' },
	]
	composer.set_text_content_with_mention_bindings('@figma please', [], [], bindings.clone())
	assert composer.mention_bindings() == bindings
}

fn test_set_text_content_rebinds_matching_sigil_only() {
	mut composer := new_test_composer()
	bindings := [MentionBinding{ sigil: `$`, mention: 'figma', path: 'app://figma' }]
	composer.set_text_content_with_mention_bindings('@figma then \$figma', [], [], bindings.clone())
	elements := composer.current_mention_elements()
	assert elements.len == 1
	assert elements[0].sigil == `$`
	assert elements[0].mention == 'figma'
	assert composer.mention_bindings() == bindings
}

fn test_set_text_content_rebinds_both_sigil_forms() {
	mut composer := new_test_composer()
	bindings := [
		MentionBinding{ sigil: `@`, mention: 'figma', path: 'plugin://figma@test' },
		MentionBinding{ sigil: `$`, mention: 'figma', path: 'app://figma' },
	]
	composer.set_text_content_with_mention_bindings('@figma then \$figma', [], [], bindings.clone())
	elements := composer.current_mention_elements()
	assert elements.len == 2
	assert elements[0].sigil == `@`
	assert elements[0].mention == 'figma'
	assert elements[1].sigil == `$`
	assert elements[1].mention == 'figma'
	assert composer.mention_bindings() == bindings
}

fn test_set_text_content_rebinds_at_mentions_after_email_substrings() {
	mut composer := new_test_composer()
	text := 'foo@sample.com then @sample'
	mention_start := text.last_index('@sample') or { panic('expected mention token') }
	bindings := [
		MentionBinding{ sigil: `@`, mention: 'sample', path: 'plugin://sample@test' },
	]
	composer.set_text_content_with_mention_bindings(text, [], [], bindings.clone())
	// Fix coverage: only the plaintext `@sample` should be atomic; the email substring stays editable.
	snapshots := composer.draft.textarea.text_element_snapshots()
	assert snapshots.len == 1
	assert snapshots[0].start == mention_start
	assert snapshots[0].end == mention_start + '@sample'.len
	assert composer.mention_bindings() == bindings
}

fn test_set_text_content_rebinds_at_mentions_after_punctuation() {
	mut composer := new_test_composer()
	text := 'Please ask (@sample)'
	mention_start := text.index('@sample') or { panic('expected mention token') }
	bindings := [
		MentionBinding{ sigil: `@`, mention: 'sample', path: 'plugin://sample@test' },
	]
	composer.set_text_content_with_mention_bindings(text, [], [], bindings.clone())
	snapshots := composer.draft.textarea.text_element_snapshots()
	assert snapshots.len == 1
	assert snapshots[0].start == mention_start
	assert snapshots[0].end == mention_start + '@sample'.len
	assert composer.mention_bindings() == bindings
}

fn test_bound_at_mentions_do_not_block_arrow_navigation() {
	mut composer := new_test_composer()
	composer.set_text_content_with_mention_bindings('go @figma now', [], [], [MentionBinding{
		sigil:   `@`
		mention: 'figma'
		path:    'plugin://figma@debug'
	}])
	composer.set_current_cursor('go'.len)
	composer.handle_key_event(composer_test_key(.right))
	assert composer.current_cursor() == 'go'.len + 1
	assert !composer.popup_active()
	composer.handle_key_event(composer_test_key(.right))
	assert composer.current_cursor() == 'go @figma'.len
	assert !composer.popup_active()
	composer.handle_key_event(composer_test_key(.left))
	assert composer.current_cursor() == 'go '.len
	composer.handle_key_event(composer_test_key(.left))
	assert composer.current_cursor() == 'go'.len
}

fn test_restored_bound_at_mentions_do_not_open_mention_popup() {
	for index, text in ['@sample', 'Please ask @sample.'] {
		mut composer := new_test_composer()
		name := 'sample'
		description := 'sample plugin'
		composer.set_plugin_mentions([rust_test_plugin_summary(&name, &description)])
		composer.set_text_content_with_mention_bindings(text.clone(), [], [], [MentionBinding{
			sigil:   `@`
			mention: 'sample'
			path:    'plugin://sample@test'
		}])
		if index == 1 {
			composer.move_cursor_to_end()
		}
		assert !composer.popup_active()
		result, consumed := composer.handle_key_event(composer_test_key(.enter))
		assert consumed
		assert result.kind == .submitted
		assert result.text == text
	}
}

fn test_enter_submits_when_file_popup_has_no_selection() {
	mut composer := new_test_composer()
	input := 'npx -y @kaeawc/auto-mobile@latest'
	composer.insert_str(&input)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
	result, consumed := composer.handle_key_event(composer_test_key(.enter))
	assert consumed
	assert result.kind == .submitted
	assert result.text == input
}

fn test_enter_submits_when_unified_mention_popup_has_no_selection() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled(true)
	input := 'npx -y @kaeawc/auto-mobile@latest'
	composer.insert_str(&input)
	composer.sync_popups()
	assert composer.popups.active.kind == .mention_v2
	result, consumed := composer.handle_key_event(composer_test_key(.enter))
	assert consumed
	assert result.kind == .submitted
	assert result.text == input
}

// Behavior: if the ASCII path has a pending first char (flicker suppression) and a non-ASCII
// char arrives next, the pending ASCII char should still be preserved and the overall input
// should submit normally (i.e. we should not misclassify this as a paste burst).
fn test_ascii_prefix_survives_non_ascii_followup() {
	mut composer := new_test_composer()
	composer.handle_key_event(composer_test_char(`1`))
	assert composer.is_in_paste_burst()
	composer.handle_key_event(composer_test_char(`あ`))
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '1あ'
}

// Behavior: a single non-ASCII char should be inserted immediately (IME-friendly) and should
// not create any paste-burst state.
fn test_non_ascii_char_inserts_immediately_without_burst_state() {
	mut composer := new_test_composer()
	composer.handle_key_event(composer_test_char(`あ`))
	assert composer.current_text() == 'あ'
	assert !composer.is_in_paste_burst()
}

// Behavior: while we're capturing a paste-like burst, Enter should be treated as a newline
// within the burst (not as "submit"), and the whole payload should flush as one paste.
fn test_non_ascii_burst_buffers_enter_and_flushes_multiline() {
	mut composer := new_test_composer()
	composer.draft.paste_burst.begin_with_retro_grabbed('', time.now().unix_milli())
	for key_event in [composer_test_char(`你`), composer_test_char(`好`), composer_test_key(.enter),
		composer_test_char(`h`), composer_test_char(`i`)] {
		composer.handle_key_event(key_event)
	}
	assert composer.current_text() == ''
	assert flush_after_paste_burst(mut composer)
	assert composer.current_text() == '你好\nhi', 'actual=${composer.current_text()}'
}

// Behavior: a paste-like burst may include a full-width/ideographic space (U+3000). It should
// still be captured as a single paste payload and preserve the exact Unicode content.
fn test_non_ascii_burst_preserves_ideographic_space_and_ascii() {
	mut composer := new_test_composer()
	composer.draft.paste_burst.begin_with_retro_grabbed('', time.now().unix_milli())
	for key_event in [composer_test_char(`你`), composer_test_char(`　`), composer_test_char(`好`),
		composer_test_key(.enter), composer_test_char(`h`), composer_test_char(`i`)] {
		composer.handle_key_event(key_event)
	}
	assert composer.current_text() == ''
	assert flush_after_paste_burst(mut composer)
	assert composer.current_text() == '你　好\nhi', 'actual=${composer.current_text()}'
}

// Behavior: a large multi-line payload containing both non-ASCII and ASCII (e.g. "UTF-8",
// "Unicode") should be captured as a single paste-like burst, and Enter key events should
// become `\n` within the buffered content.
fn test_non_ascii_burst_buffers_large_multiline_mixed_ascii_and_unicode() {
	payload := '天地玄黄 宇宙洪荒\n日月盈昃 辰宿列张\n寒来暑往 秋收冬藏\n\n你好世界 编码测试\n汉字处理 UTF-8\n终端显示 正确无误\n\n风吹竹林 月照大江\n白云千载 青山依旧\n程序员 与 Unicode 同行'
	mut composer := new_test_composer()
	// Force an active burst so the test doesn't depend on timing heuristics.
	composer.draft.paste_burst.begin_with_retro_grabbed('', time.now().unix_milli())
	for ch in payload.runes() {
		if ch == `\n` {
			composer.handle_key_event(composer_test_key(.enter))
		} else {
			composer.handle_key_event(composer_test_char(ch))
		}
	}
	assert composer.current_text() == ''
	assert flush_after_paste_burst(mut composer)
	assert composer.current_text() == payload, 'actual=${composer.current_text()}'
}

// Behavior: while a paste-like burst is active, Enter should not submit; it should insert a
// newline into the buffered payload and flush as a single paste later.
fn test_ascii_burst_treats_enter_as_newline_even_when_parent_owned() {
	for parent_owned in [false, true] {
		mut composer := new_test_composer()
		if parent_owned {
			composer.set_parent_owned_thread()
		}
		mut now_ms := time.now().unix_milli()
		composer.handle_input_basic_with_time(composer_test_char(`h`), now_ms)
		now_ms++
		composer.handle_input_basic_with_time(composer_test_char(`i`), now_ms)
		now_ms++
		result, _ := composer.handle_submission_with_time(false, now_ms)
		assert result.kind == .no_result
		for ch in 'there'.runes() {
			now_ms++
			composer.handle_input_basic_with_time(composer_test_char(ch), now_ms)
		}
		assert composer.current_text() == ''
		assert composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_active_flush_delay() + 1)
		assert composer.current_text() == 'hi\nthere', 'actual=${composer.current_text()}'
	}
}

// Behavior: startup-pending submissions are queued immediately, so Enter should flush any
// buffered burst text into that queued message instead of turning into a draft newline.
fn test_queued_submission_flushes_ascii_burst_instead_of_inserting_newline() {
	mut composer := new_test_composer()
	mut now_ms := time.now().unix_milli()
	for ch in [`h`, `i`] {
		composer.handle_input_basic_with_time(composer_test_char(ch), now_ms)
		now_ms++
	}
	assert composer.is_in_paste_burst()
	result, _ := composer.handle_submission_with_time(true, now_ms)
	assert result.kind == .queued
	assert result.text == 'hi'
	assert result.action == .plain
	assert result.pending_pastes.len == 0
	assert composer.current_text() == ''
	assert !composer.is_in_paste_burst()
}

// Behavior: even if Enter suppression would normally be active for a burst, Enter should
// still dispatch a built-in slash command when the first line begins with `/`.
fn test_slash_context_enter_ignores_paste_burst_enter_suppression() {
	mut composer := new_test_composer()
	text := '/diff'
	composer.draft.textarea.set_text_clearing_elements(&text)
	composer.move_cursor_to_end()
	composer.draft.paste_burst.begin_with_retro_grabbed('', time.now().unix_milli())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command == .diff
}

// Behavior: if a burst is buffering text and the user presses a non-char key, flush the
// buffered burst *before* applying that key so the buffer cannot get stuck.
fn test_non_char_key_flushes_active_burst_before_input() {
	mut composer := new_test_composer()
	// Force an active burst so we can deterministically buffer characters without relying on
	// timing.
	composer.draft.paste_burst.begin_with_retro_grabbed('', time.now().unix_milli())
	composer.handle_key_event(composer_test_char(`h`))
	composer.handle_key_event(composer_test_char(`i`))
	assert composer.current_text() == ''
	assert composer.is_in_paste_burst()
	composer.handle_key_event(composer_test_key(.left))
	assert composer.current_text() == 'hi'
	assert composer.current_cursor() == 1
	assert !composer.is_in_paste_burst()
}

// Behavior: enabling `disable_paste_burst` flushes any held first character (flicker
// suppression) and then inserts subsequent chars immediately without creating burst state.
fn test_disable_paste_burst_flushes_pending_first_char_and_inserts_immediately() {
	mut composer := new_test_composer()
	// First ASCII char is normally held briefly. Flip the config mid-stream and ensure the
	// held char is not dropped.
	composer.handle_key_event(composer_test_char(`a`))
	assert composer.is_in_paste_burst()
	assert composer.current_text() == ''
	composer.set_disable_paste_burst( /* disabled */
	true)
	assert composer.current_text() == 'a'
	assert !composer.is_in_paste_burst()
	composer.handle_key_event(composer_test_char(`b`))
	assert composer.current_text() == 'ab'
	assert !composer.is_in_paste_burst()
}

// Behavior: a small explicit paste inserts text directly (no placeholder), and the submitted
// text matches what is visible in the textarea.
fn test_handle_paste_small_inserts_text() {
	mut composer := new_test_composer()
	pasted := '_count_r\x1b[13;2:3uows\tindent\n\x00two\x7f'
	assert composer.handle_paste(pasted)
	assert composer.current_text() == '_count_rows\tindent\ntwo'
	assert composer.pending_pastes().len == 0
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '_count_rows\tindent\ntwo'
}

fn test_empty_enter_returns_none() {
	mut composer := new_test_composer()
	// Ensure composer is empty and press Enter.
	assert composer.current_text() == ''
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
}

// Behavior: a large explicit paste inserts a placeholder into the textarea, stores the full
// content in `pending_pastes`, and expands the placeholder to the full content on submit.
fn test_handle_paste_large_uses_placeholder_and_replaces_on_submit() {
	mut composer := new_test_composer()
	large := 'x'.repeat(large_paste_char_threshold + 10)
	assert composer.handle_paste(large.clone())
	placeholder := '[Pasted Content ${large_paste_char_threshold + 10} chars]'
	assert composer.current_text() == placeholder
	pending := composer.pending_pastes()
	assert pending.len == 1
	assert pending[0].placeholder == placeholder
	assert pending[0].actual == large
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == large
	assert composer.pending_pastes().len == 0
}

fn test_submit_at_character_limit_succeeds() {
	mut composer := new_test_composer()
	input := 'x'.repeat(user_input.max_user_input_text_chars)
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == input
}

fn test_oversized_submit_reports_error_and_restores_draft() {
	mut composer := new_test_composer()
	input := 'x'.repeat(user_input.max_user_input_text_chars + 1)
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.current_text() == input
	assert composer.app_event_tx.events.any(it.kind == .insert_history_cell
		&& app_event_history_message(it).contains(user_input_too_large_message(input.runes().len)))
}

// Behavior: editing that removes a paste placeholder should also clear the associated
// `pending_pastes` entry so it cannot be submitted accidentally.
fn test_oversized_queued_submission_reports_error_and_restores_draft() {
	mut composer := new_test_composer()
	composer.set_queue_submissions(true)
	input := 'x'.repeat(user_input.max_user_input_text_chars + 1)
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.current_text() == input
	assert composer.app_event_tx.events.any(it.kind == .insert_history_cell)
}

// Behavior: editing that removes a paste placeholder should also clear the associated
// `pending_pastes` entry so it cannot be submitted accidentally.
fn test_edit_clears_pending_paste() {
	mut composer := new_test_composer()
	large := 'y'.repeat(large_paste_char_threshold + 1)
	composer.handle_paste(large)
	assert composer.draft.pending_pastes.len == 1
	// Any edit that removes the placeholder should clear pending_paste
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.draft.pending_pastes.len == 0
}

fn test_ui_snapshots() {
	for case_name in ['empty', 'small', 'large', 'multiple_pastes', 'backspace_after_pastes'] {
		// Create a fresh composer for each test case
		mut composer := new_test_composer()
		match case_name {
			'small' { composer.handle_paste('short') }
			'large' { composer.handle_paste('z'.repeat(large_paste_char_threshold + 5)) }
			'multiple_pastes' {
				// First large paste
				composer.handle_paste('x'.repeat(large_paste_char_threshold + 3))
				// Second large paste
				composer.handle_paste('y'.repeat(large_paste_char_threshold + 7))
				// Small paste
				composer.handle_paste(' another short paste')
			}
			'backspace_after_pastes' {
				// Three large pastes
				composer.handle_paste('a'.repeat(large_paste_char_threshold + 2))
				composer.handle_paste('b'.repeat(large_paste_char_threshold + 4))
				composer.handle_paste('c'.repeat(large_paste_char_threshold + 6))
				// Move cursor to end and press backspace
				composer.draft.textarea.set_cursor(composer.draft.textarea.text().len)
				composer.handle_key_event(composer_test_key(.backspace))
			}
			else {}
		}
		mut buffer := rat_buffer.Buffer{}
		area := rat_layout.Rect{ width: 100, height: 10 }
		composer.render(area, mut buffer)
		expected := match case_name {
			'empty' {
				[
					'                                                                                                    ',
					'› Ask Codex to do anything                                                                          ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'  ? for shortcuts                                                                100% context left  ',
				]
			}
			'small' {
				[
					'                                                                                                    ',
					'› short                                                                                             ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                 100% context left  ',
				]
			}
			'large' {
				[
					'                                                                                                    ',
					'› [Pasted Content 1005 chars]                                                                       ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                 100% context left  ',
				]
			}
			'multiple_pastes' {
				[
					'                                                                                                    ',
					'› [Pasted Content 1003 chars][Pasted Content 1007 chars] another short paste                        ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                 100% context left  ',
				]
			}
			else {
				[
					'                                                                                                    ',
					'› [Pasted Content 1002 chars][Pasted Content 1004 chars]                                            ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                                    ',
					'                                                                                 100% context left  ',
				]
			}
		}
		assert composer_buffer_rows(&buffer, area) == expected, case_name
		if case_name == 'multiple_pastes' {
			assert composer.pending_pastes().len == 2
		} else if case_name == 'backspace_after_pastes' {
			assert composer.pending_pastes().len == 2
		}
	}
}

fn test_image_placeholder_snapshots() {
	mut single := new_test_composer()
	single.attach_image('/tmp/image1.png')
	assert single.current_text() == '[Image #1]'
	assert single.local_image_paths() == ['/tmp/image1.png']
	mut single_buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 100, height: 9 }
	single.render(area, mut single_buffer)
	assert composer_buffer_rows(&single_buffer, area) == [
		'                                                                                                    ',
		'› [Image #1]                                                                                        ',
		'                                                                                                    ',
		'                                                                                                    ',
		'                                                                                                    ',
		'                                                                                                    ',
		'                                                                                                    ',
		'                                                                                                    ',
		'                                                                                 100% context left  ',
	]

	mut multiple := new_test_composer()
	multiple.attach_image('/tmp/image1.png')
	multiple.attach_image('/tmp/image2.png')
	assert multiple.current_text() == '[Image #1][Image #2]'
	assert multiple.local_image_paths() == ['/tmp/image1.png', '/tmp/image2.png']
	mut multiple_buffer := rat_buffer.Buffer{}
	multiple.render(area, mut multiple_buffer)
	assert composer_buffer_rows(&multiple_buffer, area)[1] == '› [Image #1][Image #2]                                                                              '
}

fn test_remote_image_rows_snapshots() {
	urls := ['https://example.com/one.png', 'https://example.com/two.png']
	mut composer := new_test_composer()
	composer.set_remote_image_urls(urls.clone())
	composer.set_text_content('describe these', [], [])
	mut buffer := rat_buffer.Buffer{}
	composer.render(rat_layout.Rect{ width: 100, height: 10 }, mut buffer)
	assert buffer.lines[..2] == ['[Image #1]', '[Image #2]']

	composer.draft.textarea.set_cursor(0)
	composer.handle_key_event(composer_test_key(.up))
	selected_second := composer.attachments.selected_remote_image_index or {
		panic('remote selection')
	}
	assert selected_second == 1
	composer.handle_key_event(composer_test_key(.up))
	selected_first := composer.attachments.selected_remote_image_index or {
		panic('remote selection')
	}
	assert selected_first == 0
	composer.handle_key_event(composer_test_key(.delete))
	assert composer.remote_image_urls() == ['https://example.com/two.png']
}

fn test_slash_popup_model_first_for_mo_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Type "/mo" humanlike so paste-burst doesn’t interfere.
	type_chars_humanlike(mut composer, &[`/`, `m`, `o`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('mo') or { panic('no selected command') }).builtin == .model
	// Visual snapshot should show the slash popup with /model as the first entry.
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 5 }
	composer.render(area, mut buffer)
	rows := composer_buffer_rows(&buffer, area)
	assert rows == [
		'                                                            ',
		'› /mo                                                       ',
		'                                                            ',
		'                                                            ',
		'  /model  choose what model and reasoning effort to use     ',
	], '${rows}'
}

fn test_slash_popup_model_first_for_mo_logic() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `m`, `o`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('mo') or { panic("no selected command for '/mo'") }).command() == 'model'
}

fn test_slash_popup_resume_for_res_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Type "/res" humanlike so paste-burst doesn’t interfere.
	type_chars_humanlike(mut composer, &[`/`, `r`, `e`, `s`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('res') or { panic('no selected command') }).builtin == .resume
	// Snapshot should show /resume as the first entry for /res.
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 6 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                            ',
		'› /res                                                      ',
		'                                                            ',
		'                                                            ',
		'                                                            ',
		'  /resume  resume a saved chat                              ',
	]
}

fn test_slash_popup_archive_for_ar_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `a`, `r`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('ar') or { panic('no selected command') }).builtin == .archive
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 5 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                            ',
		'› /ar                                                       ',
		'                                                            ',
		'                                                            ',
		'  /archive  archive this session and exit                   ',
	]
}

fn test_slash_popup_resume_for_res_logic() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `r`, `e`, `s`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('res') or { panic("no selected command for '/res'") }).command() == 'resume'
}

fn test_slash_popup_pets_for_pet_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `p`, `e`, `t`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('pet') or { panic('no selected command') }).builtin == .pets
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 5 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                            ',
		'› /pet                                                      ',
		'                                                            ',
		'                                                            ',
		'  /pets  choose or hide the terminal pet                    ',
	]
}

fn test_slash_popup_pets_for_pet_logic() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `p`, `e`, `t`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('pet') or { panic("no selected command for '/pet'") }).command() == 'pets'
}

fn test_slash_popup_btw_for_bt_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `b`, `t`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('bt') or { panic('no selected command') }).builtin == .btw
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 5 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                            ',
		'› /bt                                                       ',
		'                                                            ',
		'                                                            ',
		'  /btw  start a side conversation in an ephemeral fork      ',
	]
}

fn test_slash_popup_btw_for_bt_logic() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `b`, `t`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('bt') or { panic("no selected command for '/bt'") }).command() == 'btw'
}

fn test_slash_popup_side_for_si_ui() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `s`, `i`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('si') or { panic('no selected command') }).builtin == .side
	mut buffer := rat_buffer.Buffer{}
	area := rat_layout.Rect{ width: 60, height: 5 }
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                                            ',
		'› /si                                                       ',
		'                                                            ',
		'                                                            ',
		'  /side  start a side conversation in an ephemeral fork     ',
	]
}

fn test_slash_popup_side_for_si_logic() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `s`, `i`])
	assert composer.popups.active.kind == .command
	assert (selected_popup_command('si') or { panic("no selected command for '/si'") }).command() == 'side'
}

fn test_service_tier_slash_command_dispatches_from_catalog_name() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_service_tier_commands_enabled( /* enabled */
	true)
	composer.set_service_tier_commands([ServiceTierCommand{
		id:          'priority'
		name:        'fast'
		description: 'Fastest inference with increased plan usage'
	}])
	type_chars_humanlike(mut composer, &[`/`, `f`, `a`, `s`, `t`])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .service_tier_command
	assert result.service_tier == ServiceTierCommand{
		id:          'priority'
		name:        'fast'
		description: 'Fastest inference with increased plan usage'
	}
}

fn test_slash_init_dispatches_command_and_does_not_submit_literal_text() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Type the slash command.
	type_chars_humanlike(mut composer, &[`/`, `i`, `n`, `i`, `t`])
	// Press Enter to dispatch the selected command.
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	// When a slash command is dispatched, the composer should return a
	// Command result (not submit literal text) and clear its textarea.
	assert result.kind == .command
	assert result.command.command() == 'init'
	assert composer.draft.textarea.is_empty(), 'composer should be cleared'
}

fn test_kill_buffer_persists_after_submit() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_steer_enabled(true)
	restore := 'restore me'
	composer.draft.textarea.insert_str(&restore)
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `k`
	}, terminal_event.KeyModifiers{ control: true }))
	assert composer.draft.textarea.is_empty()
	hello := 'hello'
	composer.draft.textarea.insert_str(&hello)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert composer.draft.textarea.is_empty()
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `y`
	}, terminal_event.KeyModifiers{ control: true }))
	assert composer.draft.textarea.text() == 'restore me'
}

fn test_kill_buffer_persists_after_slash_command_dispatch() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	restore := 'restore me'
	composer.draft.textarea.insert_str(&restore)
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `k`
	}, terminal_event.KeyModifiers{ control: true }))
	assert composer.draft.textarea.is_empty()
	diff := '/diff'
	composer.draft.textarea.insert_str(&diff)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command.command() == 'diff'
	assert composer.draft.textarea.is_empty()
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `y`
	}, terminal_event.KeyModifiers{ control: true }))
	assert composer.draft.textarea.text() == 'restore me'
}

fn test_slash_command_disabled_while_task_running_keeps_text() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_task_running( /* running */
	true)
	input := '/review these changes'
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == input
	assert composer.app_event_tx.events.any(it.kind == .insert_history_cell
		&& app_event_history_message(it).contains('disabled while a task is in progress')), 'expected error history cell to be sent'
}

fn test_enter_queues_when_queue_submissions_is_enabled() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_queue_submissions( /* queue_submissions */
	true)
	input := 'queued before session'
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .queued
	assert result.text == input
	assert result.text_elements.len == 0
	assert result.action == .plain
	assert result.pending_pastes.len == 0
}

fn test_tab_queues_slash_led_prompts_while_task_running_without_validation() {
	for input in ['/compact', '/review check regressions', '/fast', '/does-not-exist'] {
		assert_queued_slash(&input)
	}
}

fn test_remapped_submit_does_not_fall_back_to_enter() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	input := 'explain the change'
	composer.draft.textarea.set_text_clearing_elements(&input)
	composer.draft.textarea.set_cursor(input.len)
	mut keymap := tui_keymap.RuntimeKeymap.defaults()
	keymap.composer.submit = [
		key_hint.ctrl(terminal_event.KeyCode{ kind: .char_key, ch: `j` }),
	]
	composer.set_keymap_bindings(&keymap)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == 'explain the change\n'
}

fn test_remapped_queue_does_not_fall_back_to_tab() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_task_running( /* running */
	true)
	input := 'queue me'
	composer.draft.textarea.set_text_clearing_elements(&input)
	mut keymap := tui_keymap.RuntimeKeymap.defaults()
	keymap.composer.queue = [
		key_hint.ctrl(terminal_event.KeyCode{ kind: .char_key, ch: `q` }),
	]
	composer.set_keymap_bindings(&keymap)
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == input
}

fn test_remapped_history_search_does_not_fall_back_to_ctrl_r() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	mut keymap := tui_keymap.RuntimeKeymap.defaults()
	keymap.composer.history_search_previous = [key_hint.plain(terminal_event.KeyCode{
		kind: .function
		f:    2
	})]
	composer.set_keymap_bindings(&keymap)
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   `r`
	}, terminal_event.KeyModifiers{ control: true }))
	assert !composer.history_search_active()
	composer.handle_key_event(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .function
		f:    2
	}, terminal_event.KeyModifiers{}))
	assert composer.history_search_active()
}

fn test_tab_queues_leading_space_slash_as_plain_text_while_task_running() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_task_running( /* running */
	true)
	input := ' /does-not-exist'
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .queued
	assert result.text == '/does-not-exist'
	assert result.action == .plain
}

fn test_tab_queues_bang_shell_prompts_while_task_running_without_execution() {
	first_input := '!echo hi'
	first_expected := '!echo hi'
	assert_queued_shell(&first_input, &first_expected)
	second_input := '!'
	second_expected := '!'
	assert_queued_shell(&second_input, &second_expected)
	third_input := ' !echo hi'
	third_expected := '!echo hi'
	assert_queued_shell(&third_input, &third_expected)
}

fn test_slash_tab_completion_moves_cursor_to_end() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `c`])
	composer.handle_key_event(composer_test_key(.tab))
	assert composer.draft.textarea.text() == '/compact '
	assert composer.draft.textarea.cursor() == composer.draft.textarea.text().len
}

fn test_slash_tab_completion_wins_over_queueing_while_task_running() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_task_running( /* running */
	true)
	type_chars_humanlike(mut composer, &[`/`, `m`, `o`])
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == '/model '
	assert composer.draft.textarea.cursor() == composer.draft.textarea.text().len
}

fn test_slash_key_completes_selected_slash_command_as_text() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `m`])
	result, _ := composer.handle_key_event(composer_test_char(`/`))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == '/model '
	assert composer.draft.textarea.cursor() == composer.draft.textarea.text().len
}

fn test_slash_tab_then_enter_dispatches_builtin_command() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Type a prefix and complete with Tab, which inserts a trailing space
	// and moves the cursor beyond the '/name' token (hides the popup).
	type_chars_humanlike(mut composer, &[`/`, `d`, `i`])
	composer.handle_key_event(composer_test_key(.tab))
	assert composer.draft.textarea.text() == '/diff '
	// Press Enter: should dispatch the command, not submit literal text.
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command.command() == 'diff'
	assert composer.draft.textarea.is_empty()
}

fn test_slash_command_elementizes_on_space() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_collaboration_modes_enabled( /* enabled */
	true)
	type_chars_humanlike(mut composer, &[`/`, `p`, `l`, `a`, `n`, ` `])
	text := composer.draft.textarea.text()
	elements := composer.draft.textarea.text_elements()
	assert text == '/plan '
	assert elements.len == 1
	assert text[elements[0].byte_range.start..elements[0].byte_range.end] == '/plan'
}

fn test_slash_command_elementizes_only_known_commands() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_collaboration_modes_enabled( /* enabled */
	true)
	type_chars_humanlike(mut composer, &[`/`, `U`, `s`, `e`, `r`, `s`, ` `])
	assert composer.draft.textarea.text() == '/Users '
	assert composer.draft.textarea.text_elements().len == 0
}

fn test_slash_command_element_removed_when_not_at_start() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `r`, `e`, `v`, `i`, `e`, `w`, ` `])
	assert composer.draft.textarea.text() == '/review '
	assert composer.draft.textarea.text_elements().len == 1
	composer.draft.textarea.set_cursor( /* pos */
	0)
	type_chars_humanlike(mut composer, &[`x`])
	assert composer.draft.textarea.text() == 'x/review '
	assert composer.draft.textarea.text_elements().len == 0
}

fn test_tab_submits_when_no_task_running() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`h`, `i`])
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .submitted
	assert result.text == 'hi'
	assert composer.draft.textarea.is_empty()
}

fn test_tab_does_not_submit_for_bang_shell_command() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_task_running( /* running */
	false)
	type_chars_humanlike(mut composer, &[`!`, `l`, `s`])
	result, _ := composer.handle_key_event(composer_test_key(.tab))
	assert result.kind == .no_result
	assert composer.current_text().starts_with('!ls'), 'expected Tab not to submit or clear a `!` command'
}

fn test_bang_prefixed_slash_text_submits_literal_shell_command() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`!`, `/`, `d`, `i`, `f`, `f`])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '!/diff'
}

fn test_slash_mention_dispatches_command_and_inserts_at() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	type_chars_humanlike(mut composer, &[`/`, `m`, `e`, `n`, `t`, `i`, `o`, `n`])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command.command() == 'mention'
	assert composer.draft.textarea.is_empty(), 'composer should be cleared'
	at := '@'
	composer.insert_str(&at)
	assert composer.draft.textarea.text() == '@'
}

fn test_slash_plan_args_preserve_text_elements() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_collaboration_modes_enabled( /* enabled */
	true)
	type_chars_humanlike(mut composer, &[`/`, `p`, `l`, `a`, `n`, ` `])
	// `local_image_label_text(/* label_number */ 1)` belongs to the attachment sibling module;
	// its source-faithful label for this first local image is retained explicitly here.
	placeholder := '[Image #1]'
	composer.attach_image('/tmp/plan.png')
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command_with_args
	assert result.command.command() == 'plan'
	assert result.text == placeholder
	assert result.text_elements.len == 1
	assert result.text[result.text_elements[0].byte_range.start..result.text_elements[0].byte_range.end] == placeholder
}

fn test_file_completion_preserves_large_paste_placeholder_elements() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	large := 'x'.repeat(large_paste_char_threshold + 5)
	placeholder := '[Pasted Content ${large.runes().len} chars]'
	composer.handle_paste(large.clone())
	file_token := ' @ma'
	composer.insert_str(&file_token)
	composer.on_file_search_result('ma', [codex_file_search.FileMatch{
		score: 1
		path:  'src/main.rs'
		root:  '/tmp'
	}])
	composer.handle_key_event(composer_test_key(.tab))
	text := composer.draft.textarea.text()
	assert text == '${placeholder} src/main.rs '
	elements := composer.draft.textarea.text_elements()
	assert elements.len == 1
	assert elements[0].placeholder_text(&text) or { '' } == placeholder
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '${large} src/main.rs'
	assert result.text_elements.len == 0
}

fn test_legacy_file_completion_ignores_shell_variable_to_the_right() {
	mut composer := new_test_composer()
	name := 'available'
	composer.set_skill_mentions([rust_test_skill_metadata(&name)])
	text := '@src  \$HOME'
	query := 'src'
	complete_file(mut composer, &text, /* cursor */
		'@src '.len, &query, 'src/main.rs')
	assert composer.current_text() == 'src/main.rs  \$HOME'
}

fn test_unified_popup_preserves_empty_at_before_existing_text() {
	mut composer := new_test_composer()
	composer.set_mentions_v2_enabled( /* enabled */
	true)
	composer.set_text_content('@ word', [], [])
	composer.draft.textarea.set_cursor('@'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .mention_v2
}

fn test_adjacent_file_completion_inserts_leading_separator() {
	mut composer := new_test_composer()
	configure_bound_plugin_left_of_unbound_plugin(mut composer)
	path := 'src/main.rs'
	composer.insert_selected_file_path('@sample'.len, '@sample@other'.len, &path)
	assert composer.current_text() == '@sample src/main.rs '
}

fn test_adjacent_image_completion_inserts_leading_separator() {
	// Image decoding belongs to the image dependency; construct a valid PNG-header file at that
	// boundary and retain the source's adjacent-element and Vim-undo setup.
	temp_path := os.join_path(os.temp_dir(), 'chat_composer_adjacent_image_${time.now().unix_nano()}.png')
	os.write_file_array(temp_path, [u8(0x89), `P`, `N`, `G`, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0,
		`I`, `H`, `D`, `R`, 0, 0, 0, 3, 0, 0, 0, 2]) or {
		panic(err)
	}
	defer {
		os.rm(temp_path) or {}
	}
	mut composer := new_test_composer()
	configure_bound_plugin_left_of_unbound_plugin(mut composer)
	composer.set_vim_enabled(true)
	before := composer.draft_snapshot()
	composer.insert_selected_file_path('@sample'.len, '@sample@other'.len, &temp_path)
	assert composer.current_text() == '@sample [Image #1] '
	assert composer.local_image_paths() == [temp_path]
	composer.handle_key_event(composer_test_key(.escape))
	composer.handle_key_event(composer_test_char(`u`))
	assert composer.draft_snapshot() == before
}

fn test_file_completion_preserves_separator_before_existing_suffix() {
	mut composer := new_test_composer()
	text := '@ma next'
	query := 'ma'
	complete_file(mut composer, &text, /* cursor */
		'@ma'.len, &query, 'src/main.rs')
	inserted := 'foo'
	composer.insert_str(&inserted)
	assert composer.current_text() == 'src/main.rs foo next'
}

fn test_file_completion_preserves_separator_before_sigiled_suffix() {
	for suffix in ['@next', '\$next'] {
		mut composer := new_test_composer()
		composer.set_text_content('@ma ${suffix}', [], [])
		path := 'src/main.rs'
		composer.insert_selected_path(0, '@ma'.len, &path)
		inserted := 'foo'
		composer.insert_str(&inserted)
		assert composer.current_text() == 'src/main.rs foo ${suffix}'
	}
}

fn test_file_completion_inserts_separator_before_line_break() {
	mut composer := new_test_composer()
	text := '@ma\nnext'
	query := 'ma'
	complete_file(mut composer, &text, /* cursor */
		'@ma'.len, &query, 'src/main.rs')
	inserted := 'foo'
	composer.insert_str(&inserted)
	assert composer.current_text() == 'src/main.rs foo\nnext'
}

fn test_file_completion_advances_across_multibyte_horizontal_unicode_separator() {
	for separator in [' ', ' ', ' '] {
		mut composer := new_test_composer()
		composer.set_text_content('@ma${separator}', [], [])
		path := 'src/main.rs'
		composer.insert_selected_path(0, '@ma'.len, &path)
		assert composer.current_text() == '${path}${separator}'
		assert composer.current_cursor() == path.len + separator.len
	}
}

fn test_file_completion_preserves_multibyte_horizontal_separator_before_suffix() {
	mut composer := new_test_composer()
	separator := ' '
	composer.set_text_content('@ma${separator}next', [], [])
	path := 'src/main.rs'
	composer.insert_selected_path(0, '@ma'.len, &path)
	assert composer.current_text() == '${path} ${separator}next'
	assert composer.current_cursor() == path.len + 1
}

fn test_file_completion_does_not_reuse_unicode_line_separator() {
	mut composer := new_test_composer()
	line_separator := ' '
	composer.set_text_content('@ma${line_separator}next', [], [])
	path := 'src/main.rs'
	composer.insert_selected_path(0, '@ma'.len, &path)
	assert composer.current_text() == '${path} ${line_separator}next'
	assert composer.current_cursor() == path.len + 1
}

fn test_file_completion_for_sigil_path_does_not_reopen_popup() {
	mut composer := new_test_composer()
	text := '@ma\nnext'
	query := 'ma'
	complete_file(mut composer, &text, /* cursor */
		'@ma'.len, &query, '@scope/main.rs')
	assert composer.current_text() == '@scope/main.rs \nnext'
	assert composer.popups.active.kind == .none
	result, consumed := composer.handle_key_event(composer_test_key(.enter))
	assert consumed
	assert result.kind == .submitted
	assert result.text == '@scope/main.rs \nnext'
}

fn test_file_completion_does_not_dismiss_identical_next_token() {
	mut composer := new_test_composer()
	text := '@ma  @scope/main.rs'
	query := 'ma'
	complete_file(mut composer, &text, /* cursor */
		'@ma'.len, &query, '@scope/main.rs')
	composer.draft.textarea.set_cursor('@scope/main.rs  '.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
}

fn test_dismissed_file_popup_tracks_token_across_leading_whitespace_edits() {
	mut composer := new_test_composer()
	composer.set_text_content('@ma', [], [])
	composer.draft.textarea.set_cursor('@ma'.len)
	composer.sync_popups()
	assert composer.popups.active.kind == .file
	composer.handle_key_event(composer_test_key(.escape))
	composer.handle_key_event(composer_test_key(.escape))
	assert composer.popups.active.kind == .none
	composer.draft.textarea.set_cursor( /* pos */
	0)
	spaces := '   '
	composer.insert_str(&spaces)
	assert composer.popups.active.kind == .none
	for _ in 0 .. 3 {
		composer.handle_key_event(composer_test_key(.backspace))
		assert composer.popups.active.kind == .none
	}
}

fn test_dismissed_file_popup_ignores_token_substrings_in_leading_paste() {
	mut composer := new_test_composer()
	composer.set_text_content('@ma', [], [])
	composer.draft.textarea.set_cursor('@ma'.len)
	composer.sync_popups()
	composer.handle_key_event(composer_test_key(.escape))
	composer.handle_key_event(composer_test_key(.escape))
	assert composer.popups.active.kind == .none
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.handle_paste('email@ma.com ')
	assert composer.current_text() == 'email@ma.com @ma'
	assert composer.popups.active.kind == .none
}

// Behavior: multiple paste operations can coexist; placeholders should be expanded to their
// original content on submission.
fn test_multiple_pastes_submission() {
	mut composer := new_test_composer()
	// Define test cases: (paste content, is_large)
	first := 'x'.repeat(large_paste_char_threshold + 3)
	third := 'y'.repeat(large_paste_char_threshold + 7)
	// Expected states after each paste
	// Apply all pastes and build expected state
	composer.handle_paste(first.clone())
	assert composer.pending_pastes().len == 1
	composer.handle_paste(' and ')
	assert composer.pending_pastes().len == 1
	composer.handle_paste(third.clone())
	// Verify all intermediate states were correct
	assert composer.pending_pastes().len == 2
	assert composer.current_text() == '[Pasted Content ${first.runes().len} chars] and [Pasted Content ${third.runes().len} chars]'
	// Submit and verify final expansion
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '${first} and ${third}'
}

fn test_placeholder_deletion() {
	mut composer := new_test_composer()
	// Define test cases: (content, is_large)
	first := 'a'.repeat(large_paste_char_threshold + 5)
	second := 'b'.repeat(large_paste_char_threshold + 6)
	// Apply all pastes
	composer.handle_paste(first)
	first_end := composer.current_text().len
	composer.handle_paste(' and ')
	composer.handle_paste(second)
	// Delete placeholders one by one and collect states
	// First deletion
	composer.set_current_cursor(first_end)
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.current_text() == ' and [Pasted Content ${large_paste_char_threshold + 6} chars]'
	assert composer.pending_pastes().len == 1
	// Second deletion
	composer.move_cursor_to_end()
	composer.handle_key_event(composer_test_key(.backspace))
	// Verify all states
	assert composer.current_text() == ' and '
	assert composer.pending_pastes().len == 0
}

// Behavior: if multiple large pastes share the same placeholder label (same char count),
// deleting one placeholder removes only its corresponding `pending_pastes` entry.
fn test_deleting_duplicate_length_pastes_removes_only_target() {
	mut composer := new_test_composer()
	paste := 'x'.repeat(large_paste_char_threshold + 4)
	base := '[Pasted Content ${paste.runes().len} chars]'
	composer.handle_paste(paste.clone())
	composer.handle_paste(paste.clone())
	assert composer.current_text() == '${base}${base} #2'
	composer.move_cursor_to_end()
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.current_text() == base
	pending := composer.pending_pastes()
	assert pending.len == 1
	assert pending[0].placeholder == base
	assert pending[0].actual == paste
}

// Behavior: large-paste placeholder numbering continues when another placeholder of the
// same length still exists, so a new paste gets a new unique placeholder label.
fn test_large_paste_numbering_continues_with_same_length_placeholder() {
	mut composer := new_test_composer()
	paste := 'x'.repeat(large_paste_char_threshold + 4)
	base := '[Pasted Content ${paste.runes().len} chars]'
	second := '${base} #2'
	third := '${base} #3'
	composer.handle_paste(paste.clone())
	composer.handle_paste(paste.clone())
	assert composer.current_text() == '${base}${second}'
	composer.set_current_cursor(base.len)
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.current_text() == second
	assert composer.pending_pastes().len == 1
	assert composer.pending_pastes()[0].placeholder == second
	composer.move_cursor_to_end()
	composer.handle_paste(paste)
	assert composer.current_text() == '${second}${third}'
	pending := composer.pending_pastes()
	assert pending.len == 2
	assert pending[0].placeholder == second
	assert pending[1].placeholder == third
}

// Behavior: if all placeholders of a given length are removed, numbering resets to the
// base placeholder on the next paste.
fn test_large_paste_numbering_reuses_after_all_deleted() {
	mut composer := new_test_composer()
	paste := 'x'.repeat(large_paste_char_threshold + 4)
	base := '[Pasted Content ${paste.runes().len} chars]'
	composer.handle_paste(paste.clone())
	assert composer.current_text() == base
	composer.move_cursor_to_end()
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.current_text() == ''
	assert composer.pending_pastes().len == 0
	composer.handle_paste(paste)
	assert composer.current_text() == base
	assert composer.pending_pastes()[0].placeholder == base
}

fn test_partial_placeholder_deletion() {
	paste := 'x'.repeat(large_paste_char_threshold + 4)
	placeholder := '[Pasted Content ${paste.runes().len} chars]'
	// Define test cases: (cursor_position_from_end, expected_pending_count)
	for from_end in [5, 0] {
		mut composer := new_test_composer()
		composer.handle_paste(paste.clone())
		composer.set_current_cursor(placeholder.len - from_end)
		composer.handle_key_event(composer_test_key(.backspace))
		assert !composer.current_text().contains(placeholder)
		assert composer.pending_pastes().len == 0
	}
}

// --- Image attachment tests ---
fn test_attach_image_and_submit_includes_local_image_paths() {
	mut composer := new_test_composer()
	path := '/tmp/image1.png'
	composer.attach_image(path.clone())
	composer.handle_paste(' hi')
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '[Image #1] hi'
	assert result.text_elements.len == 1
	assert result.text_elements[0].byte_range.start == 0
	assert result.text_elements[0].byte_range.end == '[Image #1]'.len
	assert composer.take_recent_submission_images() == [path]
}

fn test_submit_captures_recent_mention_bindings_before_clearing_textarea() {
	mut composer := new_test_composer()
	bindings := [
		MentionBinding{ sigil: `$`, mention: 'figma', path: '/tmp/user/figma/SKILL.md' },
	]
	composer.set_text_content_with_mention_bindings('\$figma please', [], [], bindings.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert composer.take_recent_submission_mention_bindings() == bindings
	assert composer.take_mention_bindings().len == 0
}

fn test_history_navigation_restores_remote_and_local_image_attachments() {
	mut composer := new_test_composer()
	remote_url := 'https://example.com/remote.png'
	composer.set_remote_image_urls([remote_url.clone()])
	path := '/tmp/image1.png'
	composer.attach_image(path.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	composer.take_remote_image_urls()
	composer.set_text_content('', [], [])
	composer.handle_key_event(composer_test_key(.up))
	text := composer.current_text()
	assert text == '[Image #2]'
	elements := composer.text_elements()
	assert elements.len == 1
	assert text[elements[0].byte_range.start..elements[0].byte_range.end] == '[Image #2]'
	assert composer.local_image_paths() == [path]
	assert composer.remote_image_urls() == [remote_url]
}

fn test_history_navigation_restores_remote_only_submissions() {
	mut composer := new_test_composer()
	urls := ['https://example.com/one.png', 'https://example.com/two.png']
	composer.set_remote_image_urls(urls.clone())
	prepared := composer.prepare_submission_text( /* record_history */
	true) or {
		panic('remote-only submission')
	}
	assert prepared.text == ''
	assert prepared.elements.len == 0
	composer.take_remote_image_urls()
	composer.set_text_content('', [], [])
	composer.handle_key_event(composer_test_key(.up))
	assert composer.current_text() == ''
	assert composer.text_elements().len == 0
	assert composer.remote_image_urls() == urls
}

fn test_history_navigation_leaves_cursor_at_end_of_line() {
	mut composer := new_test_composer()
	for input in ['first', 'second'] {
		chars := input.runes()
		type_chars_humanlike(mut composer, &chars)
		result, _ := composer.handle_key_event(composer_test_key(.enter))
		assert result.kind == .submitted
	}
	composer.handle_key_event(composer_test_key(.up))
	assert composer.draft.textarea.text() == 'second'
	assert composer.draft.textarea.cursor() == 'second'.len
	composer.handle_key_event(composer_test_key(.up))
	assert composer.draft.textarea.text() == 'first'
	assert composer.draft.textarea.cursor() == 'first'.len
	composer.handle_key_event(composer_test_key(.down))
	assert composer.draft.textarea.text() == 'second'
	assert composer.draft.textarea.cursor() == 'second'.len
	composer.handle_key_event(composer_test_key(.down))
	assert composer.draft.textarea.is_empty()
	assert composer.draft.textarea.cursor() == 0
}

fn test_vim_normal_operator_pending_consumes_submit_key() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('hello', [], [])
	composer.set_vim_enabled( /* enabled */
	true)
	composer.handle_key_event(composer_test_char(`d`))
	assert composer.draft.textarea.is_vim_operator_pending()
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.draft.textarea.text() == 'hello'
	span := composer.vim_mode_indicator_span() or { panic('missing Vim mode') }
	assert span.text == 'Vim: Normal'
	assert span.style.fg == some_color(.magenta)
	assert !composer.draft.textarea.is_vim_operator_pending()
}

fn test_remapped_editor_history_navigation_does_not_fall_back_to_up() {
	mut composer := new_test_composer()
	input := 'first'
	chars := input.runes()
	type_chars_humanlike(mut composer, &chars)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	mut keymap := tui_keymap.RuntimeKeymap.defaults()
	f2 := key_hint.plain(terminal_event.KeyCode{ kind: .function, f: 2 })
	keymap.editor = tui_keymap.EditorKeymap{
		...keymap.editor
		move_up: [f2]
	}
	composer.set_keymap_bindings(&keymap)
	assert composer.editor_keymap.move_up == keymap.editor.move_up
	assert keymap.editor.move_up == [f2]
	composer.handle_key_event(composer_test_key(.up))
	assert composer.draft.textarea.is_empty()
	composer.handle_key_event(terminal_event.KeyEvent{
		code: terminal_event.KeyCode{ kind: .function, f: 2 }
	})
	assert composer.draft.textarea.text() == 'first'
}

fn test_history_navigation_from_start_of_bang_command_recalls_older_entry() {
	mut composer := new_test_composer()
	for input in ['first', '!git'] {
		chars := input.runes()
		type_chars_humanlike(mut composer, &chars)
		result, _ := composer.handle_key_event(composer_test_key(.enter))
		assert result.kind == .submitted
	}
	composer.handle_key_event(composer_test_key(.up))
	assert composer.current_text() == '!git'
	composer.draft.textarea.set_cursor(0)
	composer.handle_key_event(composer_test_key(.up))
	assert composer.current_text() == 'first'
}

fn test_vim_normal_history_navigation_from_start_of_bang_command_recalls_older_entry() {
	mut composer := new_test_composer()
	for input in ['first', '!git'] {
		chars := input.runes()
		type_chars_humanlike(mut composer, &chars)
		result, _ := composer.handle_key_event(composer_test_key(.enter))
		assert result.kind == .submitted
	}
	composer.set_vim_enabled(true)
	composer.handle_key_event(composer_test_char(`k`))
	assert composer.current_text() == '!git'
	assert composer.draft.textarea.cursor() == 'git'.len - 1
	composer.handle_key_event(composer_test_char(`k`))
	assert composer.current_text() == 'first'
	assert composer.draft.textarea.cursor() == 'first'.len - 1
}

fn test_set_text_content_reattaches_images_without_placeholder_metadata() {
	mut composer := new_test_composer()
	placeholder := '[Image #${ /* label_number */1}]'
	text := '${placeholder} restored'
	// The source intentionally supplies no placeholder payload metadata. Attachment restoration must
	// still associate the path with the atomic element's text range.
	text_elements := [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   placeholder.len
	}, none)]
	path := '/tmp/image1.png'
	composer.set_text_content(text, text_elements, [path.clone()])
	assert composer.local_image_paths() == [path]
}

fn test_large_paste_preserves_image_text_elements_on_submit() {
	mut composer := new_test_composer()
	large_content := 'x'.repeat(large_paste_char_threshold + 5)
	composer.handle_paste(large_content.clone())
	composer.handle_paste(' ')
	path := '/tmp/image_with_paste.png'
	composer.attach_image(path.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	expected := '${large_content} [Image #1]'
	assert result.text == expected
	assert result.text_elements.len == 1
	assert result.text_elements[0].placeholder_text(&result.text) or { '' } == '[Image #1]'
	assert result.text_elements[0].byte_range.start == large_content.len + 1
	assert result.text_elements[0].byte_range.end == large_content.len + 1 + '[Image #1]'.len
	assert composer.take_recent_submission_images() == [path]
}

fn test_large_paste_with_leading_whitespace_trims_and_shifts_elements() {
	mut composer := new_test_composer()
	large_content := '  ${'x'.repeat(large_paste_char_threshold + 5)}'
	composer.handle_paste(large_content.clone())
	composer.handle_paste(' ')
	path := '/tmp/image_with_trim.png'
	composer.attach_image(path.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	trimmed := large_content.trim_space()
	assert result.text == '${trimmed} [Image #1]'
	assert result.text_elements.len == 1
	assert result.text_elements[0].placeholder_text(&result.text) or { '' } == '[Image #1]'
	assert result.text_elements[0].byte_range.start == trimmed.len + 1
	assert result.text_elements[0].byte_range.end == trimmed.len + 1 + '[Image #1]'.len
	assert composer.take_recent_submission_images() == [path]
}

fn test_pasted_crlf_normalizes_newlines_for_elements() {
	mut composer := new_test_composer()
	composer.handle_paste('line1\r\nline2\r\n')
	composer.handle_paste(' ')
	path := '/tmp/image_crlf.png'
	composer.attach_image(path.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == 'line1\nline2\n [Image #1]'
	assert !result.text.contains('\r')
	assert result.text_elements.len == 1
	assert result.text_elements[0].placeholder_text(&result.text) or { '' } == '[Image #1]'
	assert result.text_elements[0].byte_range.start == 'line1\nline2\n '.len
	assert result.text_elements[0].byte_range.end == 'line1\nline2\n [Image #1]'.len
	assert composer.take_recent_submission_images() == [path]
}

fn test_suppressed_submission_restores_pending_paste_payload() {
	mut composer := new_test_composer()
	initial := '/unknown '
	composer.draft.textarea.set_text_clearing_elements(&initial)
	composer.draft.textarea.set_cursor(initial.len)
	large_content := 'x'.repeat(large_paste_char_threshold + 5)
	composer.handle_paste(large_content.clone())
	placeholder := composer.draft.pending_pastes[0].placeholder.clone()
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .no_result
	assert composer.draft.pending_pastes.len == 1
	assert composer.draft.textarea.text() == '/unknown ${placeholder}'
	composer.draft.textarea.set_cursor( /* pos */
	0)
	space := ' '
	composer.draft.textarea.insert_str(&space)
	result2, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result2.kind == .submitted
	assert result2.text == '/unknown ${large_content}'
	assert result2.text_elements.len == 0
	assert composer.draft.pending_pastes.len == 0
}

fn test_attach_image_without_text_submits_empty_text_and_images() {
	mut composer := new_test_composer()
	path := '/tmp/image2.png'
	composer.attach_image(path.clone())
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '[Image #1]'
	assert result.text_elements == [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   '[Image #1]'.len
	}, '[Image #1]')]
	images := composer.take_recent_submission_images()
	assert images == [path]
	assert composer.attachments.local_images.len == 0
}

fn test_duplicate_image_placeholders_get_suffix() {
	mut composer := new_test_composer()
	path := '/tmp/image_dup.png'
	composer.attach_image(path.clone())
	composer.handle_paste(' ')
	composer.attach_image(path)
	text := composer.draft.textarea.text()
	assert text.contains('[Image #1]')
	assert text.contains('[Image #2]')
	assert composer.attachments.local_images[0].placeholder == '[Image #1]'
	assert composer.attachments.local_images[1].placeholder == '[Image #2]'
}

fn test_image_placeholder_backspace_behaves_like_text_placeholder() {
	mut composer := new_test_composer()
	path := '/tmp/image3.png'
	composer.attach_image(path.clone())
	placeholder := composer.attachments.local_images[0].placeholder.clone()
	// Case 1: backspace at end
	composer.draft.textarea.set_cursor(composer.draft.textarea.text().len)
	composer.handle_key_event(composer_test_key(.backspace))
	assert !composer.draft.textarea.text().contains(placeholder)
	assert composer.attachments.local_images.len == 0
	// Re-add and ensure backspace at element start does not delete the placeholder.
	composer.attach_image(path)
	placeholder2 := composer.attachments.local_images[0].placeholder.clone()
	start := composer.draft.textarea.text().index(placeholder2.clone()) or {
		panic('placeholder not found')
	}
	// Move cursor to roughly middle of placeholder
	// Rust asks for the midpoint, which its element-aware textarea normalizes to the atomic start.
	// The V textarea dependency boundary exposes that normalized position directly.
	composer.draft.textarea.set_cursor(start)
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.draft.textarea.text().contains(placeholder2.clone())
	assert composer.attachments.local_images.len == 1
}

fn test_backspace_with_multibyte_text_before_placeholder_does_not_panic() {
	mut composer := new_test_composer()
	// Insert an image placeholder at the start
	composer.attach_image('/tmp/image_multibyte.png')
	// Add multibyte text after the placeholder
	text := '日本語'
	composer.draft.textarea.insert_str(&text)
	// Cursor is at end; pressing backspace should delete the last character
	// without panicking and leave the placeholder intact.
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.attachments.local_images.len == 1
	assert composer.draft.textarea.text().starts_with('[Image #1]')
}

fn test_deleting_one_of_duplicate_image_placeholders_removes_one_entry() {
	mut composer := new_test_composer()
	path1 := '/tmp/image_dup1.png'
	path2 := '/tmp/image_dup2.png'
	composer.attach_image(path1)
	// separate placeholders with a space for clarity
	composer.handle_paste(' ')
	composer.attach_image(path2.clone())
	placeholder1 := composer.attachments.local_images[0].placeholder.clone()
	placeholder2 := composer.attachments.local_images[1].placeholder.clone()
	text := composer.draft.textarea.text()
	start1 := text.index(placeholder1.clone()) or { panic('first placeholder present') }
	composer.draft.textarea.set_cursor(start1 + placeholder1.len)
	// Backspace should delete the first placeholder and its mapping.
	composer.handle_key_event(composer_test_key(.backspace))
	new_text := composer.draft.textarea.text()
	assert new_text.count(placeholder1.clone()) == 1, 'one placeholder remains after deletion'
	assert new_text.count(placeholder2) == 0, 'second placeholder was relabeled'
	assert new_text.count('[Image #1]') == 1, 'remaining placeholder relabeled to #1'
	assert composer.attachments.local_images == [LocalImageAttachment{
		path:        path2
		placeholder: '[Image #1]'
	}]
}

fn test_deleting_reordered_image_one_renumbers_text_in_place() {
	mut composer := new_test_composer()
	path1 := '/tmp/image_first.png'
	path2 := '/tmp/image_second.png'
	placeholder1 := '[Image #${ /* label_number */1}]'
	placeholder2 := '[Image #${ /* label_number */2}]'
	// Placeholders can be reordered in the text buffer; deleting image #1 should renumber
	// image #2 wherever it appears, not just after the cursor.
	text := 'Test ${placeholder2} test ${placeholder1}'
	start2 := text.index(placeholder2) or { panic('placeholder2 present') }
	start1 := text.index(placeholder1) or { panic('placeholder1 present') }
	composer.set_text_content(text, [user_input.TextElement.new(user_input.ByteRange{
		start: start2
		end:   start2 + placeholder2.len
	}, placeholder2), user_input.TextElement.new(user_input.ByteRange{
		start: start1
		end:   start1 + placeholder1.len
	}, placeholder1.clone())], [path1, path2.clone()])
	composer.draft.textarea.set_cursor(start1 + placeholder1.len)
	composer.handle_key_event(composer_test_key(.backspace))
	assert composer.draft.textarea.text() == 'Test ${placeholder1} test '
	assert composer.attachments.local_images == [LocalImageAttachment{
		path:        path2
		placeholder: placeholder1
	}]
}

fn test_deleting_first_text_element_renumbers_following_text_element() {
	mut composer := new_test_composer()
	path1 := '/tmp/image_first.png'
	path2 := '/tmp/image_second.png'
	// Insert two adjacent atomic elements.
	composer.attach_image(path1)
	composer.attach_image(path2.clone())
	assert composer.draft.textarea.text() == '[Image #1][Image #2]'
	assert composer.attachments.local_images.len == 2
	// Delete the first element using normal textarea editing (forward Delete at cursor start).
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.handle_key_event(composer_test_key(.delete))
	// Remaining image should be renumbered and the textarea element updated.
	assert composer.attachments.local_images.len == 1
	assert composer.attachments.local_images[0].path == path2
	assert composer.attachments.local_images[0].placeholder == '[Image #1]'
	assert composer.draft.textarea.text() == '[Image #1]'
}

fn test_pasting_filepath_attaches_image() {
	temp_path := os.join_path(os.temp_dir(), 'codex_tui_test_paste_image_${time.now().unix_nano()}.png')
	os.write_file_array(temp_path, [u8(0x89), `P`, `N`, `G`, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0,
		`I`, `H`, `D`, `R`, 0, 0, 0, 3, 0, 0, 0, 2]) or {
		panic(err)
	}
	defer {
		os.rm(temp_path) or {}
	}
	mut composer := ChatComposer.new(true, app_event_sender.AppEventSender{}, false, owned_composer_test_string('Ask Codex to do anything'), false)
	needs_redraw := composer.handle_paste(temp_path.clone())
	assert needs_redraw
	assert composer.draft.textarea.text().starts_with('[Image #1] ')
	assert composer.take_recent_submission_images() == [temp_path]
}

fn test_slash_path_input_submits_without_command_error() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	input := '/Users/example/project/src/main.rs'
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == input
	assert composer.draft.textarea.is_empty()
	assert composer.app_event_tx.events.len == 0
}

fn test_slash_with_leading_space_submits_as_text() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	input := ' /this-looks-like-a-command'
	composer.draft.textarea.set_text_clearing_elements(&input)
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .submitted
	assert result.text == '/this-looks-like-a-command'
	assert composer.draft.textarea.is_empty()
	assert composer.app_event_tx.events.len == 0
}

fn test_shortcut_modified_input_does_not_enter_paste_bursts() {
	now_ms := time.now().unix_milli()
	{
		mut composer := new_test_composer()
		for input in [composer_test_char(`a`), terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   ` `
		}, terminal_event.KeyModifiers{ super: true }), composer_test_char(`b`)] {
			composer.handle_input_basic_with_time(input, now_ms)
		}
		assert composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_active_flush_delay())
		assert_composer_snapshot('shortcut_modified_space_is_not_rendered', &composer, 100)
	}
	for modifiers in [terminal_event.KeyModifiers{ super: true },
		terminal_event.KeyModifiers{ shift: true, super: true }, terminal_event.KeyModifiers{
			hyper: true
		}, terminal_event.KeyModifiers{ meta: true }] {
		mut composer := new_test_composer()
		composer.handle_input_basic_with_time(terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   ` `
		}, modifiers), now_ms)
		assert !composer.is_in_paste_burst(), 'shortcut modifiers must not start a paste burst'
		assert !composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
		assert composer.draft.textarea.text() == ''
	}
}

fn test_plain_and_shift_spaces_insert_normally() {
	now_ms := time.now().unix_milli()
	for modifiers in [terminal_event.KeyModifiers{}, terminal_event.KeyModifiers{ shift: true }] {
		mut composer := new_test_composer()
		composer.handle_input_basic_with_time(terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   ` `
		}, modifiers), now_ms)
		assert composer.is_in_paste_burst()
		assert composer.draft.textarea.text() == ''
		assert composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
		assert composer.draft.textarea.text() == ' '
		assert !composer.is_in_paste_burst()
		mut snapshot_composer := new_test_composer()
		for input in [composer_test_char(`a`), terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   ` `
		}, modifiers), composer_test_char(`b`)] {
			snapshot_composer.handle_input_basic_with_time(input, now_ms)
		}
		assert snapshot_composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_active_flush_delay())
		name := if modifiers == terminal_event.KeyModifiers{} {
			'plain_space_is_rendered'
		} else {
			'shift_space_is_rendered'
		}
		assert_composer_snapshot(name, &snapshot_composer, 100)
	}
}

fn test_non_text_input_flushes_pending_paste_without_inserting_text() {
	mut composer := new_test_composer()
	now_ms := time.now().unix_milli()
	composer.handle_input_basic_with_time(composer_test_char(`a`), now_ms)
	composer.handle_input_basic_with_time(composer_test_char(`b`), now_ms)
	assert composer.is_in_paste_burst()
	assert composer.draft.textarea.text() == ''
	composer.handle_input_basic_with_time(terminal_event.KeyEvent.new(terminal_event.KeyCode{
		kind: .char_key
		ch:   ` `
	}, terminal_event.KeyModifiers{ super: true }), now_ms)
	assert composer.draft.textarea.text() == 'ab'
	assert !composer.is_in_paste_burst()
	assert !composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
}

fn test_platform_specific_altgr_input_remains_text() {
	now_ms := time.now().unix_milli()
	for modifiers in [terminal_event.KeyModifiers{ control: true, alt: true },
		terminal_event.KeyModifiers{ shift: true, control: true, alt: true }] {
		mut composer := new_test_composer()
		composer.handle_input_basic_with_time(terminal_event.KeyEvent.new(terminal_event.KeyCode{
			kind: .char_key
			ch:   `@`
		}, modifiers), now_ms)
		$if windows {
			assert composer.is_in_paste_burst()
			assert composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
			assert composer.draft.textarea.text() == '@'
		} $else {
			assert !composer.is_in_paste_burst()
			assert !composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
			assert composer.draft.textarea.text() == ''
		}
	}
}

// Behavior: the first fast ASCII character is held briefly to avoid flicker; if no burst
// follows, it should eventually flush as normal typed input (not as a paste).
fn test_pending_first_ascii_char_flushes_as_typed() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	now_ms := time.now().unix_milli()
	composer.handle_input_basic_with_time(composer_test_char(`h`), now_ms)
	assert composer.is_in_paste_burst()
	assert composer.draft.textarea.text().len == 0
	flushed := composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_flush_delay())
	assert flushed, 'expected pending first char to flush'
	assert composer.draft.textarea.text() == 'h'
	assert !composer.is_in_paste_burst()
}

// Behavior: fast "paste-like" ASCII input should buffer and then flush as a single paste. If
// the payload is small, it should insert directly (no placeholder).
fn test_burst_paste_fast_small_buffers_and_flushes_on_stop() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	count := 32
	mut now_ms := time.now().unix_milli()
	for _ in 0 .. count {
		composer.handle_input_basic_with_time(composer_test_char(`a`), now_ms)
		assert composer.is_in_paste_burst(), 'expected active paste burst during fast typing'
		assert composer.draft.textarea.text().len == 0, 'text should not appear during burst'
		now_ms++
	}
	assert composer.draft.textarea.text().len == 0, 'text should remain empty until flush'
	flushed := composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_active_flush_delay() + 1)
	assert flushed, 'expected buffered text to flush after stop'
	assert composer.draft.textarea.text() == 'a'.repeat(count)
	assert composer.draft.pending_pastes.len == 0, 'no placeholder for small burst'
}

// Behavior: fast "paste-like" ASCII input should buffer and then flush as a single paste. If
// the payload is large, it should insert a placeholder and defer the full text until submit.
fn test_burst_paste_fast_large_inserts_placeholder_on_flush() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	count := large_paste_char_threshold + 1
	mut now_ms := time.now().unix_milli()
	for _ in 0 .. count {
		composer.handle_input_basic_with_time(composer_test_char(`x`), now_ms)
		now_ms++
	}
	// Nothing should appear until we stop and flush
	assert composer.draft.textarea.text().len == 0
	flushed := composer.handle_paste_burst_flush(now_ms + PasteBurst.recommended_active_flush_delay() + 1)
	assert flushed, 'expected flush after stopping fast input'
	expected := '[Pasted Content ${count} chars]'
	assert composer.draft.textarea.text() == expected
	assert composer.draft.pending_pastes.len == 1
	assert composer.draft.pending_pastes[0].placeholder == expected
	assert composer.draft.pending_pastes[0].actual == 'x'.repeat(count)
}

// Behavior: human-like typing (with delays between chars) should not be classified as a paste
// burst. Characters should appear immediately and should not trigger a paste placeholder.
fn test_humanlike_typing_1000_chars_appears_live_no_placeholder() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	count := large_paste_char_threshold
	mut now_ms := time.now().unix_milli()
	for _ in 0 .. count {
		composer.handle_input_basic_with_time(composer_test_char(`z`), now_ms)
		now_ms += ChatComposer.recommended_paste_flush_delay()
		composer.handle_paste_burst_flush(now_ms)
	}
	assert composer.draft.textarea.text() == 'z'.repeat(count)
	assert composer.draft.pending_pastes.len == 0
}

fn test_slash_popup_not_activated_for_slash_space_text_history_like_input() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Simulate history-like content: "/ test"
	composer.set_text_content('/ test', [], [])
	// After set_text_content -> sync_popups is called; popup should NOT be Command.
	assert composer.popups.active.kind == .none, "expected no slash popup for '/ test'"
	// Up should be handled by history navigation path, not slash popup handler.
	result, _ := composer.handle_key_event(composer_test_key(.up))
	assert result.kind == .no_result
}

fn test_slash_popup_activated_for_bare_slash_and_valid_prefixes() {
	// use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	// Case 1: bare "/"
	composer.set_text_content('/', [], [])
	assert composer.popups.active.kind == .command, "bare '/' should activate slash popup"
	// Case 2: valid prefix "/re" (matches /review, /resume, etc.)
	composer.set_text_content('/re', [], [])
	assert composer.popups.active.kind == .command, "'/re' should activate via prefix match"
	// Case 3: fuzzy match "/ac" (subsequence of /compact and /feedback)
	composer.set_text_content('/ac', [], [])
	assert composer.popups.active.kind == .command, "'/ac' should activate via fuzzy match"
	// Case 4: invalid prefix "/zzz" – still allowed to open popup if it
	// matches no built-in command; our current logic will not open popup.
	// Verify that explicitly.
	composer.set_text_content('/zzz', [], [])
	assert composer.popups.active.kind == .none, "'/zzz' should not activate the slash popup"
}

fn test_bare_slash_command_can_be_recalled_after_recording_pending_history() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('/diff', [], [])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command == .diff
	composer.record_pending_slash_command_history()
	recall, _ := composer.handle_key_event(composer_test_key(.up))
	assert recall.kind == .no_result
	assert composer.current_text() == '/diff'
}

fn test_popup_selected_slash_command_records_canonical_command_history() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('/di', [], [])
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command
	assert result.command == .diff
	composer.record_pending_slash_command_history()
	recall, _ := composer.handle_key_event(composer_test_key(.up))
	assert recall.kind == .no_result
	assert composer.current_text() == '/diff'
}

fn test_inline_slash_command_can_be_recalled_after_recording_pending_history() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_collaboration_modes_enabled( /* enabled */
	true)
	composer.set_text_content('/plan investigate this', [], [])
	composer.popups.active = ActivePopup{}
	result, _ := composer.handle_key_event(composer_test_key(.enter))
	assert result.kind == .command_with_args
	assert result.command == .plan
	assert result.text == 'investigate this'
	assert result.text_elements.len == 0
	composer.record_pending_slash_command_history()
	recall, _ := composer.handle_key_event(composer_test_key(.up))
	assert recall.kind == .no_result
	assert composer.current_text() == '/plan investigate this'
}

fn test_apply_external_edit_rebuilds_text_and_attachments() {
	mut composer := new_test_composer()
	composer.attach_image('img.png')
	composer.draft.pending_pastes << PendingPaste{ placeholder: '[Pasted]', actual: 'data' }
	placeholder := local_image_label_text( /* label_number */
	1)
	composer.apply_external_edit('Edited ${placeholder} text')
	assert composer.current_text() == 'Edited ${placeholder} text'
	assert composer.pending_pastes().len == 0
	assert composer.local_images().len == 1
	assert composer.local_images()[0].placeholder == '[Image #1]'
	assert composer.current_cursor() == composer.current_text().len
}

fn test_apply_external_edit_absorbs_bash_prefix_without_duplication() {
	mut composer := new_test_composer()
	composer.set_text_content('!git status', [], [])
	composer.apply_external_edit('!git status')
	assert composer.draft.is_bash_mode
	assert composer.draft.textarea.text() == 'git status'
	assert composer.current_text() == '!git status'
}

fn test_apply_external_edit_can_leave_bash_mode() {
	mut composer := new_test_composer()
	composer.set_text_content('!git status', [], [])
	composer.apply_external_edit('git status')
	assert !composer.draft.is_bash_mode
	assert composer.draft.textarea.text() == 'git status'
	assert composer.current_text() == 'git status'
}

fn test_apply_external_edit_can_enter_bash_mode() {
	mut composer := new_test_composer()
	composer.set_text_content('git status', [], [])
	composer.apply_external_edit('!git status')
	assert composer.draft.is_bash_mode
	assert composer.draft.textarea.text() == 'git status'
	assert composer.current_text() == '!git status'
}

fn test_apply_external_edit_drops_missing_attachments() {
	mut composer := new_test_composer()
	composer.attach_image('img.png')
	placeholder := local_image_label_text( /* label_number */
	1)
	assert composer.local_images()[0].placeholder == placeholder
	composer.apply_external_edit('No images here')
	assert composer.current_text() == 'No images here'
	assert composer.local_images().len == 0
}

fn test_apply_external_edit_renumbers_image_placeholders() {
	mut composer := new_test_composer()
	composer.attach_image('img1.png')
	composer.attach_image('img2.png')
	placeholder2 := local_image_label_text( /* label_number */
	2)
	composer.apply_external_edit('Keep ${placeholder2}')
	placeholder1 := local_image_label_text( /* label_number */
	1)
	assert composer.current_text() == 'Keep ${placeholder1}'
	images := composer.local_images()
	assert images.len == 1
	assert images[0].placeholder == '[Image #1]'
	assert composer.local_image_paths() == ['img2.png']
	assert composer.draft.textarea.element_payloads() == ['[Image #1]']
}

fn test_current_text_with_pending_expands_placeholders() {
	mut composer := new_test_composer()
	placeholder := '[Pasted Content 5 chars]'
	composer.draft.textarea.insert_element(&placeholder)
	composer.draft.pending_pastes << PendingPaste{ placeholder: placeholder.clone(), actual: 'hello' }
	assert composer.current_text_with_pending() == 'hello'
}

fn test_current_text_with_pending_expands_overlapping_placeholders() {
	mut composer := new_test_composer()
	first := 'a'.repeat(large_paste_char_threshold + 4)
	second := 'b'.repeat(large_paste_char_threshold + 4)
	base := '[Pasted Content ${first.runes().len} chars]'
	composer.handle_paste(first.clone())
	composer.handle_paste(second.clone())
	assert composer.current_text() == '${base}${base} #2'
	assert composer.current_text_with_pending() == '${first}${second}'
}

fn test_apply_external_edit_limits_duplicates_to_occurrences() {
	mut composer := new_test_composer()
	composer.attach_image('img.png')
	placeholder := local_image_label_text( /* label_number */
	1)
	composer.apply_external_edit('${placeholder} extra ${placeholder}')
	assert composer.current_text() == '${placeholder} extra ${placeholder}'
	assert composer.local_images().len == 1
}

fn test_remote_images_do_not_modify_textarea_text_or_elements() {
	mut composer := new_test_composer()
	composer.set_remote_image_urls(['https://example.com/one.png', 'https://example.com/two.png'])
	assert composer.current_text() == ''
	assert composer.text_elements().len == 0
}

fn test_attach_image_after_remote_prefix_uses_offset_label() {
	mut composer := new_test_composer()
	composer.set_remote_image_urls(['https://example.com/one.png', 'https://example.com/two.png'])
	composer.attach_image('/tmp/local.png')
	assert composer.local_images()[0].placeholder == '[Image #3]'
	assert composer.current_text() == '[Image #3]'
}

fn test_prepare_submission_keeps_remote_offset_local_placeholder_numbering() {
	mut composer := new_test_composer()
	composer.set_remote_image_urls(['https://example.com/one.png'])
	composer.set_text_content('[Image #2] hello', [user_input.TextElement.new(user_input.ByteRange{
		start: 0
		end:   '[Image #2]'.len
	}, '[Image #2]')], ['/tmp/local.png'])
	prepared := composer.prepare_submission_text( /* record_history */
	true) or {
		panic('submission expected')
	}
	assert prepared.text == '[Image #2] hello'
	assert prepared.elements.len == 1
	assert prepared.elements[0].byte_range.start == 0
	assert prepared.elements[0].byte_range.end == '[Image #2]'.len
}

fn test_prepare_submission_with_only_remote_images_returns_empty_text() {
	mut composer := new_test_composer()
	composer.set_remote_image_urls(['https://example.com/one.png'])
	prepared := composer.prepare_submission_text( /* record_history */
	true) or {
		panic('remote-only submission expected')
	}
	assert prepared.text == ''
	assert prepared.elements.len == 0
}

fn test_delete_selected_remote_image_relabels_local_placeholders() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_remote_image_urls(['https://example.com/one.png', 'https://example.com/two.png'])
	composer.attach_image('/tmp/local.png')
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.handle_key_event(composer_test_key(.up))
	composer.handle_key_event(composer_test_key(.delete))
	assert composer.remote_image_urls() == ['https://example.com/one.png']
	assert composer.current_text() == '[Image #2]'
	assert composer.attachments.local_images[0].placeholder == '[Image #2]'
	composer.handle_key_event(composer_test_key(.up))
	composer.handle_key_event(composer_test_key(.delete))
	assert composer.remote_image_urls().len == 0
	assert composer.current_text() == '[Image #1]'
	assert composer.attachments.local_images[0].placeholder == '[Image #1]'
}

fn test_input_disabled_ignores_keypresses_and_hides_cursor() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('hello', [], [])
	composer.set_input_enabled( /* enabled */
	false, 'Input disabled for test.')
	result, redraw := composer.handle_key_event(composer_test_char(`x`))
	assert result.kind == .no_result
	assert !redraw
	assert composer.current_text() == 'hello'
	area := rat_layout.Rect{ width: 40, height: 5 }
	assert composer.cursor_pos(area) == none
}

fn test_shutdown_in_progress_disables_input_and_uses_hint_without_footer() {
	mut composer := ChatComposer.new( /* has_input_focus */
	true, app_event_sender.AppEventSender{},
		/* enhanced_keys_supported */
		false, owned_composer_test_string('Ask Codex to do anything'),
		/* disable_paste_burst */
		false)
	composer.set_text_content('hello', [], [])
	composer.show_shutdown_in_progress()
	assert !composer.input_enabled()
	assert composer.current_text() == 'hello'
	assert (composer.custom_footer_height() or { panic('missing custom footer height') }) == u16(0)
	area := rat_layout.Rect{ width: 40, height: 5 }
	assert composer.cursor_pos(area) == none
	mut buffer := rat_buffer.Buffer{}
	composer.render(area, mut buffer)
	assert composer_buffer_rows(&buffer, area) == [
		'                                        ',
		'› Shutting down...                      ',
		'                                        ',
		'                                        ',
		'                                        ',
	]
}
