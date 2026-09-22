module filters

import codex_app_server_protocol as api
import codex_protocol

// STUB: SourceFilters is the V tuple adaptation returned by app-server/filters.rs.
pub struct SourceFilters {
pub:
	allowed_sources []codex_protocol.SessionSource
	post_filter     ?[]api.ThreadSourceKind
}

// STUB: compute_source_filters is owned by app-server/filters.rs. The filtering policy is kept
// executable because thread_processor pagination depends on its interactive defaults.
pub fn compute_source_filters(source_kinds ?[]api.ThreadSourceKind) SourceFilters {
	kinds := source_kinds or {
		return SourceFilters{
			allowed_sources: [codex_protocol.SessionSource{ source_kind: .cli },
				codex_protocol.SessionSource{ source_kind: .vscode }]
		}
	}
	if kinds.len == 0 {
		return SourceFilters{
			allowed_sources: [codex_protocol.SessionSource{ source_kind: .cli },
				codex_protocol.SessionSource{ source_kind: .vscode }]
		}
	}
	mut requires_post_filter := false
	for kind in kinds {
		if kind in [.exec, .app_server, .sub_agent, .sub_agent_review, .sub_agent_compact,
			.sub_agent_thread_spawn, .sub_agent_other, .unknown] {
			requires_post_filter = true
			break
		}
	}
	mut allowed_sources := []codex_protocol.SessionSource{}
	if !requires_post_filter {
		for kind in kinds {
			match kind {
				.cli { allowed_sources << codex_protocol.SessionSource{ source_kind: .cli } }
				.vscode { allowed_sources << codex_protocol.SessionSource{ source_kind: .vscode } }
				else {}
			}
		}
	}
	return SourceFilters{
		allowed_sources: allowed_sources
		post_filter:     kinds.clone()
	}
}

// STUB: source_kind_matches is owned by app-server/filters.rs.
pub fn source_kind_matches(source &codex_protocol.SessionSource, filter &[]api.ThreadSourceKind) bool {
	for kind in *filter {
		match kind {
			.cli {
				if source.source_kind == .cli {
					return true
				}
			}
			.vscode {
				if source.source_kind == .vscode {
					return true
				}
			}
			.exec {
				if source.source_kind == .exec {
					return true
				}
			}
			.app_server {
				if source.source_kind == .mcp {
					return true
				}
			}
			.sub_agent {
				if source.source_kind == .sub_agent {
					return true
				}
			}
			.sub_agent_review {
				if subagent := source.sub_agent {
					if subagent.source_kind == .review {
						return true
					}
				}
			}
			.sub_agent_compact {
				if subagent := source.sub_agent {
					if subagent.source_kind == .compact {
						return true
					}
				}
			}
			.sub_agent_thread_spawn {
				if subagent := source.sub_agent {
					if subagent.source_kind == .thread_spawn {
						return true
					}
				}
			}
			.sub_agent_other {
				if subagent := source.sub_agent {
					if subagent.source_kind in [.other, .memory_consolidation] {
						return true
					}
				}
			}
			.unknown {
				if source.source_kind == .unknown {
					return true
				}
			}
		}
	}
	return false
}
