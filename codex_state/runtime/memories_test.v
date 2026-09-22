module runtime

import codex_protocol
import codex_protocol.openai_models
import codex_protocol.thread_id as protocol_thread_id
import codex_state.model
import codex_state.runtime.test_support
import codex_state.sqlite
import os
import rand
import sqlx
import time

struct Stage1SuccessFixture {
	thread_id         codex_protocol.ThreadId
	source_updated_at i64
	rollout_slug      string
}

struct UsageUpdateFixture {
	thread_id   codex_protocol.ThreadId
	usage_count sqlx.BindValue
	last_usage  sqlx.BindValue
}

fn stable_thread_id(value &string) codex_protocol.ThreadId {
	return protocol_thread_id.from_string(value) or { panic(err) }
}

fn fresh_thread_id() codex_protocol.ThreadId {
	value := rand.uuid_v4()
	return protocol_thread_id.from_string(&value) or { panic(err) }
}

fn new_test_state_runtime() &StateRuntime {
	codex_home := test_support.unique_temp_dir()
	sqlite_config := sqlite.SqliteConfig.new_for_testing(codex_home)
	return StateRuntime.init(sqlite_config, 'test-provider') or { panic(err) }
}

fn make_test_thread_metadata(state &StateRuntime, id &codex_protocol.ThreadId, updated_at i64, workspace &string) model.ThreadMetadata {
	codex_home := state.sqlite.home()
	mut metadata := test_support.test_thread_metadata(&codex_home, clone_thread_id(id), workspace.clone())
	metadata.created_at = time.unix(updated_at)
	metadata.updated_at = time.unix(updated_at)
	return metadata
}

fn insert_test_thread(state &StateRuntime, id &codex_protocol.ThreadId, updated_at i64, workspace string) {
	metadata := make_test_thread_metadata(state, id, updated_at, &workspace)
	state.upsert_thread(&metadata) or { panic(err) }
}

fn insert_test_thread_millis(state &StateRuntime, id &codex_protocol.ThreadId, updated_at_ms i64, workspace string) {
	codex_home := state.sqlite.home()
	mut metadata := test_support.test_thread_metadata(&codex_home, clone_thread_id(id), workspace)
	metadata.created_at = time.unix_milli(updated_at_ms)
	metadata.updated_at = time.unix_milli(updated_at_ms)
	state.upsert_thread(&metadata) or { panic(err) }
}

fn claim_token(state &StateRuntime, thread_id &codex_protocol.ThreadId, owner &codex_protocol.ThreadId, source_updated_at i64) string {
	outcome := state.try_claim_stage1_job(clone_thread_id(thread_id), clone_thread_id(owner), /* source_updated_at */
		source_updated_at, /* lease_seconds */
		3_600, /* max_running_jobs */
		64) or {
		panic(err)
	}
	assert outcome.kind == .claimed
	return outcome.ownership_token
}

fn claim_stage1_concurrently(state &StateRuntime, thread_id codex_protocol.ThreadId, owner codex_protocol.ThreadId, source_updated_at i64, max_running_jobs usize) model.Stage1JobClaimOutcome {
	return state.try_claim_stage1_job(thread_id, owner, source_updated_at, 3_600, max_running_jobs) or { panic(err) }
}

fn succeed_output(state &StateRuntime, thread_id &codex_protocol.ThreadId, owner &codex_protocol.ThreadId, source_updated_at i64, summary string) bool {
	token := claim_token(state, thread_id, owner, source_updated_at)
	raw := 'raw-${summary}'
	no_slug := model.borrowed_string_none()
	return succeed_output_with_details(state, thread_id, &token, source_updated_at, &raw, &summary, no_slug)
}

fn succeed_output_with_details(state &StateRuntime, thread_id &codex_protocol.ThreadId, ownership_token &string, source_updated_at i64, raw_memory &string, rollout_summary &string, rollout_slug model.OptionalBorrowedString) bool {
	return state.mark_stage1_job_succeeded(clone_thread_id(thread_id), ownership_token, source_updated_at, raw_memory, rollout_summary, /* rollout_slug */
		rollout_slug) or { panic(err) }
}

fn age_phase2_success_beyond_cooldown(state &StateRuntime) {
	sqlx.query('UPDATE jobs SET finished_at = ? WHERE kind = ? AND job_key = ?').bind(time.now().unix() - phase2_success_cooldown_seconds - 1).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).execute(memory_pool(state)) or { panic(err) }
}

fn memory_pool(state &StateRuntime) &SqlitePool {
	return state.memories.pool
}

fn stage1_job(state &StateRuntime, id &codex_protocol.ThreadId) sqlx.Row {
	return sqlx.query('SELECT status, lease_until, retry_at, retry_remaining, input_watermark, last_success_watermark FROM jobs WHERE kind = ? AND job_key = ?').bind(job_kind_memory_stage1).bind(id.value.clone()).fetch_one(memory_pool(state)) or {
		panic(err)
	}
}

fn finish_phase2(state &StateRuntime, owner &codex_protocol.ThreadId, selected []model.Stage1Output) bool {
	claim := state.try_claim_global_phase2_job(clone_thread_id(owner), /* lease_seconds */
		3_600) or {
		panic(err)
	}
	assert claim.kind == .claimed
	return state.mark_global_phase2_job_succeeded(&claim.ownership_token, /* completed_watermark */
		claim.input_watermark, &selected) or { panic(err) }
}

fn test_stage1_claim_skips_when_up_to_date() {
	state := new_test_state_runtime()
	thread_id := fresh_thread_id()
	owner_a := fresh_thread_id()
	owner_b := fresh_thread_id()
	insert_test_thread(state, &thread_id, 100, os.join_path(state.sqlite.home(), 'a'))
	token := claim_token(state, &thread_id, &owner_a, 100)
	raw := 'raw'
	summary := 'sum'
	assert succeed_output_with_details(state, &thread_id, &token, 100, &raw, &summary, model.borrowed_string_none())
	up_to_date := state.try_claim_stage1_job(clone_thread_id(&thread_id), clone_thread_id(&owner_b), 100, 3_600, 64) or { panic(err) }
	assert up_to_date.kind == .skipped_up_to_date
	newer := state.try_claim_stage1_job(clone_thread_id(&thread_id), clone_thread_id(&owner_b), 101, 3_600, 64) or { panic(err) }
	assert newer.kind == .claimed
}

fn test_stage1_running_stale_can_be_stolen_but_fresh_running_is_skipped() {
	state := new_test_state_runtime()
	thread_id := fresh_thread_id()
	insert_test_thread(state, &thread_id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	owner_a := fresh_thread_id()
	owner_b := fresh_thread_id()
	assert state.try_claim_stage1_job(clone_thread_id(&thread_id), clone_thread_id(&owner_a), 100, 3_600, 64)!.kind == .claimed
	assert state.try_claim_stage1_job(clone_thread_id(&thread_id), clone_thread_id(&owner_b), 100, 3_600, 64)!.kind == .skipped_running
	sqlx.query("UPDATE jobs SET lease_until = 0 WHERE kind = 'memory_stage1' AND job_key = ?").bind(thread_id.value.clone()).execute(memory_pool(state))!
	assert state.try_claim_stage1_job(clone_thread_id(&thread_id), clone_thread_id(&owner_b), 100, 3_600, 64)!.kind == .claimed
}

fn test_stage1_concurrent_claim_for_same_thread_is_conflict_safe() {
	state := new_test_state_runtime()
	thread_id := fresh_thread_id()
	insert_test_thread(state, &thread_id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	mut first_task := spawn claim_stage1_concurrently(state, clone_thread_id(&thread_id), fresh_thread_id(), 100, 64)
	mut second_task := spawn claim_stage1_concurrently(state, clone_thread_id(&thread_id), fresh_thread_id(), 100, 64)
	first := first_task.wait()
	second := second_task.wait()
	kinds := [first.kind, second.kind]
	assert kinds.filter(it == .claimed).len == 1
	assert kinds.filter(it == .skipped_running).len == 1
}

fn test_stage1_concurrent_claims_respect_running_cap() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, 101, os.join_path(state.sqlite.home(), 'workspace-b'))
	mut first_task := spawn claim_stage1_concurrently(state, clone_thread_id(&a), fresh_thread_id(), 100, 1)
	mut second_task := spawn claim_stage1_concurrently(state, clone_thread_id(&b), fresh_thread_id(), 101, 1)
	first := first_task.wait()
	second := second_task.wait()
	kinds := [first.kind, second.kind]
	assert kinds.filter(it == .claimed).len == 1
	assert kinds.filter(it == .skipped_running).len == 1
}

fn test_claim_stage1_jobs_filters_by_age_idle_and_current_thread() {
	state := new_test_state_runtime()
	now := time.now().unix()
	current := fresh_thread_id()
	fresh := fresh_thread_id()
	just_under_idle := fresh_thread_id()
	eligible := fresh_thread_id()
	old := fresh_thread_id()
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	insert_test_thread(state, &fresh, now - 3_600, os.join_path(state.sqlite.home(), 'fresh'))
	insert_test_thread(state, &just_under_idle, now - 12 * 3_600 + 60, os.join_path(state.sqlite.home(), 'just-under-idle'))
	insert_test_thread(state, &eligible, now - 12 * 3_600 - 60, os.join_path(state.sqlite.home(), 'eligible-idle'))
	insert_test_thread(state, &old, now - 31 * 86_400, os.join_path(state.sqlite.home(), 'old'))
	allowed := ['cli']
	claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             1
		max_claimed:            5
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert claims.len == 1
	assert claims[0].thread.id.value == eligible.value
}

fn test_claim_stage1_jobs_uses_millisecond_age_window_and_second_watermark() {
	// Use fixed millisecond boundaries to prove the age predicate does not silently round to
	// seconds. Both ends of the Rust SQL `BETWEEN`-equivalent comparisons are inclusive.
	fixed_now_ms := i64(1_800_000_000_789)
	idle_cutoff_ms := fixed_now_ms - 12 * 3_600 * 1_000
	max_age_cutoff_ms := fixed_now_ms - i64(30) * 86_400 * 1_000
	assert stage1_startup_age_window_contains(idle_cutoff_ms, fixed_now_ms, 30, 12)
	assert !stage1_startup_age_window_contains(idle_cutoff_ms + 1, fixed_now_ms, 30, 12)
	assert stage1_startup_age_window_contains(max_age_cutoff_ms, fixed_now_ms, 30, 12)
	assert !stage1_startup_age_window_contains(max_age_cutoff_ms - 1, fixed_now_ms, 30, 12)

	state := new_test_state_runtime()
	current := fresh_thread_id()
	candidate := fresh_thread_id()
	now := time.now()
	insert_test_thread(state, &current, now.unix(), os.join_path(state.sqlite.home(), 'current'))
	// Keep a visible millisecond component in the state-schema value while placing the row safely
	// inside the age window.
	candidate_updated_at_ms := (now.unix() - 13 * 3_600) * 1_000 + 789
	insert_test_thread_millis(state, &candidate, candidate_updated_at_ms, os.join_path(state.sqlite.home(), 'candidate'))
	allowed := ['cli']
	claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             10
		max_claimed:            1
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert claims.len == 1
	assert claims[0].thread.updated_at.unix_milli() == candidate_updated_at_ms
	// Rust filters on `updated_at_ms`, then deliberately stores `DateTime::timestamp()` seconds as
	// the extraction watermark.
	assert stage1_job(state, &candidate).try_get[sqlx.OptionalI64]('input_watermark')!.value == candidate_updated_at_ms / 1_000
}

fn test_startup_claim_hydrates_full_nondefault_thread_metadata() {
	state := new_test_state_runtime()
	current := fresh_thread_id()
	candidate := fresh_thread_id()
	now := time.now().unix()
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	codex_home := state.sqlite.home()
	mut metadata := test_support.test_thread_metadata(&codex_home, clone_thread_id(&candidate), os.join_path(state.sqlite.home(), 'workspace-candidate'))
	metadata.originator = model.some_string('desktop')
	metadata.created_at = time.unix(now - 14 * 3_600)
	metadata.updated_at = time.unix(now - 13 * 3_600)
	metadata.recency_at = time.unix(now - 12 * 3_600)
	thread_source := 'subagent'
	metadata.thread_source = model.OptionalThreadSource{
		has_value: true
		value:     codex_protocol.thread_source_from_str(&thread_source)
	}
	metadata.agent_nickname = model.some_string('Ada')
	metadata.agent_role = model.some_string('reviewer')
	metadata.agent_path = model.some_string('/root/reviewer')
	metadata.model_provider = 'custom-provider'
	metadata.model = model.some_string('gpt-test')
	metadata.reasoning_effort = model.OptionalReasoningEffort{
		has_value: true
		value:     openai_models.ReasoningEffort.high
	}
	metadata.cli_version = '1.2.3'
	metadata.title = 'Hydrated thread'
	metadata.name = model.some_string('Pinned name')
	metadata.preview = model.some_string('Visible preview')
	metadata.sandbox_policy = 'workspace-write'
	metadata.approval_mode = 'never'
	metadata.tokens_used = 321
	metadata.first_user_message = model.some_string('First prompt')
	metadata.section = model.OptionalThreadSection{
		has_value: true
		value:     model.ThreadSection{
			id:         'section-id'
			name:       'Section name'
			appearance: model.OptionalThreadSectionAppearance{
				has_value: true
				value:     model.ThreadSectionAppearance{
					icon:  model.some_string('spark')
					color: model.some_string('blue')
				}
			}
		}
	}
	metadata.section_position = model.some_i64(44)
	metadata.section_entered_at = model.some_time(time.unix(now - 7_200))
	metadata.project_id = model.some_string('project-id')
	metadata.daybreak_enabled = model.some_bool(true)
	metadata.git_sha = model.some_string('deadbeef')
	metadata.git_branch = model.some_string('feature/hydration')
	metadata.git_origin_url = model.OptionalSanitizedGitUrl{
		has_value: true
		value:     codex_protocol.SanitizedGitUrl.try_from('https://example.com/codex.git')!
	}
	state.upsert_thread(&metadata)!
	allowed := ['cli']
	claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             10
		max_claimed:            1
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert claims.len == 1
	claimed_thread := claims[0].thread
	assert claimed_thread.id.value == candidate.value
	assert claimed_thread.originator.value == 'desktop'
	assert claimed_thread.rollout_path == os.join_path(state.sqlite.home(), 'rollout-${candidate.value}.jsonl')
	assert claimed_thread.created_at.unix() == now - 14 * 3_600
	assert claimed_thread.updated_at.unix() == now - 13 * 3_600
	assert claimed_thread.recency_at.unix() == now - 12 * 3_600
	assert claimed_thread.thread_source.has_value
		&& claimed_thread.thread_source.value.as_str() == 'subagent'
	assert claimed_thread.agent_nickname.value == 'Ada'
	assert claimed_thread.agent_role.value == 'reviewer'
	assert claimed_thread.agent_path.value == '/root/reviewer'
	assert claimed_thread.model_provider == 'custom-provider'
	assert claimed_thread.model.value == 'gpt-test'
	assert claimed_thread.reasoning_effort.has_value && claimed_thread.reasoning_effort.value == .high
	assert claimed_thread.cwd == os.join_path(state.sqlite.home(), 'workspace-candidate')
	assert claimed_thread.cli_version == '1.2.3'
	assert claimed_thread.title == 'Hydrated thread'
	assert claimed_thread.name.value == 'Pinned name'
	assert claimed_thread.preview.value == 'Visible preview'
	assert claimed_thread.sandbox_policy == 'workspace-write'
	assert claimed_thread.approval_mode == 'never'
	assert claimed_thread.tokens_used == 321
	assert claimed_thread.first_user_message.value == 'First prompt'
	assert !claimed_thread.archived_at.has_value
	assert claimed_thread.section.has_value
	assert claimed_thread.section.value.id == 'section-id'
	assert claimed_thread.section.value.name == 'Section name'
	assert claimed_thread.section.value.appearance.value.icon.value == 'spark'
	assert claimed_thread.section.value.appearance.value.color.value == 'blue'
	assert claimed_thread.section_position.value == 44
	assert claimed_thread.section_entered_at.value.unix() == now - 7_200
	assert claimed_thread.project_id.value == 'project-id'
	assert claimed_thread.daybreak_enabled.has_value && claimed_thread.daybreak_enabled.value
	assert claimed_thread.git_sha.value == 'deadbeef'
	assert claimed_thread.git_branch.value == 'feature/hydration'
	assert claimed_thread.git_origin_url.value.value == 'https://example.com/codex.git'
}

fn metadata_sql_row_for_conversion_test(state &StateRuntime) sqlx.Row {
	id := fresh_thread_id()
	codex_home := state.sqlite.home()
	metadata := test_support.test_thread_metadata(&codex_home, id, os.join_path(state.sqlite.home(), 'workspace'))
	updated_at_ms := metadata.updated_at.unix_milli()
	return thread_sql_row(&ThreadStateRow{
		metadata:      metadata
		updated_at_ms: updated_at_ms
	})
}

fn test_thread_row_normalizes_legacy_second_precision_timestamps() {
	state := new_test_state_runtime()
	row := metadata_sql_row_for_conversion_test(state)
	mut integers := row.integers.clone()
	integers['created_at'] = 1_700_000_000
	integers['updated_at'] = 1_700_000_100
	integers['recency_at'] = 1_700_000_200
	legacy_row := sqlx.Row{
		...row
		integers: integers
	}
	raw := model.ThreadRow.try_from_row(&legacy_row)!
	metadata := model.ThreadMetadata.try_from(raw)!
	assert metadata.created_at.unix() == 1_700_000_000
	assert metadata.updated_at.unix() == 1_700_000_100
	assert metadata.recency_at.unix() == 1_700_000_200
}

fn test_thread_metadata_rejects_malformed_persisted_thread_uuid() {
	state := new_test_state_runtime()
	row := metadata_sql_row_for_conversion_test(state)
	mut strings := row.strings.clone()
	strings['id'] = 'not-a-uuid'
	invalid_row := sqlx.Row{
		...row
		strings: strings
	}
	raw := model.ThreadRow.try_from_row(&invalid_row)!
	if _ := model.ThreadMetadata.try_from(raw) {
		assert false, 'malformed persisted thread UUID must fail hydration'
	} else {
		assert err.msg().contains('invalid UUID')
	}
}

fn test_thread_metadata_rejects_invalid_history_mode() {
	state := new_test_state_runtime()
	row := metadata_sql_row_for_conversion_test(state)
	mut strings := row.strings.clone()
	strings['history_mode'] = 'future'
	invalid_row := sqlx.Row{
		...row
		strings: strings
	}
	raw := model.ThreadRow.try_from_row(&invalid_row)!
	if _ := model.ThreadMetadata.try_from(raw) {
		assert false, 'unknown history mode must fail hydration'
	} else {
		assert err.msg() == 'unknown thread history mode `future`'
	}
}

fn test_thread_metadata_validates_section_consistency_and_appearance() {
	state := new_test_state_runtime()
	id_only_row := metadata_sql_row_for_conversion_test(state)
	mut id_only_strings := id_only_row.strings.clone()
	mut id_only_nulls := id_only_row.nullable_strings.clone()
	id_only_strings['section'] = 'section-id'
	id_only_nulls.delete('section')
	id_only_raw := model.ThreadRow.try_from_row(&sqlx.Row{
		...id_only_row
		strings:          id_only_strings
		nullable_strings: id_only_nulls
	})!
	if _ := model.ThreadMetadata.try_from(id_only_raw) {
		assert false, 'section id without name must fail hydration'
	} else {
		assert err.msg() == 'thread references an unknown section: section-id'
	}

	name_only_row := metadata_sql_row_for_conversion_test(state)
	mut name_only_strings := name_only_row.strings.clone()
	mut name_only_nulls := name_only_row.nullable_strings.clone()
	name_only_strings['section_name'] = 'Section name'
	name_only_nulls.delete('section_name')
	name_only_raw := model.ThreadRow.try_from_row(&sqlx.Row{
		...name_only_row
		strings:          name_only_strings
		nullable_strings: name_only_nulls
	})!
	if _ := model.ThreadMetadata.try_from(name_only_raw) {
		assert false, 'section name without id must fail hydration'
	} else {
		assert err.msg() == 'thread has a section name without a section id: Section name'
	}

	valid_row := metadata_sql_row_for_conversion_test(state)
	mut valid_strings := valid_row.strings.clone()
	mut valid_nulls := valid_row.nullable_strings.clone()
	valid_strings['section'] = 'section-id'
	valid_strings['section_name'] = 'Section name'
	valid_strings['section_appearance'] = '{"icon":"spark","color":"blue"}'
	valid_nulls.delete('section')
	valid_nulls.delete('section_name')
	valid_nulls.delete('section_appearance')
	valid_raw := model.ThreadRow.try_from_row(&sqlx.Row{
		...valid_row
		strings:          valid_strings
		nullable_strings: valid_nulls
	})!
	metadata := model.ThreadMetadata.try_from(valid_raw)!
	assert metadata.section.has_value
	assert metadata.section.value.id == 'section-id'
	assert metadata.section.value.name == 'Section name'
	assert metadata.section.value.appearance.has_value
	assert metadata.section.value.appearance.value.icon.value == 'spark'
	assert metadata.section.value.appearance.value.color.value == 'blue'
}

fn test_claim_stage1_jobs_bounds_state_scan_before_memory_probes() {
	state := new_test_state_runtime()
	now := time.now().unix()
	current := fresh_thread_id()
	up_to_date := fresh_thread_id()
	stale := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	insert_test_thread(state, &up_to_date, now - 13 * 3_600, os.join_path(state.sqlite.home(), 'up-to-date'))
	insert_test_thread(state, &stale, now - 14 * 3_600, os.join_path(state.sqlite.home(), 'stale'))
	token := claim_token(state, &up_to_date, &owner, now - 13 * 3_600)
	raw := 'raw'
	summary := 'summary'
	assert succeed_output_with_details(state, &up_to_date, &token, now - 13 * 3_600, &raw, &summary, model.borrowed_string_none())
	allowed := ['cli']
	first := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             1
		max_claimed:            1
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert first.len == 0
	second := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             2
		max_claimed:            1
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert second.len == 1
	assert second[0].thread.id.value == stale.value
}

fn test_claim_stage1_jobs_skips_threads_without_enabled_memory() {
	state := new_test_state_runtime()
	now := time.now().unix()
	current := fresh_thread_id()
	disabled := fresh_thread_id()
	paginated := fresh_thread_id()
	enabled := fresh_thread_id()
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	disabled_workspace := os.join_path(state.sqlite.home(), 'disabled')
	mut disabled_metadata := make_test_thread_metadata(state, &disabled, now - 13 * 3_600, &disabled_workspace)
	disabled_metadata.history_mode = .paginated
	state.upsert_thread(&disabled_metadata)!
	paginated_workspace := os.join_path(state.sqlite.home(), 'paginated')
	mut paginated_metadata := make_test_thread_metadata(state, &paginated, now - 13 * 3_600, &paginated_workspace)
	paginated_metadata.history_mode = .paginated
	state.upsert_thread(&paginated_metadata)!
	insert_test_thread(state, &enabled, now - 13 * 3_600, os.join_path(state.sqlite.home(), 'enabled'))
	sqlx.query("UPDATE threads SET memory_mode = 'disabled' WHERE id = ?").bind(disabled.value.clone()).execute(state.pool)!
	allowed := ['cli']
	claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             10
		max_claimed:            10
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	mut ids := claims.map(it.thread.id.value)
	ids.sort()
	mut expected := [enabled.value.clone(), paginated.value.clone()]
	expected.sort()
	assert ids == expected
}

fn test_clear_memory_data_clears_rows_and_preserves_thread_memory_modes() {
	state := new_test_state_runtime()
	now := time.now().unix() - 13 * 3_600
	enabled := fresh_thread_id()
	disabled := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &enabled, now, os.join_path(state.sqlite.home(), 'enabled'))
	token := claim_token(state, &enabled, &owner, now)
	raw := 'raw'
	summary := 'summary'
	assert succeed_output_with_details(state, &enabled, &token, now, &raw, &summary, model.borrowed_string_none())
	state.enqueue_global_consolidation(now)!
	insert_test_thread(state, &disabled, now, os.join_path(state.sqlite.home(), 'disabled'))
	sqlx.query("UPDATE threads SET memory_mode = 'disabled' WHERE id = ?").bind(disabled.value.clone()).execute(state.pool)!
	state.clear_memory_data()!
	stage1_outputs_count := sqlx.query_scalar[i64]('SELECT COUNT(*) FROM stage1_outputs').fetch_one(memory_pool(state))!
	memory_jobs_count := sqlx.query_scalar[i64]('SELECT COUNT(*) FROM jobs WHERE kind = ? OR kind = ?').bind(job_kind_memory_stage1).bind(job_kind_memory_consolidate_global).fetch_one(memory_pool(state))!
	enabled_mode := sqlx.query_scalar[string]('SELECT memory_mode FROM threads WHERE id = ?').bind(enabled.value.clone()).fetch_one(state.pool)!
	disabled_mode := sqlx.query_scalar[string]('SELECT memory_mode FROM threads WHERE id = ?').bind(disabled.value.clone()).fetch_one(state.pool)!
	assert stage1_outputs_count == 0
	assert memory_jobs_count == 0
	assert enabled_mode == 'enabled'
	assert disabled_mode == 'disabled'
}

fn test_claim_stage1_jobs_enforces_global_running_cap() {
	state := new_test_state_runtime()
	current := fresh_thread_id()
	now := time.now().unix()
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	for index in 0 .. 80 {
		id := fresh_thread_id()
		updated_at := now - 13 * 3_600 - index
		workspace := os.join_path(state.sqlite.home(), 'thread-${index}')
		insert_test_thread(state, &id, updated_at, workspace)
		if index < 10 {
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
) VALUES (?, ?, 'running', ?, ?, ?, NULL, ?, NULL, ?, NULL, ?, NULL)
                    ").bind(job_kind_memory_stage1).bind(id.value.clone()).bind(current.value.clone()).bind(rand.uuid_v4()).bind(now).bind(now + 3_600).bind(i64(3)).bind(updated_at).execute(memory_pool(state))!
		}
	}
	allowed := ['cli']
	claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             200
		max_claimed:            64
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert claims.len == 54
	running_count := sqlx.query("
SELECT COUNT(*) AS count
FROM jobs
WHERE kind = 'memory_stage1'
  AND status = 'running'
  AND lease_until IS NOT NULL
	  AND lease_until > ?
            ").bind(time.now().unix()).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert running_count == 64
	more_claims := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), model.Stage1StartupClaimParams{
		scan_limit:             200
		max_claimed:            64
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	})!
	assert more_claims.len == 0
}

fn test_claim_stage1_jobs_processes_two_full_batches_across_startup_passes() {
	state := new_test_state_runtime()
	now := time.now().unix()
	current := fresh_thread_id()
	owner := clone_thread_id(&current)
	insert_test_thread(state, &current, now, os.join_path(state.sqlite.home(), 'current'))
	for index in 0 .. 200 {
		id := fresh_thread_id()
		workspace := os.join_path(state.sqlite.home(), 'thread-${index}')
		insert_test_thread(state, &id, now - 13 * 3_600 - index, workspace)
	}
	allowed := ['cli']
	params := model.Stage1StartupClaimParams{
		scan_limit:             5_000
		max_claimed:            64
		max_age_days:           30
		min_rollout_idle_hours: 12
		allowed_sources:        model.borrowed_strings(&allowed)
		lease_seconds:          3_600
	}
	first := state.claim_stage1_jobs_for_startup(clone_thread_id(&current), params)!
	assert first.len == 64
	for claim in first {
		no_slug := model.borrowed_string_none()
		raw := 'raw'
		summary := 'summary'
		assert state.mark_stage1_job_succeeded(clone_thread_id(&claim.thread.id), &claim.ownership_token, claim.thread.updated_at.unix(), &raw, &summary, no_slug)!
	}
	second := state.claim_stage1_jobs_for_startup(owner, params)!
	assert second.len == 64
}

fn test_delete_thread_removes_stage1_output_and_enqueues_phase2_when_selected() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	initial_token := claim_token(state, &id, &owner, 100)
	raw := 'raw'
	summary := 'sum'
	assert succeed_output_with_details(state, &id, &initial_token, 100, &raw, &summary, model.borrowed_string_none())
	count_before := sqlx.query('SELECT COUNT(*) AS count FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert count_before == 1
	selected := state.list_stage1_outputs_for_global(10)!
	assert finish_phase2(state, &owner, selected)
	before_delete := time.now().unix()
	assert state.delete_thread(clone_thread_id(&id))! == 1
	count_after := sqlx.query('SELECT COUNT(*) AS count FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert count_after == 0
	phase2_job := sqlx.query('
SELECT status, input_watermark
FROM jobs
WHERE kind = ? AND job_key = ?
            ').bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).fetch_one(memory_pool(state))!
	assert phase2_job.try_get[string]('status')! == 'pending'
	assert phase2_job.try_get[i64]('input_watermark')! >= before_delete
	visible_outputs := state.list_stage1_outputs_for_global(10)!
	assert visible_outputs.len == 0
}

fn test_mark_stage1_job_succeeded_no_output_skips_phase2_when_output_was_already_absent() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	owner_b := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	token := claim_token(state, &id, &owner, 100)
	assert state.mark_stage1_job_succeeded_no_output(clone_thread_id(&id), &token)!
	output_rows := sqlx.query('SELECT COUNT(*) AS count FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert output_rows == 0
	assert state.try_claim_stage1_job(clone_thread_id(&id), clone_thread_id(&owner_b), 100, 3_600, 64)!.kind == .skipped_up_to_date
	global_rows := sqlx.query('SELECT COUNT(*) AS count FROM jobs WHERE kind = ?').bind(job_kind_memory_consolidate_global).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert global_rows == 0
}

fn test_mark_stage1_job_succeeded_no_output_enqueues_phase2_when_deleting_output() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	owner_b := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	initial_token := claim_token(state, &id, &owner, 100)
	raw := 'raw'
	summary := 'sum'
	assert succeed_output_with_details(state, &id, &initial_token, 100, &raw, &summary, model.borrowed_string_none())
	phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert phase2_claim.kind == .claimed
	assert phase2_claim.input_watermark == 100
	assert state.mark_global_phase2_job_succeeded(&phase2_claim.ownership_token, phase2_claim.input_watermark, &[]model.Stage1Output{})!
	token := claim_token(state, &id, &owner_b, 101)
	assert state.mark_stage1_job_succeeded_no_output(clone_thread_id(&id), &token)!
	output_row_count := sqlx.query('SELECT COUNT(*) AS count FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!.try_get[i64]('count')!
	assert output_row_count == 0
	age_phase2_success_beyond_cooldown(state)
	second_phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert second_phase2_claim.kind == .claimed
	assert second_phase2_claim.input_watermark == 101
	assert state.mark_global_phase2_job_succeeded(&second_phase2_claim.ownership_token, second_phase2_claim.input_watermark, &[]model.Stage1Output{})!
}

fn test_stage1_retry_exhaustion_does_not_block_newer_watermark() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	reason := 'boom'
	for _ in 0 .. 3 {
		token := claim_token(state, &id, &owner, 100)
		assert state.mark_stage1_job_failed(clone_thread_id(&id), &token, &reason, 0)!
	}
	assert state.try_claim_stage1_job(clone_thread_id(&id), clone_thread_id(&owner), 100, 3_600, 64)!.kind == .skipped_retry_exhausted
	assert state.try_claim_stage1_job(clone_thread_id(&id), clone_thread_id(&owner), 101, 3_600, 64)!.kind == .claimed
	job_row := sqlx.query('SELECT retry_remaining, input_watermark FROM jobs WHERE kind = ? AND job_key = ?').bind(job_kind_memory_stage1).bind(id.value.clone()).fetch_one(memory_pool(state))!
	assert job_row.try_get[i64]('retry_remaining')! == 3
	assert job_row.try_get[i64]('input_watermark')! == 101
}

fn test_phase2_global_lock_respects_success_cooldown() {
	state := new_test_state_runtime()
	owner := fresh_thread_id()
	state.enqueue_global_consolidation( /* input_watermark */
	100)!
	assert finish_phase2(state, &owner, []model.Stage1Output{})
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .skipped_cooldown
	state.enqueue_global_consolidation(101)!
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .skipped_cooldown
	age_phase2_success_beyond_cooldown(state)
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .claimed
}

fn test_phase2_global_lock_can_be_claimed_after_retry_budget_is_exhausted() {
	state := new_test_state_runtime()
	owner := fresh_thread_id()
	reason := 'boom'
	state.enqueue_global_consolidation(100)!
	for _ in 0 .. 3 {
		claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
		assert claim.kind == .claimed
		assert state.mark_global_phase2_job_failed(&claim.ownership_token, &reason, 0)!
	}
	job_row := sqlx.query('SELECT retry_remaining FROM jobs WHERE kind = ? AND job_key = ?').bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).fetch_one(memory_pool(state))!
	assert job_row.try_get[i64]('retry_remaining')! == 0
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .claimed
}

fn test_list_stage1_outputs_for_global_returns_latest_outputs() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	b_workspace := os.join_path(state.sqlite.home(), 'workspace-b')
	mut b_metadata := make_test_thread_metadata(state, &b, 101, &b_workspace)
	b_metadata.git_branch = model.some_string('feature/stage1-b')
	state.upsert_thread(&b_metadata)!
	token_a := claim_token(state, &a, &owner, 100)
	raw_a := 'raw memory a'
	summary_a := 'summary a'
	assert succeed_output_with_details(state, &a, &token_a, 100, &raw_a, &summary_a, model.borrowed_string_none())
	token := claim_token(state, &b, &owner, 101)
	raw := 'raw memory b'
	summary := 'summary b'
	slug := 'rollout-b'
	assert state.mark_stage1_job_succeeded(clone_thread_id(&b), &token, 101, &raw, &summary, model.borrowed_string_some(&slug))!
	outputs := state.list_stage1_outputs_for_global( /* n */
	10)!
	assert outputs.len == 2
	assert outputs[0].thread_id.value == b.value
	assert outputs[0].rollout_summary == 'summary b'
	assert outputs[0].rollout_slug.value == 'rollout-b'
	assert outputs[0].cwd == os.join_path(state.sqlite.home(), 'workspace-b')
	assert outputs[0].git_branch.value == 'feature/stage1-b'
	assert outputs[1].thread_id.value == a.value
	assert outputs[1].rollout_summary == 'summary a'
	assert !outputs[1].rollout_slug.has_value
	assert outputs[1].cwd == os.join_path(state.sqlite.home(), 'workspace-a')
	assert !outputs[1].git_branch.has_value
}

fn test_list_stage1_outputs_for_global_skips_empty_payloads() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-non-empty'))
	insert_test_thread(state, &b, 101, os.join_path(state.sqlite.home(), 'workspace-empty'))
	sqlx.query('INSERT INTO stage1_outputs (thread_id, source_updated_at, raw_memory, rollout_summary, generated_at) VALUES (?, ?, ?, ?, ?)').bind(a.value.clone()).bind(i64(100)).bind('raw memory').bind('summary').bind(i64(100)).execute(memory_pool(state))!
	sqlx.query('INSERT INTO stage1_outputs (thread_id, source_updated_at, raw_memory, rollout_summary, generated_at) VALUES (?, ?, ?, ?, ?)').bind(b.value.clone()).bind(i64(101)).bind('').bind('').bind(i64(101)).execute(memory_pool(state))!
	outputs := state.list_stage1_outputs_for_global(1)!
	assert outputs.len == 1
	assert outputs[0].thread_id.value == a.value
	assert outputs[0].rollout_summary == 'summary'
	assert outputs[0].cwd == os.join_path(state.sqlite.home(), 'workspace-non-empty')
}

fn test_list_stage1_outputs_for_global_includes_paginated_and_skips_polluted_threads() {
	state := new_test_state_runtime()
	enabled := fresh_thread_id()
	polluted := fresh_thread_id()
	owner := fresh_thread_id()
	enabled_workspace := os.join_path(state.sqlite.home(), 'workspace-enabled')
	mut enabled_metadata := make_test_thread_metadata(state, &enabled, 100, &enabled_workspace)
	enabled_metadata.history_mode = .paginated
	state.upsert_thread(&enabled_metadata)!
	polluted_workspace := os.join_path(state.sqlite.home(), 'workspace-polluted')
	mut polluted_metadata := make_test_thread_metadata(state, &polluted, 100, &polluted_workspace)
	polluted_metadata.history_mode = .paginated
	state.upsert_thread(&polluted_metadata)!
	for id in [&enabled, &polluted] {
		token := claim_token(state, id, &owner, 100)
		raw := 'raw memory'
		summary := 'summary'
		assert succeed_output_with_details(state, id, &token, 100, &raw, &summary, model.borrowed_string_none())
	}
	mode := 'polluted'
	state.set_thread_memory_mode(clone_thread_id(&polluted), &mode)!
	outputs := state.list_stage1_outputs_for_global(10)!
	assert outputs.len == 1
	assert outputs[0].thread_id.value == enabled.value
}

fn test_get_phase2_input_selection_returns_current_selected_rows() {
	state := new_test_state_runtime()
	a_value := '00000000-0000-4000-8000-000000000001'
	b_value := '00000000-0000-4000-8000-000000000002'
	c_value := '00000000-0000-4000-8000-000000000003'
	a := stable_thread_id(&a_value)
	b := stable_thread_id(&b_value)
	c := stable_thread_id(&c_value)
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, 100, os.join_path(state.sqlite.home(), 'workspace-b'))
	insert_test_thread(state, &c, 100, os.join_path(state.sqlite.home(), 'workspace-c'))
	for fixture in [
		Stage1SuccessFixture{ thread_id: clone_thread_id(&a), source_updated_at: 100, rollout_slug: 'rollout-a' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&b), source_updated_at: 101, rollout_slug: 'rollout-b' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&c), source_updated_at: 102, rollout_slug: 'rollout-c' },
	] {
		token := claim_token(state, &fixture.thread_id, &owner, fixture.source_updated_at)
		raw := 'raw-${fixture.source_updated_at}'
		summary := 'summary-${fixture.source_updated_at}'
		assert succeed_output_with_details(state, &fixture.thread_id, &token, fixture.source_updated_at, &raw, &summary, model.borrowed_string_some(&fixture.rollout_slug))
	}
	phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert phase2_claim.kind == .claimed
	assert phase2_claim.input_watermark == 102
	outputs := state.list_stage1_outputs_for_global(10)!
	mut selected_outputs := []model.Stage1Output{}
	for output in outputs {
		if output.thread_id.value == c.value || output.thread_id.value == a.value {
			selected_outputs << model.clone_stage1_output(&output)
		}
	}
	assert state.mark_global_phase2_job_succeeded(&phase2_claim.ownership_token, phase2_claim.input_watermark, &selected_outputs)!
	selection := state.get_phase2_input_selection(2, 36_500)!
	assert selection.len == 2
	assert selection.map(it.thread_id.value) == [b.value, c.value]
	selected_c := selection.filter(it.thread_id.value == c.value)
	assert selected_c.len == 1
	assert selected_c[0].rollout_path == os.join_path(state.sqlite.home(), 'rollout-${c.value}.jsonl')
}

fn test_get_phase2_input_selection_excludes_polluted_previous_selection() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), '${a.value}'))
	insert_test_thread(state, &b, 100, os.join_path(state.sqlite.home(), '${b.value}'))
	for fixture in [
		Stage1SuccessFixture{ thread_id: clone_thread_id(&a), source_updated_at: 100 },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&b), source_updated_at: 101 },
	] {
		token := claim_token(state, &fixture.thread_id, &owner, fixture.source_updated_at)
		raw := 'raw-${fixture.source_updated_at}'
		summary := 'summary-${fixture.source_updated_at}'
		assert succeed_output_with_details(state, &fixture.thread_id, &token, fixture.source_updated_at, &raw, &summary, model.borrowed_string_none())
	}
	assert finish_phase2(state, &owner, state.list_stage1_outputs_for_global(10)!)
	mode := 'polluted'
	state.set_thread_memory_mode(clone_thread_id(&b), &mode)!
	selection := state.get_phase2_input_selection(2, 36_500)!
	assert selection.len == 1
	assert selection[0].thread_id.value == a.value
}

fn test_mark_thread_memory_mode_polluted_enqueues_phase2_for_selected_threads() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	token := claim_token(state, &id, &owner, 100)
	raw := 'raw'
	summary := 'summary'
	assert succeed_output_with_details(state, &id, &token, 100, &raw, &summary, model.borrowed_string_none())
	assert finish_phase2(state, &owner, state.list_stage1_outputs_for_global(10)!)
	assert state.mark_thread_memory_mode_polluted(clone_thread_id(&id))!
	age_phase2_success_beyond_cooldown(state)
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .claimed
}

fn test_mark_thread_memory_mode_polluted_enqueues_phase2_when_already_polluted() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	token := claim_token(state, &id, &owner, 100)
	raw := 'raw'
	summary := 'summary'
	assert succeed_output_with_details(state, &id, &token, 100, &raw, &summary, model.borrowed_string_none())
	assert finish_phase2(state, &owner, state.list_stage1_outputs_for_global(10)!)
	sqlx.query("UPDATE threads SET memory_mode = 'polluted' WHERE id = ?").bind(id.value.clone()).execute(state.pool)!
	assert !state.mark_thread_memory_mode_polluted(clone_thread_id(&id))!
	age_phase2_success_beyond_cooldown(state)
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.kind == .claimed
}

fn test_get_phase2_input_selection_returns_regenerated_selected_rows() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	first_token := claim_token(state, &id, &owner, 100)
	first_raw := 'raw-100'
	first_summary := 'summary-100'
	first_slug := 'rollout-100'
	assert succeed_output_with_details(state, &id, &first_token, 100, &first_raw, &first_summary, model.borrowed_string_some(&first_slug))
	phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert phase2_claim.kind == .claimed
	selected_outputs := state.list_stage1_outputs_for_global(1)!
	assert state.mark_global_phase2_job_succeeded(&phase2_claim.ownership_token, phase2_claim.input_watermark, &selected_outputs)!
	refreshed_token := claim_token(state, &id, &owner, 101)
	refreshed_raw := 'raw-101'
	refreshed_summary := 'summary-101'
	refreshed_slug := 'rollout-101'
	assert succeed_output_with_details(state, &id, &refreshed_token, 101, &refreshed_raw, &refreshed_summary, model.borrowed_string_some(&refreshed_slug))
	selection := state.get_phase2_input_selection(1, 36_500)!
	assert selection.len == 1
	assert selection[0].thread_id.value == id.value
	assert selection[0].source_updated_at.unix() == 101
	selected_snapshot := sqlx.query_as('SELECT selected_for_phase2, selected_for_phase2_source_updated_at FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!
	assert selected_snapshot.try_get[i64]('selected_for_phase2')! == 1
	assert selected_snapshot.try_get[sqlx.OptionalI64]('selected_for_phase2_source_updated_at')!.value == 100
}

fn test_get_phase2_input_selection_uses_current_ranking_after_refreshes() {
	state := new_test_state_runtime()
	a_value := '00000000-0000-4000-8000-000000000001'
	b_value := '00000000-0000-4000-8000-000000000002'
	c_value := '00000000-0000-4000-8000-000000000003'
	d_value := '00000000-0000-4000-8000-000000000004'
	a := stable_thread_id(&a_value)
	b := stable_thread_id(&b_value)
	c := stable_thread_id(&c_value)
	d := stable_thread_id(&d_value)
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, 100, os.join_path(state.sqlite.home(), 'workspace-b'))
	insert_test_thread(state, &c, 100, os.join_path(state.sqlite.home(), 'workspace-c'))
	insert_test_thread(state, &d, 100, os.join_path(state.sqlite.home(), 'workspace-d'))
	for fixture in [
		Stage1SuccessFixture{ thread_id: clone_thread_id(&a), source_updated_at: 100, rollout_slug: 'rollout-a-100' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&b), source_updated_at: 101, rollout_slug: 'rollout-b-101' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&c), source_updated_at: 99, rollout_slug: 'rollout-c-99' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&d), source_updated_at: 98, rollout_slug: 'rollout-d-98' },
	] {
		token := claim_token(state, &fixture.thread_id, &owner, fixture.source_updated_at)
		raw := 'raw-${fixture.source_updated_at}'
		summary := 'summary-${fixture.source_updated_at}'
		assert succeed_output_with_details(state, &fixture.thread_id, &token, fixture.source_updated_at, &raw, &summary, model.borrowed_string_some(&fixture.rollout_slug))
	}
	phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert phase2_claim.kind == .claimed
	selected_outputs := state.list_stage1_outputs_for_global(2)!
	assert selected_outputs.map(it.thread_id.value) == [b.value, a.value]
	assert state.mark_global_phase2_job_succeeded(&phase2_claim.ownership_token, phase2_claim.input_watermark, &selected_outputs)!
	for fixture in [
		Stage1SuccessFixture{ thread_id: clone_thread_id(&a), source_updated_at: 102, rollout_slug: 'rollout-a-102' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&c), source_updated_at: 103, rollout_slug: 'rollout-c-103' },
		Stage1SuccessFixture{ thread_id: clone_thread_id(&d), source_updated_at: 104, rollout_slug: 'rollout-d-104' },
	] {
		token := claim_token(state, &fixture.thread_id, &owner, fixture.source_updated_at)
		raw := 'raw-${fixture.source_updated_at}'
		summary := 'summary-${fixture.source_updated_at}'
		assert succeed_output_with_details(state, &fixture.thread_id, &token, fixture.source_updated_at, &raw, &summary, model.borrowed_string_some(&fixture.rollout_slug))
	}
	selection := state.get_phase2_input_selection(2, 36_500)!
	assert selection.map(it.thread_id.value) == [
		c.value,
		d.value,
	]
}

fn test_mark_global_phase2_job_succeeded_updates_selected_snapshot_timestamp() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	initial_token := claim_token(state, &id, &owner, 100)
	initial_raw := 'raw-100'
	initial_summary := 'summary-100'
	initial_slug := 'rollout-100'
	assert succeed_output_with_details(state, &id, &initial_token, 100, &initial_raw, &initial_summary, model.borrowed_string_some(&initial_slug))
	first_phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert first_phase2_claim.kind == .claimed
	first_selected_outputs := state.list_stage1_outputs_for_global(1)!
	assert state.mark_global_phase2_job_succeeded(&first_phase2_claim.ownership_token, first_phase2_claim.input_watermark, &first_selected_outputs)!
	refreshed_token := claim_token(state, &id, &owner, 101)
	refreshed_raw := 'raw-101'
	refreshed_summary := 'summary-101'
	refreshed_slug := 'rollout-101'
	assert succeed_output_with_details(state, &id, &refreshed_token, 101, &refreshed_raw, &refreshed_summary, model.borrowed_string_some(&refreshed_slug))
	age_phase2_success_beyond_cooldown(state)
	second_phase2_claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert second_phase2_claim.kind == .claimed
	second_selected_outputs := state.list_stage1_outputs_for_global(1)!
	assert second_selected_outputs[0].source_updated_at.unix() == 101
	assert state.mark_global_phase2_job_succeeded(&second_phase2_claim.ownership_token, second_phase2_claim.input_watermark, &second_selected_outputs)!
	selection := state.get_phase2_input_selection(1, 36_500)!
	assert selection.len == 1
	assert selection[0].thread_id.value == id.value
	selected_snapshot := sqlx.query_as('SELECT selected_for_phase2, selected_for_phase2_source_updated_at FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!
	assert selected_snapshot.try_get[i64]('selected_for_phase2')! == 1
	assert selected_snapshot.try_get[sqlx.OptionalI64]('selected_for_phase2_source_updated_at')!.value == 101
}

fn test_mark_global_phase2_job_succeeded_only_marks_exact_selected_snapshots() {
	state := new_test_state_runtime()
	id := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &id, 100, os.join_path(state.sqlite.home(), 'workspace'))
	initial_token := claim_token(state, &id, &owner, 100)
	initial_raw := 'raw-100'
	initial_summary := 'summary-100'
	initial_slug := 'rollout-100'
	assert succeed_output_with_details(state, &id, &initial_token, 100, &initial_raw, &initial_summary, model.borrowed_string_some(&initial_slug))
	claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	assert claim.kind == .claimed
	selected := state.list_stage1_outputs_for_global(1)!
	assert selected[0].source_updated_at.unix() == 100
	refreshed_token := claim_token(state, &id, &owner, 101)
	refreshed_raw := 'raw-101'
	refreshed_summary := 'summary-101'
	refreshed_slug := 'rollout-101'
	assert succeed_output_with_details(state, &id, &refreshed_token, 101, &refreshed_raw, &refreshed_summary, model.borrowed_string_some(&refreshed_slug))
	assert state.mark_global_phase2_job_succeeded(&claim.ownership_token, claim.input_watermark, &selected)!
	selected_snapshot := sqlx.query_as('SELECT selected_for_phase2, selected_for_phase2_source_updated_at FROM stage1_outputs WHERE thread_id = ?').bind(id.value.clone()).fetch_one(memory_pool(state))!
	assert selected_snapshot.try_get[i64]('selected_for_phase2')! == 0
	assert !selected_snapshot.try_get[sqlx.OptionalI64]('selected_for_phase2_source_updated_at')!.has_value
	selection := state.get_phase2_input_selection(1, 36_500)!
	assert selection.len == 1
	assert selection[0].source_updated_at.unix() == 101
}

fn test_record_stage1_output_usage_updates_usage_metadata() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	missing := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, 101, os.join_path(state.sqlite.home(), 'workspace-b'))
	token_a := claim_token(state, &a, &owner, 100)
	raw_a := 'raw a'
	summary_a := 'sum a'
	assert succeed_output_with_details(state, &a, &token_a, 100, &raw_a, &summary_a, model.borrowed_string_none())
	token_b := claim_token(state, &b, &owner, 101)
	raw_b := 'raw b'
	summary_b := 'sum b'
	assert succeed_output_with_details(state, &b, &token_b, 101, &raw_b, &summary_b, model.borrowed_string_none())
	ids := [clone_thread_id(&a), clone_thread_id(&a), clone_thread_id(&b), missing]
	assert state.record_stage1_output_usage(&ids)! == 3
	usage_a := sqlx.query('SELECT usage_count, last_usage FROM stage1_outputs WHERE thread_id = ?').bind(a.value.clone()).fetch_one(memory_pool(state))!
	usage_b := sqlx.query('SELECT usage_count, last_usage FROM stage1_outputs WHERE thread_id = ?').bind(b.value.clone()).fetch_one(memory_pool(state))!
	assert usage_a.try_get[i64]('usage_count')! == 2
	assert usage_b.try_get[i64]('usage_count')! == 1
	last_usage_a := usage_a.try_get[i64]('last_usage')!
	last_usage_b := usage_b.try_get[i64]('last_usage')!
	assert last_usage_a == last_usage_b
	assert last_usage_a > 0
}

fn test_get_phase2_input_selection_prioritizes_usage_count_then_recent_usage() {
	state := new_test_state_runtime()
	now := time.now().unix()
	a_value := '00000000-0000-4000-8000-000000000001'
	b_value := '00000000-0000-4000-8000-000000000002'
	c_value := '00000000-0000-4000-8000-000000000003'
	a := stable_thread_id(&a_value)
	b := stable_thread_id(&b_value)
	c := stable_thread_id(&c_value)
	owner := fresh_thread_id()
	insert_test_thread(state, &a, now, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, now, os.join_path(state.sqlite.home(), 'workspace-b'))
	insert_test_thread(state, &c, now, os.join_path(state.sqlite.home(), 'workspace-c'))
	assert succeed_output(state, &a, &owner, now - 3 * 86_400, 'summary-a')
	assert succeed_output(state, &b, &owner, now - 2 * 86_400, 'summary-b')
	assert succeed_output(state, &c, &owner, now - 86_400, 'summary-c')
	for fixture in [
		UsageUpdateFixture{ thread_id: clone_thread_id(&a), usage_count: i64(5), last_usage: now - 10 * 86_400 },
		UsageUpdateFixture{ thread_id: clone_thread_id(&b), usage_count: i64(5), last_usage: now - 86_400 },
		UsageUpdateFixture{ thread_id: clone_thread_id(&c), usage_count: i64(1), last_usage: now - 3_600 },
	] {
		sqlx.query('UPDATE stage1_outputs SET usage_count = ?, last_usage = ? WHERE thread_id = ?').bind(fixture.usage_count).bind(fixture.last_usage).bind(fixture.thread_id.value).execute(memory_pool(state))!
	}
	assert state.get_phase2_input_selection( /* n */
	1, /* max_unused_days */
		30)![0].thread_id.value == b.value
}

fn test_get_phase2_input_selection_excludes_stale_used_memories_but_keeps_fresh_never_used() {
	state := new_test_state_runtime()
	now := time.now().unix()
	a_value := '00000000-0000-4000-8000-000000000001'
	b_value := '00000000-0000-4000-8000-000000000002'
	c_value := '00000000-0000-4000-8000-000000000003'
	a := stable_thread_id(&a_value)
	b := stable_thread_id(&b_value)
	c := stable_thread_id(&c_value)
	owner := fresh_thread_id()
	insert_test_thread(state, &a, now, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, now, os.join_path(state.sqlite.home(), 'workspace-b'))
	insert_test_thread(state, &c, now, os.join_path(state.sqlite.home(), 'workspace-c'))
	assert succeed_output(state, &a, &owner, now - 40 * 86_400, 'summary-a')
	assert succeed_output(state, &b, &owner, now - 2 * 86_400, 'summary-b')
	assert succeed_output(state, &c, &owner, now - 50 * 86_400, 'summary-c')
	for fixture in [
		UsageUpdateFixture{ thread_id: clone_thread_id(&a), usage_count: i64(9), last_usage: now - 31 * 86_400 },
		UsageUpdateFixture{ thread_id: clone_thread_id(&b), usage_count: sqlx.Null{}, last_usage: sqlx.Null{} },
		UsageUpdateFixture{ thread_id: clone_thread_id(&c), usage_count: i64(1), last_usage: now - 86_400 },
	] {
		sqlx.query('UPDATE stage1_outputs SET usage_count = ?, last_usage = ? WHERE thread_id = ?').bind(fixture.usage_count).bind(fixture.last_usage).bind(fixture.thread_id.value).execute(memory_pool(state))!
	}
	assert state.get_phase2_input_selection(3, 30)!.map(it.thread_id.value) == [
		b.value,
		c.value,
	]
}

fn test_get_phase2_input_selection_prefers_recent_thread_updates_over_recent_generation() {
	state := new_test_state_runtime()
	older := fresh_thread_id()
	newer := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &older, 100, os.join_path(state.sqlite.home(), 'workspace-older'))
	insert_test_thread(state, &newer, 200, os.join_path(state.sqlite.home(), 'workspace-newer'))
	assert succeed_output(state, &older, &owner, 100, 'summary-older')
	assert succeed_output(state, &newer, &owner, 200, 'summary-newer')
	sqlx.query('UPDATE stage1_outputs SET generated_at = ? WHERE thread_id = ?').bind(i64(300)).bind(older.value.clone()).execute(memory_pool(state))!
	sqlx.query('UPDATE stage1_outputs SET generated_at = ? WHERE thread_id = ?').bind(i64(150)).bind(newer.value.clone()).execute(memory_pool(state))!
	selection := state.get_phase2_input_selection(1, 36_500)!
	assert selection.len == 1
	assert selection[0].thread_id.value == newer.value
	assert selection[0].source_updated_at.unix() == 200
}

fn test_prune_stage1_outputs_for_retention_prunes_stale_unselected_rows_only() {
	state := new_test_state_runtime()
	now := time.now().unix()
	owner := fresh_thread_id()
	stale_unused := fresh_thread_id()
	stale_used := fresh_thread_id()
	stale_selected := fresh_thread_id()
	fresh_used := fresh_thread_id()
	insert_test_thread(state, &stale_unused, now, os.join_path(state.sqlite.home(), 'workspace-stale-unused'))
	insert_test_thread(state, &stale_used, now, os.join_path(state.sqlite.home(), 'workspace-stale-used'))
	insert_test_thread(state, &stale_selected, now, os.join_path(state.sqlite.home(), 'workspace-stale-selected'))
	insert_test_thread(state, &fresh_used, now, os.join_path(state.sqlite.home(), 'workspace-fresh-used'))
	assert succeed_output(state, &stale_unused, &owner, now - 60 * 86_400, 'stale-unused')
	assert succeed_output(state, &stale_used, &owner, now - 50 * 86_400, 'stale-used')
	assert succeed_output(state, &stale_selected, &owner, now - 45 * 86_400, 'stale-selected')
	assert succeed_output(state, &fresh_used, &owner, now - 10 * 86_400, 'fresh-used')
	sqlx.query('UPDATE stage1_outputs SET usage_count = ?, last_usage = ? WHERE thread_id = ?').bind(i64(3)).bind(now - 40 * 86_400).bind(stale_used.value.clone()).execute(memory_pool(state))!
	sqlx.query('UPDATE stage1_outputs SET selected_for_phase2 = 1, selected_for_phase2_source_updated_at = source_updated_at WHERE thread_id = ?').bind(stale_selected.value.clone()).execute(memory_pool(state))!
	sqlx.query('UPDATE stage1_outputs SET usage_count = ?, last_usage = ? WHERE thread_id = ?').bind(i64(8)).bind(now - 2 * 86_400).bind(fresh_used.value.clone()).execute(memory_pool(state))!
	jobs_before := sqlx.query_scalar[i64]("SELECT COUNT(*) FROM jobs WHERE kind = 'memory_stage1'").fetch_one(memory_pool(state))!
	assert state.prune_stage1_outputs_for_retention( /* max_unused_days */
	30, /* limit */
		100)! == 2
	remaining := sqlx.query_scalar[string]('SELECT thread_id FROM stage1_outputs ORDER BY thread_id').fetch_all(memory_pool(state))!
	mut expected := [fresh_used.value.clone(), stale_selected.value.clone()]
	expected.sort()
	assert remaining == expected
	jobs_after := sqlx.query_scalar[i64]("SELECT COUNT(*) FROM jobs WHERE kind = 'memory_stage1'").fetch_one(memory_pool(state))!
	assert jobs_after == jobs_before
}

fn test_prune_stage1_outputs_for_retention_respects_batch_limit() {
	state := new_test_state_runtime()
	now := time.now().unix()
	owner := fresh_thread_id()
	a := fresh_thread_id()
	b := fresh_thread_id()
	c := fresh_thread_id()
	insert_test_thread(state, &a, now, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, now, os.join_path(state.sqlite.home(), 'workspace-b'))
	insert_test_thread(state, &c, now, os.join_path(state.sqlite.home(), 'workspace-c'))
	assert succeed_output(state, &a, &owner, now - 60 * 86_400, 'stale-a')
	assert succeed_output(state, &b, &owner, now - 50 * 86_400, 'stale-b')
	assert succeed_output(state, &c, &owner, now - 40 * 86_400, 'stale-c')
	assert state.prune_stage1_outputs_for_retention(30, 2)! == 2
	remaining_count := sqlx.query_scalar[i64]('SELECT COUNT(*) FROM stage1_outputs').fetch_one(memory_pool(state))!
	assert remaining_count == 1
}

fn test_mark_stage1_job_succeeded_enqueues_global_consolidation() {
	state := new_test_state_runtime()
	a := fresh_thread_id()
	b := fresh_thread_id()
	owner := fresh_thread_id()
	insert_test_thread(state, &a, 100, os.join_path(state.sqlite.home(), 'workspace-a'))
	insert_test_thread(state, &b, 101, os.join_path(state.sqlite.home(), 'workspace-b'))
	token_a := claim_token(state, &a, &owner, 100)
	raw_a := 'raw-a'
	summary_a := 'summary-a'
	assert succeed_output_with_details(state, &a, &token_a, 100, &raw_a, &summary_a, model.borrowed_string_none())
	token_b := claim_token(state, &b, &owner, 101)
	raw_b := 'raw-b'
	summary_b := 'summary-b'
	assert succeed_output_with_details(state, &b, &token_b, 101, &raw_b, &summary_b, model.borrowed_string_none())
	assert state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!.input_watermark == 101
}

fn test_phase2_global_lock_allows_only_one_fresh_runner() {
	state := new_test_state_runtime()
	state.enqueue_global_consolidation(200)!
	assert state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!.kind == .claimed
	assert state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!.kind == .skipped_running
}

fn test_phase2_global_lock_creates_missing_job_row() {
	state := new_test_state_runtime()
	first := state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!
	assert first.kind == .claimed
	assert first.input_watermark == 0
	assert state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!.kind == .skipped_running
	empty := []model.Stage1Output{}
	assert state.mark_global_phase2_job_succeeded(&first.ownership_token, 0, &empty)!
	assert state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!.kind == .skipped_cooldown
}

fn test_phase2_global_lock_stale_lease_allows_takeover() {
	state := new_test_state_runtime()
	state.enqueue_global_consolidation(300)!
	first := state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!
	sqlx.query('UPDATE jobs SET lease_until = ? WHERE kind = ? AND job_key = ?').bind(time.now().unix() - 1).bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).execute(memory_pool(state))!
	second := state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!
	assert second.kind == .claimed
	assert first.ownership_token != second.ownership_token
	assert second.input_watermark == 300
	empty := []model.Stage1Output{}
	assert !state.mark_global_phase2_job_succeeded(&first.ownership_token, 300, &empty)!
	assert state.mark_global_phase2_job_succeeded(&second.ownership_token, 300, &empty)!
}

fn test_enqueue_global_consolidation_keeps_phase2_input_watermark_monotonic() {
	state := new_test_state_runtime()
	state.enqueue_global_consolidation(500)!
	owner_a := fresh_thread_id()
	claim_a := state.try_claim_global_phase2_job(clone_thread_id(&owner_a), 3_600)!
	assert claim_a.kind == .claimed
	assert claim_a.input_watermark == 500
	assert state.mark_global_phase2_job_succeeded(&claim_a.ownership_token, 500, &[]model.Stage1Output{})!
	state.enqueue_global_consolidation(400)!
	age_phase2_success_beyond_cooldown(state)
	owner_b := fresh_thread_id()
	claim_b := state.try_claim_global_phase2_job(clone_thread_id(&owner_b), 3_600)!
	assert claim_b.kind == .claimed
	assert claim_b.input_watermark > 500
}

fn test_phase2_failure_fallback_updates_unowned_running_job() {
	state := new_test_state_runtime()
	reason := 'lost'
	state.enqueue_global_consolidation(400)!
	claim := state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!
	sqlx.query('UPDATE jobs SET ownership_token = NULL WHERE kind = ? AND job_key = ?').bind(job_kind_memory_consolidate_global).bind(memory_consolidation_job_key).execute(memory_pool(state))!
	assert !state.mark_global_phase2_job_failed(&claim.ownership_token, &reason, /* retry_delay_seconds */
		3_600)!
	assert state.mark_global_phase2_job_failed_if_unowned(&claim.ownership_token, &reason, 3_600)!
	assert state.try_claim_global_phase2_job(fresh_thread_id(), 3_600)!.kind == .skipped_retry_unavailable
}

fn owned_string_for_memories_test(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_datetime_from_epoch_seconds_matches_chrono_bounds() {
	minimum := i64(-8_334_601_228_800)
	maximum := i64(8_210_266_876_799)
	assert datetime_from_epoch_seconds(minimum)!.unix() == minimum
	assert datetime_from_epoch_seconds(maximum)!.unix() == maximum
	if _ := datetime_from_epoch_seconds(minimum - 1) {
		assert false, 'timestamp below Chrono minimum must fail'
	} else {
		assert err.msg() == 'invalid unix timestamp: -8334601228801'
	}
	if _ := datetime_from_epoch_seconds(maximum + 1) {
		assert false, 'timestamp above Chrono maximum must fail'
	} else {
		assert err.msg() == 'invalid unix timestamp: 8210266876800'
	}
}

fn test_borrowed_memory_apis_preserve_owners() {
	state := new_test_state_runtime()
	allowed_source := owned_string_for_memories_test('cli')
	allowed_sources := [allowed_source]
	for _ in 0 .. 2 {
		assert state.claim_stage1_jobs_for_startup(fresh_thread_id(), model.Stage1StartupClaimParams{
			scan_limit:             1
			max_claimed:            1
			max_age_days:           30
			min_rollout_idle_hours: 12
			allowed_sources:        model.borrowed_strings(&allowed_sources)
			lease_seconds:          3_600
		})!.len == 0
	}
	assert allowed_sources[0] == 'cli'

	owner := fresh_thread_id()
	state.enqueue_global_consolidation(1)!
	claim := state.try_claim_global_phase2_job(clone_thread_id(&owner), 3_600)!
	token := owned_string_for_memories_test(claim.ownership_token)
	assert state.memories.heartbeat_global_phase2_job(&token, 3_600)!
	assert state.memories.heartbeat_global_phase2_job(&token, 3_600)!
	assert token.len > 0

	id := fresh_thread_id()
	worker := fresh_thread_id()
	stage1_token := claim_token(state, &id, &worker, 10)
	raw := owned_string_for_memories_test('raw memory')
	summary := owned_string_for_memories_test('summary')
	rollout_slug := owned_string_for_memories_test('rollout-slug')
	borrowed_rollout_slug := model.borrowed_string_some(&rollout_slug)
	assert state.mark_stage1_job_succeeded(clone_thread_id(&id), &stage1_token, 10, &raw, &summary, borrowed_rollout_slug)!
	assert raw == 'raw memory'
	assert summary == 'summary'
	assert rollout_slug == 'rollout-slug'
	ids := [clone_thread_id(&id)]
	assert state.record_stage1_output_usage(&ids)! == 1
	assert state.record_stage1_output_usage(&ids)! == 1
	assert ids[0].value == id.value
}
