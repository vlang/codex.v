module update_action

import codex_install_context
import shlex

// Update action the CLI should perform after the TUI exits.
// Rust derives Debug, Clone, Copy, PartialEq and Eq; a V enum is Copy and has
// built-in formatting and equality.
pub enum UpdateAction {
	// Update via `npm install -g @openai/codex@latest`.
	npm_global_latest
	// Update via `bun install -g @openai/codex@latest`.
	bun_global_latest
	// Update via `vp install -g @openai/codex@latest`.
	vite_plus_global_latest
	// Update via `pnpm add -g @openai/codex@latest`.
	pnpm_global_latest
	// Update via `brew upgrade codex`.
	brew_upgrade
	// Update via `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh`.
	standalone_unix
	// Update via `$env:CODEX_NON_INTERACTIVE=1; irm https://chatgpt.com/codex/install.ps1 | iex`.
	standalone_windows
}

// V's built-in prod and test defines map Rust's !debug_assertions || test:
// use -prod for a release build; ordinary development builds omit this API.
$if prod || test {
	pub fn UpdateAction.from_install_context(context &codex_install_context.InstallContext) ?UpdateAction {
		method := &context.method
		match method {
			codex_install_context.Npm { return .npm_global_latest }
			codex_install_context.Bun { return .bun_global_latest }
			codex_install_context.VitePlus { return .vite_plus_global_latest }
			codex_install_context.Pnpm { return .pnpm_global_latest }
			codex_install_context.Brew { return .brew_upgrade }
			codex_install_context.Standalone {
				return match method.platform {
					.unix { UpdateAction.standalone_unix }
					.windows { UpdateAction.standalone_windows }
				}
			}
			codex_install_context.Other { return none }
		}
	}
}

// Returns the list of command-line arguments for invoking the update.
// V cannot return Rust's &'static string slice directly. Literal command text
// remains immutable, while each call allocates an owned argument array.
pub fn (action UpdateAction) command_args() (string, []string) {
	return match action {
		.npm_global_latest { 'npm', ['install', '-g', '@openai/codex'] }
		.bun_global_latest { 'bun', ['install', '-g', '@openai/codex'] }
		.vite_plus_global_latest { 'vp', ['install', '-g', '@openai/codex'] }
		.pnpm_global_latest { 'pnpm', ['add', '-g', '@openai/codex'] }
		.brew_upgrade { 'brew', ['upgrade', '--cask', 'codex'] }
		.standalone_unix {
			'sh', ['-c', 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh']
		}
		.standalone_windows {
			'powershell', ['-ExecutionPolicy', 'Bypass', '-c',
				r'$env:CODEX_NON_INTERACTIVE=1; irm https://chatgpt.com/codex/install.ps1 | iex']
		}
	}
}

// Returns string representation of the command-line arguments for invoking the update.
pub fn (action UpdateAction) command_str() string {
	command, args := action.command_args()
	// The source iterator borrows each static argument. This local owned array
	// is the V adaptation of that iterator; only the joined result escapes.
	mut words := []string{cap: args.len + 1}
	words << command
	for index in 0 .. args.len {
		words << args[index]
	}
	return shlex.try_join(&words) or { '${command} ${args.join(' ')}' }
}

// Rust cfg(not(debug_assertions)) is V's built-in -prod define.
$if prod {
	pub fn get_update_action() ?UpdateAction {
		return UpdateAction.from_install_context(codex_install_context.InstallContext.current())
	}
}
