module codex_rollout

import codex_protocol
import codex_thread_store

// STUB: plain_rollout_path is owned by codex-rollout/compression.rs and maps a compressed rollout
// path to the logical `.jsonl` path used for stale-path comparisons.
pub fn plain_rollout_path(path &string) string {
	value := *path
	if value.ends_with('.jsonl.gz') {
		return value[..value.len - 3].clone()
	}
	return value.clone()
}

// STUB: InitialHistoryKind models codex-rollout's payload-bearing InitialHistory enum.
pub enum InitialHistoryKind {
	new_history
	cleared
	resumed
	forked
}

// STUB: InitialHistory is owned by codex-rollout and retains the source id, model context, and
// optional persistent rollout path used by resume and fork.
pub struct InitialHistory {
pub:
	kind                InitialHistoryKind
	conversation_id     codex_protocol.ThreadId
	items               []codex_thread_store.RolloutItem
	rollout_path        ?string
	session_source      ?codex_protocol.SessionSource
	thread_source       ?codex_protocol.ThreadSource
	multi_agent_version ?codex_protocol.MultiAgentVersion
	session_cwd         ?string
}

// STUB: ResumedSessionSources preserves the source pair returned from resumed session metadata.
pub struct ResumedSessionSources {
pub:
	has_value      bool
	session_source codex_protocol.SessionSource
	thread_source  ?codex_protocol.ThreadSource
}

// STUB: returns the rollout items represented by any InitialHistory variant.
pub fn (history &InitialHistory) get_rollout_items() []codex_thread_store.RolloutItem {
	return history.items.clone()
}

// STUB: reads the session and thread sources embedded in resumed history metadata.
pub fn (history &InitialHistory) get_resumed_session_sources() ResumedSessionSources {
	if history.kind != .resumed {
		return ResumedSessionSources{}
	}
	for item in history.items {
		if item.kind == .session_meta {
			if source := item.session_source {
				return ResumedSessionSources{
					has_value:      true
					session_source: codex_protocol.clone_session_source(&source)
					thread_source:  if thread_source := item.thread_source {
						codex_protocol.ThreadSource{
							source_kind: thread_source.source_kind
							feature:     thread_source.feature.clone()
						}
					} else {
						none
					}
				}
			}
		}
	}
	if source := history.session_source {
		return ResumedSessionSources{
			has_value:      true
			session_source: codex_protocol.clone_session_source(&source)
			thread_source:  if thread_source := history.thread_source {
				codex_protocol.ThreadSource{
					source_kind: thread_source.source_kind
					feature:     thread_source.feature.clone()
				}
			} else {
				none
			}
		}
	}
	return ResumedSessionSources{}
}

// STUB: returns the multi-agent version embedded in InitialHistory metadata.
pub fn (history &InitialHistory) get_multi_agent_version() ?codex_protocol.MultiAgentVersion {
	for item in history.items {
		if item.kind == .session_meta {
			if history.kind != .resumed || (if id := item.session_meta_id {
				id.value == history.conversation_id.value
			} else {
				false
			}) {
				if version := item.multi_agent_version {
					return version
				}
			}
		}
	}
	return history.multi_agent_version
}

// STUB: returns the session cwd embedded in InitialHistory metadata.
pub fn (history &InitialHistory) session_cwd() ?string {
	for item in history.items {
		if item.kind == .session_meta {
			if cwd := item.session_cwd {
				return cwd.clone()
			}
		}
	}
	if cwd := history.session_cwd {
		return cwd.clone()
	}
	return none
}

// STUB: returns the persisted rollout path embedded by a resumed history variant.
pub fn (history &InitialHistory) rollout_path() ?string {
	if path := history.rollout_path {
		return path.clone()
	}
	return none
}
