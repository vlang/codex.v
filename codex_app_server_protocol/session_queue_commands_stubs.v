module codex_app_server_protocol

// STUB: protocol/v2/thread.rs::QueuedSubmission retains every typed wire field.
pub struct QueuedSubmission {
pub:
	id                     string
	input                  []UserInput
	client_user_message_id string @[json: 'clientUserMessageId']
}

// STUB: protocol/v2/thread.rs::ThreadQueueAddParams, whose wire names are camelCase.
pub struct ThreadQueueAddParams {
pub:
	thread_id              string @[json: 'threadId']
	input                  []UserInput
	client_user_message_id string @[json: 'clientUserMessageId']
}

// STUB: protocol/v2/thread.rs::ThreadQueueAddResponse retains the full submission.
pub struct ThreadQueueAddResponse {
pub:
	queued_submission QueuedSubmission @[json: 'queuedSubmission']
}

// STUB: protocol/common.rs::ClientRequest::ThreadQueueAdd payload.
pub struct ClientRequestThreadQueueAdd {
pub:
	request_id RequestId
	params     ThreadQueueAddParams
}

// STUB: protocol/experimental_api.rs::experimental_required_message builds an
// owned string from the borrowed capability reason.
pub fn experimental_required_message(reason &string) string {
	return '${*reason} requires experimentalApi capability'
}

// STUB: typed request serialization owns an independent ThreadQueueAdd payload.
pub fn (params &ThreadQueueAddParams) clone() ThreadQueueAddParams {
	mut input := []UserInput{cap: params.input.len}
	for index in 0 .. params.input.len {
		input << (&params.input[index]).clone()
	}
	return ThreadQueueAddParams{ thread_id: params.thread_id.clone(), input: input, client_user_message_id: params.client_user_message_id.clone() }
}

// STUB: a decoded queue response owns its complete submission independently.
pub fn (response &ThreadQueueAddResponse) clone() ThreadQueueAddResponse {
	mut input := []UserInput{cap: response.queued_submission.input.len}
	for index in 0 .. response.queued_submission.input.len {
		input << (&response.queued_submission.input[index]).clone()
	}
	return ThreadQueueAddResponse{ queued_submission: QueuedSubmission{ id: response.queued_submission.id.clone(), input: input, client_user_message_id: response.queued_submission.client_user_message_id.clone() } }
}
