module model

import codex_protocol
import time

// STUB: state/src/model/thread_metadata.rs::ThreadMetadataBuilder fields observed
// by named_session_lookup_tests.rs; the full builder remains untranslated.
pub struct ThreadMetadataBuilder {
pub mut:
	id           codex_protocol.ThreadId
	rollout_path string
	created_at   time.Time
	source       codex_protocol.SessionSource
	cwd          string
}

// STUB: ThreadMetadataBuilder::new consumes ID/path/source and keeps the timestamp.
pub fn ThreadMetadataBuilder.new(id codex_protocol.ThreadId, rollout_path string, created_at time.Time, source codex_protocol.SessionSource) ThreadMetadataBuilder {
	return ThreadMetadataBuilder{ id: id, rollout_path: rollout_path, created_at: created_at, source: source }
}

// STUB: ThreadMetadataBuilder::build provides canonical metadata defaults for the
// exact source test setup; timestamps retain the original 2025-02-01 oracle.
pub fn (builder &ThreadMetadataBuilder) build(default_provider &string) ThreadMetadata {
	return ThreadMetadata{ id: codex_protocol.ThreadId{ value: builder.id.value.clone() }, rollout_path: builder.rollout_path.clone(), created_at: builder.created_at, updated_at: builder.created_at, recency_at: builder.created_at, source: builder.source.str().clone(), history_mode: .legacy, cwd: builder.cwd.clone(), model_provider: default_provider.clone(), sandbox_policy: '{"type":"read-only"}', approval_mode: 'on-request' }
}
