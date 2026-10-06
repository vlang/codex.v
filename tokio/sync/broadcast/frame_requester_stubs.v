module broadcast

import sync

// STUB: the destruction contract of Tokio broadcast channel handles.
interface Drop {
mut:
	drop()
}

// STUB: the () payload of tokio::sync::broadcast; it carries no data.
pub struct Draw {}

// STUB: Tokio's broadcast ring specialized for (). Sequence numbers represent unit payloads.
@[heap]
struct DrawChannel {
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	capacity  u64
	sequence  u64
	senders   int = 1
	receivers []&DrawLease
}

// STUB: one broadcast receiver's independent cursor and native notification semaphore.
@[heap]
struct DrawLease {
mut:
	cursor u64
	active bool            = true
	wake   &sync.Semaphore = sync.new_semaphore()
}

// STUB: one owned broadcast sender lease, distinct for every explicit clone.
@[heap]
struct SenderLease {
mut:
	active bool = true
}

// STUB: tokio::sync::broadcast::Sender<()>.
pub struct DrawSender implements Drop {
	channel &DrawChannel
	lease   &SenderLease = &SenderLease{}
}

// STUB: tokio::sync::broadcast::Receiver<()>.
pub struct DrawReceiver implements Drop {
	channel &DrawChannel
	lease   &DrawLease
}

// STUB: typed Tokio receive errors, keeping lag distinct from empty/closed channels.
pub enum ReceiveErrorKind {
	empty
	closed
	lagged
}

// STUB: Tokio's TryRecvError/RecvError payload specialization.
pub struct ReceiveError {
pub:
	kind   ReceiveErrorKind
	missed u64
}

// STUB: IError formatting for the typed broadcast receive error.
pub fn (err ReceiveError) msg() string {
	return match err.kind {
		.empty { 'channel empty' }
		.closed { 'channel closed' }
		.lagged { 'channel lagged by ${err.missed}' }
	}
}

// STUB: distinct error codes for the typed broadcast receive errors.
pub fn (err ReceiveError) code() int {
	return int(err.kind) + 1
}

// STUB: tokio::sync::broadcast::channel specialized for (). Tokio rounds capacity upward
// to a power of two; a receiver beyond that retained range receives Lagged before the next draw.
pub fn channel(capacity int) (DrawSender, DrawReceiver) {
	assert capacity > 0
	mut rounded := u64(1)
	for rounded < u64(capacity) {
		rounded <<= 1
	}
	lease := &DrawLease{}
	state := &DrawChannel{ capacity: rounded, receivers: [lease] }
	return DrawSender{ channel: state }, DrawReceiver{ channel: state, lease: lease }
}

// STUB: broadcast::Sender::clone shares the broadcast state.
pub fn (sender &DrawSender) clone() DrawSender {
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		assert sender.lease.active
		state.senders++
		return DrawSender{ channel: state }
	}
}

// STUB: broadcast::Sender::subscribe starts at the newest sequence without old messages.
pub fn (sender &DrawSender) subscribe() DrawReceiver {
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		lease := &DrawLease{ cursor: state.sequence }
		state.receivers << lease
		return DrawReceiver{ channel: state, lease: lease }
	}
}

// STUB: broadcast::Sender::send(()), returning the number of current receiving halves.
pub fn (sender &DrawSender) send(_ Draw) !int {
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		if !sender.lease.active || state.receivers.len == 0 {
			return error('channel closed')
		}
		state.sequence++
		for mut receiver in state.receivers {
			receiver.wake.post()
		}
		return state.receivers.len
	}
}

// STUB: Receiver::try_recv preserves each subscriber's independent cursor and lag errors.
pub fn (mut receiver DrawReceiver) try_recv() !Draw {
	unsafe {
		mut state := receiver.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		mut lease := receiver.lease
		if !lease.active {
			return ReceiveError{ kind: .closed }
		}
		available := state.sequence - lease.cursor
		if available > state.capacity {
			lease.cursor = state.sequence - state.capacity
			return ReceiveError{ kind: .lagged, missed: available - state.capacity }
		}
		if available > 0 {
			lease.cursor++
			return Draw{}
		}
		if state.senders == 0 {
			return ReceiveError{ kind: .closed }
		}
		return ReceiveError{ kind: .empty }
	}
}

// STUB: Receiver::recv waits on a native notification and reports closure/lag faithfully.
pub fn (mut receiver DrawReceiver) recv() !Draw {
	for {
		draw := receiver.try_recv() or {
			if err.code() != int(ReceiveErrorKind.empty) + 1 {
				return err
			}
			unsafe {
				mut lease := receiver.lease
				lease.wake.wait()
			}
			continue
		}
		return draw
	}
	return Draw{}
}

// STUB: explicit sender destruction for normal builds; ownership builds call Drop.
pub fn (sender &DrawSender) close() {
	unsafe {
		mut state := sender.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		mut lease := sender.lease
		if lease.active {
			lease.active = false
			state.senders--
			if state.senders == 0 {
				for mut receiver in state.receivers {
					receiver.wake.post()
				}
			}
		}
	}
}

// STUB: owned sender Drop hook.
pub fn (mut sender DrawSender) drop() {
	sender.close()
}

// STUB: receiver destruction stops deliveries to this subscription.
pub fn (receiver &DrawReceiver) close() {
	unsafe {
		mut state := receiver.channel
		state.mutex.lock()
		defer { state.mutex.unlock() }
		mut lease := receiver.lease
		if lease.active {
			lease.active = false
			for index, subscriber in state.receivers {
				if subscriber == lease {
					state.receivers.delete(index)
					break
				}
			}
			lease.wake.post()
		}
	}
}

// STUB: owned receiver Drop hook.
pub fn (mut receiver DrawReceiver) drop() {
	receiver.close()
}
