module status

// STUB: tui/src/status/account.rs::StatusAccountDisplay discriminants.
pub enum StatusAccountDisplayKind {
	chat_gpt
	api_key
}

// STUB: tui/src/status/account.rs::StatusAccountDisplay's tagged payload.
// The account module, rather than status/helpers.rs, owns this declaration.
pub struct StatusAccountDisplay {
pub mut:
	kind  StatusAccountDisplayKind
	email ?string
	plan  ?string
}

// STUB: Rust's derived Clone copies only the active StatusAccountDisplay payload.
pub fn (display &StatusAccountDisplay) clone() StatusAccountDisplay {
	return match display.kind {
		.chat_gpt {
			StatusAccountDisplay{
				kind:  .chat_gpt
				email: if email := display.email { email.clone() } else { none }
				plan:  if plan := display.plan { plan.clone() } else { none }
			}
		}
		.api_key { StatusAccountDisplay{ kind: .api_key } }
	}
}
