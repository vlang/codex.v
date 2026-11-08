module codex_http_client

import http
import sync

// STUB: HTTP client construction preserves the real resolved proxy policy.
pub enum OutboundProxyPolicy {
	reqwest_default
	respect_system_proxy
}

// STUB: codex-http-client's Copy route bucket, including the update's Other.
pub enum ClientRouteClass {
	auth
	api
	web_socket
	other
}

// STUB: the real factory uses an Arc cookie store. A heap owner preserves shared
// factory clones without copying or consuming the configured cookie payload.
@[heap]
struct ConfiguredCookies {
	values []http.HeaderValue
}

// STUB: HTTP factory's observed policy and process-scoped configured cookies.
pub struct HttpClientFactory {
	policy  OutboundProxyPolicy
	cookies &ConfiguredCookies = unsafe { nil }
}

// STUB: factory construction resolves no transport until a request is sent.
pub fn HttpClientFactory.new(policy OutboundProxyPolicy) HttpClientFactory {
	return HttpClientFactory{ policy: policy }
}

// STUB: consumes the factory and cookie iterator at the real builder boundary.
pub fn (factory HttpClientFactory) with_chatgpt_cookies(cookies []http.HeaderValue) HttpClientFactory {
	return HttpClientFactory{
		policy:  factory.policy
		cookies: if cookies.len > 0 {
			&ConfiguredCookies{ values: cookies }
		} else {
			unsafe { nil }
		}
	}
}

// STUB: borrowed policy query returns its allocation-free Copy value.
pub fn (factory &HttpClientFactory) outbound_proxy_policy() OutboundProxyPolicy {
	return factory.policy
}

// STUB: borrowed factory cookie-presence query does not consume the store.
pub fn (factory &HttpClientFactory) has_chatgpt_cookies() bool {
	return factory.cookies != unsafe { nil }
}

// STUB: fixture observations expose owned cookie snapshots without modifying
// the source-shaped factory or inventing configuration fields.
fn (factory &HttpClientFactory) cookie_snapshot() []string {
	mut result := []string{}
	if factory.cookies != unsafe { nil } {
		for index in 0 .. factory.cookies.values.len {
			result << factory.cookies.values[index].value.clone()
		}
	}
	return result
}

// STUB: a shared client-pool owner retains source builder settings. Network
// proxy discovery, Cloudflare storage, and TLS/custom-CA construction are absent.
@[heap]
struct PoolSettings {
	factory                   HttpClientFactory
	route_class               ClientRouteClass
	cloudflare_cookies        bool
	legacy_custom_ca_fallback bool
	without_redirects         bool
}

// STUB: RouteAwareClientPool's real shared pool handle and eventual API shape.
pub struct RouteAwareClientPool {
	settings &PoolSettings
}

// STUB: route_aware_client_pool.rs::new_without_redirects retains the source's
// redirect policy for API requests; the native resolver-aware transport is absent.
pub fn RouteAwareClientPool.new_without_redirects(factory HttpClientFactory, route_class ClientRouteClass) RouteAwareClientPool {
	return RouteAwareClientPool{ settings: &PoolSettings{ factory: factory, route_class: route_class, without_redirects: true } }
}

// STUB: consumes the factory while retaining Cloudflare cookie-client selection.
pub fn RouteAwareClientPool.with_chatgpt_cloudflare_cookies(factory HttpClientFactory, route_class ClientRouteClass) RouteAwareClientPool {
	return RouteAwareClientPool{ settings: &PoolSettings{ factory: factory, route_class: route_class, cloudflare_cookies: true } }
}

// STUB: the legacy fallback applies only to transport-default proxy routes in
// the eventual network owner. This boundary records that requested selection.
pub fn (pool RouteAwareClientPool) with_legacy_custom_ca_fallback() RouteAwareClientPool {
	return RouteAwareClientPool{ settings: &PoolSettings{ factory: pool.settings.factory, route_class: pool.settings.route_class, cloudflare_cookies: pool.settings.cloudflare_cookies, legacy_custom_ca_fallback: true, without_redirects: pool.settings.without_redirects } }
}

// STUB: typed GET builder; URL conversion owns the borrowed input as Rust IntoUrl.
pub struct RouteAwareRequestBuilder {
	settings        &PoolSettings
	url             string
	request_headers http.HeaderMap
}

// STUB: shared get clones only the URL at reqwest's owned URL boundary.
pub fn (pool &RouteAwareClientPool) get(url &string) RouteAwareRequestBuilder {
	return RouteAwareRequestBuilder{ settings: pool.settings, url: url.clone() }
}

// STUB: consumes a request builder and the source-owned HeaderMap in order.
pub fn (request RouteAwareRequestBuilder) headers(headers http.HeaderMap) RouteAwareRequestBuilder {
	return RouteAwareRequestBuilder{ settings: request.settings, url: request.url, request_headers: headers }
}

// STUB: reqwest::Response's observed status and owned JSON body.
pub struct Response {
	status int
	body   string
}

// STUB: reqwest::Response::status borrows the response and returns a Copy code.
pub fn (response &Response) status() http.StatusCode {
	return http.StatusCode.from_response(response.status)
}

// STUB: consumes the response and preserves reqwest's HTTP 4xx/5xx error branch.
pub fn (response Response) error_for_status() !Response {
	if response.status >= 400 && response.status < 600 {
		return error('HTTP status ${response.status}')
	}
	return response
}

// STUB: reqwest::Response::json consumes the body and calls the target's actual
// derived Deserialize translation; malformed JSON stays an error. V3 cannot
// specialize a return-only generic method inside a release-gated imported
// module, so the typed derive function is an explicit, allocation-free witness.
pub fn (response Response) json[T](deserialize fn (&string) !T) !T {
	return deserialize(&response.body)
}

// STUB: typed external-transport fixture; a blocking gate proves spawn does not
// stall startup without replacing the update call chain with a universal shim.
pub struct UpdatesResponseFixture {
pub:
	status               int = 200
	body                 string
	transport_error      string
	block_until_released bool
	gate                 chan bool
}

// STUB: typed observation of an actual source-shaped request and client policy.
pub struct UpdatesRequestObservation {
pub:
	url                       string
	headers                   http.HeaderMap
	proxy_policy              OutboundProxyPolicy
	route_class               ClientRouteClass
	configured_cookies        []string
	cloudflare_cookies        bool
	legacy_custom_ca_fallback bool
	without_redirects         bool
}

// STUB: synchronized external fixture transport; default operation explicitly
// fails because live routing/TLS/request execution is still untranslated.
@[heap]
struct UpdatesTransportFixture {
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	enabled   bool
	responses []UpdatesResponseFixture
	index     int
	requests  []UpdatesRequestObservation
}

// STUB: the fixture is disabled unless executable tests explicitly enable it.
const updates_transport_fixture = &UpdatesTransportFixture{}

// STUB: source-shaped send consumes the builder and propagates transport errors.
pub fn (request RouteAwareRequestBuilder) send() !Response {
	if request.request_headers.unavailable_reason.len > 0 {
		return error(request.request_headers.unavailable_reason)
	}
	mut response := UpdatesResponseFixture{}
	unsafe {
		mut fixture := updates_transport_fixture
		fixture.mutex.lock()
		defer { fixture.mutex.unlock() }
		if !fixture.enabled {
			return error('STUB: HTTP transport and route resolution are untranslated')
		}
		fixture.requests << UpdatesRequestObservation{ url: request.url, headers: request.request_headers, proxy_policy: request.settings.factory.policy, route_class: request.settings.route_class, configured_cookies: request.settings.factory.cookie_snapshot(), cloudflare_cookies: request.settings.cloudflare_cookies, legacy_custom_ca_fallback: request.settings.legacy_custom_ca_fallback, without_redirects: request.settings.without_redirects }
		if fixture.index >= fixture.responses.len {
			return error('fixture HTTP response queue is exhausted')
		}
		item := &fixture.responses[fixture.index]
		response = UpdatesResponseFixture{ status: item.status, body: item.body.clone(), transport_error: item.transport_error.clone(), block_until_released: item.block_until_released, gate: item.gate }
		fixture.index++
	}
	if response.block_until_released {
		_ := <-response.gate
	}
	if response.transport_error.len > 0 {
		return error(response.transport_error)
	}
	return Response{ status: response.status, body: response.body }
}

$if test {
	// STUB: owns exact queued HTTP fixture responses before the real call chain.
	pub fn set_updates_transport_fixture(responses []UpdatesResponseFixture) {
		unsafe {
			mut fixture := updates_transport_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			fixture.enabled = true
			// The fixture owns an independent snapshot of these owned inputs; V's
			// checker cannot track repeated moves into a process-global array cell.
			mut snapshots := []UpdatesResponseFixture{cap: responses.len}
			for index in 0 .. responses.len {
				item := &responses[index]
				snapshots << UpdatesResponseFixture{ status: item.status, body: item.body.clone(), transport_error: item.transport_error.clone(), block_until_released: item.block_until_released, gate: item.gate }
			}
			fixture.responses = snapshots
			fixture.index = 0
			fixture.requests = []UpdatesRequestObservation{}
		}
	}

	// STUB: observes requests after execution; all snapshots are independently owned.
	pub fn updates_request_observations() []UpdatesRequestObservation {
		unsafe {
			mut fixture := updates_transport_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			mut result := []UpdatesRequestObservation{}
			for index in 0 .. fixture.requests.len {
				item := &fixture.requests[index]
				result << UpdatesRequestObservation{ url: item.url.clone(), headers: item.headers.clone(), proxy_policy: item.proxy_policy, route_class: item.route_class, configured_cookies: item.configured_cookies.clone(), cloudflare_cookies: item.cloudflare_cookies, legacy_custom_ca_fallback: item.legacy_custom_ca_fallback, without_redirects: item.without_redirects }
			}
			return result
		}
	}

	// STUB: returns the transport to its explicit unavailable production boundary.
	pub fn clear_updates_transport_fixture() {
		unsafe {
			mut fixture := updates_transport_fixture
			fixture.mutex.lock()
			defer { fixture.mutex.unlock() }
			fixture.enabled = false
			fixture.responses = []UpdatesResponseFixture{}
			fixture.requests = []UpdatesRequestObservation{}
			fixture.index = 0
		}
	}
}
