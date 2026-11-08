module updates_cache

import codex_core
import chrono
import serde_json
import std_fs
import std_path
import tokio.fs

pub struct VersionInfo {
pub mut:
	latest_version string
	// ISO-8601 timestamp (RFC3339)
	last_checked_at   chrono.DateTimeUtc
	dismissed_version ?string
}

// Rust's derived Clone allocates only the owned string fields; chrono is Copy.
pub fn (info &VersionInfo) clone() VersionInfo {
	return VersionInfo{
		latest_version:    info.latest_version.clone()
		last_checked_at:   info.last_checked_at
		dismissed_version: if version := info.dismissed_version { version.clone() } else { none }
	}
}

// V has no serde proc-macro derive. This is VersionInfo's derived Serialize:
// declaration order, snake_case keys, and null optional fields are preserved.
pub fn (info &VersionInfo) serialize_json() !string {
	timestamp := info.last_checked_at.to_serde_string()!
	dismissed := if version := info.dismissed_version {
		serde_json.quote_string(&version)
	} else {
		'null'
	}
	return '{"latest_version":' + serde_json.quote_string(&info.latest_version) +
		',"last_checked_at":' + serde_json.quote_string(&timestamp) +
		',"dismissed_version":' + dismissed + '}'
}

// Derived Deserialize also accepts serde's ordered struct sequence form, ignores
// unknown object fields, rejects duplicate known fields, and defaults dismissal.
pub fn VersionInfo.deserialize_json(contents &string) !VersionInfo {
	known_fields := ['latest_version', 'last_checked_at', 'dismissed_version']
	input := serde_json.deserialize_struct(contents, &known_fields)!
	mut latest := ?string(none)
	mut timestamp := ?chrono.DateTimeUtc(none)
	mut dismissed := ?string(none)
	mut dismissed_seen := false
	if input.is_sequence {
		if input.sequence.len < 2 || input.sequence.len > 3 {
			return error('invalid VersionInfo sequence length')
		}
		latest = input.sequence[0].string_owned()!
		timestamp_text := input.sequence[1].string_owned()!
		timestamp = chrono.DateTimeUtc.from_serde_string(&timestamp_text)!
		if input.sequence.len == 3 && !input.sequence[2].is_null() {
			dismissed = input.sequence[2].string_owned()!
		}
	} else {
		for field in input.fields {
			match field.name {
				'latest_version' {
					if latest != none {
						return error('duplicate field `latest_version`')
					}
					latest = field.value.string_owned()!
				}
				'last_checked_at' {
					if timestamp != none {
						return error('duplicate field `last_checked_at`')
					}
					timestamp_text := field.value.string_owned()!
					timestamp = chrono.DateTimeUtc.from_serde_string(&timestamp_text)!
				}
				'dismissed_version' {
					if dismissed_seen {
						return error('duplicate field `dismissed_version`')
					}
					dismissed_seen = true
					if !field.value.is_null() {
						dismissed = field.value.string_owned()!
					}
				}
				else {}
			}
		}
	}
	return VersionInfo{
		latest_version:    latest or { return error('missing field `latest_version`') }
		last_checked_at:   timestamp or { return error('missing field `last_checked_at`') }
		dismissed_version: dismissed
	}
}

const version_filename = 'version.json'

// PathBuf uses the existing owned-string path boundary while Config's
// AbsolutePathBuf dependency is untranslated; Path::join allocates the result.
pub fn version_filepath(config &codex_core.Config) string {
	home := std_path.Path.new(&config.codex_home)
	return home.join(&version_filename)
}

pub fn read_version_info(version_file &std_path.Path) !VersionInfo {
	contents := std_fs.read_to_string(version_file)!
	return VersionInfo.deserialize_json(&contents)
}

// Persist a dismissal for the current latest version so we don't show
// the update popup again for this version.
// V executes the two awaited filesystem operations synchronously in source order.
pub fn dismiss_version(config &codex_core.Config, version &string) ! {
	version_file := version_filepath(config)
	path := std_path.Path.new(&version_file)
	mut info := read_version_info(&path) or {
		VersionInfo{
			latest_version:    version.clone()
			last_checked_at:   chrono.DateTimeUtc.unix_epoch()
			dismissed_version: none
		}
	}
	info.dismissed_version = version.clone()
	json_line := serde_json.to_string(&info)! + '\n'
	if parent := path.parent() {
		fs.create_dir_all(&parent)!
	}
	fs.write(version_file, json_line)!
}
