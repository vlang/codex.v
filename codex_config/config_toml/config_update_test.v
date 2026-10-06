module config_toml

import toml

fn test_project_config_deserialization_preserves_serde_contract() {
	empty := ProjectConfig.from_toml(toml.parse_text('[project]\n')!.value('project'))!
	assert !empty.is_trusted() && !empty.is_untrusted()
	trusted := ProjectConfig.from_toml(toml.parse_text('[project]\ntrust_level = "trusted"\nunknown = true\n')!.value('project'))!
	assert trusted.is_trusted() && !trusted.is_untrusted()
	untrusted := ProjectConfig.from_toml(toml.parse_text('[project]\ntrust_level = "untrusted"\n')!.value('project'))!
	assert !untrusted.is_trusted() && untrusted.is_untrusted()
	for text in ['project = ["trusted"]\n', 'project = [{ trusted = {} }]\n',
		'[project]\ntrust_level = { trusted = {} }\n'] {
		project := ProjectConfig.from_toml(toml.parse_text(text)!.value('project'))!
		assert project.is_trusted() && !project.is_untrusted()
	}
	tagged_untrusted := ProjectConfig.from_toml(toml.parse_text('[project]\ntrust_level = { untrusted = [] }\n')!.value('project'))!
	assert !tagged_untrusted.is_trusted() && tagged_untrusted.is_untrusted()
	for text in ['project = true\n', 'project = []\n', 'project = ["trusted", "untrusted"]\n',
		'project = [{ trust_level = "trusted" }]\n', '[project]\ntrust_level = true\n',
		'[project]\ntrust_level = "unknown"\n', '[project]\ntrust_level = {}\n',
		'[project]\ntrust_level = []\n', '[project]\ntrust_level = { Trusted = {} }\n',
		'[project]\ntrust_level = { trusted = {}, untrusted = [] }\n',
		'[project]\ntrust_level = { trusted = true }\n',
		'[project]\ntrust_level = { trusted = ["payload"] }\n',
		'[project]\ntrust_level = { trusted = { extra = true } }\n'] {
		_ := ProjectConfig.from_toml(toml.parse_text(text)!.value('project')) or {
			continue
		}
		assert false, 'invalid project trust table must fail deserialization'
	}
	_ := ProjectConfig.from_toml(toml.Null{}) or { return }
	assert false, 'a TOML null sentinel cannot represent a present project'
}
