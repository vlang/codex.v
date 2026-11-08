module workspace_messages

import codex_app_server_protocol
import std_time

// V has no pub(crate) visibility; these cross-module declarations are public.
pub const workspace_headline_refresh_interval = std_time.Duration.from_secs(5 * 60)

// The tag preserves Available(None) separately from FeatureDisabled. V's
// generated debug representation supplies Rust's derived Debug equivalent.
pub enum WorkspaceHeadlineFetchResultKind {
	available
	feature_disabled
}

pub struct WorkspaceHeadlineFetchResult {
pub:
	kind     WorkspaceHeadlineFetchResultKind
	headline ?string
}

// Rust's derived Clone copies the optional owned headline only for Available.
pub fn (result &WorkspaceHeadlineFetchResult) clone() WorkspaceHeadlineFetchResult {
	return match result.kind {
		.available {
			WorkspaceHeadlineFetchResult{
				kind:     .available
				headline: if headline := result.headline { headline.clone() } else { none }
			}
		}
		.feature_disabled { WorkspaceHeadlineFetchResult{ kind: .feature_disabled } }
	}
}

pub fn (left &WorkspaceHeadlineFetchResult) == (right &WorkspaceHeadlineFetchResult) bool {
	if left.kind != right.kind {
		return false
	}
	return match left.kind {
		.available { left.headline == right.headline }
		.feature_disabled { true }
	}
}

// Rust str::trim uses Unicode White_Space; V trim_space covers only ASCII.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

pub fn workspace_headline_from_response(response codex_app_server_protocol.GetWorkspaceMessagesResponse) WorkspaceHeadlineFetchResult {
	if !response.feature_enabled {
		return WorkspaceHeadlineFetchResult{ kind: .feature_disabled }
	}

	for index in 0 .. response.messages.len {
		message := &response.messages[index]
		if message.message_type == .headline {
			// V trim returns an owned string, matching trim().to_string() in Rust.
			headline := message.message_body.trim(unicode_whitespace)
			if headline.len > 0 {
				return WorkspaceHeadlineFetchResult{ kind: .available, headline: headline }
			}
		}
	}
	return WorkspaceHeadlineFetchResult{ kind: .available }
}
