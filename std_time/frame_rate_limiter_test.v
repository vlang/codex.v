module std_time

fn test_duration_full_range_constructors_and_nanosecond_normalization() {
	assert Duration.new(3, 2_000_000_005) == Duration.new(5, 5)
	assert Duration.from_millis(~u64(0)).as_millis().str() == '18446744073709551615'
	assert Duration.from_micros(~u64(0)).as_micros().str() == '18446744073709551615'
	assert Duration.from_nanos(~u64(0)).as_nanos().str() == '18446744073709551615'
	assert duration_max.as_secs() == ~u64(0)
	assert duration_max.subsec_nanos() == 999_999_999
	assert duration_max.as_millis().str() == '18446744073709551615999'
	assert duration_max.as_micros().str() == '18446744073709551615999999'
	assert duration_max.as_nanos().str() == '18446744073709551615999999999'
	quotient, _ := duration_max.as_millis().quo_rem_64(600)
	assert quotient.mod_64(2) == 0
}

fn test_duration_checked_arithmetic_carries_borrows_and_overflow() {
	assert Duration.new(7, 999_999_999).add(Duration.from_nanos(2)) == Duration.new(8, 1)
	assert Duration.new(8, 1).sub(Duration.from_nanos(2)) == Duration.new(7, 999_999_999)
	assert duration_max.checked_add(Duration.from_nanos(1)) == none
	assert duration_zero.checked_sub(Duration.from_nanos(1)) == none
	assert (duration_max.checked_add(duration_zero) or { panic('zero cannot overflow') }) == duration_max
	assert (duration_max.checked_sub(duration_max) or { panic('equal durations cannot underflow') }) == duration_zero
	assert Duration.from_secs(2) > Duration.new(1, 999_999_999)
}

fn test_instant_native_monotonic_copy_arithmetic_and_saturation() {
	first := Instant.now()
	second := Instant.now()
	assert second >= first
	interval := Duration.new(1, 25)
	later := first.add(interval)
	assert later.sub(interval) == first
	assert later.duration_since(first) == interval
	assert first.duration_since(later) == duration_zero
	assert later.saturating_duration_since(first) == interval
	assert first < later
	assert first.max(later) == later
	assert first.add(interval) == later
	assert first.elapsed() >= duration_zero
}

fn test_instant_maximum_checked_add_and_nanosecond_carry() {
	maximum := Instant.maximum_for_clock()
	assert maximum.checked_add(Duration.from_nanos(1)) == none
	assert (maximum.checked_add(duration_zero) or { panic('zero cannot overflow') }) == maximum
	before := maximum.sub(Duration.from_nanos(1))
	assert before.add(Duration.from_nanos(1)) == maximum
	assert maximum.duration_since(before) == Duration.from_nanos(1)
}

fn test_unix_instant_preserves_the_full_signed_seconds_range() {
	$if !windows {
		minimum := Instant{ unix_seconds: i64(-9_223_372_036_854_775_807 - 1) }
		maximum := Instant.maximum_for_clock()
		assert minimum.checked_sub(Duration.from_nanos(1)) == none
		assert (minimum.checked_add(Duration.from_secs(~u64(0))) or { panic('full signed range must fit') }) == Instant{
			unix_seconds: 9_223_372_036_854_775_807
		}
		assert maximum.duration_since(minimum) == duration_max
		assert maximum.sub(duration_max) == minimum
		assert minimum.add(duration_max) == maximum
		assert Instant{ unix_seconds: -1, unix_nanos: 999_999_999 }.add(Duration.from_nanos(1)) == Instant{}
		assert Instant{}.sub(Duration.from_nanos(1)) == Instant{
			unix_seconds: -1
			unix_nanos:   999_999_999
		}
	}
}
