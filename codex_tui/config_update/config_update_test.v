module config_update

import codex_app_server_client as client
import codex_app_server_protocol as api
import codex_core
import codex_config.loader
import codex_tui.history_cell
import codex_tui.tests
import codex_utils_absolute_path
import codex_utils_path_uri
import color_eyre.eyre
import os
import pathdiff
import serde_json
import std_path
import toml
import uuid

fn test_app_scoped_key_path_quotes_dotted_app_ids() {
	assert app_scoped_key_path(&config_update_test_app_id, &config_update_test_enabled_key) == 'apps."plugin.linear".enabled'
}

fn test_trusted_project_edit_targets_project_trust_level() {
	path := std_path.Path.new(&config_update_test_project_path)
	assert trusted_project_edit(&path) == api.ConfigEdit{
		key_path:       'projects."/workspace/team.project".trust_level'
		value:          serde_json.Value.string('trusted')
		merge_strategy: .replace
	}
}

fn test_remote_project_trust_guards_thread_start_and_preserves_repository_decisions() {
	temp_path := os.join_path(os.temp_dir(), 'codex-v-config-update-${uuid.Uuid.new_v4()}')
	os.mkdir_all(temp_path)!
	defer { os.rmdir_all(temp_path) or { panic(err) } }
	temp_dir := os.real_path(temp_path)
	codex_home := os.join_path(temp_dir, 'codex-home')
	project_root := os.join_path(temp_dir, 'project as a trusted project in sibling')
	project_cwd := os.join_path(project_root, 'nested')
	os.mkdir_all(codex_home)!
	os.mkdir_all(project_cwd)!
	os.mkdir(os.join_path(project_root, '.git'))!
	os.write_file(os.join_path(project_root, '.git/HEAD'), 'ref: refs/heads/main\n')!
	os.mkdir(os.join_path(project_cwd, '.codex'))!
	project_path := std_path.Path.new(&project_root)
	edit := trusted_project_edit(&project_path)
	undecided_config := '[${edit.key_path.trim_string_right('.trust_level')}]\n'
	os.write_file(os.join_path(codex_home, 'config.toml'), undecided_config)!
	os.write_file(os.join_path(project_cwd, '.codex/config.toml'), 'model_reasoning_effort = "high"\n')!
	config := codex_core.ConfigBuilder.default().codex_home(codex_home.clone()).harness_overrides(codex_core.ConfigOverrides{ cwd: codex_home.clone() }).build()!
	app_server := client.AppServerClient.in_process(tests.start_test_embedded_app_server(config)!)
	current_dir := os.getwd()
	cwd_view := std_path.Path.new(&project_cwd)
	current_view := std_path.Path.new(&current_dir)
	relative_cwd := pathdiff.diff_paths(&cwd_view, &current_view) or { panic('failed to calculate relative project path') }
	relative_view := relative_cwd.as_path()
	initial := expect_project_trust(read_remote_project_trust(app_server.request_handle(), &relative_view)!)
	assert initial == RemoteProjectTrust{ cwd: std_path.PathBuf.from(project_cwd.clone()), trust_target: std_path.PathBuf.from(loader.project_trust_key(&project_root)) }
	assert os.read_file(os.join_path(codex_home, 'config.toml'))! == undecided_config
	_ := write_trusted_project(app_server.request_handle(), &project_path)!
	persisted_config := toml.parse_file(os.join_path(codex_home, 'config.toml'))!
	projects := persisted_config.value('projects').as_map()
	assert projects.value(loader.project_trust_key(&project_root)).value('trust_level').string() == 'trusted'
	_ := app_server.request_typed[api.ThreadStartResponse](api.ClientRequestThreadStart{
		request_id: api.RequestId{ kind: .integer, integer: 1 }
		params:     api.ThreadStartParams{ cwd: project_cwd.clone(), ephemeral: true }
	})!
	trusted_decision := read_remote_project_trust(app_server.request_handle(), &cwd_view)!
	assert !trusted_decision.has_value, 'trusted project must not prompt again'
	mut untrusted_project := trusted_project_edit(&project_path)
	untrusted_project.value = serde_json.Value.string('untrusted')
	_ := write_config_batch(app_server.request_handle(), [untrusted_project])!
	untrusted_decision := read_remote_project_trust(app_server.request_handle(), &cwd_view)!
	assert !untrusted_decision.has_value, 'untrusted decision must be preserved'
	response := app_server.request_typed[serde_json.Value](api.ClientRequestConfigRead{
		request_id: api.RequestId.string('untrusted-project-warning')
		params:     api.ConfigReadParams{ include_layers: true, cwd: project_cwd.clone() }
	})!
	layers := response.index(&config_update_test_layers_key)
	assert layers.is_array(), 'config layers'
	mut reason := ''
	for index in 0 .. layers.array_len()! {
		layer := layers.get_index(index)
		kind := layer.value.index(&config_update_test_name_key).index(&config_update_test_type_key).as_str()
		if kind.has_value && *kind.value == 'project' {
			reason = layer.value.index(&config_update_test_disabled_reason_key).string_owned()!
			break
		}
	}
	assert reason.len > 0, 'explicitly untrusted project warning'
	warning := history_cell.new_warning_event(reason.replace(loader.project_trust_key(&project_root), '<PROJECT>'))
	display_lines := warning.display_lines( /* width */
	80)
	mut rendered := []string{}
	for index in 0 .. display_lines.len {
		mut line := ''
		for span_index in 0 .. display_lines[index].spans.len {
			line += display_lines[index].spans[span_index].text
		}
		rendered << line
	}
	assert rendered.join('\n') == '⚠ <PROJECT> is marked as untrusted in the effective configuration. To load\n  project-local config, hooks, and exec policies, update its trust setting. If\n  that setting is managed by your organization, contact your administrator.'
	os.rm(os.join_path(project_cwd, '.codex/config.toml'))!
	os.rmdir(os.join_path(project_cwd, '.codex'))!
	canonical_project_cwd := os.join_path(loader.project_trust_key(&project_root), 'nested')
	canonical_view := std_path.Path.new(&canonical_project_cwd)
	_ := read_remote_project_trust(app_server.request_handle(), &canonical_view) or {
		assert err.msg().contains('explicitly untrusted project')
		app_server.shutdown()!
		return
	}
	assert false, 'an untrusted repository must not be overridden by its subdirectory'
}

fn test_format_config_error_preserves_server_validation_message() {
	failure := eyre.wrap_err(error('config/batchWrite failed: Invalid configuration: features.fast_mode=true violates managed requirements; allowed set [fast_mode=false]'), 'config/batchWrite failed in TUI')
	assert format_config_error(&failure) == 'config/batchWrite failed in TUI: config/batchWrite failed: Invalid configuration: features.fast_mode=true violates managed requirements; allowed set [fast_mode=false]'
}

fn test_alternate_error_display_preserves_root_and_multiple_contexts() {
	root := eyre.Report.new(error('root failure'))
	assert format_config_error(&root) == 'root failure'
	wrapped := eyre.wrap_err(eyre.wrap_err(root, 'inner context'), 'outer context')
	assert wrapped.msg() == 'outer context'
	assert format_config_error(&wrapped) == 'outer context: inner context: root failure'
	assert format_config_error(&wrapped) == 'outer context: inner context: root failure'
	assert wrapped.msg() == 'outer context'
	message := $if ownership ? { 'display text'.to_owned() } $else { 'display text'.clone() }
	assert format_config_error(&message) == 'display text'
	assert format_config_error(&message) == 'display text'
	assert message == 'display text'
}

fn test_config_edit_builders_preserve_values_and_order() {
	assert build_model_selection_edits[int](&config_update_test_model, OptionalEffort[int]{ has_value: true, value: 8 }) == [
		replace_config_value('model', serde_json.Value.string('gpt-test')),
		replace_config_value('model_reasoning_effort', serde_json.Value.string('8')),
	]
	assert build_model_selection_edits[string](&config_update_test_model, OptionalEffort[string]{ has_value: true, value: 'high' }) == [
		replace_config_value('model', serde_json.Value.string('gpt-test')),
		replace_config_value('model_reasoning_effort', serde_json.Value.string('high')),
	]
	assert build_model_selection_edits[string](&config_update_test_model, OptionalEffort[string]{}) == [
		replace_config_value('model', serde_json.Value.string('gpt-test')),
		clear_config_value('model_reasoning_effort'),
	]
	assert build_memory_settings_edits(true, false) == [
		replace_config_value('memories.use_memories', serde_json.Value.boolean(true)),
		replace_config_value('memories.generate_memories', serde_json.Value.boolean(false)),
	]
	assert build_oss_provider_edit(&config_update_test_provider) == replace_config_value('oss_provider', serde_json.Value.string('ollama'))
	assert build_feature_enabled_edit(&config_update_test_default_false_feature, false) == clear_config_value('features.memories')
	assert build_feature_enabled_edit(&config_update_test_default_false_feature, true) == replace_config_value('features.memories', serde_json.Value.boolean(true))
	assert build_feature_enabled_edit(&config_update_test_default_true_feature, false) == replace_config_value('features.fast_mode', serde_json.Value.boolean(false))
	assert build_feature_enabled_edit(&config_update_test_unknown_feature, false) == replace_config_value('features.unknown_feature', serde_json.Value.boolean(false))
}

fn test_service_tier_normalization_and_absence() {
	for input, expected in {
		'priority':    'fast'
		'fast':        'fast'
		'flex':        'flex'
		'default':     'default'
		'custom.tier': 'custom.tier'
		'':            ''
	} {
		borrow := BorrowedServiceTier{ has_value: true, value: &input }
		assert build_service_tier_selection_edits(&borrow) == [replace_config_value('service_tier', serde_json.Value.string(expected.clone()))]
	}
	assert build_service_tier_selection_edits(&BorrowedServiceTier{}) == [clear_config_value('service_tier')]
}

fn json_fixture(text &string) client.AppServerRequestHandle {
	return client.AppServerRequestHandle.config_update_json_fixture(serde_json.from_str(text) or { panic(err) }, api.EnvironmentInfoResponse{})
}

fn test_remote_project_trust_uses_last_disabled_layer_and_last_warning_separator() {
	response := '{"config":{"projects":{}},"layers":[{"name":{"type":"user"},"disabledReason":"wrong"},{"name":{"type":"project","dotCodexFolder":"/first/.codex"},"disabledReason":"disabled"},{"name":{"type":"project","dotCodexFolder":"/fallback/.codex"},"disabledReason":"To load policies, add /repo as a trusted project in sibling as a trusted project in /home/config.toml."}]}'
	path := std_path.Path.new(&config_update_test_nested_path)
	result := expect_project_trust(read_remote_project_trust(json_fixture(&response), &path)!)
	assert result == RemoteProjectTrust{ cwd: std_path.PathBuf.from('/repo/nested'), trust_target: std_path.PathBuf.from('/repo as a trusted project in sibling') }
}

fn test_remote_project_trust_falls_back_to_layer_path_and_cwd() {
	for folder, expected in {
		'/repo/.codex':     '/repo'
		'C:\\repo\\.codex': 'C:\\repo'
		'/bad/folder':      '/cwd'
	} {
		response := serde_json.Value.object({
			'layers': serde_json.Value.array_value([serde_json.Value.object({
				'name':           serde_json.Value.object({
					'type':           serde_json.Value.string('project')
					'dotCodexFolder': serde_json.Value.string(folder.clone())
				})
				'disabledReason': serde_json.Value.string('disabled')
			})])
		})
		handle := client.AppServerRequestHandle.config_update_json_fixture(response, api.EnvironmentInfoResponse{})
		path := std_path.Path.new(&config_update_test_cwd)
		result := expect_project_trust(read_remote_project_trust(handle, &path)!)
		assert result.trust_target == std_path.PathBuf.from(expected.clone())
	}
}

fn test_remote_project_trust_distinguishes_absent_null_and_nonstrings() {
	for text in [
		'{"layers":[{"name":{"type":"project"}}]}',
		'{"config":{"projects":{"/cwd":{"trust_level":"trusted"}}}}',
		'{"config":{"projects":{"/cwd":{"trust_level":"untrusted"}}}}',
		'{"config":{"projects":{"/repo":{"trust_level":"untrusted"}}},"layers":[{"name":{"type":"project"},"disabledReason":"/repo is marked as untrusted in the effective configuration."}]}',
	] {
		path := std_path.Path.new(&config_update_test_cwd)
		decision := read_remote_project_trust(json_fixture(&text), &path)!
		assert !decision.has_value, 'existing decision or enabled layer must not prompt'
	}
	for text in [
		'{"layers":[{"name":{"type":"project"},"disabledReason":null}]}',
		'{"layers":[{"name":{"type":"project"},"disabledReason":false}]}',
		'{"layers":null}',
		'{}',
		'{"config":{"projects":{"/cwd":{"trust_level":false}}}}',
	] {
		path := std_path.Path.new(&config_update_test_cwd)
		result := expect_project_trust(read_remote_project_trust(json_fixture(&text), &path)!)
		assert result == RemoteProjectTrust{ cwd: std_path.PathBuf.from('/cwd'), trust_target: std_path.PathBuf.from('/cwd') }
	}
}

fn test_remote_project_trust_untrusted_containment_respects_path_components() {
	text := '{"config":{"projects":{"/repo":{"trust_level":"untrusted"}}},"layers":[]}'
	for cwd in ['/repo/nested', '/repo/nested/deeper'] {
		path := std_path.Path.new(&cwd)
		_ := read_remote_project_trust(json_fixture(&text), &path) or {
			assert err.msg().contains('explicitly untrusted project')
			continue
		}
		assert false, 'untrusted descendants must error'
	}
	path := std_path.Path.new(&config_update_test_sibling_path)
	result := expect_project_trust(read_remote_project_trust(json_fixture(&text), &path)!)
	assert result.cwd == std_path.PathBuf.from('/repository')
}

fn test_typed_config_requests_preserve_ids_parameters_and_sequence() {
	response := serde_json.from_str(&config_update_test_config_json)!
	base := codex_utils_path_uri.PathUri.from_absolute_native_path(&config_update_test_environment_cwd, .posix) or { panic('base URI') }
	handle := client.AppServerRequestHandle.config_update_json_fixture(response, api.EnvironmentInfoResponse{ cwd: base })
	path := std_path.Path.new(&config_update_test_relative_project)
	trust := expect_project_trust(read_remote_project_trust(handle.clone(), &path)!)
	assert trust.cwd == std_path.PathBuf.from('/remote/project')
	effective := read_effective_config(handle.clone(), '/remote/project')!
	assert effective.config.additional['model'].string_owned()! == 'gpt-test'
	_ := write_config_batch(handle.clone(), [clear_config_value('service_tier')])!
	skill := codex_utils_absolute_path.from_absolute_path(&config_update_test_skill_path)!
	write_skill_enabled(handle.clone(), skill, false)!
	requests := handle.config_update_fixture_requests()
	assert requests.len == 5
	first := &(*requests)[0]
	assert first is api.ClientRequestEnvironmentInfo
	if first is api.ClientRequestEnvironmentInfo {
		assert first.request_id.string_value.starts_with('tui-environment-info-')
		assert first.params.environment_id == 'local'
	}
	second := &(*requests)[1]
	if second is api.ClientRequestConfigRead {
		assert second.request_id.string_value.starts_with('tui-project-trust-read-')
		assert second.params.include_layers
		assert second.params.cwd or { '' } == '/remote/project'
	} else {
		assert false
	}
	third := &(*requests)[2]
	if third is api.ClientRequestConfigRead {
		assert third.request_id.string_value.starts_with('tui-config-read-')
		assert !third.params.include_layers
	} else {
		assert false
	}
	fourth := &(*requests)[3]
	if fourth is api.ClientRequestConfigBatchWrite {
		assert fourth.request_id.string_value.starts_with('tui-config-write-')
		assert fourth.params.reload_user_config
		assert fourth.params.file_path == none
		assert fourth.params.expected_version == none
		assert fourth.params.edits == [clear_config_value('service_tier')]
	} else {
		assert false
	}
	fifth := &(*requests)[4]
	if fifth is api.ClientRequestSkillsConfigWrite {
		assert fifth.request_id.string_value.starts_with('tui-skill-config-write-')
		assert !fifth.params.enabled
		assert fifth.params.name == none
		assert (fifth.params.path or { panic('skill path') }).path == '/remote/skill/SKILL.md'
	} else {
		assert false
	}
}

fn test_remote_relative_cwd_errors_retain_context() {
	path := std_path.Path.new(&config_update_test_relative_path)
	_ := read_remote_project_trust(client.AppServerRequestHandle{}, &path) or {
		failure := IError(err)
		assert format_config_error(&failure).starts_with('environment/info failed while resolving remote project trust:')
		missing := client.AppServerRequestHandle.config_update_json_fixture(serde_json.Value{}, api.EnvironmentInfoResponse{})
		_ := read_remote_project_trust(missing, &path) or {
			assert err.msg() == 'remote app server did not provide a cwd'
			return
		}
		assert false, 'absent environment cwd must fail'
		return
	}
	assert false, 'untranslated runtime must fail'
}

fn test_borrowed_config_owners_remain_reusable() {
	app_id := $if ownership ? { 'plugin."quoted"'.to_owned() } $else { 'plugin."quoted"'.clone() }
	key := $if ownership ? { 'enabled'.to_owned() } $else { 'enabled'.clone() }
	provider := $if ownership ? { 'ollama'.to_owned() } $else { 'ollama'.clone() }
	tier := $if ownership ? { 'priority'.to_owned() } $else { 'priority'.clone() }
	model := $if ownership ? { 'gpt-test'.to_owned() } $else { 'gpt-test'.clone() }
	path_text := $if ownership ? { '/repo/"quoted"'.to_owned() } $else { '/repo/"quoted"'.clone() }
	path := std_path.Path.new(&path_text)
	borrow := BorrowedServiceTier{ has_value: true, value: &tier }
	trust_owner := RemoteProjectTrust{ cwd: std_path.PathBuf.from(path_text.clone()), trust_target: std_path.PathBuf.from('/repo') }
	lexical_equivalent := RemoteProjectTrust{ cwd: std_path.PathBuf.from('/repo//"quoted"/.'), trust_target: std_path.PathBuf.from('/repo/') }
	json_owner := serde_json.Value.object({
		'provider': serde_json.Value.string(provider.clone())
	})
	object_view := json_owner.as_object()
	for _ in 0 .. 2 {
		assert app_scoped_key_path(&app_id, &key) == 'apps."plugin.\\"quoted\\"".enabled'
		assert build_oss_provider_edit(&provider).value.string_owned()! == 'ollama'
		assert build_service_tier_selection_edits(&borrow)[0].value.string_owned()! == 'fast'
		assert build_model_selection_edits[string](&model, OptionalEffort[string]{})[0].value.string_owned()! == 'gpt-test'
		assert trusted_project_edit(&path).key_path == 'projects."/repo/\\"quoted\\"".trust_level'
		trust_copy := trust_owner.clone()
		assert trust_copy.equals(&trust_owner)
		assert trust_owner.equals(&lexical_equivalent)
		assert object_view.len() == 1
		object_key := object_view.key(0)
		assert *object_key == 'provider'
		assert object_view.get(object_key).value.string_owned()! == 'ollama'
	}
	assert app_id == 'plugin."quoted"'
	assert key == 'enabled'
	assert provider == 'ollama'
	assert tier == 'priority'
	assert model == 'gpt-test'
	assert path_text == '/repo/"quoted"'
	assert trust_owner.cwd.as_path().to_string_lossy() == path_text
	assert json_owner.to_string() == '{"provider":"ollama"}'
}

const config_update_test_app_id = 'plugin.linear'

const config_update_test_enabled_key = 'enabled'

const config_update_test_project_path = '/workspace/team.project'

const config_update_test_layers_key = 'layers'

const config_update_test_name_key = 'name'

const config_update_test_type_key = 'type'

const config_update_test_disabled_reason_key = 'disabledReason'

const config_update_test_model = 'gpt-test'

const config_update_test_provider = 'ollama'

const config_update_test_default_false_feature = 'memories'

const config_update_test_default_true_feature = 'fast_mode'

const config_update_test_unknown_feature = 'unknown_feature'

const config_update_test_nested_path = '/repo/nested'

const config_update_test_cwd = '/cwd'

const config_update_test_sibling_path = '/repository'

const config_update_test_config_json = '{"config":{"model":"gpt-test"},"layers":[]}'

const config_update_test_environment_cwd = '/remote/base'

const config_update_test_relative_project = '../project'

const config_update_test_skill_path = '/remote/skill/SKILL.md'

const config_update_test_relative_path = 'relative'

fn expect_project_trust(result RemoteProjectTrustOption) RemoteProjectTrust {
	assert result.has_value, 'expected a trust prompt'
	return result.value
}
