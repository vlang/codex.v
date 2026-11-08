module goal_display

import codex_app_server_protocol

fn test_format_goal_elapsed_seconds_is_compact() {
	assert format_goal_elapsed_seconds( /* seconds */
	0) == '0s'
	assert format_goal_elapsed_seconds( /* seconds */
	59) == '59s'
	assert format_goal_elapsed_seconds( /* seconds */
	60) == '1m'
	assert format_goal_elapsed_seconds(30 * 60) == '30m'
	assert format_goal_elapsed_seconds(90 * 60) == '1h 30m'
	assert format_goal_elapsed_seconds(2 * 60 * 60) == '2h'
	just_before_one_day := 24 * 60 * 60 - 1
	assert format_goal_elapsed_seconds(just_before_one_day) == '23h 59m'

	one_day := 24 * 60 * 60
	assert format_goal_elapsed_seconds(one_day) == '1d 0h 0m'

	almost_three_days := 2 * 24 * 60 * 60 + 23 * 60 * 60 + 42 * 60
	assert format_goal_elapsed_seconds(almost_three_days) == '2d 23h 42m'
}

// A shared setup helper mirrors the original Rust test helper. V test helpers
// cannot use the test_ prefix, which is reserved for zero-argument test entries.
fn fixture_thread_goal(token_budget ?i64, tokens_used i64) codex_app_server_protocol.ThreadGoal {
	return codex_app_server_protocol.ThreadGoal{
		thread_id:         'thread-1'.clone()
		objective:         'Complete the task described in ../gameboy-long-running-prompt5.txt'.clone()
		status:            .budget_limited
		token_budget:      token_budget
		tokens_used:       tokens_used
		time_used_seconds: 120
		created_at:        0
		updated_at:        0
	}
}

fn test_goal_usage_summary_formats_time_and_budgeted_tokens() {
	goal := fixture_thread_goal( /* token_budget */
	i64(50_000), /* tokens_used */
		63_876)
	assert goal_usage_summary(&goal) == 'Objective: Complete the task described in ../gameboy-long-running-prompt5.txt Time: 2m. Tokens: 63.9K/50K.'
}

fn test_elapsed_clamps_negative_values_and_discards_remainder_seconds() {
	assert format_goal_elapsed_seconds(-1) == '0s'
	assert format_goal_elapsed_seconds(i64(-9223372036854775807) - 1) == '0s'
	assert format_goal_elapsed_seconds(119) == '1m'
	assert format_goal_elapsed_seconds(3599) == '59m'
	assert format_goal_elapsed_seconds(3601) == '1h'
	assert format_goal_elapsed_seconds(86459) == '1d 0h 0m'
	assert format_goal_elapsed_seconds(9223372036854775807) == '106751991167300d 15h 30m'
}

fn test_goal_usage_summary_omits_nonpositive_time_and_unbudgeted_tokens() {
	without_usage := codex_app_server_protocol.ThreadGoal{
		objective:         'Finish the translation'.clone()
		token_budget:      none
		tokens_used:       63_876
		time_used_seconds: -1
	}
	assert goal_usage_summary(&without_usage) == 'Objective: Finish the translation'
	with_time := codex_app_server_protocol.ThreadGoal{
		objective:         'Finish the translation'.clone()
		token_budget:      none
		tokens_used:       63_876
		time_used_seconds: 59
	}
	assert goal_usage_summary(&with_time) == 'Objective: Finish the translation Time: 59s.'
	zero_budget := codex_app_server_protocol.ThreadGoal{
		objective:         'Finish the translation'.clone()
		token_budget:      i64(0)
		tokens_used:       -10
		time_used_seconds: 0
	}
	assert goal_usage_summary(&zero_budget) == 'Objective: Finish the translation Tokens: 0/0.'
}

fn test_status_labels_render_each_goal_state() {
	statuses := [codex_app_server_protocol.ThreadGoalStatus.active, .paused, .blocked, .usage_limited,
		.budget_limited, .complete]
	labels := ['active', 'paused', 'stalled', 'usage limited', 'limited by budget', 'complete']
	for index, goal_status in statuses {
		assert goal_status_label(goal_status) == labels[index]
	}
}

fn test_budget_summary_token_magnitude_boundaries() {
	values := [i64(-1), 0, 999, 1000, 9999, 10000, 63876, 99999, 100000, 999999, 1000000, 1234567,
		1000000000, 1000000000000, 9223372036854775807]
	formatted := ['0', '0', '999', '1K', '10K', '10K', '63.9K', '100K', '100K', '1000K', '1M',
		'1.23M', '1B', '1T', '9223372T']
	for index, value in values {
		goal := codex_app_server_protocol.ThreadGoal{
			objective:    'Observe usage'.clone()
			token_budget: value
			tokens_used:  value
		}
		assert goal_usage_summary(&goal) == 'Objective: Observe usage Tokens: ${formatted[index]}/${formatted[index]}.'
	}
}

fn test_budget_summary_preserves_rust_fixed_precision_rounding() {
	// These inputs cover exact halfway values and nearby binary-float values:
	// format the float exactly as Rust does, including ties to even.
	values := [i64(1005), 1025, 1055, 1125, 10125, 12500, 12650]
	formatted := ['1K', '1.02K', '1.05K', '1.12K', '10.1K', '12.5K', '12.7K']
	for index, value in values {
		goal := codex_app_server_protocol.ThreadGoal{
			objective:    'Check rounding'.clone()
			token_budget: value
			tokens_used:  value
		}
		assert goal_usage_summary(&goal) == 'Objective: Check rounding Tokens: ${formatted[index]}/${formatted[index]}.'
	}
}

fn test_borrowed_goal_summary_preserves_owner() {
	mut thread_id := 'owned-thread'
	mut objective := 'Translate 🐈 faithfully'
	$if ownership ? {
		thread_id = thread_id.to_owned()
		objective = objective.to_owned()
	}
	goal := codex_app_server_protocol.ThreadGoal{
		thread_id:         thread_id
		objective:         objective
		status:            .paused
		token_budget:      i64(50_000)
		tokens_used:       63_876
		time_used_seconds: 120
	}
	assert goal_usage_summary(&goal) == 'Objective: Translate 🐈 faithfully Time: 2m. Tokens: 63.9K/50K.'
	assert goal_usage_summary(&goal) == 'Objective: Translate 🐈 faithfully Time: 2m. Tokens: 63.9K/50K.'
	assert goal.objective == 'Translate 🐈 faithfully'
	assert goal.thread_id == 'owned-thread'
	assert goal_status_label(goal.status) == 'paused'
}
