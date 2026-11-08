module prompt

import codex_app_server_protocol as api
import codex_tui.ide_context.model

fn descriptor(label &string, path &string) model.FileDescriptor {
	return model.FileDescriptor{ label: label.clone(), path: path.clone() }
}

fn test_render_prompt_context_matches_app_format() {
	descriptor_text_0 := 'lib.rs'
	descriptor_text_1 := 'src/lib.rs'
	descriptor_text_2 := 'main.rs'
	descriptor_text_3 := 'src/main.rs'
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_1)
			selection:                model.Range{
				start: model.Position{ line: 4, character: 0 }
				end:   model.Position{ line: 6, character: 1 }
			}
			active_selection_content: 'fn selected() {}'
			selections:               []model.Range{}
		}
		open_tabs:   [descriptor(&descriptor_text_0, &descriptor_text_1),
			descriptor(&descriptor_text_2, &descriptor_text_3)]
	}
	assert render_prompt_context(&context) == ?string('# Context from my IDE setup:\n\n## Active file: src/lib.rs\n\n## Active selection of the file:\nfn selected() {}\n## Open tabs:\n- lib.rs: src/lib.rs\n- main.rs: src/main.rs\n')
}

fn test_render_prompt_context_omits_empty_context() {
	context := model.IdeContext{ active_file: none, open_tabs: []model.FileDescriptor{} }
	assert render_prompt_context(&context) == none
}

fn test_apply_ide_context_uses_desktop_prompt_request_delimiter() {
	descriptor_text_0 := 'lib.rs'
	descriptor_text_1 := 'src/lib.rs'
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_1)
			selection:                model.Range{
				start: model.Position{ line: 0, character: 0 }
				end:   model.Position{ line: 0, character: 0 }
			}
			active_selection_content: ''
			selections:               []model.Range{}
		}
		open_tabs:   []model.FileDescriptor{}
	}
	text := 'Ask $figma'
	mut items := [
		api.UserInput(api.UserInputLocalImage{ path: '/tmp/screenshot.png', detail: none }),
		api.UserInput(api.UserInputText{
			text:          text
			text_elements: [api.TextElement.new(api.ByteRange{ start: 4, end: 10 }, '$figma')]
		}),
	]
	assert apply_ide_context_to_user_input(&context, mut items)
	expected_prefix := '# Context from my IDE setup:\n\n## Active file: src/lib.rs\n\n## My request for Codex:\n'
	prefix_len := expected_prefix.len
	assert items == [
		api.UserInput(api.UserInputLocalImage{ path: '/tmp/screenshot.png', detail: none }),
		api.UserInput(api.UserInputText{
			text:          '${expected_prefix}Ask \$figma'
			text_elements: [api.TextElement.new(api.ByteRange{ start: prefix_len + 4, end: prefix_len + 10 }, '$figma')]
		}),
	]
}

fn test_extract_prompt_request_returns_text_after_last_delimiter() {
	message := '# Context\n## My request for Codex:\nFirst\n## My request for Codex:\n  Second\n'
	request, offset := extract_prompt_request_with_offset(&message)
	assert request == 'Second'
	assert offset == usize(message.index('Second') or { panic('request offset') })
}

fn test_render_prompt_context_includes_selection_ranges_without_content() {
	descriptor_text_0 := 'lib.rs'
	descriptor_text_1 := 'src/lib.rs'
	first_range := model.Range{
		start: model.Position{ line: 1, character: 2 }
		end:   model.Position{ line: 1, character: 5 }
	}
	second_range := model.Range{
		start: model.Position{ line: 3, character: 0 }
		end:   model.Position{ line: 4, character: 1 }
	}
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_1)
			selection:                first_range.clone()
			active_selection_content: ''
			selections:               [first_range, second_range]
		}
		open_tabs:   []model.FileDescriptor{}
	}
	assert render_prompt_context(&context) == ?string('# Context from my IDE setup:\n\n## Active file: src/lib.rs\n\n## Active selection ranges:\n- src/lib.rs: line 2, column 3 to line 2, column 6\n- src/lib.rs: line 4, column 1 to line 5, column 2\n')
}

fn test_render_prompt_context_truncates_large_selection() {
	descriptor_text_0 := 'large.txt'
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_0)
			selection:                model.Range{
				start: model.Position{ line: 0, character: 0 }
				end:   model.Position{ line: 0, character: 1 }
			}
			active_selection_content: '${'a'.repeat(max_active_selection_chars)}tail'
			selections:               []model.Range{}
		}
		open_tabs:   []model.FileDescriptor{}
	}
	rendered := render_prompt_context(&context) or { panic('rendered IDE context') }
	assert rendered.contains('[Selection truncated to ${max_active_selection_chars} characters.]')
	assert !rendered.contains('tail')
}

fn test_render_prompt_context_omits_excess_open_tabs() {
	mut open_tabs := []model.FileDescriptor{}
	for index in 0 .. max_open_tabs + 2 {
		label := 'file-${index}.rs'
		path := 'src/file-${index}.rs'
		open_tabs << descriptor(&label, &path)
	}
	context := model.IdeContext{ active_file: none, open_tabs: open_tabs }
	rendered := render_prompt_context(&context) or { panic('rendered IDE context') }
	assert rendered.contains('- file-99.rs: src/file-99.rs\n')
	assert !rendered.contains('- file-100.rs: src/file-100.rs\n')
	assert rendered.contains('[2 open tabs omitted.]\n')
}

fn test_selection_limit_counts_unicode_scalars_and_preserves_exact_limit() {
	descriptor_text_0 := 'unicode.txt'
	selection := '${'🦀'.repeat(max_active_selection_chars)}tail'
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_0)
			active_selection_content: selection
		}
	}
	rendered := render_prompt_context(&context) or { panic('rendered IDE context') }
	assert rendered.contains('🦀'.repeat(max_active_selection_chars))
	assert !rendered.contains('tail')
	assert rendered.contains('[Selection truncated to ${max_active_selection_chars} characters.]')
	exact_context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_0)
			active_selection_content: '🦀'.repeat(max_active_selection_chars)
		}
	}
	exact := render_prompt_context(&exact_context) or { panic('rendered IDE context') }
	assert !exact.contains('[Selection truncated')
	assert exact.ends_with('🦀'.repeat(max_active_selection_chars))
}

fn test_open_tab_budget_counts_utf8_bytes_and_keeps_exact_budget() {
	descriptor_text_0 := 'x'
	descriptor_text_1 := 'next'
	descriptor_text_2 := 'next.rs'
	path := 'é'.repeat((max_open_tabs_chars - 6) / 2)
	context := model.IdeContext{
		open_tabs: [descriptor(&descriptor_text_0, &path),
			descriptor(&descriptor_text_1, &descriptor_text_2)]
	}
	rendered := render_prompt_context(&context) or { panic('rendered IDE context') }
	assert rendered == '# Context from my IDE setup:\n\n## Open tabs:\n- x: ${path}\n[1 open tabs omitted.]\n'
	over_budget := '${path}é'
	too_large := model.IdeContext{ open_tabs: [descriptor(&descriptor_text_0, &over_budget)] }
	assert render_prompt_context(&too_large) == ?string('# Context from my IDE setup:\n\n## Open tabs:\n[1 open tabs omitted.]\n')
}

fn test_selection_fallback_empty_ranges_and_multiple_ranges_with_content() {
	descriptor_text_0 := 'f'
	selected := model.Range{
		start: model.Position{ line: 1, character: 2 }
		end:   model.Position{ line: 2, character: 3 }
	}
	context := model.IdeContext{
		active_file: model.ActiveFile{ descriptor: descriptor(&descriptor_text_0, &descriptor_text_0), selection: selected }
	}
	assert render_prompt_context(&context) == ?string('# Context from my IDE setup:\n\n## Active file: f\n\n## Active selection range:\n- f: line 2, column 3 to line 3, column 4\n')
	multiple := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&descriptor_text_0, &descriptor_text_0)
			selection:                selected
			active_selection_content: 'selected'
			selections:               [model.Range{}, selected,
				model.Range{ start: model.Position{ character: 1 }, end: model.Position{ character: 2 } }]
		}
	}
	assert render_prompt_context(&multiple) == ?string('# Context from my IDE setup:\n\n## Active file: f\n\n## Active selection ranges:\n- f: line 2, column 3 to line 3, column 4\n- f: line 1, column 2 to line 1, column 3\n\n## Active selection of the file:\nselected')
}

fn test_no_text_inserts_prefix_before_images_and_empty_context_preserves_items() {
	descriptor_text_0 := 'lib.rs'
	descriptor_text_1 := 'src/lib.rs'
	context := model.IdeContext{ open_tabs: [descriptor(&descriptor_text_0, &descriptor_text_1)] }
	mut items := [api.UserInput(api.UserInputLocalImage{ path: '/tmp/image.png', detail: none })]
	assert apply_ide_context_to_user_input(&context, mut items)
	assert items == [
		api.UserInput(api.UserInputText{ text: '# Context from my IDE setup:\n\n## Open tabs:\n- lib.rs: src/lib.rs\n\n## My request for Codex:\n' }),
		api.UserInput(api.UserInputLocalImage{ path: '/tmp/image.png', detail: none }),
	]
	empty := model.IdeContext{}
	assert !apply_ide_context_to_user_input(&empty, mut items)
	assert !has_prompt_context(&empty)
	assert items.len == 2
}

fn test_request_trimming_preserves_unicode_byte_offset_and_no_marker_text() {
	message := '🦀context## My request for Codex:\u0085\u00a0\u2003🦀request\u3000\n'
	request, offset := extract_prompt_request_with_offset(&message)
	assert request == '🦀request'
	assert offset == usize(message.index('🦀request') or { panic('request offset') })
	no_marker := '\u2003keep whitespace\n'
	original, zero := extract_prompt_request_with_offset(&no_marker)
	assert original == no_marker
	assert zero == 0
	blank := '## My request for Codex:\u2003\n'
	empty, blank_offset := extract_prompt_request_with_offset(&blank)
	assert empty == ''
	assert blank_offset == usize(blank.len)
}

fn test_borrowed_context_message_and_placeholder_owners_remain_reusable() {
	mut label := 'lib.rs'
	mut path := 'src/lib.rs'
	mut selection := 'selected 🦀'
	mut message := '# IDE\n## My request for Codex:\u2003Ask 🦀\n'
	mut placeholder := '$figma'
	mut text := '🦀 $figma'
	$if ownership ? {
		label = label.to_owned()
		path = path.to_owned()
		selection = selection.to_owned()
		message = message.to_owned()
		placeholder = placeholder.to_owned()
		text = text.to_owned()
	}
	context := model.IdeContext{
		active_file: model.ActiveFile{
			descriptor:               descriptor(&label, &path)
			active_selection_content: selection
		}
	}
	for _ in 0 .. 2 {
		assert has_prompt_context(&context)
		assert (render_prompt_context(&context) or { panic('context') }).contains('selected 🦀')
		request, offset := extract_prompt_request_with_offset(&message)
		assert request == 'Ask 🦀'
		assert offset == usize(message.index('Ask 🦀') or { panic('request offset') })
	}
	mut items := [api.UserInput(api.UserInputText{
		text:          text
		text_elements: [
			api.TextElement.new(api.ByteRange{ start: 5, end: 11 }, placeholder),
			api.TextElement.new(api.ByteRange{ start: 0, end: 4 }, none),
		]
	})]
	assert apply_ide_context_to_user_input(&context, mut items)
	assert apply_ide_context_to_user_input(&context, mut items)
	assert context.active_file or { panic('active file') }.active_selection_content == 'selected 🦀'
	assert context.active_file or { panic('active file') }.descriptor.path == path
	assert label == 'lib.rs'
	assert message.ends_with('Ask 🦀\n')
	item := items[0] as api.UserInputText
	assert item.text.ends_with('🦀 $figma')
	assert item.text_elements[0].placeholder().to_owned() == ?string('$figma')
	assert item.text_elements[1].placeholder().to_owned() == none
	assert item.text_elements[0].byte_range.start == item.text.len - 6
	assert item.text_elements[0].byte_range.end == item.text.len
}

fn test_image_detail_survives_injection_and_canonical_input_clone() {
	label := 'lib.rs'
	path := 'src/lib.rs'
	context := model.IdeContext{ open_tabs: [descriptor(&label, &path)] }
	remote := api.UserInput(api.UserInputImage{ detail: .high, url: 'https://example.invalid/image' })
	local := api.UserInput(api.UserInputLocalImage{ detail: .original, path: '/tmp/image.png' })
	assert remote.clone() == remote
	assert local.clone() == local
	mut items := [remote.clone(), local.clone()]
	assert apply_ide_context_to_user_input(&context, mut items)
	assert items[1] == remote
	assert items[2] == local
}
