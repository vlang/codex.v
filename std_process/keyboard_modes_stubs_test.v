module std_process

import std_path

// STUB: verify the native process boundary preserves borrowed executables,
// arguments, environment overrides, null input/error streams, and failure status.
fn test_command_output_preserves_native_process_contract() {
	$if !windows {
		mut executable_text := '/bin/sh'
		mut path_text := '/usr/bin:/bin'
		$if ownership ? {
			executable_text = executable_text.to_owned()
			path_text = path_text.to_owned()
		}
		executable := std_path.PathBuf.from(executable_text)
		path_key := 'PATH'
		for _ in 0 .. 2 {
			mut command := Command.new(&executable)
			command.env(&path_key, &path_text)
			command.args(['-c', 'read ignored; printf "%s|%s" "$1" "$PATH"; printf hidden >&2',
				'probe', 'argument with spaces; $(literal)'])
			command.stdin(.null)
			command.stderr(.null)
			output := command.output() or { panic(err) }
			assert output.status.success()
			assert output.stdout == 'argument with spaces; $(literal)|/usr/bin:/bin'
		}
		assert executable.as_path().to_path_buf() == '/bin/sh'
		assert path_text == '/usr/bin:/bin'
		mut unsuccessful := Command.new(&executable)
		unsuccessful.args(['-c', 'exit 7'])
		unsuccessful.stdin(.null)
		unsuccessful.stderr(.null)
		output := unsuccessful.output() or { panic(err) }
		assert !output.status.success()
		assert output.stdout == ''
		missing := std_path.PathBuf.from('/codex-missing-keyboard-helper')
		mut command := Command.new(&missing)
		command.stdin(.null)
		command.stderr(.null)
		command.output() or {
			assert err.code() != 0
			return
		}
		assert false, 'missing executable must be a spawn error'
	}
}
