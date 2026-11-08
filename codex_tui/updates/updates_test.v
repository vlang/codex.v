module updates

import os
import rand
import time
import chrono
import codex_core
import codex_features
import codex_http_client
import codex_install_context
import codex_login.default_client
import codex_tui.update_action
import codex_tui.update_versions
import codex_tui.updates_cache
import codex_tui.version
import http
import std_path

$if prod {
	import codex_tui.npm_registry
}

fn updates_owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

// V3's -prod mode removes ordinary assert statements even from test entries.
// A runtime check keeps both the tested call and its condition executable.
fn updates_assert(condition bool, location string) {
	if !condition { panic('updates fixture assertion failed: ${location}') }
}

// Executable in development builds where the source update module is omitted.
fn test_config_factory_borrows_heap_owner_and_retains_resolved_policy() {
	text := '/tmp/updates-owner-${rand.uuid_v4()}'
	home := updates_owned(&text)
	config := codex_core.Config{ codex_home: home, respect_system_proxy: true, features: codex_features.Features{ enabled_features: [.psp] } }
	first := config.http_client_factory()
	second := config.http_client_factory()
	updates_assert(first.outbound_proxy_policy() == .respect_system_proxy, @FN)
	updates_assert(first.has_chatgpt_cookies(), @FN)
	updates_assert(second.outbound_proxy_policy() == .respect_system_proxy, @FN)
	updates_assert(second.has_chatgpt_cookies(), @FN)
	updates_assert(config.codex_home == text, @FN)
	updates_assert(config.features.enabled(.psp), @FN)
}

$if prod {
	fn updates_tempdir() string {
		path := os.join_path(os.temp_dir(), 'codex-updates-${rand.uuid_v4()}')
		os.mkdir(path.clone()) or { panic(err) }
		return path
	}

	fn updates_config(home &string) codex_core.Config {
		return codex_core.Config{ codex_home: updates_owned(home) }
	}

	fn updates_begin() {
		chrono.set_updates_clock_fixture(chrono.DateTimeUtc{ seconds: 172_800, nanoseconds: 123 })
		default_client.set_updates_headers_fixture(http.HeaderMap{
			values: {
				'originator':         'codex_cli'
				'user-agent':         'fixture-agent'
				'x-openai-residency': 'us'
			}
		})
		codex_install_context.InstallContext.set_current_fixture(codex_install_context.InstallContext{ method: codex_install_context.Other{} })
	}

	fn updates_end() {
		codex_http_client.clear_updates_transport_fixture()
		default_client.clear_updates_headers_fixture()
		chrono.clear_updates_clock_fixture()
	}

	fn updates_write_cache(config &codex_core.Config, latest &string, checked chrono.DateTimeUtc, dismissed ?string) {
		info := updates_cache.VersionInfo{ latest_version: latest.clone(), last_checked_at: checked, dismissed_version: dismissed }
		os.write_file(updates_cache.version_filepath(config), info.serialize_json() or { panic(err) }) or { panic(err) }
	}

	fn updates_read_cache(config &codex_core.Config) updates_cache.VersionInfo {
		filename := updates_cache.version_filepath(config)
		path := std_path.Path.new(&filename)
		return updates_cache.read_version_info(&path) or { panic(err) }
	}

	fn updates_wait_for_version(config &codex_core.Config, latest &string) {
		for _ in 0 .. 2000 {
			filename := updates_cache.version_filepath(config)
			path := std_path.Path.new(&filename)
			if info := updates_cache.read_version_info(&path) {
				if info.latest_version == *latest {
					return
				}
			}
			time.sleep(time.millisecond)
		}
		panic('background cache refresh did not complete')
	}

	fn updates_expect_error(path &std_path.Path, action ?update_action.UpdateAction, factory codex_http_client.HttpClientFactory, expected &string) {
		if _ := check_for_update(path, action, factory) {
			updates_assert(false, @FN)
		} else {
			updates_assert(err.msg().contains(*expected), @FN)
		}
	}

	fn test_disabled_or_source_build_does_not_resolve_installation_or_touch_cache() {
		home := '/tmp/codex-nonexistent-${rand.uuid_v4()}'
		config := codex_core.Config{ codex_home: updates_owned(&home), check_for_update_on_startup: false }
		updates_assert(get_upgrade_version(&config) == none, @FN)
		updates_assert(get_upgrade_version_for_popup(&config) == none, @FN)
		updates_assert(config.codex_home == home, @FN)
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			enabled := updates_config(&home)
			updates_assert(get_upgrade_version(&enabled) == none, @FN)
			updates_assert(get_upgrade_version_for_popup(&enabled) == none, @FN)
			updates_assert(enabled.codex_home == home, @FN)
		}
		updates_assert(!os.exists(home.clone()), @FN)
	}

	fn test_fresh_cache_equal_threshold_and_future_do_not_refresh() {
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			return
		}
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		config := updates_config(&root)
		latest := '999.0.0'
		for timestamp in [chrono.Utc.now(), chrono.Utc.now().sub(chrono.Duration.hours(20)),
			chrono.DateTimeUtc{ seconds: 999_999 }] {
			updates_write_cache(&config, &latest, timestamp, none)
			codex_http_client.set_updates_transport_fixture([]codex_http_client.UpdatesResponseFixture{})
			updates_assert(get_upgrade_version(&config) or { panic('missing cached update') } == latest, @FN)
			updates_assert(get_upgrade_version(&config) or { panic('missing repeated update') } == latest, @FN)
			updates_assert(codex_http_client.updates_request_observations().len == 0, @FN)
			updates_assert(config.codex_home == root, @FN)
		}
	}

	fn test_one_nanosecond_stale_returns_before_background_http_and_preserves_dismissal() {
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			return
		}
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		config := updates_config(&root)
		latest := '999.0.0'
		updates_write_cache(&config, &latest, chrono.DateTimeUtc{ seconds: 100_800, nanoseconds: 122 }, '999.0.0')
		release := chan bool{cap: 1}
		codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v999.1.0"}', block_until_released: true, gate: release }])
		start := time.now()
		updates_assert(get_upgrade_version(&config) or { panic('missing cached update') } == latest, @FN)
		updates_assert(time.since(start) < time.second, @FN)
		for _ in 0 .. 2000 {
			if codex_http_client.updates_request_observations().len == 1 {
				break
			}
			time.sleep(time.millisecond)
		}
		updates_assert(codex_http_client.updates_request_observations().len == 1, @FN)
		updates_assert(updates_read_cache(&config).latest_version == latest, @FN)
		release <- true
		refreshed := '999.1.0'
		updates_wait_for_version(&config, &refreshed)
		info := updates_read_cache(&config)
		updates_assert(info.last_checked_at == chrono.Utc.now(), @FN)
		updates_assert(info.dismissed_version or { panic('lost dismissal') } == latest, @FN)
		updates_assert(get_upgrade_version(&config) or { panic('missing next run update') } == refreshed, @FN)
	}

	fn test_missing_and_malformed_cache_return_none_and_refresh_next_run() {
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			return
		}
		for malformed in [false, true] {
			root := updates_tempdir()
			defer { os.rmdir_all(root.clone()) or { panic(err) } }
			updates_begin()
			config := updates_config(&root)
			if malformed {
				os.write_file(updates_cache.version_filepath(&config), '{broken') or { panic(err) }
			}
			release := chan bool{cap: 1}
			codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v999.0.0"}', block_until_released: true, gate: release }])
			updates_assert(get_upgrade_version(&config) == none, @FN)
			release <- true
			latest := '999.0.0'
			updates_wait_for_version(&config, &latest)
			updates_assert(get_upgrade_version(&config) or { panic('missing cached update') } == latest, @FN)
			updates_end()
		}
	}

	fn test_current_older_and_invalid_versions_do_not_show_upgrade() {
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			return
		}
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		config := updates_config(&root)
		for latest in [version.codex_cli_version, '0.0.0', 'not-a-version'] {
			updates_write_cache(&config, &latest, chrono.Utc.now(), none)
			updates_assert(get_upgrade_version(&config) == none, @FN)
			updates_assert(get_upgrade_version_for_popup(&config) == none, @FN)
		}
	}

	fn test_popup_exact_dismissal_and_forwarded_dismissal_keep_heap_owner_reusable() {
		if update_versions.is_source_build_version(&version.codex_cli_version) {
			return
		}
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		config := updates_config(&root)
		literal := '999.0.0'
		latest := updates_owned(&literal)
		updates_write_cache(&config, &latest, chrono.Utc.now(), '998.0.0')
		updates_assert(get_upgrade_version_for_popup(&config) or { panic('different dismissal hid update') } == latest, @FN)
		dismiss_version(&config, &latest) or { panic(err) }
		dismiss_version(&config, &latest) or { panic(err) }
		updates_assert(get_upgrade_version_for_popup(&config) == none, @FN)
		updates_assert(get_upgrade_version(&config) or { panic('dismissal hid cached version') } == latest, @FN)
		updates_assert(latest == literal, @FN)
		updates_assert(config.codex_home == root, @FN)
	}

	fn test_brew_cask_version_preserves_request_policies_headers_and_cache_newline() {
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		filename := os.join_path(root.clone(), 'nested', 'cache', 'version.json')
		path := std_path.Path.new(&filename)
		config := codex_core.Config{ respect_system_proxy: true, features: codex_features.Features{ enabled_features: [.psp] } }
		codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: '{"version":"2.3.4","unrelated":{"ignored":true}}' }])
		check_for_update(&path, .brew_upgrade, config.http_client_factory()) or { panic(err) }
		requests := codex_http_client.updates_request_observations()
		updates_assert(requests.len == 1, @FN)
		updates_assert(requests[0].url == homebrew_cask_api_url, @FN)
		expected_headers := {
			'originator':         'codex_cli'
			'user-agent':         'fixture-agent'
			'x-openai-residency': 'us'
		}
		updates_assert(requests[0].headers.values == expected_headers, @FN)
		updates_assert(requests[0].proxy_policy == .respect_system_proxy, @FN)
		updates_assert(requests[0].route_class == .other, @FN)
		updates_assert(requests[0].configured_cookies == ['oai-chat-psp=true'], @FN)
		updates_assert(requests[0].cloudflare_cookies, @FN)
		updates_assert(requests[0].legacy_custom_ca_fallback, @FN)
		info := updates_cache.read_version_info(&path) or { panic(err) }
		updates_assert(info.latest_version == '2.3.4', @FN)
		updates_assert(info.last_checked_at == chrono.Utc.now(), @FN)
		updates_assert(info.dismissed_version == none, @FN)
		updates_assert(os.read_file(filename.clone()) or { panic(err) } == '{"latest_version":"2.3.4","last_checked_at":"1970-01-03T00:00:00.000000123Z","dismissed_version":null}\n', @FN)
		updates_assert(filename.ends_with(os.join_path('nested', 'cache', 'version.json')), @FN)
	}

	fn test_standalone_and_unknown_installations_request_only_github() {
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		filename := os.join_path(root.clone(), 'version.json')
		path := std_path.Path.new(&filename)
		for index in 0 .. 3 {
			codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v2.3.4"}' }])
			if index == 2 {
				check_for_update(&path, none, codex_http_client.HttpClientFactory.new(.reqwest_default)) or { panic(err) }
			} else {
				selected := if index == 0 {
					update_action.UpdateAction.standalone_unix
				} else {
					update_action.UpdateAction.standalone_windows
				}
				check_for_update(&path, selected, codex_http_client.HttpClientFactory.new(.reqwest_default)) or { panic(err) }
			}
			requests := codex_http_client.updates_request_observations()
			updates_assert(requests.len == 1, @FN)
			updates_assert(requests[0].url == latest_release_url, @FN)
			updates_assert(requests[0].proxy_policy == .reqwest_default, @FN)
			updates_assert(requests[0].configured_cookies.len == 0, @FN)
			info := updates_cache.read_version_info(&path) or { panic(err) }
			updates_assert(info.latest_version == '2.3.4', @FN)
		}
	}

	fn test_all_package_managers_require_github_and_matching_ready_npm_dist() {
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		filename := os.join_path(root.clone(), 'version.json')
		path := std_path.Path.new(&filename)
		for selected in [update_action.UpdateAction.npm_global_latest, .bun_global_latest,
			.vite_plus_global_latest, .pnpm_global_latest] {
			codex_http_client.set_updates_transport_fixture([
				codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v2.3.4"}' },
				codex_http_client.UpdatesResponseFixture{ body: '{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{"dist":{"tarball":"https://registry/npm.tgz","integrity":"sha512-checked"}}}}' },
			])
			check_for_update(&path, selected, codex_http_client.HttpClientFactory.new(.reqwest_default)) or { panic(err) }
			requests := codex_http_client.updates_request_observations()
			updates_assert(requests.len == 2, @FN)
			updates_assert(requests[0].url == latest_release_url, @FN)
			updates_assert(requests[1].url == 'https://registry.npmjs.org/@openai%2fcodex', @FN)
			info := updates_cache.read_version_info(&path) or { panic(err) }
			updates_assert(info.latest_version == '2.3.4', @FN)
		}
	}

	fn test_registry_readiness_failures_leave_previous_cache_unchanged() {
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		filename := os.join_path(root.clone(), 'version.json')
		path := std_path.Path.new(&filename)
		previous := '{"latest_version":"1.2.3","last_checked_at":"1970-01-01T00:00:00Z","dismissed_version":"1.2.3"}\n'
		os.write_file(filename.clone(), previous.clone()) or { panic(err) }
		bodies := ['{"dist-tags":{"latest":"2.3.3"},"versions":{}}', '{"dist-tags":{},"versions":{}}',
			'{"dist-tags":{"latest":"2.3.4"},"versions":{}}',
			'{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{}}}',
			'{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{"dist":{"integrity":"sha512-x"}}}}',
			'{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{"dist":{"tarball":""}}}}',
			'{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{"dist":{"tarball":"url","integrity":""}}}}']
		errors := ['latest dist-tag', 'missing latest dist-tag', 'version 2.3.4 is missing',
			'missing dist metadata', 'missing dist.tarball', 'missing dist.tarball',
			'missing dist.integrity']
		for index in 0 .. bodies.len {
			codex_http_client.set_updates_transport_fixture([
				codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v2.3.4"}' },
				codex_http_client.UpdatesResponseFixture{ body: bodies[index].clone() },
			])
			updates_expect_error(&path, .npm_global_latest, codex_http_client.HttpClientFactory.new(.reqwest_default), &errors[index])
			updates_assert(os.read_file(filename.clone()) or { panic(err) } == previous, @FN)
		}
	}

	fn test_transport_status_json_tag_and_filesystem_errors_propagate_without_cache_write() {
		root := updates_tempdir()
		defer { os.rmdir_all(root.clone()) or { panic(err) } }
		updates_begin()
		defer { updates_end() }
		filename := os.join_path(root.clone(), 'version.json')
		path := std_path.Path.new(&filename)
		fixtures := [
			codex_http_client.UpdatesResponseFixture{ transport_error: 'connection refused' },
			codex_http_client.UpdatesResponseFixture{ status: 503 },
			codex_http_client.UpdatesResponseFixture{ body: '{broken' },
			codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"v2.3.4"}' },
		]
		errors := ['connection refused', 'HTTP status 503', 'expected', 'Failed to parse latest tag']
		for index in 0 .. fixtures.len {
			item := &fixtures[index]
			codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ status: item.status, body: item.body.clone(), transport_error: item.transport_error.clone() }])
			updates_expect_error(&path, none, codex_http_client.HttpClientFactory.new(.reqwest_default), &errors[index])
			updates_assert(!os.exists(filename.clone()), @FN)
		}
		codex_http_client.set_updates_transport_fixture([codex_http_client.UpdatesResponseFixture{ body: '{"tag_name":"rust-v2.3.4"}' }])
		blocked := os.join_path(root.clone(), 'blocking-file')
		os.write_file(blocked.clone(), 'not a directory') or { panic(err) }
		unwritable := os.join_path(blocked.clone(), 'child', 'version.json')
		bad_path := std_path.Path.new(&unwritable)
		if _ := check_for_update(&bad_path, none, codex_http_client.HttpClientFactory.new(.reqwest_default)) {
			updates_assert(false, @FN)
		} else {
			updates_assert(err.msg().len > 0, @FN)
		}
		updates_assert(os.read_file(blocked.clone()) or { panic(err) } == 'not a directory', @FN)
		codex_http_client.clear_updates_transport_fixture()
		unavailable := 'untranslated'
		updates_expect_error(&path, none, codex_http_client.HttpClientFactory.new(.reqwest_default), &unavailable)
	}

	fn test_npm_readiness_repeatedly_borrows_owned_metadata_and_unicode_trimmed_version() {
		literal := '{"dist-tags":{"latest":"2.3.4"},"versions":{"2.3.4":{"dist":{"tarball":"https://registry/npm.tgz","integrity":"sha512-owned"}}}}'
		source := updates_owned(&literal)
		info := npm_registry.NpmPackageInfo.deserialize_json(&source) or { panic(err) }
		version_literal := '\u3000\u20032.3.4\u00a0'
		version_owner := updates_owned(&version_literal)
		npm_registry.ensure_version_ready(&info, &version_owner) or { panic(err) }
		npm_registry.ensure_version_ready(&info, &version_owner) or { panic(err) }
		updates_assert(info.str().contains('sha512-owned'), @FN)
		updates_assert(info.str().contains('https://registry/npm.tgz'), @FN)
		updates_assert(version_owner == version_literal, @FN)
		updates_assert(source == literal, @FN)
	}

	fn test_release_and_cask_serde_names_validation_clones_and_heap_borrow_reuse() {
		literal := '{"tag_name":"rust-v2.3.4","unknown":[1,2]}'
		source := updates_owned(&literal)
		first := ReleaseInfo.deserialize_json(&source) or { panic(err) }
		second := ReleaseInfo.deserialize_json(&source) or { panic(err) }
		updates_assert(first == second, @FN)
		updates_assert(first.clone() == second.clone(), @FN)
		updates_assert(first.tag_name == 'rust-v2.3.4', @FN)
		updates_assert(source == literal, @FN)
		for invalid in ['{}', '{"tag_name":null}', '{"tag_name":4}', '{"tag_name":"a","tag_name":"b"}',
			'[]', '["a","b"]', '{"tagName":"wrong-name"}'] {
			if _ := ReleaseInfo.deserialize_json(&invalid) {
				updates_assert(false, @FN)
			} else {
				updates_assert(err.msg().len > 0, @FN)
			}
		}
		sequence := '["rust-v2.3.4"]'
		updates_assert(ReleaseInfo.deserialize_json(&sequence) or { panic(err) } == first, @FN)
		cask_literal := '{"version":"2.3.4","unknown":false}'
		cask_source := updates_owned(&cask_literal)
		cask := HomebrewCaskInfo.deserialize_json(&cask_source) or { panic(err) }
		updates_assert(cask.clone() == HomebrewCaskInfo.deserialize_json(&cask_source) or { panic(err) }, @FN)
		updates_assert(cask_source == cask_literal, @FN)
		for invalid in ['{}', '{"version":null}', '{"version":"a","version":"b"}', '[1]'] {
			if _ := HomebrewCaskInfo.deserialize_json(&invalid) {
				updates_assert(false, @FN)
			} else {
				updates_assert(err.msg().len > 0, @FN)
			}
		}
		cask_sequence := '["2.3.4"]'
		updates_assert(HomebrewCaskInfo.deserialize_json(&cask_sequence) or { panic(err) } == cask, @FN)
	}
}
