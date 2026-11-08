module collaboration_modes

import codex_app_server_client
import codex_app_server_protocol as api
import codex_protocol
import codex_protocol.config_types
import codex_protocol.openai_models
import codex_tui.model_catalog
import time
import tokio.time as tokio_time
import x.json2

fn owned_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn mode_fixture(name string, kind ?config_types.ModeKind) config_types.CollaborationModeMask {
	return config_types.CollaborationModeMask{
		name:                   owned_string(name)
		mode:                   kind
		model:                  owned_string('fixture-model')
		reasoning_effort:       codex_protocol.OptionalReasoningEffort{ is_set: true, value: .high }
		developer_instructions: codex_protocol.OptionalString{ is_set: true, value: owned_string('restored prompt') }
	}
}

fn catalog_fixture(modes []config_types.CollaborationModeMask) model_catalog.ModelCatalog {
	return model_catalog.ModelCatalog.new([]openai_models.ModelPreset{}).with_collaboration_modes(modes)
}

fn test_empty_catalog_has_no_synthetic_presets() {
	catalog := catalog_fixture([]config_types.CollaborationModeMask{})
	assert filtered_presets(&catalog).len == 0
	assert default_mask(&catalog) == none
	assert mask_for_kind(&catalog, .default_mode) == none
	assert next_mask(&catalog, BorrowedMask.none()) == none
	assert default_mode_mask(&catalog) == none
	assert plan_mask(&catalog) == none
}

fn test_filtered_presets_preserve_order_and_reject_absent_or_hidden_kinds() {
	catalog := catalog_fixture([
		mode_fixture('absent', none),
		mode_fixture('legacy pair', .pair_programming),
		mode_fixture('planning', .plan),
		mode_fixture('legacy execute', .execute),
		mode_fixture('default', .default_mode),
		mode_fixture('second plan', .plan),
	])
	presets := filtered_presets(&catalog)
	assert presets.len == 3
	assert presets[0] == catalog.collaboration_modes[2]
	assert presets[1] == catalog.collaboration_modes[4]
	assert presets[2] == catalog.collaboration_modes[5]
	assert catalog.collaboration_modes.len == 6
}

fn test_default_prefers_first_default_over_earlier_plan() {
	catalog := catalog_fixture([
		mode_fixture('first plan', .plan),
		mode_fixture('first default', .default_mode),
		mode_fixture('second default', .default_mode),
	])
	selected := default_mask(&catalog) or { panic('missing default') }
	assert selected == catalog.collaboration_modes[1]
}

fn test_default_falls_back_to_first_visible_without_fabricating_default() {
	catalog := catalog_fixture([
		mode_fixture('invisible', .execute),
		mode_fixture('first plan', .plan),
		mode_fixture('second plan', .plan),
	])
	selected := default_mask(&catalog) or { panic('missing fallback') }
	assert selected == catalog.collaboration_modes[1]
	assert default_mode_mask(&catalog) == none
	assert plan_mask(&catalog) or { panic('missing plan') } == selected
}

fn test_kind_lookup_returns_first_exact_kind_and_rejects_hidden_kind() {
	catalog := catalog_fixture([
		mode_fixture('hidden', .pair_programming),
		mode_fixture('first plan', .plan),
		mode_fixture('second plan', .plan),
		mode_fixture('default', .default_mode),
	])
	assert mask_for_kind(&catalog, .pair_programming) == none
	assert mask_for_kind(&catalog, .execute) == none
	assert plan_mask(&catalog) or { panic('missing plan') } == catalog.collaboration_modes[1]
	assert default_mode_mask(&catalog) or { panic('missing default') } == catalog.collaboration_modes[3]
}

fn test_next_without_current_starts_at_first_visible() {
	catalog := catalog_fixture([mode_fixture('hidden', none), mode_fixture('plan', .plan),
		mode_fixture('default', .default_mode)])
	assert next_mask(&catalog, BorrowedMask.none()) or { panic('missing next') } == catalog.collaboration_modes[1]
}

fn test_next_matches_kind_independently_of_current_name_or_settings() {
	catalog := catalog_fixture([mode_fixture('plan', .plan), mode_fixture('default', .default_mode)])
	mut current := mode_fixture('a different plan label', .plan)
	current.model = owned_string('a different model')
	current.developer_instructions = codex_protocol.OptionalString{ is_set: true, value: owned_string('a different prompt') }
	view := BorrowedMask{ has_value: true, mask: &current }
	assert next_mask(&catalog, view) or { panic('missing next') } == catalog.collaboration_modes[1]
	assert next_mask(&catalog, view) or { panic('missing next') } == catalog.collaboration_modes[1]
	assert current.name == 'a different plan label'
	assert current.model or { panic('missing model') } == 'a different model'
	assert current.developer_instructions.value or { panic('missing prompt') } == 'a different prompt'
}

fn test_next_wraps_to_first_visible() {
	catalog := catalog_fixture([mode_fixture('plan', .plan), mode_fixture('default', .default_mode)])
	current := mode_fixture('default selection', .default_mode)
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &current }) or { panic('missing next') } == catalog.collaboration_modes[0]
}

fn test_next_duplicate_kind_uses_first_position_even_for_second_label() {
	catalog := catalog_fixture([mode_fixture('first plan', .plan), mode_fixture('second plan', .plan),
		mode_fixture('default', .default_mode)])
	current := mode_fixture('second plan', .plan)
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &current }) or { panic('missing next') } == catalog.collaboration_modes[1]
}

fn test_next_absent_or_unknown_current_kind_starts_at_first_visible() {
	catalog := catalog_fixture([mode_fixture('plan', .plan), mode_fixture('default', .default_mode)])
	current_absent := mode_fixture('without kind', none)
	current_hidden := mode_fixture('obsolete kind', .execute)
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &current_absent }) or { panic('missing next') } == catalog.collaboration_modes[0]
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &current_hidden }) or { panic('missing next') } == catalog.collaboration_modes[0]
}

fn test_single_visible_mode_cycles_to_itself() {
	catalog := catalog_fixture([mode_fixture('hidden', none), mode_fixture('only plan', .plan)])
	current := mode_fixture('only plan', .plan)
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &current }) or { panic('missing next') } == catalog.collaboration_modes[1]
}

fn test_borrowed_catalog_and_returned_owned_masks_remain_independent() {
	catalog := catalog_fixture([mode_fixture('owned default', .default_mode),
		mode_fixture('owned plan', .plan)])
	mut first := default_mask(&catalog) or { panic('missing default') }
	first.name = owned_string('changed selection name')
	first.model = owned_string('changed selection model')
	first.developer_instructions = codex_protocol.OptionalString{ is_set: true, value: owned_string('changed selection prompt') }
	second := default_mask(&catalog) or { panic('missing default') }
	assert second == catalog.collaboration_modes[0]
	assert plan_mask(&catalog) or { panic('missing plan') } == catalog.collaboration_modes[1]
	assert next_mask(&catalog, BorrowedMask{ has_value: true, mask: &first }) or { panic('missing next') } == catalog.collaboration_modes[1]
	assert catalog.collaboration_modes[0].name == 'owned default'
	assert catalog.collaboration_modes[0].model or { panic('missing model') } == 'fixture-model'
	assert catalog.collaboration_modes[0].developer_instructions.value or { panic('missing prompt') } == 'restored prompt'
	assert first.name == 'changed selection name'
}

fn wire_fixture() api.CollaborationModeListResponse {
	return api.CollaborationModeListResponse{
		data: [
			api.CollaborationModeMask{ name: owned_string('unclassified'), mode: none, model: none, reasoning_effort: codex_protocol.OptionalReasoningEffort{} },
			api.CollaborationModeMask{ name: owned_string('planning'), mode: .plan, model: owned_string('server-plan-model'), reasoning_effort: codex_protocol.OptionalReasoningEffort{ is_set: true, value: none } },
			api.CollaborationModeMask{ name: owned_string('default'), mode: .default_mode, model: owned_string('server-default-model'), reasoning_effort: codex_protocol.OptionalReasoningEffort{ is_set: true, value: .high } },
		]
	}
}

fn test_fallback_and_kind_results_outlive_filtered_temporary_presets() {
	catalog := catalog_fixture([mode_fixture('owned planning fallback', .plan)])
	fallback := default_mask(&catalog) or { panic('missing fallback') }
	selected_kind := mask_for_kind(&catalog, .plan) or { panic('missing plan') }
	// Repeated temporary allocations exercise both consuming iterator return paths.
	for _ in 0 .. 20 {
		selected_again := plan_mask(&catalog) or { panic('missing plan') }
		assert selected_again.name == 'owned planning fallback'
	}
	assert fallback.name == 'owned planning fallback'
	assert fallback.model or { panic('missing fallback model') } == 'fixture-model'
	assert fallback.developer_instructions.value or { panic('missing fallback prompt') } == 'restored prompt'
	assert selected_kind == fallback
	assert selected_kind.model or { panic('missing kind model') } == 'fixture-model'
	assert selected_kind.developer_instructions.value or { panic('missing kind prompt') } == 'restored prompt'
	assert catalog.collaboration_modes[0].name == 'owned planning fallback'
}

fn test_discovery_preserves_wire_order_fields_and_clears_prompt_overrides() {
	handle := codex_app_server_client.AppServerRequestHandle.collaboration_modes_fixture(wire_fixture(), 0, none)
	discovered := list(handle.clone())
	assert discovered == [
		config_types.CollaborationModeMask{ name: 'unclassified', mode: none, model: none, reasoning_effort: codex_protocol.OptionalReasoningEffort{}, developer_instructions: codex_protocol.OptionalString{ is_set: true, value: none } },
		config_types.CollaborationModeMask{ name: 'planning', mode: .plan, model: 'server-plan-model', reasoning_effort: codex_protocol.OptionalReasoningEffort{ is_set: true, value: none }, developer_instructions: codex_protocol.OptionalString{ is_set: true, value: none } },
		config_types.CollaborationModeMask{ name: 'default', mode: .default_mode, model: 'server-default-model', reasoning_effort: codex_protocol.OptionalReasoningEffort{ is_set: true, value: .high }, developer_instructions: codex_protocol.OptionalString{ is_set: true, value: none } },
	]
	assert handle.collaboration_fixture_completed_requests() == 1
}

fn test_successful_empty_discovery_adds_no_presets() {
	handle := codex_app_server_client.AppServerRequestHandle.collaboration_modes_fixture(api.CollaborationModeListResponse{}, 0, none)
	assert list(handle.clone()) == []config_types.CollaborationModeMask{}
	assert handle.collaboration_fixture_completed_requests() == 1
}

fn test_each_typed_request_failure_is_optional_discovery() {
	for kind in [codex_app_server_client.TypedRequestErrorKind.transport, .server, .deserialize] {
		handle := codex_app_server_client.AppServerRequestHandle.collaboration_modes_fixture(wire_fixture(), 0, kind)
		assert list(handle.clone()) == []config_types.CollaborationModeMask{}
		assert handle.collaboration_fixture_request_ids().len == 1
		assert handle.collaboration_fixture_completed_requests() == 1
	}
	assert list(codex_app_server_client.AppServerRequestHandle{}) == []config_types.CollaborationModeMask{}
}

fn test_discovery_request_ids_are_distinct_prefixed_version_four_uuids() {
	handle := codex_app_server_client.AppServerRequestHandle.collaboration_modes_fixture(api.CollaborationModeListResponse{}, 0, none)
	assert list(handle.clone()).len == 0
	assert list(handle.clone()).len == 0
	ids := handle.collaboration_fixture_request_ids()
	assert ids.len == 2
	assert ids[0] != ids[1]
	for id in ids {
		assert id.starts_with('collaboration-mode-list-')
		value := id['collaboration-mode-list-'.len..]
		assert value.len == 36
		assert value[14] == `4`
		assert value[19] in [`8`, `9`, `a`, `b`]
		for index, character in value {
			if index in [8, 13, 18, 23] {
				assert character == `-`
			} else {
				assert character in [`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `a`, `b`,
					`c`, `d`, `e`, `f`]
			}
		}
	}
}

fn test_discovery_deadline_returns_before_a_slow_request_finishes() {
	handle := codex_app_server_client.AppServerRequestHandle.collaboration_modes_fixture(wire_fixture(), i64(3 * time.second), none)
	stopwatch := time.new_stopwatch()
	assert list(handle.clone()) == []config_types.CollaborationModeMask{}
	elapsed := stopwatch.elapsed()
	assert elapsed >= 1_900 * time.millisecond
	assert elapsed < 2_800 * time.millisecond
	assert handle.collaboration_fixture_request_ids().len == 1
	assert handle.collaboration_fixture_completed_requests() == 0
	// V cannot cancel the worker. Wait for it to finish so no fixture task is left running.
	time.sleep(1_200 * time.millisecond)
	assert handle.collaboration_fixture_completed_requests() == 1
}

fn test_timeout_returns_owned_operation_result() {
	value := tokio_time.timeout[string](i64(time.second), fn () !string {
		return owned_string('completed operation')
	}) or { panic(err) }
	assert value == 'completed operation'
}

fn test_timeout_preserves_operation_error() {
	tokio_time.timeout[string](i64(time.second), fn () !string {
		return error('specific operation failure')
	}) or {
		assert err.msg() == 'specific operation failure'
		return
	}
	assert false, 'operation error was lost'
}

fn test_typed_request_error_formatting_borrows_its_owned_metadata() {
	failure := codex_app_server_client.TypedRequestError{
		kind:             .transport
		method:           owned_string('collaborationMode/list')
		transport_source: error(owned_string('fixture transport failure'))
	}
	assert failure.msg() == 'collaborationMode/list transport error: fixture transport failure'
	assert failure.msg() == 'collaborationMode/list transport error: fixture transport failure'
	assert failure.code() == int(codex_app_server_client.TypedRequestErrorKind.transport)
	assert failure.method == 'collaborationMode/list'
	assert failure.transport_source.msg() == 'fixture transport failure'
}

fn test_typed_server_error_retains_code_and_structured_data_when_formatted() {
	failure := codex_app_server_client.TypedRequestError{
		kind:          .server
		method:        owned_string('collaborationMode/list')
		server_source: api.JSONRPCErrorError{
			code:    -32001
			message: owned_string('server discovery unavailable')
			data:    api.OptionalJsonValue{
				has_value: true
				value:     json2.Any(owned_string('typed error data'))
			}
		}
	}
	assert failure.msg() == 'collaborationMode/list failed: server discovery unavailable (code -32001), data: "typed error data"'
	assert failure.msg() == 'collaborationMode/list failed: server discovery unavailable (code -32001), data: "typed error data"'
	assert failure.server_source.code == -32001
	assert failure.server_source.message == 'server discovery unavailable'
	assert failure.server_source.data.value.json_str() == '"typed error data"'
}

fn test_timeout_enforces_short_deadline_and_worker_can_complete_later() {
	completed := chan bool{cap: 1}
	stopwatch := time.new_stopwatch()
	tokio_time.timeout[string](i64(30 * time.millisecond), fn [completed] () !string {
		time.sleep(250 * time.millisecond)
		completed <- true
		return owned_string('late result')
	}) or {
		assert err.msg() == 'operation timed out'
		assert stopwatch.elapsed() < 200 * time.millisecond
		assert <-completed
		return
	}
	assert false, 'late operation escaped the deadline'
}
