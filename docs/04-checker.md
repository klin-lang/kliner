# Kliner — checker (stage 4)

Roadmap stage 4 ([01-roadmap.md](01-roadmap.md)). Basis: Klin main
`f9f5471` (#360: K-B1, K-B2, K-B3, D23, D24, D25; before that #359:
D20, D21, D22), checked 2026-10-24.

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
  bare `error`, `str`); equal types have equal ids.
- **Expressions** `expr.kl` — literals with the expected type
  (D12), operators, casts, calls, methods (`mut` receivers), field
  calls (D16), indexing and slicing (D15, D19), `b"…"` read-only
  bytes (D10, C8.1), `!T`, `!`, `or { }` (D21), `error(code)`;
  `str` (D22, C12.3): `"…"` is `str`, `s.len` `i32` and `s[i]` `u8`
  (both read-only), no subslice, `cstr_u8(s)` a read-only `[]u8`,
  `main(args: []str)`.
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
  `klin/` (292 snippets from Klin's `test/pipeline_*_test.dart` on which
  both checkers agree), `div_*` (known differences, Kliner's output).
- With `KLIN_SRC` set, `kliner-check` vs `klin-check` on:

| Set | Files | Equal | Expected differences |
|---|---|---|---|
| goldens (`tests/check`) | 402 | 402 | — (`div_*` skipped) |
| Kliner programs (`tools/*/main.kl`) | 7 | 7 | — |
| Kliner modules (`src/`, `rt/`, `--lib`) | 17 | 16 | 1 body-less `sys` fn |
| Klin checkout (all `.kl`) | 379 | 245 | 117 unsupported (90 remote imports `github/…`; 27 features: `pick` 11, `f64` / `float` 8, interpolation 4, `async fn` 3, `volatile` 1), 17 `$`-macro |

Before `str` (C12.3) the checkout had 244 unsupported files and 118
equal: 127 files moved to equal, none to a difference.

The snippet corpus (365 snippets): 307 agree; 36 use features Kliner
does not support; the rest are `$` macros, snippets needing files that
are not extracted, and the four late-typedef cases below.

## Known differences from Klin

| Case | Klin | Kliner | Test |
|---|---|---|---|
| float types / literals, `pick`, `async fn`, `asm`, `volatile` | checked | ``X is not supported by Kliner yet`` at the first use (string interpolation: already the parser, stage 3) | `div_float`, `div_pick`, `div_async` |
| `$fn` / `$name(…)` | expanded before lexing | lexer error (C10, DECIDED) | tests/parse `err_33` |
| `fn` without a body in `module sys` | ``expected `{` `` | ok | `div_lib_sys` |
| "complete type" check for struct fields such as `[]*mut [2]Token` and an `fn` field returning an array of structs (Klin `error_175`, `error_207`–`209`) | error | ok — partial port; Kliner's backend has no C typedefs (DECIDED C12.1) | `div_typedef` |
| remote imports `github/…` | fetched | load error | — |
| stdlib lookup | `KLIN_STDLIB`, upward from cwd, next to the binary | `KLIN_STDLIB` only | — |

## Klin bugs (repros)

Found in stage 4 on `a66ffbd` (`klin FILE`); state on main `f9f5471`
(#360, checked 2026-10-24):

- **K-B1** (fixed in `f9f5471`) `puts` / extern calls were not
  type-checked against the C prototype; `puts(b"hi")` failed in gcc.
  Now a checker error (`` `puts` expects `str`, got `[]u8` ``, also
  for `printf`'s format); ported (`err_61`, `err_85`–`err_89`).
- **K-B2** (fixed in `f9f5471`) a by-value struct cycle without arrays
  was reported as ``field `a` needs `A` to be complete (it contains an
  array of that struct)``. Now ``struct cycle A -> B -> A has infinite
  size (store one of them behind a pointer)``; the old text stays for
  cycles through an array. Ported (`err_43`, `err_64`–`err_67`).
- **K-B3** (fixed in `f9f5471`) diagnostics in an imported module
  carried the entry file's path, and a lexer/parser error doubled the
  path (`r7.kl:/tmp/sp/r7.kl:2:9: …`). Now `r7.kl:2:9: …` and
  `/path/m/m.kl:2:12: …`. (kliner-check prints `L:C:` only.)
- **K-B4** (still open in `f9f5471`) a zero-initialised `str` is a
  NULL `const char *`; `s.len` (`strlen`), `s[i]` and `cstr_u8(s)` then
  crash (SIGSEGV, exit 139). The checker accepts it:
  ```kl
  fn main(): i32 {
      let s: str
      return s.len
  }
  ```
  Same with a `str` struct field of a zeroed struct (`let t: T` /
  `t.name.len`) and a global `let mut g: str`. Expected: either `""` as
  the zero value of `str`, or a checker error for a `str` without an
  initializer. Kliner matches Klin's checker (ok).
- **K-B5** (stage 5, still open in `f9f5471`; earlier also called
  K-B4) narrow-integer arithmetic is not wrapped to its type (`u8`
  `129 << 1` is 258): repro in
  [05-ir.md](05-ir.md#differences-from-klin-klin--c--gcc). Marek
  reports it to the Klin bot.
- Former proposals, now errors in Klin `f9f5471` and ported:
  **D23** a constant out-of-range index on a fixed array
  (``index 5 is out of range for `[3]i32` ``; `err_60`, `err_70`–`err_73`);
  **D24** an unguarded `match` arm matching the same values as an
  earlier one (``duplicate `match` pattern …``; `err_62`,
  `err_77`–`err_81`, `ok_63`); **D25** duplicate enum values
  (``duplicate enum value 1 (`B` and `A`)``; `err_63`, `err_68`, `err_69`).

Fixed from stage 3 (Klin `f9f5471`, ported): `f()!` is a statement
(not in `main`: ``postfix operator `!` cannot be used in `main` ``) and
the `ok = f()!` workaround is gone (C11.4); `let _` can be repeated
(the value is still evaluated; a `!T` value must be handled);
`let mut x = b"fn"` is accepted — the binding can be reassigned, but
writing through it is an error (``cannot assign through read-only
bytes …``; `err_45`, `str_09`, `str_24`, `str_32`, `err_90`–`err_93`);
load parse errors are reported in the imported file.
