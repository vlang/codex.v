// App-server-backed config update helpers for the TUI.
//
// This module centralizes the small typed update helpers the TUI uses
// when a config mutation must be owned by the app server rather than written
// to the local `config.toml` directly.
module config_update

import codex_app_server_client
import codex_app_server_protocol as api
import codex_config.loader
import codex_exec_server
import codex_features
import codex_protocol.config_types
import codex_utils_absolute_path
import codex_utils_path_uri
import color_eyre.eyre
import serde_json
import std_path
import uuid

pub struct RemoteProjectTrust {
pub:
	cwd          std_path.PathBuf
	trust_target std_path.PathBuf
}

pub fn (trust &RemoteProjectTrust) clone() RemoteProjectTrust {
	return RemoteProjectTrust{ cwd: trust.cwd.clone(), trust_target: trust.trust_target.clone() }
}

pub fn (trust &RemoteProjectTrust) equals(other &RemoteProjectTrust) bool {
	return trust.cwd.equals(&other.cwd) && trust.trust_target.equals(&other.trust_target)
}

pub fn replace_config_value(key_path string, value serde_json.Value) api.ConfigEdit {
	return api.ConfigEdit{ key_path: key_path, value: value, merge_strategy: .replace }
}

pub fn clear_config_value(key_path string) api.ConfigEdit {
	return replace_config_value(key_path, serde_json.Value{})
}

pub fn app_scoped_key_path(app_id &string, key_path &string) string {
	quoted_app_id := serde_json.Value.string(app_id.clone()).to_string()
	return 'apps.${quoted_app_id}.${*key_path}'
}

pub fn format_config_error[T](err &T) string {
	$if T is IError {
		return eyre.alternate_display(err)
	} $else $if T is eyre.Report {
		if err.is_root { return eyre.alternate_display(&err.source) }
		return '${err.context}: ${eyre.alternate_display(&err.source)}'
	} $else $if T is string {
		return err.clone()
	} $else {
		return err.str()
	}
}

fn trusted_project_edit(project_path &std_path.Path) api.ConfigEdit {
	project_string := project_path.to_string_lossy()
	project_key := loader.project_trust_key(&project_string).replace('\\', '\\\\').replace('"', '\\"')
	return replace_config_value('projects."${project_key}".trust_level', serde_json.Value.string(config_types.TrustLevel.trusted.str()))
}

// V3 currently retains the optional type when unwrapping a generic ?T during
// C generation. The explicit tag preserves Rust's owned Option<impl ToString>.
pub struct OptionalEffort[T] {
pub:
	has_value bool
	value     T
}

pub fn build_model_selection_edits[T](model &string, effort OptionalEffort[T]) []api.ConfigEdit {
	effort_edit := if effort.has_value {
		// Rust's ToString allocates even for String. Preserve that owned boundary.
		text := $if T is string { effort.value.clone() } $else { effort.value.str() }
		replace_config_value('model_reasoning_effort', serde_json.Value.string(text))
	} else {
		clear_config_value('model_reasoning_effort')
	}
	return [replace_config_value('model', serde_json.Value.string(model.clone())), effort_edit]
}

// V cannot safely form &?string. This wrapper borrows the optional request value
// without moving its owner; the returned ConfigEdit owns the JSON string.
pub struct BorrowedServiceTier {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

pub fn build_service_tier_selection_edits(service_tier &BorrowedServiceTier) []api.ConfigEdit {
	service_tier_edit := if service_tier.has_value {
		mut config_value := service_tier.value.clone()
		if *service_tier.value != config_types.service_tier_default_request_value {
			if tier := config_types.ServiceTier.from_request_value(service_tier.value) {
				config_value = match tier {
					.fast { 'fast' }
					.flex { 'flex' }
				}
			}
		}
		replace_config_value('service_tier', serde_json.Value.string(config_value))
	} else {
		clear_config_value('service_tier')
	}
	return [service_tier_edit]
}

$if windows {
	pub fn build_windows_sandbox_mode_edits(elevated_enabled bool) []api.ConfigEdit {
		feature_key_path := fn (feature &string) string { return 'features.${*feature}' }
		return [
			replace_config_value('windows.sandbox', serde_json.Value.string(if elevated_enabled {
				'elevated'
			} else {
				'unelevated'
			})),
			clear_config_value(feature_key_path(&config_update_experimental_windows_sandbox)),
			clear_config_value(feature_key_path(&config_update_elevated_windows_sandbox)),
			clear_config_value(feature_key_path(&config_update_enable_experimental_windows_sandbox)),
		]
	}
}

pub fn build_feature_enabled_edit(feature_key &string, enabled bool) api.ConfigEdit {
	key_path := 'features.${*feature_key}'
	mut is_default_false_feature := false
	for index in 0 .. codex_features.features.len {
		spec := &codex_features.features[index]
		if spec.key == *feature_key {
			is_default_false_feature = !spec.default_enabled
			break
		}
	}
	if enabled || !is_default_false_feature {
		return replace_config_value(key_path, serde_json.Value.boolean(enabled))
	}
	return clear_config_value(key_path)
}

pub fn build_memory_settings_edits(use_memories bool, generate_memories bool) []api.ConfigEdit {
	return [
		replace_config_value('memories.use_memories', serde_json.Value.boolean(use_memories)),
		replace_config_value('memories.generate_memories', serde_json.Value.boolean(generate_memories)),
	]
}

pub fn build_oss_provider_edit(provider &string) api.ConfigEdit {
	return replace_config_value('oss_provider', serde_json.Value.string(provider.clone()))
}

// Rust's async RPC boundary is synchronous until the app-server runtime is ported.
pub fn write_config_batch(request_handle codex_app_server_client.AppServerRequestHandle, edits []api.ConfigEdit) !api.ConfigWriteResponse {
	request_id := api.RequestId.string('tui-config-write-${uuid.Uuid.new_v4()}')
	return request_handle.request_typed[api.ConfigWriteResponse](api.ClientRequestConfigBatchWrite{
		request_id: request_id
		params:     api.ConfigBatchWriteParams{ edits: edits, file_path: none, expected_version: none, reload_user_config: true }
	}) or { return eyre.wrap_err(err, 'config/batchWrite failed in TUI') }
}

pub fn write_trusted_project(request_handle codex_app_server_client.AppServerRequestHandle, project_path &std_path.Path) !api.ConfigWriteResponse {
	return write_config_batch(request_handle, [trusted_project_edit(project_path)])
}

pub fn read_effective_config(request_handle codex_app_server_client.AppServerRequestHandle, cwd string) !api.ConfigReadResponse {
	request_id := api.RequestId.string('tui-config-read-${uuid.Uuid.new_v4()}')
	return request_handle.request_typed[api.ConfigReadResponse](api.ClientRequestConfigRead{
		request_id: request_id
		params:     api.ConfigReadParams{ include_layers: false, cwd: cwd }
	}) or { return eyre.wrap_err(err, 'config/read failed in TUI') }
}

// V cannot nest Result<Option<owned type>>. Preserve the two success variants
// with an explicit presence tag and keep errors in the ordinary Result channel.
pub struct RemoteProjectTrustOption {
pub:
	has_value bool
	value     RemoteProjectTrust
}

pub fn read_remote_project_trust(request_handle codex_app_server_client.AppServerRequestHandle, cwd_path &std_path.Path) !RemoteProjectTrustOption {
	cwd_string := cwd_path.to_string_lossy()
	legacy_cwd := codex_utils_path_uri.LegacyAppPathString.from_string(cwd_string.clone())
	cwd_uri := if path := legacy_cwd.to_inferred_path_uri() {
		path
	} else {
		request_id := api.RequestId.string('tui-environment-info-${uuid.Uuid.new_v4()}')
		environment := request_handle.request_typed[api.EnvironmentInfoResponse](api.ClientRequestEnvironmentInfo{
			request_id: request_id
			params:     api.EnvironmentInfoParams{ environment_id: codex_exec_server.local_environment_id.clone() }
		}) or { return eyre.wrap_err(err, 'environment/info failed while resolving remote project trust') }
		environment_cwd := environment.cwd or { return error('remote app server did not provide a cwd') }
		environment_cwd.join(&cwd_string) or { return eyre.wrap_err(err, 'failed to resolve the remote project directory') }
	}
	cwd := cwd_uri.inferred_native_path_string()
	request_id := api.RequestId.string('tui-project-trust-read-${uuid.Uuid.new_v4()}')
	response := request_handle.request_typed[serde_json.Value](api.ClientRequestConfigRead{
		request_id: request_id
		params:     api.ConfigReadParams{ include_layers: true, cwd: cwd.clone() }
	}) or { return eyre.wrap_err(err, 'config/read failed while checking remote project trust') }
	layers := response.index(&config_update_layers)
	mut project_layers := []int{}
	if layers.is_array() {
		for index in 0 .. layers.array_len() or { 0 } {
			layer := layers.get_index(index)
			kind := layer.value.index(&config_update_name).index(&config_update_type).as_str()
			if kind.has_value && *kind.value == 'project' { project_layers << index }
		}
	}
	mut disabled_project := -1
	for index := project_layers.len - 1; index >= 0; index-- {
		layer := layers.get_index(project_layers[index])
		if layer.value.index(&config_update_disabled_reason).as_str().has_value {
			disabled_project = project_layers[index]
			break
		}
	}
	disabled_layer := layers.get_index(disabled_project)
	disabled_reason := if disabled_layer.has_value {
		disabled_layer.value.index(&config_update_disabled_reason).as_str()
	} else {
		serde_json.BorrowedString{}
	}
	// Rust holds &str slices into the response/cwd. V owns substring results, so
	// materialize the trust target explicitly before constructing the owned paths.
	mut trust_target := cwd.clone()
	mut found_target := false
	if disabled_reason.has_value {
		if split := disabled_reason.value.index(', add ') {
			remainder := (*disabled_reason.value)[split + 6..]
			if end := remainder.last_index(' as a trusted project in ') {
				trust_target = remainder[..end].clone()
				found_target = true
			}
		}
	}
	if !found_target && disabled_layer.has_value {
		folder := disabled_layer.value.index(&config_update_name).index(&config_update_dot_codex_folder).as_str()
		if folder.has_value && (folder.value.ends_with('/.codex') || folder.value.ends_with('\\.codex')) {
			trust_target = (*folder.value)[..folder.value.len - 7].clone()
		}
	}
	projects := response.index(&config_update_config).index(&config_update_projects).as_object()
	project := projects.get(&trust_target)
	level := if project.has_value {
		project.value.index(&config_update_trust_level).as_str()
	} else {
		serde_json.BorrowedString{}
	}
	has_trust_decision := level.has_value && *level.value in ['trusted', 'untrusted']
	mut explicitly_untrusted := false
	if disabled_reason.has_value {
		for index in 0 .. projects.len() {
			path := projects.key(index)
			entry := projects.get(path)
			project_level := entry.value.index(&config_update_trust_level).as_str()
			if project_level.has_value && *project_level.value == 'untrusted'
				&& disabled_reason.value.starts_with(*path)
				&& (*disabled_reason.value)[path.len..].starts_with(' is marked as untrusted') {
				explicitly_untrusted = true
				break
			}
		}
	}
	mut enabled_project := false
	if disabled_project == -1 {
		for index in project_layers {
			layer := layers.get_index(index)
			if !layer.value.get(&config_update_disabled_reason).has_value {
				enabled_project = true
				break
			}
		}
	}
	if has_trust_decision || explicitly_untrusted || enabled_project {
		return RemoteProjectTrustOption{}
	}
	if project_layers.len == 0 {
		for index in 0 .. projects.len() {
			path := projects.key(index)
			entry := projects.get(path)
			project_level := entry.value.index(&config_update_trust_level).as_str()
			if project_level.has_value && *project_level.value == 'untrusted' {
				project_path := codex_utils_path_uri.LegacyAppPathString.from_string(path.clone())
				if project_uri := project_path.to_inferred_path_uri() {
					if cwd_uri.starts_with(&project_uri) {
						return error('remote project directory is inside an explicitly untrusted project; pass the repository root explicitly with --cd')
					}
				}
			}
		}
	}
	return RemoteProjectTrustOption{ has_value: true, value: RemoteProjectTrust{ cwd: std_path.PathBuf.from(cwd.clone()), trust_target: std_path.PathBuf.from(trust_target) } }
}

pub fn write_skill_enabled(request_handle codex_app_server_client.AppServerRequestHandle, path codex_utils_absolute_path.AbsolutePathBuf, enabled bool) ! {
	request_id := api.RequestId.string('tui-skill-config-write-${uuid.Uuid.new_v4()}')
	_ := request_handle.request_typed[api.SkillsConfigWriteResponse](api.ClientRequestSkillsConfigWrite{
		request_id: request_id
		params:     api.SkillsConfigWriteParams{ path: path, name: none, enabled: enabled }
	}) or { return eyre.wrap_err(err, 'skills/config/write failed in TUI') }
}

const config_update_experimental_windows_sandbox = 'experimental_windows_sandbox'

const config_update_elevated_windows_sandbox = 'elevated_windows_sandbox'

const config_update_enable_experimental_windows_sandbox = 'enable_experimental_windows_sandbox'

const config_update_layers = 'layers'

const config_update_name = 'name'

const config_update_type = 'type'

const config_update_disabled_reason = 'disabledReason'

const config_update_dot_codex_folder = 'dotCodexFolder'

const config_update_config = 'config'

const config_update_projects = 'projects'

const config_update_trust_level = 'trust_level'
