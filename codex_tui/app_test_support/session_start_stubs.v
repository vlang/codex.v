module app_test_support

import codex_protocol
import os
import serde_json
import std_ffi
import std_path
import time
import uuid

// STUB: app-server/tests/common/rollout.rs::rollout_path retains the borrowed inputs
// and the exact sessions/YYYY/MM/DD/rollout-{timestamp}-{thread_id}.jsonl layout.
pub fn rollout_path(codex_home &std_path.Path, filename_ts &string, id &string) std_path.PathBuf {
	return std_path.PathBuf.from(os.join_path(codex_home.to_path_buf(), 'sessions', (*filename_ts)[0..4], (*filename_ts)[5..7], (*filename_ts)[8..10], 'rollout-${*filename_ts}-${*id}.jsonl'))
}

// STUB: app-server/tests/common/rollout.rs::create_fake_rollout supplies the exact
// three-line CLI/legacy fixture used by session_start_tests.rs. The borrowed provider
// wrapper retains Option<&str>; no archived server or model execution is simulated here.
// Create a minimal rollout file under CODEX_HOME/sessions/YYYY/MM/DD/.
//
// - filename_ts is the filename timestamp component in YYYY-MM-DDThh-mm-ss format.
// - meta_rfc3339 is the envelope timestamp used in JSON lines.
// - preview is the user message preview text.
// - model_provider optionally sets the provider in the session meta payload.
//
// Returns the generated conversation/session UUID as a string.
pub fn create_fake_rollout(codex_home &std_path.Path, filename_ts &string, meta_rfc3339 &string, preview &string, model_provider std_ffi.BorrowedUtf8, git_info ?codex_protocol.GitInfo) !string {
	id := uuid.Uuid.new_v4().str()
	path := rollout_path(codex_home, filename_ts, &id)
	filename := path.as_path().to_path_buf()
	os.mkdir_all(os.dir(filename.clone()))!
	// Build JSONL lines
	mut metadata := {
		'session_id':        serde_json.Value.string(id.clone())
		'id':                serde_json.Value.string(id.clone())
		'timestamp':         serde_json.Value.string(meta_rfc3339.clone())
		'cwd':               serde_json.Value.string('/')
		'originator':        serde_json.Value.string('codex')
		'cli_version':       serde_json.Value.string('0.0.0')
		'source':            serde_json.Value.string('cli')
		'model_provider':    if model_provider.present {
			serde_json.Value.string(model_provider.value.clone())
		} else {
			serde_json.Value{}
		}
		'base_instructions': serde_json.Value{}
		'history_mode':      serde_json.Value.string('legacy')
	}
	if git := git_info {
		mut details := map[string]serde_json.Value{}
		if sha := git.commit_hash {
			details['commit_hash'] = serde_json.Value.string(sha.value.clone())
		}
		if branch := git.branch { details['branch'] = serde_json.Value.string(branch.clone()) }
		if url := git.repository_url {
			details['repository_url'] = serde_json.Value.string(url.value.clone())
		}
		metadata['git'] = serde_json.Value.object(details)
	}
	// Name the consumed metadata before borrowing its serialized envelope. V's
	// ownership checker otherwise evaluates a chained constructor receiver twice.
	meta_payload := serde_json.Value.object(metadata)
	meta_envelope := serde_json.Value.object({
		'timestamp': serde_json.Value.string(meta_rfc3339.clone())
		'type':      serde_json.Value.string('session_meta')
		'payload':   meta_payload
	})
	meta_line := meta_envelope.to_string()
	lines := [
		meta_line,
		serde_json.Value.object({
			'timestamp': serde_json.Value.string(meta_rfc3339.clone())
			'type':      serde_json.Value.string('response_item')
			'payload':   serde_json.Value.object({
				'type':    serde_json.Value.string('message')
				'role':    serde_json.Value.string('user')
				'content': serde_json.Value.array_value([serde_json.Value.object({
					'type': serde_json.Value.string('input_text')
					'text': serde_json.Value.string(preview.clone())
				})])
			})
		}).to_string(),
		serde_json.Value.object({
			'timestamp': serde_json.Value.string(meta_rfc3339.clone())
			'type':      serde_json.Value.string('event_msg')
			'payload':   serde_json.Value.object({
				'type':    serde_json.Value.string('user_message')
				'message': serde_json.Value.string(preview.clone())
				'kind':    serde_json.Value.string('plain')
			})
		}).to_string(),
	]
	os.write_file(filename.clone(), lines.join('\n') + '\n')!
	// V's timestamp parser and native filesystem API consume string values; own only
	// those dependency-boundary copies while the original source inputs remain borrowed.
	parsed := time.parse_rfc3339(meta_rfc3339.clone())!
	stat := os.stat(filename.clone())!
	os.utime(filename, stat.atime, parsed.unix())!
	return id
}
