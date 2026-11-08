module auto_review_denials

import arrays
import codex_protocol.approvals
import codex_tui.text_formatting
import shlex
import std_fmt

const max_recent_denials = 10

// V registers an explicitly implemented Drop interface for scope destruction.
// This adapter represents the implicit Rust VecDeque owner's destruction contract.
interface Drop {
mut:
	drop()
}

// V's growable array retains VecDeque's ordering and ownership at this small fixed cap.
// V supplies Debug formatting and the empty-array default derived by Rust.
pub struct RecentAutoReviewDenials implements Drop {
mut:
	denial_entries []approvals.GuardianAssessmentEvent
}

pub fn (mut denials RecentAutoReviewDenials) push(event approvals.GuardianAssessmentEvent) {
	if event.status != .denied {
		discard_denial(event)
		return
	}
	for index := denials.denial_entries.len - 1; index >= 0; index-- {
		if denials.denial_entries[index].id == event.id {
			removed := denials.remove_entry(index)
			discard_denial(removed)
		}
	}
	// Normal V builds insert a derived deep copy; -ownership transfers this owned
	// parameter into the array, preserving Rust's original buffers without cloning.
	denials.denial_entries.insert(0, event)
	for denials.denial_entries.len > max_recent_denials {
		removed := denials.remove_entry(denials.denial_entries.len - 1)
		discard_denial(removed)
	}
}

pub fn (denials &RecentAutoReviewDenials) is_empty() bool {
	return denials.denial_entries.len == 0
}

pub fn (denials &RecentAutoReviewDenials) entries() DenialEntries {
	return DenialEntries{ denials: denials }
}

// Rust returns impl Iterator<Item=&GuardianAssessmentEvent>. V's lazy iterator returns
// a Copy-equivalent borrowed view, avoiding an owned optional event or unsafe ?&T.
// The view is valid while the owner lives and until its next mutable operation.
pub struct DenialEntries {
	denials &RecentAutoReviewDenials
mut:
	position int
}

pub struct BorrowedDenial {
pub:
	value &approvals.GuardianAssessmentEvent
}

pub fn (mut iter DenialEntries) next() ?BorrowedDenial {
	if iter.position >= iter.denials.denial_entries.len {
		return none
	}
	value := &iter.denials.denial_entries[iter.position]
	iter.position++
	return BorrowedDenial{ value: value }
}

pub fn (mut denials RecentAutoReviewDenials) take(id &string) ?approvals.GuardianAssessmentEvent {
	for index in 0 .. denials.denial_entries.len {
		if denials.denial_entries[index].id == *id {
			return denials.remove_entry(index)
		}
	}
	return none
}

// VecDeque::remove moves an event. V clones an indexed owned-struct assignment,
// so rotate its slot to the front, pop the original owner, and rotate back to
// preserve the other entries' order. The ten-entry cap bounds these small shifts.
fn (mut denials RecentAutoReviewDenials) remove_entry(index int) approvals.GuardianAssessmentEvent {
	if index > 0 {
		arrays.rotate_left(mut denials.denial_entries, index)
	}
	event := denials.denial_entries.pop_left()
	if index > 0 {
		arrays.rotate_right(mut denials.denial_entries, index)
	}
	return event
}

// VecDeque::retain/truncate drop excluded owners. V's explicit ownership intrinsic
// releases nested payloads at this same boundary, including the normal-build fallback.
fn discard_denial(event approvals.GuardianAssessmentEvent) {
	drop_owned(event)
}

// Rust's VecDeque destroys retained entries when its owner leaves scope. This Drop
// adapter gives ownership builds the same boundary; normal builds retain V's GC.
pub fn (mut denials RecentAutoReviewDenials) drop() {
	drop_owned(denials.denial_entries)
}

pub fn action_summary(action &approvals.GuardianAssessmentAction) string {
	match action {
		approvals.GuardianCommandAction {
			return action.command.clone()
		}
		approvals.GuardianExecveAction {
			command := if action.argv.len == 0 {
				[action.program.clone()]
			} else {
				action.argv.clone()
			}
			return shlex.try_join(&command) or { command.join(' ') }
		}
		approvals.GuardianWriteStdinAction {
			debug_stdin := std_fmt.debug_string(&action.stdin)
			stdin := text_formatting.truncate_text(&debug_stdin, /* max_graphemes */
				80)
			return 'send input to terminal ${action.process_id}: ${stdin}'
		}
		approvals.GuardianApplyPatchAction {
			if action.files.len == 1 {
				return 'apply_patch touching ${action.files[0].render_for_ui()}'
			}
			return 'apply_patch touching ${action.files.len} files'
		}
		approvals.GuardianNetworkAccessAction {
			return 'network access to ${action.target}'
		}
		approvals.GuardianMcpToolCallAction {
			if label := action.connector_name {
				return 'MCP ${action.tool_name} on ${label}'
			}
			return 'MCP ${action.tool_name} on ${action.server}'
		}
		approvals.GuardianRequestPermissionsAction {
			if reason := action.reason {
				return 'permission request: ${reason}'
			}
			return 'permission request'
		}
	}
}
