module status

import chrono
import codex_core
import codex_protocol.account
import codex_tui.exec_command
import codex_tui.text_formatting
import codex_tui.width
import codex_utils_path_uri
import dunce
import math
import os
import std_path
import unicode_segmentation

// Rust's (&str, String) entries retain their borrowed key and owned value.
pub struct ModelDisplayEntry {
pub:
	key   &string
	value string
}

fn normalize_agents_display_path(path &std_path.Path) string {
	simplified := dunce.simplified(path)
	return format_directory_display(&simplified, /* max_width */
		none)
}

pub fn compose_model_display(model_name &string, entries &[]ModelDisplayEntry) (string, []string) {
	mut details := []string{}
	for entry in *entries {
		if *entry.key == 'reasoning effort' {
			details << 'reasoning ${entry.value.to_lower_ascii()}'
			break
		}
	}
	for entry in *entries {
		if *entry.key == 'reasoning summaries' {
			summary := entry.value.trim(' \t\n\r\v\f\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
			if summary.to_lower_ascii() == 'none' || summary.to_lower_ascii() == 'off' {
				details << 'summaries off'
			} else if summary.len > 0 {
				details << 'summaries ${summary.to_lower_ascii()}'
			}
			break
		}
	}
	return (*model_name).clone(), details
}

pub fn compose_agents_summary(config &codex_core.Config, paths &[]codex_utils_path_uri.PathUri) string {
	mut rels := []string{}
	cwd := std_path.Path.new(&config.cwd)
	for path in *paths {
		// TODO(anp): Rationalize instruction-source summaries with the TUI's broader foreign-path
		// display strategy once other status surfaces can retain environment-native paths.
		convention := path.infer_path_convention() or {
			rels << path.inferred_native_path_string()
			continue
		}
		if convention != codex_utils_path_uri.PathConvention.native() {
			rels << path.inferred_native_path_string()
			continue
		}
		absolute := path.to_abs_path() or {
			rels << path.inferred_native_path_string()
			continue
		}
		p := absolute.as_path()
		file_name := p.file_name() or { '<unknown>'.clone() }
		mut display := ''
		if parent := p.parent() {
			if parent.equals(&cwd) {
				display = file_name.clone()
			} else {
				mut cur := cwd
				mut ups := usize(0)
				mut reached := false
				for {
					c := cur.parent() or { break }
					if cur.equals(&parent) {
						reached = true
						break
					}
					cur = c
					ups++
				}
				if reached {
					up := '..${os.path_separator}'
					display = '${up.repeat(int(ups))}${file_name}'
				} else if stripped := p.strip_prefix(&cwd) {
					display = normalize_agents_display_path(&stripped)
				} else {
					display = normalize_agents_display_path(&p)
				}
			}
		} else {
			display = normalize_agents_display_path(&p)
		}
		rels << display
	}
	if rels.len == 0 {
		return '<none>'.clone()
	}
	return rels.join(', ')
}

// V cannot reliably compile ?&T or &?T with owned payloads. This Copy-equivalent
// wrapper models Option<&StatusAccountDisplay> without copying the account owner.
pub struct BorrowedStatusAccountDisplay {
pub:
	has_value bool
	value     &StatusAccountDisplay = unsafe { nil }
}

pub fn compose_account_display(account_display BorrowedStatusAccountDisplay) ?StatusAccountDisplay {
	if !account_display.has_value {
		return none
	}
	return account_display.value.clone()
}

pub fn plan_type_display_name(plan_type account.PlanType) string {
	if plan_type == .enterprise_cbp_automation {
		return 'Enterprise (Automation)'.clone()
	} else if plan_type == .self_serve_business_pro_lite {
		return 'Business Premium'.clone()
	} else if plan_type.is_team_like() {
		return 'Business'.clone()
	} else if plan_type.is_business_like() {
		return 'Enterprise'.clone()
	} else if plan_type == .pro_lite {
		return 'Pro Lite'.clone()
	} else if plan_type == .edu_plus {
		return 'Edu Plus'.clone()
	} else if plan_type == .edu_pro {
		return 'Edu Pro'.clone()
	}
	debug_name := plan_type.debug_name()
	return title_case(&debug_name)
}

pub fn format_tokens_compact(value i64) string {
	clamped_value := if value < 0 { i64(0) } else { value }
	if clamped_value == 0 {
		return '0'.clone()
	}
	if clamped_value < 1_000 {
		return clamped_value.str()
	}

	value_f64 := f64(clamped_value)
	scaled, suffix := if clamped_value >= 1_000_000_000_000 {
		value_f64 / 1_000_000_000_000.0, 'T'
	} else if clamped_value >= 1_000_000_000 {
		value_f64 / 1_000_000_000.0, 'B'
	} else if clamped_value >= 1_000_000 {
		value_f64 / 1_000_000.0, 'M'
	} else {
		value_f64 / 1_000.0, 'K'
	}

	decimals := if scaled < 10.0 {
		2
	} else if scaled < 100.0 {
		1
	} else {
		0
	}
	// Rust's fixed decimal formatting rounds the exact binary float to nearest,
	// with ties to even. V's float interpolation instead adds a rounding offset;
	// round the binary significand explicitly to preserve the source at ties and
	// adjacent values. Here scaled is always in [1, 9_223_373), so the product
	// fits u64 and the denominator is a power of two with a positive exponent.
	scale := if decimals == 2 {
		u64(100)
	} else if decimals == 1 {
		u64(10)
	} else {
		u64(1)
	}
	bits := math.f64_bits(scaled)
	significand := (bits & ((u64(1) << 52) - 1)) | (u64(1) << 52)
	shift := 1075 - int((bits >> 52) & 0x7ff)
	product := significand * scale
	mut rounded := product >> shift
	remainder := product & ((u64(1) << shift) - 1)
	half := u64(1) << (shift - 1)
	if remainder > half || (remainder == half && rounded % 2 == 1) {
		rounded++
	}
	formatted := if decimals == 2 {
		'${rounded / scale}.${rounded % scale:02}'
	} else if decimals == 1 {
		'${rounded / scale}.${rounded % scale}'
	} else {
		rounded.str()
	}
	mut end := formatted.len
	if decimals > 0 {
		for end > 0 && formatted[end - 1] == `0` {
			end--
		}
		if end > 0 && formatted[end - 1] == `.` {
			end--
		}
	}
	return '${formatted[..end]}${suffix}'
}

pub fn format_directory_display(directory &std_path.Path, max_width ?usize) string {
	formatted := if rel := exec_command.relativize_to_home(directory) {
		if rel.len == 0 {
			'~'.clone()
		} else {
			relative := std_path.Path.new(&rel)
			'~${os.path_separator}${relative.to_string_lossy()}'
		}
	} else {
		directory.to_string_lossy()
	}
	if limit := max_width {
		if limit == 0 {
			return ''.clone()
		}
		if width.display_width(&formatted) > limit {
			return text_formatting.center_truncate_path(&formatted, limit)
		}
	}
	return formatted
}

pub fn format_reset_timestamp(dt chrono.DateTimeLocal, captured_at chrono.DateTimeLocal) string {
	time_format := '%H:%M'
	time := dt.format(&time_format)
	if dt.date_naive() == captured_at.date_naive() {
		return time
	}
	date_format := '%-d %b'
	return '${time} on ${dt.format(&date_format)}'
}

fn title_case(s &string) string {
	if s.len == 0 {
		return ''.clone()
	}
	mut chars := s.runes_iterator()
	first := chars.next() or { return ''.clone() }
	rest := (*s)[first.str().len..].to_lower_ascii()
	return unicode_segmentation.uppercase(first) + rest
}
