module chatwidget

import codex_core

// STUB: tui/src/chatwidget.rs::ChatWidget; only its config_ref boundary is
// observed by the temporary structured request source integration test.
pub struct ChatWidget {
	config codex_core.Config
}

// STUB: a chatwidget test constructor, with untranslated UI/runtime fields absent.
pub fn ChatWidget.fixture(config codex_core.Config) ChatWidget {
	return ChatWidget{ config: config }
}

// STUB: ChatWidget::config_ref shares the stored config exactly as the Rust helper.
pub fn (widget &ChatWidget) config_ref() &codex_core.Config {
	return &widget.config
}
