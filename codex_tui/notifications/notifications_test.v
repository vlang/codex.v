module notifications

import codex_config.types
import codex_terminal_detection
import codex_tui.notifications.bel
import codex_tui.notifications.osc9
import os

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

// V reserves the test_ prefix for zero-argument test entries.
fn make_test_terminal(name codex_terminal_detection.TerminalName) codex_terminal_detection.TerminalInfo {
	return codex_terminal_detection.TerminalInfo{
		name:         name
		term_program: none
		version:      none
		term:         none
		multiplexer:  none
	}
}

fn test_selects_osc9_method() {
	backend := detect_backend(.osc9)
	assert backend is osc9.Osc9Backend
}

fn test_selects_bel_method() {
	backend := detect_backend(.bel)
	assert backend is bel.BelBackend
}

fn test_supports_osc9_for_supported_terminals() {
	for name in [codex_terminal_detection.TerminalName.ghostty, .iterm2, .kitty, .warp_terminal,
		.wez_term] {
		terminal := make_test_terminal(name)
		assert supports_osc9(&terminal), '${name} should support OSC 9'
	}
}

fn test_supports_osc9_for_unsupported_terminals() {
	for name in [codex_terminal_detection.TerminalName.apple_terminal, .alacritty, .dumb,
		.gnome_terminal, .konsole, .unknown, .vs_code, .vte, .windows_terminal] {
		terminal := make_test_terminal(name)
		assert supports_osc9(&terminal) == false, '${name} should not support OSC 9'
	}
}

fn test_auto_selection_uses_detected_terminal() {
	terminal := codex_terminal_detection.terminal_info()
	backend := detect_backend(.auto)
	if supports_osc9(&terminal) {
		assert backend is osc9.Osc9Backend
		assert backend.method() == .osc9
	} else {
		assert backend is bel.BelBackend
		assert backend.method() == .bel
	}
}

fn test_method_repeated_shared_borrow_preserves_backend() {
	osc9_backend := DesktopNotificationBackend.for_method(.osc9)
	assert osc9_backend.method() == .osc9
	assert osc9_backend.method() == .osc9
	assert osc9_backend is osc9.Osc9Backend
	bel_backend := DesktopNotificationBackend.for_method(.bel)
	assert bel_backend.method() == .bel
	assert bel_backend.method() == .bel
	assert bel_backend is bel.BelBackend
}

fn test_supports_osc9_repeated_borrow_preserves_owned_metadata() {
	mut program := 'Ghostty'
	mut version := '1.2.3'
	mut term := 'xterm-ghostty'
	$if ownership ? {
		program = program.to_owned()
		version = version.to_owned()
		term = term.to_owned()
	}
	terminal := codex_terminal_detection.TerminalInfo{
		name:         .ghostty
		term_program: program
		version:      version
		term:         term
		multiplexer:  none
	}
	assert supports_osc9(&terminal)
	assert supports_osc9(&terminal)
	assert terminal.term_program or { panic('program should remain owned') } == 'Ghostty'
	assert terminal.version or { panic('version should remain owned') } == '1.2.3'
	assert terminal.term or { panic('term should remain owned') } == 'xterm-ghostty'
}

fn test_notify_dispatches_repeated_borrowed_message() {
	mut message := 'completed\x1b[31m'
	$if ownership ? {
		message = message.to_owned()
	}
	path := os.join_path(os.temp_dir(), 'codex-notifications-${os.getpid()}.txt')
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
	mut bel_backend := detect_backend(types.NotificationMethod.bel)
	bel_backend.notify(&message) or { panic(err) }
	bel_backend.notify(&message) or { panic(err) }
	assert bel_backend.method() == .bel
	assert os.read_file(path.clone()) or { panic(err) } == '\x07\x07'
	mut osc9_backend := detect_backend(types.NotificationMethod.osc9)
	osc9_backend.notify(&message) or { panic(err) }
	osc9_backend.notify(&message) or { panic(err) }
	assert osc9_backend.method() == .osc9
	assert message == 'completed\x1b[31m'
	terminal := codex_terminal_detection.terminal_info()
	wrapped := if mux := terminal.multiplexer { mux.kind == .tmux } else { false }
	expected_osc9 := if wrapped {
		'\x1bPtmux;\x1b\x1b]9;completed\x1b\x1b[31m\x07\x1b\\'
	} else {
		'\x1b]9;completed\x1b[31m\x07'
	}
	assert os.read_file(path.clone()) or { panic(err) } == '\x07\x07' + expected_osc9 + expected_osc9
}
