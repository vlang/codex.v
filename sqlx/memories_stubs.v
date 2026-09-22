module sqlx

// STUB: BindValue is the SQLite bind-value surface used by state/runtime/memories.rs while the
// external sqlx crate is untranslated.
pub type BindValue = Null | i64 | string

// STUB: Null represents a SQL NULL bind.
pub struct Null {}

// STUB: Row is sqlx::sqlite::SqliteRow's typed column projection.
pub struct Row {
pub:
	strings           map[string]string
	integers          map[string]i64
	nullable_strings  map[string]bool
	nullable_integers map[string]bool
}

// STUB: string_get mirrors Row::try_get for a non-null text column.
pub fn (row &Row) string_get(column string) !string {
	if column !in row.strings {
		return error('missing text column `${column}`')
	}
	return row.strings[column].clone()
}

// STUB: i64_get mirrors Row::try_get for a non-null integer column.
pub fn (row &Row) i64_get(column string) !i64 {
	if column !in row.integers {
		return error('missing integer column `${column}`')
	}
	return row.integers[column]
}

// STUB: OptionalString explicitly represents a nullable SQLite text value.
pub struct OptionalString {
pub:
	has_value bool
	value     string
}

// STUB: get returns a present nullable text value.
pub fn (value &OptionalString) get() !string {
	if !value.has_value {
		return error('nullable text is NULL')
	}
	return value.value.clone()
}

// STUB: OptionalI64 explicitly represents a nullable SQLite integer value.
pub struct OptionalI64 {
pub:
	has_value bool
	value     i64
}

// STUB: get returns a present nullable integer value.
pub fn (value OptionalI64) get() !i64 {
	if !value.has_value {
		return error('nullable integer is NULL')
	}
	return value.value
}

// STUB: optional_string_get mirrors Row::try_get for Option<String>.
pub fn (row &Row) optional_string_get(column string) !OptionalString {
	if column in row.nullable_strings && row.nullable_strings[column] {
		return OptionalString{}
	}
	return OptionalString{ has_value: true, value: row.string_get(column)! }
}

// STUB: optional_i64_get mirrors Row::try_get for Option<i64>.
pub fn (row &Row) optional_i64_get(column string) !OptionalI64 {
	if column in row.nullable_integers && row.nullable_integers[column] {
		return OptionalI64{}
	}
	return OptionalI64{ has_value: true, value: row.i64_get(column)! }
}

// STUB: try_get mirrors sqlx::Row::try_get. V's explicit OptionalString/OptionalI64 types retain
// nullable result shape because resource-owning `!?T` is not supported by the current compiler.
pub fn (row &Row) try_get[T](column string) !T {
	$if T is string {
		return row.string_get(column)!
	} $else $if T is i64 {
		return row.i64_get(column)!
	} $else $if T is OptionalString {
		return row.optional_string_get(column)!
	} $else $if T is OptionalI64 {
		return row.optional_i64_get(column)!
	} $else {
		return error('unsupported SQLite column type for `${column}`')
	}
}

// STUB: QueryResult is sqlx's execution result projection.
pub struct QueryResult {
pub:
	affected u64
}

// STUB: rows_affected mirrors sqlx::QueryResult::rows_affected.
pub fn (result QueryResult) rows_affected() u64 {
	return result.affected
}

// STUB: OptionalRow explicitly preserves sqlx fetch_optional's Result<Option<SqliteRow>> shape.
pub struct OptionalRow {
pub:
	has_value bool
	row       Row
}

// STUB: get exposes a present optional row as a Result so V's conditional-result syntax can
// express Rust's `if let Some(row)` without combining V's unsupported `!?T` form.
pub fn (value &OptionalRow) get() !Row {
	if !value.has_value {
		return error('query returned no rows')
	}
	return Row{
		strings:           value.row.strings.clone()
		integers:          value.row.integers.clone()
		nullable_strings:  value.row.nullable_strings.clone()
		nullable_integers: value.row.nullable_integers.clone()
	}
}

// STUB: Executor preserves sqlx's typed execution boundary for pools and transactions.
pub interface Executor {
	execute_query(query &Query) !QueryResult
	fetch_all_query(query &Query) ![]Row
	fetch_optional_query(query &Query) !OptionalRow
}

// STUB: Query preserves SQL text and ordered bind arguments until execution.
pub struct Query {
pub:
	statement string
pub mut:
	binds []BindValue
}

// STUB: query mirrors sqlx::query.
pub fn query(statement string) Query {
	return Query{ statement: statement }
}

// STUB: query_as mirrors sqlx::query_as. The untranslated backend returns a typed Row rather than
// decoding Rust tuples; target call sites retain the eventual constructor name and SQL text.
pub fn query_as(statement string) Query {
	return Query{ statement: statement }
}

// STUB: bind mirrors sqlx::Query::bind. V uses an explicit SQL sum type in place of Rust's
// Encode/Type generic bounds.
pub fn (query Query) bind(value BindValue) Query {
	mut next := query
	next.binds << value
	return next
}

// STUB: execute mirrors sqlx::Query::execute.
pub fn (query &Query) execute(executor Executor) !QueryResult {
	return executor.execute_query(query)
}

// STUB: fetch_all mirrors sqlx::Query::fetch_all.
pub fn (query &Query) fetch_all(executor Executor) ![]Row {
	return executor.fetch_all_query(query)
}

// STUB: fetch_optional mirrors sqlx::Query::fetch_optional.
pub fn (query &Query) fetch_optional(executor Executor) !OptionalRow {
	return executor.fetch_optional_query(query)
}

// STUB: fetch_one mirrors sqlx::Query::fetch_one.
pub fn (query &Query) fetch_one(executor Executor) !Row {
	return executor.fetch_optional_query(query)!.get()
}

// STUB: ScalarQuery mirrors sqlx::query_scalar's typed single-column query surface.
pub struct ScalarQuery[T] {
	query Query
}

// STUB: OptionalScalar explicitly preserves query_scalar::fetch_optional's Option<T> result.
pub struct OptionalScalar[T] {
pub:
	has_value bool
	value     T
}

// STUB: unwrap_or mirrors Option::unwrap_or for a typed optional scalar.
pub fn (value OptionalScalar[T]) unwrap_or(default_value T) T {
	if value.has_value {
		return value.value
	}
	return default_value
}

// STUB: query_scalar mirrors sqlx::query_scalar while preserving the requested result type.
pub fn query_scalar[T](statement string) ScalarQuery[T] {
	return ScalarQuery[T]{
		query: query(statement)
	}
}

// STUB: bind mirrors sqlx::query_scalar::QueryScalar::bind and retains source bind ordering.
pub fn (scalar_query ScalarQuery[T]) bind(value BindValue) ScalarQuery[T] {
	return ScalarQuery[T]{
		query: scalar_query.query.bind(value)
	}
}

// STUB: fetch_one mirrors sqlx::query_scalar::QueryScalar::fetch_one for the scalar types used by
// the memories tests. The in-memory backend names COUNT projections `count`.
pub fn (scalar_query &ScalarQuery[T]) fetch_one(executor Executor) !T {
	row := scalar_query.query.fetch_one(executor)!
	column := scalar_query.projection_column()!
	return row.try_get[T](column)
}

// STUB: fetch_optional mirrors sqlx::query_scalar::QueryScalar::fetch_optional.
pub fn (scalar_query &ScalarQuery[T]) fetch_optional(executor Executor) !OptionalScalar[T] {
	optional_row := scalar_query.query.fetch_optional(executor)!
	if !optional_row.has_value {
		return OptionalScalar[T]{}
	}
	row := optional_row.get()!
	column := scalar_query.projection_column()!
	return OptionalScalar[T]{
		has_value: true
		value:     row.try_get[T](column)!
	}
}

// STUB: fetch_all mirrors sqlx::query_scalar::QueryScalar::fetch_all.
pub fn (scalar_query &ScalarQuery[T]) fetch_all(executor Executor) ![]T {
	rows := scalar_query.query.fetch_all(executor)!
	column := scalar_query.projection_column()!
	mut values := []T{cap: rows.len}
	for row in rows {
		values << row.try_get[T](column)!
	}
	return values
}

// STUB: projection_column supplies the projected column name for the untranslated in-memory
// executor while retaining query_scalar's public typed API at call sites.
fn (scalar_query &ScalarQuery[T]) projection_column() !string {
	if scalar_query.query.statement.contains('COUNT(') {
		return 'count'
	}
	if scalar_query.query.statement.contains('memory_mode') {
		return 'memory_mode'
	}
	if scalar_query.query.statement.contains('selected_for_phase2') {
		return 'selected_for_phase2'
	}
	if scalar_query.query.statement.contains('thread_id') {
		return 'thread_id'
	}
	return error('unsupported scalar query projection')
}

// STUB: QueryBuilder mirrors sqlx::QueryBuilder<Sqlite> for the operations used by memories.rs.
pub struct QueryBuilder {
pub mut:
	statement string
	binds     []BindValue
}

// STUB: new_query_builder mirrors QueryBuilder::<Sqlite>::new.
pub fn new_query_builder(initial string) QueryBuilder {
	return QueryBuilder{ statement: initial }
}

// STUB: push appends literal SQL.
pub fn (mut builder QueryBuilder) push(fragment string) {
	builder.statement += fragment
}

// STUB: push_bind appends a placeholder and records its value in bind order.
pub fn (mut builder QueryBuilder) push_bind(value BindValue) {
	builder.statement += '?'
	builder.binds << value
}

// STUB: build completes a QueryBuilder as an executable query.
pub fn (builder &QueryBuilder) build() Query {
	return Query{
		statement: builder.statement.clone()
		binds:     builder.binds.clone()
	}
}
