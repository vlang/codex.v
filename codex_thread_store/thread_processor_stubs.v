module codex_thread_store

import codex_app_server_protocol
import codex_protocol

// STUB: ThreadStoreErrorKind models codex-thread-store's payload-bearing error enum.
pub enum ThreadStoreErrorKind {
	invalid_request
	unsupported
	thread_not_found
	conflict
	internal
}

// STUB: ThreadStoreError is owned by codex-thread-store.
pub struct ThreadStoreError {
pub:
	kind      ThreadStoreErrorKind
	message   string
	operation string
	thread_id codex_protocol.ThreadId
}

// STUB: ThreadSortKey is owned by codex-thread-store.
pub enum ThreadSortKey {
	created_at
	updated_at
	recency_at
	section_position
}

// STUB: SortDirection is owned by codex-thread-store.
pub enum SortDirection {
	asc
	desc
}

// STUB: StoredTurnItemsView is owned by codex-thread-store.
pub enum StoredTurnItemsView {
	not_loaded
	summary
}

// STUB: StoredTurnStatus is owned by codex-thread-store.
pub enum StoredTurnStatus {
	completed
	interrupted
	failed
	in_progress
}

// STUB: StoredThreadItem is owned by codex-thread-store. The decoded item is retained at this
// boundary until the protocol JSON codec is translated.
pub struct StoredThreadItem {
pub:
	turn_id string
	item_id string
	item    codex_app_server_protocol.ThreadItem
}

// STUB: StoredTurnError is owned by codex-thread-store.
pub struct StoredTurnError {
pub:
	message            string
	codex_error_info   string
	additional_details string
}

// STUB: StoredTurn is owned by codex-thread-store.
pub struct StoredTurn {
pub:
	turn_id      string
	items        []StoredThreadItem
	status       StoredTurnStatus
	error        ?StoredTurnError
	started_at   ?i64
	completed_at ?i64
	duration_ms  ?i64
}

// STUB: StoredThreadHistory is owned by codex-thread-store.
pub struct StoredThreadHistory {
pub:
	items []RolloutItem
}

// STUB: RolloutItemKind mirrors the portions of codex-rollout used by thread_processor.rs.
pub enum RolloutItemKind {
	session_meta
	user_message
	agent_message
	response_item
	turn
	other
}

// STUB: RolloutItem is owned by codex-rollout and will move there when that crate is translated.
pub struct RolloutItem {
pub mut:
	kind                      RolloutItemKind
	message                   string
	turn                      codex_app_server_protocol.Turn
	response_item             codex_protocol.ResponseItem
	approval_policy           ?codex_app_server_protocol.AskForApproval
	approvals_reviewer        ?codex_app_server_protocol.ApprovalsReviewer
	active_permission_profile ?codex_protocol.ActivePermissionProfile
	thread_settings_thread_id ?codex_protocol.ThreadId
	thread_settings_cwd       ?string
	session_meta_id           ?codex_protocol.ThreadId
	session_source            ?codex_protocol.SessionSource
	thread_source             ?codex_protocol.ThreadSource
	multi_agent_version       ?codex_protocol.MultiAgentVersion
	session_cwd               ?string
}

// STUB: StoredGitInfo is owned by codex-thread-store.
pub struct StoredGitInfo {
pub:
	commit_hash    ?string
	branch         ?string
	repository_url ?string
}

// STUB: StoredSectionAppearance is owned by codex-thread-store.
pub struct StoredSectionAppearance {
pub:
	icon  string
	color string
}

// STUB: StoredSection is owned by codex-thread-store.
pub struct StoredSection {
pub:
	id         string
	name       string
	appearance ?StoredSectionAppearance
}

// STUB: StoredThread is owned by codex-thread-store. Timestamp strings preserve the exact RFC3339
// precision supplied by the store; unix timestamps are retained for the v2 response.
pub struct StoredThread {
pub:
	thread_id          codex_protocol.ThreadId
	rollout_path       ?string
	forked_from_id     ?codex_protocol.ThreadId
	parent_thread_id   ?codex_protocol.ThreadId
	preview            string
	name               ?string
	model_provider     string
	model              ?string
	reasoning_effort   ?codex_protocol.ReasoningEffortConfig
	created_at         i64
	updated_at         i64
	recency_at         i64
	created_at_rfc3339 string
	updated_at_rfc3339 string
	archived_at        ?i64
	section            ?StoredSection
	section_position   ?i64
	section_entered_at ?i64
	project_id         ?string
	daybreak_enabled   ?bool
	cwd                string
	cli_version        string
	source             codex_protocol.SessionSource
	originator         ?string
	history_mode       codex_app_server_protocol.ThreadHistoryMode
	thread_source      ?codex_protocol.ThreadSource
	agent_nickname     ?string
	agent_role         ?string
	git_info           ?StoredGitInfo
	permission_profile codex_protocol.PermissionProfile
	history            ?StoredThreadHistory
}

// STUB: ThreadMetadataPatch is owned by codex-thread-store.
pub struct ThreadMetadataPatch {
pub:
	name             ClearableString
	project_id       ClearableString
	daybreak_enabled ?bool
}

// STUB: ClearableString preserves `Option<Option<String>>` for metadata mutations.
pub struct ClearableString {
pub:
	has_value bool
	clear     bool
	value     string
}

// STUB: StoredGitInfoPatch is owned by codex-thread-store.
pub struct StoredGitInfoPatch {
pub:
	sha            ClearableString
	branch         ClearableString
	repository_url ClearableString
}

// STUB: StoredThreadMetadataUpdatePatch is the complete mutation consumed by ThreadManager.
pub struct StoredThreadMetadataUpdatePatch {
pub:
	git_info         ?StoredGitInfoPatch
	name             ClearableString
	project_id       ClearableString
	daybreak_enabled ?bool
	memory_mode      ?codex_app_server_protocol.MemoryMode
}

// STUB: ForkBoundaryKind models the store's payload-bearing fork boundary.
pub enum ForkBoundaryKind {
	latest
	through_turn
	before_turn
}

// STUB: ForkBoundary is owned by codex-thread-store.
pub struct ForkBoundary {
pub:
	kind    ForkBoundaryKind
	turn_id string
}

// STUB: PrepareForkParams is owned by codex-thread-store.
pub struct PrepareForkParams {
pub:
	thread_id codex_protocol.ThreadId
	boundary  ForkBoundary
}

// STUB: PreparedFork is the store-owned durable fork plan consumed by ThreadManager.
pub struct PreparedFork {
pub:
	model_context []RolloutItem
}

// STUB: PrepareForkResult preserves the typed ThreadStoreError returned by prepare_fork.
pub struct PrepareForkResult {
pub:
	is_error    bool
	value       PreparedFork
	error_value ThreadStoreError
}

// STUB: ThreadRelationFilterKind models codex-thread-store's payload-bearing relation enum.
pub enum ThreadRelationFilterKind {
	direct_children_of
	descendants_of
}

// STUB: ThreadRelationFilter is owned by codex-thread-store.
pub struct ThreadRelationFilter {
pub:
	kind      ThreadRelationFilterKind
	thread_id codex_protocol.ThreadId
}

// STUB: OptionalStringArray preserves omission separately from an explicitly empty cwd filter.
pub struct OptionalStringArray {
pub:
	has_value bool
	value     []string
}

// STUB: ListThreadsParams is owned by codex-thread-store and mirrors its typed list request.
pub struct ListThreadsParams {
pub:
	page_size         int
	cursor            ?string
	sort_key          ThreadSortKey
	sort_direction    SortDirection
	allowed_sources   []codex_protocol.SessionSource
	model_providers   ?[]string
	archived          bool
	section_id        ClearableString
	project_id        ClearableString
	cwd_filters       OptionalStringArray
	search_term       ?string
	use_state_db_only bool
	relation_filter   ?ThreadRelationFilter
}

// STUB: ListThreadsResult preserves the typed store error returned by list_threads.
pub struct ListThreadsResult {
pub:
	is_error    bool
	value       ThreadListPage
	error_value ThreadStoreError
}

// STUB: ThreadListPage is returned by codex-thread-store's list operation.
pub struct ThreadListPage {
pub:
	items       []StoredThread
	next_cursor ?string
}

// STUB: StoredThreadSearchResult is a persisted thread plus its store-produced match snippet.
pub struct StoredThreadSearchResult {
pub:
	thread  StoredThread
	snippet string
}

// STUB: ThreadSearchPage is returned by codex-thread-store search pagination.
pub struct ThreadSearchPage {
pub:
	items       []StoredThreadSearchResult
	next_cursor ?string
}

// STUB: StoreSearchThreadsParams is owned by codex-thread-store.
pub struct StoreSearchThreadsParams {
pub:
	page_size       int
	cursor          ?string
	sort_key        ThreadSortKey
	sort_direction  SortDirection
	allowed_sources []codex_protocol.SessionSource
	archived        bool
	search_term     string
}

// STUB: SearchThreadsResult preserves the typed store error returned by search_threads.
pub struct SearchThreadsResult {
pub:
	is_error    bool
	value       ThreadSearchPage
	error_value ThreadStoreError
}

// STUB: OptionalStoredThread preserves a successful missing-row result separately from errors.
pub struct OptionalStoredThread {
pub:
	has_value bool
	value     StoredThread
}

// STUB: ThreadReadResultKind adapts Rust's typed `Result<StoredThread, ThreadStoreError>` because
// V results cannot carry a concrete error payload.
pub enum ThreadReadResultKind {
	ok
	error
}

// STUB: ThreadReadResult preserves both success data and the complete codex-thread-store error.
pub struct ThreadReadResult {
pub:
	kind        ThreadReadResultKind
	value       StoredThread
	error_value ThreadStoreError
}

// STUB: StoreReadThreadParams is owned by codex-thread-store.
pub struct StoreReadThreadParams {
pub:
	thread_id        codex_protocol.ThreadId
	include_archived bool
	include_history  bool
}

// STUB: StoreReadThreadByRolloutPathParams is owned by codex-thread-store.
pub struct StoreReadThreadByRolloutPathParams {
pub:
	rollout_path     string
	include_archived bool
	include_history  bool
}

// STUB: StoreLoadThreadHistoryParams is owned by codex-thread-store.
pub struct StoreLoadThreadHistoryParams {
pub:
	thread_id        codex_protocol.ThreadId
	include_archived bool
}

// STUB: ThreadModelContext is the latest persisted model context returned for paginated resume.
pub struct ThreadModelContext {
pub:
	thread_id codex_protocol.ThreadId
	items     []RolloutItem
}

// STUB: LoadThreadModelContextResult retains the typed store failure inspected by app-server.
pub struct LoadThreadModelContextResult {
pub:
	is_error    bool
	value       ThreadModelContext
	error_value ThreadStoreError
}

// STUB: Project is owned by codex-state and returned through codex-thread-store.
pub struct Project {
pub:
	id string
}

// STUB: ProjectReadResult preserves Rust's `Result<Option<Project>, ThreadStoreError>`.
pub struct ProjectReadResult {
pub:
	is_error    bool
	has_value   bool
	value       Project
	error_value ThreadStoreError
}

// STUB: PersistContext is owned by codex-thread-store.
pub enum PersistContext {
	standard
}

// STUB: ThreadStoreOperationResult preserves a typed store failure for mutation operations.
pub struct ThreadStoreOperationResult {
pub:
	is_error    bool
	error_value ThreadStoreError
}

// STUB: ArchiveThreadsResult preserves the typed store failure returned by `archive_threads`.
pub struct ArchiveThreadsResult {
pub:
	is_error    bool
	value       []codex_protocol.ThreadId
	error_value ThreadStoreError
}

// STUB: UnarchiveThreadResult preserves the typed store failure returned by `unarchive_thread`.
pub struct UnarchiveThreadResult {
pub:
	is_error    bool
	value       StoredThread
	error_value ThreadStoreError
}

// STUB: RevertThreadParams is owned by codex-thread-store and keeps the mutation boundary typed.
pub struct RevertThreadParams {
pub:
	thread_id           codex_protocol.ThreadId
	before_turn_id      string
	multi_agent_version ?codex_protocol.MultiAgentVersion
}

// STUB: OptionalCursorPair is returned by the two backwards-cursor probes.
pub struct OptionalCursorPair {
pub:
	turns ?string
	items ?string
}

// STUB: ThreadTurnsPage is the raw store page consumed and converted by app-server.
pub struct ThreadTurnsPage {
pub:
	turns            []StoredTurn
	next_cursor      ?string
	backwards_cursor ?string
}

// STUB: ThreadItemsPage is the raw store page consumed and converted by app-server.
pub struct ThreadItemsPage {
pub:
	items            []StoredThreadItem
	next_cursor      ?string
	backwards_cursor ?string
}

// STUB: ListTurnsResult preserves the typed ThreadStoreError returned by `ThreadStore::list_turns`.
pub struct ListTurnsResult {
pub:
	is_error    bool
	value       ThreadTurnsPage
	error_value ThreadStoreError
}

// STUB: ListItemsResult preserves the typed ThreadStoreError returned by `ThreadStore::list_items`.
pub struct ListItemsResult {
pub:
	is_error    bool
	value       ThreadItemsPage
	error_value ThreadStoreError
}

// STUB: StoreSearchTextRange is owned by codex-thread-store.
pub struct StoreSearchTextRange {
pub:
	start u32
	end   u32
}

// STUB: StoredThreadSearchOccurrence is a raw full-text match row.
pub struct StoredThreadSearchOccurrence {
pub:
	turn_id             string
	item_id             string
	snippet             string
	snippet_match_range StoreSearchTextRange
	turn_cursor         string
}

// STUB: ThreadSearchOccurrencesPage is returned by the store occurrence index.
pub struct ThreadSearchOccurrencesPage {
pub:
	items       []StoredThreadSearchOccurrence
	next_cursor ?string
}

// STUB: StoreSearchThreadOccurrencesParams is owned by codex-thread-store and keeps the indexed
// search query as one typed request.
pub struct StoreSearchThreadOccurrencesParams {
pub:
	thread_id   codex_protocol.ThreadId
	search_term string
	cursor      ?string
	page_size   int
}

// STUB: SearchThreadOccurrencesResult preserves the store's payload error variants for protocol
// error mapping at the request boundary.
pub struct SearchThreadOccurrencesResult {
pub:
	is_error    bool
	value       ThreadSearchOccurrencesPage
	error_value ThreadStoreError
}

// STUB: ListTurnsParams is owned by codex-thread-store.
pub struct ListTurnsParams {
pub:
	thread_id        codex_protocol.ThreadId
	include_archived bool
	cursor           ?string
	page_size        int
	sort_direction   SortDirection
	items_view       StoredTurnItemsView
}

// STUB: ListItemsParams is owned by codex-thread-store.
pub struct ListItemsParams {
pub:
	thread_id                codex_protocol.ThreadId
	turn_id                  ?string
	include_archived         bool
	cursor                   ?string
	page_size                int
	sort_direction           SortDirection
	sort_key                 ItemSortKey
	after_updated_at_ordinal ?u64
}

// STUB: ItemSortKey is owned by codex-thread-store/types.rs.
pub enum ItemSortKey {
	created_at_ordinal
	updated_at_ordinal
}

// STUB: ThreadStore is the codex-thread-store trait-object handle. Each method below keeps the
// actual trait method's typed request/result boundary; no app-server lifecycle or core operations
// live on this handle.
pub struct ThreadStore {
pub:
	available bool
}

// STUB: codex-thread-store stages metadata for a manager-reserved id.
pub fn (store &ThreadStore) stage_pending_thread_metadata(thread_id codex_protocol.ThreadId, patch ThreadMetadataPatch) ThreadStoreOperationResult {
	_ = store
	_ = patch
	return ThreadStoreOperationResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'stage pending thread metadata requires codex-thread-store'
			thread_id: thread_id
		}
	}
}

// STUB: codex-thread-store removes pending metadata after a failed start/fork.
pub fn (store &ThreadStore) remove_pending_thread_metadata(thread_id codex_protocol.ThreadId) ThreadStoreOperationResult {
	_ = store
	return ThreadStoreOperationResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'remove pending thread metadata requires codex-thread-store'
			thread_id: thread_id
		}
	}
}

// STUB: codex-thread-store exposes paginated timeline entries.
pub struct StoreListTimelineParams {
pub:
	thread_id codex_protocol.ThreadId
	cursor    ?string
	page_size int
}

// STUB: StoreTimelinePage is returned by codex-thread-store's timeline query.
pub struct StoreTimelinePage {
pub:
	items                                 []codex_app_server_protocol.ThreadTimelineEntry
	next_cursor                           ?string
	active_realtime_session_at_page_start ?string
}

// STUB: StoreTimelineResult preserves the typed store error returned by list_timeline.
pub struct StoreTimelineResult {
pub:
	is_error    bool
	value       StoreTimelinePage
	error_value ThreadStoreError
}

// STUB: codex-thread-store exposes paginated timeline entries.
pub fn (store &ThreadStore) list_timeline(params StoreListTimelineParams) StoreTimelineResult {
	_ = store
	return StoreTimelineResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'list timeline requires codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store archives only the selected ids while locking all affected writers.
pub fn (store &ThreadStore) archive_threads(thread_ids []codex_protocol.ThreadId, writer_lock_thread_ids []codex_protocol.ThreadId) ArchiveThreadsResult {
	_ = store
	_ = writer_lock_thread_ids
	return ArchiveThreadsResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'archive threads requires codex-thread-store'
			thread_id: if thread_ids.len > 0 { thread_ids[0] } else { codex_protocol.ThreadId{} }
		}
	}
}

// STUB: codex-thread-store reads a project and preserves missing versus typed failure outcomes.
pub fn (store &ThreadStore) read_project(project_id string) ProjectReadResult {
	_ = store
	return ProjectReadResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'read project requires codex-thread-store'
			operation: 'read_project'
			thread_id: codex_protocol.ThreadId{ value: project_id }
		}
	}
}

// STUB: ThreadStore reports whether its backend implements project APIs.
pub fn (store &ThreadStore) supports_projects() bool {
	return store.available
}

// STUB: reports whether the backend implements paginated history list APIs.
pub fn (store &ThreadStore) supports_paginated_history_lists() bool {
	return store.available
}

// STUB: LocalThreadStore is the only backend that supports rollout-path queries.
pub fn (store &ThreadStore) supports_rollout_path_queries() bool {
	return store.available
}

// STUB: codex-thread-store unarchives and returns the stored thread.
pub fn (store &ThreadStore) unarchive_thread(thread_id codex_protocol.ThreadId) UnarchiveThreadResult {
	_ = store
	return UnarchiveThreadResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'unarchive thread requires codex-thread-store'
			thread_id: thread_id
		}
	}
}

// STUB: codex-thread-store reverts durable paginated history.
pub fn (store &ThreadStore) revert_thread(params RevertThreadParams) ThreadStoreOperationResult {
	_ = store
	return ThreadStoreOperationResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'revert thread requires codex-thread-store'
			operation: 'revert'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store reads a thread, optionally hydrating legacy history.
pub fn (store &ThreadStore) read_thread(params StoreReadThreadParams) ThreadReadResult {
	_ = store
	_ = params.include_archived
	_ = params.include_history
	return ThreadReadResult{
		kind:        .error
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'read thread requires codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store materializes the live rollout into its durable projection.
pub fn (store &ThreadStore) persist_thread(thread_id codex_protocol.ThreadId, context PersistContext) ThreadStoreOperationResult {
	_ = store
	_ = context
	return ThreadStoreOperationResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'persist thread requires codex-thread-store'
			thread_id: thread_id
		}
	}
}

// STUB: codex-thread-store reads a thread by its rollout path.
pub fn (store &ThreadStore) read_thread_by_rollout_path(params StoreReadThreadByRolloutPathParams) ThreadReadResult {
	_ = store
	_ = params.include_archived
	_ = params.include_history
	return ThreadReadResult{
		kind:        .error
		error_value: ThreadStoreError{
			kind:    .internal
			message: 'rollout path read requires codex-thread-store: ${params.rollout_path}'
		}
	}
}

// STUB: codex-thread-store loads the latest model context for paginated resume.
pub fn (store &ThreadStore) load_latest_model_context(params StoreLoadThreadHistoryParams) LoadThreadModelContextResult {
	_ = store
	return LoadThreadModelContextResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'latest model context requires codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store prepares a paginated fork at a typed turn boundary.
pub fn (store &ThreadStore) prepare_fork(params PrepareForkParams) PrepareForkResult {
	_ = store
	return PrepareForkResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'prepare fork requires codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store searches occurrence rows.
pub fn (store &ThreadStore) search_thread_occurrences(params StoreSearchThreadOccurrencesParams) SearchThreadOccurrencesResult {
	_ = store
	return SearchThreadOccurrencesResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'thread occurrence search requires codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store returns one persisted turn page with its typed store error.
pub fn (store &ThreadStore) list_turns(params ListTurnsParams) ListTurnsResult {
	_ = store
	return ListTurnsResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'paginated turns require codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store returns one persisted item page with its typed store error.
pub fn (store &ThreadStore) list_items(params ListItemsParams) ListItemsResult {
	_ = store
	return ListItemsResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:      .internal
			message:   'thread items require codex-thread-store'
			thread_id: params.thread_id
		}
	}
}

// STUB: codex-thread-store returns a filtered persisted thread page.
pub fn (store &ThreadStore) list_threads(params ListThreadsParams) ListThreadsResult {
	_ = store
	return ListThreadsResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:    .internal
			message: 'thread list requires codex-thread-store'
		}
	}
}

// STUB: codex-thread-store returns one full-text search page.
pub fn (store &ThreadStore) search_threads(params StoreSearchThreadsParams) SearchThreadsResult {
	_ = store
	return SearchThreadsResult{
		is_error:    true
		error_value: ThreadStoreError{
			kind:    .internal
			message: 'thread search requires codex-thread-store'
		}
	}
}
