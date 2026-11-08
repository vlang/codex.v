module chrono

// STUB: chrono::DateTime<Utc> storage used by protocol/src/openai_models.rs::ModelUpgrade.
// A typed UTC timestamp preserves seconds and nanoseconds (including chrono leap-second
// nanoseconds); parsing, formatting, and chrono's calendar operations are untranslated.
pub struct DateTimeUtc {
pub mut:
	seconds     i64
	nanoseconds u32
}
