module bel

import crossterm
import os
import strings

#include <stdio.h>

$if windows {
	#include <io.h>
} $else {
	#include <unistd.h>
}

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C._dup(i32) i32
fn C._dup2(i32, i32) i32
fn C._close(i32) i32

fn test_notify_ignores_repeated_borrowed_heap_message() {
	mut message := 'this message must remain owned by the caller'
	$if ownership ? {
		message = message.to_owned()
	}
	path := os.join_path(os.temp_dir(), 'codex-bel-notify-${os.getpid()}.txt')
	mut output := os.create(path.clone()) or { panic(err) }
	defer {
		output.close()
		os.rm(path.clone()) or { panic(err) }
	}
	saved_stdout := $if windows { C._dup(1) } $else { C.dup(1) }
	assert saved_stdout >= 0
	defer {
		C.fflush(C.stdout)
		$if windows {
			C._dup2(saved_stdout, 1)
			C._close(saved_stdout)
		} $else {
			C.dup2(saved_stdout, 1)
			C.close(saved_stdout)
		}
	}
	C.fflush(C.stdout)
	redirected := $if windows { C._dup2(i32(output.fd), 1) } $else { C.dup2(i32(output.fd), 1) }
	assert redirected >= 0
	mut backend := BelBackend.default()
	backend.notify(&message) or { panic(err) }
	backend.notify(&message) or { panic(err) }
	assert message == 'this message must remain owned by the caller'
	assert os.read_file(path.clone()) or { panic(err) } == '\x07\x07'
}

fn test_command_formats_single_bel_byte() {
	command := PostNotification{}
	mut output := strings.new_builder(0)
	command.write_ansi(mut output) or { panic(err) }
	assert output.str() == '\x07'
}

fn test_repeated_shared_command_formatting_preserves_owner() {
	command := PostNotification{}
	mut first := strings.new_builder(0)
	command.write_ansi(mut first) or { panic(err) }
	mut second := strings.new_builder(0)
	command.write_ansi(mut second) or { panic(err) }
	assert first.str() == '\x07'
	assert second.str() == '\x07'
	cloned := command.clone()
	mut cloned_output := strings.new_builder(0)
	cloned.write_ansi(mut cloned_output) or { panic(err) }
	assert cloned_output.str() == '\x07'
	assert command == PostNotification{}
}

fn test_command_interface_keeps_source_windows_behavior() {
	command := PostNotification{}
	borrowed := crossterm.Command(&command)
	mut first := strings.new_builder(0)
	borrowed.write_ansi(mut first) or { panic(err) }
	mut second := strings.new_builder(0)
	borrowed.write_ansi(mut second) or { panic(err) }
	assert first.str() == '\x07'
	assert second.str() == '\x07'
	assert borrowed.is_ansi_code_supported()
	mut failed := false
	borrowed.execute_winapi() or {
		assert err.msg() == 'tried to execute PostNotification using WinAPI; use ANSI instead'
		failed = true
	}
	assert failed
	assert command == PostNotification{}
}

fn test_backend_default_and_debug_adaptation() {
	backend := BelBackend.default()
	assert backend == BelBackend{}
	assert backend.str().contains('BelBackend')
	assert PostNotification{}.str().contains('PostNotification')
}
