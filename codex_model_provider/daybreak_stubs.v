module codex_model_provider

import codex_login
import http

// STUB: model-provider/auth.rs's SharedAuthProvider for an immutable bearer auth
// snapshot. Agent Identity signing and custom header providers are untranslated.
pub struct SharedAuthProvider {
	token              ?string
	account_id         ?string
	is_fedramp_account bool
}

// STUB: auth_provider_from_auth uses the same token/account getter boundaries.
pub fn auth_provider_from_auth(auth &codex_login.CodexAuth) SharedAuthProvider {
	return SharedAuthProvider{ token: if token := auth.get_token() { token } else { none }, account_id: auth.get_account_id(), is_fedramp_account: auth.is_fedramp_account() }
}

// STUB: http::HeaderValue::from_str's invalid-byte rejection for auth headers.
fn valid_auth_header(value &string) bool {
	for byte in *value {
		if (byte < 32 && byte != `\t`) || byte == 127 {
			return false
		}
	}
	return true
}

// STUB: bearer_auth_provider.rs::add_auth_headers and AuthProvider::to_auth_headers
// attach only valid Authorization/account/FedRAMP values from the auth snapshot.
pub fn (provider &SharedAuthProvider) to_auth_headers() http.HeaderMap {
	mut headers := map[string]string{}
	if token := provider.token {
		bearer := 'Bearer ${token}'
		if valid_auth_header(&bearer) {
			headers['authorization'] = bearer
		}
	}
	if account := provider.account_id {
		if valid_auth_header(&account) {
			headers['chatgpt-account-id'] = account.clone()
		}
	}
	if provider.is_fedramp_account {
		headers['x-openai-fedramp'] = 'true'
	}
	return http.HeaderMap{ values: headers }
}
