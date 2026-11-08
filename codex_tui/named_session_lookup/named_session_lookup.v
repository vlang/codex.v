// Resolve a displayed session label through the app server before acting on its thread ID.
module named_session_lookup

import codex_app_server_client
import codex_app_server_protocol
import codex_protocol.thread_id
import codex_rollout
import codex_tui
import color_eyre.eyre
import std_path

// V has no pub(super) visibility for declarations used by sibling modules.
pub enum SessionCollection {
	active
	archived
}

pub enum AmbiguousSessionNameKind {
	multiple
	paginated
}

// The tag retains Rust's two error payload variants through V's IError interface.
pub struct AmbiguousSessionName {
pub:
	kind      AmbiguousSessionNameKind
	name      string
	first_id  string
	second_id string
	thread_id string
}

pub fn (failure &AmbiguousSessionName) msg() string {
	return match failure.kind {
		.multiple {
			"Multiple sessions match '${failure.name}' (including ${failure.first_id} and ${failure.second_id}); use a session UUID to disambiguate."
		}
		.paginated {
			'Cannot verify a unique session label across server pages; matching session UUID: ${failure.thread_id}. Use it only if this is the session you want.'
		}
	}
}

pub fn (failure &AmbiguousSessionName) code() int {
	return int(failure.kind)
}

// Rust str::trim uses Unicode White_Space rather than V's ASCII trim_space.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

// V has no borrowed string-slice return; allocate the selected trimmed label while
// borrowing the thread so its owned name and preview remain reusable.
pub fn display_label(listed_thread &codex_app_server_protocol.Thread) string {
	if name := listed_thread.name {
		trimmed := name.trim(unicode_whitespace)
		if trimmed.len > 0 {
			return trimmed
		}
	}
	return listed_thread.preview.trim(unicode_whitespace)
}

// Safe Rust Option<&str> adaptation: the optional tag borrows a string owner,
// avoiding V's unsupported &?string and V3's ?&string C generation.
pub struct BorrowedModelProvider {
pub:
	has_value bool
	value     &string = unsafe { nil }
}

// V cannot nest Result<Option<Thread>> reliably; retain the successful missing
// value explicitly, alongside an owned thread in the present variant.
pub struct OptionalThread {
pub:
	has_value bool
	value     codex_app_server_protocol.Thread
}

/// Resolve server-listed labels and reject distinct matches before selecting an ID.
// Async app-server awaits become synchronous typed calls at the untranslated
// transport boundary; request ordering, pagination, and failures remain identical.
pub fn lookup(mut app_server codex_tui.AppServerSession, codex_home &std_path.Path, name &string, collections &[]SessionCollection, source_kind_filters &[][]codex_app_server_protocol.ThreadSourceKind, model_provider &BorrowedModelProvider) !OptionalThread {
	if name.trim(unicode_whitespace).len == 0 {
		return OptionalThread{}
	}
	mut matched := OptionalThread{}
	mut paginated := false
	for collection in *collections {
		for source_kinds in *source_kind_filters {
			mut cursor := ?string(none)
			sort_key := if app_server.uses_embedded_app_server() {
				codex_app_server_protocol.ThreadSortKey.recency_at
			} else {
				codex_app_server_protocol.ThreadSortKey.updated_at
			}
			for {
				response := app_server.thread_list(codex_app_server_protocol.ThreadListParams{
					originators:        none
					cursor:             cursor
					limit:              u32(100)
					sort_key:           sort_key
					sort_direction:     none
					model_providers:    if model_provider.has_value {
						?[]string([model_provider.value.clone()])
					} else {
						?[]string(none)
					}
					source_kinds:       source_kinds.clone()
					archived:           collection == .archived
					section_id:         codex_app_server_protocol.ClearableString{}
					project_id:         codex_app_server_protocol.ClearableString{}
					parent_thread_id:   none
					ancestor_thread_id: none
					cwd:                none
					use_state_db_only:  false
					search_term:        none
				}) or { return eyre.wrap_err(err, 'failed to list sessions while resolving session label') }
				paginated = paginated || response.next_cursor != none
				for index in 0 .. response.data.len {
					listed_thread := &response.data[index]
					if display_label(listed_thread) != *name {
						continue
					}
					if !app_server.uses_remote_workspace() {
						if path := listed_thread.path {
							subdir := if collection == .active {
								codex_rollout.sessions_subdir
							} else {
								codex_rollout.archived_sessions_subdir
							}
							expected_root := codex_home.join(&subdir)
							path_view := std_path.Path.new(&path)
							root_view := std_path.Path.new(&expected_root)
							if !path_view.starts_with(&root_view) || (listed_thread.history_mode == .legacy && codex_rollout.existing_rollout_path(&path_view) == none) {
								continue
							}
						}
					}
					id := thread_id.from_string(&listed_thread.id) or { return eyre.wrap_err(err, 'app server returned invalid session id `${listed_thread.id}`') }
					id_display := id.str()
					current := app_server.thread_read(id, /*include_turns*/
						false) or {
						// Borrow through eyre's attached context before narrowing the
						// original typed request error, preserving the returned report.
						cause := eyre.root_cause(&err)
						if cause is codex_app_server_client.TypedRequestError {
							if cause.kind != .server {
								return err
							}
							message := &cause.server_source.message
							if *message == 'thread not loaded: ${id_display}' {
								if app_server.uses_embedded_app_server() {
									continue
								}
								listed_thread.clone()
							} else {
								metadata_mismatch := message.starts_with('failed to read thread: thread-store internal error: session metadata ') && message.contains(' belongs to thread ') && message.ends_with(', expected ${id_display}')
								metadata_unreadable := if path := listed_thread.path {
									message.starts_with('failed to read thread: thread-store internal error: failed to read session metadata ${path}: ')
								} else {
									false
								}
								if metadata_mismatch || metadata_unreadable {
									continue
								}
								return err
							}
						} else {
							return err
						}
					}
					if current.id != listed_thread.id || display_label(&current) != *name {
						continue
					}
					if matched.has_value && matched.value.id != current.id {
						return AmbiguousSessionName{ kind: .multiple, name: name.clone(), first_id: matched.value.id.clone(), second_id: current.id }
					}
					matched = OptionalThread{ has_value: true, value: current }
				}
				if next_cursor := response.next_cursor {
					cursor = next_cursor
				} else {
					break
				}
			}
		}
	}
	// Older server cursors can skip equal timestamps at a page boundary.
	if matched.has_value && paginated {
		return AmbiguousSessionName{ kind: .paginated, thread_id: matched.value.id.clone() }
	}
	return matched
}
