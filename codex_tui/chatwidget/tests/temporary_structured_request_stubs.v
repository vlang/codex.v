module tests

import codex_core
import codex_tui.app_event_sender
import codex_tui.chatwidget
import os
import tokio.sync.mpsc

// STUB: chatwidget/tests/helpers.rs::make_chatwidget_manual_with_sender; the
// discarded channels have no runtime behavior in this isolated fixture boundary.
pub fn make_chatwidget_manual_with_sender() (chatwidget.ChatWidget, app_event_sender.AppEventSender, mpsc.AppEventReceiver, mpsc.OpReceiver) {
	return chatwidget.ChatWidget.fixture(codex_core.Config{ model_provider_id: 'openai', cwd: os.getwd() }), app_event_sender.AppEventSender{}, mpsc.AppEventReceiver{}, mpsc.OpReceiver{}
}
