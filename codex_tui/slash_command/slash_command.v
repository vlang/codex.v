module slash_command

import strum

// Commands that can be invoked by starting a message with a leading slash.
// V enums provide the scalar copy, equality, hashing, and debug operations derived by Rust.
pub enum SlashCommand {
	// DO NOT ALPHA-SORT! Enum order is presentation order in the popup, so
	// more frequently used commands should be listed first.
	model
	ide
	permissions
	keymap
	vim
	elevate_sandbox
	sandbox_read_root
	experimental
	auto_review
	memories
	skills
	import_cmd
	hooks
	review
	rename
	new_thread
	archive
	delete_thread
	resume
	fork
	worktree
	app
	init
	compact
	recap
	plan
	voice
	goal
	agents
	side
	btw
	copy
	export_cmd
	raw
	diff
	mention
	status
	cd
	pwd
	usage
	debug_config
	title
	statusline
	theme
	pets
	mcp
	apps
	plugins
	logout
	quit
	exit
	feedback
	rollout
	ps
	stop
	clear
	personality
	test_approval
	multi_agents
	// Debugging commands.
	memory_drop
	memory_update
}

// User-visible description shown in the popup.
pub fn (command SlashCommand) description() string {
	return match command {
		.feedback { 'send logs to maintainers' }
		.new_thread { 'start a new chat during a conversation' }
		.init { 'create an AGENTS.md file with instructions for Codex' }
		.compact { 'summarize conversation to prevent hitting the context limit' }
		.recap { 'summarize the current conversation now' }
		.review { 'review my current changes and find issues' }
		.rename { 'rename the current thread' }
		.resume { 'resume a saved chat' }
		.archive { 'archive this session and exit' }
		.delete_thread { 'permanently delete this session and exit' }
		.clear { 'clear the terminal and start a new chat' }
		.fork { 'fork the current chat' }
		.worktree { 'start or continue a conversation in a new worktree' }
		.app { 'continue this session in the Desktop app' }
		.quit, .exit { 'exit Codex' }
		.copy { 'copy the last response or part of it' }
		.export_cmd { 'export the conversation as markdown' }
		.raw { 'toggle raw scrollback mode for copy-friendly terminal selection' }
		.diff { 'show git diff (including untracked files)' }
		.mention { 'mention a file' }
		.skills { 'use skills to improve how Codex performs specific tasks' }
		.import_cmd { 'import setup, this project, and recent chats from Claude Code' }
		.hooks { 'view and manage lifecycle hooks' }
		.status { 'show current session configuration and token usage' }
		.cd { 'change the current working directory' }
		.pwd { 'show the current working directory' }
		.usage { 'view account usage or use a usage limit reset' }
		.debug_config { 'show config layers and requirement sources for debugging' }
		.title { 'configure which items appear in the terminal title' }
		.statusline { 'configure which items appear in the status line' }
		.theme { 'choose a syntax highlighting theme' }
		.pets { 'choose or hide the terminal pet' }
		.ps { 'list background terminals' }
		.stop { 'stop all background terminals' }
		.memory_drop { 'DO NOT USE' }
		.memory_update { 'DO NOT USE' }
		.model { 'choose what model and reasoning effort to use' }
		.ide { 'include current selection, open files, and other context from your IDE' }
		.personality { 'choose a communication style for Codex' }
		.plan { 'switch to Plan mode' }
		.voice { 'start or stop a live voice conversation' }
		.goal { 'set or view the goal for a long-running task' }
		.agents { 'view and switch between all active agent sessions' }
		.multi_agents { "switch between this session's subagents" }
		.side, .btw { 'start a side conversation in an ephemeral fork' }
		.permissions { 'choose what Codex is allowed to do' }
		.keymap { 'remap TUI shortcuts' }
		.vim { 'toggle Vim mode for the composer' }
		.elevate_sandbox { 'set up elevated agent sandbox' }
		.sandbox_read_root { 'let sandbox read a directory: /sandbox-add-read-dir <absolute_path>' }
		.experimental { 'toggle experimental features' }
		.auto_review { 'approve one retry of a recent auto-review denial' }
		.memories { 'configure memory use and generation' }
		.mcp { 'list configured MCP tools; use /mcp verbose for details' }
		.apps { 'manage apps' }
		.plugins { 'browse plugins' }
		.logout { 'log out of Codex' }
		.rollout { 'print the rollout file path' }
		.test_approval { 'test approval request' }
	}
}

// Command string without the leading '/'. Provided for compatibility with
// existing code that expects a method named `command()`.
pub fn (command SlashCommand) command() string {
	return command.into_static_str()
}

// Whether this command supports inline args (for example `/review ...`).
pub fn (command SlashCommand) supports_inline_args() bool {
	return command in [.review, .rename, .new_thread, .clear, .fork, .plan, .goal, .voice, .ide,
		.keymap, .mcp, .export_cmd, .raw, .cd, .pwd, .usage, .pets, .side, .btw, .resume,
		.sandbox_read_root]
}

// Whether this command remains available inside an active side conversation.
pub fn (command SlashCommand) available_in_side_conversation() bool {
	return command in [.copy, .agents, .export_cmd, .raw, .diff, .mention, .status, .pwd, .usage,
		.ide]
}

// Whether this command can be run while a task is in progress.
pub fn (command SlashCommand) available_during_task() bool {
	return match command {
		.new_thread, .archive, .delete_thread, .fork, .worktree, .init, .compact, .recap,
		.export_cmd, .keymap, .vim, .elevate_sandbox, .sandbox_read_root, .experimental, .memories,
		.import_cmd, .review, .plan, .cd, .clear, .logout, .memory_drop, .memory_update {
			false
		}
		.diff, .resume, .model, .personality, .permissions, .copy, .raw, .rename, .mention,
		.skills, .hooks, .status, .pwd, .usage, .debug_config, .ps, .stop, .app, .goal, .voice,
		.mcp, .apps, .plugins, .title, .statusline, .auto_review, .feedback, .ide, .quit, .exit,
		.side, .btw {
			true
		}
		.rollout { true }
		.test_approval { true }
		.agents, .multi_agents { true }
		.theme, .pets { false }
	}
}

fn (command SlashCommand) is_visible() bool {
	match command {
		.sandbox_read_root {
			$if windows {
				return true
			} $else {
				return false
			}
		}
		.copy {
			$if android {
				return false
			} $else {
				return true
			}
		}
		.app {
			$if macos || windows {
				return true
			} $else {
				return false
			}
		}
		.voice { return true }
		.rollout, .test_approval {
			// Rust debug_assertions are enabled in development builds. V uses -prod to disable them.
			$if prod {
				return false
			} $else {
				return true
			}
		}
		else { return true }
	}
}

// V uses a named pair because it cannot store Rust tuple values in an array.
pub struct BuiltInSlashCommand {
pub:
	name    string
	command SlashCommand
}

// Return all built-in commands in an array paired with their command string.
pub fn built_in_slash_commands() []BuiltInSlashCommand {
	mut commands := []BuiltInSlashCommand{}
	for command in SlashCommand.iter() {
		if command.is_visible() {
			commands << BuiltInSlashCommand{ name: command.command(), command: command }
		}
	}
	return commands
}

// strum::EnumIter derives a lazy iterator. V returns an owned array in the same declaration order.
pub fn SlashCommand.iter() []SlashCommand {
	return [.model, .ide, .permissions, .keymap, .vim, .elevate_sandbox, .sandbox_read_root,
		.experimental, .auto_review, .memories, .skills, .import_cmd, .hooks, .review, .rename,
		.new_thread, .archive, .delete_thread, .resume, .fork, .worktree, .app, .init, .compact,
		.recap, .plan, .voice, .goal, .agents, .side, .btw, .copy, .export_cmd, .raw, .diff, .mention,
		.status, .cd, .pwd, .usage, .debug_config, .title, .statusline, .theme, .pets, .mcp, .apps,
		.plugins, .logout, .quit, .exit, .feedback, .rollout, .ps, .stop, .clear, .personality,
		.test_approval, .multi_agents, .memory_drop, .memory_update]
}

// strum::EnumString derives FromStr and TryFrom<&str>. Both keep the input borrowed.
pub fn SlashCommand.from_str(name &string) !SlashCommand {
	return SlashCommand.try_from(name)
}

pub fn SlashCommand.try_from(name &string) !SlashCommand {
	return match *name {
		'model' { .model }
		'ide' { .ide }
		'permissions' { .permissions }
		'keymap' { .keymap }
		'vim' { .vim }
		'setup-default-sandbox' { .elevate_sandbox }
		'sandbox-add-read-dir' { .sandbox_read_root }
		'experimental' { .experimental }
		'approve' { .auto_review }
		'memories' { .memories }
		'skills' { .skills }
		'import' { .import_cmd }
		'hooks' { .hooks }
		'review' { .review }
		'rename' { .rename }
		'new' { .new_thread }
		'archive' { .archive }
		'delete' { .delete_thread }
		'resume' { .resume }
		'fork' { .fork }
		'worktree' { .worktree }
		'app' { .app }
		'init' { .init }
		'compact' { .compact }
		'recap' { .recap }
		'plan' { .plan }
		'voice' { .voice }
		'goal' { .goal }
		'agents' { .agents }
		'side' { .side }
		'btw' { .btw }
		'copy' { .copy }
		'export' { .export_cmd }
		'raw' { .raw }
		'diff' { .diff }
		'mention' { .mention }
		'status' { .status }
		'cd' { .cd }
		'pwd', 'cwd' { .pwd }
		'usage' { .usage }
		'debug-config' { .debug_config }
		'title' { .title }
		'statusline' { .statusline }
		'theme' { .theme }
		'pets', 'pet' { .pets }
		'mcp' { .mcp }
		'apps' { .apps }
		'plugins' { .plugins }
		'logout' { .logout }
		'quit' { .quit }
		'exit' { .exit }
		'feedback' { .feedback }
		'rollout' { .rollout }
		'ps' { .ps }
		'stop', 'clean' { .stop }
		'clear' { .clear }
		'personality' { .personality }
		'test-approval' { .test_approval }
		'subagents' { .multi_agents }
		'debug-m-drop' { .memory_drop }
		'debug-m-update' { .memory_update }
		else { return strum.ParseError{ kind: .variant_not_found } }
	}
}

// strum::AsRefStr returns the same static command name. The V string also references a literal.
pub fn (command SlashCommand) as_ref() string {
	return command.into_static_str()
}

// strum::IntoStaticStr selects to_string, explicit serialize, then the kebab-case variant name.
// All results are literals, so the Rust static lifetime requires no V allocation.
pub fn (command SlashCommand) into_static_str() string {
	return match command {
		.model { 'model' }
		.ide { 'ide' }
		.permissions { 'permissions' }
		.keymap { 'keymap' }
		.vim { 'vim' }
		.elevate_sandbox { 'setup-default-sandbox' }
		.sandbox_read_root { 'sandbox-add-read-dir' }
		.experimental { 'experimental' }
		.auto_review { 'approve' }
		.memories { 'memories' }
		.skills { 'skills' }
		.import_cmd { 'import' }
		.hooks { 'hooks' }
		.review { 'review' }
		.rename { 'rename' }
		.new_thread { 'new' }
		.archive { 'archive' }
		.delete_thread { 'delete' }
		.resume { 'resume' }
		.fork { 'fork' }
		.worktree { 'worktree' }
		.app { 'app' }
		.init { 'init' }
		.compact { 'compact' }
		.recap { 'recap' }
		.plan { 'plan' }
		.voice { 'voice' }
		.goal { 'goal' }
		.agents { 'agents' }
		.side { 'side' }
		.btw { 'btw' }
		.copy { 'copy' }
		.export_cmd { 'export' }
		.raw { 'raw' }
		.diff { 'diff' }
		.mention { 'mention' }
		.status { 'status' }
		.cd { 'cd' }
		.pwd { 'pwd' }
		.usage { 'usage' }
		.debug_config { 'debug-config' }
		.title { 'title' }
		.statusline { 'statusline' }
		.theme { 'theme' }
		.pets { 'pets' }
		.mcp { 'mcp' }
		.apps { 'apps' }
		.plugins { 'plugins' }
		.logout { 'logout' }
		.quit { 'quit' }
		.exit { 'exit' }
		.feedback { 'feedback' }
		.rollout { 'rollout' }
		.ps { 'ps' }
		.stop { 'stop' }
		.clear { 'clear' }
		.personality { 'personality' }
		.test_approval { 'test-approval' }
		.multi_agents { 'subagents' }
		.memory_drop { 'debug-m-drop' }
		.memory_update { 'debug-m-update' }
	}
}
