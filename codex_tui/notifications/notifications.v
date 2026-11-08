module notifications

import codex_config.types
import codex_terminal_detection
import codex_tui.notifications.bel
import codex_tui.notifications.osc9

// The two V payload types retain the Rust enum variants; generated sum-type
// formatting supplies the derived Debug representation.
pub type DesktopNotificationBackend = osc9.Osc9Backend | bel.BelBackend

pub fn DesktopNotificationBackend.for_method(method types.NotificationMethod) DesktopNotificationBackend {
	return match method {
		.auto {
			terminal := codex_terminal_detection.terminal_info()
			if supports_osc9(&terminal) {
				DesktopNotificationBackend(osc9.Osc9Backend.new())
			} else {
				DesktopNotificationBackend(bel.BelBackend{})
			}
		}
		.osc9 { DesktopNotificationBackend(osc9.Osc9Backend.new()) }
		.bel { DesktopNotificationBackend(bel.BelBackend{}) }
	}
}

pub fn (backend &DesktopNotificationBackend) method() types.NotificationMethod {
	return match backend {
		osc9.Osc9Backend { types.NotificationMethod.osc9 }
		bel.BelBackend { types.NotificationMethod.bel }
	}
}

pub fn (mut backend DesktopNotificationBackend) notify(message &string) ! {
	match mut backend {
		osc9.Osc9Backend { backend.notify(message)! }
		bel.BelBackend { backend.notify(message)! }
	}
}

pub fn detect_backend(method types.NotificationMethod) DesktopNotificationBackend {
	return DesktopNotificationBackend.for_method(method)
}

fn supports_osc9(terminal &codex_terminal_detection.TerminalInfo) bool {
	return terminal.name in [.ghostty, .iterm2, .kitty, .warp_terminal, .wez_term]
}
