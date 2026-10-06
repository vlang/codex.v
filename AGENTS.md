# Codex Rust-to-V translation rules

This repository is a source-faithful V port of the Rust workspace at
`/Users/alex/code/3rd/codex/codex-rs`. Compile translated code with V's optional ownership
checker (`v -ownership`).

## Translating a Rust file

1. Read the entire requested Rust file, its applicable `AGENTS.md` files, and any directly
   referenced source needed to understand signatures or behavior. Do not translate from a symbol
   list alone.
   Before editing, inventory the source's functions/methods, declarations, tests, and comment lines;
   use that inventory as a completion check after translation.
2. Map the Rust crate and module path to matching V directories. For example,
   `tui/src/bottom_pane/chat_composer.rs` becomes
   `codex_tui/bottom_pane/chat_composer.v`, whose module is `bottom_pane`.
3. Translate every declaration and implementation in the requested file: constants, aliases,
   structs, enums, trait implementations, free functions, methods, helper functions, and tests.
   Preserve declaration order where V permits it. Do not replace target-file logic with stubs.
4. Translate every source comment and doc comment next to the code it documents. Preserve TODOs,
   safety notes, invariants, state-machine explanations, compatibility notes, and test rationale.
   Rust-only wording may be adjusted only enough to describe the equivalent V code accurately.
   Do not move comments into a detached source-line ledger; a comment archive is not a substitute
   for documenting the translated declaration, branch, or test in place.
5. Preserve behavior, visibility, defaults, validation, serialization names, error paths, ordering,
   and side effects. Use explicit V tagged representations when a Rust enum's payload variants do
   not map cleanly to a V sum type. Do not silently omit fields or branches.
6. Translate tests from the source file. Tests that require an untranslated runtime may use the
   smallest faithful stub boundary, but pure state transitions, parsing, formatting, validation,
   and serialization must remain executable tests.
   Preserve each test's actual setup and assertions. Do not keep only the Rust test names while
   routing them through a generic smoke test or through behavior selected from the test-name text.
   Shared test helpers are appropriate only when the source tests genuinely share that behavior.
   Copy any source fixtures needed by translated tests into this repository (or encode an exact
   local oracle). Translated tests must not depend at runtime on an absolute path into the Rust
   checkout.

## Ownership mapping

- Rust owned parameters (`String`, `Vec<T>`, `PathBuf`, owned structs, and `self`) are V value
  parameters and are consumed under `v -ownership`.
- Rust shared borrows (`&T`, `&str`, `&Path`, and `&[T]`) are V references (`&T`, `&string`, and
  `&[]T`). Dereference explicitly where V requires `*value` for matching, slicing, interpolation,
  or passing to a value-only standard-library API.
- Rust mutable borrows (`&mut self` and `&mut T`) become `mut` receivers or `mut` parameters.
- Rust `Copy` scalars and enums stay by value. Do not add references that only emulate Rust syntax
  without preserving an ownership-bearing value.
- Clone only at the same semantic boundary as Rust `.clone()`, `.to_owned()`, `to_string()`, or an
  owned return assembled from borrowed data. Prefer constructing the owned result explicitly so
  the clone boundary is visible to the ownership checker.
- V has no borrowed string-slice return equivalent to Rust `&str`. Borrow the input, return an owned
  V `string`, and document the unavoidable allocation/lifetime adaptation when it is material.
- For Rust `&Option<T>`, prefer a safe V borrowed wrapper when `T` owns resources. V currently cannot
  reliably construct `&?T`, while `?&T` can fail in V3 C generation. An optional value is acceptable
  only when `T` is allocation-free/Copy-equivalent; document the adaptation and prove the caller's
  value remains reusable in an ownership test.
- Add focused tests that create strings with `.to_owned()` in an `$if ownership ?` branch, call
  borrowed APIs more than once, and use the owner afterward. A normal build and an ownership build
  must both compile.

## Untranslated dependencies and stubs

- Translate calls to declarations from other Rust modules using their eventual V module path.
- Before declaring a dependency type, search the V tree for its translated owner and reuse that
  type. Do not serialize a translated enum or struct into a string merely to simplify a stub.
- If the dependency has not been translated, create the smallest compiling declaration in the
  corresponding V submodule. Every stub declaration and stub function must have a leading
  `// STUB:` comment explaining its eventual source owner or missing behavior.
- A stub must preserve the real call signature, ownership direction, result/error shape, and fields
  observed by the translated file. It must not pretend to implement behavior it cannot provide.
- Keep the target file calling the dependency's eventual public API. Do not replace an untranslated
  method chain with reads or writes to public fields added only for a test double. If executable
  tests need an in-memory implementation, put that behavior behind the source-shaped stub API.
- Preserve builder operations, query text, bind order, pagination calls, and transaction boundaries
  at the target call site. A stub may emulate their result, but the translated function must still
  expose the same dependency calls and ordering as the Rust source.
- Do not collapse unrelated dependency calls into a universal operation-name/string-payload shim.
  Create typed declarations for the individual dependency APIs so later translations can replace
  them without changing the target file's call sites.
- Search the V tree before adding a stub. Reuse compatible existing types and functions. When
  parallel translations need the same dependency module, use target-specific stub filenames and
  avoid redefining a symbol already present elsewhere in that module.
- Never mark code originating in the requested target file as `// STUB:`. Stubs are only for
  untranslated external modules.

## Validation and handoff

1. Compare the finished V surface against the pre-translation inventory. Account for renamed or
   merged declarations explicitly and confirm no target-owned function was replaced by a stub.
2. Format every changed V file with `v fmt -w` and finish with `v fmt -verify .`.
3. Run executable module tests with `v test <module-directory>`.
4. Compile the translated test entry (or a small ownership harness when the source has no tests)
   with `v -ownership -o <temporary-output> <entry.v>`. `v -ownership test` is not supported by the
   current compiler; a direct compile still runs ownership analysis.
5. Remove temporary outputs. Do not remove editor swap files or unrelated user changes.
6. Report any unavoidable V language/compiler adaptation explicitly; a successful non-ownership
   build alone is not completion.
7. Commit completed changes before handoff. Stage only the task's changes and preserve unrelated
   working-tree and staged changes.

## Parallel translation

- Assign one requested Rust file and its matching V module to one agent. Agents must not edit the
  same target implementation file.
- Put shared-module dependency shims in target-specific files such as
  `codex_core/<target>_stubs.v`; search the whole module first to prevent duplicate declarations.
- After parallel work completes, the integrating agent resolves duplicate stubs, runs every module
  test independently, then runs repository-wide formatting and ownership compilation. A module is
  not accepted merely because another parallel module compiles.
