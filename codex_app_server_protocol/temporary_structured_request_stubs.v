module codex_app_server_protocol

import codex_protocol
import codex_protocol.openai_models
import serde_json

// STUB: typed transport deserialization owns its independent request payload.
// Deep copies implement the smallest in-memory RPC encode/decode boundary;
// source target functions continue moving their parameters into request_typed.
pub fn (params &TurnStartParams) clone() TurnStartParams {
	mut input := []UserInput{cap: params.input.len}
	for index in 0 .. params.input.len {
		input << (&params.input[index]).clone()
	}
	// Materialize the typed optional before the struct literal: V's C lowering
	// otherwise confuses the optional Value if-expression with compiler ast.Value.
	mut output_schema := ?serde_json.Value(none)
	if schema := params.output_schema {
		output_schema = schema.clone()
	}
	return TurnStartParams{
		thread_id:       params.thread_id.clone()
		input:           input
		output_schema:   output_schema
		effort:          params.effort
		model:           if value := params.model { value.clone() } else { none }
		permissions:     if value := params.permissions { value.clone() } else { none }
		cwd:             if value := params.cwd { value.clone() } else { none }
		approval_policy: params.approval_policy
		sandbox_policy:  if policy := params.sandbox_policy {
			codex_protocol.SandboxPolicy{
				policy_kind:             policy.policy_kind
				writable_roots:          policy.writable_roots.clone()
				network_access:          policy.network_access
				external_network_access: policy.external_network_access
				exclude_tmpdir_env_var:  policy.exclude_tmpdir_env_var
				exclude_slash_tmp:       policy.exclude_slash_tmp
			}
		} else {
			none
		}
	}
}

// STUB: the generated UserInput's Clone operation at the RPC decoding boundary.
pub fn (input &UserInput) clone() UserInput {
	match input {
		UserInputText {
			mut elements := []TextElement{cap: input.text_elements.len}
			for index in 0 .. input.text_elements.len {
				element := &input.text_elements[index]
				elements << TextElement.new(element.byte_range, if placeholder := element.placeholder {
					placeholder.clone()
				} else {
					none
				})
			}
			return UserInputText{ text: input.text.clone(), text_elements: elements }
		}
		UserInputImage { return UserInputImage{ detail: input.detail, url: input.url.clone() } }
		UserInputLocalImage {
			return UserInputLocalImage{ detail: input.detail, path: input.path.clone() }
		}
		UserInputAudio { return UserInputAudio{ url: input.url.clone() } }
		UserInputLocalAudio { return UserInputLocalAudio{ path: input.path.clone() } }
		UserInputSkill {
			return UserInputSkill{ name: input.name.clone(), path: input.path.clone() }
		}
		UserInputMention {
			return UserInputMention{ name: input.name.clone(), path: input.path.clone() }
		}
	}
}

// STUB: RequestId's Clone preserves its tag and owned string id.
pub fn (id &RequestId) clone() RequestId {
	return RequestId{ kind: id.kind, string_value: id.string_value.clone(), integer: id.integer }
}

// STUB: protocol/v2/config.rs::ConfigReadParams; cwd selects effective layers.
pub struct ConfigReadParams {
pub:
	include_layers bool
	cwd            ?string
}

// STUB: protocol/v2/config.rs::Config, the flattened additional config observed here.
pub struct Config {
pub:
	additional map[string]serde_json.Value
}

// STUB: protocol/v2/config.rs::ConfigReadResponse; unobserved layer metadata is
// left to that module's eventual translation.
pub struct ConfigReadResponse {
pub:
	config Config
}

// STUB: protocol/common.rs::ClientRequest::ConfigRead payload.
pub struct ClientRequestConfigRead {
pub:
	request_id RequestId
	params     ConfigReadParams
}

// STUB: protocol/common.rs::ClientRequest::ThreadStart payload.
pub struct ClientRequestThreadStart {
pub:
	request_id RequestId
	params     ThreadStartParams
}

// STUB: protocol/v2/turn.rs::TurnStartParams; the source-owned fields observed
// here and inherited-setting overrides remain typed and default to None.
pub struct TurnStartParams {
pub:
	thread_id       string
	input           []UserInput
	output_schema   ?serde_json.Value
	effort          ?openai_models.ReasoningEffort
	model           ?string
	permissions     ?string
	cwd             ?string
	approval_policy ?AskForApproval
	sandbox_policy  ?codex_protocol.SandboxPolicy
}

// STUB: protocol/v2/turn.rs::TurnStartResponse.
pub struct TurnStartResponse {
pub:
	turn Turn
}

// STUB: protocol/common.rs::ClientRequest::TurnStart payload.
pub struct ClientRequestTurnStart {
pub:
	request_id RequestId
	params     TurnStartParams
}

// STUB: protocol/common.rs::ClientRequest::ThreadUnsubscribe payload.
pub struct ClientRequestThreadUnsubscribe {
pub:
	request_id RequestId
	params     ThreadUnsubscribeParams
}

// STUB: protocol/v2/item.rs::ItemCompletedNotification.
pub struct ItemCompletedNotification {
pub:
	item            ThreadItem
	thread_id       string
	turn_id         string
	completed_at_ms i64
}

// STUB: protocol/v2/turn.rs::TurnCompletedNotification.
pub struct TurnCompletedNotification {
pub:
	thread_id string
	turn      Turn
}

// STUB: protocol/v2/item.rs::MemoryCitation preserves the app-server field
// names; its core counterpart currently has an incompatible incomplete stub.
pub struct MemoryCitation {
pub:
	entries    []MemoryCitationEntry
	thread_ids []string
}

// STUB: protocol/v2/item.rs::MemoryCitationEntry.
pub struct MemoryCitationEntry {
pub:
	path       string
	line_start u32
	line_end   u32
	note       string
}
