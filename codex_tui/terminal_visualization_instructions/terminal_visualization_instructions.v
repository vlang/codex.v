module terminal_visualization_instructions

import codex_core
import codex_features

pub const visualization_instructions = '- This surface is a terminal. When the formatting rules require a visual, include one in the final answer using compact ASCII diagrams, trees, timelines, or tables.
- Use tables for exact mappings or comparisons rather than collapsing known mappings into prose.
- Use trees for hierarchy or one-to-many relationships, and diagrams or timelines for sequence, change, or state transferred between records across event order.
- Use only ASCII characters in visuals.'

// Rust str::trim uses Unicode White_Space; V trim_space only recognizes ASCII.
const unicode_whitespace = '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000'

pub fn with_terminal_visualization_instructions(config &codex_core.Config, control_instructions ?string) ?string {
	if !config.features.enabled(codex_features.Feature.terminal_visualization_instructions) {
		return control_instructions
	}

	mut existing_instructions := control_instructions
	if existing_instructions == none {
		existing_instructions = if developer := config.developer_instructions {
			developer.clone()
		} else {
			none
		}
	}
	if existing := existing_instructions {
		if existing.trim(unicode_whitespace).len > 0 {
			return '${existing}\n\n${visualization_instructions}'
		}
	}
	return visualization_instructions.clone()
}
