module mpsc

import codex_app_server_protocol as api
import sync

// STUB: Tokio's unbounded ServerNotification channel, with the same native wake
// owner already used by the translated Instant specialization.
@[heap]
struct NotificationChannel {
mut:
	mutex          &sync.Mutex = sync.new_mutex()
	wake           FrameWake   = FrameWake.new()
	queue          []api.ServerNotification
	sender_alive   bool = true
	receiver_alive bool = true
	receiving      int
	wake_alive     bool = true
}

// STUB: tokio::sync::mpsc::UnboundedSender<ServerNotification>.
pub struct NotificationSender implements Drop {
	channel &NotificationChannel
}

// STUB: tokio::sync::mpsc::UnboundedReceiver<ServerNotification>.
pub struct NotificationReceiver implements Drop {
	channel &NotificationChannel
}

// STUB: cancellation wake retained by a timed future's caller. Tokio dropping
// the receive future releases its receiver; V closes the shared native queue to
// wake and release its worker when timeout or an earlier request error occurs.
pub struct NotificationCancellation {
	channel &NotificationChannel
}

// STUB: borrow a cancellation wake without duplicating the owning receiver lease.
pub fn (receiver &NotificationReceiver) cancellation_handle() NotificationCancellation {
	return NotificationCancellation{ channel: receiver.channel }
}

// STUB: the cancellation path of UnboundedReceiver Drop.
pub fn (cancellation NotificationCancellation) cancel() {
	receiver := NotificationReceiver{ channel: cancellation.channel }
	receiver.close()
}

// STUB: unbounded_channel specialized for the app-server notification payload.
pub fn unbounded_notifications_channel() (NotificationSender, NotificationReceiver) {
	channel := &NotificationChannel{}
	return NotificationSender{ channel: channel }, NotificationReceiver{ channel: channel }
}

// STUB: UnboundedSender::send consumes the notification and fails after closure.
pub fn (sender &NotificationSender) send(notification api.ServerNotification) ! {
	mut channel := sender.channel
	channel.mutex.lock()
	defer { channel.mutex.unlock() }
	if !channel.sender_alive || !channel.receiver_alive {
		return error('channel closed')
	}
	// Store newest first so pop moves the oldest value out without cloning it.
	channel.queue.insert(0, notification)
	channel.wake.post()
}

// STUB: release native synchronization only after both halves and receives end.
fn (mut channel NotificationChannel) release_wake() {
	if channel.wake_alive && !channel.sender_alive && !channel.receiver_alive && channel.receiving == 0 {
		channel.wake.destroy()
		channel.wake_alive = false
	}
}

// STUB: sender Drop closes after queued notifications have been delivered. Normal
// GC builds require explicit close; ownership builds invoke Drop automatically.
pub fn (sender &NotificationSender) close() {
	mut channel := sender.channel
	channel.mutex.lock()
	defer { channel.mutex.unlock() }
	if channel.sender_alive {
		channel.sender_alive = false
		channel.wake.post()
		channel.release_wake()
	}
}

// STUB: UnboundedSender destruction.
pub fn (mut sender NotificationSender) drop() {
	sender.close()
}

// STUB: UnboundedReceiver::recv parks until an owned value arrives or senders
// close; queued values drain before closure, as in Tokio.
pub fn (mut receiver NotificationReceiver) recv() ?api.ServerNotification {
	mut channel := receiver.channel
	channel.mutex.lock()
	channel.receiving++
	channel.mutex.unlock()
	defer {
		channel.mutex.lock()
		channel.receiving--
		channel.release_wake()
		channel.mutex.unlock()
	}
	for {
		channel.mutex.lock()
		if !channel.receiver_alive {
			channel.mutex.unlock()
			return none
		}
		if channel.queue.len > 0 {
			value := channel.queue.pop()
			channel.mutex.unlock()
			return value
		}
		if !channel.sender_alive {
			channel.mutex.unlock()
			return none
		}
		channel.mutex.unlock()
		channel.wake.wait()
	}
	return none
}

// STUB: dropping the receiver closes its queue and wakes a parked receive.
pub fn (receiver &NotificationReceiver) close() {
	mut channel := receiver.channel
	channel.mutex.lock()
	defer { channel.mutex.unlock() }
	if channel.receiver_alive {
		channel.receiver_alive = false
		channel.queue.clear()
		channel.wake.post()
		channel.release_wake()
	}
}

// STUB: UnboundedReceiver destruction.
pub fn (mut receiver NotificationReceiver) drop() {
	receiver.close()
}
