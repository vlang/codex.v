module chrono

import time
import sync

// STUB: chrono::Duration stores the Copy second count used by update freshness.
pub struct Duration {
	seconds i64
}

// STUB: chrono::Duration::hours preserves the exact 20-hour offset.
pub fn Duration.hours(hours i64) Duration {
	return Duration{ seconds: hours * 3600 }
}

// STUB: chrono::Utc's clock owner and source static API namespace.
pub struct Utc {}

// STUB: deterministic clock fixture is separate from Config and disabled normally.
@[heap]
struct UpdatesClockFixture {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	now   ?DateTimeUtc
}

// STUB: synchronized fixture backing the real UTC wall-clock boundary.
const updates_clock_fixture = &UpdatesClockFixture{}

// STUB: Utc::now reads the real wall clock unless the test clock is supplied.
pub fn Utc.now() DateTimeUtc {
	unsafe {
		mut fixture := updates_clock_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		if now := fixture.now {
			return now
		}
	}
	now := time.now()
	return DateTimeUtc{ seconds: now.unix(), nanoseconds: u32(now.nanosecond) }
}

// STUB: DateTime - Duration retains the fractional timestamp component.
pub fn (timestamp DateTimeUtc) sub(duration Duration) DateTimeUtc {
	return DateTimeUtc{ seconds: timestamp.seconds - duration.seconds, nanoseconds: timestamp.nanoseconds }
}

// STUB: chrono DateTime's strict ordering compares seconds then nanoseconds.
pub fn (timestamp DateTimeUtc) before(other DateTimeUtc) bool {
	return timestamp.seconds < other.seconds || (timestamp.seconds == other.seconds && timestamp.nanoseconds < other.nanoseconds)
}

$if test {
	// STUB: installs an allocation-free deterministic UTC clock for branch tests.
	pub fn set_updates_clock_fixture(now DateTimeUtc) {
		unsafe {
			mut fixture := updates_clock_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			fixture.now = now
		}
	}

	// STUB: restores the real clock after update fixtures finish.
	pub fn clear_updates_clock_fixture() {
		unsafe {
			mut fixture := updates_clock_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			fixture.now = none
		}
	}
}
