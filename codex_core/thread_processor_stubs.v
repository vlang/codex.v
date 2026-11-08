module codex_core

import codex_app_server_protocol as api
import codex_config
import codex_config.types as settings_types
import codex_core.config as core_config
import codex_extension_api
import codex_features
import codex_login
import codex_protocol
import codex_protocol.config_types
import codex_rollout
import codex_state
import codex_state.sqlite
import codex_thread_store

// STUB: CodexErrKind models codex-core/error's payload-bearing error details.
pub enum CodexErrKind {
	thread_not_found
	invalid_request
	unsupported_operation
	io
	json
	other
}

// STUB: CodexErr is owned by codex-core/error.
pub struct CodexErr {
pub:
	kind      CodexErrKind
	message   string
	thread_id string
}

// STUB: CodexOperationResult preserves a typed codex-core error for operations without a value.
pub struct CodexOperationResult {
pub:
	is_error    bool
	error_value CodexErr
}

// STUB: RemoveThreadResult preserves both the optional detached thread and typed core failures.
pub struct RemoveThreadResult {
pub:
	is_error    bool
	value       OptionalCodexThread
	error_value CodexErr
}

// STUB: UpdateThreadMetadataResult preserves the updated stored row and typed core failures.
pub struct UpdateThreadMetadataResult {
pub:
	is_error    bool
	value       codex_thread_store.StoredThread
	error_value CodexErr
}

// STUB: ElicitationCountResult preserves the counter value and typed core failures.
pub struct ElicitationCountResult {
pub:
	is_error    bool
	value       u32
	error_value CodexErr
}

// STUB: ResumeThreadResult preserves the typed codex-core error returned by
// `ThreadManager::resume_thread_with_history`.
pub struct ResumeThreadResult {
pub:
	is_error    bool
	value       NewThread
	error_value CodexErr
}

// STUB: LoadHistoryResult preserves the typed codex-thread-store failure returned through a live
// CodexThread history read.
pub struct LoadHistoryResult {
pub:
	is_error    bool
	value       codex_thread_store.StoredThreadHistory
	error_value codex_thread_store.ThreadStoreError
}

// STUB: ConfigPermissions is the resolved permissions section owned by codex-core/config.
pub struct ConfigPermissions {
pub:
	effective_profile codex_protocol.PermissionProfile
	// STUB: selected named-profile metadata from resolved ConfigPermissions.
	active_profile        ?codex_protocol.ActivePermissionProfile
	windows_sandbox_level config_types.WindowsSandboxLevel
}

// STUB: returns the permission profile after managed constraints have been applied.
pub fn (permissions &ConfigPermissions) effective_permission_profile() codex_protocol.PermissionProfile {
	return clone_permission_profile(&permissions.effective_profile)
}

// STUB: clones the resolved permission section at config clone boundaries.
pub fn clone_config_permissions(permissions &ConfigPermissions) ConfigPermissions {
	return ConfigPermissions{
		effective_profile:     clone_permission_profile(&permissions.effective_profile)
		active_profile:        permissions.active_permission_profile()
		windows_sandbox_level: permissions.windows_sandbox_level
	}
}

// STUB: clones the protocol permission profile retained by ConfigPermissions.
pub fn clone_permission_profile(profile &codex_protocol.PermissionProfile) codex_protocol.PermissionProfile {
	return codex_protocol.PermissionProfile(profile.clone())
}

// STUB: TrustLevel is owned by codex-core/config.
pub enum TrustLevel {
	trusted
	untrusted
}

// STUB: ActiveProject is the project selected by layered configuration.
pub struct ActiveProject {
pub:
	trust_level ?TrustLevel
}

// STUB: Config is owned by codex-core/config.
pub struct Config {
pub mut:
	// Effective service tier request id preference for new turns.
	// `default` means the user explicitly selected standard routing.
	service_tier ?string
	// STUB: current model selection consumed by managed new-thread defaults.
	model ?string
	// STUB: codex-core Config fields consumed by TUI startup update and visualization helpers.
	respect_system_proxy        bool
	check_for_update_on_startup bool = true
	developer_instructions      ?string
	model_provider_id           string
	// STUB: Daybreak's observed base URL and resolved local credential-reader seam.
	chatgpt_base_url       string
	resolved_auth_config   codex_login.AuthConfig
	codex_home             string
	sqlite                 sqlite.SqliteConfig
	cwd                    string
	workspace_roots        []string
	thread_unload_delay_ms u64
	ephemeral              bool
	features               codex_features.Features
	model_reasoning_effort ?codex_protocol.ReasoningEffortConfig
	permissions            ConfigPermissions
	active_project         ActiveProject
	config_layer_stack     []string
	// STUB: typed layer companion until the legacy stack stub is migrated.
	permission_config_layer_stack codex_config.ConfigLayerStack
	custom_permission_profiles    []PermissionProfileCatalogEntry
	// STUB: client-owned resolved preferences observed by tui/src/local_settings.rs.
	tui_notifications          settings_types.TuiNotificationSettings
	animations                 bool = true
	tui_whimsy                 bool = true
	show_tooltips              bool = true
	tui_auto_recap             bool = true
	disable_paste_burst        bool
	tui_vim_mode_default       bool
	tui_question_esc_back      bool = true
	tui_raw_output_mode        bool
	tui_alternate_screen       config_types.AltScreenMode
	tui_status_line            ?[]string
	tui_status_line_use_colors bool = true
	tui_terminal_title         ?[]string
	tui_theme                  ?string
	tui_pet                    ?string
	tui_pet_anchor             settings_types.TuiPetAnchor
	tui_session_picker_view    settings_types.SessionPickerViewMode = .dense
	tui_resume_cwd             ?settings_types.ResumeCwdMode
	tui_keymap                 settings_types.TuiKeymap
	model_availability_nux     settings_types.ModelAvailabilityNuxConfig
	terminal_resize_reflow     core_config.TerminalResizeReflowConfig
	history                    settings_types.History
	notices                    settings_types.Notice
}

// STUB: Config cloning belongs to codex-core/config; this helper exposes the cwd reload boundary.
pub fn clone_config_with_cwd(config &Config, cwd string) Config {
	return Config{
		service_tier:                  if tier := config.service_tier { tier.clone() } else { none }
		model:                         if model := config.model { model.clone() } else { none }
		respect_system_proxy:          config.respect_system_proxy
		check_for_update_on_startup:   config.check_for_update_on_startup
		developer_instructions:        if instructions := config.developer_instructions {
			instructions.clone()
		} else {
			none
		}
		model_provider_id:             config.model_provider_id.clone()
		chatgpt_base_url:              config.chatgpt_base_url.clone()
		resolved_auth_config:          config.resolved_auth_config.clone()
		codex_home:                    config.codex_home.clone()
		sqlite:                        config.sqlite.clone()
		cwd:                           cwd
		workspace_roots:               config.workspace_roots.clone()
		thread_unload_delay_ms:        config.thread_unload_delay_ms
		ephemeral:                     config.ephemeral
		features:                      config.features
		model_reasoning_effort:        config.model_reasoning_effort
		permissions:                   clone_config_permissions(&config.permissions)
		active_project:                config.active_project
		config_layer_stack:            config.config_layer_stack.clone()
		permission_config_layer_stack: config.permission_config_layer_stack.clone()
		custom_permission_profiles:    clone_custom_permission_profiles(&config.custom_permission_profiles)
		tui_notifications:             config.tui_notifications.clone()
		animations:                    config.animations
		tui_whimsy:                    config.tui_whimsy
		show_tooltips:                 config.show_tooltips
		tui_auto_recap:                config.tui_auto_recap
		disable_paste_burst:           config.disable_paste_burst
		tui_vim_mode_default:          config.tui_vim_mode_default
		tui_question_esc_back:         config.tui_question_esc_back
		tui_raw_output_mode:           config.tui_raw_output_mode
		tui_alternate_screen:          config.tui_alternate_screen
		tui_status_line:               if value := config.tui_status_line {
			value.clone()
		} else {
			none
		}
		tui_status_line_use_colors:    config.tui_status_line_use_colors
		tui_terminal_title:            if value := config.tui_terminal_title {
			value.clone()
		} else {
			none
		}
		tui_theme:                     if value := config.tui_theme { value.clone() } else { none }
		tui_pet:                       if value := config.tui_pet { value.clone() } else { none }
		tui_pet_anchor:                config.tui_pet_anchor
		tui_session_picker_view:       config.tui_session_picker_view
		tui_resume_cwd:                config.tui_resume_cwd
		tui_keymap:                    config.tui_keymap.clone()
		model_availability_nux:        config.model_availability_nux.clone()
		terminal_resize_reflow:        config.terminal_resize_reflow
		history:                       config.history.clone()
		notices:                       config.notices.clone()
	}
}

// STUB: clones a runtime Config returned across the untranslated async lock boundary.
fn clone_core_config(config &Config) Config {
	return Config{
		service_tier:                  if tier := config.service_tier { tier.clone() } else { none }
		model:                         if model := config.model { model.clone() } else { none }
		respect_system_proxy:          config.respect_system_proxy
		check_for_update_on_startup:   config.check_for_update_on_startup
		developer_instructions:        if instructions := config.developer_instructions {
			instructions.clone()
		} else {
			none
		}
		model_provider_id:             config.model_provider_id.clone()
		chatgpt_base_url:              config.chatgpt_base_url.clone()
		resolved_auth_config:          config.resolved_auth_config.clone()
		codex_home:                    config.codex_home.clone()
		sqlite:                        config.sqlite.clone()
		cwd:                           config.cwd.clone()
		workspace_roots:               config.workspace_roots.clone()
		thread_unload_delay_ms:        config.thread_unload_delay_ms
		ephemeral:                     config.ephemeral
		features:                      config.features
		model_reasoning_effort:        config.model_reasoning_effort
		permissions:                   clone_config_permissions(&config.permissions)
		active_project:                config.active_project
		config_layer_stack:            config.config_layer_stack.clone()
		permission_config_layer_stack: config.permission_config_layer_stack.clone()
		custom_permission_profiles:    clone_custom_permission_profiles(&config.custom_permission_profiles)
		tui_notifications:             config.tui_notifications.clone()
		animations:                    config.animations
		tui_whimsy:                    config.tui_whimsy
		show_tooltips:                 config.show_tooltips
		tui_auto_recap:                config.tui_auto_recap
		disable_paste_burst:           config.disable_paste_burst
		tui_vim_mode_default:          config.tui_vim_mode_default
		tui_question_esc_back:         config.tui_question_esc_back
		tui_raw_output_mode:           config.tui_raw_output_mode
		tui_alternate_screen:          config.tui_alternate_screen
		tui_status_line:               if value := config.tui_status_line {
			value.clone()
		} else {
			none
		}
		tui_status_line_use_colors:    config.tui_status_line_use_colors
		tui_terminal_title:            if value := config.tui_terminal_title {
			value.clone()
		} else {
			none
		}
		tui_theme:                     if value := config.tui_theme { value.clone() } else { none }
		tui_pet:                       if value := config.tui_pet { value.clone() } else { none }
		tui_pet_anchor:                config.tui_pet_anchor
		tui_session_picker_view:       config.tui_session_picker_view
		tui_resume_cwd:                config.tui_resume_cwd
		tui_keymap:                    config.tui_keymap.clone()
		model_availability_nux:        config.model_availability_nux.clone()
		terminal_resize_reflow:        config.terminal_resize_reflow
		history:                       config.history.clone()
		notices:                       config.notices.clone()
	}
}

// STUB: codex-core/windows_sandbox::WindowsSandboxLevelExt::from_config resolves the persisted
// Windows sandbox launch mode from Config.
pub fn windows_sandbox_level_from_config(config &Config) config_types.WindowsSandboxLevel {
	return config.permissions.windows_sandbox_level
}

// STUB: resolves the root checkout whose trust setting governs this cwd.
pub fn resolve_root_git_project_for_trust(cwd &string) ?string {
	_ = cwd
	return none
}

// STUB: persists a project trust level in the user's Codex configuration.
pub fn set_project_trust_level(codex_home &string, project_path &string, trust_level TrustLevel) ! {
	_ = codex_home
	_ = project_path
	_ = trust_level
}

// STUB: ExecPolicyError is owned by codex-core/exec_policy.rs.
pub struct ExecPolicyError {
pub:
	message string
}

// STUB: OptionalExecPolicyError preserves a successful warning check with no warning.
pub struct OptionalExecPolicyError {
pub:
	has_value bool
	value     ExecPolicyError
}

// STUB: checks the resolved config layer stack for exec-policy warnings.
pub fn check_execpolicy_for_warnings(config_layer_stack &[]string) !OptionalExecPolicyError {
	_ = config_layer_stack
	return OptionalExecPolicyError{}
}

// STUB: ConfigOverrides is owned by codex-core/config.
pub struct ConfigOverrides {
pub mut:
	model                           ?string
	model_provider                  ?string
	service_tier                    api.ClearableString
	cwd                             ?string
	workspace_roots                 ?[]string
	permission_profile              ?codex_protocol.PermissionProfile
	default_permissions             ?string
	approval_policy                 ?api.AskForApproval
	approvals_reviewer              ?api.ApprovalsReviewer
	sandbox_mode                    ?api.SandboxMode
	persisted_permission_profile_id ?string
	codex_linux_sandbox_exe         string
	main_execve_wrapper_exe         string
	base_instructions               ?string
	developer_instructions          ?string
	personality                     ?codex_protocol.Personality
	ephemeral                       ?bool
}

// STUB: ThreadConfigSnapshot is owned by codex-core.
pub struct ThreadConfigSnapshot {
pub:
	model                     string
	model_provider_id         string
	service_tier              ?string
	cwd                       string
	workspace_roots           []string
	approval_policy           api.AskForApproval
	approvals_reviewer        api.ApprovalsReviewer
	permission_profile        codex_protocol.PermissionProfile
	full_access               bool
	active_permission_profile ?codex_protocol.ActivePermissionProfile
	personality               ?codex_protocol.Personality
	ephemeral                 bool
	history_mode              api.ThreadHistoryMode
	parent_thread_id          ?codex_protocol.ThreadId
	session_source            codex_protocol.SessionSource
	thread_source             ?codex_protocol.ThreadSource
	originator                string
	reasoning_effort          ?codex_protocol.ReasoningEffortConfig
	environment_selections    []codex_protocol.TurnEnvironmentSelection
}

// STUB: returns the effective sandbox policy from a live config snapshot.
pub fn (snapshot &ThreadConfigSnapshot) sandbox_policy() codex_protocol.SandboxPolicy {
	return match snapshot.permission_profile.enforcement {
		.external {
			codex_protocol.SandboxPolicy{
				policy_kind:             .external_sandbox
				external_network_access: if snapshot.permission_profile.network.kind == 'enabled' {
					codex_protocol.NetworkAccess.enabled
				} else {
					codex_protocol.NetworkAccess.restricted
				}
			}
		}
		.none {
			codex_protocol.SandboxPolicy{ policy_kind: .danger_full_access }
		}
		.legacy {
			if snapshot.permission_profile.file_system.kind == 'unrestricted' {
				codex_protocol.SandboxPolicy{ policy_kind: .danger_full_access }
			} else {
				codex_protocol.SandboxPolicy{
					policy_kind:    .workspace_write
					network_access: snapshot.permission_profile.network.kind == 'enabled'
				}
			}
		}
	}
}

// STUB: returns an owned cwd at the V boundary where Rust borrows the snapshot path.
pub fn (snapshot &ThreadConfigSnapshot) cwd() string {
	return snapshot.cwd.clone()
}

// STUB: returns the current ordered environment selections.
pub fn (snapshot &ThreadConfigSnapshot) environment_selections() []codex_protocol.TurnEnvironmentSelection {
	return snapshot.environment_selections.clone()
}

// STUB: CodexThreadSettingsOverrides is owned by codex-core and is captured for revert reloads.
pub struct CodexThreadSettingsOverrides {}

// STUB: ThreadSettingsSnapshot is returned by CodexThread::thread_settings_snapshot.
pub struct ThreadSettingsSnapshot {
pub:
	approval_policy           api.AskForApproval
	approvals_reviewer        api.ApprovalsReviewer
	active_permission_profile ?codex_protocol.ActivePermissionProfile
}

// STUB: SessionConfigured contains the durable runtime identity returned by a thread start.
pub struct SessionConfigured {
pub:
	session_id         string
	rollout_path       ?string
	model              string
	model_provider_id  string
	service_tier       ?string
	cwd                string
	approval_policy    api.AskForApproval
	approvals_reviewer api.ApprovalsReviewer
	reasoning_effort   ?codex_protocol.ReasoningEffortConfig
}

// STUB: StartThreadOptions is owned by codex-core/thread_manager.rs. The fields preserve every
// option assembled by thread_processor.rs before the manager takes ownership.
pub struct StartThreadOptions {
pub:
	config                        Config
	allow_provider_model_fallback bool
	initial_history               codex_rollout.InitialHistory
	history_mode                  ?api.ThreadHistoryMode
	thread_source                 ?codex_protocol.ThreadSource
	dynamic_tools                 []api.DynamicToolSpec
	metrics_service_name          ?string
	parent_trace                  ?codex_protocol.W3cTraceContext
	environments                  ?[]codex_protocol.TurnEnvironmentSelection
	thread_extension_init         codex_extension_api.ExtensionDataInit
	client_mcp_extensions         codex_protocol.ClientMcpExtensions
	reserved_thread_id            ?codex_protocol.ThreadId
}

// STUB: NewThread is the exact manager result observed by app-server lifecycle handlers.
pub struct NewThread {
pub:
	thread_id          codex_protocol.ThreadId
	thread             CodexThread
	session_configured SessionConfigured
}

// STUB: StartThreadResultKind adapts Rust's typed `CodexResult<NewThread>` for V.
pub enum StartThreadResultKind {
	ok
	error
}

// STUB: StartThreadResult preserves the core error details inspected by app-server.
pub struct StartThreadResult {
pub:
	kind        StartThreadResultKind
	value       NewThread
	error_value CodexErr
}

// STUB: ForkSnapshot is owned by codex-core/thread_manager.rs. The thread processor uses the
// interrupted persisted-history snapshot mode.
pub enum ForkSnapshot {
	interrupted
}

// STUB: CodexThread is owned by codex-core. Only observations and operation boundaries used by
// thread_processor.rs are exposed.
pub struct CodexThread {
pub:
	id                    codex_protocol.ThreadId
	config                Config
	config_snapshot       ThreadConfigSnapshot
	settings              CodexThreadSettingsOverrides
	client_mcp_extensions codex_protocol.ClientMcpExtensions
	background_terminals  []api.ThreadBackgroundTerminal
	session_id            string
	rollout_path          ?string
	multi_agent_version   ?codex_protocol.MultiAgentVersion
	direct_input_enabled  bool = true
	local_environment     bool = true
	agent_running         bool
	shutdown_result       ThreadShutdownResult
	elicitation_count     u32
	history_items         []codex_thread_store.RolloutItem
	state_db              ?codex_state.StateDbHandle
}

// STUB: snapshots the live thread configuration.
pub fn (thread_value &CodexThread) config_snapshot() ThreadConfigSnapshot {
	return clone_thread_config_snapshot(&thread_value.config_snapshot)
}

// STUB: snapshots live approval/reviewer/profile settings for a paginated fork.
pub fn (thread_value &CodexThread) thread_settings_snapshot() ThreadSettingsSnapshot {
	return ThreadSettingsSnapshot{
		approval_policy:           thread_value.config_snapshot.approval_policy
		approvals_reviewer:        thread_value.config_snapshot.approvals_reviewer
		active_permission_profile: codex_protocol.clone_optional_active_permission_profile(thread_value.config_snapshot.active_permission_profile)
	}
}

// STUB: returns the current multi-agent protocol version for the live thread.
pub fn (thread_value &CodexThread) multi_agent_version() ?codex_protocol.MultiAgentVersion {
	return thread_value.multi_agent_version
}

// STUB: returns the materialized rollout path, if this live thread has one.
pub fn (thread_value &CodexThread) rollout_path() ?string {
	return clone_optional_core_string(thread_value.rollout_path)
}

// STUB: returns the latest session-configured event snapshot.
pub fn (thread_value &CodexThread) session_configured() SessionConfigured {
	return SessionConfigured{
		session_id:         thread_value.session_id.clone()
		rollout_path:       clone_optional_core_string(thread_value.rollout_path)
		model:              thread_value.config_snapshot.model.clone()
		model_provider_id:  thread_value.config_snapshot.model_provider_id.clone()
		service_tier:       clone_optional_core_string(thread_value.config_snapshot.service_tier)
		cwd:                thread_value.config_snapshot.cwd.clone()
		approval_policy:    thread_value.config_snapshot.approval_policy
		approvals_reviewer: thread_value.config_snapshot.approvals_reviewer
		reasoning_effort:   thread_value.config_snapshot.reasoning_effort
	}
}

// STUB: returns the current runtime Config behind the live thread lock.
pub fn (thread_value &CodexThread) config() Config {
	return clone_core_config(&thread_value.config)
}

// STUB: returns the client MCP extension set captured at thread creation.
pub fn (thread_value &CodexThread) client_mcp_extensions() codex_protocol.ClientMcpExtensions {
	return thread_value.client_mcp_extensions
}

// STUB: returns the state database used by the live thread runtime.
pub fn (thread_value &CodexThread) state_db() ?codex_state.StateDbHandle {
	return thread_value.state_db
}

// STUB: clones the core snapshot returned across the untranslated async lock boundary.
fn clone_thread_config_snapshot(snapshot &ThreadConfigSnapshot) ThreadConfigSnapshot {
	return ThreadConfigSnapshot{
		model:                     snapshot.model.clone()
		model_provider_id:         snapshot.model_provider_id.clone()
		service_tier:              clone_optional_core_string(snapshot.service_tier)
		cwd:                       snapshot.cwd.clone()
		workspace_roots:           snapshot.workspace_roots.clone()
		approval_policy:           snapshot.approval_policy
		approvals_reviewer:        snapshot.approvals_reviewer
		permission_profile:        clone_permission_profile(&snapshot.permission_profile)
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

// STUB: clones an optional string owned by core snapshot fields.
fn clone_optional_core_string(value ?string) ?string {
	if item := value {
		return item.clone()
	}
	return none
}

// STUB: clones the optional analytics thread-source enum at a core snapshot boundary.
fn clone_optional_thread_source(value ?codex_protocol.ThreadSource) ?codex_protocol.ThreadSource {
	if source := value {
		return codex_protocol.ThreadSource{
			source_kind: source.source_kind
			feature:     source.feature.clone()
		}
	}
	return none
}

// STUB: AgentStatus is owned by codex-core and returned by the live thread status channel.
pub enum AgentStatus {
	pending_init
	running
	interrupted
	completed
	errored
	shutdown
	not_found
}

// STUB: BackgroundTerminalInfo is owned by codex-core/codex_thread.rs.
pub struct BackgroundTerminalInfo {
pub:
	item_id    string
	process_id string
	command    string
	cwd        string
}

// STUB: ThreadShutdownResult is produced by codex-core bounded shutdown.
pub enum ThreadShutdownResult {
	complete
	submit_failed
	timed_out
}

// STUB: OptionalCodexThread retains the removed/not-loaded distinction.
pub struct OptionalCodexThread {
pub:
	has_value bool
	value     CodexThread
}

// STUB: ThreadShutdownReport is returned by ThreadManager::shutdown_all_threads_bounded.
pub struct ThreadShutdownReport {
pub:
	submit_failed []codex_protocol.ThreadId
	timed_out     []codex_protocol.ThreadId
}

// STUB: ThreadCreatedReceiver preserves broadcast receiver semantics.
pub struct ThreadCreatedReceiver {
pub:
	manager &ThreadManager = unsafe { nil }
}

// STUB: subscribes to future thread-created broadcasts.
pub fn (manager &ThreadManager) subscribe_thread_created() ThreadCreatedReceiver {
	return ThreadCreatedReceiver{ manager: manager }
}

// STUB: ThreadManager is owned by codex-core/thread_manager.rs.
@[heap]
pub struct ThreadManager {
pub:
	loaded_thread_ids           []codex_protocol.ThreadId
	threads                     []CodexThread
	local_environment_available bool = true
}

// STUB: EnvironmentManager is owned by codex-core/environment.rs.
pub struct EnvironmentManager {
pub:
	local_environment_available bool
}

// STUB: LocalEnvironment is the configured local-host execution environment.
pub struct LocalEnvironment {}

// STUB: returns the environment manager associated with this thread manager.
pub fn (manager &ThreadManager) environment_manager() EnvironmentManager {
	return EnvironmentManager{ local_environment_available: manager.local_environment_available }
}

// STUB: returns the configured local environment, when host execution is available.
pub fn (manager &EnvironmentManager) try_local_environment() ?LocalEnvironment {
	if manager.local_environment_available {
		return LocalEnvironment{}
	}
	return none
}

// STUB: ThreadManager reserves a fresh persistent id before store metadata staging.
pub fn (manager &ThreadManager) reserve_thread_id() codex_protocol.ThreadId {
	return codex_protocol.ThreadId{ value: 'reserved-${manager.loaded_thread_ids.len + 1}' }
}

// STUB: ThreadManager resolves the configured default environment selection for a workspace.
pub fn (manager &ThreadManager) default_environment_selections(cwd &string, workspace_roots &[]string) []codex_protocol.TurnEnvironmentSelection {
	_ = manager
	_ = cwd
	_ = workspace_roots
	return []codex_protocol.TurnEnvironmentSelection{}
}

// STUB: validates environment selections against the configured environment manager.
pub fn (manager &ThreadManager) validate_environment_selections(selections &[]codex_protocol.TurnEnvironmentSelection) ! {
	_ = manager
	_ = selections
}

// STUB: ensures that a parent-owned multi-agent V2 child has been loaded through its owner.
pub fn (manager &ThreadManager) ensure_multi_agent_v2_child_loaded(thread_id codex_protocol.ThreadId) ! {
	_ = manager
	_ = thread_id
	return error('multi-agent child loading requires translated ThreadManager')
}

// STUB: ThreadManager owns thread creation and registration.
pub fn (manager &ThreadManager) start_thread(options StartThreadOptions) StartThreadResult {
	_ = manager
	_ = options
	return StartThreadResult{
		kind:        .error
		error_value: CodexErr{
			kind:    .other
			message: 'start thread requires translated ThreadManager'
		}
	}
}

// STUB: ThreadManager reopens a thread from persisted model context.
pub fn (manager &ThreadManager) resume_thread_with_history(config Config, history codex_rollout.InitialHistory, auth_manager codex_login.AuthManager, parent_trace ?codex_protocol.W3cTraceContext, client_mcp_extensions codex_protocol.ClientMcpExtensions) ResumeThreadResult {
	_ = manager
	_ = config
	_ = history
	_ = auth_manager
	_ = parent_trace
	_ = client_mcp_extensions
	return ResumeThreadResult{
		is_error:    true
		error_value: CodexErr{
			kind:    .other
			message: 'resume thread requires translated ThreadManager'
		}
	}
}

// STUB: ThreadManager creates a fork from a truncated legacy history.
pub fn (manager &ThreadManager) fork_thread_from_history(snapshot ForkSnapshot, config Config, history codex_rollout.InitialHistory, thread_source ?codex_protocol.ThreadSource, parent_trace ?codex_protocol.W3cTraceContext, client_mcp_extensions codex_protocol.ClientMcpExtensions, reserved_thread_id ?codex_protocol.ThreadId) StartThreadResult {
	_ = manager
	_ = snapshot
	_ = config
	_ = history
	_ = thread_source
	_ = parent_trace
	_ = client_mcp_extensions
	_ = reserved_thread_id
	return StartThreadResult{
		kind:        .error
		error_value: CodexErr{
			kind:    .other
			message: 'fork thread requires translated ThreadManager'
		}
	}
}

// STUB: ThreadManager creates a fork from a store-prepared paginated fork plan.
pub fn (manager &ThreadManager) fork_prepared_thread(config Config, prepared_fork codex_thread_store.PreparedFork, thread_source ?codex_protocol.ThreadSource, parent_trace ?codex_protocol.W3cTraceContext, client_mcp_extensions codex_protocol.ClientMcpExtensions, reserved_thread_id ?codex_protocol.ThreadId) StartThreadResult {
	_ = manager
	_ = config
	_ = prepared_fork
	_ = thread_source
	_ = parent_trace
	_ = client_mcp_extensions
	_ = reserved_thread_id
	return StartThreadResult{
		kind:        .error
		error_value: CodexErr{
			kind:    .other
			message: 'prepared fork requires translated ThreadManager'
		}
	}
}

// STUB: truncate_rollout_after_turn_id is owned by codex-core rollout truncation.
pub fn truncate_rollout_after_turn_id(items []codex_thread_store.RolloutItem, turn_id &string) ![]codex_thread_store.RolloutItem {
	_ = items
	_ = turn_id
	return error('rollout truncation requires translated codex-core')
}

// STUB: truncate_rollout_before_turn_id is owned by codex-core rollout truncation.
pub fn truncate_rollout_before_turn_id(items []codex_thread_store.RolloutItem, turn_id &string) ![]codex_thread_store.RolloutItem {
	_ = items
	_ = turn_id
	return error('rollout truncation requires translated codex-core')
}

// STUB: ThreadManager returns the live thread handle for an id.
pub fn (manager &ThreadManager) get_thread(thread_id &codex_protocol.ThreadId) !CodexThread {
	for thread_value in manager.threads {
		if thread_value.id.value == thread_id.value {
			return thread_value
		}
	}
	return error('thread not found: ${thread_id.value}')
}

// STUB: ThreadManager snapshots the ids of all currently loaded threads.
pub fn (manager &ThreadManager) list_thread_ids() []codex_protocol.ThreadId {
	mut ids := []codex_protocol.ThreadId{cap: manager.loaded_thread_ids.len}
	for thread_id in manager.loaded_thread_ids {
		ids << codex_protocol.ThreadId{ value: thread_id.value.clone() }
	}
	return ids
}

// STUB: ThreadManager atomically detaches a thread for a client mutation.
pub fn (manager &ThreadManager) remove_thread(thread_id &codex_protocol.ThreadId) RemoveThreadResult {
	thread_value := manager.get_thread(thread_id) or {
		return RemoveThreadResult{ value: OptionalCodexThread{} }
	}
	return RemoveThreadResult{ value: OptionalCodexThread{ has_value: true, value: thread_value } }
}

// STUB: ThreadManager::remove_thread_for_client removes a loaded thread before archive/delete and
// returns the runtime that still needs a bounded shutdown.
pub fn (manager &ThreadManager) remove_thread_for_client(thread_id &codex_protocol.ThreadId) RemoveThreadResult {
	return manager.remove_thread(thread_id)
}

// STUB: ThreadManager lists the root followed by its spawned descendants.
pub fn (manager &ThreadManager) list_agent_subtree_thread_ids(thread_id codex_protocol.ThreadId) ![]codex_protocol.ThreadId {
	_ = manager
	return [thread_id]
}

// STUB: ThreadManager owns section mutation and its state-store transaction.
pub fn (manager &ThreadManager) move_thread_to_section(thread_id codex_protocol.ThreadId, section_id ?string, before_thread_id ?codex_protocol.ThreadId) CodexOperationResult {
	_ = manager
	_ = section_id
	_ = before_thread_id
	return CodexOperationResult{
		is_error:    true
		error_value: CodexErr{
			kind:      .other
			message:   'move thread to section requires translated ThreadManager'
			thread_id: thread_id.value
		}
	}
}

// STUB: ThreadManager coordinates durable and loaded-state metadata updates.
pub fn (manager &ThreadManager) update_thread_metadata(thread_id codex_protocol.ThreadId, patch codex_thread_store.StoredThreadMetadataUpdatePatch, include_archived bool) UpdateThreadMetadataResult {
	_ = manager
	_ = patch
	_ = include_archived
	return UpdateThreadMetadataResult{
		is_error:    true
		error_value: CodexErr{
			kind:      .other
			message:   'update thread metadata requires translated ThreadManager'
			thread_id: thread_id.value
		}
	}
}

// STUB: ThreadManager shuts down every loaded thread with a bounded wait.
pub fn (manager &ThreadManager) shutdown_all_threads_bounded(timeout_ms u64) ThreadShutdownReport {
	_ = manager
	_ = timeout_ms
	return ThreadShutdownReport{}
}

// STUB: CodexThread applies app-server client compatibility information.
pub fn (thread_value &CodexThread) set_app_server_client_info(client_name ?string, client_version ?string, auto_deny_elicitations bool) ! {
	_ = thread_value
	_ = client_name
	_ = client_version
	_ = auto_deny_elicitations
}

// STUB: CodexThread restores the live approval/sandbox settings captured before a revert reload.
pub fn (thread_value &CodexThread) restore_thread_settings(settings CodexThreadSettingsOverrides) ! {
	_ = thread_value
	_ = settings
	return error('restoring thread settings requires translated CodexThread')
}

// STUB: CodexThread increments its out-of-band elicitation counter.
pub fn (thread_value &CodexThread) increment_out_of_band_elicitation_count() ElicitationCountResult {
	return ElicitationCountResult{ value: thread_value.elicitation_count + 1 }
}

// STUB: CodexThread decrements its out-of-band elicitation counter.
pub fn (thread_value &CodexThread) decrement_out_of_band_elicitation_count() ElicitationCountResult {
	return ElicitationCountResult{
		value: if thread_value.elicitation_count > 0 {
			thread_value.elicitation_count - 1
		} else {
			0
		}
	}
}

// STUB: CodexThread submits one core op with the request's W3C parent trace.
pub fn (thread_value &CodexThread) submit_with_trace(op codex_protocol.Op, trace ?codex_protocol.W3cTraceContext) !string {
	_ = thread_value
	_ = op
	_ = trace
	return error('submit operation requires translated CodexThread')
}

// STUB: CodexThread loads its materialized legacy rollout history.
pub fn (thread_value &CodexThread) load_history(include_archived bool) LoadHistoryResult {
	_ = include_archived
	return LoadHistoryResult{
		value: codex_thread_store.StoredThreadHistory{ items: thread_value.history_items.clone() }
	}
}

// STUB: CodexThread snapshots the background terminals currently owned by its session.
pub fn (thread_value &CodexThread) list_background_terminals() []BackgroundTerminalInfo {
	mut terminals := []BackgroundTerminalInfo{cap: thread_value.background_terminals.len}
	for terminal in thread_value.background_terminals {
		terminals << BackgroundTerminalInfo{
			item_id:    terminal.item_id.clone()
			process_id: terminal.process_id.clone()
			command:    terminal.command.clone()
			cwd:        terminal.cwd.clone()
		}
	}
	return terminals
}

// STUB: CodexThread reads its current core agent status.
pub fn (thread_value &CodexThread) agent_status() AgentStatus {
	return if thread_value.agent_running { .running } else { .completed }
}

// STUB: CodexThread emits a lifecycle idle event after a successful resume when currently idle.
pub fn (thread_value &CodexThread) emit_thread_idle_lifecycle_if_idle(cause codex_extension_api.ThreadIdleCause) {
	_ = thread_value
	_ = cause
}

// STUB: CodexThread reports the legacy instruction source labels exposed in start responses.
pub fn (thread_value &CodexThread) legacy_instruction_sources() []string {
	_ = thread_value
	return []string{}
}

// STUB: SessionTelemetry is owned by codex-core telemetry and records startup phase timing.
pub struct SessionTelemetry {}

// STUB: CodexThread exposes the telemetry handle created for its session.
pub fn (thread_value &CodexThread) session_telemetry() SessionTelemetry {
	_ = thread_value
	return SessionTelemetry{}
}

// STUB: records one named thread-startup phase and its readiness outcome.
pub fn (telemetry &SessionTelemetry) record_startup_phase(phase &string, elapsed_ms i64, outcome ?string) {
	_ = telemetry
	_ = phase
	_ = elapsed_ms
	_ = outcome
}

// STUB: CodexThread terminates one background terminal and reports whether it existed.
pub fn (thread_value &CodexThread) terminate_background_terminal(process_id int) bool {
	for terminal in thread_value.background_terminals {
		if terminal.process_id == process_id.str() {
			return true
		}
	}
	return false
}

// STUB: CodexThread snapshots live approval/sandbox settings before a revert.
pub fn (thread_value &CodexThread) restorable_thread_settings() CodexThreadSettingsOverrides {
	return thread_value.settings
}
