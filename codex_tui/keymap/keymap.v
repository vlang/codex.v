module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event
import x.json2

// Runtime keymap resolution for the TUI.
//
// This module converts deserialized config (`TuiKeymap`) into a concrete
// `RuntimeKeymap` used by input handlers at runtime.
//
// Key responsibilities:
//
// 1. Apply deterministic precedence (`context -> global fallback -> defaults`).
// 2. Parse canonical key spec strings into `KeyBinding` values.
// 3. Enforce uniqueness across runtime surfaces so one key cannot trigger
//    multiple actions on the same focused input path.
// 4. Return actionable, user-facing error messages with config paths and next
//    steps.
//
// Non-responsibilities:
//
// 1. This module does not decide which action should run in a given screen.
//    Callers resolve actions by checking the relevant action binding set.
// 2. This module does not persist configuration; it only resolves loaded config.
//
// Rust splits the module across `keymap.rs` plus the `bindings`, `chords` and `vim_search`
// submodules; V maps a directory to one module, so those submodules live beside this file and are
// visible without a re-export. The Rust `pub(crate) use` re-export block therefore has no V
// counterpart: `KeymapContext`, `bindings_for_action`, `keymap_action_id`, `keymap_action_ids`,
// `runtime_action_bindings`, `KEY_CHORD_TIMEOUT`, `KeyChordMatch`, `KeyChordMatcher`,
// `KeymapContextSet`, `RuntimeChordKeymap` and `VimSearchKeymap` are already module-scoped names.

// Named stand-in for the Rust `(&'static str, &[KeyBinding])` pairs that the validation helpers
// iterate. V has no comparable tuple type, and the slices must be owned because V cannot store a
// borrowed slice in an array element.
pub struct ActionBindings {
pub:
	action   string
	bindings []key_hint.KeyBinding
}

// Rust validation tables contain `&'static str` and borrowed slices, so copying an array of them is
// allocation-free. V stores owned strings and arrays in the translated shape; this helper makes
// that otherwise implicit copy boundary explicit for the one table that is validated twice.
fn clone_action_bindings(pairs &[]ActionBindings) []ActionBindings {
	mut cloned := []ActionBindings{cap: pairs.len}
	for pair in *pairs {
		cloned << ActionBindings{
			action:   pair.action.clone()
			bindings: pair.bindings.clone()
		}
	}
	return cloned
}

// Named stand-in for the Rust `(&'static str, KeyBinding)` reserved-shortcut pairs.
pub struct ReservedBinding {
pub:
	action  string
	binding key_hint.KeyBinding
}

// Named stand-in for the Rust `(&'static str, &'static str, KeyBinding)` allowed-overlap triples.
pub struct AllowedOverlap {
pub:
	primary  string
	shadowed string
	binding  key_hint.KeyBinding
}

// Named stand-in for the Rust `(Option<&KeybindingsSpec>, &[KeyBinding])` pairs consumed by
// `configured_bindings_to_preserve`.
pub struct ConfiguredPair {
pub:
	configured ?types.KeybindingsSpec
	resolved   []key_hint.KeyBinding
}

// Runtime keymap used by TUI input handlers.
//
// Resolution precedence is:
//
// 1. Context-specific binding (`tui.keymap.<context>`).
// 2. `tui.keymap.global` for actions that support global fallback.
// 3. Built-in defaults.
//
// This is the only shape UI code should use for dispatch. It represents a
// fully resolved snapshot with parsing, fallback, explicit unbinding, and
// duplicate-key validation already applied. If a caller keeps using an older
// snapshot after config changes, visible hints and active handlers can drift.
//
// Rust shares `chords` and `editor` through `Arc`; V has no `Arc` equivalent in this tree, so both
// are stored by value. The shared data is immutable after resolution apart from the dispatch-token
// append in `install_dispatch_bindings`, which runs before any clone escapes `from_config`.
pub struct RuntimeKeymap {
pub mut:
	app             AppKeymap
	chords          RuntimeChordKeymap
	chat            ChatKeymap
	composer        ComposerKeymap
	editor          EditorKeymap
	vim_normal      VimNormalKeymap
	vim_operator    VimOperatorKeymap
	vim_search      VimSearchKeymap
	vim_text_object VimTextObjectKeymap
	pager           PagerKeymap
	list            ListKeymap
	agents          AgentsKeymap
	approval        ApprovalKeymap
}

pub struct AppKeymap {
pub mut:
	// Open the daemon-wide agent-session overview.
	open_agents []key_hint.KeyBinding
	// Open transcript overlay.
	open_transcript []key_hint.KeyBinding
	// Open external editor for the current draft.
	open_external_editor []key_hint.KeyBinding
	// Copy the last agent response to the clipboard.
	copy []key_hint.KeyBinding
	// Clear the terminal UI.
	clear_terminal []key_hint.KeyBinding
	// Toggle Vim mode for the composer input.
	toggle_vim_mode []key_hint.KeyBinding
	// Toggle Fast mode.
	toggle_fast_mode []key_hint.KeyBinding
	// Toggle raw scrollback mode for copy-friendly transcript selection.
	toggle_raw_output []key_hint.KeyBinding
	// Switch between a side conversation and its parent without closing either.
	toggle_side_conversation []key_hint.KeyBinding
}

// Chat-level keybindings evaluated at the app event layer.
//
// These participate in the first app-scope conflict validation pass alongside
// `AppKeymap` actions because both are checked before input reaches the
// composer. Dispatch gating (empty-composer guard for backtrack) happens in
// handler code, not here.
pub struct ChatKeymap {
pub mut:
	// Interrupt the active turn.
	interrupt_turn []key_hint.KeyBinding
	// Decrease the active reasoning effort.
	decrease_reasoning_effort []key_hint.KeyBinding
	// Increase the active reasoning effort.
	increase_reasoning_effort []key_hint.KeyBinding
	// Switch to the previous available permission mode.
	previous_permission_mode []key_hint.KeyBinding
	// Switch to the next available permission mode.
	next_permission_mode []key_hint.KeyBinding
	// Move up through async questions, then edit the most recently queued message.
	edit_queued_message []key_hint.KeyBinding
	// Move back through async questions toward the composer.
	prompt_stack_back []key_hint.KeyBinding
	// Skip the focused question.
	skip_question []key_hint.KeyBinding
}

// Composer-level keybindings validated in the second app-scope conflict pass.
//
// App-level handlers execute before the composer receives input, so any key
// bound here that also appears in `AppKeymap` would be silently intercepted.
// The conflict validator prevents this by checking app + composer uniqueness.
pub struct ComposerKeymap {
pub mut:
	// Submit current draft.
	submit []key_hint.KeyBinding
	// Queue current draft while a task is running.
	queue []key_hint.KeyBinding
	// Toggle composer shortcut overlay.
	toggle_shortcuts []key_hint.KeyBinding
	// Open reverse history search or move to the previous match.
	history_search_previous []key_hint.KeyBinding
	// Move to the next match in reverse history search.
	history_search_next []key_hint.KeyBinding
}

// Editor-specific keybindings used by the composer textarea.
//
// These bindings are interpreted only by text-editing widgets and do not
// participate in global/chat fallback resolution.
pub struct EditorKeymap {
pub mut:
	insert_newline       []key_hint.KeyBinding
	move_left            []key_hint.KeyBinding
	move_right           []key_hint.KeyBinding
	move_up              []key_hint.KeyBinding
	move_down            []key_hint.KeyBinding
	move_word_left       []key_hint.KeyBinding
	move_word_right      []key_hint.KeyBinding
	move_line_start      []key_hint.KeyBinding
	move_line_end        []key_hint.KeyBinding
	delete_backward      []key_hint.KeyBinding
	delete_forward       []key_hint.KeyBinding
	delete_backward_word []key_hint.KeyBinding
	delete_forward_word  []key_hint.KeyBinding
	kill_line_start      []key_hint.KeyBinding
	kill_whole_line      []key_hint.KeyBinding
	kill_line_end        []key_hint.KeyBinding
	yank                 []key_hint.KeyBinding
}

// Vim normal-mode keybindings for modal editing in the composer textarea.
//
// Normal mode is the resting state when Vim is enabled. Pressing a movement
// or editing key here either moves the cursor, triggers an operator-pending
// state (via `start_delete_operator`, `start_yank_operator`, or `start_change_operator`), or transitions
// to insert mode. Default bindings include both `shift(letter)` and
// `plain(UPPERCASE)` variants for uppercase commands like `A`, `I`, `O` to
// handle cross-terminal shift-reporting inconsistencies.
pub struct VimNormalKeymap {
pub mut:
	enter_insert          []key_hint.KeyBinding
	append_after_cursor   []key_hint.KeyBinding
	append_line_end       []key_hint.KeyBinding
	insert_line_start     []key_hint.KeyBinding
	open_line_below       []key_hint.KeyBinding
	open_line_above       []key_hint.KeyBinding
	enter_replace_mode    []key_hint.KeyBinding
	move_left             []key_hint.KeyBinding
	move_right            []key_hint.KeyBinding
	move_up               []key_hint.KeyBinding
	move_down             []key_hint.KeyBinding
	move_word_forward     []key_hint.KeyBinding
	move_word_backward    []key_hint.KeyBinding
	move_word_end         []key_hint.KeyBinding
	move_line_start       []key_hint.KeyBinding
	move_line_end         []key_hint.KeyBinding
	find_forward          []key_hint.KeyBinding
	find_backward         []key_hint.KeyBinding
	till_forward          []key_hint.KeyBinding
	till_backward         []key_hint.KeyBinding
	jump_top              []key_hint.KeyBinding
	jump_bottom           []key_hint.KeyBinding
	delete_char           []key_hint.KeyBinding
	replace_char          []key_hint.KeyBinding
	repeat_last_change    []key_hint.KeyBinding
	substitute_char       []key_hint.KeyBinding
	delete_to_line_end    []key_hint.KeyBinding
	change_to_line_end    []key_hint.KeyBinding
	yank_line             []key_hint.KeyBinding
	paste_after           []key_hint.KeyBinding
	start_delete_operator []key_hint.KeyBinding
	start_yank_operator   []key_hint.KeyBinding
	start_change_operator []key_hint.KeyBinding
	undo                  []key_hint.KeyBinding
	redo                  []key_hint.KeyBinding
	cancel_operator       []key_hint.KeyBinding
}

// Vim operator-pending keybindings active after `d`, `y`, or `c` in normal mode.
//
// When a delete, yank, or change operator is
// pressed, the next keypress is matched against this context to determine the
// motion range. Repeating the operator key (`dd`, `yy`) acts on the whole
// line. `Esc` cancels the pending operator and returns to normal mode.
pub struct VimOperatorKeymap {
pub mut:
	delete_line               []key_hint.KeyBinding
	yank_line                 []key_hint.KeyBinding
	motion_left               []key_hint.KeyBinding
	motion_right              []key_hint.KeyBinding
	motion_up                 []key_hint.KeyBinding
	motion_down               []key_hint.KeyBinding
	motion_word_forward       []key_hint.KeyBinding
	motion_word_backward      []key_hint.KeyBinding
	motion_word_end           []key_hint.KeyBinding
	motion_line_start         []key_hint.KeyBinding
	motion_line_end           []key_hint.KeyBinding
	motion_find_forward       []key_hint.KeyBinding
	motion_find_backward      []key_hint.KeyBinding
	motion_till_forward       []key_hint.KeyBinding
	motion_till_backward      []key_hint.KeyBinding
	motion_jump_top           []key_hint.KeyBinding
	motion_jump_bottom        []key_hint.KeyBinding
	select_inner_text_object  []key_hint.KeyBinding
	select_around_text_object []key_hint.KeyBinding
	cancel                    []key_hint.KeyBinding
}

// Vim text-object keybindings active after an operator plus inner/around prefix.
pub struct VimTextObjectKeymap {
pub mut:
	word         []key_hint.KeyBinding
	big_word     []key_hint.KeyBinding
	parentheses  []key_hint.KeyBinding
	brackets     []key_hint.KeyBinding
	braces       []key_hint.KeyBinding
	double_quote []key_hint.KeyBinding
	single_quote []key_hint.KeyBinding
	backtick     []key_hint.KeyBinding
	cancel       []key_hint.KeyBinding
}

// Pager/overlay keybindings for transcript and static help views.
pub struct PagerKeymap {
pub mut:
	scroll_up        []key_hint.KeyBinding
	scroll_down      []key_hint.KeyBinding
	page_up          []key_hint.KeyBinding
	page_down        []key_hint.KeyBinding
	half_page_up     []key_hint.KeyBinding
	half_page_down   []key_hint.KeyBinding
	jump_top         []key_hint.KeyBinding
	jump_bottom      []key_hint.KeyBinding
	close            []key_hint.KeyBinding
	close_transcript []key_hint.KeyBinding
mut:
	chord_hints RuntimeChordKeymap
}

pub fn (resolved_keymap &PagerKeymap) primary_hint(action string, bindings &[]key_hint.KeyBinding) ?key_hint.ShortcutHint {
	action_id := keymap_action_id(KeymapContext.pager.config_name(), action)?
	return resolved_keymap.chord_hints.primary_hint(action_id, bindings)
}

// Semantic navigation and confirmation actions shared by list-like views.
pub enum ListAction {
	move_up
	move_down
	move_left
	move_right
	page_up
	page_down
	jump_top
	jump_bottom
	accept
	cancel
}

fn (action ListAction) config_name() string {
	return match action {
		.move_up { 'move_up' }
		.move_down { 'move_down' }
		.move_left { 'move_left' }
		.move_right { 'move_right' }
		.page_up { 'page_up' }
		.page_down { 'page_down' }
		.jump_top { 'jump_top' }
		.jump_bottom { 'jump_bottom' }
		.accept { 'accept' }
		.cancel { 'cancel' }
	}
}

// Generic list picker keybindings shared across popup list views.
//
// These actions describe list intent rather than a specific widget layout.
// Vertical actions move the highlighted row, page and jump actions move within
// the current filtered row set, and horizontal actions are available to views
// that expose adjacent choices such as tabs, toolbar values, or ordered item
// movement. Views that also accept search text are responsible for checking
// `is_plain_text_key_event` before dispatching plain-character bindings so a
// configured `j`, `k`, `h`, or `l` does not steal query input.
pub struct ListKeymap {
pub mut:
	move_up     []key_hint.KeyBinding
	move_down   []key_hint.KeyBinding
	move_left   []key_hint.KeyBinding
	move_right  []key_hint.KeyBinding
	page_up     []key_hint.KeyBinding
	page_down   []key_hint.KeyBinding
	jump_top    []key_hint.KeyBinding
	jump_bottom []key_hint.KeyBinding
	accept      []key_hint.KeyBinding
	cancel      []key_hint.KeyBinding
mut:
	chord_hints RuntimeChordKeymap
}

// Rust returns a borrowed `&[KeyBinding]`; V has no borrowed-slice return, so the matching action
// list is copied for the caller.
pub fn (resolved_keymap &ListKeymap) bindings_for(action ListAction) []key_hint.KeyBinding {
	return match action {
		.move_up { resolved_keymap.move_up.clone() }
		.move_down { resolved_keymap.move_down.clone() }
		.move_left { resolved_keymap.move_left.clone() }
		.move_right { resolved_keymap.move_right.clone() }
		.page_up { resolved_keymap.page_up.clone() }
		.page_down { resolved_keymap.page_down.clone() }
		.jump_top { resolved_keymap.jump_top.clone() }
		.jump_bottom { resolved_keymap.jump_bottom.clone() }
		.accept { resolved_keymap.accept.clone() }
		.cancel { resolved_keymap.cancel.clone() }
	}
}

pub fn (resolved_keymap &ListKeymap) action_for(input event.KeyEvent) ?ListAction {
	for action in [ListAction.move_up, .move_down, .move_left, .move_right, .page_up, .page_down,
		.jump_top, .jump_bottom, .accept, .cancel] {
		bindings := resolved_keymap.bindings_for(action)
		if key_hint.bindings_are_pressed(&bindings, input) {
			return action
		}
	}
	return none
}

pub fn (resolved_keymap &ListKeymap) primary_hint(action ListAction) ?key_hint.ShortcutHint {
	action_id := keymap_action_id(KeymapContext.list.config_name(), action.config_name())?
	bindings := resolved_keymap.bindings_for(action)
	return resolved_keymap.chord_hints.primary_hint(action_id, &bindings)
}

// Task-management shortcuts specific to the shared agents dashboard.
pub struct AgentsKeymap {
pub mut:
	resume          []key_hint.KeyBinding
	search          []key_hint.KeyBinding
	new_task        []key_hint.KeyBinding
	rename          []key_hint.KeyBinding
	stop            []key_hint.KeyBinding
	toggle_grouping []key_hint.KeyBinding
mut:
	chord_hints RuntimeChordKeymap
}

pub fn (resolved_keymap &AgentsKeymap) primary_hint(action string, bindings &[]key_hint.KeyBinding) ?key_hint.ShortcutHint {
	action_id := keymap_action_id(KeymapContext.agents.config_name(), action)?
	return resolved_keymap.chord_hints.primary_hint(action_id, bindings)
}

// Approval modal keybindings.
//
// This covers both selection actions and the "open details fullscreen" escape
// hatch for large approval payloads.
pub struct ApprovalKeymap {
pub mut:
	open_fullscreen     []key_hint.KeyBinding
	open_thread         []key_hint.KeyBinding
	approve             []key_hint.KeyBinding
	approve_for_session []key_hint.KeyBinding
	approve_for_prefix  []key_hint.KeyBinding
	deny                []key_hint.KeyBinding
	decline             []key_hint.KeyBinding
	cancel              []key_hint.KeyBinding
mut:
	chord_hints RuntimeChordKeymap
}

pub fn (resolved_keymap &ApprovalKeymap) primary_hint(action string, bindings &[]key_hint.KeyBinding) ?key_hint.ShortcutHint {
	action_id := keymap_action_id(KeymapContext.approval.config_name(), action)?
	return resolved_keymap.chord_hints.primary_hint(action_id, bindings)
}

pub fn (resolved_keymap &ApprovalKeymap) hint_for_bindings(bindings &[]key_hint.KeyBinding) ?key_hint.ShortcutHint {
	for candidate in [
		ActionBindings{
			action:   'open_fullscreen'
			bindings: resolved_keymap.open_fullscreen.clone()
		},
		ActionBindings{
			action:   'open_thread'
			bindings: resolved_keymap.open_thread.clone()
		},
		ActionBindings{
			action:   'approve'
			bindings: resolved_keymap.approve.clone()
		},
		ActionBindings{
			action:   'approve_for_session'
			bindings: resolved_keymap.approve_for_session.clone()
		},
		ActionBindings{
			action:   'approve_for_prefix'
			bindings: resolved_keymap.approve_for_prefix.clone()
		},
		ActionBindings{
			action:   'deny'
			bindings: resolved_keymap.deny.clone()
		},
		ActionBindings{
			action:   'decline'
			bindings: resolved_keymap.decline.clone()
		},
		ActionBindings{
			action:   'cancel'
			bindings: resolved_keymap.cancel.clone()
		},
	] {
		if bindings.len == 0 {
			continue
		}
		mut all_configured := true
		for binding in *bindings {
			if binding !in candidate.bindings {
				all_configured = false
				break
			}
		}
		if !all_configured {
			continue
		}
		if hint := resolved_keymap.primary_hint(candidate.action, &candidate.bindings) {
			return hint
		}
	}
	if binding := primary_binding(bindings) {
		return key_hint.ShortcutHint.from_binding(binding)
	}
	return none
}

// Returns the first binding, used as the primary UI hint for an action.
//
// Rendering code should prefer this for concise hints while preserving all
// bindings for actual input matching.
pub fn primary_binding(bindings &[]key_hint.KeyBinding) ?key_hint.KeyBinding {
	user := user_bindings(*bindings)
	if user.len == 0 {
		return none
	}
	return user[0]
}

// Remove the trailing internal dispatch token, when present.
//
// Rust returns a borrowed subslice; V has no borrowed-slice return, so the retained prefix is
// copied.
pub fn user_bindings(bindings []key_hint.KeyBinding) []key_hint.KeyBinding {
	if bindings.len > 0 && is_dispatch_token(bindings[bindings.len - 1]) {
		return bindings[..bindings.len - 1].clone()
	}
	return bindings.clone()
}

// Resolve one context-local action binding from config.
//
// Rust wraps this in the `resolve_local!` macro with:
// - configured source: `tui.keymap.<context>.<action>`
// - fallback source: the same action from built-in defaults
// - error path: a stable string path for user-facing diagnostics
//
// V has no macro expansion, so each call below is written out with the same three arguments; the
// path string still mirrors the field names exactly.
//
// The companion `resolve_with_global!` macro resolves one action binding with precedence:
// 1. `tui.keymap.<context>.<action>`
// 2. `tui.keymap.global.<action>`
// 3. built-in defaults for `<context>.<action>`
//
// It is used only for actions that intentionally support global reuse.
// Context-local empty lists still count as configured values, so they unbind
// the action instead of falling back to `global`.
//
// Rust also declares `default_binding!`/`default_bindings!` to expand one default-table entry into
// a [`key_hint.KeyBinding`]. The supported forms are `plain(<KeyCode>)`, `ctrl(<KeyCode>)`,
// `alt(<KeyCode>)`, `shift(<KeyCode>)` and `raw(<KeyBinding expression>)` for bindings that do not
// match the helpers (for example combined modifiers like Ctrl+Shift). Those macros are
// intentionally scoped to built-in keymaps: runtime config parsing still goes through
// `parse_bindings(...)` so user errors can be reported with config-path-aware diagnostics. In V the
// default tables below call `key_hint.plain`/`ctrl`/`alt`/`shift` and `key_hint.KeyBinding.new`
// directly.

// Return built-in defaults.
//
// This is a convenience for tests and bootstrapping UI state before user
// config has been loaded. It should not be used as a fallback after
// parsing `TuiKeymap`, because doing so would ignore explicit user
// unbindings and conflict diagnostics.
//
// Rust memoizes the resolved value in a `OnceLock` and clones it. V has no equivalent lazy static
// in this tree, so the defaults are resolved on each call; the result is identical because
// `TuiKeymap` defaults are constant.
pub fn RuntimeKeymap.defaults() RuntimeKeymap {
	return RuntimeKeymap.from_config(&types.TuiKeymap{}) or {
		panic('built-in keymap defaults must be valid: ${err.msg()}')
	}
}

// Resolve a runtime keymap from config, applying precedence and validation.
//
// Returns an error when:
//
// 1. A keybinding spec cannot be parsed.
// 2. A context has ambiguous bindings (same key assigned to multiple actions).
//
// The error text includes the relevant config path and a concrete next step.
// Calling code should not merge bindings across unrelated contexts before
// dispatch, or conflict guarantees from this resolver no longer hold.
pub fn RuntimeKeymap.from_config(resolved_keymap &types.TuiKeymap) !RuntimeKeymap {
	defaults := RuntimeKeymap.built_in_defaults()
	chords := RuntimeChordKeymap.from_config(resolved_keymap)!
	mut side_toggle_default_is_shadowed := false
	if resolved_keymap.global.toggle_side_conversation == none {
		for alias in ['ctrl-/', 'ctrl-7'] {
			if configured_main_surface_alias_is_used(resolved_keymap, alias.clone())
				|| configured_context_alias_is_used(&resolved_keymap.list, alias.clone())
				|| configured_context_alias_is_used(&resolved_keymap.approval, alias) {
				side_toggle_default_is_shadowed = true
				break
			}
		}
	}
	mut resolved_toggle_side_conversation := []key_hint.KeyBinding{}
	if !side_toggle_default_is_shadowed {
		resolved_toggle_side_conversation = resolve_bindings(resolved_keymap.global.toggle_side_conversation, &defaults.app.toggle_side_conversation, 'tui.keymap.global.toggle_side_conversation')!
	}
	app := AppKeymap{
		open_agents:              resolve_bindings(resolved_keymap.global.open_agents, &defaults.app.open_agents, 'tui.keymap.global.open_agents')!
		open_transcript:          resolve_bindings(resolved_keymap.global.open_transcript, &defaults.app.open_transcript, 'tui.keymap.global.open_transcript')!
		open_external_editor:     resolve_bindings(resolved_keymap.global.open_external_editor, &defaults.app.open_external_editor, 'tui.keymap.global.open_external_editor')!
		copy:                     resolve_bindings(resolved_keymap.global.copy, &defaults.app.copy, 'tui.keymap.global.copy')!
		clear_terminal:           resolve_bindings(resolved_keymap.global.clear_terminal, &defaults.app.clear_terminal, 'tui.keymap.global.clear_terminal')!
		toggle_vim_mode:          resolve_bindings(resolved_keymap.global.toggle_vim_mode, &defaults.app.toggle_vim_mode, 'tui.keymap.global.toggle_vim_mode')!
		toggle_fast_mode:         resolve_bindings(resolved_keymap.global.toggle_fast_mode, &defaults.app.toggle_fast_mode, 'tui.keymap.global.toggle_fast_mode')!
		toggle_raw_output:        resolve_bindings(resolved_keymap.global.toggle_raw_output, &defaults.app.toggle_raw_output, 'tui.keymap.global.toggle_raw_output')!
		toggle_side_conversation: resolved_toggle_side_conversation
	}

	mut chat := ChatKeymap{
		interrupt_turn:            resolve_bindings(resolved_keymap.chat.interrupt_turn, &defaults.chat.interrupt_turn, 'tui.keymap.chat.interrupt_turn')!
		decrease_reasoning_effort: resolve_bindings(resolved_keymap.chat.decrease_reasoning_effort, &defaults.chat.decrease_reasoning_effort, 'tui.keymap.chat.decrease_reasoning_effort')!
		increase_reasoning_effort: resolve_bindings(resolved_keymap.chat.increase_reasoning_effort, &defaults.chat.increase_reasoning_effort, 'tui.keymap.chat.increase_reasoning_effort')!
		previous_permission_mode:  resolve_bindings(resolved_keymap.chat.previous_permission_mode, &defaults.chat.previous_permission_mode, 'tui.keymap.chat.previous_permission_mode')!
		next_permission_mode:      resolve_bindings(resolved_keymap.chat.next_permission_mode, &defaults.chat.next_permission_mode, 'tui.keymap.chat.next_permission_mode')!
		edit_queued_message:       resolve_bindings(resolved_keymap.chat.edit_queued_message, &defaults.chat.edit_queued_message, 'tui.keymap.chat.edit_queued_message')!
		prompt_stack_back:         resolve_bindings(resolved_keymap.chat.prompt_stack_back, &defaults.chat.prompt_stack_back, 'tui.keymap.chat.prompt_stack_back')!
		skip_question:             resolve_bindings(resolved_keymap.chat.skip_question, &defaults.chat.skip_question, 'tui.keymap.chat.skip_question')!
	}

	composer := ComposerKeymap{
		submit:                  resolve_bindings_with_global_fallback(resolved_keymap.composer.submit, resolved_keymap.global.submit, &defaults.composer.submit, 'tui.keymap.composer.submit')!
		queue:                   resolve_bindings_with_global_fallback(resolved_keymap.composer.queue, resolved_keymap.global.queue, &defaults.composer.queue, 'tui.keymap.composer.queue')!
		toggle_shortcuts:        resolve_bindings_with_global_fallback(resolved_keymap.composer.toggle_shortcuts, resolved_keymap.global.toggle_shortcuts, &defaults.composer.toggle_shortcuts, 'tui.keymap.composer.toggle_shortcuts')!
		history_search_previous: resolve_bindings(resolved_keymap.composer.history_search_previous, &defaults.composer.history_search_previous, 'tui.keymap.composer.history_search_previous')!
		history_search_next:     resolve_bindings(resolved_keymap.composer.history_search_next, &defaults.composer.history_search_next, 'tui.keymap.composer.history_search_next')!
	}

	editor := EditorKeymap{
		insert_newline:       resolve_bindings(resolved_keymap.editor.insert_newline, &defaults.editor.insert_newline, 'tui.keymap.editor.insert_newline')!
		move_left:            resolve_bindings(resolved_keymap.editor.move_left, &defaults.editor.move_left, 'tui.keymap.editor.move_left')!
		move_right:           resolve_bindings(resolved_keymap.editor.move_right, &defaults.editor.move_right, 'tui.keymap.editor.move_right')!
		move_up:              resolve_bindings(resolved_keymap.editor.move_up, &defaults.editor.move_up, 'tui.keymap.editor.move_up')!
		move_down:            resolve_bindings(resolved_keymap.editor.move_down, &defaults.editor.move_down, 'tui.keymap.editor.move_down')!
		move_word_left:       resolve_bindings(resolved_keymap.editor.move_word_left, &defaults.editor.move_word_left, 'tui.keymap.editor.move_word_left')!
		move_word_right:      resolve_bindings(resolved_keymap.editor.move_word_right, &defaults.editor.move_word_right, 'tui.keymap.editor.move_word_right')!
		move_line_start:      resolve_bindings(resolved_keymap.editor.move_line_start, &defaults.editor.move_line_start, 'tui.keymap.editor.move_line_start')!
		move_line_end:        resolve_bindings(resolved_keymap.editor.move_line_end, &defaults.editor.move_line_end, 'tui.keymap.editor.move_line_end')!
		delete_backward:      resolve_bindings(resolved_keymap.editor.delete_backward, &defaults.editor.delete_backward, 'tui.keymap.editor.delete_backward')!
		delete_forward:       resolve_bindings(resolved_keymap.editor.delete_forward, &defaults.editor.delete_forward, 'tui.keymap.editor.delete_forward')!
		delete_backward_word: resolve_bindings(resolved_keymap.editor.delete_backward_word, &defaults.editor.delete_backward_word, 'tui.keymap.editor.delete_backward_word')!
		delete_forward_word:  resolve_bindings(resolved_keymap.editor.delete_forward_word, &defaults.editor.delete_forward_word, 'tui.keymap.editor.delete_forward_word')!
		kill_line_start:      resolve_bindings(resolved_keymap.editor.kill_line_start, &defaults.editor.kill_line_start, 'tui.keymap.editor.kill_line_start')!
		kill_whole_line:      resolve_bindings(resolved_keymap.editor.kill_whole_line, &defaults.editor.kill_whole_line, 'tui.keymap.editor.kill_whole_line')!
		kill_line_end:        resolve_bindings(resolved_keymap.editor.kill_line_end, &defaults.editor.kill_line_end, 'tui.keymap.editor.kill_line_end')!
		yank:                 resolve_bindings(resolved_keymap.editor.yank, &defaults.editor.yank, 'tui.keymap.editor.yank')!
	}

	mut vim_normal := VimNormalKeymap{
		enter_insert:          resolve_bindings(resolved_keymap.vim_normal.enter_insert, &defaults.vim_normal.enter_insert, 'tui.keymap.vim_normal.enter_insert')!
		append_after_cursor:   resolve_bindings(resolved_keymap.vim_normal.append_after_cursor, &defaults.vim_normal.append_after_cursor, 'tui.keymap.vim_normal.append_after_cursor')!
		append_line_end:       resolve_bindings(resolved_keymap.vim_normal.append_line_end, &defaults.vim_normal.append_line_end, 'tui.keymap.vim_normal.append_line_end')!
		insert_line_start:     resolve_bindings(resolved_keymap.vim_normal.insert_line_start, &defaults.vim_normal.insert_line_start, 'tui.keymap.vim_normal.insert_line_start')!
		open_line_below:       resolve_bindings(resolved_keymap.vim_normal.open_line_below, &defaults.vim_normal.open_line_below, 'tui.keymap.vim_normal.open_line_below')!
		open_line_above:       resolve_bindings(resolved_keymap.vim_normal.open_line_above, &defaults.vim_normal.open_line_above, 'tui.keymap.vim_normal.open_line_above')!
		enter_replace_mode:    resolve_bindings(resolved_keymap.vim_normal.enter_replace_mode, &defaults.vim_normal.enter_replace_mode, 'tui.keymap.vim_normal.enter_replace_mode')!
		move_left:             resolve_bindings(resolved_keymap.vim_normal.move_left, &defaults.vim_normal.move_left, 'tui.keymap.vim_normal.move_left')!
		move_right:            resolve_bindings(resolved_keymap.vim_normal.move_right, &defaults.vim_normal.move_right, 'tui.keymap.vim_normal.move_right')!
		move_up:               resolve_bindings(resolved_keymap.vim_normal.move_up, &defaults.vim_normal.move_up, 'tui.keymap.vim_normal.move_up')!
		move_down:             resolve_bindings(resolved_keymap.vim_normal.move_down, &defaults.vim_normal.move_down, 'tui.keymap.vim_normal.move_down')!
		move_word_forward:     resolve_bindings(resolved_keymap.vim_normal.move_word_forward, &defaults.vim_normal.move_word_forward, 'tui.keymap.vim_normal.move_word_forward')!
		move_word_backward:    resolve_bindings(resolved_keymap.vim_normal.move_word_backward, &defaults.vim_normal.move_word_backward, 'tui.keymap.vim_normal.move_word_backward')!
		move_word_end:         resolve_bindings(resolved_keymap.vim_normal.move_word_end, &defaults.vim_normal.move_word_end, 'tui.keymap.vim_normal.move_word_end')!
		move_line_start:       resolve_bindings(resolved_keymap.vim_normal.move_line_start, &defaults.vim_normal.move_line_start, 'tui.keymap.vim_normal.move_line_start')!
		move_line_end:         resolve_bindings(resolved_keymap.vim_normal.move_line_end, &defaults.vim_normal.move_line_end, 'tui.keymap.vim_normal.move_line_end')!
		find_forward:          resolve_bindings(resolved_keymap.vim_normal.find_forward, &defaults.vim_normal.find_forward, 'tui.keymap.vim_normal.find_forward')!
		find_backward:         resolve_bindings(resolved_keymap.vim_normal.find_backward, &defaults.vim_normal.find_backward, 'tui.keymap.vim_normal.find_backward')!
		till_forward:          resolve_bindings(resolved_keymap.vim_normal.till_forward, &defaults.vim_normal.till_forward, 'tui.keymap.vim_normal.till_forward')!
		till_backward:         resolve_bindings(resolved_keymap.vim_normal.till_backward, &defaults.vim_normal.till_backward, 'tui.keymap.vim_normal.till_backward')!
		jump_top:              resolve_bindings(resolved_keymap.vim_normal.jump_top, &defaults.vim_normal.jump_top, 'tui.keymap.vim_normal.jump_top')!
		jump_bottom:           resolve_bindings(resolved_keymap.vim_normal.jump_bottom, &defaults.vim_normal.jump_bottom, 'tui.keymap.vim_normal.jump_bottom')!
		delete_char:           resolve_bindings(resolved_keymap.vim_normal.delete_char, &defaults.vim_normal.delete_char, 'tui.keymap.vim_normal.delete_char')!
		replace_char:          resolve_bindings(resolved_keymap.vim_normal.replace_char, &defaults.vim_normal.replace_char, 'tui.keymap.vim_normal.replace_char')!
		repeat_last_change:    resolve_bindings(resolved_keymap.vim_normal.repeat_last_change, &defaults.vim_normal.repeat_last_change, 'tui.keymap.vim_normal.repeat_last_change')!
		substitute_char:       resolve_bindings(resolved_keymap.vim_normal.substitute_char, &defaults.vim_normal.substitute_char, 'tui.keymap.vim_normal.substitute_char')!
		delete_to_line_end:    resolve_bindings(resolved_keymap.vim_normal.delete_to_line_end, &defaults.vim_normal.delete_to_line_end, 'tui.keymap.vim_normal.delete_to_line_end')!
		change_to_line_end:    resolve_bindings(resolved_keymap.vim_normal.change_to_line_end, &defaults.vim_normal.change_to_line_end, 'tui.keymap.vim_normal.change_to_line_end')!
		yank_line:             resolve_bindings(resolved_keymap.vim_normal.yank_line, &defaults.vim_normal.yank_line, 'tui.keymap.vim_normal.yank_line')!
		paste_after:           resolve_bindings(resolved_keymap.vim_normal.paste_after, &defaults.vim_normal.paste_after, 'tui.keymap.vim_normal.paste_after')!
		start_delete_operator: resolve_bindings(resolved_keymap.vim_normal.start_delete_operator, &defaults.vim_normal.start_delete_operator, 'tui.keymap.vim_normal.start_delete_operator')!
		start_yank_operator:   resolve_bindings(resolved_keymap.vim_normal.start_yank_operator, &defaults.vim_normal.start_yank_operator, 'tui.keymap.vim_normal.start_yank_operator')!
		start_change_operator: resolve_bindings(resolved_keymap.vim_normal.start_change_operator, &defaults.vim_normal.start_change_operator, 'tui.keymap.vim_normal.start_change_operator')!
		undo:                  resolve_bindings(resolved_keymap.vim_normal.undo, &defaults.vim_normal.undo, 'tui.keymap.vim_normal.undo')!
		redo:                  resolve_bindings(resolved_keymap.vim_normal.redo, &defaults.vim_normal.redo, 'tui.keymap.vim_normal.redo')!
		cancel_operator:       resolve_bindings(resolved_keymap.vim_normal.cancel_operator, &defaults.vim_normal.cancel_operator, 'tui.keymap.vim_normal.cancel_operator')!
	}

	configured_vim_normal_bindings_to_preserve := configured_bindings_to_preserve([
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.enter_insert
			resolved:   vim_normal.enter_insert.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.append_after_cursor
			resolved:   vim_normal.append_after_cursor.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.append_line_end
			resolved:   vim_normal.append_line_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.insert_line_start
			resolved:   vim_normal.insert_line_start.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.open_line_below
			resolved:   vim_normal.open_line_below.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.open_line_above
			resolved:   vim_normal.open_line_above.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.enter_replace_mode
			resolved:   vim_normal.enter_replace_mode.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_left
			resolved:   vim_normal.move_left.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_right
			resolved:   vim_normal.move_right.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_up
			resolved:   vim_normal.move_up.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_down
			resolved:   vim_normal.move_down.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_word_forward
			resolved:   vim_normal.move_word_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_word_backward
			resolved:   vim_normal.move_word_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_word_end
			resolved:   vim_normal.move_word_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_line_start
			resolved:   vim_normal.move_line_start.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.move_line_end
			resolved:   vim_normal.move_line_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.find_forward
			resolved:   vim_normal.find_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.find_backward
			resolved:   vim_normal.find_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.till_forward
			resolved:   vim_normal.till_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.till_backward
			resolved:   vim_normal.till_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.jump_top
			resolved:   vim_normal.jump_top.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.jump_bottom
			resolved:   vim_normal.jump_bottom.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.delete_char
			resolved:   vim_normal.delete_char.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.replace_char
			resolved:   vim_normal.replace_char.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.substitute_char
			resolved:   vim_normal.substitute_char.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.repeat_last_change
			resolved:   vim_normal.repeat_last_change.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.change_to_line_end
			resolved:   vim_normal.change_to_line_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.delete_to_line_end
			resolved:   vim_normal.delete_to_line_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.yank_line
			resolved:   vim_normal.yank_line.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.paste_after
			resolved:   vim_normal.paste_after.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.start_delete_operator
			resolved:   vim_normal.start_delete_operator.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.start_yank_operator
			resolved:   vim_normal.start_yank_operator.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.start_change_operator
			resolved:   vim_normal.start_change_operator.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.undo
			resolved:   vim_normal.undo.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.redo
			resolved:   vim_normal.redo.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_normal.cancel_operator
			resolved:   vim_normal.cancel_operator.clone()
		},
	])

	if resolved_keymap.vim_normal.start_change_operator == none {
		vim_normal.start_change_operator = retain_not_in(vim_normal.start_change_operator, configured_vim_normal_bindings_to_preserve)
	}
	if resolved_keymap.vim_normal.substitute_char == none {
		vim_normal.substitute_char = retain_not_in(vim_normal.substitute_char, configured_vim_normal_bindings_to_preserve)
	}
	if resolved_keymap.vim_normal.replace_char == none {
		mut retained := []key_hint.KeyBinding{}
		for binding in vim_normal.replace_char {
			if binding !in configured_vim_normal_bindings_to_preserve
				&& !chord_prefix_parts_in_context(chords, .vim_normal, binding) {
				retained << binding
			}
		}
		vim_normal.replace_char = retained
	}
	if resolved_keymap.vim_normal.repeat_last_change == none {
		mut retained := []key_hint.KeyBinding{}
		for binding in vim_normal.repeat_last_change {
			if binding !in configured_vim_normal_bindings_to_preserve
				&& !chord_prefix_parts_in_context(chords, .vim_normal, binding) {
				retained << binding
			}
		}
		vim_normal.repeat_last_change = retained
	}
	// Rust walks `[(Option<&KeybindingsSpec>, &mut Vec<KeyBinding>); 6]` here. V cannot build an
	// array of mutable field references, so the same body runs per slot in the source order.
	vim_normal.find_forward = retain_new_default_vim_bindings(resolved_keymap.vim_normal.find_forward, vim_normal.find_forward, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	vim_normal.find_backward = retain_new_default_vim_bindings(resolved_keymap.vim_normal.find_backward, vim_normal.find_backward, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	vim_normal.till_forward = retain_new_default_vim_bindings(resolved_keymap.vim_normal.till_forward, vim_normal.till_forward, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	vim_normal.till_backward = retain_new_default_vim_bindings(resolved_keymap.vim_normal.till_backward, vim_normal.till_backward, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	vim_normal.jump_top = retain_new_default_vim_bindings(resolved_keymap.vim_normal.jump_top, vim_normal.jump_top, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	vim_normal.jump_bottom = retain_new_default_vim_bindings(resolved_keymap.vim_normal.jump_bottom, vim_normal.jump_bottom, configured_vim_normal_bindings_to_preserve, chords, .vim_normal)
	mut vim_operator := VimOperatorKeymap{
		delete_line:               resolve_bindings(resolved_keymap.vim_operator.delete_line, &defaults.vim_operator.delete_line, 'tui.keymap.vim_operator.delete_line')!
		yank_line:                 resolve_bindings(resolved_keymap.vim_operator.yank_line, &defaults.vim_operator.yank_line, 'tui.keymap.vim_operator.yank_line')!
		motion_left:               resolve_bindings(resolved_keymap.vim_operator.motion_left, &defaults.vim_operator.motion_left, 'tui.keymap.vim_operator.motion_left')!
		motion_right:              resolve_bindings(resolved_keymap.vim_operator.motion_right, &defaults.vim_operator.motion_right, 'tui.keymap.vim_operator.motion_right')!
		motion_up:                 resolve_bindings(resolved_keymap.vim_operator.motion_up, &defaults.vim_operator.motion_up, 'tui.keymap.vim_operator.motion_up')!
		motion_down:               resolve_bindings(resolved_keymap.vim_operator.motion_down, &defaults.vim_operator.motion_down, 'tui.keymap.vim_operator.motion_down')!
		motion_word_forward:       resolve_bindings(resolved_keymap.vim_operator.motion_word_forward, &defaults.vim_operator.motion_word_forward, 'tui.keymap.vim_operator.motion_word_forward')!
		motion_word_backward:      resolve_bindings(resolved_keymap.vim_operator.motion_word_backward, &defaults.vim_operator.motion_word_backward, 'tui.keymap.vim_operator.motion_word_backward')!
		motion_word_end:           resolve_bindings(resolved_keymap.vim_operator.motion_word_end, &defaults.vim_operator.motion_word_end, 'tui.keymap.vim_operator.motion_word_end')!
		motion_line_start:         resolve_bindings(resolved_keymap.vim_operator.motion_line_start, &defaults.vim_operator.motion_line_start, 'tui.keymap.vim_operator.motion_line_start')!
		motion_line_end:           resolve_bindings(resolved_keymap.vim_operator.motion_line_end, &defaults.vim_operator.motion_line_end, 'tui.keymap.vim_operator.motion_line_end')!
		motion_find_forward:       resolve_bindings(resolved_keymap.vim_operator.motion_find_forward, &defaults.vim_operator.motion_find_forward, 'tui.keymap.vim_operator.motion_find_forward')!
		motion_find_backward:      resolve_bindings(resolved_keymap.vim_operator.motion_find_backward, &defaults.vim_operator.motion_find_backward, 'tui.keymap.vim_operator.motion_find_backward')!
		motion_till_forward:       resolve_bindings(resolved_keymap.vim_operator.motion_till_forward, &defaults.vim_operator.motion_till_forward, 'tui.keymap.vim_operator.motion_till_forward')!
		motion_till_backward:      resolve_bindings(resolved_keymap.vim_operator.motion_till_backward, &defaults.vim_operator.motion_till_backward, 'tui.keymap.vim_operator.motion_till_backward')!
		motion_jump_top:           resolve_bindings(resolved_keymap.vim_operator.motion_jump_top, &defaults.vim_operator.motion_jump_top, 'tui.keymap.vim_operator.motion_jump_top')!
		motion_jump_bottom:        resolve_bindings(resolved_keymap.vim_operator.motion_jump_bottom, &defaults.vim_operator.motion_jump_bottom, 'tui.keymap.vim_operator.motion_jump_bottom')!
		select_inner_text_object:  resolve_bindings(resolved_keymap.vim_operator.select_inner_text_object, &defaults.vim_operator.select_inner_text_object, 'tui.keymap.vim_operator.select_inner_text_object')!
		select_around_text_object: resolve_bindings(resolved_keymap.vim_operator.select_around_text_object, &defaults.vim_operator.select_around_text_object, 'tui.keymap.vim_operator.select_around_text_object')!
		cancel:                    resolve_bindings(resolved_keymap.vim_operator.cancel, &defaults.vim_operator.cancel, 'tui.keymap.vim_operator.cancel')!
	}

	configured_vim_operator_bindings_to_preserve := configured_bindings_to_preserve([
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.delete_line
			resolved:   vim_operator.delete_line.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.yank_line
			resolved:   vim_operator.yank_line.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_left
			resolved:   vim_operator.motion_left.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_right
			resolved:   vim_operator.motion_right.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_up
			resolved:   vim_operator.motion_up.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_down
			resolved:   vim_operator.motion_down.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_word_forward
			resolved:   vim_operator.motion_word_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_word_backward
			resolved:   vim_operator.motion_word_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_word_end
			resolved:   vim_operator.motion_word_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_line_start
			resolved:   vim_operator.motion_line_start.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_line_end
			resolved:   vim_operator.motion_line_end.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_find_forward
			resolved:   vim_operator.motion_find_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_find_backward
			resolved:   vim_operator.motion_find_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_till_forward
			resolved:   vim_operator.motion_till_forward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_till_backward
			resolved:   vim_operator.motion_till_backward.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_jump_top
			resolved:   vim_operator.motion_jump_top.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.motion_jump_bottom
			resolved:   vim_operator.motion_jump_bottom.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.vim_operator.cancel
			resolved:   vim_operator.cancel.clone()
		},
	])

	if resolved_keymap.vim_operator.select_inner_text_object == none {
		vim_operator.select_inner_text_object = retain_not_in(vim_operator.select_inner_text_object, configured_vim_operator_bindings_to_preserve)
	}
	if resolved_keymap.vim_operator.select_around_text_object == none {
		vim_operator.select_around_text_object = retain_not_in(vim_operator.select_around_text_object, configured_vim_operator_bindings_to_preserve)
	}
	// Same `[(Option<&KeybindingsSpec>, &mut Vec<KeyBinding>); 6]` walk as the normal-mode block.
	vim_operator.motion_find_forward = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_find_forward, vim_operator.motion_find_forward, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)
	vim_operator.motion_find_backward = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_find_backward, vim_operator.motion_find_backward, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)
	vim_operator.motion_till_forward = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_till_forward, vim_operator.motion_till_forward, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)
	vim_operator.motion_till_backward = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_till_backward, vim_operator.motion_till_backward, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)
	vim_operator.motion_jump_top = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_jump_top, vim_operator.motion_jump_top, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)
	vim_operator.motion_jump_bottom = retain_new_default_vim_bindings(resolved_keymap.vim_operator.motion_jump_bottom, vim_operator.motion_jump_bottom, configured_vim_operator_bindings_to_preserve, chords, .vim_operator)

	vim_text_object := VimTextObjectKeymap{
		word:         resolve_bindings(resolved_keymap.vim_text_object.word, &defaults.vim_text_object.word, 'tui.keymap.vim_text_object.word')!
		big_word:     resolve_bindings(resolved_keymap.vim_text_object.big_word, &defaults.vim_text_object.big_word, 'tui.keymap.vim_text_object.big_word')!
		parentheses:  resolve_bindings(resolved_keymap.vim_text_object.parentheses, &defaults.vim_text_object.parentheses, 'tui.keymap.vim_text_object.parentheses')!
		brackets:     resolve_bindings(resolved_keymap.vim_text_object.brackets, &defaults.vim_text_object.brackets, 'tui.keymap.vim_text_object.brackets')!
		braces:       resolve_bindings(resolved_keymap.vim_text_object.braces, &defaults.vim_text_object.braces, 'tui.keymap.vim_text_object.braces')!
		double_quote: resolve_bindings(resolved_keymap.vim_text_object.double_quote, &defaults.vim_text_object.double_quote, 'tui.keymap.vim_text_object.double_quote')!
		single_quote: resolve_bindings(resolved_keymap.vim_text_object.single_quote, &defaults.vim_text_object.single_quote, 'tui.keymap.vim_text_object.single_quote')!
		backtick:     resolve_bindings(resolved_keymap.vim_text_object.backtick, &defaults.vim_text_object.backtick, 'tui.keymap.vim_text_object.backtick')!
		cancel:       resolve_bindings(resolved_keymap.vim_text_object.cancel, &defaults.vim_text_object.cancel, 'tui.keymap.vim_text_object.cancel')!
	}

	// New question shortcuts yield individually to existing explicit bindings.
	// Rust iterates `[(Option<&KeybindingsSpec>, &mut Vec<KeyBinding>, Vec<(alias, KeyBinding)>); 2]`.
	chat.prompt_stack_back = retain_new_question_shortcut_bindings(resolved_keymap.chat.prompt_stack_back, chat.prompt_stack_back, [
		ChatAliasDefault{
			alias:     'alt-down'
			candidate: key_hint.alt(event.key_code_down)
		},
		ChatAliasDefault{
			alias:     'shift-right'
			candidate: key_hint.shift(event.key_code_right)
		},
	], resolved_keymap, chords)
	chat.skip_question = retain_new_question_shortcut_bindings(resolved_keymap.chat.skip_question, chat.skip_question, [
		ChatAliasDefault{
			alias:     'ctrl-]'
			candidate: key_hint.ctrl(event.KeyCode.char_key(`]`))
		},
	], resolved_keymap, chords)

	// Reasoning arrow aliases are fallback defaults: existing explicit
	// bindings on the same input path keep the keys, while explicit
	// reasoning bindings remain authoritative.
	if resolved_keymap.chat.decrease_reasoning_effort == none
		&& configured_main_surface_alias_is_used(resolved_keymap, 'shift-down') {
		chat.decrease_reasoning_effort = retain_not_equal(chat.decrease_reasoning_effort, key_hint.shift(event.key_code_down))
	}
	if resolved_keymap.chat.increase_reasoning_effort == none
		&& configured_main_surface_alias_is_used(resolved_keymap, 'shift-up') {
		chat.increase_reasoning_effort = retain_not_equal(chat.increase_reasoning_effort, key_hint.shift(event.key_code_up))
	}

	pager := PagerKeymap{
		scroll_up:        resolve_bindings(resolved_keymap.pager.scroll_up, &defaults.pager.scroll_up, 'tui.keymap.pager.scroll_up')!
		scroll_down:      resolve_bindings(resolved_keymap.pager.scroll_down, &defaults.pager.scroll_down, 'tui.keymap.pager.scroll_down')!
		page_up:          resolve_bindings(resolved_keymap.pager.page_up, &defaults.pager.page_up, 'tui.keymap.pager.page_up')!
		page_down:        resolve_bindings(resolved_keymap.pager.page_down, &defaults.pager.page_down, 'tui.keymap.pager.page_down')!
		half_page_up:     resolve_bindings(resolved_keymap.pager.half_page_up, &defaults.pager.half_page_up, 'tui.keymap.pager.half_page_up')!
		half_page_down:   resolve_bindings(resolved_keymap.pager.half_page_down, &defaults.pager.half_page_down, 'tui.keymap.pager.half_page_down')!
		jump_top:         resolve_bindings(resolved_keymap.pager.jump_top, &defaults.pager.jump_top, 'tui.keymap.pager.jump_top')!
		jump_bottom:      resolve_bindings(resolved_keymap.pager.jump_bottom, &defaults.pager.jump_bottom, 'tui.keymap.pager.jump_bottom')!
		close:            resolve_bindings(resolved_keymap.pager.close, &defaults.pager.close, 'tui.keymap.pager.close')!
		close_transcript: resolve_bindings(resolved_keymap.pager.close_transcript, &defaults.pager.close_transcript, 'tui.keymap.pager.close_transcript')!
		// Rust uses `Arc::clone(&chords)` here. V stores the immutable chord table by value, so the
		// corresponding ownership boundary is an explicit structural clone.
		chord_hints:      clone_runtime_chord_keymap(&chords)
	}

	mut resume_default_is_shadowed := false
	if resolved_keymap.agents.resume == none {
		resume_default_is_shadowed = configured_context_alias_is_used(&resolved_keymap.agents, 'ctrl-o')
			|| configured_context_alias_is_used(&resolved_keymap.list, 'ctrl-o')
			|| chord_prefix_parts_overlapping_context(&chords, .agents, key_hint.ctrl(event.KeyCode.char_key(`o`)))
	}
	mut resolved_resume := []key_hint.KeyBinding{}
	if !resume_default_is_shadowed {
		resolved_resume = resolve_bindings(resolved_keymap.agents.resume, &defaults.agents.resume, 'tui.keymap.agents.resume')!
	}
	mut agents := AgentsKeymap{
		resume:          resolved_resume
		search:          resolve_bindings(resolved_keymap.agents.search, &defaults.agents.search, 'tui.keymap.agents.search')!
		new_task:        resolve_bindings(resolved_keymap.agents.new_task, &defaults.agents.new_task, 'tui.keymap.agents.new_task')!
		rename:          resolve_bindings(resolved_keymap.agents.rename, &defaults.agents.rename, 'tui.keymap.agents.rename')!
		stop:            resolve_bindings(resolved_keymap.agents.stop, &defaults.agents.stop, 'tui.keymap.agents.stop')!
		toggle_grouping: resolve_bindings(resolved_keymap.agents.toggle_grouping, &defaults.agents.toggle_grouping, 'tui.keymap.agents.toggle_grouping')!
		chord_hints:     clone_runtime_chord_keymap(&chords)
	}

	approval := ApprovalKeymap{
		open_fullscreen:     resolve_bindings(resolved_keymap.approval.open_fullscreen, &defaults.approval.open_fullscreen, 'tui.keymap.approval.open_fullscreen')!
		open_thread:         resolve_bindings(resolved_keymap.approval.open_thread, &defaults.approval.open_thread, 'tui.keymap.approval.open_thread')!
		approve:             resolve_bindings(resolved_keymap.approval.approve, &defaults.approval.approve, 'tui.keymap.approval.approve')!
		approve_for_session: resolve_bindings(resolved_keymap.approval.approve_for_session, &defaults.approval.approve_for_session, 'tui.keymap.approval.approve_for_session')!
		approve_for_prefix:  resolve_bindings(resolved_keymap.approval.approve_for_prefix, &defaults.approval.approve_for_prefix, 'tui.keymap.approval.approve_for_prefix')!
		deny:                resolve_bindings(resolved_keymap.approval.deny, &defaults.approval.deny, 'tui.keymap.approval.deny')!
		decline:             resolve_bindings(resolved_keymap.approval.decline, &defaults.approval.decline, 'tui.keymap.approval.decline')!
		cancel:              resolve_bindings(resolved_keymap.approval.cancel, &defaults.approval.cancel, 'tui.keymap.approval.cancel')!
		chord_hints:         clone_runtime_chord_keymap(&chords)
	}

	list_move_up := resolve_bindings(resolved_keymap.list.move_up, &defaults.list.move_up, 'tui.keymap.list.move_up')!
	list_move_down := resolve_bindings(resolved_keymap.list.move_down, &defaults.list.move_down, 'tui.keymap.list.move_down')!
	list_accept := resolve_bindings(resolved_keymap.list.accept, &defaults.list.accept, 'tui.keymap.list.accept')!
	list_cancel := resolve_bindings(resolved_keymap.list.cancel, &defaults.list.cancel, 'tui.keymap.list.cancel')!
	// Rust names this local `configured_bindings_to_preserve`, shadowing the free function of the
	// same name. V forbids that shadowing, so the local carries a `list` qualifier.
	configured_list_bindings_to_preserve := configured_bindings_to_preserve([
		ConfiguredPair{
			configured: resolved_keymap.global.open_agents
			resolved:   app.open_agents.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.open_transcript
			resolved:   app.open_transcript.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.open_external_editor
			resolved:   app.open_external_editor.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.copy
			resolved:   app.copy.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.clear_terminal
			resolved:   app.clear_terminal.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.toggle_vim_mode
			resolved:   app.toggle_vim_mode.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.toggle_fast_mode
			resolved:   app.toggle_fast_mode.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.toggle_raw_output
			resolved:   app.toggle_raw_output.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.global.toggle_side_conversation
			resolved:   app.toggle_side_conversation.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.list.move_up
			resolved:   list_move_up.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.list.move_down
			resolved:   list_move_down.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.list.accept
			resolved:   list_accept.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.list.cancel
			resolved:   list_cancel.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.open_fullscreen
			resolved:   approval.open_fullscreen.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.open_thread
			resolved:   approval.open_thread.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.approve
			resolved:   approval.approve.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.approve_for_session
			resolved:   approval.approve_for_session.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.approve_for_prefix
			resolved:   approval.approve_for_prefix.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.deny
			resolved:   approval.deny.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.decline
			resolved:   approval.decline.clone()
		},
		ConfiguredPair{
			configured: resolved_keymap.approval.cancel
			resolved:   approval.cancel.clone()
		},
	])

	list := ListKeymap{
		move_up:     list_move_up
		move_down:   list_move_down
		move_left:   resolve_new_default_bindings(resolved_keymap.list.move_left, &defaults.list.move_left, configured_list_bindings_to_preserve, 'tui.keymap.list.move_left')!
		move_right:  resolve_new_default_bindings(resolved_keymap.list.move_right, &defaults.list.move_right, configured_list_bindings_to_preserve, 'tui.keymap.list.move_right')!
		page_up:     resolve_new_default_bindings(resolved_keymap.list.page_up, &defaults.list.page_up, configured_list_bindings_to_preserve, 'tui.keymap.list.page_up')!
		page_down:   resolve_new_default_bindings(resolved_keymap.list.page_down, &defaults.list.page_down, configured_list_bindings_to_preserve, 'tui.keymap.list.page_down')!
		jump_top:    resolve_new_default_bindings(resolved_keymap.list.jump_top, &defaults.list.jump_top, configured_list_bindings_to_preserve, 'tui.keymap.list.jump_top')!
		jump_bottom: resolve_new_default_bindings(resolved_keymap.list.jump_bottom, &defaults.list.jump_bottom, configured_list_bindings_to_preserve, 'tui.keymap.list.jump_bottom')!
		accept:      list_accept
		cancel:      list_cancel
		chord_hints: clone_runtime_chord_keymap(&chords)
	}

	// Rust iterates `[(Option<&KeybindingsSpec>, &mut Vec<KeyBinding>); 6]` for the agents block.
	agents.resume = retain_agents_bindings(resolved_keymap.agents.resume, agents.resume, &chords)
	agents.search = retain_agents_bindings(resolved_keymap.agents.search, agents.search, &chords)
	agents.new_task = retain_agents_bindings(resolved_keymap.agents.new_task, agents.new_task, &chords)
	agents.rename = retain_agents_bindings(resolved_keymap.agents.rename, agents.rename, &chords)
	agents.stop = retain_agents_bindings(resolved_keymap.agents.stop, agents.stop, &chords)
	agents.toggle_grouping = retain_agents_bindings(resolved_keymap.agents.toggle_grouping, agents.toggle_grouping, &chords)

	mut resolved := RuntimeKeymap{
		app:             app
		chords:          chords
		chat:            chat
		composer:        composer
		editor:          editor
		vim_normal:      vim_normal
		vim_operator:    vim_operator
		vim_search:      VimSearchKeymap{
			forward:  resolve_bindings(resolved_keymap.vim_search.forward, &defaults.vim_search.forward, 'tui.keymap.vim_search.forward')!
			backward: resolve_bindings(resolved_keymap.vim_search.backward, &defaults.vim_search.backward, 'tui.keymap.vim_search.backward')!
			next:     resolve_bindings(resolved_keymap.vim_search.next, &defaults.vim_search.next, 'tui.keymap.vim_search.next')!
			previous: resolve_bindings(resolved_keymap.vim_search.previous, &defaults.vim_search.previous, 'tui.keymap.vim_search.previous')!
		}
		vim_text_object: vim_text_object
		pager:           pager
		list:            list
		agents:          agents
		approval:        approval
	}

	mut configured := []key_hint.KeyBinding{}
	for action in runtime_action_bindings(&resolved) {
		if !action.id.context.overlaps(.vim_normal) {
			continue
		}
		slot := configured_binding_for_action(resolved_keymap, action.id) or { continue }
		if slot.spec == none {
			continue
		}
		for binding in action.bindings {
			configured << binding
		}
	}
	// Rust iterates `[(Option<&KeybindingsSpec>, &mut Vec<KeyBinding>); 3]` over the three actions
	// whose defaults yield to an explicitly configured Vim binding on the same input path.
	resolved.vim_normal.undo = retain_vim_history_bindings(resolved_keymap.vim_normal.undo, resolved.vim_normal.undo, &configured, &resolved.chords)
	resolved.vim_normal.redo = retain_vim_history_bindings(resolved_keymap.vim_normal.redo, resolved.vim_normal.redo, &configured, &resolved.chords)
	resolved.vim_normal.enter_replace_mode = retain_vim_history_bindings(resolved_keymap.vim_normal.enter_replace_mode, resolved.vim_normal.enter_replace_mode, &configured, &resolved.chords)
	resolved.configure_vim_search(resolved_keymap)!
	resolved.validate_conflicts()!
	validate_chord_conflicts(resolved)!
	install_dispatch_bindings(mut resolved)!
	return resolved
}

// Resolve the visible primary shortcut from configured declaration order.
pub fn (resolved_keymap &RuntimeKeymap) primary_hint(context KeymapContext, action string) ?key_hint.ShortcutHint {
	action_id := keymap_action_id(context.config_name(), action)?
	bindings := bindings_for_action(resolved_keymap, context.config_name(), action)?
	return resolved_keymap.chords.primary_hint(action_id, &bindings)
}

// Built-in keymap defaults.
//
// Some actions intentionally include compatibility variants (for example
// both `?` and `shift-?`) because terminals disagree on whether SHIFT is
// preserved for certain printable/control chords.
fn RuntimeKeymap.built_in_defaults() RuntimeKeymap {
	return RuntimeKeymap{
		app:             AppKeymap{
			open_agents:              []key_hint.KeyBinding{}
			open_transcript:          [key_hint.ctrl(event.KeyCode.char_key(`t`))]
			open_external_editor:     [key_hint.ctrl(event.KeyCode.char_key(`g`))]
			copy:                     [key_hint.ctrl(event.KeyCode.char_key(`o`))]
			clear_terminal:           [key_hint.ctrl(event.KeyCode.char_key(`l`))]
			toggle_vim_mode:          []key_hint.KeyBinding{}
			toggle_fast_mode:         []key_hint.KeyBinding{}
			toggle_raw_output:        [key_hint.alt(event.KeyCode.char_key(`r`))]
			toggle_side_conversation: [key_hint.ctrl(event.KeyCode.char_key(`/`))]
		}
		chords:          RuntimeChordKeymap{}
		chat:            ChatKeymap{
			interrupt_turn:            [key_hint.plain(event.key_code_esc)]
			decrease_reasoning_effort: [
				key_hint.alt(event.KeyCode.char_key(`,`)),
				key_hint.shift(event.key_code_down),
			]
			increase_reasoning_effort: [
				key_hint.alt(event.KeyCode.char_key(`.`)),
				key_hint.shift(event.key_code_up),
			]
			previous_permission_mode:  []key_hint.KeyBinding{}
			next_permission_mode:      []key_hint.KeyBinding{}
			edit_queued_message:       [key_hint.alt(event.key_code_up),
				key_hint.shift(event.key_code_left)]
			prompt_stack_back:         [key_hint.alt(event.key_code_down),
				key_hint.shift(event.key_code_right)]
			skip_question:             [key_hint.ctrl(event.KeyCode.char_key(`]`))]
		}
		composer:        ComposerKeymap{
			submit:                  [key_hint.plain(event.key_code_enter)]
			queue:                   [key_hint.plain(event.key_code_tab)]
			toggle_shortcuts:        [
				key_hint.plain(event.KeyCode.char_key(`?`)),
				key_hint.shift(event.KeyCode.char_key(`?`)),
			]
			history_search_previous: [key_hint.ctrl(event.KeyCode.char_key(`r`))]
			history_search_next:     [key_hint.ctrl(event.KeyCode.char_key(`s`))]
		}
		editor:          EditorKeymap{
			insert_newline:       [
				key_hint.ctrl(event.KeyCode.char_key(`j`)),
				key_hint.ctrl(event.KeyCode.char_key(`m`)),
				key_hint.plain(event.key_code_enter),
				key_hint.shift(event.key_code_enter),
				key_hint.alt(event.key_code_enter),
			]
			move_left:            [key_hint.plain(event.key_code_left),
				key_hint.ctrl(event.KeyCode.char_key(`b`))]
			move_right:           [key_hint.plain(event.key_code_right),
				key_hint.ctrl(event.KeyCode.char_key(`f`))]
			move_up:              [key_hint.plain(event.key_code_up),
				key_hint.ctrl(event.KeyCode.char_key(`p`))]
			move_down:            [key_hint.plain(event.key_code_down),
				key_hint.ctrl(event.KeyCode.char_key(`n`))]
			move_word_left:       [
				key_hint.alt(event.KeyCode.char_key(`b`)),
				key_hint.KeyBinding.new(event.key_code_left, event.key_modifiers_alt),
				key_hint.KeyBinding.new(event.key_code_left, event.key_modifiers_control),
			]
			move_word_right:      [
				key_hint.alt(event.KeyCode.char_key(`f`)),
				key_hint.KeyBinding.new(event.key_code_right, event.key_modifiers_alt),
				key_hint.KeyBinding.new(event.key_code_right, event.key_modifiers_control),
			]
			move_line_start:      [key_hint.plain(event.key_code_home),
				key_hint.ctrl(event.KeyCode.char_key(`a`))]
			move_line_end:        [key_hint.plain(event.key_code_end),
				key_hint.ctrl(event.KeyCode.char_key(`e`))]
			delete_backward:      [
				key_hint.plain(event.key_code_backspace),
				key_hint.shift(event.key_code_backspace),
				key_hint.ctrl(event.KeyCode.char_key(`h`)),
			]
			delete_forward:       [
				key_hint.plain(event.key_code_delete),
				key_hint.shift(event.key_code_delete),
				key_hint.ctrl(event.KeyCode.char_key(`d`)),
			]
			delete_backward_word: [
				key_hint.alt(event.key_code_backspace),
				key_hint.ctrl(event.key_code_backspace),
				key_hint.KeyBinding.new(event.key_code_backspace, event.key_modifiers_control.union(event.key_modifiers_shift)),
				key_hint.ctrl(event.KeyCode.char_key(`w`)),
				key_hint.KeyBinding.new(event.KeyCode.char_key(`h`), event.key_modifiers_control.union(event.key_modifiers_alt)),
			]
			delete_forward_word:  [
				key_hint.alt(event.key_code_delete),
				key_hint.ctrl(event.key_code_delete),
				key_hint.KeyBinding.new(event.key_code_delete, event.key_modifiers_control.union(event.key_modifiers_shift)),
				key_hint.alt(event.KeyCode.char_key(`d`)),
			]
			kill_line_start:      [key_hint.ctrl(event.KeyCode.char_key(`u`))]
			kill_whole_line:      []key_hint.KeyBinding{}
			kill_line_end:        [key_hint.ctrl(event.KeyCode.char_key(`k`))]
			yank:                 [key_hint.ctrl(event.KeyCode.char_key(`y`))]
		}
		vim_normal:      VimNormalKeymap{
			enter_insert:          [key_hint.plain(event.KeyCode.char_key(`i`)),
				key_hint.plain(event.key_code_insert)]
			append_after_cursor:   [key_hint.plain(event.KeyCode.char_key(`a`))]
			append_line_end:       [
				key_hint.shift(event.KeyCode.char_key(`a`)),
				key_hint.plain(event.KeyCode.char_key(`A`)),
			]
			insert_line_start:     [
				key_hint.shift(event.KeyCode.char_key(`i`)),
				key_hint.plain(event.KeyCode.char_key(`I`)),
			]
			open_line_below:       [key_hint.plain(event.KeyCode.char_key(`o`))]
			open_line_above:       [
				key_hint.shift(event.KeyCode.char_key(`o`)),
				key_hint.plain(event.KeyCode.char_key(`O`)),
			]
			enter_replace_mode:    [
				key_hint.shift(event.KeyCode.char_key(`r`)),
				key_hint.plain(event.KeyCode.char_key(`R`)),
			]
			move_left:             [key_hint.plain(event.KeyCode.char_key(`h`)),
				key_hint.plain(event.key_code_left)]
			move_right:            [key_hint.plain(event.KeyCode.char_key(`l`)),
				key_hint.plain(event.key_code_right)]
			move_up:               [key_hint.plain(event.KeyCode.char_key(`k`)),
				key_hint.plain(event.key_code_up)]
			move_down:             [key_hint.plain(event.KeyCode.char_key(`j`)),
				key_hint.plain(event.key_code_down)]
			move_word_forward:     [key_hint.plain(event.KeyCode.char_key(`w`))]
			move_word_backward:    [key_hint.plain(event.KeyCode.char_key(`b`))]
			move_word_end:         [key_hint.plain(event.KeyCode.char_key(`e`))]
			move_line_start:       [key_hint.plain(event.KeyCode.char_key(`0`))]
			move_line_end:         [
				key_hint.plain(event.KeyCode.char_key(`$`)),
				key_hint.shift(event.KeyCode.char_key(`$`)),
			]
			find_forward:          [key_hint.plain(event.KeyCode.char_key(`f`))]
			find_backward:         [key_hint.shift(event.KeyCode.char_key(`f`))]
			till_forward:          [key_hint.plain(event.KeyCode.char_key(`t`))]
			till_backward:         [key_hint.shift(event.KeyCode.char_key(`t`))]
			jump_top:              []key_hint.KeyBinding{}
			jump_bottom:           [
				key_hint.shift(event.KeyCode.char_key(`g`)),
				key_hint.plain(event.KeyCode.char_key(`G`)),
			]
			delete_char:           [key_hint.plain(event.KeyCode.char_key(`x`))]
			replace_char:          [key_hint.plain(event.KeyCode.char_key(`r`))]
			repeat_last_change:    [key_hint.plain(event.KeyCode.char_key(`.`))]
			substitute_char:       [key_hint.plain(event.KeyCode.char_key(`s`))]
			delete_to_line_end:    [
				key_hint.shift(event.KeyCode.char_key(`d`)),
				key_hint.plain(event.KeyCode.char_key(`D`)),
			]
			change_to_line_end:    [
				key_hint.shift(event.KeyCode.char_key(`c`)),
				key_hint.plain(event.KeyCode.char_key(`C`)),
			]
			yank_line:             [key_hint.shift(event.KeyCode.char_key(`y`)),
				key_hint.plain(event.KeyCode.char_key(`Y`))]
			paste_after:           [key_hint.plain(event.KeyCode.char_key(`p`))]
			start_delete_operator: [key_hint.plain(event.KeyCode.char_key(`d`))]
			start_yank_operator:   [key_hint.plain(event.KeyCode.char_key(`y`))]
			start_change_operator: [key_hint.plain(event.KeyCode.char_key(`c`))]
			undo:                  [key_hint.plain(event.KeyCode.char_key(`u`))]
			redo:                  [key_hint.ctrl(event.KeyCode.char_key(`r`))]
			cancel_operator:       [key_hint.plain(event.key_code_esc)]
		}
		vim_search:      VimSearchKeymap.default()
		vim_operator:    VimOperatorKeymap{
			delete_line:               [key_hint.plain(event.KeyCode.char_key(`d`))]
			yank_line:                 [key_hint.plain(event.KeyCode.char_key(`y`))]
			motion_left:               [key_hint.plain(event.KeyCode.char_key(`h`))]
			motion_right:              [key_hint.plain(event.KeyCode.char_key(`l`))]
			motion_up:                 [key_hint.plain(event.KeyCode.char_key(`k`))]
			motion_down:               [key_hint.plain(event.KeyCode.char_key(`j`))]
			motion_word_forward:       [key_hint.plain(event.KeyCode.char_key(`w`))]
			motion_word_backward:      [key_hint.plain(event.KeyCode.char_key(`b`))]
			motion_word_end:           [key_hint.plain(event.KeyCode.char_key(`e`))]
			motion_line_start:         [key_hint.plain(event.KeyCode.char_key(`0`))]
			motion_line_end:           [
				key_hint.plain(event.KeyCode.char_key(`$`)),
				key_hint.shift(event.KeyCode.char_key(`$`)),
			]
			motion_find_forward:       [key_hint.plain(event.KeyCode.char_key(`f`))]
			motion_find_backward:      [key_hint.shift(event.KeyCode.char_key(`f`))]
			motion_till_forward:       [key_hint.plain(event.KeyCode.char_key(`t`))]
			motion_till_backward:      [key_hint.shift(event.KeyCode.char_key(`t`))]
			motion_jump_top:           []key_hint.KeyBinding{}
			motion_jump_bottom:        [
				key_hint.shift(event.KeyCode.char_key(`g`)),
				key_hint.plain(event.KeyCode.char_key(`G`)),
			]
			select_inner_text_object:  [key_hint.plain(event.KeyCode.char_key(`i`))]
			select_around_text_object: [key_hint.plain(event.KeyCode.char_key(`a`))]
			cancel:                    [key_hint.plain(event.key_code_esc)]
		}
		vim_text_object: VimTextObjectKeymap{
			word:         [key_hint.plain(event.KeyCode.char_key(`w`))]
			big_word:     [key_hint.shift(event.KeyCode.char_key(`w`)),
				key_hint.plain(event.KeyCode.char_key(`W`))]
			parentheses:  [
				key_hint.plain(event.KeyCode.char_key(`(`)),
				key_hint.shift(event.KeyCode.char_key(`(`)),
				key_hint.plain(event.KeyCode.char_key(`)`)),
				key_hint.shift(event.KeyCode.char_key(`)`)),
				key_hint.plain(event.KeyCode.char_key(`b`)),
			]
			brackets:     [key_hint.plain(event.KeyCode.char_key(`[`)),
				key_hint.plain(event.KeyCode.char_key(`]`))]
			braces:       [
				key_hint.plain(event.KeyCode.char_key(`{`)),
				key_hint.shift(event.KeyCode.char_key(`{`)),
				key_hint.plain(event.KeyCode.char_key(`}`)),
				key_hint.shift(event.KeyCode.char_key(`}`)),
				key_hint.shift(event.KeyCode.char_key(`b`)),
				key_hint.plain(event.KeyCode.char_key(`B`)),
			]
			double_quote: [
				key_hint.plain(event.KeyCode.char_key(`"`)),
				key_hint.shift(event.KeyCode.char_key(`"`)),
			]
			single_quote: [key_hint.plain(event.KeyCode.char_key(`\'`))]
			backtick:     [key_hint.plain(event.KeyCode.char_key(`\``))]
			cancel:       [key_hint.plain(event.key_code_esc)]
		}
		pager:           PagerKeymap{
			scroll_up:        [key_hint.plain(event.key_code_up),
				key_hint.plain(event.KeyCode.char_key(`k`))]
			scroll_down:      [key_hint.plain(event.key_code_down),
				key_hint.plain(event.KeyCode.char_key(`j`))]
			page_up:          [
				key_hint.plain(event.key_code_page_up),
				key_hint.shift(event.KeyCode.char_key(` `)),
				key_hint.ctrl(event.KeyCode.char_key(`b`)),
			]
			page_down:        [
				key_hint.plain(event.key_code_page_down),
				key_hint.plain(event.KeyCode.char_key(` `)),
				key_hint.ctrl(event.KeyCode.char_key(`f`)),
			]
			half_page_up:     [key_hint.ctrl(event.KeyCode.char_key(`u`))]
			half_page_down:   [key_hint.ctrl(event.KeyCode.char_key(`d`))]
			jump_top:         [key_hint.plain(event.key_code_home)]
			jump_bottom:      [key_hint.plain(event.key_code_end)]
			close:            [key_hint.plain(event.KeyCode.char_key(`q`)),
				key_hint.ctrl(event.KeyCode.char_key(`c`))]
			close_transcript: [key_hint.ctrl(event.KeyCode.char_key(`t`))]
			chord_hints:      RuntimeChordKeymap{}
		}
		list:            ListKeymap{
			move_up:     [
				key_hint.plain(event.key_code_up),
				key_hint.ctrl(event.KeyCode.char_key(`p`)),
				key_hint.ctrl(event.KeyCode.char_key(`k`)),
				key_hint.plain(event.KeyCode.char_key(`k`)),
			]
			move_down:   [
				key_hint.plain(event.key_code_down),
				key_hint.ctrl(event.KeyCode.char_key(`n`)),
				key_hint.ctrl(event.KeyCode.char_key(`j`)),
				key_hint.plain(event.KeyCode.char_key(`j`)),
			]
			move_left:   [key_hint.plain(event.key_code_left),
				key_hint.ctrl(event.KeyCode.char_key(`h`))]
			move_right:  [key_hint.plain(event.key_code_right),
				key_hint.ctrl(event.KeyCode.char_key(`l`))]
			page_up:     [key_hint.plain(event.key_code_page_up),
				key_hint.ctrl(event.KeyCode.char_key(`b`))]
			page_down:   [key_hint.plain(event.key_code_page_down),
				key_hint.ctrl(event.KeyCode.char_key(`f`))]
			jump_top:    [key_hint.plain(event.key_code_home)]
			jump_bottom: [key_hint.plain(event.key_code_end)]
			accept:      [key_hint.plain(event.key_code_enter)]
			cancel:      [key_hint.plain(event.key_code_esc)]
			chord_hints: RuntimeChordKeymap{}
		}
		agents:          AgentsKeymap{
			resume:          [key_hint.ctrl(event.KeyCode.char_key(`o`))]
			search:          [key_hint.ctrl(event.KeyCode.char_key(`f`))]
			new_task:        [key_hint.ctrl(event.KeyCode.char_key(`n`))]
			rename:          [key_hint.ctrl(event.KeyCode.char_key(`r`))]
			stop:            [key_hint.ctrl(event.KeyCode.char_key(`x`))]
			toggle_grouping: [key_hint.ctrl(event.KeyCode.char_key(`s`))]
			chord_hints:     RuntimeChordKeymap{}
		}
		approval:        ApprovalKeymap{
			open_fullscreen:     [
				key_hint.ctrl(event.KeyCode.char_key(`a`)),
				key_hint.KeyBinding.new(event.KeyCode.char_key(`a`), event.key_modifiers_control.union(event.key_modifiers_shift)),
			]
			open_thread:         [key_hint.plain(event.KeyCode.char_key(`o`))]
			approve:             [key_hint.plain(event.KeyCode.char_key(`y`))]
			approve_for_session: [key_hint.plain(event.KeyCode.char_key(`a`))]
			approve_for_prefix:  [key_hint.plain(event.KeyCode.char_key(`p`))]
			deny:                [key_hint.plain(event.KeyCode.char_key(`d`))]
			decline:             [key_hint.plain(event.key_code_esc),
				key_hint.plain(event.KeyCode.char_key(`n`))]
			cancel:              [key_hint.plain(event.KeyCode.char_key(`c`))]
			chord_hints:         RuntimeChordKeymap{}
		}
	}
}

// Reject ambiguous bindings in scopes that are evaluated together.
//
// We validate in multiple passes because runtime handling has mixed
// precedence:
//
// 1. `app` actions can shadow composer actions because app checks run
//    before forwarding to the composer.
// 2. Contexts with hard-coded sequence behavior, such as edit-previous
//    backtracking, intentionally stay outside this configurable keymap.
fn (resolved_keymap &RuntimeKeymap) validate_conflicts() ! {
	for pair in [
		ActionBindings{
			action:   'previous_permission_mode'
			bindings: resolved_keymap.chat.previous_permission_mode.clone()
		},
		ActionBindings{
			action:   'next_permission_mode'
			bindings: resolved_keymap.chat.next_permission_mode.clone()
		},
		ActionBindings{
			action:   'prompt_stack_back'
			bindings: resolved_keymap.chat.prompt_stack_back.clone()
		},
		ActionBindings{
			action:   'skip_question'
			bindings: resolved_keymap.chat.skip_question.clone()
		},
	] {
		mut reserves_text_input := false
		for binding in pair.bindings {
			parts := binding.parts()
			if key_hint.is_plain_text_key_event(event.KeyEvent.new(parts.code, parts.modifiers))
				|| (parts.code.kind == .char_key && key_hint.is_altgr(parts.modifiers)) {
				reserves_text_input = true
				break
			}
		}
		if reserves_text_input {
			return error('tui.keymap.chat.${pair.action}: printable keys are reserved for text input')
		}
	}
	// Rust guards this branch with `#[cfg(unix)]`; the V tree only targets Unix hosts today.
	if key_hint.ctrl(event.KeyCode.char_key(`z`)) in resolved_keymap.app.open_agents {
		return error('tui.keymap.global.open_agents: ctrl-z is reserved for suspend')
	}
	mut open_agents_uses_altgr := false
	for binding in resolved_keymap.app.open_agents {
		parts := binding.parts()
		if parts.code.kind == .char_key && key_hint.is_altgr(parts.modifiers) {
			open_agents_uses_altgr = true
			break
		}
	}
	if open_agents_uses_altgr {
		return error('tui.keymap.global.open_agents: AltGr characters are reserved for text input')
	}
	mut side_toggle_bindings := resolved_keymap.app.toggle_side_conversation.clone()
	slash_binding := key_hint.ctrl(event.KeyCode.char_key(`/`))
	legacy_slash_binding := key_hint.ctrl(event.KeyCode.char_key(`7`))
	if slash_binding in side_toggle_bindings && legacy_slash_binding !in side_toggle_bindings {
		side_toggle_bindings << legacy_slash_binding
	}

	main_bindings := [
		ActionBindings{
			action:   'open_agents'
			bindings: resolved_keymap.app.open_agents.clone()
		},
		ActionBindings{
			action:   'open_transcript'
			bindings: resolved_keymap.app.open_transcript.clone()
		},
		ActionBindings{
			action:   'open_external_editor'
			bindings: resolved_keymap.app.open_external_editor.clone()
		},
		ActionBindings{
			action:   'copy'
			bindings: resolved_keymap.app.copy.clone()
		},
		ActionBindings{
			action:   'clear_terminal'
			bindings: resolved_keymap.app.clear_terminal.clone()
		},
		ActionBindings{
			action:   'toggle_vim_mode'
			bindings: resolved_keymap.app.toggle_vim_mode.clone()
		},
		ActionBindings{
			action:   'toggle_fast_mode'
			bindings: resolved_keymap.app.toggle_fast_mode.clone()
		},
		ActionBindings{
			action:   'toggle_raw_output'
			bindings: resolved_keymap.app.toggle_raw_output.clone()
		},
		ActionBindings{
			action:   'toggle_side_conversation'
			bindings: side_toggle_bindings.clone()
		},
		ActionBindings{
			action:   'chat.interrupt_turn'
			bindings: resolved_keymap.chat.interrupt_turn.clone()
		},
		ActionBindings{
			action:   'chat.decrease_reasoning_effort'
			bindings: resolved_keymap.chat.decrease_reasoning_effort.clone()
		},
		ActionBindings{
			action:   'chat.increase_reasoning_effort'
			bindings: resolved_keymap.chat.increase_reasoning_effort.clone()
		},
		ActionBindings{
			action:   'chat.previous_permission_mode'
			bindings: resolved_keymap.chat.previous_permission_mode.clone()
		},
		ActionBindings{
			action:   'chat.next_permission_mode'
			bindings: resolved_keymap.chat.next_permission_mode.clone()
		},
		ActionBindings{
			action:   'chat.edit_queued_message'
			bindings: resolved_keymap.chat.edit_queued_message.clone()
		},
		ActionBindings{
			action:   'chat.prompt_stack_back'
			bindings: resolved_keymap.chat.prompt_stack_back.clone()
		},
		ActionBindings{
			action:   'chat.skip_question'
			bindings: resolved_keymap.chat.skip_question.clone()
		},
		ActionBindings{
			action:   'composer.submit'
			bindings: resolved_keymap.composer.submit.clone()
		},
		ActionBindings{
			action:   'composer.queue'
			bindings: resolved_keymap.composer.queue.clone()
		},
		ActionBindings{
			action:   'composer.toggle_shortcuts'
			bindings: resolved_keymap.composer.toggle_shortcuts.clone()
		},
		ActionBindings{
			action:   'composer.history_search_previous'
			bindings: resolved_keymap.composer.history_search_previous.clone()
		},
		ActionBindings{
			action:   'composer.history_search_next'
			bindings: resolved_keymap.composer.history_search_next.clone()
		},
	]
	validate_unique('app', clone_action_bindings(&main_bindings))!

	validate_no_reserved('main', main_bindings, main_reserved_bindings, [
		AllowedOverlap{
			primary:  'chat.interrupt_turn'
			shadowed: 'fixed.backtrack'
			binding:  key_hint.plain(event.key_code_esc)
		},
	])!

	approval_overlay_bindings := [
		ActionBindings{
			action:   'list.move_up'
			bindings: resolved_keymap.list.move_up.clone()
		},
		ActionBindings{
			action:   'list.move_down'
			bindings: resolved_keymap.list.move_down.clone()
		},
		ActionBindings{
			action:   'list.move_left'
			bindings: resolved_keymap.list.move_left.clone()
		},
		ActionBindings{
			action:   'list.move_right'
			bindings: resolved_keymap.list.move_right.clone()
		},
		ActionBindings{
			action:   'list.page_up'
			bindings: resolved_keymap.list.page_up.clone()
		},
		ActionBindings{
			action:   'list.page_down'
			bindings: resolved_keymap.list.page_down.clone()
		},
		ActionBindings{
			action:   'list.jump_top'
			bindings: resolved_keymap.list.jump_top.clone()
		},
		ActionBindings{
			action:   'list.jump_bottom'
			bindings: resolved_keymap.list.jump_bottom.clone()
		},
		ActionBindings{
			action:   'list.accept'
			bindings: resolved_keymap.list.accept.clone()
		},
		ActionBindings{
			action:   'list.cancel'
			bindings: resolved_keymap.list.cancel.clone()
		},
		ActionBindings{
			action:   'approval.open_fullscreen'
			bindings: resolved_keymap.approval.open_fullscreen.clone()
		},
		ActionBindings{
			action:   'approval.open_thread'
			bindings: resolved_keymap.approval.open_thread.clone()
		},
		ActionBindings{
			action:   'approval.approve'
			bindings: resolved_keymap.approval.approve.clone()
		},
		ActionBindings{
			action:   'approval.approve_for_session'
			bindings: resolved_keymap.approval.approve_for_session.clone()
		},
		ActionBindings{
			action:   'approval.approve_for_prefix'
			bindings: resolved_keymap.approval.approve_for_prefix.clone()
		},
		ActionBindings{
			action:   'approval.deny'
			bindings: resolved_keymap.approval.deny.clone()
		},
		ActionBindings{
			action:   'approval.decline'
			bindings: resolved_keymap.approval.decline.clone()
		},
		ActionBindings{
			action:   'approval.cancel'
			bindings: resolved_keymap.approval.cancel.clone()
		},
	]
	validate_no_shadow_with_allowed_overlaps('app', [
		ActionBindings{
			action:   'open_agents'
			bindings: resolved_keymap.app.open_agents.clone()
		},
		ActionBindings{
			action:   'open_transcript'
			bindings: resolved_keymap.app.open_transcript.clone()
		},
		ActionBindings{
			action:   'open_external_editor'
			bindings: resolved_keymap.app.open_external_editor.clone()
		},
		ActionBindings{
			action:   'copy'
			bindings: resolved_keymap.app.copy.clone()
		},
		ActionBindings{
			action:   'clear_terminal'
			bindings: resolved_keymap.app.clear_terminal.clone()
		},
		ActionBindings{
			action:   'toggle_vim_mode'
			bindings: resolved_keymap.app.toggle_vim_mode.clone()
		},
		ActionBindings{
			action:   'toggle_fast_mode'
			bindings: resolved_keymap.app.toggle_fast_mode.clone()
		},
		ActionBindings{
			action:   'toggle_raw_output'
			bindings: resolved_keymap.app.toggle_raw_output.clone()
		},
		ActionBindings{
			action:   'toggle_side_conversation'
			bindings: side_toggle_bindings.clone()
		},
	], approval_overlay_bindings, [
		AllowedOverlap{
			primary:  'clear_terminal'
			shadowed: 'list.move_right'
			binding:  key_hint.ctrl(event.KeyCode.char_key(`l`))
		},
	])!

	// The request-user-input overlay consumes turn interruption before
	// configurable question navigation reaches its list handler.
	validate_no_shadow_with_allowed_overlaps('request_user_input', [
		ActionBindings{
			action:   'chat.interrupt_turn'
			bindings: resolved_keymap.chat.interrupt_turn.clone()
		},
	], [
		ActionBindings{
			action:   'list.move_left'
			bindings: resolved_keymap.list.move_left.clone()
		},
		ActionBindings{
			action:   'list.move_right'
			bindings: resolved_keymap.list.move_right.clone()
		},
	], [])!

	// Async question shortcuts run before option selection and text editing.
	validate_no_shadow_with_allowed_overlaps('async_questions', [
		ActionBindings{
			action:   'chat.prompt_stack_back'
			bindings: resolved_keymap.chat.prompt_stack_back.clone()
		},
		ActionBindings{
			action:   'chat.skip_question'
			bindings: resolved_keymap.chat.skip_question.clone()
		},
	], [
		ActionBindings{
			action:   'list.move_up'
			bindings: resolved_keymap.list.move_up.clone()
		},
		ActionBindings{
			action:   'list.move_down'
			bindings: resolved_keymap.list.move_down.clone()
		},
		ActionBindings{
			action:   'list.accept'
			bindings: resolved_keymap.list.accept.clone()
		},
	], [])!

	// While the composer is focused, these main-surface handlers always
	// consume matching keys before the event reaches the textarea editor.
	validate_no_shadow_with_allowed_overlaps('main', [
		ActionBindings{
			action:   'open_agents'
			bindings: resolved_keymap.app.open_agents.clone()
		},
		ActionBindings{
			action:   'open_transcript'
			bindings: resolved_keymap.app.open_transcript.clone()
		},
		ActionBindings{
			action:   'open_external_editor'
			bindings: resolved_keymap.app.open_external_editor.clone()
		},
		ActionBindings{
			action:   'copy'
			bindings: resolved_keymap.app.copy.clone()
		},
		ActionBindings{
			action:   'clear_terminal'
			bindings: resolved_keymap.app.clear_terminal.clone()
		},
		ActionBindings{
			action:   'chat.interrupt_turn'
			bindings: resolved_keymap.chat.interrupt_turn.clone()
		},
		ActionBindings{
			action:   'chat.decrease_reasoning_effort'
			bindings: resolved_keymap.chat.decrease_reasoning_effort.clone()
		},
		ActionBindings{
			action:   'chat.increase_reasoning_effort'
			bindings: resolved_keymap.chat.increase_reasoning_effort.clone()
		},
		ActionBindings{
			action:   'chat.previous_permission_mode'
			bindings: resolved_keymap.chat.previous_permission_mode.clone()
		},
		ActionBindings{
			action:   'chat.next_permission_mode'
			bindings: resolved_keymap.chat.next_permission_mode.clone()
		},
		ActionBindings{
			action:   'chat.prompt_stack_back'
			bindings: resolved_keymap.chat.prompt_stack_back.clone()
		},
		ActionBindings{
			action:   'chat.skip_question'
			bindings: resolved_keymap.chat.skip_question.clone()
		},
		ActionBindings{
			action:   'composer.submit'
			bindings: resolved_keymap.composer.submit.clone()
		},
		ActionBindings{
			action:   'toggle_vim_mode'
			bindings: resolved_keymap.app.toggle_vim_mode.clone()
		},
		ActionBindings{
			action:   'toggle_fast_mode'
			bindings: resolved_keymap.app.toggle_fast_mode.clone()
		},
		ActionBindings{
			action:   'toggle_raw_output'
			bindings: resolved_keymap.app.toggle_raw_output.clone()
		},
		ActionBindings{
			action:   'toggle_side_conversation'
			bindings: side_toggle_bindings.clone()
		},
		ActionBindings{
			action:   'composer.history_search_previous'
			bindings: resolved_keymap.composer.history_search_previous.clone()
		},
	], [
		ActionBindings{
			action:   'editor.insert_newline'
			bindings: resolved_keymap.editor.insert_newline.clone()
		},
		ActionBindings{
			action:   'editor.move_left'
			bindings: resolved_keymap.editor.move_left.clone()
		},
		ActionBindings{
			action:   'editor.move_right'
			bindings: resolved_keymap.editor.move_right.clone()
		},
		ActionBindings{
			action:   'editor.move_up'
			bindings: resolved_keymap.editor.move_up.clone()
		},
		ActionBindings{
			action:   'editor.move_down'
			bindings: resolved_keymap.editor.move_down.clone()
		},
		ActionBindings{
			action:   'editor.move_word_left'
			bindings: resolved_keymap.editor.move_word_left.clone()
		},
		ActionBindings{
			action:   'editor.move_word_right'
			bindings: resolved_keymap.editor.move_word_right.clone()
		},
		ActionBindings{
			action:   'editor.move_line_start'
			bindings: resolved_keymap.editor.move_line_start.clone()
		},
		ActionBindings{
			action:   'editor.move_line_end'
			bindings: resolved_keymap.editor.move_line_end.clone()
		},
		ActionBindings{
			action:   'editor.delete_backward'
			bindings: resolved_keymap.editor.delete_backward.clone()
		},
		ActionBindings{
			action:   'editor.delete_forward'
			bindings: resolved_keymap.editor.delete_forward.clone()
		},
		ActionBindings{
			action:   'editor.delete_backward_word'
			bindings: resolved_keymap.editor.delete_backward_word.clone()
		},
		ActionBindings{
			action:   'editor.delete_forward_word'
			bindings: resolved_keymap.editor.delete_forward_word.clone()
		},
		ActionBindings{
			action:   'editor.kill_line_start'
			bindings: resolved_keymap.editor.kill_line_start.clone()
		},
		ActionBindings{
			action:   'editor.kill_whole_line'
			bindings: resolved_keymap.editor.kill_whole_line.clone()
		},
		ActionBindings{
			action:   'editor.kill_line_end'
			bindings: resolved_keymap.editor.kill_line_end.clone()
		},
		ActionBindings{
			action:   'editor.yank'
			bindings: resolved_keymap.editor.yank.clone()
		},
	], [
		AllowedOverlap{
			primary:  'composer.submit'
			shadowed: 'editor.insert_newline'
			binding:  key_hint.plain(event.key_code_enter)
		},
	])!

	for context in [KeymapContext.editor, .vim_normal, .vim_operator, .vim_text_object, .pager] {
		validate_unique(context.config_name(), context_bindings(resolved_keymap, context))!
	}

	validate_no_reserved('pager', context_bindings(resolved_keymap, .pager), transcript_backtrack_reserved_bindings, [])!

	validate_unique('list', context_bindings(resolved_keymap, .list))!

	validate_unique('agents', context_bindings(resolved_keymap, .agents))!
	validate_no_reserved('agents', context_bindings(resolved_keymap, .agents), main_reserved_bindings, [])!
	for pair in context_bindings(resolved_keymap, .agents) {
		// Rust guards this branch with `#[cfg(unix)]`; the V tree only targets Unix hosts today.
		if key_hint.ctrl(event.KeyCode.char_key(`z`)) in pair.bindings {
			return error('tui.keymap.agents.${pair.action}: ctrl-z is reserved for suspend')
		}
		mut reserves_task_input := false
		for binding in pair.bindings {
			parts := binding.parts()
			if (parts.code.kind == .char_key && (parts.modifiers.is_empty()
				|| parts.modifiers == event.key_modifiers_shift
				|| key_hint.is_altgr(parts.modifiers)))
				|| parts == key_hint.plain(event.key_code_backspace).parts() {
				reserves_task_input = true
				break
			}
		}
		if reserves_task_input {
			return error('tui.keymap.agents.${pair.action}: printable keys and backspace are reserved for task input')
		}
	}

	validate_unique('approval', context_bindings(resolved_keymap, .approval))!

	mut seen := map[string]string{}
	for pair in approval_overlay_bindings {
		for binding in pair.bindings {
			key := binding.normalized_parts()
			map_key := binding_map_key(key)
			if previous := seen[map_key] {
				// Approval overlays intentionally reserve Esc as a stable
				// cancellation path even though decline options may also
				// display it in contexts where that is safe.
				if previous == 'list.cancel' && pair.action == 'approval.decline'
					&& key == key_hint.plain(event.key_code_esc).parts() {
					seen[map_key] = pair.action
					continue
				}
				return error('Ambiguous approval overlay keymap bindings: `${previous}` and `${pair.action}` use the same key. Set unique keys in `~/.codex/config.toml` and retry. See the Codex keymap documentation for supported actions and examples.')
			}
			seen[map_key] = pair.action
		}
	}
}

// Rust builds this with a `|context|` closure over `runtime_action_bindings(self)`; V has no
// closure capture for the same shape, so the filter is a named helper.
fn context_bindings(resolved_keymap &RuntimeKeymap, context KeymapContext) []ActionBindings {
	mut pairs := []ActionBindings{}
	for binding in runtime_action_bindings(resolved_keymap) {
		if binding.id.context == context {
			pairs << ActionBindings{
				action:   binding.id.action
				bindings: binding.bindings.clone()
			}
		}
	}
	return pairs
}

// V maps accept only scalar keys, so every Rust `HashMap<(KeyCode, KeyModifiers), &'static str>`
// lookup below is keyed by a lossless rendering of the same pair.
fn binding_map_key(parts key_hint.KeyParts) string {
	return '${int(parts.code.kind)}:${u32(parts.code.ch)}:${parts.code.f}:${parts.modifiers.shift}:${parts.modifiers.control}:${parts.modifiers.alt}:${parts.modifiers.super}:${parts.modifiers.hyper}:${parts.modifiers.meta}'
}

// Reject duplicate keys inside one effective context map.
//
// This intentionally allows the same key across different contexts; handlers
// only evaluate one context at a time.
fn validate_unique(context string, pairs []ActionBindings) ! {
	mut seen := map[string]string{}
	for pair in pairs {
		for binding in pair.bindings {
			key := binding_map_key(binding.normalized_parts())
			if previous := seen[key] {
				return error('Ambiguous `tui.keymap.${context}` bindings: `${previous}` and `${pair.action}` use the same key. Set unique keys in `~/.codex/config.toml` and retry. See the Codex keymap documentation for supported actions and examples.')
			}
			seen[key] = pair.action
		}
	}
}

fn validate_no_shadow_with_allowed_overlaps(context string, primary []ActionBindings, shadowed []ActionBindings, allowed_overlaps []AllowedOverlap) ! {
	mut seen := map[string]string{}
	for pair in primary {
		for binding in pair.bindings {
			seen[binding_map_key(binding.normalized_parts())] = pair.action
		}
	}
	for pair in shadowed {
		for binding in pair.bindings {
			key := binding.normalized_parts()
			map_key := binding_map_key(key)
			if previous := seen[map_key] {
				mut is_allowed := false
				for allowed in allowed_overlaps {
					if allowed.primary == previous && allowed.shadowed == pair.action
						&& allowed.binding.normalized_parts() == key {
						is_allowed = true
						break
					}
				}
				if is_allowed {
					continue
				}
				return error('Ambiguous `tui.keymap.${context}` bindings: `${previous}` shadows `${pair.action}` with the same key. Set unique keys in `~/.codex/config.toml` and retry. See the Codex keymap documentation for supported actions and examples.')
			}
		}
	}
}

fn validate_no_reserved(context string, pairs []ActionBindings, reserved []ReservedBinding, allowed_overlaps []AllowedOverlap) ! {
	for pair in pairs {
		for binding in pair.bindings {
			key := binding.parts()
			mut reserved_action := ''
			mut found := false
			for entry in reserved {
				if entry.binding.parts() == key {
					reserved_action = entry.action
					found = true
					break
				}
			}
			if !found {
				continue
			}
			mut is_allowed := false
			for allowed in allowed_overlaps {
				if allowed.primary == pair.action && allowed.shadowed == reserved_action
					&& allowed.binding.parts() == key {
					is_allowed = true
					break
				}
			}
			if is_allowed {
				continue
			}
			return error('Ambiguous `tui.keymap.${context}` bindings: `${pair.action}` uses a key reserved by `${reserved_action}`. Set a different key in `~/.codex/config.toml` and retry. See the Codex keymap documentation for supported actions and examples.')
		}
	}
}

const main_reserved_bindings = [
	ReservedBinding{
		action:  'fixed.interrupt_or_quit'
		binding: key_hint.ctrl(event.KeyCode.char_key(`c`))
	},
	ReservedBinding{
		action:  'fixed.quit'
		binding: key_hint.ctrl(event.KeyCode.char_key(`d`))
	},
	ReservedBinding{
		action:  'fixed.paste_image'
		binding: key_hint.ctrl(event.KeyCode.char_key(`v`))
	},
	ReservedBinding{
		action:  'fixed.paste_image'
		binding: key_hint.ctrl_alt(event.KeyCode.char_key(`v`))
	},
	ReservedBinding{
		action:  'fixed.cycle_collaboration_mode'
		binding: key_hint.shift(event.key_code_tab)
	},
	ReservedBinding{
		action:  'fixed.backtrack'
		binding: key_hint.plain(event.key_code_esc)
	},
	ReservedBinding{
		action:  'fixed.previous_agent'
		binding: key_hint.alt(event.key_code_left)
	},
	ReservedBinding{
		action:  'fixed.next_agent'
		binding: key_hint.alt(event.key_code_right)
	},
	ReservedBinding{
		action:  'fixed.slash_command'
		binding: key_hint.plain(event.KeyCode.char_key(`/`))
	},
	ReservedBinding{
		action:  'fixed.shell_command'
		binding: key_hint.plain(event.KeyCode.char_key(`!`))
	},
	ReservedBinding{
		action:  'fixed.file_paths'
		binding: key_hint.plain(event.KeyCode.char_key(`@`))
	},
	ReservedBinding{
		action:  'fixed.connector_mentions'
		binding: key_hint.plain(event.KeyCode.char_key(`$`))
	},
]

const transcript_backtrack_reserved_bindings = [
	ReservedBinding{
		action:  'fixed.transcript_edit_previous'
		binding: key_hint.plain(event.key_code_esc)
	},
	ReservedBinding{
		action:  'fixed.transcript_edit_previous'
		binding: key_hint.plain(event.key_code_left)
	},
	ReservedBinding{
		action:  'fixed.transcript_edit_next'
		binding: key_hint.plain(event.key_code_right)
	},
	ReservedBinding{
		action:  'fixed.transcript_confirm_edit'
		binding: key_hint.plain(event.key_code_enter)
	},
]

// Resolve one action with context -> global -> default precedence.
//
// `path` should be the context-specific config path so parser errors point
// users at the override they attempted to set.
//
// A configured empty list is authoritative: it returns an empty binding set
// and does not continue to the global or built-in fallback. This is what makes
// explicit unbinding work for globally reusable actions like composer submit.
fn resolve_bindings_with_global_fallback(configured ?types.KeybindingsSpec, global ?types.KeybindingsSpec, fallback &[]key_hint.KeyBinding, path string) ![]key_hint.KeyBinding {
	if spec := configured {
		return parse_bindings(&spec, path)!
	}
	if spec := global {
		return parse_bindings(&spec, path)!
	}
	return (*fallback).clone()
}

// Resolve one action binding in a context without global fallback.
//
// Missing values inherit from the built-in fallback; configured values, including
// empty lists, replace that fallback for the action.
fn resolve_bindings(configured ?types.KeybindingsSpec, fallback &[]key_hint.KeyBinding, path string) ![]key_hint.KeyBinding {
	spec := configured or { return (*fallback).clone() }
	return parse_bindings(&spec, path)!
}

fn configured_bindings_to_preserve(pairs []ConfiguredPair) []key_hint.KeyBinding {
	mut configured_bindings := []key_hint.KeyBinding{}
	for pair in pairs {
		if pair.configured == none {
			continue
		}
		for binding in pair.resolved {
			if binding !in configured_bindings {
				configured_bindings << binding
			}
		}
	}
	return configured_bindings
}

// V cannot pass a string literal to `&string`, so this translation accepts an owned string and
// clones it at the Rust `&str` reuse points below. Callers that already own a string clone only at
// those same logical borrow boundaries.
fn configured_main_surface_alias_is_used(resolved_keymap &types.TuiKeymap, alias string) bool {
	mut global := resolved_keymap.global
	if resolved_keymap.composer.submit != none {
		global.submit = none
	}
	if resolved_keymap.composer.queue != none {
		global.queue = none
	}
	if resolved_keymap.composer.toggle_shortcuts != none {
		global.toggle_shortcuts = none
	}

	// Reasoning shortcuts run before composer/editor key handling, so fallback
	// aliases must yield to any explicit binding on the same main-surface input
	// path.
	return configured_context_alias_is_used(&global, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.chat, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.composer, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.editor, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.vim_normal, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.vim_operator, alias.clone())
		|| configured_context_alias_is_used(&resolved_keymap.vim_text_object, alias)
}

// Rust accepts `&impl Serialize` and calls `serde_json::to_value`; V uses a generic parameter plus
// `json2.encode`/`json2.decode` to reach the same dynamic value.
fn configured_context_alias_is_used[T](context &T, alias string) bool {
	return encoded_context_contains_alias(json2.encode(*context), alias)
}

// V 0.5.2 discards the explicit `[json2.Any]` type argument when `json2.decode` is called from
// inside a generic function, binding it to the enclosing function's return type instead, so the
// object decodes as a string and fails. Keeping the decode in this non-generic helper preserves the
// Rust `serde_json::to_value(..)` -> walk sequence. Fixed upstream by vlang/v#28527; this helper can
// be inlined again once that lands in the pinned compiler.
fn encoded_context_contains_alias(encoded string, alias string) bool {
	value := json2.decode[json2.Any](encoded) or { return false }
	return keymap_value_contains_alias(value, alias)
}

fn keymap_value_contains_alias(value json2.Any, alias string) bool {
	match value {
		string {
			first := parse_keybinding(value) or { return false }
			second := parse_keybinding(alias) or { return false }
			return first.normalized_parts() == second.normalized_parts()
		}
		[]json2.Any {
			for item in value {
				if keymap_value_contains_alias(item, alias.clone()) {
					return true
				}
			}
			return false
		}
		map[string]json2.Any {
			for _, item in value {
				if keymap_value_contains_alias(item, alias.clone()) {
					return true
				}
			}
			return false
		}
		else {
			// `serde_json::Value::Bool`, `::Number` and `::Null` can never name a keybinding.
			return false
		}
	}
}

fn resolve_new_default_bindings(configured ?types.KeybindingsSpec, fallback &[]key_hint.KeyBinding, bindings_to_preserve []key_hint.KeyBinding, path string) ![]key_hint.KeyBinding {
	spec := configured or {
		mut retained := []key_hint.KeyBinding{}
		for binding in *fallback {
			if binding !in bindings_to_preserve {
				retained << binding
			}
		}
		return retained
	}
	return parse_bindings(&spec, path)!
}

// Parse one keybinding value (`string` or `list[string]`) into concrete bindings.
//
// Duplicate entries are de-duplicated while preserving first-seen order so the
// first key can remain the primary UI hint.
fn parse_bindings(spec &types.KeybindingsSpec, path string) ![]key_hint.KeyBinding {
	mut parsed := []key_hint.KeyBinding{}
	for raw in spec.specs() {
		if raw.as_str().contains(' ') {
			continue
		}
		binding := parse_keybinding(raw.as_str()) or {
			return error('Invalid `${path}` = `${raw.as_str()}`. Use values like `ctrl-a`, `shift-enter`, or `page-down`. See the Codex keymap documentation for supported actions and examples.')
		}

		mut already_parsed := false
		for previous in parsed {
			if previous.normalized_parts() == binding.normalized_parts() {
				already_parsed = true
				break
			}
		}
		if !already_parsed {
			parsed << binding
		}
	}
	return parsed
}

// Parse one normalized keybinding spec such as `ctrl-a` or `shift-enter`.
//
// Specs are expected to be normalized by config deserialization, but this
// parser remains strict to keep runtime error messages precise.
// V cannot borrow string literals as `&string`, so the Rust `&str` parameter is represented as a
// value parameter. Callers clone only when they must reuse an owned string under `-ownership`.
fn parse_keybinding(spec string) ?key_hint.KeyBinding {
	parts := spec.split('-')
	mut modifiers := event.key_modifiers_none
	mut key_name := ''
	mut has_key_name := false

	mut index := 0
	for index < parts.len {
		part := parts[index]
		index++
		match part {
			'ctrl' {
				modifiers = modifiers.union(event.key_modifiers_control)
			}
			'alt' {
				modifiers = modifiers.union(event.key_modifiers_alt)
			}
			'shift' {
				modifiers = modifiers.union(event.key_modifiers_shift)
			}
			else {
				key_name = part
				has_key_name = true
				break
			}
		}
	}

	if !has_key_name {
		return none
	}
	for index < parts.len {
		key_name += '-'
		key_name += parts[index]
		index++
	}

	mut key := event.KeyCode{}
	// Rust matches the named keys first, then falls through to the one-character and `f<N>` guard
	// arms in that order; the V chain preserves the same precedence.
	if key_name == 'enter' {
		key = event.key_code_enter
	} else if key_name == 'tab' {
		key = event.key_code_tab
	} else if key_name == 'backspace' {
		key = event.key_code_backspace
	} else if key_name == 'esc' {
		key = event.key_code_esc
	} else if key_name == 'delete' {
		key = event.key_code_delete
	} else if key_name == 'up' {
		key = event.key_code_up
	} else if key_name == 'down' {
		key = event.key_code_down
	} else if key_name == 'left' {
		key = event.key_code_left
	} else if key_name == 'right' {
		key = event.key_code_right
	} else if key_name == 'home' {
		key = event.key_code_home
	} else if key_name == 'end' {
		key = event.key_code_end
	} else if key_name == 'page-up' {
		key = event.key_code_page_up
	} else if key_name == 'page-down' {
		key = event.key_code_page_down
	} else if key_name == 'space' {
		key = event.KeyCode.char_key(` `)
	} else if key_name == 'minus' {
		key = event.KeyCode.char_key(`-`)
	} else if key_name.len == 1 {
		key = event.KeyCode.char_key(rune(key_name[0]))
	} else if key_name.starts_with('f') {
		digits := key_name[1..]
		if digits.len == 0 {
			return none
		}
		for digit in digits.bytes() {
			if digit < `0` || digit > `9` {
				return none
			}
		}
		parsed := digits.u64()
		if parsed > 255 {
			return none
		}
		number := u8(parsed)
		if number >= 1 && number <= types.max_function_key {
			key = event.KeyCode.function_key(number)
		} else {
			return none
		}
	} else {
		return none
	}

	return key_hint.KeyBinding.new(key, modifiers)
}

// Rust spells the `retain` predicates below as inline closures that capture locals. V's `filter`
// cannot capture, so each predicate shape used by `from_config` is named once and called from the
// same places.

// `bindings.retain(|binding| !excluded.contains(binding))`
fn retain_not_in(bindings []key_hint.KeyBinding, excluded []key_hint.KeyBinding) []key_hint.KeyBinding {
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		if binding !in excluded {
			retained << binding
		}
	}
	return retained
}

// `bindings.retain(|binding| *binding != excluded)`
fn retain_not_equal(bindings []key_hint.KeyBinding, excluded key_hint.KeyBinding) []key_hint.KeyBinding {
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		if binding != excluded {
			retained << binding
		}
	}
	return retained
}

// `chords.bindings.iter().any(|chord| chord.action.context == context && chord.chord.prefix.parts() == binding.parts())`
fn chord_prefix_parts_in_context(chords &RuntimeChordKeymap, context KeymapContext, binding key_hint.KeyBinding) bool {
	for chord in chords.bindings {
		if chord.action.context == context && chord.chord.prefix.parts() == binding.parts() {
			return true
		}
	}
	return false
}

// `chords.bindings.iter().any(|chord| chord.action.context.overlaps(context) && chord.chord.prefix.parts() == binding.parts())`
fn chord_prefix_parts_overlapping_context(chords &RuntimeChordKeymap, context KeymapContext, binding key_hint.KeyBinding) bool {
	for chord in chords.bindings {
		if chord.action.context.overlaps(context)
			&& chord.chord.prefix.parts() == binding.parts() {
			return true
		}
	}
	return false
}

// `chords.bindings.iter().any(|chord| chord.action.context.overlaps(context) && binding.normalized_parts() == chord.chord.prefix.normalized_parts())`
fn chord_prefix_normalized_overlapping_context(chords &RuntimeChordKeymap, context KeymapContext, binding key_hint.KeyBinding) bool {
	for chord in chords.bindings {
		if chord.action.context.overlaps(context)
			&& binding.normalized_parts() == chord.chord.prefix.normalized_parts() {
			return true
		}
	}
	return false
}

// Body of the six-slot `find`/`till`/`jump` retain loops in `from_config`.
fn retain_new_default_vim_bindings(configured ?types.KeybindingsSpec, bindings []key_hint.KeyBinding, bindings_to_preserve []key_hint.KeyBinding, chords &RuntimeChordKeymap, context KeymapContext) []key_hint.KeyBinding {
	if configured != none {
		return bindings.clone()
	}
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		if binding !in bindings_to_preserve
			&& !chord_prefix_parts_in_context(chords, context, binding) {
			retained << binding
		}
	}
	return retained
}

// One `(alias, candidate)` entry of the new question-shortcut fallback tables.
struct ChatAliasDefault {
	alias     string
	candidate key_hint.KeyBinding
}

// Body of the `prompt_stack_back`/`skip_question` retain loop in `from_config`.
fn retain_new_question_shortcut_bindings(configured ?types.KeybindingsSpec, bindings []key_hint.KeyBinding, aliases []ChatAliasDefault, resolved_keymap &types.TuiKeymap, chords &RuntimeChordKeymap) []key_hint.KeyBinding {
	if configured != none {
		return bindings.clone()
	}
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		mut alias_is_taken := false
		for entry in aliases {
			if binding == entry.candidate && (configured_main_surface_alias_is_used(resolved_keymap, entry.alias.clone())
				|| configured_context_alias_is_used(&resolved_keymap.list, entry.alias.clone())
				|| configured_context_alias_is_used(&resolved_keymap.vim_search, entry.alias)) {
				alias_is_taken = true
				break
			}
		}
		if !alias_is_taken && !chord_prefix_normalized_overlapping_context(chords, .chat, binding) {
			retained << binding
		}
	}
	return retained
}

// Body of the agents retain loop in `from_config`.
fn retain_agents_bindings(configured ?types.KeybindingsSpec, bindings []key_hint.KeyBinding, chords &RuntimeChordKeymap) []key_hint.KeyBinding {
	if configured != none {
		return bindings.clone()
	}
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		mut shadowed := false
		for chord in chords.bindings {
			if chord.action.context == .list && chord.chord.prefix == binding {
				shadowed = true
				break
			}
		}
		if !shadowed {
			retained << binding
		}
	}
	return retained
}

// Body of the `undo`/`redo`/`enter_replace_mode` retain loop in `from_config`.
fn retain_vim_history_bindings(setting ?types.KeybindingsSpec, bindings []key_hint.KeyBinding, configured &[]key_hint.KeyBinding, chords &RuntimeChordKeymap) []key_hint.KeyBinding {
	if setting != none {
		return bindings.clone()
	}
	mut retained := []key_hint.KeyBinding{}
	for binding in bindings {
		parts := binding.parts()
		input := event.KeyEvent.new(parts.code, parts.modifiers)
		if key_hint.bindings_are_pressed(configured, input) {
			continue
		}
		mut shadowed_by_chord := false
		for chord in chords.bindings {
			if chord.action.context.overlaps(.vim_normal) && chord.chord.prefix.is_press(input) {
				shadowed_by_chord = true
				break
			}
		}
		if !shadowed_by_chord {
			retained << binding
		}
	}
	return retained
}
