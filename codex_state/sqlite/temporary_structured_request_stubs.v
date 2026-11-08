module sqlite

// STUB: state/src/sqlite.rs::SqliteConfig's derived Clone owns its home path.
pub fn (config &SqliteConfig) clone() SqliteConfig {
	return SqliteConfig{ sqlite_home: config.sqlite_home.clone() }
}
