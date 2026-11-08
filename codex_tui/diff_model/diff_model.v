module diff_model

import serde_json
import std_path

// Minimal file-change model used by TUI diff rendering and approval previews.
// V payload structs retain the three Rust enum variants. Explicit serde methods
// preserve #[serde(tag = "type", rename_all = "snake_case")] on the wire.
// V's generated payload and sum-type formatting supplies the derived Debug view.
pub type FileChange = Add | Delete | Update

pub struct Add {
pub mut:
	content string @[required]
}

pub struct Delete {
pub mut:
	content string @[required]
}

pub struct Update {
pub mut:
	unified_diff string @[required]
	move_path    ?std_path.PathBuf
}

// Rust's derived Clone creates independent owned String and PathBuf storage.
pub fn (change &FileChange) clone() FileChange {
	match change {
		Add { return Add{ content: change.content.clone() } }
		Delete { return Delete{ content: change.content.clone() } }
		Update {
			return Update{
				unified_diff: change.unified_diff.clone()
				move_path:    if path := change.move_path { path.clone() } else { none }
			}
		}
	}
}

// Rust's derived PartialEq compares discriminants and payloads. PathBuf compares
// normalized path components, so native V aggregate equality is insufficient.
pub fn (change &FileChange) equals(other &FileChange) bool {
	match change {
		Add { return other is Add && change.content == other.content }
		Delete { return other is Delete && change.content == other.content }
		Update {
			if other !is Update || change.unified_diff != other.unified_diff {
				return false
			}
			if path := change.move_path {
				if other_path := other.move_path {
					return path.equals(&other_path)
				}
				return false
			}
			return other.move_path == none
		}
	}
}

// V has no serde derive. Serialize keeps the internal type tag first, fields in
// declaration order, and an explicit null for an absent optional move_path.
pub fn (change &FileChange) serialize_json() !string {
	match change {
		Add {
			return '{"type":"add","content":' + serde_json.quote_string(&change.content) + '}'
		}
		Delete {
			return '{"type":"delete","content":' + serde_json.quote_string(&change.content) + '}'
		}
		Update {
			path := if move_path := change.move_path { move_path.serialize_json()! } else { 'null' }
			return '{"type":"update","unified_diff":' + serde_json.quote_string(&change.unified_diff) +
				',"move_path":' + path + '}'
		}
	}
}

// Deserialize implements the derived internally tagged enum's map and sequence
// visitors. Unknown fields are ignored after Content buffering, required strings
// cannot default, duplicate known fields fail, and omitted move_path means None.
pub fn FileChange.deserialize_json(text &string) !FileChange {
	tag_name := 'type'
	tagged := serde_json.deserialize_tagged(text, &tag_name)!
	if tagged.tag !in ['add', 'delete', 'update'] {
		return error('unknown variant `${tagged.tag}`, expected `add`, `delete` or `update`')
	}
	is_update := tagged.tag == 'update'
	mut content := ?string(none)
	mut unified_diff := ?string(none)
	mut move_path := ?std_path.PathBuf(none)
	mut move_path_seen := false
	if tagged.input.is_sequence {
		if tagged.input.sequence.len != if is_update {
			2
		} else {
			1
		} {
			return error('invalid FileChange sequence length')
		}
		if is_update {
			unified_diff = tagged.input.sequence[0].string_owned()!
			if tagged.input.sequence.len == 2 && !tagged.input.sequence[1].is_null() {
				bytes := tagged.input.sequence[1].string_owned()!
				move_path = std_path.PathBuf.from(bytes)
			}
		} else {
			content = tagged.input.sequence[0].string_owned()!
		}
	} else {
		for field in tagged.input.fields {
			match field.name {
				'content' {
					if !is_update {
						if content != none {
							return error('duplicate field `content`')
						}
						content = field.value.string_owned()!
					}
				}
				'unified_diff' {
					if is_update {
						if unified_diff != none {
							return error('duplicate field `unified_diff`')
						}
						unified_diff = field.value.string_owned()!
					}
				}
				'move_path' {
					if is_update {
						if move_path_seen {
							return error('duplicate field `move_path`')
						}
						move_path_seen = true
						if !field.value.is_null() {
							bytes := field.value.string_owned()!
							move_path = std_path.PathBuf.from(bytes)
						}
					}
				}
				else {}
			}
		}
	}
	match tagged.tag {
		'add' { return Add{ content: content or { return error('missing field `content`') } } }
		'delete' {
			return Delete{ content: content or { return error('missing field `content`') } }
		}
		else {
			return Update{
				unified_diff: unified_diff or { return error('missing field `unified_diff`') }
				move_path:    move_path
			}
		}
	}
}
