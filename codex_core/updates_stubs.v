module codex_core

import codex_features
import codex_http_client
import http

// STUB: core/config::Config::http_client_factory retains effective proxy policy
// and the PSP process cookie. Resolver-aware live HTTP remains untranslated.
pub fn (config &Config) http_client_factory() codex_http_client.HttpClientFactory {
	policy := if config.respect_system_proxy {
		codex_http_client.OutboundProxyPolicy.respect_system_proxy
	} else {
		codex_http_client.OutboundProxyPolicy.reqwest_default
	}
	factory := codex_http_client.HttpClientFactory.new(policy)
	if config.features.enabled(codex_features.Feature.psp) {
		cookie := 'oai-chat-psp=true'
		return factory.with_chatgpt_cookies([http.HeaderValue.from_static(&cookie)])
	}
	return factory
}
