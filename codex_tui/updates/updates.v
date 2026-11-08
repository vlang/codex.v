module updates

// Rust cfg(not(debug_assertions)) maps to V's release -prod define. Normal
// development builds intentionally omit this module's executable surface.
$if prod {
	import codex_core
	import codex_tui.npm_registry
	import codex_tui.update_action
	import codex_tui.update_versions
	import codex_tui.updates_cache
	import chrono
	import codex_http_client
	import codex_login.default_client
	import serde_json
	import std_path
	import tokio.fs
	import tracing
	import codex_tui.version

	// V has no cross-module function reexport. This public forwarding function
	// retains the Rust reexport's borrowed signature and error propagation.
	pub fn dismiss_version(config &codex_core.Config, latest &string) ! {
		updates_cache.dismiss_version(config, latest)!
	}

	pub fn get_upgrade_version(config &codex_core.Config) ?string {
		if !config.check_for_update_on_startup || update_versions.is_source_build_version(&version.codex_cli_version) {
			return none
		}
		action := update_action.get_update_action()
		version_file := updates_cache.version_filepath(config)
		path := std_path.Path.new(&version_file)
		// Splitting Rust's resource-bearing Option into this early return avoids
		// unsupported borrowed Option storage while retaining one cache read.
		info := updates_cache.read_version_info(&path) or {
			http_client_factory := config.http_client_factory()
			// Refresh the cached latest version in the background so TUI startup
			// isn’t blocked by a network call. The UI reads the previously cached
			// value (if any) for this run; the next run shows the banner if needed.
			spawn refresh_version_cache(version_file, action, http_client_factory)
			return none
		}
		if info.last_checked_at.before(chrono.Utc.now().sub(chrono.Duration.hours(20))) {
			http_client_factory := config.http_client_factory()
			// Refresh the cached latest version in the background so TUI startup
			// isn’t blocked by a network call. The UI reads the previously cached
			// value (if any) for this run; the next run shows the banner if needed.
			spawn refresh_version_cache(version_file, action, http_client_factory)
		}
		if update_versions.is_newer(&info.latest_version, &version.codex_cli_version) or { false } {
			return info.latest_version
		}
		return none
	}

	// V's spawn runs the moved async closure in a separate worker. The worker
	// constructs a borrowed Path view only after taking ownership of its bytes.
	fn refresh_version_cache(version_file string, action ?update_action.UpdateAction, factory codex_http_client.HttpClientFactory) {
		path := std_path.Path.new(&version_file)
		check_for_update(&path, action, factory) or { tracing.error_update_version(&err) }
	}

	// We use the latest version from the cask if installation is via homebrew - homebrew does not immediately pick up the latest release and can lag behind.
	const homebrew_cask_api_url = 'https://formulae.brew.sh/api/cask/codex.json'
	const latest_release_url = 'https://api.github.com/repos/openai/codex/releases/latest'

	// Rust derives Deserialize, Debug and Clone. V debug formatting is automatic;
	// the explicit methods retain serde validation and owned clone boundaries.
	struct ReleaseInfo {
		tag_name string
	}

	fn (info &ReleaseInfo) clone() ReleaseInfo {
		return ReleaseInfo{ tag_name: info.tag_name.clone() }
	}

	fn ReleaseInfo.deserialize_json(source &string) !ReleaseInfo {
		fields := ['tag_name']
		input := serde_json.deserialize_struct(source, &fields)!
		if input.is_sequence {
			if input.sequence.len != 1 {
				return error('invalid ReleaseInfo sequence length')
			}
			return ReleaseInfo{ tag_name: input.sequence[0].string_owned()! }
		}
		mut tag := ?string(none)
		for index in 0 .. input.fields.len {
			field := &input.fields[index]
			if tag != none {
				return error('duplicate field `tag_name`')
			}
			tag = field.value.string_owned()!
		}
		return ReleaseInfo{ tag_name: tag or { return error('missing field `tag_name`') } }
	}

	struct HomebrewCaskInfo {
		version string
	}

	fn (info &HomebrewCaskInfo) clone() HomebrewCaskInfo {
		return HomebrewCaskInfo{ version: info.version.clone() }
	}

	fn HomebrewCaskInfo.deserialize_json(source &string) !HomebrewCaskInfo {
		fields := ['version']
		input := serde_json.deserialize_struct(source, &fields)!
		if input.is_sequence {
			if input.sequence.len != 1 {
				return error('invalid HomebrewCaskInfo sequence length')
			}
			return HomebrewCaskInfo{ version: input.sequence[0].string_owned()! }
		}
		mut version_text := ?string(none)
		for index in 0 .. input.fields.len {
			field := &input.fields[index]
			if version_text != none {
				return error('duplicate field `version`')
			}
			version_text = field.value.string_owned()!
		}
		return HomebrewCaskInfo{ version: version_text or { return error('missing field `version`') } }
	}

	// The two awaited filesystem operations run synchronously inside this worker,
	// preserving source order while startup remains independent of the worker.
	fn check_for_update(version_file &std_path.Path, action ?update_action.UpdateAction, http_client_factory codex_http_client.HttpClientFactory) ! {
		client_pool := codex_http_client.RouteAwareClientPool.with_chatgpt_cloudflare_cookies(http_client_factory, .other).with_legacy_custom_ca_fallback()
		latest_version := if selected := action {
			match selected {
				.brew_upgrade {
					response := client_pool.get(&homebrew_cask_api_url).headers(default_client.default_headers()).send()!.error_for_status()!
					// The explicit serde derive function lets V3 infer json<T>'s
					// concrete return type inside this release-gated module.
					info := response.json(HomebrewCaskInfo.deserialize_json)!
					info.version
				}
				.npm_global_latest, .bun_global_latest, .vite_plus_global_latest,
				.pnpm_global_latest {
					latest := fetch_latest_github_release_version(&client_pool)!
					response := client_pool.get(&npm_registry.package_url).headers(default_client.default_headers()).send()!.error_for_status()!
					package_info := response.json(npm_registry.NpmPackageInfo.deserialize_json)!
					npm_registry.ensure_version_ready(&package_info, &latest)!
					latest
				}
				.standalone_unix, .standalone_windows {
					fetch_latest_github_release_version(&client_pool)!
				}
			}
		} else {
			fetch_latest_github_release_version(&client_pool)!
		}

		// Preserve any previously dismissed version if present.
		prev_info := updates_cache.read_version_info(version_file) or { updates_cache.VersionInfo{} }
		info := updates_cache.VersionInfo{ latest_version: latest_version, last_checked_at: chrono.Utc.now(), dismissed_version: prev_info.dismissed_version }
		json_line := serde_json.to_string(&info)! + '\n'
		if parent := version_file.parent() { fs.create_dir_all(&parent)! }
		fs.write(version_file.to_path_buf(), json_line)!
	}

	fn fetch_latest_github_release_version(client_pool &codex_http_client.RouteAwareClientPool) !string {
		response := client_pool.get(&latest_release_url).headers(default_client.default_headers()).send()!.error_for_status()!
		info := response.json(ReleaseInfo.deserialize_json)!
		return update_versions.extract_version_from_latest_tag(&info.tag_name)
	}

	/// Returns the latest version to show in a popup, if it should be shown.
	/// This respects the user's dismissal choice for the current latest version.
	pub fn get_upgrade_version_for_popup(config &codex_core.Config) ?string {
		if !config.check_for_update_on_startup || update_versions.is_source_build_version(&version.codex_cli_version) {
			return none
		}
		version_file := updates_cache.version_filepath(config)
		latest := get_upgrade_version(config) or { return none }
		path := std_path.Path.new(&version_file)
		if info := updates_cache.read_version_info(&path) {
			// If the user dismissed this exact version previously, do not show the popup.
			if dismissed := info.dismissed_version {
				if dismissed == latest {
					return none
				}
			}
		}
		return latest
	}
}
