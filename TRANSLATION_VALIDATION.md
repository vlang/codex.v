# Translation validation

The latest batch translates these Rust TUI files, including all declarations,
comments, and the four original tests in the included test modules:

| Rust source | V module | Executable tests |
| --- | --- | ---: |
| `tui/src/shimmer.rs` | `codex_tui/shimmer` | 7 |
| `tui/src/approval_events.rs` | `codex_tui/approval_events` | 16 |
| `tui/src/backend_banners.rs` | `codex_tui/backend_banners` | 12 |
| `tui/src/session_start.rs` | `codex_tui/session_start` | 9 |

## Compiler setup

Validation uses V `e690943e7191bb2309a418245bdbf9003031fc1d` with its matching
compiler sources and standard library. The installed compiler reports that version,
but the active V source checkout has advanced. Its ownership compiler rejects
string reuse inside `json2`, `time`, and `toml`. An isolated, unmodified checkout of
the installed version permits full ownership checking without suppressing library
diagnostics. A negative test confirms that consuming a heap-owned string and then
using its owner fails ownership analysis.

To reproduce the isolated setup with the installed V binary:

```sh
PORT_V_SRC=/Users/alex/code/v
PORT_V_PIN=$(mktemp -d /tmp/codex-v-validation.XXXXXX)
git -C "$PORT_V_SRC" archive e690943e7191bb2309a418245bdbf9003031fc1d | tar -x -C "$PORT_V_PIN"
cp "$PORT_V_SRC/v" "$PORT_V_PIN/v"
mkdir -p "$PORT_V_PIN/thirdparty/tcc/lib"
cp "$PORT_V_SRC/thirdparty/tcc/lib/libgc.a" "$PORT_V_PIN/thirdparty/tcc/lib/libgc.a"
export VEXE="$PORT_V_PIN/v"
```

The copied GC library is a build artifact needed by the formatter and test runner.
Ownership entries use `-gc none` because the existing TOML boundary combines raw
allocation with frees that are incompatible with the GC allocator. No compiler or
standard-library source is patched. The unused legacy `json2/count.v` generic helper
is excluded because this compiler cannot check its unspecialized `val.variants`;
the JSON parsing and encoding exercised by the tests remain included.

Run normal module tests and compile each test entry in both ownership modes:

```sh
for PORT_MODULE in shimmer approval_events backend_banners session_start; do
    VJOBS=1 "$VEXE" -new-compiler -cc clang -exclude @vlib/json2/count.v test "codex_tui/$PORT_MODULE"
    PORT_ENTRY="codex_tui/$PORT_MODULE/${PORT_MODULE}_test.v"
    PORT_OUTPUT=$(mktemp /tmp/codex-v-ownership.XXXXXX)
    "$VEXE" -new-compiler -cc clang -exclude @vlib/json2/count.v -gc none -ownership -skip-running -o "$PORT_OUTPUT" "$PORT_ENTRY"
    "$PORT_OUTPUT"
    "$VEXE" -new-compiler -cc clang -exclude @vlib/json2/count.v -gc none -ownership -d ownership -skip-running -o "$PORT_OUTPUT" "$PORT_ENTRY"
    "$PORT_OUTPUT"
    rm -f "$PORT_OUTPUT"
done
"$VEXE" fmt -verify .
```

Assertions remain enabled. Each ownership executable runs the complete target test
file, including focused heap-owner reuse tests. Temporary validation outputs are
removed after the checks.

## Translation boundaries

Shimmer returns owned rune strings from borrowed input and uses a mutex for Rust's
lazy process-wide `OnceLock`. Float remainder uses `fmod`, and padded positions use
widened signed arithmetic. Terminal color detection remains an explicit dependency
stub; deterministic rendering tests cover both RGB and fallback styling.

Approval events use tagged owned options and borrowed views for resource-bearing
optional payloads. Clone implementations copy string buffers at Rust's clone
boundaries. The existing buffered JSON dependency can report malformed JSON syntax
before an earlier typed-field error. Its untranslated absolute-path base guard is
also explicitly marked at the dependency boundary. Owned optional temporaries use
explicit presence flags and concrete backing constructors while keeping the public
aliases. Visitor guards avoid early `continue` paths that can prematurely drop
retained accumulators in this compiler's ownership code generation.

Banner parsing preserves Rust's UTF-8 byte limits, whitespace, line, and control
character rules. A borrowed decimal decoder preserves integer ranges and float
exponents while avoiding the older standard parser's string-alias cleanup under
ownership. Its render dependency implements the original tests' ordered
`view_usage` label projection; other actions fail explicitly pending translation.

Session startup retains confirmation, unarchive, retry-by-ID, cancellation, and
error ordering. Async APIs use synchronous typed boundaries. The original integration
tests create and move real local rollout files through a transport fixture; native
app-server networking, SQLite, and history hydration remain untranslated. Fixture
error observations use immutable borrowed receivers so repeat calls retain their
configured failures in ownership builds.
