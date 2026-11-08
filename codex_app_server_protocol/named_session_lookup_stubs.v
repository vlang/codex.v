module codex_app_server_protocol

import codex_protocol
import codex_protocol.items as protocol_items

// STUB: protocol/common.rs::ClientRequest::ThreadRead payload.
pub struct ClientRequestThreadRead {
pub:
	request_id RequestId
	params     ThreadReadParams
}

// STUB: ThreadListParams's derived Clone consumes owned request payloads only at
// the source's serialization boundary, keeping the session's retry input reusable.
pub fn (params &ThreadListParams) clone() ThreadListParams {
	return ThreadListParams{
		cursor:             if value := params.cursor { value.clone() } else { none }
		limit:              params.limit
		sort_key:           params.sort_key
		sort_direction:     params.sort_direction
		model_providers:    if values := params.model_providers { values.clone() } else { none }
		source_kinds:       if values := params.source_kinds { values.clone() } else { none }
		originators:        if values := params.originators { values.clone() } else { none }
		archived:           params.archived
		section_id:         ClearableString{ has_value: params.section_id.has_value, clear: params.section_id.clear, value: params.section_id.value.clone() }
		project_id:         ClearableString{ has_value: params.project_id.has_value, clear: params.project_id.clear, value: params.project_id.value.clone() }
		cwd:                if value := params.cwd {
			ThreadListCwdFilter{ kind: value.kind, one: value.one.clone(), many: value.many.clone() }
		} else {
			none
		}
		use_state_db_only:  params.use_state_db_only
		search_term:        if value := params.search_term { value.clone() } else { none }
		parent_thread_id:   if value := params.parent_thread_id { value.clone() } else { none }
		ancestor_thread_id: if value := params.ancestor_thread_id { value.clone() } else { none }
	}
}

// STUB: Thread's derived Clone; preserve its canonical typed payload instead of
// replacing the whole thread with a label/ID surrogate in the fixture.
pub fn (listed_thread &Thread) clone() Thread {
	mut environments := []ThreadEnvironment{cap: listed_thread.environments.value.len}
	for index in 0 .. listed_thread.environments.value.len {
		item := &listed_thread.environments.value[index]
		environments << ThreadEnvironment{ environment_id: item.environment_id.clone(), cwd: item.cwd.clone(), runtime_workspace_roots: item.runtime_workspace_roots.clone() }
	}
	mut turns := []Turn{cap: listed_thread.turns.len}
	for index in 0 .. listed_thread.turns.len {
		turn := &listed_thread.turns[index]
		mut items := []ThreadItem{cap: turn.items.len}
		for item_index in 0 .. turn.items.len {
			item := &turn.items[item_index]
			items << ThreadItem{ id: item.id.clone(), kind: item.kind, content: item.content.clone(), text: item.text.clone(), phase: item.phase, memory_citation: clone_named_session_item_citation(item), delivery: clone_named_session_item_delivery(item), questions: clone_named_session_item_questions(item) }
		}
		turns << Turn{ id: turn.id.clone(), items: items, items_view: turn.items_view, status: turn.status, error: clone_named_session_turn_error(turn), started_at: turn.started_at, completed_at: turn.completed_at, duration_ms: turn.duration_ms }
	}
	return Thread{
		id:                      listed_thread.id.clone()
		environments:            OptionalThreadEnvironments{ has_value: listed_thread.environments.has_value, value: environments }
		extra:                   listed_thread.extra
		session_id:              listed_thread.session_id.clone()
		forked_from_id:          if value := listed_thread.forked_from_id {
			value.clone()
		} else {
			none
		}
		parent_thread_id:        if value := listed_thread.parent_thread_id {
			value.clone()
		} else {
			none
		}
		preview:                 listed_thread.preview.clone()
		ephemeral:               listed_thread.ephemeral
		section:                 if value := listed_thread.section {
			ThreadSection{
				id:         value.id.clone()
				name:       value.name.clone()
				appearance: if appearance := value.appearance {
					ThreadSectionAppearance{ icon: appearance.icon.clone(), color: appearance.color.clone() }
				} else {
					none
				}
			}
		} else {
			none
		}
		section_entered_at:      listed_thread.section_entered_at
		project_id:              if value := listed_thread.project_id {
			value.clone()
		} else {
			none
		}
		history_mode:            listed_thread.history_mode
		model_provider:          listed_thread.model_provider.clone()
		model:                   if value := listed_thread.model { value.clone() } else { none }
		reasoning_effort:        listed_thread.reasoning_effort
		created_at:              listed_thread.created_at
		updated_at:              listed_thread.updated_at
		recency_at:              listed_thread.recency_at
		status:                  listed_thread.status
		path:                    if value := listed_thread.path { value.clone() } else { none }
		cwd:                     listed_thread.cwd.clone()
		cli_version:             listed_thread.cli_version.clone()
		originator:              if value := listed_thread.originator {
			value.clone()
		} else {
			none
		}
		agent_nickname:          if value := listed_thread.agent_nickname {
			value.clone()
		} else {
			none
		}
		agent_role:              if value := listed_thread.agent_role {
			value.clone()
		} else {
			none
		}
		source:                  codex_protocol.clone_session_source(&listed_thread.source)
		can_accept_direct_input: listed_thread.can_accept_direct_input
		thread_source:           if value := listed_thread.thread_source {
			codex_protocol.ThreadSource{ source_kind: value.source_kind, feature: value.feature.clone() }
		} else {
			none
		}
		git_info:                if value := listed_thread.git_info {
			GitInfo{
				sha:        if sha := value.sha { sha.clone() } else { none }
				branch:     if branch := value.branch {
					branch.clone()
				} else {
					none
				}
				origin_url: if url := value.origin_url { url.clone() } else { none }
			}
		} else {
			none
		}
		name:                    if value := listed_thread.name { value.clone() } else { none }
		daybreak_enabled:        listed_thread.daybreak_enabled
		turns:                   turns
	}
}

// STUB: clone Turn's optional error through its enclosing borrowed owner so V's
// ownership checker does not move an optional payload out of an array element.
fn clone_named_session_turn_error(turn &Turn) ?TurnError {
	if failure := turn.error {
		return TurnError{ message: failure.message.clone(), codex_error_info: failure.codex_error_info.clone(), additional_details: failure.additional_details.clone() }
	}
	return none
}

// STUB: derived Clone of the optional item citation through the enclosing owner.
fn clone_named_session_item_citation(item &ThreadItem) ?MemoryCitation {
	if citation := item.memory_citation {
		mut entries := []MemoryCitationEntry{cap: citation.entries.len}
		for index in 0 .. citation.entries.len {
			entry := &citation.entries[index]
			entries << MemoryCitationEntry{ path: entry.path.clone(), line_start: entry.line_start, line_end: entry.line_end, note: entry.note.clone() }
		}
		return MemoryCitation{ entries: entries, thread_ids: citation.thread_ids.clone() }
	}
	return none
}

// STUB: derived Clone of optional delivery metadata through the enclosing owner.
fn clone_named_session_item_delivery(item &ThreadItem) ?protocol_items.AgentMessageDelivery {
	if delivery := item.delivery {
		return protocol_items.AgentMessageDelivery{ channel: delivery.channel.clone() }
	}
	return none
}

// STUB: derived Clone of optional deferred questions through the enclosing owner.
fn clone_named_session_item_questions(item &ThreadItem) ?[]protocol_items.AsyncUserInputQuestion {
	if questions := item.questions {
		mut result := []protocol_items.AsyncUserInputQuestion{cap: questions.len}
		for index in 0 .. questions.len {
			result << protocol_items.AsyncUserInputQuestion{ id: questions[index].id.clone() }
		}
		return result
	}
	return none
}
