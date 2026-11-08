module auto_review_denials

import codex_protocol.approvals
import codex_protocol.request_permissions
import codex_protocol.models
import codex_utils_absolute_path
import codex_utils_path_uri
import std_fmt
import unicode_segmentation

fn denied_event(id usize) approvals.GuardianAssessmentEvent {
	mut turn_id := 'turn-1'
	mut cwd := '/tmp'
	$if ownership ? {
		turn_id = turn_id.to_owned()
		cwd = cwd.to_owned()
	}
	absolute := codex_utils_absolute_path.from_absolute_path(&cwd) or { panic(err) }
	command := approvals.GuardianCommandAction{
		source:  .shell
		command: 'rm -rf /tmp/test-${id}'
		cwd:     codex_utils_path_uri.LegacyAppPathString.from_absolute(absolute)
	}
	return approvals.GuardianAssessmentEvent{
		review_reason:      none
		id:                 'review-${id}'
		target_item_id:     none
		plugin_id:          none
		script_path:        none
		turn_id:            turn_id
		started_at_ms:      0
		completed_at_ms:    i64(1)
		status:             .denied
		risk_level:         none
		user_authorization: none
		rationale:          'rationale ${id}'
		decision_source:    none
		action:             command
	}
}

// The Rust test collects Vec<&str>; owned V strings adapt that borrowed collection
// only in the test oracle. The implementation iterator itself never clones an event.
fn denial_ids(denials &RecentAutoReviewDenials) []string {
	mut ids := []string{}
	mut entries := denials.entries()
	for {
		entry := entries.next() or { break }
		ids << entry.value.id.clone()
	}
	return ids
}

fn test_keeps_only_ten_most_recent_denials() {
	mut denials := RecentAutoReviewDenials{}
	for id in 0 .. 12 {
		denials.push(denied_event(usize(id)))
	}
	ids := denial_ids(&denials)
	assert ids == ['review-11', 'review-10', 'review-9', 'review-8', 'review-7', 'review-6', 'review-5',
		'review-4', 'review-3', 'review-2']
}

fn test_push_ignores_every_other_status_and_refreshes_duplicate_at_front() {
	mut denials := RecentAutoReviewDenials{}
	assert denials.is_empty()
	for status in [approvals.GuardianAssessmentStatus.in_progress, .approved, .timed_out, .aborted] {
		mut ignored := denied_event(9)
		ignored.status = status
		denials.push(ignored)
	}
	assert denials.is_empty()
	denials.push(denied_event(1))
	denials.push(denied_event(2))
	denials.push(denied_event(3))
	mut updated := denied_event(1)
	updated.completed_at_ms = i64(50)
	updated.rationale = 'refreshed rationale'
	denials.push(updated)
	assert denial_ids(&denials) == ['review-1', 'review-3', 'review-2']
	mut iter := denials.entries()
	first := iter.next() or { panic('expected refreshed denial') }
	assert first.value.completed_at_ms or { i64(-1) } == 50
	assert first.value.rationale or { '' } == 'refreshed rationale'
	assert !denials.is_empty()
	assert denial_ids(&denials) == ['review-1', 'review-3', 'review-2']
}

fn test_borrowed_entries_are_lazy_reusable_views_of_the_original_events() {
	mut denials := RecentAutoReviewDenials{}
	denials.push(denied_event(3))
	denials.push(denied_event(4))
	mut first_iter := denials.entries()
	mut second_iter := denials.entries()
	first := first_iter.next() or { panic('first iterator was empty') }
	second := second_iter.next() or { panic('second iterator was empty') }
	assert first.value == second.value
	assert first.value.id == 'review-4'
	assert first.value.turn_id == 'turn-1'
	assert first.value.rationale or { '' } == 'rationale 4'
	after := first_iter.next() or { panic('missing older denial') }
	assert after.value.id == 'review-3'
	assert first_iter.next() == none
	assert first_iter.next() == none
	assert denial_ids(&denials) == ['review-4', 'review-3']
}

fn extract_denial_from_dropped_owner() approvals.GuardianAssessmentEvent {
	mut denials := RecentAutoReviewDenials{}
	denials.push(denied_event(1))
	denials.push(denied_event(2))
	denials.push(denied_event(3))
	mut id := 'review-2'
	$if ownership ? {
		id = id.to_owned()
	}
	event := denials.take(&id) or { panic('missing denial') }
	assert id == 'review-2'
	assert denials.take(&id) == none
	assert denial_ids(&denials) == ['review-3', 'review-1']
	return event
}

fn test_take_moves_the_complete_event_and_preserves_remaining_order() {
	event := extract_denial_from_dropped_owner()
	assert event.id == 'review-2'
	assert event.turn_id == 'turn-1'
	assert event.rationale or { '' } == 'rationale 2'
	assert event.completed_at_ms or { i64(-1) } == 1
	assert action_summary(&event.action) == 'rm -rf /tmp/test-2'
	assert action_summary(&event.action) == 'rm -rf /tmp/test-2'
	match event.action {
		approvals.GuardianCommandAction {
			assert event.action.source == .shell
			assert event.action.command == 'rm -rf /tmp/test-2'
			assert event.action.cwd.render_for_ui() == '/tmp'
		}
		else {
			assert false
		}
	}
}

struct EventBuffers {
	id        voidptr
	turn_id   voidptr
	rationale voidptr
	plugin_id voidptr
	argv      voidptr
	argument  voidptr
}

fn take_nested_event_and_buffers() (approvals.GuardianAssessmentEvent, EventBuffers) {
	mut id := 'nested-review'
	mut turn_id := 'nested-turn'
	mut rationale := 'heap rationale'
	mut plugin_id := 'plugin-owned'
	mut program := 'program-owner'
	mut first_arg := 'argv-zero'
	mut second_arg := 'argument with spaces'
	$if ownership ? {
		id = id.to_owned()
		turn_id = turn_id.to_owned()
		rationale = rationale.to_owned()
		plugin_id = plugin_id.to_owned()
		program = program.to_owned()
		first_arg = first_arg.to_owned()
		second_arg = second_arg.to_owned()
	} $else {
		id = id.clone()
		turn_id = turn_id.clone()
		rationale = rationale.clone()
		plugin_id = plugin_id.clone()
		program = program.clone()
		first_arg = first_arg.clone()
		second_arg = second_arg.clone()
	}
	arguments := [first_arg, second_arg]
	buffers := EventBuffers{
		id:        id.str
		turn_id:   turn_id.str
		rationale: rationale.str
		plugin_id: plugin_id.str
		argv:      arguments.data
		argument:  arguments[1].str
	}
	command := approvals.GuardianExecveAction{
		program: program
		argv:    arguments
		cwd:     codex_utils_absolute_path.AbsolutePathBuf{ path: '/tmp' }
	}
	event := approvals.GuardianAssessmentEvent{
		id:        id
		turn_id:   turn_id
		rationale: rationale
		plugin_id: plugin_id
		status:    .denied
		action:    command
	}
	mut denials := RecentAutoReviewDenials{}
	denials.push(denied_event(1))
	denials.push(event)
	{
		mut iter := denials.entries()
		stored := iter.next() or { panic('missing nested event') }
		$if ownership ? {
			assert voidptr(stored.value.id.str) == buffers.id
		}
		match stored.value.action {
			approvals.GuardianExecveAction {
				$if ownership ? {
					assert stored.value.action.argv.data == buffers.argv
				}
			}
			else {
				assert false
			}
		}
	}
	lookup := 'nested-review'
	taken := denials.take(&lookup) or { panic('missing nested event') }
	$if ownership ? {
		assert voidptr(taken.id.str) == buffers.id
	}
	assert denial_ids(&denials) == ['review-1']
	// Refill/remove the deque before its destruction, exposing retained-slot aliases.
	denials.push(denied_event(3))
	denials.push(denied_event(1))
	return taken, buffers
}

fn test_take_transfers_nested_buffers_without_cloning_after_owner_is_dropped() {
	// Normal V array.insert emits a derived deep copy of the event; ownership
	// insertion transfers the original owner. Content/lifetime checks run in both
	// modes, while buffer identity checks assert the source move in ownership mode.
	event, buffers := take_nested_event_and_buffers()
	assert event.id == 'nested-review'
	assert event.turn_id == 'nested-turn'
	$if ownership ? {
		assert voidptr(event.id.str) == buffers.id
		assert voidptr(event.turn_id.str) == buffers.turn_id
	}
	if rationale := event.rationale {
		assert rationale == 'heap rationale'
		$if ownership ? {
			assert voidptr(rationale.str) == buffers.rationale
		}
	} else {
		assert false
	}
	if plugin_id := event.plugin_id {
		assert plugin_id == 'plugin-owned'
		$if ownership ? {
			assert voidptr(plugin_id.str) == buffers.plugin_id
		}
	} else {
		assert false
	}
	assert action_summary(&event.action) == "argv-zero 'argument with spaces'"
	assert action_summary(&event.action) == "argv-zero 'argument with spaces'"
	match event.action {
		approvals.GuardianExecveAction {
			assert event.action.argv == ['argv-zero', 'argument with spaces']
			$if ownership ? {
				assert event.action.argv.data == buffers.argv
				assert voidptr(event.action.argv[1].str) == buffers.argument
			}
			assert event.action.program == 'program-owner'
		}
		else {
			assert false
		}
	}
}

fn test_command_and_execve_summaries_preserve_quoting_and_nul_fallback() {
	mut text := 'printf "literal"'
	mut program := 'fallback executable'
	mut argv := ['printf', 'a b', "don't", '$HOME']
	$if ownership ? {
		text = text.to_owned()
		program = program.to_owned()
		argv = ['printf'.to_owned(), 'a b'.to_owned(), "don't".to_owned(), '$HOME'.to_owned()]
	}
	command := approvals.GuardianAssessmentAction(approvals.GuardianCommandAction{
		command: text
		cwd:     codex_utils_path_uri.LegacyAppPathString.from_string('/tmp')
	})
	assert action_summary(&command) == 'printf "literal"'
	assert action_summary(&command) == 'printf "literal"'
	execve := approvals.GuardianAssessmentAction(approvals.GuardianExecveAction{
		source:  .unified_exec
		program: program
		argv:    argv
		cwd:     codex_utils_absolute_path.AbsolutePathBuf{ path: '/tmp' }
	})
	assert action_summary(&execve) == 'printf \'a b\' "don\'t" \'$HOME\''
	assert action_summary(&execve) == 'printf \'a b\' "don\'t" \'$HOME\''
	match execve {
		approvals.GuardianExecveAction {
			assert execve.argv == ['printf', 'a b', "don't", '$HOME']
			assert execve.program == 'fallback executable'
		}
		else {
			assert false
		}
	}
	fallback_program := approvals.GuardianAssessmentAction(approvals.GuardianExecveAction{
		program: 'fallback executable'
	})
	assert action_summary(&fallback_program) == "'fallback executable'"
	contains_nul := approvals.GuardianAssessmentAction(approvals.GuardianExecveAction{
		program: 'unused'
		argv:    ['echo', 'a\x00b', 'two words']
	})
	assert action_summary(&contains_nul) == 'echo a\x00b two words'
}

fn test_stdin_summary_uses_rust_debug_then_grapheme_truncation() {
	mut input := '"quoted"\\\n\r\t\x00\x01 é 👩‍💻'
	mut process_id := 'process-9'
	$if ownership ? {
		input = input.to_owned()
		process_id = process_id.to_owned()
	}
	stdin := approvals.GuardianAssessmentAction(approvals.GuardianWriteStdinAction{
		approval_id: 'approval-1'
		process_id:  process_id
		stdin:       input
		cwd:         codex_utils_path_uri.PathUri{ path: 'file:///launch-directory' }
	})
	expected := 'send input to terminal process-9: "\\"quoted\\"\\\\\\n\\r\\t\\0\\u{1} e\\u{301} 👩\\u{200d}💻"'
	assert action_summary(&stdin) == expected
	assert action_summary(&stdin) == expected
	long_input := '界'.repeat(100)
	long_stdin := approvals.GuardianAssessmentAction(approvals.GuardianWriteStdinAction{
		process_id: 'p'
		stdin:      long_input
	})
	result := action_summary(&long_stdin)
	assert result == 'send input to terminal p: "${'界'.repeat(76)}...'
	quoted_result := result.all_after(': ')
	assert unicode_segmentation.grapheme_indices(&quoted_result, true).len == 80
}

fn test_patch_and_network_summaries_preserve_single_path_and_file_counts() {
	mut file := '/tmp/dir/../name with spaces/'
	$if ownership ? {
		file = file.to_owned()
	}
	single := approvals.GuardianAssessmentAction(approvals.GuardianApplyPatchAction{
		files: [codex_utils_path_uri.LegacyAppPathString.from_string(file)]
	})
	assert action_summary(&single) == 'apply_patch touching /tmp/name with spaces/'
	assert action_summary(&single) == 'apply_patch touching /tmp/name with spaces/'
	empty := approvals.GuardianAssessmentAction(approvals.GuardianApplyPatchAction{})
	assert action_summary(&empty) == 'apply_patch touching 0 files'
	multiple := approvals.GuardianAssessmentAction(approvals.GuardianApplyPatchAction{
		files: [codex_utils_path_uri.LegacyAppPathString.from_string('relative-a'),
			codex_utils_path_uri.LegacyAppPathString.from_string('relative-b')]
	})
	assert action_summary(&multiple) == 'apply_patch touching 2 files'
	network := approvals.GuardianAssessmentAction(approvals.GuardianNetworkAccessAction{
		target:   'https://example.com:8443'
		host:     'example.com'
		protocol: .https
		port:     8443
	})
	assert action_summary(&network) == 'network access to https://example.com:8443'
	assert action_summary(&network) == 'network access to https://example.com:8443'
}

fn test_mcp_and_permission_optional_text_distinguish_absent_and_empty() {
	mut server := 'server-1'
	mut connector := 'connector name'
	mut tool := 'tool-name'
	mut reason := 'write generated files'
	$if ownership ? {
		server = server.to_owned()
		connector = connector.to_owned()
		tool = tool.to_owned()
		reason = reason.to_owned()
	}
	mcp := approvals.GuardianAssessmentAction(approvals.GuardianMcpToolCallAction{
		server:         server
		tool_name:      tool
		connector_id:   'connector-id'
		connector_name: connector
		tool_title:     'Tool title'
	})
	assert action_summary(&mcp) == 'MCP tool-name on connector name'
	assert action_summary(&mcp) == 'MCP tool-name on connector name'
	no_connector := approvals.GuardianAssessmentAction(approvals.GuardianMcpToolCallAction{
		server:    'server-1'
		tool_name: 'tool-name'
	})
	assert action_summary(&no_connector) == 'MCP tool-name on server-1'
	empty_connector := approvals.GuardianAssessmentAction(approvals.GuardianMcpToolCallAction{
		server:         'server-1'
		tool_name:      'tool-name'
		connector_name: ''
	})
	assert action_summary(&empty_connector) == 'MCP tool-name on '
	permissions := approvals.GuardianAssessmentAction(approvals.GuardianRequestPermissionsAction{
		reason:      reason
		permissions: request_permissions.RequestPermissionProfile{
			network: models.NetworkPermissions{ enabled: true }
		}
	})
	assert action_summary(&permissions) == 'permission request: write generated files'
	assert action_summary(&permissions) == 'permission request: write generated files'
	no_reason := approvals.GuardianAssessmentAction(approvals.GuardianRequestPermissionsAction{})
	assert action_summary(&no_reason) == 'permission request'
	empty_reason := approvals.GuardianAssessmentAction(approvals.GuardianRequestPermissionsAction{
		reason: ''
	})
	assert action_summary(&empty_reason) == 'permission request: '
}

fn test_standard_debug_escape_oracle_handles_controls_extensions_and_nonprintable_scalars() {
	mut input := "a\x08\x7f\u00a0\u200b\u2028\ue000\u0301\uFE0F\U0001f600'"
	$if ownership ? {
		input = input.to_owned()
	}
	expected := '"a\\u{8}\\u{7f}\\u{a0}\\u{200b}\\u{2028}\\u{e000}\\u{301}\\u{fe0f}😀\'"'
	assert std_fmt.debug_string(&input) == expected
	assert std_fmt.debug_string(&input) == expected
	assert input.ends_with("😀'")
}
