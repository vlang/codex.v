module exec_command

import dirs
import os
import shlex
import std_path

fn test_escape_command() {
	args := ['foo', 'bar baz', 'weird&stuff']
	cmdline := escape_command(&args)
	assert cmdline == "foo 'bar baz' 'weird&stuff'"
}

fn test_strip_bash_lc_and_escape() {
	// Test bash
	args_bash := ['bash', '-lc', 'echo hello']
	cmdline_bash := strip_bash_lc_and_escape(&args_bash)
	assert cmdline_bash == 'echo hello'

	// Test zsh
	args_zsh := ['zsh', '-lc', 'echo hello']
	cmdline_zsh := strip_bash_lc_and_escape(&args_zsh)
	assert cmdline_zsh == 'echo hello'

	// Test absolute path to zsh
	args_absolute_zsh := ['/usr/bin/zsh', '-lc', 'echo hello']
	cmdline_absolute_zsh := strip_bash_lc_and_escape(&args_absolute_zsh)
	assert cmdline_absolute_zsh == 'echo hello'

	// Test absolute path to bash
	args_absolute_bash := ['/bin/bash', '-lc', 'echo hello']
	cmdline_absolute_bash := strip_bash_lc_and_escape(&args_absolute_bash)
	assert cmdline_absolute_bash == 'echo hello'
}

fn test_split_command_string_round_trips_shell_wrappers() {
	args := ['/bin/zsh', '-lc', 'python3 -c \'print("Hello, world!")\'']
	command := shlex.try_join(&args) or { panic('round-trippable command') }
	assert split_command_string(&command) == ['/bin/zsh', '-lc', 'python3 -c \'print("Hello, world!")\'']
}

fn test_split_command_string_preserves_non_roundtrippable_windows_commands() {
	command := r'C:\Program Files\Git\bin\bash.exe -lc "echo hi"'
	assert split_command_string(&command) == [command]
}

fn test_escape_command_nul_falls_back_to_space_join() {
	args := ['foo', 'a\x00b c', 'd&e']
	assert escape_command(&args) == 'foo a\x00b c d&e'
	if _ := shlex.try_join(&args) {
		assert false, 'NUL must produce the typed quoting error'
	} else {
		assert err is shlex.QuoteError
		assert err.kind == .nul
	}
}

fn test_split_command_string_keeps_malformed_and_nul_input() {
	for command in ['foo "unterminated', "foo 'unterminated", 'foo \\', 'foo a\x00b'] {
		assert split_command_string(&command) == [command]
	}
	command := '   foo "bar"baz # omitted\nbaz\\\nqux'
	assert split_command_string(&command) == ['foo', 'barbaz', 'bazqux']
}

fn test_shell_extraction_supports_source_shells_and_rejects_extra_bash_args() {
	args_sh := ['/bin/sh', '-c', 'echo hello']
	assert strip_bash_lc_and_escape(&args_sh) == 'echo hello'
	args_pwsh := ['/usr/local/bin/pwsh', '-NoProfile', '-c', 'echo hello', 'ignored']
	assert strip_bash_lc_and_escape(&args_pwsh) == 'echo hello'
	args_powershell := ['powershell.exe', '-NoLogo', '-NoProfile', '-Command', 'Write-Host hi']
	assert strip_bash_lc_and_escape(&args_powershell) == 'Write-Host hi'
	args_extra := ['bash', '-lc', 'echo hello', 'extra']
	assert strip_bash_lc_and_escape(&args_extra) == "bash -lc 'echo hello' extra"
	args_unknown_flag := ['pwsh', '-Unknown', '-Command', 'echo hi']
	assert strip_bash_lc_and_escape(&args_unknown_flag) == "pwsh -Unknown -Command 'echo hi'"
}

struct TestPathAdapter {
	path string
}

fn (path &TestPathAdapter) as_ref() std_path.Path {
	return std_path.Path.new(&path.path)
}

fn test_relativize_to_home_preserves_generic_path_adapters() {
	home := dirs.home_dir() or { panic('test requires a home directory') }
	path := os.join_path(home, 'codex-path', 'file')
	assert relativize_to_home(path.clone()) or { panic('inside home') } == os.join_path('codex-path',
		'file')
	assert relativize_to_home(&path) or { panic('inside home') } == os.join_path('codex-path', 'file')
	view := std_path.Path.new(&path)
	assert relativize_to_home(view) or { panic('path view inside home') } == os.join_path('codex-path',
		'file')
	assert relativize_to_home(&view) or { panic('borrowed path view inside home') } == os.join_path('codex-path',
		'file')
	assert relativize_to_home(TestPathAdapter{path.clone()}) or { panic('inside home') } == os.join_path('codex-path',
		'file')
	assert relativize_to_home(&home) or { panic('home itself') } == ''
	assert relativize_to_home('relative/path') == none
	out := '${home}-other/file'
	assert relativize_to_home(&out) == none
}

fn test_native_path_prefix_uses_components_without_resolving_parent_directories() {
	$if !windows {
		prefix := '/home/alex'
		repeated := '/home/alex//foo///bar//'
		dots := '/home/alex/./foo/./bar/.'
		home := '//home///alex'
		parent := '/home/alex/../other'
		outside := '/home/alexander/file'
		windows := r'C:\Users\Alex'
		prefix_path := std_path.Path.new(&prefix)
		repeated_path := std_path.Path.new(&repeated)
		assert (repeated_path.strip_prefix(&prefix_path) or { panic('inside') }).to_path_buf() == 'foo///bar'
		dots_path := std_path.Path.new(&dots)
		assert (dots_path.strip_prefix(&prefix_path) or { panic('inside') }).to_path_buf() == 'foo/./bar'
		home_path := std_path.Path.new(&home)
		assert (home_path.strip_prefix(&prefix_path) or { panic('home') }).to_path_buf() == ''
		parent_path := std_path.Path.new(&parent)
		assert (parent_path.strip_prefix(&prefix_path) or { panic('inside') }).to_path_buf() == '../other'
		outside_path := std_path.Path.new(&outside)
		if _ := outside_path.strip_prefix(&prefix_path) {
			assert false
		}
		windows_path := std_path.Path.new(&windows)
		assert windows_path.is_absolute() == false
	}
}

fn test_borrowed_command_owners_are_reusable() {
	mut executable := 'bash'
	mut flag := '-lc'
	mut script := 'echo hello'
	mut command := "foo 'bar baz'"
	$if ownership ? {
		executable = executable.to_owned()
		flag = flag.to_owned()
		script = script.to_owned()
		command = command.to_owned()
	}
	args := [executable, flag, script]
	for _ in 0 .. 2 {
		assert escape_command(&args) == "bash -lc 'echo hello'"
		assert strip_bash_lc_and_escape(&args) == 'echo hello'
		assert split_command_string(&command) == ['foo', 'bar baz']
	}
	assert args == ['bash', '-lc', 'echo hello']
	assert command == "foo 'bar baz'"
}

fn test_borrowed_path_owner_is_reusable() {
	home := dirs.home_dir() or { panic('test requires a home directory') }
	mut path := os.join_path(home, 'owned-path')
	$if ownership ? {
		path = path.to_owned()
	}
	assert relativize_to_home(&path) or { panic('inside home') } == 'owned-path'
	assert relativize_to_home(&path) or { panic('inside home') } == 'owned-path'
	assert path.ends_with('owned-path')
	mut adapter_path := os.join_path(home, 'adapter-path')
	$if ownership ? {
		adapter_path = adapter_path.to_owned()
	}
	adapter := TestPathAdapter{adapter_path}
	assert relativize_to_home(&adapter) or { panic('adapter inside home') } == 'adapter-path'
	assert relativize_to_home(&adapter) or { panic('adapter inside home') } == 'adapter-path'
	assert adapter.path.ends_with('adapter-path')
}
