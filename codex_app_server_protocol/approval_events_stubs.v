module codex_app_server_protocol

import codex_protocol.approvals
import codex_utils_path_uri
import serde_json

// STUB: app-server-protocol/protocol/v2/item.rs's Copy approval-kind enum.
pub enum CommandExecutionApprovalKind {
	command
	write_stdin
}

// STUB: app-server v2's network enums have the existing core Copy identities.
pub type NetworkApprovalProtocol = approvals.NetworkApprovalProtocol

// STUB: app-server v2's network-rule action has the existing core Copy identities.
pub type NetworkPolicyRuleAction = approvals.NetworkPolicyRuleAction

// STUB: v2/permissions.rs::ExecPolicyAmendment is a transparent argv newtype.
pub struct ExecPolicyAmendment {
pub:
	command []string
}

// STUB: v2/permissions.rs::NetworkApprovalContext retains both observed fields.
pub struct NetworkApprovalContext {
pub:
	host     string
	protocol NetworkApprovalProtocol
}

// STUB: v2/permissions.rs::NetworkPolicyAmendment retains its host and action.
pub struct NetworkPolicyAmendment {
pub:
	host   string
	action NetworkPolicyRuleAction
}

// STUB: v2/permissions.rs::AdditionalPermissionProfile's typed overlays.
pub struct AdditionalPermissionProfile {
pub:
	network     ?AdditionalNetworkPermissions
	file_system ?AdditionalFileSystemPermissions
}

// STUB: v2/item.rs::CommandExecutionApprovalDecision variant identities.
pub enum CommandExecutionApprovalDecisionKind {
	accept
	accept_for_session
	accept_with_execpolicy_amendment
	apply_network_policy_amendment
	decline
	cancel
}

// STUB: The explicit tag preserves both owned Rust enum payloads. Serde exposes
// only the active payload; the app-server review runtime remains untranslated.
pub struct CommandExecutionApprovalDecision {
pub:
	kind                     CommandExecutionApprovalDecisionKind
	execpolicy_amendment     ExecPolicyAmendment
	network_policy_amendment NetworkPolicyAmendment
}

// STUB: ExecPolicyAmendment's derived Clone owns independent argv strings.
pub fn (value &ExecPolicyAmendment) clone() ExecPolicyAmendment {
	return ExecPolicyAmendment{ command: approval_events_clone_strings(&value.command) }
}

// STUB: Rust Vec<String>::clone clones the strings as well as their container;
// V's array clone is shallow for string elements in a normal compiler build.
pub fn approval_events_clone_strings(values &[]string) []string {
	mut copied := []string{cap: values.len}
	for value in *values { copied << value.clone() }
	return copied
}

// STUB: NetworkApprovalContext's derived Clone owns independent host storage.
pub fn (value &NetworkApprovalContext) clone() NetworkApprovalContext {
	return NetworkApprovalContext{ host: value.host.clone(), protocol: value.protocol }
}

// STUB: NetworkPolicyAmendment's derived Clone owns independent host storage.
pub fn (value &NetworkPolicyAmendment) clone() NetworkPolicyAmendment {
	return NetworkPolicyAmendment{ host: value.host.clone(), action: value.action }
}

// STUB: CommandExecutionApprovalDecision's Clone clones only its active payload.
pub fn (value &CommandExecutionApprovalDecision) clone() CommandExecutionApprovalDecision {
	return match value.kind {
		.accept_with_execpolicy_amendment {
			CommandExecutionApprovalDecision{ kind: value.kind, execpolicy_amendment: value.execpolicy_amendment.clone() }
		}
		.apply_network_policy_amendment {
			CommandExecutionApprovalDecision{ kind: value.kind, network_policy_amendment: value.network_policy_amendment.clone() }
		}
		.accept, .accept_for_session, .decline, .cancel {
			CommandExecutionApprovalDecision{ kind: value.kind }
		}
	}
}

// STUB: AdditionalFileSystemPermissions's Clone clones every legacy/canonical path.
pub fn (value &AdditionalFileSystemPermissions) clone() AdditionalFileSystemPermissions {
	mut read := ?[]codex_utils_path_uri.LegacyAppPathString(none)
	if paths := value.read {
		mut copied := []codex_utils_path_uri.LegacyAppPathString{cap: paths.len}
		for index in 0 .. paths.len {
			copied << paths[index].clone()
		}
		read = copied
	}
	mut write := ?[]codex_utils_path_uri.LegacyAppPathString(none)
	if paths := value.write {
		mut copied := []codex_utils_path_uri.LegacyAppPathString{cap: paths.len}
		for index in 0 .. paths.len {
			copied << paths[index].clone()
		}
		write = copied
	}
	mut entries := ?[]FileSystemSandboxEntry(none)
	if original := value.entries {
		mut copied := []FileSystemSandboxEntry{cap: original.len}
		for index in 0 .. original.len {
			path := &original[index].path
			copied << FileSystemSandboxEntry{
				path:   FileSystemPath{ kind: path.kind, path: path.path.clone(), pattern: path.pattern.clone(), value: path.value.clone() }
				access: original[index].access
			}
		}
		entries = copied
	}
	return AdditionalFileSystemPermissions{ read: read, write: write, glob_scan_max_depth: value.glob_scan_max_depth, entries: entries }
}

// STUB: FileSystemSpecialPath's derived Clone borrows the selector directly,
// preserving the optional owned legacy subpath without moving an array entry.
pub fn (path &FileSystemSpecialPath) clone() FileSystemSpecialPath {
	return AppServerFileSystemSpecialPath{
		kind:    path.kind
		path:    path.path.clone()
		subpath: if subpath := path.subpath {
			subpath.clone()
		} else {
			none
		}
	}
}

// STUB: AdditionalPermissionProfile's Clone retains both optional typed overlays.
pub fn (value &AdditionalPermissionProfile) clone() AdditionalPermissionProfile {
	return AdditionalPermissionProfile{
		network:     if network := value.network {
			AdditionalNetworkPermissions{ enabled: network.enabled }
		} else {
			none
		}
		file_system: if fs := value.file_system { fs.clone() } else { none }
	}
}

// STUB: serde derived struct visitors retain duplicates, sequence positions, and
// ignored unknown JSON fields; length checks follow conversion of earlier fields.
pub struct ApprovalEventsStructInput {
pub:
	fields      []serde_json.RawJsonField
	is_sequence bool
	length      int
}

// STUB: Buffer lexical JSON without converting unknown fields to finite numbers.
// Positional fields beyond the declaration count are rejected by validate_length,
// after the caller has visited and validated the preceding declared fields.
pub fn approval_events_struct_fields(text &string, names &[]string) !ApprovalEventsStructInput {
	input := serde_json.raw_json_value(text)!
	if input.text.starts_with('[') {
		values := input.sequence_values()!
		mut fields := []serde_json.RawJsonField{cap: int_min(values.len, names.len)}
		for index in 0 .. int_min(values.len, names.len) {
			fields << serde_json.RawJsonField{ name: names[index].clone(), value: serde_json.RawJsonValue{ text: values[index].text.clone() } }
		}
		return ApprovalEventsStructInput{ fields: fields, is_sequence: true, length: values.len }
	}
	return ApprovalEventsStructInput{ fields: input.object_fields()! }
}

// STUB: serde sequence visitors report an absent required position or trailing
// elements only after earlier field values have passed their typed visitors.
pub fn (input &ApprovalEventsStructInput) validate_length(minimum int, maximum int) ! {
	if input.is_sequence && (input.length < minimum || input.length > maximum) {
		return error('invalid struct sequence length')
	}
}

// STUB: serde's duplicate-field check runs before converting a repeated value.
pub fn approval_events_check_duplicate(mut seen map[string]bool, name &string) ! {
	if *name in seen { return error('duplicate field `${*name}`') }
	seen[name.clone()] = true
}

// STUB: serde's Vec<String> deserializer owns strings in their source order.
pub fn approval_events_strings(text &string) ![]string {
	value := serde_json.raw_json_value(text)!
	mut output := []string{}
	for item in value.sequence_values()! { output << item.string_owned()! }
	return output
}

// STUB: serde's Vec<String> serializer borrows every string and owns its output.
pub fn approval_events_strings_json(values &[]string) string {
	mut parts := []string{cap: values.len}
	for value in *values { parts << serde_json.quote_string(&value) }
	return '[' + parts.join(',') + ']'
}

// STUB: serde's externally tagged enum visits the first tag and payload before
// rejecting additional object entries. A string carries no payload or entry count.
fn approval_events_enum(text &string) !(string, serde_json.RawJsonValue, bool, int) {
	value := serde_json.raw_json_value(text)!
	if value.text.starts_with('"') {
		return value.string_owned()!, serde_json.RawJsonValue{}, false, 0
	}
	fields := value.object_fields()!
	if fields.len == 0 { return error('expected externally tagged enum with one entry') }
	return fields[0].name.clone(), serde_json.RawJsonValue{ text: fields[0].value.text.clone() }, true, fields.len
}

// STUB: serde_json finishes an enum object only after the selected variant's
// visitor succeeds; unknown variants and malformed payloads take precedence.
fn approval_events_enum_end(entry_count int) ! {
	if entry_count > 1 { return error('expected externally tagged enum with one entry') }
}

// STUB: serde_json's unit-variant payload must be null when externally tagged.
fn approval_events_unit(value &serde_json.RawJsonValue, has_payload bool) ! {
	if has_payload && value.text != 'null' { return error('expected unit variant') }
}

// STUB: CommandExecutionApprovalKind's camelCase serde enum names.
pub fn (kind CommandExecutionApprovalKind) serialize_json() string {
	return if kind == .command { '"command"' } else { '"writeStdin"' }
}

// STUB: CommandExecutionApprovalKind's serde enum visitor rejects null/unknowns.
pub fn CommandExecutionApprovalKind.deserialize_json(text &string) !CommandExecutionApprovalKind {
	tag, value, has_payload, entry_count := approval_events_enum(text)!
	kind := match tag {
		'command' { CommandExecutionApprovalKind.command }
		'writeStdin' { CommandExecutionApprovalKind.write_stdin }
		else { return error('unknown command approval kind: ${tag}') }
	}
	approval_events_unit(&value, has_payload)!
	approval_events_enum_end(entry_count)!
	return kind
}

// STUB: NetworkApprovalProtocol's v2 camelCase wire naming.
fn approval_events_protocol_json(protocol NetworkApprovalProtocol) string {
	return match protocol {
		.http { '"http"' }
		.https { '"https"' }
		.socks5_tcp { '"socks5Tcp"' }
		.socks5_udp { '"socks5Udp"' }
	}
}

// STUB: NetworkApprovalProtocol's serde enum visitor.
fn approval_events_protocol(text &string) !NetworkApprovalProtocol {
	tag, value, has_payload, entry_count := approval_events_enum(text)!
	protocol := match tag {
		'http' { NetworkApprovalProtocol.http }
		'https' { NetworkApprovalProtocol.https }
		'socks5Tcp' { NetworkApprovalProtocol.socks5_tcp }
		'socks5Udp' { NetworkApprovalProtocol.socks5_udp }
		else { return error('unknown network approval protocol: ${tag}') }
	}
	approval_events_unit(&value, has_payload)!
	approval_events_enum_end(entry_count)!
	return protocol
}

// STUB: NetworkPolicyRuleAction's v2 camelCase serde visitor.
fn approval_events_action(text &string) !NetworkPolicyRuleAction {
	tag, value, has_payload, entry_count := approval_events_enum(text)!
	action := match tag {
		'allow' { NetworkPolicyRuleAction.allow }
		'deny' { NetworkPolicyRuleAction.deny }
		else { return error('unknown network policy action: ${tag}') }
	}
	approval_events_unit(&value, has_payload)!
	approval_events_enum_end(entry_count)!
	return action
}

// STUB: ExecPolicyAmendment's transparent serialization exposes only argv.
pub fn (value &ExecPolicyAmendment) serialize_json() string {
	return approval_events_strings_json(&value.command)
}

// STUB: ExecPolicyAmendment's transparent deserialization consumes argv storage.
pub fn ExecPolicyAmendment.deserialize_json(text &string) !ExecPolicyAmendment {
	return ExecPolicyAmendment{ command: approval_events_strings(text)! }
}

// STUB: NetworkApprovalContext's declaration-ordered serde serialization.
pub fn (value &NetworkApprovalContext) serialize_json() string {
	return '{"host":' + serde_json.quote_string(&value.host) + ',"protocol":' + approval_events_protocol_json(value.protocol) + '}'
}

// STUB: NetworkApprovalContext's required-field serde deserialization.
pub fn NetworkApprovalContext.deserialize_json(text &string) !NetworkApprovalContext {
	names := ['host', 'protocol']
	mut seen := map[string]bool{}
	mut host := ?string(none)
	mut protocol := ?NetworkApprovalProtocol(none)
	input := approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { approval_events_check_duplicate(mut seen, &field.name)! }
		match field.name {
			'host' { host = field.value.string_owned()! }
			'protocol' { protocol = approval_events_protocol(&field.value.text)! }
			else {}
		}
	}
	input.validate_length(2, names.len)!
	return NetworkApprovalContext{ host: host or { return error('missing field `host`') }, protocol: protocol or { return error('missing field `protocol`') } }
}

// STUB: NetworkPolicyAmendment's declaration-ordered serde serialization.
pub fn (value &NetworkPolicyAmendment) serialize_json() string {
	return '{"host":' + serde_json.quote_string(&value.host) + ',"action":"${value.action}"}'
}

// STUB: NetworkPolicyAmendment's required-field serde deserialization.
pub fn NetworkPolicyAmendment.deserialize_json(text &string) !NetworkPolicyAmendment {
	names := ['host', 'action']
	mut seen := map[string]bool{}
	mut host := ?string(none)
	mut action := ?NetworkPolicyRuleAction(none)
	input := approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { approval_events_check_duplicate(mut seen, &field.name)! }
		match field.name {
			'host' { host = field.value.string_owned()! }
			'action' { action = approval_events_action(&field.value.text)! }
			else {}
		}
	}
	input.validate_length(2, names.len)!
	return NetworkPolicyAmendment{ host: host or { return error('missing field `host`') }, action: action or { return error('missing field `action`') } }
}

// STUB: CommandExecutionApprovalDecision's externally tagged serde encoding;
// rename_all affects variant names, while payload fields remain snake_case.
pub fn (value &CommandExecutionApprovalDecision) serialize_json() string {
	return match value.kind {
		.accept { '"accept"' }
		.accept_for_session { '"acceptForSession"' }
		.accept_with_execpolicy_amendment {
			'{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":' + value.execpolicy_amendment.serialize_json() + '}}'
		}
		.apply_network_policy_amendment {
			'{"applyNetworkPolicyAmendment":{"network_policy_amendment":' + value.network_policy_amendment.serialize_json() + '}}'
		}
		.decline { '"decline"' }
		.cancel { '"cancel"' }
	}
}

// STUB: CommandExecutionApprovalDecision's serde variant and payload visitors.
pub fn CommandExecutionApprovalDecision.deserialize_json(text &string) !CommandExecutionApprovalDecision {
	tag, value, has_payload, entry_count := approval_events_enum(text)!
	kind := match tag {
		'accept' { CommandExecutionApprovalDecisionKind.accept }
		'acceptForSession' { CommandExecutionApprovalDecisionKind.accept_for_session }
		'acceptWithExecpolicyAmendment' {
			CommandExecutionApprovalDecisionKind.accept_with_execpolicy_amendment
		}
		'applyNetworkPolicyAmendment' {
			CommandExecutionApprovalDecisionKind.apply_network_policy_amendment
		}
		'decline' { CommandExecutionApprovalDecisionKind.decline }
		'cancel' { CommandExecutionApprovalDecisionKind.cancel }
		else { return error('unknown approval decision: ${tag}') }
	}
	if kind !in [.accept_with_execpolicy_amendment, .apply_network_policy_amendment] {
		approval_events_unit(&value, has_payload)!
		approval_events_enum_end(entry_count)!
		return CommandExecutionApprovalDecision{ kind: kind }
	}
	if !has_payload { return error('expected approval decision payload') }
	name := if kind == .accept_with_execpolicy_amendment {
		'execpolicy_amendment'
	} else {
		'network_policy_amendment'
	}
	names := [name.clone()]
	mut seen := map[string]bool{}
	mut result := CommandExecutionApprovalDecision{ kind: kind }
	mut found := false
	input := approval_events_struct_fields(&value.text, &names)!
	for field in input.fields {
		if field.name == name {
			approval_events_check_duplicate(mut seen, &field.name)!
			found = true
			result = if kind == .accept_with_execpolicy_amendment {
				CommandExecutionApprovalDecision{ kind: kind, execpolicy_amendment: ExecPolicyAmendment.deserialize_json(&field.value.text)! }
			} else {
				CommandExecutionApprovalDecision{ kind: kind, network_policy_amendment: NetworkPolicyAmendment.deserialize_json(&field.value.text)! }
			}
		}
	}
	input.validate_length(1, names.len)!
	if !found { return error('missing field `${name}`') }
	approval_events_enum_end(entry_count)!
	return result
}

// STUB: AdditionalPermissionProfile's serde preserves null overlays and camelCase.
pub fn (value &AdditionalPermissionProfile) serialize_json() !string {
	network := if item := value.network {
		'{"enabled":' + if enabled := item.enabled { enabled.str() } else { 'null' } + '}'
	} else {
		'null'
	}
	fs := if item := value.file_system { item.serialize_json()! } else { 'null' }
	return '{"network":' + network + ',"fileSystem":' + fs + '}'
}

// STUB: AdditionalPermissionProfile's serde field/sequence and nested visitors.
// Guards replace early loop continues because V3 otherwise drops the retained
// function-scope filesystem buffer while continuing to the following field.
pub fn AdditionalPermissionProfile.deserialize_json(text &string) !AdditionalPermissionProfile {
	names := ['network', 'fileSystem']
	mut seen := map[string]bool{}
	mut network := ?AdditionalNetworkPermissions(none)
	mut fs := ?AdditionalFileSystemPermissions(none)
	input := approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names {
			approval_events_check_duplicate(mut seen, &field.name)!
			if field.value.text != 'null' {
				if field.name == 'fileSystem' {
					fs = AdditionalFileSystemPermissions.deserialize_json(&field.value.text)!
				} else {
					enabled_names := ['enabled']
					mut enabled_seen := map[string]bool{}
					mut enabled := ?bool(none)
					network_input := approval_events_struct_fields(&field.value.text, &enabled_names)!
					for item in network_input.fields {
						if item.name == 'enabled' {
							approval_events_check_duplicate(mut enabled_seen, &item.name)!
							if item.value.text != 'null' {
								if item.value.text !in ['true', 'false'] {
									return error('expected a boolean')
								}
								enabled = item.value.text == 'true'
							}
						}
					}
					network_input.validate_length(1, enabled_names.len)!
					network = AdditionalNetworkPermissions{ enabled: enabled }
				}
			}
		}
	}
	input.validate_length(2, names.len)!
	return AdditionalPermissionProfile{ network: network, file_system: fs }
}

// STUB: AdditionalFileSystemPermissions's legacy nullable roots and optional
// canonical entries retain their source order and NonZeroUsize wire constraint.
pub fn (value &AdditionalFileSystemPermissions) serialize_json() !string {
	mut fields := []string{}
	for name in ['read', 'write'] {
		mut values := 'null'
		if name == 'read' {
			if paths := value.read {
				mut parts := []string{}
				for index in 0 .. paths.len { parts << paths[index].serialize_json() }
				values = '[' + parts.join(',') + ']'
			}
		} else {
			if paths := value.write {
				mut parts := []string{}
				for index in 0 .. paths.len { parts << paths[index].serialize_json() }
				values = '[' + parts.join(',') + ']'
			}
		}
		fields << '"${name}":' + values
	}
	if depth := value.glob_scan_max_depth {
		if depth == 0 { return error('globScanMaxDepth must be nonzero') }
		fields << '"globScanMaxDepth":${depth}'
	}
	if entries := value.entries {
		mut parts := []string{cap: entries.len}
		for index in 0 .. entries.len { parts << entries[index].serialize_json() }
		fields << '"entries":[' + parts.join(',') + ']'
	}
	return '{' + fields.join(',') + '}'
}

// STUB: AdditionalFileSystemPermissions's serde field/default validation.
pub fn AdditionalFileSystemPermissions.deserialize_json(text &string) !AdditionalFileSystemPermissions {
	names := ['read', 'write', 'globScanMaxDepth', 'entries']
	mut seen := map[string]bool{}
	mut read := ?[]codex_utils_path_uri.LegacyAppPathString(none)
	mut write := ?[]codex_utils_path_uri.LegacyAppPathString(none)
	mut depth := ?usize(none)
	mut entries := ?[]FileSystemSandboxEntry(none)
	input := approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { approval_events_check_duplicate(mut seen, &field.name)! }
		if field.value.text != 'null' {
			match field.name {
				'read', 'write' {
					mut paths := []codex_utils_path_uri.LegacyAppPathString{}
					for item in field.value.sequence_values()! {
						paths << codex_utils_path_uri.LegacyAppPathString.from_string(item.string_owned()!)
					}
					if field.name == 'read' { read = paths } else { write = paths }
				}
				'globScanMaxDepth' {
					value := serde_json.from_str(&field.value.text)!
					number := value.as_u64() or { return error('globScanMaxDepth must be a nonzero unsigned integer') }
					if number == 0 || number > u64(~usize(0)) {
						return error('globScanMaxDepth must be a nonzero unsigned integer')
					}
					depth = usize(number)
				}
				'entries' {
					mut values := []FileSystemSandboxEntry{}
					for item in field.value.sequence_values()! {
						values << FileSystemSandboxEntry.deserialize_json(&item.text)!
					}
					entries = values
				}
				else {}
			}
		}
	}
	input.validate_length(2, names.len)!
	return AdditionalFileSystemPermissions{ read: read, write: write, glob_scan_max_depth: depth, entries: entries }
}

// STUB: FileSystemSandboxEntry's declaration-ordered camelCase serialization.
pub fn (entry &FileSystemSandboxEntry) serialize_json() string {
	return '{"path":' + entry.path.serialize_json() + ',"access":"${entry.access}"}'
}

// STUB: FileSystemSandboxEntry's required-field serde visitors.
pub fn FileSystemSandboxEntry.deserialize_json(text &string) !FileSystemSandboxEntry {
	names := ['path', 'access']
	mut seen := map[string]bool{}
	// Keep required owned path storage separate from its presence marker during
	// visitation, avoiding cleanup of a nested native optional selector temporary.
	mut has_path := false
	mut path := FileSystemPath{}
	mut access := ?FileSystemAccessMode(none)
	input := approval_events_struct_fields(text, &names)!
	for field in input.fields {
		if field.name in names { approval_events_check_duplicate(mut seen, &field.name)! }
		match field.name {
			'path' {
				path = FileSystemPath.deserialize_json(&field.value.text)!
				has_path = true
			}
			'access' {
				tag, payload, has_payload, entry_count := approval_events_enum(&field.value.text)!
				access = match tag {
					'read' { FileSystemAccessMode.read }
					'write' { FileSystemAccessMode.write }
					'deny' { FileSystemAccessMode.deny }
					else { return error('unknown filesystem access: ${tag}') }
				}
				approval_events_unit(&payload, has_payload)!
				approval_events_enum_end(entry_count)!
			}
			else {}
		}
	}
	input.validate_length(2, names.len)!
	if !has_path { return error('missing field `path`') }
	return FileSystemSandboxEntry{ path: path, access: access or { return error('missing field `access`') } }
}

// STUB: FileSystemPath's internally tagged snake_case wire representation.
pub fn (path &FileSystemPath) serialize_json() string {
	return match path.kind {
		.path { '{"type":"path","path":' + path.path.serialize_json() + '}' }
		.glob_pattern {
			'{"type":"glob_pattern","pattern":' + serde_json.quote_string(&path.pattern) + '}'
		}
		.special { '{"type":"special","value":' + path.value.serialize_json() + '}' }
	}
}

// STUB: FileSystemPath's internally tagged enum and payload serde visitors.
pub fn FileSystemPath.deserialize_json(text &string) !FileSystemPath {
	tag_name := 'type'
	input := serde_json.deserialize_tagged(text, &tag_name)!
	kind := match input.tag {
		'path' { FileSystemPathTag.path }
		'glob_pattern' { FileSystemPathTag.glob_pattern }
		'special' { FileSystemPathTag.special }
		else { return error('unknown filesystem path type: ${input.tag}') }
	}
	name := match kind {
		.path { 'path' }
		.glob_pattern { 'pattern' }
		.special { 'value' }
	}
	mut sequence_fields := []serde_json.StructField{}
	if input.input.is_sequence {
		if input.input.sequence.len != 1 { return error('invalid filesystem path sequence length') }
		sequence_fields << serde_json.StructField{ name: name.clone(), value: input.input.sequence[0].clone() }
	}
	// Borrow the buffered Content fields so their enclosing input remains the
	// sole owner; V3's cleanup cannot safely transfer a nested array projection.
	fields := if input.input.is_sequence { &sequence_fields } else { &input.input.fields }
	mut seen := map[string]bool{}
	mut found := false
	mut result := FileSystemPath{}
	for field in *fields {
		if field.name == name {
			approval_events_check_duplicate(mut seen, &field.name)!
			found = true
			result = match kind {
				.path {
					FileSystemPath{ kind: kind, path: codex_utils_path_uri.LegacyAppPathString.from_string(field.value.string_owned()!) }
				}
				.glob_pattern { FileSystemPath{ kind: kind, pattern: field.value.string_owned()! } }
				.special {
					encoded := field.value.to_string()
					FileSystemPath{ kind: kind, value: FileSystemSpecialPath.deserialize_json(&encoded)! }
				}
			}
		}
	}
	if !found { return error('missing field `${name}`') }
	return result
}

// STUB: FileSystemSpecialPath's tagged selector and optional subpath serialization.
pub fn (path &FileSystemSpecialPath) serialize_json() string {
	kind := match path.kind {
		.root { 'root' }
		.minimal { 'minimal' }
		.project_roots { 'project_roots' }
		.tmpdir { 'tmpdir' }
		.slash_tmp { 'slash_tmp' }
		.unknown { 'unknown' }
	}
	mut fields := ['"kind":"${kind}"']
	if path.kind == .unknown { fields << '"path":' + serde_json.quote_string(&path.path) }
	if path.kind in [.project_roots, .unknown] {
		fields << '"subpath":' + if subpath := path.subpath {
			subpath.serialize_json()
		} else {
			'null'
		}
	}
	return '{' + fields.join(',') + '}'
}

// STUB: FileSystemSpecialPath retains the current_working_directory serde alias.
pub fn FileSystemSpecialPath.deserialize_json(text &string) !FileSystemSpecialPath {
	tag_name := 'kind'
	input := serde_json.deserialize_tagged(text, &tag_name)!
	kind := match input.tag {
		'root' { FileSystemSpecialPathTag.root }
		'minimal' { FileSystemSpecialPathTag.minimal }
		'project_roots', 'current_working_directory' { FileSystemSpecialPathTag.project_roots }
		'tmpdir' { FileSystemSpecialPathTag.tmpdir }
		'slash_tmp' { FileSystemSpecialPathTag.slash_tmp }
		'unknown' { FileSystemSpecialPathTag.unknown }
		else { return error('unknown filesystem special path: ${input.tag}') }
	}
	mut sequence_fields := []serde_json.StructField{}
	if input.input.is_sequence {
		expected := if kind == .unknown {
			2
		} else if kind == .project_roots {
			1
		} else {
			0
		}
		if input.input.sequence.len != expected {
			return error('invalid filesystem special path sequence length')
		}
		if kind == .unknown {
			sequence_fields << serde_json.StructField{ name: 'path', value: input.input.sequence[0].clone() }
		}
		if expected > 0 {
			sequence_fields << serde_json.StructField{ name: 'subpath', value: input.input.sequence[expected - 1].clone() }
		}
	}
	// Keep map fields borrowed from Content rather than partially moving its
	// resource-owning nested array; sequence fields keep their own local owner.
	fields := if input.input.is_sequence { &sequence_fields } else { &input.input.fields }
	mut seen := map[string]bool{}
	mut path := ?string(none)
	mut subpath := ?codex_utils_path_uri.LegacyAppPathString(none)
	for field in *fields {
		if (field.name == 'path' && kind == .unknown) || (field.name == 'subpath' && kind in [
			.unknown,
			.project_roots,
		]) {
			approval_events_check_duplicate(mut seen, &field.name)!
			if field.name == 'path' {
				path = field.value.string_owned()!
			} else if !field.value.is_null() {
				subpath = codex_utils_path_uri.LegacyAppPathString.from_string(field.value.string_owned()!)
			}
		}
	}
	// Construct the existing concrete backing type so V3 recognizes that the
	// native optional subpath moves into the aliased API return value.
	return AppServerFileSystemSpecialPath{
		kind:    kind
		path:    if kind == .unknown {
			path or { return error('missing field `path`') }
		} else {
			''.clone()
		}
		subpath: subpath
	}
}
