module types

// STUB: config/src/tui_keymap.rs::KeybindingSpec derived Clone at LocalSettings config boundaries.
pub fn (value &KeybindingSpec) clone() KeybindingSpec {
	return KeybindingSpec{
		value: value.value.clone()
	}
}

// STUB: config/src/tui_keymap.rs::KeybindingsSpec derived Clone at LocalSettings config boundaries.
pub fn (value &KeybindingsSpec) clone() KeybindingsSpec {
	return KeybindingsSpec{
		kind: value.kind
		one:  value.one.clone()
		many: clone_local_settings_keybinding_specs(&value.many)
	}
}

// STUB: config/src/tui_keymap.rs::TuiGlobalKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiGlobalKeymap) clone() TuiGlobalKeymap {
	return TuiGlobalKeymap{
		open_agents:              if item := value.open_agents { item.clone() } else { none }
		open_transcript:          if item := value.open_transcript { item.clone() } else { none }
		open_external_editor:     if item := value.open_external_editor {
			item.clone()
		} else {
			none
		}
		copy:                     if item := value.copy { item.clone() } else { none }
		clear_terminal:           if item := value.clear_terminal { item.clone() } else { none }
		submit:                   if item := value.submit { item.clone() } else { none }
		queue:                    if item := value.queue { item.clone() } else { none }
		toggle_shortcuts:         if item := value.toggle_shortcuts { item.clone() } else { none }
		toggle_vim_mode:          if item := value.toggle_vim_mode { item.clone() } else { none }
		toggle_fast_mode:         if item := value.toggle_fast_mode { item.clone() } else { none }
		toggle_raw_output:        if item := value.toggle_raw_output { item.clone() } else { none }
		toggle_side_conversation: if item := value.toggle_side_conversation {
			item.clone()
		} else {
			none
		}
	}
}

// STUB: config/src/tui_keymap.rs::TuiChatKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiChatKeymap) clone() TuiChatKeymap {
	return TuiChatKeymap{
		toggle_voice_mute:         if item := value.toggle_voice_mute { item.clone() } else { none }
		interrupt_turn:            if item := value.interrupt_turn { item.clone() } else { none }
		decrease_reasoning_effort: if item := value.decrease_reasoning_effort {
			item.clone()
		} else {
			none
		}
		increase_reasoning_effort: if item := value.increase_reasoning_effort {
			item.clone()
		} else {
			none
		}
		previous_permission_mode:  if item := value.previous_permission_mode {
			item.clone()
		} else {
			none
		}
		next_permission_mode:      if item := value.next_permission_mode {
			item.clone()
		} else {
			none
		}
		edit_queued_message:       if item := value.edit_queued_message {
			item.clone()
		} else {
			none
		}
		prompt_stack_back:         if item := value.prompt_stack_back { item.clone() } else { none }
		skip_question:             if item := value.skip_question { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiComposerKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiComposerKeymap) clone() TuiComposerKeymap {
	return TuiComposerKeymap{
		submit:                  if item := value.submit { item.clone() } else { none }
		queue:                   if item := value.queue { item.clone() } else { none }
		toggle_shortcuts:        if item := value.toggle_shortcuts { item.clone() } else { none }
		history_search_previous: if item := value.history_search_previous {
			item.clone()
		} else {
			none
		}
		history_search_next:     if item := value.history_search_next { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiEditorKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiEditorKeymap) clone() TuiEditorKeymap {
	return TuiEditorKeymap{
		insert_newline:       if item := value.insert_newline { item.clone() } else { none }
		move_left:            if item := value.move_left { item.clone() } else { none }
		move_right:           if item := value.move_right { item.clone() } else { none }
		move_up:              if item := value.move_up { item.clone() } else { none }
		move_down:            if item := value.move_down { item.clone() } else { none }
		move_word_left:       if item := value.move_word_left { item.clone() } else { none }
		move_word_right:      if item := value.move_word_right { item.clone() } else { none }
		move_line_start:      if item := value.move_line_start { item.clone() } else { none }
		move_line_end:        if item := value.move_line_end { item.clone() } else { none }
		delete_backward:      if item := value.delete_backward { item.clone() } else { none }
		delete_forward:       if item := value.delete_forward { item.clone() } else { none }
		delete_backward_word: if item := value.delete_backward_word { item.clone() } else { none }
		delete_forward_word:  if item := value.delete_forward_word { item.clone() } else { none }
		kill_line_start:      if item := value.kill_line_start { item.clone() } else { none }
		kill_whole_line:      if item := value.kill_whole_line { item.clone() } else { none }
		kill_line_end:        if item := value.kill_line_end { item.clone() } else { none }
		yank:                 if item := value.yank { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiVimNormalKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiVimNormalKeymap) clone() TuiVimNormalKeymap {
	return TuiVimNormalKeymap{
		enter_insert:          if item := value.enter_insert { item.clone() } else { none }
		append_after_cursor:   if item := value.append_after_cursor { item.clone() } else { none }
		append_line_end:       if item := value.append_line_end { item.clone() } else { none }
		insert_line_start:     if item := value.insert_line_start { item.clone() } else { none }
		open_line_below:       if item := value.open_line_below { item.clone() } else { none }
		open_line_above:       if item := value.open_line_above { item.clone() } else { none }
		enter_replace_mode:    if item := value.enter_replace_mode { item.clone() } else { none }
		move_left:             if item := value.move_left { item.clone() } else { none }
		move_right:            if item := value.move_right { item.clone() } else { none }
		move_up:               if item := value.move_up { item.clone() } else { none }
		move_down:             if item := value.move_down { item.clone() } else { none }
		move_word_forward:     if item := value.move_word_forward { item.clone() } else { none }
		move_word_backward:    if item := value.move_word_backward { item.clone() } else { none }
		move_word_end:         if item := value.move_word_end { item.clone() } else { none }
		move_line_start:       if item := value.move_line_start { item.clone() } else { none }
		move_line_end:         if item := value.move_line_end { item.clone() } else { none }
		find_forward:          if item := value.find_forward { item.clone() } else { none }
		find_backward:         if item := value.find_backward { item.clone() } else { none }
		till_forward:          if item := value.till_forward { item.clone() } else { none }
		till_backward:         if item := value.till_backward { item.clone() } else { none }
		jump_top:              if item := value.jump_top { item.clone() } else { none }
		jump_bottom:           if item := value.jump_bottom { item.clone() } else { none }
		delete_char:           if item := value.delete_char { item.clone() } else { none }
		replace_char:          if item := value.replace_char { item.clone() } else { none }
		repeat_last_change:    if item := value.repeat_last_change { item.clone() } else { none }
		substitute_char:       if item := value.substitute_char { item.clone() } else { none }
		delete_to_line_end:    if item := value.delete_to_line_end { item.clone() } else { none }
		change_to_line_end:    if item := value.change_to_line_end { item.clone() } else { none }
		yank_line:             if item := value.yank_line { item.clone() } else { none }
		paste_after:           if item := value.paste_after { item.clone() } else { none }
		start_delete_operator: if item := value.start_delete_operator { item.clone() } else { none }
		start_yank_operator:   if item := value.start_yank_operator { item.clone() } else { none }
		start_change_operator: if item := value.start_change_operator { item.clone() } else { none }
		undo:                  if item := value.undo { item.clone() } else { none }
		redo:                  if item := value.redo { item.clone() } else { none }
		cancel_operator:       if item := value.cancel_operator { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiVimOperatorKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiVimOperatorKeymap) clone() TuiVimOperatorKeymap {
	return TuiVimOperatorKeymap{
		delete_line:               if item := value.delete_line { item.clone() } else { none }
		yank_line:                 if item := value.yank_line { item.clone() } else { none }
		motion_left:               if item := value.motion_left { item.clone() } else { none }
		motion_right:              if item := value.motion_right { item.clone() } else { none }
		motion_up:                 if item := value.motion_up { item.clone() } else { none }
		motion_down:               if item := value.motion_down { item.clone() } else { none }
		motion_word_forward:       if item := value.motion_word_forward {
			item.clone()
		} else {
			none
		}
		motion_word_backward:      if item := value.motion_word_backward {
			item.clone()
		} else {
			none
		}
		motion_word_end:           if item := value.motion_word_end { item.clone() } else { none }
		motion_line_start:         if item := value.motion_line_start { item.clone() } else { none }
		motion_line_end:           if item := value.motion_line_end { item.clone() } else { none }
		motion_find_forward:       if item := value.motion_find_forward {
			item.clone()
		} else {
			none
		}
		motion_find_backward:      if item := value.motion_find_backward {
			item.clone()
		} else {
			none
		}
		motion_till_forward:       if item := value.motion_till_forward {
			item.clone()
		} else {
			none
		}
		motion_till_backward:      if item := value.motion_till_backward {
			item.clone()
		} else {
			none
		}
		motion_jump_top:           if item := value.motion_jump_top { item.clone() } else { none }
		motion_jump_bottom:        if item := value.motion_jump_bottom {
			item.clone()
		} else {
			none
		}
		select_inner_text_object:  if item := value.select_inner_text_object {
			item.clone()
		} else {
			none
		}
		select_around_text_object: if item := value.select_around_text_object {
			item.clone()
		} else {
			none
		}
		cancel:                    if item := value.cancel { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiVimSearchKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiVimSearchKeymap) clone() TuiVimSearchKeymap {
	return TuiVimSearchKeymap{
		forward:  if item := value.forward { item.clone() } else { none }
		backward: if item := value.backward { item.clone() } else { none }
		next:     if item := value.next { item.clone() } else { none }
		previous: if item := value.previous { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiVimTextObjectKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiVimTextObjectKeymap) clone() TuiVimTextObjectKeymap {
	return TuiVimTextObjectKeymap{
		word:         if item := value.word { item.clone() } else { none }
		big_word:     if item := value.big_word { item.clone() } else { none }
		parentheses:  if item := value.parentheses { item.clone() } else { none }
		brackets:     if item := value.brackets { item.clone() } else { none }
		braces:       if item := value.braces { item.clone() } else { none }
		double_quote: if item := value.double_quote { item.clone() } else { none }
		single_quote: if item := value.single_quote { item.clone() } else { none }
		backtick:     if item := value.backtick { item.clone() } else { none }
		cancel:       if item := value.cancel { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiPagerKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiPagerKeymap) clone() TuiPagerKeymap {
	return TuiPagerKeymap{
		scroll_up:        if item := value.scroll_up { item.clone() } else { none }
		scroll_down:      if item := value.scroll_down { item.clone() } else { none }
		page_up:          if item := value.page_up { item.clone() } else { none }
		page_down:        if item := value.page_down { item.clone() } else { none }
		half_page_up:     if item := value.half_page_up { item.clone() } else { none }
		half_page_down:   if item := value.half_page_down { item.clone() } else { none }
		jump_top:         if item := value.jump_top { item.clone() } else { none }
		jump_bottom:      if item := value.jump_bottom { item.clone() } else { none }
		close:            if item := value.close { item.clone() } else { none }
		close_transcript: if item := value.close_transcript { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiListKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiListKeymap) clone() TuiListKeymap {
	return TuiListKeymap{
		move_up:     if item := value.move_up { item.clone() } else { none }
		move_down:   if item := value.move_down { item.clone() } else { none }
		move_left:   if item := value.move_left { item.clone() } else { none }
		move_right:  if item := value.move_right { item.clone() } else { none }
		page_up:     if item := value.page_up { item.clone() } else { none }
		page_down:   if item := value.page_down { item.clone() } else { none }
		jump_top:    if item := value.jump_top { item.clone() } else { none }
		jump_bottom: if item := value.jump_bottom { item.clone() } else { none }
		accept:      if item := value.accept { item.clone() } else { none }
		cancel:      if item := value.cancel { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiAgentsKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiAgentsKeymap) clone() TuiAgentsKeymap {
	return TuiAgentsKeymap{
		resume:          if item := value.resume { item.clone() } else { none }
		search:          if item := value.search { item.clone() } else { none }
		new_task:        if item := value.new_task { item.clone() } else { none }
		rename:          if item := value.rename { item.clone() } else { none }
		stop:            if item := value.stop { item.clone() } else { none }
		toggle_grouping: if item := value.toggle_grouping { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiApprovalKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiApprovalKeymap) clone() TuiApprovalKeymap {
	return TuiApprovalKeymap{
		open_fullscreen:     if item := value.open_fullscreen { item.clone() } else { none }
		open_thread:         if item := value.open_thread { item.clone() } else { none }
		approve:             if item := value.approve { item.clone() } else { none }
		approve_for_session: if item := value.approve_for_session { item.clone() } else { none }
		approve_for_prefix:  if item := value.approve_for_prefix { item.clone() } else { none }
		deny:                if item := value.deny { item.clone() } else { none }
		decline:             if item := value.decline { item.clone() } else { none }
		cancel:              if item := value.cancel { item.clone() } else { none }
	}
}

// STUB: config/src/tui_keymap.rs::TuiKeymap derived Clone at LocalSettings config boundaries.
pub fn (value &TuiKeymap) clone() TuiKeymap {
	return TuiKeymap{
		global:          value.global.clone()
		chat:            value.chat.clone()
		composer:        value.composer.clone()
		editor:          value.editor.clone()
		vim_normal:      value.vim_normal.clone()
		vim_operator:    value.vim_operator.clone()
		vim_search:      value.vim_search.clone()
		vim_text_object: value.vim_text_object.clone()
		pager:           value.pager.clone()
		list:            value.list.clone()
		agents:          value.agents.clone()
		approval:        value.approval.clone()
	}
}

// STUB: Vec<KeybindingSpec>::clone allocates each independent canonical key string.
fn clone_local_settings_keybinding_specs(values &[]KeybindingSpec) []KeybindingSpec {
	mut result := []KeybindingSpec{cap: values.len}
	for index in 0 .. values.len {
		result << values[index].clone()
	}
	return result
}
