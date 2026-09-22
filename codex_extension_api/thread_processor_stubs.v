module codex_extension_api

import codex_app_server_protocol as api

// STUB: ExtensionDataInit is owned by codex-extension-api.
pub struct ExtensionDataInit {
pub mut:
	selected_capability_roots []api.SelectedCapabilityRoot
}

// STUB: ThreadIdleCause is owned by codex-extension-api's thread-lifecycle contributor API.
pub enum ThreadIdleCause {
	completed
}

// STUB: constructs the heterogeneous extension-data initializer used by core thread startup.
pub fn new_extension_data_init() ExtensionDataInit {
	return ExtensionDataInit{}
}

// STUB: inserts app-server selected capability roots into the thread extension initializer.
pub fn (mut init ExtensionDataInit) insert_selected_capability_roots(roots []api.SelectedCapabilityRoot) {
	init.selected_capability_roots = roots
}
