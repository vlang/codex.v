module runtime

import codex_protocol
import codex_state.sqlite
import codex_state.model
import json2
import sqlx
import sync

// STUB: SqlitePool is owned by sqlx and state/src/sqlite.rs. This target-specific backing store
// exposes the rows needed by memories.rs while the shared SQLite runtime remains untranslated.
@[heap]
pub struct SqlitePool {
pub mut:
	closed  bool
	outputs map[string]&Stage1OutputRow
	jobs    map[string]&MemoryJobRow
	threads map[string]&ThreadStateRow
	mutex   &sync.Mutex = unsafe { nil }
}

// STUB: close mirrors sqlx::SqlitePool::close.
pub fn (pool &SqlitePool) close() {
	unsafe {
		mut mutable_pool := pool
		mutable_pool.closed = true
	}
}

// STUB: SqliteTransaction mirrors sqlx's transaction executor. The in-memory implementation
// serializes BEGIN..COMMIT with the pool mutex so claim transitions stay conflict-safe.
@[heap]
pub struct SqliteTransaction {
	pool &SqlitePool = unsafe { nil }
mut:
	active bool
}

// STUB: begin mirrors SqlitePool::begin.
pub fn (pool &SqlitePool) begin() !&SqliteTransaction {
	pool.mutex.lock()
	return &SqliteTransaction{
		pool:   pool
		active: true
	}
}

// STUB: begin_with mirrors sqlx's immediate transaction extension used by claim paths.
pub fn (pool &SqlitePool) begin_with(statement string) !&SqliteTransaction {
	if statement != 'BEGIN IMMEDIATE' {
		return error('unsupported transaction statement `${statement}`')
	}
	return pool.begin()
}

// STUB: commit mirrors sqlx::Transaction::commit.
pub fn (mut transaction SqliteTransaction) commit() ! {
	if !transaction.active {
		return error('transaction is already complete')
	}
	transaction.active = false
	transaction.pool.mutex.unlock()
}

// STUB: execute_query makes a transaction satisfy sqlx.Executor.
pub fn (transaction &SqliteTransaction) execute_query(query &sqlx.Query) !sqlx.QueryResult {
	return transaction.pool.execute_query(query)
}

// STUB: fetch_all_query makes a transaction satisfy sqlx.Executor.
pub fn (transaction &SqliteTransaction) fetch_all_query(query &sqlx.Query) ![]sqlx.Row {
	return transaction.pool.fetch_all_query(query)
}

// STUB: fetch_optional_query makes a transaction satisfy sqlx.Executor.
pub fn (transaction &SqliteTransaction) fetch_optional_query(query &sqlx.Query) !sqlx.OptionalRow {
	return transaction.pool.fetch_optional_query(query)
}

// STUB: new_sqlite_pool replaces sqlx pool construction for the isolated runtime translation.
pub fn new_sqlite_pool() &SqlitePool {
	return &SqlitePool{
		outputs: map[string]&Stage1OutputRow{}
		jobs:    map[string]&MemoryJobRow{}
		threads: map[string]&ThreadStateRow{}
		mutex:   &sync.Mutex{}
	}
}

// STUB: query_bind_string decodes an ordered sqlx text bind for the in-memory executor.
fn query_bind_string(query &sqlx.Query, index int) !string {
	if index < 0 || index >= query.binds.len {
		return error('missing SQL bind ${index}')
	}
	value := query.binds[index]
	return match value {
		string { value.clone() }
		else { error('SQL bind ${index} is not text') }
	}
}

// STUB: query_bind_i64 decodes an ordered sqlx integer bind for the in-memory executor.
fn query_bind_i64(query &sqlx.Query, index int) !i64 {
	if index < 0 || index >= query.binds.len {
		return error('missing SQL bind ${index}')
	}
	value := query.binds[index]
	return match value {
		i64 { value }
		else { error('SQL bind ${index} is not an integer') }
	}
}

// STUB: query_bind_optional_i64 decodes a nullable ordered integer bind.
fn query_bind_optional_i64(query &sqlx.Query, index int) !OptionalI64 {
	if index < 0 || index >= query.binds.len {
		return error('missing SQL bind ${index}')
	}
	value := query.binds[index]
	return match value {
		i64 { some_i64(value) }
		sqlx.Null { OptionalI64{} }
		else { error('SQL bind ${index} is not a nullable integer') }
	}
}

// STUB: optional_i64_columns hydrates a nullable SQLite integer in the row test double.
fn optional_i64_columns(value OptionalI64, column string, mut integers map[string]i64, mut nulls map[string]bool) {
	if value.has_value {
		integers[column] = value.value
	} else {
		nulls[column] = true
	}
}

// STUB: optional_string_columns hydrates a nullable SQLite string in the row test double.
fn optional_string_columns(value &model.OptionalString, column string, mut strings map[string]string, mut nulls map[string]bool) {
	if value.has_value {
		strings[column] = value.value.clone()
	} else {
		nulls[column] = true
	}
}

// STUB: output_sql_row projects an in-memory stage1_outputs record as a SqliteRow.
fn output_sql_row(output &Stage1OutputRow) sqlx.Row {
	mut strings := {
		'thread_id':       output.thread_id.clone()
		'raw_memory':      output.raw_memory.clone()
		'rollout_summary': output.rollout_summary.clone()
	}
	mut integers := {
		'source_updated_at':   output.source_updated_at
		'generated_at':        output.generated_at
		'selected_for_phase2': i64(if output.selected_for_phase2 { 1 } else { 0 })
		'usage_count':         output.usage_count
	}
	mut nullable_strings := map[string]bool{}
	mut nullable_integers := map[string]bool{}
	optional_string_columns(&output.rollout_slug, 'rollout_slug', mut strings, mut nullable_strings)
	optional_i64_columns(output.selected_for_phase2_source_updated_at, 'selected_for_phase2_source_updated_at', mut integers, mut nullable_integers)
	optional_i64_columns(output.last_usage, 'last_usage', mut integers, mut nullable_integers)
	return sqlx.Row{
		strings:           strings
		integers:          integers
		nullable_strings:  nullable_strings
		nullable_integers: nullable_integers
	}
}

// STUB: job_sql_row projects an in-memory jobs record as a SqliteRow.
fn job_sql_row(job &MemoryJobRow) sqlx.Row {
	mut strings := {
		'kind':    job.kind.clone()
		'job_key': job.job_key.clone()
		'status':  job.status.clone()
	}
	mut integers := {
		'retry_remaining': job.retry_remaining
	}
	mut nullable_strings := map[string]bool{}
	mut nullable_integers := map[string]bool{}
	optional_string_columns(&job.worker_id, 'worker_id', mut strings, mut nullable_strings)
	optional_string_columns(&job.ownership_token, 'ownership_token', mut strings, mut nullable_strings)
	optional_string_columns(&job.last_error, 'last_error', mut strings, mut nullable_strings)
	optional_i64_columns(job.started_at, 'started_at', mut integers, mut nullable_integers)
	optional_i64_columns(job.finished_at, 'finished_at', mut integers, mut nullable_integers)
	optional_i64_columns(job.lease_until, 'lease_until', mut integers, mut nullable_integers)
	optional_i64_columns(job.retry_at, 'retry_at', mut integers, mut nullable_integers)
	optional_i64_columns(job.input_watermark, 'input_watermark', mut integers, mut nullable_integers)
	optional_i64_columns(job.last_success_watermark, 'last_success_watermark', mut integers, mut nullable_integers)
	return sqlx.Row{
		strings:           strings
		integers:          integers
		nullable_strings:  nullable_strings
		nullable_integers: nullable_integers
	}
}

// STUB: thread_sql_row projects an in-memory threads record as a SqliteRow.
fn thread_sql_row(state_thread &ThreadStateRow) sqlx.Row {
	mut strings := {
		'id':                 state_thread.metadata.id.value.clone()
		'rollout_path':       state_thread.metadata.rollout_path.clone()
		'source':             state_thread.metadata.source.clone()
		'history_mode':       state_thread.metadata.history_mode.as_str()
		'model_provider':     state_thread.metadata.model_provider.clone()
		'cwd':                state_thread.metadata.cwd.clone()
		'cli_version':        state_thread.metadata.cli_version.clone()
		'title':              state_thread.metadata.title.clone()
		'preview':            if state_thread.metadata.preview.has_value {
			state_thread.metadata.preview.value.clone()
		} else {
			''
		}
		'sandbox_policy':     state_thread.metadata.sandbox_policy.clone()
		'approval_mode':      state_thread.metadata.approval_mode.clone()
		'first_user_message': if state_thread.metadata.first_user_message.has_value {
			state_thread.metadata.first_user_message.value.clone()
		} else {
			''
		}
		'memory_mode':        state_thread.memory_mode.clone()
	}
	mut integers := {
		'created_at':  state_thread.metadata.created_at.unix_milli()
		'updated_at':  state_thread.updated_at_ms
		'recency_at':  state_thread.metadata.recency_at.unix_milli()
		'tokens_used': state_thread.metadata.tokens_used
	}
	mut nullable_strings := map[string]bool{}
	mut nullable_integers := map[string]bool{}
	optional_string_columns(&state_thread.metadata.originator, 'originator', mut strings, mut nullable_strings)
	if state_thread.metadata.thread_source.has_value {
		strings['thread_source'] = state_thread.metadata.thread_source.value.as_str()
	} else {
		nullable_strings['thread_source'] = true
	}
	optional_string_columns(&state_thread.metadata.agent_nickname, 'agent_nickname', mut strings, mut nullable_strings)
	optional_string_columns(&state_thread.metadata.agent_role, 'agent_role', mut strings, mut nullable_strings)
	optional_string_columns(&state_thread.metadata.agent_path, 'agent_path', mut strings, mut nullable_strings)
	optional_string_columns(&state_thread.metadata.model, 'model', mut strings, mut nullable_strings)
	if state_thread.metadata.reasoning_effort.has_value {
		strings['reasoning_effort'] = if state_thread.metadata.reasoning_effort.value == .custom {
			state_thread.metadata.reasoning_effort.custom.clone()
		} else {
			state_thread.metadata.reasoning_effort.value.str()
		}
	} else {
		nullable_strings['reasoning_effort'] = true
	}
	optional_string_columns(&state_thread.metadata.name, 'name', mut strings, mut nullable_strings)
	if state_thread.metadata.archived_at.has_value {
		integers['archived_at'] = state_thread.metadata.archived_at.value.unix()
	} else {
		nullable_integers['archived_at'] = true
	}
	if state_thread.metadata.section.has_value {
		section := state_thread.metadata.section.value
		strings['section'] = section.id.clone()
		strings['section_name'] = section.name.clone()
		if section.appearance.has_value {
			mut appearance := map[string]string{}
			if section.appearance.value.icon.has_value {
				appearance['icon'] = section.appearance.value.icon.value.clone()
			}
			if section.appearance.value.color.has_value {
				appearance['color'] = section.appearance.value.color.value.clone()
			}
			strings['section_appearance'] = json2.encode(appearance, escape_unicode: true)
		} else {
			nullable_strings['section_appearance'] = true
		}
	} else {
		nullable_strings['section'] = true
		nullable_strings['section_name'] = true
		nullable_strings['section_appearance'] = true
	}
	if state_thread.metadata.section_position.has_value {
		integers['section_position'] = state_thread.metadata.section_position.value
	} else {
		nullable_integers['section_position'] = true
	}
	if state_thread.metadata.section_entered_at.has_value {
		integers['section_entered_at_ms'] = state_thread.metadata.section_entered_at.value.unix_milli()
	} else {
		nullable_integers['section_entered_at_ms'] = true
	}
	optional_string_columns(&state_thread.metadata.project_id, 'project_id', mut strings, mut nullable_strings)
	if state_thread.metadata.daybreak_enabled.has_value {
		integers['daybreak_enabled'] = if state_thread.metadata.daybreak_enabled.value {
			1
		} else {
			0
		}
	} else {
		nullable_integers['daybreak_enabled'] = true
	}
	optional_string_columns(&state_thread.metadata.git_sha, 'git_sha', mut strings, mut nullable_strings)
	optional_string_columns(&state_thread.metadata.git_branch, 'git_branch', mut strings, mut nullable_strings)
	if state_thread.metadata.git_origin_url.has_value {
		strings['git_origin_url'] = state_thread.metadata.git_origin_url.value.value.clone()
	} else {
		nullable_strings['git_origin_url'] = true
	}
	return sqlx.Row{
		strings:           strings
		integers:          integers
		nullable_strings:  nullable_strings
		nullable_integers: nullable_integers
	}
}

// STUB: query_bind_optional_string decodes a nullable ordered text bind.
fn query_bind_optional_string(query &sqlx.Query, index int) !model.OptionalString {
	if index < 0 || index >= query.binds.len {
		return error('missing SQL bind ${index}')
	}
	value := query.binds[index]
	return match value {
		string { model.some_string(value.clone()) }
		sqlx.Null { model.OptionalString{} }
		else { error('SQL bind ${index} is not nullable text') }
	}
}

// STUB: execute_query is the in-memory sqlx Executor implementation used by the translated tests.
// Its dispatch remains behind the source-shaped SQL API; memories.v never observes backing maps.
pub fn (pool &SqlitePool) execute_query(query &sqlx.Query) !sqlx.QueryResult {
	sql_text := query.statement.trim_space()
	mut affected := u64(0)
	unsafe {
		mut db := pool
		if sql_text == 'UPDATE jobs SET finished_at = ? WHERE kind = ? AND job_key = ?' {
			finished_at := query_bind_i64(query, 0)!
			kind := query_bind_string(query, 1)!
			job_key := query_bind_string(query, 2)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				job.finished_at = some_i64(finished_at)
				affected = 1
			}
		} else if sql_text == "UPDATE jobs SET lease_until = 0 WHERE kind = 'memory_stage1' AND job_key = ?" {
			job_key := query_bind_string(query, 0)!
			key := 'memory_stage1:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				job.lease_until = some_i64(0)
				affected = 1
			}
		} else if sql_text.starts_with('UPDATE jobs SET lease_until = ') {
			lease := query_bind_i64(query, 0)!
			kind := query_bind_string(query, 1)!
			job_key := query_bind_string(query, 2)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				job.lease_until = some_i64(lease)
				affected = 1
			}
		} else if sql_text == 'UPDATE jobs SET ownership_token = NULL WHERE kind = ? AND job_key = ?' {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				job.ownership_token = model.OptionalString{}
				affected = 1
			}
		} else if sql_text == 'UPDATE stage1_outputs SET usage_count = ?, last_usage = ? WHERE thread_id = ?' {
			usage := query_bind_optional_i64(query, 0)!
			last_usage := query_bind_optional_i64(query, 1)!
			id := query_bind_string(query, 2)!
			if id in db.outputs {
				mut output := db.outputs[id]
				output.usage_count = if usage.has_value { usage.value } else { 0 }
				output.last_usage = last_usage
				affected = 1
			}
		} else if sql_text == 'UPDATE stage1_outputs SET generated_at = ? WHERE thread_id = ?' {
			generated := query_bind_i64(query, 0)!
			id := query_bind_string(query, 1)!
			if id in db.outputs {
				mut output := db.outputs[id]
				output.generated_at = generated
				affected = 1
			}
		} else if sql_text == 'UPDATE stage1_outputs SET selected_for_phase2 = 1, selected_for_phase2_source_updated_at = source_updated_at WHERE thread_id = ?' {
			id := query_bind_string(query, 0)!
			if id in db.outputs {
				mut output := db.outputs[id]
				output.selected_for_phase2 = true
				output.selected_for_phase2_source_updated_at = some_i64(output.source_updated_at)
				affected = 1
			}
		} else if sql_text == "UPDATE threads SET memory_mode = 'disabled' WHERE id = ?" {
			id := query_bind_string(query, 0)!
			if id in db.threads {
				mut state_thread := db.threads[id]
				state_thread.memory_mode = 'disabled'
				affected = 1
			}
		} else if sql_text.starts_with('UPDATE stage1_outputs\nSET\n    usage_count = COALESCE') {
			now := query_bind_i64(query, 0)!
			id := query_bind_string(query, 1)!
			if id in db.outputs {
				mut output := db.outputs[id]
				output.usage_count++
				output.last_usage = some_i64(now)
				affected = 1
			}
		} else if sql_text.starts_with('DELETE FROM stage1_outputs\nWHERE thread_id IN') {
			cutoff := query_bind_i64(query, 0)!
			limit := query_bind_i64(query, 1)!
			mut candidates := []&Stage1OutputRow{}
			for _, output in db.outputs {
				recency := if output.last_usage.has_value {
					output.last_usage.value
				} else {
					output.source_updated_at
				}
				if !output.selected_for_phase2 && recency < cutoff {
					candidates << output
				}
			}
			candidates.sort_with_compare(fn (a &&Stage1OutputRow, b &&Stage1OutputRow) int {
				left := *a
				right := *b
				left_recency := if left.last_usage.has_value {
					left.last_usage.value
				} else {
					left.source_updated_at
				}
				right_recency := if right.last_usage.has_value {
					right.last_usage.value
				} else {
					right.source_updated_at
				}
				if left_recency != right_recency {
					return if left_recency < right_recency { -1 } else { 1 }
				}
				if left.source_updated_at != right.source_updated_at {
					return if left.source_updated_at < right.source_updated_at { -1 } else { 1 }
				}
				return if left.thread_id < right.thread_id {
					-1
				} else if left.thread_id > right.thread_id { 1 } else { 0 }
			})
			count := if limit < i64(candidates.len) { int(limit) } else { candidates.len }
			for index in 0 .. count {
				db.outputs.delete(candidates[index].thread_id)
			}
			affected = u64(count)
		} else if sql_text == 'DELETE FROM stage1_outputs' {
			affected = u64(db.outputs.len)
			db.outputs.clear()
		} else if sql_text.starts_with('DELETE FROM stage1_outputs\nWHERE thread_id = ?') {
			id := query_bind_string(query, 0)!
			if id in db.outputs {
				db.outputs.delete(id)
				affected = 1
			}
		} else if sql_text.starts_with('DELETE FROM jobs\nWHERE kind = ? AND job_key = ?') {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				db.jobs.delete(key)
				affected = 1
			}
		} else if sql_text.starts_with('DELETE FROM jobs\nWHERE kind = ? OR kind = ?') {
			first := query_bind_string(query, 0)!
			second := query_bind_string(query, 1)!
			mut keys := []string{}
			for key, job in db.jobs {
				if job.kind == first || job.kind == second {
					keys << key.clone()
				}
			}
			for key in keys {
				db.jobs.delete(key)
				affected++
			}
		} else if sql_text.starts_with("UPDATE threads\nSET memory_mode = 'polluted'")
			|| sql_text == "UPDATE threads SET memory_mode = 'polluted' WHERE id = ?" {
			id := query_bind_string(query, 0)!
			if id in db.threads && db.threads[id].memory_mode != 'polluted' {
				mut state_thread := db.threads[id]
				state_thread.memory_mode = 'polluted'
				affected = 1
			}
		} else if sql_text.starts_with('INSERT INTO jobs') && sql_text.contains("SELECT ?, ?, 'running'") {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			worker := query_bind_string(query, 2)!
			token := query_bind_string(query, 3)!
			now := query_bind_i64(query, 4)!
			lease := query_bind_i64(query, 5)!
			retry_default := query_bind_i64(query, 6)!
			watermark := query_bind_i64(query, 7)!
			max_running := query_bind_i64(query, 10)!
			key := '${kind}:${job_key}'
			mut running := i64(0)
			for other_key, candidate in db.jobs {
				if candidate.kind == kind && candidate.status == 'running' && candidate.lease_until.has_value
					&& candidate.lease_until.value > now && other_key != key {
					running++
				}
			}
			if running < max_running {
				if key in db.jobs {
					mut job := db.jobs[key]
					advanced := !job.input_watermark.has_value || watermark > job.input_watermark.value
					claimable := (job.status != 'running' || !job.lease_until.has_value || job.lease_until.value <= now)
						&& (!job.retry_at.has_value || job.retry_at.value <= now || advanced)
						&& (job.retry_remaining > 0 || advanced)
					if claimable {
						job.status = 'running'
						job.worker_id = model.some_string(worker)
						job.ownership_token = model.some_string(token)
						job.started_at = some_i64(now)
						job.finished_at = OptionalI64{}
						job.lease_until = some_i64(lease)
						job.retry_at = OptionalI64{}
						if advanced {
							job.retry_remaining = retry_default
						}
						job.last_error = model.OptionalString{}
						job.input_watermark = some_i64(watermark)
						affected = 1
					}
				} else {
					db.jobs[key] = &MemoryJobRow{
						kind:            kind
						job_key:         job_key
						status:          'running'
						worker_id:       model.some_string(worker)
						ownership_token: model.some_string(token)
						started_at:      some_i64(now)
						lease_until:     some_i64(lease)
						retry_remaining: retry_default
						input_watermark: some_i64(watermark)
					}
					affected = 1
				}
			}
		} else if sql_text.starts_with("UPDATE jobs\nSET\n    status = 'done'") && sql_text.contains('last_success_watermark = input_watermark') {
			now := query_bind_i64(query, 0)!
			kind := query_bind_string(query, 1)!
			job_key := query_bind_string(query, 2)!
			token := query_bind_string(query, 3)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				if job.status == 'running' && job.ownership_token.has_value && job.ownership_token.value == token {
					job.status = 'done'
					job.finished_at = some_i64(now)
					job.lease_until = OptionalI64{}
					job.last_error = model.OptionalString{}
					job.last_success_watermark = job.input_watermark
					affected = 1
				}
			}
		} else if sql_text.starts_with('INSERT INTO stage1_outputs') && !sql_text.contains('rollout_slug') {
			id := query_bind_string(query, 0)!
			db.outputs[id] = &Stage1OutputRow{
				thread_id:         id
				source_updated_at: query_bind_i64(query, 1)!
				raw_memory:        query_bind_string(query, 2)!
				rollout_summary:   query_bind_string(query, 3)!
				generated_at:      query_bind_i64(query, 4)!
			}
			affected = 1
		} else if sql_text.starts_with('INSERT INTO stage1_outputs') {
			id := query_bind_string(query, 0)!
			watermark := query_bind_i64(query, 1)!
			raw := query_bind_string(query, 2)!
			summary := query_bind_string(query, 3)!
			slug := query_bind_optional_string(query, 4)!
			generated := query_bind_i64(query, 5)!
			if id !in db.outputs || watermark >= db.outputs[id].source_updated_at {
				mut selected := false
				mut selected_at := OptionalI64{}
				mut usage := i64(0)
				mut last_usage := OptionalI64{}
				if id in db.outputs {
					existing := db.outputs[id]
					selected = existing.selected_for_phase2
					selected_at = existing.selected_for_phase2_source_updated_at
					usage = existing.usage_count
					last_usage = existing.last_usage
				}
				db.outputs[id] = &Stage1OutputRow{
					thread_id:                             id
					source_updated_at:                     watermark
					raw_memory:                            raw
					rollout_summary:                       summary
					rollout_slug:                          slug
					generated_at:                          generated
					selected_for_phase2:                   selected
					selected_for_phase2_source_updated_at: selected_at
					usage_count:                           usage
					last_usage:                            last_usage
				}
				affected = 1
			}
		} else if sql_text.starts_with("UPDATE jobs\nSET\n    status = 'error'") {
			now := query_bind_i64(query, 0)!
			retry_at := query_bind_i64(query, 1)!
			reason := query_bind_string(query, 2)!
			kind := query_bind_string(query, 3)!
			job_key := query_bind_string(query, 4)!
			token := query_bind_string(query, 5)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				owned := job.ownership_token.has_value && job.ownership_token.value == token
				allow_unowned := sql_text.contains('OR ownership_token IS NULL')
				if job.status == 'running' && (owned || (allow_unowned && !job.ownership_token.has_value)) {
					job.status = 'error'
					job.finished_at = some_i64(now)
					job.lease_until = OptionalI64{}
					job.retry_at = some_i64(retry_at)
					job.retry_remaining = if sql_text.contains('max(retry_remaining - 1, 0)') {
						if job.retry_remaining > 0 { job.retry_remaining - 1 } else { 0 }
					} else {
						job.retry_remaining - 1
					}
					job.last_error = model.some_string(reason)
					affected = 1
				}
			}
		} else if sql_text.starts_with('INSERT INTO jobs') && sql_text.contains("VALUES (?, ?, 'running'") {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			is_stage1_seed := query.binds.len > 7
			key := '${kind}:${job_key}'
			if key !in db.jobs {
				db.jobs[key] = &MemoryJobRow{
					kind:                   kind
					job_key:                job_key
					status:                 'running'
					worker_id:              model.some_string(query_bind_string(query, 2)!)
					ownership_token:        model.some_string(query_bind_string(query, 3)!)
					started_at:             some_i64(query_bind_i64(query, 4)!)
					lease_until:            some_i64(query_bind_i64(query, 5)!)
					retry_remaining:        query_bind_i64(query, 6)!
					input_watermark:        if is_stage1_seed {
						some_i64(query_bind_i64(query, 7)!)
					} else {
						some_i64(0)
					}
					last_success_watermark: if is_stage1_seed {
						OptionalI64{}
					} else {
						some_i64(0)
					}
				}
				affected = 1
			}
		} else if sql_text.starts_with("UPDATE jobs\nSET\n    status = 'running'") {
			worker := query_bind_string(query, 0)!
			token := query_bind_string(query, 1)!
			now := query_bind_i64(query, 2)!
			lease := query_bind_i64(query, 3)!
			kind := query_bind_string(query, 4)!
			job_key := query_bind_string(query, 5)!
			cooldown := query_bind_i64(query, 8)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				if (job.status != 'running' || !job.lease_until.has_value || job.lease_until.value <= now)
					&& (!job.retry_at.has_value || job.retry_at.value <= now)
					&& (job.last_error.has_value || !job.finished_at.has_value || job.finished_at.value <= cooldown) {
					job.status = 'running'
					job.worker_id = model.some_string(worker)
					job.ownership_token = model.some_string(token)
					job.started_at = some_i64(now)
					job.finished_at = OptionalI64{}
					job.lease_until = some_i64(lease)
					job.retry_at = OptionalI64{}
					job.last_error = model.OptionalString{}
					affected = 1
				}
			}
		} else if sql_text.starts_with('UPDATE jobs\nSET lease_until = ?') {
			lease := query_bind_i64(query, 0)!
			kind := query_bind_string(query, 1)!
			job_key := query_bind_string(query, 2)!
			token := query_bind_string(query, 3)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				if job.status == 'running' && job.ownership_token.has_value && job.ownership_token.value == token {
					job.lease_until = some_i64(lease)
					affected = 1
				}
			}
		} else if sql_text.starts_with('UPDATE stage1_outputs\nSET\n    selected_for_phase2 = 0') {
			for _, row in db.outputs {
				if row.selected_for_phase2 || row.selected_for_phase2_source_updated_at.has_value {
					mut output := row
					output.selected_for_phase2 = false
					output.selected_for_phase2_source_updated_at = OptionalI64{}
					affected++
				}
			}
		} else if sql_text.starts_with('UPDATE stage1_outputs\nSET\n    selected_for_phase2 = 1') {
			snapshot := query_bind_i64(query, 0)!
			id := query_bind_string(query, 1)!
			watermark := query_bind_i64(query, 2)!
			if id in db.outputs && db.outputs[id].source_updated_at == watermark {
				mut output := db.outputs[id]
				output.selected_for_phase2 = true
				output.selected_for_phase2_source_updated_at = some_i64(snapshot)
				affected = 1
			}
		} else if sql_text.starts_with("UPDATE jobs\nSET\n    status = 'done'") && sql_text.contains('max(COALESCE') {
			now := query_bind_i64(query, 0)!
			completed := query_bind_i64(query, 1)!
			kind := query_bind_string(query, 2)!
			job_key := query_bind_string(query, 3)!
			token := query_bind_string(query, 4)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				mut job := db.jobs[key]
				if job.status == 'running' && job.ownership_token.has_value && job.ownership_token.value == token {
					job.status = 'done'
					job.finished_at = some_i64(now)
					job.lease_until = OptionalI64{}
					job.last_error = model.OptionalString{}
					existing := if job.last_success_watermark.has_value {
						job.last_success_watermark.value
					} else {
						0
					}
					job.last_success_watermark = some_i64(if completed > existing {
						completed
					} else {
						existing
					})
					affected = 1
				}
			}
		} else if sql_text.starts_with('INSERT INTO jobs') && sql_text.contains("VALUES (?, ?, 'pending'") {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			retry_default := query_bind_i64(query, 2)!
			watermark := query_bind_i64(query, 3)!
			key := '${kind}:${job_key}'
			if key !in db.jobs {
				db.jobs[key] = &MemoryJobRow{
					kind:                   kind
					job_key:                job_key
					status:                 'pending'
					retry_remaining:        retry_default
					input_watermark:        some_i64(watermark)
					last_success_watermark: some_i64(0)
				}
			} else {
				mut job := db.jobs[key]
				if job.status != 'running' {
					job.status = 'pending'
					job.retry_at = OptionalI64{}
				}
				if job.retry_remaining < retry_default {
					job.retry_remaining = retry_default
				}
				existing := if job.input_watermark.has_value {
					job.input_watermark.value
				} else {
					0
				}
				job.input_watermark = some_i64(if watermark > existing {
					watermark
				} else {
					existing + 1
				})
			}
			affected = 1
		} else {
			return error('unsupported SQL execute: ${sql_text}')
		}
	}
	return sqlx.QueryResult{ affected: affected }
}

// STUB: fetch_all_query is the in-memory sqlx row hydration used by translated runtime tests.
pub fn (pool &SqlitePool) fetch_all_query(query &sqlx.Query) ![]sqlx.Row {
	sql_text := query.statement.trim_space()
	mut rows := []sqlx.Row{}
	unsafe {
		db := pool
		if sql_text == 'SELECT thread_id FROM stage1_outputs ORDER BY thread_id' {
			mut ids := db.outputs.keys()
			ids.sort()
			for id in ids {
				rows << sqlx.Row{
					strings: {
						'thread_id': id
					}
				}
			}
		} else if sql_text.starts_with('SELECT\n    so.thread_id,\n    so.source_updated_at,\n    so.raw_memory')
			&& !sql_text.contains('WHERE so.thread_id = ?') {
			mut outputs := []&Stage1OutputRow{}
			for _, output in db.outputs {
				if output.raw_memory.trim_space().len > 0 || output.rollout_summary.trim_space().len > 0 {
					outputs << output
				}
			}
			outputs.sort_with_compare(fn (a &&Stage1OutputRow, b &&Stage1OutputRow) int {
				left := *a
				right := *b
				if left.source_updated_at != right.source_updated_at {
					return if left.source_updated_at > right.source_updated_at { -1 } else { 1 }
				}
				return if left.thread_id > right.thread_id {
					-1
				} else if left.thread_id < right.thread_id { 1 } else { 0 }
			})
			for output in outputs {
				rows << output_sql_row(output)
			}
		} else if sql_text.starts_with('SELECT\n    so.thread_id,\n    so.source_updated_at\nFROM stage1_outputs') {
			cutoff := query_bind_i64(query, 0)!
			limit := query_bind_i64(query, 2)!
			offset := query_bind_i64(query, 3)!
			mut outputs := []&Stage1OutputRow{}
			for _, output in db.outputs {
				non_empty := output.raw_memory.trim_space().len > 0 || output.rollout_summary.trim_space().len > 0
				recent := if output.last_usage.has_value {
					output.last_usage.value >= cutoff
				} else {
					output.source_updated_at >= cutoff
				}
				if non_empty && recent { outputs << output }
			}
			outputs.sort_with_compare(fn (a &&Stage1OutputRow, b &&Stage1OutputRow) int {
				left := *a
				right := *b
				if left.usage_count != right.usage_count {
					return if left.usage_count > right.usage_count { -1 } else { 1 }
				}
				left_recency := if left.last_usage.has_value {
					left.last_usage.value
				} else {
					left.source_updated_at
				}
				right_recency := if right.last_usage.has_value {
					right.last_usage.value
				} else {
					right.source_updated_at
				}
				if left_recency != right_recency {
					return if left_recency > right_recency { -1 } else { 1 }
				}
				if left.source_updated_at != right.source_updated_at {
					return if left.source_updated_at > right.source_updated_at { -1 } else { 1 }
				}
				return if left.thread_id > right.thread_id {
					-1
				} else if left.thread_id < right.thread_id { 1 } else { 0 }
			})
			start := if offset < i64(outputs.len) { int(offset) } else { outputs.len }
			end := if start + int(limit) < outputs.len { start + int(limit) } else { outputs.len }
			for index in start .. end {
				rows << output_sql_row(outputs[index])
			}
		} else if sql_text.starts_with('SELECT\n    threads.id') && sql_text.contains("threads.memory_mode = 'enabled'")
			&& sql_text.contains('threads.id !=') {
			if query.binds.len < 4 {
				return error('startup thread query is missing terminal binds')
			}
			allowed_count := query.binds.len - 4
			mut allowed := []string{}
			for index in 0 .. allowed_count {
				allowed << query_bind_string(query, index)!
			}
			current_id := query_bind_string(query, allowed_count)!
			max_age_cutoff := query_bind_i64(query, allowed_count + 1)!
			idle_cutoff := query_bind_i64(query, allowed_count + 2)!
			limit := query_bind_i64(query, allowed_count + 3)!
			mut threads := []&ThreadStateRow{}
			for _, state_thread in db.threads {
				if !state_thread.metadata.archived_at.has_value && state_thread.memory_mode == 'enabled'
					&& state_thread.metadata.id.value != current_id
					&& state_thread.updated_at_ms >= max_age_cutoff && state_thread.updated_at_ms <= idle_cutoff
					&& (allowed.len == 0 || state_thread.metadata.source in allowed) {
					threads << state_thread
				}
			}
			threads.sort(a.updated_at_ms > b.updated_at_ms)
			count := if limit < i64(threads.len) { int(limit) } else { threads.len }
			for index in 0 .. count {
				rows << thread_sql_row(threads[index])
			}
		} else if sql_text.starts_with('SELECT\n    threads.id') && sql_text.contains('WHERE threads.id = ?') {
			id := query_bind_string(query, 0)!
			if id in db.threads && db.threads[id].memory_mode == 'enabled' {
				rows << thread_sql_row(db.threads[id])
			}
		} else {
			optional := pool.fetch_optional_query_without_all(query)!
			if optional.has_value { rows << optional.get()! }
		}
	}
	return rows
}

// STUB: fetch_optional_query_without_all implements scalar/optional fetches without recursion.
fn (pool &SqlitePool) fetch_optional_query_without_all(query &sqlx.Query) !sqlx.OptionalRow {
	sql_text := query.statement.trim_space()
	unsafe {
		db := pool
		if sql_text == 'SELECT COUNT(*) FROM stage1_outputs' {
			return sqlx.OptionalRow{
				has_value: true
				row:       sqlx.Row{
					integers: {
						'count': i64(db.outputs.len)
					}
				}
			}
		}
		if sql_text.starts_with('SELECT COUNT(*)') && sql_text.contains('FROM jobs') {
			mut count := i64(0)
			if sql_text.contains("kind = 'memory_stage1'") {
				now := if query.binds.len > 0 { query_bind_i64(query, 0)! } else { i64(0) }
				for _, job in db.jobs {
					if job.kind == 'memory_stage1'
						&& (!sql_text.contains("status = 'running'") || (job.status == 'running'
							&& job.lease_until.has_value && job.lease_until.value > now)) {
						count++
					}
				}
			} else if query.binds.len >= 2 {
				first := query_bind_string(query, 0)!
				second := query_bind_string(query, 1)!
				for _, job in db.jobs {
					if job.kind == first || job.kind == second { count++ }
				}
			} else if query.binds.len == 1 {
				kind := query_bind_string(query, 0)!
				for _, job in db.jobs {
					if job.kind == kind { count++ }
				}
			} else {
				count = i64(db.jobs.len)
			}
			return sqlx.OptionalRow{
				has_value: true
				row:       sqlx.Row{
					integers: {
						'count': count
					}
				}
			}
		}
		if sql_text.starts_with('SELECT COUNT(*) AS count FROM stage1_outputs WHERE thread_id = ?') {
			id := query_bind_string(query, 0)!
			return sqlx.OptionalRow{
				has_value: true
				row:       sqlx.Row{
					integers: {
						'count': i64(if id in db.outputs { 1 } else { 0 })
					}
				}
			}
		}
		if sql_text == 'SELECT memory_mode FROM threads WHERE id = ?' {
			id := query_bind_string(query, 0)!
			if id in db.threads {
				return sqlx.OptionalRow{ has_value: true, row: thread_sql_row(db.threads[id]) }
			}
			return sqlx.OptionalRow{}
		}
		if sql_text.starts_with('SELECT source_updated_at\nFROM stage1_outputs')
			|| sql_text.starts_with('SELECT selected_for_phase2\nFROM stage1_outputs')
			|| (sql_text.contains('FROM stage1_outputs') && sql_text.contains('WHERE thread_id = ?')) {
			id := query_bind_string(query, 0)!
			if id in db.outputs {
				return sqlx.OptionalRow{ has_value: true, row: output_sql_row(db.outputs[id]) }
			}
			return sqlx.OptionalRow{}
		}
		if sql_text.starts_with('SELECT\n    so.thread_id') && sql_text.contains('WHERE so.thread_id = ?') {
			id := query_bind_string(query, 0)!
			watermark := query_bind_i64(query, 1)!
			if id in db.outputs && db.outputs[id].source_updated_at == watermark {
				return sqlx.OptionalRow{ has_value: true, row: output_sql_row(db.outputs[id]) }
			}
			return sqlx.OptionalRow{}
		}
		if sql_text.starts_with('SELECT last_success_watermark\nFROM jobs')
			|| sql_text.starts_with('SELECT status, lease_until, retry_at, retry_remaining\nFROM jobs')
			|| sql_text.starts_with('SELECT input_watermark\nFROM jobs')
			|| sql_text.starts_with('SELECT status, lease_until, retry_at, input_watermark, finished_at, last_error\nFROM jobs')
			|| (sql_text.contains('FROM jobs') && sql_text.contains('WHERE kind = ? AND job_key = ?')) {
			kind := query_bind_string(query, 0)!
			job_key := query_bind_string(query, 1)!
			key := '${kind}:${job_key}'
			if key in db.jobs {
				if sql_text.starts_with('SELECT input_watermark') && query.binds.len > 2 {
					token := query_bind_string(query, 2)!
					if !db.jobs[key].ownership_token.has_value || db.jobs[key].ownership_token.value != token {
						return sqlx.OptionalRow{}
					}
				}
				return sqlx.OptionalRow{ has_value: true, row: job_sql_row(db.jobs[key]) }
			}
			return sqlx.OptionalRow{}
		}
	}
	return error('unsupported SQL fetch: ${sql_text}')
}

// STUB: fetch_optional_query completes the sqlx Executor implementation.
pub fn (pool &SqlitePool) fetch_optional_query(query &sqlx.Query) !sqlx.OptionalRow {
	sql_text := query.statement.trim_space()
	if sql_text.starts_with('SELECT\n    threads.id') || (sql_text.starts_with('SELECT\n    so.thread_id') && sql_text.contains('WHERE so.thread_id = ?')) {
		rows := pool.fetch_all_query(query)!
		if rows.len == 0 {
			return sqlx.OptionalRow{}
		}
		return sqlx.OptionalRow{ has_value: true, row: rows[0] }
	}
	return pool.fetch_optional_query_without_all(query)
}

// STUB: Stage1OutputRow mirrors the memories migration's stage1_outputs table columns observed by
// runtime/memories.rs.
pub struct Stage1OutputRow {
pub mut:
	thread_id                             string
	source_updated_at                     i64
	raw_memory                            string
	rollout_summary                       string
	rollout_slug                          model.OptionalString
	generated_at                          i64
	selected_for_phase2                   bool
	selected_for_phase2_source_updated_at OptionalI64
	usage_count                           i64
	last_usage                            OptionalI64
}

// STUB: MemoryJobRow mirrors the memories migration's jobs table columns observed by
// runtime/memories.rs.
pub struct MemoryJobRow {
pub mut:
	kind                   string
	job_key                string
	status                 string
	worker_id              model.OptionalString
	ownership_token        model.OptionalString
	started_at             OptionalI64
	finished_at            OptionalI64
	lease_until            OptionalI64
	retry_at               OptionalI64
	retry_remaining        i64
	last_error             model.OptionalString
	input_watermark        OptionalI64
	last_success_watermark OptionalI64
}

// STUB: OptionalI64 represents nullable SQLite integer columns and is allocation-free.
pub struct OptionalI64 {
pub:
	has_value bool
	value     i64
}

// STUB: some_i64 constructs a nullable SQLite integer value.
pub fn some_i64(value i64) OptionalI64 {
	return OptionalI64{
		has_value: true
		value:     value
	}
}

// STUB: ThreadStateRow represents the state DB thread row and memory_mode column used by this
// translation.
pub struct ThreadStateRow {
pub mut:
	metadata      model.ThreadMetadata
	memory_mode   string = 'enabled'
	updated_at_ms i64
}

// STUB: StateRuntime is owned by state/src/runtime.rs; this projection exposes only members and
// integration calls directly referenced by runtime/memories.rs and its tests.
@[heap]
pub struct StateRuntime {
pub:
	sqlite           sqlite.SqliteConfig
	default_provider string
	memories         &MemoryStore = unsafe { nil }
	pool             &SqlitePool  = unsafe { nil }
}

// STUB: init mirrors StateRuntime::init; the executable test backend opens its isolated in-memory
// pools behind the eventual public initialization API.
pub fn StateRuntime.init(config sqlite.SqliteConfig, default_provider string) !&StateRuntime {
	return new_in_memory_state_runtime(config, default_provider)
}

// STUB: new_in_memory_state_runtime implements the untranslated SQLite open/migrate behavior for
// tests and remains private behind StateRuntime.init.
fn new_in_memory_state_runtime(config sqlite.SqliteConfig, default_provider string) &StateRuntime {
	memory_database_pool := new_sqlite_pool()
	state_pool := new_sqlite_pool()
	store := &MemoryStore{
		pool:       memory_database_pool
		state_pool: state_pool
	}
	return &StateRuntime{
		sqlite:           config
		default_provider: default_provider
		memories:         store
		pool:             state_pool
	}
}

// STUB: upsert_thread is owned by state/src/runtime/threads.rs.
pub fn (state &StateRuntime) upsert_thread(item &model.ThreadMetadata) ! {
	id := item.id.value.clone()
	mut memory_mode := 'enabled'
	unsafe {
		if id in state.pool.threads {
			memory_mode = state.pool.threads[id].memory_mode.clone()
		}
	}
	row := &ThreadStateRow{
		metadata:      model.clone_thread_metadata(item)
		memory_mode:   memory_mode
		updated_at_ms: item.updated_at.unix_milli()
	}
	unsafe {
		mut pool := state.pool
		pool.threads[id] = row
	}
}

// STUB: set_thread_memory_mode is owned by state/src/runtime/threads.rs.
pub fn (state &StateRuntime) set_thread_memory_mode(thread_id codex_protocol.ThreadId, mode &string) ! {
	id := thread_id.value
	unsafe {
		mut pool := state.pool
		if id !in pool.threads {
			return error('thread `${id}` does not exist')
		}
		mut row := pool.threads[id]
		row.memory_mode = mode.clone()
	}
}

// STUB: delete_thread is owned by state/src/runtime/threads.rs and invokes the translated memory
// cleanup hook after removing the state row.
pub fn (state &StateRuntime) delete_thread(thread_id codex_protocol.ThreadId) !u64 {
	id := thread_id.value.clone()
	mut deleted := u64(0)
	unsafe {
		mut pool := state.pool
		if id in pool.threads {
			pool.threads.delete(id.clone())
			deleted = 1
		}
	}
	state.memories.delete_thread_memory(codex_protocol.ThreadId{ value: id })!
	return deleted
}

// STUB: SortKey is owned by state/src/model/thread_metadata.rs.
enum SortKey {
	created_at
	updated_at
	recency_at
	section_position
}

// STUB: SortDirection is owned by state/src/lib.rs.
enum SortDirection {
	asc
	desc
}

// STUB: OptionalBorrowedStrings is the safe V representation of Rust Option<&[String]> and
// Option<&[PathBuf]> used by ThreadFilterOptions.
struct OptionalBorrowedStrings {
	has_value bool
	value     model.BorrowedStrings
}

// STUB: optional_borrowed_strings_none constructs None for borrowed filter slices.
fn optional_borrowed_strings_none() OptionalBorrowedStrings {
	return OptionalBorrowedStrings{}
}

// STUB: NestedOptionalBorrowedString represents Rust Option<Option<&str>>.
struct NestedOptionalBorrowedString {
	has_outer bool
	has_inner bool
	value     &string = unsafe { nil }
}

// STUB: nested_optional_borrowed_string_none constructs the outer None filter state.
fn nested_optional_borrowed_string_none() NestedOptionalBorrowedString {
	return NestedOptionalBorrowedString{}
}

// STUB: OptionalBorrowedAnchor represents Rust Option<&Anchor>.
struct OptionalBorrowedAnchor {
	has_value bool
	value     &model.Anchor = unsafe { nil }
}

// STUB: optional_borrowed_anchor_none constructs None for an anchor filter.
fn optional_borrowed_anchor_none() OptionalBorrowedAnchor {
	return OptionalBorrowedAnchor{}
}

// STUB: ThreadFilterOptions is owned by state/src/runtime/threads.rs and preserves its full
// source field surface.
struct ThreadFilterOptions {
	archived_only   bool
	allowed_sources model.BorrowedStrings
	model_providers OptionalBorrowedStrings
	cwd_filters     OptionalBorrowedStrings
	section         NestedOptionalBorrowedString
	project_id      NestedOptionalBorrowedString
	anchor          OptionalBorrowedAnchor
	sort_key        SortKey
	sort_direction  SortDirection
	search_term     model.OptionalBorrowedString
}

// STUB: push_thread_filters is owned by state/src/runtime/threads.rs and preserves its
// QueryBuilder call shape, filter SQL, and bind order.
fn push_thread_filters(mut builder sqlx.QueryBuilder, options ThreadFilterOptions, include_thread_id_tiebreaker bool) {
	builder.push(' WHERE 1 = 1')
	if options.archived_only {
		builder.push(' AND threads.archived = 1')
	} else {
		builder.push(' AND threads.archived = 0')
	}
	if !(options.section.has_outer && options.section.has_inner) {
		builder.push(" AND threads.preview <> ''")
	}
	if options.section.has_outer {
		if options.section.has_inner {
			builder.push(' AND threads.thread_section_id = ')
			builder.push_bind(unsafe { (*options.section.value).clone() })
		} else {
			builder.push(' AND threads.thread_section_id IS NULL')
		}
	}
	if options.project_id.has_outer {
		if options.project_id.has_inner {
			builder.push(' AND threads.project_id = ')
			builder.push_bind(unsafe { (*options.project_id.value).clone() })
		} else {
			builder.push(' AND threads.project_id IS NULL')
		}
	}
	if options.allowed_sources.len > 0 {
		builder.push(' AND threads.source IN (')
		unsafe {
			for index in 0 .. options.allowed_sources.len {
				if index > 0 { builder.push(', ') }
				builder.push_bind(options.allowed_sources.data[index].clone())
			}
		}
		builder.push(')')
	}
	if options.model_providers.has_value && options.model_providers.value.len > 0 {
		builder.push(' AND threads.model_provider IN (')
		unsafe {
			for index in 0 .. options.model_providers.value.len {
				if index > 0 {
					builder.push(', ')
				}
				builder.push_bind(options.model_providers.value.data[index].clone())
			}
		}
		builder.push(')')
	}
	if options.cwd_filters.has_value {
		if options.cwd_filters.value.len == 0 {
			builder.push(' AND 1 = 0')
		} else {
			builder.push(' AND threads.cwd IN (')
			unsafe {
				for index in 0 .. options.cwd_filters.value.len {
					if index > 0 {
						builder.push(', ')
					}
					builder.push_bind(options.cwd_filters.value.data[index].clone())
				}
			}
			builder.push(')')
		}
	}
	if options.search_term.has_value {
		term := unsafe { (*options.search_term.value).clone() }
		builder.push(" AND (instr(COALESCE(threads.name, ''), ")
		builder.push_bind(term.clone())
		builder.push(') > 0 OR instr(threads.title, ')
		builder.push_bind(term.clone())
		builder.push(') > 0 OR instr(threads.preview, ')
		builder.push_bind(term)
		builder.push(') > 0)')
	}
	if options.anchor.has_value {
		anchor := unsafe { options.anchor.value }
		anchor_ts := anchor.ts.unix_milli()
		column := match options.sort_key {
			.created_at { 'threads.created_at_ms' }
			.updated_at { 'threads.updated_at_ms' }
			.recency_at { 'threads.recency_at_ms' }
			.section_position { 'threads.section_position' }
		}
		operator := if options.sort_direction == .asc { '>' } else { '<' }
		builder.push(' AND (')
		builder.push(column)
		builder.push(' ')
		builder.push(operator)
		builder.push(' ')
		builder.push_bind(anchor_ts)
		if include_thread_id_tiebreaker && anchor.id.has_value {
			builder.push(' OR (')
			builder.push(column)
			builder.push(' = ')
			builder.push_bind(anchor_ts)
			builder.push(' AND threads.id ')
			builder.push(operator)
			builder.push(' ')
			builder.push_bind(anchor.id.value.value.clone())
			builder.push(')')
		}
		builder.push(')')
	}
}
