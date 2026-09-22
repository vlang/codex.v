module types

// STUB: codex_config::types re-exports of codex_config::tui_keymap. The persistence shapes below
// mirror `config/src/tui_keymap.rs`; only the declarations observed by `crate::keymap` are
// modeled here, and the normalizing `Deserialize` impl for `KeybindingSpec` is not ported yet.

// STUB: codex_config::types::MAX_FUNCTION_KEY.
// Highest function key supported by portable TUI keymap configuration.
pub const max_function_key = u8(24)

// STUB: codex_config::tui_keymap::KeybindingSpec.
//
// Normalized representation of one key event or a two-stroke key chord.
//
// The parser accepts a small alias set (for example `escape` -> `esc`,
// `pageup` -> `page-up`) and stores each stroke in its canonical form. Chord
// strokes are separated by one space, for example `ctrl-x ctrl-s`. Arrays of
// bindings remain alternatives; their entries do not form a chord together.
//
// Rust marks this `#[serde(transparent)]` so the JSON form is a bare string. The V stub keeps a
// named field, which only adds an object wrapper that `keymap_value_contains_alias` walks through.
pub struct KeybindingSpec {
pub mut:
	value string
}

// STUB: codex_config::tui_keymap::KeybindingSpec::as_str.
// Returns the canonical key-spec string (for example `ctrl-x ctrl-s`).
pub fn (spec &KeybindingSpec) as_str() string {
	return spec.value
}

// STUB: discriminant of the untagged codex_config::tui_keymap::KeybindingsSpec enum.
pub enum KeybindingsSpecKind {
	one
	many
}

// STUB: codex_config::tui_keymap::KeybindingsSpec.
//
// One action binding value in config.
//
// This accepts either:
//
// 1. A single key or chord string (`"ctrl-a"` or `"ctrl-x ctrl-s"`).
// 2. A list of alternative bindings (`["ctrl-a", "ctrl-x ctrl-s"]`).
//
// An empty list explicitly unbinds the action in that scope. Because an
// explicit empty list is still a configured value, runtime resolution must not
// fall through to global or built-in defaults for that action.
//
// Rust models this as an untagged enum; V uses an explicit tagged representation so the `One` and
// `Many` payloads stay disjoint.
pub struct KeybindingsSpec {
pub mut:
	kind KeybindingsSpecKind
	one  KeybindingSpec
	many []KeybindingSpec
}

// STUB: codex_config::tui_keymap::KeybindingsSpec::One.
pub fn KeybindingsSpec.from_one(spec KeybindingSpec) KeybindingsSpec {
	return KeybindingsSpec{
		kind: .one
		one:  spec
	}
}

// STUB: codex_config::tui_keymap::KeybindingsSpec::Many.
pub fn KeybindingsSpec.from_many(specs []KeybindingSpec) KeybindingsSpec {
	return KeybindingsSpec{
		kind: .many
		many: specs
	}
}

// STUB: codex_config::tui_keymap::KeybindingsSpec::specs.
//
// Returns all configured key specs for one action in declaration order.
//
// Callers should preserve this ordering when deriving UI hints so the
// first binding remains the primary affordance shown to users.
//
// Rust returns `Vec<&KeybindingSpec>`; V has no borrowed-element vector, so the specs are copied.
pub fn (spec &KeybindingsSpec) specs() []KeybindingSpec {
	return match spec.kind {
		.one { [spec.one] }
		.many { spec.many.clone() }
	}
}

// STUB: codex_config::tui_keymap::TuiGlobalKeymap.
// Global keybindings. These are used when a context does not define an override.
pub struct TuiGlobalKeymap {
pub mut:
	// Open the shared agent-session overview.
	open_agents ?KeybindingsSpec
	// Open the transcript overlay.
	open_transcript ?KeybindingsSpec
	// Open the external editor for the current draft.
	open_external_editor ?KeybindingsSpec
	// Copy the last agent response to the clipboard.
	copy ?KeybindingsSpec
	// Clear the terminal UI.
	clear_terminal ?KeybindingsSpec
	// Submit the current composer draft.
	submit ?KeybindingsSpec
	// Queue the current composer draft while a task is running.
	queue ?KeybindingsSpec
	// Toggle the composer shortcut overlay.
	toggle_shortcuts ?KeybindingsSpec
	// Toggle Vim mode for the composer input.
	toggle_vim_mode ?KeybindingsSpec
	// Toggle Fast mode.
	toggle_fast_mode ?KeybindingsSpec
	// Toggle raw scrollback mode for copy-friendly transcript selection.
	toggle_raw_output ?KeybindingsSpec
	// Switch between a side conversation and its parent without closing either.
	toggle_side_conversation ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiChatKeymap.
// Chat context keybindings.
pub struct TuiChatKeymap {
pub mut:
	// Toggle the microphone in an active voice conversation.
	toggle_voice_mute ?KeybindingsSpec
	// Interrupt the active turn.
	interrupt_turn ?KeybindingsSpec
	// Decrease the active reasoning effort.
	decrease_reasoning_effort ?KeybindingsSpec
	// Increase the active reasoning effort.
	increase_reasoning_effort ?KeybindingsSpec
	// Switch to the previous available permission mode.
	previous_permission_mode ?KeybindingsSpec
	// Switch to the next available permission mode.
	next_permission_mode ?KeybindingsSpec
	// Move up through pending async questions, then edit the most recently queued message.
	edit_queued_message ?KeybindingsSpec
	// Move back through pending async questions toward the composer.
	prompt_stack_back ?KeybindingsSpec
	// Skip the focused question.
	skip_question ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiComposerKeymap.
// Composer context keybindings. These override corresponding `global` actions.
pub struct TuiComposerKeymap {
pub mut:
	// Submit the current composer draft.
	submit ?KeybindingsSpec
	// Queue the current composer draft while a task is running.
	queue ?KeybindingsSpec
	// Toggle the composer shortcut overlay.
	toggle_shortcuts ?KeybindingsSpec
	// Open reverse history search or move to the previous match.
	history_search_previous ?KeybindingsSpec
	// Move to the next match in reverse history search.
	history_search_next ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiEditorKeymap.
// Editor context keybindings for text editing inside text areas.
pub struct TuiEditorKeymap {
pub mut:
	// Insert a newline in the editor.
	insert_newline ?KeybindingsSpec
	// Move cursor left by one grapheme.
	move_left ?KeybindingsSpec
	// Move cursor right by one grapheme.
	move_right ?KeybindingsSpec
	// Move cursor up one visual line.
	move_up ?KeybindingsSpec
	// Move cursor down one visual line.
	move_down ?KeybindingsSpec
	// Move cursor to beginning of previous word.
	move_word_left ?KeybindingsSpec
	// Move cursor to end of next word.
	move_word_right ?KeybindingsSpec
	// Move cursor to beginning of line.
	move_line_start ?KeybindingsSpec
	// Move cursor to end of line.
	move_line_end ?KeybindingsSpec
	// Delete one grapheme to the left.
	delete_backward ?KeybindingsSpec
	// Delete one grapheme to the right.
	delete_forward ?KeybindingsSpec
	// Delete the previous word.
	delete_backward_word ?KeybindingsSpec
	// Delete the next word.
	delete_forward_word ?KeybindingsSpec
	// Kill text from cursor to line start.
	kill_line_start ?KeybindingsSpec
	// Kill the current line.
	kill_whole_line ?KeybindingsSpec
	// Kill text from cursor to line end.
	kill_line_end ?KeybindingsSpec
	// Yank the kill buffer.
	yank ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiVimNormalKeymap.
//
// Vim normal-mode keybindings for modal editing inside text areas.
//
// Actions that use uppercase letters (like `A` for append-line-end) should
// be specified as `shift-a` in config; the runtime matcher handles
// cross-terminal shift-reporting differences automatically.
pub struct TuiVimNormalKeymap {
pub mut:
	// Enter insert mode at cursor (`i`).
	enter_insert ?KeybindingsSpec
	// Enter insert mode after cursor (`a`).
	append_after_cursor ?KeybindingsSpec
	// Enter insert mode at end of line (`A`).
	append_line_end ?KeybindingsSpec
	// Enter insert mode at first non-blank of line (`I`).
	insert_line_start ?KeybindingsSpec
	// Open a new line below and enter insert mode (`o`).
	open_line_below ?KeybindingsSpec
	// Open a new line above and enter insert mode (`O`).
	open_line_above ?KeybindingsSpec
	// Enter replace mode and overwrite characters under the cursor (`R`).
	enter_replace_mode ?KeybindingsSpec
	// Move cursor left (`h`).
	move_left ?KeybindingsSpec
	// Move cursor right (`l`).
	move_right ?KeybindingsSpec
	// Move cursor up (`k`), or recall older composer history at history boundaries.
	move_up ?KeybindingsSpec
	// Move cursor down (`j`), or recall newer composer history at history boundaries.
	move_down ?KeybindingsSpec
	// Move cursor to start of next word (`w`).
	move_word_forward ?KeybindingsSpec
	// Move cursor to start of previous word (`b`).
	move_word_backward ?KeybindingsSpec
	// Move cursor to end of current/next word (`e`).
	move_word_end ?KeybindingsSpec
	// Move cursor to start of line (`0`).
	move_line_start ?KeybindingsSpec
	// Move cursor to end of line (`$`).
	move_line_end ?KeybindingsSpec
	// Find the next character on the current line (`f`).
	find_forward ?KeybindingsSpec
	// Find the previous character on the current line (`F`).
	find_backward ?KeybindingsSpec
	// Stop before the next character on the current line (`t`).
	till_forward ?KeybindingsSpec
	// Stop after the previous character on the current line (`T`).
	till_backward ?KeybindingsSpec
	// Begin a jump to the first buffer line (`gg`).
	jump_top ?KeybindingsSpec
	// Jump to the last buffer line (`G`).
	jump_bottom ?KeybindingsSpec
	// Delete character under cursor (`x`).
	delete_char ?KeybindingsSpec
	// Replace the character under the cursor (`r`).
	replace_char ?KeybindingsSpec
	// Repeat the last complete edit (`.`).
	repeat_last_change ?KeybindingsSpec
	// Delete character under cursor and enter insert mode (`s`).
	substitute_char ?KeybindingsSpec
	// Delete from cursor to end of line (`D`).
	delete_to_line_end ?KeybindingsSpec
	// Change from cursor to end of line and enter insert mode (`C`).
	change_to_line_end ?KeybindingsSpec
	// Yank the entire line (`Y`).
	yank_line ?KeybindingsSpec
	// Paste after cursor (`p`).
	paste_after ?KeybindingsSpec
	// Begin delete operator; next key selects motion (`d`).
	start_delete_operator ?KeybindingsSpec
	// Begin yank operator; next key selects motion (`y`).
	start_yank_operator ?KeybindingsSpec
	// Begin change operator; next keys select a text object.
	start_change_operator ?KeybindingsSpec
	// Undo the last complete edit (`u`).
	undo ?KeybindingsSpec
	// Redo the last undone edit (`ctrl-r`).
	redo ?KeybindingsSpec
	// Cancel a pending operator and return to normal mode.
	cancel_operator ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiVimOperatorKeymap.
//
// Vim operator-pending keybindings for modal editing inside text areas.
//
// This context is active only while waiting for a motion after `d` or `y`.
// Repeating the operator key (`dd`, `yy`) targets the entire line. Pressing
// `Esc` cancels the pending operator and returns to normal mode without
// modifying text.
pub struct TuiVimOperatorKeymap {
pub mut:
	// Repeat delete operator to delete the whole line (`dd`).
	delete_line ?KeybindingsSpec
	// Repeat yank operator to yank the whole line (`yy`).
	yank_line ?KeybindingsSpec
	// Motion: left (`h`).
	motion_left ?KeybindingsSpec
	// Motion: right (`l`).
	motion_right ?KeybindingsSpec
	// Motion: up one line (`k`).
	motion_up ?KeybindingsSpec
	// Motion: down one line (`j`).
	motion_down ?KeybindingsSpec
	// Motion: to start of next word (`w`).
	motion_word_forward ?KeybindingsSpec
	// Motion: to start of previous word (`b`).
	motion_word_backward ?KeybindingsSpec
	// Motion: to end of current/next word (`e`).
	motion_word_end ?KeybindingsSpec
	// Motion: to start of line (`0`).
	motion_line_start ?KeybindingsSpec
	// Motion: to end of line (`$`).
	motion_line_end ?KeybindingsSpec
	// Motion: find the next character on the current line (`f`).
	motion_find_forward ?KeybindingsSpec
	// Motion: find the previous character on the current line (`F`).
	motion_find_backward ?KeybindingsSpec
	// Motion: stop before the next character on the current line (`t`).
	motion_till_forward ?KeybindingsSpec
	// Motion: stop after the previous character on the current line (`T`).
	motion_till_backward ?KeybindingsSpec
	// Motion: begin a jump to the first buffer line (`gg`).
	motion_jump_top ?KeybindingsSpec
	// Motion: jump to the last buffer line (`G`).
	motion_jump_bottom ?KeybindingsSpec
	// Select an inner text object after an operator.
	select_inner_text_object ?KeybindingsSpec
	// Select an around text object after an operator.
	select_around_text_object ?KeybindingsSpec
	// Cancel the pending operator and return to normal mode.
	cancel ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiVimSearchKeymap.
// Search motions shared by Vim normal and operator-pending input.
pub struct TuiVimSearchKeymap {
pub mut:
	// Search forward in the active buffer (`/`).
	forward ?KeybindingsSpec
	// Search backward in the active buffer (`?`).
	backward ?KeybindingsSpec
	// Repeat the accepted search (`n`).
	next ?KeybindingsSpec
	// Repeat in the opposite direction (`N`).
	previous ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiVimTextObjectKeymap.
// Vim text-object keybindings for modal editing inside text areas.
pub struct TuiVimTextObjectKeymap {
pub mut:
	// Text object: word.
	word ?KeybindingsSpec
	// Text object: whitespace-delimited WORD.
	big_word ?KeybindingsSpec
	// Text object: parentheses.
	parentheses ?KeybindingsSpec
	// Text object: brackets.
	brackets ?KeybindingsSpec
	// Text object: braces.
	braces ?KeybindingsSpec
	// Text object: double quotes.
	double_quote ?KeybindingsSpec
	// Text object: single quotes.
	single_quote ?KeybindingsSpec
	// Text object: backticks.
	backtick ?KeybindingsSpec
	// Cancel the pending text-object command.
	cancel ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiPagerKeymap.
// Pager context keybindings for transcript and static overlays.
pub struct TuiPagerKeymap {
pub mut:
	// Scroll up by one row.
	scroll_up ?KeybindingsSpec
	// Scroll down by one row.
	scroll_down ?KeybindingsSpec
	// Scroll up by one page.
	page_up ?KeybindingsSpec
	// Scroll down by one page.
	page_down ?KeybindingsSpec
	// Scroll up by half a page.
	half_page_up ?KeybindingsSpec
	// Scroll down by half a page.
	half_page_down ?KeybindingsSpec
	// Jump to the beginning.
	jump_top ?KeybindingsSpec
	// Jump to the end.
	jump_bottom ?KeybindingsSpec
	// Close the pager overlay.
	close ?KeybindingsSpec
	// Close the transcript overlay via its dedicated toggle key.
	close_transcript ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiListKeymap.
// List selection context keybindings for popup-style selectable lists.
pub struct TuiListKeymap {
pub mut:
	// Move list selection up.
	move_up ?KeybindingsSpec
	// Move list selection down.
	move_down ?KeybindingsSpec
	// Move horizontally left in list pickers that support horizontal actions.
	move_left ?KeybindingsSpec
	// Move horizontally right in list pickers that support horizontal actions.
	move_right ?KeybindingsSpec
	// Move list selection up by one page.
	page_up ?KeybindingsSpec
	// Move list selection down by one page.
	page_down ?KeybindingsSpec
	// Jump to the first list item.
	jump_top ?KeybindingsSpec
	// Jump to the last list item.
	jump_bottom ?KeybindingsSpec
	// Accept current selection.
	accept ?KeybindingsSpec
	// Cancel and close selection view.
	cancel ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiAgentsKeymap.
// Shortcuts specific to the shared agents overview.
pub struct TuiAgentsKeymap {
pub mut:
	// Open the session resume picker.
	resume ?KeybindingsSpec
	// Search the available agent tasks.
	search ?KeybindingsSpec
	// Start composing a new agent task.
	new_task ?KeybindingsSpec
	// Rename the selected task.
	rename ?KeybindingsSpec
	// Stop the selected running task.
	stop ?KeybindingsSpec
	// Toggle grouping tasks by status or project.
	toggle_grouping ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiApprovalKeymap.
// Approval overlay keybindings.
pub struct TuiApprovalKeymap {
pub mut:
	// Open the full-screen approval details view.
	open_fullscreen ?KeybindingsSpec
	// Open the thread that requested approval when shown from another thread.
	open_thread ?KeybindingsSpec
	// Approve the primary option.
	approve ?KeybindingsSpec
	// Approve for session when that option exists.
	approve_for_session ?KeybindingsSpec
	// Approve with exec-policy prefix when that option exists.
	approve_for_prefix ?KeybindingsSpec
	// Deny without providing follow-up guidance.
	deny ?KeybindingsSpec
	// Decline and provide corrective guidance.
	decline ?KeybindingsSpec
	// Cancel an elicitation request.
	cancel ?KeybindingsSpec
}

// STUB: codex_config::tui_keymap::TuiKeymap.
//
// Raw keymap configuration from `[tui.keymap]`.
//
// Each context contains action-level overrides. Missing actions inherit from
// built-in defaults, and selected chat/composer actions can fall back
// through `global` during runtime resolution.
//
// This type is intentionally a persistence shape, not the structure used by
// input handlers. Runtime consumers should resolve it into
// `RuntimeKeymap` first so precedence, empty-list unbinding, and duplicate-key
// validation are applied consistently.
pub struct TuiKeymap {
pub mut:
	global          TuiGlobalKeymap
	chat            TuiChatKeymap
	composer        TuiComposerKeymap
	editor          TuiEditorKeymap
	vim_normal      TuiVimNormalKeymap
	vim_operator    TuiVimOperatorKeymap
	vim_search      TuiVimSearchKeymap
	vim_text_object TuiVimTextObjectKeymap
	pager           TuiPagerKeymap
	list            TuiListKeymap
	agents          TuiAgentsKeymap
	approval        TuiApprovalKeymap
}
