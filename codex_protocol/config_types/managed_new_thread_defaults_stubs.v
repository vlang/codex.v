module config_types

// STUB: protocol/src/config_types.rs::ServiceTier.
pub enum ServiceTier {
	fast
	flex
}

// STUB: ServiceTier::request_value returns a static request spelling.
// V string literals have static storage; callers clone at Rust's to_string boundary.
pub fn (tier ServiceTier) request_value() string {
	return match tier {
		.fast { 'priority' }
		.flex { 'flex' }
	}
}

// STUB: ServiceTier::from_request_value borrows the request/config spelling.
pub fn ServiceTier.from_request_value(value &string) ?ServiceTier {
	return match *value {
		'fast', 'priority' { ServiceTier.fast }
		'flex' { ServiceTier.flex }
		else { none }
	}
}
