module app_event

import codex_connectors
import codex_protocol.thread_id
import codex_tui.history_cell
import codex_tui.task_mentions

// STUB: crate::app_event::ConnectorsSnapshot.
pub struct ConnectorsSnapshot {
pub:
	connectors []codex_connectors.AppInfo
}

// STUB: crate::app_event::HistoryBatchEntryResponse.
pub struct HistoryBatchEntryResponse {
pub:
	offset int
	entry  ?string
}

// STUB: crate::app_event::AppEvent discriminants observed by ChatComposer.
pub enum AppEventKind {
	start_file_search
	open_agents_overview
	insert_history_cell
	lookup_message_history_entry
	task_search_result
	permission_profiles_loaded
}

// STUB: crate::app_event::AppEvent payloads observed by ChatComposer and task-mention search. Rust's payload enum is an
// explicit V tag with variant-specific storage; file-search text cannot be mistaken for a history
// cell.
pub struct AppEvent {
pub:
	kind                AppEventKind
	file_search_query   string
	history_cell        ?history_cell.HistoryCell
	thread_id           thread_id.ThreadId
	history_offset      int
	history_log_id      u64
	task_search_query   string
	task_matches        []task_mentions.TaskMention
	permission_profiles PermissionProfilesLoaded
}

// STUB: crate::app_event::AppEvent::StartFileSearch.
pub fn start_file_search(query string) AppEvent {
	return AppEvent{ kind: .start_file_search, file_search_query: query }
}

// STUB: crate::app_event::AppEvent::OpenAgentsOverview.
pub fn open_agents_overview() AppEvent {
	return AppEvent{ kind: .open_agents_overview }
}

// STUB: crate::app_event::AppEvent::InsertHistoryCell.
pub fn insert_history_cell(cell history_cell.HistoryCell) AppEvent {
	return AppEvent{ kind: .insert_history_cell, history_cell: cell }
}

// STUB: crate::app_event::AppEvent::LookupMessageHistoryEntry.
pub fn lookup_message_history_entry(id thread_id.ThreadId, offset int, log_id u64) AppEvent {
	return AppEvent{
		kind:           .lookup_message_history_entry
		thread_id:      id
		history_offset: offset
		history_log_id: log_id
	}
}

// STUB: crate::app_event::AppEvent::TaskSearchResult.
pub fn task_search_result(id thread_id.ThreadId, query string, matches []task_mentions.TaskMention) AppEvent {
	return AppEvent{
		kind:              .task_search_result
		thread_id:         id
		task_search_query: query
		task_matches:      matches
	}
}
