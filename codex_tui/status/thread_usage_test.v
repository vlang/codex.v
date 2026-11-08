module status

import codex_app_server_protocol as api
import ratatui.text
import std_collections
import std_iter

fn test_thread_usage_breakdown_groups_aggregate_model_credit_percentages() {
	group := api.ThreadUsageBreakdownGroup{
		model:                          'gpt-5.4'.clone()
		reasoning_effort:               'high'.clone()
		speed:                          'fast'.clone()
		estimated_usage_credits_micros: 30000000
		net_new_input_tokens:           i64(60)
		cached_input_tokens:            i64(10)
		input_tokens:                   i64(70)
		output_tokens:                  i64(20)
		total_tokens:                   i64(90)
	}
	groups := [group.clone(), api.ThreadUsageBreakdownGroup{
		...group.clone()
		reasoning_effort:               'medium'.clone()
		speed:                          'standard'.clone()
		estimated_usage_credits_micros: 10000000
	}, api.ThreadUsageBreakdownGroup{
		...group
		model:                          'gpt-5-mini'.clone()
		reasoning_effort:               'low'.clone()
		speed:                          'standard'.clone()
		estimated_usage_credits_micros: 10000000
	}]
	assert grouped_usage(&groups, .model) == ?string('GPT-5.4 80%, GPT-5 Mini 20%')
	assert grouped_usage(&groups, .reasoning) == ?string('Light 20%, Medium 20%, High 60%')
	assert grouped_usage(&groups, .speed) == ?string('Fast mode 60%, Standard 40%')
}

fn test_thread_usage_credit_formatting_rounds_to_one_decimal_place() {
	assert format_credit_micros( /* micros */
	0) == '0'
	assert format_credit_micros( /* micros */
	400000) == '0.4'
	assert format_credit_micros( /* micros */
	5200000) == '5.2'
	assert format_credit_micros( /* micros */
	5240000) == '5.2'
	assert format_credit_micros( /* micros */
	5250000) == '5.3'
	assert format_credit_micros( /* micros */
	46000000) == '46'
	assert format_credit_micros( /* micros */
	1240000000) == '1.2K'
	assert format_credit_micros( /* micros */
	12400000000) == '12.4K'
}

fn test_thread_usage_model_names_match_desktop_display_names() {
	gpt54 := 'gpt-5.4'
	mini := 'gpt-5-mini'
	sol := 'gpt-5.6-sol'
	example := 'examplemodel'
	assert format_model_display_name(&gpt54) == 'GPT-5.4'
	assert format_model_display_name(&mini) == 'GPT-5 Mini'
	assert format_model_display_name(&sol) == 'GPT-5.6 Sol'
	assert format_model_display_name(&example) == 'examplemodel'
}

fn thread_usage_owned(value &string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn thread_usage_text(lines &[]text.Line) []string {
	mut values := []string{}
	for index in 0 .. lines.len {
		line := &(*lines)[index]
		mut value := ''
		for span_index in 0 .. line.spans.len {
			value += line.spans[span_index].text
		}
		values << value
	}
	return values
}

fn test_thread_usage_borrowed_owned_model_and_groups_remain_reusable() {
	literal := 'gPt-5.6-ßeta-oAi'
	model := thread_usage_owned(&literal)
	assert format_model_display_name(&model) == 'GPT-5.6 SSeta OAI'
	assert format_model_display_name(&model) == 'GPT-5.6 SSeta OAI'
	assert model == literal
	groups := [api.ThreadUsageBreakdownGroup{ model: thread_usage_owned(&model), estimated_usage_credits_micros: 1 }]
	assert grouped_usage(&groups, .model) == ?string('GPT-5.6 SSeta OAI 100%')
	assert grouped_usage(&groups, .model) == ?string('GPT-5.6 SSeta OAI 100%')
	assert groups[0].model == ?string(model)
}

fn test_thread_usage_shared_updates_reserve_labels_without_placeholder_rows() {
	usage := StatusThreadUsage.default()
	cloned := usage.clone()
	unrelated := StatusThreadUsage.default()
	cloned.reserve_label_width()
	mut labels := []string{}
	mut seen := std_collections.BTreeSet[string]{}
	usage.push_labels(mut labels, mut seen)
	usage.push_labels(mut labels, mut seen)
	assert labels == ['  Billed tokens']
	formatter := FieldFormatter.from_labels(std_iter.borrowed_slice(&labels))
	assert usage.lines(&formatter, 20).len == 0
	thread_id := 'thread-1'
	model := 'gpt-5.4'
	cloned.set_estimate(api.ThreadUsage{
		thread_id:                      thread_usage_owned(&thread_id)
		estimated_usage_credits_micros: 5250000
		estimated_usage_usd_micros:     i64(1250000)
		groups:                         [api.ThreadUsageBreakdownGroup{
			model:                          thread_usage_owned(&model)
			reasoning_effort:               'high'.clone()
			speed:                          'fast'.clone()
			input_tokens:                   i64(70)
			cached_input_tokens:            i64(10)
			output_tokens:                  i64(20)
			estimated_usage_credits_micros: 5250000
		}]
	})
	usage.push_labels(mut labels, mut seen)
	assert labels == ['  Billed tokens', 'Thread usage', '  Models', '  Reasoning', '  Speed']
	aligned := FieldFormatter.from_labels(std_iter.borrowed_slice(&labels))
	first := usage.lines(&aligned, 80)
	second := cloned.lines(&aligned, 80)
	assert first == second
	assert thread_usage_text(&first) == [
		' Thread usage:      5.3 credits · ~$1.25',
		'   Models:          GPT-5.4 100%',
		'   Reasoning:       High 100%',
		'   Speed:           Fast mode 100%',
		'   Billed tokens:   70 input (10 cached) + 20 output',
	]
	assert unrelated.lines(&aligned, 80).len == 0
	cloned.set_estimate(none)
	assert usage.lines(&aligned, 80).len == 0
	assert model == 'gpt-5.4'
}

fn test_thread_usage_saturating_totals_exact_percentages_and_sort_order() {
	maximum := i64(9223372036854775807)
	groups := [
		api.ThreadUsageBreakdownGroup{ model: 'b'.clone(), estimated_usage_credits_micros: maximum },
		api.ThreadUsageBreakdownGroup{ model: 'a'.clone(), estimated_usage_credits_micros: maximum },
		api.ThreadUsageBreakdownGroup{ model: 'z'.clone(), estimated_usage_credits_micros: -1 },
	]
	assert grouped_usage(&groups, .model) == ?string('a 100%, b 100%')
	assert format_credit_micros(maximum) == '9.2T'
	assert format_credit_micros(-1) == '0'
	assert thread_usage_saturating_add(maximum, 1) == maximum
	assert thread_usage_saturating_add(-maximum - 1, -1) == -maximum - 1
	zeros := [api.ThreadUsageBreakdownGroup{ reasoning_effort: 'z'.clone() },
		api.ThreadUsageBreakdownGroup{ reasoning_effort: 'max'.clone() },
		api.ThreadUsageBreakdownGroup{ reasoning_effort: 'a'.clone() }]
	assert grouped_usage(&zeros, .reasoning) == ?string('Max 0%, a 0%, z 0%')
	negatives := [api.ThreadUsageBreakdownGroup{ estimated_usage_credits_micros: -1 }]
	assert grouped_usage(&negatives, .model) == none
	assert grouped_usage(&[]api.ThreadUsageBreakdownGroup{}, .speed) == none
}

fn test_thread_usage_usd_precision_rounding_and_saturating_cents() {
	assert format_estimated_usd_micros(-1) == none
	assert format_estimated_usd_micros(0) == ?string('~$0.00')
	assert format_estimated_usd_micros(1) == ?string('~$0.000001')
	assert format_estimated_usd_micros(99) == ?string('~$0.000099')
	assert format_estimated_usd_micros(100) == ?string('~$0.0001')
	assert format_estimated_usd_micros(149) == ?string('~$0.0001')
	assert format_estimated_usd_micros(150) == ?string('~$0.0002')
	assert format_estimated_usd_micros(9999) == ?string('~$0.0100')
	assert format_estimated_usd_micros(10000) == ?string('~$0.01')
	assert format_estimated_usd_micros(14999) == ?string('~$0.01')
	assert format_estimated_usd_micros(15000) == ?string('~$0.02')
	assert format_estimated_usd_micros(9223372036854775807) == ?string('~$9223372036854.77')
}

fn test_thread_usage_partial_token_counts_hide_only_unavailable_columns() {
	usage := StatusThreadUsage{}
	groups := [
		api.ThreadUsageBreakdownGroup{ input_tokens: i64(40), cached_input_tokens: i64(10), output_tokens: i64(20) },
		api.ThreadUsageBreakdownGroup{ input_tokens: i64(30), output_tokens: i64(10) },
	]
	assert sum_thread_usage_tokens(&groups, .input) == ?i64(70)
	assert sum_thread_usage_tokens(&groups, .cached) == none
	assert sum_thread_usage_tokens(&groups, .output) == ?i64(30)
	usage.set_estimate(api.ThreadUsage{ groups: groups })
	label := '  Billed tokens'
	formatter := FieldFormatter.from_labels(std_iter.owned_array([label.clone()]))
	lines := usage.lines(&formatter, 80)
	values := thread_usage_text(&lines)
	assert values.last() == '   Billed tokens:   70 input + 30 output'
}

fn test_thread_usage_wrapped_dimensions_have_formatter_continuations() {
	usage := StatusThreadUsage{}
	usage.set_estimate(api.ThreadUsage{
		groups: [
			api.ThreadUsageBreakdownGroup{ model: 'gpt-5.4'.clone(), estimated_usage_credits_micros: 4 },
			api.ThreadUsageBreakdownGroup{ model: 'gpt-5-mini'.clone(), estimated_usage_credits_micros: 1 },
		]
	})
	formatter := FieldFormatter.from_labels(std_iter.owned_array(['Thread usage', '  Models',
		'  Reasoning', '  Speed']))
	lines := usage.lines(&formatter, 12)
	values := thread_usage_text(&lines)
	assert values[1] == '   Models:       GPT-5.4 80%,'
	assert values[2] == '                 GPT-5 Mini'
	assert values[3] == '                 20%'
	assert values[0].contains('credits')
}
