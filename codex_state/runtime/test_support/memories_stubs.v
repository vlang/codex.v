module test_support

import codex_protocol
import codex_protocol.openai_models
import codex_state.model
import os
import rand
import time

// STUB: unique_temp_dir is owned by state/src/runtime/test_support.rs.
pub fn unique_temp_dir() string {
	return os.join_path(os.temp_dir(), 'codex-state-runtime-test-${time.now().unix_nano()}-${rand.uuid_v4()}')
}

// STUB: test_thread_metadata is owned by state/src/runtime/test_support.rs and preserves its full
// canonical fixture.
pub fn test_thread_metadata(codex_home &string, thread_id codex_protocol.ThreadId, cwd string) model.ThreadMetadata {
	now := time.unix(1_700_000_000)
	rollout_path := os.join_path(*codex_home, 'rollout-${thread_id.value}.jsonl')
	return model.ThreadMetadata{
		id:                 thread_id
		rollout_path:       rollout_path
		created_at:         now
		updated_at:         now
		recency_at:         now
		source:             'cli'
		history_mode:       .legacy
		model_provider:     'test-provider'
		model:              model.some_string('gpt-5')
		reasoning_effort:   model.OptionalReasoningEffort{
			has_value: true
			value:     openai_models.ReasoningEffort.medium
		}
		cwd:                cwd
		cli_version:        '0.0.0'
		preview:            model.some_string('hello')
		sandbox_policy:     'read-only'
		approval_mode:      'on-request'
		first_user_message: model.some_string('hello')
	}
}
