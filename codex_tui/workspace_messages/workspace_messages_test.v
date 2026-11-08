module workspace_messages

import codex_app_server_protocol

fn fixture_owned_string(value string) string {
	$if ownership ? {
		return value.to_owned()
	} $else {
		return value.clone()
	}
}

fn test_workspace_headline_from_response_uses_first_non_empty_headline() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: true
		messages:        [
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('announcement-id')
				message_type: .announcement
				message_body: fixture_owned_string('Announcement body')
				created_at:   none
				archived_at:  none
			},
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('empty-headline-id')
				message_type: .headline
				message_body: fixture_owned_string('   ')
				created_at:   none
				archived_at:  none
			},
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('headline-id')
				message_type: .headline
				message_body: fixture_owned_string(' Workspace headline ')
				created_at:   none
				archived_at:  none
			},
		]
	}

	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{
		kind:     .available
		headline: fixture_owned_string('Workspace headline')
	}
}

fn test_workspace_headline_from_response_reports_feature_disabled() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: false
		messages:        []codex_app_server_protocol.WorkspaceMessage{}
	}

	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{
		kind: .feature_disabled
	}
}

fn test_enabled_empty_response_is_available_without_headline() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: true
		messages:        []codex_app_server_protocol.WorkspaceMessage{}
	}
	result := workspace_headline_from_response(response)
	assert result == WorkspaceHeadlineFetchResult{ kind: .available }
	assert result != WorkspaceHeadlineFetchResult{ kind: .feature_disabled }
}

fn test_only_non_headline_and_empty_headline_messages_produce_available_none() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: true
		messages:        [
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('announcement')
				message_type: .announcement
				message_body: fixture_owned_string('Announcement body')
			},
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('unknown')
				message_type: .unknown
				message_body: fixture_owned_string('Unknown body')
			},
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('empty')
				message_type: .headline
				message_body: fixture_owned_string('\t\r\n ')
			},
		]
	}
	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{ kind: .available }
}

fn test_disabled_feature_ignores_nonempty_headlines() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: false
		messages:        [codex_app_server_protocol.WorkspaceMessage{
			message_id:   fixture_owned_string('headline')
			message_type: .headline
			message_body: fixture_owned_string('Must not be available')
		}]
	}
	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{ kind: .feature_disabled }
}

fn test_first_nonempty_headline_wins_over_later_headlines() {
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: true
		messages:        [
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('first')
				message_type: .headline
				message_body: fixture_owned_string(' First\nheadline ')
				created_at:   i64(1)
				archived_at:  i64(2)
			},
			codex_app_server_protocol.WorkspaceMessage{
				message_id:   fixture_owned_string('second')
				message_type: .headline
				message_body: fixture_owned_string('Second headline')
			},
		]
	}
	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{
		kind:     .available
		headline: fixture_owned_string('First\nheadline')
	}
}

fn test_unicode_whitespace_matches_rust_trim_without_trimming_other_characters() {
	for separator in unicode_whitespace.runes() {
		response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
			feature_enabled: true
			messages:        [
				codex_app_server_protocol.WorkspaceMessage{
					message_id:   fixture_owned_string('empty')
					message_type: .headline
					message_body: '${separator}${separator}'
				},
				codex_app_server_protocol.WorkspaceMessage{
					message_id:   fixture_owned_string('unicode')
					message_type: .headline
					message_body: '${separator}Workspace${separator}headline${separator}'
				},
			]
		}
		assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{
			kind:     .available
			headline: 'Workspace${separator}headline'
		}
	}
	response := codex_app_server_protocol.GetWorkspaceMessagesResponse{
		feature_enabled: true
		messages:        [codex_app_server_protocol.WorkspaceMessage{
			message_id:   fixture_owned_string('non-whitespace')
			message_type: .headline
			message_body: fixture_owned_string(' \u180e\u200bHeadline\u200b\u180e ')
		}]
	}
	assert workspace_headline_from_response(response) == WorkspaceHeadlineFetchResult{
		kind:     .available
		headline: fixture_owned_string('\u180e\u200bHeadline\u200b\u180e')
	}
}

fn test_result_clone_borrows_and_preserves_owned_headline() {
	result := WorkspaceHeadlineFetchResult{
		kind:     .available
		headline: fixture_owned_string('Owned workspace headline')
	}
	first := result.clone()
	second := result.clone()
	assert first == result
	assert second == result
	assert result.headline == ?string('Owned workspace headline')
	assert result.kind == .available
	assert WorkspaceHeadlineFetchResult{ kind: .available }.clone() == WorkspaceHeadlineFetchResult{ kind: .available }
	assert WorkspaceHeadlineFetchResult{ kind: .feature_disabled }.clone() == WorkspaceHeadlineFetchResult{ kind: .feature_disabled }
}
