// Narrow conversion helpers for approval-related app-server payloads.
//
// The TUI mostly keeps app-server approval types intact. These helpers cover
// the remaining cases where the UI consumes a private file-change display
// model or needs to translate a granted permission response for outbound
// submission.
module app_server_approval_conversions

import codex_tui.diff_model
import codex_app_server_protocol
import codex_protocol.request_permissions
import std_collections
import std_path

pub fn granted_permission_profile_from_request(value request_permissions.RequestPermissionProfile) codex_app_server_protocol.GrantedPermissionProfile {
	return codex_app_server_protocol.GrantedPermissionProfile{
		network:     if network := value.network {
			codex_app_server_protocol.AdditionalNetworkPermissions{ enabled: network.enabled }
		} else {
			none
		}
		file_system: if file_system := value.file_system {
			codex_app_server_protocol.AdditionalFileSystemPermissions.from_core(file_system)
		} else {
			none
		}
	}
}

pub fn file_update_changes_to_display(changes []codex_app_server_protocol.FileUpdateChange) std_collections.HashMap[std_path.PathBuf, diff_model.FileChange] {
	mut display := std_collections.HashMap[std_path.PathBuf, diff_model.FileChange]{}
	for change in changes {
		path := std_path.PathBuf.from(change.path)
		file_change := match change.kind.kind {
			.add { diff_model.FileChange(diff_model.Add{ content: change.diff }) }
			.delete { diff_model.FileChange(diff_model.Delete{ content: change.diff }) }
			.update {
				diff_model.FileChange(diff_model.Update{
					unified_diff: change.diff
					move_path:    change.kind.move_path
				})
			}
		}
		display.insert(path, file_change)
	}
	return display
}
