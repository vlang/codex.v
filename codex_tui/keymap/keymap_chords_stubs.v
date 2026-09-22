module keymap

import codex_config.types
import codex_tui.key_hint
import crossterm.event
import tokio.time as tokio_time

// STUB: crate::keymap::chords.
//
// Bounded, context-aware two-stroke shortcuts for TUI actions.
//
// Single-event bindings remain in the ordinary runtime keymaps. A completed
// chord becomes an internal function-key token appended to the target action,
// so existing handlers remain the only action dispatch table.

// STUB: crate::keymap::chords::FIRST_DISPATCH_FUNCTION_KEY.
const first_dispatch_function_key = types.max_function_key + 1

// STUB: crate::keymap::chords::LAST_DISPATCH_FUNCTION_KEY.
const last_dispatch_function_key = u8(255)

// STUB: crate::keymap::chords::LIST_RESERVED_BINDINGS.
const list_reserved_bindings = [
	ReservedBinding{
		action:  'cancel'
		binding: key_hint.ctrl(event.KeyCode.char_key(`c`))
	},
	ReservedBinding{
		action:  'resume_picker.toggle_transcript'
		binding: key_hint.ctrl(event.KeyCode.char_key(`t`))
	},
	ReservedBinding{
		action:  'resume_picker.toggle_expansion'
		binding: key_hint.ctrl(event.KeyCode.char_key(`e`))
	},
	ReservedBinding{
		action:  'resume_picker.toggle_density'
		binding: key_hint.ctrl(event.KeyCode.char_key(`o`))
	},
]

// STUB: crate::keymap::chords::KEY_CHORD_TIMEOUT.
// Time allowed between the first and second strokes of a key chord, in nanoseconds.
pub const key_chord_timeout = i64(1_000_000_000) // secs: 1

// STUB: crate::keymap::chords::KeymapContextSet.
// Compact set of keymap contexts that share one active input path.
pub struct KeymapContextSet {
pub:
	bits u16
}

// STUB: crate::keymap::chords::KeymapContextSet::new.
pub fn KeymapContextSet.new(context KeymapContext) KeymapContextSet {
	return KeymapContextSet{
		bits: context_bit(context)
	}
}

// STUB: crate::keymap::chords::KeymapContextSet::with.
pub fn (set KeymapContextSet) with(context KeymapContext) KeymapContextSet {
	return KeymapContextSet{
		bits: set.bits | context_bit(context)
	}
}

// STUB: crate::keymap::chords::KeymapContextSet::contains.
pub fn (set KeymapContextSet) contains(context KeymapContext) bool {
	return set.bits & context_bit(context) != 0
}

// STUB: crate::keymap::chords::context_bit.
fn context_bit(context KeymapContext) u16 {
	shift := match context {
		.global { 0 }
		.chat { 1 }
		.composer { 2 }
		.editor { 3 }
		.vim_normal { 4 }
		.vim_operator { 5 }
		.vim_text_object { 6 }
		.pager { 7 }
		.list { 8 }
		.approval { 9 }
		.agents { 10 }
		.vim_search { 11 }
	}
	return u16(1) << shift
}

// STUB: crate::keymap::chords::KeyChord.
pub struct KeyChord {
pub:
	prefix     key_hint.KeyBinding
	completion key_hint.KeyBinding
}

// STUB: crate::keymap::chords::RuntimeChordBinding.
pub struct RuntimeChordBinding {
pub:
	action KeymapActionId
	chord  KeyChord
mut:
	spec string
}

// STUB: the `(KeymapActionId, Vec<String>)` pair stored by RuntimeChordKeymap::configured_specs.
struct ConfiguredActionSpecs {
	action KeymapActionId
mut:
	specs []string
}

// STUB: crate::keymap::chords::RuntimeChordKeymap.
// Chord bindings plus configured alternatives in declaration order.
//
// The Rust field and accessor are both named `configured_specs`; V forbids a method that shadows a
// field name, so the storage is renamed while the accessor keeps the source name.
pub struct RuntimeChordKeymap {
pub mut:
	bindings []RuntimeChordBinding
mut:
	configured_specs_by_action []ConfiguredActionSpecs
}

// STUB: the Rust type derives `Clone`; V has no automatic struct clone, so keymap.rs uses this
// source-shaped dependency helper at each `Arc::clone(&chords)` boundary until chords.rs is fully
// translated.
pub fn clone_runtime_chord_keymap(chords &RuntimeChordKeymap) RuntimeChordKeymap {
	mut bindings := []RuntimeChordBinding{cap: chords.bindings.len}
	for binding in chords.bindings {
		bindings << RuntimeChordBinding{
			action: KeymapActionId{
				context: binding.action.context
				action:  binding.action.action.clone()
			}
			chord:  binding.chord
			spec:   binding.spec.clone()
		}
	}
	mut configured_specs_by_action := []ConfiguredActionSpecs{cap: chords.configured_specs_by_action.len}
	for configured in chords.configured_specs_by_action {
		mut specs := []string{cap: configured.specs.len}
		for spec in configured.specs {
			specs << spec.clone()
		}
		configured_specs_by_action << ConfiguredActionSpecs{
			action: KeymapActionId{
				context: configured.action.context
				action:  configured.action.action.clone()
			}
			specs:  specs
		}
	}
	return RuntimeChordKeymap{
		bindings:                   bindings
		configured_specs_by_action: configured_specs_by_action
	}
}

// STUB: crate::keymap::chords::RuntimeChordKeymap::from_config.
pub fn RuntimeChordKeymap.from_config(resolved_keymap &types.TuiKeymap) !RuntimeChordKeymap {
	mut keymap_chords := RuntimeChordKeymap{}
	for action in keymap_action_ids() {
		configured := effective_configured_binding(resolved_keymap, &action) or { continue }
		mut configured_specs := []string{}
		for spec in configured.specs() {
			raw := spec.as_str()
			if raw in configured_specs {
				continue
			}
			if space_index := raw.index(' ') {
				prefix := raw[..space_index]
				completion := raw[space_index + 1..]
				invalid_binding := 'Invalid `${action.config_path()}` = `${raw}`. Use a single key such as `ctrl-a` or a two-stroke chord such as `ctrl-x ctrl-t`.'
				parsed_prefix := parse_keybinding(prefix) or { return error(invalid_binding) }
				parsed_completion := parse_keybinding(completion) or {
					return error(invalid_binding)
				}
				keymap_chords.bindings << RuntimeChordBinding{
					action: clone_keymap_action_id(&action)
					chord:  KeyChord{
						prefix:     normalize_chord_binding(parsed_prefix)
						completion: normalize_chord_binding(parsed_completion)
					}
					spec:   raw
				}
			}
			configured_specs << raw
		}
		keymap_chords.configured_specs_by_action << ConfiguredActionSpecs{
			action: action
			specs:  configured_specs
		}
	}

	g := key_hint.plain(event.KeyCode.char_key(`g`))
	jump_top := KeyChord{
		prefix:     g
		completion: g
	}
	for action in keymap_action_ids() {
		is_jump_top_action := (action.context == .vim_normal && action.action == 'jump_top')
			|| (action.context == .vim_operator && action.action == 'motion_jump_top')
		if !is_jump_top_action {
			continue
		}
		mut already_bound := false
		if _ := effective_configured_binding(resolved_keymap, &action) {
			already_bound = true
		}
		if !already_bound {
			for configured in keymap_chords.bindings {
				if action.context.overlaps(configured.action.context) && configured.chord == jump_top {
					already_bound = true
					break
				}
			}
		}
		if !already_bound {
			for configured in keymap_action_ids() {
				if !action.context.overlaps(configured.context) {
					continue
				}
				spec_set := effective_configured_binding(resolved_keymap, &configured) or { continue }
				for spec in spec_set.specs() {
					if binding := parse_keybinding(spec.as_str()) {
						if binding.parts() == g.parts() {
							already_bound = true
							break
						}
					}
				}
				if already_bound {
					break
				}
			}
		}
		if already_bound {
			continue
		}

		keymap_chords.bindings << RuntimeChordBinding{
			action: action
			chord:  jump_top
			spec:   'g g'
		}
	}
	return keymap_chords
}

// STUB: crate::keymap::chords::RuntimeChordKeymap::configured_specs.
pub fn (chords &RuntimeChordKeymap) configured_specs(action &KeymapActionId) ?[]string {
	for entry in chords.configured_specs_by_action {
		if entry.action == *action {
			return entry.specs.clone()
		}
	}
	return none
}

// STUB: crate::keymap::chords::RuntimeChordKeymap::primary_hint.
// Return the user's first configured shortcut without exposing dispatch tokens.
pub fn (chords &RuntimeChordKeymap) primary_hint(action &KeymapActionId, bindings &[]key_hint.KeyBinding) ?key_hint.ShortcutHint {
	if specs := chords.configured_specs(action) {
		if specs.len > 0 {
			spec := specs[0]
			if space_index := spec.index(' ') {
				prefix := parse_keybinding(spec[..space_index])?
				completion := parse_keybinding(spec[space_index + 1..])?
				return key_hint.ShortcutHint.chord(prefix, completion)
			}
			return key_hint.ShortcutHint.single(parse_keybinding(spec)?)
		}
	}

	if binding := primary_binding(bindings) {
		return key_hint.ShortcutHint.single(binding)
	}
	for binding in chords.bindings {
		if binding.action == *action {
			return key_hint.ShortcutHint.chord(binding.chord.prefix, binding.chord.completion)
		}
	}
	return none
}

// STUB: discriminants of the payload-bearing crate::keymap::chords::KeyChordMatch enum.
pub enum KeyChordMatchKind {
	pass_through
	pending
	completed
	cancelled
	ignored
}

// STUB: crate::keymap::chords::KeyChordMatch.
// Outcome of routing one physical key through the chord state machine.
//
// Rust carries the `Pending` and `Completed` payloads inside the enum; V keeps them in disjoint
// fields selected by `kind`.
pub struct KeyChordMatch {
pub:
	kind      KeyChordMatchKind
	pending   key_hint.KeyBinding
	completed event.KeyEvent
}

// STUB: crate::keymap::chords::KeyChordMatch::PassThrough.
pub fn KeyChordMatch.pass_through() KeyChordMatch {
	return KeyChordMatch{
		kind: .pass_through
	}
}

// STUB: crate::keymap::chords::KeyChordMatch::Pending.
pub fn KeyChordMatch.new_pending(prefix key_hint.KeyBinding) KeyChordMatch {
	return KeyChordMatch{
		kind:    .pending
		pending: prefix
	}
}

// STUB: crate::keymap::chords::KeyChordMatch::Completed.
pub fn KeyChordMatch.new_completed(dispatch event.KeyEvent) KeyChordMatch {
	return KeyChordMatch{
		kind:      .completed
		completed: dispatch
	}
}

// STUB: crate::keymap::chords::KeyChordMatch::Cancelled.
pub fn KeyChordMatch.cancelled() KeyChordMatch {
	return KeyChordMatch{
		kind: .cancelled
	}
}

// STUB: crate::keymap::chords::KeyChordMatch::Ignored.
pub fn KeyChordMatch.ignored() KeyChordMatch {
	return KeyChordMatch{
		kind: .ignored
	}
}

// STUB: crate::keymap::chords::PendingChord.
struct PendingChord {
	prefix     key_hint.KeyBinding
	contexts   KeymapContextSet
	started_at tokio_time.Instant
}

// STUB: crate::keymap::chords::KeyChordMatcher.
// Tracks one pending two-stroke chord without buffering ordinary input.
pub struct KeyChordMatcher {
mut:
	pending ?PendingChord
}

// STUB: crate::keymap::chords::KeyChordMatcher::is_pending.
pub fn (matcher &KeyChordMatcher) is_pending() bool {
	return matcher.pending != none
}

// STUB: crate::keymap::chords::KeyChordMatcher::cancel.
pub fn (mut matcher KeyChordMatcher) cancel() bool {
	if matcher.pending != none {
		matcher.pending = none
		return true
	}
	return false
}

// STUB: crate::keymap::chords::KeyChordMatcher::expire.
pub fn (mut matcher KeyChordMatcher) expire(contexts KeymapContextSet, now tokio_time.Instant) bool {
	if pending := matcher.pending {
		if pending.contexts != contexts
			|| now.saturating_duration_since(pending.started_at) >= key_chord_timeout {
			matcher.pending = none
			return true
		}
	}
	return false
}

// STUB: crate::keymap::chords::KeyChordMatcher::advance.
pub fn (mut matcher KeyChordMatcher) advance(key_event event.KeyEvent, resolved_keymap &RuntimeChordKeymap, contexts KeymapContextSet, now tokio_time.Instant) KeyChordMatch {
	if is_dispatch_token_event(key_event) {
		return KeyChordMatch.ignored()
	}

	matcher.expire(contexts, now)

	if matcher.pending != none && key_event.kind != .press {
		return KeyChordMatch.ignored()
	}
	if key_event.kind != .press {
		return KeyChordMatch.pass_through()
	}

	if pending := matcher.pending {
		matcher.pending = none
		if key_hint.plain(event.key_code_esc).is_press(key_event) {
			return KeyChordMatch.cancelled()
		}
		for binding in resolved_keymap.bindings {
			if contexts.contains(binding.action.context) && binding.chord.prefix == pending.prefix
				&& chord_stroke_matches(binding.chord.completion, key_event) {
				dispatch := dispatch_event(binding.action) or { return KeyChordMatch.ignored() }
				return KeyChordMatch.new_completed(dispatch)
			}
		}
	}

	for binding in resolved_keymap.bindings {
		if contexts.contains(binding.action.context)
			&& chord_stroke_matches(binding.chord.prefix, key_event) {
			prefix := binding.chord.prefix
			matcher.pending = PendingChord{
				prefix:     prefix
				contexts:   contexts
				started_at: now
			}
			return KeyChordMatch.new_pending(prefix)
		}
	}

	return KeyChordMatch.pass_through()
}

// STUB: crate::keymap::chords::install_dispatch_bindings.
pub fn install_dispatch_bindings(mut resolved_keymap RuntimeKeymap) ! {
	mut actions := []KeymapActionId{}
	for binding in resolved_keymap.chords.bindings {
		if binding.action !in actions {
			actions << clone_keymap_action_id(&binding.action)
		}
	}
	for action in actions {
		binding := dispatch_binding(action) or {
			return error('Cannot dispatch `${action.config_path()}`: the keymap action inventory exceeds ${int(last_dispatch_function_key) - int(first_dispatch_function_key) + 1} internal tokens.')
		}
		if !push_binding_for_action(mut resolved_keymap, action, binding) {
			return error('Cannot dispatch unknown keymap action `${action.config_path()}`.')
		}
	}
}

// STUB: crate::keymap::chords::dispatch_binding.
fn dispatch_binding(action &KeymapActionId) ?key_hint.KeyBinding {
	mut index := -1
	for candidate_index, candidate in keymap_action_ids() {
		if candidate == *action {
			index = candidate_index
			break
		}
	}
	if index < 0 {
		return none
	}
	function_key := int(first_dispatch_function_key) + index
	if function_key > int(last_dispatch_function_key) {
		return none
	}
	return key_hint.KeyBinding.new(event.KeyCode.function_key(u8(function_key)), event.key_modifiers_none)
}

// STUB: crate::keymap::chords::dispatch_event.
fn dispatch_event(action &KeymapActionId) ?event.KeyEvent {
	parts := dispatch_binding(action)?.parts()
	return event.KeyEvent.new(parts.code, parts.modifiers)
}

// STUB: crate::keymap::chords::is_dispatch_token.
pub fn is_dispatch_token(binding key_hint.KeyBinding) bool {
	parts := binding.parts()
	return parts.code.kind == .function && parts.code.f >= int(first_dispatch_function_key)
		&& parts.code.f <= int(last_dispatch_function_key)
}

// STUB: crate::keymap::chords::is_dispatch_token_event.
fn is_dispatch_token_event(input event.KeyEvent) bool {
	return input.code.kind == .function && input.code.f >= int(first_dispatch_function_key)
		&& input.code.f <= int(last_dispatch_function_key)
}

// STUB: crate::keymap::chords::chord_stroke_matches.
fn chord_stroke_matches(binding key_hint.KeyBinding, key_event event.KeyEvent) bool {
	ctrl_slash := key_hint.ctrl(event.KeyCode.char_key(`/`))
	ctrl_seven := key_hint.ctrl(event.KeyCode.char_key(`7`))

	return binding.is_press(key_event)
		|| (binding.parts() == ctrl_slash.parts() && ctrl_seven.is_press(key_event))
		|| (binding.parts() == ctrl_seven.parts() && ctrl_slash.is_press(key_event))
}

// STUB: crate::keymap::chords::effective_configured_binding.
fn effective_configured_binding(resolved_keymap &types.TuiKeymap, action &KeymapActionId) ?types.KeybindingsSpec {
	slot := configured_binding_for_action(resolved_keymap, action)?
	if configured := slot.spec {
		return configured
	}
	if action.context != .composer {
		return none
	}
	return match action.action {
		'submit' { resolved_keymap.global.submit }
		'queue' { resolved_keymap.global.queue }
		'toggle_shortcuts' { resolved_keymap.global.toggle_shortcuts }
		else { none }
	}
}

// STUB: crate::keymap::chords::normalize_chord_binding.
pub fn normalize_chord_binding(binding key_hint.KeyBinding) key_hint.KeyBinding {
	parts := binding.normalized_parts()
	normalized := key_hint.KeyBinding.new(parts.code, parts.modifiers)
	if normalized.parts() == key_hint.ctrl(event.KeyCode.char_key(`7`)).parts() {
		return key_hint.ctrl(event.KeyCode.char_key(`/`))
	}
	return normalized
}

// STUB: crate::keymap::chords::validate_chord_conflicts.
// Reject chords that would shadow an active single binding or fixed shortcut.
pub fn validate_chord_conflicts(resolved_keymap &RuntimeKeymap) ! {
	for index, binding in resolved_keymap.chords.bindings {
		validate_binding_shape(binding)!
		validate_reserved_strokes(binding)!

		for candidate in runtime_action_bindings(resolved_keymap) {
			if !binding.action.context.overlaps(candidate.id.context) {
				continue
			}
			mut shadows := false
			for single in candidate.bindings {
				if normalize_chord_binding(single).parts() == binding.chord.prefix.parts() {
					shadows = true
					break
				}
			}
			if shadows {
				return error('Ambiguous `${binding.action.config_path()}` = `${binding.spec}`: its prefix shadows `${candidate.id.config_path()}`. Unbind or remap the existing shortcut before using it as a chord prefix.')
			}
		}

		for previous in resolved_keymap.chords.bindings[..index] {
			if previous.action != binding.action
				&& previous.action.context.overlaps(binding.action.context)
				&& previous.chord == binding.chord {
				return error('Ambiguous `${binding.action.config_path()}` = `${binding.spec}`: the same chord is already assigned to `${previous.action.config_path()}`. Choose a unique chord and retry.')
			}
		}
	}
}

// STUB: crate::keymap::chords::validate_binding_shape.
fn validate_binding_shape(binding &RuntimeChordBinding) ! {
	path := binding.action.config_path()
	prefix := binding.chord.prefix.parts()

	if prefix.code.kind == .char_key && key_hint.is_altgr(prefix.modifiers)
		&& !binding.action.context.allows_plain_chord_prefix() {
		return error('Invalid `${path}` = `${binding.spec}`: a ctrl-alt character prefix may be AltGr text input on Windows. Choose a different chord and retry.')
	}

	if prefix.code.kind == .char_key && !key_hint.has_ctrl_or_alt(prefix.modifiers)
		&& !binding.action.context.allows_plain_chord_prefix() {
		return error('Invalid `${path}` = `${binding.spec}`: a chord prefix outside Vim must use ctrl, alt, or a non-character key so ordinary text input is not intercepted.')
	}
}

// STUB: crate::keymap::chords::validate_reserved_strokes.
fn validate_reserved_strokes(binding &RuntimeChordBinding) ! {
	path := binding.action.config_path()
	strokes := [
		binding.chord.prefix.parts(),
		binding.chord.completion.parts(),
	]

	esc_parts := key_hint.plain(event.key_code_esc).parts()
	if esc_parts in strokes {
		return error('Ambiguous `${path}` = `${binding.spec}`: plain `esc` is reserved for cancelling a pending chord.')
	}

	if binding.action.context == .agents
		&& binding.chord.prefix.parts() == key_hint.plain(event.key_code_backspace).parts() {
		return error('Invalid `${path}` = `${binding.spec}`: `backspace` is reserved for editing task input.')
	}

	// Rust guards this branch with `#[cfg(unix)]`; the V tree only targets Unix hosts today.
	if key_hint.ctrl(event.KeyCode.char_key(`z`)).parts() in strokes {
		return error('Ambiguous `${path}` = `${binding.spec}`: `ctrl-z` is reserved for suspending the terminal on Unix. Choose a different chord and retry.')
	}

	reserved := match binding.action.context {
		.pager {
			transcript_backtrack_reserved_bindings
		}
		.global, .chat, .composer, .editor, .vim_normal, .vim_operator, .vim_search,
		.vim_text_object {
			main_reserved_bindings
		}
		.list {
			list_reserved_bindings
		}
		.agents, .approval {
			list_reserved_bindings[..1]
		}
	}
	for entry in reserved {
		matches_prefix := binding.chord.prefix.parts() == entry.binding.parts()
		matches_completion := binding.chord.completion.parts() == entry.binding.parts()
			&& (binding.action.context != .list
				|| entry.binding.parts() == key_hint.ctrl(event.KeyCode.char_key(`c`)).parts())
		if matches_prefix || matches_completion {
			return error('Ambiguous `${path}` = `${binding.spec}`: the chord uses the key reserved by `${entry.action}`. Choose a different chord and retry.')
		}
	}
}
