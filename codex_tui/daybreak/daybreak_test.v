module daybreak

import codex_app_server_client
import codex_app_server_protocol as api
import codex_core
import codex_features
import codex_http_client
import codex_login
import codex_tui
import time
import uuid

fn owned(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

struct ParseCase {
	programs string
	expected Notice
}

fn test_refusal_copy_uses_verified_access() {
	// Exact programs and expectations from daybreak_tests.rs's seven cases.
	cases := [
		ParseCase{ programs: '[]', expected: Notice.apply },
		ParseCase{ programs: '[{"program":"cyber","state":"inactive","grants":[]}]', expected: Notice.apply },
		ParseCase{ programs: '[{"program":"cyber","state":"unavailable","grants":[]}]', expected: Notice.limited },
		ParseCase{ programs: '[{"program":"cyber","state":"active","grants":[{"level":"tac2"}]}]', expected: Notice.limited },
		ParseCase{ programs: '[{"program":"cyber","state":"active","grants":[]}]', expected: Notice.limited },
		ParseCase{ programs: '[{"program":"cyber","state":"inactive","grants":[{"level":"tac2"}]}]', expected: Notice.limited },
		ParseCase{ programs: '[{"program":"cyber","state":"unknown","grants":[]}]', expected: Notice.limited },
	]
	for index in 0 .. cases.len {
		case := &cases[index]
		text := '{"programs":${case.programs}}'
		access := deserialize_verified_access(&text) or { panic(err) }
		assert access.notice() == case.expected
	}
}

fn test_unknown_programs_ignored_grants_and_all_programs_decision() {
	for text in [
		'{"programs":[{"program":"other","state":null,"grants":false}]}',
		'{"programs":[{"program":"Cyber"},{"program":"future"},{"program":"cyber","state":"inactive","grants":[]}],"unknown":{"nested":1e999}}',
		'[[{"program":"cyber","state":"inactive","grants":[]}]]',
		'{"programs":[["cyber","inactive",[]],["future",12]]}',
	] {
		access := deserialize_verified_access(&text) or { panic(err) }
		assert access.notice() == .apply
	}
	for text in [
		'{"programs":[{"program":"future"},{"program":"cyber","state":"inactive","grants":[]},{"program":"cyber","state":"active","grants":[]}]}',
		'{"programs":[{"program":"cyber","state":"inactive","grants":[null,true,4,"value",[],{"x":[1e308,"valid"]}]}]}',
	] {
		access := deserialize_verified_access(&text) or { panic(err) }
		assert access.notice() == .limited
	}
}

fn test_serde_required_fields_types_and_duplicates() {
	cases := {
		'{}':                                                                                   'missing field `programs`'
		'{"programs":null}':                                                                    'invalid type: null, expected a sequence'
		'{"programs":{}}':                                                                      'invalid type: map, expected a sequence'
		'{"programs":[],"programs":[]}':                                                        'duplicate field `programs`'
		'{"programs":[{}]}':                                                                    'missing field `program`'
		'{"programs":[{"program":true}]}':                                                      'invalid type: boolean `true`, expected variant identifier'
		'{"programs":[{"program":"cyber","state":"inactive"}]}':                                'missing field `grants`'
		'{"programs":[{"program":"cyber","grants":[]}]}':                                       'missing field `state`'
		'{"programs":[{"program":"cyber","state":null,"grants":[]}]}':                          'invalid type: null, expected a string'
		'{"programs":[{"program":"cyber","state":"inactive","grants":{}}]}':                    'invalid type: map, expected a sequence'
		'{"programs":[{"program":"other","program":"other"}]}':                                 'duplicate field `program`'
		'{"programs":[{"program":"cyber","state":"inactive","state":"inactive","grants":[]}]}': 'duplicate field `state`'
		'{"programs":[{"program":"cyber","state":"inactive","grants":[],"grants":[]}]}':        'duplicate field `grants`'
	}
	for text, expected in cases {
		deserialize_verified_access(&text) or {
			assert err.msg() == expected
			continue
		}
		assert false, text
	}
	for text in ['{"programs":[]', '{"programs":[{"program":"other","ignored":[1,]}]}',
		'{"programs":[]} trailing'] {
		deserialize_verified_access(&text) or { continue }
		assert false, text
	}
}

fn test_serde_decodes_fields_before_later_duplicate_and_sequence_errors() {
	// Struct derives decode each next_value/next_element before advancing.
	// Internally tagged Program first buffers its tag/content map, then Cyber
	// decodes state/grants in the order they occur in that buffered map.
	cases := {
		'{"programs":null,"programs":[]}':                                                  'invalid type: null, expected a sequence'
		'{"programs":[{}],"programs":[]}':                                                  'missing field `program`'
		'{"programs":[],"programs":null}':                                                  'duplicate field `programs`'
		'[null,[]]':                                                                        'invalid type: null, expected a sequence'
		'[[{}],[]]':                                                                        'missing field `program`'
		'{"programs":[{"program":true,"program":"cyber","state":"inactive","grants":[]}]}': 'invalid type: boolean `true`, expected variant identifier'
		'{"programs":[{"program":"cyber","state":null,"state":"inactive","grants":[]}]}':   'invalid type: null, expected a string'
		'{"programs":[{"program":"cyber","grants":null,"grants":[],"state":"inactive"}]}':  'invalid type: null, expected a sequence'
		'{"programs":[{"program":"cyber","state":null,"program":"cyber","grants":[]}]}':    'duplicate field `program`'
	}
	for text, expected in cases {
		deserialize_verified_access(&text) or {
			assert err.msg() == expected
			continue
		}
		assert false, text
	}
}

fn stable_auth() codex_login.CodexAuth {
	return codex_login.CodexAuth{ kind: .chatgpt, token: owned('token'), account_id: owned('account'), fedramp_account: true }
}

fn auth_reply() codex_login.DaybreakAuthLoadReply {
	return codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: stable_auth() }
}

fn fixture_config(replies []codex_login.DaybreakAuthLoadReply) codex_core.Config {
	return codex_core.Config{ model_provider_id: owned('openai'), chatgpt_base_url: owned('https://chatgpt.example/backend-api///'), codex_home: owned('/tmp/daybreak-auth'), cwd: owned('/tmp'), respect_system_proxy: true, features: codex_features.Features{ enabled_features: [.psp] }, resolved_auth_config: codex_login.AuthConfig.daybreak_fixture(replies) }
}

fn status_handle(response api.GetAuthStatusResponse, failure ?codex_app_server_client.TypedRequestErrorKind) codex_app_server_client.AppServerRequestHandle {
	return codex_app_server_client.AppServerRequestHandle.daybreak_auth_status_fixture(response, failure, false, chan bool{cap: 1})
}

fn stable_handle() codex_app_server_client.AppServerRequestHandle {
	return status_handle(api.GetAuthStatusResponse{ auth_method: .chatgpt, auth_token: owned('token'), requires_openai_auth: true }, none)
}

fn wait_for_request(handle &codex_app_server_client.AppServerRequestHandle) {
	for _ in 0 .. 1000 {
		if handle.daybreak_auth_status_requests().len > 0 {
			return
		}
		time.sleep(time.millisecond)
	}
	assert false, 'auth-status request did not start'
}

fn wait_for_notice(cache NoticeCache) Notice {
	for _ in 0 .. 5000 {
		if notice := cache.get() {
			return notice
		}
		time.sleep(time.millisecond)
	}
	panic('notice cache did not initialize')
}

fn test_read_notice_preserves_rpc_http_auth_order_and_identity() {
	codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: owned('{"programs":[]}') }])
	defer { codex_http_client.clear_updates_transport_fixture() }
	config := fixture_config([auth_reply(), auth_reply()])
	gate := chan bool{cap: 1}
	handle := codex_app_server_client.AppServerRequestHandle.daybreak_auth_status_fixture(api.GetAuthStatusResponse{ auth_method: .chatgpt, auth_token: owned('token') }, none, true, gate)
	server := codex_tui.AppServerSession.new(handle.clone(), .embedded)
	cache := NoticeCache.new()
	prefetch_notice(&config, &server, cache)
	wait_for_request(&handle)
	assert config.auth_config().daybreak_load_flags().len == 0
	assert codex_http_client.updates_request_observations().len == 0
	gate <- true
	assert wait_for_notice(cache) == .apply
	requests := handle.daybreak_auth_status_requests()
	assert requests.len == 1
	assert requests[0].params == api.GetAuthStatusParams{ include_token: true, refresh_token: false }
	assert requests[0].request_id.kind == .string_id
	id := &requests[0].request_id.string_value
	assert uuid.Uuid.parse_str(id) or { panic(err) }.str() == *id
	assert (*id)[14] == `4`
	assert (*id)[19] in [`8`, `9`, `a`, `b`]
	assert config.auth_config().daybreak_load_flags() == [false, false]
	observations := codex_http_client.updates_request_observations()
	assert observations.len == 1
	assert observations[0].url == 'https://chatgpt.example/backend-api/accounts/verified_access'
	assert observations[0].headers.values == {
		'authorization':      'Bearer token'
		'chatgpt-account-id': 'account'
		'x-openai-fedramp':   'true'
	}
	assert observations[0].route_class == .api
	assert observations[0].without_redirects
	assert observations[0].proxy_policy == .respect_system_proxy
	assert observations[0].configured_cookies == ['oai-chat-psp=true']
}

fn test_auth_unavailability_and_server_mismatch_fail_closed_before_http() {
	for failure in [codex_app_server_client.TypedRequestErrorKind.transport, .server, .deserialize] {
		config := fixture_config([auth_reply(), auth_reply()])
		handle := status_handle(api.GetAuthStatusResponse{}, failure)
		assert read_notice(&config, &handle) == .limited
		assert config.auth_config().daybreak_load_flags().len == 0
	}
	for response in [api.GetAuthStatusResponse{},
		api.GetAuthStatusResponse{ auth_method: .api_key, auth_token: owned('token') },
		api.GetAuthStatusResponse{ auth_method: .chatgpt, auth_token: owned('different') },
		api.GetAuthStatusResponse{ auth_method: .chatgpt }] {
		config := fixture_config([auth_reply(), auth_reply()])
		handle := status_handle(response, none)
		assert read_notice(&config, &handle) == .limited
		assert config.auth_config().daybreak_load_flags() == [false]
	}
	for reply in [codex_login.DaybreakAuthLoadReply{},
		codex_login.DaybreakAuthLoadReply{ load_error: owned('store failed') },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .api_key, token: owned('token') } },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .chatgpt, token_error: owned('token unavailable') } }] {
		config := fixture_config([reply])
		handle := stable_handle()
		assert read_notice(&config, &handle) == .limited
	}
	assert codex_http_client.updates_request_observations().len == 0
}

fn test_http_status_transport_json_and_reload_fail_closed() {
	defer { codex_http_client.clear_updates_transport_fixture() }
	for response in [
		codex_http_client.UpdatesResponseFixture{ status: 302, body: owned('{"programs":[]}') },
		codex_http_client.UpdatesResponseFixture{ status: 401, body: owned('{"programs":[]}') },
		codex_http_client.UpdatesResponseFixture{ status: 500 },
		codex_http_client.UpdatesResponseFixture{ transport_error: owned('network failed') },
		codex_http_client.UpdatesResponseFixture{ body: owned('{"programs":null}') },
	] {
		codex_http_client.set_updates_transport_fixture([response])
		config := fixture_config([auth_reply(), auth_reply()])
		handle := stable_handle()
		assert read_notice(&config, &handle) == .limited
		assert config.auth_config().daybreak_load_flags() == [false]
	}
	for changed in [codex_login.DaybreakAuthLoadReply{},
		codex_login.DaybreakAuthLoadReply{ load_error: owned('reload failed') },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .chatgpt, token: owned('different'), account_id: owned('account') } },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .chatgpt, token: owned('token'), account_id: owned('different-account') } },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .chatgpt, token: owned('token') } },
		codex_login.DaybreakAuthLoadReply{ has_auth: true, auth: codex_login.CodexAuth{ kind: .chatgpt, token_error: owned('current token unavailable') } }] {
		codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: owned('{"programs":[]}') }])
		config := fixture_config([auth_reply(), changed])
		handle := stable_handle()
		assert read_notice(&config, &handle) == .limited
		assert config.auth_config().daybreak_load_flags() == [false, false]
	}
}

fn test_prefetch_skips_non_openai_remote_and_initialized_and_runs_once_concurrently() {
	codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: owned('{"programs":[]}') }])
	defer { codex_http_client.clear_updates_transport_fixture() }
	mut config := fixture_config([auth_reply(), auth_reply()])
	gate := chan bool{cap: 1}
	handle := codex_app_server_client.AppServerRequestHandle.daybreak_auth_status_fixture(api.GetAuthStatusResponse{ auth_method: .chatgpt, auth_token: owned('token') }, none, true, gate)
	server := codex_tui.AppServerSession.new(handle.clone(), .embedded)
	remote := codex_tui.AppServerSession.new(handle.clone(), .remote)
	cache := NoticeCache.new()
	config.model_provider_id = owned('custom')
	prefetch_notice(&config, &server, cache)
	config.model_provider_id = owned('openai')
	prefetch_notice(&config, &remote, cache)
	assert cache.get() == none
	assert handle.daybreak_auth_status_requests().len == 0
	started := time.sys_mono_now()
	mut workers := []thread{}
	for _ in 0 .. 12 {
		workers << spawn prefetch_notice(&config, &server, cache)
	}
	workers.wait()
	assert time.sys_mono_now() - started < u64(500_000_000)
	wait_for_request(&handle)
	assert cache.get() == none
	assert handle.daybreak_auth_status_requests().len == 1
	gate <- true
	assert wait_for_notice(cache) == .apply
	prefetch_notice(&config, &server, cache)
	assert handle.daybreak_auth_status_requests().len == 1
	assert config.auth_config().daybreak_load_flags() == [false, false]
}

fn test_three_second_deadline_caches_neutral_and_stops_late_http_continuation() {
	gate := chan bool{cap: 1}
	codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: owned('{"programs":[]}'), block_until_released: true, gate: gate }])
	defer { codex_http_client.clear_updates_transport_fixture() }
	config := fixture_config([auth_reply(), auth_reply()])
	handle := stable_handle()
	server := codex_tui.AppServerSession.new(handle.clone(), .embedded)
	cache := NoticeCache.new()
	started := time.sys_mono_now()
	prefetch_notice(&config, &server, cache)
	assert wait_for_notice(cache) == .limited
	elapsed := time.sys_mono_now() - started
	assert elapsed >= u64(2_900_000_000)
	assert elapsed < u64(4_500_000_000)
	assert codex_http_client.updates_request_observations().len == 1
	assert config.auth_config().daybreak_load_flags() == [false]
	gate <- true
	time.sleep(30 * time.millisecond)
	assert cache.get() == ?Notice(.limited)
	assert config.auth_config().daybreak_load_flags() == [false]
}

fn test_expired_worker_does_not_start_rpc_and_unported_runtime_never_authenticates() {
	config := fixture_config([auth_reply()])
	handle := stable_handle()
	read_notice_attempt(&config, &handle, time.sys_mono_now() - 1) or {
		assert err.msg() == 'verified access discovery timed out'
		assert handle.daybreak_auth_status_requests().len == 0
		assert config.auth_config().daybreak_load_flags().len == 0
	}
	assert read_notice(&codex_core.Config{}, &codex_app_server_client.AppServerRequestHandle{}) == .limited
	unconfigured := codex_core.Config{ model_provider_id: owned('openai') }
	assert read_notice(&unconfigured, &handle) == .limited
}

fn test_borrowed_model_parser_and_auth_owners_reused_after_config_clone() {
	text := owned('{"programs":[{"program":"cyber","state":"inactive","grants":[]}]}')
	model := owned('gpt-5.6-sol')
	for _ in 0 .. 2 {
		access := deserialize_verified_access(&text) or { panic(err) }
		assert access.notice().for_model(&model) == .apply
		assert Notice.limited.for_model(&model) == .limited
		assert Notice.astra.for_model(&model) == .astra
	}
	assert text.contains('inactive')
	assert model == 'gpt-5.6-sol'
	for notice in [Notice.apply, .limited, .astra] {
		for astra in [owned('gpt-6-astra'), owned('gpt-6-astra-wm')] {
			assert notice.for_model(&astra) == .astra
		}
		for other in [owned('gpt-6-astra-other'), owned('gpt-5.6-sol-wm'), owned('gpt-5.4'), owned('')] {
			assert notice.for_model(&other) == .limited
		}
	}
	config := fixture_config([auth_reply(), auth_reply()])
	cloned := codex_core.clone_config_with_cwd(&config, owned('/changed'))
	assert config.chatgpt_base_url == cloned.chatgpt_base_url
	assert config.model_provider_id == cloned.model_provider_id
	for _ in 0 .. 2 {
		loaded := cloned.auth_config().load_auth(false) or { panic(err) }
		assert loaded.has_value
		assert loaded.value.get_token() or { panic(err) } == 'token'
		assert loaded.value.get_token() or { panic(err) } == 'token'
		assert loaded.value.get_account_id() == ?string('account')
		assert loaded.value.token == 'token'
	}
	assert config.auth_config().daybreak_load_flags() == [false, false]
	assert config.cwd == '/tmp'
	assert cloned.cwd == '/changed'
}
