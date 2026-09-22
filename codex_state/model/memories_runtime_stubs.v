module model

import codex_protocol
import codex_protocol as protocol_types
import codex_protocol.openai_models
import codex_protocol.thread_id
import json2
import sqlx
import time

// STUB: MIN_EPOCH_MILLIS is owned by state/src/model/thread_metadata.rs.
const min_epoch_millis = i64(1_577_836_800_000)

// STUB: OptionalThreadId represents Rust Option<ThreadId> in pagination anchors.
pub struct OptionalThreadId {
pub:
	has_value bool
	value     codex_protocol.ThreadId
}

// STUB: Anchor is owned by state/src/model/thread_metadata.rs.
pub struct Anchor {
pub:
	ts time.Time
	id OptionalThreadId
}

// STUB: ThreadMetadata is owned by state/src/model/thread_metadata.rs; this target-specific
// declaration preserves all fields of the canonical persisted model.
pub struct ThreadMetadata {
pub mut:
	originator         OptionalString
	id                 codex_protocol.ThreadId
	rollout_path       string
	created_at         time.Time
	updated_at         time.Time
	recency_at         time.Time
	source             string = 'cli'
	history_mode       protocol_types.ThreadHistoryMode
	thread_source      OptionalThreadSource
	agent_nickname     OptionalString
	agent_role         OptionalString
	agent_path         OptionalString
	model_provider     string
	model              OptionalString
	reasoning_effort   OptionalReasoningEffort
	cwd                string
	cli_version        string
	title              string
	name               OptionalString
	preview            OptionalString
	sandbox_policy     string
	approval_mode      string
	tokens_used        i64
	first_user_message OptionalString
	archived_at        OptionalTime
	section            OptionalThreadSection
	section_position   OptionalI64
	section_entered_at OptionalTime
	project_id         OptionalString
	daybreak_enabled   OptionalBool
	git_sha            OptionalString
	git_branch         OptionalString
	git_origin_url     OptionalSanitizedGitUrl
}

// STUB: clone_thread_metadata mirrors ThreadMetadata's derived Clone boundary.
pub fn clone_thread_metadata(item &ThreadMetadata) ThreadMetadata {
	return ThreadMetadata{
		originator:         clone_optional_string(&item.originator)
		id:                 codex_protocol.ThreadId{
			value: item.id.value.clone()
		}
		rollout_path:       item.rollout_path.clone()
		created_at:         item.created_at
		updated_at:         item.updated_at
		recency_at:         item.recency_at
		source:             item.source.clone()
		history_mode:       item.history_mode
		thread_source:      clone_optional_thread_source(&item.thread_source)
		agent_nickname:     clone_optional_string(&item.agent_nickname)
		agent_role:         clone_optional_string(&item.agent_role)
		agent_path:         clone_optional_string(&item.agent_path)
		model_provider:     item.model_provider.clone()
		model:              clone_optional_string(&item.model)
		reasoning_effort:   clone_optional_reasoning_effort(&item.reasoning_effort)
		cwd:                item.cwd.clone()
		cli_version:        item.cli_version.clone()
		title:              item.title.clone()
		name:               clone_optional_string(&item.name)
		preview:            clone_optional_string(&item.preview)
		sandbox_policy:     item.sandbox_policy.clone()
		approval_mode:      item.approval_mode.clone()
		tokens_used:        item.tokens_used
		first_user_message: clone_optional_string(&item.first_user_message)
		archived_at:        item.archived_at
		section:            clone_optional_thread_section(&item.section)
		section_position:   item.section_position
		section_entered_at: item.section_entered_at
		project_id:         clone_optional_string(&item.project_id)
		daybreak_enabled:   item.daybreak_enabled
		git_sha:            clone_optional_string(&item.git_sha)
		git_branch:         clone_optional_string(&item.git_branch)
		git_origin_url:     clone_optional_sanitized_git_url(&item.git_origin_url)
	}
}

// STUB: OptionalString represents owned Rust Option<String> fields until the shared state model
// module is translated.
pub struct OptionalString {
pub:
	has_value bool
	value     string
}

// STUB: some_string constructs the owned Option<String> representation.
pub fn some_string(value string) OptionalString {
	return OptionalString{
		has_value: true
		value:     value
	}
}

// STUB: clone_optional_string performs the clone required when an owned result is assembled from
// a borrowed state row.
pub fn clone_optional_string(value &OptionalString) OptionalString {
	return OptionalString{
		has_value: value.has_value
		value:     value.value.clone()
	}
}

// STUB: OptionalI64 represents an owned Rust Option<i64> model field.
pub struct OptionalI64 {
pub:
	has_value bool
	value     i64
}

// STUB: some_i64 constructs the owned Option<i64> representation.
pub fn some_i64(value i64) OptionalI64 {
	return OptionalI64{
		has_value: true
		value:     value
	}
}

// STUB: OptionalBool represents an owned Rust Option<bool> model field.
pub struct OptionalBool {
pub:
	has_value bool
	value     bool
}

// STUB: some_bool constructs the owned Option<bool> representation.
pub fn some_bool(value bool) OptionalBool {
	return OptionalBool{
		has_value: true
		value:     value
	}
}

// STUB: OptionalTime represents an owned Rust Option<DateTime<Utc>> model field.
pub struct OptionalTime {
pub:
	has_value bool
	value     time.Time
}

// STUB: some_time constructs the owned Option<DateTime<Utc>> representation.
pub fn some_time(value time.Time) OptionalTime {
	return OptionalTime{
		has_value: true
		value:     value
	}
}

// STUB: OptionalThreadSource represents an owned Rust Option<ThreadSource> model field.
pub struct OptionalThreadSource {
pub:
	has_value bool
	value     protocol_types.ThreadSource
}

// STUB: clone_optional_thread_source mirrors cloning Option<ThreadSource>.
pub fn clone_optional_thread_source(value &OptionalThreadSource) OptionalThreadSource {
	return OptionalThreadSource{
		has_value: value.has_value
		value:     protocol_types.ThreadSource{
			source_kind: value.value.source_kind
			feature:     value.value.feature.clone()
		}
	}
}

// STUB: OptionalReasoningEffort is the explicit tagged V representation of Rust
// Option<ReasoningEffort>; `custom` retains the payload of ReasoningEffort::Custom.
pub struct OptionalReasoningEffort {
pub:
	has_value bool
	value     openai_models.ReasoningEffort
	custom    string
}

// STUB: clone_optional_reasoning_effort mirrors cloning Option<ReasoningEffort> including the
// payload-bearing custom variant.
pub fn clone_optional_reasoning_effort(value &OptionalReasoningEffort) OptionalReasoningEffort {
	return OptionalReasoningEffort{
		has_value: value.has_value
		value:     value.value
		custom:    value.custom.clone()
	}
}

// STUB: ThreadSectionAppearance is owned by state/src/model/thread_metadata.rs.
pub struct ThreadSectionAppearance {
pub:
	icon  OptionalString
	color OptionalString
}

// STUB: ThreadSection is owned by state/src/model/thread_metadata.rs.
pub struct ThreadSection {
pub:
	id         string
	name       string
	appearance OptionalThreadSectionAppearance
}

// STUB: OptionalThreadSectionAppearance represents Rust Option<ThreadSectionAppearance>.
pub struct OptionalThreadSectionAppearance {
pub:
	has_value bool
	value     ThreadSectionAppearance
}

// STUB: OptionalThreadSection represents Rust Option<ThreadSection>.
pub struct OptionalThreadSection {
pub:
	has_value bool
	value     ThreadSection
}

// STUB: clone_optional_thread_section mirrors cloning Option<ThreadSection>.
pub fn clone_optional_thread_section(value &OptionalThreadSection) OptionalThreadSection {
	return OptionalThreadSection{
		has_value: value.has_value
		value:     ThreadSection{
			id:         value.value.id.clone()
			name:       value.value.name.clone()
			appearance: OptionalThreadSectionAppearance{
				has_value: value.value.appearance.has_value
				value:     ThreadSectionAppearance{
					icon:  clone_optional_string(&value.value.appearance.value.icon)
					color: clone_optional_string(&value.value.appearance.value.color)
				}
			}
		}
	}
}

// STUB: OptionalSanitizedGitUrl represents Rust Option<SanitizedGitUrl>.
pub struct OptionalSanitizedGitUrl {
pub:
	has_value bool
	value     codex_protocol.SanitizedGitUrl
}

// STUB: clone_optional_sanitized_git_url mirrors cloning Option<SanitizedGitUrl>.
pub fn clone_optional_sanitized_git_url(value &OptionalSanitizedGitUrl) OptionalSanitizedGitUrl {
	return OptionalSanitizedGitUrl{
		has_value: value.has_value
		value:     codex_protocol.SanitizedGitUrl{
			value: value.value.value.clone()
		}
	}
}

// STUB: ThreadRow is the raw SQLite row owned by state/src/model/thread_metadata.rs.
pub struct ThreadRow {
pub:
	originator            sqlx.OptionalString
	id                    string
	rollout_path          string
	created_at            i64
	updated_at            i64
	recency_at            i64
	source                string
	history_mode          string
	thread_source         sqlx.OptionalString
	agent_nickname        sqlx.OptionalString
	agent_role            sqlx.OptionalString
	agent_path            sqlx.OptionalString
	model_provider        string
	model                 sqlx.OptionalString
	reasoning_effort      sqlx.OptionalString
	cwd                   string
	cli_version           string
	title                 string
	name                  sqlx.OptionalString
	preview               string
	sandbox_policy        string
	approval_mode         string
	tokens_used           i64
	first_user_message    string
	archived_at           sqlx.OptionalI64
	section               sqlx.OptionalString
	section_name          sqlx.OptionalString
	section_appearance    sqlx.OptionalString
	section_position      sqlx.OptionalI64
	section_entered_at_ms sqlx.OptionalI64
	project_id            sqlx.OptionalString
	daybreak_enabled      sqlx.OptionalI64
	git_sha               sqlx.OptionalString
	git_branch            sqlx.OptionalString
	git_origin_url        sqlx.OptionalString
}

// STUB: try_from_row mirrors ThreadRow::try_from_row and preserves each typed Row::try_get call.
pub fn ThreadRow.try_from_row(row &sqlx.Row) !ThreadRow {
	return ThreadRow{
		originator:            row.try_get[sqlx.OptionalString]('originator')!
		id:                    row.try_get[string]('id')!
		rollout_path:          row.try_get[string]('rollout_path')!
		created_at:            row.try_get[i64]('created_at')!
		updated_at:            row.try_get[i64]('updated_at')!
		recency_at:            row.try_get[i64]('recency_at')!
		source:                row.try_get[string]('source')!
		history_mode:          row.try_get[string]('history_mode')!
		thread_source:         row.try_get[sqlx.OptionalString]('thread_source')!
		agent_nickname:        row.try_get[sqlx.OptionalString]('agent_nickname')!
		agent_role:            row.try_get[sqlx.OptionalString]('agent_role')!
		agent_path:            row.try_get[sqlx.OptionalString]('agent_path')!
		model_provider:        row.try_get[string]('model_provider')!
		model:                 row.try_get[sqlx.OptionalString]('model')!
		reasoning_effort:      row.try_get[sqlx.OptionalString]('reasoning_effort')!
		cwd:                   row.try_get[string]('cwd')!
		cli_version:           row.try_get[string]('cli_version')!
		title:                 row.try_get[string]('title')!
		name:                  row.try_get[sqlx.OptionalString]('name')!
		preview:               row.try_get[string]('preview')!
		sandbox_policy:        row.try_get[string]('sandbox_policy')!
		approval_mode:         row.try_get[string]('approval_mode')!
		tokens_used:           row.try_get[i64]('tokens_used')!
		first_user_message:    row.try_get[string]('first_user_message')!
		archived_at:           row.try_get[sqlx.OptionalI64]('archived_at')!
		section:               row.try_get[sqlx.OptionalString]('section')!
		section_name:          row.try_get[sqlx.OptionalString]('section_name')!
		section_appearance:    row.try_get[sqlx.OptionalString]('section_appearance')!
		section_position:      row.try_get[sqlx.OptionalI64]('section_position')!
		section_entered_at_ms: row.try_get[sqlx.OptionalI64]('section_entered_at_ms')!
		project_id:            row.try_get[sqlx.OptionalString]('project_id')!
		daybreak_enabled:      row.try_get[sqlx.OptionalI64]('daybreak_enabled')!
		git_sha:               row.try_get[sqlx.OptionalString]('git_sha')!
		git_branch:            row.try_get[sqlx.OptionalString]('git_branch')!
		git_origin_url:        row.try_get[sqlx.OptionalString]('git_origin_url')!
	}
}

// STUB: ThreadSectionAppearanceWire is the serde JSON shape for persisted section appearance.
struct ThreadSectionAppearanceWire {
	icon  ?string
	color ?string
}

// STUB: optional_string_from_sqlx converts a nullable SQL string into the owned model option.
fn optional_string_from_sqlx(value sqlx.OptionalString) OptionalString {
	if value.has_value {
		return some_string(value.value)
	}
	return OptionalString{}
}

// STUB: optional_section_from_row preserves ThreadSection::from_row validation and JSON parsing.
fn optional_section_from_row(id sqlx.OptionalString, name sqlx.OptionalString, appearance sqlx.OptionalString) !OptionalThreadSection {
	if id.has_value && name.has_value {
		mut parsed_appearance := OptionalThreadSectionAppearance{}
		if appearance.has_value {
			wire := json2.decode[ThreadSectionAppearanceWire](appearance.value)!
			parsed_appearance = OptionalThreadSectionAppearance{
				has_value: true
				value:     ThreadSectionAppearance{
					icon:  if icon := wire.icon { some_string(icon) } else { OptionalString{} }
					color: if color := wire.color { some_string(color) } else { OptionalString{} }
				}
			}
		}
		return OptionalThreadSection{
			has_value: true
			value:     ThreadSection{
				id:         id.value
				name:       name.value
				appearance: parsed_appearance
			}
		}
	}
	if id.has_value {
		return error('thread references an unknown section: ${id.value}')
	}
	if name.has_value {
		return error('thread has a section name without a section id: ${name.value}')
	}
	return OptionalThreadSection{}
}

// STUB: epoch_millis_to_datetime mirrors the state model's legacy-seconds compatibility rule and
// chrono DateTime<Utc> range validation.
fn epoch_millis_to_datetime(value i64) !time.Time {
	mut millis := value
	if value < min_epoch_millis {
		millis = saturating_multiply_by_1000(value)
	}
	if millis < i64(-8_334_601_228_800_000) || millis > i64(8_210_266_876_799_999) {
		return error('invalid unix timestamp millis: ${value}')
	}
	return time.unix_milli(millis)
}

// STUB: epoch_seconds_to_datetime mirrors DateTime::<Utc>::from_timestamp validation.
fn epoch_seconds_to_datetime(value i64) !time.Time {
	if value < i64(-8_334_601_228_800) || value > i64(8_210_266_876_799) {
		return error('invalid unix timestamp seconds: ${value}')
	}
	return time.unix(value)
}

// STUB: saturating_multiply_by_1000 mirrors i64::saturating_mul used for legacy timestamps.
fn saturating_multiply_by_1000(value i64) i64 {
	if value > i64(9_223_372_036_854_775) {
		return i64(9_223_372_036_854_775_807)
	}
	if value < i64(-9_223_372_036_854_775) {
		return i64(-9_223_372_036_854_775_808)
	}
	return value * 1_000
}

// STUB: try_from mirrors TryFrom<ThreadRow> for ThreadMetadata.
pub fn ThreadMetadata.try_from(row ThreadRow) !ThreadMetadata {
	history_mode := protocol_types.thread_history_mode_from_str(&row.history_mode)!
	section := optional_section_from_row(row.section, row.section_name, row.section_appearance)!
	mut thread_source := OptionalThreadSource{}
	if row.thread_source.has_value {
		thread_source = OptionalThreadSource{
			has_value: true
			value:     protocol_types.thread_source_from_str(&row.thread_source.value)
		}
	}
	mut reasoning_effort := OptionalReasoningEffort{}
	if row.reasoning_effort.has_value {
		if parsed := openai_models.reasoning_effort_from_str(&row.reasoning_effort.value) {
			reasoning_effort = OptionalReasoningEffort{
				has_value: true
				value:     parsed
				custom:    if parsed == .custom { row.reasoning_effort.value.clone() } else { '' }
			}
		}
	}
	mut archived_at := OptionalTime{}
	if row.archived_at.has_value {
		archived_at = some_time(epoch_seconds_to_datetime(row.archived_at.value)!)
	}
	mut section_entered_at := OptionalTime{}
	if row.section_entered_at_ms.has_value {
		section_entered_at = some_time(epoch_millis_to_datetime(row.section_entered_at_ms.value)!)
	}
	mut git_origin_url := OptionalSanitizedGitUrl{}
	if row.git_origin_url.has_value {
		if origin := codex_protocol.SanitizedGitUrl.try_from(row.git_origin_url.value) {
			git_origin_url = OptionalSanitizedGitUrl{
				has_value: true
				value:     origin
			}
		}
	}
	return ThreadMetadata{
		originator:         optional_string_from_sqlx(row.originator)
		id:                 thread_id.from_string(&row.id)!
		rollout_path:       row.rollout_path
		created_at:         epoch_millis_to_datetime(row.created_at)!
		updated_at:         epoch_millis_to_datetime(row.updated_at)!
		recency_at:         epoch_millis_to_datetime(row.recency_at)!
		source:             row.source
		history_mode:       history_mode
		thread_source:      thread_source
		agent_nickname:     optional_string_from_sqlx(row.agent_nickname)
		agent_role:         optional_string_from_sqlx(row.agent_role)
		agent_path:         optional_string_from_sqlx(row.agent_path)
		model_provider:     row.model_provider
		model:              optional_string_from_sqlx(row.model)
		reasoning_effort:   reasoning_effort
		cwd:                row.cwd
		cli_version:        row.cli_version
		title:              row.title
		name:               optional_string_from_sqlx(row.name)
		preview:            if row.preview.len > 0 {
			some_string(row.preview)
		} else {
			OptionalString{}
		}
		sandbox_policy:     row.sandbox_policy
		approval_mode:      row.approval_mode
		tokens_used:        row.tokens_used
		first_user_message: if row.first_user_message.len > 0 {
			some_string(row.first_user_message)
		} else {
			OptionalString{}
		}
		archived_at:        archived_at
		section:            section
		section_position:   if row.section_position.has_value {
			some_i64(row.section_position.value)
		} else {
			OptionalI64{}
		}
		section_entered_at: section_entered_at
		project_id:         optional_string_from_sqlx(row.project_id)
		daybreak_enabled:   if row.daybreak_enabled.has_value {
			some_bool(row.daybreak_enabled.value != 0)
		} else {
			OptionalBool{}
		}
		git_sha:            optional_string_from_sqlx(row.git_sha)
		git_branch:         optional_string_from_sqlx(row.git_branch)
		git_origin_url:     git_origin_url
	}
}

// STUB: OptionalBorrowedString is the safe V representation of Rust Option<&str>. It is
// allocation-free and copy-equivalent.
pub struct OptionalBorrowedString {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

// STUB: borrowed_string_some constructs the Option<&str> representation without taking ownership.
pub fn borrowed_string_some(value &string) OptionalBorrowedString {
	return unsafe {
		OptionalBorrowedString{
			has_value: true
			value:     value
		}
	}
}

// STUB: borrowed_string_none constructs None for an Option<&str> argument.
pub fn borrowed_string_none() OptionalBorrowedString {
	return OptionalBorrowedString{}
}

// STUB: Stored stage-1 memory extraction output is owned by state/src/model/memories.rs.
pub struct Stage1Output {
pub:
	thread_id         codex_protocol.ThreadId
	rollout_path      string
	source_updated_at time.Time
	raw_memory        string
	rollout_summary   string
	rollout_slug      OptionalString
	cwd               string
	git_branch        OptionalString
	generated_at      time.Time
}

// STUB: clone_stage1_output preserves the source model's Clone boundary.
pub fn clone_stage1_output(output &Stage1Output) Stage1Output {
	return Stage1Output{
		thread_id:         codex_protocol.ThreadId{
			value: output.thread_id.value.clone()
		}
		rollout_path:      output.rollout_path.clone()
		source_updated_at: output.source_updated_at
		raw_memory:        output.raw_memory.clone()
		rollout_summary:   output.rollout_summary.clone()
		rollout_slug:      clone_optional_string(&output.rollout_slug)
		cwd:               output.cwd.clone()
		git_branch:        clone_optional_string(&output.git_branch)
		generated_at:      output.generated_at
	}
}

// STUB: The payload-bearing Stage1JobClaimOutcome enum is owned by
// state/src/model/memories.rs.
pub enum Stage1JobClaimOutcomeKind {
	claimed
	skipped_up_to_date
	skipped_running
	skipped_retry_backoff
	skipped_retry_exhausted
}

// STUB: V uses an explicit tag and payload to preserve every Rust enum variant.
pub struct Stage1JobClaimOutcome {
pub:
	kind            Stage1JobClaimOutcomeKind
	ownership_token string
}

// STUB: Claimed stage-1 job metadata is owned by state/src/model/memories.rs.
pub struct Stage1JobClaim {
pub:
	thread          ThreadMetadata
	ownership_token string
}

// STUB: BorrowedStrings is the allocation-free V projection of Rust's `&[String]`. V 0.5.2
// rejects `&[]string` struct fields, so this keeps a pointer and length for the synchronous borrow.
pub struct BorrowedStrings {
pub:
	data &string = unsafe { nil }
	len  int
}

// STUB: borrowed_strings constructs a borrowed slice without cloning or taking its array owner.
pub fn borrowed_strings(values &[]string) BorrowedStrings {
	return unsafe {
		BorrowedStrings{
			data: if values.len == 0 { nil } else { &(*values)[0] }
			len:  values.len
		}
	}
}

// STUB: contains provides the source slice membership operation used by thread filtering.
pub fn (values BorrowedStrings) contains(value &string) bool {
	unsafe {
		for index in 0 .. values.len {
			candidate := values.data[index]
			if candidate.len == value.len && vmemcmp(candidate.str, value.str, candidate.len) == 0 {
				return true
			}
		}
	}
	return false
}

// STUB: Stage1StartupClaimParams is owned by state/src/model/memories.rs. The source slice remains
// borrowed through the allocation-free BorrowedStrings projection above.
pub struct Stage1StartupClaimParams {
pub:
	scan_limit             usize
	max_claimed            usize
	max_age_days           i64
	min_rollout_idle_hours i64
	allowed_sources        BorrowedStrings
	lease_seconds          i64
}

// STUB: The payload-bearing Phase2JobClaimOutcome enum is owned by
// state/src/model/memories.rs.
pub enum Phase2JobClaimOutcomeKind {
	claimed
	skipped_retry_unavailable
	skipped_cooldown
	skipped_running
}

// STUB: V uses an explicit tag and payload to preserve every Rust enum variant.
pub struct Phase2JobClaimOutcome {
pub:
	kind            Phase2JobClaimOutcomeKind
	ownership_token string
	// Snapshot of `input_watermark` at claim time.
	input_watermark i64
}
