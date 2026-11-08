module goal_display

import codex_app_server_protocol
import codex_tui.status

pub const goal_usage = 'Usage: /goal [<objective>|clear|edit|pause|resume]'

pub fn format_goal_elapsed_seconds(seconds i64) string {
	clamped_seconds := u64(if seconds < 0 { i64(0) } else { seconds })
	if clamped_seconds < 60 {
		return '${clamped_seconds}s'
	}

	minutes := clamped_seconds / 60
	if minutes < 60 {
		return '${minutes}m'
	}

	hours := minutes / 60
	remaining_minutes := minutes % 60
	if hours >= 24 {
		days := hours / 24
		remaining_hours := hours % 24
		return '${days}d ${remaining_hours}h ${remaining_minutes}m'
	}

	if remaining_minutes == 0 {
		return '${hours}h'
	} else {
		return '${hours}h ${remaining_minutes}m'
	}
}

// Rust returns static string literals; the equivalent V literals require no
// borrow lifetime or allocation adaptation.
pub fn goal_status_label(goal_status codex_app_server_protocol.ThreadGoalStatus) string {
	return match goal_status {
		.active { 'active' }
		.paused { 'paused' }
		.blocked { 'stalled' }
		.usage_limited { 'usage limited' }
		.budget_limited { 'limited by budget' }
		.complete { 'complete' }
	}
}

pub fn goal_usage_summary(goal &codex_app_server_protocol.ThreadGoal) string {
	mut parts := ['Objective: ${goal.objective}']
	if goal.time_used_seconds > 0 {
		parts << 'Time: ${format_goal_elapsed_seconds(goal.time_used_seconds)}.'
	}
	if token_budget := goal.token_budget {
		parts << 'Tokens: ${status.format_tokens_compact(goal.tokens_used)}/${status.format_tokens_compact(token_budget)}.'
	}
	return parts.join(' ')
}
