// Server collaboration-mode discovery and TUI-visible selection. Missing discovery adds no presets.
module collaboration_modes

import codex_app_server_client
import codex_app_server_protocol as api
import codex_protocol
import codex_protocol.config_types
import codex_tui.model_catalog
import std_time
import tokio.time as tokio_time
import tracing
import uuid

fn filtered_presets(catalog &model_catalog.ModelCatalog) []config_types.CollaborationModeMask {
	mut presets := []config_types.CollaborationModeMask{}
	for index in 0 .. catalog.collaboration_modes.len {
		if mode := catalog.collaboration_modes[index].mode {
			if mode.is_tui_visible() {
				presets << (&catalog.collaboration_modes[index]).clone()
			}
		}
	}
	return presets
}

// V exports cross-module names because it has no Rust pub(crate) visibility.
pub fn default_mask(catalog &model_catalog.ModelCatalog) ?config_types.CollaborationModeMask {
	presets := filtered_presets(catalog)
	for index in 0 .. presets.len {
		if mode := presets[index].mode {
			if mode == .default_mode {
				return (&presets[index]).clone()
			}
		}
	}
	if presets.len > 0 {
		return presets[0]
	}
	return none
}

pub fn mask_for_kind(catalog &model_catalog.ModelCatalog, kind config_types.ModeKind) ?config_types.CollaborationModeMask {
	if !kind.is_tui_visible() {
		return none
	}
	presets := filtered_presets(catalog)
	for mask in presets {
		if mode := mask.mode {
			if mode == kind {
				return mask
			}
		}
	}
	return none
}

// Safe representation of Rust Option<&CollaborationModeMask>. V cannot reliably
// generate a nested optional reference; the tag guards its borrowed pointer.
// The owner must outlive this view, which next_mask never retains.
pub struct BorrowedMask {
pub:
	has_value bool
	mask      &config_types.CollaborationModeMask = unsafe { nil }
}

pub fn BorrowedMask.none() BorrowedMask {
	return BorrowedMask{}
}

/// Cycle to the next collaboration mode preset in list order.
pub fn next_mask(catalog &model_catalog.ModelCatalog, current BorrowedMask) ?config_types.CollaborationModeMask {
	presets := filtered_presets(catalog)
	if presets.len == 0 {
		return none
	}
	current_kind := if current.has_value && current.mask != unsafe { nil } {
		current.mask.mode
	} else {
		?config_types.ModeKind(none)
	}
	mut next_index := 0
	for index in 0 .. presets.len {
		if presets[index].mode == current_kind {
			next_index = (index + 1) % presets.len
			break
		}
	}
	return (&presets[next_index]).clone()
}

pub fn default_mode_mask(catalog &model_catalog.ModelCatalog) ?config_types.CollaborationModeMask {
	return mask_for_kind(catalog, .default_mode)
}

pub fn plan_mask(catalog &model_catalog.ModelCatalog) ?config_types.CollaborationModeMask {
	return mask_for_kind(catalog, .plan)
}

/// Discovery is optional even on servers that accept the rest of TUI bootstrap.
// Rust awaits an asynchronous future; V waits for a bounded worker operation.
// This owned handle and request move into the operation, and its two-second deadline
// remains at the discovery call site. The runtime boundary documents cancellation.
pub fn list(request_handle codex_app_server_client.AppServerRequestHandle) []config_types.CollaborationModeMask {
	duration := std_time.Duration.from_secs( /*secs*/
	2)
	request_uuid := uuid.Uuid.new_v4()
	params := api.CollaborationModeListParams.default()
	// V closures cannot consume an owned captured request as Rust futures do.
	// Capture its allocation-free UUID/params, then assemble the owned request once
	// inside the operation. UUID generation still precedes starting the deadline.
	if response := tokio_time.timeout[api.CollaborationModeListResponse](i64(duration.as_nanos().lo), fn [request_handle, request_uuid, params] () !api.CollaborationModeListResponse {
		return request_handle.request_typed[api.CollaborationModeListResponse](api.ClientRequestCollaborationModeList{
			request_id: api.RequestId.string('collaboration-mode-list-${request_uuid}')
			params:     params
		})
	}) {
		mut masks := []config_types.CollaborationModeMask{cap: response.data.len}
		for mask in response.data {
			masks << config_types.CollaborationModeMask{
				name:                   mask.name
				mode:                   mask.mode
				model:                  mask.model
				reasoning_effort:       mask.reasoning_effort
				// The RPC intentionally omits prompts. Clear restored overrides so the server
				// supplies its current instructions when this mode is selected.
				developer_instructions: codex_protocol.OptionalString{ is_set: true, value: none }
			}
		}
		return masks
	}
	message := 'optional collaborationMode/list discovery unavailable'
	tracing.warn(&message)
	return []config_types.CollaborationModeMask{}
}
