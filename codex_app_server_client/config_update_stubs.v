module codex_app_server_client

import codex_app_server_protocol as api
import codex_core
import codex_utils_absolute_path
import codex_utils_path_uri
import os
import serde_json
import sync
import toml

// STUB: shared typed config RPC fixture. Native JSON-RPC transport, layered
// configuration, and thread startup are untranslated. Embedded tests use actual
// local config files and lexical repository discovery through this boundary.
@[heap]
struct ConfigUpdateFixture {
	mutex         &sync.Mutex = sync.new_mutex()
	embedded      bool
	codex_home    string
	environment   api.EnvironmentInfoResponse
	json_response serde_json.Value
mut:
	requests []api.ClientRequest
	shutdown bool
}

// STUB: native embedded app-server startup's smallest config test boundary.
pub fn AppServerRequestHandle.config_update_embedded_fixture(config &codex_core.Config) !AppServerRequestHandle {
	config_path := os.join_path(config.codex_home, 'config.toml')
	_ := toml.parse_file(config_path)!
	native_cwd := os.getwd()
	uri := codex_utils_path_uri.PathUri.from_absolute_native_path(&native_cwd, codex_utils_path_uri.PathConvention.native()) or { return error('failed to determine environment cwd') }
	return AppServerRequestHandle{ config_update_fixture: &ConfigUpdateFixture{ embedded: true, codex_home: config.codex_home.clone(), environment: api.EnvironmentInfoResponse{ cwd: uri } } }
}

// STUB: typed config/read and environment/info oracle for pure remote trust
// transitions; target code still issues the individual source-shaped RPCs.
pub fn AppServerRequestHandle.config_update_json_fixture(response serde_json.Value, environment api.EnvironmentInfoResponse) AppServerRequestHandle {
	return AppServerRequestHandle{ config_update_fixture: &ConfigUpdateFixture{ json_response: response, environment: environment } }
}

// STUB: source-owned AppServerClient's observed InProcess variant boundary.
pub struct AppServerClient {
	handle AppServerRequestHandle
}

// STUB: AppServerClient::InProcess consumes its embedded client handle.
pub fn AppServerClient.in_process(handle AppServerRequestHandle) AppServerClient {
	return AppServerClient{ handle: handle }
}

// STUB: AppServerClient::request_handle clones the shared request sender.
pub fn (client &AppServerClient) request_handle() AppServerRequestHandle {
	return client.handle.clone()
}

// STUB: AppServerClient::request_typed delegates each concrete RPC unchanged.
pub fn (client &AppServerClient) request_typed[T](request api.ClientRequest) !T {
	return client.handle.request_typed[T](request)
}

// STUB: AppServerClient::shutdown releases this in-memory client only.
pub fn (client AppServerClient) shutdown() ! {
	if client.handle.config_update_fixture == unsafe { nil } {
		return error('app-server client is not available')
	}
	mut fixture := client.handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.shutdown = true
}

// STUB: typed observations are borrowed and retain request payloads/ordering.
pub fn (handle &AppServerRequestHandle) config_update_fixture_requests() &[]api.ClientRequest {
	return &handle.config_update_fixture.requests
}

// STUB: unavailable native transports fail explicitly before any fake success.
fn (handle &AppServerRequestHandle) config_update_fixture_available(method string) ! {
	if handle.config_update_fixture == unsafe { nil } {
		return TypedRequestError{ kind: .transport, method: method, transport_source: error('app-server client is not available') }
	}
	if handle.config_update_fixture.shutdown { return error('app-server client has shut down') }
}

// STUB: config/read's untyped JSON decoding API preserves missing, null, and
// malformed fields rather than imposing the typed response schema on the target.
fn (handle &AppServerRequestHandle) config_update_request_config_read_json(request api.ClientRequestConfigRead) !serde_json.Value {
	handle.config_update_fixture_available('config/read')!
	cwd := if value := request.params.cwd { value.clone() } else { os.getwd() }
	mut fixture := handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << request
	if !fixture.embedded { return fixture.json_response.clone() }
	return config_update_embedded_read(fixture, &cwd)
}

// STUB: config/read's typed response retains the effective Config owner.
fn (handle &AppServerRequestHandle) config_update_request_config_read(request api.ClientRequestConfigRead) !api.ConfigReadResponse {
	response := handle.config_update_request_config_read_json(request)!
	config := response.index(&config_update_config)
	keys := config.object_keys() or { []string{} }
	mut additional := map[string]serde_json.Value{}
	for index in 0 .. keys.len {
		key := &keys[index]
		additional[key.clone()] = config.index(key).clone()
	}
	return api.ConfigReadResponse{ config: api.Config{ additional: additional } }
}

// STUB: environment/info returns a fresh owned URI decoded from the fixture.
fn (handle &AppServerRequestHandle) request_environment_info(request api.ClientRequestEnvironmentInfo) !api.EnvironmentInfoResponse {
	handle.config_update_fixture_available('environment/info')!
	mut fixture := handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << request
	return api.EnvironmentInfoResponse{
		shell: api.EnvironmentShellInfo{ name: fixture.environment.shell.name.clone(), path: fixture.environment.shell.path.clone() }
		cwd:   if cwd := fixture.environment.cwd {
			cwd.clone()
		} else {
			none
		}
	}
}

// STUB: config/batchWrite consumes each typed edit in order, persisting the
// source integration test's project trust field to its actual local config file.
fn (handle &AppServerRequestHandle) request_config_batch_write(request api.ClientRequestConfigBatchWrite) !api.ConfigWriteResponse {
	handle.config_update_fixture_available('config/batchWrite')!
	mut fixture := handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	if fixture.embedded { config_update_persist_trust(fixture, &request.params)! }
	fixture.requests << request
	file_path := if fixture.embedded {
		os.join_path(fixture.codex_home, 'config.toml')
	} else {
		os.join_path(os.getwd(), 'config.toml')
	}
	return api.ConfigWriteResponse{ status: .ok, version: 'fixture-version', file_path: codex_utils_absolute_path.from_absolute_path(&file_path)! }
}

// STUB: skills/config/write is an in-memory typed RPC response only. No live
// skill configuration is changed before its native dependency is translated.
fn (handle &AppServerRequestHandle) request_skills_config_write(request api.ClientRequestSkillsConfigWrite) !api.SkillsConfigWriteResponse {
	handle.config_update_fixture_available('skills/config/write')!
	enabled := request.params.enabled
	mut fixture := handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.requests << request
	return api.SkillsConfigWriteResponse{ effective_enabled: enabled }
}

// STUB: thread/start validates an explicitly trusted repository using the same
// actual fixture config file, then returns its typed ephemeral thread response.
fn (handle &AppServerRequestHandle) config_update_request_thread_start(request api.ClientRequestThreadStart) !api.ThreadStartResponse {
	handle.config_update_fixture_available('thread/start')!
	cwd := if value := request.params.cwd { value.clone() } else { os.getwd() }
	mut fixture := handle.config_update_fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	if !fixture.embedded {
		return error('thread/start is not implemented by the JSON config fixture')
	}
	response := config_update_embedded_read(fixture, &cwd)!
	root := config_update_repository_root(&cwd)
	trust := response.index(&config_update_config).index(&config_update_projects).index(&root).index(&config_update_trust_level).as_str()
	if !trust.has_value || *trust.value != 'trusted' {
		return error('project directory is not trusted')
	}
	ephemeral := request.params.ephemeral or { false }
	fixture.requests << request
	return api.ThreadStartResponse{ thread: api.Thread{ id: 'config-update-thread', ephemeral: ephemeral }, cwd: cwd }
}

// STUB: find the repository root by walking actual .git directory boundaries.
fn config_update_repository_root(cwd &string) string {
	mut path := cwd.clone()
	for {
		if os.exists(os.join_path(path.clone(), '.git')) { return path }
		parent := os.dir(path.clone())
		if parent == path || parent.len == 0 { return cwd.clone() }
		path = parent
	}
	return cwd.clone()
}

// STUB: config-loader's project trust and .codex layer discovery boundary. It
// reads current files on every call, preserving changes and layer disappearance.
fn config_update_embedded_read(fixture &ConfigUpdateFixture, cwd &string) !serde_json.Value {
	path := os.join_path(fixture.codex_home, 'config.toml')
	doc := toml.parse_file(path)!
	projects := doc.value('projects').as_map()
	mut project_values := map[string]serde_json.Value{}
	for project_path, value in projects {
		level := value.value('trust_level')
		mut fields := map[string]serde_json.Value{}
		if level is string { fields['trust_level'] = serde_json.Value.string(level.clone()) }
		project_values[project_path] = serde_json.Value.object(fields)
	}
	root := config_update_repository_root(cwd)
	mut response_projects := serde_json.Value.object(project_values)
	trust := response_projects.index(&root).index(&config_update_trust_level).as_str()
	mut layers := []serde_json.Value{}
	mut current := cwd.clone()
	for {
		folder := os.join_path(current.clone(), '.codex')
		if os.exists(os.join_path(folder, 'config.toml')) {
			mut layer := map[string]serde_json.Value{}
			layer['name'] = serde_json.Value.object({
				'type':           serde_json.Value.string('project')
				'dotCodexFolder': serde_json.Value.string(folder.clone())
			})
			if !trust.has_value || *trust.value != 'trusted' {
				reason := if trust.has_value && *trust.value == 'untrusted' {
					'${root} is marked as untrusted in the effective configuration. To load project-local config, hooks, and exec policies, update its trust setting. If that setting is managed by your organization, contact your administrator.'
				} else {
					'To load project-local config, hooks, and exec policies, add ${root} as a trusted project in ${path}.'
				}
				layer['disabledReason'] = serde_json.Value.string(reason)
			}
			layers << serde_json.Value.object(layer)
		}
		if current == root { break }
		parent := os.dir(current.clone())
		if parent == current { break }
		current = parent
	}
	layers.reverse_in_place()
	return serde_json.Value.object({
		'layers': serde_json.Value.array_value(layers)
		'config': serde_json.Value.object({
			'projects': response_projects
		})
	})
}

// STUB: config batch editing for the source test's project trust selector only.
// Other write behavior fails explicitly instead of fabricating an implementation.
fn config_update_persist_trust(fixture &ConfigUpdateFixture, params &api.ConfigBatchWriteParams) ! {
	path := os.join_path(fixture.codex_home, 'config.toml')
	if params.file_path != none || params.expected_version != none {
		return error('fixture does not implement alternate config files or expected versions')
	}
	for index in 0 .. params.edits.len {
		edit := &params.edits[index]
		if !edit.key_path.starts_with('projects.') || !edit.key_path.ends_with('.trust_level') || edit.merge_strategy != .replace {
			return error('fixture only implements project trust replacement')
		}
		quoted_path := edit.key_path[9..edit.key_path.len - 12]
		project_value := serde_json.from_str(&quoted_path)!
		project_path := project_value.string_owned()!
		level := edit.value.string_owned()!
		doc := toml.parse_file(path.clone())!
		mut root := doc.to_any().as_map()
		mut projects := root.clone().value('projects').as_map()
		mut project := projects.clone().value(project_path.clone()).as_map()
		project['trust_level'] = toml.Any(level)
		projects[project_path] = toml.Any(project)
		root['projects'] = toml.Any(projects)
		os.write_file(path.clone(), root.to_toml())!
	}
}

// STUB: borrowed JSON field/request key for config_update RPC fixtures.
const config_update_config = 'config'

// STUB: borrowed JSON field/request key for config_update RPC fixtures.
const config_update_projects = 'projects'

// STUB: borrowed JSON field/request key for config_update RPC fixtures.
const config_update_trust_level = 'trust_level'
