module codex_core

import os
import std_io
import uuid

fn test_config_builder_classifies_invalid_project_config_as_invalid_data() {
	home := os.join_path(os.temp_dir(), 'codex-v-project-config-${uuid.Uuid.new_v4()}')
	os.mkdir_all(home)!
	defer { os.rmdir_all(home) or { panic(err) } }
	for text in ['projects = true\n', '[projects]\n"/repo" = true\n',
		'[projects."/repo"]\ntrust_level = "unknown"\n'] {
		os.write_file(os.join_path(home.clone(), 'config.toml'), text)!
		_ := ConfigBuilder.default().codex_home(home.clone()).fallback_cwd(home.clone()).build() or {
			if err is std_io.Error {
				assert err.kind() == .invalid_data
			} else {
				assert false, 'invalid project config must retain its IO error classification'
			}
			continue
		}
		assert false, 'invalid project config must fail the real builder dependency'
	}
}
