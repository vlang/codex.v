module request_processors

import codex_app_server as app_server
import codex_app_server_protocol as api
import codex_app_server.config_manager as app_config_manager
import codex_app_server.outgoing_message as app_outgoing
import codex_app_server.thread_lifecycle
import codex_app_server.thread_state as app_thread_state
import codex_app_server.filters as app_filters
import codex_app_server.persisted_resume_settings
import codex_core
import codex_config.loader as config_loader
import codex_extension_api
import codex_features
import codex_login
import codex_protocol
import codex_tools
import codex_memories_write
import codex_rollout
import codex_thread_store as store
import codex_utils_absolute_path
import codex_utils_absolute_path.path_utils
import os
import strconv
import sync
import time
import tracing
import x.json2

pub const thread_list_default_limit = 25
pub const thread_list_max_limit = 100

const codex_tui_client_name = 'codex-tui'
const thread_rollback_deprecation_summary = 'thread/rollback is deprecated and will be removed soon'
const paginated_full_history_deprecation_summary = 'Full-history hydration is deprecated for paginated threads; use `excludeTurns: true`, then page with `thread/turns/list` and `thread/items/list`.'
const paginated_thread_read_deprecation_summary = 'Full-history hydration is deprecated for paginated threads; omit `includeTurns` or set it to `false`, then page with `thread/turns/list` and `thread/items/list`.'

const dynamic_tool_name_max_len = 128
const dynamic_tool_namespace_max_len = 64
const dynamic_tool_namespace_description_max_len = 1024
const dynamic_tool_identifier_pattern = '^[a-zA-Z0-9_-]+$'
const reserved_responses_namespaces = [
	'api_tool',
	'browser',
	'computer',
	'container',
	'file_search',
	'functions',
	'image_gen',
	'multi_tool_use',
	'python',
	'python_user_visible',
	'submodel_delegator',
	'terminal',
	'tool_search',
	'web',
]

const thread_turns_default_limit = 25
const thread_turns_max_limit = 100
const thread_items_default_limit = 25
const thread_items_max_limit = 100
const thread_search_occurrences_default_limit = 50
const thread_search_occurrences_max_limit = 250

// OptionalStringMap is the explicit V representation of Rust's
// `Option<HashMap<String, serde_json::Value>>`. Values are serialized JSON at the untranslated
// serde boundary.
pub struct OptionalStringMap {
pub mut:
	has_value bool
	value     map[string]string
}

// OptionalStringArray preserves the distinction between no cwd filter and an empty filter list.
pub struct OptionalStringArray {
pub:
	has_value bool
	value     []string
}

// OptionalThreadId is the explicit V representation of Rust's
// `Result<Option<ThreadId>, JSONRPCErrorError>` success value. V 0.5.2 cannot parse a qualified
// optional type directly behind `!`.
struct OptionalThreadId {
	has_value bool
	value     codex_protocol.ThreadId
}

// OptionalClientResponsePayload preserves the difference between handlers that send their own
// response and handlers that return a response payload. It adapts Rust's `Result<Option<_>, _>`
// because V 0.5.2 does not support nesting an Option directly in a Result signature.
pub struct OptionalClientResponsePayload {
pub:
	has_value bool
	value     api.ClientResponsePayload
}

// OptionalApiThread adapts `Result<Option<Thread>, ThreadReadViewError>` at the V compiler
// boundary while retaining the source's two success states.
struct OptionalApiThread {
	has_value bool
	value     api.Thread
}

// OptionalStoredThread adapts `Result<Option<StoredThread>, ThreadReadViewError>` without
// conflating a missing persisted record with an error.
struct OptionalStoredThread {
	has_value bool
	value     store.StoredThread
}

// OptionalCursorPair is the V representation of the two optional cursors returned together by
// Rust's `Result<(Option<String>, Option<String>), _>`.
pub struct OptionalCursorPair {
pub:
	turns ?string
	items ?string
}

// StoreThreadMetadataPatch is consumed when pending metadata is staged.
pub struct StoreThreadMetadataPatch {
pub:
	project_id       store.ClearableString
	name             store.ClearableString
	daybreak_enabled ?bool
}

fn (patch &StoreThreadMetadataPatch) is_empty() bool {
	return !patch.project_id.has_value && !patch.name.has_value && patch.daybreak_enabled == none
}

fn clearable_string_from_optional(value ?string) store.ClearableString {
	if item := value {
		return store.ClearableString{ has_value: true, value: item.clone() }
	}
	return store.ClearableString{}
}

fn stage_pending_thread_metadata(
	thread_manager &ThreadManager,
	thread_store &store.ThreadStore,
	patch StoreThreadMetadataPatch,
	operation &string
) !OptionalThreadId {
	if patch.is_empty() {
		return OptionalThreadId{}
	}
	thread_id := thread_manager.reserve_thread_id()
	stage_result := thread_store.stage_pending_thread_metadata(copy_thread_id(&thread_id), store.ThreadMetadataPatch{
		name:             patch.name
		project_id:       patch.project_id
		daybreak_enabled: patch.daybreak_enabled
	})
	if stage_result.is_error {
		error_value := clone_thread_store_error(&stage_result.error_value)
		return fail(match error_value.kind {
			.unsupported { method_not_found('${*operation} is unavailable without sqlite state') }
			.invalid_request { invalid_request(error_value.message) }
			.thread_not_found, .conflict, .internal {
				internal_error('failed to stage ${*operation} metadata: ${error_value.message}')
			}
		})
	}
	return OptionalThreadId{
		has_value: true
		value:     thread_id
	}
}

fn remove_pending_thread_metadata(
	thread_store &store.ThreadStore,
	thread_id ?codex_protocol.ThreadId
) {
	if id := thread_id {
		remove_result := thread_store.remove_pending_thread_metadata(id)
		if remove_result.is_error {
			message := 'failed to remove staged thread metadata for ${remove_result.error_value.thread_id.value}: ${remove_result.error_value.message}'
			tracing.warn(&message)
		}
	}
}

struct ThreadListFilters {
	model_providers   ?[]string
	source_kinds      ?[]api.ThreadSourceKind
	archived          bool
	section_id        api.ClearableString
	project_id        api.ClearableString
	cwd_filters       OptionalStringArray
	search_term       ?string
	use_state_db_only bool
	relation_filter   ?store.ThreadRelationFilter
}

// Persisted inputs that can change while loading configuration without the metadata permit.
struct ResumeConfigState {
	history_cwd        ?string
	persisted_metadata ?ThreadMetadata
	persisted_settings ?PersistedResumeSettings
}

struct PreparedResumeConfig {
	state  ResumeConfigState
	config Config
}

// OptionalPreparedResumeConfig replaces `&mut Option<PreparedResumeConfig>` because V 0.5.2's
// ownership checker lowers mutable optional parameters as nested references.
struct OptionalPreparedResumeConfig {
mut:
	has_value bool
	value     PreparedResumeConfig
}

// ResumeControlFlow mirrors Rust's `ControlFlow<()>`: configuration may be prepared outside the
// thread-list permit and then the request retries its mutation phase.
enum ResumeControlFlow {
	continue_loop
	stop
}

struct ThreadRevertRuntimeSnapshot {
	config                Config
	settings              CodexThreadSettingsOverrides
	client_mcp_extensions ClientMcpExtensions
}

// ThreadListStateSemaphore preserves the source's shared one-permit mutation gate.
pub struct ThreadListStateSemaphore {
pub:
	state &ThreadListStateSemaphoreState = unsafe { nil }
}

pub struct ThreadListStateSemaphoreState {
pub mut:
	mutex  sync.Mutex
	closed bool
}

pub struct ThreadListStatePermit {
pub:
	state &ThreadListStateSemaphoreState = unsafe { nil }
}

pub fn (permit &ThreadListStatePermit) release() {
	if !isnil(permit.state) {
		permit.state.mutex.unlock()
	}
}

fn invalid_params(message string) api.JSONRPCErrorError {
	return api.JSONRPCErrorError{
		code:    -32602
		message: message
	}
}

fn is_rust_unicode_whitespace(value rune) bool {
	return value in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `\u0085`, `\u00a0`, `\u1680`, `\u2000`,
		`\u2001`, `\u2002`, `\u2003`, `\u2004`, `\u2005`, `\u2006`, `\u2007`, `\u2008`, `\u2009`,
		`\u200a`, `\u2028`, `\u2029`, `\u202f`, `\u205f`, `\u3000`]
}

// Rust `str::trim` is Unicode-aware; V's byte-oriented `trim_space` is not.
fn trim_rust_whitespace(value &string) string {
	runes := value.runes()
	mut start := 0
	mut end := runes.len
	for start < end && is_rust_unicode_whitespace(runes[start]) {
		start++
	}
	for end > start && is_rust_unicode_whitespace(runes[end - 1]) {
		end--
	}
	return runes[start..end].string()
}

// Rust's UUID-backed ThreadId is Copy. Its temporary V representation owns a string, so copies
// must be made explicit at the points where Rust performs an implicit Copy.
fn copy_thread_id(id &codex_protocol.ThreadId) codex_protocol.ThreadId {
	return codex_protocol.ThreadId{ value: id.value.clone() }
}

// V uses an explicit tagged struct for Rust's `Option<Option<String>>`.
fn clone_clearable_string(value &api.ClearableString) api.ClearableString {
	return api.ClearableString{
		has_value: value.has_value
		clear:     value.clear
		value:     value.value.clone()
	}
}

fn sandbox_mode_matches_policy(mode api.SandboxMode, policy &codex_protocol.SandboxPolicy) bool {
	return match mode {
		.read_only { policy.policy_kind == .read_only }
		.workspace_write { policy.policy_kind == .workspace_write }
		.danger_full_access {
			policy.policy_kind in [.danger_full_access, .external_sandbox]
		}
	}
}

fn optional_string_debug(value ?string) string {
	if text := value {
		return 'Some("${text}")'
	}
	return 'None'
}

fn reasoning_effort_config_name(value codex_protocol.ReasoningEffortConfig) string {
	return match value {
		.none { 'none' }
		.minimal { 'minimal' }
		.low { 'low' }
		.medium { 'medium' }
		.high { 'high' }
		.xhigh { 'xhigh' }
		.max { 'max' }
		.ultra { 'ultra' }
		.persistent { 'persistent' }
		.custom { 'custom' }
		else { value.str() }
	}
}

fn clone_config(config &Config) Config {
	return Config{
		model_provider_id:      config.model_provider_id.clone()
		codex_home:             config.codex_home.clone()
		cwd:                    config.cwd.clone()
		workspace_roots:        config.workspace_roots.clone()
		thread_unload_delay_ms: config.thread_unload_delay_ms
		ephemeral:              config.ephemeral
		features:               config.features
		model_reasoning_effort: config.model_reasoning_effort
		permissions:            codex_core.clone_config_permissions(&config.permissions)
		active_project:         config.active_project
		config_layer_stack:     config.config_layer_stack.clone()
	}
}

fn clone_config_overrides(overrides &ConfigOverrides) ConfigOverrides {
	return ConfigOverrides{
		model:                           clone_optional_string(overrides.model)
		model_provider:                  clone_optional_string(overrides.model_provider)
		service_tier:                    clone_clearable_string(&overrides.service_tier)
		cwd:                             clone_optional_string(overrides.cwd)
		workspace_roots:                 clone_optional_string_array(overrides.workspace_roots)
		permission_profile:              if profile := overrides.permission_profile {
			codex_core.clone_permission_profile(&profile)
		} else {
			none
		}
		default_permissions:             clone_optional_string(overrides.default_permissions)
		approval_policy:                 overrides.approval_policy
		approvals_reviewer:              overrides.approvals_reviewer
		sandbox_mode:                    overrides.sandbox_mode
		persisted_permission_profile_id: clone_optional_string(overrides.persisted_permission_profile_id)
		codex_linux_sandbox_exe:         overrides.codex_linux_sandbox_exe.clone()
		main_execve_wrapper_exe:         overrides.main_execve_wrapper_exe.clone()
		base_instructions:               clone_optional_string(overrides.base_instructions)
		developer_instructions:          clone_optional_string(overrides.developer_instructions)
		personality:                     overrides.personality
		ephemeral:                       overrides.ephemeral
	}
}

fn clone_optional_config_map(value ?map[string]string) ?map[string]string {
	if values := value {
		return values.clone()
	}
	return none
}

fn invalid_request(message string) api.JSONRPCErrorError {
	return api.JSONRPCErrorError{
		code:    -32600
		message: message
	}
}

fn internal_error(message string) api.JSONRPCErrorError {
	return api.JSONRPCErrorError{
		code:    -32603
		message: message
	}
}

fn method_not_found(message string) api.JSONRPCErrorError {
	return api.JSONRPCErrorError{
		code:    -32601
		message: message
	}
}

struct JsonRpcErrorCarrier {
	value api.JSONRPCErrorError
}

fn (error_value JsonRpcErrorCarrier) msg() string {
	return error_value.value.message
}

fn (error_value JsonRpcErrorCarrier) code() int {
	return error_value.value.code
}

fn fail(error_value api.JSONRPCErrorError) IError {
	return JsonRpcErrorCarrier{ value: error_value }
}

// V's `!` carrier exposes only `msg()` and `code()`. Rebuild the typed JSON-RPC error at the
// request-owned send boundary; errors produced by this file retain those exact fields.
fn json_rpc_error_from_ierror(error_value IError) api.JSONRPCErrorError {
	if error_value is JsonRpcErrorCarrier {
		return error_value.value
	}
	return api.JSONRPCErrorError{
		code:    error_value.code()
		message: error_value.msg()
	}
}

pub fn collect_resume_override_mismatches(
	request &api.ThreadResumeParams,
	config_snapshot &ThreadConfigSnapshot
) []string {
	mut mismatch_details := []string{}
	if requested_model := request.model {
		if requested_model != config_snapshot.model {
			mismatch_details << 'model requested=${requested_model} active=${config_snapshot.model}'
		}
	}
	if requested_provider := request.model_provider {
		if requested_provider != config_snapshot.model_provider_id {
			mismatch_details << 'model_provider requested=${requested_provider} active=${config_snapshot.model_provider_id}'
		}
	}
	if request.service_tier.has_value {
		mut requested_service_tier := ?string(none)
		if !request.service_tier.clear {
			requested_service_tier = request.service_tier.value.clone()
		}
		if requested_service_tier != config_snapshot.service_tier {
			mismatch_details << 'service_tier requested=${optional_string_debug(requested_service_tier)} active=${optional_string_debug(config_snapshot.service_tier)}'
		}
	}
	if requested_cwd := request.cwd {
		requested_cwd_path := os.norm_path(requested_cwd)
		active_cwd := config_snapshot.cwd()
		if requested_cwd_path != os.norm_path(active_cwd) {
			mismatch_details << 'cwd requested=${requested_cwd_path} active=${active_cwd}'
		}
	}
	if requested_roots := request.runtime_workspace_roots {
		if requested_roots != config_snapshot.workspace_roots {
			mismatch_details << 'runtime_workspace_roots requested=${requested_roots} active=${config_snapshot.workspace_roots}'
		}
	}
	if requested_approval := request.approval_policy {
		if requested_approval != config_snapshot.approval_policy {
			mismatch_details << 'approval_policy requested=${requested_approval} active=${config_snapshot.approval_policy}'
		}
	}
	if requested_review_policy := request.approvals_reviewer {
		if requested_review_policy != config_snapshot.approvals_reviewer {
			mismatch_details << 'approvals_reviewer requested=${requested_review_policy} active=${config_snapshot.approvals_reviewer}'
		}
	}
	if requested_sandbox := request.sandbox {
		active_sandbox := config_snapshot.sandbox_policy()
		if !sandbox_mode_matches_policy(requested_sandbox, &active_sandbox) {
			mismatch_details << 'sandbox requested=${requested_sandbox} active=${active_sandbox}'
		}
	}
	if request.permissions != none {
		mismatch_details << 'permissions override was provided and ignored while running; active=${config_snapshot.active_permission_profile}'
	}
	if requested_personality := request.personality {
		if active_personality := config_snapshot.personality {
			if requested_personality != active_personality {
				mismatch_details << 'personality requested=${requested_personality} active=${active_personality}'
			}
		} else {
			mismatch_details << 'personality requested=${requested_personality} active=none'
		}
	}
	if request.config != none {
		mismatch_details << 'config overrides were provided and ignored while running'
	}
	if request.base_instructions != none {
		mismatch_details << 'baseInstructions override was provided and ignored while running'
	}
	if request.developer_instructions != none {
		mismatch_details << 'developerInstructions override was provided and ignored while running'
	}
	return mismatch_details
}

pub fn merge_persisted_resume_metadata(
	mut request_overrides OptionalStringMap,
	mut typesafe_overrides ConfigOverrides,
	persisted_metadata &ThreadMetadata
) {
	if has_model_resume_override(&request_overrides, &typesafe_overrides) {
		return
	}

	if model := persisted_metadata.model {
		typesafe_overrides.model = model.clone()
	}
	typesafe_overrides.model_provider = persisted_metadata.model_provider.clone()

	if reasoning_effort := persisted_metadata.reasoning_effort {
		request_overrides.has_value = true
		request_overrides.value['model_reasoning_effort'] = reasoning_effort_config_name(reasoning_effort)
	}
}

pub fn normalize_thread_list_cwd_filters(cwd ?api.ThreadListCwdFilter) !OptionalStringArray {
	filter := cwd or { return OptionalStringArray{} }
	cwds := match filter.kind {
		.one { [filter.one.clone()] }
		.many { filter.many.clone() }
	}
	mut normalized_cwds := []string{cap: cwds.len}
	for cwd_value in cwds {
		if cwd_value.len == 0 {
			return fail(invalid_params('invalid thread/list cwd filter `${cwd_value}`: path must not be empty'))
		}
		normalized_cwds << os.norm_path(os.abs_path(cwd_value))
	}
	return OptionalStringArray{
		has_value: true
		value:     normalized_cwds
	}
}

pub fn has_model_resume_override(
	request_overrides &OptionalStringMap,
	typesafe_overrides &ConfigOverrides
) bool {
	return typesafe_overrides.model != none || typesafe_overrides.model_provider != none
		|| (request_overrides.has_value && ('model' in request_overrides.value
			|| 'model_reasoning_effort' in request_overrides.value))
}

fn parse_approval_policy_override(value &string) !api.AskForApproval {
	normalized := trim_rust_whitespace(value).trim('"')
	return match normalized {
		'untrusted' { .untrusted }
		'on-failure', 'on_failure' { .on_failure }
		'on-request', 'on_request' { .on_request }
		'never' { .never }
		else { error('unknown approval policy `${normalized}`') }
	}
}

fn resume_history_cwd(history &InitialHistory) ?string {
	if history.kind == .resumed {
		for reverse_index in 0 .. history.items.len {
			item := history.items[history.items.len - 1 - reverse_index]
			if applied_thread_id := item.thread_settings_thread_id {
				if applied_thread_id.value == history.conversation_id.value {
					if cwd := item.thread_settings_cwd {
						return cwd.clone()
					}
				}
			}
		}
	}
	return history.session_cwd()
}

pub fn has_permission_override(
	request_overrides &OptionalStringMap,
	typesafe_overrides &ConfigOverrides
) bool {
	return typesafe_overrides.sandbox_mode != none
		|| typesafe_overrides.permission_profile != none
		|| typesafe_overrides.default_permissions != none
		|| (request_overrides.has_value && ('sandbox_mode' in request_overrides.value
			|| 'default_permissions' in request_overrides.value))
}

fn escape_identifier_for_error(value &string) string {
	mut escaped := ''
	for character in value.runes() {
		if character < 0x20 || character == 0x7f {
			escaped += '\\u${character:04x}'
		} else {
			escaped += character.str()
		}
	}
	return escaped
}

fn validate_dynamic_tool_identifier(value &string, label &string, max_len int) ! {
	for byte in value.bytes() {
		is_valid := (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`) || byte == `_` || byte == `-`
		if !is_valid {
			return error('${*label} must match ${dynamic_tool_identifier_pattern} to match Responses API: ${escape_identifier_for_error(value)}')
		}
	}
	if value.runes().len > max_len {
		return error('${*label} must be at most ${max_len} characters to match Responses API: ${escape_identifier_for_error(value)}')
	}
}

fn validate_dynamic_tool(
	tool &api.DynamicToolFunctionSpec,
	namespace ?string,
	mut seen map[string]bool
) ! {
	name := trim_rust_whitespace(&tool.name)
	if name.len == 0 {
		return error('dynamic tool name must not be empty')
	}
	if name != tool.name {
		return error('dynamic tool name has leading/trailing whitespace: ${escape_identifier_for_error(&tool.name)}')
	}
	tool_label := 'dynamic tool name'
	validate_dynamic_tool_identifier(&name, &tool_label, dynamic_tool_name_max_len)!
	if name == 'mcp' || name.starts_with('mcp__') {
		return error('dynamic tool name is reserved: ${name}')
	}
	if name in seen {
		if namespace_name := namespace {
			return error('duplicate dynamic tool name in namespace ${namespace_name}: ${name}')
		}
		return error('duplicate dynamic tool name: ${name}')
	}
	seen[name] = true
	if tool.defer_loading && namespace == none {
		return error('deferred dynamic tool must include a namespace: ${name}')
	}
	codex_tools.parse_tool_input_schema(&tool.input_schema) or {
		return error('dynamic tool input schema is not supported for ${name}: ${err}')
	}
}

pub fn validate_dynamic_tools(tools &[]api.DynamicToolSpec) ! {
	mut seen_tools := map[string]bool{}
	mut seen_namespaces := map[string]bool{}
	for spec in *tools {
		match spec.kind {
			.function {
				validate_dynamic_tool(&spec.function, none, mut seen_tools)!
			}
			.namespace {
				name := trim_rust_whitespace(&spec.namespace.name)
				if name.len == 0 {
					return error('dynamic tool namespace must not be empty')
				}
				if name != spec.namespace.name {
					return error('dynamic tool namespace has leading/trailing whitespace: ${escape_identifier_for_error(&spec.namespace.name)}')
				}
				namespace_label := 'dynamic tool namespace'
				validate_dynamic_tool_identifier(&name, &namespace_label, dynamic_tool_namespace_max_len)!
				if spec.namespace.description.runes().len > dynamic_tool_namespace_description_max_len {
					return error('dynamic tool namespace description must be at most ${dynamic_tool_namespace_description_max_len} characters')
				}
				if name == 'mcp' || name.starts_with('mcp__') {
					return error('dynamic tool namespace is reserved: ${name}')
				}
				if name in reserved_responses_namespaces {
					return error('dynamic tool namespace collides with a reserved Responses API namespace: ${name}')
				}
				if name in seen_namespaces {
					return error('duplicate dynamic tool namespace: ${name}')
				}
				seen_namespaces[name] = true
				if spec.namespace.tools.len == 0 {
					return error('dynamic tool namespace must contain at least one tool: ${name}')
				}
				mut seen_namespace_tools := map[string]bool{}
				for tool in spec.namespace.tools {
					validate_dynamic_tool(&tool, name, mut seen_namespace_tools)!
				}
			}
		}
	}
}

// ThreadRequestProcessor retains the Rust processor's dependency ownership. Rust `Arc<T>` values
// are V value handles here; the concrete shared implementations replace these shells with their
// own synchronization when their modules are translated.
pub struct ThreadRequestProcessor {
pub:
	auth_manager             AuthManager
	thread_manager           ThreadManager
	outgoing                 OutgoingMessageSender
	arg0_paths               Arg0DispatchPaths
	config                   Config
	config_manager           ConfigManager
	thread_store             store.ThreadStore
	pending_thread_unloads   PendingThreadUnloadSet
	thread_state_manager     ThreadStateManager
	thread_watch_manager     ThreadWatchManager
	thread_list_state_permit ThreadListStateSemaphore
	thread_goal_processor    ThreadGoalRequestProcessor
	state_db                 ?StateDbHandle
	log_db                   ?LogDbLayer
	background_tasks         TaskTracker
	skills_watcher           SkillsWatcher
	turn_cost_worker         ?TurnCostWorkerHandle
	initial_config_warnings  []ConfigWarningNotification
}

/// Outcome of trying to satisfy a resume request from an already loaded thread.
enum RunningThreadResumeResultKind {
	/// The request was delegated to the loaded thread.
	handled
	/// No loaded thread handled the request.
	///
	/// The optional stored thread contains the history-bearing probe that cold
	/// resume can reuse instead of reading the rollout again.
	not_running
}

struct RunningThreadResumeResult {
	kind          RunningThreadResumeResultKind
	stored_thread ?store.StoredThread
}

pub fn new_thread_request_processor(
	auth_manager AuthManager,
	thread_manager ThreadManager,
	outgoing OutgoingMessageSender,
	arg0_paths Arg0DispatchPaths,
	config Config,
	config_manager ConfigManager,
	thread_store store.ThreadStore,
	pending_thread_unloads PendingThreadUnloadSet,
	thread_state_manager ThreadStateManager,
	thread_watch_manager ThreadWatchManager,
	thread_list_state_permit ThreadListStateSemaphore,
	thread_goal_processor ThreadGoalRequestProcessor,
	state_db ?StateDbHandle,
	log_db ?LogDbLayer,
	skills_watcher SkillsWatcher,
	turn_cost_worker ?TurnCostWorkerHandle,
	initial_config_warnings []ConfigWarningNotification
) ThreadRequestProcessor {
	return ThreadRequestProcessor{
		auth_manager:             auth_manager
		thread_manager:           thread_manager
		outgoing:                 outgoing
		arg0_paths:               arg0_paths
		config:                   config
		config_manager:           config_manager
		thread_store:             thread_store
		pending_thread_unloads:   pending_thread_unloads
		thread_state_manager:     thread_state_manager
		thread_watch_manager:     thread_watch_manager
		thread_list_state_permit: thread_list_state_permit
		thread_goal_processor:    thread_goal_processor
		state_db:                 state_db
		log_db:                   log_db
		background_tasks:         TaskTracker{}
		skills_watcher:           skills_watcher
		turn_cost_worker:         turn_cost_worker
		initial_config_warnings:  initial_config_warnings
	}
}

fn response_payload_with_value(payload api.ClientResponsePayload) OptionalClientResponsePayload {
	return OptionalClientResponsePayload{
		has_value: true
		value:     payload
	}
}

fn clone_connection_request_id(request_id &ConnectionRequestId) ConnectionRequestId {
	return ConnectionRequestId{
		connection_id: request_id.connection_id
		request_id:    request_id.request_id.clone()
	}
}

pub fn (processor &ThreadRequestProcessor) thread_start(
	request_id ConnectionRequestId,
	params api.ThreadStartParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions,
	request_context RequestContext
) !OptionalClientResponsePayload {
	processor.thread_start_inner(request_id, params, app_server_client_name, app_server_client_version, client_mcp_extensions, request_context)!
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_unsubscribe(
	request_id &ConnectionRequestId,
	params api.ThreadUnsubscribeParams
) !OptionalClientResponsePayload {
	response := processor.thread_unsubscribe_response_inner(params, request_id.connection_id)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_resume(
	request_id ConnectionRequestId,
	params api.ThreadResumeParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions
) !OptionalClientResponsePayload {
	mut prepared_config := OptionalPreparedResumeConfig{}
	// Configuration loading intentionally happens outside the list-state permit. A Continue result
	// stores the prepared config and retries the operation exactly like Rust's ControlFlow loop.
	for {
		flow := processor.thread_resume_inner(clone_connection_request_id(&request_id), &params, clone_optional_string(app_server_client_name), clone_optional_string(app_server_client_version), codex_protocol.clone_client_mcp_extensions(&client_mcp_extensions), mut prepared_config)!
		if flow == .stop {
			break
		}
	}
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_fork(
	request_id ConnectionRequestId,
	params api.ThreadForkParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions
) !OptionalClientResponsePayload {
	processor.thread_fork_inner(request_id, params, app_server_client_name, app_server_client_version, client_mcp_extensions)!
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_revert(
	request_id ConnectionRequestId,
	params api.ThreadRevertParams,
	app_server_client_name ?string,
	app_server_client_version ?string
) !OptionalClientResponsePayload {
	response, thread_id := processor.thread_revert_response(&request_id, params, app_server_client_name, app_server_client_version)!
	processor.outgoing.send_response(clone_connection_request_id(&request_id), api.ClientResponsePayload(response))
	processor.outgoing.send_server_notification(api.ServerNotification(api.ThreadRevertedNotification{
		thread_id: thread_id
	}))
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_archive(
	request_id ConnectionRequestId,
	params api.ThreadArchiveParams
) !OptionalClientResponsePayload {
	response, archived_ids := processor.thread_archive_inner(params)!
	processor.outgoing.send_response(clone_connection_request_id(&request_id), api.ClientResponsePayload(response))
	for archived_id in archived_ids {
		processor.outgoing.send_server_notification(api.ServerNotification(api.ThreadArchivedNotification{
			thread_id: archived_id
		}))
	}
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_increment_elicitation(
	params api.ThreadIncrementElicitationParams
) !OptionalClientResponsePayload {
	response := processor.thread_increment_elicitation_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_decrement_elicitation(
	params api.ThreadDecrementElicitationParams
) !OptionalClientResponsePayload {
	response := processor.thread_decrement_elicitation_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_set_name(
	request_id ConnectionRequestId,
	params api.ThreadSetNameParams
) !OptionalClientResponsePayload {
	response, notification := processor.thread_set_name_response_inner(params)!
	processor.outgoing.send_response(clone_connection_request_id(&request_id), api.ClientResponsePayload(response))
	if update := notification {
		processor.outgoing.send_server_notification(api.ServerNotification(update))
	}
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_metadata_update(
	params api.ThreadMetadataUpdateParams
) !OptionalClientResponsePayload {
	response := processor.thread_metadata_update_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_section_move(
	params api.ThreadSectionMoveParams
) !OptionalClientResponsePayload {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	if section_id := params.section_id {
		if trim_rust_whitespace(&section_id).len == 0 {
			return fail(invalid_request('sectionId must not be empty'))
		}
	} else if params.before_thread_id != none {
		return fail(invalid_request('beforeThreadId requires a non-null sectionId'))
	}
	mut before_thread_uuid := ?codex_protocol.ThreadId(none)
	if before_thread_id := params.before_thread_id {
		before_thread_uuid = codex_protocol.thread_id_from_string(&before_thread_id) or {
			return fail(invalid_request('invalid before thread id: ${err}'))
		}
	}
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	move_result := processor.thread_manager.move_thread_to_section(thread_id, params.section_id,
		before_thread_uuid)
	if move_result.is_error {
		operation := 'move thread in section'
		return fail(core_thread_write_error(&operation, clone_codex_error(&move_result.error_value)))
	}
	return response_payload_with_value(api.ClientResponsePayload(api.ThreadSectionMoveResponse{}))
}

pub fn (processor &ThreadRequestProcessor) thread_memory_mode_set(
	params api.ThreadMemoryModeSetParams
) !OptionalClientResponsePayload {
	response := processor.thread_memory_mode_set_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) memory_reset() !OptionalClientResponsePayload {
	response := processor.memory_reset_response_inner()!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_unarchive(
	request_id ConnectionRequestId,
	params api.ThreadUnarchiveParams
) !OptionalClientResponsePayload {
	response, notification := processor.thread_unarchive_inner(params)!
	processor.outgoing.send_response(clone_connection_request_id(&request_id), api.ClientResponsePayload(response))
	processor.outgoing.send_server_notification(api.ServerNotification(notification))
	return OptionalClientResponsePayload{}
}

pub fn (processor &ThreadRequestProcessor) thread_compact_start(
	request_id &ConnectionRequestId,
	params api.ThreadCompactStartParams
) !OptionalClientResponsePayload {
	response := processor.thread_compact_start_inner(request_id, params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_background_terminals_clean(
	request_id &ConnectionRequestId,
	params api.ThreadBackgroundTerminalsCleanParams
) !OptionalClientResponsePayload {
	response := processor.thread_background_terminals_clean_inner(request_id, params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_background_terminals_list(
	params api.ThreadBackgroundTerminalsListParams
) !OptionalClientResponsePayload {
	response := processor.thread_background_terminals_list_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_background_terminals_terminate(
	params api.ThreadBackgroundTerminalsTerminateParams
) !OptionalClientResponsePayload {
	response := processor.thread_background_terminals_terminate_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_rollback(
	request_id &ConnectionRequestId,
	params api.ThreadRollbackParams,
	app_server_client_name ?&string
) !OptionalClientResponsePayload {
	if client_name := app_server_client_name {
		if *client_name != codex_tui_client_name {
			processor.send_deprecation_notice(request_id.connection_id, &thread_rollback_deprecation_summary)
		}
	} else {
		processor.send_deprecation_notice(request_id.connection_id, &thread_rollback_deprecation_summary)
	}
	processor.thread_rollback_inner(request_id, params)!
	return OptionalClientResponsePayload{}
}

fn (processor &ThreadRequestProcessor) send_deprecation_notice(
	connection_id ConnectionId,
	summary &string
) {
	connections := [app_outgoing.ConnectionId{ value: connection_id.value }]
	processor.outgoing.send_server_notification_to_connections(&connections, api.ServerNotification(api.DeprecationNoticeNotification{
		summary: summary.clone()
		details: none
	}))
}

pub fn (processor &ThreadRequestProcessor) thread_list(
	params api.ThreadListParams
) !OptionalClientResponsePayload {
	response := processor.thread_list_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_search(
	params api.ThreadSearchParams
) !OptionalClientResponsePayload {
	response := processor.thread_search_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_search_occurrences(
	params api.ThreadSearchOccurrencesParams
) !OptionalClientResponsePayload {
	response := processor.thread_search_occurrences_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_loaded_list(
	params api.ThreadLoadedListParams
) !OptionalClientResponsePayload {
	response := processor.thread_loaded_list_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_read(
	request_id &ConnectionRequestId,
	params api.ThreadReadParams
) !OptionalClientResponsePayload {
	include_turns := params.include_turns
	response := processor.thread_read_response_inner(params)!
	if include_turns && response.thread.history_mode == .paginated {
		processor.send_deprecation_notice(request_id.connection_id, &paginated_thread_read_deprecation_summary)
	}
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_turns_list(
	params api.ThreadTurnsListParams
) !OptionalClientResponsePayload {
	response := processor.thread_turns_list_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_items_list(
	params api.ThreadItemsListParams
) !OptionalClientResponsePayload {
	response := processor.thread_items_list_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_timeline_list(
	params api.ThreadTimelineListParams
) !OptionalClientResponsePayload {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	limit := clamp_page_size(params.limit, thread_items_default_limit, thread_items_max_limit)
	page_result := processor.thread_store.list_timeline(store.StoreListTimelineParams{
		thread_id: thread_id
		cursor:    params.cursor
		page_size: limit
	})
	if page_result.is_error {
		return fail(paginated_history_list_error(clone_thread_store_error(&page_result.error_value)))
	}
	page := page_result.value
	response := api.ThreadTimelineListResponse{
		data:                                  page.items
		next_cursor:                           page.next_cursor
		active_realtime_session_at_page_start: page.active_realtime_session_at_page_start
	}
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_shell_command(
	request_id &ConnectionRequestId,
	params api.ThreadShellCommandParams
) !OptionalClientResponsePayload {
	response := processor.thread_shell_command_inner(request_id, params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) thread_approve_guardian_denied_action(
	request_id &ConnectionRequestId,
	params api.ThreadApproveGuardianDeniedActionParams
) !OptionalClientResponsePayload {
	response := processor.thread_approve_guardian_denied_action_inner(request_id, params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

pub fn (processor &ThreadRequestProcessor) conversation_summary(
	params api.GetConversationSummaryParams
) !OptionalClientResponsePayload {
	response := processor.get_thread_summary_response_inner(params)!
	return response_payload_with_value(api.ClientResponsePayload(response))
}

fn clone_codex_thread(thread_value &CodexThread) CodexThread {
	return CodexThread{
		id:                    codex_protocol.ThreadId{ value: thread_value.id.value.clone() }
		config:                clone_config(&thread_value.config)
		config_snapshot:       clone_config_snapshot(&thread_value.config_snapshot)
		settings:              thread_value.settings
		client_mcp_extensions: thread_value.client_mcp_extensions
		background_terminals:  thread_value.background_terminals.clone()
		session_id:            thread_value.session_id.clone()
		rollout_path:          if path := thread_value.rollout_path { path.clone() } else { none }
		multi_agent_version:   thread_value.multi_agent_version
		agent_running:         thread_value.agent_running
		direct_input_enabled:  thread_value.direct_input_enabled
		local_environment:     thread_value.local_environment
		shutdown_result:       thread_value.shutdown_result
		elicitation_count:     thread_value.elicitation_count
		history_items:         thread_value.history_items.clone()
	}
}

fn clone_config_snapshot(snapshot &ThreadConfigSnapshot) ThreadConfigSnapshot {
	return ThreadConfigSnapshot{
		model:                     snapshot.model.clone()
		model_provider_id:         snapshot.model_provider_id.clone()
		service_tier:              if value := snapshot.service_tier { value.clone() } else { none }
		cwd:                       snapshot.cwd.clone()
		workspace_roots:           snapshot.workspace_roots.clone()
		approval_policy:           snapshot.approval_policy
		approvals_reviewer:        snapshot.approvals_reviewer
		permission_profile:        codex_core.clone_permission_profile(&snapshot.permission_profile)
		full_access:               snapshot.full_access
		active_permission_profile: codex_protocol.clone_optional_active_permission_profile(snapshot.active_permission_profile)
		personality:               snapshot.personality
		ephemeral:                 snapshot.ephemeral
		history_mode:              snapshot.history_mode
		parent_thread_id:          if id := snapshot.parent_thread_id {
			codex_protocol.ThreadId{ value: id.value.clone() }
		} else {
			none
		}
		session_source:            codex_protocol.clone_session_source(&snapshot.session_source)
		thread_source:             clone_optional_thread_source(snapshot.thread_source)
		originator:                snapshot.originator.clone()
		reasoning_effort:          snapshot.reasoning_effort
		environment_selections:    snapshot.environment_selections.clone()
	}
}

fn clone_initial_history(history &InitialHistory) InitialHistory {
	return InitialHistory{
		kind:                history.kind
		conversation_id:     copy_thread_id(&history.conversation_id)
		items:               history.items.clone()
		rollout_path:        clone_optional_string(history.rollout_path)
		session_source:      codex_protocol.clone_optional_session_source(history.session_source)
		thread_source:       clone_optional_thread_source(history.thread_source)
		multi_agent_version: history.multi_agent_version
		session_cwd:         clone_optional_string(history.session_cwd)
	}
}

// Rust keeps the persisted metadata available both for override merging and for the
// prepared-config equality key. V ownership requires making that source `.clone()` explicit.
fn clone_thread_metadata(metadata &ThreadMetadata) ThreadMetadata {
	return ThreadMetadata{
		id:                 copy_thread_id(&metadata.id)
		rollout_path:       metadata.rollout_path.clone()
		first_user_message: clone_optional_string(metadata.first_user_message)
		preview:            clone_optional_string(metadata.preview)
		created_at:         metadata.created_at.clone()
		updated_at:         metadata.updated_at.clone()
		model:              clone_optional_string(metadata.model)
		model_provider:     metadata.model_provider.clone()
		reasoning_effort:   metadata.reasoning_effort
		cwd:                metadata.cwd.clone()
		cli_version:        metadata.cli_version.clone()
		source:             metadata.source.clone()
		thread_source:      clone_optional_thread_source(metadata.thread_source)
		agent_nickname:     clone_optional_string(metadata.agent_nickname)
		agent_role:         clone_optional_string(metadata.agent_role)
		git_sha:            clone_optional_string(metadata.git_sha)
		git_branch:         clone_optional_string(metadata.git_branch)
		git_origin_url:     clone_optional_string(metadata.git_origin_url)
	}
}

fn (processor &ThreadRequestProcessor) load_thread(thread_id &string) !(codex_protocol.ThreadId, CodexThread) {
	// Resolve the core conversation handle from a v2 thread id string.
	id := codex_protocol.thread_id_from_string(thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	thread_value := processor.thread_manager.get_thread(&id) or {
		return fail(invalid_request('thread not found: ${id.str()}'))
	}
	return id, clone_codex_thread(&thread_value)
}

pub fn (processor &ThreadRequestProcessor) acquire_thread_list_state_permit() !ThreadListStatePermit {
	if isnil(processor.thread_list_state_permit.state)
		|| processor.thread_list_state_permit.state.closed {
		return fail(internal_error('failed to acquire thread list state permit: permit is closed'))
	}
	processor.thread_list_state_permit.state.mutex.lock()
	return ThreadListStatePermit{ state: processor.thread_list_state_permit.state }
}

fn set_app_server_client_info(
	thread_value &CodexThread,
	app_server_client_name ?string,
	app_server_client_version ?string
) ! {
	name := app_server_client_name or { '' }
	version := app_server_client_version or { '' }
	auto_deny := xcode_26_4_mcp_elicitations_auto_deny(&name, &version)
	thread_value.set_app_server_client_info(app_server_client_name, app_server_client_version, auto_deny) or {
		return fail(internal_error('failed to set app server client info: ${err}'))
	}
}

fn (processor &ThreadRequestProcessor) finalize_thread_teardown(teardown_thread_id codex_protocol.ThreadId) {
	processor.pending_thread_unloads.remove(&teardown_thread_id.value)
	processor.outgoing.cancel_requests_for_thread(copy_thread_id(&teardown_thread_id))
	processor.thread_state_manager.remove_thread_state(&teardown_thread_id)
	processor.thread_watch_manager.remove_thread(&teardown_thread_id.value)
}

fn (processor &ThreadRequestProcessor) thread_unsubscribe_response_inner(
	params api.ThreadUnsubscribeParams,
	connection_id ConnectionId
) !api.ThreadUnsubscribeResponse {
	id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	processor.thread_manager.get_thread(&id) or {
		processor.finalize_thread_teardown(id)
		return api.ThreadUnsubscribeResponse{ status: .not_loaded }
	}
	was_subscribed := processor.thread_state_manager.unsubscribe_connection_from_thread(id, connection_id)
	return api.ThreadUnsubscribeResponse{
		status: if was_subscribed { .unsubscribed } else { .not_subscribed }
	}
}

fn (processor &ThreadRequestProcessor) prepare_thread_for_archive(
	thread_id codex_protocol.ThreadId
) ! {
	operation := 'archive'
	processor.prepare_thread_for_removal(thread_id, &operation)!
}

pub fn (processor &ThreadRequestProcessor) prepare_thread_for_removal(
	thread_id codex_protocol.ThreadId,
	operation &string
) ! {
	removed_result := processor.thread_manager.remove_thread_for_client(&thread_id)
	if removed_result.is_error {
		return fail(core_thread_write_error(operation, clone_codex_error(&removed_result.error_value)))
	}
	removed := removed_result.value
	if removed.has_value {
		match wait_for_thread_shutdown(&removed.value) {
			.complete {}
			.submit_failed, .timed_out {
				message := 'thread ${thread_id.value} shutdown did not complete; proceeding with ${*operation}'
				processor.outgoing.log_warning(&message)
			}
			else {}
		}
	}
	processor.finalize_thread_teardown(thread_id)
}

fn (processor &ThreadRequestProcessor) listener_task_context() ListenerTaskContext {
	return ListenerTaskContext{
		thread_manager:          processor.thread_manager
		thread_state_manager:    processor.thread_state_manager
		outgoing:                processor.outgoing
		pending_thread_unloads:  processor.pending_thread_unloads
		thread_watch_manager:    processor.thread_watch_manager
		thread_list_permit_open: !isnil(processor.thread_list_state_permit.state)
			&& !processor.thread_list_state_permit.state.closed
		fallback_model_provider: processor.config.model_provider_id.clone()
		codex_home:              processor.config.codex_home.clone()
		thread_unload_delay_ms:  processor.config.thread_unload_delay_ms
		skills_watcher:          processor.skills_watcher
		turn_cost_worker:        processor.turn_cost_worker
	}
}

fn (processor &ThreadRequestProcessor) ensure_conversation_listener(
	conversation_id codex_protocol.ThreadId,
	connection_id ConnectionId,
	raw_events_enabled bool
) !EnsureConversationListenerResult {
	context := processor.listener_task_context()
	return thread_lifecycle.ensure_conversation_listener(&context, conversation_id, connection_id, raw_events_enabled)
}

fn (processor &ThreadRequestProcessor) ensure_listener_task_running(
	conversation_id codex_protocol.ThreadId,
	conversation CodexThread,
	thread_state &app_thread_state.ThreadState
) ! {
	context := processor.listener_task_context()
	thread_lifecycle.ensure_listener_task_running(&context, conversation_id, &conversation, thread_state)!
}

fn (processor &ThreadRequestProcessor) thread_start_inner(
	request_id ConnectionRequestId,
	params api.ThreadStartParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions,
	request_context RequestContext
) ! {
	if history_mode := params.history_mode {
		if history_mode == .paginated && !processor.thread_store.supports_paginated_history_lists() {
			return fail(invalid_request('paginated threads require thread/turns/list and thread/items/list support'))
		}
	}
	if params.sandbox != none && params.permissions != none {
		return fail(invalid_request('`permissions` cannot be combined with `sandbox`'))
	}
	if project_id := params.project_id {
		if project_id.len == 0 {
			return fail(invalid_request('projectId must not be empty'))
		}
		project_result := processor.thread_store.read_project(project_id.clone())
		if project_result.is_error {
			if project_result.error_value.kind == .unsupported {
				return fail(unsupported_thread_store_operation(&project_result.error_value.operation))
			}
			return fail(internal_error('failed to read project: ${project_result.error_value.message}'))
		}
		if !project_result.has_value {
			return fail(invalid_request('project not found: ${project_id}'))
		}
	}
	mut resolved_runtime_workspace_roots := ?[]string(none)
	if roots := clone_optional_string_array(params.runtime_workspace_roots) {
		resolved_runtime_workspace_roots = resolve_runtime_workspace_roots(roots)
	}
	resolved_environment_result := resolve_turn_environment_selections(&processor.thread_manager, clone_optional_turn_environment_params(params.environments))!
	mut resolved_environment_selections := ?[]codex_protocol.TurnEnvironmentSelection(none)
	if resolved_environment_result.has_value {
		resolved_environment_selections = resolved_environment_result.value.clone()
	}
	mut typesafe_overrides := processor.build_thread_config_overrides(params.model, params.model_provider, params.service_tier, params.cwd, resolved_runtime_workspace_roots, params.approval_policy, params.approvals_reviewer, params.sandbox, params.permissions, params.base_instructions, params.developer_instructions, params.personality)
	typesafe_overrides.ephemeral = params.ephemeral
	listener_task_context := processor.listener_task_context()
	thread_store := processor.thread_store
	config_manager := processor.config_manager
	outgoing := processor.outgoing
	error_request_id := clone_connection_request_id(&request_id)
	background_tasks := processor.background_tasks
	initial_config_warnings := processor.initial_config_warnings.clone()
	request_trace := request_context.request_trace()
	background_task := fn [listener_task_context, thread_store, config_manager, request_id, app_server_client_name, app_server_client_version, client_mcp_extensions, params, typesafe_overrides, resolved_environment_selections, request_trace, outgoing, error_request_id, initial_config_warnings] () {
		thread_start_task(listener_task_context, thread_store, config_manager, request_id, app_server_client_name, app_server_client_version, client_mcp_extensions, params.config, typesafe_overrides, params.dynamic_tools, params.selected_capability_roots or { []api.SelectedCapabilityRoot{} }, params.history_mode, params.session_start_source, params.thread_source, params.project_id, resolved_environment_selections, params.service_name, params.allow_provider_model_fallback, params.experimental_raw_events, request_trace, initial_config_warnings) or {
			outgoing.send_error(error_request_id, api.JSONRPCErrorError{
				code:    err.code()
				message: err.msg()
			})
		}
	}
	background_tasks.spawn(tracing.instrument_task(background_task, request_context.span()))
}

pub fn (processor &ThreadRequestProcessor) drain_background_tasks() {
	processor.background_tasks.close()
	if !processor.background_tasks.wait_bounded(10_000) {
		message := 'timed out waiting for background tasks to shut down; proceeding'
		processor.outgoing.log_warning(&message)
	}
}

pub fn (processor &ThreadRequestProcessor) clear_all_thread_listeners() {
	processor.thread_state_manager.clear_all_listeners()
}

pub fn (processor &ThreadRequestProcessor) shutdown_threads() {
	report := processor.thread_manager.shutdown_all_threads_bounded(10_000)
	for id in report.submit_failed {
		message := 'failed to submit Shutdown to thread ${id.value}'
		processor.outgoing.log_warning(&message)
	}
	for id in report.timed_out {
		message := 'timed out waiting for thread ${id.value} to shut down'
		processor.outgoing.log_warning(&message)
	}
}

fn (processor &ThreadRequestProcessor) request_trace_context(
	request_id &ConnectionRequestId
) ?codex_protocol.W3cTraceContext {
	return processor.outgoing.request_trace_context(request_id)
}

fn (processor &ThreadRequestProcessor) submit_core_op(
	request_id &ConnectionRequestId,
	thread_value &CodexThread,
	op codex_protocol.Op
) !string {
	trace := processor.request_trace_context(request_id)
	return thread_value.submit_with_trace(op, trace)
}

// V runs this static-equivalent task inside the spawned closure established by thread_start_inner.
// All owned inputs remain consumed exactly where Rust moves them into the background task.
fn thread_start_task(
	listener_task_context ListenerTaskContext,
	thread_store store.ThreadStore,
	config_manager ConfigManager,
	request_id ConnectionRequestId,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions,
	config_overrides ?map[string]string,
	typesafe_overrides ConfigOverrides,
	dynamic_tools ?[]api.DynamicToolSpec,
	selected_capability_roots []api.SelectedCapabilityRoot,
	history_mode ?api.ThreadHistoryMode,
	session_start_source ?api.ThreadStartSource,
	thread_source ?codex_protocol.ThreadSource,
	project_id ?string,
	environment_selections ?[]codex_protocol.TurnEnvironmentSelection,
	service_name ?string,
	allow_provider_model_fallback bool,
	experimental_raw_events bool,
	request_trace ?codex_protocol.W3cTraceContext,
	initial_config_warnings []ConfigWarningNotification
) ! {
	thread_start_started_at := time.now()
	requested_cwd := clone_optional_string(typesafe_overrides.cwd)
	mut config := config_manager.load_with_overrides(clone_optional_config_map(config_overrides), clone_config_overrides(&typesafe_overrides)) or {
		message := err.msg()
		return fail(config_load_error(&message))
	}
	// Project-local config can launch host processes, so only the effective
	// permissions after managed constraints can imply project trust.
	effective_permission_profile := config.permissions.effective_permission_profile()
	effective_permissions_trust_project := match effective_permission_profile.enforcement {
		.none, .external { true }
		.legacy {
			file_system_policy := effective_permission_profile.file_system_sandbox_policy()
			file_system_policy.can_write_local_path_with_cwd(&config.cwd, &config.cwd)
		}
	}
	if requested_cwd != none && config.active_project.trust_level == none
		&& effective_permissions_trust_project {
		trust_target := codex_core.resolve_root_git_project_for_trust(&config.cwd) or {
			config.cwd.clone()
		}
		current_cli_overrides := config_manager.current_cli_overrides()
		mut cli_overrides_for_reload := current_cli_overrides.clone()
		codex_core.set_project_trust_level(&listener_task_context.codex_home, &trust_target, .trusted) or {
			message := 'failed to persist trusted project state for ${trust_target}; continuing with in-memory trust for this thread: ${err}'
			listener_task_context.outgoing.log_warning(&message)
			trust_key := config_loader.project_trust_key(&trust_target)
			cli_overrides_for_reload << app_config_manager.CliConfigOverride{
				key:   'projects.${trust_key}.trust_level'
				value: 'trusted'
			}
		}
		config = config_manager.load_with_cli_overrides(cli_overrides_for_reload, config_overrides, typesafe_overrides, none) or {
			message := err.msg()
			return fail(config_load_error(&message))
		}
	}
	warning_result := codex_core.check_execpolicy_for_warnings(&config.config_layer_stack) or {
		codex_core.OptionalExecPolicyError{}
	}
	if warning_result.has_value {
		warning := app_server.exec_policy_config_warning(&warning_result.value)
		mut already_sent := false
		for initial_warning in initial_config_warnings {
			if initial_warning == warning {
				already_sent = true
				break
			}
		}
		if !already_sent {
			connections := [request_id.connection_id]
			listener_task_context.outgoing.send_server_notification_to_connections(&connections, api.ServerNotification(warning))
		}
	}
	mut resolved_environments := []codex_protocol.TurnEnvironmentSelection{}
	if values := environment_selections {
		// Optional extraction is borrowed by V, so materialize the owned vector consumed by
		// StartThreadOptions at the same handoff where Rust unwraps the owned Option<Vec<_>>.
		resolved_environments = values.clone()
	} else {
		resolved_environments = listener_task_context.thread_manager.default_environment_selections(&config.cwd, &config.workspace_roots)
	}
	mut runtime_tools := []api.DynamicToolSpec{}
	if tools := dynamic_tools {
		validate_dynamic_tools(&tools) or { return fail(invalid_request(err.msg())) }
		// V's optional extraction exposes an immutable array, so clone at this ownership handoff.
		runtime_tools = tools.clone()
	}
	// Count callable functions rather than top-level namespace containers.
	mut dynamic_tool_count := 0
	for tool in runtime_tools {
		dynamic_tool_count += if tool.kind == .function { 1 } else { tool.namespace.tools.len }
	}
	tracing.record_thread_start_create_dynamic_tool_count(dynamic_tool_count)
	mut resolved_history_mode := history_mode
	if resolved_history_mode == none && !config.ephemeral
		&& thread_store.supports_paginated_history_lists() {
		resolved_history_mode = api.ThreadHistoryMode.paginated
	}
	initial_history := if session_start_source or { api.ThreadStartSource.startup } == .clear {
		InitialHistory{ kind: .cleared }
	} else {
		InitialHistory{ kind: .new_history }
	}
	mut thread_extension_init := codex_extension_api.new_extension_data_init()
	if selected_capability_roots.len > 0 {
		thread_extension_init.insert_selected_capability_roots(selected_capability_roots)
	}
	mut reserved_thread_id := ?codex_protocol.ThreadId(none)
	mut cleanup_thread_id := ?codex_protocol.ThreadId(none)
	mut staged_project_id := store.ClearableString{}
	mut response_project_id := ?string(none)
	if value := project_id {
		staged_project_id = store.ClearableString{ has_value: true, value: value.clone() }
		response_project_id = value.clone()
	}
	if !config.ephemeral {
		operation := 'thread/start'
		reserved := stage_pending_thread_metadata(&listener_task_context.thread_manager, &thread_store, StoreThreadMetadataPatch{
			project_id: staged_project_id
		}, &operation)!
		if reserved.has_value {
			reserved_thread_id = copy_thread_id(&reserved.value)
			cleanup_thread_id = copy_thread_id(&reserved.value)
		}
	}
	create_thread_started_at := time.now()
	start_result := listener_task_context.thread_manager.start_thread(codex_core.StartThreadOptions{
		config:                        config
		allow_provider_model_fallback: allow_provider_model_fallback
		initial_history:               initial_history
		history_mode:                  resolved_history_mode
		thread_source:                 thread_source
		dynamic_tools:                 runtime_tools
		metrics_service_name:          service_name
		parent_trace:                  request_trace
		environments:                  resolved_environments
		thread_extension_init:         thread_extension_init
		client_mcp_extensions:         client_mcp_extensions
		reserved_thread_id:            reserved_thread_id
	})
	if start_result.kind == .error {
		remove_pending_thread_metadata(&thread_store, cleanup_thread_id)
		return match start_result.error_value.kind {
			.invalid_request { fail(invalid_request(start_result.error_value.message)) }
			.unsupported_operation { fail(method_not_found(start_result.error_value.message)) }
			.thread_not_found, .io, .json, .other {
				fail(internal_error('error creating thread: ${start_result.error_value.message}'))
			}
		}
	}
	new_thread := start_result.value
	session_telemetry := new_thread.thread.session_telemetry()
	create_phase := 'thread_start_create_thread'
	ready := 'ready'
	session_telemetry.record_startup_phase(&create_phase, time.since(create_thread_started_at).milliseconds(), ready)
	set_app_server_client_info(&new_thread.thread, app_server_client_name, app_server_client_version)!
	instruction_sources := new_thread.thread.legacy_instruction_sources()
	config_snapshot := new_thread.thread.config_snapshot()
	mut api_thread := build_thread_from_snapshot(copy_thread_id(&new_thread.thread_id), new_thread.session_configured.session_id.clone(), new_thread.thread.multi_agent_version(), &config_snapshot, clone_optional_string(new_thread.session_configured.rollout_path))
	api_thread.project_id = response_project_id
	// Auto-attach a thread listener when starting a thread.
	thread_kind := 'thread'
	mut listener_attach_succeeded := true
	listener_result := thread_lifecycle.ensure_conversation_listener(&listener_task_context, copy_thread_id(&new_thread.thread_id), request_id.connection_id, experimental_raw_events) or {
		listener_attach_succeeded = false
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:          .error
			error_message: err.msg()
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
		EnsureConversationListenerResult.connection_closed
	}
	if listener_attach_succeeded {
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:  .ok
			value: listener_result
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
	}
	listener_task_context.thread_watch_manager.upsert_thread_silently(&api_thread.id)
	api_thread.status = resolve_thread_status(listener_task_context.thread_watch_manager.loaded_status_for_thread(&api_thread.id), false)
	started_notification := thread_started_notification(clone_api_thread(&api_thread))
	response := api.ThreadStartResponse{
		thread:                    api_thread
		model:                     config_snapshot.model.clone()
		model_provider:            config_snapshot.model_provider_id.clone()
		service_tier:              clone_optional_string(config_snapshot.service_tier)
		cwd:                       config_snapshot.cwd()
		runtime_workspace_roots:   config_snapshot.workspace_roots.clone()
		instruction_sources:       instruction_sources
		approval_policy:           config_snapshot.approval_policy
		approvals_reviewer:        config_snapshot.approvals_reviewer
		sandbox:                   config_snapshot.sandbox_policy()
		active_permission_profile: thread_response_active_permission_profile(config_snapshot.active_permission_profile)
		reasoning_effort:          config_snapshot.reasoning_effort
		multi_agent_mode:          .explicit_request_only
	}
	listener_task_context.outgoing.send_response_with_thread_originator(clone_connection_request_id(&request_id), api.ClientResponsePayload(response), config_snapshot.originator.clone())
	listener_task_context.outgoing.send_server_notification(api.ServerNotification(started_notification))
	total_phase := 'thread_start_total'
	session_telemetry.record_startup_phase(&total_phase, time.since(thread_start_started_at).milliseconds(), ready)
}

fn (processor &ThreadRequestProcessor) build_thread_config_overrides(
	model ?string,
	model_provider ?string,
	service_tier api.ClearableString,
	cwd ?string,
	runtime_workspace_roots ?[]string,
	approval_policy ?api.AskForApproval,
	approvals_reviewer ?api.ApprovalsReviewer,
	sandbox ?api.SandboxMode,
	permissions ?string,
	base_instructions ?string,
	developer_instructions ?string,
	personality ?codex_protocol.Personality
) ConfigOverrides {
	return ConfigOverrides{
		model:                   model
		model_provider:          model_provider
		service_tier:            service_tier
		cwd:                     cwd
		workspace_roots:         runtime_workspace_roots
		default_permissions:     permissions
		approval_policy:         approval_policy
		approvals_reviewer:      approvals_reviewer
		sandbox_mode:            sandbox
		codex_linux_sandbox_exe: processor.arg0_paths.codex_linux_sandbox_exe.clone()
		main_execve_wrapper_exe: processor.arg0_paths.main_execve_wrapper_exe.clone()
		base_instructions:       base_instructions
		developer_instructions:  developer_instructions
		personality:             personality
	}
}

fn (processor &ThreadRequestProcessor) thread_archive_inner(
	params api.ThreadArchiveParams
) !(api.ThreadArchiveResponse, []string) {
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	return processor.thread_archive_response(params)
}

fn (processor &ThreadRequestProcessor) thread_archive_response(
	params api.ThreadArchiveParams
) !(api.ThreadArchiveResponse, []string) {
	archive_root_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid session id: ${err}'))
	}
	subtree_thread_ids := processor.state_db_spawn_subtree_thread_ids(codex_protocol.ThreadId{
		value: archive_root_id.value.clone()
	})!
	mut archive_thread_ids := []codex_protocol.ThreadId{}
	root_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        copy_thread_id(&archive_root_id)
		include_archived: false
		include_history:  false
	})
	if root_result.kind != .ok {
		operation := 'archive'
		return fail(thread_store_mutation_error(&operation, clone_thread_store_error(&root_result.error_value)))
	}
	if root_result.value.archived_at == none {
		archive_thread_ids << copy_thread_id(&archive_root_id)
	}
	for descendant_id in subtree_thread_ids[1..] {
		descendant_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
			thread_id:        copy_thread_id(&descendant_id)
			include_archived: true
			include_history:  false
		})
		if descendant_result.kind != .ok {
			descendant_error := clone_thread_store_error(&descendant_result.error_value)
			warning := 'failed to read spawned descendant thread ${descendant_id.str()} while archiving ${archive_root_id.str()}: ${descendant_error.message}'
			tracing.warn(&warning)
			continue
		}
		if descendant_result.value.archived_at == none {
			archive_thread_ids << copy_thread_id(&descendant_id)
		}
	}
	if archive_thread_ids.len == 0 {
		return api.ThreadArchiveResponse{}, []string{}
	}
	if archive_thread_ids.len > 1 {
		root_to_archive := codex_protocol.ThreadId{ value: archive_thread_ids[0].value.clone() }
		mut reversed_descendants := archive_thread_ids[1..].clone()
		reversed_descendants.reverse_in_place()
		archive_thread_ids = [root_to_archive]
		archive_thread_ids << reversed_descendants
	}
	// Collaboration may resume an archived descendant without unarchiving it.
	processor.prepare_thread_for_archive(codex_protocol.ThreadId{
		value: archive_root_id.value.clone()
	})!
	for index := subtree_thread_ids.len - 1; index > 0; index-- {
		processor.prepare_thread_for_archive(copy_thread_id(&subtree_thread_ids[index]))!
	}
	mut writer_lock_thread_ids := []codex_protocol.ThreadId{cap: subtree_thread_ids.len}
	for id in subtree_thread_ids {
		writer_lock_thread_ids << copy_thread_id(&id)
	}
	archive_result := processor.thread_store.archive_threads(archive_thread_ids, writer_lock_thread_ids)
	if archive_result.is_error {
		operation := 'archive'
		return fail(thread_store_mutation_error(&operation, clone_thread_store_error(&archive_result.error_value)))
	}
	archived_ids := archive_result.value
	mut archived_thread_ids := []string{cap: archived_ids.len}
	for id in archived_ids {
		archived_thread_ids << id.str()
	}
	return api.ThreadArchiveResponse{}, archived_thread_ids
}

pub fn (processor &ThreadRequestProcessor) state_db_spawn_subtree_thread_ids(
	thread_id codex_protocol.ThreadId
) ![]codex_protocol.ThreadId {
	return processor.thread_manager.list_agent_subtree_thread_ids(thread_id) or {
		return fail(internal_error('failed to list spawned descendants for thread id: ${err}'))
	}
}

fn (processor &ThreadRequestProcessor) thread_increment_elicitation_inner(
	params api.ThreadIncrementElicitationParams
) !api.ThreadIncrementElicitationResponse {
	_, thread_value := processor.load_thread(&params.thread_id)!
	count_result := thread_value.increment_out_of_band_elicitation_count()
	if count_result.is_error {
		return fail(internal_error('failed to increment out-of-band elicitation counter: ${count_result.error_value.message}'))
	}
	count := count_result.value
	return api.ThreadIncrementElicitationResponse{
		count:  count
		paused: count > 0
	}
}

fn (processor &ThreadRequestProcessor) thread_decrement_elicitation_inner(
	params api.ThreadDecrementElicitationParams
) !api.ThreadDecrementElicitationResponse {
	_, thread_value := processor.load_thread(&params.thread_id)!
	count_result := thread_value.decrement_out_of_band_elicitation_count()
	if count_result.is_error {
		if count_result.error_value.kind == .invalid_request {
			return fail(invalid_request(count_result.error_value.message.clone()))
		}
		return fail(internal_error('failed to decrement out-of-band elicitation counter: ${count_result.error_value.message}'))
	}
	count := count_result.value
	return api.ThreadDecrementElicitationResponse{
		count:  count
		paused: count > 0
	}
}

fn normalize_thread_name(name &string) ?string {
	normalized := trim_rust_whitespace(name)
	if normalized.len == 0 {
		return none
	}
	return normalized.clone()
}

fn (processor &ThreadRequestProcessor) thread_set_name_response_inner(
	params api.ThreadSetNameParams
) !(api.ThreadSetNameResponse, ?api.ThreadNameUpdatedNotification) {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	name := normalize_thread_name(&params.name) or {
		return fail(invalid_request('thread name must not be empty'))
	}
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	update_result := processor.thread_manager.update_thread_metadata(copy_thread_id(&thread_id), store.StoredThreadMetadataUpdatePatch{
		name: store.ClearableString{ has_value: true, value: name.clone() }
	}, false)
	if update_result.is_error {
		operation := 'set thread name'
		return fail(core_thread_write_error(&operation, clone_codex_error(&update_result.error_value)))
	}
	return api.ThreadSetNameResponse{}, api.ThreadNameUpdatedNotification{
		thread_id:   thread_id.str()
		thread_name: name
	}
}

fn (processor &ThreadRequestProcessor) thread_memory_mode_set_response_inner(
	params api.ThreadMemoryModeSetParams
) !api.ThreadMemoryModeSetResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	// Rust's UUID-backed ThreadId is Copy; preserve that boundary for V's string-backed port.
	update_result := processor.thread_manager.update_thread_metadata(copy_thread_id(&thread_id), store.StoredThreadMetadataUpdatePatch{
		memory_mode: params.mode
	}, false)
	if update_result.is_error {
		operation := 'set thread memory mode'
		return fail(core_thread_write_error(&operation, clone_codex_error(&update_result.error_value)))
	}
	return api.ThreadMemoryModeSetResponse{}
}

fn (processor &ThreadRequestProcessor) memory_reset_response_inner() !api.MemoryResetResponse {
	state_db := processor.state_db or {
		return fail(internal_error('sqlite state db unavailable for memory reset'))
	}
	state_db.memories().clear_memory_data() or {
		return fail(internal_error('failed to clear memory rows in memories db: ${err}'))
	}
	codex_memories_write.clear_memory_roots_contents(&processor.config.codex_home) or {
		return fail(internal_error('failed to clear memory directories under ${processor.config.codex_home}: ${err}'))
	}
	return api.MemoryResetResponse{}
}

fn (processor &ThreadRequestProcessor) thread_metadata_update_response_inner(
	params api.ThreadMetadataUpdateParams
) !api.ThreadMetadataUpdateResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	if params.git_info == none && params.project_id == none && params.daybreak_enabled == none {
		return fail(invalid_request('thread metadata update must include at least one field'))
	}
	mut project_patch := store.ClearableString{}
	if project_id := params.project_id {
		project_patch = store.ClearableString{
			has_value: true
			clear:     project_id.len == 0
			value:     project_id.clone()
		}
		if project_id.len == 0 {
			// The API uses an empty projectId to clear the association.
		} else {
			project_result := processor.thread_store.read_project(project_id.clone())
			if project_result.is_error {
				if project_result.error_value.kind == .unsupported {
					return fail(unsupported_thread_store_operation(&project_result.error_value.operation))
				}
				return fail(internal_error('failed to read project: ${project_result.error_value.message}'))
			}
			if !project_result.has_value {
				return fail(invalid_request('project not found: ${project_id}'))
			}
		}
	}
	mut git_patch := ?store.StoredGitInfoPatch(none)
	if git_info := params.git_info {
		if !git_info.sha.has_value && !git_info.branch.has_value && !git_info.origin_url.has_value {
			return fail(invalid_request('gitInfo must include at least one field'))
		}
		mut origin_url := store.ClearableString{}
		if git_info.origin_url.has_value {
			origin_url_label := 'gitInfo.originUrl'
			normalized_url := normalize_thread_metadata_git_field(git_info.origin_url, &origin_url_label)!
			if !normalized_url.clear {
				codex_protocol.sanitized_git_url_from_string(normalized_url.value.clone()) or {
					return fail(invalid_request('gitInfo.originUrl must be a valid Git remote'))
				}
			}
			origin_url = store.ClearableString{
				has_value: true
				clear:     normalized_url.clear
				value:     normalized_url.value.clone()
			}
		}
		mut sha := store.ClearableString{}
		if git_info.sha.has_value {
			sha_label := 'gitInfo.sha'
			normalized_sha := normalize_thread_metadata_git_field(git_info.sha, &sha_label)!
			sha = store.ClearableString{
				has_value: true
				clear:     normalized_sha.clear
				value:     normalized_sha.value.clone()
			}
		}
		mut branch := store.ClearableString{}
		if git_info.branch.has_value {
			branch_label := 'gitInfo.branch'
			normalized_branch := normalize_thread_metadata_git_field(git_info.branch, &branch_label)!
			branch = store.ClearableString{
				has_value: true
				clear:     normalized_branch.clear
				value:     normalized_branch.value.clone()
			}
		}
		git_patch = store.StoredGitInfoPatch{
			sha:            sha
			branch:         branch
			repository_url: origin_url
		}
	}
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	mut previous_project_marker := '__not-read__'
	if project_patch.has_value {
		stored_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
			thread_id:        copy_thread_id(&thread_id)
			include_archived: true
			include_history:  false
		})
		if stored_result.kind != .ok {
			read_error := clone_thread_store_error(&stored_result.error_value)
			return fail(match read_error.kind {
				.thread_not_found { invalid_request('thread not found: ${params.thread_id}') }
				.unsupported { unsupported_thread_store_operation(&read_error.operation) }
				.invalid_request, .conflict, .internal {
					internal_error('failed to read thread metadata: ${read_error.message}')
				}
			})
		}
		previous_project_marker = stored_result.value.project_id or { '' }
	}
	updated_result := processor.thread_manager.update_thread_metadata(copy_thread_id(&thread_id), store.StoredThreadMetadataUpdatePatch{
		git_info:         git_patch
		// Rust explicitly clones this double-option before the manager consumes its patch.
		project_id:       store.ClearableString{
			has_value: project_patch.has_value
			clear:     project_patch.clear
			value:     project_patch.value.clone()
		}
		daybreak_enabled: params.daybreak_enabled
	}, true)
	if updated_result.is_error {
		operation := 'update thread metadata'
		return fail(core_thread_write_error(&operation, clone_codex_error(&updated_result.error_value)))
	}
	updated_thread := updated_result.value
	if project_patch.has_value {
		updated_project := if project_patch.clear { '' } else { project_patch.value.clone() }
		if previous_project_marker != updated_project {
			project_notification := if project_patch.clear {
				?string(none)
			} else {
				?string(project_patch.value.clone())
			}
			processor.outgoing.send_server_notification(api.ServerNotification(api.ThreadProjectUpdatedNotification{
				thread_id:  params.thread_id.clone()
				project_id: project_notification
			}))
		}
	}
	mut thread_value, _ := thread_from_stored_thread(updated_thread, &processor.config.model_provider_id, &processor.config.cwd)
	if loaded := processor.thread_manager.get_thread(&thread_id) {
		session_configured := loaded.session_configured()
		config_snapshot := loaded.config_snapshot()
		thread_value.session_id = session_configured.session_id
		apply_live_thread_settings(mut thread_value, &config_snapshot)
	}
	processor.attach_thread_name(copy_thread_id(&thread_id), mut thread_value)
	thread_value.status = resolve_thread_status(processor.thread_watch_manager.loaded_status_for_thread(&thread_value.id), false)
	return api.ThreadMetadataUpdateResponse{
		thread: thread_value
	}
}

fn normalize_thread_metadata_git_field(
	value api.ClearableString,
	name &string
) !api.ClearableString {
	if value.clear {
		return value
	}
	normalized := trim_rust_whitespace(&value.value)
	if normalized.len == 0 {
		return fail(invalid_request('${*name} must not be empty'))
	}
	return api.ClearableString{
		has_value: true
		value:     normalized
	}
}

fn (processor &ThreadRequestProcessor) thread_unarchive_inner(
	params api.ThreadUnarchiveParams
) !(api.ThreadUnarchiveResponse, api.ThreadUnarchivedNotification) {
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	response, thread_id := processor.thread_unarchive_response(params)!
	return response, api.ThreadUnarchivedNotification{ thread_id: thread_id }
}

fn (processor &ThreadRequestProcessor) thread_unarchive_response(
	params api.ThreadUnarchiveParams
) !(api.ThreadUnarchiveResponse, string) {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid session id: ${err}'))
	}
	unarchive_result := processor.thread_store.unarchive_thread(copy_thread_id(&thread_id))
	if unarchive_result.is_error {
		operation := 'unarchive'
		return fail(thread_store_mutation_error(&operation, clone_thread_store_error(&unarchive_result.error_value)))
	}
	stored_thread := unarchive_result.value
	mut thread_value, _ := thread_from_stored_thread(stored_thread, &processor.config.model_provider_id, &processor.config.cwd)
	if loaded := processor.thread_manager.get_thread(&thread_id) {
		config_snapshot := loaded.config_snapshot()
		apply_live_thread_settings(mut thread_value, &config_snapshot)
	}
	thread_value.status = resolve_thread_status(processor.thread_watch_manager.loaded_status_for_thread(&thread_value.id), false)
	processor.attach_thread_name(copy_thread_id(&thread_id), mut thread_value)
	return api.ThreadUnarchiveResponse{ thread: thread_value }, thread_id.str()
}

fn (processor &ThreadRequestProcessor) thread_rollback_inner(
	request_id &ConnectionRequestId,
	params api.ThreadRollbackParams
) ! {
	processor.thread_rollback_start(request_id, params)!
}

fn (processor &ThreadRequestProcessor) thread_revert_response(
	request_id &ConnectionRequestId,
	params api.ThreadRevertParams,
	app_server_client_name ?string,
	app_server_client_version ?string
) !(api.ThreadRevertResponse, string) {
	permit := processor.acquire_thread_list_state_permit()!
	defer {
		permit.release()
	}
	thread_id, thread_value := processor.load_thread(&params.thread_id)!
	ensure_direct_input_allowed(&thread_value) or { return fail(invalid_request(err.msg())) }
	config_snapshot := thread_value.config_snapshot()
	if config_snapshot.history_mode != .paginated {
		return fail(invalid_request('thread/revert only supports paginated threads'))
	}
	runtime_snapshot := ThreadRevertRuntimeSnapshot{
		config:                thread_value.config()
		settings:              thread_value.restorable_thread_settings()
		client_mcp_extensions: thread_value.client_mcp_extensions()
	}
	// Subscribe before shutdown so a pending idle unload either rejects this request or can
	// no longer race the replacement runtime. The same listener then drains Core's shutdown
	// events before we replace it.
	listener_result := processor.ensure_conversation_listener(copy_thread_id(&thread_id), request_id.connection_id, false)!
	if listener_result == .connection_closed {
		return fail(internal_error('connection closed before thread ${thread_id.value} could be reverted'))
	}
	thread_state := processor.thread_state_manager.thread_state(&thread_id)
	shutdown_drain_rx := thread_state.register_shutdown_drain_waiter()
	match wait_for_thread_shutdown(&thread_value) {
		.complete {}
		.submit_failed {
			thread_state.take_shutdown_drain_waiter()
			return fail(internal_error('failed to shut down thread ${thread_id.value} before revert'))
		}
		.timed_out {
			thread_state.take_shutdown_drain_waiter()
			return fail(internal_error('timed out shutting down thread ${thread_id.value} before revert'))
		}
		else {}
	}
	match shutdown_drain_rx.wait(10_000) {
		.complete {}
		.timed_out {
			thread_state.take_shutdown_drain_waiter()
			return fail(internal_error('timed out waiting for thread ${thread_id.value} listener to drain shutdown events'))
		}
		.listener_stopped {
			thread_state.take_shutdown_drain_waiter()
			return fail(internal_error('thread ${thread_id.value} listener stopped before draining shutdown events'))
		}
	}
	removed_result := processor.thread_manager.remove_thread(&thread_id)
	if removed_result.is_error {
		operation := 'revert thread'
		return fail(core_thread_write_error(&operation, clone_codex_error(&removed_result.error_value)))
	}
	removed := removed_result.value
	if !removed.has_value {
		return fail(internal_error('thread ${thread_id.value} disappeared before revert'))
	}
	// Keep thread state and subscriptions across the internal reload. Full teardown would
	// force clients to call thread/resume after a successful revert.
	processor.outgoing.cancel_requests_for_thread(copy_thread_id(&thread_id))
	revert_result := processor.thread_store.revert_thread(store.RevertThreadParams{
		thread_id:           copy_thread_id(&thread_id)
		before_turn_id:      params.before_turn_id
		multi_agent_version: thread_value.multi_agent_version()
	})
	response := processor.reload_paginated_thread(request_id, copy_thread_id(&thread_id), runtime_snapshot, app_server_client_name, app_server_client_version)!
	if revert_result.is_error {
		operation := 'revert'
		return fail(thread_store_mutation_error(&operation, clone_thread_store_error(&revert_result.error_value)))
	}
	return response, thread_id.str()
}

fn (processor &ThreadRequestProcessor) reload_paginated_thread(
	reload_request_id &ConnectionRequestId,
	thread_id codex_protocol.ThreadId,
	runtime_snapshot ThreadRevertRuntimeSnapshot,
	app_server_client_name ?string,
	app_server_client_version ?string
) !api.ThreadRevertResponse {
	stored_thread := processor.read_stored_thread_for_resume(&thread_id.value, none, false)!
	thread_history, resume_source_thread := processor.load_resume_initial_history_from_stored_thread(stored_thread)!
	response_history := clone_initial_history(&thread_history)
	// V3's ownership pass currently aliases identically named parameters across the spawned
	// thread/start closure. Keep this borrowed request distinctly named at the V boundary.
	trace_request_id := clone_connection_request_id(reload_request_id)
	resume_result := processor.thread_manager.resume_thread_with_history(runtime_snapshot.config, thread_history, codex_login.clone_auth_manager(&processor.auth_manager), processor.request_trace_context(&trace_request_id), runtime_snapshot.client_mcp_extensions)
	if resume_result.is_error {
		return fail(internal_error('error reloading thread after revert: ${resume_result.error_value.message}'))
	}
	new_thread := resume_result.value
	if new_thread.thread_id.value != thread_id.value {
		return fail(internal_error('thread ${thread_id.value} reloaded as ${new_thread.thread_id.value} after revert'))
	}
	new_thread.thread.restore_thread_settings(runtime_snapshot.settings) or {
		return fail(internal_error('failed to restore thread settings after revert: ${err}'))
	}
	set_app_server_client_info(&new_thread.thread, app_server_client_name, app_server_client_version)!
	rollout_path := new_thread.session_configured.rollout_path or {
		return fail(internal_error('rollout path missing after reloading thread ${thread_id.value}'))
	}
	// Revert keeps the existing thread state and subscriptions across the internal reload.
	// Start the replacement listener from that state instead of depending on the requesting
	// connection still being open.
	reload_thread_state := processor.thread_state_manager.thread_state(&thread_id)
	processor.ensure_listener_task_running(copy_thread_id(&thread_id), clone_codex_thread(&new_thread.thread), &reload_thread_state)!
	mut thread_value := processor.load_thread_from_resume_source_or_send_internal(copy_thread_id(&thread_id), &new_thread.thread, &response_history, &rollout_path, resume_source_thread, false)!
	processor.thread_watch_manager.upsert_thread(&thread_value.id)
	loaded_status := processor.thread_watch_manager.loaded_status_for_thread(&thread_value.id)
	set_thread_status_and_interrupt_stale_turns(mut thread_value, loaded_status, false)
	cursors := paginated_resume_backwards_cursors(&processor.thread_store, copy_thread_id(&thread_id))!
	return api.ThreadRevertResponse{
		thread:                 thread_value
		turns_backwards_cursor: cursors.turns
		items_backwards_cursor: cursors.items
	}
}

fn (processor &ThreadRequestProcessor) thread_rollback_start(
	request_id &ConnectionRequestId,
	params api.ThreadRollbackParams
) ! {
	if params.num_turns == 0 {
		return fail(invalid_request('numTurns must be >= 1'))
	}
	thread_id, thread_value := processor.load_thread(&params.thread_id)!
	ensure_direct_input_allowed(&thread_value) or {
		return fail(invalid_request(err.msg()))
	}
	config_snapshot := thread_value.config_snapshot()
	if config_snapshot.history_mode == .paginated {
		return fail(invalid_request('paginated threads do not support thread/rollback'))
	}
	if !processor.thread_state_manager.begin_rollback(&thread_id, clone_connection_request_id(request_id)) {
		return fail(invalid_request('rollback already in progress for this thread'))
	}
	processor.submit_core_op(request_id, &thread_value, codex_protocol.Op{
		op_kind:   .thread_rollback
		num_turns: params.num_turns
	}) or {
		// No ThreadRollback event will arrive if an error occurs.
		// Clean up and reply immediately.
		processor.thread_state_manager.clear_rollback(&thread_id)
		return fail(internal_error('failed to start rollback: ${err}'))
	}
}

fn (processor &ThreadRequestProcessor) thread_compact_start_inner(
	request_id &ConnectionRequestId,
	params api.ThreadCompactStartParams
) !api.ThreadCompactStartResponse {
	_, thread_value := processor.load_thread(&params.thread_id)!
	ensure_direct_input_allowed(&thread_value) or { return fail(invalid_request(err.msg())) }
	processor.submit_core_op(request_id, &thread_value, codex_protocol.Op{
		op_kind: .compact
	}) or { return fail(internal_error('failed to start compaction: ${err}')) }
	return api.ThreadCompactStartResponse{}
}

fn (processor &ThreadRequestProcessor) thread_background_terminals_clean_inner(
	request_id &ConnectionRequestId,
	params api.ThreadBackgroundTerminalsCleanParams
) !api.ThreadBackgroundTerminalsCleanResponse {
	_, thread_value := processor.load_thread(&params.thread_id)!
	processor.submit_core_op(request_id, &thread_value, codex_protocol.Op{
		op_kind: .clean_background_terminals
	}) or { return fail(internal_error('failed to clean background terminals: ${err}')) }
	return api.ThreadBackgroundTerminalsCleanResponse{}
}

fn (processor &ThreadRequestProcessor) thread_background_terminals_list_inner(
	params api.ThreadBackgroundTerminalsListParams
) !api.ThreadBackgroundTerminalsListResponse {
	_, thread_value := processor.load_thread(&params.thread_id)!
	background_terminals := thread_value.list_background_terminals()
	mut terminals := []api.ThreadBackgroundTerminal{cap: background_terminals.len}
	for terminal in background_terminals {
		terminals << api.ThreadBackgroundTerminal{
			item_id:     terminal.item_id
			process_id:  terminal.process_id
			command:     terminal.command
			cwd:         terminal.cwd
			os_pid:      none
			cpu_percent: none
			rss_kb:      none
		}
	}
	data, next_cursor := paginate_background_terminals(&terminals, params.cursor, params.limit)!
	return api.ThreadBackgroundTerminalsListResponse{
		data:        data
		next_cursor: next_cursor
	}
}

fn (processor &ThreadRequestProcessor) thread_background_terminals_terminate_inner(
	params api.ThreadBackgroundTerminalsTerminateParams
) !api.ThreadBackgroundTerminalsTerminateResponse {
	process_id := parse_i32_strict(&params.process_id) or {
		return fail(invalid_request('invalid background terminal process id: ${params.process_id}'))
	}
	_, thread_value := processor.load_thread(&params.thread_id)!
	terminated := thread_value.terminate_background_terminal(process_id)
	return api.ThreadBackgroundTerminalsTerminateResponse{ terminated: terminated }
}

fn (processor &ThreadRequestProcessor) thread_shell_command_inner(
	request_id &ConnectionRequestId,
	params api.ThreadShellCommandParams
) !api.ThreadShellCommandResponse {
	command := trim_rust_whitespace(&params.command)
	if command.len == 0 {
		return fail(invalid_request('command must not be empty'))
	}
	if timeout_ms := params.timeout_ms {
		if timeout_ms < 0 {
			return fail(invalid_params('thread/shellCommand timeoutMs must be non-negative, got ${timeout_ms}'))
		}
	}
	_, thread_value := processor.load_thread(&params.thread_id)!
	ensure_direct_input_allowed(&thread_value) or { return fail(invalid_request(err.msg())) }
	// `thread/shellCommand` is app-server's local-host shell escape hatch,
	// not the normal turn-selected shell tool path.
	if processor.thread_manager.environment_manager().try_local_environment() == none {
		return fail(internal_error('local environment is not configured'))
	}
	mut timeout := ?u64(none)
	if timeout_ms := params.timeout_ms {
		timeout = u64(timeout_ms)
	}
	processor.submit_core_op(request_id, &thread_value, codex_protocol.Op{
		op_kind:    .run_user_shell_command
		command:    command
		timeout_ms: timeout
	}) or { return fail(internal_error('failed to start shell command: ${err}')) }
	return api.ThreadShellCommandResponse{}
}

fn (processor &ThreadRequestProcessor) thread_approve_guardian_denied_action_inner(
	request_id &ConnectionRequestId,
	params api.ThreadApproveGuardianDeniedActionParams
) !api.ThreadApproveGuardianDeniedActionResponse {
	event := json2.decode[codex_protocol.GuardianAssessmentEvent](params.event) or {
		return fail(invalid_request('invalid Guardian denial event: ${err}'))
	}
	_, thread_value := processor.load_thread(&params.thread_id)!
	ensure_direct_input_allowed(&thread_value) or { return fail(invalid_request(err.msg())) }
	processor.submit_core_op(request_id, &thread_value, codex_protocol.Op{
		op_kind:        .approve_guardian_denied_action
		guardian_event: event
	}) or { return fail(internal_error('failed to approve Guardian denial: ${err}')) }
	return api.ThreadApproveGuardianDeniedActionResponse{}
}

fn (processor &ThreadRequestProcessor) thread_list_response_inner(
	params api.ThreadListParams
) !api.ThreadListResponse {
	if originators := params.originators {
		if originators.len > 0 {
			return fail(invalid_params('originator filtering is not supported by the local app-server'))
		}
	}
	if params.project_id.has_value && !processor.thread_store.supports_projects() {
		project_operation := 'projects'
		return fail(unsupported_thread_store_operation(&project_operation))
	}
	if params.project_id.has_value && !params.project_id.clear {
		if params.project_id.value.len == 0 {
			return fail(invalid_params('projectId must not be empty'))
		}
		project_result := processor.thread_store.read_project(params.project_id.value.clone())
		if project_result.is_error {
			if project_result.error_value.kind == .unsupported {
				return fail(unsupported_thread_store_operation(&project_result.error_value.operation))
			}
			return fail(internal_error('failed to read project: ${project_result.error_value.message}'))
		}
		if !project_result.has_value {
			return fail(invalid_params('project not found: ${params.project_id.value}'))
		}
	}
	cwd_filters := normalize_thread_list_cwd_filters(params.cwd)!
	if params.parent_thread_id != none && params.ancestor_thread_id != none {
		return fail(invalid_request('parentThreadId and ancestorThreadId are mutually exclusive'))
	}
	mut relation_filter := ?store.ThreadRelationFilter(none)
	if parent_id := params.parent_thread_id {
		id := codex_protocol.thread_id_from_string(&parent_id) or {
			return fail(invalid_request('invalid parent thread id: ${err}'))
		}
		relation_filter = store.ThreadRelationFilter{
			kind:      .direct_children_of
			thread_id: id
		}
	} else if ancestor_id := params.ancestor_thread_id {
		id := codex_protocol.thread_id_from_string(&ancestor_id) or {
			return fail(invalid_request('invalid ancestor thread id: ${err}'))
		}
		relation_filter = store.ThreadRelationFilter{
			kind:      .descendants_of
			thread_id: id
		}
	}
	requested_page_size := clamp_page_size(params.limit, thread_list_default_limit, thread_list_max_limit)
	store_sort_key := match params.sort_key or { api.ThreadSortKey.created_at } {
		.created_at { store.ThreadSortKey.created_at }
		.updated_at { store.ThreadSortKey.updated_at }
		.recency_at { store.ThreadSortKey.recency_at }
		.section_position { store.ThreadSortKey.section_position }
	}
	sort_direction := params.sort_direction or {
		if store_sort_key == .section_position { api.SortDirection.asc } else { api.SortDirection.desc }
	}
	filters := ThreadListFilters{
		model_providers:   params.model_providers
		source_kinds:      params.source_kinds
		archived:          params.archived or { false }
		section_id:        params.section_id
		project_id:        params.project_id
		cwd_filters:       cwd_filters
		search_term:       params.search_term
		use_state_db_only: params.use_state_db_only
		relation_filter:   relation_filter
	}
	stored_threads, next_cursor := processor.list_threads_common(requested_page_size, params.cursor, store_sort_key, sort_direction, filters)!
	mut backwards_cursor := ?string(none)
	if stored_threads.len > 0 {
		backwards_cursor = thread_backwards_cursor_for_sort_key(&stored_threads[0], store_sort_key, sort_direction)
	}
	mut data := []api.Thread{cap: stored_threads.len}
	for stored_thread in stored_threads {
		thread_value, _ := thread_from_stored_thread(stored_thread, &processor.config.model_provider_id, &processor.config.cwd)
		data << thread_value
	}
	enrich_loaded_thread_summaries(&processor.thread_manager, &processor.thread_watch_manager, mut data)
	return api.ThreadListResponse{
		data:             data
		next_cursor:      next_cursor
		backwards_cursor: backwards_cursor
	}
}

fn (processor &ThreadRequestProcessor) thread_search_response_inner(
	params api.ThreadSearchParams
) !api.ThreadSearchResponse {
	search_term := trim_rust_whitespace(&params.search_term)
	if search_term.len == 0 {
		return fail(invalid_request('thread/search requires a non-empty searchTerm'))
	}
	requested_page_size := clamp_page_size(params.limit, thread_list_default_limit, thread_list_max_limit)
	store_sort_key := match params.sort_key or { api.ThreadSearchSortKey.created_at } {
		.created_at { store.ThreadSortKey.created_at }
		.updated_at { store.ThreadSortKey.updated_at }
		.recency_at { store.ThreadSortKey.recency_at }
	}
	api_sort_direction := params.sort_direction or { api.SortDirection.desc }
	store_direction := match api_sort_direction {
		.asc { store.SortDirection.asc }
		.desc { store.SortDirection.desc }
	}
	source_filters := app_filters.compute_source_filters(params.source_kinds)
	mut cursor := clone_optional_string(params.cursor)
	mut last_cursor := clone_optional_string(cursor)
	mut remaining := requested_page_size
	mut results := []store.StoredThreadSearchResult{cap: requested_page_size}
	mut next_cursor := ?string(none)
	for remaining > 0 {
		page_size := if remaining < thread_list_max_limit {
			remaining
		} else {
			thread_list_max_limit
		}
		mut allowed_sources := []codex_protocol.SessionSource{cap: source_filters.allowed_sources.len}
		for source in source_filters.allowed_sources {
			allowed_sources << codex_protocol.clone_session_source(&source)
		}
		page_result := processor.thread_store.search_threads(store.StoreSearchThreadsParams{
			page_size:       page_size
			cursor:          clone_optional_string(cursor)
			sort_key:        store_sort_key
			sort_direction:  store_direction
			allowed_sources: allowed_sources
			archived:        params.archived or { false }
			search_term:     search_term.clone()
		})
		if page_result.is_error {
			return fail(thread_store_list_error(clone_thread_store_error(&page_result.error_value)))
		}
		page := page_result.value
		for result in page.items {
			source := with_thread_spawn_agent_metadata(codex_protocol.clone_session_source(&result.thread.source), clone_optional_string(result.thread.agent_nickname), clone_optional_string(result.thread.agent_role))
			if source_filter := source_filters.post_filter {
				if source_filter.len > 0
					&& !app_filters.source_kind_matches(&source, &source_filter) {
					continue
				}
			}
			results << result
			if results.len >= requested_page_size {
				break
			}
		}
		remaining = requested_page_size - results.len
		next_cursor = page.next_cursor
		if remaining == 0 {
			break
		}
		cursor_value := next_cursor or { break }
		if previous := last_cursor {
			if previous == cursor_value {
				next_cursor = none
				break
			}
		}
		last_cursor = cursor_value.clone()
		cursor = cursor_value
	}
	mut backwards_cursor := ?string(none)
	if results.len > 0 {
		backwards_cursor = thread_backwards_cursor_for_sort_key(&results[0].thread, store_sort_key, api_sort_direction)
	}
	mut data := []api.ThreadSearchResult{cap: results.len}
	for result in results {
		thread_value, _ := thread_from_stored_thread(result.thread, &processor.config.model_provider_id, &processor.config.cwd)
		data << api.ThreadSearchResult{ thread: thread_value, snippet: result.snippet }
	}
	enrich_loaded_thread_search_results(&processor.thread_manager, &processor.thread_watch_manager, mut data)
	return api.ThreadSearchResponse{
		data:             data
		next_cursor:      next_cursor
		backwards_cursor: backwards_cursor
	}
}

fn (processor &ThreadRequestProcessor) thread_loaded_list_response_inner(
	params api.ThreadLoadedListParams
) !api.ThreadLoadedListResponse {
	loaded_thread_ids := processor.thread_manager.list_thread_ids()
	mut data := []string{cap: loaded_thread_ids.len}
	for thread_id in loaded_thread_ids {
		data << thread_id.str()
	}
	if data.len == 0 {
		return api.ThreadLoadedListResponse{}
	}
	data.sort()
	total := data.len
	mut start := 0
	if cursor := params.cursor {
		cursor_id := codex_protocol.thread_id_from_string(&cursor) or {
			return fail(invalid_request('invalid cursor: ${cursor}'))
		}
		for index, value in data {
			if value <= cursor_id.value {
				start = index + 1
			} else {
				break
			}
		}
	}
	requested_limit := int(params.limit or { u32(total) })
	effective_limit := if requested_limit < 1 { 1 } else { requested_limit }
	page_end := start + effective_limit
	end := if page_end < total { page_end } else { total }
	page := if start < total { data[start..end].clone() } else { []string{} }
	mut next_cursor := ?string(none)
	if end < total && page.len > 0 {
		next_cursor = page.last().clone()
	}
	return api.ThreadLoadedListResponse{
		data:        page
		next_cursor: next_cursor
	}
}

fn (processor &ThreadRequestProcessor) thread_read_response_inner(
	params api.ThreadReadParams
) !api.ThreadReadResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	thread_value := processor.read_thread_view(thread_id, params.include_turns)!
	return api.ThreadReadResponse{ thread: thread_value }
}

/// Builds the API view for `thread/read` from persisted metadata plus optional live state.
fn (processor &ThreadRequestProcessor) read_thread_view(
	thread_id codex_protocol.ThreadId,
	include_turns bool
) !api.Thread {
	mut has_loaded_thread := false
	mut loaded_thread := CodexThread{}
	if live := processor.thread_manager.get_thread(&thread_id) {
		has_loaded_thread = true
		loaded_thread = clone_codex_thread(&live)
	}
	mut thread_value := api.Thread{}
	if include_turns {
		if has_loaded_thread {
			// Loaded thread with turns: use persisted metadata when it exists,
			// but reconstruct turns from the live ThreadStore history.
			persisted := processor.load_persisted_thread_for_read(copy_thread_id(&thread_id), false)!
			if persisted.has_value {
				thread_value = processor.load_live_thread_view(copy_thread_id(&thread_id), include_turns,
					&loaded_thread, persisted.value)!
			} else {
				thread_value = processor.load_live_thread_view(copy_thread_id(&thread_id), include_turns,
					&loaded_thread, none)!
			}
		} else {
			persisted := processor.load_persisted_thread_for_read(copy_thread_id(&thread_id), true)!
			if !persisted.has_value {
				return fail(invalid_request('thread not loaded: ${thread_id.str()}'))
			}
			// Unloaded thread with turns: load metadata and history together
			// from the ThreadStore.
			thread_value = persisted.value
		}
	} else {
		persisted := processor.load_persisted_thread_for_read(copy_thread_id(&thread_id), false)!
		if persisted.has_value {
			if has_loaded_thread {
				thread_value = processor.load_live_thread_view(copy_thread_id(&thread_id), include_turns,
					&loaded_thread, persisted.value)!
			} else {
				thread_value = persisted.value
			}
		} else if has_loaded_thread {
			// Loaded metadata-only read before persistence is materialized: build
			// the response from the live thread snapshot.
			thread_value = processor.load_live_thread_view(copy_thread_id(&thread_id), include_turns,
				&loaded_thread, none)!
		} else {
			return fail(invalid_request('thread not loaded: ${thread_id.str()}'))
		}
	}
	has_live_in_progress_turn := has_loaded_thread && loaded_thread.agent_status() == .running
	loaded_status := processor.thread_watch_manager.loaded_status_for_thread(&thread_value.id)
	set_thread_status_and_interrupt_stale_turns(mut thread_value, loaded_status,
		has_live_in_progress_turn)
	return thread_value
}

fn (processor &ThreadRequestProcessor) load_persisted_thread_for_read(
	thread_id codex_protocol.ThreadId,
	include_turns bool
) !OptionalApiThread {
	fallback_provider := processor.config.model_provider_id.clone()
	if include_turns {
		stored_result := processor.read_stored_thread_for_read(copy_thread_id(&thread_id), false)!
		if !stored_result.has_value {
			return OptionalApiThread{}
		}
		if stored_result.value.history_mode == .paginated {
			mut thread_value, _ := thread_from_stored_thread(stored_result.value, &fallback_provider, &processor.config.cwd)
			thread_value.turns = processor.paginated_thread_full_turns(copy_thread_id(&thread_id))!
			return OptionalApiThread{
				has_value: true
				value:     thread_value
			}
		}
	}
	stored_result := processor.read_stored_thread_for_read(copy_thread_id(&thread_id), include_turns)!
	if !stored_result.has_value {
		return OptionalApiThread{}
	}
	mut thread_value, history := thread_from_stored_thread(stored_result.value, &fallback_provider, &processor.config.cwd)
	if include_turns {
		if stored_history := history {
			thread_lifecycle.populate_thread_turns_from_history(mut thread_value, &stored_history.items, none)
		}
	}
	return OptionalApiThread{
		has_value: true
		value:     thread_value
	}
}

fn (processor &ThreadRequestProcessor) read_stored_thread_for_read(
	thread_id codex_protocol.ThreadId,
	include_history bool
) !OptionalStoredThread {
	result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        copy_thread_id(&thread_id)
		include_archived: true
		include_history:  include_history
	})
	if result.kind == .ok {
		return OptionalStoredThread{
			has_value: true
			value:     result.value
		}
	}
	// V's explicit typed-result wrapper cannot move an owned error field after borrowing the
	// wrapper. Materialize the Rust match arm's owned error at this boundary.
	error_value := clone_thread_store_error(&result.error_value)
	if is_exact_thread_store_miss(&thread_id, &error_value) {
		return OptionalStoredThread{}
	}
	view_error := match error_value.kind {
		.invalid_request {
			ThreadReadViewError{
				kind:    .invalid_request
				message: error_value.message
			}
		}
		.unsupported {
			ThreadReadViewError{
				kind:      .unsupported
				operation: error_value.operation
			}
		}
		.thread_not_found, .conflict, .internal {
			ThreadReadViewError{
				kind:    .internal
				message: 'failed to read thread: ${error_value.message}'
			}
		}
	}
	return fail(thread_read_view_error(view_error))
}

/// Builds a `thread/read` view from a loaded thread plus optional persisted metadata.
fn (processor &ThreadRequestProcessor) load_live_thread_view(
	thread_id codex_protocol.ThreadId,
	include_turns bool,
	loaded_thread &CodexThread,
	persisted_thread ?api.Thread
) !api.Thread {
	config_snapshot := loaded_thread.config_snapshot()
	if include_turns && config_snapshot.ephemeral {
		return fail(invalid_request('ephemeral threads do not support includeTurns'))
	}
	mut thread_value := if existing := persisted_thread {
		mut persisted := existing
		fallback := build_thread_from_loaded_snapshot(copy_thread_id(&thread_id), &config_snapshot,
			loaded_thread)
		if persisted.path == none {
			persisted.path = clone_optional_string(fallback.path)
		}
		persisted.session_id = fallback.session_id
		persisted.ephemeral = fallback.ephemeral
		persisted.can_accept_direct_input = fallback.can_accept_direct_input
		persisted
	} else {
		build_thread_from_loaded_snapshot(copy_thread_id(&thread_id), &config_snapshot, loaded_thread)
	}
	apply_live_thread_settings(mut thread_value, &config_snapshot)
	processor.apply_thread_read_store_fields(thread_id, mut thread_value, include_turns, loaded_thread)!
	return thread_value
}

fn (processor &ThreadRequestProcessor) apply_thread_read_store_fields(
	thread_id codex_protocol.ThreadId,
	mut thread_value api.Thread,
	include_turns bool,
	loaded_thread &CodexThread
) ! {
	processor.attach_thread_name(copy_thread_id(&thread_id), mut thread_value)
	if include_turns {
		if thread_value.history_mode == .paginated {
			persist_result := processor.thread_store.persist_thread(copy_thread_id(&thread_id), .standard)
			if persist_result.is_error {
				persist_error := clone_thread_store_error(&persist_result.error_value)
				return fail(thread_read_view_error(thread_read_history_load_error(copy_thread_id(&thread_id), persist_error)))
			}
			thread_value.turns = processor.paginated_thread_full_turns(thread_id)!
			return
		}
		history_result := loaded_thread.load_history(true)
		if history_result.is_error {
			return fail(thread_read_view_error(thread_read_history_load_error(copy_thread_id(&thread_id),
				clone_thread_store_error(&history_result.error_value))))
		}
		thread_lifecycle.populate_thread_turns_from_history(mut thread_value, &history_result.value.items,
			none)
	}
}

fn (processor &ThreadRequestProcessor) thread_turns_list_response_inner(
	params api.ThreadTurnsListParams
) !api.ThreadTurnsListResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	stored_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        copy_thread_id(&thread_id)
		include_archived: true
		include_history:  false
	})
	if stored_result.kind == .ok && stored_result.value.history_mode == .paginated {
		return processor.paginated_thread_turns_list_response(copy_thread_id(&thread_id),
			params.cursor, params.limit, params.sort_direction, params.items_view)
	}
	if stored_result.kind != .ok {
		error_value := clone_thread_store_error(&stored_result.error_value)
		if !is_exact_thread_store_miss(&thread_id, &error_value) {
			materialization_message := 'thread/turns/list is unavailable before first user message'
			return fail(thread_read_view_error(thread_store_error_to_read_view(copy_thread_id(&thread_id),
				error_value, &materialization_message)))
		}
	}
	// This API optimizes network transfer by letting clients page through a
	// thread's turns incrementally, but it still replays the entire rollout on
	// every request. Rollback and compaction events can change earlier turns, so
	// the server has to rebuild the full turn list until turn metadata is indexed
	// separately.
	items := processor.load_thread_turns_list_history(copy_thread_id(&thread_id))!
	// Persisted history may not yet include the currently running turn. The
	// app-server listener has already projected live turn events into ThreadState,
	// so merge that in-memory snapshot before paginating.
	mut has_live_running_thread := false
	mut has_loaded_thread := false
	if loaded := processor.thread_manager.get_thread(&thread_id) {
		has_loaded_thread = true
		has_live_running_thread = loaded.agent_status() == .running
	}
	active_turn := if has_loaded_thread {
		processor.thread_state_manager.active_turn_snapshot(&thread_id)
	} else {
		?api.Turn(none)
	}
	thread_status := processor.thread_watch_manager.loaded_status_for_thread(&thread_id.value)
	return build_thread_turns_page_response(&items, thread_status, has_live_running_thread, active_turn, ThreadTurnsPageOptions{
		cursor:         params.cursor or { '' }
		has_cursor:     params.cursor != none
		limit:          params.limit
		sort_direction: params.sort_direction or { api.SortDirection.desc }
		items_view:     params.items_view or { api.TurnItemsView.summary }
	})
}

fn (processor &ThreadRequestProcessor) thread_search_occurrences_response_inner(
	params api.ThreadSearchOccurrencesParams
) !api.ThreadSearchOccurrencesResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	if trim_rust_whitespace(&params.search_term).len == 0 {
		return fail(invalid_request('thread/searchOccurrences requires a non-empty searchTerm'))
	}
	page_size := clamp_page_size(params.limit, thread_search_occurrences_default_limit, thread_search_occurrences_max_limit)
	page_result := processor.thread_store.search_thread_occurrences(store.StoreSearchThreadOccurrencesParams{
		thread_id:   thread_id
		search_term: params.search_term
		cursor:      params.cursor
		page_size:   page_size
	})
	if page_result.is_error {
		error_value := clone_thread_store_error(&page_result.error_value)
		return fail(match error_value.kind {
			.invalid_request { invalid_request(error_value.message) }
			.unsupported { unsupported_thread_store_operation(&error_value.operation) }
			.thread_not_found {
				invalid_request('no rollout found for thread id ${error_value.thread_id.value}')
			}
			.conflict, .internal {
				internal_error('failed to search thread occurrences: ${error_value.message}')
			}
		})
	}
	page := page_result.value
	mut data := []api.ThreadSearchOccurrence{cap: page.items.len}
	for item in page.items {
		data << api.ThreadSearchOccurrence{
			turn_id:             item.turn_id
			item_id:             item.item_id
			snippet:             item.snippet
			snippet_match_range: api.ThreadSearchTextRange{
				start: item.snippet_match_range.start
				end:   item.snippet_match_range.end
			}
			turn_cursor:         item.turn_cursor
		}
	}
	return api.ThreadSearchOccurrencesResponse{ data: data, next_cursor: page.next_cursor }
}

fn (processor &ThreadRequestProcessor) paginated_thread_turns_list_response(
	thread_id codex_protocol.ThreadId,
	cursor ?string,
	limit ?u32,
	sort_direction ?api.SortDirection,
	items_view ?api.TurnItemsView
) !api.ThreadTurnsListResponse {
	requested_items_view := items_view or { api.TurnItemsView.summary }
	page_size := thread_turns_page_size(limit)
	store_direction := if sort_direction or { api.SortDirection.desc } == .asc {
		store.SortDirection.asc
	} else {
		store.SortDirection.desc
	}
	// `Full` is only a temporary compatibility path. Keep it out of ThreadStore's API:
	// load turn shells here, then hydrate their items below.
	stored_items_view := match requested_items_view {
		.not_loaded { store.StoredTurnItemsView.not_loaded }
		.summary { store.StoredTurnItemsView.summary }
		.full { store.StoredTurnItemsView.not_loaded }
	}
	page_result := processor.thread_store.list_turns(store.ListTurnsParams{
		thread_id:        copy_thread_id(&thread_id)
		include_archived: true
		cursor:           cursor
		page_size:        page_size
		sort_direction:   store_direction
		items_view:       stored_items_view
	})
	if page_result.is_error {
		return fail(paginated_history_list_error(clone_thread_store_error(&page_result.error_value)))
	}
	page := page_result.value
	mut turns := []api.Turn{cap: page.turns.len}
	for stored_turn in page.turns {
		mut turn := stored_turn_to_api_turn(stored_turn, requested_items_view)!
		if requested_items_view == .full {
			turn.items = processor.paginated_turn_full_items(copy_thread_id(&thread_id), &turn.id)!
		}
		turns << turn
	}
	mut has_live_running_thread := false
	if loaded := processor.thread_manager.get_thread(&thread_id) {
		has_live_running_thread = loaded.agent_status() == .running
	}
	normalize_thread_turns_status(mut turns, processor.thread_watch_manager.loaded_status_for_thread(&thread_id.value), has_live_running_thread)
	return api.ThreadTurnsListResponse{
		data:             turns
		next_cursor:      page.next_cursor
		backwards_cursor: page.backwards_cursor
	}
}

// Older clients still request `itemsView: "full"` from turn pages. Keep this
// app-server-only hydration path until those clients use `thread/items/list`.
fn (processor &ThreadRequestProcessor) paginated_turn_full_items(
	thread_id codex_protocol.ThreadId,
	turn_id &string
) ![]api.ThreadItem {
	mut cursor := ?string(none)
	mut items := []api.ThreadItem{}
	for {
		page_result := processor.thread_store.list_items(store.ListItemsParams{
			thread_id:                copy_thread_id(&thread_id)
			turn_id:                  turn_id.clone()
			include_archived:         true
			cursor:                   clone_optional_string(cursor)
			page_size:                thread_items_max_limit
			sort_direction:           .asc
			sort_key:                 .created_at_ordinal
			after_updated_at_ordinal: none
		})
		if page_result.is_error {
			return fail(paginated_history_list_error(clone_thread_store_error(&page_result.error_value)))
		}
		page := page_result.value
		for stored_item in page.items {
			items << deserialize_stored_thread_item(stored_item)!
		}
		next_cursor := page.next_cursor or { return items }
		if previous := cursor {
			if previous == next_cursor {
				return fail(internal_error('failed to load full turn items for ${*turn_id}: thread store returned a repeated cursor'))
			}
		}
		cursor = next_cursor
	}
	return items
}

// Older clients expect full `thread.turns` from resume and `thread/read(includeTurns=true)`.
// Keep this slow compatibility path until all clients page history directly.
fn (processor &ThreadRequestProcessor) paginated_thread_full_turns(
	thread_id codex_protocol.ThreadId
) ![]api.Turn {
	mut cursor := ?string(none)
	mut turns := []api.Turn{}
	for {
		page := processor.paginated_thread_turns_list_response(copy_thread_id(&thread_id), clone_optional_string(cursor), u32(thread_turns_max_limit), .asc, .full)!
		turns << page.data
		next_cursor := page.next_cursor or { return turns }
		if previous := cursor {
			if previous == next_cursor {
				return fail(internal_error('failed to load full thread turns for ${thread_id.value}: thread store returned a repeated cursor'))
			}
		}
		cursor = next_cursor
	}
	return turns
}

fn (processor &ThreadRequestProcessor) paginated_resume_initial_turns_page(
	thread_id codex_protocol.ThreadId,
	params &api.ThreadResumeInitialTurnsPageParams
) !api.TurnsPage {
	response := processor.paginated_thread_turns_list_response(thread_id, none, params.limit, params.sort_direction, params.items_view)!
	return api.TurnsPage{
		data:             response.data
		next_cursor:      response.next_cursor
		backwards_cursor: response.backwards_cursor
	}
}

fn (processor &ThreadRequestProcessor) paginated_resume_initial_turns_page_with_active_slot(
	thread_id codex_protocol.ThreadId,
	params &api.ThreadResumeInitialTurnsPageParams
) !api.TurnsPage {

	// A running resume overlays the newest live turn on this durable page.
	// Reserve one row so the overlay keeps the requested limit and the
	// durable next cursor still starts after the last returned stored turn.
	page_size := thread_turns_page_size(params.limit)
	if page_size == 1 {
		// ThreadStore does not accept an empty page. Use its backwards cursor as
		// the next cursor so the omitted durable row is returned next.
		page := processor.paginated_resume_initial_turns_page(thread_id, params)!
		return api.TurnsPage{
			data:             []api.Turn{}
			next_cursor:      page.backwards_cursor
			backwards_cursor: page.backwards_cursor
		}
	}
	adjusted := api.ThreadResumeInitialTurnsPageParams{
		limit:          u32(page_size - 1)
		sort_direction: params.sort_direction
		items_view:     params.items_view
	}
	return processor.paginated_resume_initial_turns_page(thread_id, &adjusted)
}

pub fn paginated_resume_backwards_cursors(
	thread_store &store.ThreadStore,
	thread_id codex_protocol.ThreadId
) !OptionalCursorPair {
	turns_result := thread_store.list_turns(store.ListTurnsParams{
		thread_id:        copy_thread_id(&thread_id)
		include_archived: true
		page_size:        1
		sort_direction:   .desc
		items_view:       .not_loaded
	})
	if turns_result.is_error {
		return fail(paginated_history_list_error(clone_thread_store_error(&turns_result.error_value)))
	}
	turns_page := turns_result.value
	items_result := thread_store.list_items(store.ListItemsParams{
		thread_id:                thread_id
		include_archived:         true
		page_size:                1
		sort_direction:           .desc
		sort_key:                 .created_at_ordinal
		after_updated_at_ordinal: none
	})
	if items_result.is_error {
		return fail(paginated_history_list_error(clone_thread_store_error(&items_result.error_value)))
	}
	items_page := items_result.value
	return OptionalCursorPair{
		turns: turns_page.backwards_cursor
		items: items_page.backwards_cursor
	}
}

fn (processor &ThreadRequestProcessor) thread_items_list_response_inner(
	params api.ThreadItemsListParams
) !api.ThreadItemsListResponse {
	thread_id := codex_protocol.thread_id_from_string(&params.thread_id) or {
		return fail(invalid_request('invalid thread id: ${err}'))
	}
	page_size := clamp_page_size(params.limit, thread_items_default_limit, thread_items_max_limit)
	store_direction := if params.sort_direction or { api.SortDirection.asc } == .asc {
		store.SortDirection.asc
	} else {
		store.SortDirection.desc
	}
	page_result := processor.thread_store.list_items(store.ListItemsParams{
		thread_id:                thread_id
		turn_id:                  params.turn_id
		include_archived:         true
		cursor:                   params.cursor
		page_size:                page_size
		sort_direction:           store_direction
		sort_key:                 .created_at_ordinal
		after_updated_at_ordinal: none
	})
	if page_result.is_error {
		error_value := clone_thread_store_error(&page_result.error_value)
		return fail(match error_value.kind {
			.invalid_request { invalid_request(error_value.message) }
			.unsupported { method_not_found('thread/items/list is not supported yet') }
			.thread_not_found {
				invalid_request('no rollout found for thread id ${error_value.thread_id.str()}')
			}
			.conflict, .internal {
				internal_error('failed to list thread items: ${error_value.message}')
			}
		})
	}
	page := page_result.value
	mut data := []api.ThreadItemEntry{cap: page.items.len}
	for stored_item in page.items {
		turn_id := stored_item.turn_id.clone()
		data << api.ThreadItemEntry{
			turn_id: turn_id
			item:    deserialize_stored_thread_item(stored_item)!
		}
	}
	return api.ThreadItemsListResponse{
		data:             data
		next_cursor:      page.next_cursor
		backwards_cursor: page.backwards_cursor
	}
}

fn (processor &ThreadRequestProcessor) load_thread_turns_list_history(
	thread_id codex_protocol.ThreadId
) ![]store.RolloutItem {
	stored_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        copy_thread_id(&thread_id)
		include_archived: true
		include_history:  true
	})
	if stored_result.kind == .ok {
		history := stored_result.value.history or {
			return fail(internal_error('thread store did not return history for thread ${thread_id.value}'))
		}
		return history.items
	}
	error_value := clone_thread_store_error(&stored_result.error_value)
	if !is_exact_thread_store_miss(&thread_id, &error_value) {
		view_error := match error_value.kind {
			.invalid_request {
				ThreadReadViewError{
					kind:    .invalid_request
					message: error_value.message
				}
			}
			.unsupported {
				ThreadReadViewError{
					kind:      .unsupported
					operation: error_value.operation
				}
			}
			.thread_not_found, .conflict, .internal {
				ThreadReadViewError{
					kind:    .internal
					message: 'failed to read thread: ${error_value.message}'
				}
			}
		}
		return fail(thread_read_view_error(view_error))
	}
	return processor.load_live_thread_turns_list_history(thread_id)
}

// V spells the Rust store-miss arm as a helper because `or` blocks cannot continue the outer
// expression while retaining the owned thread id.
fn (processor &ThreadRequestProcessor) load_live_thread_turns_list_history(
	thread_id codex_protocol.ThreadId
) ![]store.RolloutItem {
	loaded := processor.thread_manager.get_thread(&thread_id) or {
		return fail(invalid_request('thread not loaded: ${thread_id.value}'))
	}
	config_snapshot := loaded.config_snapshot()
	if config_snapshot.ephemeral {
		return fail(invalid_request('ephemeral threads do not support thread/turns/list'))
	}
	history_result := loaded.load_history(true)
	if history_result.is_error {
		return fail(thread_read_view_error(thread_turns_list_history_load_error(copy_thread_id(&thread_id),
			clone_thread_store_error(&history_result.error_value))))
	}
	return history_result.value.items
}

pub fn (processor &ThreadRequestProcessor) thread_created_receiver() ThreadCreatedReceiver {
	return processor.thread_manager.subscribe_thread_created()
}

pub fn (processor &ThreadRequestProcessor) connection_initialized(
	connection_id ConnectionId,
	capabilities ConnectionCapabilities
) {
	processor.thread_state_manager.connection_initialized(connection_id, capabilities)
}

pub fn (processor &ThreadRequestProcessor) connection_closed(connection_id ConnectionId) {
	affected_threads := processor.thread_state_manager.remove_connection(connection_id)
	// Reconcile stale app-server bookkeeping when the thread has already been
	// removed from the core manager.
	for thread_id in affected_threads {
		processor.thread_manager.get_thread(&thread_id) or {
			processor.finalize_thread_teardown(thread_id)
		}
	}
}

pub fn (processor &ThreadRequestProcessor) subscribe_running_assistant_turn_count() RunningTurnCountReceiver {
	return processor.thread_watch_manager.subscribe_running_turn_count()
}

/// Best-effort: ensure initialized connections are subscribed to this thread.
pub fn (processor &ThreadRequestProcessor) try_attach_thread_listener(
	thread_id codex_protocol.ThreadId,
	connection_ids []ConnectionId
) {

	// Rust ThreadId is Copy; V's string-backed translation reconstructs each owned call argument.
	thread_id_value := thread_id.value.clone()
	mut raw_events_enabled := false
	loaded_thread_id := codex_protocol.ThreadId{ value: thread_id_value.clone() }
	if thread_value := processor.thread_manager.get_thread(&loaded_thread_id) {
		processor.thread_watch_manager.upsert_thread(&thread_id_value)
		config_snapshot := thread_value.config_snapshot()
		if parent_thread_id := config_snapshot.parent_thread_id {
			raw_events_enabled = processor.thread_state_manager.raw_events_enabled(&parent_thread_id)
		}
	}
	for connection_id in connection_ids {
		thread_kind := 'thread'
		attach_thread_id := codex_protocol.ThreadId{ value: thread_id_value.clone() }
		result := processor.ensure_conversation_listener(attach_thread_id, connection_id, raw_events_enabled) or {
			thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
				kind:          .error
				error_message: err.msg()
			}, codex_protocol.ThreadId{ value: thread_id_value.clone() }, connection_id, &thread_kind)
			continue
		}
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:  .ok
			value: result
		}, codex_protocol.ThreadId{ value: thread_id_value.clone() }, connection_id, &thread_kind)
	}
}

fn (processor &ThreadRequestProcessor) thread_resume_inner(
	request_id ConnectionRequestId,
	params &api.ThreadResumeParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions,
	mut prepared_config OptionalPreparedResumeConfig
) !ResumeControlFlow {
	if processor.pending_thread_unloads.contains(&params.thread_id) {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), invalid_request('thread ${params.thread_id} is closing; retry thread/resume after the thread is closed'))
		return .stop
	}
	if params.sandbox != none && params.permissions != none {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), invalid_request('`permissions` cannot be combined with `sandbox`'))
		return .stop
	}
	redact_resume_payloads := should_redact_thread_resume_payloads(app_server_client_name)
	probe_permit := processor.acquire_thread_list_state_permit() or {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
		return .stop
	}
	mut probe_permit_held := true
	defer {
		if probe_permit_held {
			probe_permit.release()
		}
	}
	running_result := processor.resume_running_thread(&request_id, params, clone_optional_string(app_server_client_name), clone_optional_string(app_server_client_version), none) or {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
		return .stop
	}
	if running_result.kind == .handled {
		return .stop
	}
	// Attach to the resolved child with only the caller's history-paging preferences.
	// Parent-owned V2 children must resume through their owner, not caller configuration.
	// Copied or referenced history can contain another thread's settings. Only snapshots
	// explicitly owned by this thread can override its startup cwd.
	mut request_overrides := OptionalStringMap{}
	if values := params.config {
		request_overrides = OptionalStringMap{
			has_value: true
			value:     values.clone()
		}
	}
	mut typesafe_overrides := processor.build_thread_config_overrides(params.model, params.model_provider, params.service_tier, params.cwd, params.runtime_workspace_roots, params.approval_policy, params.approvals_reviewer, params.sandbox, params.permissions, params.base_instructions, params.developer_instructions, params.personality)
	mut resume_source_thread := ?store.StoredThread(none)
	mut paginated_resume := false
	mut history := InitialHistory{}
	if items := params.history {
		history = processor.resume_thread_from_history(&items) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
	} else if stored_thread := running_result.stored_thread {
		loaded, source := processor.load_resume_initial_history_from_stored_thread(stored_thread) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
		paginated_resume = source.history_mode == .paginated
		resume_source_thread = source
		history = loaded
	} else {
		stored := processor.read_stored_thread_for_resume(&params.thread_id, params.path, false) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
		loaded, source := processor.load_resume_initial_history_from_stored_thread(stored) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
		paginated_resume = source.history_mode == .paginated
		resume_source_thread = source
		history = loaded
	}
	if history.kind == .resumed
		&& processor.pending_thread_unloads.contains(&history.conversation_id.value) {
		return fail(invalid_request('thread ${history.conversation_id.value} is closing; retry thread/resume after the thread is closed'))
	}
	if paginated_resume && !params.exclude_turns && !prepared_config.has_value {
		processor.send_deprecation_notice(request_id.connection_id, &paginated_full_history_deprecation_summary)
	}
	resumed_sources := history.get_resumed_session_sources()
	if history.kind == .resumed && resumed_sources.has_value
		&& !can_accept_direct_input(history.get_multi_agent_version(), &resumed_sources.session_source) {
		child_thread_id := copy_thread_id(&history.conversation_id)
		processor.thread_manager.ensure_multi_agent_v2_child_loaded(copy_thread_id(&child_thread_id)) or {
			message := 'failed to resume a multi-agent v2 child through its parent: ${err}'
			processor.outgoing.log_warning(&message)
			return fail(invalid_request('cannot resume an unloaded multi-agent v2 sub-agent through its parent; resume the parent first, or use thread/read to inspect it'))
		}
		cold_resume_history := if paginated_resume {
			?[]store.RolloutItem(history.get_rollout_items())
		} else {
			?[]store.RolloutItem(none)
		}
		attach_params := api.ThreadResumeParams{
			thread_id:          child_thread_id.value.clone()
			exclude_turns:      params.exclude_turns
			initial_turns_page: params.initial_turns_page
		}
		attach_result := processor.resume_running_thread(&request_id, &attach_params, app_server_client_name, app_server_client_version, cold_resume_history)!
		if attach_result.kind == .handled {
			return .stop
		}
		return fail(invalid_request('cannot resume an unloaded multi-agent v2 sub-agent through its parent; resume the parent first, or use thread/read to inspect it'))
	}
	if typesafe_overrides.approval_policy == none && request_overrides.has_value
		&& 'approval_policy' in request_overrides.value {
		approval_policy_value := request_overrides.value['approval_policy']
		request_overrides.value.delete('approval_policy')
		typesafe_overrides.approval_policy = parse_approval_policy_override(&approval_policy_value) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), invalid_params('invalid `approval_policy` config override: ${err}'))
			return .stop
		}
	}
	has_explicit_model_resume_override := has_model_resume_override(&request_overrides, &typesafe_overrides)
	persisted_metadata := processor.load_and_apply_persisted_resume_metadata(&history, mut request_overrides, mut typesafe_overrides)
	mut clear_reasoning_effort := false
	mut persisted_metadata_for_state := ?ThreadMetadata(none)
	if metadata := persisted_metadata {
		clear_reasoning_effort = !has_explicit_model_resume_override
			&& metadata.reasoning_effort == none
		persisted_metadata_for_state = clone_thread_metadata(&metadata)
	}
	// Rust clones this owned path into ResumeConfigState and then borrows the original for loading.
	// V's optional owner cannot be safely borrowed, so derive the same pure value twice and give
	// each consumer its own owner.
	history_cwd_for_state := resume_history_cwd(&history)
	history_cwd_for_load := resume_history_cwd(&history)
	persisted_settings_result := persisted_resume_settings.latest_persisted_resume_settings(&history.items)
	persisted_settings := if persisted_settings_result.has_value {
		?PersistedResumeSettings(persisted_settings_result.value)
	} else {
		?PersistedResumeSettings(none)
	}
	config_state := ResumeConfigState{
		history_cwd:        history_cwd_for_state
		persisted_metadata: persisted_metadata_for_state
		persisted_settings: persisted_settings
	}
	if prepared_config.has_value && prepared_config.value.state != config_state {
		prepared_config.has_value = false
	}
	if !prepared_config.has_value {
		// Config loading can call back into Desktop; release the permit during host work.
		probe_permit_held = false
		probe_permit.release()
		mut owned_overrides := ?map[string]string(none)
		if request_overrides.has_value {
			owned_overrides = request_overrides.value.clone()
		}
		loaded_config := processor.config_manager.load_for_cwd(owned_overrides, typesafe_overrides, history_cwd_for_load) or {
			message := err.msg()
			processor.outgoing.send_error(clone_connection_request_id(&request_id), config_load_error(&message))
			return .stop
		}
		prepared_config.has_value = true
		prepared_config.value = PreparedResumeConfig{
			state:  config_state
			config: loaded_config
		}
		return .continue_loop
	}
	mut resume_config := clone_config(&prepared_config.value.config)
	if clear_reasoning_effort {
		resume_config.model_reasoning_effort = none
	}
	// Recheck the thread and history after a possible archive, delete, or aliased resume.
	// Paginated JSONL is canonical, but its SQLite projection can lag after a
	// previous write failure. Persist after reopening the live writer so legacy
	// response hydration reads the latest durable turns and items.
	response_history := clone_initial_history(&history)
	resume_result := processor.thread_manager.resume_thread_with_history(resume_config, history, codex_login.clone_auth_manager(&processor.auth_manager), processor.request_trace_context(&request_id), client_mcp_extensions)
	if resume_result.is_error {
		resume_error := clone_codex_error(&resume_result.error_value)
		mapped_error := if resume_error.kind == .invalid_request {
			invalid_request(resume_error.message)
		} else {
			internal_error('error resuming thread: ${resume_error.message}')
		}
		processor.outgoing.send_error(clone_connection_request_id(&request_id), mapped_error)
		return .stop
	}
	new_thread := resume_result.value
	set_app_server_client_info(&new_thread.thread, app_server_client_name, app_server_client_version) or {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
		return .stop
	}
	rollout_path := new_thread.session_configured.rollout_path or {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), internal_error('rollout path missing for thread ${new_thread.thread_id.value}'))
		return .stop
	}
	instruction_sources := new_thread.thread.legacy_instruction_sources()
	config_snapshot := new_thread.thread.config_snapshot()
	if paginated_resume {
		persist_result := processor.thread_store.persist_thread(copy_thread_id(&new_thread.thread_id), .standard)
		if persist_result.is_error {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), thread_store_resume_read_error(clone_thread_store_error(&persist_result.error_value)))
			return .stop
		}
	}
	mut materialized_turns := []api.Turn{}
	mut has_materialized_turns := false
	if paginated_resume && !params.exclude_turns {
		materialized_turns = processor.paginated_thread_full_turns(copy_thread_id(&new_thread.thread_id)) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
		has_materialized_turns = true
	}
	thread_kind := 'thread'
	mut listener_attach_succeeded := true
	listener_result := processor.ensure_conversation_listener(copy_thread_id(&new_thread.thread_id), request_id.connection_id, false) or {
		listener_attach_succeeded = false
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:          .error
			error_message: err.msg()
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
		EnsureConversationListenerResult.connection_closed
	}
	if listener_attach_succeeded {
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:  .ok
			value: listener_result
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
	}
	mut api_thread := processor.load_thread_from_resume_source_or_send_internal(copy_thread_id(&new_thread.thread_id), &new_thread.thread, &response_history, &rollout_path, resume_source_thread, !params.exclude_turns && !paginated_resume) or {
		processor.outgoing.send_error(clone_connection_request_id(&request_id), internal_error(err.msg()))
		return .stop
	}
	api_thread.thread_source = clone_optional_thread_source(config_snapshot.thread_source)
	if has_materialized_turns {
		api_thread.turns = materialized_turns
	}
	processor.thread_watch_manager.upsert_thread(&api_thread.id)
	loaded_status := processor.thread_watch_manager.loaded_status_for_thread(&api_thread.id)
	set_thread_status_and_interrupt_stale_turns(mut api_thread, loaded_status, false)
	cursors := if paginated_resume {
		paginated_resume_backwards_cursors(&processor.thread_store, copy_thread_id(&new_thread.thread_id)) or {
			processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
			return .stop
		}
	} else {
		OptionalCursorPair{}
	}
	mut initial_turns_page := ?api.TurnsPage(none)
	if page_params := params.initial_turns_page {
		if paginated_resume {
			initial_turns_page = processor.paginated_resume_initial_turns_page(copy_thread_id(&new_thread.thread_id), &page_params) or {
				processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
				return .stop
			}
		} else {
			response_items := response_history.get_rollout_items()
			initial_turns_page = build_thread_resume_initial_turns_page(&response_items, api_thread.status, false, none, &page_params) or {
				processor.outgoing.send_error(clone_connection_request_id(&request_id), json_rpc_error_from_ierror(err))
				return .stop
			}
		}
	}
	mut restored_usage_turn_id := ''
	if !params.exclude_turns || paginated_resume {
		mut usage_turns := api_thread.turns.clone()
		if usage_turns.len == 0 {
			if page := initial_turns_page {
				usage_turns = page.data.clone()
				initial_turns_page = clone_turns_page(&page)
			}
		}
		response_items_for_usage := response_history.get_rollout_items()
		restored_usage_turn_id = restored_token_usage_turn_id(&response_items_for_usage, &usage_turns)
	}
	if redact_resume_payloads {
		redact_thread_resume_payloads(mut api_thread.turns)
		if page := initial_turns_page {
			mut redacted_data := page.data.clone()
			redact_thread_resume_payloads(mut redacted_data)
			initial_turns_page = api.TurnsPage{
				data:             redacted_data
				next_cursor:      page.next_cursor
				backwards_cursor: page.backwards_cursor
			}
		}
	}
	thread_originator := config_snapshot.originator.clone()
	response := api.ThreadResumeResponse{
		thread:                    api_thread
		model:                     new_thread.session_configured.model.clone()
		model_provider:            new_thread.session_configured.model_provider_id.clone()
		service_tier:              clone_optional_string(new_thread.session_configured.service_tier)
		cwd:                       new_thread.session_configured.cwd.clone()
		runtime_workspace_roots:   config_snapshot.workspace_roots.clone()
		instruction_sources:       instruction_sources
		approval_policy:           new_thread.session_configured.approval_policy
		approvals_reviewer:        new_thread.session_configured.approvals_reviewer
		sandbox:                   config_snapshot.sandbox_policy()
		active_permission_profile: thread_response_active_permission_profile(config_snapshot.active_permission_profile)
		reasoning_effort:          new_thread.session_configured.reasoning_effort
		multi_agent_mode:          .explicit_request_only
		initial_turns_page:        initial_turns_page
		turns_backwards_cursor:    cursors.turns
		items_backwards_cursor:    cursors.items
	}
	processor.outgoing.send_response_with_thread_originator(clone_connection_request_id(&request_id), api.ClientResponsePayload(response), thread_originator)
	// Auto-attach a thread listener when resuming a thread.
	// `excludeTurns` is explicitly the cheap resume path, so avoid
	// rebuilding history only to attribute a replayed usage update.
	// The client needs restored usage before it starts another turn.
	// Sending after the response preserves JSON-RPC request ordering while
	// still filling the status line before the next turn lifecycle begins.
	if restored_usage_turn_id.len > 0 {
		send_thread_token_usage_update_to_connection(&processor.outgoing, request_id.connection_id, copy_thread_id(&new_thread.thread_id), &new_thread.thread, restored_usage_turn_id)
	}
	processor.thread_goal_processor.emit_resume_goal_snapshot(copy_thread_id(&new_thread.thread_id))
	new_thread.thread.emit_thread_idle_lifecycle_if_idle(.completed)
	return .stop
}

fn (processor &ThreadRequestProcessor) load_and_apply_persisted_resume_metadata(
	thread_history &InitialHistory,
	mut request_overrides OptionalStringMap,
	mut typesafe_overrides ConfigOverrides
) ?ThreadMetadata {
	if thread_history.kind != .resumed {
		return none
	}
	persisted := persisted_resume_settings.latest_persisted_resume_settings(&thread_history.items)
	if persisted.has_value {
		if typesafe_overrides.approval_policy == none {
			typesafe_overrides.approval_policy = persisted.value.approval_policy
		}
		if typesafe_overrides.approvals_reviewer == none
			&& (!request_overrides.has_value || 'approvals_reviewer' !in request_overrides.value) {
			typesafe_overrides.approvals_reviewer = persisted.value.approvals_reviewer
		}
		if !has_permission_override(&request_overrides, &typesafe_overrides) {
			if profile := persisted.value.active_permission_profile {
				typesafe_overrides.persisted_permission_profile_id = profile.id.clone()
			}
		}
	}
	state_db := processor.state_db or { return none }
	metadata_result := state_db.get_thread(copy_thread_id(&thread_history.conversation_id)) or {
		return none
	}
	if !metadata_result.has_value {
		return none
	}
	metadata := metadata_result.value
	merge_persisted_resume_metadata(mut request_overrides, mut typesafe_overrides, &metadata)
	return metadata
}

fn (processor &ThreadRequestProcessor) resume_running_thread(
	request_id &ConnectionRequestId,
	params &api.ThreadResumeParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	cold_resume_history ?[]store.RolloutItem
) !RunningThreadResumeResult {
	redact_resume_payloads := should_redact_thread_resume_payloads(app_server_client_name)
	if params.history != none {
		if parsed_id := codex_protocol.thread_id_from_string(&params.thread_id) {
			processor.thread_manager.get_thread(&parsed_id) or {
				return RunningThreadResumeResult{ kind: .not_running }
			}
			if parsed_id.value.len > 0 {
				return fail(invalid_request('cannot resume thread ${params.thread_id} with history while it is already running'))
			}
		}
		return RunningThreadResumeResult{ kind: .not_running }
	}
	mut source_thread := store.StoredThread{}
	mut has_loaded_thread := false
	mut existing_thread := CodexThread{}
	if parsed_id := codex_protocol.thread_id_from_string(&params.thread_id) {
		if directly_loaded := processor.thread_manager.get_thread(&parsed_id) {
			source_thread = processor.read_stored_thread_for_resume(&params.thread_id, none, false)!
			has_loaded_thread = true
			existing_thread = clone_codex_thread(&directly_loaded)
		} else {
			source_thread = processor.read_stored_thread_for_resume(&params.thread_id, params.path, false)!
			resolved_thread_id := copy_thread_id(&source_thread.thread_id)
			if resolved_thread := processor.thread_manager.get_thread(&resolved_thread_id) {
				has_loaded_thread = true
				existing_thread = clone_codex_thread(&resolved_thread)
			}
		}
	} else {
		source_thread = processor.read_stored_thread_for_resume(&params.thread_id, params.path, false)!
		resolved_thread_id := copy_thread_id(&source_thread.thread_id)
		if resolved_thread := processor.thread_manager.get_thread(&resolved_thread_id) {
			has_loaded_thread = true
			existing_thread = clone_codex_thread(&resolved_thread)
		}
	}
	if !has_loaded_thread {
		return RunningThreadResumeResult{
			kind:          .not_running
			stored_thread: source_thread
		}
	}
	if requested_path := params.path {
		active_path := existing_thread.rollout_path() or { source_thread.rollout_path or { '' } }
		requested_plain_path := codex_rollout.plain_rollout_path(&requested_path)
		active_plain_path := codex_rollout.plain_rollout_path(&active_path)
		if active_path.len > 0
			&& !path_utils.paths_match_after_normalization(&requested_plain_path, &active_plain_path) {
			return fail(invalid_request('cannot resume running thread ${existing_thread.id.value} with stale path: requested `${requested_path}`, active `${active_path}`'))
		}
	}
	config_snapshot := existing_thread.config_snapshot()
	mismatches := collect_resume_override_mismatches(params, &config_snapshot)
	if mismatches.len > 0 {
		subscribers := processor.thread_state_manager.subscribed_connection_ids(&existing_thread.id)
		loaded_status := processor.thread_watch_manager.loaded_status_for_thread(&existing_thread.id.value)
		// Parent-owned V2 children must not be rebuilt from public resume overrides.
		if can_accept_direct_input(existing_thread.multi_agent_version(), &config_snapshot.session_source) && subscribers.len == 0
			&& loaded_status.kind == .idle && existing_thread.agent_status() != .running {
			// A loaded idle thread is only a cache entry. Shut it down
			// before removing it so cold resume cannot duplicate a
			// thread that timed out during shutdown.
			match wait_for_thread_shutdown(&existing_thread) {
				.complete {
					_ = processor.thread_manager.remove_thread(&existing_thread.id)
					processor.finalize_thread_teardown(copy_thread_id(&existing_thread.id))
					// Shutdown can flush newer rollout items, so reload the
					// stored thread before starting the replacement session.
					return RunningThreadResumeResult{ kind: .not_running }
				}
				.submit_failed {
					message := 'failed to submit Shutdown to thread ${existing_thread.id.value}'
					processor.outgoing.log_warning(&message)
				}
				.timed_out {
					message := 'thread ${existing_thread.id.value} shutdown timed out'
					processor.outgoing.log_warning(&message)
				}
				else {}
			}
		}
		// Preserve rejoin semantics when another client can still observe
		// the loaded thread or shutdown did not complete.
		message := 'thread/resume overrides ignored for loaded thread ${existing_thread.id.value}: ${mismatches.join('; ')}'
		processor.outgoing.log_warning(&message)
	}
	paginated_resume := source_thread.history_mode == .paginated
	include_turns := !params.exclude_turns
	if paginated_resume && include_turns {
		processor.send_deprecation_notice(request_id.connection_id, &paginated_full_history_deprecation_summary)
	}
	needs_history := !paginated_resume && (include_turns || params.initial_turns_page != none)
	if needs_history {
		source_thread = processor.read_stored_thread_for_resume(&source_thread.thread_id.value, source_thread.rollout_path, true)!
	}
	if paginated_resume && (include_turns || params.initial_turns_page != none) {
		persist_result := processor.thread_store.persist_thread(copy_thread_id(&existing_thread.id), .standard)
		if persist_result.is_error {
			return fail(thread_store_resume_read_error(clone_thread_store_error(&persist_result.error_value)))
		}
	}
	history_items := if needs_history {
		history := source_thread.history or {
			return fail(internal_error('thread ${existing_thread.id.value} did not include persisted history'))
		}
		history.items.clone()
	} else {
		[]store.RolloutItem{}
	}
	thread_state := processor.thread_state_manager.thread_state(&existing_thread.id)
	processor.ensure_listener_task_running(copy_thread_id(&existing_thread.id), clone_codex_thread(&existing_thread), &thread_state)!
	set_app_server_client_info(&existing_thread, app_server_client_name, app_server_client_version)!
	mut thread_summary := processor.stored_thread_to_api_thread(source_thread, &config_snapshot.model_provider_id, false)
	session_configured := existing_thread.session_configured()
	thread_summary.session_id = session_configured.session_id
	thread_summary.thread_source = clone_optional_thread_source(config_snapshot.thread_source)
	apply_live_thread_settings(mut thread_summary, &config_snapshot)
	thread_summary.can_accept_direct_input = can_accept_direct_input(existing_thread.multi_agent_version(), &config_snapshot.session_source)
	instruction_sources := existing_thread.legacy_instruction_sources()
	listener_command_tx := thread_state.listener_command_tx() or {
		return fail(internal_error('failed to enqueue running thread resume for thread ${existing_thread.id.value}: thread listener is not running'))
	}
	goal_state := processor.thread_goal_processor.pending_resume_goal_state(&existing_thread)
	mut paginated_turns := ?[]api.Turn(none)
	if paginated_resume && include_turns {
		paginated_turns = processor.paginated_thread_full_turns(copy_thread_id(&existing_thread.id))!
	}
	mut paginated_initial_turns_page := ?api.TurnsPage(none)
	if paginated_resume {
		if initial_page := params.initial_turns_page {
			paginated_initial_turns_page = processor.paginated_resume_initial_turns_page(copy_thread_id(&existing_thread.id), &initial_page)!
		}
	}
	mut cold_resume_token_usage_turn_id := ?string(none)
	if history := cold_resume_history {
		mut usage_turns := []api.Turn{}
		if turns := paginated_turns {
			if turns.len > 0 {
				usage_turns = turns.clone()
			}
		}
		if usage_turns.len == 0 {
			if page := paginated_initial_turns_page {
				usage_turns = page.data.clone()
				paginated_initial_turns_page = clone_turns_page(&page)
			}
		}
		turn_id := restored_token_usage_turn_id(&history, &usage_turns)
		if turn_id.len > 0 {
			cold_resume_token_usage_turn_id = turn_id
		}
	}
	mut paginated_initial_turns_page_with_active_slot := ?api.TurnsPage(none)
	if paginated_resume {
		if initial_page := params.initial_turns_page {
			if initial_page.sort_direction or { api.SortDirection.desc } == .desc {
				paginated_initial_turns_page_with_active_slot = processor.paginated_resume_initial_turns_page_with_active_slot(copy_thread_id(&existing_thread.id), &initial_page)!
			}
		}
	}
	resume_cursor_store := if paginated_resume {
		?store.ThreadStore(processor.thread_store)
	} else {
		?store.ThreadStore(none)
	}
	command := app_thread_state.ThreadListenerCommand{
		kind:           .send_thread_resume_response
		resume_request: app_thread_state.PendingThreadResumeRequest{
			request_id:                                    clone_connection_request_id(request_id)
			history_items:                                 history_items
			cold_resume_token_usage_turn_id:               cold_resume_token_usage_turn_id
			config_snapshot:                               config_snapshot
			instruction_sources:                           instruction_sources
			thread_summary:                                thread_summary
			emit_thread_goal_update:                       goal_state.emit_thread_goal_update
			thread_goal_state_db:                          goal_state.thread_goal_state_db
			include_turns:                                 include_turns
			initial_turns_page:                            params.initial_turns_page
			paginated_turns:                               paginated_turns
			paginated_initial_turns_page:                  paginated_initial_turns_page
			paginated_initial_turns_page_with_active_slot: paginated_initial_turns_page_with_active_slot
			resume_cursor_store:                           resume_cursor_store
			redact_resume_payloads:                        redact_resume_payloads
		}
	}
	if !listener_command_tx.send(command) {
		return fail(internal_error('failed to enqueue running thread resume for thread ${existing_thread.id.value}: thread listener command channel is closed'))
	}
	return RunningThreadResumeResult{ kind: .handled }
}

fn (processor &ThreadRequestProcessor) resume_thread_from_history(
	history &[]codex_protocol.ResponseItem
) !InitialHistory {
	_ = processor
	if history.len == 0 {
		return fail(invalid_request('history must not be empty'))
	}
	mut items := []store.RolloutItem{cap: history.len}
	for item in *history {
		items << store.RolloutItem{
			kind:          .response_item
			response_item: clone_response_item(&item)
		}
	}
	return InitialHistory{
		kind:  .forked
		items: items
	}
}

// Rust's iterator uses `cloned()` before converting each protocol response item into a rollout
// item. This explicit constructor is the corresponding V ownership boundary.
fn clone_response_item(item &codex_protocol.ResponseItem) codex_protocol.ResponseItem {
	return codex_protocol.ResponseItem{
		kind:                                       item.kind.clone()
		id:                                         clone_optional_string(item.id)
		author:                                     item.author.clone()
		recipient:                                  item.recipient.clone()
		content:                                    item.content.clone()
		internal_chat_message_metadata_passthrough: item.internal_chat_message_metadata_passthrough
	}
}

fn (processor &ThreadRequestProcessor) load_resume_initial_history_from_stored_thread(
	stored_thread store.StoredThread
) !(InitialHistory, store.StoredThread) {
	if stored_thread.history_mode == .paginated {
		model_context_result := processor.thread_store.load_latest_model_context(store.StoreLoadThreadHistoryParams{
			thread_id:        copy_thread_id(&stored_thread.thread_id)
			include_archived: true
		})
		if model_context_result.is_error {
			return fail(thread_store_resume_read_error(clone_thread_store_error(&model_context_result.error_value)))
		}
		model_context := model_context_result.value
		return InitialHistory{
			kind:            .resumed
			conversation_id: model_context.thread_id
			items:           model_context.items
			rollout_path:    clone_optional_string(stored_thread.rollout_path)
		}, stored_thread
	}
	thread_id := stored_thread.thread_id.value.clone()
	rollout_path := clone_optional_string(stored_thread.rollout_path)
	mut mutable_stored_thread := processor.read_stored_thread_for_resume(&thread_id, rollout_path, true)!
	history := processor.stored_thread_to_initial_history(mut mutable_stored_thread)!
	return history, mutable_stored_thread
}

fn (processor &ThreadRequestProcessor) read_stored_thread_for_resume(
	thread_id &string,
	path ?string,
	include_history bool
) !store.StoredThread {
	stored_thread := if requested_path := path {
		result := processor.thread_store.read_thread_by_rollout_path(store.StoreReadThreadByRolloutPathParams{
			rollout_path:     requested_path
			include_archived: true
			include_history:  include_history
		})
		if result.kind != .ok {
			return fail(thread_store_resume_read_error(clone_thread_store_error(&result.error_value)))
		}
		result.value
	} else {
		existing_thread_id := codex_protocol.thread_id_from_string(thread_id) or {
			return fail(invalid_request('invalid session id: ${err}'))
		}
		result := processor.thread_store.read_thread(store.StoreReadThreadParams{
			thread_id:        existing_thread_id
			include_archived: true
			include_history:  include_history
		})
		if result.kind != .ok {
			return fail(thread_store_resume_read_error(clone_thread_store_error(&result.error_value)))
		}
		result.value
	}
	if requested_path := path {
		if stored_thread.history_mode == .paginated {
			current_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
				thread_id:        copy_thread_id(&stored_thread.thread_id)
				include_archived: true
				include_history:  false
			})
			if current_result.kind != .ok {
				return fail(thread_store_resume_read_error(clone_thread_store_error(&current_result.error_value)))
			}
			if current_path := current_result.value.rollout_path {
				if os.norm_path(requested_path) != os.norm_path(current_path.clone()) {
					return fail(invalid_request('cannot resume paginated thread ${stored_thread.thread_id.value} with stale path: requested ${requested_path}, current ${current_path}; omit path and resume by thread id'))
				}
			}
		}
	}
	if stored_thread.archived_at != none {
		return fail(invalid_request('session ${stored_thread.thread_id.value} is archived. Run `codex unarchive ${stored_thread.thread_id.value}` to unarchive it first.'))
	}
	return stored_thread
}

fn (processor &ThreadRequestProcessor) stored_thread_to_initial_history(
	mut stored_thread store.StoredThread
) !InitialHistory {
	_ = processor
	history := stored_thread.history or {
		return fail(internal_error('thread ${stored_thread.thread_id.str()} did not include persisted history'))
	}
	return InitialHistory{
		kind:            .resumed
		conversation_id: stored_thread.thread_id
		items:           history.items
		rollout_path:    stored_thread.rollout_path
	}
}

fn (processor &ThreadRequestProcessor) stored_thread_to_api_thread(
	stored_thread store.StoredThread,
	fallback_provider &string,
	include_turns bool
) api.Thread {
	mut thread_value, history := thread_from_stored_thread(stored_thread, fallback_provider, &processor.config.cwd)
	if include_turns {
		if stored_history := history {
			thread_lifecycle.populate_thread_turns_from_history(mut thread_value, &stored_history.items, none)
		}
	}
	return thread_value
}

fn (processor &ThreadRequestProcessor) read_stored_thread_for_new_fork(
	thread_id codex_protocol.ThreadId,
	include_history bool
) !store.StoredThread {
	result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        thread_id
		include_archived: true
		include_history:  include_history
	})
	if result.kind != .ok {
		return fail(thread_store_resume_read_error(clone_thread_store_error(&result.error_value)))
	}
	return result.value
}

fn (processor &ThreadRequestProcessor) load_thread_from_resume_source_or_send_internal(
	thread_id codex_protocol.ThreadId,
	thread_value &CodexThread,
	thread_history &InitialHistory,
	rollout_path &string,
	resume_source_thread ?store.StoredThread,
	include_turns bool
) !api.Thread {
	thread_id_value := thread_id.value.clone()
	config_snapshot := thread_value.config_snapshot()
	session_configured := thread_value.session_configured()
	multi_agent_version := thread_value.multi_agent_version()
	mut api_thread := match thread_history.kind {
		.resumed {
			refreshed_source := if source := resume_source_thread {
				if source_path := source.rollout_path {
					read_result := processor.thread_store.read_thread_by_rollout_path(store.StoreReadThreadByRolloutPathParams{
						rollout_path:     source_path
						include_archived: true
						include_history:  false
					})
					if read_result.kind == .ok {
						read_result.value
					} else {
						store.StoredThread{ ...source, history: none }
					}
				} else {
					read_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
						thread_id:        copy_thread_id(&source.thread_id)
						include_archived: true
						include_history:  false
					})
					if read_result.kind == .ok {
						read_result.value
					} else {
						store.StoredThread{ ...source, history: none }
					}
				}
			} else {
				read_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
					thread_id:        copy_thread_id(&thread_history.conversation_id)
					include_archived: true
					include_history:  false
				})
				if read_result.kind != .ok {
					return error('failed to load resume source for thread ${thread_id_value}: ${read_result.error_value.message}')
				}
				read_result.value
			}
			processor.stored_thread_to_api_thread(refreshed_source, &config_snapshot.model_provider_id, false)
		}
		.forked {
			mut fork_thread := build_thread_from_snapshot(copy_thread_id(&thread_id), session_configured.session_id.clone(), multi_agent_version, &config_snapshot, rollout_path.clone())
			fork_thread.preview = preview_from_rollout_items(&thread_history.items)
			fork_thread
		}
		.new_history, .cleared {
			return fail(internal_error('thread ${thread_id_value} has invalid resume history'))
		}
	}
	api_thread.id = thread_id_value
	api_thread.session_id = session_configured.session_id
	api_thread.path = rollout_path.clone()
	apply_live_thread_settings(mut api_thread, &config_snapshot)
	api_thread.can_accept_direct_input = can_accept_direct_input(thread_value.multi_agent_version(), &config_snapshot.session_source)
	if include_turns {
		history_items := thread_history.get_rollout_items()
		thread_lifecycle.populate_thread_turns_from_history(mut api_thread, &history_items, none)
	}
	processor.attach_thread_name(copy_thread_id(&thread_id), mut api_thread)
	return api_thread
}

fn (processor &ThreadRequestProcessor) attach_thread_name(
	thread_id codex_protocol.ThreadId,
	mut thread_value api.Thread
) {
	stored_result := processor.thread_store.read_thread(store.StoreReadThreadParams{
		thread_id:        thread_id
		include_archived: true
		include_history:  false
	})
	if stored_result.kind == .ok {
		if name := stored_result.value.name {
			if normalized := normalize_thread_name(&name) {
				if stored_result.value.history_mode == .paginated {
					thread_value.name = normalized
				} else {
					set_thread_name_from_title(mut thread_value, normalized)
				}
			}
		}
	}
}

fn (processor &ThreadRequestProcessor) thread_fork_inner(
	request_id ConnectionRequestId,
	params api.ThreadForkParams,
	app_server_client_name ?string,
	app_server_client_version ?string,
	client_mcp_extensions ClientMcpExtensions
) ! {
	if params.sandbox != none && params.permissions != none {
		return fail(invalid_request('`permissions` cannot be combined with `sandbox`'))
	}
	if params.last_turn_id != none && params.before_turn_id != none {
		return fail(invalid_request('`beforeTurnId` cannot be combined with `lastTurnId`'))
	}
	if params.ephemeral && params.defer_goal_continuation {
		return fail(invalid_request('`deferGoalContinuation` cannot be combined with `ephemeral`'))
	}
	mut source_thread := processor.read_stored_thread_for_resume(&params.thread_id, params.path, false)!
	paginated_source := source_thread.history_mode == .paginated
	include_turns := !params.exclude_turns
	if paginated_source && params.ephemeral && include_turns {
		return fail(invalid_request('ephemeral paginated thread/fork requires `excludeTurns: true`'))
	}
	if paginated_source && include_turns {
		processor.send_deprecation_notice(request_id.connection_id, &paginated_full_history_deprecation_summary)
	}
	source_thread_id := copy_thread_id(&source_thread.thread_id)
	mut source_thread_name := ?string(none)
	mut persisted_source_thread_name := ?string(none)
	if stored_name := source_thread.name {
		if normalized_name := normalize_thread_name(&stored_name) {
			// Rust clones the name for the durable metadata update, retaining the original for the
			// response materialization below.
			source_thread_name = normalized_name.clone()
			persisted_source_thread_name = normalized_name
		}
	}
	mut boundary := store.ForkBoundary{ kind: .latest }
	if last_turn_id := params.last_turn_id {
		boundary = store.ForkBoundary{ kind: .through_turn, turn_id: last_turn_id.clone() }
	} else if before_turn_id := params.before_turn_id {
		boundary = store.ForkBoundary{ kind: .before_turn, turn_id: before_turn_id.clone() }
	}
	mut prepared_fork := store.PreparedFork{}
	mut has_prepared_fork := false
	mut source_history_items := []store.RolloutItem{}
	if paginated_source {
		prepare_result := processor.thread_store.prepare_fork(store.PrepareForkParams{
			thread_id: copy_thread_id(&source_thread_id)
			boundary:  boundary
		})
		if prepare_result.is_error {
			prepare_error := clone_thread_store_error(&prepare_result.error_value)
			return fail(match prepare_error.kind {
				.invalid_request { invalid_request(prepare_error.message.clone()) }
				.thread_not_found {
					invalid_request('no rollout found for thread id ${prepare_error.thread_id.value}')
				}
				.unsupported { method_not_found('paginated_threads is not supported yet') }
				else {
					internal_error('failed to prepare paginated fork: ${prepare_error.message}')
				}
			})
		}
		prepared_fork = prepare_result.value
		has_prepared_fork = true
		source_history_items = prepared_fork.model_context.clone()
	} else {
		source_thread = processor.read_stored_thread_for_resume(&params.thread_id, params.path, true)!
		stored_history := source_thread.history or {
			return fail(internal_error('thread ${source_thread_id.value} did not include persisted history'))
		}
		source_history_items = stored_history.items.clone()
	}
	// Persist Windows sandbox mode.
	mut cli_overrides := map[string]string{}
	if supplied_overrides := clone_optional_config_map(params.config) {
		cli_overrides = supplied_overrides.clone()
	}
	$if windows {
		match codex_core.windows_sandbox_level_from_config(&processor.config) {
			.elevated {
				cli_overrides['windows.sandbox'] = '"elevated"'
			}
			.restricted_token {
				cli_overrides['windows.sandbox'] = '"unelevated"'
			}
			.disabled {}
		}
	}
	mut resolved_runtime_workspace_roots := ?[]string(none)
	if roots := params.runtime_workspace_roots {
		resolved_runtime_workspace_roots = resolve_runtime_workspace_roots(roots)
	}
	mut typesafe_overrides := processor.build_thread_config_overrides(params.model, params.model_provider, params.service_tier, params.cwd, resolved_runtime_workspace_roots, params.approval_policy, params.approvals_reviewer, params.sandbox, params.permissions, params.base_instructions, params.developer_instructions, none)
	if params.ephemeral {
		typesafe_overrides.ephemeral = true
	}
	restore_approval_policy := typesafe_overrides.approval_policy == none
	restore_approvals_reviewer := typesafe_overrides.approvals_reviewer == none
		&& !('approvals_reviewer' in cli_overrides)
	request_override_map := if cli_overrides.len > 0 {
		OptionalStringMap{ has_value: true, value: cli_overrides.clone() }
	} else {
		OptionalStringMap{}
	}
	// Rust borrows one request map for override inspection and later moves it into config loading.
	// Give the final load its own owned V optional after those inspections are complete.
	request_overrides_for_load := if cli_overrides.len == 0 {
		?map[string]string(none)
	} else {
		?map[string]string(cli_overrides.clone())
	}
	restore_permission_profile := !has_permission_override(&request_override_map, &typesafe_overrides)
	needs_latest_settings := restore_approval_policy || restore_approvals_reviewer
		|| restore_permission_profile
	mut loaded_parent := codex_core.OptionalCodexThread{}
	if paginated_source && needs_latest_settings {
		mut parent_loaded := true
		parent := processor.thread_manager.get_thread(&source_thread_id) or {
			parent_loaded = false
			codex_core.CodexThread{}
		}
		if parent_loaded {
			loaded_parent = codex_core.OptionalCodexThread{ has_value: true, value: parent }
		}
	}
	mut latest_settings := persisted_resume_settings.latest_persisted_resume_settings(&source_history_items)
	mut latest_context_items := []store.RolloutItem{}
	mut has_latest_context := false
	if loaded_parent.has_value {
		snapshot := loaded_parent.value.thread_settings_snapshot()
		latest_settings = persisted_resume_settings.OptionalPersistedResumeSettings{
			has_value: true
			value:     persisted_resume_settings.PersistedResumeSettings{
				approval_policy:           snapshot.approval_policy
				approvals_reviewer:        snapshot.approvals_reviewer
				active_permission_profile: codex_protocol.clone_optional_active_permission_profile(snapshot.active_permission_profile)
			}
		}
	} else if paginated_source && needs_latest_settings
		&& (params.last_turn_id != none || params.before_turn_id != none) {
		latest_context_result := processor.thread_store.load_latest_model_context(store.StoreLoadThreadHistoryParams{
			thread_id:        copy_thread_id(&source_thread_id)
			include_archived: true
		})
		if latest_context_result.is_error {
			return fail(thread_store_resume_read_error(clone_thread_store_error(&latest_context_result.error_value)))
		}
		latest_context_items = latest_context_result.value.items.clone()
		has_latest_context = true
		latest_settings = persisted_resume_settings.latest_persisted_resume_settings(&latest_context_result.value.items)
	}
	if latest_settings.has_value {
		if restore_approval_policy {
			typesafe_overrides.approval_policy = latest_settings.value.approval_policy
		}
		if restore_approvals_reviewer {
			typesafe_overrides.approvals_reviewer = latest_settings.value.approvals_reviewer
		}
		if restore_permission_profile {
			if profile := latest_settings.value.active_permission_profile {
				typesafe_overrides.persisted_permission_profile_id = profile.id.clone()
			}
		}
	}
	multi_agent_history_items := if has_latest_context {
		latest_context_items.clone()
	} else {
		source_history_items.clone()
	}
	multi_agent_history := InitialHistory{
		kind:            .resumed
		conversation_id: copy_thread_id(&source_thread_id)
		items:           multi_agent_history_items
		rollout_path:    clone_optional_string(source_thread.rollout_path)
	}
	mut source_multi_agent_version := multi_agent_history.get_multi_agent_version()
	if source_multi_agent_version == none && loaded_parent.has_value {
		source_multi_agent_version = loaded_parent.value.multi_agent_version()
	}
	config := processor.config_manager.load_for_cwd(request_overrides_for_load, typesafe_overrides, source_thread.cwd.clone()) or {
		message := err.msg()
		return fail(config_load_error(&message))
	}
	goals_enabled := config.features.enabled(codex_features.Feature.goals)
	mut history_items := source_history_items.clone()
	if !has_prepared_fork {
		if last_turn_id := params.last_turn_id {
			// Rust moves the unwrapped Arc into the truncation helper and rebinds the result. V's
			// ownership checker cannot model a move-and-rebind of the same array variable, so retain
			// the rebound owner explicitly at this ownership adaptation boundary.
			history_items = codex_core.truncate_rollout_after_turn_id(history_items.clone(), &last_turn_id) or {
				return fail(internal_error('failed to truncate thread for fork: ${err}'))
			}
		} else if before_turn_id := params.before_turn_id {
			history_items = codex_core.truncate_rollout_before_turn_id(history_items.clone(), &before_turn_id) or {
				return fail(internal_error('failed to truncate thread for fork: ${err}'))
			}
		}
	}
	// The fork cutoff can remove the only TurnContext that records the selected version.
	// Recover it from the untrimmed source or live parent, independently of permission overrides.
	if version := source_multi_agent_version {
		if params.last_turn_id != none || params.before_turn_id != none {
			for mut item in history_items {
				if item.kind == .session_meta {
					if meta_id := item.session_meta_id {
						if meta_id.value == source_thread_id.value {
							item.multi_agent_version = version
						}
					}
				}
			}
			if has_prepared_fork {
				prepared_fork = store.PreparedFork{ model_context: history_items.clone() }
			}
		}
	}
	// Update only the fork's in-memory metadata; the source rollout stays unchanged.
	// Derive a Config using the same logic as new conversation, honoring overrides if provided.
	fallback_model_provider := config.model_provider_id.clone()
	ephemeral_preview := if params.ephemeral {
		if paginated_source && params.last_turn_id == none && params.before_turn_id == none {
			source_thread.preview.clone()
		} else {
			preview_from_rollout_items(&history_items)
		}
	} else {
		''
	}
	ephemeral_turns := if params.ephemeral && include_turns {
		build_legacy_api_turns_from_rollout_items(&history_items)
	} else {
		[]api.Turn{}
	}
	mut ephemeral_token_usage_turn_id := ?string(none)
	if params.ephemeral && include_turns {
		ephemeral_token_usage_turn_id = restored_token_usage_turn_id(&history_items, &ephemeral_turns)
	}
	token_usage_history_items := if paginated_source {
		history_items.clone()
	} else {
		[]store.RolloutItem{}
	}
	inherited_project_id := clone_optional_string(source_thread.project_id)
	mut reserved_thread_id := ?codex_protocol.ThreadId(none)
	mut cleanup_thread_id := ?codex_protocol.ThreadId(none)
	if !config.ephemeral {
		operation := 'thread/fork'
		reserved := stage_pending_thread_metadata(&processor.thread_manager, &processor.thread_store, StoreThreadMetadataPatch{
			project_id:       clearable_string_from_optional(clone_optional_string(inherited_project_id))
			daybreak_enabled: source_thread.daybreak_enabled
		}, &operation)!
		if reserved.has_value {
			reserved_thread_id = copy_thread_id(&reserved.value)
			cleanup_thread_id = copy_thread_id(&reserved.value)
		}
	}
	parent_trace := processor.request_trace_context(&request_id)
	thread_source := clone_optional_thread_source(params.thread_source)
	response_history := InitialHistory{
		kind:            .resumed
		conversation_id: copy_thread_id(&source_thread_id)
		items:           history_items.clone()
		rollout_path:    clone_optional_string(source_thread.rollout_path)
	}
	fork_result := if has_prepared_fork {
		processor.thread_manager.fork_prepared_thread(config, prepared_fork, thread_source, parent_trace, client_mcp_extensions, reserved_thread_id)
	} else {
		processor.thread_manager.fork_thread_from_history(.interrupted, config, clone_initial_history(&response_history), thread_source, parent_trace, client_mcp_extensions, reserved_thread_id)
	}
	if fork_result.kind == .error {
		remove_pending_thread_metadata(&processor.thread_store, cleanup_thread_id)
		fork_error := fork_result.error_value
		return fail(match fork_error.kind {
			.io, .json {
				invalid_request('failed to load thread ${source_thread_id.value}: ${fork_error.message}')
			}
			.invalid_request { invalid_request(fork_error.message.clone()) }
			else { internal_error('error forking thread: ${fork_error.message}') }
		})
	}
	new_thread := fork_result.value
	set_app_server_client_info(&new_thread.thread, app_server_client_name, app_server_client_version)!
	if new_thread.session_configured.rollout_path != none {
		if inherited_name := persisted_source_thread_name {
			name_result := processor.thread_manager.update_thread_metadata(copy_thread_id(&new_thread.thread_id), store.StoredThreadMetadataUpdatePatch{
				name: store.ClearableString{ has_value: true, value: inherited_name.clone() }
			}, true)
			if name_result.is_error {
				operation := 'inherit source thread name'
				return fail(core_thread_write_error(&operation, clone_codex_error(&name_result.error_value)))
			}
		}
	}
	mut inherited_goal := false
	if params.defer_goal_continuation && new_thread.session_configured.rollout_path != none
		&& goals_enabled {
		mut goal_state_db := new_thread.thread.state_db()
		if goal_state_db == none {
			if server_state_db := processor.state_db {
				goal_state_db = server_state_db
			}
		}
		if state_db := goal_state_db {
			processor.thread_goal_processor.flush_goal_progress_for_fork(copy_thread_id(&source_thread_id)) or {
				return fail(internal_error('failed to flush source thread goal: ${err}'))
			}
			inherited_goal = inherit_thread_goal_snapshot(&state_db, copy_thread_id(&source_thread_id), copy_thread_id(&new_thread.thread_id)) or {
				return fail(internal_error('failed to inherit source thread goal: ${err}'))
			}
		}
	}
	if inherited_goal {
		processor.thread_goal_processor.restore_inherited_goal_runtime(copy_thread_id(&new_thread.thread_id))
	}
	instruction_sources := new_thread.thread.legacy_instruction_sources()
	// Auto-attach a conversation listener when forking a thread.
	thread_kind := 'thread'
	mut listener_attach_succeeded := true
	listener_result := processor.ensure_conversation_listener(copy_thread_id(&new_thread.thread_id), request_id.connection_id, false) or {
		listener_attach_succeeded = false
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:          .error
			error_message: err.msg()
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
		EnsureConversationListenerResult.connection_closed
	}
	if listener_attach_succeeded {
		thread_lifecycle.log_listener_attach_result(ListenerAttachResult{
			kind:  .ok
			value: listener_result
		}, copy_thread_id(&new_thread.thread_id), request_id.connection_id, &thread_kind)
	}
	// Persistent forks materialize their own rollout immediately. Ephemeral forks stay
	// pathless, so their visible history is projected before the source history is consumed.
	fork_config_snapshot := new_thread.thread.config_snapshot()
	mut token_usage_turn_id := ephemeral_token_usage_turn_id
	mut thread_value := if new_thread.session_configured.rollout_path != none {
		stored_fork := processor.read_stored_thread_for_new_fork(copy_thread_id(&new_thread.thread_id), include_turns && !paginated_source)!
		mut stored_api, history := thread_from_stored_thread(stored_fork, &fallback_model_provider, &processor.config.cwd)
		if include_turns {
			if stored_history := history {
				thread_lifecycle.populate_thread_turns_from_history(mut stored_api, &stored_history.items, none)
				token_usage_turn_id = restored_token_usage_turn_id(&stored_history.items, &stored_api.turns)
			} else if token_usage_history_items.len > 0 {
				token_usage_turn_id = restored_token_usage_turn_id(&token_usage_history_items, &stored_api.turns)
			}
		}
		stored_api
	} else {
		mut ephemeral_thread := build_thread_from_snapshot(copy_thread_id(&new_thread.thread_id), new_thread.session_configured.session_id.clone(), new_thread.thread.multi_agent_version(), &fork_config_snapshot, none)
		ephemeral_thread.preview = ephemeral_preview
		ephemeral_thread.forked_from_id = source_thread_id.str()
		ephemeral_thread.turns = ephemeral_turns
		ephemeral_thread
	}
	if paginated_source && include_turns {
		thread_value.turns = processor.paginated_thread_full_turns(copy_thread_id(&new_thread.thread_id))!
		token_usage_turn_id = restored_token_usage_turn_id(&token_usage_history_items, &thread_value.turns)
	}
	if inherited_name := source_thread_name {
		set_thread_name_from_title(mut thread_value, inherited_name)
	}
	thread_value.session_id = new_thread.session_configured.session_id.clone()
	thread_value.thread_source = clone_optional_thread_source(fork_config_snapshot.thread_source)
	thread_value.can_accept_direct_input = can_accept_direct_input(new_thread.thread.multi_agent_version(), &fork_config_snapshot.session_source)
	apply_live_thread_settings(mut thread_value, &fork_config_snapshot)
	if thread_value.path == none {
		thread_value.project_id = clone_optional_string(inherited_project_id)
	}
	processor.thread_watch_manager.upsert_thread_silently(&thread_value.id)
	thread_value.status = resolve_thread_status(processor.thread_watch_manager.loaded_status_for_thread(&thread_value.id), false)
	thread_originator := fork_config_snapshot.originator.clone()
	started_notification := thread_started_notification(clone_api_thread(&thread_value))
	response := api.ThreadForkResponse{
		thread:                    thread_value
		model:                     new_thread.session_configured.model.clone()
		model_provider:            new_thread.session_configured.model_provider_id.clone()
		service_tier:              clone_optional_string(new_thread.session_configured.service_tier)
		cwd:                       new_thread.session_configured.cwd.clone()
		runtime_workspace_roots:   fork_config_snapshot.workspace_roots.clone()
		instruction_sources:       instruction_sources
		approval_policy:           new_thread.session_configured.approval_policy
		approvals_reviewer:        new_thread.session_configured.approvals_reviewer
		sandbox:                   fork_config_snapshot.sandbox_policy()
		active_permission_profile: thread_response_active_permission_profile(fork_config_snapshot.active_permission_profile)
		reasoning_effort:          new_thread.session_configured.reasoning_effort
		multi_agent_mode:          .explicit_request_only
	}
	processor.outgoing.send_response_with_thread_originator(clone_connection_request_id(&request_id), api.ClientResponsePayload(response), thread_originator)
	// `excludeTurns` is the cheap fork path, so skip restored usage replay
	// instead of rebuilding history only to attribute a historical update.
	// Mirror the resume contract for forks: the new thread is usable as soon
	// as the response arrives, so restored usage must follow immediately.
	if usage_turn_id := token_usage_turn_id {
		send_thread_token_usage_update_to_connection(&processor.outgoing, request_id.connection_id, copy_thread_id(&new_thread.thread_id), &new_thread.thread, usage_turn_id)
	}
	processor.outgoing.send_server_notification(api.ServerNotification(started_notification))
	if inherited_goal {
		processor.thread_goal_processor.emit_thread_goal_snapshot(copy_thread_id(&new_thread.thread_id))
	}
}

fn (processor &ThreadRequestProcessor) get_thread_summary_response_inner(
	params api.GetConversationSummaryParams
) !api.GetConversationSummaryResponse {
	stored_thread := match params.kind {
		.thread_id {
			conversation_id := codex_protocol.thread_id_from_string(&params.conversation_id) or {
				return fail(invalid_request('invalid conversation id: ${err}'))
			}
			result := processor.thread_store.read_thread(store.StoreReadThreadParams{
				thread_id:        copy_thread_id(&conversation_id)
				include_archived: true
				include_history:  false
			})
			if result.kind != .ok {
				return fail(conversation_summary_thread_id_read_error(copy_thread_id(&conversation_id),
					clone_thread_store_error(&result.error_value)))
			}
			result.value
		}
		.rollout_path {
			if !processor.thread_store.supports_rollout_path_queries() {
				return fail(invalid_request('rollout path queries are only supported with the local thread store'))
			}
			result := processor.thread_store.read_thread_by_rollout_path(store.StoreReadThreadByRolloutPathParams{
				rollout_path:     params.rollout_path.clone()
				include_archived: true
				include_history:  false
			})
			if result.kind != .ok {
				return fail(conversation_summary_rollout_path_read_error(&params.rollout_path,
					clone_thread_store_error(&result.error_value)))
			}
			result.value
		}
	}
	summary := summary_from_stored_thread(stored_thread, &processor.config.model_provider_id)
	return api.GetConversationSummaryResponse{ summary: summary }
}

fn clone_optional_string_array(value ?[]string) ?[]string {
	if values := value {
		return values.clone()
	}
	return none
}

fn clone_optional_turn_environment_params(
	value ?[]api.TurnEnvironmentParams
) ?[]api.TurnEnvironmentParams {
	if values := value {
		mut cloned := []api.TurnEnvironmentParams{cap: values.len}
		for environment in values {
			cloned << api.TurnEnvironmentParams{
				environment_id:          environment.environment_id.clone()
				cwd:                     environment.cwd.clone()
				runtime_workspace_roots: clone_optional_string_array(environment.runtime_workspace_roots)
			}
		}
		return cloned
	}
	return none
}

fn clone_optional_source_kind_array(value ?[]api.ThreadSourceKind) ?[]api.ThreadSourceKind {
	if values := value {
		return values.clone()
	}
	return none
}

fn clone_relation_filter(value ?store.ThreadRelationFilter) ?store.ThreadRelationFilter {
	if filter := value {
		return store.ThreadRelationFilter{
			kind:      filter.kind
			thread_id: copy_thread_id(&filter.thread_id)
		}
	}
	return none
}

fn (processor &ThreadRequestProcessor) list_threads_common(
	requested_page_size int,
	cursor ?string,
	sort_key store.ThreadSortKey,
	sort_direction api.SortDirection,
	filters ThreadListFilters
) !([]store.StoredThread, ?string) {
	mut model_provider_filter := []string{}
	mut has_model_provider_filter := false
	if providers := filters.model_providers {
		if providers.len == 0 {
			has_model_provider_filter = false
		} else {
			model_provider_filter = providers.clone()
			has_model_provider_filter = true
		}
	} else if filters.relation_filter == none {
		model_provider_filter = [processor.config.model_provider_id.clone()]
		has_model_provider_filter = true
	}
	source_filters := if filters.relation_filter != none && filters.source_kinds == none {
		app_filters.SourceFilters{}
	} else {
		app_filters.compute_source_filters(clone_optional_source_kind_array(filters.source_kinds))
	}
	store_sort_direction := match sort_direction {
		.asc { store.SortDirection.asc }
		.desc { store.SortDirection.desc }
	}
	mut cursor_obj := clone_optional_string(cursor)
	mut last_cursor := clone_optional_string(cursor_obj)
	mut remaining := requested_page_size
	mut items := []store.StoredThread{cap: requested_page_size}
	mut next_cursor := ?string(none)
	for remaining > 0 {
		page_size := if remaining < thread_list_max_limit {
			remaining
		} else {
			thread_list_max_limit
		}
		mut allowed_sources := []codex_protocol.SessionSource{cap: source_filters.allowed_sources.len}
		for source in source_filters.allowed_sources {
			allowed_sources << codex_protocol.clone_session_source(&source)
		}
		page_result := processor.thread_store.list_threads(store.ListThreadsParams{
			page_size:         page_size
			cursor:            clone_optional_string(cursor_obj)
			sort_key:          sort_key
			sort_direction:    store_sort_direction
			allowed_sources:   allowed_sources
			model_providers:   if has_model_provider_filter {
				model_provider_filter.clone()
			} else {
				none
			}
			archived:          filters.archived
			section_id:        store.ClearableString{
				has_value: filters.section_id.has_value
				clear:     filters.section_id.clear
				value:     filters.section_id.value.clone()
			}
			project_id:        store.ClearableString{
				has_value: filters.project_id.has_value
				clear:     filters.project_id.clear
				value:     filters.project_id.value.clone()
			}
			cwd_filters:       store.OptionalStringArray{
				has_value: filters.cwd_filters.has_value
				value:     filters.cwd_filters.value.clone()
			}
			search_term:       clone_optional_string(filters.search_term)
			use_state_db_only: filters.use_state_db_only
			relation_filter:   clone_relation_filter(filters.relation_filter)
		})
		if page_result.is_error {
			return fail(thread_store_list_error(clone_thread_store_error(&page_result.error_value)))
		}
		page := page_result.value
		for stored_thread in page.items {
			source := with_thread_spawn_agent_metadata(codex_protocol.clone_session_source(&stored_thread.source), clone_optional_string(stored_thread.agent_nickname), clone_optional_string(stored_thread.agent_role))
			if source_filter := source_filters.post_filter {
				if source_filter.len > 0 && !app_filters.source_kind_matches(&source, &source_filter) {
					continue
				}
			}
			if filters.cwd_filters.has_value {
				mut cwd_matches := false
				for expected_cwd in filters.cwd_filters.value {
					if path_utils.paths_match_after_normalization(&stored_thread.cwd, &expected_cwd) {
						cwd_matches = true
						break
					}
				}
				if !cwd_matches {
					continue
				}
			}
			items << stored_thread
			if items.len >= requested_page_size {
				break
			}
		}
		remaining = requested_page_size - items.len
		next_cursor = page.next_cursor
		if remaining == 0 {
			break
		}
		cursor_value := next_cursor or { break }
		// Break if our pagination would reuse the same cursor again; this avoids
		// an infinite loop when filtering drops everything on the page.
		if previous := last_cursor {
			if previous == cursor_value {
				next_cursor = none
				break
			}
		}
		last_cursor = cursor_value.clone()
		cursor_obj = cursor_value
	}
	return items, next_cursor
}

pub fn xcode_26_4_mcp_elicitations_auto_deny(
	client_name &string,
	client_version &string
) bool {

	// Xcode 26.4 shipped before app-server MCP elicitation requests were
	// client-visible. Keep elicitations auto-denied for that client line.
	// TODO: Remove this compatibility hack once Xcode 26.4 ages out.
	return *client_name == 'Xcode' && client_version.starts_with('26.4')
}

pub fn thread_turns_page_size(limit ?u32) int {
	return clamp_page_size(limit, thread_turns_default_limit, thread_turns_max_limit)
}

fn clamp_page_size(limit ?u32, default_limit int, max_limit int) int {
	value := int(limit or { u32(default_limit) })
	if value < 1 {
		return 1
	}
	if value > max_limit {
		return max_limit
	}
	return value
}

fn thread_backwards_cursor_for_sort_key(
	thread_value &store.StoredThread,
	sort_key store.ThreadSortKey,
	sort_direction api.SortDirection
) ?string {
	if sort_key == .section_position {
		position := thread_value.section_position or { return none }
		if sort_direction == .asc && position == i64(0x7fff_ffff_ffff_ffff) {
			return none
		}
		if sort_direction == .desc && position == i64(-0x7fff_ffff_ffff_ffff) - 1 {
			return none
		}
		offset_position := if sort_direction == .asc { position + 1 } else { position - 1 }
		return '${offset_position}|${thread_value.thread_id.str()}'
	}

	timestamp := match sort_key {
		.created_at { thread_value.created_at }
		.updated_at { thread_value.updated_at }
		.recency_at { thread_value.recency_at }
		.section_position {
			return none
		}
	}
	// The state DB stores unique millisecond timestamps. Offset the reverse cursor by one
	// millisecond so the opposite-direction query includes the page anchor.
	if sort_direction == .asc && timestamp == i64(0x7fff_ffff_ffff_ffff) {
		return none
	}
	if sort_direction == .desc && timestamp == i64(-0x7fff_ffff_ffff_ffff) - 1 {
		return none
	}
	offset_timestamp := if sort_direction == .asc { timestamp + 1 } else { timestamp - 1 }
	return time.unix_milli(offset_timestamp).format_rfc3339()
}

struct ThreadTurnsPage {
	turns            []api.Turn
	next_cursor      ?string
	backwards_cursor ?string
}

struct ThreadTurnsCursor {
	turn_id        string @[json: 'turnId']
	include_anchor bool   @[json: 'includeAnchor']
}

// OptionalCursor lets V borrow the option as a whole. This avoids V's currently unreliable
// `?&string` C generation while preserving Rust's `Option<&str>` ownership direction.
pub struct OptionalCursor {
pub:
	has_value bool
	value     string
}

pub fn paginate_thread_turns(
	turns []api.Turn,
	cursor &OptionalCursor,
	limit ?u32,
	sort_direction api.SortDirection
) !ThreadTurnsPage {
	if turns.len == 0 {
		return ThreadTurnsPage{}
	}

	anchor := if cursor.has_value {
		parse_thread_turns_cursor(&cursor.value)!
	} else {
		ThreadTurnsCursor{}
	}
	page_size := thread_turns_page_size(limit)
	mut anchor_index := -1
	if cursor.has_value {
		for index, turn in turns {
			if turn.id == anchor.turn_id {
				anchor_index = index
				break
			}
		}
		if anchor_index < 0 {
			return fail(invalid_request('invalid cursor: anchor turn is no longer present'))
		}
	}

	mut ordered_indices := []int{cap: turns.len}
	if sort_direction == .asc {
		for index in 0 .. turns.len {
			if !cursor.has_value || index > anchor_index || (anchor.include_anchor
				&& index == anchor_index) {
				ordered_indices << index
			}
		}
	} else {
		for reverse_index := turns.len - 1; reverse_index >= 0; reverse_index-- {
			if !cursor.has_value || reverse_index < anchor_index || (anchor.include_anchor
				&& reverse_index == anchor_index) {
				ordered_indices << reverse_index
			}
			if reverse_index == 0 {
				break
			}
		}
	}

	more_turns_available := ordered_indices.len > page_size
	if ordered_indices.len > page_size {
		ordered_indices = ordered_indices[..page_size].clone()
	}
	mut page_turns := []api.Turn{cap: ordered_indices.len}
	for index in ordered_indices {
		page_turns << clone_turn(&turns[index])
	}
	mut backwards_cursor := ?string(none)
	if page_turns.len > 0 {
		backwards_cursor = serialize_thread_turns_cursor(&page_turns[0].id, true)!
	}
	mut next_cursor := ?string(none)
	if more_turns_available && page_turns.len > 0 {
		last_turn_id := page_turns.last().id.clone()
		next_cursor = serialize_thread_turns_cursor(&last_turn_id, false)!
	}
	return ThreadTurnsPage{
		turns:            page_turns
		next_cursor:      next_cursor
		backwards_cursor: backwards_cursor
	}
}

fn serialize_thread_turns_cursor(turn_id &string, include_anchor bool) !string {
	return '{"turnId":${quote_json_string(turn_id)},"includeAnchor":${include_anchor}}'
}

fn parse_thread_turns_cursor(cursor &string) !ThreadTurnsCursor {
	turn_id_field := 'turnId'
	turn_id := parse_json_string_field(cursor, &turn_id_field) or {
		return fail(invalid_request('invalid cursor: ${*cursor}'))
	}
	include_anchor_field := 'includeAnchor'
	include_anchor := parse_json_bool_field(cursor, &include_anchor_field) or {
		return fail(invalid_request('invalid cursor: ${*cursor}'))
	}
	return ThreadTurnsCursor{
		turn_id:        turn_id
		include_anchor: include_anchor
	}
}

// The cursor is a two-field JSON object. These focused helpers avoid a V 0.5.2 ownership-codegen
// failure in the generic JSON encoder while preserving the Rust camelCase wire representation.
fn quote_json_string(value &string) string {
	mut encoded := '"'
	for character in value.runes() {
		encoded += match character {
			`"` { '\\"' }
			`\\` { '\\\\' }
			`\b` { '\\b' }
			`\f` { '\\f' }
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			else {
				if character < 0x20 { '\\u${character:04x}' } else { character.str() }
			}
		}
	}
	return encoded + '"'
}

fn json_field_value_start(source &string, field &string) !int {
	text := *source
	needle := '"${*field}"'
	field_index := text.index(needle) or { return error('missing field') }
	mut index := field_index + needle.len
	for index < text.len && text[index] in [` `, `\t`, `\r`, `\n`] {
		index++
	}
	if index >= text.len || text[index] != `:` {
		return error('missing colon')
	}
	index++
	for index < text.len && text[index] in [` `, `\t`, `\r`, `\n`] {
		index++
	}
	return index
}

fn parse_json_string_field(source &string, field &string) !string {
	text := *source
	mut index := json_field_value_start(source, field)!
	if index >= text.len || text[index] != `"` {
		return error('not a string')
	}
	index++
	mut decoded := ''
	for index < text.len {
		byte := text[index]
		if byte == `"` {
			return decoded
		}
		if byte != `\\` {
			decoded += byte.ascii_str()
			index++
			continue
		}
		index++
		if index >= text.len {
			return error('truncated escape')
		}
		escape := text[index]
		decoded += match escape {
			`"` { '"' }
			`\\` { '\\' }
			`/` { '/' }
			`b` { '\b' }
			`f` { '\f' }
			`n` { '\n' }
			`r` { '\r' }
			`t` { '\t' }
			`u` {
				if index + 4 >= text.len {
					return error('truncated unicode escape')
				}
				hex := text[index + 1..index + 5]
				codepoint := strconv.parse_int(hex, 16, 32) or {
					return error('invalid unicode escape')
				}
				index += 4
				rune(codepoint).str()
			}
			else {
				return error('invalid escape')
			}
		}
		index++
	}
	return error('unterminated string')
}

fn parse_json_bool_field(source &string, field &string) !bool {
	text := *source
	index := json_field_value_start(source, field)!
	remainder := text[index..]
	if remainder.starts_with('true') {
		return true
	}
	if remainder.starts_with('false') {
		return false
	}
	return error('not a boolean')
}

fn is_json_object(source &string) bool {
	value := trim_rust_whitespace(source)
	if value.len < 2 || value[0] != `{` || value[value.len - 1] != `}` {
		return false
	}
	mut depth := 0
	mut in_string := false
	mut escaped := false
	for byte in value.bytes() {
		if in_string {
			if escaped {
				escaped = false
			} else if byte == `\\` {
				escaped = true
			} else if byte == `"` {
				in_string = false
			}
			continue
		}
		if byte == `"` {
			in_string = true
		} else if byte == `{` {
			depth++
		} else if byte == `}` {
			depth--
			if depth < 0 {
				return false
			}
		}
	}
	return depth == 0 && !in_string && !escaped
}

struct ThreadTurnsPageOptions {
	cursor         string
	has_cursor     bool
	limit          ?u32
	sort_direction api.SortDirection
	items_view     api.TurnItemsView
}

fn build_thread_turns_page_response(
	items &[]store.RolloutItem,
	loaded_status api.ThreadStatus,
	has_live_running_thread bool,
	active_turn ?api.Turn,
	options ThreadTurnsPageOptions
) !api.ThreadTurnsListResponse {
	mut turns := reconstruct_thread_turns_for_turns_list(items, loaded_status, has_live_running_thread, active_turn)
	apply_thread_turns_items_view(mut turns, options.items_view)
	page := paginate_thread_turns(turns, &OptionalCursor{
		has_value: options.has_cursor
		value:     options.cursor
	}, options.limit, options.sort_direction)!
	return api.ThreadTurnsListResponse{
		data:             page.turns
		next_cursor:      page.next_cursor
		backwards_cursor: page.backwards_cursor
	}
}

pub fn build_thread_resume_initial_turns_page(
	items &[]store.RolloutItem,
	loaded_status api.ThreadStatus,
	has_live_running_thread bool,
	active_turn ?api.Turn,
	params &api.ThreadResumeInitialTurnsPageParams
) !api.TurnsPage {
	response := build_thread_turns_page_response(items, loaded_status, has_live_running_thread, active_turn, ThreadTurnsPageOptions{
		limit:          params.limit
		sort_direction: params.sort_direction or { api.SortDirection.desc }
		items_view:     params.items_view or { api.TurnItemsView.summary }
	})!
	return api.TurnsPage{
		data:             response.data
		next_cursor:      response.next_cursor
		backwards_cursor: response.backwards_cursor
	}
}

pub fn apply_thread_turns_items_view(mut turns []api.Turn, items_view api.TurnItemsView) {
	for mut turn in turns {
		match items_view {
			.not_loaded {
				turn.items.clear()
				turn.items_view = .not_loaded
			}
			.summary {
				mut first_user_message := ?api.ThreadItem(none)
				mut final_agent_message := ?api.ThreadItem(none)
				for item in turn.items {
					if first_user_message == none && item.kind == .user_message {
						first_user_message = clone_thread_item(&item)
					}
					if item.kind == .agent_message {
						final_agent_message = clone_thread_item(&item)
					}
				}
				mut summary_items := []api.ThreadItem{}
				if user_message := first_user_message {
					summary_items << user_message
				}
				if agent_message := final_agent_message {
					if summary_items.len == 0 || summary_items[0].id != agent_message.id {
						summary_items << agent_message
					}
				}
				turn.items = summary_items
				turn.items_view = .summary
			}
			.full {
				turn.items_view = .full
			}
		}
	}
}

fn reconstruct_thread_turns_for_turns_list(
	items &[]store.RolloutItem,
	loaded_status api.ThreadStatus,
	has_live_running_thread bool,
	active_turn ?api.Turn
) []api.Turn {
	mut turns := build_legacy_api_turns_from_rollout_items(items)
	if current := active_turn {
		has_live_in_progress_turn := has_live_running_thread || current.status == .in_progress
		normalize_thread_turns_status(mut turns, loaded_status, has_live_in_progress_turn)
		merge_turn_history_with_active_turn(mut turns, current)
	} else {
		normalize_thread_turns_status(mut turns, loaded_status, has_live_running_thread)
	}
	return turns
}

pub fn normalize_thread_turns_status(
	mut turns []api.Turn,
	loaded_status api.ThreadStatus,
	has_live_in_progress_turn bool
) {
	status := resolve_thread_status(loaded_status, has_live_in_progress_turn)
	if status.kind == .active {
		return
	}
	for mut turn in turns {
		if turn.status == .in_progress {
			turn.status = .interrupted
		}
	}
}

fn resolve_thread_status(loaded_status api.ThreadStatus, has_live_in_progress_turn bool) api.ThreadStatus {
	if has_live_in_progress_turn {
		return api.ThreadStatus{ kind: .active }
	}
	return loaded_status
}

fn merge_turn_history_with_active_turn(mut turns []api.Turn, active_turn api.Turn) {
	for index, turn in turns {
		if turn.id == active_turn.id {
			turns[index] = active_turn
			return
		}
	}
	turns << active_turn
}

fn build_legacy_api_turns_from_rollout_items(items &[]store.RolloutItem) []api.Turn {
	mut turns := []api.Turn{}
	for item in *items {
		match item.kind {
			.turn {
				turns << clone_turn(&item.turn)
			}
			.user_message {
				turns << api.Turn{
					id:         'turn-${turns.len + 1}'
					items:      [api.ThreadItem{
						id:      'user-${turns.len + 1}'
						kind:    .user_message
						content: [item.message.clone()]
					}]
					items_view: .full
					status:     .completed
				}
			}
			.agent_message {
				if turns.len > 0 {
					turns.last().items << api.ThreadItem{
						id:      'agent-${turns.len}'
						kind:    .agent_message
						content: [item.message.clone()]
					}
				}
			}
			.session_meta, .response_item, .other {}
		}
	}
	return turns
}

fn clone_thread_item(item &api.ThreadItem) api.ThreadItem {
	return api.ThreadItem{
		id:      item.id.clone()
		kind:    item.kind
		content: item.content.clone()
	}
}

fn clone_turn(turn &api.Turn) api.Turn {
	mut items := []api.ThreadItem{cap: turn.items.len}
	for item in turn.items {
		items << clone_thread_item(&item)
	}
	return api.Turn{
		id:           turn.id.clone()
		items:        items
		items_view:   turn.items_view
		status:       turn.status
		error:        turn.error
		started_at:   turn.started_at
		completed_at: turn.completed_at
		duration_ms:  turn.duration_ms
	}
}

fn clone_turns_page(page &api.TurnsPage) api.TurnsPage {
	mut data := []api.Turn{cap: page.data.len}
	for turn in page.data {
		data << clone_turn(&turn)
	}
	return api.TurnsPage{
		data:             data
		next_cursor:      clone_optional_string(page.next_cursor)
		backwards_cursor: clone_optional_string(page.backwards_cursor)
	}
}

// Rust clones the response thread before moving the original into the started notification.
fn clone_api_thread(thread_value &api.Thread) api.Thread {
	mut environments := []api.ThreadEnvironment{cap: thread_value.environments.value.len}
	for environment in thread_value.environments.value {
		environments << api.ThreadEnvironment{
			environment_id:          environment.environment_id.clone()
			cwd:                     environment.cwd.clone()
			runtime_workspace_roots: environment.runtime_workspace_roots.clone()
		}
	}
	mut section := ?api.ThreadSection(none)
	if value := thread_value.section {
		mut appearance := ?api.ThreadSectionAppearance(none)
		if style := value.appearance {
			appearance = api.ThreadSectionAppearance{
				icon:  style.icon.clone()
				color: style.color.clone()
			}
		}
		section = api.ThreadSection{
			id:         value.id.clone()
			name:       value.name.clone()
			appearance: appearance
		}
	}
	mut git_info := ?api.GitInfo(none)
	if value := thread_value.git_info {
		git_info = api.GitInfo{
			sha:        clone_optional_string(value.sha)
			branch:     clone_optional_string(value.branch)
			origin_url: clone_optional_string(value.origin_url)
		}
	}
	mut turns := []api.Turn{cap: thread_value.turns.len}
	for turn in thread_value.turns {
		turns << clone_turn(&turn)
	}
	return api.Thread{
		id:                      thread_value.id.clone()
		environments:            api.OptionalThreadEnvironments{
			has_value: thread_value.environments.has_value
			value:     environments
		}
		extra:                   thread_value.extra
		session_id:              thread_value.session_id.clone()
		forked_from_id:          clone_optional_string(thread_value.forked_from_id)
		parent_thread_id:        clone_optional_string(thread_value.parent_thread_id)
		preview:                 thread_value.preview.clone()
		ephemeral:               thread_value.ephemeral
		section:                 section
		section_entered_at:      thread_value.section_entered_at
		project_id:              clone_optional_string(thread_value.project_id)
		history_mode:            thread_value.history_mode
		model_provider:          thread_value.model_provider.clone()
		model:                   clone_optional_string(thread_value.model)
		reasoning_effort:        thread_value.reasoning_effort
		created_at:              thread_value.created_at
		updated_at:              thread_value.updated_at
		recency_at:              thread_value.recency_at
		status:                  api.ThreadStatus{ kind: thread_value.status.kind }
		path:                    clone_optional_string(thread_value.path)
		cwd:                     thread_value.cwd.clone()
		cli_version:             thread_value.cli_version.clone()
		originator:              clone_optional_string(thread_value.originator)
		agent_nickname:          clone_optional_string(thread_value.agent_nickname)
		agent_role:              clone_optional_string(thread_value.agent_role)
		source:                  codex_protocol.clone_session_source(&thread_value.source)
		can_accept_direct_input: thread_value.can_accept_direct_input
		thread_source:           clone_optional_thread_source(thread_value.thread_source)
		git_info:                git_info
		name:                    clone_optional_string(thread_value.name)
		daybreak_enabled:        thread_value.daybreak_enabled
		turns:                   turns
	}
}

enum ThreadReadViewErrorKind {
	invalid_request
	unsupported
	internal
	json_rpc
}

struct ThreadReadViewError {
	kind      ThreadReadViewErrorKind
	message   string
	operation string
	json_rpc  api.JSONRPCErrorError
}

fn thread_read_view_error(error_value ThreadReadViewError) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.internal { internal_error(error_value.message) }
		.json_rpc { error_value.json_rpc }
	}
}

fn is_exact_thread_store_miss(
	thread_id &codex_protocol.ThreadId,
	error_value &store.ThreadStoreError
) bool {
	no_rollout_message := 'no rollout found for thread id ${thread_id.value}'
	return (error_value.kind == .invalid_request
		&& error_value.message == no_rollout_message)
		|| (error_value.kind == .thread_not_found
			&& error_value.thread_id.value == thread_id.value)
}

fn clone_thread_store_error(error_value &store.ThreadStoreError) store.ThreadStoreError {
	return store.ThreadStoreError{
		kind:      error_value.kind
		message:   error_value.message.clone()
		operation: error_value.operation.clone()
		thread_id: copy_thread_id(&error_value.thread_id)
	}
}

// Rust's typed core errors are moved out of Result arms. V's explicit result wrappers retain the
// error next to their discriminator, so make that ownership transfer visible.
fn clone_codex_error(error_value &CodexErr) CodexErr {
	return CodexErr{
		kind:      error_value.kind
		message:   error_value.message.clone()
		thread_id: error_value.thread_id.clone()
	}
}

fn paginated_history_list_error(error_value store.ThreadStoreError) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.thread_not_found {
			invalid_request('no rollout found for thread id ${error_value.thread_id.str()}')
		}
		.conflict, .internal {
			internal_error('failed to list thread history: ${error_value.message}')
		}
	}
}

fn deserialize_stored_thread_item(item store.StoredThreadItem) !api.ThreadItem {
	return item.item
}

fn stored_turn_to_api_turn(
	turn store.StoredTurn,
	items_view api.TurnItemsView
) !api.Turn {
	status := match turn.status {
		.completed { api.TurnStatus.completed }
		.interrupted { api.TurnStatus.interrupted }
		.failed { api.TurnStatus.failed }
		.in_progress { api.TurnStatus.in_progress }
	}
	mut error_value := ?api.TurnError(none)
	if stored_error := turn.error {
		error_value = api.TurnError{
			message:            stored_error.message
			codex_error_info:   stored_error.codex_error_info
			additional_details: stored_error.additional_details
		}
	}
	mut items := []api.ThreadItem{cap: turn.items.len}
	for item in turn.items {
		items << deserialize_stored_thread_item(item)!
	}
	return api.Turn{
		id:           turn.turn_id
		items:        items
		items_view:   items_view
		status:       status
		error:        error_value
		started_at:   turn.started_at
		completed_at: turn.completed_at
		duration_ms:  turn.duration_ms
	}
}

pub fn unsupported_thread_store_operation(operation &string) api.JSONRPCErrorError {
	return method_not_found('${*operation} is not supported yet')
}

fn thread_store_list_error(error_value store.ThreadStoreError) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.thread_not_found, .conflict, .internal {
			internal_error('failed to list threads: ${error_value.message}')
		}
	}
}

fn thread_store_resume_read_error(error_value store.ThreadStoreError) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.thread_not_found {
			invalid_request('no rollout found for thread id ${error_value.thread_id.str()}')
		}
		.conflict, .internal { internal_error('failed to read thread: ${error_value.message}') }
	}
}

fn thread_turns_list_history_load_error(
	thread_id codex_protocol.ThreadId,
	error_value store.ThreadStoreError
) ThreadReadViewError {
	if error_value.kind == .invalid_request
		&& error_value.message.starts_with('failed to resolve rollout path `') {
		return ThreadReadViewError{
			kind:    .invalid_request
			message: 'thread ${thread_id.str()} is not materialized yet; thread/turns/list is unavailable before first user message'
		}
	}
	materialization_message := 'thread/turns/list is unavailable before first user message'
	return thread_store_error_to_read_view(thread_id, error_value, &materialization_message)
}

fn thread_read_history_load_error(
	thread_id codex_protocol.ThreadId,
	error_value store.ThreadStoreError
) ThreadReadViewError {
	if (error_value.kind == .invalid_request
		&& error_value.message.starts_with('failed to resolve rollout path `'))
		|| (error_value.kind == .thread_not_found
			&& error_value.thread_id.value == thread_id.value) {
		return ThreadReadViewError{
			kind:    .invalid_request
			message: 'thread ${thread_id.str()} is not materialized yet; includeTurns is unavailable before first user message'
		}
	}
	materialization_message := 'includeTurns is unavailable before first user message'
	return thread_store_error_to_read_view(thread_id, error_value, &materialization_message)
}

fn thread_store_error_to_read_view(
	thread_id codex_protocol.ThreadId,
	error_value store.ThreadStoreError,
	materialization_message &string
) ThreadReadViewError {
	return match error_value.kind {
		.invalid_request {
			ThreadReadViewError{
				kind:    .invalid_request
				message: error_value.message
			}
		}
		.unsupported {
			ThreadReadViewError{
				kind:      .unsupported
				operation: error_value.operation
			}
		}
		.thread_not_found {
			ThreadReadViewError{
				kind:    .invalid_request
				message: 'thread ${thread_id.str()} is not materialized yet; ${*materialization_message}'
			}
		}
		.conflict, .internal {
			ThreadReadViewError{
				kind:    .internal
				message: 'failed to load thread history for thread ${thread_id.str()}: ${error_value.message}'
			}
		}
	}
}

fn conversation_summary_thread_id_read_error(
	conversation_id codex_protocol.ThreadId,
	error_value store.ThreadStoreError
) api.JSONRPCErrorError {
	no_rollout_message := 'no rollout found for thread id ${conversation_id.str()}'
	if (error_value.kind == .invalid_request && error_value.message == no_rollout_message)
		|| (error_value.kind == .thread_not_found
			&& error_value.thread_id.value == conversation_id.value) {
		return conversation_summary_not_found_error(conversation_id)
	}
	return match error_value.kind {
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.invalid_request { invalid_request(error_value.message) }
		.thread_not_found, .conflict, .internal {
			internal_error('failed to load conversation summary for ${conversation_id.str()}: ${error_value.message}')
		}
	}
}

fn conversation_summary_not_found_error(
	conversation_id codex_protocol.ThreadId
) api.JSONRPCErrorError {
	return invalid_request('no rollout found for conversation id ${conversation_id.str()}')
}

fn conversation_summary_rollout_path_read_error(
	path &string,
	error_value store.ThreadStoreError
) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.thread_not_found, .conflict, .internal {
			internal_error('failed to load conversation summary from ${*path}: ${error_value.message}')
		}
	}
}

pub fn core_thread_write_error(operation &string, error_value CodexErr) api.JSONRPCErrorError {
	return match error_value.kind {
		.thread_not_found { invalid_request('thread not found: ${error_value.thread_id}') }
		.invalid_request { invalid_request(error_value.message) }
		.unsupported_operation { method_not_found(error_value.message) }
		.io, .json, .other { internal_error('failed to ${*operation}: ${error_value.message}') }
	}
}

fn thread_store_mutation_error(
	operation &string,
	error_value store.ThreadStoreError
) api.JSONRPCErrorError {
	return match error_value.kind {
		.invalid_request, .conflict { invalid_request(error_value.message) }
		.unsupported { unsupported_thread_store_operation(&error_value.operation) }
		.thread_not_found, .internal {
			internal_error('failed to ${*operation} session: ${error_value.message}')
		}
	}
}

fn set_thread_name_from_title(mut thread_value api.Thread, title string) {
	title_trimmed := trim_rust_whitespace(&title)
	preview_trimmed := trim_rust_whitespace(&thread_value.preview)
	if title_trimmed.len == 0 || preview_trimmed == title_trimmed {
		return
	}
	thread_value.name = title
}

pub fn thread_from_stored_thread(
	stored_thread store.StoredThread,
	fallback_provider &string,
	fallback_cwd &string
) (api.Thread, ?store.StoredThreadHistory) {
	path := stored_thread.rollout_path
	mut git_info := ?api.GitInfo(none)
	if info := stored_thread.git_info {
		git_info = api.GitInfo{
			sha:        info.commit_hash
			branch:     info.branch
			origin_url: info.repository_url
		}
	}
	normalized_cwd := path_utils.normalize_for_native_workdir(stored_thread.cwd)
	cwd_path := codex_utils_absolute_path.AbsolutePathBuf.relative_to_current_dir(normalized_cwd) or {
		warning := 'failed to normalize thread cwd while reading stored thread: ${err}'
		tracing.warn(&warning)
		codex_utils_absolute_path.AbsolutePathBuf{ path: fallback_cwd.clone() }
	}
	cwd := cwd_path.path
	history := stored_thread.history
	thread_id := stored_thread.thread_id.str()
	source := with_thread_spawn_agent_metadata(stored_thread.source, clone_optional_string(stored_thread.agent_nickname), clone_optional_string(stored_thread.agent_role))
	mut section := ?api.ThreadSection(none)
	if source_section := stored_thread.section {
		mut appearance_value := ?api.ThreadSectionAppearance(none)
		if appearance := source_section.appearance {
			appearance_value = api.ThreadSectionAppearance{
				icon:  appearance.icon
				color: appearance.color
			}
		}
		section = api.ThreadSection{
			id:         source_section.id
			name:       source_section.name
			appearance: appearance_value
		}
	}
	thread_value := api.Thread{
		id:                      thread_id.clone()
		environments:            api.OptionalThreadEnvironments{}
		extra:                   none
		session_id:              thread_id
		forked_from_id:          if id := stored_thread.forked_from_id { id.str() } else { none }
		parent_thread_id:        if id := stored_thread.parent_thread_id { id.str() } else { none }
		preview:                 stored_thread.preview
		ephemeral:               false
		section:                 section
		section_entered_at:      if entered_at := stored_thread.section_entered_at {
			?i64(entered_at / 1000)
		} else {
			none
		}
		project_id:              stored_thread.project_id
		history_mode:            stored_thread.history_mode
		model_provider:          if stored_thread.model_provider.len == 0 {
			fallback_provider.clone()
		} else {
			stored_thread.model_provider
		}
		model:                   stored_thread.model
		reasoning_effort:        stored_thread.reasoning_effort
		created_at:              stored_thread.created_at / 1000
		updated_at:              stored_thread.updated_at / 1000
		recency_at:              stored_thread.recency_at / 1000
		status:                  api.ThreadStatus{ kind: .not_loaded }
		path:                    path
		cwd:                     cwd
		cli_version:             stored_thread.cli_version
		originator:              stored_thread.originator
		agent_nickname:          source.get_nickname()
		agent_role:              source.get_agent_role()
		source:                  source
		can_accept_direct_input: none
		thread_source:           stored_thread.thread_source
		git_info:                git_info
		name:                    stored_thread.name
		daybreak_enabled:        stored_thread.daybreak_enabled
		turns:                   []api.Turn{}
	}
	return thread_value, history
}

fn summary_from_stored_thread(
	stored_thread store.StoredThread,
	fallback_provider &string
) api.ConversationSummary {
	source := with_thread_spawn_agent_metadata(stored_thread.source, clone_optional_string(stored_thread.agent_nickname), clone_optional_string(stored_thread.agent_role))
	mut git_info := ?api.ConversationGitInfo(none)
	if git := stored_thread.git_info {
		git_info = api.ConversationGitInfo{
			sha:        git.commit_hash
			branch:     git.branch
			origin_url: git.repository_url
		}
	}
	// Preserve millisecond precision from the thread store so thread/list cursors
	// round-trip the same ordering key used by pagination queries.
	timestamp := if stored_thread.created_at_rfc3339.len > 0 {
		stored_thread.created_at_rfc3339
	} else {
		time.unix_milli(stored_thread.created_at).format_rfc3339()
	}
	updated_at := if stored_thread.updated_at_rfc3339.len > 0 {
		stored_thread.updated_at_rfc3339
	} else {
		time.unix_milli(stored_thread.updated_at).format_rfc3339()
	}
	return api.ConversationSummary{
		conversation_id: stored_thread.thread_id.str()
		path:            stored_thread.rollout_path or { '' }
		preview:         stored_thread.preview
		timestamp:       timestamp
		updated_at:      updated_at
		model_provider:  if stored_thread.model_provider.len == 0 {
			fallback_provider.clone()
		} else {
			stored_thread.model_provider
		}
		cwd:             stored_thread.cwd
		cli_version:     stored_thread.cli_version
		source:          source
		git_info:        git_info
	}
}

fn summary_from_state_db_metadata(
	conversation_id codex_protocol.ThreadId,
	path string,
	first_user_message ?string,
	preview ?string,
	timestamp string,
	updated_at string,
	model_provider string,
	cwd string,
	cli_version string,
	source string,
	_thread_source ?codex_protocol.ThreadSource,
	agent_nickname ?string,
	agent_role ?string,
	git_sha ?string,
	git_branch ?string,
	git_origin_url ?string
) api.ConversationSummary {
	resolved_preview := preview or { first_user_message or { '' } }
	parsed_source := decode_state_db_session_source(&source)
	resolved_source := with_thread_spawn_agent_metadata(parsed_source, agent_nickname, agent_role)
	mut git_info := ?api.ConversationGitInfo(none)
	if git_sha != none || git_branch != none || git_origin_url != none {
		git_info = api.ConversationGitInfo{
			sha:        git_sha
			branch:     git_branch
			origin_url: git_origin_url
		}
	}
	return api.ConversationSummary{
		conversation_id: conversation_id.str()
		path:            path
		preview:         resolved_preview
		timestamp:       timestamp
		updated_at:      updated_at
		model_provider:  model_provider
		cwd:             cwd
		cli_version:     cli_version
		source:          resolved_source
		git_info:        git_info
	}
}

struct SerializedThreadSpawnSource {
	parent_thread_id string
	depth            i32
	agent_path       ?string
	agent_nickname   ?string
	agent_role       ?string
}

struct SerializedSubAgentSource {
	thread_spawn SerializedThreadSpawnSource
}

struct SerializedSessionSource {
	sub_agent SerializedSubAgentSource
}

fn decode_state_db_session_source(source &string) codex_protocol.SessionSource {
	if source.contains('"sub_agent"') && source.contains('"thread_spawn"') {
		decoded := json2.decode[SerializedSessionSource](*source) or {
			return codex_protocol.SessionSource{ source_kind: .unknown }
		}
		return codex_protocol.SessionSource{
			source_kind: .sub_agent
			sub_agent:   codex_protocol.SubAgentSource{
				source_kind:      .thread_spawn
				parent_thread_id: if decoded.sub_agent.thread_spawn.parent_thread_id.len > 0 {
					codex_protocol.ThreadId{
						value: decoded.sub_agent.thread_spawn.parent_thread_id.clone()
					}
				} else {
					none
				}
				depth:            decoded.sub_agent.thread_spawn.depth
				agent_path:       if value := decoded.sub_agent.thread_spawn.agent_path {
					codex_protocol.AgentPath{ value: value.clone() }
				} else {
					none
				}
				agent_nickname:   clone_optional_string(decoded.sub_agent.thread_spawn.agent_nickname)
				agent_role:       clone_optional_string(decoded.sub_agent.thread_spawn.agent_role)
			}
		}
	}
	plain_source := source.trim('"')
	return codex_protocol.session_source_from_startup_arg(&plain_source) or {
		codex_protocol.SessionSource{ source_kind: .unknown }
	}
}

fn summary_from_thread_metadata(metadata &ThreadMetadata) api.ConversationSummary {
	return summary_from_state_db_metadata(codex_protocol.ThreadId{
		value: metadata.id.value.clone()
	}, metadata.rollout_path.clone(), clone_optional_string(metadata.first_user_message), clone_optional_string(metadata.preview), truncate_rfc3339_to_seconds(&metadata.created_at), truncate_rfc3339_to_seconds(&metadata.updated_at), metadata.model_provider.clone(), metadata.cwd.clone(), metadata.cli_version.clone(), metadata.source.clone(), clone_optional_thread_source(metadata.thread_source), clone_optional_string(metadata.agent_nickname), clone_optional_string(metadata.agent_role), clone_optional_string(metadata.git_sha), clone_optional_string(metadata.git_branch), clone_optional_string(metadata.git_origin_url))
}

fn clone_optional_string(value ?string) ?string {
	if unwrapped := value {
		return unwrapped.clone()
	}
	return none
}

fn clone_optional_thread_source(
	value ?codex_protocol.ThreadSource
) ?codex_protocol.ThreadSource {
	if source := value {
		return codex_protocol.ThreadSource{
			source_kind: source.source_kind
			feature:     source.feature.clone()
		}
	}
	return none
}

fn truncate_rfc3339_to_seconds(value &string) string {
	parsed := time.parse_rfc3339(*value) or { return value.clone() }
	return parsed.format_ss().replace(' ', 'T') + 'Z'
}

fn preview_from_rollout_items(items &[]store.RolloutItem) string {
	for item in *items {
		if item.kind == .user_message {
			return codex_protocol.strip_user_message_prefix(&item.message)
		}
	}
	return ''
}

fn build_thread_from_snapshot(
	thread_id codex_protocol.ThreadId,
	session_id string,
	multi_agent_version ?codex_protocol.MultiAgentVersion,
	config_snapshot &ThreadConfigSnapshot,
	path ?string
) api.Thread {
	now := time.now().unix()
	environment_selections := config_snapshot.environment_selections()
	mut environments := []api.ThreadEnvironment{cap: environment_selections.len}
	for selection in environment_selections {
		environments << api.ThreadEnvironment{
			environment_id:          selection.environment_id.clone()
			cwd:                     selection.cwd.path.clone()
			runtime_workspace_roots: selection.workspace_roots.map(it.path.clone())
		}
	}
	return api.Thread{
		id:                      thread_id.str()
		environments:            api.OptionalThreadEnvironments{ has_value: true, value: environments }
		extra:                   none
		session_id:              session_id
		forked_from_id:          none
		parent_thread_id:        if id := config_snapshot.parent_thread_id {
			id.str()
		} else {
			none
		}
		preview:                 ''
		ephemeral:               config_snapshot.ephemeral
		section:                 none
		section_entered_at:      none
		project_id:              none
		history_mode:            config_snapshot.history_mode
		model_provider:          config_snapshot.model_provider_id.clone()
		model:                   config_snapshot.model.clone()
		reasoning_effort:        config_snapshot.reasoning_effort
		created_at:              now
		updated_at:              now
		recency_at:              now
		status:                  api.ThreadStatus{ kind: .not_loaded }
		path:                    path
		cwd:                     config_snapshot.cwd()
		cli_version:             '0.0.1'
		originator:              if config_snapshot.originator.len > 0 {
			config_snapshot.originator.clone()
		} else {
			none
		}
		source:                  codex_protocol.clone_session_source(&config_snapshot.session_source)
		agent_nickname:          config_snapshot.session_source.get_nickname()
		agent_role:              config_snapshot.session_source.get_agent_role()
		can_accept_direct_input: can_accept_direct_input(multi_agent_version, &config_snapshot.session_source)
		thread_source:           clone_optional_thread_source(config_snapshot.thread_source)
		git_info:                none
		name:                    none
		daybreak_enabled:        none
		turns:                   []api.Turn{}
	}
}

pub fn paginate_background_terminals(
	terminals &[]api.ThreadBackgroundTerminal,
	cursor ?string,
	limit ?u32
) !([]api.ThreadBackgroundTerminal, ?string) {
	mut start := 0
	if cursor_value := cursor {
		cursor_number := parse_i32_strict(&cursor_value) or {
			return fail(invalid_request('invalid cursor: ${err}'))
		}
		start = terminals.len
		for index, terminal in *terminals {
			process_id := parse_i32_strict(&terminal.process_id) or { continue }
			if process_id > cursor_number {
				start = index
				break
			}
		}
	}
	requested_limit := int(limit or { u32(terminals.len) })
	effective_limit := if requested_limit < 1 { 1 } else { requested_limit }
	page_end := start + effective_limit
	end := if page_end < terminals.len { page_end } else { terminals.len }
	mut data := []api.ThreadBackgroundTerminal{cap: end - start}
	for index, terminal in *terminals {
		if index >= start && index < end {
			data << clone_terminal(&terminal)
		}
	}
	mut next_cursor := ?string(none)
	if end < terminals.len && data.len > 0 {
		next_cursor = data.last().process_id.clone()
	}
	return data, next_cursor
}

fn parse_i32_strict(value &string) !int {
	source := *value
	if source.len == 0 {
		return error('empty integer')
	}
	mut start := 0
	if source[0] == `-` {
		if source.len == 1 {
			return error('invalid integer `${*value}`')
		}
		start = 1
	}
	for index in start .. source.len {
		if source[index] < `0` || source[index] > `9` {
			return error('invalid integer `${*value}`')
		}
	}
	parsed := value.i64()
	if parsed < -2147483648 || parsed > 2147483647 {
		return error('integer out of range `${*value}`')
	}
	return int(parsed)
}

fn clone_terminal(terminal &api.ThreadBackgroundTerminal) api.ThreadBackgroundTerminal {
	return api.ThreadBackgroundTerminal{
		item_id:     terminal.item_id.clone()
		process_id:  terminal.process_id.clone()
		command:     terminal.command.clone()
		cwd:         terminal.cwd.clone()
		os_pid:      terminal.os_pid
		cpu_percent: terminal.cpu_percent
		rss_kb:      terminal.rss_kb
	}
}

fn build_thread_from_loaded_snapshot(
	thread_id codex_protocol.ThreadId,
	config_snapshot &ThreadConfigSnapshot,
	loaded_thread &CodexThread
) api.Thread {
	session_configured := loaded_thread.session_configured()
	return build_thread_from_snapshot(thread_id, session_configured.session_id, loaded_thread.multi_agent_version(), config_snapshot, loaded_thread.rollout_path())
}
