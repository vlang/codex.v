module codex_app_server_protocol

import codex_utils_absolute_path
import codex_utils_path_uri
import serde_json

// STUB: protocol/v2/config.rs::MergeStrategy retains both wire spellings.
pub enum MergeStrategy {
	replace
	upsert
}

// STUB: protocol/v2/config.rs::ConfigEdit's typed owned edit payload.
pub struct ConfigEdit {
pub mut:
	key_path       string
	value          serde_json.Value
	merge_strategy MergeStrategy
}

// STUB: ConfigEdit serialization preserves source camelCase names and nulls.
pub fn (edit &ConfigEdit) serialize_json() !string {
	return '{"keyPath":${serde_json.quote_string(&edit.key_path)},"value":${edit.value.to_string()},"mergeStrategy":"${edit.merge_strategy}"}'
}

// STUB: ConfigEdit::Clone for the in-memory RPC encoding/decoding boundary.
pub fn (edit &ConfigEdit) clone() ConfigEdit {
	return ConfigEdit{ key_path: edit.key_path.clone(), value: edit.value.clone(), merge_strategy: edit.merge_strategy }
}

// STUB: protocol/v2/config.rs::ConfigBatchWriteParams, including source reload
// and optimistic-version options rather than collapsing them into a write shim.
pub struct ConfigBatchWriteParams {
pub:
	edits              []ConfigEdit
	file_path          ?string
	expected_version   ?string
	reload_user_config bool
}

// STUB: ClientRequest::ConfigBatchWrite keeps its request id and typed params.
pub struct ClientRequestConfigBatchWrite {
pub:
	request_id RequestId
	params     ConfigBatchWriteParams
}

// STUB: protocol/v2/config.rs::WriteStatus.
pub enum WriteStatus {
	ok
	ok_overridden
}

// STUB: protocol/v2/config.rs::ConfigLayerSource payload variant tags.
pub enum ConfigLayerSourceKind {
	packaged_defaults
	mdm
	system
	enterprise_managed
	user
	project
	session_flags
	legacy_managed_config_toml_from_file
	legacy_managed_config_toml_from_mdm
}

// STUB: ConfigLayerSource's payload storage preserves typed native paths; only
// Project is inspected by config_update's runtime fixture.
pub struct ConfigLayerSource {
pub:
	kind             ConfigLayerSourceKind
	file             codex_utils_absolute_path.AbsolutePathBuf
	domain           string
	key              string
	id               string
	name             string
	profile          ?string
	dot_codex_folder codex_utils_absolute_path.AbsolutePathBuf
}

// STUB: protocol/v2/config.rs::ConfigLayerMetadata.
pub struct ConfigLayerMetadata {
pub:
	name    ConfigLayerSource
	version string
}

// STUB: protocol/v2/config.rs::OverriddenMetadata.
pub struct OverriddenMetadata {
pub:
	message          string
	overriding_layer ConfigLayerMetadata
	effective_value  serde_json.Value
}

// STUB: protocol/v2/config.rs::ConfigWriteResponse retains the entire result
// shape, including canonical output path and optional override metadata.
pub struct ConfigWriteResponse {
pub:
	status              WriteStatus
	version             string
	file_path           codex_utils_absolute_path.AbsolutePathBuf
	overridden_metadata ?OverriddenMetadata
}

// STUB: protocol/v2/environment.rs::EnvironmentInfoParams.
pub struct EnvironmentInfoParams {
pub:
	environment_id string
}

// STUB: protocol/v2/environment.rs::EnvironmentShellInfo.
pub struct EnvironmentShellInfo {
pub:
	name string
	path string
}

// STUB: protocol/v2/environment.rs::EnvironmentInfoResponse's typed shell/cwd.
pub struct EnvironmentInfoResponse {
pub:
	shell EnvironmentShellInfo
	cwd   ?codex_utils_path_uri.PathUri
}

// STUB: ClientRequest::EnvironmentInfo keeps the executor environment selector.
pub struct ClientRequestEnvironmentInfo {
pub:
	request_id RequestId
	params     EnvironmentInfoParams
}

// STUB: protocol/v2/plugin.rs::SkillsConfigWriteParams preserves both selectors.
pub struct SkillsConfigWriteParams {
pub:
	path    ?codex_utils_absolute_path.AbsolutePathBuf
	name    ?string
	enabled bool
}

// STUB: protocol/v2/plugin.rs::SkillsConfigWriteResponse.
pub struct SkillsConfigWriteResponse {
pub:
	effective_enabled bool
}

// STUB: ClientRequest::SkillsConfigWrite keeps its typed source RPC payload.
pub struct ClientRequestSkillsConfigWrite {
pub:
	request_id RequestId
	params     SkillsConfigWriteParams
}
