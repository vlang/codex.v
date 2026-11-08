module diff_model

import serde_json
import std_path

fn test_tagged_variants_serialize_and_round_trip() {
	add := FileChange(Add{ content: 'new\n"quoted"\t🌱' })
	delete := FileChange(Delete{ content: 'old\r\n' })
	update := FileChange(Update{
		unified_diff: '@@ -1 +1 @@\n-old\n+new\n'
		move_path:    std_path.PathBuf.from('next/./file.txt')
	})
	unchanged_path := FileChange(Update{ unified_diff: 'diff', move_path: none })
	assert serde_json.to_string(&add) or { panic(err) } == '{"type":"add","content":"new\\n\\"quoted\\"\\t🌱"}'
	assert serde_json.to_string(&delete) or { panic(err) } == '{"type":"delete","content":"old\\r\\n"}'
	assert serde_json.to_string(&update) or { panic(err) } == '{"type":"update","unified_diff":"@@ -1 +1 @@\\n-old\\n+new\\n","move_path":"next/./file.txt"}'
	assert serde_json.to_string(&unchanged_path) or { panic(err) } == '{"type":"update","unified_diff":"diff","move_path":null}'
	for change in [&add, &delete, &update, &unchanged_path] {
		encoded := change.serialize_json() or { panic(err) }
		decoded := FileChange.deserialize_json(&encoded) or { panic(err) }
		assert change.equals(&decoded)
	}
}

fn test_map_optional_default_unknown_fields_and_tag_order() {
	missing := '{"unified_diff":"diff","type":"update"}'
	null_path := '{"type":"update","move_path":null,"unified_diff":"diff"}'
	with_unknown := '{"content":"diff","unknown":{"nested":[1,true,null]},"type":"add","move_path":false,"move_path":false}'
	expected_update := FileChange(Update{ unified_diff: 'diff', move_path: none })
	expected_add := FileChange(Add{ content: 'diff' })
	from_missing := FileChange.deserialize_json(&missing) or { panic(err) }
	from_null := FileChange.deserialize_json(&null_path) or { panic(err) }
	from_unknown := FileChange.deserialize_json(&with_unknown) or { panic(err) }
	assert from_missing.equals(&expected_update)
	assert from_null.equals(&expected_update)
	assert from_unknown.equals(&expected_add)
}

fn test_sequence_visitor_requires_optional_path_position() {
	add_input := '["add","new"]'
	delete_input := '["delete","old"]'
	update_input := '["update","diff","next/file"]'
	no_move_input := '["update","diff",null]'
	add := FileChange.deserialize_json(&add_input) or { panic(err) }
	delete := FileChange.deserialize_json(&delete_input) or { panic(err) }
	update := FileChange.deserialize_json(&update_input) or { panic(err) }
	no_move := FileChange.deserialize_json(&no_move_input) or { panic(err) }
	assert add.serialize_json() or { panic(err) } == '{"type":"add","content":"new"}'
	assert delete.serialize_json() or { panic(err) } == '{"type":"delete","content":"old"}'
	assert update.serialize_json() or { panic(err) } == '{"type":"update","unified_diff":"diff","move_path":"next/file"}'
	assert no_move.serialize_json() or { panic(err) } == '{"type":"update","unified_diff":"diff","move_path":null}'
	for input in ['["update","diff"]', '["add"]', '["delete","old","extra"]', '["update","diff",null,0]'] {
		if _ := FileChange.deserialize_json(&input) {
			assert false, input
		} else {
			assert err.msg() == 'invalid FileChange sequence length'
		}
	}
}

fn test_deserialize_required_duplicate_and_variant_errors() {
	inputs := [
		'{}',
		'{"content":"x"}',
		'{"type":"Add","content":"x"}',
		'{"type":"other","content":"x"}',
		'{"type":"add"}',
		'{"type":"delete"}',
		'{"type":"update","content":"x"}',
		'{"type":"add","type":"delete","content":"x"}',
		'{"type":"add","content":"x","content":"y"}',
		'{"type":"update","unified_diff":"x","unified_diff":"y"}',
		'{"type":"update","unified_diff":"x","move_path":null,"move_path":null}',
		'{"type":"update","unified_diff":"x","move_path":"a","move_path":"b"}',
	]
	expected := [
		'missing field `type`',
		'missing field `type`',
		'unknown variant `Add`, expected `add`, `delete` or `update`',
		'unknown variant `other`, expected `add`, `delete` or `update`',
		'missing field `content`',
		'missing field `content`',
		'missing field `unified_diff`',
		'duplicate field `type`',
		'duplicate field `content`',
		'duplicate field `unified_diff`',
		'duplicate field `move_path`',
		'duplicate field `move_path`',
	]
	for index, input in inputs {
		if _ := FileChange.deserialize_json(&input) {
			assert false, input
		} else {
			assert err.msg() == expected[index]
		}
	}
}

fn test_deserialize_rejects_wrong_types_and_malformed_json() {
	for input in ['null', 'true', '1', '"add"', '{"type":0,"content":"x"}',
		'{"type":null,"content":"x"}', '{"type":"add","content":null}', '{"type":"delete","content":[]}',
		'{"type":"update","unified_diff":{}}', '{"type":"update","unified_diff":"x","move_path":false}',
		'{"type":"update","unified_diff":"x","move_path":[]}', '{"type":"add","content":"x"} trailing',
		'{"type":"add","content":"x",}', '{"type":"add","content":"\\ud800"}', '[]', '[0,"x"]'] {
		if _ := FileChange.deserialize_json(&input) {
			assert false, input
		} else {
			assert err.msg().len > 0
		}
	}
}

fn test_unknown_fields_use_strict_content_buffering() {
	for input in ['{"type":"add","content":"x","ignored":1e999}',
		'{"type":"add","content":"x","ignored":"\\ud800"}', '{"type":"add","content":"x","ignored":[}',
		'{"type":"update","unified_diff":"x","content":"\\udc00"}'] {
		if _ := FileChange.deserialize_json(&input) {
			assert false, input
		} else {
			assert err.msg().len > 0
		}
	}
	invalid_utf8 := '{"type":"add","content":"' + [u8(0xff)].bytestr() + '"}'
	if _ := FileChange.deserialize_json(&invalid_utf8) {
		assert false
	} else {
		assert err.msg() == 'invalid UTF-8 in JSON input'
	}
}

fn test_partial_eq_compares_variants_and_path_components() {
	add := FileChange(Add{ content: 'same' })
	delete := FileChange(Delete{ content: 'same' })
	other_add := FileChange(Add{ content: 'different' })
	left := FileChange(Update{ unified_diff: 'diff', move_path: std_path.PathBuf.from('a//./b/') })
	right := FileChange(Update{ unified_diff: 'diff', move_path: std_path.PathBuf.from('a/b') })
	changed_diff := FileChange(Update{ unified_diff: 'other', move_path: std_path.PathBuf.from('a/b') })
	no_move := FileChange(Update{ unified_diff: 'diff', move_path: none })
	assert !add.equals(&delete)
	assert !add.equals(&other_add)
	assert left.equals(&right)
	assert right.equals(&left)
	assert !left.equals(&changed_diff)
	assert !left.equals(&no_move)
	assert !no_move.equals(&left)
	assert no_move.equals(&no_move)
}

fn test_path_serialization_rejects_invalid_utf8_without_consuming_owner() {
	$if windows {
		return
	}
	change := FileChange(Update{ unified_diff: 'diff', move_path: std_path.PathBuf.from([u8(0xff)].bytestr()) })
	for _ in 0 .. 2 {
		if _ := change.serialize_json() {
			assert false
		} else {
			assert err.msg() == 'path contains invalid UTF-8 characters'
		}
	}
	assert change is Update
	assert change.unified_diff == 'diff'
	assert change.move_path != none
}

fn test_borrowed_serialization_deserialization_and_clone_keep_heap_owners() {
	mut content := 'heap add content'
	mut old_content := 'heap delete content'
	mut diff := 'heap unified diff'
	mut path_bytes := 'heap/path'
	mut input := '{"type":"update","unified_diff":"borrowed diff","move_path":"borrowed/path"}'
	$if ownership ? {
		content = content.to_owned()
		old_content = old_content.to_owned()
		diff = diff.to_owned()
		path_bytes = path_bytes.to_owned()
		input = input.to_owned()
	}
	add_payload := Add{ content: content }
	delete_payload := Delete{ content: old_content }
	path := std_path.PathBuf.from(path_bytes)
	update_payload := Update{ unified_diff: diff, move_path: path }
	add := FileChange(add_payload)
	delete := FileChange(delete_payload)
	update := FileChange(update_payload)
	for change in [&add, &delete, &update] {
		first := serde_json.to_string(change) or { panic(err) }
		second := serde_json.to_string(change) or { panic(err) }
		assert first == second
		cloned := change.clone()
		assert cloned.equals(change)
		assert change.equals(&cloned)
	}
	first := FileChange.deserialize_json(&input) or { panic(err) }
	second := FileChange.deserialize_json(&input) or { panic(err) }
	assert first.equals(&second)
	assert input.contains('borrowed/path')
	assert add is Add && add.content == 'heap add content'
	assert delete is Delete && delete.content == 'heap delete content'
	assert update is Update && update.unified_diff == 'heap unified diff'
	mut cloned_add := add.clone()
	mut cloned_delete := delete.clone()
	mut cloned_update := update.clone()
	if mut cloned_add is Add {
		assert cloned_add.content.str != add.content.str
		cloned_add.content += ' changed'
	}
	if mut cloned_delete is Delete {
		assert cloned_delete.content.str != delete.content.str
		cloned_delete.content += ' changed'
	}
	if mut cloned_update is Update {
		assert cloned_update.unified_diff.str != update.unified_diff.str
		cloned_update.unified_diff += ' changed'
		cloned_update.move_path = std_path.PathBuf.from('elsewhere')
	}
	assert add.content == 'heap add content'
	assert delete.content == 'heap delete content'
	assert update.unified_diff == 'heap unified diff'
	assert update.serialize_json() or { panic(err) } == '{"type":"update","unified_diff":"heap unified diff","move_path":"heap/path"}'
}
