module skills_helpers

import codex_app_server_protocol.skill_metadata

fn test_display_name_uses_interface_value_without_trimming_or_empty_filtering() {
	for display in ['My Skill', '', '  My Skill  '] {
		skill := skill_metadata.SkillMetadata{
			name:      'plugin:raw'
			interface: skill_metadata.SkillInterface{ display_name: display.clone() }
		}
		assert skill_display_name(&skill) == display
	}
}

fn test_display_name_plugin_formatting_splits_only_first_colon() {
	for raw, expected in {
		'plain':        'plain'
		'plug:skill':   'skill (plug)'
		'plug:a:b':     'a:b (plug)'
		'plug::':       ': (plug)'
		':skill':       ':skill'
		'plug:':        'plug:'
		':':            ':'
		'':             ''
		'插件:技巧':    '技巧 (插件)'
		' plug:skill ': 'skill  ( plug)'
	} {
		skill := skill_metadata.SkillMetadata{ name: raw }
		assert skill_display_name(&skill) == expected
	}
}

fn test_display_name_interface_without_override_falls_back_to_raw_name() {
	skill := skill_metadata.SkillMetadata{
		name:      'plug:skill'
		interface: skill_metadata.SkillInterface{ short_description: 'Help' }
	}
	assert skill_display_name(&skill) == 'skill (plug)'
}

fn test_description_prefers_interface_then_legacy_then_full() {
	full_only := skill_metadata.SkillMetadata{ description: 'Full' }
	legacy := skill_metadata.SkillMetadata{
		description:       'Full'
		short_description: 'Legacy'
	}
	modern := skill_metadata.SkillMetadata{
		description:       'Full'
		short_description: 'Legacy'
		interface:         skill_metadata.SkillInterface{ short_description: 'Modern' }
	}
	missing_modern := skill_metadata.SkillMetadata{
		description:       'Full'
		short_description: 'Legacy'
		interface:         skill_metadata.SkillInterface{ display_name: 'Name' }
	}
	assert skill_description(&full_only) == 'Full'
	assert skill_description(&legacy) == 'Legacy'
	assert skill_description(&modern) == 'Modern'
	assert skill_description(&missing_modern) == 'Legacy'
}

fn test_description_empty_and_whitespace_overrides_are_present() {
	for short in ['', '  ', '\nHello\n'] {
		modern := skill_metadata.SkillMetadata{
			description:       'Full'
			short_description: 'Legacy'
			interface:         skill_metadata.SkillInterface{ short_description: short.clone() }
		}
		legacy := skill_metadata.SkillMetadata{
			description:       'Full'
			short_description: short.clone()
		}
		assert skill_description(&modern) == short
		assert skill_description(&legacy) == short
	}
}

fn test_match_skill_display_match_wins_even_if_raw_match_has_better_score() {
	filter := 'abc'
	display := 'a-b-c'
	raw := 'abc'
	matched := match_skill(&filter, &display, &raw) or { panic('display should match') }
	assert matched == SkillMatch{ indices: [0, 2, 4], score: -98 }
}

fn test_match_skill_raw_fallback_omits_display_highlights() {
	filter := 'plugin'
	display := 'Pretty Name'
	raw := 'plugin:skill'
	matched := match_skill(&filter, &display, &raw) or { panic('raw name should match') }
	assert matched == SkillMatch{ indices: none, score: -100 }
	unicode_filter := 'is'
	unicode_raw := 'plug:İstanbul'
	unicode_match := match_skill(&unicode_filter, &display, &unicode_raw) or {
		panic('raw Unicode name should match')
	}
	assert unicode_match == SkillMatch{ indices: none, score: 1 }
}

fn test_match_skill_missing_match_and_identical_names() {
	filter := 'xyz'
	display := 'abc'
	raw := 'abc'
	assert match_skill(&filter, &display, &raw) == none
	other_raw := 'qrs'
	assert match_skill(&filter, &display, &other_raw) == none
}

fn test_match_skill_empty_filter_has_present_empty_highlights() {
	filter := ''
	display := 'Pretty'
	raw := 'plugin:skill'
	matched := match_skill(&filter, &display, &raw) or { panic('empty filter should match') }
	assert matched == SkillMatch{ indices: []int{}, score: 0x7fffffff }
}

fn test_match_skill_unicode_expansion_uses_original_character_positions() {
	filter := 'i\u0307'
	display := 'İstanbul'
	raw := 'plugin:istanbul'
	matched := match_skill(&filter, &display, &raw) or { panic('Unicode display should match') }
	assert matched == SkillMatch{ indices: [0], score: -100 }

	other_filter := '技巧'
	other_display := '技巧 (插件)'
	other_raw := '插件:技巧'
	other_match := match_skill(&other_filter, &other_display, &other_raw) or {
		panic('Unicode display should match')
	}
	assert other_match == SkillMatch{ indices: [0, 1], score: -100 }
}

fn test_borrowed_skill_with_owned_optional_interface_remains_reusable() {
	mut raw := 'plugin:raw'
	mut full := 'Full description'
	mut legacy := 'Legacy description'
	mut display := 'Pretty skill'
	mut modern := 'Modern description'
	$if ownership ? {
		raw = 'plugin:raw'.to_owned()
		full = 'Full description'.to_owned()
		legacy = 'Legacy description'.to_owned()
		display = 'Pretty skill'.to_owned()
		modern = 'Modern description'.to_owned()
	}
	skill := skill_metadata.SkillMetadata{
		name:              raw
		description:       full
		short_description: legacy
		interface:         skill_metadata.SkillInterface{
			display_name:      display
			short_description: modern
		}
	}
	for _ in 0 .. 4 {
		assert skill_display_name(&skill) == 'Pretty skill'
		assert skill_description(&skill) == 'Modern description'
	}
	assert skill.name == 'plugin:raw'
	assert skill.description == 'Full description'
	assert skill.short_description or { panic('legacy value was consumed') } == 'Legacy description'
	skill_interface := skill.interface or { panic('interface was consumed') }
	assert skill_interface.display_name or { panic('display name was consumed') } == 'Pretty skill'
	assert skill_interface.short_description or { panic('description was consumed') } == 'Modern description'
}

fn test_borrowed_skill_without_interface_and_match_inputs_remain_reusable() {
	mut raw := 'plugin:skill'
	mut full := 'Full description'
	mut legacy := 'Legacy description'
	mut filter := 'plugin'
	mut display := 'Pretty Name'
	$if ownership ? {
		raw = 'plugin:skill'.to_owned()
		full = 'Full description'.to_owned()
		legacy = 'Legacy description'.to_owned()
		filter = 'plugin'.to_owned()
		display = 'Pretty Name'.to_owned()
	}
	skill := skill_metadata.SkillMetadata{
		name:              raw
		description:       full
		short_description: legacy
	}
	for _ in 0 .. 4 {
		assert skill_display_name(&skill) == 'skill (plugin)'
		assert skill_description(&skill) == 'Legacy description'
		matched := match_skill(&filter, &display, &skill.name) or { panic('raw should match') }
		assert matched == SkillMatch{ indices: none, score: -100 }
		assert filter == 'plugin'
		assert display == 'Pretty Name'
	}
	assert skill.name == 'plugin:skill'
	assert skill.description == 'Full description'
	assert skill.short_description or { panic('description was consumed') } == 'Legacy description'
}

fn test_borrowed_skill_plain_name_and_full_description_remain_reusable() {
	mut name := 'Plain skill'
	mut description := 'Full description'
	$if ownership ? {
		name = 'Plain skill'.to_owned()
		description = 'Full description'.to_owned()
	}
	skill := skill_metadata.SkillMetadata{
		name:        name
		description: description
	}
	for _ in 0 .. 4 {
		assert skill_display_name(&skill) == 'Plain skill'
		assert skill_description(&skill) == 'Full description'
	}
	assert skill.name == 'Plain skill'
	assert skill.description == 'Full description'
	assert skill.interface == none
	assert skill.short_description == none
}
