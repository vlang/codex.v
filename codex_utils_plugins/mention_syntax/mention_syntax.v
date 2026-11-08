module mention_syntax

// Sigils for tool/plugin mentions in plaintext (shared across Codex crates).

// Default plaintext sigil for tools.
pub const tool_mention_sigil = `$`

// Plugins use `@` in linked plaintext outside TUI.
pub const plugin_text_mention_sigil = `@`
