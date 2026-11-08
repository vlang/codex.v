module codex_login

import sync

// STUB: login/auth/manager.rs::CodexAuth's payload tag; only bearer-token and
// account identity observations are needed by Daybreak's read-only discovery.
pub enum CodexAuthKind {
	api_key
	chatgpt
	chatgpt_auth_tokens
	headers
	agent_identity
	personal_access_token
	bedrock_api_key
	bedrock_access_keys
}

// STUB: immutable CodexAuth snapshot at the untranslated credential-store seam.
// Real ChatGPT token data, refresh storage, keyring, and JWT parsing are absent.
pub struct CodexAuth {
pub:
	kind            CodexAuthKind
	token           string
	token_error     string
	account_id      ?string
	fedramp_account bool
}

// STUB: CodexAuth::get_token returns a newly owned bearer token or IO error.
pub fn (auth &CodexAuth) get_token() !string {
	if auth.token_error.len > 0 {
		return error(auth.token_error)
	}
	return match auth.kind {
		.api_key, .chatgpt, .chatgpt_auth_tokens, .personal_access_token { auth.token.clone() }
		.agent_identity { return error('agent identity auth does not expose a bearer token') }
		.headers { return error('header auth does not expose a bearer token') }
		.bedrock_api_key, .bedrock_access_keys {
			return error('Bedrock API key auth does not expose a Codex bearer token')
		}
	}
}

// STUB: CodexAuth::get_account_id returns an owned optional account identity.
pub fn (auth &CodexAuth) get_account_id() ?string {
	if account := auth.account_id {
		return account.clone()
	}
	return none
}

// STUB: CodexAuth::is_fedramp_account observes the decoded routing claim.
pub fn (auth &CodexAuth) is_fedramp_account() bool {
	return auth.fedramp_account
}

// STUB: immutable auth snapshot cloning at load_auth's owned result boundary.
fn (auth &CodexAuth) clone() CodexAuth {
	return CodexAuth{ kind: auth.kind, token: auth.token.clone(), token_error: auth.token_error.clone(), account_id: auth.get_account_id(), fedramp_account: auth.fedramp_account }
}

// STUB: io::Result<Option<CodexAuth>> fixture outcome retains all result states.
pub struct DaybreakAuthLoadReply {
pub:
	has_auth   bool
	auth       CodexAuth
	load_error string
}

// STUB: synchronized sequential credential snapshots for before/after checks.
@[heap]
struct DaybreakAuthFixture {
	replies []DaybreakAuthLoadReply
mut:
	mutex      &sync.Mutex = sync.new_mutex()
	index      int
	load_flags []bool
}

// STUB: login/auth/manager.rs::AuthConfig resolved credential-loading settings.
// The canonical Config supplies home/base URL. Managed policy/keyring/route
// validation remains unavailable, so production load_auth returns an IO error.
pub struct AuthConfig {
pub:
	codex_home       string
	chatgpt_base_url ?string
	fixture          &DaybreakAuthFixture = unsafe { nil }
}

// STUB: config-owned auth setting cloning shares the credential reader, matching
// persisted credentials shared by Rust's independently owned AuthConfig values.
pub fn (config &AuthConfig) clone() AuthConfig {
	return AuthConfig{
		codex_home:       config.codex_home.clone()
		chatgpt_base_url: if url := config.chatgpt_base_url {
			url.clone()
		} else {
			none
		}
		fixture:          config.fixture
	}
}

// STUB: resolves the observed paths while retaining the shared reader boundary.
pub fn (config &AuthConfig) with_paths(home string, base_url string) AuthConfig {
	return AuthConfig{ codex_home: home, chatgpt_base_url: base_url, fixture: config.fixture }
}

// STUB: safe owned Option<CodexAuth> result; V cannot nest !? resource returns.
pub struct OptionalCodexAuth {
pub:
	has_value bool
	value     CodexAuth
}

// STUB: AuthConfig::load_auth preserves IO failure, no auth, and owned auth.
pub fn (config &AuthConfig) load_auth(enable_codex_api_key_env bool) !OptionalCodexAuth {
	if config.fixture == unsafe { nil } {
		return error('STUB: credential storage, keyring, and authentication policy are untranslated')
	}
	mut fixture := config.fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	fixture.load_flags << enable_codex_api_key_env
	if fixture.index >= fixture.replies.len {
		return error('fixture credential queue is exhausted')
	}
	reply := &fixture.replies[fixture.index]
	fixture.index++
	if reply.load_error.len > 0 {
		return error(reply.load_error)
	}
	if !reply.has_auth {
		return OptionalCodexAuth{}
	}
	return OptionalCodexAuth{ has_value: true, value: reply.auth.clone() }
}

// STUB: config fixture constructor for the typed local credential-store seam.
pub fn AuthConfig.daybreak_fixture(replies []DaybreakAuthLoadReply) AuthConfig {
	return AuthConfig{ fixture: &DaybreakAuthFixture{ replies: replies } }
}

// STUB: observes load calls through the source-shaped credential API.
pub fn (config &AuthConfig) daybreak_load_flags() []bool {
	if config.fixture == unsafe { nil } {
		return []bool{}
	}
	fixture := config.fixture
	fixture.mutex.lock()
	defer { fixture.mutex.unlock() }
	return fixture.load_flags.clone()
}
