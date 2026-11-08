module status

import chrono
import codex_core
import codex_protocol.account
import codex_tui.width
import codex_utils_absolute_path
import codex_utils_path_uri
import dirs
import os
import rand
import std_path

struct FixtureTempDir {
	path string
}

fn new_fixture_temp_dir() FixtureTempDir {
	path := os.join_path(os.temp_dir(), 'codex-status-helpers-${rand.uuid_v4()}')
	os.mkdir(path.clone()) or { panic(err) }
	return FixtureTempDir{ path: path }
}

// Rust's async test_config helper needs only these ConfigBuilder overrides.
// The typed builder's in-memory dependency boundary preserves their call order.
fn fixture_config(codex_home &FixtureTempDir, cwd &FixtureTempDir) codex_core.Config {
	return codex_core.ConfigBuilder.default()
		.codex_home(codex_home.path.clone())
		.fallback_cwd(cwd.path.clone())
		.build() or { panic('load config: ${err}') }
}

fn fixture_abs(path &string) codex_utils_absolute_path.AbsolutePathBuf {
	return codex_utils_absolute_path.from_absolute_path(path) or { panic(err) }
}

fn test_plan_type_display_name_remaps_display_labels() {
	plans := [account.PlanType.free, .go, .plus, .pro, .pro_lite, .team,
		.self_serve_business_usage_based, .business, .enterprise_cbp_automation,
		.enterprise_cbp_usage_based, .enterprise, .edu, .unknown]
	expected := ['Free', 'Go', 'Plus', 'Pro', 'Pro Lite', 'Business', 'Business', 'Enterprise',
		'Enterprise (Automation)', 'Enterprise', 'Enterprise', 'Edu', 'Unknown']
	for i, plan in plans {
		assert plan_type_display_name(plan) == expected[i]
	}
	assert plan_type_display_name(.self_serve_business_pro_lite) == 'Business Premium'
	names := [plan_type_display_name(.edu), plan_type_display_name(.edu_plus),
		plan_type_display_name(.edu_pro)]
	snapshot := $embed_file('fixtures/education_plan_display_names.snap').to_string()
	assert names.join('\n') + '\n' == snapshot.split('---\n')[2]
}

fn test_format_directory_display_truncates_halfwidth_sound_marks() {
	directory := os.join_path('workspace', 'ｶﾞ', 'project')
	max_width := width.display_width(&directory) - 1
	path := std_path.Path.new(&directory)
	formatted := format_directory_display(&path, max_width)
	assert formatted.replace('\\', '/') == 'workspace/…/project'
}

fn test_compose_agents_summary_includes_global_agents_path() {
	codex_home := new_fixture_temp_dir()
	cwd := new_fixture_temp_dir()
	defer { os.rmdir(codex_home.path.clone()) or { panic(err) } }
	defer { os.rmdir(cwd.path.clone()) or { panic(err) } }
	global_agents_path := os.join_path(codex_home.path.clone(), 'global.md')
	config := fixture_config(&codex_home, &cwd)
	absolute := fixture_abs(&global_agents_path)
	paths := [codex_utils_path_uri.PathUri.from_abs_path(&absolute)]
	path := std_path.Path.new(&global_agents_path)
	assert compose_agents_summary(&config, &paths) == format_directory_display(&path, /* max_width */
		none)
}

fn test_compose_agents_summary_collapses_home_and_preserves_project_relative_paths() {
	home := dirs.home_dir() or { return }
	codex_home := new_fixture_temp_dir()
	cwd := new_fixture_temp_dir()
	defer { os.rmdir(codex_home.path.clone()) or { panic(err) } }
	defer { os.rmdir(cwd.path.clone()) or { panic(err) } }
	mut config := fixture_config(&codex_home, &cwd)
	config.cwd = os.join_path(home.clone(), 'workspace', 'project')
	raw_paths := [os.join_path(home.clone(), '.codex', 'AGENTS.md'),
		os.join_path(home.clone(), 'workspace', 'AGENTS.md'),
		os.join_path(config.cwd.clone(), 'AGENTS.md'),
		os.join_path(config.cwd.clone(), 'nested', 'AGENTS.md')]
	mut paths := []codex_utils_path_uri.PathUri{}
	for raw in raw_paths {
		absolute := fixture_abs(&raw)
		paths << codex_utils_path_uri.PathUri.from_abs_path(&absolute)
	}
	summary := compose_agents_summary(&config, &paths)
	assert summary.replace('\\', '/') == '~/.codex/AGENTS.md, ../AGENTS.md, AGENTS.md, nested/AGENTS.md'
}

fn test_compose_agents_summary_names_global_agents_override() {
	codex_home := new_fixture_temp_dir()
	cwd := new_fixture_temp_dir()
	defer { os.rmdir(codex_home.path.clone()) or { panic(err) } }
	defer { os.rmdir(cwd.path.clone()) or { panic(err) } }
	override_path := os.join_path(codex_home.path.clone(), 'override.md')
	config := fixture_config(&codex_home, &cwd)
	absolute := fixture_abs(&override_path)
	paths := [codex_utils_path_uri.PathUri.from_abs_path(&absolute)]
	path := std_path.Path.new(&override_path)
	assert compose_agents_summary(&config, &paths) == format_directory_display(&path, /* max_width */
		none)
}

fn test_compose_agents_summary_shows_relative_native_and_full_foreign_paths() {
	codex_home := new_fixture_temp_dir()
	cwd := new_fixture_temp_dir()
	defer { os.rmdir(codex_home.path.clone()) or { panic(err) } }
	defer { os.rmdir(cwd.path.clone()) or { panic(err) } }
	config := fixture_config(&codex_home, &cwd)
	native := os.join_path(config.cwd.clone(), 'AGENTS.md')
	absolute := fixture_abs(&native)
	native_source := codex_utils_path_uri.PathUri.from_abs_path(&absolute)
	foreign_uri := $if windows {
		'file:///remote%20workspace/AGENTS.md'
	} $else {
		'file:///C:/remote%20workspace/AGENTS.md'
	}
	foreign_source := codex_utils_path_uri.PathUri.parse(&foreign_uri) or { panic(err) }
	paths := [native_source, foreign_source]
	summary := compose_agents_summary(&config, &paths)
	$if windows {
		assert summary == 'AGENTS.md, /remote workspace/AGENTS.md'
	} $else {
		assert summary == 'AGENTS.md, C:\\remote workspace\\AGENTS.md'
	}
}

fn test_compose_agents_summary_orders_global_before_project_agents() {
	codex_home := new_fixture_temp_dir()
	cwd := new_fixture_temp_dir()
	defer { os.rmdir(codex_home.path.clone()) or { panic(err) } }
	defer { os.rmdir(cwd.path.clone()) or { panic(err) } }
	global_agents_path := os.join_path(codex_home.path.clone(), 'global.md')
	project_agents_path := os.join_path(cwd.path.clone(), 'project.md')
	config := fixture_config(&codex_home, &cwd)
	global_abs := fixture_abs(&global_agents_path)
	project_abs := fixture_abs(&project_agents_path)
	paths := [codex_utils_path_uri.PathUri.from_abs_path(&global_abs),
		codex_utils_path_uri.PathUri.from_abs_path(&project_abs)]
	summary := compose_agents_summary(&config, &paths)
	pieces := summary.split(', ')
	path := std_path.Path.new(&global_agents_path)
	assert pieces[0] == format_directory_display(&path, /* max_width */
		none)
	assert pieces[1].ends_with('project.md')
	assert pieces.len == 2
}

fn test_model_display_uses_first_matching_entry_and_ascii_only_case_folding() {
	model := 'GPT-é'
	effort_key := 'reasoning effort'
	summary_key := 'reasoning summaries'
	entries := [ModelDisplayEntry{ key: &effort_key, value: 'HIGH É'.clone() },
		ModelDisplayEntry{ key: &effort_key, value: 'ignored'.clone() },
		ModelDisplayEntry{ key: &summary_key, value: '\u2003OFF\u00a0'.clone() },
		ModelDisplayEntry{ key: &summary_key, value: 'ignored'.clone() }]
	name, details := compose_model_display(&model, &entries)
	assert name == 'GPT-é'
	assert details == ['reasoning high É', 'summaries off']
	empty := []ModelDisplayEntry{}
	empty_name, empty_details := compose_model_display(&model, &empty)
	assert empty_name == model
	assert empty_details.len == 0
	summaries := [ModelDisplayEntry{ key: &summary_key, value: ' Detailed É '.clone() }]
	_, on_details := compose_model_display(&model, &summaries)
	assert on_details == ['summaries detailed É']
}

fn test_account_display_clones_active_payload_and_preserves_owner() {
	mut email := 'owner@example.com'
	mut plan := 'Business'
	$if ownership ? {
		email = email.to_owned()
		plan = plan.to_owned()
	}
	owner := StatusAccountDisplay{ kind: .chat_gpt, email: email, plan: plan }
	borrowed := BorrowedStatusAccountDisplay{ has_value: true, value: &owner }
	mut copied := compose_account_display(borrowed) or { panic('missing account') }
	again := compose_account_display(borrowed) or { panic('missing second account') }
	assert copied == owner
	assert again == owner
	copied.email = 'changed'.clone()
	assert owner.email or { '' } == 'owner@example.com'
	assert owner.plan or { '' } == 'Business'
	assert compose_account_display(BorrowedStatusAccountDisplay{}) == none
	api := StatusAccountDisplay{ kind: .api_key }
	assert compose_account_display(BorrowedStatusAccountDisplay{ has_value: true, value: &api }) or { panic('missing API key') } == api
}

fn test_directory_home_zero_width_and_borrowed_owner_reuse() {
	mut native := 'workspace/宽/project'
	$if ownership ? {
		native = native.to_owned()
	}
	path := std_path.Path.new(&native)
	assert format_directory_display(&path, none) == native
	assert format_directory_display(&path, none) == native
	assert native == 'workspace/宽/project'
	assert format_directory_display(&path, usize(0)) == ''
	home := dirs.home_dir() or { return }
	home_path := std_path.Path.new(&home)
	assert format_directory_display(&home_path, none) == '~'
	assert home.len > 0
}

fn test_compact_tokens_preserves_exact_rust_rounding_and_i64_boundaries() {
	values := [i64(-1), 0, 999, 1000, 1005, 1025, 1055, 1125, 10125, 12500, 12650, 999999, 1000000,
		1234567, 1000000000, 1000000000000, 9223372036854775807]
	expected := ['0', '0', '999', '1K', '1K', '1.02K', '1.05K', '1.12K', '10.1K', '12.5K', '12.7K',
		'1000K', '1M', '1.23M', '1B', '1T', '9223372T']
	for i, value in values {
		assert format_tokens_compact(value) == expected[i]
	}
}

fn test_reset_timestamp_compares_local_dates_and_formats_fixed_english_months() {
	captured := chrono.DateTimeLocal{ timestamp: chrono.DateTimeUtc{ seconds: 1767225600 }, offset_seconds: 10800 }
	same_day := chrono.DateTimeLocal{ timestamp: chrono.DateTimeUtc{ seconds: 1767263400 }, offset_seconds: 10800 }
	assert format_reset_timestamp(same_day, captured) == '13:30'
	next_day := chrono.DateTimeLocal{ timestamp: chrono.DateTimeUtc{ seconds: 1767312000 }, offset_seconds: 10800 }
	assert format_reset_timestamp(next_day, captured) == '03:00 on 2 Jan'
	same_instant_other_day := chrono.DateTimeLocal{ timestamp: chrono.DateTimeUtc{ seconds: 1767225600 }, offset_seconds: -3600 }
	assert format_reset_timestamp(same_instant_other_day, captured) == '23:00 on 31 Dec'
}

fn test_title_case_expands_unicode_first_scalar_and_ascii_folds_only_the_rest() {
	samples := ['', 'hELLO', 'ßUPPERÉ', 'éCOLE']
	expected := ['', 'Hello', 'SSupperÉ', 'École']
	for i, sample in samples {
		assert title_case(&sample) == expected[i]
	}
}

fn test_agents_summary_preserves_config_uri_owners_and_root_ancestor_edge_case() {
	mut cwd := os.join_path(os.temp_dir(), 'codex-status-parent', 'child')
	mut raw := os.join_path(cwd.clone(), 'AGENTS.md')
	$if ownership ? {
		cwd = cwd.to_owned()
		raw = raw.to_owned()
	}
	config := codex_core.Config{ cwd: cwd }
	absolute := fixture_abs(&raw)
	paths := [codex_utils_path_uri.PathUri.from_abs_path(&absolute)]
	assert compose_agents_summary(&config, &paths) == 'AGENTS.md'
	assert compose_agents_summary(&config, &paths) == 'AGENTS.md'
	assert config.cwd.ends_with('child')
	assert paths[0].path.ends_with('AGENTS.md')
	assert raw.ends_with('AGENTS.md')
	assert compose_agents_summary(&config, &[]codex_utils_path_uri.PathUri{}) == '<none>'
	// Rust stops the ancestor loop before checking root, so a root file retains
	// its absolute display rather than receiving a sequence of '..' segments.
	root_file := $if windows { 'C:\\AGENTS.md' } $else { '/AGENTS.md' }
	root_abs := fixture_abs(&root_file)
	root_paths := [codex_utils_path_uri.PathUri.from_abs_path(&root_abs)]
	root_view := std_path.Path.new(&root_file)
	assert compose_agents_summary(&config, &root_paths) == format_directory_display(&root_view, none)
}

fn test_model_display_borrows_dynamic_entries_and_key_owners() {
	mut model := 'owned-model'
	mut key := 'reasoning effort'
	mut effort := 'HIGH'
	$if ownership ? {
		model = model.to_owned()
		key = key.to_owned()
		effort = effort.to_owned()
	}
	entries := [ModelDisplayEntry{ key: &key, value: effort }]
	first, first_details := compose_model_display(&model, &entries)
	second, second_details := compose_model_display(&model, &entries)
	assert first == 'owned-model'
	assert second == 'owned-model'
	assert first_details == ['reasoning high']
	assert second_details == ['reasoning high']
	assert model == 'owned-model'
	assert key == 'reasoning effort'
	assert entries[0].value == 'HIGH'
}

fn test_agents_summary_retains_unknown_conventions_and_opaque_native_paths() {
	cwd := os.join_path(os.temp_dir(), 'codex-status-source')
	config := codex_core.Config{ cwd: cwd }
	// A canonical opaque payload with no absolute-path prefix has no convention.
	opaque_text := 'file:///%00/bad/path/b3BhcXVl'
	unknown := codex_utils_path_uri.PathUri.parse(&opaque_text) or { panic(err) }
	paths := [unknown]
	assert compose_agents_summary(&config, &paths) == opaque_text
	// The fallback retains absolute native Unix bytes with a null as a lexical
	// PathBuf value. Filesystem APIs, rather than this pure conversion, reject NUL.
	$if !windows {
		null_text := 'file:///%00/bad/path/L2EA'
		native_invalid := codex_utils_path_uri.PathUri.parse(&null_text) or { panic(err) }
		round_trip := native_invalid.to_abs_path() or { panic(err) }
		assert round_trip.path == '/a\x00'
		invalid_paths := [native_invalid]
		assert compose_agents_summary(&config, &invalid_paths) == '/a\x00'
	}
}

fn test_opaque_native_paths_require_source_round_trip_before_relativizing() {
	$if !windows {
		config := codex_core.Config{ cwd: '/'.clone() }
		// '/a' has an ordinary URI, so this opaque spelling is not its identity.
		ordinary_as_opaque := 'file:///%00/bad/path/L2E'
		forged := codex_utils_path_uri.PathUri.parse(&ordinary_as_opaque) or { panic(err) }
		if _ := forged.to_abs_path() {
			assert false, 'noncanonical opaque path must fail native conversion'
		}
		assert compose_agents_summary(&config, &[forged]) == '/a'
		// A native null-containing path requires the opaque representation and
		// must still round-trip and use the ordinary project-relative summary.
		null_uri := 'file:///%00/bad/path/L2EA'
		genuine := codex_utils_path_uri.PathUri.parse(&null_uri) or { panic(err) }
		absolute := genuine.to_abs_path() or { panic(err) }
		assert absolute.path == '/a\x00'
		assert codex_utils_path_uri.PathUri.from_abs_path(&absolute).path == null_uri
		assert compose_agents_summary(&config, &[genuine]) == 'a\x00'
	}
}
