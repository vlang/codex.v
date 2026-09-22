module runtime

import codex_protocol
import codex_protocol.thread_id as protocol_thread_id
import codex_state.model
import rand
import sqlx
import time

const job_kind_memory_stage1 = 'memory_stage1'
const job_kind_memory_consolidate_global = 'memory_consolidate_global'
const memory_consolidation_job_key = 'global'
const phase2_success_cooldown_seconds = i64(6 * 60 * 60)
const phase2_input_selection_page_size = 512

const default_retry_remaining = i64(3)

// Store for generated memory state and memory extraction/consolidation jobs.
//
// The untranslated V state runtime currently supplies a target-specific SqlitePool projection.
// Like Rust's Arc<SqlitePool>, these references are copyable handles with interior mutation.
pub struct MemoryStore {
	pool       &SqlitePool = unsafe { nil }
	state_pool &SqlitePool = unsafe { nil }
}

pub fn MemoryStore.new(pool &SqlitePool, state_pool &SqlitePool) MemoryStore {
	return MemoryStore{
		pool:       pool
		state_pool: state_pool
	}
}

pub fn (store &MemoryStore) close() {
	store.pool.close()
}

// Deletes all persisted memory state in one transaction.
//
// This removes every `stage1_outputs` row and all `jobs` rows for the
// stage-1 (`memory_stage1`) and phase-2 (`memory_consolidate_global`)
// memory pipelines.
pub fn (store &MemoryStore) clear_memory_data() ! {
	clear_memory_data_in_pool(store.pool)!
}

// Record usage for cited stage-1 outputs.
//
// Each thread id increments `usage_count` by one and sets `last_usage` to
// the current Unix timestamp. Missing rows are ignored.
pub fn (store &MemoryStore) record_stage1_output_usage(thread_ids &[]codex_protocol.ThreadId) !usize {
	if thread_ids.len == 0 {
		return 0
	}
	now := time.now().unix()
	mut tx := store.pool.begin()!
	mut updated_rows := usize(0)
	for thread_id in *thread_ids {
		updated_rows += usize(sqlx.query('
UPDATE stage1_outputs
SET
    usage_count = COALESCE(usage_count, 0) + 1,
    last_usage = ?
WHERE thread_id = ?
                ').bind(now).bind(thread_id.value.clone()).execute(tx)!.rows_affected())
	}
	tx.commit()!
	return updated_rows
}

fn (store &MemoryStore) stage1_source_needs_update(thread_id codex_protocol.ThreadId, source_updated_at i64) !bool {
	id := thread_id.value
	if existing_output := sqlx.query('
SELECT source_updated_at
FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id.clone()).fetch_optional(store.pool)!.get() {
		if existing_output.try_get[i64]('source_updated_at')! >= source_updated_at {
			return false
		}
	}
	if existing_job := sqlx.query('
SELECT last_success_watermark
FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_stage1).bind(id.clone()).fetch_optional(store.pool)!.get() {
		watermark := existing_job.try_get[sqlx.OptionalI64]('last_success_watermark')!
		if watermark.has_value {
			if watermark.value >= source_updated_at {
				return false
			}
		}
	}
	return true
}

// Selects and claims stage-1 startup jobs for stale threads.
//
// Query behavior:
// - starts from `threads` filtered to active threads and allowed sources
//   (`push_thread_filters`)
// - excludes threads with `memory_mode != 'enabled'`
// - excludes the current thread id
// - keeps only threads whose millisecond `updated_at` is in the age window
// - checks memory staleness against the memories DB
// - orders by `updated_at_ms DESC` and applies `scan_limit` to bound
//   state-DB work before probing the memories DB
//
// For each selected thread, this function calls [`Self::try_claim_stage1_job`]
// with `source_updated_at = thread.updated_at.timestamp()` and returns up to
// `max_claimed` successful claims.
pub fn (store &MemoryStore) claim_stage1_jobs_for_startup(current_thread_id codex_protocol.ThreadId, params model.Stage1StartupClaimParams) ![]model.Stage1JobClaim {
	if params.scan_limit == 0 || params.max_claimed == 0 {
		return []model.Stage1JobClaim{}
	}
	worker_id := current_thread_id
	current_id := worker_id.value.clone()
	max_age_cutoff := time.now().unix_milli() - max_i64(params.max_age_days, 0) * 24 * 60 * 60 * 1_000
	idle_cutoff := time.now().unix_milli() - max_i64(params.min_rollout_idle_hours, 0) * 60 * 60 * 1_000
	mut builder := sqlx.new_query_builder('
SELECT
    threads.id,
    threads.rollout_path,
    threads.created_at_ms AS created_at,
    threads.updated_at_ms AS updated_at,
    threads.recency_at_ms AS recency_at,
    threads.source,
    threads.originator,
    threads.history_mode,
    threads.thread_source,
    threads.agent_path,
    threads.agent_nickname,
    threads.agent_role,
    threads.model_provider,
    threads.model,
    threads.reasoning_effort,
    threads.cwd,
    threads.cli_version,
    threads.title,
    threads.name,
    threads.preview,
    threads.sandbox_policy,
    threads.approval_mode,
    threads.tokens_used,
    threads.first_user_message,
    threads.archived_at,
    threads.thread_section_id AS section,
    (
        SELECT thread_sections.name
        FROM thread_sections
        WHERE thread_sections.id = threads.thread_section_id
    ) AS section_name,
    (
        SELECT thread_sections.appearance
        FROM thread_sections
        WHERE thread_sections.id = threads.thread_section_id
    ) AS section_appearance,
    threads.section_position,
    threads.section_entered_at_ms,
    threads.project_id,
    threads.daybreak_enabled,
    threads.git_sha,
    threads.git_branch,
    threads.git_origin_url
FROM threads
            ')
	push_thread_filters(mut builder, ThreadFilterOptions{
		archived_only:   false
		allowed_sources: params.allowed_sources
		model_providers: optional_borrowed_strings_none()
		cwd_filters:     optional_borrowed_strings_none()
		section:         nested_optional_borrowed_string_none()
		project_id:      nested_optional_borrowed_string_none()
		anchor:          optional_borrowed_anchor_none()
		sort_key:        .updated_at
		sort_direction:  .desc
		search_term:     model.borrowed_string_none()
	}, /* include_thread_id_tiebreaker */
		false)
	builder.push(" AND threads.memory_mode = 'enabled'")
	builder.push(' AND threads.id != ')
	builder.push_bind(current_id.clone())
	builder.push(' AND ')
	builder.push('threads.updated_at_ms')
	builder.push(' >= ')
	builder.push_bind(max_age_cutoff)
	builder.push(' AND ')
	builder.push('threads.updated_at_ms')
	builder.push(' <= ')
	builder.push_bind(idle_cutoff)
	scan_limit_i64 := usize_to_i64_saturating(params.scan_limit)
	builder.push(' ORDER BY threads.updated_at_ms DESC LIMIT ')
	builder.push_bind(scan_limit_i64)
	rows := builder.build().fetch_all(store.state_pool)!
	mut items := []model.ThreadMetadata{}
	for row in rows {
		thread_row := model.ThreadRow.try_from_row(&row)!
		items << model.ThreadMetadata.try_from(thread_row)!
	}
	mut claimed := []model.Stage1JobClaim{}
	for item in items {
		if claimed.len >= int(params.max_claimed) {
			break
		}
		source_updated_at := item.updated_at.unix()
		item_id_for_check := clone_thread_id(&item.id)
		if !store.stage1_source_needs_update(item_id_for_check, source_updated_at)! {
			continue
		}
		outcome := store.try_claim_stage1_job(clone_thread_id(&item.id), codex_protocol.ThreadId{
			value: worker_id.value.clone()
		}, source_updated_at, params.lease_seconds, params.max_claimed)!
		if outcome.kind == .claimed {
			claimed << model.Stage1JobClaim{
				thread:          item
				ownership_token: outcome.ownership_token
			}
		}
	}
	return claimed
}

fn stage1_startup_age_window_contains(updated_at_ms i64, now_ms i64, max_age_days i64, min_rollout_idle_hours i64) bool {
	max_age_cutoff_ms := now_ms - max_i64(max_age_days, 0) * 24 * 60 * 60 * 1_000
	idle_cutoff_ms := now_ms - max_i64(min_rollout_idle_hours, 0) * 60 * 60 * 1_000
	return updated_at_ms >= max_age_cutoff_ms && updated_at_ms <= idle_cutoff_ms
}

pub fn (store &MemoryStore) delete_thread_memory(thread_id codex_protocol.ThreadId) ! {
	now := time.now().unix()
	id := thread_id.value
	mut tx := store.pool.begin()!
	selected_row := sqlx.query('
SELECT selected_for_phase2
FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id.clone()).fetch_optional(tx)!
	was_selected := if row := selected_row.get() {
		row.try_get[i64]('selected_for_phase2')! != 0
	} else {
		false
	}
	deleted_rows := sqlx.query('
DELETE FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id.clone()).execute(tx)!.rows_affected()
	sqlx.query('
DELETE FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_stage1).bind(id).execute(tx)!
	if deleted_rows > 0 && was_selected {
		enqueue_global_consolidation_with_executor(tx, now)!
	}
	tx.commit()!
}

// Lists the most recent non-empty stage-1 outputs for global consolidation.
//
// Query behavior:
// - filters out rows where both `raw_memory` and `rollout_summary` are blank
// - hydrates thread `cwd`, `rollout_path`, and `git_branch` from the state DB
// - filters out missing or non-enabled threads
// - orders by `source_updated_at DESC, thread_id DESC`
// - returns the first `n` visible outputs
pub fn (store &MemoryStore) list_stage1_outputs_for_global(n usize) ![]model.Stage1Output {
	if n == 0 {
		return []model.Stage1Output{}
	}
	rows := sqlx.query('
SELECT
    so.thread_id,
    so.source_updated_at,
    so.raw_memory,
    so.rollout_summary,
    so.rollout_slug,
    so.generated_at
FROM stage1_outputs AS so
WHERE length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0
ORDER BY so.source_updated_at DESC, so.thread_id DESC
            ').fetch_all(store.pool)!
	mut outputs := []model.Stage1Output{}
	for row in rows {
		output := store.stage1_output_from_row_if_thread_enabled(&row)!
		if output.has_value {
			outputs << output.value
			if outputs.len >= int(n) {
				break
			}
		}
	}
	return outputs
}

// Prunes stale stage-1 outputs while preserving the latest phase-2
// baseline and stage-1 job watermarks.
//
// Query behavior:
// - considers only rows with `selected_for_phase2 = 0`
// - keeps recency as `COALESCE(last_usage, source_updated_at)`
// - removes rows older than `max_unused_days`
// - prunes at most `limit` rows ordered from stalest to newest
pub fn (store &MemoryStore) prune_stage1_outputs_for_retention(max_unused_days i64, limit usize) !usize {
	if limit == 0 {
		return 0
	}
	cutoff := time.now().unix() - max_i64(max_unused_days, 0) * 24 * 60 * 60
	return usize(sqlx.query('
DELETE FROM stage1_outputs
WHERE thread_id IN (
    SELECT thread_id
    FROM stage1_outputs
    WHERE selected_for_phase2 = 0
      AND COALESCE(last_usage, source_updated_at) < ?
    ORDER BY
      COALESCE(last_usage, source_updated_at) ASC,
      source_updated_at ASC,
      thread_id ASC
    LIMIT ?
)
            ').bind(cutoff).bind(i64(limit)).execute(store.pool)!.rows_affected())
}

// Returns the current phase-2 input set.
//
// Query behavior:
// - current selection keeps only non-empty stage-1 outputs whose
//   `last_usage` is within `max_unused_days`, or whose
//   `source_updated_at` is within that window when the memory has never
//   been used
// - eligible rows are ranked by `usage_count DESC`,
//   `COALESCE(last_usage, source_updated_at) DESC`, `source_updated_at DESC`,
//   `thread_id DESC`
// - the selected top-N rows are returned in stable `thread_id ASC` order
//
// The returned rows are the complete Phase 2 filesystem input. Phase 2
// syncs these rows directly; deletions are represented by the workspace
// diff against the previous successful memory baseline.
pub fn (store &MemoryStore) get_phase2_input_selection(n usize, max_unused_days i64) ![]model.Stage1Output {
	if n == 0 {
		return []model.Stage1Output{}
	}
	cutoff := time.now().unix() - max_i64(max_unused_days, 0) * 24 * 60 * 60
	page_size := clamp_usize(n, 1, phase2_input_selection_page_size)
	page_size_i64 := usize_to_i64_saturating(page_size)
	mut offset := i64(0)
	mut selected_keys := []Stage1OutputKey{cap: int(n)}
	for selected_keys.len < int(n) {
		candidate_rows := sqlx.query('
SELECT
    so.thread_id,
    so.source_updated_at
FROM stage1_outputs AS so
WHERE (length(trim(so.raw_memory)) > 0 OR length(trim(so.rollout_summary)) > 0)
  AND (
        (so.last_usage IS NOT NULL AND so.last_usage >= ?)
        OR (so.last_usage IS NULL AND so.source_updated_at >= ?)
  )
ORDER BY
    COALESCE(so.usage_count, 0) DESC,
    COALESCE(so.last_usage, so.source_updated_at) DESC,
    so.source_updated_at DESC,
    so.thread_id DESC
LIMIT ? OFFSET ?
            ').bind(cutoff).bind(cutoff).bind(page_size_i64).bind(offset).fetch_all(store.pool)!
		if candidate_rows.len == 0 {
			break
		}
		candidate_count := usize_to_i64_saturating(usize(candidate_rows.len))
		for row in candidate_rows {
			thread_id := row.try_get[string]('thread_id')!
			source_updated_at := row.try_get[i64]('source_updated_at')!
			enabled := store.enabled_thread_metadata(protocol_thread_id.from_string(&thread_id)!)!
			if enabled.has_value {
				selected_keys << Stage1OutputKey{ thread_id: thread_id, source_updated_at: source_updated_at }
				if selected_keys.len >= int(n) {
					break
				}
			}
		}
		offset = saturating_add_i64(offset, candidate_count)
	}
	mut selected := []model.Stage1Output{cap: selected_keys.len}
	for key in selected_keys {
		if row := sqlx.query('
SELECT
    so.thread_id,
    so.source_updated_at,
    so.raw_memory,
    so.rollout_summary,
    so.rollout_slug,
    so.generated_at
FROM stage1_outputs AS so
WHERE so.thread_id = ? AND so.source_updated_at = ?
            ').bind(key.thread_id).bind(key.source_updated_at).fetch_optional(store.pool)!.get() {
			output := store.stage1_output_from_row_if_thread_enabled(&row)!
			if output.has_value { selected << output.value }
		}
	}
	selected.sort_with_compare(fn (a &model.Stage1Output, b &model.Stage1Output) int {
		return if a.thread_id.value < b.thread_id.value {
			-1
		} else if a.thread_id.value > b.thread_id.value { 1 } else { 0 }
	})
	return selected
}

struct Stage1OutputKey {
	thread_id         string
	source_updated_at i64
}

struct OptionalStage1Output {
	has_value bool
	value     model.Stage1Output
}

struct OptionalThreadMetadata {
	has_value bool
	value     model.ThreadMetadata
}

fn (store &MemoryStore) stage1_output_from_row_if_thread_enabled(row &sqlx.Row) !OptionalStage1Output {
	thread_id := row.try_get[string]('thread_id')!
	item := store.enabled_thread_metadata(protocol_thread_id.from_string(&thread_id)!)!
	if !item.has_value {
		return OptionalStage1Output{}
	}
	return OptionalStage1Output{ has_value: true, value: stage1_output_from_row_and_thread(row, item.value)! }
}

fn (store &MemoryStore) enabled_thread_metadata(thread_id codex_protocol.ThreadId) !OptionalThreadMetadata {
	id := thread_id.value
	optional_row := sqlx.query("
SELECT
    threads.id,
    threads.rollout_path,
    threads.created_at_ms AS created_at,
    threads.updated_at_ms AS updated_at,
    threads.recency_at_ms AS recency_at,
    threads.source,
    threads.originator,
    threads.history_mode,
    threads.thread_source,
    threads.agent_nickname,
    threads.agent_role,
    threads.agent_path,
    threads.model_provider,
    threads.model,
    threads.reasoning_effort,
    threads.cwd,
    threads.cli_version,
    threads.title,
    threads.name,
    threads.preview,
    threads.sandbox_policy,
    threads.approval_mode,
    threads.tokens_used,
    threads.first_user_message,
    threads.archived_at,
    threads.thread_section_id AS section,
    (
        SELECT thread_sections.name
        FROM thread_sections
        WHERE thread_sections.id = threads.thread_section_id
    ) AS section_name,
    (
        SELECT thread_sections.appearance
        FROM thread_sections
        WHERE thread_sections.id = threads.thread_section_id
    ) AS section_appearance,
    threads.section_position,
    threads.section_entered_at_ms,
    threads.project_id,
    threads.daybreak_enabled,
    threads.git_sha,
    threads.git_branch,
    threads.git_origin_url
FROM threads
WHERE threads.id = ? AND threads.memory_mode = 'enabled'
            ").bind(id.clone()).fetch_optional(store.state_pool)!
	if !optional_row.has_value {
		return OptionalThreadMetadata{}
	}
	row := optional_row.get()!
	thread_row := model.ThreadRow.try_from_row(&row)!
	return OptionalThreadMetadata{
		has_value: true
		value:     model.ThreadMetadata.try_from(thread_row)!
	}
}

// Marks a thread as polluted and enqueues phase-2 forgetting when the
// thread participated in the last successful phase-2 baseline.
pub fn (store &MemoryStore) mark_thread_memory_mode_polluted(thread_id codex_protocol.ThreadId) !bool {
	now := time.now().unix()
	id := thread_id.value
	selected_for_phase2 := sqlx.query_scalar[i64]('
SELECT selected_for_phase2
FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id.clone()).fetch_optional(store.pool)!.unwrap_or(0)
	rows_affected := sqlx.query("
UPDATE threads
SET memory_mode = 'polluted'
WHERE id = ? AND memory_mode != 'polluted'
            ").bind(id).execute(store.state_pool)!.rows_affected()
	if selected_for_phase2 != 0 {
		store.enqueue_global_consolidation(now)!
	}
	return rows_affected > 0
}

// Attempts to claim a stage-1 job for a thread at `source_updated_at`.
//
// Claim semantics:
// - skips as up-to-date when either:
//   - `stage1_outputs.source_updated_at >= source_updated_at`, or
//   - `jobs.last_success_watermark >= source_updated_at`
// - inserts or updates a `jobs` row to `running` only when:
//   - global running job count for `memory_stage1` is below `max_running_jobs`
//   - existing row is not actively running with a valid lease
//   - retry backoff (if present) has elapsed, or `source_updated_at` advanced
//   - retries remain, or `source_updated_at` advanced (which resets retries)
//
// The update path refreshes ownership token, lease, and `input_watermark`.
// If claiming fails, a follow-up read maps current row state to a precise
// skip outcome (`SkippedRunning`, `SkippedRetryBackoff`, or
// `SkippedRetryExhausted`).
pub fn (store &MemoryStore) try_claim_stage1_job(thread_id codex_protocol.ThreadId, worker_id codex_protocol.ThreadId, source_updated_at i64, lease_seconds i64, max_running_jobs usize) !model.Stage1JobClaimOutcome {
	now := time.now().unix()
	lease_until := saturating_add_i64(now, max_i64(lease_seconds, 0))
	ownership_token := rand.uuid_v4()
	id := thread_id.value
	worker := worker_id.value
	mut tx := store.pool.begin_with('BEGIN IMMEDIATE')!
	if existing_output := sqlx.query('
SELECT source_updated_at
FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id.clone()).fetch_optional(tx)!.get() {
		if existing_output.try_get[i64]('source_updated_at')! >= source_updated_at {
			tx.commit()!
			return stage1_outcome(.skipped_up_to_date, '')
		}
	}
	if existing_job := sqlx.query('
SELECT last_success_watermark
FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_stage1).bind(id.clone()).fetch_optional(tx)!.get() {
		watermark := existing_job.try_get[sqlx.OptionalI64]('last_success_watermark')!
		if watermark.has_value {
			if watermark.value >= source_updated_at {
				tx.commit()!
				return stage1_outcome(.skipped_up_to_date, '')
			}
		}
	}
	rows_affected := sqlx.query("
INSERT INTO jobs (
    kind,
    job_key,
    status,
    worker_id,
    ownership_token,
    started_at,
    finished_at,
    lease_until,
    retry_at,
    retry_remaining,
    last_error,
    input_watermark,
    last_success_watermark
)
SELECT ?, ?, 'running', ?, ?, ?, NULL, ?, NULL, ?, NULL, ?, NULL
WHERE (
    SELECT COUNT(*)
    FROM jobs
    WHERE kind = ?
      AND status = 'running'
      AND lease_until IS NOT NULL
      AND lease_until > ?
) < ?
ON CONFLICT(kind, job_key) DO UPDATE SET
    status = 'running',
    worker_id = excluded.worker_id,
    ownership_token = excluded.ownership_token,
    started_at = excluded.started_at,
    finished_at = NULL,
    lease_until = excluded.lease_until,
    retry_at = NULL,
    retry_remaining = CASE
        WHEN excluded.input_watermark > COALESCE(jobs.input_watermark, -1) THEN ?
        ELSE jobs.retry_remaining
    END,
    last_error = NULL,
    input_watermark = excluded.input_watermark
WHERE
    (jobs.status != 'running' OR jobs.lease_until IS NULL OR jobs.lease_until <= excluded.started_at)
    AND (
        jobs.retry_at IS NULL
        OR jobs.retry_at <= excluded.started_at
        OR excluded.input_watermark > COALESCE(jobs.input_watermark, -1)
    )
    AND (
        jobs.retry_remaining > 0
        OR excluded.input_watermark > COALESCE(jobs.input_watermark, -1)
    )
    AND (
        SELECT COUNT(*)
        FROM jobs AS running_jobs
        WHERE running_jobs.kind = excluded.kind
          AND running_jobs.status = 'running'
          AND running_jobs.lease_until IS NOT NULL
          AND running_jobs.lease_until > excluded.started_at
          AND running_jobs.job_key != excluded.job_key
    ) < ?
            ").bind(job_kind_memory_stage1).bind(id.clone()).bind(worker).bind(ownership_token.clone()).bind(now).bind(lease_until).bind(default_retry_remaining).bind(source_updated_at).bind(job_kind_memory_stage1).bind(now).bind(i64(max_running_jobs)).bind(default_retry_remaining).bind(i64(max_running_jobs)).execute(tx)!.rows_affected()
	if rows_affected > 0 {
		tx.commit()!
		return stage1_outcome(.claimed, ownership_token)
	}
	existing_job := sqlx.query('
SELECT status, lease_until, retry_at, retry_remaining
FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_stage1).bind(id).fetch_optional(tx)!
	tx.commit()!
	if row := existing_job.get() {
		if row.try_get[i64]('retry_remaining')! <= 0 {
			return stage1_outcome(.skipped_retry_exhausted, '')
		}
		retry_at := row.try_get[sqlx.OptionalI64]('retry_at')!
		if retry_at.has_value {
			if retry_at.value > now {
				return stage1_outcome(.skipped_retry_backoff, '')
			}
		}
		if row.try_get[string]('status')! == 'running' {
			existing_lease := row.try_get[sqlx.OptionalI64]('lease_until')!
			if existing_lease.has_value {
				if existing_lease.value > now {
					return stage1_outcome(.skipped_running, '')
				}
			}
		}
	}
	return stage1_outcome(.skipped_running, '')
}

// Marks a claimed stage-1 job successful and upserts generated output.
//
// Transaction behavior:
// - updates `jobs` only for the currently owned running row
// - sets `status='done'` and `last_success_watermark = input_watermark`
// - upserts `stage1_outputs` for the thread, replacing existing output only
//   when `source_updated_at` is newer or equal
// - preserves any existing `selected_for_phase2` baseline until the next
//   successful phase-2 run rewrites the baseline selection, including the
//   snapshot timestamp chosen during that run
// - persists optional `rollout_slug` for rollout summary artifact naming
// - enqueues/advances the global phase-2 job watermark using
//   `source_updated_at`
pub fn (store &MemoryStore) mark_stage1_job_succeeded(thread_id codex_protocol.ThreadId, ownership_token &string, source_updated_at i64, raw_memory &string, rollout_summary &string, rollout_slug model.OptionalBorrowedString) !bool {
	now := time.now().unix()
	id := thread_id.value
	mut tx := store.pool.begin()!
	rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'done',
    finished_at = ?,
    lease_until = NULL,
    last_error = NULL,
    last_success_watermark = input_watermark
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(now).bind(job_kind_memory_stage1).bind(id.clone()).bind((*ownership_token).clone()).execute(tx)!.rows_affected()
	if rows_affected == 0 {
		tx.commit()!
		return false
	}
	slug_bind := if rollout_slug.has_value {
		sqlx.BindValue(rollout_slug.value.clone())
	} else {
		sqlx.BindValue(sqlx.Null{})
	}
	sqlx.query('
INSERT INTO stage1_outputs (
    thread_id,
    source_updated_at,
    raw_memory,
    rollout_summary,
    rollout_slug,
    generated_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(thread_id) DO UPDATE SET
    source_updated_at = excluded.source_updated_at,
    raw_memory = excluded.raw_memory,
    rollout_summary = excluded.rollout_summary,
    rollout_slug = excluded.rollout_slug,
    generated_at = excluded.generated_at
WHERE excluded.source_updated_at >= stage1_outputs.source_updated_at
            ').bind(id).bind(source_updated_at).bind((*raw_memory).clone()).bind((*rollout_summary).clone()).bind(slug_bind).bind(now).execute(tx)!
	enqueue_global_consolidation_with_executor(tx, source_updated_at)!
	tx.commit()!
	return true
}

// Marks a claimed stage-1 job successful when extraction produced no output.
//
// Transaction behavior:
// - updates `jobs` only for the currently owned running row
// - sets `status='done'` and `last_success_watermark = input_watermark`
// - deletes any existing `stage1_outputs` row for the thread
// - enqueues/advances the global phase-2 job watermark using the claimed
//   `input_watermark` only when deleting an existing `stage1_outputs` row
pub fn (store &MemoryStore) mark_stage1_job_succeeded_no_output(thread_id codex_protocol.ThreadId, ownership_token &string) !bool {
	now := time.now().unix()
	id := thread_id.value
	mut tx := store.pool.begin()!
	rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'done',
    finished_at = ?,
    lease_until = NULL,
    last_error = NULL,
    last_success_watermark = input_watermark
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(now).bind(job_kind_memory_stage1).bind(id.clone()).bind((*ownership_token).clone()).execute(tx)!.rows_affected()
	if rows_affected == 0 {
		tx.commit()!
		return false
	}
	source_updated_at := sqlx.query('
SELECT input_watermark
FROM jobs
WHERE kind = ? AND job_key = ? AND ownership_token = ?
            ').bind(job_kind_memory_stage1).bind(id.clone()).bind((*ownership_token).clone()).fetch_one(tx)!.try_get[i64]('input_watermark')!
	deleted_rows := sqlx.query('
DELETE FROM stage1_outputs
WHERE thread_id = ?
            ').bind(id).execute(tx)!.rows_affected()
	if deleted_rows > 0 {
		enqueue_global_consolidation_with_executor(tx, source_updated_at)!
	}
	tx.commit()!
	return true
}

// Marks a claimed stage-1 job as failed and schedules retry backoff.
//
// Query behavior:
// - updates only the owned running row for `(kind='memory_stage1', job_key)`
// - sets `status='error'`, clears lease, writes `last_error`
// - decrements `retry_remaining`
// - sets `retry_at = now + retry_delay_seconds`
pub fn (store &MemoryStore) mark_stage1_job_failed(thread_id codex_protocol.ThreadId, ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	now := time.now().unix()
	retry_at := saturating_add_i64(now, max_i64(retry_delay_seconds, 0))
	id := thread_id.value
	rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'error',
    finished_at = ?,
    lease_until = NULL,
    retry_at = ?,
    retry_remaining = retry_remaining - 1,
    last_error = ?
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(now).bind(retry_at).bind((*failure_reason).clone()).bind(job_kind_memory_stage1).bind(id).bind((*ownership_token).clone()).execute(store.pool)!.rows_affected()
	return rows_affected > 0
}

// Enqueues or advances the global phase-2 consolidation job watermark.
//
// The underlying upsert keeps the job `running` when already running, resets
// `pending/error` jobs to `pending`, and advances `input_watermark` as
// bookkeeping even when `source_updated_at` is older than prior maxima.
// Phase 2 does not use this watermark as a dirty check; git workspace diffing
// decides whether consolidation work exists after the lock is claimed.
pub fn (store &MemoryStore) enqueue_global_consolidation(input_watermark i64) ! {
	enqueue_global_consolidation_with_executor(store.pool, input_watermark)!
}

// Attempts to claim the global phase-2 consolidation lock.
//
// Claim semantics:
// - reads the singleton global job row (`kind='memory_consolidate_global'`)
// - creates and claims the singleton row when it does not exist yet
// - does not use DB watermarks to decide whether Phase 2 has work; git workspace
//   dirtiness is the source of truth after the caller materializes inputs
// - returns `SkippedRetryUnavailable` when retry backoff is active
// - returns `SkippedRunning` when an active running lease exists
// - returns `SkippedCooldown` when the latest successful run finished
//   within the phase-2 success cooldown
// - otherwise updates the row to `running`, sets ownership + lease, and
//   returns `Claimed`
pub fn (store &MemoryStore) try_claim_global_phase2_job(worker_id codex_protocol.ThreadId, lease_seconds i64) !model.Phase2JobClaimOutcome {
	now := time.now().unix()
	lease_until := saturating_add_i64(now, max_i64(lease_seconds, 0))
	cooldown_cutoff := saturating_sub_i64(now, phase2_success_cooldown_seconds)
	ownership_token := rand.uuid_v4()
	worker := worker_id.value
	mut tx := store.pool.begin_with('BEGIN IMMEDIATE')!
	existing_job := sqlx.query('
SELECT status, lease_until, retry_at, input_watermark, finished_at, last_error
FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).fetch_optional(tx)!
	if row := existing_job.get() {
		input_watermark_optional := row.try_get[sqlx.OptionalI64]('input_watermark')!
		input_watermark := if input_watermark_optional.has_value {
			input_watermark_optional.value
		} else {
			i64(0)
		}
		retry_at := row.try_get[sqlx.OptionalI64]('retry_at')!
		if retry_at.has_value {
			if retry_at.value > now {
				tx.commit()!
				return phase2_outcome(.skipped_retry_unavailable, '', input_watermark)
			}
		}
		if row.try_get[string]('status')! == 'running' {
			existing_lease := row.try_get[sqlx.OptionalI64]('lease_until')!
			if existing_lease.has_value {
				if existing_lease.value > now {
					tx.commit()!
					return phase2_outcome(.skipped_running, '', input_watermark)
				}
			}
		}
		last_error := row.try_get[sqlx.OptionalString]('last_error')!
		if !last_error.has_value {
			finished_at := row.try_get[sqlx.OptionalI64]('finished_at')!
			if finished_at.has_value {
				if finished_at.value > cooldown_cutoff {
					tx.commit()!
					return phase2_outcome(.skipped_cooldown, '', input_watermark)
				}
			}
		}
		rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'running',
    worker_id = ?,
    ownership_token = ?,
    started_at = ?,
    finished_at = NULL,
    lease_until = ?,
    retry_at = NULL,
    last_error = NULL
WHERE kind = ? AND job_key = ?
  AND (status != 'running' OR lease_until IS NULL OR lease_until <= ?)
  AND (retry_at IS NULL OR retry_at <= ?)
  AND (last_error IS NOT NULL OR finished_at IS NULL OR finished_at <= ?)
            ").bind(worker).bind(ownership_token.clone()).bind(now).bind(lease_until).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind(now).bind(now).bind(cooldown_cutoff).execute(tx)!.rows_affected()
		tx.commit()!
		return if rows_affected == 0 {
			phase2_outcome(.skipped_running, '', input_watermark)
		} else {
			phase2_outcome(.claimed, ownership_token, input_watermark)
		}
	}
	rows_affected := sqlx.query("
INSERT INTO jobs (
    kind,
    job_key,
    status,
    worker_id,
    ownership_token,
    started_at,
    finished_at,
    lease_until,
    retry_at,
    retry_remaining,
    last_error,
    input_watermark,
    last_success_watermark
) VALUES (?, ?, 'running', ?, ?, ?, NULL, ?, NULL, ?, NULL, 0, 0)
                ").bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind(worker).bind(ownership_token.clone()).bind(now).bind(lease_until).bind(default_retry_remaining).execute(tx)!.rows_affected()
	tx.commit()!
	return if rows_affected == 0 {
		phase2_outcome(.skipped_running, '', 0)
	} else {
		phase2_outcome(.claimed, ownership_token, 0)
	}
}

// Extends the lease for an owned running phase-2 global job.
//
// Query behavior:
// - `UPDATE jobs SET lease_until = ?` for the singleton global row
// - requires `status='running'` and matching `ownership_token`
pub fn (store &MemoryStore) heartbeat_global_phase2_job(ownership_token &string, lease_seconds i64) !bool {
	now := time.now().unix()
	lease_until := saturating_add_i64(now, max_i64(lease_seconds, 0))
	rows_affected := sqlx.query("
UPDATE jobs
SET lease_until = ?
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(lease_until).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind((*ownership_token).clone()).execute(store.pool)!.rows_affected()
	return rows_affected > 0
}

// Marks the owned running global phase-2 job as succeeded.
//
// Query behavior:
// - updates only the owned running singleton global row
// - sets `status='done'`, clears lease/errors
// - advances `last_success_watermark` to
//   `max(existing_last_success_watermark, completed_watermark)`
// - rewrites `selected_for_phase2` so only the exact selected stage-1
//   snapshots remain marked as part of the latest successful phase-2
//   selection, and persists each selected snapshot's `source_updated_at`
pub fn (store &MemoryStore) mark_global_phase2_job_succeeded(ownership_token &string, completed_watermark i64, selected_outputs &[]model.Stage1Output) !bool {
	mut tx := store.pool.begin()!
	rows_affected := mark_global_phase2_job_succeeded_row(tx, ownership_token, completed_watermark)!
	if rows_affected == 0 {
		tx.commit()!
		return false
	}
	sqlx.query('
UPDATE stage1_outputs
SET
    selected_for_phase2 = 0,
    selected_for_phase2_source_updated_at = NULL
WHERE selected_for_phase2 != 0 OR selected_for_phase2_source_updated_at IS NOT NULL
            ').execute(tx)!
	for output in *selected_outputs {
		selected_at := output.source_updated_at.unix()
		sqlx.query('
UPDATE stage1_outputs
SET
    selected_for_phase2 = 1,
    selected_for_phase2_source_updated_at = ?
WHERE thread_id = ? AND source_updated_at = ?
                ').bind(selected_at).bind(output.thread_id.value.clone()).bind(selected_at).execute(tx)!
	}
	tx.commit()!
	return true
}

// Marks the owned running global phase-2 job as failed and schedules retry.
//
// Query behavior:
// - updates only the owned running singleton global row
// - sets `status='error'`, clears lease
// - writes failure reason and retry time
// - decrements `retry_remaining` without going below zero
pub fn (store &MemoryStore) mark_global_phase2_job_failed(ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	now := time.now().unix()
	retry_at := saturating_add_i64(now, max_i64(retry_delay_seconds, 0))
	rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'error',
    finished_at = ?,
    lease_until = NULL,
    retry_at = ?,
    retry_remaining = max(retry_remaining - 1, 0),
    last_error = ?
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(now).bind(retry_at).bind((*failure_reason).clone()).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind((*ownership_token).clone()).execute(store.pool)!.rows_affected()
	return rows_affected > 0
}

// Fallback failure finalization when ownership may have been lost.
//
// Query behavior:
// - same state transition as [`Self::mark_global_phase2_job_failed`]
// - matches rows where `ownership_token = ? OR ownership_token IS NULL`
// - allows recovering a stuck unowned running row
pub fn (store &MemoryStore) mark_global_phase2_job_failed_if_unowned(ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	now := time.now().unix()
	retry_at := saturating_add_i64(now, max_i64(retry_delay_seconds, 0))
	rows_affected := sqlx.query("
UPDATE jobs
SET
    status = 'error',
    finished_at = ?,
    lease_until = NULL,
    retry_at = ?,
    retry_remaining = max(retry_remaining - 1, 0),
    last_error = ?
WHERE kind = ? AND job_key = ?
  AND status = 'running'
  AND (ownership_token = ? OR ownership_token IS NULL)
            ").bind(now).bind(retry_at).bind((*failure_reason).clone()).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind((*ownership_token).clone()).execute(store.pool)!.rows_affected()
	return rows_affected > 0
}

fn mark_global_phase2_job_succeeded_row(executor sqlx.Executor, ownership_token &string, completed_watermark i64) !u64 {
	now := time.now().unix()
	return sqlx.query("
UPDATE jobs
SET
    status = 'done',
    finished_at = ?,
    lease_until = NULL,
    last_error = NULL,
    last_success_watermark = max(COALESCE(last_success_watermark, 0), ?)
WHERE kind = ? AND job_key = ?
  AND status = 'running' AND ownership_token = ?
            ").bind(now).bind(completed_watermark).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind((*ownership_token).clone()).execute(executor)!.rows_affected()
}

pub fn clear_memory_data_in_pool(pool &SqlitePool) ! {
	mut tx := pool.begin()!
	sqlx.query('
DELETE FROM stage1_outputs
        ').execute(tx)!
	sqlx.query('
DELETE FROM jobs
WHERE kind = ? OR kind = ?
        ').bind(job_kind_memory_stage1).bind(job_kind_memory_consolidate_global).execute(tx)!
	tx.commit()!
}

fn stage1_output_from_row_and_thread(row &sqlx.Row, item model.ThreadMetadata) !model.Stage1Output {
	slug := row.try_get[sqlx.OptionalString]('rollout_slug')!
	rollout_slug := if slug.has_value {
		model.some_string(slug.value)
	} else {
		model.OptionalString{}
	}
	return model.Stage1Output{
		thread_id:         item.id
		rollout_path:      item.rollout_path
		source_updated_at: datetime_from_epoch_seconds(row.try_get[i64]('source_updated_at')!)!
		raw_memory:        row.try_get[string]('raw_memory')!
		rollout_summary:   row.try_get[string]('rollout_summary')!
		rollout_slug:      rollout_slug
		cwd:               item.cwd
		git_branch:        item.git_branch
		generated_at:      datetime_from_epoch_seconds(row.try_get[i64]('generated_at')!)!
	}
}

fn datetime_from_epoch_seconds(secs i64) !time.Time {
	// chrono rejects timestamps beyond its representable calendar range. V's time.unix accepts the
	// full i64 domain, so retain the equivalent guard before constructing the owned Time value.
	if secs < -8_334_601_228_800 || secs > 8_210_266_876_799 {
		return error('invalid unix timestamp: ${secs}')
	}
	return time.unix(secs)
}

fn enqueue_global_consolidation_with_executor(executor sqlx.Executor, input_watermark i64) ! {
	sqlx.query("
INSERT INTO jobs (
    kind,
    job_key,
    status,
    worker_id,
    ownership_token,
    started_at,
    finished_at,
    lease_until,
    retry_at,
    retry_remaining,
    last_error,
    input_watermark,
    last_success_watermark
) VALUES (?, ?, 'pending', NULL, NULL, NULL, NULL, NULL, NULL, ?, NULL, ?, 0)
ON CONFLICT(kind, job_key) DO UPDATE SET
    status = CASE
		WHEN jobs.status = 'running' THEN 'running'
		ELSE 'pending'
    END,
    retry_at = CASE
		WHEN jobs.status = 'running' THEN jobs.retry_at
		ELSE NULL
    END,
	retry_remaining = max(jobs.retry_remaining, excluded.retry_remaining),
	input_watermark = CASE
		WHEN excluded.input_watermark > COALESCE(jobs.input_watermark, 0)
			THEN excluded.input_watermark
		ELSE COALESCE(jobs.input_watermark, 0) + 1
	END
        ").bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).bind(default_retry_remaining).bind(input_watermark).execute(executor)!
}

fn (state &StateRuntime) clear_memory_data() ! {
	state.memories.clear_memory_data()!
}

fn (state &StateRuntime) record_stage1_output_usage(thread_ids &[]codex_protocol.ThreadId) !usize {
	return state.memories.record_stage1_output_usage(thread_ids)
}

fn (state &StateRuntime) claim_stage1_jobs_for_startup(current_thread_id codex_protocol.ThreadId, params model.Stage1StartupClaimParams) ![]model.Stage1JobClaim {
	return state.memories.claim_stage1_jobs_for_startup(current_thread_id, params)
}

fn (state &StateRuntime) list_stage1_outputs_for_global(n usize) ![]model.Stage1Output {
	return state.memories.list_stage1_outputs_for_global(n)
}

fn (state &StateRuntime) prune_stage1_outputs_for_retention(max_unused_days i64, limit usize) !usize {
	return state.memories.prune_stage1_outputs_for_retention(max_unused_days, limit)
}

fn (state &StateRuntime) get_phase2_input_selection(n usize, max_unused_days i64) ![]model.Stage1Output {
	return state.memories.get_phase2_input_selection(n, max_unused_days)
}

fn (state &StateRuntime) mark_thread_memory_mode_polluted(thread_id codex_protocol.ThreadId) !bool {
	return state.memories.mark_thread_memory_mode_polluted(thread_id)
}

fn (state &StateRuntime) try_claim_stage1_job(thread_id codex_protocol.ThreadId, worker_id codex_protocol.ThreadId, source_updated_at i64, lease_seconds i64, max_running_jobs usize) !model.Stage1JobClaimOutcome {
	return state.memories.try_claim_stage1_job(thread_id, worker_id, source_updated_at, lease_seconds, max_running_jobs)
}

fn (state &StateRuntime) mark_stage1_job_succeeded(thread_id codex_protocol.ThreadId, ownership_token &string, source_updated_at i64, raw_memory &string, rollout_summary &string, rollout_slug model.OptionalBorrowedString) !bool {
	return state.memories.mark_stage1_job_succeeded(thread_id, ownership_token, source_updated_at, raw_memory, rollout_summary, rollout_slug)
}

fn (state &StateRuntime) mark_stage1_job_succeeded_no_output(thread_id codex_protocol.ThreadId, ownership_token &string) !bool {
	return state.memories.mark_stage1_job_succeeded_no_output(thread_id, ownership_token)
}

fn (state &StateRuntime) mark_stage1_job_failed(thread_id codex_protocol.ThreadId, ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	return state.memories.mark_stage1_job_failed(thread_id, ownership_token, failure_reason, retry_delay_seconds)
}

fn (state &StateRuntime) enqueue_global_consolidation(input_watermark i64) ! {
	state.memories.enqueue_global_consolidation(input_watermark)!
}

fn (state &StateRuntime) try_claim_global_phase2_job(worker_id codex_protocol.ThreadId, lease_seconds i64) !model.Phase2JobClaimOutcome {
	return state.memories.try_claim_global_phase2_job(worker_id, lease_seconds)
}

fn (state &StateRuntime) mark_global_phase2_job_succeeded(ownership_token &string, completed_watermark i64, selected_outputs &[]model.Stage1Output) !bool {
	return state.memories.mark_global_phase2_job_succeeded(ownership_token, completed_watermark, selected_outputs)
}

fn (state &StateRuntime) mark_global_phase2_job_failed(ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	return state.memories.mark_global_phase2_job_failed(ownership_token, failure_reason, retry_delay_seconds)
}

fn (state &StateRuntime) mark_global_phase2_job_failed_if_unowned(ownership_token &string, failure_reason &string, retry_delay_seconds i64) !bool {
	return state.memories.mark_global_phase2_job_failed_if_unowned(ownership_token, failure_reason, retry_delay_seconds)
}

fn stage1_outcome(kind model.Stage1JobClaimOutcomeKind, ownership_token string) model.Stage1JobClaimOutcome {
	return model.Stage1JobClaimOutcome{
		kind:            kind
		ownership_token: ownership_token
	}
}

fn phase2_outcome(kind model.Phase2JobClaimOutcomeKind, ownership_token string, input_watermark i64) model.Phase2JobClaimOutcome {
	return model.Phase2JobClaimOutcome{
		kind:            kind
		ownership_token: ownership_token
		input_watermark: input_watermark
	}
}

fn clone_thread_id(id &codex_protocol.ThreadId) codex_protocol.ThreadId {
	return codex_protocol.ThreadId{
		value: id.value.clone()
	}
}

fn max_i64(a i64, b i64) i64 {
	return if a > b { a } else { b }
}

fn clamp_usize(value usize, low usize, high usize) usize {
	return if value < low {
		low
	} else if value > high { high } else { value }
}

fn usize_to_i64_saturating(value usize) i64 {
	if u64(value) > u64(9_223_372_036_854_775_807) {
		return i64(9_223_372_036_854_775_807)
	}
	return i64(value)
}

fn saturating_add_i64(left i64, right i64) i64 {
	if right > 0 && left > i64(9_223_372_036_854_775_807) - right {
		return i64(9_223_372_036_854_775_807)
	}
	return left + right
}

fn saturating_sub_i64(left i64, right i64) i64 {
	if right > 0 && left < i64(-9_223_372_036_854_775_807) - 1 + right {
		return i64(-9_223_372_036_854_775_807) - 1
	}
	return left - right
}
