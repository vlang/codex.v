module config_types

// STUB: protocol/src/config_types.rs::SERVICE_TIER_DEFAULT_REQUEST_VALUE.
// Request/config sentinel for explicit standard routing.
//
// This is not a catalog service tier id. It means the user intentionally
// selected no service tier, so model catalog defaults should not apply.
pub const service_tier_default_request_value = 'default'
