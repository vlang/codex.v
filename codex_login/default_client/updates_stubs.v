module default_client

import http
import sync

// STUB: login/auth/default_client's originator, user agent, and residency globals
// are not translated. Explicit fixture headers exercise the real call boundary.
@[heap]
struct DefaultHeadersFixture {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	enabled bool
	headers &http.HeaderMap = unsafe { nil }
}

// STUB: fixture storage for login's process-wide shared default headers.
const updates_default_headers_fixture = &DefaultHeadersFixture{}

// STUB: default_headers preserves its owned HeaderMap signature. Without a
// fixture, unavailable metadata remains explicit and the HTTP send fails.
pub fn default_headers() http.HeaderMap {
	unsafe {
		mut fixture := updates_default_headers_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		if fixture.enabled {
			return fixture.headers.clone()
		}
	}
	return http.HeaderMap{ unavailable_reason: 'STUB: login default request headers are untranslated' }
}

$if test {
	// STUB: test-only owned injection for the untranslated login default globals.
	pub fn set_updates_headers_fixture(headers http.HeaderMap) {
		unsafe {
			mut fixture := updates_default_headers_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			// Keep a stable owning pointer rather than a resource-bearing Option
			// cell, which V3 cannot reliably reset and then borrow repeatedly.
			fixture.headers = &http.HeaderMap{ values: headers.values, unavailable_reason: headers.unavailable_reason }
			fixture.enabled = true
		}
	}

	// STUB: restores the explicit unavailable default-header boundary after tests.
	pub fn clear_updates_headers_fixture() {
		unsafe {
			mut fixture := updates_default_headers_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			fixture.enabled = false
			fixture.headers = unsafe { nil }
		}
	}
}
