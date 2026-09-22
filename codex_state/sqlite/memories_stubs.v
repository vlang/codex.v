module sqlite

// STUB: SqliteConfig is owned by state/src/sqlite.rs; this target-specific declaration retains
// the configured SQLite home used by the in-memory memories backend.
pub struct SqliteConfig {
pub:
	sqlite_home string
}

// STUB: new_for_testing mirrors SqliteConfig::new_for_testing.
pub fn SqliteConfig.new_for_testing(sqlite_home string) SqliteConfig {
	return SqliteConfig{
		sqlite_home: sqlite_home
	}
}

// STUB: home mirrors SqliteConfig::home.
pub fn (config &SqliteConfig) home() string {
	return config.sqlite_home
}
