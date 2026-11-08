module terminal_visualization_instructions

import codex_core
import codex_features

fn fixture_owned_text(text string) string {
	$if ownership ? {
		return text.to_owned()
	} $else {
		return text.clone()
	}
}

fn fixture_config(enabled bool, developer_instructions ?string) codex_core.Config {
	return codex_core.Config{
		developer_instructions: developer_instructions
		features:               codex_features.Features{
			enabled_features: if enabled {
				[.terminal_visualization_instructions]
			} else {
				[]codex_features.Feature{}
			}
		}
	}
}

fn test_disabled_feature_preserves_owned_control_and_absence() {
	config := fixture_config(false, fixture_owned_text('developer fallback'))
	assert with_terminal_visualization_instructions(&config, none) == none
	control := fixture_owned_text(' \ncontrol text\u3000')
	assert with_terminal_visualization_instructions(&config, control) == ?string(' \ncontrol text\u3000')
	assert config.developer_instructions == ?string('developer fallback')
}

fn test_control_precedes_developer_without_trimming_existing_text() {
	config := fixture_config(true, fixture_owned_text('developer fallback'))
	control := fixture_owned_text('\n  control text \u00a0')
	result := with_terminal_visualization_instructions(&config, control)
	assert result == ?string('\n  control text  \n\n${visualization_instructions}')
	assert config.developer_instructions == ?string('developer fallback')
}

fn test_present_blank_control_suppresses_developer_fallback() {
	config := fixture_config(true, fixture_owned_text('developer fallback'))
	assert with_terminal_visualization_instructions(&config, fixture_owned_text('')) == ?string(visualization_instructions)
	assert with_terminal_visualization_instructions(&config, fixture_owned_text(' \t\n\r')) == ?string(visualization_instructions)
	assert config.developer_instructions == ?string('developer fallback')
}

fn test_absent_control_clones_developer_and_keeps_borrowed_config_reusable() {
	config := fixture_config(true, fixture_owned_text('owned developer text\n'))
	first := with_terminal_visualization_instructions(&config, none)
	second := with_terminal_visualization_instructions(&config, none)
	assert first == ?string('owned developer text\n\n\n${visualization_instructions}')
	assert second == ?string('owned developer text\n\n\n${visualization_instructions}')
	assert config.developer_instructions == ?string('owned developer text\n')
	assert config.features.enabled(.terminal_visualization_instructions)
}

fn test_absent_and_blank_developer_add_only_visualization_guidance() {
	without_developer := fixture_config(true, none)
	assert with_terminal_visualization_instructions(&without_developer, none) == ?string(visualization_instructions)
	blank_developer := fixture_config(true, fixture_owned_text('\u3000\u0085'))
	assert with_terminal_visualization_instructions(&blank_developer, none) == ?string(visualization_instructions)
	assert with_terminal_visualization_instructions(&blank_developer, none) == ?string(visualization_instructions)
	assert blank_developer.developer_instructions == ?string('\u3000\u0085')
}

fn test_unicode_whitespace_control_is_blank_but_zero_width_space_is_content() {
	config := fixture_config(true, fixture_owned_text('developer fallback'))
	for separator in unicode_whitespace.runes() {
		control := fixture_owned_text(separator.str())
		assert with_terminal_visualization_instructions(&config, control) == ?string(visualization_instructions)
	}
	control := fixture_owned_text('\u200b')
	assert with_terminal_visualization_instructions(&config, control) == ?string('​\n\n${visualization_instructions}')
	assert config.developer_instructions == ?string('developer fallback')
}
