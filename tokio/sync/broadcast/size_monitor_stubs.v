module broadcast

// STUB: broadcast::Receiver::resubscribe starts at the current sequence, with no retained
// messages. The subscription owns an independent lease on the existing specialized channel.
pub fn (receiver &DrawReceiver) resubscribe() DrawReceiver {
	unsafe {
		mut state := receiver.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		lease := &DrawLease{ cursor: state.sequence }
		state.receivers << lease
		return DrawReceiver{ channel: state, lease: lease }
	}
}
