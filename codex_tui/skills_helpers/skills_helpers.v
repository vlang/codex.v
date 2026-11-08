module skills_helpers

import codex_app_server_protocol.skill_metadata
import codex_utils_fuzzy_match

pub fn skill_display_name(skill &skill_metadata.SkillMetadata) string {
	if skill_interface := skill.interface {
		if display_name := skill_interface.display_name {
			return display_name.clone()
		}
	}

	if colon := skill.name.index(':') {
		if colon > 0 && colon + 1 < skill.name.len {
			return '${skill.name[colon + 1..]} (${skill.name[..colon]})'
		}
	}

	return skill.name.clone()
}

pub fn skill_description(skill &skill_metadata.SkillMetadata) string {
	if skill_interface := skill.interface {
		if description := skill_interface.short_description {
			// V cannot return Rust's borrowed &str. Allocate only the selected description.
			return description.clone()
		}
	}
	if description := skill.short_description {
		// This selected branch has the same unavoidable borrowed-return allocation.
		return description.clone()
	}
	return skill.description.clone()
}

// V adaptation: a typed result represents Rust's (Option<Vec<usize>>, i32) tuple.
// Indices use int, matching the existing fuzzy matcher and V rune-array positions.
pub struct SkillMatch {
pub:
	indices ?[]int
	score   int
}

pub fn match_skill(filter &string, display_name &string, skill_name &string) ?SkillMatch {
	if matched := codex_utils_fuzzy_match.fuzzy_match(display_name, filter) {
		return SkillMatch{
			indices: matched.indices
			score:   matched.score
		}
	}
	if *display_name != *skill_name {
		if matched := codex_utils_fuzzy_match.fuzzy_match(skill_name, filter) {
			return SkillMatch{
				indices: none
				score:   matched.score
			}
		}
	}
	return none
}
