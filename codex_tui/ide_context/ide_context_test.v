module ide_context

import codex_app_server_protocol as api
import serde_json
import codex_tui.ide_context.model
import std_path

fn test_deserializes_existing_ide_context_shape() {
	text := '{
        "activeFile": {
            "label": "lib.rs",
            "path": "src/lib.rs",
            "fsPath": "/repo/src/lib.rs",
            "selection": {
                "start": { "line": 1, "character": 2 },
                "end": { "line": 3, "character": 4 }
            },
            "activeSelectionContent": "selected",
            "selections": []
        },
        "openTabs": [
            {
                "label": "main.rs",
                "path": "src/main.rs",
                "fsPath": "/repo/src/main.rs",
                "startLine": 2,
                "endLine": 10
            }
        ],
        "processEnv": {
            "path": "/usr/bin"
        }
    }'
	value := serde_json.from_str(&text) or { panic(err) }
	context := serde_json.from_value[model.IdeContext](value, model.IdeContext.deserialize_value) or { panic('deserialize ide context: ${err}') }
	assert context == IdeContext{
		active_file: ActiveFile{
			descriptor:               FileDescriptor{ label: 'lib.rs', path: 'src/lib.rs' }
			selection:                Range{
				start: Position{ line: 1, character: 2 }
				end:   Position{ line: 3, character: 4 }
			}
			active_selection_content: 'selected'
			selections:               []Range{}
		}
		open_tabs:   [FileDescriptor{ label: 'main.rs', path: 'src/main.rs' }]
	}
}

fn test_defaults_null_optional_and_exact_camel_case_keys() {
	for text in ['{}', '{"activeFile":null}', '{"active_file":false,"open_tabs":null}'] {
		context := IdeContext.deserialize_json(&text) or { panic(err) }
		assert context == IdeContext{}
	}
	text := '{"activeFile":{"label":"file","path":"src/file","selection":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"active_selection_content":false},"openTabs":[]}'
	context := IdeContext.deserialize_json(&text) or { panic(err) }
	assert context == IdeContext{
		active_file: ActiveFile{
			descriptor:               FileDescriptor{ label: 'file', path: 'src/file' }
			selection:                Range{}
			active_selection_content: ''
			selections:               []Range{}
		}
		open_tabs:   []FileDescriptor{}
	}
}

fn assert_decode_error(text string, expected string) {
	if _ := IdeContext.deserialize_json(&text) {
		assert false, 'expected decode failure for ${text}'
	} else {
		assert err.msg().contains(expected), '${err.msg()} should contain ${expected}'
	}
}

fn test_required_fields_and_wrong_or_null_types_are_rejected() {
	for text in ['null', 'true', '42', '"context"'] {
		assert_decode_error(text, 'expected struct IdeContext')
	}
	for text in ['{"activeFile":false}', '{"activeFile":[]}', '{"activeFile":"file"}'] {
		assert_decode_error(text, 'expected struct ActiveFile')
	}
	assert_decode_error('{"activeFile":{"label":"file","path":"file"}}', 'missing field `selection`')
	assert_decode_error('{"activeFile":{"selection":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}}}', 'missing field `label`')
	assert_decode_error('{"openTabs":[{"label":"file"}]}', 'missing field `path`')
	for text in ['{"openTabs":null}', '{"openTabs":{}}', '{"openTabs":false}'] {
		assert_decode_error(text, 'expected a sequence')
	}
	for text in ['{"openTabs":[{"label":null,"path":"file"}]}',
		'{"openTabs":[{"label":"file","path":42}]}'] {
		assert_decode_error(text, 'expected a string')
	}
	base := '{"activeFile":{"label":"file","path":"file","selection":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}}'
	for field in ['"activeSelectionContent":null', '"activeSelectionContent":false', '"selections":null',
		'"selections":{}'] {
		text := base + ',' + field + '}}'
		if _ := IdeContext.deserialize_json(&text) {
			assert false, 'present invalid defaulted field should fail: ${field}'
		}
	}
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":null}}', 'expected struct Range')
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":{}}}', 'missing field `start`')
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":{"start":null}}}', 'expected struct Position')
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":{"start":{}}}}', 'missing field `line`')
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":{"start":{"line":0}}}}', 'missing field `character`')
	assert_decode_error('{"activeFile":{"label":"file","path":"file","selection":{"start":{"line":0,"character":0}}}}', 'missing field `end`')
}

fn position_context_json(number &string) string {
	return '{"activeFile":{"label":"file","path":"file","selection":{"start":{"line":${*number},"character":0},"end":{"line":0,"character":${*number}}}}}'
}

fn test_position_numbers_preserve_u32_integer_validation() {
	for number in ['0', '4294967295'] {
		text := position_context_json(&number)
		context := IdeContext.deserialize_json(&text) or { panic(err) }
		active := context.active_file or { panic('active file expected') }
		assert active.selection == Range{
			start: Position{ line: u32(number.u64()), character: 0 }
			end:   Position{ line: 0, character: u32(number.u64()) }
		}
	}
	for number in ['-1', '-0', '4294967296', '18446744073709551615', '1.0', '1e0', '"1"', 'true',
		'null'] {
		text := position_context_json(&number)
		assert_decode_error(text, 'expected u32')
	}
}

fn test_sequence_representations_and_flattened_descriptor_shape() {
	text := '[null, [["main.rs", "src/main.rs"]]]'
	context := IdeContext.deserialize_json(&text) or { panic(err) }
	assert context == IdeContext{ open_tabs: [FileDescriptor{ label: 'main.rs', path: 'src/main.rs' }] }
	defaulted := '[null]'
	assert IdeContext.deserialize_json(&defaulted) or { panic(err) } == IdeContext{}
	text_with_sequences := '{"activeFile":{"label":"file","path":"file","selection":[[1,2],[3,4]],"selections":[[[5,6],[7,8]]]}}'
	context_with_sequences := IdeContext.deserialize_json(&text_with_sequences) or { panic(err) }
	assert context_with_sequences == IdeContext{
		active_file: ActiveFile{
			descriptor: FileDescriptor{ label: 'file', path: 'file' }
			selection:  Range{ start: Position{ line: 1, character: 2 }, end: Position{ line: 3, character: 4 } }
			selections: [Range{ start: Position{ line: 5, character: 6 }, end: Position{ line: 7, character: 8 } }]
		}
	}
	for invalid_sequence in ['[]', '[null,[],null]', '{"openTabs":[[]]}', '{"openTabs":[["file"]]}',
		'{"openTabs":[["file","file",null]]}'] {
		assert_decode_error(invalid_sequence, 'invalid length')
	}
	assert_decode_error('{"activeFile":{"descriptor":{"label":"file","path":"file"},"selection":[[0,0],[0,0]]}}', 'missing field `label`')
}

fn test_borrowed_decoding_cloning_and_helpers_leave_owned_inputs_reusable() {
	mut text := '{"activeFile":{"label":"lib.rs","path":"src/lib.rs","selection":{"start":{"line":1,"character":2},"end":{"line":3,"character":4}},"activeSelectionContent":"selected","selections":[]},"openTabs":[{"label":"main.rs","path":"src/main.rs"}]}'
	mut message := 'request'
	mut workspace := '/repo'
	mut home := '/home/user/.codex'
	$if ownership ? {
		text = text.to_owned()
		message = message.to_owned()
		workspace = workspace.to_owned()
		home = home.to_owned()
	}
	value := serde_json.from_str(&text) or { panic(err) }
	first := IdeContext.deserialize_value(&value) or { panic(err) }
	second := IdeContext.deserialize_value(&value) or { panic(err) }
	assert first == second
	assert value.is_object()
	assert text.contains('selected')
	copy := first.clone()
	assert copy == first
	assert first.clone() == second
	assert first.open_tabs[0].path == 'src/main.rs'
	assert first.active_file or { panic('active file expected') } == second.active_file or { panic('active file expected') }
	mut items := []api.UserInput{}
	assert apply_ide_context_to_user_input(&first, mut items)
	assert apply_ide_context_to_user_input(&first, mut items)
	assert items.len == 1
	assert has_prompt_context(&first)
	assert has_prompt_context(&first)
	item := items[0] as api.UserInputText
	assert item.text.count('## My request for Codex:') == 2
	assert item.text.count('src/lib.rs') == 2
	for _ in 0 .. 2 {
		request, offset := extract_prompt_request_with_offset(&message)
		assert request == 'request'
		assert offset == 0
	}
	assert message == 'request'
	workspace_path := std_path.Path.new(&workspace)
	home_path := std_path.Path.new(&home)
	for _ in 0 .. 2 {
		if _ := fetch_ide_context(&workspace_path, &home_path) {
			assert false, 'untranslated IPC must report an explicit error'
		} else {
			assert err.msg().contains('transport is not translated')
		}
	}
	assert workspace == '/repo'
	assert home == '/home/user/.codex'
	assert copy == first
}
