module edit

import os
import toml
import codex_config.types
import std_path

// STUB: core/src/config/edit.rs::ConfigEdit's SetPath variant used by LocalSettings's tests.
pub struct ConfigEdit {
	segments []string
	value    toml.Any
}

// STUB: syntax_theme_edit sets [tui].theme through the source-shaped edit API.
pub fn syntax_theme_edit(name &string) ConfigEdit {
	return ConfigEdit{ segments: ['tui'.clone(), 'theme'.clone()], value: toml.Any(name.clone()) }
}

// STUB: core/src/config/edit.rs::ConfigEditsBuilder's owned file and ordered edits.
pub struct ConfigEditsBuilder {
mut:
	config_path string
	edits       []ConfigEdit
}

// STUB: ConfigEditsBuilder::new targets CODEX_HOME/config.toml.
pub fn ConfigEditsBuilder.new(codex_home &std_path.Path) ConfigEditsBuilder {
	child := 'config.toml'
	path := codex_home.join(&child)
	view := std_path.Path.new(&path)
	return ConfigEditsBuilder.for_config_path(&view)
}

// STUB: ConfigEditsBuilder::for_config_path preserves the exact selected writable file.
pub fn ConfigEditsBuilder.for_config_path(config_path &std_path.Path) ConfigEditsBuilder {
	return ConfigEditsBuilder{ config_path: config_path.to_path_buf() }
}

// STUB: ConfigEditsBuilder::set_session_picker_view appends the source SetPath edit.
pub fn (builder ConfigEditsBuilder) set_session_picker_view(mode types.SessionPickerViewMode) ConfigEditsBuilder {
	mut owned := builder
	owned.edits << ConfigEdit{ segments: ['tui'.clone(), 'session_picker_view'.clone()], value: toml.Any(mode.as_str().clone()) }
	return owned
}

// STUB: ConfigEditsBuilder::with_edits consumes and appends the owned edit sequence.
pub fn (builder ConfigEditsBuilder) with_edits(edits []ConfigEdit) ConfigEditsBuilder {
	mut owned := builder
	owned.edits << edits
	return owned
}

// STUB: ConfigEditsBuilder::apply's async persistence boundary runs synchronously in V.
// Preserve atomic replacement and untouched TOML values; formatting/comments and symlink
// write-path resolution await the real config editor. Only two-level SetPath edits are modeled.
pub fn (builder ConfigEditsBuilder) apply() ! {
	if builder.edits.len == 0 {
		return
	}
	text := if os.exists(builder.config_path.clone()) {
		os.read_file(builder.config_path.clone())!
	} else {
		''.clone()
	}
	doc := toml.parse_text(text)!
	mut root := doc.to_any().as_map()
	for entry in builder.edits {
		if entry.segments.len != 2 {
			return error('untranslated config edit depth')
		}
		// V's TOML accessor consumes the map receiver; provide independent map storage
		// while the editor retains the owned document for subsequent ordered edits.
		mut table := local_settings_edit_table(root.clone().value(entry.segments[0]))!
		table[entry.segments[1].clone()] = entry.value
		root[entry.segments[0].clone()] = toml.Any(table)
	}
	temporary := builder.config_path + '.local-settings.tmp'
	os.write_file(temporary.clone(), root.to_toml())!
	os.rename(temporary, builder.config_path)!
}

// STUB: ConfigDocument::SetPath creates an empty section when the source table is absent.
fn local_settings_edit_table(value toml.Any) !map[string]toml.Any {
	return match value {
		map[string]toml.Any { value }
		toml.Null { map[string]toml.Any{} }
		else { return error('config edit section must be a table') }
	}
}
