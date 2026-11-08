module startup_error

import std_path

// PathBuf uses the existing std_path owned-string representation. The fields
// remain private; V's generated struct formatting supplies Rust's derived Debug.
pub struct LocalStateDbStartupError {
	database_path string
	detail        string
}

pub fn LocalStateDbStartupError.new(database_path string, detail string) LocalStateDbStartupError {
	return LocalStateDbStartupError{
		database_path: database_path
		detail:        detail
	}
}

// Rust returns &Path. The Copy-equivalent V Path view borrows the error's owned
// path bytes; the error must outlive this view, as enforced by Rust's lifetime.
pub fn (failure &LocalStateDbStartupError) database_path() std_path.Path {
	return std_path.Path.new(&failure.database_path)
}

pub fn (failure &LocalStateDbStartupError) state_db_path() std_path.Path {
	return failure.database_path()
}

// V has no borrowed &str return. Allocate an owned result from the borrowed
// field so callers can reuse the error and keep the detail after it is dropped.
pub fn (failure &LocalStateDbStartupError) detail() string {
	return failure.detail.clone()
}

// V's error-message accessor implements thiserror's exact Display text. Path
// display is lossy UTF-8; constructing the message leaves the native path intact.
pub fn (failure &LocalStateDbStartupError) msg() string {
	path := failure.database_path()
	return 'failed to initialize sqlite local db at ${path.to_string_lossy()}: ${failure.detail}'
}

// IError requires a numeric code; this Rust error has no native error code.
pub fn (failure &LocalStateDbStartupError) code() int {
	return 0
}
