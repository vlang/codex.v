module dunce

import std_path

// STUB: dunce::simplified borrows its Path. Unix paths and ordinary Windows
// paths are unchanged. The complete safety checks for converting Windows verbatim
// namespace paths are untranslated; retain those prefixes rather than changing
// their meaning until dunce's platform implementation is ported.
pub fn simplified(path &std_path.Path) std_path.Path {
	return *path
}
