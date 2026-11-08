module named_session_lookup

import codex_app_server_client
import codex_app_server_protocol
import codex_core
import codex_protocol
import codex_protocol.thread_id
import codex_state.model
import codex_state.runtime
import codex_state.sqlite
import codex_tui
import color_eyre.eyre
import os
import serde_json
import std_path
import time
import uuid

// Rust TempDir drops remove the directory; V tests explicitly defer cleanup.
struct TempDir {
	path string
}

fn TempDir.new() !TempDir {
	path := os.join_path(os.temp_dir(), 'codex-named-session-${uuid.Uuid.new_v4()}')
	os.mkdir_all(path)!
	return TempDir{ path: path }
}

fn build_config(temp_dir &TempDir) !codex_core.Config {
	initial_builder := codex_core.ConfigBuilder.default()
	home_builder := initial_builder.codex_home(temp_dir.path.clone())
	return home_builder.build()!
}

fn state_runtime(config &codex_core.Config) !&runtime.StateRuntime {
	state := runtime.StateRuntime.init(sqlite.SqliteConfig.new_for_testing(config.codex_home.clone()), config.model_provider_id.clone())!
	state.mark_backfill_complete( /*last_watermark*/
	none)!
	// The native SQLite transport is untranslated; register this exact upserted
	// runtime so independently started embedded fixtures share the same state.
	state.register_named_session_fixture()
	return state
}

fn lookup_name(config &codex_core.Config, name &string, collections &[]SessionCollection, mode codex_tui.ThreadParamsMode, model_provider &BorrowedModelProvider) !OptionalThread {
	handle := codex_tui.start_test_embedded_app_server(config.clone())!
	mut app_server := codex_tui.AppServerSession.new(handle, mode)
	home_path := std_path.Path.new(&config.codex_home)
	source_kinds := [codex_tui.resume_source_kinds( /*include_non_interactive*/
	false)]
	target := lookup(mut app_server, &home_path, name, collections, &source_kinds, model_provider)!
	app_server.shutdown()!
	return target
}

fn upsert_thread(state &runtime.StateRuntime, metadata model.ThreadMetadata) ! {
	state.upsert_thread(&metadata)!
}

fn thread_metadata(config &codex_core.Config, id codex_protocol.ThreadId, rollout_path string, title &string) model.ThreadMetadata {
	created_at := time.parse_rfc3339('2025-02-01T10:00:00Z') or { panic('timestamp should parse') }
	mut builder := model.ThreadMetadataBuilder.new(id, rollout_path, created_at, codex_protocol.SessionSource{ source_kind: .cli })
	builder.cwd = os.join_path(config.codex_home, 'project')
	mut metadata := builder.build(&config.model_provider_id)
	metadata.title = title.clone()
	metadata.first_user_message = model.some_string('preview text')
	metadata.preview = model.some_string(metadata.first_user_message.value.clone())
	return metadata
}

fn write_rollout(config &codex_core.Config, id codex_protocol.ThreadId, timestamp &string, preview &string, source codex_protocol.SessionSource, history_mode codex_protocol.ThreadHistoryMode) !string {
	rollout_path := os.join_path(config.codex_home, 'sessions/2025/02/01', 'rollout-2025-02-01T10-00-00-${id}.jsonl')
	os.mkdir_all(os.dir(rollout_path))!
	session_meta := codex_protocol.SessionMetaLine{
		meta: codex_protocol.SessionMeta{
			session_id:     codex_protocol.SessionId{ value: id.value.clone() }
			id:             id
			timestamp:      timestamp.clone()
			cwd:            os.join_path(config.codex_home, 'project')
			originator:     'codex'
			cli_version:    '0.0.0'
			source:         source
			model_provider: config.model_provider_id.clone()
			history_mode:   history_mode
		}
		git:  none
	}
	// Preserve Rust's flattened SessionMetaLine and enum serialization, rather
	// than V's generated tagged-struct JSON encoding of those canonical types.
	meta := &session_meta.meta
	lines := [
		serde_json.Value.object({
			'timestamp': serde_json.Value.string(timestamp.clone())
			'type':      serde_json.Value.string('session_meta')
			'payload':   serde_json.Value.object({
				'session_id':        serde_json.Value.string(meta.session_id.value.clone())
				'id':                serde_json.Value.string(meta.id.value.clone())
				'timestamp':         serde_json.Value.string(meta.timestamp.clone())
				'cwd':               serde_json.Value.string(meta.cwd.clone())
				'originator':        serde_json.Value.string(meta.originator.clone())
				'cli_version':       serde_json.Value.string(meta.cli_version.clone())
				'source':            serde_json.Value.string(meta.source.str())
				'model_provider':    serde_json.Value.string((meta.model_provider or { '' }).clone())
				'base_instructions': serde_json.Value{}
				'history_mode':      serde_json.Value.string(meta.history_mode.str())
			})
		}),
		serde_json.Value.object({
			'timestamp': serde_json.Value.string(timestamp.clone())
			'type':      serde_json.Value.string('response_item')
			'payload':   serde_json.Value.object({
				'type':    serde_json.Value.string('message')
				'role':    serde_json.Value.string('user')
				'content': serde_json.Value.array_value([serde_json.Value.object({
					'type': serde_json.Value.string('input_text')
					'text': serde_json.Value.string(preview.clone())
				})])
			})
		}),
		serde_json.Value.object({
			'timestamp': serde_json.Value.string(timestamp.clone())
			'type':      serde_json.Value.string('event_msg')
			'payload':   serde_json.Value.object({
				'type':    serde_json.Value.string('user_message')
				'message': serde_json.Value.string(preview.clone())
				'kind':    serde_json.Value.string('plain')
			})
		}),
	]
	mut serialized := []string{cap: lines.len}
	for index in 0 .. lines.len {
		serialized << (&lines[index]).to_string()
	}
	os.write_file(rollout_path, serialized.join('\n') + '\n')!
	return rollout_path
}

// Rust ThreadId is Copy (UUID bytes); its temporary V owner stores a string,
// requiring a visible storage copy wherever those source tests reuse the UUID.
fn copy_id(id &codex_protocol.ThreadId) codex_protocol.ThreadId {
	return codex_protocol.ThreadId{ value: id.value.clone() }
}

fn present_id(value &OptionalThread) ?string {
	if value.has_value {
		return value.value.id.clone()
	}
	return none
}

const fixture_timestamp_1 = '2025-02-01T10:00:00Z'
const fixture_timestamp_2 = '2025-02-02T10:00:00Z'
const fixture_timestamp_3 = '2025-02-03T10:00:00Z'
const fixture_timestamp_valid = '2025-02-01T10:00:01Z'
const fixture_named_label = 'saved-session'
const fixture_preview_label = 'preview text'
const fixture_duplicate_label = 'same-label'
const fixture_other_1_label = 'other-1'

fn test_resolves_name_and_preview_from_server_list() {
	temp_dir := TempDir.new() or { panic(err.msg()) }
	defer { os.rmdir_all(temp_dir.path) or {} }
	config := build_config(&temp_dir) or { panic(err.msg()) }
	state := state_runtime(&config) or { panic(err.msg()) }
	named_id := thread_id.new()
	named_path := write_rollout(&config, copy_id(&named_id), &fixture_timestamp_1, &fixture_preview_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, copy_id(&named_id), named_path, &fixture_named_label)) or { panic(err.msg()) }
	preview_id := thread_id.new()
	preview_path := write_rollout(&config, copy_id(&preview_id), &fixture_timestamp_2, &fixture_preview_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, copy_id(&preview_id), preview_path, &fixture_preview_label)) or { panic(err.msg()) }
	other_id := thread_id.new()
	mut other_config := config.clone()
	other_config.model_provider_id = 'another-provider'
	other_path := write_rollout(&other_config, copy_id(&other_id), &fixture_timestamp_3, &fixture_preview_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&other_config, copy_id(&other_id), other_path, &fixture_named_label)) or { panic(err.msg()) }
	collections := [SessionCollection.active]
	provider := BorrowedModelProvider{ has_value: true, value: &config.model_provider_id }
	other_provider := BorrowedModelProvider{ has_value: true, value: &other_config.model_provider_id }
	absent_provider := BorrowedModelProvider{}
	named := lookup_name(&config, &fixture_named_label, &collections, .embedded, &provider) or { panic(err.msg()) }
	preview := lookup_name(&config, &fixture_preview_label, &collections, .embedded, &provider) or { panic(err.msg()) }
	switched_provider := lookup_name(&config, &fixture_named_label, &collections, .embedded, &other_provider) or { panic(err.msg()) }
	remote := lookup_name(&other_config, &fixture_named_label, &collections, .remote, /*model_provider*/
		&absent_provider) or { panic(err.msg()) }
	assert present_id(&named) == ?string(named_id.value.clone())
	assert present_id(&preview) == ?string(preview_id.value.clone())
	assert present_id(&switched_provider) == ?string(other_id.value.clone())
	assert present_id(&remote) == ?string(other_id.value.clone())
}

fn test_rejects_duplicate_labels_across_server_pages() {
	temp_dir := TempDir.new() or { panic(err.msg()) }
	defer { os.rmdir_all(temp_dir.path) or {} }
	config := build_config(&temp_dir) or { panic(err.msg()) }
	state := state_runtime(&config) or { panic(err.msg()) }
	mut relevant_ids := []codex_protocol.ThreadId{}
	for index in 0 .. 102 {
		id := thread_id.new()
		if index in [0, 1, 101] { relevant_ids << copy_id(&id) }
		rollout_path := write_rollout(&config, copy_id(&id), &fixture_timestamp_1, &fixture_preview_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
		name := if index in [0, 101] { fixture_duplicate_label } else { 'other-${index}' }
		mut metadata := thread_metadata(&config, id, rollout_path, &name)
		metadata.recency_at = metadata.recency_at.add_seconds(index)
		metadata.updated_at = metadata.updated_at.add_seconds(index)
		upsert_thread(state, metadata) or { panic(err.msg()) }
	}
	handle := codex_tui.start_test_embedded_app_server(config.clone()) or { panic(err.msg()) }
	observer := handle.clone()
	mut app_server := codex_tui.AppServerSession.new(handle, .embedded)
	home := std_path.Path.new(&config.codex_home)
	collections := [SessionCollection.active]
	sources := [codex_tui.resume_source_kinds( /*include_non_interactive*/
	false)]
	provider := BorrowedModelProvider{ has_value: true, value: &config.model_provider_id }
	mut duplicate_error := ''
	lookup(mut app_server, &home, &fixture_duplicate_label, &collections, &sources, &provider) or {
		assert err is AmbiguousSessionName
		duplicate_error = err.msg()
		OptionalThread{}
	}
	assert duplicate_error.len > 0, 'duplicate labels should require an ID'
	mut unverified := ''
	lookup(mut app_server, &home, &fixture_other_1_label, &collections, &sources, &provider) or {
		assert err is AmbiguousSessionName
		unverified = err.msg()
		OptionalThread{}
	}
	assert unverified.len > 0, 'paginated listings cannot prove uniqueness on older servers'
	app_server.shutdown() or { panic(err.msg()) }
	assert duplicate_error == "Multiple sessions match 'same-label' (including ${relevant_ids[2]} and ${relevant_ids[0]}); use a session UUID to disambiguate."
	assert unverified == 'Cannot verify a unique session label across server pages; matching session UUID: ${relevant_ids[1]}. Use it only if this is the session you want.'
	requests := observer.named_session_fixture_requests()
	mut list_count := 0
	for index in 0 .. requests.len {
		request := &requests[index]
		if request is codex_app_server_protocol.ClientRequestThreadList { list_count++ }
	}
	assert list_count == 4
}

fn test_skips_stale_listed_thread_before_valid_label() {
	temp_dir := TempDir.new() or { panic(err.msg()) }
	defer { os.rmdir_all(temp_dir.path) or {} }
	config := build_config(&temp_dir) or { panic(err.msg()) }
	state := state_runtime(&config) or { panic(err.msg()) }
	stale_id := thread_id.new()
	stale_path := write_rollout(&config, copy_id(&stale_id), &fixture_timestamp_1, &fixture_duplicate_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, stale_id, stale_path.clone(), &fixture_duplicate_label)) or { panic(err.msg()) }
	os.rm(stale_path) or { panic(err.msg()) }
	corrupt_id := thread_id.new()
	corrupt_path := write_rollout(&config, copy_id(&corrupt_id), &fixture_timestamp_1, &fixture_duplicate_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, corrupt_id, corrupt_path.clone(), &fixture_duplicate_label)) or { panic(err.msg()) }
	os.write_file(corrupt_path, 'invalid session header\n') or { panic(err.msg()) }
	valid_id := thread_id.new()
	valid_path := write_rollout(&config, copy_id(&valid_id), &fixture_timestamp_valid, &fixture_duplicate_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, copy_id(&valid_id), valid_path.clone(), &fixture_duplicate_label)) or { panic(err.msg()) }
	wrong_id := thread_id.new()
	upsert_thread(state, thread_metadata(&config, wrong_id, valid_path, &fixture_duplicate_label)) or { panic(err.msg()) }
	collections := [SessionCollection.active]
	provider := BorrowedModelProvider{ has_value: true, value: &config.model_provider_id }
	found := lookup_name(&config, &fixture_duplicate_label, &collections, .embedded, &provider) or { panic(err.msg()) }
	assert present_id(&found) == ?string(valid_id.value.clone())
}

fn test_uses_listed_thread_when_older_server_cannot_read_it() {
	temp_dir := TempDir.new() or { panic(err.msg()) }
	defer { os.rmdir_all(temp_dir.path) or {} }
	config := build_config(&temp_dir) or { panic(err.msg()) }
	state := state_runtime(&config) or { panic(err.msg()) }
	id := thread_id.new()
	path := write_rollout(&config, copy_id(&id), &fixture_timestamp_1, &fixture_preview_label, codex_protocol.SessionSource{ source_kind: .cli }, .legacy) or { panic(err.msg()) }
	upsert_thread(state, thread_metadata(&config, copy_id(&id), path, &fixture_named_label)) or { panic(err.msg()) }
	embedded_handle := codex_tui.start_test_embedded_app_server(config.clone()) or { panic(err.msg()) }
	mut embedded := codex_tui.AppServerSession.new(embedded_handle, .embedded)
	listed := embedded.thread_read(copy_id(&id), /*include_turns*/
		false) or { panic(err.msg()) }
	embedded.shutdown() or { panic(err.msg()) }
	for mode in [codex_tui.ThreadParamsMode.remote, .embedded] {
		// Replace the localhost listener/socket task at the native transport
		// boundary. Its actual typed list response and read error remain intact.
		url := 'ws://127.0.0.1/named-session-${uuid.Uuid.new_v4()}'
		listed_for_server := listed.clone()
		replies := [
			codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadListResponse{ data: [listed_for_server.clone()], next_cursor: none }),
			codex_app_server_client.NamedSessionReply(codex_app_server_client.TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'thread not loaded: ${id}' } }),
		]
		initialize_result := serde_json.Value.object({
			'userAgent': serde_json.Value.string('legacy-test')
		})
		handle := codex_app_server_client.AppServerRequestHandle.named_session_remote_rpc_fixture(initialize_result, replies)
		observer := handle.clone()
		codex_app_server_client.bind_named_session_fixture_endpoint(url.clone(), handle)
		client := codex_app_server_client.RemoteAppServerClient.connect(codex_app_server_client.RemoteAppServerConnectArgs{
			endpoint:                           codex_app_server_client.RemoteAppServerWebSocket{ websocket_url: url, auth_token: none }
			client_name:                        'legacy-test'
			client_version:                     '0.0.0'
			experimental_api:                   true
			mcp_server_openai_form_elicitation: false
			opt_out_notification_methods:       []
			channel_capacity:                   8
		}) or { panic(err.msg()) }
		mut remote := codex_tui.AppServerSession.new(client.request_handle(), mode)
		home := std_path.Path.new(&config.codex_home)
		collections := [SessionCollection.active]
		sources := [codex_tui.resume_source_kinds( /*include_non_interactive*/
		false)]
		provider := BorrowedModelProvider{}
		found := lookup(mut remote, &home, &fixture_named_label, &collections, &sources, /*model_provider*/
			&provider) or { panic(err.msg()) }
		assert found.has_value
		assert found.value == listed.clone()
		requests := observer.named_session_fixture_requests()
		assert requests.len == 2
		assert requests[0] is codex_app_server_protocol.ClientRequestThreadList
		read := &requests[1]
		assert read is codex_app_server_protocol.ClientRequestThreadRead
		if read is codex_app_server_protocol.ClientRequestThreadRead {
			assert read.params.thread_id == id.value
			assert !read.params.include_turns
		}
	}
}

fn test_borrowed_label_and_lookup_inputs_remain_reusable() {
	mut name := '\u2003saved-session\u00a0'
	mut preview := '\u3000preview text\u0085'
	mut query := 'saved-session'
	mut provider_owner := 'borrowed-provider'
	mut home_owner := '/borrowed-home'
	$if ownership ? {
		name = name.to_owned()
		preview = preview.to_owned()
		query = query.to_owned()
		provider_owner = provider_owner.to_owned()
		home_owner = home_owner.to_owned()
	}
	id := thread_id.new()
	owner := codex_app_server_protocol.Thread{ id: id.value.clone(), name: name, preview: preview }
	assert display_label(&owner) == query
	assert display_label(&owner) == query
	assert owner.name or { '' } == '\u2003saved-session\u00a0'
	assert owner.preview == '\u3000preview text\u0085'
	provider := BorrowedModelProvider{ has_value: true, value: &provider_owner }
	home := std_path.Path.new(&home_owner)
	collections := [SessionCollection.active]
	sources := [[codex_app_server_protocol.ThreadSourceKind.cli, .vscode]]
	mut replies := []codex_app_server_client.NamedSessionReply{}
	for _ in 0 .. 2 {
		replies << codex_app_server_protocol.ThreadListResponse{ data: [owner.clone()] }
		replies << codex_app_server_protocol.ThreadReadResponse{ thread: owner.clone() }
	}
	handle := codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies)
	observer := handle.clone()
	mut session := codex_tui.AppServerSession.new(handle, .remote)
	first := lookup(mut session, &home, &query, &collections, &sources, &provider) or { panic(err.msg()) }
	second := lookup(mut session, &home, &query, &collections, &sources, &provider) or { panic(err.msg()) }
	assert first.has_value && second.has_value
	assert first.value.id == id.value && second.value.id == id.value
	assert query == 'saved-session'
	assert provider_owner == 'borrowed-provider'
	assert home_owner == '/borrowed-home'
	assert collections == [SessionCollection.active]
	assert sources == [[codex_app_server_protocol.ThreadSourceKind.cli, .vscode]]
	requests := observer.named_session_fixture_requests()
	assert requests.len == 4
	for index in 0 .. requests.len {
		request := &requests[index]
		if request is codex_app_server_protocol.ClientRequestThreadList {
			assert request.request_id == codex_app_server_protocol.RequestId{ kind: .integer, integer: i64(index + 1) }
			assert request.params == codex_app_server_protocol.ThreadListParams{
				originators:        none
				cursor:             none
				limit:              u32(100)
				sort_key:           codex_app_server_protocol.ThreadSortKey.updated_at
				sort_direction:     none
				model_providers:    [provider_owner.clone()]
				source_kinds:       [
					codex_app_server_protocol.ThreadSourceKind.cli,
					.vscode,
				]
				archived:           false
				section_id:         codex_app_server_protocol.ClearableString{}
				project_id:         codex_app_server_protocol.ClearableString{}
				parent_thread_id:   none
				ancestor_thread_id: none
				cwd:                none
				use_state_db_only:  false
				search_term:        none
			}
		}
	}
}

fn test_preserves_collection_and_source_filter_request_order() {
	collections := [SessionCollection.active, .archived]
	sources := [[codex_app_server_protocol.ThreadSourceKind.cli, .vscode],
		[codex_app_server_protocol.ThreadSourceKind.exec, .app_server]]
	mut replies := []codex_app_server_client.NamedSessionReply{}
	for _ in 0 .. 4 {
		replies << codex_app_server_protocol.ThreadListResponse{}
	}
	handle := codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies)
	observer := handle.clone()
	mut session := codex_tui.AppServerSession.new(handle, .remote)
	home_owner := '/local'
	home := std_path.Path.new(&home_owner)
	provider := BorrowedModelProvider{}
	query := 'missing'
	found := lookup(mut session, &home, &query, &collections, &sources, &provider) or { panic(err.msg()) }
	assert !found.has_value
	requests := observer.named_session_fixture_requests()
	assert requests.len == 4
	for index in 0 .. requests.len {
		request := &requests[index]
		assert request is codex_app_server_protocol.ClientRequestThreadList
		if request is codex_app_server_protocol.ClientRequestThreadList {
			assert request.params.archived == ?bool(index >= 2)
			assert request.params.source_kinds == ?[]codex_app_server_protocol.ThreadSourceKind(sources[index % 2].clone())
			assert request.params.model_providers == none
			assert request.params.cursor == none
		}
	}
}

fn test_blank_label_skips_server_and_duplicate_same_id_remains_unique() {
	blank := '\u2003\u00a0\u3000'
	home_owner := '/local'
	home := std_path.Path.new(&home_owner)
	collections := [SessionCollection.active]
	sources := [[codex_app_server_protocol.ThreadSourceKind.cli]]
	provider := BorrowedModelProvider{}
	handle := codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture([])
	observer := handle.clone()
	mut empty_session := codex_tui.AppServerSession.new(handle, .remote)
	assert !(lookup(mut empty_session, &home, &blank, &collections, &sources, &provider) or { panic(err.msg()) }).has_value
	assert observer.named_session_fixture_requests().len == 0
	id := thread_id.new()
	listed := codex_app_server_protocol.Thread{ id: id.value.clone(), name: fixture_named_label }
	replies := [
		codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadListResponse{
			data: [
				listed.clone(),
				listed.clone(),
			]
		}),
		codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadReadResponse{ thread: listed.clone() }),
		codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadReadResponse{ thread: listed.clone() }),
	]
	mut session := codex_tui.AppServerSession.new(codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies), .remote)
	found := lookup(mut session, &home, &fixture_named_label, &collections, &sources, &provider) or { panic(err.msg()) }
	assert found.has_value
	assert found.value == listed
}

fn test_uuid_parse_accepts_source_forms_and_keeps_borrowed_input() {
	mut owner := 'AABBCCDD-1122-3344-5566-77889900AABB'
	$if ownership ? {
		owner = owner.to_owned()
	}
	canonical := 'aabbccdd-1122-3344-5566-77889900aabb'
	first := thread_id.from_string(&owner) or { panic(err.msg()) }
	second := thread_id.from_string(&owner) or { panic(err.msg()) }
	assert first.str() == canonical
	assert first.str() == canonical
	assert second.str() == canonical
	assert owner == 'AABBCCDD-1122-3344-5566-77889900AABB'
	for input in ['aabbccdd11223344556677889900aabb', '{AABBCCDD-1122-3344-5566-77889900AABB}',
		'urn:uuid:AABBCCDD-1122-3344-5566-77889900AABB'] {
		assert (thread_id.from_string(&input) or { panic(err.msg()) }).str() == canonical
	}
	for input in ['', 'not-a-uuid', 'aabbccdd-1122-3344-5566-77889900aabg'] {
		mut rejected := false
		thread_id.from_string(&input) or {
			rejected = true
			codex_protocol.ThreadId{}
		}
		assert rejected
	}
}

fn test_read_failures_keep_typed_errors_and_filter_only_stale_metadata() {
	id := thread_id.new()
	path := '/server/sessions/listed.jsonl'
	listed := codex_app_server_protocol.Thread{ id: id.value.clone(), name: fixture_named_label, path: path }
	home_owner := '/local'
	home := std_path.Path.new(&home_owner)
	collections := [SessionCollection.active]
	sources := [[codex_app_server_protocol.ThreadSourceKind.cli]]
	provider := BorrowedModelProvider{}
	failures := [
		codex_app_server_client.TypedRequestError{ kind: .transport, method: 'thread/read', transport_source: error('connection closed') },
		codex_app_server_client.TypedRequestError{ kind: .deserialize, method: 'thread/read', deserialize_source: error('invalid thread payload') },
		codex_app_server_client.TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'unrelated failure' } },
		codex_app_server_client.TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'failed to read thread: thread-store internal error: session metadata listed.jsonl belongs to thread another-id, expected ${id}' } },
		codex_app_server_client.TypedRequestError{ kind: .server, method: 'thread/read', server_source: codex_app_server_protocol.JSONRPCErrorError{ code: -32603, message: 'failed to read thread: thread-store internal error: failed to read session metadata ${path}: invalid JSON' } },
	]
	for index in 0 .. failures.len {
		replies := [
			codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadListResponse{ data: [listed.clone()] }),
			codex_app_server_client.NamedSessionReply((&failures[index]).clone()),
		]
		mut session := codex_tui.AppServerSession.new(codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies), .remote)
		mut failure_message := ''
		found := lookup(mut session, &home, &fixture_named_label, &collections, &sources, &provider) or {
			cause := eyre.root_cause(&err)
			assert cause is codex_app_server_client.TypedRequestError
			if cause is codex_app_server_client.TypedRequestError {
				assert cause.msg() == (&failures[index]).msg()
			}
			failure_message = err.msg()
			OptionalThread{}
		}
		assert !found.has_value
		if index < 3 {
			assert failure_message == 'thread/read failed during TUI session lookup'
		} else {
			assert failure_message == ''
		}
	}
}

fn test_read_must_confirm_id_and_label_and_legacy_local_path_must_exist() {
	id := thread_id.new()
	other_id := thread_id.new()
	listed := codex_app_server_protocol.Thread{ id: id.value.clone(), name: fixture_named_label }
	home_owner := '/local'
	home := std_path.Path.new(&home_owner)
	collections := [SessionCollection.active]
	sources := [[codex_app_server_protocol.ThreadSourceKind.cli]]
	provider := BorrowedModelProvider{}
	changed := [
		codex_app_server_protocol.Thread{ id: other_id.value.clone(), name: fixture_named_label },
		codex_app_server_protocol.Thread{ id: id.value.clone(), name: fixture_preview_label },
	]
	for index in 0 .. changed.len {
		replies := [
			codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadListResponse{ data: [listed.clone()] }),
			codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadReadResponse{ thread: (&changed[index]).clone() }),
		]
		mut session := codex_tui.AppServerSession.new(codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies), .remote)
		assert !(lookup(mut session, &home, &fixture_named_label, &collections, &sources, &provider) or { panic(err.msg()) }).has_value
	}
	for path in ['/local/sessions-old/thread.jsonl', '/local/sessions/missing.jsonl'] {
		candidate := codex_app_server_protocol.Thread{ id: id.value.clone(), name: fixture_named_label, path: path }
		replies := [codex_app_server_client.NamedSessionReply(codex_app_server_protocol.ThreadListResponse{ data: [candidate] })]
		handle := codex_app_server_client.AppServerRequestHandle.named_session_rpc_fixture(replies)
		observer := handle.clone()
		mut session := codex_tui.AppServerSession.new(handle, .embedded)
		assert !(lookup(mut session, &home, &fixture_named_label, &collections, &sources, &provider) or { panic(err.msg()) }).has_value
		assert observer.named_session_fixture_requests().len == 1
	}
}
