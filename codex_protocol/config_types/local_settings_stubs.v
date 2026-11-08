module config_types

// STUB: protocol/src/config_types.rs::AltScreenMode's Copy/Default configuration enum.
// Controls use of the terminal alternate screen; --no-alt-screen can override it.
pub enum AltScreenMode {
	auto
	always
	never
}

// STUB: protocol/src/config_types.rs::ProfileV2Name's validated owned plain profile name.
pub struct ProfileV2Name {
pub:
	value string
}

// STUB: ProfileV2Name::FromStr accepts only nonempty ASCII letters, digits, underscores and hyphens.
pub fn ProfileV2Name.parse(value &string) !ProfileV2Name {
	if value.len == 0 {
		return error('invalid --profile value `${value}`; pass a plain name such as `work`')
	}
	for byte in value.bytes() {
		if !byte.is_alnum() && byte != `_` && byte != `-` {
			return error('invalid --profile value `${value}`; pass a plain name such as `work`')
		}
	}
	return ProfileV2Name{ value: value.clone() }
}

// STUB: ProfileV2Name's derived Clone owns independent name bytes.
pub fn (profile &ProfileV2Name) clone() ProfileV2Name {
	return ProfileV2Name{ value: profile.value.clone() }
}
