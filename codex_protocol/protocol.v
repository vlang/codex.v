// Defines the protocol for a Codex session between a client and an agent.
//
// Uses a SQ (Submission Queue) / EQ (Event Queue) pattern to asynchronously communicate
// between user and agent.
module codex_protocol

import math
import os
import json
import x.json2
import tokio.sync.oneshot
import codex_extension_items.image_generation
import codex_protocol.account
import codex_protocol.approvals
import codex_protocol.capabilities
import codex_protocol.config_types
import codex_protocol.dynamic_tools
import codex_protocol.environment
import codex_protocol.items
import codex_protocol.legacy_events
import codex_protocol.mcp
import codex_protocol.memory_citation
import codex_protocol.models
import codex_protocol.num_format
import codex_protocol.openai_models
import codex_protocol.parse_command
import codex_protocol.permissions
import codex_protocol.plan_tool
import codex_protocol.realtime
import codex_protocol.request_permissions
import codex_protocol.request_user_input
import codex_protocol.turn_input
import codex_protocol.user_input
import codex_utils_absolute_path
import codex_utils_path_uri
import codex_utils_string

pub type AbsolutePathBuf = codex_utils_absolute_path.AbsolutePathBuf

pub type ActivePermissionProfile = models.ActivePermissionProfile

pub type AgentMessageDelivery = items.AgentMessageDelivery

pub type AgentMessageInputContent = models.AgentMessageInputContent

pub type ApplyPatchApprovalRequestEvent = approvals.ApplyPatchApprovalRequestEvent

pub type ApprovalsReviewer = config_types.ApprovalsReviewer

pub type AsyncUserInputQuestion = items.AsyncUserInputQuestion

pub type BaseInstructions = models.BaseInstructions

pub type CallToolResult = mcp.CallToolResult

pub type CollaborationMode = config_types.CollaborationMode

pub type ContentItem = models.ContentItem

pub type CyberAccessProgram = turn_input.CyberAccessProgram

pub type DynamicToolCallOutputContentItem = dynamic_tools.DynamicToolCallOutputContentItem

pub type DynamicToolCallRequest = dynamic_tools.DynamicToolCallRequest

pub type DynamicToolResponse = dynamic_tools.DynamicToolResponse

pub type DynamicToolSpec = dynamic_tools.DynamicToolSpec

pub type ElicitationAction = approvals.ElicitationAction

pub type ElicitationRequestEvent = approvals.ElicitationRequestEvent

pub type EnvironmentConfig = environment.EnvironmentConfig

pub type EnvironmentConfigState = environment.EnvironmentConfigState

pub type ExecApprovalRequestEvent = approvals.ExecApprovalRequestEvent

pub type ExecPolicyAmendment = approvals.ExecPolicyAmendment

pub type FileSystemSandboxPolicy = permissions.FileSystemSandboxPolicy

pub type FileSystemAccessMode = permissions.FileSystemAccessMode

pub type FileSystemPath = permissions.FileSystemPath

pub type FileSystemSandboxEntry = permissions.FileSystemSandboxEntry

pub type FileSystemSandboxKind = permissions.FileSystemSandboxKind

pub type FileSystemSpecialPath = permissions.FileSystemSpecialPath

pub type GuardianAssessmentAction = approvals.GuardianAssessmentAction

pub type GuardianAssessmentDecisionSource = approvals.GuardianAssessmentDecisionSource

pub type GuardianAssessmentEvent = approvals.GuardianAssessmentEvent

pub type GuardianAssessmentOutcome = approvals.GuardianAssessmentOutcome

pub type GuardianAssessmentStatus = approvals.GuardianAssessmentStatus

pub type GuardianCommandSource = approvals.GuardianCommandSource

pub type GuardianRiskLevel = approvals.GuardianRiskLevel

pub type GuardianUserAuthorization = approvals.GuardianUserAuthorization

pub type HasLegacyEvent = legacy_events.HasLegacyEvent

pub type ImageDetail = models.ImageDetail

pub type ImageGenerationFailure = image_generation.ImageGenerationFailure

pub type InternalChatMessageMetadataPassthrough = models.InternalChatMessageMetadataPassthrough

pub type McpCallToolResult = mcp.CallToolResult

pub type MemoryCitation = memory_citation.MemoryCitation

pub type MessagePhase = models.MessagePhase

pub type ModeKind = config_types.ModeKind

pub type MultiAgentMode = config_types.MultiAgentMode

pub type NetworkPolicyAmendment = approvals.NetworkPolicyAmendment

pub type NetworkPolicyRuleAction = approvals.NetworkPolicyRuleAction

pub type NetworkApprovalContext = approvals.NetworkApprovalContext

pub type NetworkApprovalProtocol = approvals.NetworkApprovalProtocol

pub type NetworkSandboxPolicy = permissions.NetworkSandboxPolicy

pub type ParsedCommand = parse_command.ParsedCommand

pub type PathUri = codex_utils_path_uri.PathUri

pub type PermissionProfile = models.PermissionProfile

pub type Personality = config_types.Personality

pub type RawFileSystemSandboxPolicy = permissions.RawFileSystemSandboxPolicy

pub type ReasoningEffortConfig = openai_models.ReasoningEffort

pub type ReasoningSummaryConfig = config_types.ReasoningSummary

pub type RequestId = mcp.RequestId

pub type RequestPermissionsEvent = request_permissions.RequestPermissionsEvent

pub type RequestPermissionsArgs = request_permissions.RequestPermissionsArgs

pub type RequestPermissionsResponse = request_permissions.RequestPermissionsResponse

pub type RequestUserInputEvent = request_user_input.RequestUserInputEvent

pub type RequestUserInputResponse = request_user_input.RequestUserInputResponse

pub type ResponseInputItem = models.ResponseInputItem

pub type ResponseItem = models.ResponseItem

pub type SandboxEnforcement = models.SandboxEnforcement

pub type SelectedCapabilityRoot = capabilities.SelectedCapabilityRoot

pub type SuspendTurnOutcome = turn_input.SuspendTurnOutcome

pub type TextElement = user_input.TextElement

pub type TurnInputMode = turn_input.TurnInputMode

pub type TurnInputRequest = turn_input.TurnInputRequest

pub type TurnInputSubmission = turn_input.TurnInputSubmission

pub type TurnItem = items.TurnItem

pub type TurnStartOptions = turn_input.TurnStartOptions

pub type UpdatePlanArgs = plan_tool.UpdatePlanArgs

pub type WebSearchAction = models.WebSearchAction

// Re-exported environment access helper.
pub fn has_full_access(approval_policy AskForApproval, thread_profile &PermissionProfile, environments &[]EnvironmentConfigState) bool {
	return environment.has_full_access(approval_policy.kind == .never, thread_profile, environments)
}

// Open/close tags for special context blocks. Used across crates to avoid duplicated hardcoded
// strings.
pub const user_instructions_open_tag = '<user_instructions>'
pub const user_instructions_close_tag = '</user_instructions>'
pub const environment_context_open_tag = '<environment_context>'
pub const environment_context_close_tag = '</environment_context>'
pub const environments_instructions_open_tag = '<environments_instructions>'
pub const environments_instructions_close_tag = '</environments_instructions>'
pub const apps_instructions_open_tag = '<apps_instructions>'
pub const apps_instructions_close_tag = '</apps_instructions>'
pub const skills_instructions_open_tag = '<skills_instructions>'
pub const skills_instructions_close_tag = '</skills_instructions>'
pub const plugins_instructions_open_tag = '<plugins_instructions>'
pub const plugins_instructions_close_tag = '</plugins_instructions>'
pub const tools_open_tag = '<tools>'
pub const tools_close_tag = '</tools>'
pub const collaboration_mode_open_tag = '<collaboration_mode>'
pub const collaboration_mode_close_tag = '</collaboration_mode>'
pub const multi_agent_mode_open_tag = '<multi_agent_mode>'
pub const multi_agent_mode_close_tag = '</multi_agent_mode>'
pub const realtime_conversation_open_tag = '<realtime_conversation>'
pub const realtime_conversation_close_tag = '</realtime_conversation>'
pub const context_window_open_tag = '<context_window>'
pub const context_window_close_tag = '</context_window>'
pub const context_window_guidance_open_tag = '<context_window_guidance>'
pub const context_window_guidance_close_tag = '</context_window_guidance>'
pub const user_message_begin = '## My request for Codex:'

// Removes the model-context prefix from a user message before displaying it.
pub fn strip_user_message_prefix(text &string) string {
	if index := text.index(user_message_begin) {
		return (*text)[index + user_message_begin.len..].trim_space()
	}
	return text.trim_space()
}

// TODO(anp): Replace `TurnEnvironmentSelection` with `PathUri` once path URIs carry environment
// identifiers.
pub struct TurnEnvironmentSelection {
pub:
	environment_id  string
	cwd             PathUri
	workspace_roots []PathUri
	config          EnvironmentConfigState
}

pub struct TurnEnvironmentSelections {
pub:
	legacy_fallback_cwd AbsolutePathBuf
	environments        []TurnEnvironmentSelection
}

pub fn new_turn_environment_selections(legacy_fallback_cwd AbsolutePathBuf, environments []TurnEnvironmentSelection) TurnEnvironmentSelections {
	return TurnEnvironmentSelections{ legacy_fallback_cwd: legacy_fallback_cwd, environments: environments }
}

pub fn TurnEnvironmentSelections.new(legacy_fallback_cwd AbsolutePathBuf, environments []TurnEnvironmentSelection) TurnEnvironmentSelections {
	return new_turn_environment_selections(legacy_fallback_cwd, environments)
}

pub struct GitSha {
pub:
	value string
}

pub fn new_git_sha(sha &string) GitSha {
	return GitSha{ value: *sha }
}

pub fn GitSha.new(sha &string) GitSha {
	return new_git_sha(sha)
}

// Submission Queue Entry - requests from user
pub struct Submission {
pub:
	// Unique id for this Submission to correlate with Events
	id string
	// Payload
	op Op
	// Optional W3C trace carrier propagated across async submission handoffs.
	trace ?W3cTraceContext
	// Core-provided ID of the parent turn that directly initiated this submission.
	//
	// This is only used for inter-agent communication.
	parent_turn_id ?string
	// Core-provided ID of the top-level turn that causally initiated this submission.
	root_turn_id ?string
}

pub struct W3cTraceContext {
pub:
	traceparent ?string
	tracestate  ?string
}

// Represents Rust's `Option<Option<T>>`: `is_set` distinguishes preserve from clear.
pub struct OptionalReasoningEffort {
pub:
	is_set bool
	value  ?ReasoningEffortConfig
}

// Represents Rust's `Option<Option<String>>`: `is_set` distinguishes preserve from clear.
pub struct OptionalString {
pub:
	is_set bool
	value  ?string
}

pub struct ConversationStartParams {
pub:
	// Whether Codex response handoffs are managed through explicit client append calls.
	client_managed_handoffs bool
	// Whether a realtime V3 delegation produces an acknowledgement filler.
	// `None` preserves the Realtime API's default behavior.
	delegation_ack_filler ?bool
	// Whether to route any remaining transcript tail through Codex when the session ends.
	// TODO: Remove this rollout knob once transcript-tail flushing is always enabled.
	flush_transcript_tail_on_session_end bool
	// Sends automatic Codex responses as realtime conversation items instead of handoff appends.
	codex_responses_as_items bool
	// Optional prefix added to automatic Codex response items when `codex_responses_as_items` is set.
	codex_response_item_prefix ?string
	// Selects how automatic Codex handoffs are routed in Frameless Bidi sessions.
	// Realtime V1 and V2 ignore this setting.
	codex_response_handoff_mode CodexResponseHandoffMode
	// Optional client-selected BEM prefixes keyed by `analysis`, `commentary`, and `final`.
	codex_response_handoff_channel_prefixes ?map[string][]string
	// Overrides the configured realtime model for this session only.
	model ?string
	// Selects whether the realtime session should produce text or audio output.
	output_modality RealtimeOutputModality
	// Whether to append Codex's startup context to the realtime backend prompt.
	include_startup_context bool
	// Complete role-bearing text items to include in the initial realtime session history.
	initial_items []ConversationTextParams
	// Developer instructions given to Codex when this realtime session starts.
	realtime_start_instructions ?string
	// Developer instructions given to Codex when this realtime session ends.
	realtime_end_instructions ?string
	prompt                    OptionalString
	realtime_session_id       ?string
	transport                 ?ConversationStartTransport
	// Overrides the configured realtime protocol version for this session only.
	version ?RealtimeConversationVersion
	voice   ?RealtimeVoice
}

pub enum ConversationStartTransportKind {
	websocket
	webrtc
	existing_call
}

pub struct ConversationStartTransport {
pub:
	kind    ConversationStartTransportKind
	sdp     string
	call_id string
	// Endpoint selected by the embedding runtime for this call's sideband.
	// This is an in-process override, not a client-supplied API parameter.
	// `None` uses the configured endpoint or the default public API.
	sideband_base_url ?string
}

pub enum RealtimeOutputModality {
	text
	audio
}

pub enum RealtimeVoice {
	alloy
	arbor
	ash
	ballad
	breeze
	cedar
	coral
	cove
	echo
	ember
	juniper
	maple
	marin
	sage
	shimmer
	sol
	spruce
	vale
	verse
}

pub fn (voice RealtimeVoice) wire_name() string {
	return voice.str()
}

pub struct RealtimeVoicesList {
pub:
	v1         []RealtimeVoice
	v2         []RealtimeVoice
	default_v1 RealtimeVoice
	default_v2 RealtimeVoice
}

pub fn builtin_realtime_voices_list() RealtimeVoicesList {
	return RealtimeVoicesList{
		v1:         [.juniper, .maple, .spruce, .ember, .vale, .breeze, .arbor, .sol, .cove]
		v2:         [.alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse, .marin, .cedar]
		default_v1: .cove
		default_v2: .marin
	}
}

pub fn RealtimeVoicesList.builtin() RealtimeVoicesList {
	return builtin_realtime_voices_list()
}

pub struct RealtimeAudioFrame {
pub:
	data                string
	sample_rate         u32
	num_channels        u16
	samples_per_channel ?u32
	item_id             ?string
}

pub struct RealtimeTranscriptDelta {
pub:
	delta string
}

pub struct RealtimeTranscriptDone {
pub:
	text string
}

pub struct RealtimeTranscriptEntry {
pub:
	role string
	text string
}

pub struct RealtimeHandoffRequested {
pub:
	handoff_id        string
	item_id           string
	input_transcript  string
	active_transcript []RealtimeTranscriptEntry
}

pub struct RealtimeNoopRequested {
pub:
	call_id string
	item_id string
}

pub struct RealtimeInputAudioSpeechStarted {
pub:
	item_id ?string
}

pub struct RealtimeResponseCancelled {
pub:
	response_id ?string
}

pub struct RealtimeResponseCreated {
pub:
	response_id ?string
}

pub struct RealtimeResponseDone {
pub:
	response_id ?string
}

pub enum RealtimeEventKind {
	session_updated
	input_audio_speech_started
	input_transcript_delta
	input_transcript_done
	output_transcript_delta
	output_transcript_done
	audio_out
	response_created
	response_cancelled
	response_done
	conversation_item_added
	conversation_item_done
	// Canonical display history produced by Core, separate from provider events.
	history_item_started
	history_transcript_delta
	history_item_completed
	handoff_requested
	noop_requested
	error
}

pub struct RealtimeEvent {
pub:
	kind                RealtimeEventKind
	realtime_session_id string
	instructions        ?string
	speech_started      ?RealtimeInputAudioSpeechStarted
	transcript_delta    ?RealtimeTranscriptDelta
	transcript_done     ?RealtimeTranscriptDone
	audio_frame         ?RealtimeAudioFrame
	response_created    ?RealtimeResponseCreated
	response_cancelled  ?RealtimeResponseCancelled
	response_done       ?RealtimeResponseDone
	conversation_item   json2.Any
	item_id             string
	history_item        ?realtime.RealtimeItem
	delta               string
	handoff             ?RealtimeHandoffRequested
	noop                ?RealtimeNoopRequested
	error_message       string
}

pub struct ConversationAudioParams {
pub:
	frame RealtimeAudioFrame
}

pub struct ConversationTextParams {
pub:
	text string
	role ConversationTextRole
}

pub enum ConversationTextRole {
	user
	developer
	assistant
}

pub struct ConversationSpeechParams {
pub:
	text string
}

// Supported sparse changes to one live task's current settings, regardless of
// task kind. Child sessions and consumers of frozen initial settings are unchanged.
pub struct TurnSettingsUpdate {
pub:
	// Changes the reviewer for subsequent approval requests, not pending reviews.
	approvals_reviewer ?ApprovalsReviewer
	model              ?string
	// `None` preserves the selection; `Some(None)` clears it.
	effort  OptionalReasoningEffort
	summary ?ReasoningSummaryConfig
	// `None` preserves the requested tier; `Some(None)` clears it.
	service_tier OptionalString
}

// The result of processing a turn-settings update, not merely queueing it.
pub enum TurnSettingsUpdateOutcomeKind {
	// Published for subsequent captures; already captured steps are unchanged.
	// The task need not sample or consume every selected preference.
	applied
	// The named live task was absent or lost before publication.
	target_unavailable
	rejected
}

pub struct TurnSettingsUpdateOutcome {
pub:
	kind   TurnSettingsUpdateOutcomeKind
	reason string
}

// Thread-settings overrides that can be applied before user input or on their
// own. Standalone updates change the settings inherited by future turns.
pub struct ThreadSettingsOverrides {
pub:
	// Updated fallback `cwd` and environments supplied together as a complete pair.
	environments ?TurnEnvironmentSelections
	// Updated profile-defined workspace roots for status summaries and
	// per-turn config reconstruction.
	profile_workspace_roots ?[]AbsolutePathBuf
	// Updated command approval policy.
	approval_policy ?AskForApproval
	// Updated approval reviewer for future approval prompts.
	approvals_reviewer ?ApprovalsReviewer
	// Updated sandbox policy for tool calls.
	sandbox_policy ?SandboxPolicy
	// Updated permissions profile for tool calls.
	permission_profile ?PermissionProfile
	// Named or built-in profile that produced `permission_profile`, if the
	// update selected a profile rather than supplying raw permissions.
	active_permission_profile ?ActivePermissionProfile
	// Updated Windows sandbox mode for tool execution.
	windows_sandbox_level ?config_types.WindowsSandboxLevel
	// Updated model slug. When set, the model info is derived automatically.
	model ?string
	// Updated reasoning effort (honored only for reasoning-capable models).
	//
	// Use `Some(Some(_))` to set a specific effort, `Some(None)` to clear the
	// effort, or `None` to leave the existing value unchanged.
	effort OptionalReasoningEffort
	// Updated reasoning summary preference (honored only for reasoning-capable models).
	summary ?ReasoningSummaryConfig
	// Updated service tier preference for future turns.
	//
	// Use `Some(Some(_))` to set a specific tier, `Some(None)` to clear the
	// preference, or `None` to leave the existing value unchanged.
	service_tier OptionalString
	// EXPERIMENTAL - set a pre-set collaboration mode.
	// Takes precedence over model, effort, and developer instructions if set.
	collaboration_mode ?CollaborationMode
	// Updated personality preference.
	personality ?Personality
}

// Source classification for client-supplied context.
pub enum AdditionalContextKind {
	untrusted
	application
}

// Client-supplied context keyed by an opaque source identifier.
pub struct AdditionalContextEntry {
pub:
	value string
	kind  AdditionalContextKind
}

// Submission operation
pub enum OpKind {
	// Abort current task without terminating background terminal processes.
	// This server sends [`EventMsg::TurnAborted`] in response.
	interrupt
	// Terminate all running background terminal processes for this thread.
	// Use this when callers intentionally want to stop long-lived background shells.
	clean_background_terminals
	// Start a realtime conversation stream.
	realtime_conversation_start
	// Send audio input to the running realtime conversation stream.
	realtime_conversation_audio
	// Send text input to the running realtime conversation stream.
	realtime_conversation_text
	// Append speakable text to the running realtime conversation stream.
	realtime_conversation_speech
	// Close the running realtime conversation stream.
	realtime_conversation_close
	// Request the list of voices supported by realtime conversation streams.
	realtime_conversation_list_voices
	// Submit turn input using the requested routing behavior.
	turn_input
	// Resume an interrupted regular turn.
	recover_turn
	// Stop the active root turn without recording a terminal turn event.
	suspend_turn_and_shutdown
	// Apply thread-settings overrides without starting a turn.
	//
	// This uses the same submission queue as turn starts so app-server can
	// preserve caller order between both kinds of mutation.
	thread_settings
	// Update only the named running turn, without changing future settings.
	// The reply reports the actual publication or why it did not occur.
	turn_settings
	// Inter-agent communication that should be recorded as agent-message history
	// while still using the normal thread submission lifecycle.
	inter_agent_communication
	// Approve a command execution
	exec_approval
	// Approve a code patch
	patch_approval
	// Resolve an MCP elicitation request.
	resolve_elicitation
	// Resolve a request_user_input tool call.
	user_input_answer
	// Resolve a request_permissions tool call.
	request_permissions_response
	// Resolve a dynamic tool call request.
	dynamic_tool_response
	// Request MCP servers to reinitialize and refresh cached tool lists.
	refresh_mcp_servers
	// Reload user config layer overrides for the active session.
	//
	// This updates runtime config-derived behavior (for example app
	// enable/disable state) without restarting the thread.
	reload_user_config
	// Request the agent to summarize the current conversation context.
	// The agent will use its existing context (either conversation history or previous response id)
	// to generate a summary which will be returned as an AgentMessage event.
	compact
	// Set whether the thread remains eligible for memory generation.
	//
	// This persists thread-level memory mode metadata without involving the
	// model.
	set_thread_memory_mode
	// Request Codex to drop the last N user turns from in-memory context.
	//
	// This does not attempt to revert local filesystem changes. Clients are
	// responsible for undoing any edits on disk.
	thread_rollback
	// Request a code review from the agent.
	review
	// Record that the user approved one retry of a concrete Guardian-denied action.
	approve_guardian_denied_action
	// Request to shut down codex instance.
	shutdown
	// Execute a user-initiated one-off shell command (triggered by "!cmd").
	//
	// The command string is executed using the user's default shell and may
	// include shell syntax (pipes, redirects, etc.). Output is streamed via
	// `ExecCommand*` events and the UI regains control upon `TurnComplete`.
	run_user_shell_command
}

pub struct Op {
pub:
	op_kind             OpKind
	conversation_start  ?ConversationStartParams
	conversation_audio  ?ConversationAudioParams
	conversation_text   ?ConversationTextParams
	conversation_speech ?ConversationSpeechParams
	request             ?TurnInputRequest
	mode                ?TurnInputMode
	turn_input_reply    ?oneshot.Sender[TurnInputSubmission]
	// Sparse thread-settings overrides to apply.
	thread_settings ?ThreadSettingsOverrides
	start_options   ?TurnStartOptions
	suspend_reply   ?oneshot.Sender[SuspendTurnOutcome]
	// Turn id associated with the approval event, when available.
	turn_id              string
	turn_settings_update ?TurnSettingsUpdate
	turn_settings_reply  ?oneshot.Sender[TurnSettingsUpdateOutcome]
	communication        ?InterAgentCommunication
	// The id of the submission we are approving
	// The id of the submission we are approving
	// Turn id for the in-flight request.
	// Call id for the in-flight request.
	// Call id for the in-flight request.
	id string
	// The user's decision in response to the request.
	// The user's decision in response to the request.
	decision ?ReviewDecision
	// Name of the MCP server that issued the request.
	server_name string
	// Request identifier from the MCP server.
	request_id ?RequestId
	// User's decision for the request.
	elicitation_decision ?ElicitationAction
	// Structured user input supplied for accepted elicitations.
	content json2.Any
	// Optional client metadata associated with the elicitation response.
	meta json2.Any
	// User-provided answers.
	user_input_response ?RequestUserInputResponse
	// User-granted permissions.
	permissions_response ?RequestPermissionsResponse
	// Tool output payload.
	dynamic_tool_response ?DynamicToolResponse
	thread_memory_mode    ?ThreadMemoryMode
	num_turns             u32
	review_request        ?ReviewRequest
	guardian_event        ?GuardianAssessmentEvent
	// The raw command string after '!'
	command string
	// Maximum execution time in milliseconds. Defaults to one hour.
	timeout_ms ?u64
}

pub enum ThreadMemoryMode {
	enabled
	disabled
}

pub enum ThreadHistoryMode {
	legacy
	paginated
}

pub fn (mode ThreadHistoryMode) as_str() string {
	return mode.str()
}

pub fn thread_history_mode_from_str(value &string) !ThreadHistoryMode {
	return match *value {
		'legacy' { .legacy }
		'paginated' { .paginated }
		else { error('unknown thread history mode `${*value}`') }
	}
}

pub fn ThreadHistoryMode.from_str(value &string) !ThreadHistoryMode {
	return thread_history_mode_from_str(value)
}

pub struct InterAgentCommunication {
pub mut:
	id                                         ?ResponseItemId
	internal_chat_message_metadata_passthrough ?InternalChatMessageMetadataPassthrough
pub:
	author            AgentPath
	recipient         AgentPath
	other_recipients  []AgentPath
	content           string
	encrypted_content ?string
	trigger_turn      bool
}

pub fn new_inter_agent_communication(author AgentPath, recipient AgentPath, other_recipients []AgentPath, content string, trigger_turn bool) InterAgentCommunication {
	return InterAgentCommunication{
		author:           author
		recipient:        recipient
		other_recipients: other_recipients
		content:          content
		trigger_turn:     trigger_turn
	}
}

pub fn InterAgentCommunication.new(author AgentPath, recipient AgentPath, other_recipients []AgentPath, content string, trigger_turn bool) InterAgentCommunication {
	return new_inter_agent_communication(author, recipient, other_recipients, content, trigger_turn)
}

pub fn new_encrypted_inter_agent_communication(author AgentPath, recipient AgentPath, other_recipients []AgentPath, encrypted_content string, trigger_turn bool) InterAgentCommunication {
	return InterAgentCommunication{
		author:            author
		recipient:         recipient
		other_recipients:  other_recipients
		encrypted_content: encrypted_content
		trigger_turn:      trigger_turn
	}
}

pub fn InterAgentCommunication.new_encrypted(author AgentPath, recipient AgentPath, other_recipients []AgentPath, encrypted_content string, trigger_turn bool) InterAgentCommunication {
	return new_encrypted_inter_agent_communication(author, recipient, other_recipients, encrypted_content, trigger_turn)
}

pub fn (mut communication InterAgentCommunication) set_turn_id_if_missing(turn_id &string) {
	communication.internal_chat_message_metadata_passthrough = models.set_turn_id_if_missing(communication.internal_chat_message_metadata_passthrough, turn_id)
}

pub fn (communication &InterAgentCommunication) to_response_input_item() ResponseInputItem {
	// Rust clones `self` here, then strips transport-only metadata. Constructing the
	// owned value explicitly makes that clone boundary visible to `v -ownership`.
	serialized_communication := InterAgentCommunication{
		author:            communication.author
		recipient:         communication.recipient
		other_recipients:  communication.other_recipients
		content:           communication.content
		encrypted_content: communication.encrypted_content
		trigger_turn:      communication.trigger_turn
	}
	return ResponseInputItem{
		kind:    'message'
		role:    'assistant'
		content: [ContentItem{
			kind: 'output_text'
			// V3's optional ownership pass cannot specialize json2's generic encoder when this
			// protocol module is pulled into a decode-only downstream executable. The stable JSON
			// encoder preserves the same wire object while avoiding that compiler-only failure.
			text: json.encode(serialized_communication)
		}]
		phase:   MessagePhase.commentary
	}
}

pub fn (communication &InterAgentCommunication) to_model_input_item() ResponseItem {
	mut content := []AgentMessageInputContent{}
	if encrypted_content := communication.encrypted_content {
		message_type := if communication.trigger_turn { 'NEW_TASK' } else { 'MESSAGE' }
		content << AgentMessageInputContent{
			kind: 'input_text'
			text: 'Message Type: ${message_type}\nTask name: ${communication.recipient}\nSender: ${communication.author}\nPayload:\n'
		}
		content << AgentMessageInputContent{
			kind:              'encrypted_content'
			encrypted_content: encrypted_content
		}
	} else {
		content << AgentMessageInputContent{ kind: 'input_text', text: communication.content }
	}
	mut item_id := ?string(none)
	if id := communication.id {
		item_id = id.value
	}
	return ResponseItem{
		kind:                                       'agent_message'
		id:                                         item_id
		author:                                     communication.author.str()
		recipient:                                  communication.recipient.str()
		content:                                    content
		internal_chat_message_metadata_passthrough: communication.internal_chat_message_metadata_passthrough
	}
}

pub fn InterAgentCommunication.is_message_content(content &[]ContentItem) bool {
	_ := InterAgentCommunication.from_message_content(content) or { return false }
	return true
}

pub fn InterAgentCommunication.from_message_content(content &[]ContentItem) !InterAgentCommunication {
	if content.len != 1 || (content[0].kind != 'input_text' && content[0].kind != 'output_text') {
		return error('content is not a serialized inter-agent message')
	}
	return json2.decode[InterAgentCommunication](content[0].text)
}

pub fn (op &Op) kind() string {
	return op.op_kind.str()
}

// Determines the conditions under which the user is consulted to approve
// running the command proposed by Codex.
pub enum AskForApprovalKind {
	// Internal policy for projects marked untrusted. Commands require
	// approval unless an explicit exec policy rule allows them.
	unless_trusted
	// The model decides when to ask the user for approval.
	on_request
	// Fine-grained controls for individual approval flows.
	//
	// When a field is `true`, commands in that category are allowed. When it
	// is `false`, those requests are automatically rejected instead of shown
	// to the user.
	granular
	// Never ask the user to approve commands. Failures are immediately returned
	// to the model, and never escalated to the user for approval.
	never
}

pub struct AskForApproval {
pub:
	kind     AskForApprovalKind = .on_request
	granular ?GranularApprovalConfig
}

pub struct GranularApprovalConfig {
pub:
	// Whether to allow shell command approval requests, including inline
	// `with_additional_permissions` and `require_escalated` requests.
	sandbox_approval bool
	// Whether to allow prompts triggered by execpolicy `prompt` rules.
	rules bool
	// Whether to allow approval prompts triggered by skill script execution.
	skill_approval bool
	// Whether to allow prompts triggered by the `request_permissions` tool.
	request_permissions bool
	// Whether to allow MCP elicitation prompts.
	mcp_elicitations bool
}

pub fn (config GranularApprovalConfig) allows_sandbox_approval() bool {
	return config.sandbox_approval
}

pub fn (config GranularApprovalConfig) allows_rules_approval() bool {
	return config.rules
}

pub fn (config GranularApprovalConfig) allows_skill_approval() bool {
	return config.skill_approval
}

pub fn (config GranularApprovalConfig) allows_request_permissions() bool {
	return config.request_permissions
}

pub fn (config GranularApprovalConfig) allows_mcp_elicitations() bool {
	return config.mcp_elicitations
}

// Represents whether outbound network access is available to the agent.
pub enum NetworkAccess {
	restricted
	enabled
}

pub fn (access NetworkAccess) is_enabled() bool {
	return access == .enabled
}

// Determines execution restrictions for model shell commands.
pub enum SandboxPolicyKind {
	// No restrictions whatsoever. Use with caution.
	danger_full_access
	// Read-only access configuration.
	read_only
	// Indicates the process is already in an external sandbox. Allows full
	// disk access while honoring the provided network setting.
	external_sandbox
	// Same as `ReadOnly` but additionally grants write access to the current
	// working directory ("workspace").
	workspace_write
}

pub struct SandboxPolicy {
pub:
	policy_kind SandboxPolicyKind
	// Additional folders (beyond cwd and possibly TMPDIR) that should be
	// writable from within the sandbox.
	writable_roots []AbsolutePathBuf
	// The `ReadOnly` payload:
	// When set to `true`, outbound network access is allowed. `false` by
	// default.
	// The `WorkspaceWrite` payload:
	// When set to `true`, outbound network access is allowed. `false` by
	// default.
	network_access bool
	// Whether the external sandbox permits outbound network traffic.
	external_network_access NetworkAccess
	// When set to `true`, will NOT include the per-user `TMPDIR`
	// environment variable among the default writable roots. Defaults to
	// `false`.
	exclude_tmpdir_env_var bool
	// When set to `true`, will NOT include the `/tmp` among the default
	// writable roots on UNIX. Defaults to `false`.
	exclude_slash_tmp bool
}

// A writable root path accompanied by a list of subpaths that should remain
// read‑only even when the root is writable. This is primarily used to ensure
// that folders containing files that could be modified to escalate the
// privileges of the agent (e.g. `.codex`, `.git`, notably `.git/hooks`) under
// a writable root are not modified by the agent.
pub struct WritableRoot {
pub:
	root AbsolutePathBuf
	// By construction, these subpaths are all under `root`.
	read_only_subpaths []AbsolutePathBuf
	// Workspace metadata path names that must not be created or replaced under
	// `root` unless the policy grants an explicit write rule for that metadata
	// path.
	protected_metadata_names []string
}

fn path_starts_with(path &string, root &string) bool {
	clean_path := os.norm_path(path)
	clean_root := os.norm_path(root)
	if clean_path == clean_root {
		return true
	}
	prefix := if clean_root == os.path_separator.str() {
		clean_root
	} else {
		clean_root + os.path_separator.str()
	}
	return clean_path.starts_with(prefix)
}

pub fn (root &WritableRoot) is_path_writable(path &string) bool {
	// Check if the path is under the root.
	if !path_starts_with(path, root.root.path) {
		return false
	}
	// Check if the path is under any of the read-only subpaths.
	for subpath in root.read_only_subpaths {
		if path_starts_with(path, subpath.path) {
			return false
		}
	}
	if root.path_contains_protected_metadata_name(path) {
		return false
	}
	return true
}

fn (root &WritableRoot) path_contains_protected_metadata_name(path &string) bool {
	if !path_starts_with(path, root.root.path) {
		return false
	}
	relative := os.norm_path(path).trim_string_left(os.norm_path(root.root.path)).trim_left(os.path_separator.str())
	if relative.len == 0 {
		return false
	}
	first_component := relative.all_before(os.path_separator.str())
	return first_component in root.protected_metadata_names
}

pub fn sandbox_policy_from_str(value &string) !SandboxPolicy {
	return json2.decode[SandboxPolicy](*value)
}

pub fn SandboxPolicy.from_str(value &string) !SandboxPolicy {
	return sandbox_policy_from_str(value)
}

pub fn file_system_sandbox_policy_from_str(value &string) !FileSystemSandboxPolicy {
	return permissions.file_system_sandbox_policy_from_str(value)
}

pub fn network_sandbox_policy_from_str(value &string) !NetworkSandboxPolicy {
	return permissions.network_sandbox_policy_from_str(value)
}

// Returns a policy with read-only disk access and no network.
pub fn new_read_only_policy() SandboxPolicy {
	return SandboxPolicy{ policy_kind: .read_only, external_network_access: .restricted }
}

pub fn SandboxPolicy.new_read_only_policy() SandboxPolicy {
	return new_read_only_policy()
}

// Returns a policy that can read the entire disk, but can only write to
// the current working directory and the per-user tmp dir on macOS. It does
// not allow network access.
pub fn new_workspace_write_policy() SandboxPolicy {
	return SandboxPolicy{ policy_kind: .workspace_write, external_network_access: .restricted }
}

pub fn SandboxPolicy.new_workspace_write_policy() SandboxPolicy {
	return new_workspace_write_policy()
}

pub fn (policy &SandboxPolicy) has_full_disk_read_access() bool {
	return true
}

pub fn (policy &SandboxPolicy) has_full_disk_write_access() bool {
	return policy.policy_kind in [.danger_full_access, .external_sandbox]
}

pub fn (policy &SandboxPolicy) has_full_network_access() bool {
	return match policy.policy_kind {
		.danger_full_access { true }
		.external_sandbox { policy.external_network_access.is_enabled() }
		.read_only, .workspace_write { policy.network_access }
	}
}

// Returns the list of writable roots (tailored to the current working
// directory) together with subpaths that should remain read‑only under
// each writable root.
pub fn (policy &SandboxPolicy) get_writable_roots_with_cwd(cwd &string) []WritableRoot {
	if policy.policy_kind != .workspace_write {
		return []WritableRoot{}
	}
	// Start from explicitly configured writable roots.
	mut roots := policy.writable_roots.clone()
	// Always include defaults: cwd, /tmp (if present on Unix), and
	// on macOS, the per-user TMPDIR unless explicitly excluded.
	// TODO(mbolin): cwd param should be AbsolutePathBuf.
	if cwd_absolute := codex_utils_absolute_path.from_absolute_path(cwd) {
		roots << cwd_absolute
	}
	// Include /tmp on Unix unless explicitly excluded.
	if os.user_os() != 'windows' && !policy.exclude_slash_tmp && os.is_dir('/tmp') {
		slash_tmp_path := '/tmp'
		if slash_tmp := codex_utils_absolute_path.from_absolute_path(slash_tmp_path) {
			roots << slash_tmp
		}
	}
	// Include $TMPDIR unless explicitly excluded. On macOS, TMPDIR
	// is per-user, so writes to TMPDIR should not be readable by
	// other users on the system.
	//
	// By comparison, TMPDIR is not guaranteed to be defined on
	// Linux or Windows, but supporting it here gives users a way to
	// provide the model with their own temporary directory without
	// having to hardcode it in the config.
	if !policy.exclude_tmpdir_env_var {
		tmpdir := os.getenv('TMPDIR')
		if tmpdir.len > 0 {
			if tmpdir_path := codex_utils_absolute_path.from_absolute_path(tmpdir) {
				roots << tmpdir_path
			}
		}
	}
	// For each root, compute subpaths that should remain read-only.
	mut writable := []WritableRoot{cap: roots.len}
	for candidate in roots {
		protect_missing_dot_codex := os.norm_path(candidate.path) == os.norm_path(cwd)
		read_only_subpaths := permissions.default_read_only_subpaths_for_writable_root(candidate, protect_missing_dot_codex)
		writable << WritableRoot{
			root:               candidate
			read_only_subpaths: read_only_subpaths
		}
	}
	return writable
}

// Event Queue Entry - events from agent
pub struct Event {
pub:
	// Submission `id` that this event is correlated with.
	id string
	// Payload
	msg EventMsg
}

pub struct EnvironmentConnectionEvent {
pub:
	environment_id string
}

// Response event from the agent
// NOTE: Make sure none of these values have optional types, as it will mess up the extension code-gen.
pub enum EventMsgKind {
	// Error while executing a submission
	error
	// Warning issued while processing a submission. Unlike `Error`, this
	// indicates the turn continued but the user should still be notified.
	warning
	// Provider-owned authentication recovery has started for the current turn.
	auth_recovery_started
	// Provider-owned authentication recovery has completed for the current turn.
	auth_recovery_completed
	// Warning issued by the guardian automatic approval reviewer.
	guardian_warning
	// Realtime conversation lifecycle start event.
	realtime_conversation_started
	// Realtime conversation streaming payload event.
	realtime_conversation_realtime
	// Realtime conversation lifecycle close event.
	realtime_conversation_closed
	// Realtime session description protocol payload.
	realtime_conversation_sdp
	// Model routing changed from the requested model to a different model.
	model_reroute
	// Backend recommends additional account verification for this turn.
	model_verification
	// Backend moderation metadata intended for first-party turn presentation.
	turn_moderation_metadata
	// Backend indicates that response output is waiting on a safety review.
	safety_buffering
	// Conversation history was compacted (either automatically or manually).
	context_compacted
	// Conversation history was rolled back by dropping the last N user turns.
	thread_rolled_back
	// Agent has started a turn.
	// v1 wire format uses `task_started`; accept `turn_started` for v2 interop.
	turn_started
	// Persistent thread-settings overrides from the correlated submission have
	// been applied to the session configuration.
	thread_settings_applied
	// Agent has completed all actions.
	// v1 wire format uses `task_complete`; accept `turn_complete` for v2 interop.
	turn_complete
	// Usage update for the current session, including totals and last turn.
	// Optional means unknown — UIs should not display when `None`.
	token_count
	// Agent text output message
	agent_message
	// User/system input message (what was sent to the model)
	user_message
	// Reasoning event from agent.
	agent_reasoning
	// Raw chain-of-thought from agent.
	agent_reasoning_raw_content
	// Signaled when the model begins a new reasoning summary section (e.g., a new titled block).
	agent_reasoning_section_break
	// Ack the client's configure message.
	session_configured
	// A selected environment completed its connection handshake.
	environment_connected
	// A selected environment lost its established connection.
	environment_disconnected
	// Updated long-running goal metadata for the thread.
	thread_goal_updated
	// A durable thread-scoped user-message queue changed.
	thread_queue_changed
	// Incremental MCP startup progress updates.
	mcp_startup_update
	// Aggregate MCP startup completion summary.
	mcp_startup_complete
	mcp_tool_call_begin
	mcp_tool_call_end
	web_search_begin
	web_search_end
	image_generation_begin
	image_generation_end
	// Notification that the server is about to execute a command.
	exec_command_begin
	// Incremental chunk of output from a running command.
	exec_command_output_delta
	// Terminal interaction for an in-progress command (stdin sent and stdout observed).
	terminal_interaction
	exec_command_end
	// Notification that the agent attached a local image via the view_image tool.
	view_image_tool_call
	exec_approval_request
	request_permissions
	request_user_input
	dynamic_tool_call_request
	dynamic_tool_call_response
	elicitation_request
	apply_patch_approval_request
	// Structured lifecycle event for a guardian-reviewed approval request.
	guardian_assessment
	// Notification advising the user that something they are using has been
	// deprecated and should be phased out.
	deprecation_notice
	// Notification that a model stream experienced an error or disconnect
	// and the system is handling it (e.g., retrying with backoff).
	stream_error
	// Notification that the agent is about to apply a code patch. Mirrors
	// `ExecCommandBegin` so front‑ends can show progress indicators.
	patch_apply_begin
	// Latest model-generated structured changes for an `apply_patch` call.
	patch_apply_updated
	// Notification that a patch application has finished.
	patch_apply_end
	turn_diff
	// List of voices supported by realtime conversation streams.
	realtime_conversation_list_voices_response
	plan_update
	turn_aborted
	// Notification that the agent is shutting down.
	shutdown_complete
	// Entered review mode.
	entered_review_mode
	// Exited review mode with an optional final result to apply.
	exited_review_mode
	raw_response_item
	raw_response_completed
	item_started
	item_completed
	hook_started
	hook_completed
	agent_message_content_delta
	plan_delta
	reasoning_content_delta
	reasoning_raw_content_delta
	// Collab interaction: agent spawn begin.
	collab_agent_spawn_begin
	// Collab interaction: agent spawn end.
	collab_agent_spawn_end
	// Collab interaction: agent interaction begin.
	collab_agent_interaction_begin
	// Collab interaction: agent interaction end.
	collab_agent_interaction_end
	// Collab interaction: waiting begin.
	collab_waiting_begin
	// Collab interaction: waiting end.
	collab_waiting_end
	// Collab interaction: close begin.
	collab_close_begin
	// Collab interaction: close end.
	collab_close_end
	// Collab interaction: resume begin.
	collab_resume_begin
	// Collab interaction: resume end.
	collab_resume_end
	// Path-based v2 sub-agent activity.
	sub_agent_activity
}

// V has no Rust-style data-carrying enums. The discriminator and owned optional payloads
// preserve every `EventMsg` variant without sharing mutable storage between events.
pub struct EventMsg {
pub:
	msg_kind                                         EventMsgKind
	error_event                                      ?ErrorEvent
	warning_event                                    ?WarningEvent
	auth_recovery_event                              ?AuthRecoveryEvent
	realtime_conversation_started_event              ?RealtimeConversationStartedEvent
	realtime_conversation_realtime_event             ?RealtimeConversationRealtimeEvent
	realtime_conversation_closed_event               ?RealtimeConversationClosedEvent
	realtime_conversation_sdp_event                  ?RealtimeConversationSdpEvent
	model_reroute_event                              ?ModelRerouteEvent
	model_verification_event                         ?ModelVerificationEvent
	turn_moderation_metadata_event                   ?TurnModerationMetadataEvent
	safety_buffering_event                           ?SafetyBufferingEvent
	context_compacted_event                          ?ContextCompactedEvent
	thread_rolled_back_event                         ?ThreadRolledBackEvent
	turn_started_event                               ?TurnStartedEvent
	thread_settings_applied_event                    ?ThreadSettingsAppliedEvent
	turn_complete_event                              ?TurnCompleteEvent
	token_count_event                                ?TokenCountEvent
	agent_message_event                              ?AgentMessageEvent
	user_message_event                               ?UserMessageEvent
	agent_reasoning_event                            ?AgentReasoningEvent
	agent_reasoning_raw_content_event                ?AgentReasoningRawContentEvent
	agent_reasoning_section_break_event              ?AgentReasoningSectionBreakEvent
	session_configured_event                         ?SessionConfiguredEvent
	environment_connection_event                     ?EnvironmentConnectionEvent
	thread_goal_updated_event                        ?ThreadGoalUpdatedEvent
	thread_queue_changed_event                       ?ThreadQueueChangedEvent
	mcp_startup_update_event                         ?McpStartupUpdateEvent
	mcp_startup_complete_event                       ?McpStartupCompleteEvent
	mcp_tool_call_begin_event                        ?McpToolCallBeginEvent
	mcp_tool_call_end_event                          ?McpToolCallEndEvent
	web_search_begin_event                           ?WebSearchBeginEvent
	web_search_end_event                             ?WebSearchEndEvent
	image_generation_begin_event                     ?ImageGenerationBeginEvent
	image_generation_end_event                       ?ImageGenerationEndEvent
	exec_command_begin_event                         ?ExecCommandBeginEvent
	exec_command_output_delta_event                  ?ExecCommandOutputDeltaEvent
	terminal_interaction_event                       ?TerminalInteractionEvent
	exec_command_end_event                           ?ExecCommandEndEvent
	view_image_tool_call_event                       ?ViewImageToolCallEvent
	exec_approval_request_event                      ?ExecApprovalRequestEvent
	request_permissions_event                        ?RequestPermissionsEvent
	request_user_input_event                         ?RequestUserInputEvent
	dynamic_tool_call_request_event                  ?DynamicToolCallRequest
	dynamic_tool_call_response_event                 ?DynamicToolCallResponseEvent
	elicitation_request_event                        ?ElicitationRequestEvent
	apply_patch_approval_request_event               ?approvals.ApplyPatchApprovalRequestEvent
	guardian_assessment_event                        ?GuardianAssessmentEvent
	deprecation_notice_event                         ?DeprecationNoticeEvent
	stream_error_event                               ?StreamErrorEvent
	patch_apply_begin_event                          ?PatchApplyBeginEvent
	patch_apply_updated_event                        ?PatchApplyUpdatedEvent
	patch_apply_end_event                            ?PatchApplyEndEvent
	turn_diff_event                                  ?TurnDiffEvent
	realtime_conversation_list_voices_response_event ?RealtimeConversationListVoicesResponseEvent
	plan_update                                      ?UpdatePlanArgs
	turn_aborted_event                               ?TurnAbortedEvent
	entered_review_mode_event                        ?EnteredReviewModeEvent
	exited_review_mode_event                         ?ExitedReviewModeEvent
	raw_response_item_event                          ?RawResponseItemEvent
	raw_response_completed_event                     ?RawResponseCompletedEvent
	item_started_event                               ?ItemStartedEvent
	item_completed_event                             ?ItemCompletedEvent
	hook_started_event                               ?HookStartedEvent
	hook_completed_event                             ?HookCompletedEvent
	agent_message_content_delta_event                ?AgentMessageContentDeltaEvent
	plan_delta_event                                 ?PlanDeltaEvent
	reasoning_content_delta_event                    ?ReasoningContentDeltaEvent
	reasoning_raw_content_delta_event                ?ReasoningRawContentDeltaEvent
	collab_agent_spawn_begin_event                   ?CollabAgentSpawnBeginEvent
	collab_agent_spawn_end_event                     ?CollabAgentSpawnEndEvent
	collab_agent_interaction_begin_event             ?CollabAgentInteractionBeginEvent
	collab_agent_interaction_end_event               ?CollabAgentInteractionEndEvent
	collab_waiting_begin_event                       ?CollabWaitingBeginEvent
	collab_waiting_end_event                         ?CollabWaitingEndEvent
	collab_close_begin_event                         ?CollabCloseBeginEvent
	collab_close_end_event                           ?CollabCloseEndEvent
	collab_resume_begin_event                        ?CollabResumeBeginEvent
	collab_resume_end_event                          ?CollabResumeEndEvent
	sub_agent_activity_event                         ?SubAgentActivityEvent
}

pub enum HookEventName {
	pre_tool_use
	permission_request
	post_tool_use
	pre_compact
	post_compact
	session_start
	session_end
	user_prompt_submit
	subagent_start
	subagent_stop
	stop
	interrupt
}

pub enum HookHandlerType {
	command
	mcp_tool
	prompt
	agent
}

pub enum HookExecutionMode {
	sync
	async_mode
}

pub enum HookScope {
	thread
	turn
}

pub enum HookSource {
	system
	user
	project
	mdm
	session_flags
	plugin
	cloud_requirements
	cloud_managed_config
	legacy_managed_config_file
	legacy_managed_config_mdm
	unknown
}

pub enum HookTrustStatus {
	managed
	untrusted
	trusted
	modified
}

pub enum HookRunStatus {
	running
	completed
	failed
	blocked
	stopped
}

pub enum HookOutputEntryKind {
	warning
	stop
	feedback
	context
	error
}

pub struct HookOutputEntry {
pub:
	kind HookOutputEntryKind
	text string
}

pub struct HookRunSummary {
pub mut:
	// Internal classification used to suppress lifecycle notifications without losing telemetry.
	builtin bool @[json: '-']
pub:
	id             string
	event_name     HookEventName
	handler_type   HookHandlerType
	execution_mode HookExecutionMode
	scope          HookScope
	source_path    AbsolutePathBuf
	source         HookSource
	display_order  i64
	status         HookRunStatus
	status_message ?string
	started_at     i64
	completed_at   ?i64
	duration_ms    ?i64
	entries        []HookOutputEntry
}

pub struct HookStartedEvent {
pub:
	turn_id ?string
	run     HookRunSummary
}

pub struct HookCompletedEvent {
pub:
	turn_id ?string
	run     HookRunSummary
}

pub enum RealtimeConversationVersion {
	v1
	v2
	v3
}

pub enum CodexResponseHandoffMode {
	thinking
	commentary
	bem_tags
}

pub struct RealtimeConversationStartedEvent {
pub:
	realtime_session_id ?string
	version             RealtimeConversationVersion = .v2
}

pub struct RealtimeConversationRealtimeEvent {
pub:
	payload RealtimeEvent
}

pub struct RealtimeConversationClosedEvent {
pub:
	reason ?string
}

pub struct RealtimeConversationSdpEvent {
pub:
	sdp string
}

pub fn event_msg_from_collab_agent_spawn_begin(event CollabAgentSpawnBeginEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_agent_spawn_begin, collab_agent_spawn_begin_event: event }
}

pub fn event_msg_from_collab_agent_spawn_end(event CollabAgentSpawnEndEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_agent_spawn_end, collab_agent_spawn_end_event: event }
}

pub fn event_msg_from_collab_agent_interaction_begin(event CollabAgentInteractionBeginEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_agent_interaction_begin, collab_agent_interaction_begin_event: event }
}

pub fn event_msg_from_collab_agent_interaction_end(event CollabAgentInteractionEndEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_agent_interaction_end, collab_agent_interaction_end_event: event }
}

pub fn event_msg_from_collab_waiting_begin(event CollabWaitingBeginEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_waiting_begin, collab_waiting_begin_event: event }
}

pub fn event_msg_from_collab_waiting_end(event CollabWaitingEndEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_waiting_end, collab_waiting_end_event: event }
}

pub fn event_msg_from_collab_close_begin(event CollabCloseBeginEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_close_begin, collab_close_begin_event: event }
}

pub fn event_msg_from_collab_close_end(event CollabCloseEndEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_close_end, collab_close_end_event: event }
}

pub fn event_msg_from_collab_resume_begin(event CollabResumeBeginEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_resume_begin, collab_resume_begin_event: event }
}

pub fn event_msg_from_collab_resume_end(event CollabResumeEndEvent) EventMsg {
	return EventMsg{ msg_kind: .collab_resume_end, collab_resume_end_event: event }
}

pub fn event_msg_from_sub_agent_activity(event SubAgentActivityEvent) EventMsg {
	return EventMsg{ msg_kind: .sub_agent_activity, sub_agent_activity_event: event }
}

// Agent lifecycle status, derived from emitted events.
pub enum AgentStatusKind {
	// Agent is waiting for initialization.
	pending_init
	// Agent is currently running.
	running
	// Agent's current turn was interrupted and it may receive more input.
	interrupted
	// Agent is done. Contains the final assistant message.
	completed
	// Agent encountered an error.
	errored
	// Agent has been shutdown.
	shutdown
	// Agent is not found.
	not_found
}

pub struct AgentStatus {
pub:
	kind    AgentStatusKind
	message ?string
}

// Turn kinds that reject same-turn steering.
pub enum NonSteerableTurnKind {
	review
	compact
}

// Ownership-safe equivalent of `Option<NonSteerableTurnKind>`.
pub struct OptionalNonSteerableTurnKind {
pub:
	is_set bool
	value  NonSteerableTurnKind
}

// Codex errors that we expose to clients.
pub enum CodexErrorInfoKind {
	context_window_exceeded
	session_budget_exceeded
	usage_limit_exceeded
	rate_limit_exceeded
	server_overloaded
	cyber_policy
	misalignment_policy_violation
	http_connection_failed
	// Failed to connect to the response SSE stream.
	response_stream_connection_failed
	internal_server_error
	unauthorized
	bad_request
	sandbox_error
	// The response SSE stream disconnected in the middle of a turnbefore completion.
	response_stream_disconnected
	// Reached the retry limit for responses.
	response_too_many_failed_attempts
	// Returned when `turn/start` or `turn/steer` is submitted while the current active turn
	// cannot accept same-turn steering, for example `/review` or manual `/compact`.
	active_turn_not_steerable
	thread_rollback_failed
	other
}

pub struct CodexErrorInfo {
pub:
	kind             CodexErrorInfoKind
	http_status_code ?u16
	turn_kind        OptionalNonSteerableTurnKind
}

// Whether this error should mark the current turn as failed when replaying history.
pub fn (info &CodexErrorInfo) affects_turn_status() bool {
	return info.kind !in [.thread_rollback_failed, .active_turn_not_steerable]
}

pub struct RawResponseItemEvent {
pub:
	item ResponseItem
}

// Exact usage and metadata reported by one upstream Responses API completion.
//
// Unlike TokenCountEvent, this is not accumulated, estimated, or replayed.
pub struct RawResponseCompletedEvent {
pub:
	response_id    string
	token_usage    ?TokenUsage
	usage_metadata ?ResponseUsageMetadata
}

pub struct ItemStartedEvent {
pub:
	thread_id     ThreadId
	turn_id       string
	item          TurnItem
	started_at_ms i64
}

// V's decoder defaults missing numeric fields, so enforce the Rust wire contract explicitly.
pub fn item_started_event_from_json(encoded string) !ItemStartedEvent {
	value := json2.decode[json2.Any](encoded)!
	fields := value.as_map()
	if 'started_at_ms' !in fields {
		return error('missing field `started_at_ms`')
	}
	return json2.decode[ItemStartedEvent](encoded)
}

pub struct ItemCompletedEvent {
pub:
	thread_id     ThreadId
	turn_id       string
	item          TurnItem
	started_at_ms ?i64
	// Old rollout files may contain ItemCompleted events for PlanItem without
	// this field. Default to 0 so those persisted rollouts still deserialize
	// after tightening the core event contract.
	completed_at_ms i64
}

fn default_item_completed_at_ms() i64 {
	return 0
}

pub struct AgentMessageContentDeltaEvent {
pub:
	thread_id string
	turn_id   string
	item_id   string
	delta     string
}

pub struct PlanDeltaEvent {
pub:
	thread_id string
	turn_id   string
	item_id   string
	delta     string
}

pub struct ReasoningContentDeltaEvent {
pub:
	thread_id string
	turn_id   string
	item_id   string
	delta     string
	// load with default value so it's backward compatible with the old format.
	summary_index i64
}

pub struct ReasoningRawContentDeltaEvent {
pub:
	thread_id string
	turn_id   string
	item_id   string
	delta     string
	// load with default value so it's backward compatible with the old format.
	content_index i64
}

pub struct EnteredReviewModeEvent {
pub:
	target           ReviewTarget
	user_facing_hint ?string
	turn_id          ?string
	item_id          ?string
}

pub struct ExitedReviewModeEvent {
pub:
	turn_id       ?string
	item_id       ?string
	review_output ?ReviewOutputEvent
}

// Individual event payload types matching each `EventMsg` variant.

// Public, customer-facing details supplied by the Responses API for a misalignment block.
pub struct MisalignmentErrorDetails {
pub:
	// Open-ended classification; new values must not prevent the error from being surfaced.
	error_type ?string
	// A localized explanation is required before a client may offer continuation.
	detailed_explanation ?string
	// Model-visible instruction to submit if the user elects to continue.
	steer ?MisalignmentSteer
}

pub fn (details &MisalignmentErrorDetails) str() string {
	return 'MisalignmentErrorDetails{error_type: ${details.error_type}, has_detailed_explanation: ${details.detailed_explanation != none}, has_steer: ${details.steer != none}}'
}

// Public steering instruction returned alongside a resumable misalignment block.
pub struct MisalignmentSteer {
pub:
	message string
}

pub fn (steer &MisalignmentSteer) str() string {
	_ = steer
	return 'MisalignmentSteer{message: [REDACTED]}'
}

pub struct ErrorEvent {
pub:
	message          string
	codex_error_info ?CodexErrorInfo
	// Sensitive explanation and steering are delivered live but never enter rollout storage.
	misalignment ?MisalignmentErrorDetails @[json: '-']
}

// Whether this error should mark the current turn as failed when replaying history.
pub fn (event &ErrorEvent) affects_turn_status() bool {
	if info := event.codex_error_info {
		return info.affects_turn_status()
	}
	return true
}

pub struct WarningEvent {
pub:
	message string
}

// User-facing progress for provider-owned authentication recovery.
pub struct AuthRecoveryEvent {
pub:
	// Display name of the model provider whose authentication is recovering.
	provider string
	// User-facing description of the authentication recovery stage.
	message string
}

pub enum ModelRerouteReason {
	high_risk_cyber_activity
}

pub struct ModelRerouteEvent {
pub:
	from_model string
	to_model   string
	reason     ModelRerouteReason
}

pub enum ModelVerification {
	trusted_access_for_cyber
}

pub struct ModelVerificationEvent {
pub:
	verifications []ModelVerification
}

pub struct TurnModerationMetadataEvent {
pub:
	metadata json2.Any
}

pub struct SafetyBufferingEvent {
pub:
	model             string
	use_cases         []string
	reasons           []string
	show_buffering_ui bool
	faster_model      ?string
}

pub struct ContextCompactedEvent {
pub:
	marker bool
}

pub struct TurnCompleteEvent {
pub:
	turn_id            string
	last_agent_message ?string
	// Terminal error details when the turn completed unsuccessfully.
	error ?ErrorEvent
	// Unix timestamp (in seconds) when the turn started.
	started_at ?i64
	// Unix timestamp (in seconds) when the turn completed.
	completed_at ?i64
	// Duration between turn start and completion in milliseconds, if known.
	duration_ms ?i64
	// Duration between turn start and the first model token in milliseconds, if known.
	time_to_first_token_ms ?i64
}

pub struct TurnStartedEvent {
pub:
	turn_id string
	// Persist for rollout consumers that correlate turns with telemetry traces.
	trace_id ?string
	// Unix timestamp (in seconds) when the turn started.
	started_at ?i64
	// TODO(aibrahim): make this not optional
	model_context_window    ?i64
	collaboration_mode_kind ModeKind
}

pub struct ThreadSettingsAppliedEvent {
pub:
	// Logical task that owns this snapshot, independent of the physical rollout file.
	// Absent in older histories; copied snapshots retain their original owner's ID.
	thread_id       ?ThreadId
	thread_settings ThreadSettingsSnapshot
}

pub struct ThreadSettingsSnapshot {
pub:
	model                     string
	model_provider_id         string
	service_tier              ?string
	approval_policy           AskForApproval
	approvals_reviewer        ApprovalsReviewer
	permission_profile        PermissionProfile
	active_permission_profile ?ActivePermissionProfile
	cwd                       AbsolutePathBuf
	reasoning_effort          ?ReasoningEffortConfig
	reasoning_summary         ?ReasoningSummaryConfig
	personality               ?Personality
	collaboration_mode        CollaborationMode
}

pub struct TokenUsage {
pub mut:
	input_tokens             i64
	cached_input_tokens      i64
	cache_write_input_tokens i64
	output_tokens            i64
	reasoning_output_tokens  i64
	total_tokens             i64
	// Provider-reported units consumed from the shared rollout budget.
	codex_rollout_budget_units ?f64
}

// Best-effort Responses API usage observed for one completed response.
pub struct TokenUsageRecord {
pub:
	thread_id          ThreadId
	turn_id            string
	session_id         SessionId
	root_turn_id       string
	response_id        string
	usage              TokenUsage
	turn_token_usage   TokenUsage
	thread_token_usage TokenUsage
}

pub struct TokenUsageInfo {
pub mut:
	total_token_usage TokenUsage
	last_token_usage  TokenUsage
	// TODO(aibrahim): make this not optional
	model_context_window ?i64
}

// V has no usable `&Option<T>` equivalent: `&?T` cannot be constructed and `?&T`
// currently miscompiles in V3's C backend. These structs contain only numeric fields,
// so passing their optional values copies data and transfers no owned allocation.
pub fn token_usage_info_new_or_append(info ?TokenUsageInfo, last ?TokenUsage, model_context_window ?i64) ?TokenUsageInfo {
	mut has_value := false
	mut result := TokenUsageInfo{}
	if existing := info {
		result = existing
		has_value = true
	}
	if usage := last {
		result.append_last_usage(usage)
		has_value = true
	}
	if window := model_context_window {
		result.model_context_window = window
	}
	if !has_value {
		return none
	}
	return result
}

pub fn TokenUsageInfo.new_or_append(info ?TokenUsageInfo, last ?TokenUsage, model_context_window ?i64) ?TokenUsageInfo {
	return token_usage_info_new_or_append(info, last, model_context_window)
}

pub fn (mut info TokenUsageInfo) append_last_usage(last &TokenUsage) {
	info.total_token_usage.add_assign(last)
	info.last_token_usage = *last
}

pub fn (mut info TokenUsageInfo) fill_to_context_window(context_window i64) {
	previous_total := info.total_token_usage.total_tokens
	delta := max_i64(context_window - previous_total, 0)
	info.model_context_window = context_window
	info.total_token_usage = TokenUsage{ total_tokens: context_window }
	info.last_token_usage = TokenUsage{ total_tokens: delta }
}

pub fn full_context_window_token_usage_info(context_window i64) TokenUsageInfo {
	mut info := TokenUsageInfo{ model_context_window: context_window }
	info.fill_to_context_window(context_window)
	return info
}

pub fn TokenUsageInfo.full_context_window(context_window i64) TokenUsageInfo {
	return full_context_window_token_usage_info(context_window)
}

pub struct TokenCountEvent {
pub:
	info        ?TokenUsageInfo
	rate_limits ?RateLimitSnapshot
}

pub struct RateLimitSnapshot {
pub:
	limit_id   ?string
	limit_name ?string
	// Normal model metadata for a quota alias; never a replacement for the request model.
	normal_model_slug ?string
	primary           ?RateLimitWindow
	secondary         ?RateLimitWindow
	credits           ?CreditsSnapshot
	individual_limit  ?SpendControlLimitSnapshot
	// Backend-reported spend-control state. `None` is unavailable, not a sparse-update recovery.
	spend_control_reached   ?bool
	plan_type               ?account.PlanType
	rate_limit_reached_type ?RateLimitReachedType
}

pub enum RateLimitReachedType {
	rate_limit_reached
	workspace_owner_credits_depleted
	workspace_member_credits_depleted
	workspace_owner_usage_limit_reached
	workspace_member_usage_limit_reached
}

pub fn rate_limit_reached_type_from_str(value &string) !RateLimitReachedType {
	return match *value {
		'rate_limit_reached' { .rate_limit_reached }
		'workspace_owner_credits_depleted' { .workspace_owner_credits_depleted }
		'workspace_member_credits_depleted' { .workspace_member_credits_depleted }
		'workspace_owner_usage_limit_reached' { .workspace_owner_usage_limit_reached }
		'workspace_member_usage_limit_reached' { .workspace_member_usage_limit_reached }
		else { error('unknown rate limit reached type: ${*value}') }
	}
}

pub fn RateLimitReachedType.from_str(value &string) !RateLimitReachedType {
	return rate_limit_reached_type_from_str(value)
}

pub struct RateLimitWindow {
pub:
	// Percentage (0-100) of the window that has been consumed.
	used_percent f64
	// Rolling window duration, in minutes.
	window_minutes ?i64
	// Unix timestamp (seconds since epoch) when the window resets.
	resets_at ?i64
}

pub struct CreditsSnapshot {
pub:
	has_credits bool
	unlimited   bool
	balance     ?string
}

pub struct SpendControlLimitSnapshot {
pub:
	limit             string
	used              string
	remaining_percent i32
	resets_at         i64
}

// Includes prompts, tools and space to call compact.
const baseline_tokens = i64(12000)

fn max_i64(left i64, right i64) i64 {
	return if left > right { left } else { right }
}

pub fn (usage &TokenUsage) is_zero() bool {
	return usage.total_tokens == 0
}

pub fn (usage &TokenUsage) cached_input() i64 {
	return max_i64(usage.cached_input_tokens, 0)
}

pub fn (usage &TokenUsage) non_cached_input() i64 {
	return max_i64(usage.input_tokens - usage.cached_input(), 0)
}

// Primary count for display as a single absolute value: non-cached input + output.
pub fn (usage &TokenUsage) blended_total() i64 {
	return max_i64(usage.non_cached_input() + max_i64(usage.output_tokens, 0), 0)
}

pub fn (usage &TokenUsage) tokens_in_context_window() i64 {
	return usage.total_tokens
}

// Estimate the remaining user-controllable percentage of the model's context window.
//
// `context_window` is the total size of the model's context window.
// `BASELINE_TOKENS` should capture tokens that are always present in
// (The equivalent V constant is `baseline_tokens`.)
// the context (e.g., system prompt and fixed tool instructions) so that
// the percentage reflects the portion the user can influence.
//
// This normalizes both the numerator and denominator by subtracting the
// baseline, so immediately after the first prompt the UI shows 100% left
// and trends toward 0% as the user fills the effective window.
pub fn (usage &TokenUsage) percent_of_context_window_remaining(context_window i64) i64 {
	if context_window <= baseline_tokens {
		return 0
	}
	effective_window := context_window - baseline_tokens
	used := max_i64(usage.tokens_in_context_window() - baseline_tokens, 0)
	remaining := max_i64(effective_window - used, 0)
	percent := math.round((f64(remaining) / f64(effective_window)) * 100.0)
	return i64(math.max(0.0, math.min(100.0, percent)))
}

// In-place element-wise sum of token counts.
pub fn (mut usage TokenUsage) add_assign(other &TokenUsage) {
	usage.input_tokens += other.input_tokens
	usage.cached_input_tokens += other.cached_input_tokens
	usage.cache_write_input_tokens += other.cache_write_input_tokens
	usage.output_tokens += other.output_tokens
	usage.reasoning_output_tokens += other.reasoning_output_tokens
	usage.total_tokens += other.total_tokens
}

pub struct FinalOutput {
pub:
	token_usage TokenUsage
}

pub fn final_output_from_token_usage(token_usage TokenUsage) FinalOutput {
	return FinalOutput{ token_usage: token_usage }
}

pub fn FinalOutput.from(token_usage TokenUsage) FinalOutput {
	return final_output_from_token_usage(token_usage)
}

pub fn (output &FinalOutput) str() string {
	usage := output.token_usage
	cached_suffix := if usage.cached_input() > 0 {
		' (+ ${num_format.format_with_separators(usage.cached_input())} cached)'
	} else {
		''
	}
	reasoning_suffix := if usage.reasoning_output_tokens > 0 {
		' (reasoning ${num_format.format_with_separators(usage.reasoning_output_tokens)})'
	} else {
		''
	}
	return 'Token usage: total=${num_format.format_with_separators(usage.blended_total())} input=${num_format.format_with_separators(usage.non_cached_input())}${cached_suffix} output=${num_format.format_with_separators(usage.output_tokens)}${reasoning_suffix}'
}

pub struct AgentMessageEvent {
pub:
	message         string
	phase           ?MessagePhase
	memory_citation ?MemoryCitation
	delivery        ?AgentMessageDelivery
	questions       ?[]AsyncUserInputQuestion
}

// Ownership-safe equivalent of `Option<ImageDetail>` for elements stored in a V array.
pub struct OptionalImageDetail {
pub:
	has_value bool
	value     ImageDetail
}

// Ownership-safe equivalent of `Option<Vec<Value>>`.
pub struct OptionalJsonValues {
pub:
	is_set bool
	values []json2.Any
}

pub struct UserMessageEvent {
pub:
	client_id ?string
	message   string
	// Image URLs sourced from `UserInput::Image`. These are safe
	// to replay in legacy UI history events and correspond to images sent to
	// the model.
	images ?[]string
	// Detail hints for `images`, indexed in parallel. Missing entries imply
	// default image detail behavior.
	image_details []OptionalImageDetail
	// Local file paths sourced from `UserInput::LocalImage`. These are kept so
	// the UI can reattach images when editing history. Local image prompts may
	// include a display form of the path, but these should not be treated as
	// API-ready URLs.
	local_images []string
	// Detail hints for `local_images`, indexed in parallel. Missing entries
	// imply default image detail behavior.
	local_image_details []OptionalImageDetail
	// Audio URLs sourced from `UserInput::Audio`. These are safe to replay in
	// legacy UI history events and correspond to audio sent to the model.
	audio ?[]string
	// Local file paths sourced from `UserInput::LocalAudio`. These are kept so
	// clients can reattach audio when editing history and should not be
	// treated as API-ready URLs.
	local_audio []string
	// UI-defined spans within `message` used to render or persist special elements.
	text_elements []TextElement
}

// Returns the user-facing preview text for a user message.
pub fn user_message_preview(user &UserMessageEvent) ?string {
	message := strip_user_message_prefix(user.message)
	if message.len > 0 {
		return message
	}
	if images := user.images {
		if images.len > 0 {
			return '[Image]'
		}
	}
	if user.local_images.len > 0 {
		return '[Image]'
	}
	if audio := user.audio {
		if audio.len > 0 {
			return '[Audio]'
		}
	}
	if user.local_audio.len > 0 {
		return '[Audio]'
	}
	return none
}

pub struct AgentReasoningEvent {
pub:
	text string
}

pub struct AgentReasoningRawContentEvent {
pub:
	text string
}

pub struct AgentReasoningSectionBreakEvent {
pub:
	// load with default value so it's backward compatible with the old format.
	item_id       string
	summary_index i64
}

pub struct McpInvocation {
pub:
	// Name of the MCP server as defined in the config.
	server string
	// Name of the tool as given by the MCP server.
	tool string
	// Arguments to the tool call.
	arguments json2.Any
}

pub struct McpToolCallBeginEvent {
pub:
	// Identifier so this can be paired with the McpToolCallEnd event.
	call_id              string
	invocation           McpInvocation
	connector_id         ?string
	mcp_app_resource_uri ?string
	link_id              ?string
	app_name             ?string
	action_name          ?string
	plugin_id            ?string
	// Whether the selected tool is annotated as read-only, not its execution outcome.
	read_only_hint ?bool
}

// Duration is stored as nanoseconds and encoded as a string at protocol boundaries.
pub struct Duration {
pub:
	nanoseconds i64
}

pub struct McpToolCallEndEvent {
pub:
	// Identifier for the corresponding McpToolCallBegin that finished.
	call_id              string
	invocation           McpInvocation
	connector_id         ?string
	mcp_app_resource_uri ?string
	link_id              ?string
	app_name             ?string
	action_name          ?string
	plugin_id            ?string
	read_only_hint       ?bool
	duration             Duration
	// Result of the tool call. Note this could be an error.
	result       ?CallToolResult
	result_error ?string
}

pub struct DynamicToolCallResponseEvent {
pub:
	// Identifier for the corresponding DynamicToolCallRequest.
	call_id string
	// Turn ID that this dynamic tool call belongs to.
	turn_id         string
	completed_at_ms i64
	// Dynamic tool namespace, when one was provided.
	namespace ?string
	// Dynamic tool name.
	tool string
	// Dynamic tool call arguments.
	arguments json2.Any
	// Dynamic tool response content items.
	content_items []DynamicToolCallOutputContentItem
	// Whether the tool call succeeded.
	success bool
	// Optional error text when the tool call failed before producing a response.
	error ?string
	// The duration of the dynamic tool call.
	duration Duration
}

pub fn (event &McpToolCallEndEvent) is_success() bool {
	if result := event.result {
		if is_error := result.is_error {
			return !is_error
		}
		return true
	}
	return false
}

pub struct WebSearchBeginEvent {
pub:
	call_id string
}

pub struct WebSearchEndEvent {
pub:
	call_id string
	query   string
	action  WebSearchAction
	// Structured search results returned out-of-band by standalone web search.
	results OptionalJsonValues
}

pub struct ImageGenerationBeginEvent {
pub:
	call_id string
}

pub struct ImageGenerationEndEvent {
pub:
	call_id                string
	status                 string
	revised_prompt         ?string
	result                 string
	transparent_background ?bool
	failure                ?ImageGenerationFailure
	saved_path             ?AbsolutePathBuf
}

// Conversation kept for backward compatibility.
// Response payload for `Op::GetHistory` containing the current session's
// in-memory transcript.
pub struct ConversationPathResponseEvent {
pub:
	conversation_id ThreadId
	path            string
}

pub enum SessionSourceKind {
	cli
	vscode
	exec
	mcp
	custom
	internal
	sub_agent
	unknown
}

pub struct SessionSource {
pub:
	source_kind SessionSourceKind = .vscode
	custom      string
	internal    ?InternalSessionSource
	sub_agent   ?SubAgentSource
}

pub enum ThreadSourceKind {
	user
	subagent
	guardian_review
	feature
	memory_consolidation
}

pub struct ThreadSource {
pub:
	source_kind ThreadSourceKind
	feature     string
}

pub fn (source &ThreadSource) as_str() string {
	return if source.source_kind == .feature { source.feature } else { source.source_kind.str() }
}

pub fn (source &ThreadSource) str() string {
	return source.as_str()
}

pub fn thread_source_from_str(value &string) ThreadSource {
	return match *value {
		'user' { ThreadSource{ source_kind: .user } }
		'subagent' { ThreadSource{ source_kind: .subagent } }
		'guardian_review' { ThreadSource{ source_kind: .guardian_review } }
		'memory_consolidation' { ThreadSource{ source_kind: .memory_consolidation } }
		else { ThreadSource{ source_kind: .feature, feature: *value } }
	}
}

pub fn ThreadSource.from_str(value &string) ThreadSource {
	return thread_source_from_str(value)
}

pub fn ThreadSource.try_from(value string) ThreadSource {
	return thread_source_from_str(value)
}

pub enum InternalSessionSource {
	memory_consolidation
	guardian
}

pub enum SubAgentSourceKind {
	review
	compact
	thread_spawn
	memory_consolidation
	other
}

pub struct SubAgentSource {
pub:
	source_kind      SubAgentSourceKind
	parent_thread_id ?ThreadId
	depth            i32
	agent_path       ?AgentPath
	agent_nickname   ?string
	agent_role       ?string
	other            string
}

pub fn (source &SessionSource) str() string {
	return match source.source_kind {
		.cli { 'cli' }
		.vscode { 'vscode' }
		.exec { 'exec' }
		.mcp { 'mcp' }
		.custom { source.custom }
		.internal {
			if value := source.internal { 'internal_${value}' } else { 'internal_unknown' }
		}
		.sub_agent {
			if value := source.sub_agent { 'subagent_${value}' } else { 'subagent_unknown' }
		}
		.unknown { 'unknown' }
	}
}

pub fn session_source_from_startup_arg(value &string) !SessionSource {
	trimmed := value.trim_space()
	if trimmed.len == 0 {
		return error('session source must not be empty')
	}
	normalized := trimmed.to_lower()
	return match normalized {
		'cli' { SessionSource{ source_kind: .cli } }
		'vscode' { SessionSource{ source_kind: .vscode } }
		'exec' { SessionSource{ source_kind: .exec } }
		'mcp', 'appserver', 'app-server', 'app_server' { SessionSource{ source_kind: .mcp } }
		'unknown' { SessionSource{ source_kind: .unknown } }
		else { SessionSource{ source_kind: .custom, custom: normalized } }
	}
}

pub fn SessionSource.from_startup_arg(value &string) !SessionSource {
	return session_source_from_startup_arg(value)
}

pub fn (source &SessionSource) is_internal() bool {
	return source.source_kind == .internal
}

pub fn (source &SessionSource) is_non_root_agent() bool {
	return source.source_kind in [.internal, .sub_agent]
}

pub fn (source &SessionSource) get_nickname() ?string {
	if subagent := source.sub_agent {
		return subagent.agent_nickname
	}
	return none
}

pub fn (source &SessionSource) get_agent_role() ?string {
	if subagent := source.sub_agent {
		return subagent.agent_role
	}
	return none
}

pub fn (source &SessionSource) get_agent_path() ?AgentPath {
	if subagent := source.sub_agent {
		return subagent.agent_path
	}
	return none
}

pub fn (source &SessionSource) restriction_product() ?Product {
	return match source.source_kind {
		.custom { product_from_session_source_name(source.custom) }
		.cli, .vscode, .exec, .mcp, .unknown { Product.codex }
		.internal, .sub_agent { none }
	}
}

pub fn (source &SessionSource) matches_product_restriction(products &[]Product) bool {
	if products.len == 0 {
		return true
	}
	if product := source.restriction_product() {
		return product.matches_product_restriction(products)
	}
	return false
}

pub fn (source &SessionSource) parent_thread_id() ?ThreadId {
	if subagent := source.sub_agent {
		return subagent.parent_thread_id_value()
	}
	return none
}

pub fn (source &SubAgentSource) str() string {
	return match source.source_kind {
		.review { 'review' }
		.compact { 'compact' }
		.memory_consolidation { 'memory_consolidation' }
		.thread_spawn {
			if parent := source.parent_thread_id {
				'thread_spawn_${parent}_d${source.depth}'
			} else {
				'thread_spawn_unknown_d${source.depth}'
			}
		}
		.other { source.other }
	}
}

pub fn (source &SubAgentSource) kind() string {
	return if source.source_kind == .other { source.other } else { source.source_kind.str() }
}

pub fn (source &SubAgentSource) parent_thread_id_value() ?ThreadId {
	if source.source_kind == .thread_spawn {
		return source.parent_thread_id
	}
	return none
}

pub fn (source InternalSessionSource) str() string {
	return match source {
		.memory_consolidation { 'memory_consolidation' }
		.guardian { 'guardian' }
	}
}

pub enum MultiAgentVersion {
	disabled
	v1
	v2
}

pub struct SessionContextWindow {
pub:
	// UUIDv7 identity of this context window.
	window_id string
}

pub fn new_session_context_window(window_id string) SessionContextWindow {
	return SessionContextWindow{ window_id: window_id }
}

pub fn SessionContextWindow.new(window_id string) SessionContextWindow {
	return new_session_context_window(window_id)
}

// Exclusive position in another rollout's paginated history.
pub struct HistoryPosition {
pub:
	// Rollout ID for the immutable prefix file.
	//
	// `HistoryPosition` predates `thread/revert`, so this field is named `thread_id`. Treat its
	// value as a `rollout_id`: ordinary rollouts use the thread ID as their rollout ID, while a
	// reverted thread's filename carries a distinct rollout ID. It is not necessarily
	// [`SessionMeta::id`], which remains the stable thread ID across revert.
	thread_id ThreadId
	// First rollout ordinal not included from the prefix file.
	end_ordinal_exclusive u64
	// Byte offset immediately after the last included JSONL record from the prefix file.
	end_byte_offset u64
}

// SessionMeta contains session-level data that doesn't correspond to a specific turn.
//
// NOTE: There used to be an `instructions` field here, which stored user_instructions, but we
// now save that on TurnContext. base_instructions stores the base instructions for the session,
// and should be used when there is no config override.
pub struct SessionMeta {
pub:
	// session_id is equal to the root thread's ID.
	session_id     SessionId
	id             ThreadId
	forked_from_id ?ThreadId
	// Exclusive ordinal inherited from the logical fork parent, independent of `history_base`.
	// Revert may replace the physical history base while retaining this fork boundary.
	forked_from_ordinal_exclusive ?u64
	parent_thread_id              ?ThreadId
	timestamp                     string
	cwd                           string
	originator                    string
	cli_version                   string
	source                        SessionSource
	// Optional analytics source classification for this thread.
	thread_source ?ThreadSource
	// Optional random unique nickname assigned to an AgentControl-spawned sub-agent.
	agent_nickname ?string
	// Optional role (agent_role) assigned to an AgentControl-spawned sub-agent.
	agent_role ?string
	// Optional canonical agent path assigned to an AgentControl-spawned sub-agent.
	agent_path     ?string
	model_provider ?string
	// base_instructions for the session. This *should* always be present when creating a new session,
	// but may be missing for older sessions. If not present, fall back to rendering the base_instructions
	// from ModelsManager.
	base_instructions ?BaseInstructions
	dynamic_tools     ?[]DynamicToolSpec
	// Capability roots selected for this thread by the hosting platform.
	selected_capability_roots []SelectedCapabilityRoot
	memory_mode               ?string
	history_mode              ThreadHistoryMode
	// Exclusive prefix of another paginated rollout inherited by this thread.
	history_base ?HistoryPosition
	// First rollout ordinal that belongs to this subagent's own projected history.
	//
	// Earlier rollout records are inherited model context and stay out of child
	// turn/item projection.
	subagent_history_start_ordinal ?u64
	multi_agent_version            ?MultiAgentVersion
	// Initial context-window identity for consumers that tail rollout JSONL before compaction.
	context_window ?SessionContextWindow
}

pub fn default_session_meta() SessionMeta {
	id := ThreadId{}
	return SessionMeta{
		session_id:   SessionId{ value: id.value }
		id:           id
		source:       SessionSource{ source_kind: .vscode }
		history_mode: .legacy
	}
}

pub fn SessionMeta.default() SessionMeta {
	return default_session_meta()
}

pub struct SessionMetaLine {
pub:
	meta SessionMeta
	git  ?GitInfo
}

// Preserves compatibility with metadata written before `session_id` was introduced.
pub fn session_meta_line_from_json(encoded string) !SessionMetaLine {
	mut value := json2.decode[json2.Any](encoded)!
	mut fields := value.as_map()
	if 'session_id' !in fields {
		if id := fields['id'] {
			fields['session_id'] = id
		} else {
			return error('missing field `id`')
		}
	}
	value = fields
	return json2.decode[SessionMetaLine](value.str())
}

pub fn SessionMetaLine.deserialize(encoded string) !SessionMetaLine {
	return session_meta_line_from_json(encoded)
}

// Persisted comparison state used to resume model-visible world-state diffing.
pub struct WorldStateItem {
pub:
	// Full snapshots establish a new baseline; patches update the current baseline.
	full  bool
	state map[string]json2.Any
}

pub fn full_world_state_item(state map[string]json2.Any) WorldStateItem {
	return WorldStateItem{ full: true, state: state }
}

pub fn WorldStateItem.full(state map[string]json2.Any) WorldStateItem {
	return full_world_state_item(state)
}

pub fn patch_world_state_item(state map[string]json2.Any) WorldStateItem {
	return WorldStateItem{ full: false, state: state }
}

pub fn WorldStateItem.patch(state map[string]json2.Any) WorldStateItem {
	return patch_world_state_item(state)
}

pub struct TurnContextNetworkItem {
pub:
	allowed_domains []string
	denied_domains  []string
}

// Persist once per real user turn after computing that turn's model-visible
// context updates, and again after mid-turn compaction when replacement
// history re-establishes full context, so resume/fork replay can recover the
// latest durable baseline.
pub struct TurnContextItem {
pub:
	turn_id ?string
	// Root turn that owns this subagent turn's attribution.
	// Only set for subagent turns; persisted so resume keeps the scope frozen at turn start.
	root_turn_id ?string
	cwd          AbsolutePathBuf
	// Effective workspace roots used to materialize symbolic
	// `:workspace_roots` filesystem permissions in `permission_profile`.
	workspace_roots          ?[]AbsolutePathBuf
	current_date             ?string
	timezone                 ?string
	approval_policy          AskForApproval
	approvals_reviewer       ?ApprovalsReviewer
	sandbox_policy           SandboxPolicy
	permission_profile_value ?PermissionProfile
	// Built-in or named profile that produced `permission_profile`, when known.
	active_permission_profile  ?ActivePermissionProfile
	network                    ?TurnContextNetworkItem
	file_system_sandbox_policy ?RawFileSystemSandboxPolicy
	model                      string
	comp_hash                  ?string
	personality                ?Personality
	collaboration_mode         ?CollaborationMode
	multi_agent_version        ?MultiAgentVersion
	// Legacy effective model-visible mode retained to deserialize older rollouts.
	multi_agent_mode     ?MultiAgentMode
	realtime_active      ?bool
	cyber_access_program ?CyberAccessProgram
	effort               ?ReasoningEffortConfig
	// Compatibility-only field written with a default value so older Codex
	// versions can deserialize turn-context rollout items. It is no longer
	// read by context reconstruction and should be removed in a future schema
	// cleanup.
	summary ReasoningSummaryConfig
}

pub fn (item &TurnContextItem) permission_profile() PermissionProfile {
	if profile := item.permission_profile_value {
		return profile
	}
	mut file_system := permissions.from_legacy_sandbox_policy_for_cwd(item.sandbox_policy.policy_kind.str(), item.cwd.path)
	if raw := item.file_system_sandbox_policy {
		file_system = permissions.from_raw(raw) or {
			permissions.restricted([]permissions.FileSystemSandboxEntry{})
		}
	}
	network := permissions.network_from_legacy(item.sandbox_policy.policy_kind.str(), item.sandbox_policy.has_full_network_access())
	return models.permission_profile_from_runtime_permissions(models.sandbox_enforcement_from_legacy(item.sandbox_policy.policy_kind.str()), file_system, network)
}

pub enum TruncationPolicyKind {
	bytes
	tokens
}

pub struct TruncationPolicy {
pub:
	kind  TruncationPolicyKind
	limit usize
}

pub fn truncation_policy_from_config(config openai_models.TruncationPolicyConfig) TruncationPolicy {
	return TruncationPolicy{
		kind:  if config.mode == .bytes { .bytes } else { .tokens }
		limit: usize(config.limit)
	}
}

pub fn TruncationPolicy.from(config openai_models.TruncationPolicyConfig) TruncationPolicy {
	return truncation_policy_from_config(config)
}

pub fn (policy &TruncationPolicy) token_budget() usize {
	return match policy.kind {
		.bytes {
			value := codex_utils_string.approx_tokens_from_byte_count(policy.limit)
			if value < 0 { usize(0) } else { usize(value) }
		}
		.tokens { policy.limit }
	}
}

pub fn (policy &TruncationPolicy) byte_budget() usize {
	return match policy.kind {
		.bytes { policy.limit }
		.tokens { codex_utils_string.approx_bytes_for_tokens(policy.limit) }
	}
}

pub fn (policy TruncationPolicy) multiply(multiplier f64) TruncationPolicy {
	return TruncationPolicy{ kind: policy.kind, limit: usize(math.ceil(f64(policy.limit) * multiplier)) }
}

pub fn (policy TruncationPolicy) mul(multiplier f64) TruncationPolicy {
	return policy.multiply(multiplier)
}

pub struct GitInfo {
pub:
	// Current commit hash (SHA)
	commit_hash ?GitSha
	// Current branch name
	branch ?string
	// Repository URL (if available from remote)
	repository_url ?SanitizedGitUrl
}

pub enum ReviewDelivery {
	inline
	detached
}

pub enum ReviewTargetKind {
	// Review the working tree: staged, unstaged, and untracked files.
	uncommitted_changes
	// Review changes between the current branch and the given base branch.
	base_branch
	// Review the changes introduced by a specific commit.
	commit
	// Arbitrary instructions provided by the user.
	custom
}

pub struct ReviewTarget {
pub:
	kind   ReviewTargetKind
	branch string
	sha    string
	// Optional human-readable label (e.g., commit subject) for UIs.
	title        ?string
	instructions string
}

// Review request sent to the review session.
pub struct ReviewRequest {
pub:
	target           ReviewTarget
	user_facing_hint ?string
}

// Structured review result produced by a child review session.
pub struct ReviewOutputEvent {
pub:
	findings                 []ReviewFinding
	overall_correctness      string
	overall_explanation      string
	overall_confidence_score f32
}

pub fn default_review_output_event() ReviewOutputEvent {
	return ReviewOutputEvent{}
}

pub fn ReviewOutputEvent.default() ReviewOutputEvent {
	return default_review_output_event()
}

// A single review finding describing an observed issue or recommendation.
pub struct ReviewFinding {
pub:
	title            string
	body             string
	confidence_score f32
	priority         i32
	code_location    ReviewCodeLocation
}

// Location of the code related to a review finding.
pub struct ReviewCodeLocation {
pub:
	absolute_file_path string
	line_range         ReviewLineRange
}

// Inclusive line range in a file associated with the finding.
pub struct ReviewLineRange {
pub:
	start u32
	end   u32
}

pub enum ExecCommandSource {
	agent
	user_shell
	unified_exec_startup
	unified_exec_interaction
}

pub enum ExecCommandStatus {
	completed
	failed
	declined
}

pub struct ExecCommandBeginEvent {
pub:
	// Identifier so this can be paired with the ExecCommandEnd event.
	call_id string
	// Trusted first-party plugin attributed to this command, when known.
	plugin_id ?string
	// Safe plugin-relative path attributed to this command, when known.
	script_path ?string
	// Identifier for the underlying PTY process (when available).
	process_id ?string
	// Turn ID that this command belongs to.
	turn_id       string
	started_at_ms i64
	// The command to be executed.
	command []string
	// The command's working directory if not the default cwd for the agent.
	cwd        PathUri
	parsed_cmd []ParsedCommand
	// Where the command originated. Defaults to Agent for backward compatibility.
	source ExecCommandSource
	// Raw input sent to a unified exec session (if this is an interaction event).
	interaction_input ?string
}

pub struct ExecCommandEndEvent {
pub:
	// Identifier for the ExecCommandBegin that finished.
	call_id string
	// Trusted first-party plugin attributed to this command, when known.
	plugin_id ?string
	// Safe plugin-relative path attributed to this command, when known.
	script_path ?string
	// Identifier for the underlying PTY process (when available).
	process_id ?string
	// Turn ID that this command belongs to.
	turn_id         string
	completed_at_ms i64
	// The command that was executed.
	command []string
	// The command's working directory if not the default cwd for the agent.
	cwd        PathUri
	parsed_cmd []ParsedCommand
	// Where the command originated. Defaults to Agent for backward compatibility.
	source ExecCommandSource
	// Raw input sent to a unified exec session (if this is an interaction event).
	interaction_input ?string
	// Captured stdout
	stdout string
	// Captured stderr
	stderr string
	// Captured aggregated output
	aggregated_output string
	// The command's exit code.
	exit_code i32
	// The duration of the command execution.
	duration Duration
	// Formatted output from the command, as seen by the model.
	formatted_output string
	// Completion status for this command execution.
	status ExecCommandStatus
}

pub struct ViewImageToolCallEvent {
pub:
	// Identifier for the originating tool call.
	call_id string
	// Filesystem path resolved for the selected environment.
	//
	// This core event is not exposed directly in the app-server API. App-server
	// converts the path to `LegacyAppPathString` when building its public item.
	path PathUri
}

pub enum ExecOutputStream {
	stdout
	stderr
}

pub struct ExecCommandOutputDeltaEvent {
pub:
	// Identifier for the ExecCommandBegin that produced this chunk.
	call_id string
	// Which stream produced this chunk.
	stream ExecOutputStream
	// Raw bytes from the stream (may not be valid UTF-8).
	chunk []u8
}

pub struct TerminalInteractionEvent {
pub:
	// Identifier for the ExecCommandBegin that produced this chunk.
	call_id string
	// Process id associated with the running command.
	process_id string
	// Stdin sent to the running session.
	stdin string
}

pub struct DeprecationNoticeEvent {
pub:
	// Concise summary of what is deprecated.
	summary string
	// Optional extra guidance, such as migration steps or rationale.
	details ?string
}

pub struct ThreadRolledBackEvent {
pub:
	// Number of user turns that were removed from context.
	num_turns u32
}

pub struct StreamErrorEvent {
pub:
	message          string
	codex_error_info ?CodexErrorInfo
	// Optional details about the underlying stream failure (often the same
	// human-readable message that is surfaced as the terminal error if retries
	// are exhausted).
	additional_details ?string
}

pub struct StreamInfoEvent {
pub:
	message string
}

pub struct PatchApplyBeginEvent {
pub:
	// Identifier so this can be paired with the PatchApplyEnd event.
	call_id string
	// Turn ID that this patch belongs to.
	// Uses `#[serde(default)]` for backwards compatibility.
	turn_id string
	// If true, there was no ApplyPatchApprovalRequest for this patch.
	auto_approved bool
	// The changes to be applied.
	changes map[string]FileChange
}

pub struct PatchApplyUpdatedEvent {
pub:
	// Identifier for the originating `apply_patch` tool call.
	call_id string
	// Structured file changes parsed from the model-generated patch input so far.
	changes map[string]FileChange
}

pub struct PatchApplyEndEvent {
pub:
	// Identifier for the PatchApplyBegin that finished.
	call_id string
	// Turn ID that this patch belongs to.
	// Uses `#[serde(default)]` for backwards compatibility.
	turn_id string
	// Captured stdout (summary printed by apply_patch).
	stdout string
	// Captured stderr (parser errors, IO failures, etc.).
	stderr string
	// Whether the patch was applied successfully.
	success bool
	// The changes that were applied (mirrors PatchApplyBeginEvent::changes).
	changes map[string]FileChange
	// Completion status for this patch application.
	status PatchApplyStatus
}

pub enum PatchApplyStatus {
	completed
	failed
	declined
}

pub struct TurnDiffEvent {
pub:
	unified_diff string
}

pub struct McpStartupUpdateEvent {
pub:
	// Server name being started.
	server string
	// Current startup status.
	status McpStartupStatus
}

pub enum McpStartupStatusKind {
	starting
	ready
	failed
	cancelled
}

pub struct McpStartupStatus {
pub:
	kind   McpStartupStatusKind
	error  string
	reason OptionalMcpStartupFailureReason
}

pub enum McpStartupFailureReason {
	reauthentication_required
}

// Ownership-safe equivalent of `Option<McpStartupFailureReason>`.
pub struct OptionalMcpStartupFailureReason {
pub:
	is_set bool
	value  McpStartupFailureReason
}

pub struct McpStartupCompleteEvent {
pub:
	ready     []string
	failed    []McpStartupFailure
	cancelled []string
}

pub struct McpStartupFailure {
pub:
	server string
	error  string
}

pub enum McpAuthStatus {
	unknown
	unsupported
	not_logged_in
	bearer_token
	oauth
}

pub fn (status &McpAuthStatus) display() string {
	return match *status {
		.unknown { 'Unknown' }
		.unsupported { 'Unsupported' }
		.not_logged_in { 'Not logged in' }
		.bearer_token { 'Bearer token' }
		.oauth { 'OAuth' }
	}
}

pub struct RealtimeConversationListVoicesResponseEvent {
pub:
	voices RealtimeVoicesList
}

pub enum Product {
	chatgpt
	codex
	atlas
}

pub fn (product Product) to_app_platform() string {
	return match product {
		.chatgpt { 'chat' }
		.codex { 'codex' }
		.atlas { 'atlas' }
	}
}

pub fn product_from_session_source_name(value &string) ?Product {
	return match value.trim_space().to_lower() {
		'chatgpt' { Product.chatgpt }
		'codex' { Product.codex }
		'atlas' { Product.atlas }
		else { none }
	}
}

pub fn Product.from_session_source_name(value &string) ?Product {
	return product_from_session_source_name(value)
}

pub fn (product &Product) matches_product_restriction(products &[]Product) bool {
	return products.len == 0 || *product in *products
}

pub enum SkillScope {
	user
	repo
	system
	admin
}

pub struct SkillMetadata {
pub:
	name        string
	description string
	// Legacy short_description from SKILL.md. Prefer SKILL.json interface.short_description.
	short_description ?string
	interface         ?SkillInterface
	dependencies      ?SkillDependencies
	path              AbsolutePathBuf
	scope             SkillScope
	enabled           bool
}

pub struct SkillInterface {
pub:
	display_name      ?string
	short_description ?string
	icon_small        ?AbsolutePathBuf
	icon_large        ?AbsolutePathBuf
	brand_color       ?string
	default_prompt    ?string
}

pub struct SkillDependencies {
pub:
	tools []SkillToolDependency
}

pub struct SkillToolDependency {
pub:
	type_name   string @[json: 'type']
	value       string
	description ?string
	transport   ?string
	command     ?string
	url         ?string
}

pub struct SessionNetworkProxyRuntime {
pub:
	http_addr  string
	socks_addr string
}

pub struct SessionConfiguredEvent {
pub:
	session_id       SessionId
	thread_id        ThreadId
	forked_from_id   ?ThreadId
	parent_thread_id ?ThreadId
	// Optional analytics source classification for this thread.
	thread_source ?ThreadSource
	// Optional user-facing thread name (may be unset).
	thread_name ?string
	// Tell the client what model is being queried.
	model             string
	model_provider_id string
	service_tier      ?string
	// When to escalate for approval for execution
	approval_policy AskForApproval
	// Configures who approval requests are routed to for review once they have
	// been escalated. This does not disable separate safety checks such as
	// ARC.
	approvals_reviewer ApprovalsReviewer
	// Canonical effective permissions for commands executed in the session.
	permission_profile PermissionProfile
	// Named or implicit built-in profile that produced `permission_profile`,
	// when known.
	active_permission_profile ?ActivePermissionProfile
	// Working directory that should be treated as the *root* of the
	// session.
	cwd AbsolutePathBuf
	// The effort the model is putting into reasoning about the user's request.
	reasoning_effort ?ReasoningEffortConfig
	// Optional initial messages (as events) for resumed sessions.
	// When present, UIs can use these to seed the history.
	initial_messages ?[]EventMsg
	// Runtime proxy bind addresses, when the managed proxy was started for this session.
	network_proxy ?SessionNetworkProxyRuntime
	// Path in which the rollout is stored. Can be `None` for ephemeral threads
	rollout_path ?string
}

pub fn session_configured_event_from_json(encoded string) !SessionConfiguredEvent {
	mut decoded := json2.decode[SessionConfiguredEventWire](encoded)!
	mut permission_profile := PermissionProfile{}
	if profile := decoded.permission_profile {
		permission_profile = profile
	} else if sandbox := decoded.sandbox_policy {
		file_system := permissions.from_legacy_sandbox_policy_for_cwd(sandbox.policy_kind.str(), decoded.cwd.path)
		network := permissions.network_from_legacy(sandbox.policy_kind.str(), sandbox.has_full_network_access())
		permission_profile = models.permission_profile_from_runtime_permissions(models.sandbox_enforcement_from_legacy(sandbox.policy_kind.str()), file_system, network)
	} else {
		return error('missing field `permission_profile`')
	}
	thread_id := if value := decoded.thread_id {
		value
	} else {
		ThreadId{ value: decoded.session_id.value }
	}
	return SessionConfiguredEvent{
		session_id:                decoded.session_id
		thread_id:                 thread_id
		forked_from_id:            decoded.forked_from_id
		parent_thread_id:          decoded.parent_thread_id
		thread_source:             decoded.thread_source
		thread_name:               decoded.thread_name
		model:                     decoded.model
		model_provider_id:         decoded.model_provider_id
		service_tier:              decoded.service_tier
		approval_policy:           decoded.approval_policy
		approvals_reviewer:        decoded.approvals_reviewer
		permission_profile:        permission_profile
		active_permission_profile: decoded.active_permission_profile
		cwd:                       decoded.cwd
		reasoning_effort:          decoded.reasoning_effort
		initial_messages:          decoded.initial_messages
		network_proxy:             decoded.network_proxy
		rollout_path:              decoded.rollout_path
	}
}

pub fn SessionConfiguredEvent.deserialize(encoded string) !SessionConfiguredEvent {
	return session_configured_event_from_json(encoded)
}

struct SessionConfiguredEventWire {
	session_id         SessionId
	thread_id          ?ThreadId
	forked_from_id     ?ThreadId
	parent_thread_id   ?ThreadId
	thread_source      ?ThreadSource
	thread_name        ?string
	model              string
	model_provider_id  string
	service_tier       ?string
	approval_policy    AskForApproval
	approvals_reviewer ApprovalsReviewer
	// `SessionConfiguredEvent` is persisted into rollout history. Older
	// rollouts only have `sandbox_policy`, so accept it on deserialize
	// and immediately project it into the canonical `permission_profile`.
	sandbox_policy            ?SandboxPolicy
	permission_profile        ?PermissionProfile
	active_permission_profile ?ActivePermissionProfile
	cwd                       AbsolutePathBuf
	reasoning_effort          ?ReasoningEffortConfig
	initial_messages          ?[]EventMsg
	network_proxy             ?SessionNetworkProxyRuntime
	rollout_path              ?string
}

pub enum ThreadGoalStatus {
	active
	paused
	blocked
	usage_limited
	budget_limited
	complete
}

pub const max_thread_goal_objective_chars = 4_000

pub fn validate_thread_goal_objective(value &string) ! {
	if value.len == 0 {
		return error('goal objective must not be empty')
	}
	if value.runes().len > max_thread_goal_objective_chars {
		return error('goal objective must be at most ${max_thread_goal_objective_chars} characters')
	}
}

pub struct ThreadGoal {
pub:
	thread_id         ThreadId
	objective         string
	status            ThreadGoalStatus
	token_budget      ?i64
	tokens_used       i64
	time_used_seconds i64
	created_at        i64
	updated_at        i64
}

pub struct ThreadGoalUpdatedEvent {
pub:
	thread_id ThreadId
	turn_id   ?string
	goal      ThreadGoal
}

pub struct ThreadQueueChangedEvent {
pub:
	thread_id ThreadId
}

// User's decision in response to an ExecApprovalRequest.
pub enum ReviewDecisionKind {
	// User has approved this command and the agent should execute it.
	approved
	// User has approved this command and wants to apply the proposed execpolicy
	// amendment so future matching commands are permitted.
	approved_execpolicy_amendment
	// User has approved this request and wants future prompts in the same
	// session-scoped approval cache to be automatically approved for the
	// remainder of the session.
	approved_for_session
	// User has approved this MCP tool call and wants to amend its policy so
	// matching future calls are automatically approved across sessions.
	approved_mcp_policy_amendment
	// User chose to persist a network policy rule (allow/deny) for future
	// requests to the same host.
	network_policy_amendment
	// User has denied this command and the agent should not execute it, but
	// it should continue the session and try something else.
	denied
	// Automatic approval review timed out before reaching a decision.
	timed_out
	// User has denied this command and the agent should not do anything until
	// the user's next command.
	abort
}

pub struct ReviewDecision {
pub:
	kind                          ReviewDecisionKind = .denied
	proposed_execpolicy_amendment ?ExecPolicyAmendment
	network_policy_amendment      ?NetworkPolicyAmendment
	rejection                     string = 'denied'
}

pub fn denied_review_decision(rejection string) ReviewDecision {
	return ReviewDecision{ kind: .denied, rejection: rejection }
}

pub fn ReviewDecision.default() ReviewDecision {
	return ReviewDecision{ kind: .denied, rejection: 'denied' }
}

pub fn ReviewDecision.denied(rejection string) ReviewDecision {
	return denied_review_decision(rejection)
}

// Returns an opaque version of the decision without PII. We can't use an ignored flag
// on `serde` because the serialization is required by some surfaces.
pub fn (decision &ReviewDecision) to_opaque_string() string {
	return match decision.kind {
		.approved { 'approved' }
		.approved_execpolicy_amendment { 'approved_with_amendment' }
		.approved_for_session { 'approved_for_session' }
		.approved_mcp_policy_amendment { 'approved_mcp_policy_amendment' }
		.network_policy_amendment {
			if amendment := decision.network_policy_amendment {
				if amendment.action == .allow {
					'approved_with_network_policy_allow'
				} else {
					'denied_with_network_policy_deny'
				}
			} else {
				'denied_with_network_policy_deny'
			}
		}
		.denied { 'denied' }
		.timed_out { 'timed_out' }
		.abort { 'abort' }
	}
}

pub enum FileChangeKind {
	add
	delete
	update
}

pub struct FileChange {
pub:
	kind         FileChangeKind
	content      string
	unified_diff string
	move_path    ?string
}

pub struct Chunk {
pub:
	// 1-based line index of the first line in the original file
	orig_index     u32
	deleted_lines  []string
	inserted_lines []string
}

pub struct TurnAbortedEvent {
pub:
	turn_id ?string
	reason  TurnAbortReason
	// Unix timestamp (in seconds) when the turn started.
	started_at ?i64
	// Unix timestamp (in seconds) when the turn was aborted.
	completed_at ?i64
	// Duration between turn start and abort in milliseconds, if known.
	duration_ms ?i64
}

pub enum TurnAbortReason {
	interrupted
	replaced
	review_ended
	budget_limited
}

pub struct CollabAgentSpawnBeginEvent {
pub:
	// Identifier for the collab tool call.
	call_id       string
	started_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Initial prompt sent to the agent. Can be empty to prevent CoT leaking at the
	// beginning.
	prompt           string
	model            string
	reasoning_effort ReasoningEffortConfig
}

pub struct CollabAgentRef {
pub:
	// Thread ID of the receiver/new agent.
	thread_id ThreadId
	// Optional nickname assigned to an AgentControl-spawned sub-agent.
	agent_nickname ?string
	// Optional role (agent_role) assigned to an AgentControl-spawned sub-agent.
	agent_role ?string
}

pub struct CollabAgentStatusEntry {
pub:
	// Thread ID of the receiver/new agent.
	thread_id ThreadId
	// Optional nickname assigned to an AgentControl-spawned sub-agent.
	agent_nickname ?string
	// Optional role (agent_role) assigned to an AgentControl-spawned sub-agent.
	agent_role ?string
	// Last known status of the agent.
	status AgentStatus
}

pub struct CollabAgentSpawnEndEvent {
pub:
	// Identifier for the collab tool call.
	call_id         string
	completed_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the newly spawned agent, if it was created.
	new_thread_id ?ThreadId
	// Optional nickname assigned to the new agent.
	new_agent_nickname ?string
	// Optional role assigned to the new agent.
	new_agent_role ?string
	// Initial prompt sent to the agent. Can be empty to prevent CoT leaking at the
	// beginning.
	prompt string
	// Effective model used by the spawned agent after inheritance and role overrides.
	model string
	// Effective reasoning effort used by the spawned agent after inheritance and role overrides.
	reasoning_effort ReasoningEffortConfig
	// Last known status of the new agent reported to the sender agent.
	status AgentStatus
}

pub struct CollabAgentInteractionBeginEvent {
pub:
	// Identifier for the collab tool call.
	call_id       string
	started_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
	// Prompt sent from the sender to the receiver. Can be empty to prevent CoT
	// leaking at the beginning.
	prompt string
}

pub struct CollabAgentInteractionEndEvent {
pub:
	// Identifier for the collab tool call.
	call_id         string
	completed_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
	// Optional nickname assigned to the receiver agent.
	receiver_agent_nickname ?string
	// Optional role assigned to the receiver agent.
	receiver_agent_role ?string
	// Prompt sent from the sender to the receiver. Can be empty to prevent CoT
	// leaking at the beginning.
	prompt string
	// Last known status of the receiver agent reported to the sender agent.
	status AgentStatus
}

pub enum SubAgentActivityKind {
	started
	interacted
	interrupted
	completed
}

pub struct SubAgentActivityEvent {
pub:
	event_id       string
	occurred_at_ms i64
	// Thread ID of the affected sub-agent.
	agent_thread_id ThreadId
	// Canonical v2 path of the affected sub-agent.
	agent_path AgentPath
	kind       SubAgentActivityKind
}

pub struct CollabWaitingBeginEvent {
pub:
	started_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receivers.
	receiver_thread_ids []ThreadId
	// Optional nicknames/roles for receivers.
	receiver_agents []CollabAgentRef
	// ID of the waiting call.
	call_id string
}

pub struct CollabWaitingEndEvent {
pub:
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// ID of the waiting call.
	call_id         string
	completed_at_ms i64
	// Optional receiver metadata paired with final statuses.
	agent_statuses []CollabAgentStatusEntry
	// Last known status of the receiver agents reported to the sender agent.
	statuses map[string]AgentStatus
}

pub struct CollabCloseBeginEvent {
pub:
	// Identifier for the collab tool call.
	call_id       string
	started_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
}

pub struct CollabCloseEndEvent {
pub:
	// Identifier for the collab tool call.
	call_id         string
	completed_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
	// Optional nickname assigned to the receiver agent.
	receiver_agent_nickname ?string
	// Optional role assigned to the receiver agent.
	receiver_agent_role ?string
	// Last known status of the receiver agent reported to the sender agent before
	// the close.
	status AgentStatus
}

pub struct CollabResumeBeginEvent {
pub:
	// Identifier for the collab tool call.
	call_id       string
	started_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
	// Optional nickname assigned to the receiver agent.
	receiver_agent_nickname ?string
	// Optional role assigned to the receiver agent.
	receiver_agent_role ?string
}

pub struct CollabResumeEndEvent {
pub:
	// Identifier for the collab tool call.
	call_id         string
	completed_at_ms i64
	// Thread ID of the sender.
	sender_thread_id ThreadId
	// Thread ID of the receiver.
	receiver_thread_id ThreadId
	// Optional nickname assigned to the receiver agent.
	receiver_agent_nickname ?string
	// Optional role assigned to the receiver agent.
	receiver_agent_role ?string
	// Last known status of the receiver agent reported to the sender agent after
	// resume.
	status AgentStatus
}
