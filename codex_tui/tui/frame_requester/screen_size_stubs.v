module frame_requester

import std_time

// STUB: screen-size fixture observation of attempted request-channel sends, including
// the ignored closed-channel sends made through FrameRequester::test_dummy.
pub fn (requester &FrameRequester) fixture_request_count() int {
	return requester.frame_schedule_tx.fixture_request_count()
}

// STUB: screen-size fixture observation of the last attempted deadline; Instant is Copy.
pub fn (requester &FrameRequester) fixture_last_request() ?std_time.Instant {
	return requester.frame_schedule_tx.fixture_last_request()
}
