module broadcast

fn test_broadcast_subscribers_receive_independently_and_new_subscriber_skips_old() {
	sender, mut receiver := channel(16)
	defer {
		sender.close()
		receiver.close()
	}
	assert sender.send(Draw{}) or { panic(err) } == 1
	mut second := sender.subscribe()
	defer { second.close() }
	receiver.try_recv() or { panic(err) }
	if _ := second.try_recv() {
		assert false, 'new subscriber observed an earlier draw'
	} else {
		assert err.code() == int(ReceiveErrorKind.empty) + 1
	}
	assert sender.send(Draw{}) or { panic(err) } == 2
	receiver.try_recv() or { panic(err) }
	second.try_recv() or { panic(err) }
}

fn test_broadcast_reports_lag_and_retains_rounded_capacity() {
	sender, mut receiver := channel(3)
	defer {
		sender.close()
		receiver.close()
	}
	for _ in 0 .. 7 {
		sender.send(Draw{}) or { panic(err) }
	}
	if _ := receiver.try_recv() {
		assert false, 'overrun receiver must report lag'
	} else {
		assert err is ReceiveError
		assert err.kind == .lagged
		assert err.missed == 3
	}
	for _ in 0 .. 4 {
		receiver.try_recv() or { panic(err) }
	}
	if _ := receiver.try_recv() {
		assert false, 'retained messages were delivered more than once'
	} else {
		assert err.code() == int(ReceiveErrorKind.empty) + 1
	}
}

fn test_broadcast_clones_and_close_are_idempotent_and_drain_before_closure() {
	sender, mut receiver := channel(16)
	clone := sender.clone()
	sender.close()
	sender.close()
	clone.send(Draw{}) or { panic(err) }
	clone.close()
	receiver.recv() or { panic(err) }
	if _ := receiver.recv() {
		assert false, 'last sender should close an exhausted receiver'
	} else {
		assert err.code() == int(ReceiveErrorKind.closed) + 1
	}
	receiver.close()
	receiver.close()
}

fn test_broadcast_send_fails_without_receivers_and_can_recover_after_subscribe() {
	sender, mut receiver := channel(16)
	defer { sender.close() }
	receiver.close()
	if _ := sender.send(Draw{}) {
		assert false, 'send without receivers must fail'
	}
	mut second := sender.subscribe()
	defer { second.close() }
	assert sender.send(Draw{}) or { panic(err) } == 1
	second.try_recv() or { panic(err) }
}
