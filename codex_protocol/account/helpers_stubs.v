module account

// STUB: protocol/src/account.rs::PlanType::is_team_like, used by status labels.
pub fn (plan PlanType) is_team_like() bool {
	return plan in [.team, .self_serve_business_pro_lite, .self_serve_business_usage_based]
}

// STUB: protocol/src/account.rs::PlanType::is_business_like, used by status labels.
pub fn (plan PlanType) is_business_like() bool {
	return plan in [.business, .ent26, .enterprise_cbp_automation, .enterprise_cbp_usage_based]
}

// STUB: Rust derives Debug with the original variant spellings. V enum strings
// use snake_case, so status title-casing uses this exact derived-name adapter.
pub fn (plan PlanType) debug_name() string {
	return match plan {
		.unknown { 'Unknown'.clone() }
		.free { 'Free'.clone() }
		.plus { 'Plus'.clone() }
		.pro { 'Pro'.clone() }
		.team { 'Team'.clone() }
		.enterprise { 'Enterprise'.clone() }
		.go { 'Go'.clone() }
		.pro_lite { 'ProLite'.clone() }
		.self_serve_business_pro_lite { 'SelfServeBusinessProLite'.clone() }
		.self_serve_business_usage_based { 'SelfServeBusinessUsageBased'.clone() }
		.business { 'Business'.clone() }
		.ent26 { 'Ent26'.clone() }
		.enterprise_cbp_automation { 'EnterpriseCbpAutomation'.clone() }
		.enterprise_cbp_usage_based { 'EnterpriseCbpUsageBased'.clone() }
		.edu { 'Edu'.clone() }
		.edu_plus { 'EduPlus'.clone() }
		.edu_pro { 'EduPro'.clone() }
	}
}
