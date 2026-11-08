module request_processors

import serde_json

fn test_typed_config_clone_preserves_nested_json_and_borrowed_owner() {
	mut document := '{"enabled":false,"nested":{"name":"owned settings"},"order":[1,2]}'
	$if ownership ? {
		document = document.to_owned()
	}
	settings := serde_json.from_str(&document) or { panic(err) }
	owner := OptionalStringMap{
		has_value: true
		value:     {
			'tools': settings
		}
	}
	mut first := clone_optional_config_map(&owner) or { panic('missing first clone') }
	second := clone_optional_config_map(&owner) or { panic('missing second clone') }
	assert json_config_maps_equal(&first, &second)
	first['tools'] = serde_json.Value.boolean(true)
	assert !json_config_maps_equal(&first, &second)
	assert json_config_maps_equal(&owner.value, &second)
	assert owner.value['tools'].to_string() == document
	assert document.contains('owned settings')
	consumed := optional_config_map_value(owner) or { panic('missing consumed map') }
	assert json_config_maps_equal(&consumed, &second)
}

fn test_typed_config_option_preserves_absence_and_empty_object() {
	absent := OptionalStringMap{}
	assert clone_optional_config_map(&absent) == none
	assert clone_optional_config_map(&absent) == none
	present := OptionalStringMap{ has_value: true, value: map[string]serde_json.Value{} }
	first := clone_optional_config_map(&present) or { panic('empty map became absent') }
	second := clone_optional_config_map(&present) or { panic('empty map became absent') }
	assert json_config_maps_equal(&first, &second)
	assert first.len == 0
	assert present.has_value
}
