// Local file-link parsing, label comparison, and display for Markdown transcripts.
//
// Markdown rendering intentionally treats local file links differently from normal web links. For
// local paths, transcripts always show the real file target (including normalized location
// suffixes) and can shorten absolute paths relative to a known working directory. Descriptive
// Markdown labels remain visible alongside that target, while path-like labels collapse to the
// canonical target to avoid duplicate file references.
//
module local_links

import codex_utils_fuzzy_match
import codex_utils_path_uri
import codex_utils_string
import regex_lite
import std_path
import sync
import url
import urlencoding

// Rust's LazyLock publishes one compiled regex at first use. V keeps the same
// lazy initialization in a mutex-protected heap cell; Regex is Copy-equivalent.
@[heap]
struct LazyLocationRegex {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	initialized bool
	regex       regex_lite.Regex
}

const colon_location_suffix_re = &LazyLocationRegex{}

fn load_colon_location_suffix_regex() regex_lite.Regex {
	mut cache := unsafe { colon_location_suffix_re }
	cache.mutex.lock()
	defer { cache.mutex.unlock() }
	if !cache.initialized {
		pattern := r':\d+(?::\d+)?(?:[-–]\d+(?::\d+)?)?$'
		cache.regex = regex_lite.Regex.new(&pattern) or {
			panic('invalid location suffix regex: ${err}')
		}
		cache.initialized = true
	}
	return cache.regex
}

// Covered by load_location_suffix_regexes.
const hash_location_suffix_re = &LazyLocationRegex{}

fn load_hash_location_suffix_regex() regex_lite.Regex {
	mut cache := unsafe { hash_location_suffix_re }
	cache.mutex.lock()
	defer { cache.mutex.unlock() }
	if !cache.initialized {
		pattern := r'^L\d+(?:C\d+)?(?:-L\d+(?:C\d+)?)?$'
		cache.regex = regex_lite.Regex.new(&pattern) or {
			panic('invalid hash location regex: ${err}')
		}
		cache.initialized = true
	}
	return cache.regex
}

// Rust pub(super) becomes public for V's separate child module.
pub fn is_local_path_like_link(dest_url &string) bool {
	return dest_url.starts_with('file://') || dest_url.starts_with('/')
		|| dest_url.starts_with('~/') || dest_url.starts_with('./')
		|| dest_url.starts_with('../') || dest_url.starts_with('\\\\')
		|| (dest_url.len >= 3 && (*dest_url)[0].is_letter() && (*dest_url)[1] == `:`
			&& (*dest_url)[2] in [`/`, `\\`])
}

// Decide whether a local-file link label adds meaning beyond its canonical target.
//
// Matching path-like labels collapse to the target; prose labels remain visible.
pub fn should_render_local_link_label(label &string, destination &string) bool {
	trimmed := trim_local_label_whitespace(label)
	if trimmed.len == 0 {
		return false
	}
	parsed_label := comparable_local_link_path(&trimmed) or { return true }
	target := comparable_local_link_path(destination) or { return true }
	without_dot := trim_leading_dot_slash(&target)
	target_path := trim_trailing_local_path_separator(&without_dot)
	// Labels can spell a filename literally or URL-encode it. Compare both without decoding
	// the destination twice (for example, percent%2520.rs denotes percent%20.rs).
	literal_normalized := normalize_local_link_path_text(&trimmed)
	literal_label := codex_utils_fuzzy_match.lowercase_string(&literal_normalized).string()
	labels := [literal_label, parsed_label]
	for index in 0 .. labels.len {
		label_without_dot := trim_leading_dot_slash(&labels[index])
		label_path := trim_trailing_local_path_separator(&label_without_dot)
		if has_boundary_suffix(&target_path, &label_path)
			|| (is_absolute_local_link_path(&label_path) && has_boundary_suffix(&label_path, &target_path)) {
			return false
		}
	}
	return true
}

// The source's has_boundary_suffix closure, retaining nonempty slash-boundary checks.
fn has_boundary_suffix(path &string, suffix &string) bool {
	if suffix.len == 0 || !path.ends_with(*suffix) {
		return false
	}
	prefix_length := path.len - suffix.len
	return prefix_length == 0 || (*path)[prefix_length - 1] == `/`
}

// Normalize original Markdown strings for comparison only, never already-rendered path text.
// Case and URL spelling are intentionally forgiving; the visible target retains its spelling.
fn comparable_local_link_path(text &string) ?string {
	canonical_text := if text.len >= 7 && (*text)[..7].to_lower_ascii() == 'file://' {
		'file://${(*text)[7..]}'
	} else {
		text.clone()
	}
	parsed := parse_local_link_target(&canonical_text) or { return none }
	normalized := normalize_local_link_path_text(&parsed.path)
	// Reuse the translated Rust Unicode mapping, including expansions and Final_Sigma.
	return codex_utils_fuzzy_match.lowercase_string(&normalized).string()
}

// Parse a local link target into normalized path text plus an optional location suffix.
//
// This accepts the path shapes Codex emits today: `file://` URLs, absolute and relative paths,
// `~/...`, Windows paths, and `#L..C..` or `:line:col` suffixes.
// Option<&Path> is an optional Copy-equivalent borrowed Path view; no owner moves.
pub fn render_local_link_target(dest_url &string, cwd ?std_path.Path) ?string {
	parsed := parse_local_link_target(dest_url) or { return none }
	mut rendered := display_local_link_path(&parsed.path, cwd)
	if location_suffix := parsed.location_suffix {
		rendered += location_suffix
	}
	return rendered
}

// V represents Rust's Option<(String, Option<String>)> with an owned tuple struct.
struct LocalLinkTarget {
	path            string
	location_suffix ?string
}

// Split a local-link destination into (normalized_path_text, location_suffix).
//
// The returned path text never includes a trailing #L.. or :line[:col] suffix. Path
// normalization preserves ~/... and rewrites path separators into display-stable forward
// slashes. The suffix, when present, is returned separately in normalized markdown form.
//
// Returns None only when the destination looks like a file:// URL but cannot be parsed into a
// local path. Plain path-like inputs always return Some(...) even if they are relative.
fn parse_local_link_target(dest_url &string) ?LocalLinkTarget {
	if dest_url.starts_with('file://') {
		parsed_url := url.Url.parse(dest_url) or { return none }
		// Infer the path's OS from the URI, not the host running the TUI.
		uri_prefix := parsed_url.prefix(.after_path)
		path := codex_utils_path_uri.PathUri.parse(&uri_prefix) or { return none }
		native := path.inferred_native_path_string()
		path_text := normalize_local_link_path_text(&native)
		fragment := parsed_url.fragment()
		location_suffix := if fragment.has_value {
			normalize_hash_location_suffix_fragment(fragment.value)
		} else {
			?string(none)
		}
		return LocalLinkTarget{ path: path_text, location_suffix: location_suffix }
	}

	mut path_end := dest_url.len
	mut location_suffix := ?string(none)
	// Prefer #L.. style fragments when both forms are present so URLs like path#L10 do not
	// get misparsed as a plain path ending in :10.
	hash_index := dest_url.last_index_u8(`#`)
	if hash_index >= 0 {
		fragment := (*dest_url)[hash_index + 1..]
		if normalized := normalize_hash_location_suffix_fragment(&fragment) {
			path_end = hash_index
			location_suffix = normalized
		}
	}
	if location_suffix == none {
		path_text := (*dest_url)[..path_end]
		if suffix := extract_colon_location_suffix(&path_text) {
			path_end -= suffix.len
			location_suffix = suffix
		}
	}
	path_text := (*dest_url)[..path_end]
	decoded_path_text := urlencoding.decode(&path_text) or { path_text.clone() }
	return LocalLinkTarget{
		path:            normalize_local_link_path_text(&decoded_path_text)
		location_suffix: location_suffix
	}
}

// Normalize a hash fragment like L12 or L12C3-L14C9 into the display suffix we render.
//
// Returns None for fragments that are not location references. This deliberately ignores other
// #... fragments so non-location hashes stay part of the path text.
fn normalize_hash_location_suffix_fragment(fragment &string) ?string {
	regex := load_hash_location_suffix_regex()
	if !regex.is_match(fragment) {
		return none
	}
	suffix := '#${*fragment}'
	return codex_utils_string.normalize_markdown_hash_location_suffix(&suffix)
}

// Extract a trailing :line, :line:col, or range suffix from a plain path-like string.
//
// The suffix must occur at the end of the input; embedded colons elsewhere in the path are left
// alone. This is what keeps Windows drive letters like C:/... from being misread as locations.
pub fn extract_colon_location_suffix(path_text &string) ?string {
	regex := load_colon_location_suffix_regex()
	matched := regex.find(path_text) or { return none }
	if matched.end() != path_text.len {
		return none
	}
	return matched.as_str()
}

// Normalize local-path text into the transcript display form.
//
// Display normalization is intentionally lexical: it does not touch the filesystem, resolve
// symlinks, or collapse `.` / `..` It only converts separators to forward slashes and rewrites
// UNC-style \\\\server\\share inputs into //server/share so later prefix checks operate on a
// stable representation.
fn normalize_local_link_path_text(path_text &string) string {
	// Render all local link paths with forward slashes so display and prefix stripping are stable
	// across mixed Windows and Unix-style inputs.
	if path_text.starts_with('\\\\') {
		rest := (*path_text)[2..].replace('\\', '/')
		return '//${rest.trim_left('/')}'
	}
	return path_text.replace('\\', '/')
}

fn is_absolute_local_link_path(path_text &string) bool {
	return path_text.starts_with('/') || path_text.starts_with('//')
		|| (path_text.len >= 3 && (*path_text)[0].is_letter() && (*path_text)[1] == `:`
			&& (*path_text)[2] == `/`)
}

// Remove trailing separators from a local path without destroying root semantics.
//
// Roots like /, //, and C:/ stay intact so callers can still distinguish "the root itself"
// from "a path under the root".
// V cannot return a Rust borrowed string slice; the borrowed input produces an owned copy.
fn trim_trailing_local_path_separator(path_text &string) string {
	if *path_text in ['/', '//'] {
		return path_text.clone()
	}
	if path_text.len == 3 && (*path_text)[0].is_letter() && (*path_text)[1] == `:`
		&& (*path_text)[2] == `/` {
		return path_text.clone()
	}
	return path_text.trim_right('/')
}

// Strip cwd_text from the start of path_text when path_text is strictly underneath it.
//
// Returns the relative remainder without a leading slash. If the path equals the cwd exactly, this
// returns None so callers can keep rendering the full path instead of collapsing it to an empty
// string.
// V cannot return a borrowed substring, so Some owns a copy of the borrowed path's remainder.
fn strip_local_path_prefix(path_text &string, cwd_text &string) ?string {
	path := trim_trailing_local_path_separator(path_text)
	cwd := trim_trailing_local_path_separator(cwd_text)
	if path == cwd {
		return none
	}

	// Treat filesystem roots specially so /tmp/x under / becomes tmp/x instead of being
	// left unchanged by the generic prefix-stripping branch.
	if cwd in ['/', '//'] {
		return if path.starts_with('/') { path[1..].clone() } else { none }
	}
	if !path.starts_with(cwd) {
		return none
	}
	rest := path[cwd.len..]
	return if rest.starts_with('/') { rest[1..].clone() } else { none }
}

// Choose the visible path text for a local link after normalization.
//
// Relative paths (including ~/...) stay relative. Absolute paths prefer cwd-relative display
// and otherwise stay absolute: the frontend home may differ from the execution host's home.
// This is display logic only, not filesystem canonicalization.
fn display_local_link_path(path_text &string, cwd ?std_path.Path) string {
	path := normalize_local_link_path_text(path_text)
	if !is_absolute_local_link_path(&path) {
		return path
	}
	if working_directory := cwd {
		// Only the session cwd is known to refer to the execution host.
		cwd_lossy := working_directory.to_string_lossy()
		cwd_normalized := normalize_local_link_path_text(&cwd_lossy)
		if stripped := strip_local_path_prefix(&path, &cwd_normalized) {
			return stripped
		}
	}
	return path
}

// Rust trim_start_matches("./") repeatedly removes the complete two-byte pattern,
// not every individual dot or slash. V lacks that borrowed slicing operation.
fn trim_leading_dot_slash(text &string) string {
	mut start := 0
	for start + 2 <= text.len && (*text)[start..start + 2] == './' {
		start += 2
	}
	return (*text)[start..].clone()
}

// Rust str::trim uses Unicode White_Space; V trim_space is ASCII-only. Use the
// equivalent scalar set and retain an owned copy because V cannot return &str.
fn trim_local_label_whitespace(text &string) string {
	return text.trim('\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
}
