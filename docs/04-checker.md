# Kliner — checker (stage 4)

Roadmap stage 4 ([01-roadmap.md](01-roadmap.md)). Basis: Klin main
`a66ffbd` (#359: D20, D21, D22), checked 2026-10-24.

## What it does

`src/check/` (module `check`) is a port of Klin's `lib/checker.dart`
for the Kliner subset: the same passes in the same order and the same
**first error** (message and `line:col`), so `kliner-check` and Klin
can be compared byte for byte.

- **Loader** `src/load.kl` — port of `loadProject` (`lib/project.dart`):
  the entry file, its same-module siblings, imported packages (search
  roots `-I DIR`, `KLIN_PATH`, `KLIN_STDLIB`, as in Klin), the same file
  and declaration order and the same load errors (missing module,
  module name mismatch, import cycle, …). Remote imports are an error.
- **Declarations** `decl.kl` — collects structs, enums, consts,
  module `let` / `let mut`, functions and methods per module; duplicate
  names; constant expressions (128-bit `Big`, Klin's BigInt ranges);
  `[N]T` lengths; struct cycles and the "complete type" rules for
  arrays of structs (partial, see below); `main` signature (unless
  `--lib`).
- **Names** `resolve.kl` — scopes, `pub` / private across modules,
  `mod.name` for consts, globals, functions, structs and enums; types
  from AST type nodes.
- **Types** `src/types.kl` — interned types (`Tk`: prim, struct, enum,
  `*T` / `*mut T`, `[N]T`, `[]T`, `fn`, `!T`, untyped int, `[]`,
  bare `error`); equal types have equal ids.
- **Expressions** `expr.kl` — literals with the expected type
  (D12), operators, casts, calls, methods (`mut` receivers), field
  calls (D16), indexing and slicing (D15, D19), `b"…"` read-only
  bytes (D10, C8.1), `!T`, `!`, `or { }` (D21), `error(code)`.
- **Statements** `stmt.kl` — `let` / `let mut` (also struct and array
  destructuring), assignment and compound assignment, mutability
  (`cannot assign to …`), `match` (exhaustiveness of enums, arm order),
  `for` loops, `break` / `continue`, `return`, "missing return" via
  path analysis (`returns_all`, `stmt_diverges`).

State: one `Ck` reached through `*mut Ck`, no globals (C7.3). Facts that
Klin stores on AST nodes (`resolvedType`, `arrayByValue`, …) live in
per-file side arrays (`load.File.rt` type id per node, `load.File.fl`
flags). Errors: code `E_CHECK`, message in `Ck.msg`, position as file +
token.

## Tools

- `tools/kliner-check/` — `kliner-check [--lib] [-I DIR]... FILE`:
  prints `ok` (exit 0) or `L:C: message` (exit 1). `--lib` = no `main`
  required (Klin's `requireMain: false`).
- `tools/klin-check.dart` — the same output from Klin's
  `loadProject` + `Checker().check()` (built with the checkout's
  `.dart_tool/package_config.json`). Paths are dropped from the output
  on purpose: Klin prints the wrong file for errors in imported modules
  (bug K-B3 below).

## Tests and comparison (`scripts/test.sh`, stage 4 section)

- Goldens in `tests/check/` ([README](../tests/check/README.md)):
  `ok_*` / `err_*` (own cases), `mod_*/` (multi-module projects),
  `klin/` (277 snippets from Klin's `test/pipeline_*_test.dart` on which
  both checkers agree), `div_*` (known differences, Kliner's output).
- With `KLIN_SRC` set, `kliner-check` vs `klin-check` on:

| Set | Files | Equal | Expected differences |
|---|---|---|---|
| goldens (`tests/check`) | 347 | 347 | — (`div_*` skipped) |
| Kliner programs (`tools/*/main.kl`) | 7 | 7 | — |
| Kliner modules (`src/`, `rt/`, `--lib`) | 17 | 16 | 1 body-less `sys` fn |
| Klin checkout (all `.kl`) | 379 | 118 | 244 unsupported feature, 17 `$`-macro |

The snippet corpus (365 snippets): 278 agree; 48 use features Kliner
does not support; the rest are `$` macros, snippets needing files that
are not extracted, and the four late-typedef cases below.

## Known differences from Klin

| Case | Klin | Kliner | Test |
|---|---|---|---|
| `str` (also `main(args: []str)`), float types / literals, `pick`, `async fn`, `asm`, `volatile` | checked | ``X is not supported by Kliner yet`` at the first use (string interpolation: already the parser, stage 3) | `div_str`, `div_float`, `div_pick`, `div_async` |
| `cstr_u8(s)` (D22) | checked | always an error (needs `str`) | — |
| `$fn` / `$name(…)` | expanded before lexing | lexer error (C10, DECIDED) | tests/parse `err_33` |
| `fn` without a body in `module sys` | ``expected `{` `` | ok | `div_lib_sys` |
| "complete type" check for struct fields such as `[]*mut [2]Token` and an `fn` field returning an array of structs (Klin `error_175`, `error_207`–`209`) | error | ok — partial port; Kliner's backend has no C typedefs | `div_typedef` |
| remote imports `github/…` | fetched | load error | — |
| stdlib lookup | `KLIN_STDLIB`, upward from cwd, next to the binary | `KLIN_STDLIB` only | — |

## Klin bugs (not fixed, repros)

Found in stage 4 on `a66ffbd` (`klin FILE`):

- **K-B1** `puts` / extern calls are not type-checked against the C
  prototype; gcc fails:
  ```kl
  fn main() {
      puts(b"hi")
  }
  ```
  `klin: C compiler error (gcc): … incompatible type for argument 1 of 'puts'`.
- **K-B2** Misleading message for a struct cycle without arrays:
  ```kl
  struct A {
      b: B
  }
  struct B {
      a: A
  }
  fn main() {
  }
  ```
  ``5:5: field `a` needs `b43.A` to be complete (it contains an array of that struct)`` —
  no array is involved; the real error is a by-value cycle. Kliner
  prints the same text (port).
- **K-B3** (from stage 3, still open) diagnostics in an imported module
  carry the entry file's path; a parse error doubles the path
  (`main.kl:/abs/m.kl:2:10: …`).
- Proposals (behaviour, maybe intended): a constant out-of-range index
  on a fixed array passes and runs silently
  (`let a = [1, 2, 3]` / `return a[5]` → exit 0); a duplicate integer
  `match` arm (`1 { } 1 { }`) is accepted; duplicate enum values
  (`A = 1`, `B = 1`) are accepted. Kliner matches Klin in all three.

Still open from stage 3: `f()!` is not a statement and `let _` cannot
be repeated (pattern `ok = f()!`, DECIDED C11.4); `let mut x = b"fn"`
is rejected; load parse errors are reported at the import position.
