// IDE context data model and public helpers for TUI `/ide` support.
module ide_context

import codex_app_server_protocol as api
import codex_tui.ide_context.ipc
import codex_tui.ide_context.prompt
import codex_tui.ide_context.model
import serde_json
import std_path

// V cannot re-export functions. These forwarding functions preserve the public
// API; the canonical model also avoids circular parent/child imports.
pub fn fetch_ide_context(workspace_root &std_path.Path, codex_home &std_path.Path) !IdeContext {
	return ipc.fetch_ide_context[IdeContext](workspace_root, codex_home)
}

pub fn apply_ide_context_to_user_input(context &IdeContext, mut items []api.UserInput) bool {
	return prompt.apply_ide_context_to_user_input(context, mut items)
}

// Rust returns a borrowed str. The child boundary returns an owned V string,
// because V cannot express the source's borrowed substring return lifetime.
pub fn extract_prompt_request_with_offset(message &string) (string, usize) {
	return prompt.extract_prompt_request_with_offset(message)
}

pub fn has_prompt_context(context &IdeContext) bool {
	return prompt.has_prompt_context(context)
}

pub type IdeContext = model.IdeContext

type ActiveFile = model.ActiveFile

type FileDescriptor = model.FileDescriptor

type Range = model.Range

type Position = model.Position

// Keep the parent's Deserialize entry points while the single canonical model
// owns decoding. Generic callback calls use model.IdeContext directly because V
// cannot generate their result type correctly when instantiated with an alias.
pub fn IdeContext.deserialize_value(value &serde_json.Value) !IdeContext {
	decoded := model.IdeContext.deserialize_value(value)!
	return IdeContext(decoded)
}

pub fn IdeContext.deserialize_json(text &string) !IdeContext {
	decoded := model.IdeContext.deserialize_json(text)!
	return IdeContext(decoded)
}
