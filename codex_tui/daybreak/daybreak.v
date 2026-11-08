// Read-only Daybreak eligibility used to choose cyber refusal copy.
// Account-scoped discovery runs in the background; pending/failed reads use neutral copy.
// Astra takes precedence; the TUI does not configure the app’s Daybreak access program.
module daybreak

import codex_app_server_client
import codex_app_server_protocol as api
import codex_core
import codex_http_client
import codex_model_provider
import codex_tui
import serde_json
import sync
import time
import tokio.time as tokio_time
import uuid

// Arc<OnceCell<Notice>> becomes a shared heap cell. Separate mutexes keep get()
// responsive while get_or_init serializes the one background initialization.
@[heap]
struct NoticeCell {
	value_mutex &sync.Mutex = sync.new_mutex()
	init_mutex  &sync.Mutex = sync.new_mutex()
mut:
	initialized bool
	value       Notice = .limited
}

// V exports crate-visible names across modules; this pointer-only value retains
// the source's shared Arc ownership when passed to another background task.
pub struct NoticeCache {
	cell &NoticeCell = &NoticeCell{}
}

pub fn NoticeCache.new() NoticeCache {
	return NoticeCache{}
}

pub fn (cache NoticeCache) get() ?Notice {
	cache.cell.value_mutex.lock()
	defer { cache.cell.value_mutex.unlock() }
	if cache.cell.initialized {
		return cache.cell.value
	}
	return none
}

fn (cache NoticeCache) get_or_init(config &codex_core.Config, request_handle &codex_app_server_client.AppServerRequestHandle) Notice {
	cache.cell.init_mutex.lock()
	defer { cache.cell.init_mutex.unlock() }
	if existing := cache.get() {
		return existing
	}
	value := read_notice(config, request_handle)
	mut cell := cache.cell
	cell.value_mutex.lock()
	cell.value = value
	cell.initialized = true
	cell.value_mutex.unlock()
	return value
}

// V puts the default variant first instead of Rust's #[default] attribute.
pub enum Notice {
	limited
	apply
	astra
}

pub fn prefetch_notice(config &codex_core.Config, server &codex_tui.AppServerSession, cache NoticeCache) {
	if config.model_provider_id != 'openai' || server.uses_remote_workspace() || cache.get() != none {
		return
	}
	context := &NoticeInitializationContext{
		config:         codex_core.clone_config_with_cwd(config, config.cwd.clone())
		request_handle: server.request_handle()
		cache:          cache
	}
	spawn initialize_notice(context)
}

// The spawned task owns the source's cloned Config and shared request handle.
// Moving a heap owner avoids V generating a second implicit deep clone of Config.
@[heap]
struct NoticeInitializationContext {
	config         codex_core.Config
	request_handle codex_app_server_client.AppServerRequestHandle
	cache          NoticeCache
}

fn initialize_notice(context &NoticeInitializationContext) {
	context.cache.get_or_init(&context.config, &context.request_handle)
}

// Tokio drops a timed-out future. V's synchronous worker cannot be forcibly
// cancelled, so its borrowed inputs need an owned heap lifetime after return.
// These additional clones are the allocation adaptation at that runtime boundary.
@[heap]
struct NoticeReadContext {
	config         codex_core.Config
	request_handle codex_app_server_client.AppServerRequestHandle
	deadline       u64
}

fn read_notice(config &codex_core.Config, request_handle &codex_app_server_client.AppServerRequestHandle) Notice {
	context := &NoticeReadContext{ config: codex_core.clone_config_with_cwd(config, config.cwd.clone()), request_handle: request_handle.clone(), deadline: time.sys_mono_now() + u64(3_000_000_000) }
	return tokio_time.timeout[Notice](i64(3_000_000_000), fn [context] () !Notice {
		return read_notice_attempt(&context.config, &context.request_handle, context.deadline)
	}) or { Notice.limited }
}

// The async block's Option short-circuits become errors caught by read_notice;
// every unavailable, failed, or timed-out read still yields the default notice.
fn read_notice_attempt(config &codex_core.Config, request_handle &codex_app_server_client.AppServerRequestHandle, deadline u64) !Notice {
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	// Allow the server to refresh its token before reading local credentials.
	status := request_handle.request_typed[api.GetAuthStatusResponse](api.ClientRequestGetAuthStatus{
		request_id: api.RequestId.string(uuid.Uuid.new_v4().str())
		params:     api.GetAuthStatusParams{ include_token: true, refresh_token: false }
	})!
	// A deadline cannot interrupt native V work already running, but these
	// checkpoints prevent a late operation from starting the next source call.
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	loaded := config.auth_config().load_auth( /*enable_codex_api_key_env*/
	false)!
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	if !loaded.has_value {
		return error('local authentication is unavailable')
	}
	auth := &loaded.value
	if auth.kind != .chatgpt {
		return error('local authentication is not ChatGPT')
	}
	token := auth.get_token()!
	if status.auth_method != ?api.AuthMode(.chatgpt) || status.auth_token != ?string(token) {
		return error('server authentication does not match local credentials')
	}
	client := codex_http_client.RouteAwareClientPool.new_without_redirects(config.http_client_factory(), .api)
	url := '${config.chatgpt_base_url.trim_right('/')}/accounts/verified_access'
	response := client.get(&url)
		.headers(codex_model_provider.auth_provider_from_auth(auth).to_auth_headers())
		.send()!
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	if !response.status().is_success() {
		return error('verified access request was unsuccessful')
	}
	access := response.json(VerifiedAccess.deserialize_json)!
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	current_loaded := config.auth_config().load_auth( /*enable_codex_api_key_env*/
	false)!
	if time.sys_mono_now() >= deadline {
		return error('verified access discovery timed out')
	}
	if !current_loaded.has_value {
		return error('current authentication is unavailable')
	}
	current_auth := &current_loaded.value
	if current_auth.get_token()! != auth.get_token()! || current_auth.get_account_id() != auth.get_account_id() {
		return error('authentication changed during verified access discovery')
	}
	return access.notice()
}

struct VerifiedAccess {
	programs []Program
}

fn VerifiedAccess.deserialize_json(text &string) !VerifiedAccess {
	return deserialize_verified_access(text)
}

enum ProgramKind {
	cyber
	other
}

// Rust's internally tagged enum needs an explicit tag plus owned Cyber payload.
// IgnoredAny retains the number of grants while discarding each JSON payload.
struct Program {
	kind   ProgramKind
	state  string
	grants []serde_json.IgnoredAny
}

// V has no serde derive; the visitor preserves required fields, type errors,
// duplicate-field rejection, sequence structs, and serde(other)'s unknown tags.
fn deserialize_verified_access(text &string) !VerifiedAccess {
	value := serde_json.raw_json_value(text)!
	mut programs := []Program{}
	mut seen_programs := false
	if value.text.starts_with('[') {
		sequence := value.sequence_values()!
		if sequence.len == 0 {
			return error('invalid length 0, expected struct VerifiedAccess with 1 element')
		}
		// Serde next_element decodes the first field before it checks whether
		// the sequence has an extra element.
		programs = deserialize_programs(&sequence[0])!
		if sequence.len > 1 {
			return error('invalid length ${sequence.len}, expected fewer elements in array')
		}
		seen_programs = true
	} else {
		if !value.text.starts_with('{') {
			return error('invalid type: ${value.unexpected()}, expected struct VerifiedAccess')
		}
		fields := value.object_fields()!
		for index in 0 .. fields.len {
			field := &fields[index]
			if field.name == 'programs' {
				if seen_programs {
					return error('duplicate field `programs`')
				}
				seen_programs = true
				// Serde next_value decodes this Vec immediately. A bad first
				// value must fail before a later duplicate field is examined.
				programs = deserialize_programs(&field.value)!
			}
		}
	}
	if !seen_programs {
		return error('missing field `programs`')
	}
	return VerifiedAccess{ programs: programs }
}

fn deserialize_programs(value &serde_json.RawJsonValue) ![]Program {
	values := value.sequence_values()!
	mut programs := []Program{cap: values.len}
	for index in 0 .. values.len {
		programs << deserialize_program(&values[index])!
	}
	return programs
}

fn deserialize_program(value &serde_json.RawJsonValue) !Program {
	// Serde's internally tagged visitor also accepts a sequence: the first
	// element is the tag and the remaining elements are the variant's fields.
	if value.text.starts_with('[') {
		sequence := value.sequence_values()!
		if sequence.len == 0 {
			return error('missing field `program`')
		}
		tag := deserialize_program_tag(&sequence[0])!
		for index in 1 .. sequence.len {
			serde_json.from_str(&sequence[index].text)!
		}
		if tag != 'cyber' {
			return Program{ kind: .other }
		}
		if sequence.len < 2 {
			return error('invalid length 0, expected struct variant Program::Cyber with 2 elements')
		}
		state := sequence[1].string_owned()!
		if sequence.len < 3 {
			return error('invalid length 1, expected struct variant Program::Cyber with 2 elements')
		}
		values := sequence[2].sequence_values()!
		if sequence.len > 3 {
			return error('invalid length ${sequence.len - 1}, expected fewer elements in array')
		}
		return Program{ kind: .cyber, state: state, grants: []serde_json.IgnoredAny{len: values.len} }
	}
	if !value.text.starts_with('{') {
		return error('invalid type: ${value.unexpected()}, expected internally tagged enum Program')
	}
	fields := value.object_fields()!
	mut tag := ''
	mut seen_tag := false
	for index in 0 .. fields.len {
		field := &fields[index]
		if field.name == 'program' {
			if seen_tag {
				return error('duplicate field `program`')
			}
			seen_tag = true
			tag = deserialize_program_tag(&field.value)!
		} else {
			// Internally tagged Deserialize buffers content before choosing a
			// variant, so these are JSON Values before Cyber ignores its grants.
			serde_json.from_str(&field.value.text)!
		}
	}
	if !seen_tag {
		return error('missing field `program`')
	}
	if tag != 'cyber' {
		return Program{ kind: .other }
	}
	mut state := ''
	mut grants := []serde_json.IgnoredAny{}
	mut seen_state := false
	mut seen_grants := false
	for index in 0 .. fields.len {
		field := &fields[index]
		match field.name {
			'state' {
				if seen_state {
					return error('duplicate field `state`')
				}
				seen_state = true
				state = field.value.string_owned()!
			}
			'grants' {
				if seen_grants {
					return error('duplicate field `grants`')
				}
				seen_grants = true
				values := field.value.sequence_values()!
				for _ in values {
					grants << serde_json.IgnoredAny{}
				}
			}
			else {}
		}
	}
	if !seen_state {
		return error('missing field `state`')
	}
	if !seen_grants {
		return error('missing field `grants`')
	}
	return Program{ kind: .cyber, state: state, grants: grants }
}

fn deserialize_program_tag(value &serde_json.RawJsonValue) !string {
	if !value.text.starts_with('"') {
		return error('invalid type: ${value.unexpected()}, expected variant identifier')
	}
	return value.string_owned()
}

fn (access &VerifiedAccess) notice() Notice {
	mut absent := true
	for index in 0 .. access.programs.len {
		program := &access.programs[index]
		match program.kind {
			.cyber {
				if program.state != 'inactive' || program.grants.len != 0 {
					absent = false
					break
				}
			}
			.other {}
		}
	}
	return if absent { .apply } else { .limited }
}

pub fn (notice Notice) for_model(model &string) Notice {
	return match *model {
		// Same identifiers as the app's isDaybreakUnavailableModel.
		'gpt-6-astra', 'gpt-6-astra-wm' { .astra }
		'gpt-5.6-sol' { notice }
		// Other model/access-program mappings are not established for the TUI.
		else { .limited }
	}
}
