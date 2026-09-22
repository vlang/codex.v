module codex_protocol

// STUB: SanitizedGitUrl.try_from is owned by protocol/src/sanitized_git_url.rs. This preserves
// validation and removes URL-authority credentials for the state row hydration boundary.
pub fn SanitizedGitUrl.try_from(value string) !SanitizedGitUrl {
	if value.len == 0 || value.contains(' ') || value.contains('\t') || value.contains('\r')
		|| value.contains('\n') {
		return error('invalid git remote URL')
	}
	if scheme_index := value.index('://') {
		authority_start := scheme_index + 3
		remaining := value[authority_start..]
		authority_len := if slash := remaining.index('/') { slash } else { remaining.len }
		authority := remaining[..authority_len]
		if authority.len == 0 {
			return error('invalid git remote URL')
		}
		if at := authority.last_index('@') {
			host := authority[at + 1..]
			if host.len == 0 {
				return error('invalid git remote URL')
			}
			scheme := value[..scheme_index]
			preserved_user := if scheme == 'ssh' && authority[..at] == 'git' {
				'git@'
			} else {
				''
			}
			return SanitizedGitUrl{
				value: '${scheme}://${preserved_user}${host}${remaining[authority_len..]}'
			}
		}
		return SanitizedGitUrl{ value: value }
	}
	colon := value.index(':') or { return error('invalid git remote URL') }
	authority := value[..colon]
	if authority.len == 0 || colon + 1 >= value.len {
		return error('invalid git remote URL')
	}
	if at := authority.last_index('@') {
		if at + 1 >= authority.len {
			return error('invalid git remote URL')
		}
		if authority[..at] == 'git' {
			return SanitizedGitUrl{ value: value }
		}
		return SanitizedGitUrl{ value: value[at + 1..] }
	}
	return SanitizedGitUrl{ value: value }
}
