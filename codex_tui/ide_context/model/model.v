// Canonical IDE context model from tui/src/ide_context.rs.
module model

import serde_json

// Rust exposes these fields to its child modules. V has no pub(super), so the
// canonical model and fields are public across the parent/prompt module boundary.
// The parent retains its original names through aliases; no duplicate model exists.
pub struct IdeContext {
pub:
	active_file ?ActiveFile      @[json: 'activeFile']
	open_tabs   []FileDescriptor @[json: 'openTabs']
}

pub struct ActiveFile {
pub:
	descriptor               FileDescriptor
	selection                Range
	active_selection_content string @[json: 'activeSelectionContent']
	selections               []Range
}

pub struct FileDescriptor {
pub:
	label string
	path  string
}

pub struct Range {
pub:
	start Position
	end   Position
}

pub struct Position {
pub:
	line      u32
	character u32
}

// V has no serde derive or flatten annotation. Explicit decoding preserves the
// camelCase keys, flattened descriptor, required fields and source defaults.
// This borrowed boundary constructs the owned result serde Deserialize returns.
pub fn IdeContext.deserialize_value(value &serde_json.Value) !IdeContext {
	if value.is_array() {
		count := value.array_len()!
		if count < 1 || count > 2 {
			return error('invalid length ${count}, expected struct IdeContext with 2 elements')
		}
		active := value.get_index(0)
		return IdeContext{
			active_file: if active.value.is_null() {
				none
			} else {
				decode_active_file(active.value)!
			}
			open_tabs:   if count == 2 {
				tabs := value.get_index(1)
				decode_open_tabs(tabs.value)!
			} else {
				[]FileDescriptor{}
			}
		}
	}
	require_object(value, 'IdeContext')!
	active := optional_field(value, 'activeFile')
	tabs := optional_field(value, 'openTabs')
	return IdeContext{
		active_file: if active.has_value && !active.value.is_null() {
			decode_active_file(active.value)!
		} else {
			none
		}
		open_tabs:   if tabs.has_value { decode_open_tabs(tabs.value)! } else { []FileDescriptor{} }
	}
}

// Parse into serde_json::Value before applying the source's from_value decoder.
// V needs an explicit typed callback in place of Rust's Deserialize trait bound.
// The input remains borrowed; the result owns decoded strings.
pub fn IdeContext.deserialize_json(text &string) !IdeContext {
	value := serde_json.from_str(text)!
	return serde_json.from_value[IdeContext](value, IdeContext.deserialize_value)
}

fn decode_active_file(value &serde_json.Value) !ActiveFile {
	// serde(flatten) makes ActiveFile map-only; unlike the other structs it does
	// not accept JSON sequences. selection is checked before flattened fields.
	require_object(value, 'ActiveFile')!
	selection := required_field(value, 'selection')!
	decoded_selection := decode_range(selection.value)!
	content := optional_field(value, 'activeSelectionContent')
	decoded_content := if content.has_value { content.value.string_owned()! } else { '' }
	selections := optional_field(value, 'selections')
	decoded_selections := if selections.has_value {
		decode_ranges(selections.value)!
	} else {
		[]Range{}
	}
	return ActiveFile{
		descriptor:               decode_file_descriptor(value)!
		selection:                decoded_selection
		active_selection_content: decoded_content
		selections:               decoded_selections
	}
}

fn decode_file_descriptor(value &serde_json.Value) !FileDescriptor {
	if value.is_array() {
		require_sequence_length(value, 2, 'FileDescriptor')!
		label := value.get_index(0)
		path := value.get_index(1)
		return FileDescriptor{ label: label.value.string_owned()!, path: path.value.string_owned()! }
	}
	require_object(value, 'FileDescriptor')!
	label := required_field(value, 'label')!
	decoded_label := label.value.string_owned()!
	path := required_field(value, 'path')!
	return FileDescriptor{ label: decoded_label, path: path.value.string_owned()! }
}

fn decode_range(value &serde_json.Value) !Range {
	if value.is_array() {
		require_sequence_length(value, 2, 'Range')!
		start := value.get_index(0)
		end := value.get_index(1)
		return Range{ start: decode_position(start.value)!, end: decode_position(end.value)! }
	}
	require_object(value, 'Range')!
	start := required_field(value, 'start')!
	decoded_start := decode_position(start.value)!
	end := required_field(value, 'end')!
	return Range{ start: decoded_start, end: decode_position(end.value)! }
}

fn decode_position(value &serde_json.Value) !Position {
	if value.is_array() {
		require_sequence_length(value, 2, 'Position')!
		line := value.get_index(0)
		character := value.get_index(1)
		return Position{ line: decode_u32(line.value)!, character: decode_u32(character.value)! }
	}
	require_object(value, 'Position')!
	line := required_field(value, 'line')!
	decoded_line := decode_u32(line.value)!
	character := required_field(value, 'character')!
	return Position{ line: decoded_line, character: decode_u32(character.value)! }
}

fn decode_u32(value &serde_json.Value) !u32 {
	number := value.as_u64() or { return error('invalid type, expected u32') }
	if number > u64(4294967295) {
		return error('invalid value ${number}, expected u32')
	}
	return u32(number)
}

fn decode_open_tabs(value &serde_json.Value) ![]FileDescriptor {
	count := value.array_len()!
	mut tabs := []FileDescriptor{cap: count}
	for index in 0 .. count {
		tab := value.get_index(index)
		tabs << decode_file_descriptor(tab.value)!
	}
	return tabs
}

fn decode_ranges(value &serde_json.Value) ![]Range {
	count := value.array_len()!
	mut ranges := []Range{cap: count}
	for index in 0 .. count {
		range := value.get_index(index)
		ranges << decode_range(range.value)!
	}
	return ranges
}

fn required_field(value &serde_json.Value, name string) !serde_json.BorrowedValue {
	field := value.get(&name)
	if !field.has_value {
		return error('missing field `${name}`')
	}
	return field
}

fn optional_field(value &serde_json.Value, name string) serde_json.BorrowedValue {
	return value.get(&name)
}

fn require_object(value &serde_json.Value, name string) ! {
	if !value.is_object() {
		return error('invalid type, expected struct ${name}')
	}
}

fn require_sequence_length(value &serde_json.Value, expected int, name string) ! {
	count := value.array_len()!
	if count != expected {
		return error('invalid length ${count}, expected struct ${name} with ${expected} elements')
	}
}

// Explicit Clone implementations retain Rust's owned copy boundaries. V provides
// Debug formatting and field-wise equality for these nonrecursive model structs.
pub fn (context &IdeContext) clone() IdeContext {
	mut tabs := []FileDescriptor{cap: context.open_tabs.len}
	for index in 0 .. context.open_tabs.len {
		tabs << context.open_tabs[index].clone()
	}
	return IdeContext{
		active_file: if active := context.active_file { active.clone() } else { none }
		open_tabs:   tabs
	}
}

pub fn (active &ActiveFile) clone() ActiveFile {
	return ActiveFile{
		descriptor:               active.descriptor.clone()
		selection:                active.selection.clone()
		active_selection_content: active.active_selection_content.clone()
		selections:               active.selections.clone()
	}
}

pub fn (descriptor &FileDescriptor) clone() FileDescriptor {
	return FileDescriptor{ label: descriptor.label.clone(), path: descriptor.path.clone() }
}

pub fn (range &Range) clone() Range {
	return Range{ start: range.start.clone(), end: range.end.clone() }
}

pub fn (position &Position) clone() Position {
	return *position
}
