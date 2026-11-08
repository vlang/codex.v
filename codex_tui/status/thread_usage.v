// Live-updating, thread-scoped billing details embedded in `/status` history cards.
module status

import codex_app_server_protocol
import codex_tui.model_catalog
import codex_tui.wrapping
import math.unsigned
import ratatui.text
import std_collections
import sync
import unicode_segmentation

const reasoning_order = ['None', 'Minimal', 'Light', 'Medium', 'High', 'Extra High', 'Max', 'Ultra']
const speed_order = ['Fast mode', 'Ultrafast', 'Standard']
const models_label = '  Models'
const reasoning_label = '  Reasoning'
const speed_label = '  Speed'
const billed_tokens_label = '  Billed tokens'

// Shared state updates a committed `/status` card when its asynchronous estimate arrives.
// A GC-managed shared cell supplies Arc identity; explicit clone shares both cells.
// V does not unwind panics, so a lock cannot become poisoned as a Rust RwLock can.
pub struct StatusThreadUsage {
	estimate &ThreadUsageEstimateState = &ThreadUsageEstimateState{}
	reserved &ThreadUsageReservedState = &ThreadUsageReservedState{}
}

@[heap]
struct ThreadUsageEstimateState {
mut:
	lock    &sync.RwMutex = sync.new_rwmutex()
	present bool
	value   codex_app_server_protocol.ThreadUsage
}

@[heap]
struct ThreadUsageReservedState {
mut:
	value u32
}

pub fn StatusThreadUsage.default() StatusThreadUsage {
	return StatusThreadUsage{}
}

pub fn (usage &StatusThreadUsage) clone() StatusThreadUsage {
	return StatusThreadUsage{ estimate: usage.estimate, reserved: usage.reserved }
}

pub fn (usage &StatusThreadUsage) reserve_label_width() {
	thread_usage_store_reserved(&usage.reserved.value)
}

pub fn (usage &StatusThreadUsage) set_estimate(estimate ?codex_app_server_protocol.ThreadUsage) {
	mut stored_estimate := unsafe { usage.estimate }
	stored_estimate.lock.lock()
	defer { stored_estimate.lock.unlock() }
	if value := estimate {
		stored_estimate.value = value
		stored_estimate.present = true
	} else {
		stored_estimate.value = codex_app_server_protocol.ThreadUsage{}
		stored_estimate.present = false
	}
}

pub fn (usage &StatusThreadUsage) push_labels(mut labels []string, mut seen std_collections.BTreeSet[string]) {
	// Keep existing card rows stable when asynchronous billing details arrive. Reserving a
	// formatter label does not emit a loading placeholder or an empty billing row.
	if thread_usage_load_reserved(&usage.reserved.value) {
		push_label(mut labels, mut seen, &billed_tokens_label)
	}
	mut stored_estimate := unsafe { usage.estimate }
	stored_estimate.lock.rlock()
	defer { stored_estimate.lock.runlock() }
	if !stored_estimate.present {
		return
	}
	estimate := &stored_estimate.value
	thread_label := 'Thread usage'
	push_label(mut labels, mut seen, &thread_label)
	if estimate.groups.len > 0 {
		push_label(mut labels, mut seen, &models_label)
		push_label(mut labels, mut seen, &reasoning_label)
		push_label(mut labels, mut seen, &speed_label)
		for index in 0 .. estimate.groups.len {
			group := &estimate.groups[index]
			if group.input_tokens != none || group.output_tokens != none {
				push_label(mut labels, mut seen, &billed_tokens_label)
				break
			}
		}
	}
}

pub fn (usage &StatusThreadUsage) lines(formatter &FieldFormatter, value_width usize) []text.Line {
	mut stored_estimate := unsafe { usage.estimate }
	stored_estimate.lock.rlock()
	defer { stored_estimate.lock.runlock() }
	if !stored_estimate.present {
		return []text.Line{}
	}
	estimate := &stored_estimate.value
	// V currently carries borrow provenance through a scalar cast; adding zero
	// constructs the Copy value without treating the shared lock cell as a move.
	credits_micros := estimate.estimated_usage_credits_micros + i64(0)
	mut usage_spans := [text.Span{ text: '${format_credit_micros(credits_micros)} credits' }]
	if micros := estimate.estimated_usage_usd_micros {
		if cost := format_estimated_usd_micros(micros) {
			usage_spans << text.Span{ text: ' · ' }.dim()
			usage_spans << text.Span{ text: cost }
		}
	}
	thread_label := 'Thread usage'
	mut lines := [formatter.line(&thread_label, usage_spans)]
	for dimension in [BreakdownDimension.model, .reasoning, .speed] {
		value := grouped_usage(&estimate.groups, dimension) or { continue }
		label := match dimension {
			.model { &models_label }
			.reasoning { &reasoning_label }
			.speed { &speed_label }
		}
		available := if value_width > 0 {
			value_width
		} else { /* other */
			usize(1)
		}
		wrapped := wrapping.word_wrap_lines([text.line_from(value)], wrapping.RtOptions.new(available))
		mut remaining := ThreadUsageConsumedLines{ values: wrapped }
		remaining.values.reverse_in_place()
		count := remaining.values.len
		for index in 0 .. count {
			line := remaining.values.pop()
			if index == 0 {
				lines << formatter.line(label, line.spans)
			} else {
				lines << formatter.continuation(line.spans)
			}
		}
	}
	input_tokens := sum_thread_usage_tokens(&estimate.groups, .input)
	cached_tokens := sum_thread_usage_tokens(&estimate.groups, .cached)
	output_tokens := sum_thread_usage_tokens(&estimate.groups, .output)
	if estimate.groups.len > 0 && (input_tokens != none || output_tokens != none) {
		mut tokens := []string{}
		if input := input_tokens {
			tokens << '${format_tokens_compact(input)} input'
			if cached := cached_tokens { tokens << '(${format_tokens_compact(cached)} cached)' }
		}
		if output := output_tokens {
			if tokens.len > 0 { tokens << '+' }
			tokens << '${format_tokens_compact(output)} output'
		}
		lines << formatter.line(&billed_tokens_label, [text.Span{ text: tokens.join(' ') }])
	}
	return lines
}

struct ThreadUsageConsumedLines {
mut:
	values []text.Line
}

// V represents Rust's inline count closure with a Copy selector and a shared helper.
enum ThreadUsageTokenDimension {
	input
	cached
	output
}

fn sum_thread_usage_tokens(groups &[]codex_app_server_protocol.ThreadUsageBreakdownGroup, dimension ThreadUsageTokenDimension) ?i64 {
	mut total := /* init */
	i64(0)
	for index in 0 .. groups.len {
		group := &(*groups)[index]
		count := match dimension {
			.input { group.input_tokens }
			.cached { group.cached_input_tokens }
			.output { group.output_tokens }
		}
		tokens := count or { return none }
		total = thread_usage_saturating_add(total, tokens)
	}
	return total
}

enum BreakdownDimension {
	model
	reasoning
	speed
}

struct ThreadUsageCreditsTotal {
	name  string
	order usize
mut:
	credits i64
}

fn grouped_usage(groups &[]codex_app_server_protocol.ThreadUsageBreakdownGroup, dimension BreakdownDimension) ?string {
	// Ordered entries supply BTreeMap's accumulation and its final owned iteration.
	// Each display name is constructed from borrowed source data exactly once per group.
	mut totals := []ThreadUsageCreditsTotal{}
	for index in 0 .. groups.len {
		group := &(*groups)[index]
		if group.estimated_usage_credits_micros < 0 {
			continue
		}
		value := match dimension {
			.model {
				if model := group.model {
					format_model_display_name(&model)
				} else {
					'Other'.clone()
				}
			}
			.reasoning {
				if effort := group.reasoning_effort {
					match effort {
						'none' { 'None'.clone() }
						'minimal' { 'Minimal'.clone() }
						'low' { 'Light'.clone() }
						'medium' { 'Medium'.clone() }
						'high' { 'High'.clone() }
						'xhigh' { 'Extra High'.clone() }
						'max' { 'Max'.clone() }
						'ultra' { 'Ultra'.clone() }
						else { effort.clone() }
					}
				} else {
					'Other'.clone()
				}
			}
			.speed {
				if speed := group.speed {
					match speed {
						'fast' { 'Fast mode'.clone() }
						'ultrafast' { 'Ultrafast'.clone() }
						'standard' { 'Standard'.clone() }
						else { speed.clone() }
					}
				} else {
					'Other'.clone()
				}
			}
		}
		mut found := false
		for total_index in 0 .. totals.len {
			if totals[total_index].name == value {
				totals[total_index].credits = thread_usage_saturating_add(totals[total_index].credits, group.estimated_usage_credits_micros)
				found = true
				break
			}
		}
		if !found {
			order := match dimension {
				.model { usize(0) }
				.reasoning { thread_usage_order(&value, &reasoning_order) }
				.speed { thread_usage_order(&value, &speed_order) }
			}
			totals << ThreadUsageCreditsTotal{ name: value, order: order, credits: group.estimated_usage_credits_micros }
		}
	}
	if totals.len == 0 {
		return none
	}
	mut total_credits_micros := /* init */
	i64(0)
	for index in 0 .. totals.len {
		total_credits_micros = thread_usage_saturating_add(total_credits_micros, totals[index].credits)
	}
	match dimension {
		.model { totals.sort_with_compare(thread_usage_compare_model) }
		.reasoning, .speed {
			totals.sort_with_compare(thread_usage_compare_order)
		}
	}
	ordered_totals := totals
	mut values := []string{cap: ordered_totals.len}
	for index in 0 .. ordered_totals.len {
		total := &ordered_totals[index]
		// All retained credits are nonnegative: Uint128 exactly models this i128
		// expression without the overflow or rounding of a floating-point conversion.
		percentage := if total_credits_micros <= 0 {
			u64(0)
		} else {
			unsigned.uint128_from_64(u64(total.credits)).mul_64(100).add_64(u64(total_credits_micros) / 2).div(unsigned.uint128_from_64(u64(total_credits_micros))).lo
		}
		values << '${total.name} ${percentage}%'
	}
	return values.join(', ')
}

fn thread_usage_order(name &string, order &[]string) usize {
	for index in 0 .. order.len {
		if (*order)[index] == *name {
			return usize(index)
		}
	}
	return ~usize(0)
}

fn thread_usage_compare_model(left &ThreadUsageCreditsTotal, right &ThreadUsageCreditsTotal) int {
	if left.credits > right.credits {
		return -1
	}
	if left.credits < right.credits {
		return 1
	}
	return compare_strings(left.name, right.name)
}

fn thread_usage_compare_order(left &ThreadUsageCreditsTotal, right &ThreadUsageCreditsTotal) int {
	if left.order < right.order {
		return -1
	}
	if left.order > right.order {
		return 1
	}
	return compare_strings(left.name, right.name)
}

fn thread_usage_saturating_add(left i64, right i64) i64 {
	maximum := i64(9223372036854775807)
	minimum := -maximum - 1
	if right > 0 && left > maximum - right {
		return maximum
	}
	if right < 0 && left < minimum - right {
		return minimum
	}
	return left + right
}

fn format_model_display_name(source &string) string {
	model := model_catalog.model_display_name(source)
	dash := model.index('-') or { return model }
	prefix := model[..dash]
	remainder := model[dash + 1..]
	gpt := 'gpt'
	if !thread_usage_ascii_equal(&prefix, &gpt) || remainder.len == 0 {
		return model
	}
	segments := remainder.split('-')
	first := &segments[0]
	mut display_name := 'GPT-${*first}'
	numeric_model := first.len > 0 && (*first)[0] >= `0` && (*first)[0] <= `9`
	oai := 'oai'
	for index in 1 .. segments.len {
		segment := &segments[index]
		display_name += if numeric_model { ' ' } else { '-' }
		if thread_usage_ascii_equal(segment, &oai) {
			display_name += 'OAI'
			continue
		}
		mut characters := segment.runes_iterator()
		if first_character := characters.next() {
			display_name += unicode_segmentation.uppercase(first_character)
			display_name += (*segment)[first_character.str().len..]
		}
	}
	return display_name
}

fn thread_usage_ascii_equal(left &string, right &string) bool {
	if left.len != right.len {
		return false
	}
	for index in 0 .. left.len {
		a := (*left)[index]
		b := (*right)[index]
		if (if a >= `A` && a <= `Z` { a + 32 } else { a }) != (if b >= `A` && b <= `Z` {
			b + 32
		} else {
			b
		}) {
			return false
		}
	}
	return true
}

pub fn format_credit_micros(value i64) string {
	micros := unsigned.uint128_from_64(u64(if value > 0 {
		value
	} else { /* other */
		i64(0)
	}))
	mut unit_micros := u64(1000000)
	mut suffix := ''
	for index, unit in [u64(1000000000000000000), 1000000000000000, 1000000000000, 1000000000] {
		if micros.cmp_64(unit) >= 0 {
			unit_micros = unit
			suffix = ['T', 'B', 'M', 'K'][index]
			break
		}
	}
	tenths := micros.mul_64(10).add_64(unit_micros / 2).div(unsigned.uint128_from_64(unit_micros)).lo
	whole := tenths / 10
	fraction := tenths % 10
	if fraction == 0 {
		return '${whole}${suffix}'
	}
	return '${whole}.${fraction}${suffix}'
}

pub fn format_estimated_usd_micros(micros i64) ?string {
	if micros < 0 {
		return none
	}
	if micros > 0 && micros < 100 {
		return '~$0.${micros:06}'
	}
	if micros > 0 && micros < 10000 {
		ten_thousandths := thread_usage_saturating_add(micros, /* rhs */
			50) / 100
		return '~$0.${ten_thousandths:04}'
	}
	cents := thread_usage_saturating_add(micros, /* rhs */
		5000) / 10000
	return '~\$${cents / 100}.${cents % 100:02}'
}
