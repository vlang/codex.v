module codex_app_server_protocol

// STUB: app-server-protocol/src/protocol/v2/thread_usage.rs::ThreadUsage.
// Complete observed data shape; schema/TypeScript generation remain untranslated.
pub struct ThreadUsage {
pub:
	thread_id                      string @[json: 'threadId']
	estimated_usage_credits_micros i64    @[json: 'estimatedUsageCreditsMicros']
	estimated_usage_usd_micros     ?i64   @[json: 'estimatedUsageUsdMicros']
	groups                         []ThreadUsageBreakdownGroup
}

// STUB: app-server-protocol/src/protocol/v2/thread_usage.rs::ThreadUsageBreakdownGroup.
pub struct ThreadUsageBreakdownGroup {
pub:
	model                          ?string
	reasoning_effort               ?string @[json: 'reasoningEffort']
	speed                          ?string
	estimated_usage_credits_micros i64  @[json: 'estimatedUsageCreditsMicros']
	net_new_input_tokens           ?i64 @[json: 'netNewInputTokens']
	cached_input_tokens            ?i64 @[json: 'cachedInputTokens']
	input_tokens                   ?i64 @[json: 'inputTokens']
	output_tokens                  ?i64 @[json: 'outputTokens']
	total_tokens                   ?i64 @[json: 'totalTokens']
}

// STUB: derived Clone, duplicating owned optional strings at the real clone boundary.
pub fn (value &ThreadUsageBreakdownGroup) clone() ThreadUsageBreakdownGroup {
	return ThreadUsageBreakdownGroup{
		model:                          if model := value.model { model.clone() } else { none }
		reasoning_effort:               if effort := value.reasoning_effort {
			effort.clone()
		} else {
			none
		}
		speed:                          if speed := value.speed { speed.clone() } else { none }
		estimated_usage_credits_micros: value.estimated_usage_credits_micros
		net_new_input_tokens:           value.net_new_input_tokens
		cached_input_tokens:            value.cached_input_tokens
		input_tokens:                   value.input_tokens
		output_tokens:                  value.output_tokens
		total_tokens:                   value.total_tokens
	}
}

// STUB: derived Clone, duplicating the owned thread ID and breakdown groups.
pub fn (value &ThreadUsage) clone() ThreadUsage {
	mut groups := []ThreadUsageBreakdownGroup{cap: value.groups.len}
	for index in 0 .. value.groups.len {
		groups << (&value.groups[index]).clone()
	}
	return ThreadUsage{
		thread_id:                      value.thread_id.clone()
		estimated_usage_credits_micros: value.estimated_usage_credits_micros
		estimated_usage_usd_micros:     value.estimated_usage_usd_micros
		groups:                         groups
	}
}
