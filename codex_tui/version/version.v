module version

// V has no Cargo package environment. Accept the equivalent build-time variable
// and otherwise use the version inherited by codex-tui from the Rust workspace.
const cargo_pkg_version = $env('CARGO_PKG_VERSION')

/// The current Codex CLI version as embedded at compile time.
pub const codex_cli_version = if cargo_pkg_version.len > 0 {
	cargo_pkg_version
} else {
	'0.0.0'
}
