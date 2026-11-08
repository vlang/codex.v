module bottom_pane

import codex_tui.slash_command
import codex_utils_fuzzy_match
import codex_app_server_protocol.skill_metadata
import codex_connectors
import codex_connectors.metadata as connector_metadata
import codex_file_search
import codex_plugin
import codex_protocol.openai_models
import codex_protocol.thread_id as protocol_thread_id
import codex_protocol.user_input
import codex_tui.app_event
import codex_tui.app_event_sender
import codex_tui.clipboard_paste
import codex_tui.history_cell
import codex_tui.key_hint
import codex_tui.keymap as tui_keymap
import codex_tui.bottom_pane.prompt_args
import codex_tui.bottom_pane.slash_input as slash_parser
import codex_tui.style as tui_style
import codex_tui.task_mentions
import crossterm.cursor as terminal_cursor
import crossterm.event as terminal_event
import image
import ratatui.buffer as rat_buffer
import ratatui.layout as rat_layout
import ratatui.style as rat_style
import ratatui.text as rat_text
import time
import tracing

// The chat composer is the bottom-pane text input state machine.
// 
// It edits the [`TextArea`] buffer and attachment elements, routes popup keys, promotes
// completed slash commands to atomic elements, and handles Enter submission/newlines.
// It also shows Luna Reserve's yellow prompt arrow and detects unbracketed paste bursts
// from raw key streams, particularly on Windows.
// 
// The plain-text preset keeps command prefixes literal, including `!`, so Enter and Tab
// submit ordinary text without enabling shell mode.
// 
// # Mention Menus
// 
// By default, `@` lists plugins, filesystem entries, and skills. Skills are hidden when their
// owning plugin is listed. `$` lists individual skills and apps, but not plugins.
// Disabling `mentions_v2` restores file-only `@` search and adds plugins back to `$`.
// 
// # Key Event Routing
// 
// Plain Left opens agents when the local-daemon composer is empty and available for input.
// Explicit editor remaps take precedence.
// Most key handling goes through [`ChatComposer::handle_key_event`], which dispatches to a
// popup-specific handler if a popup is visible and otherwise to
// [`ChatComposer::handle_key_event_without_popup`]. After every handled key, we call
// [`ChatComposer::sync_popups`] so UI state follows the latest buffer/cursor.
// Fresh Vim drafts start in Insert; Normal `/` and `?` search the composer.
// Backspace on an empty Vim search query cancels search and any pending operator.
// 
// # Completion and Popup Dismissal
// 
// Popup targeting resolves an editable token range around the cursor and treats atomic text
// elements as hard boundaries. When that range begins immediately after an atomic element, the
// insertion path first adds a horizontal separator and shifts the range so the completion cannot
// merge with the atomic element. After replacing the range, completion leaves the cursor after one
// horizontal separator. It advances across an existing separator when no suffix would be joined;
// otherwise it inserts a space, preserving the existing separator before a non-whitespace suffix.
// It also inserts a space rather than crossing a line break.
// 
// `Esc` records the active token as dismissed. A completed value that begins with `@` or `$` is
// also re-dismissed before popup synchronization, because separator affinity can still identify
// the completed token to the left of the cursor. Synchronization keeps the popup hidden only while
// the query, complete token text, and ordinal among matching occurrences remain the same.
// Whitespace and atomic-element edges delimit occurrences, while nested sigils do not. This
// preserves dismissal across offset-only edits without suppressing a later identical token.
// 
// Slash-command dismissal is tracked separately. Pressing `Esc` while the command popup is active
// records the first-line `/name` token and keeps the popup closed while that token is unchanged.
// Editing the command token clears the dismissal and allows the popup to reopen.
// 
// # History Navigation (↑/↓)
// 
// The Up/Down history path is managed by [`ChatComposerHistory`]. It merges:
// 
// - Persistent cross-session history (text-only storage; task links recover element ranges and
//   mention bindings, but attachments cannot be restored).
// - Local in-session history (full text + text elements + local/remote image attachments).
// 
// Plain-text history recall strips images and their placeholders.
// When recalling a persistent entry, encoded task links restore atomic elements and bindings.
// Recall moves the cursor to the end. Question editors copy primary history on recall/search;
// draft capture cancels previews, and restoration resets traversal.
// Ctrl+R searches history in the footer and previews matches in the composer.
// Enter accepts the preview; Esc restores the original draft.
// Vim undo/redo snapshots complete drafts and groups direct edits with active Vim transactions.
// An active edit keeps one separately capped snapshot; canceling does not evict committed history.
// Canceled history previews restore history and active commands; accepting another prompt resets them.
// Normal-mode Ctrl+R redoes an edit, or does nothing when redo is empty. Insert-mode Ctrl+R
// keeps prompt-history search; explicitly configured keybindings retain precedence.
// Vim queries stay draft-local.
// 
// Slash commands are staged for local history instead of being recorded immediately. Command
// recall is a two-phase handoff: stage the submitted slash text here, then record it after
// `ChatWidget` dispatches the command.
// 
// # Startup Draft Handoff
// 
// Startup uses a provisional plain-text composer: editing remains available, but submission,
// popups, attachments, and other actions are disabled. [`ComposerDraftSnapshot`] transfers its
// text, cursor, pending paste placeholders, local history, and recent activity to the fully
// initialized composer.
// `ChatWidget` merges the draft with any existing initial prompt and attachments, rebasing cursor
// and placeholder positions while preserving both composers' contents. The draft remains deferred
// until protected views close, input is enabled, and required sandbox setup completes.
// 
// # Submission and Prompt Expansion
// 
// `Enter` submits immediately. `Tab` requests queuing while a task is running; if no task is
// running, `Tab` submits just like Enter so input is never dropped.
// Vim Replace shares Insert's composer actions; only textarea editing differs.
// Literal completion/paste edits discard stale Replace recovery; subsequent typing records anew.
// Token markers added during Replace are removed when restoring overwritten characters.
// `Tab` does not submit when entering a `!` shell command.
// 
// On submit/queue paths, the composer:
// 
// - Expands pending paste placeholders so element ranges align with the final text.
// - Trims whitespace and rebases elements when `trim_submission` is enabled (the default).
//   Otherwise, preserves both.
// - Treats a leading `!` revealed only by paste expansion as literal model input, not shell input.
// - Prunes local attached images so only placeholders that survive expansion are sent.
// - Preserves remote image URLs as separate attachments even when text is empty.
// 
// When these paths clear the visible textarea after a successful submit or slash-command
// dispatch, they intentionally preserve the textarea kill buffer. That lets users `Ctrl+K` part
// of a draft, perform a composer action such as changing reasoning level, and then `Ctrl+Y` the
// killed text back into the now-empty draft.
// 
// The numeric auto-submit path used by the slash popup performs the same pending-paste expansion
// and attachment pruning, and clears pending paste state on success.
// Slash commands with arguments (like `/plan` and `/review`) reuse the same preparation path so
// pasted content and text elements are preserved when extracting args.
// 
// # Parent-Owned Thread Mode
// 
// Parent-owned subagent threads keep the draft editable while blocking agent-directed submission.
// On the `Enter` and `Tab` submission paths, normal prompts, disallowed slash commands, and `!`
// shell commands return `ParentOwnedInputBlocked` without clearing the draft. Bare local and
// navigation slash commands remain available so users can leave or manage the view. Transcript
// exports also remain available, including an explicit destination filename.
// 
// During reconnection, `handle_disconnected_key` edits the draft directly without
// popup dispatch or submission. Enter and Tab leave the draft intact until reconnection succeeds.
// Collapsed pastes expand into editable text so the full draft can be copied before quitting.
// 
// # Reasoning Effort Animations
// 
// The composer observes the effective reasoning tier whenever model-dependent surfaces refresh.
// The first observation, session configuration, and restored threads establish a baseline;
// genuine changes to Max/Ultra can then queue composer and status-line transitions when motion
// and color support allow them.
// Repeated selections do not restart either effect, dropping below Max clears them, and
// restoration clears any transition queued while replaying the saved session. Rendering advances
// active transitions through the frame requester until they finish.
// 
// # Large Paste Placeholders
// 
// Large pastes insert an element placeholder in the buffer and store the full text in
// `pending_pastes`. The placeholder label is derived from the pasted character count:
// 
// - First paste of a given size uses `[Pasted Content N chars]`.
// - Additional pending pastes of the same size add a numeric suffix (`#2`, `#3`, ...), where the
//   next suffix is computed from the placeholders that still exist in `pending_pastes`.
// - When all placeholders for a size are cleared or deleted, the next paste of that size reuses
//   the base label without a suffix.
// 
// # Remote Image Rows (Up/Down/Delete)
// 
// Remote image URLs are rendered as non-editable `[Image #N]` rows above the textarea (inside the
// same composer block). These rows represent image attachments rehydrated from app-server/backtrack
// history; TUI users can remove them, but cannot type into that row region.
// 
// Keyboard behavior:
// 
// - `Up` at textarea cursor `0` enters remote-row selection at the last remote image.
// - `Up`/`Down` move selection between remote rows.
// - `Down` on the last row clears selection and returns control to the textarea.
// - `Delete`/`Backspace` remove the selected remote image row.
// 
// Placeholder numbering is unified across remote and local images:
// 
// - Remote rows occupy `[Image #1]..[Image #M]`.
// - Local placeholders are offset after that range (`[Image #M+1]..`).
// - Deleting a remote row relabels local placeholders to keep numbering contiguous.
// 
// # Non-bracketed Paste Bursts
// 
// On some terminals (especially on Windows), pastes arrive as a rapid sequence of
// `KeyCode::Char` and `KeyCode::Enter` key events instead of a single paste event.
// 
// To avoid misinterpreting these bursts as real typing (and to prevent transient UI effects like
// shortcut overlays toggling on a pasted `?`), we feed text-producing character events (plain,
// Shift, or Windows AltGr) into
// [`PasteBurst`](super::paste_burst::PasteBurst), which buffers bursts and later flushes them
// through [`ChatComposer::handle_paste`].
// Parent views must keep flushing editors that lose focus while input is buffered; a hidden
// editor's pending burst can otherwise keep the shared draw loop waiting indefinitely.
// 
// The burst detector intentionally treats ASCII and non-ASCII differently:
// 
// - ASCII: we briefly hold the first fast char (flicker suppression) until we know whether the
//   stream is paste-like.
// - non-ASCII: we do not hold the first char (IME input would feel dropped), but we still allow
//   burst detection for actual paste streams.
// 
// The burst detector can also be disabled (`disable_paste_burst`), which bypasses the state
// machine and treats the key stream as normal typing. When toggling from enabled → disabled, the
// composer flushes/clears any in-flight burst state so it cannot leak into subsequent input.
// 
// For the detailed burst state machine, see `codex-rs/tui/src/bottom_pane/paste_burst.rs`.
// 
// # PasteBurst Integration Points
// 
// The burst detector is consulted in a few specific places:
// 
// - [`ChatComposer::handle_input_basic`]: flushes any due burst first, then intercepts plain char
//   input to either buffer it or insert normally.
// - [`ChatComposer::handle_non_ascii_char`]: handles the non-ASCII/IME path without holding the
//   first char, while still allowing paste detection via retro-capture.
// - [`ChatComposer::flush_paste_burst_if_due`]/[`ChatComposer::handle_paste_burst_flush`]: called
//   from UI ticks to turn a pending burst into either an explicit paste (`handle_paste`) or a
//   normal typed character.
// 
// # Input Disabled Mode
// 
// The composer can be temporarily read-only (`input_enabled = false`). In that mode it ignores
// edits and renders a placeholder prompt instead of the editable textarea. This is part of the
// overall state machine, since it affects which transitions are even possible from a given UI
// state.
// 

// If the pasted content exceeds this number of characters, replace it with a
// placeholder in the UI.
pub const large_paste_char_threshold = 1000

// Conservative cap mirrored from codex_protocol::user_input::MAX_USER_INPUT_TEXT_CHARS.
pub fn user_input_too_large_message(actual_chars int) string {
	return 'Message exceeds the maximum length of ${user_input.max_user_input_text_chars} characters (${actual_chars} provided).'
}

// Result returned when the user interacts with the text area.
// Rust payload variants use an
// explicit V tag so all ownership-bearing payloads have one unambiguous owner.
pub enum InputResultKind {
	submitted
	queued
	// A bare slash command parsed by the composer.
	//
	// Callers that dispatch this variant are also responsible for resolving any pending local
	// command-history entry that the composer staged before clearing the visible input.
	command
	// A bare model service-tier command parsed by the composer.
	service_tier_command
	// An inline slash command and its trimmed argument text.
	//
	// The `TextElement` ranges are rebased into the argument string, while any pending local
	// command-history entry still represents the original command invocation that should be
	// committed only if dispatch accepts it.
	command_with_args
	// Agent-directed input was attempted while viewing a parent-owned spawned child thread.
	parent_owned_input_blocked
	no_result
}

pub struct InputResult {
pub:
	kind           InputResultKind
	text           string
	text_elements  []user_input.TextElement
	command        slash_command.SlashCommand
	service_tier   ServiceTierCommand
	action         QueuedInputAction
	pending_pastes []PendingPaste
}

// A pending paste keeps the UI placeholder and its owned full payload together.
pub struct PendingPaste {
pub:
	placeholder string
	actual      string
}

fn input_result_none() InputResult {
	return InputResult{ kind: .no_result }
}

fn parent_owned_command_is_allowed(command slash_command.SlashCommand, args &string) bool {
	if command == .export_cmd {
		return true
	}
	if args.len != 0 {
		return false
	}
	return command in [.feedback, .new_thread, .clear, .resume, .app, .side, .btw, .agents,
		.multi_agents, .vim, .keymap, .elevate_sandbox, .sandbox_read_root, .experimental, .memories,
		.quit, .exit, .logout, .copy, .raw, .diff, .mention, .skills, .import_cmd, .hooks, .status,
		.usage, .ide, .debug_config, .title, .statusline, .theme, .pets, .ps, .stop, .memory_drop,
		.memory_update, .mcp, .apps, .plugins, .rollout]
}

pub enum QueuedInputAction {
	plain
	// Preserve model-input provenance when paste expansion reveals a leading shell sigil.
	literal
	parse_slash
	run_shell
}

enum PendingPasteHandling {
	expand
	preserve
}

// Shared composer behavior; defaults match the main chat input.
pub struct ChatComposerConfig {
pub:
	// Whether command/file/skill popups are allowed to appear.
	popups_enabled bool = true
	// Whether `/...` input is parsed and dispatched as slash commands.
	slash_commands_enabled bool = true
	// Whether a leading `!` switches the editor into shell mode.
	shell_commands_enabled bool = true
	// Whether pasting a file path can attach local images.
	image_paste_enabled bool = true
	// Strip leading and trailing whitespace from submissions.
	trim_submission bool = true
	// Embedded editors reset Vim only when their owner accepts the answer.
	reset_vim_on_submission bool = true
}

pub fn ChatComposerConfig.default_config() ChatComposerConfig {
	return ChatComposerConfig{}
}

// A minimal preset for plain-text inputs embedded in other surfaces.
//
// This disables popups, slash and shell commands, and image-path attachment behavior
// so the composer behaves like a simple notes field.
pub fn ChatComposerConfig.plain_text() ChatComposerConfig {
	return ChatComposerConfig{
		popups_enabled:          false
		slash_commands_enabled:  false
		shell_commands_enabled:  false
		image_paste_enabled:     false
		trim_submission:         true
		reset_vim_on_submission: true
	}
}

// Rust stores the catalog in an `Arc<Vec<_>>`. A heap wrapper preserves one shared backing array
// without cloning every owning element; callers borrow slices through skills()/plugins().
struct SkillCatalogRef {
	items []skill_metadata.SkillMetadata
}

struct PluginCatalogRef {
	items []codex_plugin.PluginCapabilitySummary
}

pub struct ChatComposer {
mut:
	draft                         DraftState
	popups                        PopupState
	app_event_tx                  app_event_sender.AppEventSender
	history                       ChatComposerHistory
	agents_navigation_enabled     bool
	footer                        FooterState
	has_focus                     bool
	frame_requester               ?FrameRequester
	effort_tier                   ?EffortTier
	effort_animation_style        ?IgnitionStyle
	effort_ignition               ?EffortIgnition
	astra_sparkle                 ?Sparkle
	effort_status_line_transition ?EffortStatusLineTransition
	effort_observed               bool
	luna_reserve_active           bool
	attachments                   AttachmentState
	placeholder_text              string
	blocks_direct_input           bool
	is_task_running               bool
	queue_submissions             bool
	// Slash-command draft staged for local recall after application-level dispatch.
	//
	// This slot is intentionally separate from `ChatComposerHistory` so inline slash commands can
	// prepare their argument text without also double-recording the full command invocation.
	pending_slash_command_history   ?HistoryEntry
	skills                          ?&SkillCatalogRef
	plugins                         ?&PluginCatalogRef
	task_mentions                   ?[]task_mentions.TaskMention
	connectors_snapshot             ?app_event.ConnectorsSnapshot
	collaboration_modes_enabled     bool
	config                          ChatComposerConfig
	connectors_enabled              bool
	plugins_command_enabled         bool
	token_activity_command_enabled  bool
	service_tier_commands_enabled   bool
	service_tier_commands           []ServiceTierCommand
	mentions_v2_enabled             bool
	goal_command_enabled            bool
	personality_command_enabled     bool
	voice_command_enabled           bool
	worktrees_enabled               bool
	windows_degraded_sandbox_active bool
	side_conversation_active        bool
	history_search                  ?HistorySearchSession
	vim_history                     VimHistory
	submit_keys                     []key_hint.KeyBinding
	queue_keys                      []key_hint.KeyBinding
	toggle_shortcuts_keys           []key_hint.KeyBinding
	history_search_previous_keys    []key_hint.KeyBinding
	history_search_next_keys        []key_hint.KeyBinding
	editor_keymap                   tui_keymap.EditorKeymap
	vim_normal_keymap               tui_keymap.VimNormalKeymap
}

// A resolved legacy `$` target plus any catalog built while disambiguating shell syntax.
struct MentionCompletionTarget {
	start             int
	end               int
	query             string
	prebuilt_mentions ?[]MentionItem
}

pub struct ComposerDraft {
	text              string
	text_elements     []user_input.TextElement
	local_image_paths []string
	remote_image_urls []string
	mention_bindings  []MentionBinding
	pending_pastes    []PendingPaste
	cursor            int
}

pub struct ComposerDraftSnapshot {
pub:
	text                      string
	cursor                    int
	text_elements             []user_input.TextElement
	local_images              []LocalImageAttachment
	remote_image_urls         []string
	mention_bindings          []MentionBinding
	pending_pastes            []PendingPaste
	startup_local_history     []HistoryEntry
	last_composer_activity_at ?i64
}

const footer_spacing_height = u16(0)

// V cannot make an optional multi-return tuple, so the Rust `(u16, u16)` cursor pair is retained
// as a fixed-shape value object rather than a variable-length array.
pub struct CursorPosition {
pub:
	x u16
	y u16
}

// Construct the slash-input view from current composer state.
fn (composer &ChatComposer) slash_input() SlashInput {
	return SlashInput.new(composer.slash_commands_enabled(), composer.draft.is_bash_mode, composer.builtin_command_flags(), &composer.service_tier_commands)
}

pub fn ChatComposer.new(has_input_focus bool, app_event_tx app_event_sender.AppEventSender, enhanced_keys_supported bool,
	placeholder_text string, disable_paste_burst bool) ChatComposer {
	return ChatComposer.new_with_config(has_input_focus, app_event_tx, enhanced_keys_supported, placeholder_text, disable_paste_burst, ChatComposerConfig.default_config())
}

// Construct a composer with explicit feature gating.
//
// This enables reuse in contexts like request-user-input where we want
// the same visuals and editing behavior without slash commands or popups.
pub fn ChatComposer.new_with_config(has_input_focus bool, app_event_tx app_event_sender.AppEventSender,
	enhanced_keys_supported bool, placeholder_text string, disable_paste_burst bool,
	config ChatComposerConfig) ChatComposer {
	runtime_keymap := tui_keymap.RuntimeKeymap.defaults()
	insert_newline_binding := footer_insert_newline_key(&runtime_keymap.editor.insert_newline, enhanced_keys_supported)
	mut composer := ChatComposer{
		draft:                        DraftState.new()
		app_event_tx:                 app_event_tx
		history:                      ChatComposerHistory.new()
		footer:                       FooterState{
			quit_shortcut_key:    key_hint.ctrl(terminal_event.KeyCode{ kind: .char_key, ch: `c` })
			use_shift_enter_hint: enhanced_keys_supported
			mode:                 .composer_empty
			insert_newline_key:   if binding := insert_newline_binding {
				key_hint.ShortcutHint.single(binding)
			} else {
				none
			}
		}
		has_focus:                    has_input_focus
		placeholder_text:             placeholder_text
		config:                       config
		submit_keys:                  runtime_keymap.composer.submit.clone()
		queue_keys:                   runtime_keymap.composer.queue.clone()
		toggle_shortcuts_keys:        runtime_keymap.composer.toggle_shortcuts.clone()
		history_search_previous_keys: runtime_keymap.composer.history_search_previous.clone()
		history_search_next_keys:     runtime_keymap.composer.history_search_next.clone()
		editor_keymap:                tui_keymap.EditorKeymap{
			insert_newline: runtime_keymap.editor.insert_newline.clone()
			move_up:        runtime_keymap.editor.move_up.clone()
			move_down:      runtime_keymap.editor.move_down.clone()
		}
		vim_normal_keymap:            tui_keymap.VimNormalKeymap{
			move_up:   runtime_keymap.vim_normal.move_up.clone()
			move_down: runtime_keymap.vim_normal.move_down.clone()
		}
	}
	// Populate footer hints from the same default snapshot used by dispatch and the textarea.
	composer.set_keymap_bindings(&runtime_keymap)
	// Apply configuration via the setter to keep side-effects centralized.
	composer.set_disable_paste_burst(disable_paste_burst)
	return composer
}

pub fn (mut composer ChatComposer) set_frame_requester(frame_requester FrameRequester) {
	composer.frame_requester = frame_requester
}

// Records the effective reasoning tier, captures the outgoing status
// line, and queues the one-shot effects for a genuine Max/Ultra change
// after the initial baseline.
// ReasoningEffort is allocation-free/Copy-equivalent, so V uses an optional value instead of the
// compiler-fragile Rust `&Option<T>`/V `?&T` shape.
pub fn (mut composer ChatComposer) set_active_reasoning_effort(effort ?openai_models.ReasoningEffort,
	animations_enabled bool) bool {
	tier := effort_tier_from_effort(effort)
	is_baseline := !composer.effort_observed
	composer.effort_observed = true
	if composer.effort_tier == tier {
		return false
	}
	composer.effort_tier = tier
	composer.effort_ignition = none
	composer.effort_status_line_transition = none
	if active_tier := tier {
		if !is_baseline && animations_enabled {
			style := IgnitionStyle.random(composer.effort_animation_style)
			composer.effort_ignition = EffortIgnition.new(active_tier, style)
			composer.effort_animation_style = style
			if composer.footer.status_line_enabled {
				props := composer.footer_props()
				if previous := passive_footer_status_line(&props) {
					composer.effort_status_line_transition = EffortStatusLineTransition{
						tier:     active_tier
						previous: previous
					}
				}
			}
			if requester := composer.frame_requester {
				requester.schedule_frame()
			}
		}
	}
	return true
}

// Establishes the current tier without retaining or starting a one-shot effect.
pub fn (mut composer ChatComposer) set_active_reasoning_effort_baseline(effort ?openai_models.ReasoningEffort) {
	composer.effort_tier = effort_tier_from_effort(effort)
	composer.effort_observed = true
	composer.effort_ignition = none
	composer.effort_status_line_transition = none
}

fn effort_tier_from_effort(effort ?openai_models.ReasoningEffort) ?EffortTier {
	if value := effort {
		return match value {
			.max { EffortTier.max }
			.ultra { EffortTier.ultra }
			else { none }
		}
	}
	return none
}

pub fn (mut composer ChatComposer) set_skill_mentions(skills ?[]skill_metadata.SkillMetadata) {
	if values := skills {
		composer.skills = &SkillCatalogRef{ items: values }
	} else {
		composer.skills = none
	}
	composer.refresh_mentions_v2_popup_candidates()
	composer.sync_popups()
}

pub fn (mut composer ChatComposer) set_plugin_mentions(plugins ?[]codex_plugin.PluginCapabilitySummary) {
	if values := plugins {
		composer.plugins = &PluginCatalogRef{ items: values }
	} else {
		composer.plugins = none
	}
	composer.refresh_mentions_v2_popup_candidates()
	composer.sync_popups()
}

pub fn (mut composer ChatComposer) set_task_mentions_enabled(enabled bool) {
	composer.task_mentions = if enabled { []task_mentions.TaskMention{} } else { none }
	composer.refresh_mentions_v2_popup_candidates()
	if enabled && composer.popups.active.kind == .mention_v2 {
		if query := composer.current_mentions_v2_token() {
			if query.len > 0 {
				composer.app_event_tx.send(app_event.start_file_search(query))
			}
		}
	}
}

pub fn (composer &ChatComposer) task_mentions_enabled() bool {
	return composer.task_mentions != none
}

pub fn (mut composer ChatComposer) on_task_search_result(query &string, matches []task_mentions.TaskMention) {
	current := composer.current_mentions_v2_token() or { return }
	if current != *query {
		return
	}
	if composer.task_mentions == none {
		return
	}
	mut mentioned_ids := map[string]bool{}
	for binding in composer.snapshot_mention_bindings() {
		if thread_id := task_mentions.valid_thread_path(&binding.path) {
			mentioned_ids[thread_id] = true
		}
	}
	mut filtered := []task_mentions.TaskMention{}
	for task in matches {
		if mentioned_ids.len < task_mentions.max_referenced_tasks && task.thread_id !in mentioned_ids {
			filtered << task
		}
	}
	composer.task_mentions = filtered
	composer.refresh_mentions_v2_popup_candidates()
}

// Refreshes an open mention catalog when skill or plugin metadata changes.
fn (mut composer ChatComposer) refresh_mentions_v2_popup_candidates() {
	if composer.popups.active.kind == .mention_v2 {
		tasks := composer.task_mentions or { []task_mentions.TaskMention{} }
		items := build_mentions_v2_catalog(composer.skills(), composer.plugins(), &tasks)
		composer.popups.active.mention_v2.set_candidates(items)
	}
}

pub fn (mut composer ChatComposer) set_plugins_command_enabled(enabled bool) {
	composer.plugins_command_enabled = enabled
}

pub fn (mut composer ChatComposer) set_token_activity_command_enabled(enabled bool) {
	composer.token_activity_command_enabled = enabled
}

pub fn (mut composer ChatComposer) set_mentions_v2_enabled(enabled bool) {
	composer.mentions_v2_enabled = enabled
	composer.history.set_at_mention_restore_enabled(enabled)
	composer.sync_popups()
}

// Toggle composer-side image paste handling.
//
// This only affects whether image-like paste content is converted into attachments; the
// `ChatWidget` layer still performs capability checks before images are submitted.
pub fn (mut composer ChatComposer) set_image_paste_enabled(enabled bool) {
	composer.config = ChatComposerConfig{
		...composer.config
		image_paste_enabled: enabled
	}
}

pub fn (mut composer ChatComposer) set_connector_mentions(snapshot ?app_event.ConnectorsSnapshot) {
	composer.connectors_snapshot = snapshot
	composer.sync_popups()
}

pub fn (mut composer ChatComposer) take_mention_bindings() []MentionBinding {
	bindings := composer.snapshot_mention_bindings()
	composer.draft.mention_bindings.clear()
	return bindings
}

pub fn (mut composer ChatComposer) set_collaboration_modes_enabled(enabled bool) {
	composer.collaboration_modes_enabled = enabled
}

pub fn (mut composer ChatComposer) set_connectors_enabled(enabled bool) {
	composer.connectors_enabled = enabled
}

pub fn (mut composer ChatComposer) set_service_tier_commands_enabled(enabled bool) {
	composer.service_tier_commands_enabled = enabled
}

pub fn (mut composer ChatComposer) set_service_tier_commands(commands []ServiceTierCommand) {
	composer.service_tier_commands = commands
	composer.sync_popups()
}

pub fn (mut composer ChatComposer) set_goal_command_enabled(enabled bool) {
	composer.goal_command_enabled = enabled
}

pub fn (mut composer ChatComposer) set_voice_command_enabled(enabled bool) {
	composer.voice_command_enabled = enabled
}

// Replace composer, editor, and footer-hint key bindings from one runtime snapshot.
//
// Submit and queue bindings are cached here because composer dispatch must
// check them before generic textarea editing. The embedded textarea receives
// the same snapshot's editor bindings so a live remap cannot leave submit
// keys updated while cursor/editing keys still use old defaults.
pub fn (mut composer ChatComposer) set_keymap_bindings(keymap &tui_keymap.RuntimeKeymap) {
	composer.submit_keys = keymap.composer.submit.clone()
	composer.queue_keys = keymap.composer.queue.clone()
	composer.toggle_shortcuts_keys = keymap.composer.toggle_shortcuts.clone()
	composer.history_search_previous_keys = keymap.composer.history_search_previous.clone()
	composer.history_search_next_keys = keymap.composer.history_search_next.clone()
	// Rust clones shared Arc handles here. V arrays are reference-backed, but explicit struct clones
	// preserve the caller/composer ownership boundary and keep both owners reusable.
	composer.editor_keymap = tui_keymap.EditorKeymap{
		insert_newline: keymap.editor.insert_newline.clone()
		move_up:        keymap.editor.move_up.clone()
		move_down:      keymap.editor.move_down.clone()
	}
	composer.vim_normal_keymap = tui_keymap.VimNormalKeymap{
		move_up:   keymap.vim_normal.move_up.clone()
		move_down: keymap.vim_normal.move_down.clone()
	}
	composer.draft.textarea.set_keymap_bindings(keymap)
	composer.footer.external_editor_key = keymap.primary_hint(.global, 'open_external_editor')
	composer.footer.show_transcript_key = keymap.primary_hint(.global, 'open_transcript')
	if preferred := keymap.primary_hint(.editor, 'insert_newline') {
		if preferred.kind == .chord {
			composer.footer.insert_newline_key = preferred
		} else if binding := footer_insert_newline_key(&keymap.editor.insert_newline, composer.footer.use_shift_enter_hint) {
			composer.footer.insert_newline_key = key_hint.ShortcutHint.single(binding)
		} else {
			composer.footer.insert_newline_key = none
		}
	} else if binding := footer_insert_newline_key(&keymap.editor.insert_newline, composer.footer.use_shift_enter_hint) {
		composer.footer.insert_newline_key = key_hint.ShortcutHint.single(binding)
	} else {
		composer.footer.insert_newline_key = none
	}
	composer.footer.queue_key = keymap.primary_hint(.composer, 'queue')
	composer.footer.toggle_shortcuts_key = keymap.primary_hint(.composer, 'toggle_shortcuts')
	composer.footer.history_search_key = keymap.primary_hint(.composer, 'history_search_previous')
	composer.footer.reasoning_down_key = keymap.primary_hint(.chat, 'decrease_reasoning_effort')
	composer.footer.reasoning_up_key = keymap.primary_hint(.chat, 'increase_reasoning_effort')
}

// Return the contexts whose handlers can consume the next composer key.
pub fn (composer &ChatComposer) keymap_contexts() tui_keymap.KeymapContextSet {
	if composer.draft.textarea.vim_query_active() {
		return tui_keymap.KeymapContextSet.new(.editor)
	}
	if composer.history_search != none {
		return tui_keymap.KeymapContextSet.new(.composer)
	}
	if !composer.draft.input_enabled || composer.popups.is_active() {
		return tui_keymap.KeymapContextSet{}
	}
	return composer.draft.textarea.keymap_contexts().with(.composer)
}

pub fn (mut composer ChatComposer) set_collaboration_mode_indicator(indicator ?CollaborationModeIndicator) {
	composer.footer.collaboration_mode_indicator = indicator
}

pub fn (mut composer ChatComposer) set_goal_status_indicator(indicator ?GoalStatusIndicator) {
	composer.footer.goal_status_indicator = indicator
}

pub fn (mut composer ChatComposer) set_ide_context_active(active bool) {
	composer.footer.ide_context_active = active
}

pub fn (mut composer ChatComposer) set_personality_command_enabled(enabled bool) {
	composer.personality_command_enabled = enabled
}

pub fn (mut composer ChatComposer) set_side_conversation_active(active bool) {
	composer.side_conversation_active = active
}

// Compatibility shim for tests that still toggle the removed steer mode flag.
pub fn (mut composer ChatComposer) set_steer_enabled(_enabled bool) {}

// Centralized feature gating keeps config checks out of call sites.
fn (composer &ChatComposer) popups_enabled() bool {
	return composer.config.popups_enabled
}

fn (composer &ChatComposer) slash_commands_enabled() bool {
	return composer.config.slash_commands_enabled
}

fn (composer &ChatComposer) image_paste_enabled() bool {
	return composer.config.image_paste_enabled
}

pub fn (mut composer ChatComposer) set_windows_degraded_sandbox_active(enabled bool) {
	composer.windows_degraded_sandbox_active = enabled
}

fn (composer &ChatComposer) layout_areas(area rat_layout.Rect) []rat_layout.Rect {
	return composer.layout_areas_with_textarea_right_reserve(area, /* textarea_right_reserve */
		0)
}

fn (composer &ChatComposer) layout_areas_with_textarea_right_reserve(area rat_layout.Rect,
	textarea_right_reserve u16) []rat_layout.Rect {
	props := composer.footer_props()
	footer_hint_height := composer.custom_footer_height() or { footer_height(&props) }
	footer_total_height := footer_hint_height + ChatComposer.footer_spacing(footer_hint_height)
	requested_popup := composer.popups.active.required_height(area.width, footer_total_height)
	// Ratatui's `[Constraint::Min(3), Constraint::Max(requested)]` gives the flexible composer all
	// spare height. Until the caller supplies the full desired height, the popup therefore retains
	// only its single visible row instead of shrinking the composer to exactly three rows.
	popup_height := if requested_popup == 0 || area.height == 0 {
		u16(0)
	} else if area.height >= requested_popup + 3 {
		requested_popup
	} else {
		u16(1)
	}
	composer_height := area.height - popup_height
	composer_rect := rat_layout.Rect{
		x:      area.x
		y:      area.y
		width:  area.width
		height: composer_height
	}
	popup_rect := rat_layout.Rect{
		x:      area.x
		y:      area.y + composer_height
		width:  area.width
		height: popup_height
	}
	inset_width := if composer_rect.width > live_prefix_cols + /* right */
	1 + textarea_right_reserve {
		composer_rect.width - live_prefix_cols - /* right */
		1 - textarea_right_reserve
	} else {
		u16(0)
	}
	inset_height := if composer_rect.height > /* top */
	1 + /* bottom */
	1 {
		composer_rect.height - /* top */
		1 - /* bottom */
		1
	} else {
		u16(0)
	}
	available_remote_height := if inset_height > 0 { inset_height - 1 } else { u16(0) }
	remote_height := min_u16(u16(composer.attachments.remote_urls.len), available_remote_height)
	remote_separator := if remote_height > 0 { u16(1) } else { u16(0) }
	textarea_y := composer_rect.y + 1 + remote_height + remote_separator
	textarea_height := inset_height - remote_height - remote_separator
	return [composer_rect,
		rat_layout.Rect{ x: composer_rect.x + 2, y: composer_rect.y + 1, width: inset_width, height: remote_height },
		rat_layout.Rect{
			x:      composer_rect.x + 2
			y:      textarea_y
			width:  inset_width
			height: textarea_height
		}, popup_rect]
}

fn ChatComposer.footer_spacing(footer_hint_height u16) u16 {
	return if footer_hint_height == 0 { u16(0) } else { footer_spacing_height }
}

pub fn (composer &ChatComposer) cursor_pos(area rat_layout.Rect) ?CursorPosition {
	return composer.cursor_pos_with_textarea_right_reserve(area, /* textarea_right_reserve */
		0)
}

pub fn (composer &ChatComposer) cursor_style(_area rat_layout.Rect) terminal_cursor.CursorStyle {
	return if composer.draft.textarea.uses_vim_insert_cursor() {
		.steady_bar
	} else {
		.default_user_shape
	}
}

pub fn (composer &ChatComposer) cursor_pos_with_textarea_right_reserve(area rat_layout.Rect,
	textarea_right_reserve u16) ?CursorPosition {
	if !composer.draft.input_enabled || composer.attachments.selected_remote_image_index != none {
		return none
	}
	if position := composer.vim_search_cursor_pos(area) {
		return position
	}
	if position := composer.history_search_cursor_pos(area) {
		return position
	}
	areas := composer.layout_areas_with_textarea_right_reserve(area, textarea_right_reserve)
	return composer.draft.textarea.cursor_pos_with_state(areas[2], composer.draft.textarea_state)
}

// Returns true if the composer currently contains no user-entered input.
pub fn (composer &ChatComposer) is_empty() bool {
	return composer.draft.textarea.is_empty() && !composer.draft.is_bash_mode && composer.attachments.is_empty()
}

// Record local persistent-history metadata so the composer can navigate
// cross-session history.
pub fn (mut composer ChatComposer) set_history_metadata(thread_id protocol_thread_id.ThreadId, log_id u64,
	entry_count int) {
	composer.history.set_metadata(thread_id, log_id, entry_count)
}

// Integrate an asynchronous response to an on-demand history lookup.
//
// If the entry is present and the offset still matches the active history cursor, the
// composer rehydrates the entry immediately. This path intentionally routes through
// [`Self::apply_history_entry`] so cursor placement remains aligned with keyboard history
// recall semantics.
pub fn (mut composer ChatComposer) on_history_entry_response(log_id u64, offset int, entry ?string) bool {
	response := composer.history.on_entry_response(log_id, offset, entry, &composer.app_event_tx)
	match response.kind {
		.found {
			// Persistent ↑/↓ history is text-only (backwards-compatible and avoids persisting
			// attachments), but local in-session ↑/↓ history can rehydrate elements and image paths.
			composer.apply_history_entry(response.entry)
			return true
		}
		.search {
			composer.apply_history_search_result(response.search)
			return true
		}
		.ignored {}
	}
	return false
}

pub fn (mut composer ChatComposer) on_history_batch_response(log_id u64, cursor HistoryBatchCursor,
	entries []app_event.HistoryBatchEntryResponse, next_older_cursor ?HistoryBatchCursor) bool {
	result := composer.history.on_batch_response(log_id, cursor, entries, next_older_cursor, &composer.app_event_tx)
	return composer.apply_history_batch_result(result)
}

// Applies a failed batch lookup without conflating it with history exhaustion.
//
// The history state machine either schedules a bounded retry, preserves an existing match, or
// returns the search UI to its idle draft when no match has been selected yet.
pub fn (mut composer ChatComposer) on_history_batch_error(log_id u64, cursor HistoryBatchCursor) bool {
	result := composer.history.on_batch_error(log_id, cursor, &composer.app_event_tx)
	return composer.apply_history_batch_result(result)
}

fn (mut composer ChatComposer) apply_history_batch_result(result ?HistorySearchResult) bool {
	if value := result {
		composer.apply_history_search_result(value)
		return true
	}
	return false
}

pub fn (mut composer ChatComposer) record_replayed_user_message_history(entry HistoryEntry) {
	composer.history.record_replayed_submission(entry)
}

// Integrate pasted text into the composer.
//
// Acts as the only place where paste text is integrated, both for:
//
// - Real/explicit paste events surfaced by the terminal, and
// - Non-bracketed "paste bursts" that [`PasteBurst`](super::paste_burst::PasteBurst) buffers
//   and later flushes here.
//
// Behavior:
//
// - If the paste is larger than `LARGE_PASTE_CHAR_THRESHOLD` chars, inserts a placeholder
//   element (expanded on submit) and stores the full text in `pending_pastes`.
// - Otherwise, if the paste looks like an image path, attaches the image and inserts a
//   trailing space so the user can keep typing naturally.
// - Otherwise, inserts the pasted text directly into the textarea.
//
// In all cases, clears any paste-burst Enter suppression state so a real paste cannot affect
// the next user Enter key, then syncs popup state.
pub fn (mut composer ChatComposer) handle_paste(pasted string) bool {
	mut normalized := pasted.replace('\r\n', '\n').replace('\r', '\n')
	normalized = history_cell.sanitize_user_text(normalized)
	if composer.draft.textarea.insert_into_vim_query(&normalized) {
		return true
	}
	started_vim_edit := composer.begin_direct_vim_edit()
	char_count := normalized.runes().len
	if char_count > large_paste_char_threshold {
		placeholder := composer.next_large_paste_placeholder(char_count)
		composer.draft.textarea.insert_element(&placeholder)
		composer.draft.pending_pastes << PendingPaste{ placeholder: placeholder, actual: normalized }
	} else if char_count > 1 && composer.image_paste_enabled() && composer.handle_paste_image_path(&normalized) {
		space := ' '
		composer.draft.textarea.insert_str(&space)
	} else {
		composer.insert_str(&normalized)
	}
	composer.draft.paste_burst.clear_after_explicit_paste()
	composer.sync_popups()
	if started_vim_edit {
		composer.finish_vim_edit()
	}
	return true
}

pub fn (mut composer ChatComposer) handle_paste_image_path(pasted &string) bool {
	path := clipboard_paste.normalize_pasted_path(pasted) or { return false }
	width, height := image.image_dimensions(&path) or {
		message := 'ERR: ${err}'
		tracing.trace(&message)
		return false
	}
	// normalize_pasted_path already handles Windows → WSL path conversion,
	// so we can directly try to read the image dimensions.
	message := 'OK: ${*pasted}'
	tracing.info(&message)
	dimensions_message := 'image dimensions=${width}x${height}'
	tracing.debug(&dimensions_message)
	format := clipboard_paste.pasted_image_format(&path)
	format_message := 'attached image format=${format.label()}'
	tracing.debug(&format_message)
	composer.attach_image(path)
	return true
}

// Enable or disable paste-burst handling.
//
// `disable_paste_burst` is an escape hatch for terminals/platforms where the burst heuristic
// is unwanted or has already been handled elsewhere.
//
// When transitioning from enabled → disabled, we "defuse" any in-flight burst state so it
// cannot affect subsequent normal typing:
//
// - First, flush any held/buffered text immediately via
//   [`PasteBurst::flush_before_modified_input`], and feed it through `handle_paste(String)`.
//   This preserves user input and routes it through the same integration path as explicit
//   pastes (large-paste placeholders, image-path detection, and popup sync).
// - Then clear the burst timing and Enter-suppression window via
//   [`PasteBurst::clear_after_explicit_paste`].
//
// We intentionally do not use `clear_window_after_non_char()` here: it clears timing state
// without emitting any buffered text, which can leave a non-empty buffer unable to flush
// later (because `flush_if_due()` relies on `last_plain_char_time` to time out).
pub fn (mut composer ChatComposer) set_disable_paste_burst(disabled bool) {
	was_disabled := composer.draft.disable_paste_burst
	composer.draft.disable_paste_burst = disabled
	if disabled && !was_disabled {
		if pasted := composer.draft.paste_burst.flush_before_modified_input() {
			composer.handle_paste(pasted)
		}
		composer.draft.paste_burst.clear_after_explicit_paste()
	}
}

// Replace the composer content with text from an external editor.
// Clears pending paste placeholders and keeps only attachments whose
// placeholder labels still appear in the new text. Image placeholders
// are renumbered to `[Image #M+1]..[Image #N]` (where `M` is the number of
// remote images). Cursor is placed at the end after rebuilding elements.
pub fn (mut composer ChatComposer) apply_external_edit(text string) {
	composer.vim_history = VimHistory{}
	composer.draft.pending_pastes.clear()
	imported, _ := composer.imported_text_for_textarea(text, [])
	mut kept := []LocalImageAttachment{}
	// Count placeholder occurrences in the new text.
	mut placeholder_counts := map[string]int{}
	for image in composer.attachments.local_images {
		if image.placeholder !in placeholder_counts {
			placeholder_counts[image.placeholder] = count_substring_occurrences(&imported, &image.placeholder)
		}
		if placeholder_counts[image.placeholder] > 0 {
			placeholder_counts[image.placeholder]--
			kept << image
		}
	}
	// Keep attachments only while we have matching occurrences left.
	composer.attachments.local_images = kept
	// Import literally so placeholders remain atomic and Replace recovery starts empty.
	composer.draft.textarea.set_text_clearing_elements(&imported)
	mut remaining := map[string]int{}
	for image in composer.attachments.local_images {
		remaining[image.placeholder]++
	}
	mut occurrences := []TextOccurrence{}
	for placeholder, _ in remaining {
		for start in substring_occurrences(&imported, &placeholder) {
			occurrences << TextOccurrence{ start: start, text: placeholder.clone() }
		}
	}
	occurrences.sort(a.start < b.start)
	for occurrence in occurrences {
		if remaining[occurrence.text] > 0 {
			composer.draft.textarea.add_element_range(occurrence.start, occurrence.start + occurrence.text.len)
			remaining[occurrence.text]--
		}
	}
	// Keep local image placeholders normalized in attachment order after the
	// remote-image prefix.
	composer.attachments.relabel_local_images(mut composer.draft.textarea)
	composer.draft.textarea.set_cursor(composer.draft.textarea.text().len)
	composer.sync_popups()
}

// Enable or disable Vim editing for the composer textarea.
//
// The composer flushes buffered typing and clears paste-burst state when the mode
// changes because Vim normal mode treats rapid character sequences as
// commands, not as candidate literal paste text. It also resets transient
// footer mode so the visible hints match the new editing surface.
pub fn (mut composer ChatComposer) set_vim_enabled(enabled bool) {
	if pasted := composer.draft.paste_burst.flush_before_modified_input() {
		composer.handle_paste(pasted)
	}
	composer.draft.textarea.enable_vim_search()
	composer.draft.textarea.set_vim_enabled(enabled)
	composer.vim_history = VimHistory{}
	composer.draft.paste_burst.clear_after_explicit_paste()
	composer.footer.mode = composer.reset_footer_mode_after_activity()
}

// Enable Vim while keeping already-active text entry in insert mode.
pub fn (mut composer ChatComposer) enable_vim_in_insert_mode() {
	composer.set_vim_enabled( /* enabled */
	true)
	composer.resume_text_entry()
}

// Resume text entry after a parent view takes focus, preserving Vim undo history.
pub fn (mut composer ChatComposer) resume_text_entry() {
	composer.draft.textarea.enter_vim_insert_mode()
}

// Restore draft history transferred from the startup composer.
pub fn (mut composer ChatComposer) restore_startup_local_history(startup []HistoryEntry) {
	for entry in startup {
		composer.history.record_local_submission(entry)
	}
}

// Toggle Vim editing and return the new enabled state.
//
// This is the app-level command target for the configurable Vim toggle
// keybinding; callers should use the returned value for status messages
// instead of rereading state after additional composer mutations.
pub fn (mut composer ChatComposer) toggle_vim_enabled() bool {
	enabled := !composer.draft.textarea.is_vim_enabled()
	composer.set_vim_enabled(enabled)
	return enabled
}

// Return whether Vim editing is enabled.
pub fn (composer &ChatComposer) is_vim_enabled() bool {
	return composer.draft.textarea.is_vim_enabled()
}

// Return whether Escape should be routed to the textarea before popups.
//
// Vim insert mode owns Escape as a transition back to normal mode. The app
// event layer asks this before running generic Escape behavior so the same
// key does not both leave insert mode and dismiss unrelated UI.
pub fn (composer &ChatComposer) should_handle_vim_insert_escape(key_event terminal_event.KeyEvent) bool {
	return composer.draft.textarea.is_vim_enabled()
		&& composer.draft.textarea.vim_mode in ['insert', 'replace']
		&& key_event.code.kind == .escape && key_event.kind in [.press, .repeat]
}

pub fn (composer &ChatComposer) vim_mode_indicator_span() ?rat_text.Span {
	if !composer.draft.textarea.is_vim_enabled() {
		return none
	}
	mode := composer.draft.textarea.vim_mode
	color := match mode {
		'insert' { rat_style.Color{ kind: .green } }
		'replace' { rat_style.Color{ kind: .cyan } }
		else { rat_style.Color{ kind: .magenta } }
	}
	return rat_text.Span{
		text:  'Vim: ${mode.title()}'
		style: rat_style.Style.default().fg(color)
	}
}

fn (composer &ChatComposer) mode_indicator_line(show_cycle_hint bool) ?rat_text.Line {
	mut spans := []rat_text.Span{}
	if vim_span := composer.vim_mode_indicator_span() {
		spans << vim_span
	}
	if indicators := status_line_right_indicator_line(composer.footer.collaboration_mode_indicator, composer.footer.goal_status_indicator, composer.footer.ide_context_active, show_cycle_hint) {
		if spans.len > 0 {
			spans << rat_text.Span{ text: ' | ', style: rat_style.Style.default().dim() }
		}
		spans << indicators.spans
	}
	if spans.len > 0 {
		return rat_text.Line{ spans: spans }
	}
	return none
}

fn (composer &ChatComposer) right_footer_line_with_context() rat_text.Line {
	mut line := if composer.footer.context_window_pending {
		rat_text.Line{}
	} else {
		context_window_line(composer.footer.context_window_percent, composer.footer.context_window_used_tokens)
	}
	if span := composer.vim_mode_indicator_span() {
		mut spans := line.spans.clone()
		spans << rat_text.Span{ text: ' | ', style: rat_style.Style.default().dim() }
		spans << span
		line = rat_text.Line{ spans: spans }
	}
	return line
}

pub fn (composer &ChatComposer) current_text_with_pending() string {
	text := composer.current_text()
	if composer.draft.pending_pastes.len == 0 {
		return text
	}
	mut elements := composer.current_text_elements()
	expanded, _ := ChatComposer.expand_pending_pastes(&text, mut elements, &composer.draft.pending_pastes)
	return expanded
}

// Returns whether the composer currently accepts interactive draft edits.
pub fn (composer &ChatComposer) input_enabled() bool {
	return composer.draft.input_enabled
}

pub fn (composer &ChatComposer) pending_pastes() []PendingPaste {
	return clone_pending_pastes(&composer.draft.pending_pastes)
}

pub fn (mut composer ChatComposer) set_pending_pastes(pending []PendingPaste) {
	text := composer.current_text()
	composer.draft.pending_pastes = pending.filter(text.contains(it.placeholder))
}

// Override the footer hint items displayed beneath the composer. Passing
// `None` restores the default shortcut footer.
pub fn (mut composer ChatComposer) set_footer_hint_override(items ?[][]string) {
	composer.footer.hint_override = items
}

pub fn (mut composer ChatComposer) set_remote_image_urls(urls []string) {
	composer.attachments.set_remote_image_urls(urls, mut composer.draft.textarea)
	composer.sync_popups()
}

pub fn (composer &ChatComposer) remote_image_urls() []string {
	return composer.attachments.remote_image_urls()
}

pub fn (mut composer ChatComposer) take_remote_image_urls() []string {
	urls := composer.attachments.take_remote_image_urls(mut composer.draft.textarea)
	composer.sync_popups()
	return urls
}

// Replace the entire composer content with `text` and reset cursor.
//
// This is the "fresh draft" path: it clears pending paste payloads and
// mention link targets. Callers restoring a previously submitted draft
// that must keep sigiled mention target resolution should use
// [`Self::set_text_content_with_mention_bindings`] instead.
pub fn (mut composer ChatComposer) set_text_content(text string, elements []user_input.TextElement,
	local_image_paths []string) {
	composer.set_text_content_with_mention_bindings(text, elements, local_image_paths, [])
}

// Restore draft content; clear pending input and undo history. The cursor starts at zero.
pub fn (mut composer ChatComposer) set_text_content_with_mention_bindings(text string,
	elements []user_input.TextElement, local_image_paths []string, bindings []MentionBinding) {
	// Clear any existing content, placeholders, and attachments first.
	composer.footer.flash = none
	composer.vim_history = VimHistory{}
	empty := ''
	composer.draft.textarea.set_text_clearing_elements(&empty)
	composer.draft.is_bash_mode = false
	composer.draft.pending_pastes.clear()
	composer.draft.mention_bindings.clear()
	imported, shifted := composer.imported_text_for_textarea(text, elements)
	composer.draft.textarea.set_text_with_elements(&imported, &shifted)
	composer.attachments.reset_local_images(local_image_paths, mut composer.draft.textarea)
	composer.bind_mentions_from_snapshot(bindings)
	composer.draft.textarea.set_cursor( /* pos */
	0)
	composer.sync_popups()
}

pub fn (composer &ChatComposer) current_cursor() int {
	return composer.draft.textarea.cursor() + if composer.draft.is_bash_mode { 1 } else { 0 }
}

pub fn (composer &ChatComposer) cursor() int {
	return composer.current_cursor()
}

fn (composer &ChatComposer) history_navigation_cursor() int {
	if composer.draft.is_bash_mode && composer.draft.textarea.cursor() == 0 {
		return 0
	}
	if composer.draft.textarea.is_vim_normal_mode() && composer.draft.textarea.text().len > 0
		&& composer.draft.textarea.cursor() == composer.draft.textarea.vim_normal_end_cursor() {
		// Normal mode cannot place its visible cursor after the last character. Treat that position
		// as logical end-of-input so shell-style history navigation remains available.
		return composer.current_text().len
	}
	return composer.current_cursor()
}

pub fn (mut composer ChatComposer) set_current_cursor(cursor int) {
	visible := if composer.draft.is_bash_mode { max_int(cursor - 1, 0) } else { cursor }
	composer.draft.textarea.set_cursor(visible)
}

fn (composer &ChatComposer) current_text_elements() []user_input.TextElement {
	shift_amount := if composer.draft.is_bash_mode { 1 } else { 0 }
	mut elements := []user_input.TextElement{}
	for element in composer.draft.textarea.text_elements() {
		if shifted := ChatComposer.shift_text_element(element, shift_amount) {
			elements << shifted
		}
	}
	return elements
}

fn ChatComposer.shift_text_element(element user_input.TextElement, shift_amount int) ?user_input.TextElement {
	start := element.byte_range.start + shift_amount
	end := element.byte_range.end + shift_amount
	if start < 0 || start >= end {
		return none
	}
	return user_input.TextElement.new(user_input.ByteRange{ start: start, end: end }, element.not_hidden_placeholder_for_conversion_only())
}

pub fn (composer &ChatComposer) snapshot_draft() ComposerDraft {
	return ComposerDraft{
		text:              composer.current_text()
		text_elements:     composer.current_text_elements()
		local_image_paths: composer.attachments.local_image_paths()
		remote_image_urls: composer.attachments.remote_image_urls()
		mention_bindings:  composer.snapshot_mention_bindings()
		pending_pastes:    clone_pending_pastes(&composer.draft.pending_pastes)
		cursor:            composer.current_cursor()
	}
}

pub fn (mut composer ChatComposer) restore_draft(draft ComposerDraft) {
	composer.set_remote_image_urls(draft.remote_image_urls)
	composer.set_text_content_with_mention_bindings(draft.text, draft.text_elements, draft.local_image_paths, draft.mention_bindings)
	composer.set_pending_pastes(draft.pending_pastes)
	composer.set_current_cursor(draft.cursor)
	composer.sync_popups()
}

// Update the placeholder text without changing input enablement.
pub fn (mut composer ChatComposer) set_placeholder_text(placeholder string) {
	composer.placeholder_text = placeholder
}

pub fn (mut composer ChatComposer) set_parent_owned_thread() {
	composer.blocks_direct_input = true
	composer.placeholder_text = 'Viewing sub-agent — direct input is disabled'
}

// Move the cursor to the end of the current text buffer.
pub fn (mut composer ChatComposer) move_cursor_to_end() {
	composer.draft.textarea.set_cursor(composer.draft.textarea.text().len)
	composer.sync_popups()
}

fn (mut composer ChatComposer) move_cursor_to_history_entry_end() {
	cursor := if composer.draft.textarea.is_vim_normal_mode() {
		composer.draft.textarea.vim_normal_end_cursor()
	} else {
		composer.draft.textarea.text().len
	}
	composer.draft.textarea.set_cursor(cursor)
	composer.sync_popups()
}

// Convert canonical composer text into the textarea's internal representation.
//
// Shell mode stores the leading `!` as prompt state instead of editable text,
// so full-buffer imports must absorb that prefix before rebuilding the textarea.
fn (mut composer ChatComposer) imported_text_for_textarea(text string,
	elements []user_input.TextElement) (string, []user_input.TextElement) {
	if composer.config.shell_commands_enabled && text.starts_with('!') {
		composer.draft.is_bash_mode = true
		mut shifted := []user_input.TextElement{}
		for element in elements {
			if value := ChatComposer.shift_text_element(element, /* shift */
				-1) {
				shifted << value
			}
		}
		return text[1..].clone(), shifted
	}
	composer.draft.is_bash_mode = false
	return text, elements
}

// Flush buffered typing before clearing so cancellation preserves the complete draft in history.
pub fn (mut composer ChatComposer) clear_for_ctrl_c() ?string {
	if pasted := composer.draft.paste_burst.flush_before_modified_input() {
		composer.handle_paste(pasted)
	}
	if composer.is_empty() {
		return none
	}
	previous := composer.current_text()
	entry := HistoryEntry{
		text:              previous.clone()
		text_elements:     composer.current_text_elements()
		local_image_paths: composer.attachments.local_image_paths()
		remote_image_urls: composer.attachments.remote_image_urls()
		mention_bindings:  composer.snapshot_mention_bindings()
		pending_pastes:    clone_pending_pastes(&composer.draft.pending_pastes)
	}
	composer.draft.pending_pastes.clear()
	composer.set_text_content('', [], [])
	composer.attachments.clear_remote_image_urls()
	composer.history.reset_navigation()
	composer.history.record_local_submission(entry)
	return previous
}

// Get the current composer text.
// V returns an owned string because V has no borrowed string-slice return equivalent.
pub fn (composer &ChatComposer) current_text() string {
	text := composer.draft.textarea.text()
	return if composer.draft.is_bash_mode { '!${text}' } else { text }
}

// Recall content at its history boundary, preserving pending pastes and omitting images
// in plain-text editors.
fn (mut composer ChatComposer) apply_history_entry(entry HistoryEntry) {
	composer.set_remote_image_urls(entry.remote_image_urls)
	composer.set_text_content_with_mention_bindings(entry.text, entry.text_elements, entry.local_image_paths, entry.mention_bindings)
	composer.set_pending_pastes(entry.pending_pastes)
	if !composer.config.image_paste_enabled {
		// Plain-text composers discard both restored image state and its atomic placeholder spans.
		// Removing the spans before clearing attachment metadata keeps the visible draft consistent.
		for image in composer.attachments.local_images {
			for element in composer.draft.textarea.text_elements() {
				visible_text := composer.draft.textarea.text()
				placeholder := element.placeholder_text(&visible_text) or { continue }
				if placeholder == image.placeholder {
					empty := ''
					composer.draft.textarea.replace_range(element.byte_range.start, element.byte_range.end, &empty)
					break
				}
			}
		}
		composer.attachments = AttachmentState{}
	}
	composer.history.record_recalled_text(composer.current_text())
	composer.move_cursor_to_history_entry_end()
}

pub fn (composer &ChatComposer) text_elements() []user_input.TextElement {
	return composer.current_text_elements()
}

pub fn (composer &ChatComposer) draft_snapshot() ComposerDraftSnapshot {
	return ComposerDraftSnapshot{
		text:                  composer.current_text()
		cursor:                composer.current_cursor()
		text_elements:         composer.text_elements()
		local_images:          composer.local_images()
		remote_image_urls:     composer.remote_image_urls()
		mention_bindings:      composer.mention_bindings()
		pending_pastes:        composer.pending_pastes()
		startup_local_history: composer.history.startup_local_history()
	}
}

pub fn (composer &ChatComposer) local_image_paths() []string {
	return composer.attachments.local_image_paths()
}

pub fn (composer &ChatComposer) status_line_text() ?string {
	if line := composer.footer.status_line_value {
		return line.spans.map(it.text).join('')
	}
	return none
}

pub fn (composer &ChatComposer) local_images() []LocalImageAttachment {
	return composer.attachments.local_images_copy()
}

pub fn (composer &ChatComposer) mention_bindings() []MentionBinding {
	return composer.snapshot_mention_bindings()
}

pub fn (mut composer ChatComposer) take_recent_submission_mention_bindings() []MentionBinding {
	bindings := composer.draft.recent_submission_mention_bindings.clone()
	composer.draft.recent_submission_mention_bindings.clear()
	return bindings
}

// Commit the staged slash-command draft to local Up-arrow recall.
//
// Call this after command dispatch. Calling it more than once is harmless because the pending
// slot is consumed on the first call.
pub fn (mut composer ChatComposer) record_pending_slash_command_history() {
	if entry := composer.pending_slash_command_history {
		composer.history.record_local_submission(entry)
		composer.pending_slash_command_history = none
	}
}

// Insert an attachment placeholder and track it for the next submission.
pub fn (mut composer ChatComposer) attach_image(path string) {
	started := composer.begin_direct_vim_edit()
	composer.attachments.attach_image(mut composer.draft.textarea, path)
	if started {
		composer.finish_vim_edit()
	}
}

pub fn (mut composer ChatComposer) take_recent_submission_images() []string {
	return composer.attachments.take_recent_submission_images()
}

pub fn (mut composer ChatComposer) take_recent_submission_images_with_placeholders() []LocalImageAttachment {
	return composer.attachments.take_recent_submission_images_with_placeholders()
}

// Flushes any due paste-burst state.
//
// Call this from a UI tick to turn paste-burst transient state into explicit textarea edits:
//
// - If a burst times out, flush it via `handle_paste(String)`.
// - If only the first ASCII char was held (flicker suppression) and no burst followed, emit it
//   as normal typed input.
//
// This also allows a single "held" ASCII char to render even when it turns out not to be part
// of a paste burst.
pub fn (mut composer ChatComposer) flush_paste_burst_if_due() bool {
	return composer.handle_paste_burst_flush(time.now().unix_milli())
}

// Returns whether the composer is currently in any paste-burst related transient state.
//
// This includes actively buffering, having a non-empty burst buffer, or holding the first
// ASCII char for flicker suppression.
pub fn (composer &ChatComposer) is_in_paste_burst() bool {
	return composer.draft.paste_burst.is_active()
}

// Returns a delay that reliably exceeds the paste-burst timing threshold.
//
// Use this in tests to avoid boundary flakiness around the `PasteBurst` timeout.
pub fn ChatComposer.recommended_paste_flush_delay() i64 {
	return PasteBurst.recommended_flush_delay()
}

// Integrate results from an asynchronous file search.
pub fn (mut composer ChatComposer) on_file_search_result(query string, matches []codex_file_search.FileMatch) {
	// Only apply if user is still editing a token starting with `query`.
	mut current_option := ?string(none)
	if composer.mentions_v2_enabled {
		current_option = composer.current_mentions_v2_token()
	} else {
		current_option = ChatComposer.current_at_token(&composer.draft.textarea)
	}
	current := current_option or { return }
	if !current.starts_with(query) {
		return
	}
	match composer.popups.active.kind {
		.file { composer.popups.active.file.set_matches(&query, matches) }
		.mention_v2 { composer.popups.active.mention_v2.set_file_matches(&query, matches) }
		else {}
	}
}

// Show the transient "press again to quit" hint for `key`.
//
// The owner (`BottomPane`/`ChatWidget`) is responsible for scheduling a
// redraw after [`super::QUIT_SHORTCUT_TIMEOUT`] so the hint can disappear
// even when the UI is otherwise idle.
pub fn (mut composer ChatComposer) show_quit_shortcut_hint(key key_hint.KeyBinding, has_focus bool) {
	composer.footer.quit_shortcut_expires_at = time.now().unix_milli() + quit_shortcut_timeout_ms
	composer.footer.quit_shortcut_key = key
	composer.footer.mode = .quit_shortcut_reminder
	composer.set_has_focus(has_focus)
}

// Clear the "press again to quit" hint immediately.
pub fn (mut composer ChatComposer) clear_quit_shortcut_hint(has_focus bool) {
	composer.footer.quit_shortcut_expires_at = 0
	composer.footer.mode = composer.reset_footer_mode_after_activity()
	composer.set_has_focus(has_focus)
}

// Whether the quit shortcut hint should currently be shown.
//
// This is time-based rather than event-based: it may become false without
// any additional user input, so the UI schedules a redraw when the hint
// expires.
pub fn (composer &ChatComposer) quit_shortcut_hint_visible() bool {
	return composer.footer.quit_shortcut_expires_at > time.now().unix_milli()
}

fn (composer &ChatComposer) next_large_paste_placeholder(char_count int) string {
	base := '[Pasted Content ${char_count} chars]'
	prefix := '${base} #'
	mut max_suffix := 0
	for pending in composer.draft.pending_pastes {
		if pending.placeholder == base {
			max_suffix = max_int(max_suffix, 1)
		} else if pending.placeholder.starts_with(prefix) {
			value := pending.placeholder[prefix.len..].int()
			max_suffix = max_int(max_suffix, value)
		}
	}
	return if max_suffix == 0 { base } else { '${base} #${max_suffix + 1}' }
}

pub fn (mut composer ChatComposer) insert_str(text &string) {
	started := composer.begin_direct_vim_edit()
	composer.draft.textarea.insert_str(text)
	composer.sync_bash_mode_from_text()
	composer.sync_popups()
	if started {
		composer.finish_vim_edit()
	}
}

// Handle a key event coming from the main UI.
pub fn (mut composer ChatComposer) handle_key_event(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if !composer.draft.input_enabled || key_event.kind == .release {
		return input_result_none(), false
	}
	if composer.history_search == none && !composer.popups.is_active()
		&& composer.draft.textarea.wants_vim_search_key(key_event) {
		return composer.handle_input_basic(key_event)
	}
	if composer.history_search != none {
		return composer.handle_history_search_key(key_event)
	}
	if composer.handle_vim_history_key(key_event) {
		return input_result_none(), true
	}
	if key_hint.bindings_are_pressed(&composer.history_search_previous_keys, key_event) {
		return composer.begin_history_search()
	}
	mut result := input_result_none()
	mut redraw := false
	match composer.popups.active.kind {
		.command {
			result, redraw = composer.handle_key_event_with_slash_popup(key_event)
		}
		.file {
			result, redraw = composer.handle_key_event_with_file_popup(key_event)
		}
		.skill {
			result, redraw = composer.handle_key_event_with_skill_popup(key_event)
		}
		.mention_v2 {
			result, redraw = composer.handle_key_event_with_mentions_v2_popup(key_event)
		}
		.none {
			result, redraw = composer.handle_key_event_without_popup(key_event)
		}
	}
	composer.reset_vim_mode_after_successful_dispatch(&result)
	// Update (or hide/show) popup after processing the key.
	composer.sync_popups()
	return result, redraw
}

// Whether a popup or query owns input.
pub fn (composer &ChatComposer) popup_active() bool {
	return composer.history_search != none || composer.draft.textarea.vim_query_active()
		|| composer.popups.is_active()
}

fn ChatComposer.clamp_to_char_boundary(text &string, position int) int {
	mut pos := clamp_int(position, 0, text.len)
	for pos > 0 && pos < text.len && is_utf8_continuation((*text)[pos]) {
		pos--
	}
	return pos
}

// Handle non-ASCII character input (often IME) while still supporting paste-burst detection.
//
// This handler exists because non-ASCII input often comes from IMEs, where characters can
// legitimately arrive in short bursts that should **not** be treated as paste.
//
// The key differences from the ASCII path:
//
// - We never hold the first character (`PasteBurst::on_plain_char_no_hold`), because holding a
//   non-ASCII char can feel like dropped input.
// - If a burst is detected, we may need to retroactively remove already-inserted text before
//   the cursor and move it into the paste buffer (see `PasteBurst::decide_begin_buffer`).
//
// Because this path mixes "insert immediately" with "maybe retro-grab later", it must clamp
// the cursor to a UTF-8 char boundary before slicing `textarea.text()`.
fn (mut composer ChatComposer) handle_non_ascii_char(input terminal_event.KeyEvent,
	now_ms i64) (InputResult, bool) {
	if composer.draft.disable_paste_burst {
		// When burst detection is disabled, treat IME/non-ASCII input as normal typing.
		// In particular, do not retro-capture or buffer already-inserted prefix text.
		composer.draft.textarea.input(input)
		composer.retain_present_pending_pastes()
		return input_result_none(), true
	}
	if composer.draft.paste_burst.try_append_char_if_active(input.code.ch, now_ms) {
		return input_result_none(), true
	}
	// Non-ASCII input often comes from IMEs and can arrive in quick bursts.
	// We do not want to hold the first char (flicker suppression) on this path, but we
	// still want to detect paste-like bursts. Before applying any non-ASCII input, flush
	// any existing burst buffer (including a pending first char from the ASCII path) so
	// we don't carry that transient state forward.
	if pasted := composer.draft.paste_burst.flush_before_modified_input() {
		composer.handle_paste(pasted)
	}
	if decision := composer.draft.paste_burst.on_plain_char_no_hold(now_ms) {
		match decision.kind {
			.buffer_append {
				composer.draft.paste_burst.append_char_to_buffer(input.code.ch, now_ms)
				return input_result_none(), true
			}
			.begin_buffer {
				// For non-ASCII we inserted prior chars immediately, so if this turns out
				// to be paste-like we need to retroactively grab & remove the already-
				// inserted prefix from the textarea before buffering the burst.
				cursor := composer.draft.textarea.cursor()
				text := composer.draft.textarea.text()
				safe_cursor := ChatComposer.clamp_to_char_boundary(&text, cursor)
				before := text[..safe_cursor]
				if grab := composer.draft.paste_burst.decide_begin_buffer(now_ms, &before, int(decision.retro_chars)) {
					if grab.grabbed.len == 0
						|| composer.draft.textarea.retract_paste_burst(grab.start_byte) {
						composer.draft.paste_burst.append_char_to_buffer(input.code.ch, now_ms)
						return input_result_none(), true
					}
					composer.draft.paste_burst.clear_after_explicit_paste()
				}
				// If decide_begin_buffer opted not to start buffering,
				// fall through to normal insertion below.
			}
			else {
				panic('on_plain_char_no_hold returned unexpected decision')
			}
		}
	}
	if pasted := composer.draft.paste_burst.flush_before_modified_input() {
		composer.handle_paste(pasted)
	}
	composer.draft.textarea.input(input)
	composer.retain_present_pending_pastes()
	return input_result_none(), true
}

// Handle key events when file search popup is visible.
fn (mut composer ChatComposer) handle_key_event_with_file_popup(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if composer.handle_empty_prompt_shortcut(&key_event) {
		return input_result_none(), true
	}
	if key_event.code.kind == .escape {
		next_mode := esc_hint_mode(composer.footer.mode, composer.is_task_running)
		if next_mode != composer.footer.mode {
			composer.footer.mode = next_mode
			return input_result_none(), true
		}
	} else {
		composer.footer.mode = reset_mode_after_activity(composer.footer.mode)
	}
	is_previous := key_event.code.kind == .up
		|| (key_event.code.kind == .char_key && key_event.code.ch == `p`
			&& key_event.modifiers.control)
	is_next := key_event.code.kind == .down
		|| (key_event.code.kind == .char_key && key_event.code.ch == `n`
			&& key_event.modifiers.control)
	if is_previous {
		composer.popups.active.file.move_up()
		return input_result_none(), true
	}
	if is_next {
		composer.popups.active.file.move_down()
		return input_result_none(), true
	}
	match key_event.code.kind {
		.escape {
			if start, end, query := composer.current_editable_at_token_range_with_options(
			/* allow_empty */
			false) {
				composer.popups.dismissed_file_token = DismissedToken.new(&composer.draft.textarea, start, end, query)
			}
			composer.popups.active = ActivePopup{}
			return input_result_none(), true
		}
		.enter, .tab {
			if path := composer.popups.active.file.selected_match() {
				if start, end, _ := composer.current_editable_at_token_range_with_options(
				/* allow_empty */
				false) {
					composer.insert_selected_file_path(start, end, &path)
				}
				composer.popups.active = ActivePopup{}
				return input_result_none(), true
			}
			composer.popups.active = ActivePopup{}
			if key_event.code.kind == .enter {
				return composer.handle_key_event_without_popup(key_event)
			}
			return input_result_none(), true
		}
		else {
			return composer.handle_input_basic(key_event)
		}
	}
}

// Handle key events when the legacy skill mention popup is visible.
fn (mut composer ChatComposer) handle_key_event_with_skill_popup(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if composer.handle_empty_prompt_shortcut(&key_event) {
		return input_result_none(), true
	}
	composer.footer.mode = reset_mode_after_activity(composer.footer.mode)
	is_previous := key_event.code.kind == .up
		|| (key_event.code.kind == .char_key && key_event.code.ch == `p`
			&& key_event.modifiers.control)
	is_next := key_event.code.kind == .down
		|| (key_event.code.kind == .char_key && key_event.code.ch == `n`
			&& key_event.modifiers.control)
	if is_previous {
		composer.popups.active.skill.move_up()
		return input_result_none(), true
	}
	if is_next {
		composer.popups.active.skill.move_down()
		return input_result_none(), true
	}
	if key_event.code.kind == .escape {
		if target := composer.current_mention_target() {
			composer.popups.dismissed_mention_token = DismissedToken.new(&composer.draft.textarea, target.start, target.end, target.query)
		}
		composer.popups.active = ActivePopup{}
		return input_result_none(), true
	}
	if key_event.code.kind in [.enter, .tab] {
		if mention := composer.popups.active.skill.selected_mention() {
			if target := composer.current_mention_target() {
				composer.insert_selected_mention(target.start, target.end, &mention.insert_text, mention.path)
			}
		}
		composer.popups.active = ActivePopup{}
		return input_result_none(), true
	}
	return composer.handle_input_basic(key_event)
}

fn (mut composer ChatComposer) handle_key_event_with_mentions_v2_popup(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if composer.handle_empty_prompt_shortcut(&key_event) {
		return input_result_none(), true
	}
	composer.footer.mode = reset_mode_after_activity(composer.footer.mode)
	can_switch_search_mode := composer.current_editable_at_token() != none
	is_previous := key_event.code.kind == .up
		|| (key_event.code.kind == .char_key && key_event.code.ch == `p`
			&& key_event.modifiers.control)
	is_next := key_event.code.kind == .down
		|| (key_event.code.kind == .char_key && key_event.code.ch == `n`
			&& key_event.modifiers.control)
	if is_previous {
		composer.popups.active.mention_v2.move_up()
		return input_result_none(), true
	}
	if is_next {
		composer.popups.active.mention_v2.move_down()
		return input_result_none(), true
	}
	if key_event.code.kind == .left && !key_event.modifiers.control && !key_event.modifiers.alt
		&& !key_event.modifiers.shift && can_switch_search_mode {
		composer.popups.active.mention_v2.previous_search_mode()
		return input_result_none(), true
	}
	if key_event.code.kind == .right && !key_event.modifiers.control && !key_event.modifiers.alt
		&& !key_event.modifiers.shift && can_switch_search_mode {
		composer.popups.active.mention_v2.next_search_mode()
		return input_result_none(), true
	}
	if key_event.code.kind == .escape {
		if start, end, token := composer.current_editable_at_token_range_with_options(
		/* allow_empty */
		true) {
			composer.popups.dismissed_mention_token = DismissedToken.new(&composer.draft.textarea, start, end, token)
		}
		composer.popups.current_file_query = OwnedStringSlot{}
		composer.popups.active = ActivePopup{}
		return input_result_none(), true
	}
	if key_event.code.kind in [.enter, .tab] {
		if selection := composer.popups.active.mention_v2.selected() {
			if start, end, _ := composer.current_editable_at_token_range_with_options(
			/* allow_empty */
			true) {
				if selection.path.len > 0 {
					composer.insert_selected_mention(start, end, &selection.insert_text, selection.path)
				} else {
					composer.insert_selected_file_path(start, end, &selection.insert_text)
				}
			}
			composer.popups.active = ActivePopup{}
			return input_result_none(), true
		}
		composer.popups.active = ActivePopup{}
		if key_event.code.kind == .enter {
			return composer.handle_key_event_without_popup(key_event)
		}
		return input_result_none(), true
	}
	return composer.handle_input_basic(key_event)
}

fn ChatComposer.is_image_path(path &string) bool {
	lower := path.to_lower()
	return lower.ends_with('.png') || lower.ends_with('.jpg') || lower.ends_with('.jpeg')
		|| lower.ends_with('.gif') || lower.ends_with('.webp')
}

// Leaves the cursor after one horizontal separator following a completion.
//
// Another separator is preserved before any non-whitespace suffix so subsequent typing does
// not merge into it. Line breaks are never reused as separators; a space is inserted before
// them so subsequent typing stays on the completed token's line.
fn (mut composer ChatComposer) advance_past_completion_separator() {
	cursor := composer.draft.textarea.cursor()
	text := composer.draft.textarea.text()
	if cursor < text.len {
		separator := rune_at_byte(&text, cursor) or { rune(0) }
		if is_horizontal_completion_space(separator) {
			after := next_char_boundary(&text, cursor)
			separator_precedes_suffix := if next := rune_at_byte(&text, after) {
				!rune_is_space(next)
			} else {
				false
			}
			if separator_precedes_suffix {
				space := ' '
				composer.draft.textarea.insert_str_at(cursor, &space)
			} else {
				composer.draft.textarea.set_cursor(after)
			}
			return
		}
	}
	space := ' '
	composer.draft.textarea.insert_str_at(cursor, &space)
}

// Dismisses popup synchronization only for the exact token occurrence just inserted.
//
// Matching both range and text prevents an identical token later in the draft from inheriting
// the completed token's dismissal state.
fn (mut composer ChatComposer) dismiss_completed_prefixed_token(prefix rune, start int, end int,
	inserted_text &string) {
	if inserted_text.len == 0 || inserted_text.runes()[0] != prefix {
		return
	}
	// Completion leaves the cursor on separator whitespace, where normal token affinity would
	// otherwise immediately reopen the popup for sigil-prefixed inserted text.
	if current_start, current_end, token := current_prefixed_token_range(&composer.draft.textarea, prefix, /* allow_empty */
		true) {
		if current_start == start && current_end == end && token == (*inserted_text)[1..] {
			if prefix == `@` && !composer.mentions_v2_enabled {
				composer.popups.dismissed_file_token = DismissedToken.new(&composer.draft.textarea, current_start, current_end, token)
			} else {
				composer.popups.dismissed_mention_token = DismissedToken.new(&composer.draft.textarea, current_start, current_end, token)
			}
		}
	}
}

fn (mut composer ChatComposer) insert_selected_file_path(start int, end int, selected_path &string) {
	started := composer.begin_direct_vim_edit()
	adjusted_start, adjusted_end := composer.separate_completion_from_adjacent_element(start, end)
	mut image_dimensions_found := false
	if ChatComposer.is_image_path(selected_path) {
		image.image_dimensions(selected_path) or {
			composer.insert_selected_path(adjusted_start, adjusted_end, selected_path)
			if started {
				composer.finish_vim_edit()
			}
			return
		}
		image_dimensions_found = true
	}
	if image_dimensions_found {
		empty := ''
		composer.draft.textarea.replace_range(adjusted_start, adjusted_end, &empty)
		composer.draft.textarea.set_cursor(adjusted_start)
		composer.attach_image(selected_path.clone())
		composer.advance_past_completion_separator()
	} else {
		composer.insert_selected_path(adjusted_start, adjusted_end, selected_path)
	}
	if started {
		composer.finish_vim_edit()
	}
}

fn ChatComposer.trim_text_elements(original &string, trimmed &string,
	elements []user_input.TextElement) []user_input.TextElement {
	if trimmed.len == 0 || elements.len == 0 {
		return []
	}
	trimmed_start := original.len - trim_left_unicode_whitespace(original).len
	trimmed_end := trimmed_start + trimmed.len
	mut result := []user_input.TextElement{}
	for element in elements {
		if element.byte_range.end <= trimmed_start || element.byte_range.start >= trimmed_end {
			continue
		}
		start := max_int(element.byte_range.start - trimmed_start, 0)
		end := min_int(element.byte_range.end - trimmed_start, trimmed.len)
		if start < end {
			result << user_input.TextElement.new(user_input.ByteRange{ start: start, end: end }, (*trimmed)[start..end].clone())
		}
	}
	return result
}

// Expand large-paste placeholders using element ranges and rebuild other element spans.
pub fn ChatComposer.expand_pending_pastes(text &string, mut elements []user_input.TextElement,
	pending_pastes &[]PendingPaste) (string, []user_input.TextElement) {
	if pending_pastes.len == 0 || elements.len == 0 {
		return text.clone(), elements
	}
	// Stage 1: index pending paste payloads by placeholder for deterministic replacements.
	mut queues := map[string][]string{}
	for pending in *pending_pastes {
		queues[pending.placeholder] << pending.actual.clone()
	}
	// Stage 2: walk elements in order and rebuild text/spans in a single pass.
	elements.sort(a.byte_range.start < b.byte_range.start)
	mut rebuilt := ''
	mut rebuilt_elements := []user_input.TextElement{}
	mut cursor := 0
	for element in elements {
		start := clamp_int(element.byte_range.start, 0, text.len)
		end := clamp_int(element.byte_range.end, start, text.len)
		if start > cursor {
			rebuilt += (*text)[cursor..start]
		}
		placeholder := element.placeholder_text(text) or { (*text)[start..end].clone() }
		if mut replacements := queues[placeholder] {
			if replacements.len > 0 {
				// Stage 3: inline actual paste payloads and drop their placeholder elements.
				rebuilt += replacements[0]
				replacements.delete(0)
				queues[placeholder] = replacements
				cursor = end
				continue
			}
		}
		// Stage 4: keep non-paste elements, updating their byte ranges for the new text.
		new_start := rebuilt.len
		rebuilt += (*text)[start..end]
		rebuilt_elements << user_input.TextElement.new(user_input.ByteRange{
			start: new_start
			end:   rebuilt.len
		}, placeholder)
		cursor = end
	}
	// Stage 5: append any trailing text that followed the last element.
	if cursor < text.len {
		rebuilt += (*text)[cursor..]
	}
	return rebuilt, rebuilt_elements
}

// V arrays are already reference-backed; the optional array value is the safe adaptation for
// Rust's Option<&Vec<_>> because V rejects an explicit reference-to-array return type.
pub fn (composer &ChatComposer) skills() ?[]skill_metadata.SkillMetadata {
	if catalog := composer.skills {
		return catalog.items[..]
	}
	return none
}

// See skills() for the V optional-array borrowing adaptation.
pub fn (composer &ChatComposer) plugins() ?[]codex_plugin.PluginCapabilitySummary {
	if catalog := composer.plugins {
		return catalog.items[..]
	}
	return none
}

fn (composer &ChatComposer) mentions_enabled() bool {
	mut ready := false
	if catalog := composer.skills {
		ready = ready || catalog.items.len > 0
	}
	if catalog := composer.plugins {
		ready = ready || catalog.items.len > 0
	}
	if composer.connectors_enabled {
		if snapshot := composer.connectors_snapshot {
			ready = ready || snapshot.connectors.len > 0
		}
	}
	return ready
}

fn ChatComposer.current_prefixed_token(textarea &TextArea, prefix rune, allow_empty bool) ?string {
	_, _, token := current_prefixed_token_range(textarea, prefix, allow_empty) or { return none }
	return token
}

// Extract the `@token` that the cursor is currently positioned on, if any.
//
// The returned string **does not** include the leading `@`.
fn ChatComposer.current_at_token(textarea &TextArea) ?string {
	return ChatComposer.current_prefixed_token(textarea, `@`, /* allow_empty */
		false)
}

// Returns the active prefixed token only when its sigil and name remain editable plaintext.
//
// Atomic elements and tokens whose mention prefix is already atomic are excluded so bound
// mentions are not offered for completion again.
fn (composer &ChatComposer) current_editable_prefixed_token_range(prefix rune,
	allow_empty bool) ?(int, int, string) {
	start, end, token := current_prefixed_token_range(&composer.draft.textarea, prefix, allow_empty) or { return none }
	for element in composer.draft.textarea.text_elements() {
		if ranges_overlap(start, max_int(end, start + 1), element.byte_range.start, element.byte_range.end) {
			return none
		}
	}
	return start, end, token
}

fn (composer &ChatComposer) current_editable_at_token_range_with_options(allow_empty bool) ?(int, int, string) {
	return composer.current_editable_prefixed_token_range(`@`, allow_empty)
}

fn (composer &ChatComposer) current_editable_at_token_with_options(allow_empty bool) ?string {
	_, _, token := composer.current_editable_at_token_range_with_options(allow_empty) or { return none }
	return token
}

fn (composer &ChatComposer) current_editable_at_token() ?string {
	return composer.current_editable_at_token_with_options( /* allow_empty */
	false)
}

fn (composer &ChatComposer) current_mentions_v2_token_range() ?(int, int, string) {
	if !composer.mentions_v2_enabled {
		return none
	}
	return composer.current_editable_at_token_range_with_options( /* allow_empty */
	true)
}

fn (composer &ChatComposer) current_mentions_v2_token() ?string {
	_, _, token := composer.current_mentions_v2_token_range() or { return none }
	return token
}

// Resolves the active legacy `$` target without eagerly cloning the mention catalog.
// Rust fills the catalog lazily; the ownership-safe V closure adaptation materializes the same
// query-independent catalog once before arbitration.
//
// Definite shell syntax is rejected. Ambiguous shell-like queries are accepted only when a
// bindable mention matches. The query-independent catalog built during that check is carried
// forward only when the selected target is also ambiguous.
fn (composer &ChatComposer) current_mention_target() ?MentionCompletionTarget {
	if !composer.mentions_enabled() {
		return none
	}
	// Rust fills this catalog lazily through OnceCell. V closure captures cannot mutate an owned
	// optional array under `-ownership`, so build the same query-independent catalog once here.
	bindable_mentions := composer.mention_items().filter(mention_item_is_bindable(it))
	dollar_predicate := fn [bindable_mentions] (query &string) bool {
		return match dollar_query_kind(query) {
			.completable { true }
			.ambiguous_shell_parameter {
				bindable_mentions.any(mention_item_fuzzy_matches(&it, query))
			}
			.shell_variable, .definite_shell_parameter, .invalid { false }
		}
	}
	start, end, query := current_prefixed_token_range_with_dollar_predicate(&composer.draft.textarea, `$`, true, dollar_predicate) or { return none }
	for element in composer.draft.textarea.text_elements() {
		if ranges_overlap(start, max_int(end, start + 1), element.byte_range.start, element.byte_range.end) {
			return none
		}
	}
	if !dollar_predicate(&query) {
		return none
	}
	prebuilt := if dollar_query_kind(&query) == .ambiguous_shell_parameter {
		?[]MentionItem(bindable_mentions.clone())
	} else {
		?[]MentionItem(none)
	}
	return MentionCompletionTarget{ start: start, end: end, query: query, prebuilt_mentions: prebuilt }
}

fn mention_item_fuzzy_matches(item &MentionItem, query &string) bool {
	if fuzzy_match(&item.display_name, query) {
		return true
	}
	for term in item.search_terms {
		if term != item.display_name && fuzzy_match(&term, query) {
			return true
		}
	}
	return false
}

fn mention_item_is_bindable(item MentionItem) bool {
	if item.path == none {
		return false
	}
	_, _ := ChatComposer.mention_token_from_insert_text(&item.insert_text) or { return false }
	return true
}

// Replace the active `@token` (the one under the cursor) with `path`.
fn (mut composer ChatComposer) insert_selected_path(start int, end int, path &string) {
	// If the path contains whitespace, wrap it in double quotes so the
	// local prompt arg parser treats it as a single argument. Avoid adding
	// quotes when the path already contains one to keep behavior simple.
	needs_quotes := path.runes().any(rune_is_space(it))
	inserted := if needs_quotes && !path.contains('"') { '"${*path}"' } else { path.clone() }
	// Replace just the active `@token` so unrelated text elements, such as
	// large-paste placeholders, remain atomic and can still expand on submit.
	composer.draft.textarea.replace_range(start, end, &inserted)
	inserted_end := start + inserted.len
	composer.draft.textarea.set_cursor(inserted_end)
	composer.advance_past_completion_separator()
	composer.dismiss_completed_prefixed_token(`@`, start, inserted_end, &inserted)
}

fn (mut composer ChatComposer) insert_selected_mention(start int, end int, insert_text &string,
	path ?string) {
	adjusted_start, adjusted_end := composer.separate_completion_from_adjacent_element(start, end)
	// Remove the active token and insert the selected mention as an atomic element.
	empty := ''
	composer.draft.textarea.replace_range(adjusted_start, adjusted_end, &empty)
	composer.draft.textarea.set_cursor(adjusted_start)
	id := composer.draft.textarea.insert_element(insert_text)
	if value := path {
		is_task_path := task_mentions.valid_thread_path(&value) != none
		if is_task_path && insert_text.starts_with('@') && insert_text.len > 1 {
			composer.draft.mention_bindings[id] = ComposerMentionBinding{
				sigil:   `@`
				mention: (*insert_text)[1..].clone()
				path:    value
			}
		} else if sigil, mention := ChatComposer.mention_token_from_insert_text(insert_text) {
			composer.draft.mention_bindings[id] = ComposerMentionBinding{
				sigil:   sigil
				mention: mention
				path:    value
			}
		}
		if is_task_path {
			if mut tasks := composer.task_mentions {
				tasks.clear()
				composer.task_mentions = tasks
			}
		}
	}
	composer.advance_past_completion_separator()
	runes := insert_text.runes()
	if runes.len > 0 && runes[0] in [`$`, `@`] {
		composer.dismiss_completed_prefixed_token(runes[0], adjusted_start, adjusted_start + insert_text.len, insert_text)
	}
}

// Inserts a leading separator when a completion starts directly after an atomic element.
//
// The returned range is shifted to keep replacing the same editable token after insertion.
fn (mut composer ChatComposer) separate_completion_from_adjacent_element(start int, end int) (int, int) {
	for element in composer.draft.textarea.text_elements() {
		if element.byte_range.end == start {
			space := ' '
			composer.draft.textarea.replace_range(start, start, &space)
			return start + 1, end + 1
		}
	}
	return start, end
}

fn ChatComposer.mention_token_from_insert_text(insert_text &string) ?(rune, string) {
	runes := insert_text.runes()
	if runes.len < 2 || runes[0] !in [`$`, `@`] {
		return none
	}
	name := runes[1..].string()
	for byte in name.bytes() {
		if !is_mention_name_char(byte) {
			return none
		}
	}
	return runes[0], name
}

fn (composer &ChatComposer) current_mention_elements() []MentionElement {
	mut result := []MentionElement{}
	for snapshot in composer.draft.textarea.text_element_snapshots() {
		if binding := composer.draft.mention_bindings[snapshot.id] {
			if task_mentions.valid_thread_path(&binding.path) != none
				&& snapshot.text == '${binding.sigil}${binding.mention}' {
				result << MentionElement{ id: snapshot.id, sigil: binding.sigil, mention: binding.mention.clone() }
				continue
			}
		}
		if sigil, mention := ChatComposer.mention_token_from_insert_text(&snapshot.text) {
			result << MentionElement{ id: snapshot.id, sigil: sigil, mention: mention }
		}
	}
	return result
}

struct MentionElement {
	id      u64
	sigil   rune
	mention string
}

fn (composer &ChatComposer) snapshot_mention_bindings() []MentionBinding {
	mut result := []MentionBinding{}
	for element in composer.current_mention_elements() {
		if binding := composer.draft.mention_bindings[element.id] {
			if binding.sigil == element.sigil && binding.mention == element.mention {
				result << MentionBinding{ sigil: binding.sigil, mention: binding.mention.clone(), path: binding.path.clone() }
			}
		}
	}
	return result
}

fn (mut composer ChatComposer) bind_mentions_from_snapshot(bindings []MentionBinding) {
	composer.draft.mention_bindings.clear()
	if bindings.len == 0 {
		return
	}
	text := composer.draft.textarea.text()
	mut scan_from := 0
	for binding in bindings {
		token := '${binding.sigil}${binding.mention}'
		mut matched_start := -1
		mut matched_end := -1
		if task_mentions.valid_thread_path(&binding.path) != none {
			for snapshot in composer.draft.textarea.text_element_snapshots() {
				if snapshot.start >= scan_from && snapshot.text == token {
					matched_start = snapshot.start
					matched_end = snapshot.end
					break
				}
			}
		} else if start, end := find_next_mention_token_range(&text, &token, scan_from) {
			matched_start = start
			matched_end = end
		}
		if matched_start < 0 {
			continue
		}
		start := matched_start
		end := matched_end
		id := composer.draft.textarea.add_element_range(start, end) or {
			composer.draft.textarea.element_id_for_exact_range(start, end) or { continue }
		}
		composer.draft.mention_bindings[id] = ComposerMentionBinding{
			sigil:   binding.sigil
			mention: binding.mention
			path:    binding.path
		}
		scan_from = end
	}
}

fn (composer &ChatComposer) plugin_at_mention_highlights() []Highlight {
	mut result := []Highlight{}
	for snapshot in composer.draft.textarea.text_element_snapshots() {
		if binding := composer.draft.mention_bindings[snapshot.id] {
			if binding.path.starts_with('plugin://') && snapshot.text.starts_with('@') {
				result << Highlight{ start: snapshot.start, end: snapshot.end, style: rat_style.Style.default().fg(rat_style.Color{ kind: .magenta }) }
			}
		}
	}
	return result
}

struct Highlight {
	start int
	end   int
	style rat_style.Style
}

// Prepare text for submission/queuing. Returns None if submission should be suppressed.
// On success, clears pending paste payloads because placeholders have been expanded.
//
// When `record_history` is true, the final submission is stored for ↑/↓ recall.
fn (mut composer ChatComposer) prepare_submission_text(record_history bool) ?PreparedSubmission {
	return composer.prepare_submission_text_with_options(record_history, .immediate, .expand)
}

struct PreparedSubmission {
	text     string
	elements []user_input.TextElement
}

fn (mut composer ChatComposer) prepare_submission_text_with_options(record_history bool,
	slash_validation SlashValidation, pending_handling PendingPasteHandling) ?PreparedSubmission {
	mut text := composer.current_text()
	original_input := text.clone()
	original_elements := composer.current_text_elements()
	original_bindings := composer.snapshot_mention_bindings()
	original_images := composer.attachments.local_image_paths()
	original_pending := clone_pending_pastes(&composer.draft.pending_pastes)
	mut elements := original_elements.clone()
	input_starts_with_space := original_input.starts_with(' ')
	composer.draft.recent_submission_mention_bindings.clear()
	empty := ''
	composer.draft.textarea.set_text_clearing_elements(&empty)
	composer.draft.is_bash_mode = false
	if pending_handling == .expand && composer.draft.pending_pastes.len > 0 {
		// Expand placeholders so element byte ranges stay aligned.
		text, elements = ChatComposer.expand_pending_pastes(&text, mut elements, &composer.draft.pending_pastes)
	}
	if composer.config.trim_submission {
		expanded := text.clone()
		text = trim_unicode_whitespace(&text)
		elements = ChatComposer.trim_text_elements(&expanded, &text, elements)
	}
	validation := composer.slash_input().validate_submission(&text, input_starts_with_space)
	if slash_validation == .immediate && validation.kind == .unknown_command {
		message := 'Unrecognized command \'/${validation.name}\'. Type "/" for a list of supported commands.'
		composer.app_event_tx.send(app_event.insert_history_cell(history_cell.new_info_event(message,
			/* hint */
			none)))
		composer.restore_suppressed_submission(original_input, original_elements, original_images, original_bindings, original_pending)
		return none
	}
	actual_chars := text.runes().len
	if actual_chars > user_input.max_user_input_text_chars {
		composer.app_event_tx.send(app_event.insert_history_cell(history_cell.new_error_event(user_input_too_large_message(actual_chars))))
		composer.restore_suppressed_submission(original_input, original_elements, original_images, original_bindings, original_pending)
		// Embedded composers may cover the transcript that receives the full error.
		if composer.footer.hint_override != none {
			footer_message := 'Message too long; limit ${user_input.max_user_input_text_chars} characters'
			composer.show_footer_flash(line_from_string(&footer_message), 5_000)
		}
		return none
	}
	composer.attachments.prune_local_images_for_submission(&text, &elements)
	if trim_unicode_whitespace(&text).len == 0 && composer.attachments.is_empty() {
		return none
	}
	composer.draft.recent_submission_mention_bindings = original_bindings.clone()
	if record_history && (text.len > 0 || !composer.attachments.is_empty()) {
		preserve_literal_paste := composer.slash_commands_enabled() && text.starts_with('!')
			&& !trim_left_unicode_whitespace(&original_input).starts_with('!')
		history_text := if preserve_literal_paste {
			trim_unicode_whitespace(&original_input)
		} else {
			text.clone()
		}
		history_elements := if preserve_literal_paste {
			ChatComposer.trim_text_elements(&original_input, &history_text, original_elements)
		} else {
			elements.clone()
		}
		composer.history.record_local_submission(HistoryEntry{
			text:              history_text
			text_elements:     history_elements
			local_image_paths: composer.attachments.local_image_paths()
			remote_image_urls: composer.attachments.remote_image_urls()
			mention_bindings:  original_bindings
			pending_pastes:    if pending_handling == .preserve || preserve_literal_paste {
				original_pending
			} else {
				[]
			}
		})
	}
	composer.draft.pending_pastes.clear()
	return PreparedSubmission{ text: text, elements: elements }
}

// Common logic for handling message submission/queuing.
// Returns the appropriate InputResult based on `should_queue`.
fn (mut composer ChatComposer) handle_submission(should_queue bool) (InputResult, bool) {
	result, redraw := composer.handle_submission_with_time(should_queue, time.now().unix_milli())
	composer.reset_vim_mode_after_successful_dispatch(&result)
	return result, redraw
}

fn (mut composer ChatComposer) reset_vim_mode_after_successful_dispatch(result &InputResult) {
	if result.kind in [.submitted, .queued, .command, .service_tier_command, .command_with_args]
		&& composer.config.reset_vim_on_submission {
		composer.reset_vim_mode()
	}
}

fn (mut composer ChatComposer) handle_submission_with_time(should_queue bool, now_ms i64) (InputResult, bool) {
	if !should_queue && composer.handle_paste_enter(now_ms) {
		return input_result_none(), true
	}
	if blocked := composer.handle_parent_owned_submission() {
		return blocked, true
	}
	if should_queue {
		if pasted := composer.draft.paste_burst.flush_before_modified_input() {
			composer.handle_paste(pasted)
		}
		visible_shell := composer.is_bang_shell_command()
		original_input := composer.current_text()
		original_elements := composer.current_text_elements()
		original_pending := clone_pending_pastes(&composer.draft.pending_pastes)
		raw_text := composer.draft.textarea.text()
		defer_slash_validation := composer.slash_input().should_parse_on_dequeue(&raw_text)
		preserve_pending := defer_slash_validation && composer.draft.pending_pastes.len > 0
			&& if name, _, _ := prompt_args.parse_slash_name(&raw_text) {
				name == slash_command.SlashCommand.goal.command()
			} else {
				false
			}
		queued_pending := if preserve_pending {
			clone_pending_pastes(&composer.draft.pending_pastes)
		} else {
			[]PendingPaste{}
		}
		validation := if defer_slash_validation { SlashValidation.deferred } else { .immediate }
		paste_handling := if preserve_pending { PendingPasteHandling.preserve } else { .expand }
		if prepared := composer.prepare_submission_text_with_options( /* record_history */
		true, validation, paste_handling) {
			action := if prepared.text.starts_with('!') && !visible_shell {
				QueuedInputAction.literal
			} else {
				queued_input_action(&prepared.text, defer_slash_validation)
			}
			if action == .literal {
				literal_text := trim_unicode_whitespace(&original_input)
				literal_elements := ChatComposer.trim_text_elements(&original_input, &literal_text, original_elements)
				return InputResult{
					kind:           .queued
					text:           literal_text
					text_elements:  literal_elements
					action:         action
					pending_pastes: original_pending
				}, true
			}
			return InputResult{
				kind:           .queued
				text:           prepared.text
				text_elements:  prepared.elements
				action:         action
				pending_pastes: queued_pending
			}, true
		}
		return input_result_none(), true
	}
	// If the first line is a bare built-in slash command (no args),
	// dispatch it even when the slash popup isn't visible. This preserves
	// the workflow: type a prefix ("/di"), press Tab to complete to
	// "/diff ", then press Enter/Ctrl+Shift+Q to run it. Tab moves the cursor beyond
	// the '/name' token and our caret-based heuristic hides the popup,
	// but Enter/Ctrl+Shift+Q should still dispatch the command rather than submit
	// literal text.
	if result := composer.try_dispatch_bare_slash_command() {
		return result, true
	}
	original_input := composer.current_text()
	original_elements := composer.current_text_elements()
	original_bindings := composer.snapshot_mention_bindings()
	original_images := composer.attachments.local_image_paths()
	original_pending := clone_pending_pastes(&composer.draft.pending_pastes)
	if result := composer.try_dispatch_slash_command_with_args() {
		return result, true
	}
	if prepared := composer.prepare_submission_text( /* record_history */
	true) {
		if composer.slash_commands_enabled() && prepared.text.starts_with('!')
			&& !trim_left_unicode_whitespace(&original_input).starts_with('!') {
			literal_text := trim_unicode_whitespace(&original_input)
			literal_elements := ChatComposer.trim_text_elements(&original_input, &literal_text, original_elements)
			return InputResult{
				kind:           .queued
				text:           literal_text
				text_elements:  literal_elements
				action:         .literal
				pending_pastes: original_pending
			}, true
		}
		// Do not clear local attachments here; ChatWidget drains them via
		// take_recent_submission_images().
		return InputResult{ kind: .submitted, text: prepared.text, text_elements: prepared.elements }, true
	}
	// Restore suppressed input, preserving validation feedback.
	flash := composer.footer.flash
	composer.footer.flash = none
	composer.set_text_content_with_mention_bindings(original_input, original_elements, original_images, original_bindings)
	composer.draft.pending_pastes = original_pending
	composer.footer.flash = flash
	return input_result_none(), true
}

fn (mut composer ChatComposer) handle_parent_owned_submission() ?InputResult {
	if !composer.blocks_direct_input {
		return none
	}
	text := composer.current_text()
	name, args, _ := prompt_args.parse_slash_name(&text) or {
		return InputResult{ kind: .parent_owned_input_blocked }
	}
	if command := composer.slash_input().command(&name) {
		if text.starts_with('/') && command.kind == .builtin && name == command.builtin.command()
			&& parent_owned_command_is_allowed(command.builtin, &args) {
			return none
		}
	}
	return InputResult{ kind: .parent_owned_input_blocked }
}

// Check if the first line is a bare slash command (no args) and dispatch it.
// Returns Some(InputResult) if a command was dispatched, None otherwise.
fn (mut composer ChatComposer) try_dispatch_bare_slash_command() ?InputResult {
	text := composer.draft.textarea.text()
	command := composer.slash_input().bare_command(&text) or { return none }
	if composer.reject_slash_command_if_unavailable(&command) {
		composer.stage_slash_command_history(&command)
		composer.record_pending_slash_command_history()
		return input_result_none()
	}
	composer.stage_slash_command_history(&command)
	empty := ''
	composer.draft.textarea.set_text_clearing_elements(&empty)
	composer.draft.is_bash_mode = false
	return if command.kind == .builtin {
		InputResult{ kind: .command, command: command.builtin }
	} else {
		InputResult{ kind: .service_tier_command, service_tier: command.service_tier }
	}
}

// Check if the input is a slash command with args (e.g., /review args) and dispatch it.
// Returns Some(InputResult) if a command was dispatched, None otherwise.
fn (mut composer ChatComposer) try_dispatch_slash_command_with_args() ?InputResult {
	text := composer.draft.textarea.text()
	inline := composer.slash_input().inline_command(&text) or { return none }
	command := inline.command
	if composer.reject_slash_command_if_unavailable(&command) {
		composer.stage_slash_command_history(&command)
		composer.record_pending_slash_command_history()
		return input_result_none()
	}
	composer.stage_slash_command_history(&command)
	text_elements := composer.draft.textarea.text_elements()
	args_elements := slash_parser.args_elements(&inline.rest, inline.rest_offset, &text_elements)
	trimmed_args := trim_unicode_whitespace(&inline.rest)
	elements := ChatComposer.trim_text_elements(&inline.rest, &trimmed_args, args_elements)
	if command.kind != .builtin {
		return none
	}
	return InputResult{
		kind:          .command_with_args
		command:       command.builtin
		text:          trimmed_args
		text_elements: elements
	}
}

// Expand pending placeholders and extract normalized inline-command args.
//
// Inline-arg commands are initially dispatched using the raw draft so command rejection does
// not consume user input. Once a command needs its args, this helper performs the usual
// submission preparation (paste expansion, element trimming) and rebases element ranges from
// full-text offsets to command-arg offsets.
//
// Callers that already staged slash-command history should normally pass `false` for
// `record_history`; otherwise a command such as `/plan investigate` would be entered into
// local recall through both the slash-command path and the message-submission path.
pub fn (mut composer ChatComposer) prepare_inline_args_submission(record_history bool) ?PreparedSubmission {
	prepared := composer.prepare_submission_text(record_history) or { return none }
	args, args_offset := slash_parser.prepared_args(&prepared.text) or { return none }
	prepared_elements := slash_parser.args_elements(&args, args_offset, &prepared.elements)
	trimmed := trim_unicode_whitespace(&args)
	elements := ChatComposer.trim_text_elements(&args, &trimmed, prepared_elements)
	composer.draft.textarea.enter_vim_insert_mode()
	return PreparedSubmission{ text: trimmed, elements: elements }
}

fn (mut composer ChatComposer) reject_slash_command_if_unavailable(command &SlashCommandItem) bool {
	if !composer.is_task_running || command.available_during_task() {
		return false
	}
	composer.app_event_tx.send(app_event.insert_history_cell(history_cell.new_error_event("'/${command.command()}' is disabled while a task is in progress.")))
	return true
}

// Stage the current slash-command text for later local recall.
//
// Staging snapshots the rich composer state before the textarea is cleared. `ChatWidget`
// commits the staged entry after dispatch so command recall follows the submitted text, not
// the command outcome.
fn (mut composer ChatComposer) stage_slash_command_history(command &SlashCommandItem) {
	if command.kind == .builtin && command.builtin == .clear {
		return
	}
	composer.stage_slash_command_history_text(composer.draft.textarea.text().trim_space())
}

// Stage a popup-selected command using its canonical command text.
//
// Popup filtering text can be partial, so recording the selected command avoids recalling
// `/di` after the user actually accepted `/diff`.
fn (mut composer ChatComposer) stage_selected_slash_command_history(command &SlashCommandItem) {
	if command.kind != .builtin || command.builtin != .clear {
		composer.stage_slash_command_history_text('/${command.command()}')
	}
}

// Store the provided command text and the current composer adornments in the pending slot.
//
// The pending entry intentionally has the same shape as other local history entries so recall
// can rehydrate attachments, mention bindings, and pending paste placeholders if command
// workflows start carrying those through in the future.
fn (mut composer ChatComposer) stage_slash_command_history_text(text string) {
	composer.pending_slash_command_history = HistoryEntry{
		text:              text
		text_elements:     composer.draft.textarea.text_elements()
		local_image_paths: composer.attachments.local_image_paths()
		remote_image_urls: composer.attachments.remote_image_urls()
		mention_bindings:  composer.snapshot_mention_bindings()
		pending_pastes:    clone_pending_pastes(&composer.draft.pending_pastes)
	}
}

fn (mut composer ChatComposer) handle_remote_image_selection_key(key_event &terminal_event.KeyEvent) ?(InputResult, bool) {
	removes_remote_image := key_event.code.kind in [.delete, .backspace]
		&& composer.attachments.selected_remote_image_index != none
	started_vim_edit := removes_remote_image && composer.begin_direct_vim_edit()
	if result, redraw := composer.attachments.handle_remote_image_selection_key(key_event, mut composer.draft.textarea) {
		if started_vim_edit {
			composer.finish_vim_edit()
		}
		return result, redraw
	}
	if started_vim_edit {
		composer.finish_vim_edit()
	}
	return none
}

// Handle key event when no popup is visible.
fn (mut composer ChatComposer) handle_key_event_without_popup(key_event terminal_event.KeyEvent) (InputResult, bool) {
	if result, redraw := composer.handle_remote_image_selection_key(&key_event) {
		return result, redraw
	}
	if composer.attachments.selected_remote_image_index != none {
		composer.attachments.clear_remote_image_selection()
	}
	if composer.handle_empty_prompt_shortcut(&key_event) {
		return input_result_none(), true
	}
	if composer.draft.is_bash_mode && key_event.code.kind == .escape {
		if pasted := composer.draft.paste_burst.flush_before_modified_input() {
			composer.handle_paste(pasted)
		}
		if composer.draft.textarea.is_empty() {
			composer.draft.is_bash_mode = false
			return input_result_none(), true
		}
	}
	if composer.should_handle_vim_insert_escape(key_event) {
		return composer.handle_input_basic(key_event)
	}
	if composer.draft.textarea.is_vim_normal_mode()
		&& composer.draft.textarea.is_vim_operator_pending() {
		return composer.handle_input_basic(key_event)
	}
	if composer.config.shell_commands_enabled && composer.draft.textarea.is_vim_normal_mode()
		&& composer.is_empty() && key_event.code.kind == .char_key && key_event.code.ch == `!` {
		composer.draft.is_bash_mode = true
		composer.draft.textarea.enter_vim_insert_mode()
		return input_result_none(), true
	}
	if key_event.code.kind == .escape {
		if composer.is_empty() {
			next_mode := esc_hint_mode(composer.footer.mode, composer.is_task_running)
			if next_mode != composer.footer.mode {
				composer.footer.mode = next_mode
				return input_result_none(), true
			}
		}
	} else {
		composer.footer.mode = reset_mode_after_activity(composer.footer.mode)
	}
	if key_hint.bindings_are_pressed(&composer.queue_keys, key_event)
		&& (composer.is_task_running || composer.queue_submissions || !composer.is_bang_shell_command()) {
		return composer.handle_submission(composer.is_task_running || composer.queue_submissions)
	}
	if key_hint.bindings_are_pressed(&composer.submit_keys, key_event) {
		return composer.handle_submission(composer.queue_submissions)
	}
	if key_event.code.kind == .char_key && key_event.code.ch == `d` && key_event.modifiers.control
		&& key_event.kind == .press && composer.is_empty() {
		return input_result_none(), false
	}
	history_up_pressed, history_down_pressed := if composer.draft.textarea.is_vim_normal_mode() {
		if composer.draft.textarea.is_vim_operator_pending() {
			false, false
		} else {
			key_hint.bindings_are_pressed(&composer.vim_normal_keymap.move_up, key_event), key_hint.bindings_are_pressed(&composer.vim_normal_keymap.move_down, key_event)
		}
	} else {
		key_hint.bindings_are_pressed(&composer.editor_keymap.move_up, key_event), key_hint.bindings_are_pressed(&composer.editor_keymap.move_down, key_event)
	}
	if history_up_pressed || history_down_pressed {
		current_text := composer.current_text()
		if composer.history.should_handle_navigation(&current_text, composer.history_navigation_cursor()) {
			entry := if history_up_pressed {
				composer.history.navigate_up(&composer.app_event_tx)
			} else {
				composer.history.navigate_down(&composer.app_event_tx)
			}
			if value := entry {
				composer.apply_history_entry(value)
				return input_result_none(), true
			}
		}
	}
	return composer.handle_input_basic(key_event)
}

fn (composer &ChatComposer) is_bang_shell_command() bool {
	text := composer.current_text()
	return composer.config.shell_commands_enabled && trim_left_unicode_whitespace(&text).starts_with('!')
}

fn (composer &ChatComposer) shell_mode_footer_line() ?rat_text.Line {
	if composer.is_bang_shell_command() {
		return rat_text.Line{
			spans: [rat_text.Span{
				text:  'Shell mode'
				style: rat_style.Style.default().light_red()
			}]
		}
	}
	return none
}

// Applies any due `PasteBurst` flush at time `now`.
//
// Converts [`PasteBurst::flush_if_due`] results into concrete textarea mutations.
//
// Callers:
//
// - UI ticks via [`ChatComposer::flush_paste_burst_if_due`], so held first-chars can render.
// - Input handling via [`ChatComposer::handle_input_basic`], so a due burst does not lag.
fn (mut composer ChatComposer) handle_paste_burst_flush(now_ms i64) bool {
	result := composer.draft.paste_burst.flush_if_due(now_ms)
	match result.kind {
		.paste {
			composer.handle_paste(result.text)
			return true
		}
		.typed {
			text := result.ch.str()
			composer.insert_str(&text)
			return true
		}
		.no_flush {
			return false
		}
	}
}

// Handles keys that mutate the textarea, including paste-burst detection.
//
// Acts as the lowest-level keypath for keys that mutate the textarea. It is also where plain
// character streams are converted into explicit paste operations on terminals that do not
// reliably provide bracketed paste.
//
// Ordering is important:
//
// - Always flush any *due* paste burst first so buffered text does not lag behind unrelated
//   edits.
// - Then handle the incoming key, intercepting only text-producing character input.
// - For non-text keys, flush via `flush_before_modified_input()` before applying the key;
//   otherwise `clear_window_after_non_char()` can leave buffered text waiting without a
//   timestamp to time out against.
fn (mut composer ChatComposer) handle_input_basic(input terminal_event.KeyEvent) (InputResult, bool) {
	// Ignore key releases here to avoid treating them as additional input
	// (e.g., appending the same character twice via paste-burst logic).
	if input.kind !in [.press, .repeat] {
		return input_result_none(), false
	}
	return composer.handle_input_basic_with_time(input, time.now().unix_milli())
}

fn (mut composer ChatComposer) handle_input_basic_with_time(input terminal_event.KeyEvent,
	now_ms i64) (InputResult, bool) {
	if !composer.draft.textarea.is_vim_normal_mode() {
		composer.begin_vim_edit(input)
	}
	// If we have a buffered non-bracketed paste burst and enough time has
	// elapsed since the last char, flush it before handling a new input.
	composer.handle_paste_burst_flush(now_ms)
	if input.code.kind != .escape {
		composer.footer.mode = reset_mode_after_activity(composer.footer.mode)
	}

	// If we're capturing a burst and receive Enter, accumulate it instead of inserting.
	if input.code.kind == .enter && !composer.draft.disable_paste_burst
		&& composer.draft.paste_burst.is_active()
		&& composer.draft.paste_burst.append_newline_if_active(now_ms) {
		return input_result_none(), true
	}

	mut has_non_text_modifier := input.modifiers.control || input.modifiers.alt
		|| input.modifiers.super || input.modifiers.hyper || input.modifiers.meta
	$if windows {
		// Windows reports AltGr as Ctrl+Alt; it remains text-producing input.
		if input.modifiers.control && input.modifiers.alt && !input.modifiers.super
			&& !input.modifiers.hyper && !input.modifiers.meta {
			has_non_text_modifier = false
		}
	}

	// Intercept text-producing Char inputs to optionally accumulate into a burst buffer.
	//
	// This preserves plain, Shift, and Windows AltGr input while keeping shortcut modifiers
	// out of the burst detector and flushing any in-flight text before a non-text key.
	if input.code.kind == .char_key {
		if !has_non_text_modifier && !composer.draft.disable_paste_burst
			&& composer.draft.textarea.allows_paste_burst() {
			// Non-ASCII characters (e.g., from IMEs) can arrive in quick bursts, so avoid
			// holding the first char while still allowing burst detection for paste input.
			if input.code.ch > 127 {
				return composer.handle_non_ascii_char(input, now_ms)
			}
			decision := composer.draft.paste_burst.on_plain_char(input.code.ch, now_ms)
			match decision.kind {
				.buffer_append {
					composer.draft.paste_burst.append_char_to_buffer(input.code.ch, now_ms)
					return input_result_none(), true
				}
				.begin_buffer {
					cursor := composer.draft.textarea.cursor()
					text := composer.draft.textarea.text()
					safe_cursor := ChatComposer.clamp_to_char_boundary(&text, cursor)
					before := text[..safe_cursor]
					if grab := composer.draft.paste_burst.decide_begin_buffer(now_ms, &before, int(decision.retro_chars)) {
						if grab.grabbed.len == 0
							|| composer.draft.textarea.retract_paste_burst(grab.start_byte) {
							composer.draft.paste_burst.append_char_to_buffer(input.code.ch, now_ms)
							return input_result_none(), true
						}
						composer.draft.paste_burst.clear_after_explicit_paste()
					}
					// If decide_begin_buffer opted not to start buffering,
					// fall through to normal insertion below.
				}
				.begin_buffer_from_pending {
					// First char was held; now append the current one.
					composer.draft.paste_burst.append_char_to_buffer(input.code.ch, now_ms)
					return input_result_none(), true
				}
				.retain_first_char {
					// Keep the first fast char pending momentarily.
					return input_result_none(), true
				}
			}
		}
		if pasted := composer.draft.paste_burst.flush_before_modified_input() {
			composer.handle_paste(pasted)
		}
	}

	// Flush any buffered burst before applying a non-char input (arrow keys, etc).
	//
	// `clear_window_after_non_char()` clears `last_plain_char_time`. If we cleared that while
	// `PasteBurst.buffer` is non-empty, `flush_if_due()` would no longer have a timestamp to
	// time out against, and the buffered paste could remain stuck until another plain char
	// arrives.
	if input.code.kind !in [.char_key, .enter] {
		if pasted := composer.draft.paste_burst.flush_before_modified_input() {
			composer.handle_paste(pasted)
		}
	}

	// For non-char inputs (or after flushing), handle normally.
	// Track element removals so we can drop any corresponding placeholders without scanning
	// the full text. (Placeholders are atomic elements; when deleted, the element disappears.)
	elements_before := if composer.draft.pending_pastes.len == 0 && composer.attachments.is_empty() {
		[]string{}
	} else {
		composer.draft.textarea.element_payloads()
	}
	if composer.draft.is_bash_mode && !composer.draft.textarea.vim_query_active()
		&& input.code.kind == .backspace && composer.draft.textarea.cursor() == 0 {
		started := composer.begin_direct_vim_edit()
		composer.draft.is_bash_mode = false
		if started {
			composer.finish_vim_edit()
		}
		return input_result_none(), true
	}

	composer.begin_vim_edit(input)
	composer.draft.textarea.input(input)
	composer.sync_bash_mode_from_text()
	if elements_before.len > 0 {
		composer.reconcile_deleted_elements(elements_before)
	}
	composer.finish_vim_edit()

	// Update the paste-burst heuristic for text, shortcut, and non-char events.
	match input.code.kind {
		.char_key {
			if has_non_text_modifier {
				composer.draft.paste_burst.clear_window_after_non_char()
			}
		}
		.enter {
			// Keep burst window alive (supports blank lines in paste).
		}
		else {
			// Other keys: clear burst window (buffer should have been flushed above if needed).
			composer.draft.paste_burst.clear_window_after_non_char()
		}
	}
	return input_result_none(), true
}

fn (mut composer ChatComposer) sync_bash_mode_from_text() {
	text := composer.draft.textarea.text()
	if composer.config.shell_commands_enabled && !composer.draft.is_bash_mode && text.starts_with('!') {
		cursor := composer.draft.textarea.cursor()
		empty := ''
		composer.draft.textarea.replace_range(0, 1, &empty)
		composer.draft.textarea.set_cursor(max_int(cursor - 1, 0))
		composer.draft.is_bash_mode = true
	}
}

fn (mut composer ChatComposer) reconcile_deleted_elements(elements_before []string) {
	after := composer.draft.textarea.element_payloads()
	mut removed := []string{}
	for payload in elements_before {
		if payload !in after {
			removed << payload
		}
	}
	composer.draft.pending_pastes = composer.draft.pending_pastes.filter(it.placeholder !in removed)
	composer.attachments.remove_deleted_local_placeholders(&removed, mut composer.draft.textarea)
}

// Handle empty-prompt agents navigation and the shortcut-overlay toggle.
//
// This only toggles when the composer is empty and no paste burst is in
// progress, so typing/pasting `?` still inserts text instead of opening
// help. The bound key list intentionally supports terminal-variant
// modifier reporting (for example `?` vs `shift-?`).
fn (mut composer ChatComposer) handle_empty_prompt_shortcut(key_event &terminal_event.KeyEvent) bool {
	if key_event.kind != .press {
		return false
	}
	if key_event.code.kind == .left && composer.agents_navigation_available() {
		composer.app_event_tx.send(app_event.open_agents_overview())
		return true
	}
	toggles := composer.footer.hint_override == none
		&& key_hint.bindings_are_pressed(&composer.toggle_shortcuts_keys, *key_event)
		&& composer.is_empty() && !composer.is_in_paste_burst()
	if !toggles {
		return false
	}
	next := toggle_shortcut_mode(composer.footer.mode, composer.quit_shortcut_hint_visible(), composer.is_empty())
	changed := next != composer.footer.mode
	composer.footer.mode = next
	return changed
}

fn (composer &ChatComposer) footer_props() FooterProps {
	mode := composer.footer_mode()
	mut is_wsl := false
	$if linux {
		is_wsl = mode == .shortcut_overlay && clipboard_paste.is_probably_wsl()
	}
	return FooterProps{
		mode:                        mode
		esc_backtrack_hint:          composer.footer.esc_backtrack_hint
		use_shift_enter_hint:        composer.footer.use_shift_enter_hint
		is_task_running:             composer.is_task_running
		queue_submissions:           composer.queue_submissions
		quit_shortcut_key:           composer.footer.quit_shortcut_key
		collaboration_modes_enabled: composer.collaboration_modes_enabled
		is_wsl:                      is_wsl
		status_line_value:           composer.footer.status_line_value
		status_line_enabled:         composer.footer.status_line_enabled
		key_hints:                   FooterKeyHints{
			agents:           if composer.agents_navigation_available() {
				key_hint.ShortcutHint.single(key_hint.plain(terminal_event.KeyCode{ kind: .left }))
			} else {
				none
			}
			toggle_shortcuts: composer.footer.toggle_shortcuts_key
			queue:            composer.footer.queue_key
			insert_newline:   composer.footer.insert_newline_key
			external_editor:  composer.footer.external_editor_key
			edit_previous:    key_hint.ShortcutHint.single(key_hint.plain(terminal_event.KeyCode{
				kind: .escape
			}))
			show_transcript:  composer.footer.show_transcript_key
			history_search:   composer.footer.history_search_key
			reasoning_down:   composer.footer.reasoning_down_key
			reasoning_up:     composer.footer.reasoning_up_key
		}
		active_agent_label:          composer.footer.active_agent_label
	}
}

// Resolve the effective footer mode via a small priority waterfall.
//
// The base mode is derived solely from whether the composer is empty:
// `ComposerEmpty` iff empty, otherwise `ComposerHasDraft`. Transient
// modes (Esc hint, overlay, quit reminder) can override that base when
// their conditions are active.
fn (composer &ChatComposer) footer_mode() FooterMode {
	if composer.history_search != none || composer.draft.textarea.vim_query_active() {
		return .history_search
	}
	base := if composer.is_empty() {
		FooterMode.composer_empty
	} else {
		FooterMode.composer_has_draft
	}
	return match composer.footer.mode {
		.history_search { .history_search }
		.esc_hint { .esc_hint }
		.shortcut_overlay { .shortcut_overlay }
		.quit_shortcut_reminder {
			if composer.quit_shortcut_hint_visible() { .quit_shortcut_reminder } else { base }
		}
		else {
			if composer.quit_shortcut_hint_visible() { .quit_shortcut_reminder } else { base }
		}
	}
}

fn (composer &ChatComposer) custom_footer_height() ?u16 {
	if composer.draft.textarea.vim_query_active() || composer.footer.flash_visible() {
		return u16(1)
	}
	if items := composer.footer.hint_override {
		return if items.len == 0 { u16(0) } else { u16(1) }
	}
	return none
}

struct EditablePopupToken {
	start int
	end   int
	query string
}

// V's ownership checker moves resource-bearing optionals on every extraction. These explicit
// slots preserve Rust's reusable borrowed `Option` state without cloning token strings.
struct EditablePopupTokenSlot {
mut:
	present bool
	token   EditablePopupToken
}

struct MentionCompletionTargetSlot {
mut:
	present bool
	target  MentionCompletionTarget
}

fn (mut composer ChatComposer) cancel_file_search() {
	if composer.popups.current_file_query.present {
		composer.app_event_tx.send(app_event.start_file_search(''))
		composer.popups.current_file_query = OwnedStringSlot{}
	}
}

pub fn (mut composer ChatComposer) sync_popups() {
	composer.sync_slash_command_elements()
	if composer.history_search != none || composer.draft.textarea.vim_query_active() {
		composer.cancel_file_search()
		composer.popups.active = ActivePopup{}
		composer.popups.dismissed_file_token = none
		composer.popups.dismissed_mention_token = none
		return
	}
	if !composer.popups_enabled() {
		composer.popups.active = ActivePopup{}
		return
	}
	mut mentions_v2_token := EditablePopupTokenSlot{}
	if start, end, query := composer.current_mentions_v2_token_range() {
		mentions_v2_token = EditablePopupTokenSlot{
			present: true
			token:   EditablePopupToken{ start: start, end: end, query: query }
		}
	}
	mut file_token := EditablePopupTokenSlot{}
	if !composer.mentions_v2_enabled {
		if start, end, query := composer.current_editable_at_token_range_with_options(
		/* allow_empty */
		false) {
			file_token = EditablePopupTokenSlot{
				present: true
				token:   EditablePopupToken{ start: start, end: end, query: query }
			}
		}
	}
	current_text := composer.current_text()
	if composer.history.should_handle_navigation(&current_text, composer.history_navigation_cursor()) {
		// When browsing input history (shell-style Up/Down recall), skip all popup
		// synchronization so nothing steals focus from continued history navigation.
		composer.cancel_file_search()
		composer.popups.active = ActivePopup{}
		return
	}
	mut mention_target := MentionCompletionTargetSlot{}
	if target := composer.current_mention_target() {
		mention_target = MentionCompletionTargetSlot{ present: true, target: target }
	}
	mut at_start := -1
	if mentions_v2_token.present {
		at_start = mentions_v2_token.token.start
	} else if file_token.present {
		at_start = file_token.token.start
	}
	if mention_target.present {
		if at_start >= 0 && at_start > mention_target.target.start {
			mention_target.present = false
		} else if at_start >= 0 && mention_target.target.start > at_start {
			mentions_v2_token.present = false
			file_token.present = false
		}
	}
	allow_command := composer.slash_commands_enabled() && !composer.draft.is_bash_mode
		&& !file_token.present && !mentions_v2_token.present && !mention_target.present
	composer.sync_command_popup(allow_command)
	if composer.popups.active.kind == .command {
		composer.cancel_file_search()
		composer.popups.dismissed_file_token = none
		composer.popups.dismissed_mention_token = none
		return
	}
	if mentions_v2_token.present {
		token := mentions_v2_token.token
		composer.sync_mentions_v2_popup(token.start, token.end, token.query)
		return
	}
	if mention_target.present {
		composer.cancel_file_search()
		composer.sync_mention_popup(mention_target.target)
		return
	}
	composer.popups.dismissed_mention_token = none
	if file_token.present {
		token := file_token.token
		composer.sync_file_search_popup(token.start, token.end, token.query)
		return
	}
	composer.cancel_file_search()
	composer.popups.dismissed_file_token = none
	if composer.popups.active.kind in [.file, .skill, .mention_v2] {
		composer.popups.active = ActivePopup{}
	}
}

// Synchronize `self.command_popup` with the current text in the
// textarea. This must be called after every modification that can change
// the text so the popup is shown/updated/hidden as appropriate.
fn (mut composer ChatComposer) sync_command_popup(allow bool) {
	text := composer.draft.textarea.text()
	line := text.all_before('\n')
	// Keep an explicitly dismissed popup closed until the command token changes.
	command_token := command_popup_filter_text(&line, /* cursor */
		0)
	if token := command_token {
		// Rust compares through `Option::as_deref`. An if-guard on a field of the `mut`
		// receiver takes the value under `-ownership`, so guard a local copy of the field.
		dismissed_token := composer.popups.dismissed_command_token
		if dismissed := dismissed_token {
			if dismissed == token {
				return
			}
		}
	}
	composer.popups.dismissed_command_token = none
	if !allow {
		if composer.popups.active.kind == .command {
			composer.popups.active = ActivePopup{}
		}
		return
	}
	// Determine whether the caret is inside the initial '/name' token on the first line.
	cursor := composer.draft.textarea.cursor()
	caret_on_first_line := cursor <= line.len
	is_editing := caret_on_first_line
		&& composer.slash_input().is_editing_command_name(&line, cursor)
	mut filter_text := ?string(none)
	if caret_on_first_line {
		filter_text = command_popup_filter_text(&line, cursor)
	}
	// If the cursor is currently positioned within an `@token`, prefer the
	// file-search popup over the slash popup so users can insert a file path
	// as an argument to the command (e.g., "/review @docs/...").
	if ChatComposer.current_at_token(&composer.draft.textarea) != none {
		if composer.popups.active.kind == .command {
			composer.popups.active = ActivePopup{}
		}
		return
	}
	if is_editing {
		if filter := filter_text {
			if composer.popups.active.kind == .command {
				composer.popups.active.command.on_composer_text_change(filter)
			} else {
				slash_input := composer.slash_input()
				popup := slash_input.command_popup(&filter)
				composer.popups.active = ActivePopup{ kind: .command, command: popup }
			}
			return
		}
		composer.popups.active = ActivePopup{}
	} else if composer.popups.active.kind == .command {
		composer.popups.active = ActivePopup{}
	}
}

// Synchronize the legacy file-search popup with the current `@` token.
fn (mut composer ChatComposer) sync_file_search_popup(start int, end int, query string) {
	// Rust tests the token through `Option::as_ref`. An if-guard on a field of the `mut`
	// receiver takes the value under `-ownership`, so guard a local copy of the field
	// instead (an independent clone under `-ownership`).
	dismissed_token := composer.popups.dismissed_file_token
	if dismissed := dismissed_token {
		if dismissed.matches(&composer.draft.textarea, start, end, &query) {
			return
		}
	}
	composer.app_event_tx.send(app_event.start_file_search(query.clone()))
	composer.popups.current_file_query = if query.len == 0 {
		OwnedStringSlot{}
	} else {
		OwnedStringSlot{ present: true, value: query.clone() }
	}
	if composer.popups.active.kind == .file {
		if query.len == 0 {
			composer.popups.active.file.set_empty_prompt()
		} else {
			composer.popups.active.file.set_query(&query)
		}
	} else {
		mut popup := FileSearchPopup.new()
		if query.len == 0 {
			popup.set_empty_prompt()
		} else {
			popup.set_query(&query)
		}
		composer.popups.active = ActivePopup{ kind: .file, file: popup }
	}
	composer.popups.dismissed_file_token = none
}

fn (mut composer ChatComposer) sync_mention_popup(target MentionCompletionTarget) {
	// Rust tests the token through `Option::as_ref`. An if-guard on a field of the `mut`
	// receiver takes the value under `-ownership`, so guard a local copy of the field
	// instead (an independent clone under `-ownership`).
	dismissed_token := composer.popups.dismissed_mention_token
	if dismissed := dismissed_token {
		if dismissed.matches(&composer.draft.textarea, target.start, target.end, &target.query) {
			return
		}
	}
	items := target.prebuilt_mentions or { composer.mention_items() }
	if items.len == 0 {
		composer.popups.active = ActivePopup{}
		return
	}
	if composer.popups.active.kind == .skill {
		composer.popups.active.skill.set_query(&target.query)
		composer.popups.active.skill.set_mentions(items)
	} else {
		mut popup := SkillPopup.new(items)
		popup.set_query(&target.query)
		composer.popups.active = ActivePopup{ kind: .skill, skill: popup }
	}
	composer.popups.dismissed_mention_token = none
}

fn (mut composer ChatComposer) sync_mentions_v2_popup(start int, end int, query string) {
	// Rust tests the token through `Option::as_ref`. An if-guard on a field of the `mut`
	// receiver takes the value under `-ownership`, so guard a local copy of the field
	// instead (an independent clone under `-ownership`).
	dismissed_token := composer.popups.dismissed_mention_token
	if dismissed := dismissed_token {
		if dismissed.matches(&composer.draft.textarea, start, end, &query) {
			return
		}
	}
	if query.len == 0 {
		composer.app_event_tx.send(app_event.start_file_search(''))
		composer.popups.current_file_query = OwnedStringSlot{}
	} else if composer.popups.current_file_query.present {
		if composer.popups.current_file_query.value != query {
			composer.app_event_tx.send(app_event.start_file_search(query.clone()))
			composer.popups.current_file_query = OwnedStringSlot{
				present: true
				value:   query.clone()
			}
		}
	} else {
		// A fresh popup has no cached matches, and the app-owned file-search manager can
		// retain an identical query. Reset it before issuing the query so results arrive.
		composer.app_event_tx.send(app_event.start_file_search(''))
		composer.app_event_tx.send(app_event.start_file_search(query.clone()))
		composer.popups.current_file_query = OwnedStringSlot{
			present: true
			value:   query.clone()
		}
	}
	if composer.popups.active.kind == .mention_v2 {
		composer.popups.active.mention_v2.set_query(&query)
	} else {
		tasks := composer.task_mentions or { []task_mentions.TaskMention{} }
		candidates := build_mentions_v2_catalog(composer.skills(), composer.plugins(), &tasks)
		composer.popups.active = ActivePopup{
			kind:       .mention_v2
			mention_v2: MentionV2Popup.new(candidates, &query)
		}
	}
	composer.popups.dismissed_mention_token = none
}

fn (composer &ChatComposer) mention_items() []MentionItem {
	mut mentions := []MentionItem{}
	if catalog := composer.skills {
		for skill in catalog.items {
			description := skill_description(&skill)
			mut display_name := skill.name.clone()
			if skill_interface := skill.interface {
				if interface_name := skill_interface.display_name {
					display_name = interface_name
				}
			}
			// V 0.5.2 miscompiles an `if` expression whose branches build arrays from `.clone()`
			// calls, so the equivalent Rust `if display_name == skill.name { vec![..] } else { .. }`
			// is spelled as an accumulating local here.
			mut search_terms := [skill.name.clone()]
			if display_name != skill.name {
				search_terms << display_name.clone()
			}
			mentions << MentionItem{
				display_name: display_name
				description:  description
				insert_text:  '\$${skill.name}'
				search_terms: search_terms
				path:         skill.path.clone()
				category_tag: '[Skill]'
				sort_rank:    1
			}
		}
	}
	if !composer.mentions_v2_enabled {
		if catalog := composer.plugins {
			for plugin in catalog.items {
				separator := plugin.config_name.index('@') or { plugin.config_name.len }
				name := plugin.config_name[..separator].clone()
				marketplace_name := if separator < plugin.config_name.len {
					plugin.config_name[separator + 1..].clone()
				} else {
					''
				}
				mut capability_labels := []string{}
				if plugin.has_skills {
					capability_labels << 'skills'
				}
				if plugin.mcp_server_names.len == 1 {
					capability_labels << '1 MCP server'
				} else if plugin.mcp_server_names.len > 1 {
					capability_labels << '${plugin.mcp_server_names.len} MCP servers'
				}
				if plugin.app_connector_ids.len == 1 {
					capability_labels << '1 app'
				} else if plugin.app_connector_ids.len > 1 {
					capability_labels << '${plugin.app_connector_ids.len} apps'
				}
				description := if plugin_description := plugin.description {
					?string(plugin_description.clone())
				} else if capability_labels.len == 0 {
					?string('Plugin')
				} else {
					?string('Plugin · ${capability_labels.join(' · ')}')
				}
				mut search_terms := [name.clone(), plugin.config_name.clone()]
				if plugin.display_name != name {
					search_terms << plugin.display_name.clone()
				}
				if marketplace_name.len > 0 {
					search_terms << marketplace_name
				}
				mentions << MentionItem{
					display_name: plugin.display_name.clone()
					description:  description
					insert_text:  '\$${name}'
					search_terms: search_terms
					path:         'plugin://${plugin.config_name}'
					category_tag: '[Plugin]'
					sort_rank:    0
				}
			}
		}
	}
	if composer.connectors_enabled {
		if snapshot := composer.connectors_snapshot {
			for connector in snapshot.connectors {
				if !connector.is_accessible || !connector.is_enabled {
					continue
				}
				display_name := connector_metadata.connector_display_label(&connector)
				slug := connector_metadata.connector_mention_slug(&connector)
				mentions << MentionItem{
					display_name: display_name.clone()
					description:  ChatComposer.connector_brief_description(&connector)
					insert_text:  '\$${slug}'
					search_terms: [display_name, connector.id.clone(), slug]
					path:         'app://${connector.id}'
					category_tag: '[App]'
					sort_rank:    1
				}
			}
		}
	}
	return mentions
}

fn ChatComposer.connector_brief_description(connector &codex_connectors.AppInfo) string {
	return ChatComposer.connector_description(connector) or { '' }
}

fn ChatComposer.connector_description(connector &codex_connectors.AppInfo) ?string {
	if value := connector.description {
		trimmed := value.trim_space()
		if trimmed.len > 0 {
			return trimmed
		}
	}
	return none
}

fn (mut composer ChatComposer) set_has_focus(has_focus bool) {
	composer.has_focus = has_focus
}

pub fn (mut composer ChatComposer) set_input_enabled(enabled bool, placeholder ?string) {
	composer.draft.input_enabled = enabled
	composer.draft.input_disabled_placeholder = if enabled { none } else { placeholder }
	// Avoid leaving interactive popups open while input is blocked.
	if !enabled && composer.popups.is_active() {
		composer.popups.active = ActivePopup{}
	}
}

pub fn (mut composer ChatComposer) show_shutdown_in_progress() {
	composer.set_input_enabled( /* enabled */
	false, 'Shutting down...')
	composer.footer.quit_shortcut_expires_at = 0
	composer.footer.mode = .composer_empty
	composer.footer.flash = none
	composer.footer.hint_override = [][]string{}
}

pub fn (mut composer ChatComposer) set_task_running(running bool) {
	composer.is_task_running = running
}

pub fn (mut composer ChatComposer) set_queue_submissions(enabled bool) {
	composer.queue_submissions = enabled
}

pub fn (mut composer ChatComposer) set_context_window(percent ?i64, used_tokens ?i64) {
	if composer.footer.context_window_percent == percent
		&& composer.footer.context_window_used_tokens == used_tokens {
		return
	}
	composer.footer.context_window_percent = percent
	composer.footer.context_window_used_tokens = used_tokens
}

pub fn (mut composer ChatComposer) set_context_window_pending(pending bool) {
	composer.footer.context_window_pending = pending
}

pub fn (mut composer ChatComposer) set_esc_backtrack_hint(show bool) {
	composer.footer.esc_backtrack_hint = show
	composer.footer.mode = if show {
		.esc_hint
	} else {
		composer.reset_footer_mode_after_activity()
	}
}

pub fn (mut composer ChatComposer) set_status_line(status_line ?rat_text.Line) bool {
	if composer.footer.status_line_value == status_line {
		return false
	}
	composer.footer.status_line_value = status_line
	return true
}

pub fn (mut composer ChatComposer) set_status_line_hyperlink(url ?string) bool {
	if composer.footer.status_line_hyperlink_url == url {
		return false
	}
	composer.footer.status_line_hyperlink_url = url
	return true
}

pub fn (mut composer ChatComposer) set_status_line_enabled(enabled bool) bool {
	if composer.footer.status_line_enabled == enabled {
		return false
	}
	composer.footer.status_line_enabled = enabled
	return true
}

pub fn (mut composer ChatComposer) set_side_conversation_context_label(label ?string) bool {
	if composer.footer.side_conversation_context_label == label {
		return false
	}
	composer.footer.side_conversation_context_label = label
	return true
}

// Replaces the contextual footer label for the currently viewed agent.
//
// Returning `false` means the value was unchanged, so callers can skip redraw work. This
// field is intentionally just cached presentation state; `ChatComposer` does not infer which
// thread is active on its own.
pub fn (mut composer ChatComposer) set_active_agent_label(label ?string) bool {
	if composer.footer.active_agent_label == label {
		return false
	}
	composer.footer.active_agent_label = label
	return true
}

fn footer_insert_newline_key(bindings &[]key_hint.KeyBinding, enhanced_keys_supported bool) ?key_hint.KeyBinding {
	shift_enter := key_hint.shift(terminal_event.KeyCode{ kind: .enter })
	if enhanced_keys_supported && shift_enter in *bindings {
		return shift_enter
	}
	plain_enter := key_hint.plain(terminal_event.KeyCode{ kind: .enter })
	for binding in *bindings {
		if binding != plain_enter {
			return binding
		}
	}
	if bindings.len > 0 {
		return (*bindings)[0]
	}
	return none
}

fn skill_description(skill &skill_metadata.SkillMetadata) ?string {
	mut description := skill.description.clone()
	if short := skill.short_description {
		description = short
	}
	if skill_interface := skill.interface {
		if short := skill_interface.short_description {
			description = short
		}
	}
	trimmed := description.trim_space()
	return if trimmed.len > 0 { trimmed } else { none }
}

fn is_mention_name_char(byte u8) bool {
	return byte.is_alnum() || byte in [`_`, `-`]
}

fn ends_plaintext_at_mention(bytes &[]u8, index int) bool {
	if index >= bytes.len {
		return true
	}
	byte := (*bytes)[index]
	if byte.is_space() {
		return true
	}
	if byte == `.` {
		return index + 1 >= bytes.len || (*bytes)[index + 1].is_space()
			|| (!(*bytes)[index + 1].is_alnum() && (*bytes)[index + 1] !in [`_`, `-`])
	}
	return byte !in [`.`, `/`, `\\`] && !byte.is_alnum() && byte !in [`_`, `-`]
}

fn ends_plaintext_at_dollar_mention(bytes &[]u8, index int) bool {
	return index >= bytes.len || !is_mention_name_char((*bytes)[index])
}

fn starts_plaintext_at_mention(text &string, index int) bool {
	if index == 0 {
		return true
	}
	previous := previous_char_boundary(text, index)
	runes := (*text)[previous..index].runes()
	return runes.len > 0 && (rune_is_space(runes[0]) || !is_mention_name_char_char(runes[0]))
}

fn is_mention_name_char_char(ch rune) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
		|| ch in [`_`, `-`]
}

fn find_next_mention_token_range(text &string, token &string, from int) ?(int, int) {
	if token.len == 0 || from >= text.len {
		return none
	}
	bytes := text.bytes()
	token_bytes := token.bytes()
	sigil := token_bytes[0]
	mut index := from
	for index < bytes.len {
		relative := (*text)[index..].index(*token) or { return none }
		index += relative
		end := index + token.len
		// Fix for restored `@` mentions: rebinding must not attach to embedded substrings such
		// as email addresses, while preserving the existing `$` mention matching behavior.
		starts := if sigil == `@` { starts_plaintext_at_mention(text, index) } else { true }
		// Fix for restored `@` mentions: mirror history encoding's trailing boundary so path-like
		// text such as `@sample/pkg` is not rebound as the plain `@sample` mention.
		ends := if sigil == `@` {
			ends_plaintext_at_mention(&bytes, end)
		} else {
			ends_plaintext_at_dollar_mention(&bytes, end)
		}
		// Restored @ mentions never bind embedded email/path substrings. Dollar matching retains its
		// established boundary behavior.
		if starts && ends {
			return index, end
		}
		index = end
	}
	return none
}

// Set Luna Reserve state and report whether rendering needs a redraw.
pub fn (mut composer ChatComposer) set_luna_reserve_active(active bool) bool {
	if composer.luna_reserve_active == active {
		return false
	}
	composer.luna_reserve_active = active
	return true
}

pub fn (composer &ChatComposer) desired_height(width u16) u16 {
	return composer.desired_height_with_textarea_right_reserve(width, /* textarea_right_reserve */
		0)
}

pub fn (composer &ChatComposer) desired_height_with_textarea_right_reserve(width u16,
	textarea_right_reserve u16) u16 {
	props := composer.footer_props()
	footer_hint_height := composer.custom_footer_height() or { footer_height(&props) }
	footer_total_height := footer_hint_height + ChatComposer.footer_spacing(footer_hint_height)
	inner := if width > 3 + textarea_right_reserve { width - 3 - textarea_right_reserve } else { 0 }
	text_lines := composer.draft.textarea.desired_height(inner)
	remote_height := u16(composer.attachments.remote_urls.len)
	remote_separator := if remote_height > 0 { u16(1) } else { u16(0) }
	return text_lines + remote_height + remote_separator + 2 + composer.popups.active.required_height(width, footer_total_height)
}

pub fn (composer &ChatComposer) render(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	composer.render_with_mask(area, mut buffer, /* mask_char */
		none)
}

pub fn (composer &ChatComposer) render_with_mask(area rat_layout.Rect, mut buffer rat_buffer.Buffer, mask_char ?rune) {
	composer.render_with_mask_and_textarea_right_reserve(area, mut buffer, mask_char,
		/* textarea_right_reserve */
		0)
}

pub fn (composer &ChatComposer) render_with_mask_and_textarea_right_reserve(area rat_layout.Rect,
	mut buffer rat_buffer.Buffer, mask_char ?rune, textarea_right_reserve u16) {
	areas := composer.layout_areas_with_textarea_right_reserve(area, textarea_right_reserve)
	composer_rect := areas[0]
	remote_images_rect := areas[1]
	textarea_rect := areas[2]
	popup_rect := areas[3]
	buffer.regions << rat_buffer.Region{ name: 'composer', rect: composer_rect }
	buffer.regions << rat_buffer.Region{ name: 'remote_images', rect: remote_images_rect }
	buffer.regions << rat_buffer.Region{ name: 'textarea', rect: textarea_rect }
	buffer.regions << rat_buffer.Region{ name: 'popup_or_footer', rect: popup_rect }

	message_style := tui_style.user_message_style()
	buffer.set_style(composer_rect, message_style)
	remote_lines := composer.attachments.remote_image_lines()
	for row in 0 .. remote_images_rect.height {
		if int(row) >= remote_lines.len {
			break
		}
		line := remote_lines[int(row)]
		label := line.spans.map(it.text).join('')
		style := if line.spans.len > 0 { line.spans[0].style } else { message_style }
		write_render_text(mut buffer, remote_images_rect.x, remote_images_rect.y + row, remote_images_rect.width, &label, style, [])
		buffer.lines << label
	}

	if textarea_rect.width > 0 && textarea_rect.height > 0 {
		prompt_style, prompt := composer.prompt_for_render()
		prompt_x := if textarea_rect.x >= live_prefix_cols {
			textarea_rect.x - live_prefix_cols
		} else {
			u16(0)
		}
		buffer.put_cell(prompt_x, textarea_rect.y, prompt, prompt_style)
	}

	textarea_is_empty := composer.draft.textarea.text().len == 0 && !composer.draft.is_bash_mode
	mut textarea_state := composer.draft.textarea_state
	if composer.draft.input_enabled && !textarea_is_empty {
		if mask := mask_char {
			composer.draft.textarea.render_ref_masked(textarea_rect, mut buffer, mut textarea_state, mask)
			buffer.lines << mask.str().repeat(composer.draft.textarea.text().runes().len)
		} else {
			mut highlights := composer.plugin_at_mention_highlights()
			for range in composer.search_highlights() {
				highlights << range
			}
			if highlights.len == 0 {
				composer.draft.textarea.render_ref(textarea_rect, mut buffer, mut textarea_state)
			} else {
				composer.draft.textarea.render_ref_styled_with_highlights(textarea_rect, mut buffer, mut textarea_state, message_style, highlights)
			}
			buffer.lines << composer.draft.textarea.text()
		}
	}
	if !composer.draft.input_enabled || textarea_is_empty {
		placeholder := if composer.draft.input_enabled {
			composer.placeholder_text.clone()
		} else {
			composer.draft.input_disabled_placeholder or { 'Input disabled.' }
		}
		write_render_text(mut buffer, textarea_rect.x, textarea_rect.y, textarea_rect.width, &placeholder, rat_style.Style.default().dim(), [])
		buffer.lines << placeholder
	}

	// Popups have exclusive ownership of the footer region and therefore suppress all footer hints.
	match composer.popups.active.kind {
		.command { composer.popups.active.command.render_ref(popup_rect, mut buffer) }
		.file { composer.popups.active.file.render_ref(popup_rect, mut buffer) }
		.skill { composer.popups.active.skill.render_ref(popup_rect, mut buffer) }
		.mention_v2 { composer.popups.active.mention_v2.render_ref(popup_rect, mut buffer) }
		.none { composer.render_footer(popup_rect, mut buffer) }
	}

	if composer.popups.active.kind == .none {
		if ignition := composer.effort_ignition {
			protected_top := if remote_images_rect.height == 0 {
				textarea_rect.y
			} else {
				remote_images_rect.y
			}
			protected := rat_layout.Rect{
				x:      composer_rect.x
				y:      protected_top
				width:  composer_rect.width
				height: textarea_rect.y + textarea_rect.height - protected_top
			}
			if !ignition.is_finished() && ignition.render(composer_rect, protected, mut buffer) {
				if yen := composer.frame_requester {
					yen.schedule_frame_in(33)
				}
			}
		}
	}
	if composer.astra_sparkle != none {
		composer.render_sparkle(composer_rect, composer.cursor_pos_with_textarea_right_reserve(area, textarea_right_reserve), mut buffer)
	}
}

fn (composer &ChatComposer) render_footer(area rat_layout.Rect, mut buffer rat_buffer.Buffer) {
	if area.height == 0 {
		return
	}
	props := composer.footer_props()
	show_cycle_hint := !props.is_task_running
		&& composer.footer.collaboration_mode_indicator != none
	show_shortcuts_hint := props.mode == .composer_empty && !composer.is_in_paste_burst()
	show_queue_hint := props.mode == .composer_has_draft && props.is_task_running
	if props.mode == .shortcut_overlay {
		render_footer_from_props(area, mut buffer, &props, composer.footer.collaboration_mode_indicator, show_cycle_hint, show_shortcuts_hint, show_queue_hint)
		return
	}
	// Both of these modes render the single-line footer style (with
	// either the shortcuts hint or the optional queue hint). We still
	// want the single-line collapse rules so the mode label can win over
	// the context indicator on narrow widths.
	if composer.render_collapsed_footer(area, &props, mut buffer) {
		return
	}
	status_line_active := uses_passive_footer_status_layout(&props)
	transition_visible := status_line_active && !composer.footer.flash_visible()
		&& composer.footer.hint_override == none
	mut transition_active := false
	mut left_line := rat_text.Line{}
	if query := composer.draft.textarea.vim_query_text() {
		search_text := 'search: ${query}'
		left_line = line_from_string(&search_text)
	} else if history_line := composer.history_search_footer_line() {
		left_line = history_line
	} else if composer.footer.flash_visible() {
		if flash := composer.footer.flash {
			left_line = flash.line
		}
	} else if hints := composer.footer.hint_override {
		hint_text := hints.map(it.join(' ')).join('  ')
		left_line = line_from_string(&hint_text)
	} else if status_line_active {
		if status := passive_footer_status_line(&props) {
			left_line = status
		}
		if transition := composer.effort_status_line_transition {
			if transition_visible && !transition.is_finished() {
				transition_active = true
				left_line = transition.render_line(left_line, area.width - min_u16(area.width, live_prefix_cols))
			}
		}
	} else {
		summary := if show_queue_hint {
			'Tab to queue'
		} else if show_shortcuts_hint {
			'? for shortcuts'
		} else {
			composer.footer_summary_line()
		}
		left_line = line_from_string(&summary)
	}
	available_width := int(area.width - min_u16(area.width, live_prefix_cols))
	left_line = truncate_line_with_ellipsis_if_overflow(left_line, available_width)
	mut right_line := rat_text.Line{}
	mut has_right := false
	if props.mode !in [.history_search, .quit_shortcut_reminder, .shortcut_overlay, .esc_hint] {
		if label := composer.footer.side_conversation_context_label {
			right_line = line_from_string(&label)
			has_right = true
		} else if shell_line := composer.shell_mode_footer_line() {
			right_line = shell_line
			has_right = true
		} else if !transition_active {
			if status_line_active {
				if mode_line := composer.mode_indicator_line(show_cycle_hint) {
					right_line = mode_line
					has_right = true
				}
			} else {
				right_line = composer.right_footer_line_with_context()
				has_right = true
			}
		}
	}
	right_text := right_line.spans.map(it.text).join('')
	right_width := u16(right_text.runes().len)
	mut left_text := left_line.spans.map(it.text).join('')
	if status_line_active && has_right {
		if max_left := max_left_width_for_right(area, right_width) {
			if left_text.runes().len > int(max_left) {
				left_line = truncate_line_with_ellipsis_if_overflow(left_line, int(max_left))
				left_text = left_line.spans.map(it.text).join('')
			}
		}
	}
	show_right := has_right && props.mode !in [.history_search, .quit_shortcut_reminder,
		.shortcut_overlay, .esc_hint] && can_show_left_with_context(area, u16(left_text.runes().len), right_width)
	render_footer_line(area, mut buffer, left_line)
	if show_right {
		render_context_right(area, mut buffer, right_line)
		buffer.lines << '${left_text}  ${right_text}'
	} else if left_text.len > 0 {
		buffer.lines << left_text
	}
	if url := composer.footer.status_line_hyperlink_url {
		if status_line_active && !composer.footer.flash_visible()
			&& composer.footer.hint_override == none {
			buffer.mark_hyperlink(area, url)
		}
	}
	if transition_active {
		if requester := composer.frame_requester {
			requester.schedule_frame_in(33)
		}
	}
}

// Preserve footer::SummaryLeft's collapse ladder while the sibling footer module is still a typed
// boundary. At each width the richer queue/mode label wins before less informative variants, and
// the context indicator is retained only at the source-defined collapse level.
fn (composer &ChatComposer) render_collapsed_footer(area rat_layout.Rect, props &FooterProps,
	mut buffer rat_buffer.Buffer) bool {
	if composer.history_search != none || composer.draft.textarea.vim_query_active()
		|| composer.footer.flash_visible() || composer.footer.hint_override != none
		|| uses_passive_footer_status_layout(props)
		|| composer.footer.side_conversation_context_label != none
		|| composer.shell_mode_footer_line() != none
		|| props.mode !in [.composer_empty, .composer_has_draft] {
		return false
	}
	right := composer.right_footer_line_with_context()
	right_text := right.spans.map(it.text).join('')
	plan := if mode := composer.footer.collaboration_mode_indicator {
		mode == .plan
	} else {
		false
	}
	mut left_text := ''
	mut show_right := right_text.len > 0
	if props.mode == .composer_empty {
		if plan {
			full := '? for shortcuts · Plan mode (shift+tab to cycle)'
			cycle := 'Plan mode (shift+tab to cycle)'
			if int(area.width) >= full.runes().len + right_text.runes().len + 5 {
				left_text = full
			} else if int(area.width) >= cycle.runes().len + right_text.runes().len + 5 {
				left_text = cycle
			} else if int(area.width) >= cycle.runes().len + 4 {
				left_text = cycle
				show_right = false
			} else {
				left_text = 'Plan mode'
				show_right = false
			}
		} else {
			left_text = '? for shortcuts'
			if int(area.width) < left_text.runes().len + right_text.runes().len + 5 {
				left_text = ''
			}
		}
	} else if props.is_task_running {
		full_queue := 'tab to queue message'
		short_queue := 'tab to queue'
		if plan {
			full := '${full_queue} · Plan mode'
			short := '${short_queue} · Plan mode'
			if int(area.width) >= full.runes().len + right_text.runes().len + 5 {
				left_text = full
			} else if int(area.width) >= short.runes().len + right_text.runes().len + 5 {
				left_text = short
			} else if int(area.width) >= full.runes().len + 4 {
				left_text = full
				show_right = false
			} else if int(area.width) >= short.runes().len + 4 {
				left_text = short
				show_right = false
			} else {
				left_text = 'Plan mode'
				show_right = false
			}
		} else if int(area.width) >= full_queue.runes().len + right_text.runes().len + 5 {
			left_text = full_queue
		} else if int(area.width) >= short_queue.runes().len + right_text.runes().len + 5 {
			left_text = short_queue
		} else if int(area.width) >= full_queue.runes().len + 4 {
			left_text = full_queue
			show_right = false
		} else {
			left_text = short_queue
			show_right = false
		}
	}
	if left_text.len > 0 {
		render_footer_line(area, mut buffer, rat_text.Line{
			spans: [
				rat_text.Span{ text: left_text, style: rat_style.Style.default().dim() },
			]
		})
	}
	if show_right {
		render_context_right(area, mut buffer, right)
	}
	if left_text.len > 0 || show_right {
		buffer.lines << if show_right { '${left_text}  ${right_text}' } else { left_text }
	}
	return true
}

fn (composer &ChatComposer) prompt_for_render() (rat_style.Style, string) {
	if !composer.draft.input_enabled {
		return rat_style.Style.default().dim(), '›'
	}
	if composer.draft.is_bash_mode {
		return rat_style.Style.default().light_red().bold(), '!'
	}
	if composer.luna_reserve_active {
		// Reserve keeps one arrow at every reasoning effort; only its foreground changes.
		return rat_style.Style.default().yellow().bold(), '›'
	}
	if tier := composer.effort_tier {
		charge := if ignition := composer.effort_ignition {
			ignition.charge_alpha()
		} else {
			f32(1.0)
		}
		return tier.prompt(charge)
	}
	return rat_style.Style.default().bold(), '›'
}

fn (composer &ChatComposer) search_highlights() []Highlight {
	mut result := []Highlight{}
	query := if search := composer.history_search {
		search.query
	} else if vim_query := composer.draft.textarea.vim_query_text() {
		vim_query
	} else {
		return result
	}
	if query.len == 0 {
		return result
	}
	text := composer.draft.textarea.text()
	for start in substring_occurrences(&text, &query) {
		result << Highlight{
			start: start
			end:   start + query.len
			style: rat_style.Style.default().add_modifier(rat_style.Modifier.reversed | rat_style.Modifier.bold)
		}
	}
	return result
}

fn write_wrapped_render_text(mut buffer rat_buffer.Buffer, area rat_layout.Rect, text &string,
	base_style rat_style.Style, highlights []Highlight) {
	if area.width == 0 || area.height == 0 {
		return
	}
	mut x := area.x
	mut y := area.y
	mut byte_offset := 0
	for value in text.runes() {
		if value == `\n` {
			x = area.x
			y++
			byte_offset++
			if y >= area.y + area.height {
				break
			}
			continue
		}
		if x >= area.x + area.width {
			x = area.x
			y++
		}
		if y >= area.y + area.height {
			break
		}
		mut cell_style := base_style
		for highlight in highlights {
			if byte_offset >= highlight.start && byte_offset < highlight.end {
				cell_style = highlight.style
				break
			}
		}
		buffer.put_cell(x, y, value.str(), cell_style)
		x++
		byte_offset += value.str().len
	}
}

fn write_render_text(mut buffer rat_buffer.Buffer, x u16, y u16, width u16, text &string,
	base_style rat_style.Style, highlights []Highlight) {
	write_wrapped_render_text(mut buffer, rat_layout.Rect{ x: x, y: y, width: width, height: 1 }, text, base_style, highlights)
}

fn (composer &ChatComposer) footer_summary_line() string {
	return match composer.footer_mode() {
		.shortcut_overlay { 'Shortcuts' }
		.quit_shortcut_reminder {
			'${composer.footer.quit_shortcut_key.display_label()} again to quit'
		}
		.esc_hint {
			if composer.footer.esc_backtrack_hint {
				'esc again to edit previous message'
			} else {
				'esc esc to edit previous message'
			}
		}
		.composer_has_draft {
			if composer.is_task_running { 'tab to queue' } else { '' }
		}
		.composer_empty { '? for shortcuts' }
		.history_search { 'reverse-i-search: ' }
	}
}

// --- Small target-file helpers used to express Rust adapters in V. ---

fn clone_pending_pastes(values &[]PendingPaste) []PendingPaste {
	return values.map(PendingPaste{ placeholder: it.placeholder.clone(), actual: it.actual.clone() })
}

struct TextOccurrence {
	start int
	text  string
}

fn substring_occurrences(text &string, needle &string) []int {
	mut starts := []int{}
	if needle.len == 0 {
		return starts
	}
	mut offset := 0
	for offset + needle.len <= text.len {
		relative := (*text)[offset..].index(*needle) or { break }
		start := offset + relative
		starts << start
		offset = start + needle.len
	}
	return starts
}

fn count_substring_occurrences(text &string, needle &string) int {
	return substring_occurrences(text, needle).len
}

fn ranges_overlap(a_start int, a_end int, b_start int, b_end int) bool {
	return a_start < b_end && b_start < a_end
}

fn fuzzy_match(candidate &string, query &string) bool {
	return codex_utils_fuzzy_match.fuzzy_match(candidate, query) != none
}

fn slash_command_from_name(name &string) ?slash_command.SlashCommand {
	parsed := slash_command.SlashCommand.from_str(name) or { return none }
	for item in slash_command.built_in_slash_commands() {
		if item.command == parsed {
			return parsed
		}
	}
	return none
}

fn (composer &ChatComposer) service_tier_for_name(name &string) ?ServiceTierCommand {
	if !composer.service_tier_commands_enabled {
		return none
	}
	for command in composer.service_tier_commands {
		if command.name == *name {
			return ServiceTierCommand{ id: command.id.clone(), name: command.name.clone(), description: command.description.clone() }
		}
	}
	return none
}

fn slash_command_catalog() []slash_command.SlashCommand {
	return slash_command.built_in_slash_commands().map(it.command)
}

fn catalog_has_fuzzy_match(filter &string) bool {
	for command in slash_command_catalog() {
		name := command.command()
		if fuzzy_match(&name, filter) {
			return true
		}
	}
	return false
}

fn line_from_string(text &string) rat_text.Line {
	return rat_text.Line{ spans: [rat_text.Span{ text: text.clone() }] }
}

fn (composer &ChatComposer) reset_footer_mode_after_activity() FooterMode {
	return if composer.is_empty() { .composer_empty } else { .composer_has_draft }
}

fn (mut composer ChatComposer) retain_present_pending_pastes() {
	text := composer.draft.textarea.text()
	composer.draft.pending_pastes = composer.draft.pending_pastes.filter(text.contains(it.placeholder))
}

fn (mut composer ChatComposer) restore_suppressed_submission(text string,
	elements []user_input.TextElement, images []string, bindings []MentionBinding,
	pending []PendingPaste) {
	composer.set_text_content_with_mention_bindings(text.clone(), elements, images, bindings)
	composer.draft.pending_pastes = pending
	composer.draft.textarea.set_cursor(text.len)
}

fn clamp_int(value int, low int, high int) int {
	return min_int(max_int(value, low), high)
}

fn is_utf8_continuation(value u8) bool {
	return value & 0xc0 == 0x80
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

fn min_u16(a u16, b u16) u16 {
	return if a < b { a } else { b }
}

fn rune_is_space(value rune) bool {
	return value in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `\u0085`, `\u00a0`, `\u1680`, `\u2000`,
		`\u2001`, `\u2002`, `\u2003`, `\u2004`, `\u2005`, `\u2006`, `\u2007`, `\u2008`, `\u2009`,
		`\u200a`, `\u2028`, `\u2029`, `\u202f`, `\u205f`, `\u3000`]
}

// Rust `str::trim_start`/`trim_end` use Unicode whitespace. V's byte-oriented trim helpers cannot
// preserve the byte offsets needed to rebase inline TextElement ranges, so these adapters walk
// scalar boundaries explicitly and return the necessarily owned V strings.
fn trim_left_unicode_whitespace(text &string) string {
	mut start := 0
	for value in text.runes() {
		if !rune_is_space(value) {
			break
		}
		start += value.str().len
	}
	return (*text)[start..].clone()
}

fn trim_right_unicode_whitespace(text &string) string {
	mut end := text.len
	for end > 0 {
		previous := previous_char_boundary(text, end)
		value := rune_at_byte(text, previous) or { break }
		if !rune_is_space(value) {
			break
		}
		end = previous
	}
	return (*text)[..end].clone()
}

fn trim_unicode_whitespace(text &string) string {
	left := trim_left_unicode_whitespace(text)
	return trim_right_unicode_whitespace(&left)
}
