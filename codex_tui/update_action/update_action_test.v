module update_action

import codex_install_context
import codex_utils_absolute_path
import os
import shlex

fn test_maps_install_context_to_update_action() {
	native_release_path := os.join_path(os.temp_dir(), 'native-release')
	native_release_dir := codex_utils_absolute_path.from_absolute_path(&native_release_path) or {
		panic('temp dir path should be absolute')
	}
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Other{}
		package_layout: none
	}) == none
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Npm{}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.npm_global_latest)
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Bun{}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.bun_global_latest)
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Pnpm{}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.pnpm_global_latest)
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Brew{}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.brew_upgrade)
	resources_name := 'codex-resources'
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Standalone{
			platform:      .unix
			release_dir:   native_release_dir.clone()
			resources_dir: native_release_dir.join(&resources_name)
		}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.standalone_unix)
	assert UpdateAction.from_install_context(&codex_install_context.InstallContext{
		method:         codex_install_context.Standalone{
			platform:      .windows
			release_dir:   native_release_dir.clone()
			resources_dir: native_release_dir.join(&resources_name)
		}
		package_layout: none
	}) == ?UpdateAction(UpdateAction.standalone_windows)
}

fn test_standalone_update_commands_rerun_latest_installer() {
	unix_command, unix_args := UpdateAction.standalone_unix.command_args()
	assert unix_command == 'sh'
	assert unix_args == ['-c',
		'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh']
	windows_command, windows_args := UpdateAction.standalone_windows.command_args()
	assert windows_command == 'powershell'
	assert windows_args == ['-ExecutionPolicy', 'Bypass', '-c',
		r'$env:CODEX_NON_INTERACTIVE=1; irm https://chatgpt.com/codex/install.ps1 | iex']
}

fn test_vite_plus_context_is_supported() {
	context := codex_install_context.InstallContext{ method: codex_install_context.VitePlus{} }
	assert UpdateAction.from_install_context(&context) == ?UpdateAction(UpdateAction.vite_plus_global_latest)
}

fn test_update_commands_have_exact_shell_quoting_and_round_trip() {
	for action in [UpdateAction.npm_global_latest, .bun_global_latest, .vite_plus_global_latest,
		.pnpm_global_latest, .brew_upgrade, .standalone_unix, .standalone_windows] {
		command, args := action.command_args()
		command_string := action.command_str()
		parsed := shlex.split(&command_string) or { panic('command should round trip') }
		assert parsed.len == args.len + 1
		assert parsed[0] == command
		assert parsed[1..] == args
	}
	assert UpdateAction.npm_global_latest.command_str() == 'npm install -g @openai/codex'
	assert UpdateAction.bun_global_latest.command_str() == 'bun install -g @openai/codex'
	assert UpdateAction.vite_plus_global_latest.command_str() == 'vp install -g @openai/codex'
	assert UpdateAction.pnpm_global_latest.command_str() == 'pnpm add -g @openai/codex'
	assert UpdateAction.brew_upgrade.command_str() == 'brew upgrade --cask codex'
	assert UpdateAction.standalone_unix.command_str() == "sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh'"
	assert UpdateAction.standalone_windows.command_str() == "powershell -ExecutionPolicy Bypass -c '\$env:CODEX_NON_INTERACTIVE=1; irm https://chatgpt.com/codex/install.ps1 | iex'"
}

fn test_borrowed_context_retains_owned_paths_and_package_layout() {
	mut release_path := os.join_path(os.temp_dir(), 'owned-native-release')
	mut package_path := os.join_path(os.temp_dir(), 'owned-package')
	$if ownership ? {
		release_path = release_path.to_owned()
		package_path = package_path.to_owned()
	}
	release_dir := codex_utils_absolute_path.from_absolute_path(&release_path) or { panic(err) }
	package_dir := codex_utils_absolute_path.from_absolute_path(&package_path) or { panic(err) }
	resource_name := 'codex-resources'
	bin_name := 'bin'
	path_name := 'codex-path'
	context := codex_install_context.InstallContext{
		method:         codex_install_context.Standalone{
			platform:      .unix
			release_dir:   release_dir.clone()
			resources_dir: release_dir.join(&resource_name)
		}
		package_layout: codex_install_context.CodexPackageLayout{
			package_dir:   package_dir.clone()
			bin_dir:       package_dir.join(&bin_name)
			resources_dir: package_dir.join(&resource_name)
			path_dir:      package_dir.join(&path_name)
		}
	}
	for _ in 0 .. 2 {
		assert UpdateAction.from_install_context(&context) == ?UpdateAction(UpdateAction.standalone_unix)
	}
	method := &context.method
	assert method is codex_install_context.Standalone
	assert method.release_dir.path == release_path
	assert (method.resources_dir or { panic('resource owner') }).path.ends_with('codex-resources')
	layout := context.package_layout or { panic('package layout') }
	assert layout.package_dir.path == package_path
	assert layout.bin_dir.path.ends_with('bin')
	assert release_dir.path == release_path
	assert package_dir.path == package_path
	assert release_path.ends_with('owned-native-release')
	assert package_path.ends_with('owned-package')
}

fn test_current_context_fixture_retains_shared_owner() {
	context := codex_install_context.InstallContext{ method: codex_install_context.Pnpm{} }
	codex_install_context.InstallContext.set_current_fixture(context)
	first := codex_install_context.InstallContext.current()
	second := codex_install_context.InstallContext.current()
	assert first == second
	assert UpdateAction.from_install_context(first) == ?UpdateAction(UpdateAction.pnpm_global_latest)
	assert UpdateAction.from_install_context(second) == ?UpdateAction(UpdateAction.pnpm_global_latest)
	$if prod {
		// Production removes assert statements, including their API calls.
		// Keep the release-only public API and its repeated shared-owner check executable.
		if get_update_action() != ?UpdateAction(UpdateAction.pnpm_global_latest)
			|| get_update_action() != ?UpdateAction(UpdateAction.pnpm_global_latest) {
			panic('current installation lost its update action')
		}
	}
}
