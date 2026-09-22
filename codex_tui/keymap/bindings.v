module keymap

import codex_config.types
import codex_tui.key_hint

// Shared inventory of resolved runtime bindings.
//
// `/keymap` lookup and chord-prefix conflict detection must inspect the same
// actions. Declaring those actions once prevents a new binding from appearing
// in the picker while being silently omitted from chord validation.
//
// Rust generates every accessor below from one `define_runtime_action_bindings!` table. V has no
// macro expansion, so the same table is spelled out once per accessor in the same declaration
// order; `keymap_action_ids` order is load-bearing because `dispatch_binding` indexes into it.

// Config context in which a keymap action is active.
pub enum KeymapContext {
	global
	chat
	composer
	editor
	vim_normal
	vim_operator
	vim_search
	vim_text_object
	pager
	list
	agents
	approval
}

pub fn (context KeymapContext) config_name() string {
	return match context {
		.global { 'global' }
		.chat { 'chat' }
		.composer { 'composer' }
		.editor { 'editor' }
		.vim_normal { 'vim_normal' }
		.vim_operator { 'vim_operator' }
		.vim_search { 'vim_search' }
		.vim_text_object { 'vim_text_object' }
		.pager { 'pager' }
		.list { 'list' }
		.agents { 'agents' }
		.approval { 'approval' }
	}
}

pub fn (context KeymapContext) allows_plain_chord_prefix() bool {
	return context in [KeymapContext.vim_normal, .vim_operator, .vim_search, .vim_text_object]
}

pub fn (context KeymapContext) overlaps(other KeymapContext) bool {
	if context == other {
		return true
	}

	paired := (context == .vim_search && other in [KeymapContext.vim_normal, .vim_operator])
		|| (context in [KeymapContext.vim_normal, .vim_operator] && other == .vim_search)
		|| (context == .list && other == .approval) || (context == .approval && other == .list)
		|| (context == .list && other == .agents) || (context == .agents && other == .list)
		|| (context == .chat && other == .list) || (context == .list && other == .chat)
	return paired || (context.is_shared_main() && other.is_main_editor())
		|| (other.is_shared_main() && context.is_main_editor())
		|| (context.is_shared_main() && other.is_shared_main())
}

fn (context KeymapContext) is_shared_main() bool {
	return context in [KeymapContext.global, .chat, .composer]
}

fn (context KeymapContext) is_main_editor() bool {
	return context in [KeymapContext.editor, .vim_normal, .vim_operator, .vim_search, .vim_text_object]
}

// Stable identity for one configurable action.
pub struct KeymapActionId {
pub:
	context KeymapContext
	action  string
}

pub fn (action &KeymapActionId) config_path() string {
	return 'tui.keymap.${action.context.config_name()}.${action.action}'
}

// Rust derives `Clone` and `Copy` because the action name is `&'static str`; V represents the
// name as an owned string, so dependency call sites use this helper where a copied identity must be
// stored while the original remains live.
pub fn clone_keymap_action_id(action &KeymapActionId) KeymapActionId {
	return KeymapActionId{
		context: action.context
		action:  action.action.clone()
	}
}

// Rust borrows the resolved slice; V has no borrowed-slice struct field, so the bindings are copied
// out of the runtime keymap.
pub struct RuntimeActionBinding {
pub:
	id       KeymapActionId
	bindings []key_hint.KeyBinding
}

// Rust returns `Option<&Option<KeybindingsSpec>>`; V has no reliable borrowed nested-optional
// representation, so the outer "action is known" state is the optional return and the inner
// "action is configured" state is this owned field.
pub struct ConfiguredBindingSlot {
pub:
	spec ?types.KeybindingsSpec
}

// Resolve a config context/action pair to its runtime identity.
//
// Rust accepts borrowed `&str` values. V cannot borrow string literals as `&string`, so this
// translation accepts values and only compares them; callers clone an owned string when they need
// to retain it after the call under `-ownership`.
pub fn keymap_action_id(context string, action string) ?KeymapActionId {
	for candidate in keymap_action_ids() {
		if candidate.context.config_name() == context && candidate.action == action {
			return candidate
		}
	}
	return none
}

// Return the configured slot for one runtime action, including global fallbacks.
pub fn configured_binding_for_action(resolved_keymap &types.TuiKeymap, action &KeymapActionId) ?ConfiguredBindingSlot {
	context := action.context.config_name()
	if context == 'composer' && action.action == 'submit' && resolved_keymap.composer.submit == none {
		return ConfiguredBindingSlot{
			spec: resolved_keymap.global.submit
		}
	}
	if context == 'composer' && action.action == 'queue' && resolved_keymap.composer.queue == none {
		return ConfiguredBindingSlot{
			spec: resolved_keymap.global.queue
		}
	}
	if context == 'composer' && action.action == 'toggle_shortcuts'
		&& resolved_keymap.composer.toggle_shortcuts == none {
		return ConfiguredBindingSlot{
			spec: resolved_keymap.global.toggle_shortcuts
		}
	}
	match context {
		'global' {
			match action.action {
				'open_agents' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.open_agents
					}
				}
				'open_transcript' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.open_transcript
					}
				}
				'open_external_editor' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.open_external_editor
					}
				}
				'copy' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.copy
					}
				}
				'clear_terminal' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.clear_terminal
					}
				}
				'toggle_vim_mode' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.toggle_vim_mode
					}
				}
				'toggle_fast_mode' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.toggle_fast_mode
					}
				}
				'toggle_raw_output' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.toggle_raw_output
					}
				}
				'toggle_side_conversation' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.global.toggle_side_conversation
					}
				}
				else {
					return none
				}
			}
		}
		'chat' {
			match action.action {
				'interrupt_turn' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.interrupt_turn
					}
				}
				'decrease_reasoning_effort' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.decrease_reasoning_effort
					}
				}
				'increase_reasoning_effort' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.increase_reasoning_effort
					}
				}
				'previous_permission_mode' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.previous_permission_mode
					}
				}
				'next_permission_mode' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.next_permission_mode
					}
				}
				'edit_queued_message' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.edit_queued_message
					}
				}
				'prompt_stack_back' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.prompt_stack_back
					}
				}
				'skip_question' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.chat.skip_question
					}
				}
				else {
					return none
				}
			}
		}
		'composer' {
			match action.action {
				'submit' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.composer.submit
					}
				}
				'queue' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.composer.queue
					}
				}
				'toggle_shortcuts' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.composer.toggle_shortcuts
					}
				}
				'history_search_previous' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.composer.history_search_previous
					}
				}
				'history_search_next' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.composer.history_search_next
					}
				}
				else {
					return none
				}
			}
		}
		'editor' {
			match action.action {
				'insert_newline' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.insert_newline
					}
				}
				'move_left' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_left
					}
				}
				'move_right' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_right
					}
				}
				'move_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_up
					}
				}
				'move_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_down
					}
				}
				'move_word_left' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_word_left
					}
				}
				'move_word_right' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_word_right
					}
				}
				'move_line_start' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_line_start
					}
				}
				'move_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.move_line_end
					}
				}
				'delete_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.delete_backward
					}
				}
				'delete_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.delete_forward
					}
				}
				'delete_backward_word' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.delete_backward_word
					}
				}
				'delete_forward_word' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.delete_forward_word
					}
				}
				'kill_line_start' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.kill_line_start
					}
				}
				'kill_whole_line' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.kill_whole_line
					}
				}
				'kill_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.kill_line_end
					}
				}
				'yank' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.editor.yank
					}
				}
				else {
					return none
				}
			}
		}
		'vim_normal' {
			match action.action {
				'enter_insert' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.enter_insert
					}
				}
				'append_after_cursor' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.append_after_cursor
					}
				}
				'append_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.append_line_end
					}
				}
				'insert_line_start' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.insert_line_start
					}
				}
				'open_line_below' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.open_line_below
					}
				}
				'open_line_above' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.open_line_above
					}
				}
				'enter_replace_mode' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.enter_replace_mode
					}
				}
				'move_left' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_left
					}
				}
				'move_right' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_right
					}
				}
				'move_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_up
					}
				}
				'move_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_down
					}
				}
				'move_word_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_word_forward
					}
				}
				'move_word_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_word_backward
					}
				}
				'move_word_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_word_end
					}
				}
				'move_line_start' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_line_start
					}
				}
				'move_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.move_line_end
					}
				}
				'find_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.find_forward
					}
				}
				'find_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.find_backward
					}
				}
				'till_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.till_forward
					}
				}
				'till_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.till_backward
					}
				}
				'jump_top' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.jump_top
					}
				}
				'jump_bottom' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.jump_bottom
					}
				}
				'delete_char' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.delete_char
					}
				}
				'replace_char' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.replace_char
					}
				}
				'repeat_last_change' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.repeat_last_change
					}
				}
				'substitute_char' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.substitute_char
					}
				}
				'delete_to_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.delete_to_line_end
					}
				}
				'change_to_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.change_to_line_end
					}
				}
				'yank_line' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.yank_line
					}
				}
				'paste_after' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.paste_after
					}
				}
				'start_delete_operator' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.start_delete_operator
					}
				}
				'start_yank_operator' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.start_yank_operator
					}
				}
				'start_change_operator' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.start_change_operator
					}
				}
				'undo' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.undo
					}
				}
				'redo' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.redo
					}
				}
				'cancel_operator' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_normal.cancel_operator
					}
				}
				else {
					return none
				}
			}
		}
		'vim_search' {
			match action.action {
				'forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_search.forward
					}
				}
				'backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_search.backward
					}
				}
				'next' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_search.next
					}
				}
				'previous' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_search.previous
					}
				}
				else {
					return none
				}
			}
		}
		'vim_operator' {
			match action.action {
				'delete_line' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.delete_line
					}
				}
				'yank_line' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.yank_line
					}
				}
				'motion_left' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_left
					}
				}
				'motion_right' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_right
					}
				}
				'motion_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_up
					}
				}
				'motion_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_down
					}
				}
				'motion_word_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_word_forward
					}
				}
				'motion_word_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_word_backward
					}
				}
				'motion_word_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_word_end
					}
				}
				'motion_line_start' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_line_start
					}
				}
				'motion_line_end' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_line_end
					}
				}
				'motion_find_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_find_forward
					}
				}
				'motion_find_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_find_backward
					}
				}
				'motion_till_forward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_till_forward
					}
				}
				'motion_till_backward' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_till_backward
					}
				}
				'motion_jump_top' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_jump_top
					}
				}
				'motion_jump_bottom' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.motion_jump_bottom
					}
				}
				'select_inner_text_object' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.select_inner_text_object
					}
				}
				'select_around_text_object' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.select_around_text_object
					}
				}
				'cancel' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_operator.cancel
					}
				}
				else {
					return none
				}
			}
		}
		'vim_text_object' {
			match action.action {
				'word' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.word
					}
				}
				'big_word' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.big_word
					}
				}
				'parentheses' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.parentheses
					}
				}
				'brackets' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.brackets
					}
				}
				'braces' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.braces
					}
				}
				'double_quote' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.double_quote
					}
				}
				'single_quote' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.single_quote
					}
				}
				'backtick' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.backtick
					}
				}
				'cancel' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.vim_text_object.cancel
					}
				}
				else {
					return none
				}
			}
		}
		'pager' {
			match action.action {
				'scroll_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.scroll_up
					}
				}
				'scroll_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.scroll_down
					}
				}
				'page_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.page_up
					}
				}
				'page_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.page_down
					}
				}
				'half_page_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.half_page_up
					}
				}
				'half_page_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.half_page_down
					}
				}
				'jump_top' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.jump_top
					}
				}
				'jump_bottom' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.jump_bottom
					}
				}
				'close' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.close
					}
				}
				'close_transcript' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.pager.close_transcript
					}
				}
				else {
					return none
				}
			}
		}
		'list' {
			match action.action {
				'move_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.move_up
					}
				}
				'move_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.move_down
					}
				}
				'move_left' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.move_left
					}
				}
				'move_right' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.move_right
					}
				}
				'page_up' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.page_up
					}
				}
				'page_down' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.page_down
					}
				}
				'jump_top' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.jump_top
					}
				}
				'jump_bottom' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.jump_bottom
					}
				}
				'accept' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.accept
					}
				}
				'cancel' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.list.cancel
					}
				}
				else {
					return none
				}
			}
		}
		'agents' {
			match action.action {
				'resume' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.resume
					}
				}
				'search' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.search
					}
				}
				'new_task' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.new_task
					}
				}
				'rename' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.rename
					}
				}
				'stop' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.stop
					}
				}
				'toggle_grouping' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.agents.toggle_grouping
					}
				}
				else {
					return none
				}
			}
		}
		'approval' {
			match action.action {
				'open_fullscreen' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.open_fullscreen
					}
				}
				'open_thread' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.open_thread
					}
				}
				'approve' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.approve
					}
				}
				'approve_for_session' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.approve_for_session
					}
				}
				'approve_for_prefix' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.approve_for_prefix
					}
				}
				'deny' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.deny
					}
				}
				'decline' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.decline
					}
				}
				'cancel' {
					return ConfiguredBindingSlot{
						spec: resolved_keymap.approval.cancel
					}
				}
				else {
					return none
				}
			}
		}
		else {
			return none
		}
	}
}

// Iterate over every stable runtime action identity.
pub fn keymap_action_ids() []KeymapActionId {
	return [
		KeymapActionId{
			context: .global
			action:  'open_agents'
		},
		KeymapActionId{
			context: .global
			action:  'open_transcript'
		},
		KeymapActionId{
			context: .global
			action:  'open_external_editor'
		},
		KeymapActionId{
			context: .global
			action:  'copy'
		},
		KeymapActionId{
			context: .global
			action:  'clear_terminal'
		},
		KeymapActionId{
			context: .global
			action:  'toggle_vim_mode'
		},
		KeymapActionId{
			context: .global
			action:  'toggle_fast_mode'
		},
		KeymapActionId{
			context: .global
			action:  'toggle_raw_output'
		},
		KeymapActionId{
			context: .global
			action:  'toggle_side_conversation'
		},
		KeymapActionId{
			context: .chat
			action:  'interrupt_turn'
		},
		KeymapActionId{
			context: .chat
			action:  'decrease_reasoning_effort'
		},
		KeymapActionId{
			context: .chat
			action:  'increase_reasoning_effort'
		},
		KeymapActionId{
			context: .chat
			action:  'previous_permission_mode'
		},
		KeymapActionId{
			context: .chat
			action:  'next_permission_mode'
		},
		KeymapActionId{
			context: .chat
			action:  'edit_queued_message'
		},
		KeymapActionId{
			context: .chat
			action:  'prompt_stack_back'
		},
		KeymapActionId{
			context: .chat
			action:  'skip_question'
		},
		KeymapActionId{
			context: .composer
			action:  'submit'
		},
		KeymapActionId{
			context: .composer
			action:  'queue'
		},
		KeymapActionId{
			context: .composer
			action:  'toggle_shortcuts'
		},
		KeymapActionId{
			context: .composer
			action:  'history_search_previous'
		},
		KeymapActionId{
			context: .composer
			action:  'history_search_next'
		},
		KeymapActionId{
			context: .editor
			action:  'insert_newline'
		},
		KeymapActionId{
			context: .editor
			action:  'move_left'
		},
		KeymapActionId{
			context: .editor
			action:  'move_right'
		},
		KeymapActionId{
			context: .editor
			action:  'move_up'
		},
		KeymapActionId{
			context: .editor
			action:  'move_down'
		},
		KeymapActionId{
			context: .editor
			action:  'move_word_left'
		},
		KeymapActionId{
			context: .editor
			action:  'move_word_right'
		},
		KeymapActionId{
			context: .editor
			action:  'move_line_start'
		},
		KeymapActionId{
			context: .editor
			action:  'move_line_end'
		},
		KeymapActionId{
			context: .editor
			action:  'delete_backward'
		},
		KeymapActionId{
			context: .editor
			action:  'delete_forward'
		},
		KeymapActionId{
			context: .editor
			action:  'delete_backward_word'
		},
		KeymapActionId{
			context: .editor
			action:  'delete_forward_word'
		},
		KeymapActionId{
			context: .editor
			action:  'kill_line_start'
		},
		KeymapActionId{
			context: .editor
			action:  'kill_whole_line'
		},
		KeymapActionId{
			context: .editor
			action:  'kill_line_end'
		},
		KeymapActionId{
			context: .editor
			action:  'yank'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'enter_insert'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'append_after_cursor'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'append_line_end'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'insert_line_start'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'open_line_below'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'open_line_above'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'enter_replace_mode'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_left'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_right'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_up'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_down'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_word_forward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_word_backward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_word_end'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_line_start'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'move_line_end'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'find_forward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'find_backward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'till_forward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'till_backward'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'jump_top'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'jump_bottom'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'delete_char'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'replace_char'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'repeat_last_change'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'substitute_char'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'delete_to_line_end'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'change_to_line_end'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'yank_line'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'paste_after'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'start_delete_operator'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'start_yank_operator'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'start_change_operator'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'undo'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'redo'
		},
		KeymapActionId{
			context: .vim_normal
			action:  'cancel_operator'
		},
		KeymapActionId{
			context: .vim_search
			action:  'forward'
		},
		KeymapActionId{
			context: .vim_search
			action:  'backward'
		},
		KeymapActionId{
			context: .vim_search
			action:  'next'
		},
		KeymapActionId{
			context: .vim_search
			action:  'previous'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'delete_line'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'yank_line'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_left'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_right'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_up'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_down'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_word_forward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_word_backward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_word_end'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_line_start'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_line_end'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_find_forward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_find_backward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_till_forward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_till_backward'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_jump_top'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'motion_jump_bottom'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'select_inner_text_object'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'select_around_text_object'
		},
		KeymapActionId{
			context: .vim_operator
			action:  'cancel'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'word'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'big_word'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'parentheses'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'brackets'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'braces'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'double_quote'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'single_quote'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'backtick'
		},
		KeymapActionId{
			context: .vim_text_object
			action:  'cancel'
		},
		KeymapActionId{
			context: .pager
			action:  'scroll_up'
		},
		KeymapActionId{
			context: .pager
			action:  'scroll_down'
		},
		KeymapActionId{
			context: .pager
			action:  'page_up'
		},
		KeymapActionId{
			context: .pager
			action:  'page_down'
		},
		KeymapActionId{
			context: .pager
			action:  'half_page_up'
		},
		KeymapActionId{
			context: .pager
			action:  'half_page_down'
		},
		KeymapActionId{
			context: .pager
			action:  'jump_top'
		},
		KeymapActionId{
			context: .pager
			action:  'jump_bottom'
		},
		KeymapActionId{
			context: .pager
			action:  'close'
		},
		KeymapActionId{
			context: .pager
			action:  'close_transcript'
		},
		KeymapActionId{
			context: .list
			action:  'move_up'
		},
		KeymapActionId{
			context: .list
			action:  'move_down'
		},
		KeymapActionId{
			context: .list
			action:  'move_left'
		},
		KeymapActionId{
			context: .list
			action:  'move_right'
		},
		KeymapActionId{
			context: .list
			action:  'page_up'
		},
		KeymapActionId{
			context: .list
			action:  'page_down'
		},
		KeymapActionId{
			context: .list
			action:  'jump_top'
		},
		KeymapActionId{
			context: .list
			action:  'jump_bottom'
		},
		KeymapActionId{
			context: .list
			action:  'accept'
		},
		KeymapActionId{
			context: .list
			action:  'cancel'
		},
		KeymapActionId{
			context: .agents
			action:  'resume'
		},
		KeymapActionId{
			context: .agents
			action:  'search'
		},
		KeymapActionId{
			context: .agents
			action:  'new_task'
		},
		KeymapActionId{
			context: .agents
			action:  'rename'
		},
		KeymapActionId{
			context: .agents
			action:  'stop'
		},
		KeymapActionId{
			context: .agents
			action:  'toggle_grouping'
		},
		KeymapActionId{
			context: .approval
			action:  'open_fullscreen'
		},
		KeymapActionId{
			context: .approval
			action:  'open_thread'
		},
		KeymapActionId{
			context: .approval
			action:  'approve'
		},
		KeymapActionId{
			context: .approval
			action:  'approve_for_session'
		},
		KeymapActionId{
			context: .approval
			action:  'approve_for_prefix'
		},
		KeymapActionId{
			context: .approval
			action:  'deny'
		},
		KeymapActionId{
			context: .approval
			action:  'decline'
		},
		KeymapActionId{
			context: .approval
			action:  'cancel'
		},
	]
}

// Return resolved bindings for one stable config context and action.
// Rust returns a borrowed slice. V returns an owned array because it has no borrowed-slice return
// equivalent, leaving the runtime keymap reusable by the caller.
pub fn bindings_for_action(runtime_keymap &RuntimeKeymap, context string, action string) ?[]key_hint.KeyBinding {
	match context {
		'global' {
			match action {
				'open_agents' {
					return user_bindings(runtime_keymap.app.open_agents)
				}
				'open_transcript' {
					return user_bindings(runtime_keymap.app.open_transcript)
				}
				'open_external_editor' {
					return user_bindings(runtime_keymap.app.open_external_editor)
				}
				'copy' {
					return user_bindings(runtime_keymap.app.copy)
				}
				'clear_terminal' {
					return user_bindings(runtime_keymap.app.clear_terminal)
				}
				'toggle_vim_mode' {
					return user_bindings(runtime_keymap.app.toggle_vim_mode)
				}
				'toggle_fast_mode' {
					return user_bindings(runtime_keymap.app.toggle_fast_mode)
				}
				'toggle_raw_output' {
					return user_bindings(runtime_keymap.app.toggle_raw_output)
				}
				'toggle_side_conversation' {
					return user_bindings(runtime_keymap.app.toggle_side_conversation)
				}
				else {
					return none
				}
			}
		}
		'chat' {
			match action {
				'interrupt_turn' {
					return user_bindings(runtime_keymap.chat.interrupt_turn)
				}
				'decrease_reasoning_effort' {
					return user_bindings(runtime_keymap.chat.decrease_reasoning_effort)
				}
				'increase_reasoning_effort' {
					return user_bindings(runtime_keymap.chat.increase_reasoning_effort)
				}
				'previous_permission_mode' {
					return user_bindings(runtime_keymap.chat.previous_permission_mode)
				}
				'next_permission_mode' {
					return user_bindings(runtime_keymap.chat.next_permission_mode)
				}
				'edit_queued_message' {
					return user_bindings(runtime_keymap.chat.edit_queued_message)
				}
				'prompt_stack_back' {
					return user_bindings(runtime_keymap.chat.prompt_stack_back)
				}
				'skip_question' {
					return user_bindings(runtime_keymap.chat.skip_question)
				}
				else {
					return none
				}
			}
		}
		'composer' {
			match action {
				'submit' {
					return user_bindings(runtime_keymap.composer.submit)
				}
				'queue' {
					return user_bindings(runtime_keymap.composer.queue)
				}
				'toggle_shortcuts' {
					return user_bindings(runtime_keymap.composer.toggle_shortcuts)
				}
				'history_search_previous' {
					return user_bindings(runtime_keymap.composer.history_search_previous)
				}
				'history_search_next' {
					return user_bindings(runtime_keymap.composer.history_search_next)
				}
				else {
					return none
				}
			}
		}
		'editor' {
			match action {
				'insert_newline' {
					return user_bindings(runtime_keymap.editor.insert_newline)
				}
				'move_left' {
					return user_bindings(runtime_keymap.editor.move_left)
				}
				'move_right' {
					return user_bindings(runtime_keymap.editor.move_right)
				}
				'move_up' {
					return user_bindings(runtime_keymap.editor.move_up)
				}
				'move_down' {
					return user_bindings(runtime_keymap.editor.move_down)
				}
				'move_word_left' {
					return user_bindings(runtime_keymap.editor.move_word_left)
				}
				'move_word_right' {
					return user_bindings(runtime_keymap.editor.move_word_right)
				}
				'move_line_start' {
					return user_bindings(runtime_keymap.editor.move_line_start)
				}
				'move_line_end' {
					return user_bindings(runtime_keymap.editor.move_line_end)
				}
				'delete_backward' {
					return user_bindings(runtime_keymap.editor.delete_backward)
				}
				'delete_forward' {
					return user_bindings(runtime_keymap.editor.delete_forward)
				}
				'delete_backward_word' {
					return user_bindings(runtime_keymap.editor.delete_backward_word)
				}
				'delete_forward_word' {
					return user_bindings(runtime_keymap.editor.delete_forward_word)
				}
				'kill_line_start' {
					return user_bindings(runtime_keymap.editor.kill_line_start)
				}
				'kill_whole_line' {
					return user_bindings(runtime_keymap.editor.kill_whole_line)
				}
				'kill_line_end' {
					return user_bindings(runtime_keymap.editor.kill_line_end)
				}
				'yank' {
					return user_bindings(runtime_keymap.editor.yank)
				}
				else {
					return none
				}
			}
		}
		'vim_normal' {
			match action {
				'enter_insert' {
					return user_bindings(runtime_keymap.vim_normal.enter_insert)
				}
				'append_after_cursor' {
					return user_bindings(runtime_keymap.vim_normal.append_after_cursor)
				}
				'append_line_end' {
					return user_bindings(runtime_keymap.vim_normal.append_line_end)
				}
				'insert_line_start' {
					return user_bindings(runtime_keymap.vim_normal.insert_line_start)
				}
				'open_line_below' {
					return user_bindings(runtime_keymap.vim_normal.open_line_below)
				}
				'open_line_above' {
					return user_bindings(runtime_keymap.vim_normal.open_line_above)
				}
				'enter_replace_mode' {
					return user_bindings(runtime_keymap.vim_normal.enter_replace_mode)
				}
				'move_left' {
					return user_bindings(runtime_keymap.vim_normal.move_left)
				}
				'move_right' {
					return user_bindings(runtime_keymap.vim_normal.move_right)
				}
				'move_up' {
					return user_bindings(runtime_keymap.vim_normal.move_up)
				}
				'move_down' {
					return user_bindings(runtime_keymap.vim_normal.move_down)
				}
				'move_word_forward' {
					return user_bindings(runtime_keymap.vim_normal.move_word_forward)
				}
				'move_word_backward' {
					return user_bindings(runtime_keymap.vim_normal.move_word_backward)
				}
				'move_word_end' {
					return user_bindings(runtime_keymap.vim_normal.move_word_end)
				}
				'move_line_start' {
					return user_bindings(runtime_keymap.vim_normal.move_line_start)
				}
				'move_line_end' {
					return user_bindings(runtime_keymap.vim_normal.move_line_end)
				}
				'find_forward' {
					return user_bindings(runtime_keymap.vim_normal.find_forward)
				}
				'find_backward' {
					return user_bindings(runtime_keymap.vim_normal.find_backward)
				}
				'till_forward' {
					return user_bindings(runtime_keymap.vim_normal.till_forward)
				}
				'till_backward' {
					return user_bindings(runtime_keymap.vim_normal.till_backward)
				}
				'jump_top' {
					return user_bindings(runtime_keymap.vim_normal.jump_top)
				}
				'jump_bottom' {
					return user_bindings(runtime_keymap.vim_normal.jump_bottom)
				}
				'delete_char' {
					return user_bindings(runtime_keymap.vim_normal.delete_char)
				}
				'replace_char' {
					return user_bindings(runtime_keymap.vim_normal.replace_char)
				}
				'repeat_last_change' {
					return user_bindings(runtime_keymap.vim_normal.repeat_last_change)
				}
				'substitute_char' {
					return user_bindings(runtime_keymap.vim_normal.substitute_char)
				}
				'delete_to_line_end' {
					return user_bindings(runtime_keymap.vim_normal.delete_to_line_end)
				}
				'change_to_line_end' {
					return user_bindings(runtime_keymap.vim_normal.change_to_line_end)
				}
				'yank_line' {
					return user_bindings(runtime_keymap.vim_normal.yank_line)
				}
				'paste_after' {
					return user_bindings(runtime_keymap.vim_normal.paste_after)
				}
				'start_delete_operator' {
					return user_bindings(runtime_keymap.vim_normal.start_delete_operator)
				}
				'start_yank_operator' {
					return user_bindings(runtime_keymap.vim_normal.start_yank_operator)
				}
				'start_change_operator' {
					return user_bindings(runtime_keymap.vim_normal.start_change_operator)
				}
				'undo' {
					return user_bindings(runtime_keymap.vim_normal.undo)
				}
				'redo' {
					return user_bindings(runtime_keymap.vim_normal.redo)
				}
				'cancel_operator' {
					return user_bindings(runtime_keymap.vim_normal.cancel_operator)
				}
				else {
					return none
				}
			}
		}
		'vim_search' {
			match action {
				'forward' {
					return user_bindings(runtime_keymap.vim_search.forward)
				}
				'backward' {
					return user_bindings(runtime_keymap.vim_search.backward)
				}
				'next' {
					return user_bindings(runtime_keymap.vim_search.next)
				}
				'previous' {
					return user_bindings(runtime_keymap.vim_search.previous)
				}
				else {
					return none
				}
			}
		}
		'vim_operator' {
			match action {
				'delete_line' {
					return user_bindings(runtime_keymap.vim_operator.delete_line)
				}
				'yank_line' {
					return user_bindings(runtime_keymap.vim_operator.yank_line)
				}
				'motion_left' {
					return user_bindings(runtime_keymap.vim_operator.motion_left)
				}
				'motion_right' {
					return user_bindings(runtime_keymap.vim_operator.motion_right)
				}
				'motion_up' {
					return user_bindings(runtime_keymap.vim_operator.motion_up)
				}
				'motion_down' {
					return user_bindings(runtime_keymap.vim_operator.motion_down)
				}
				'motion_word_forward' {
					return user_bindings(runtime_keymap.vim_operator.motion_word_forward)
				}
				'motion_word_backward' {
					return user_bindings(runtime_keymap.vim_operator.motion_word_backward)
				}
				'motion_word_end' {
					return user_bindings(runtime_keymap.vim_operator.motion_word_end)
				}
				'motion_line_start' {
					return user_bindings(runtime_keymap.vim_operator.motion_line_start)
				}
				'motion_line_end' {
					return user_bindings(runtime_keymap.vim_operator.motion_line_end)
				}
				'motion_find_forward' {
					return user_bindings(runtime_keymap.vim_operator.motion_find_forward)
				}
				'motion_find_backward' {
					return user_bindings(runtime_keymap.vim_operator.motion_find_backward)
				}
				'motion_till_forward' {
					return user_bindings(runtime_keymap.vim_operator.motion_till_forward)
				}
				'motion_till_backward' {
					return user_bindings(runtime_keymap.vim_operator.motion_till_backward)
				}
				'motion_jump_top' {
					return user_bindings(runtime_keymap.vim_operator.motion_jump_top)
				}
				'motion_jump_bottom' {
					return user_bindings(runtime_keymap.vim_operator.motion_jump_bottom)
				}
				'select_inner_text_object' {
					return user_bindings(runtime_keymap.vim_operator.select_inner_text_object)
				}
				'select_around_text_object' {
					return user_bindings(runtime_keymap.vim_operator.select_around_text_object)
				}
				'cancel' {
					return user_bindings(runtime_keymap.vim_operator.cancel)
				}
				else {
					return none
				}
			}
		}
		'vim_text_object' {
			match action {
				'word' {
					return user_bindings(runtime_keymap.vim_text_object.word)
				}
				'big_word' {
					return user_bindings(runtime_keymap.vim_text_object.big_word)
				}
				'parentheses' {
					return user_bindings(runtime_keymap.vim_text_object.parentheses)
				}
				'brackets' {
					return user_bindings(runtime_keymap.vim_text_object.brackets)
				}
				'braces' {
					return user_bindings(runtime_keymap.vim_text_object.braces)
				}
				'double_quote' {
					return user_bindings(runtime_keymap.vim_text_object.double_quote)
				}
				'single_quote' {
					return user_bindings(runtime_keymap.vim_text_object.single_quote)
				}
				'backtick' {
					return user_bindings(runtime_keymap.vim_text_object.backtick)
				}
				'cancel' {
					return user_bindings(runtime_keymap.vim_text_object.cancel)
				}
				else {
					return none
				}
			}
		}
		'pager' {
			match action {
				'scroll_up' {
					return user_bindings(runtime_keymap.pager.scroll_up)
				}
				'scroll_down' {
					return user_bindings(runtime_keymap.pager.scroll_down)
				}
				'page_up' {
					return user_bindings(runtime_keymap.pager.page_up)
				}
				'page_down' {
					return user_bindings(runtime_keymap.pager.page_down)
				}
				'half_page_up' {
					return user_bindings(runtime_keymap.pager.half_page_up)
				}
				'half_page_down' {
					return user_bindings(runtime_keymap.pager.half_page_down)
				}
				'jump_top' {
					return user_bindings(runtime_keymap.pager.jump_top)
				}
				'jump_bottom' {
					return user_bindings(runtime_keymap.pager.jump_bottom)
				}
				'close' {
					return user_bindings(runtime_keymap.pager.close)
				}
				'close_transcript' {
					return user_bindings(runtime_keymap.pager.close_transcript)
				}
				else {
					return none
				}
			}
		}
		'list' {
			match action {
				'move_up' {
					return user_bindings(runtime_keymap.list.move_up)
				}
				'move_down' {
					return user_bindings(runtime_keymap.list.move_down)
				}
				'move_left' {
					return user_bindings(runtime_keymap.list.move_left)
				}
				'move_right' {
					return user_bindings(runtime_keymap.list.move_right)
				}
				'page_up' {
					return user_bindings(runtime_keymap.list.page_up)
				}
				'page_down' {
					return user_bindings(runtime_keymap.list.page_down)
				}
				'jump_top' {
					return user_bindings(runtime_keymap.list.jump_top)
				}
				'jump_bottom' {
					return user_bindings(runtime_keymap.list.jump_bottom)
				}
				'accept' {
					return user_bindings(runtime_keymap.list.accept)
				}
				'cancel' {
					return user_bindings(runtime_keymap.list.cancel)
				}
				else {
					return none
				}
			}
		}
		'agents' {
			match action {
				'resume' {
					return user_bindings(runtime_keymap.agents.resume)
				}
				'search' {
					return user_bindings(runtime_keymap.agents.search)
				}
				'new_task' {
					return user_bindings(runtime_keymap.agents.new_task)
				}
				'rename' {
					return user_bindings(runtime_keymap.agents.rename)
				}
				'stop' {
					return user_bindings(runtime_keymap.agents.stop)
				}
				'toggle_grouping' {
					return user_bindings(runtime_keymap.agents.toggle_grouping)
				}
				else {
					return none
				}
			}
		}
		'approval' {
			match action {
				'open_fullscreen' {
					return user_bindings(runtime_keymap.approval.open_fullscreen)
				}
				'open_thread' {
					return user_bindings(runtime_keymap.approval.open_thread)
				}
				'approve' {
					return user_bindings(runtime_keymap.approval.approve)
				}
				'approve_for_session' {
					return user_bindings(runtime_keymap.approval.approve_for_session)
				}
				'approve_for_prefix' {
					return user_bindings(runtime_keymap.approval.approve_for_prefix)
				}
				'deny' {
					return user_bindings(runtime_keymap.approval.deny)
				}
				'decline' {
					return user_bindings(runtime_keymap.approval.decline)
				}
				'cancel' {
					return user_bindings(runtime_keymap.approval.cancel)
				}
				else {
					return none
				}
			}
		}
		else {
			return none
		}
	}
}

// Append an internal dispatch binding to one resolved action.
pub fn push_binding_for_action(mut runtime_keymap RuntimeKeymap, action &KeymapActionId, binding key_hint.KeyBinding) bool {
	match action.context.config_name() {
		'global' {
			match action.action {
				'open_agents' {
					runtime_keymap.app.open_agents << binding
					return true
				}
				'open_transcript' {
					runtime_keymap.app.open_transcript << binding
					return true
				}
				'open_external_editor' {
					runtime_keymap.app.open_external_editor << binding
					return true
				}
				'copy' {
					runtime_keymap.app.copy << binding
					return true
				}
				'clear_terminal' {
					runtime_keymap.app.clear_terminal << binding
					return true
				}
				'toggle_vim_mode' {
					runtime_keymap.app.toggle_vim_mode << binding
					return true
				}
				'toggle_fast_mode' {
					runtime_keymap.app.toggle_fast_mode << binding
					return true
				}
				'toggle_raw_output' {
					runtime_keymap.app.toggle_raw_output << binding
					return true
				}
				'toggle_side_conversation' {
					runtime_keymap.app.toggle_side_conversation << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'chat' {
			match action.action {
				'interrupt_turn' {
					runtime_keymap.chat.interrupt_turn << binding
					return true
				}
				'decrease_reasoning_effort' {
					runtime_keymap.chat.decrease_reasoning_effort << binding
					return true
				}
				'increase_reasoning_effort' {
					runtime_keymap.chat.increase_reasoning_effort << binding
					return true
				}
				'previous_permission_mode' {
					runtime_keymap.chat.previous_permission_mode << binding
					return true
				}
				'next_permission_mode' {
					runtime_keymap.chat.next_permission_mode << binding
					return true
				}
				'edit_queued_message' {
					runtime_keymap.chat.edit_queued_message << binding
					return true
				}
				'prompt_stack_back' {
					runtime_keymap.chat.prompt_stack_back << binding
					return true
				}
				'skip_question' {
					runtime_keymap.chat.skip_question << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'composer' {
			match action.action {
				'submit' {
					runtime_keymap.composer.submit << binding
					return true
				}
				'queue' {
					runtime_keymap.composer.queue << binding
					return true
				}
				'toggle_shortcuts' {
					runtime_keymap.composer.toggle_shortcuts << binding
					return true
				}
				'history_search_previous' {
					runtime_keymap.composer.history_search_previous << binding
					return true
				}
				'history_search_next' {
					runtime_keymap.composer.history_search_next << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'editor' {
			match action.action {
				'insert_newline' {
					runtime_keymap.editor.insert_newline << binding
					return true
				}
				'move_left' {
					runtime_keymap.editor.move_left << binding
					return true
				}
				'move_right' {
					runtime_keymap.editor.move_right << binding
					return true
				}
				'move_up' {
					runtime_keymap.editor.move_up << binding
					return true
				}
				'move_down' {
					runtime_keymap.editor.move_down << binding
					return true
				}
				'move_word_left' {
					runtime_keymap.editor.move_word_left << binding
					return true
				}
				'move_word_right' {
					runtime_keymap.editor.move_word_right << binding
					return true
				}
				'move_line_start' {
					runtime_keymap.editor.move_line_start << binding
					return true
				}
				'move_line_end' {
					runtime_keymap.editor.move_line_end << binding
					return true
				}
				'delete_backward' {
					runtime_keymap.editor.delete_backward << binding
					return true
				}
				'delete_forward' {
					runtime_keymap.editor.delete_forward << binding
					return true
				}
				'delete_backward_word' {
					runtime_keymap.editor.delete_backward_word << binding
					return true
				}
				'delete_forward_word' {
					runtime_keymap.editor.delete_forward_word << binding
					return true
				}
				'kill_line_start' {
					runtime_keymap.editor.kill_line_start << binding
					return true
				}
				'kill_whole_line' {
					runtime_keymap.editor.kill_whole_line << binding
					return true
				}
				'kill_line_end' {
					runtime_keymap.editor.kill_line_end << binding
					return true
				}
				'yank' {
					runtime_keymap.editor.yank << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'vim_normal' {
			match action.action {
				'enter_insert' {
					runtime_keymap.vim_normal.enter_insert << binding
					return true
				}
				'append_after_cursor' {
					runtime_keymap.vim_normal.append_after_cursor << binding
					return true
				}
				'append_line_end' {
					runtime_keymap.vim_normal.append_line_end << binding
					return true
				}
				'insert_line_start' {
					runtime_keymap.vim_normal.insert_line_start << binding
					return true
				}
				'open_line_below' {
					runtime_keymap.vim_normal.open_line_below << binding
					return true
				}
				'open_line_above' {
					runtime_keymap.vim_normal.open_line_above << binding
					return true
				}
				'enter_replace_mode' {
					runtime_keymap.vim_normal.enter_replace_mode << binding
					return true
				}
				'move_left' {
					runtime_keymap.vim_normal.move_left << binding
					return true
				}
				'move_right' {
					runtime_keymap.vim_normal.move_right << binding
					return true
				}
				'move_up' {
					runtime_keymap.vim_normal.move_up << binding
					return true
				}
				'move_down' {
					runtime_keymap.vim_normal.move_down << binding
					return true
				}
				'move_word_forward' {
					runtime_keymap.vim_normal.move_word_forward << binding
					return true
				}
				'move_word_backward' {
					runtime_keymap.vim_normal.move_word_backward << binding
					return true
				}
				'move_word_end' {
					runtime_keymap.vim_normal.move_word_end << binding
					return true
				}
				'move_line_start' {
					runtime_keymap.vim_normal.move_line_start << binding
					return true
				}
				'move_line_end' {
					runtime_keymap.vim_normal.move_line_end << binding
					return true
				}
				'find_forward' {
					runtime_keymap.vim_normal.find_forward << binding
					return true
				}
				'find_backward' {
					runtime_keymap.vim_normal.find_backward << binding
					return true
				}
				'till_forward' {
					runtime_keymap.vim_normal.till_forward << binding
					return true
				}
				'till_backward' {
					runtime_keymap.vim_normal.till_backward << binding
					return true
				}
				'jump_top' {
					runtime_keymap.vim_normal.jump_top << binding
					return true
				}
				'jump_bottom' {
					runtime_keymap.vim_normal.jump_bottom << binding
					return true
				}
				'delete_char' {
					runtime_keymap.vim_normal.delete_char << binding
					return true
				}
				'replace_char' {
					runtime_keymap.vim_normal.replace_char << binding
					return true
				}
				'repeat_last_change' {
					runtime_keymap.vim_normal.repeat_last_change << binding
					return true
				}
				'substitute_char' {
					runtime_keymap.vim_normal.substitute_char << binding
					return true
				}
				'delete_to_line_end' {
					runtime_keymap.vim_normal.delete_to_line_end << binding
					return true
				}
				'change_to_line_end' {
					runtime_keymap.vim_normal.change_to_line_end << binding
					return true
				}
				'yank_line' {
					runtime_keymap.vim_normal.yank_line << binding
					return true
				}
				'paste_after' {
					runtime_keymap.vim_normal.paste_after << binding
					return true
				}
				'start_delete_operator' {
					runtime_keymap.vim_normal.start_delete_operator << binding
					return true
				}
				'start_yank_operator' {
					runtime_keymap.vim_normal.start_yank_operator << binding
					return true
				}
				'start_change_operator' {
					runtime_keymap.vim_normal.start_change_operator << binding
					return true
				}
				'undo' {
					runtime_keymap.vim_normal.undo << binding
					return true
				}
				'redo' {
					runtime_keymap.vim_normal.redo << binding
					return true
				}
				'cancel_operator' {
					runtime_keymap.vim_normal.cancel_operator << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'vim_search' {
			match action.action {
				'forward' {
					runtime_keymap.vim_search.forward << binding
					return true
				}
				'backward' {
					runtime_keymap.vim_search.backward << binding
					return true
				}
				'next' {
					runtime_keymap.vim_search.next << binding
					return true
				}
				'previous' {
					runtime_keymap.vim_search.previous << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'vim_operator' {
			match action.action {
				'delete_line' {
					runtime_keymap.vim_operator.delete_line << binding
					return true
				}
				'yank_line' {
					runtime_keymap.vim_operator.yank_line << binding
					return true
				}
				'motion_left' {
					runtime_keymap.vim_operator.motion_left << binding
					return true
				}
				'motion_right' {
					runtime_keymap.vim_operator.motion_right << binding
					return true
				}
				'motion_up' {
					runtime_keymap.vim_operator.motion_up << binding
					return true
				}
				'motion_down' {
					runtime_keymap.vim_operator.motion_down << binding
					return true
				}
				'motion_word_forward' {
					runtime_keymap.vim_operator.motion_word_forward << binding
					return true
				}
				'motion_word_backward' {
					runtime_keymap.vim_operator.motion_word_backward << binding
					return true
				}
				'motion_word_end' {
					runtime_keymap.vim_operator.motion_word_end << binding
					return true
				}
				'motion_line_start' {
					runtime_keymap.vim_operator.motion_line_start << binding
					return true
				}
				'motion_line_end' {
					runtime_keymap.vim_operator.motion_line_end << binding
					return true
				}
				'motion_find_forward' {
					runtime_keymap.vim_operator.motion_find_forward << binding
					return true
				}
				'motion_find_backward' {
					runtime_keymap.vim_operator.motion_find_backward << binding
					return true
				}
				'motion_till_forward' {
					runtime_keymap.vim_operator.motion_till_forward << binding
					return true
				}
				'motion_till_backward' {
					runtime_keymap.vim_operator.motion_till_backward << binding
					return true
				}
				'motion_jump_top' {
					runtime_keymap.vim_operator.motion_jump_top << binding
					return true
				}
				'motion_jump_bottom' {
					runtime_keymap.vim_operator.motion_jump_bottom << binding
					return true
				}
				'select_inner_text_object' {
					runtime_keymap.vim_operator.select_inner_text_object << binding
					return true
				}
				'select_around_text_object' {
					runtime_keymap.vim_operator.select_around_text_object << binding
					return true
				}
				'cancel' {
					runtime_keymap.vim_operator.cancel << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'vim_text_object' {
			match action.action {
				'word' {
					runtime_keymap.vim_text_object.word << binding
					return true
				}
				'big_word' {
					runtime_keymap.vim_text_object.big_word << binding
					return true
				}
				'parentheses' {
					runtime_keymap.vim_text_object.parentheses << binding
					return true
				}
				'brackets' {
					runtime_keymap.vim_text_object.brackets << binding
					return true
				}
				'braces' {
					runtime_keymap.vim_text_object.braces << binding
					return true
				}
				'double_quote' {
					runtime_keymap.vim_text_object.double_quote << binding
					return true
				}
				'single_quote' {
					runtime_keymap.vim_text_object.single_quote << binding
					return true
				}
				'backtick' {
					runtime_keymap.vim_text_object.backtick << binding
					return true
				}
				'cancel' {
					runtime_keymap.vim_text_object.cancel << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'pager' {
			match action.action {
				'scroll_up' {
					runtime_keymap.pager.scroll_up << binding
					return true
				}
				'scroll_down' {
					runtime_keymap.pager.scroll_down << binding
					return true
				}
				'page_up' {
					runtime_keymap.pager.page_up << binding
					return true
				}
				'page_down' {
					runtime_keymap.pager.page_down << binding
					return true
				}
				'half_page_up' {
					runtime_keymap.pager.half_page_up << binding
					return true
				}
				'half_page_down' {
					runtime_keymap.pager.half_page_down << binding
					return true
				}
				'jump_top' {
					runtime_keymap.pager.jump_top << binding
					return true
				}
				'jump_bottom' {
					runtime_keymap.pager.jump_bottom << binding
					return true
				}
				'close' {
					runtime_keymap.pager.close << binding
					return true
				}
				'close_transcript' {
					runtime_keymap.pager.close_transcript << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'list' {
			match action.action {
				'move_up' {
					runtime_keymap.list.move_up << binding
					return true
				}
				'move_down' {
					runtime_keymap.list.move_down << binding
					return true
				}
				'move_left' {
					runtime_keymap.list.move_left << binding
					return true
				}
				'move_right' {
					runtime_keymap.list.move_right << binding
					return true
				}
				'page_up' {
					runtime_keymap.list.page_up << binding
					return true
				}
				'page_down' {
					runtime_keymap.list.page_down << binding
					return true
				}
				'jump_top' {
					runtime_keymap.list.jump_top << binding
					return true
				}
				'jump_bottom' {
					runtime_keymap.list.jump_bottom << binding
					return true
				}
				'accept' {
					runtime_keymap.list.accept << binding
					return true
				}
				'cancel' {
					runtime_keymap.list.cancel << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'agents' {
			match action.action {
				'resume' {
					runtime_keymap.agents.resume << binding
					return true
				}
				'search' {
					runtime_keymap.agents.search << binding
					return true
				}
				'new_task' {
					runtime_keymap.agents.new_task << binding
					return true
				}
				'rename' {
					runtime_keymap.agents.rename << binding
					return true
				}
				'stop' {
					runtime_keymap.agents.stop << binding
					return true
				}
				'toggle_grouping' {
					runtime_keymap.agents.toggle_grouping << binding
					return true
				}
				else {
					return false
				}
			}
		}
		'approval' {
			match action.action {
				'open_fullscreen' {
					runtime_keymap.approval.open_fullscreen << binding
					return true
				}
				'open_thread' {
					runtime_keymap.approval.open_thread << binding
					return true
				}
				'approve' {
					runtime_keymap.approval.approve << binding
					return true
				}
				'approve_for_session' {
					runtime_keymap.approval.approve_for_session << binding
					return true
				}
				'approve_for_prefix' {
					runtime_keymap.approval.approve_for_prefix << binding
					return true
				}
				'deny' {
					runtime_keymap.approval.deny << binding
					return true
				}
				'decline' {
					runtime_keymap.approval.decline << binding
					return true
				}
				'cancel' {
					runtime_keymap.approval.cancel << binding
					return true
				}
				else {
					return false
				}
			}
		}
		else {
			return false
		}
	}
}

// Iterate over the same runtime bindings exposed to the keymap editor.
pub fn runtime_action_bindings(runtime_keymap &RuntimeKeymap) []RuntimeActionBinding {
	return [
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'open_agents'
			}
			bindings: user_bindings(runtime_keymap.app.open_agents)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'open_transcript'
			}
			bindings: user_bindings(runtime_keymap.app.open_transcript)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'open_external_editor'
			}
			bindings: user_bindings(runtime_keymap.app.open_external_editor)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'copy'
			}
			bindings: user_bindings(runtime_keymap.app.copy)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'clear_terminal'
			}
			bindings: user_bindings(runtime_keymap.app.clear_terminal)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'toggle_vim_mode'
			}
			bindings: user_bindings(runtime_keymap.app.toggle_vim_mode)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'toggle_fast_mode'
			}
			bindings: user_bindings(runtime_keymap.app.toggle_fast_mode)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'toggle_raw_output'
			}
			bindings: user_bindings(runtime_keymap.app.toggle_raw_output)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .global
				action:  'toggle_side_conversation'
			}
			bindings: user_bindings(runtime_keymap.app.toggle_side_conversation)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'interrupt_turn'
			}
			bindings: user_bindings(runtime_keymap.chat.interrupt_turn)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'decrease_reasoning_effort'
			}
			bindings: user_bindings(runtime_keymap.chat.decrease_reasoning_effort)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'increase_reasoning_effort'
			}
			bindings: user_bindings(runtime_keymap.chat.increase_reasoning_effort)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'previous_permission_mode'
			}
			bindings: user_bindings(runtime_keymap.chat.previous_permission_mode)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'next_permission_mode'
			}
			bindings: user_bindings(runtime_keymap.chat.next_permission_mode)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'edit_queued_message'
			}
			bindings: user_bindings(runtime_keymap.chat.edit_queued_message)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'prompt_stack_back'
			}
			bindings: user_bindings(runtime_keymap.chat.prompt_stack_back)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .chat
				action:  'skip_question'
			}
			bindings: user_bindings(runtime_keymap.chat.skip_question)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .composer
				action:  'submit'
			}
			bindings: user_bindings(runtime_keymap.composer.submit)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .composer
				action:  'queue'
			}
			bindings: user_bindings(runtime_keymap.composer.queue)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .composer
				action:  'toggle_shortcuts'
			}
			bindings: user_bindings(runtime_keymap.composer.toggle_shortcuts)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .composer
				action:  'history_search_previous'
			}
			bindings: user_bindings(runtime_keymap.composer.history_search_previous)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .composer
				action:  'history_search_next'
			}
			bindings: user_bindings(runtime_keymap.composer.history_search_next)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'insert_newline'
			}
			bindings: user_bindings(runtime_keymap.editor.insert_newline)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_left'
			}
			bindings: user_bindings(runtime_keymap.editor.move_left)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_right'
			}
			bindings: user_bindings(runtime_keymap.editor.move_right)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_up'
			}
			bindings: user_bindings(runtime_keymap.editor.move_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_down'
			}
			bindings: user_bindings(runtime_keymap.editor.move_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_word_left'
			}
			bindings: user_bindings(runtime_keymap.editor.move_word_left)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_word_right'
			}
			bindings: user_bindings(runtime_keymap.editor.move_word_right)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_line_start'
			}
			bindings: user_bindings(runtime_keymap.editor.move_line_start)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'move_line_end'
			}
			bindings: user_bindings(runtime_keymap.editor.move_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'delete_backward'
			}
			bindings: user_bindings(runtime_keymap.editor.delete_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'delete_forward'
			}
			bindings: user_bindings(runtime_keymap.editor.delete_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'delete_backward_word'
			}
			bindings: user_bindings(runtime_keymap.editor.delete_backward_word)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'delete_forward_word'
			}
			bindings: user_bindings(runtime_keymap.editor.delete_forward_word)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'kill_line_start'
			}
			bindings: user_bindings(runtime_keymap.editor.kill_line_start)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'kill_whole_line'
			}
			bindings: user_bindings(runtime_keymap.editor.kill_whole_line)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'kill_line_end'
			}
			bindings: user_bindings(runtime_keymap.editor.kill_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .editor
				action:  'yank'
			}
			bindings: user_bindings(runtime_keymap.editor.yank)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'enter_insert'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.enter_insert)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'append_after_cursor'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.append_after_cursor)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'append_line_end'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.append_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'insert_line_start'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.insert_line_start)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'open_line_below'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.open_line_below)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'open_line_above'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.open_line_above)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'enter_replace_mode'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.enter_replace_mode)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_left'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_left)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_right'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_right)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_up'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_down'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_word_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_word_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_word_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_word_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_word_end'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_word_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_line_start'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_line_start)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'move_line_end'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.move_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'find_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.find_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'find_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.find_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'till_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.till_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'till_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.till_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'jump_top'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.jump_top)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'jump_bottom'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.jump_bottom)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'delete_char'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.delete_char)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'replace_char'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.replace_char)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'repeat_last_change'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.repeat_last_change)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'substitute_char'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.substitute_char)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'delete_to_line_end'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.delete_to_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'change_to_line_end'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.change_to_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'yank_line'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.yank_line)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'paste_after'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.paste_after)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'start_delete_operator'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.start_delete_operator)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'start_yank_operator'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.start_yank_operator)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'start_change_operator'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.start_change_operator)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'undo'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.undo)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'redo'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.redo)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_normal
				action:  'cancel_operator'
			}
			bindings: user_bindings(runtime_keymap.vim_normal.cancel_operator)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_search
				action:  'forward'
			}
			bindings: user_bindings(runtime_keymap.vim_search.forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_search
				action:  'backward'
			}
			bindings: user_bindings(runtime_keymap.vim_search.backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_search
				action:  'next'
			}
			bindings: user_bindings(runtime_keymap.vim_search.next)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_search
				action:  'previous'
			}
			bindings: user_bindings(runtime_keymap.vim_search.previous)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'delete_line'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.delete_line)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'yank_line'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.yank_line)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_left'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_left)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_right'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_right)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_up'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_down'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_word_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_word_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_word_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_word_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_word_end'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_word_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_line_start'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_line_start)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_line_end'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_line_end)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_find_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_find_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_find_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_find_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_till_forward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_till_forward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_till_backward'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_till_backward)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_jump_top'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_jump_top)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'motion_jump_bottom'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.motion_jump_bottom)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'select_inner_text_object'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.select_inner_text_object)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'select_around_text_object'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.select_around_text_object)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_operator
				action:  'cancel'
			}
			bindings: user_bindings(runtime_keymap.vim_operator.cancel)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'word'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.word)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'big_word'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.big_word)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'parentheses'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.parentheses)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'brackets'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.brackets)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'braces'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.braces)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'double_quote'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.double_quote)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'single_quote'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.single_quote)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'backtick'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.backtick)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .vim_text_object
				action:  'cancel'
			}
			bindings: user_bindings(runtime_keymap.vim_text_object.cancel)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'scroll_up'
			}
			bindings: user_bindings(runtime_keymap.pager.scroll_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'scroll_down'
			}
			bindings: user_bindings(runtime_keymap.pager.scroll_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'page_up'
			}
			bindings: user_bindings(runtime_keymap.pager.page_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'page_down'
			}
			bindings: user_bindings(runtime_keymap.pager.page_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'half_page_up'
			}
			bindings: user_bindings(runtime_keymap.pager.half_page_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'half_page_down'
			}
			bindings: user_bindings(runtime_keymap.pager.half_page_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'jump_top'
			}
			bindings: user_bindings(runtime_keymap.pager.jump_top)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'jump_bottom'
			}
			bindings: user_bindings(runtime_keymap.pager.jump_bottom)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'close'
			}
			bindings: user_bindings(runtime_keymap.pager.close)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .pager
				action:  'close_transcript'
			}
			bindings: user_bindings(runtime_keymap.pager.close_transcript)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'move_up'
			}
			bindings: user_bindings(runtime_keymap.list.move_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'move_down'
			}
			bindings: user_bindings(runtime_keymap.list.move_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'move_left'
			}
			bindings: user_bindings(runtime_keymap.list.move_left)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'move_right'
			}
			bindings: user_bindings(runtime_keymap.list.move_right)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'page_up'
			}
			bindings: user_bindings(runtime_keymap.list.page_up)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'page_down'
			}
			bindings: user_bindings(runtime_keymap.list.page_down)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'jump_top'
			}
			bindings: user_bindings(runtime_keymap.list.jump_top)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'jump_bottom'
			}
			bindings: user_bindings(runtime_keymap.list.jump_bottom)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'accept'
			}
			bindings: user_bindings(runtime_keymap.list.accept)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .list
				action:  'cancel'
			}
			bindings: user_bindings(runtime_keymap.list.cancel)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'resume'
			}
			bindings: user_bindings(runtime_keymap.agents.resume)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'search'
			}
			bindings: user_bindings(runtime_keymap.agents.search)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'new_task'
			}
			bindings: user_bindings(runtime_keymap.agents.new_task)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'rename'
			}
			bindings: user_bindings(runtime_keymap.agents.rename)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'stop'
			}
			bindings: user_bindings(runtime_keymap.agents.stop)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .agents
				action:  'toggle_grouping'
			}
			bindings: user_bindings(runtime_keymap.agents.toggle_grouping)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'open_fullscreen'
			}
			bindings: user_bindings(runtime_keymap.approval.open_fullscreen)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'open_thread'
			}
			bindings: user_bindings(runtime_keymap.approval.open_thread)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'approve'
			}
			bindings: user_bindings(runtime_keymap.approval.approve)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'approve_for_session'
			}
			bindings: user_bindings(runtime_keymap.approval.approve_for_session)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'approve_for_prefix'
			}
			bindings: user_bindings(runtime_keymap.approval.approve_for_prefix)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'deny'
			}
			bindings: user_bindings(runtime_keymap.approval.deny)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'decline'
			}
			bindings: user_bindings(runtime_keymap.approval.decline)
		},
		RuntimeActionBinding{
			id:       KeymapActionId{
				context: .approval
				action:  'cancel'
			}
			bindings: user_bindings(runtime_keymap.approval.cancel)
		},
	]
}
