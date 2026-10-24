# Kliner — core subset and runtime (stage 1)

Roadmap stage 1 ([01-roadmap.md](01-roadmap.md)). Decisions this builds
on: [00-decisions.md](00-decisions.md) K2 (bootstrap), K4 (compatibility),
K6 (stdlib).

Two questions:

1. **Which Klin features form the core** — the subset the Kliner
   compiler is written in, and which Kliner supports from day one?
2. **What is the minimal runtime** on Linux syscalls?

Basis: [klin-lang/klin](https://github.com/klin-lang/klin) main at
`d7625f1` (2026-10-24; earlier probes on `824e4af` and `757b782`, Klin 0.1.4) —
`docs/` (decisions D1–D19), `lib/` (lexer, parser, checker, types),
`stdlib/`, `test/`, `examples/`. Every "bootstrap risk" below marked
*probed* was checked by compiling a small program with that Klin
(Dart 3.13.7 → C → gcc); the C6 and C7 snippets were re-probed with
`824e4af` on 2026-10-24, and `rt/` builds and passes `scripts/test.sh`
on `d7625f1`.

Status: C1–C4 and C6 **PROPOSED**. The five stage-1 questions are
**DECIDED (2026-10-23)** — see [C7](#c7-decisions--decided-2026-10-23).
Four review questions (read-only bytes, literal range, literal typing,
runtime API) are **DECIDED (2026-10-23)** — see
[C8](#c8-review-decisions--decided-2026-10-23). Questions opened by the
sync with Klin main are in
[C9](#c9-sync-with-klin-main--proposed) (**PROPOSED**, Marek decides).
The stage 3 review (C10, the AST model, the roadmap numbering) is
**DECIDED (2026-10-24)** — see [C11](#c11-stage-3-review--decided-2026-10-24).
The stage 5 IR choices are in [C13](#c13-stage-5-ir--proposed)
(**PROPOSED**, Marek decides).

The Klin changes the compiler source relies on are **merged into Klin
main**: [#351](https://github.com/klin-lang/klin/pull/351) to
[#356](https://github.com/klin-lang/klin/pull/356) (table in C5).
[#357](https://github.com/klin-lang/klin/pull/357) (`a7e49ac`) and
[#358](https://github.com/klin-lang/klin/pull/358) (`d7625f1`, G13, D19)
are merged too; the runtime in `rt/` uses #358.

---

## C1. Rule for the core — PROPOSED

A feature is **IN core** when all three hold:

- the compiler needs it (or it costs almost nothing to support),
- current Klin compiles it correctly today (or the fix in Klin is small),
- it lowers to the IR (K9) without a runtime beyond C6.

**LATER** = useful, valid Klin, but not needed to self-host.
**NOT IN KLINER** = C-specific; Kliner gives a clear error (K4).

Kliner from day one must accept every IN-core feature, because its own
source uses them (stage2 == stage3).

---

## C2. IN core

Risk column = risk that current Klin (Dart → C) **cannot build** the
compiler written with this feature. `low` = used in Klin tests/examples
and probed OK.

| Feature | Klin form | Bootstrap risk | Notes |
|---|---|---|---|
| Integers | `i8`…`i64`, `u8`…`u64`, `usize`/`isize`, `int` = `i32` | low | Widths matter (K8). `u64` literals and shifts probed OK. A literal, unary `-` / `~` on it, and an integer constant expression take the expected type (D12, C8.3): `f(-1)` for an `i64` param, `r >= -4095` with `r: i64`, `let x: i64 = 1 << 40`. An out-of-range literal is a compile error (`let x: u8 = 300`, D12, C8.2). With no expected type it is still `i32` (`let x = 1 << 40` → shift wider than `i32`). `match` / `pick` arms adopt it too (`let x: u8 = match k { 0 { 1 + 2 } else { 5 } }`, #357). `xs.len` is `i32` |
| `bool` | `true` / `false`; `if` wants `bool` | low | No numeric truthiness |
| Literals | `0xFF`, `0b1010`, `0o755`, `1_000`, `'A'` | low | Char literal is an integer — the lexer lives on these. An array literal takes the element type from context: `let a: [2]u8 = [65, 66]` (D12) |
| Numeric `cast` | `cast(i64, x)`, `cast(u8, 300)` | low | No implicit widen/narrow — good for IR widths |
| Operators | arithmetic, bitwise (D8), `&&` / `\|\|` (D9), compound `+=` … | low | Rust-like precedence |
| `let` / `let mut` / `:=` | | low | ZII: zeroed when no initializer (D6) |
| Control flow | `if` / `else if` / `while` / `for i in a..<b` / C-style `for` / `break` / `continue` / `return` | low | |
| `match` on integers and enums | value groups, `a..=b`, relational arms, `when`, `else` | low | Lexer/parser dispatch. Probed: `match c { 48..=57 {…} 32, 10 {…} < 32 {…} _ when x > 3 {…} else {…} }` |
| `enum` (named integer) | `enum Tok: u8 { … }`, `Tok.Ident`, `cast(u8, Tok.Ident)` | low | Enum fields (`struct T { k: Tok }`) build since #351 (G2) |
| `struct` + methods | `fn (v: T) f()`, `fn (mut v: T) f()`, `fn T.new(): T` called as `T.new()` / `mod.T.new()` | low | Nested structs and `[N]T` fields probed OK. A `mut` method accepts any mutable place, including through `*mut`: `(*c).err.lit(b"x")`; `&(*c).err` is `*mut Out` (G11, D5) |
| Fixed arrays | `[N]T`, `xs[i]`, `xs.len`, `[N]Struct` | low | Arrays of structs probed OK. The length may be an integer constant expression (`[BUF]u8`, `[N * 2]T`, D11). A function may return `[N]T` (D13) |
| Slices | `[]u8`, `[]i64`, `[]Token`, `[][]u8`, `xs[:]`, `xs[a:b]`, `xs[a:]`, `xs[:b]`, `xs.len` | low | Any value element: struct, `str`, slice, pointer, function pointer (D14, G3); not `[]!T`, `[]void`, `[][N]Struct`. Subslices have no bounds check (D15, G6). Writes follow the place (D5, G4): `let mut s = xs[:]` can write; an immutable binding or a slice parameter cannot (`cannot assign through an immutable slice`) — copy the header first (`let mut w = dst`) |
| Pointers | `*T` / `*mut T`, `&x`, `*p`, `(*p).f` | low | Self-reference (`struct Node { next: *mut Node }`) builds since #351 (G1). `cast` between a pointer and an integer goes through `uintptr_t` / `intptr_t` (D17, G9); `str` is not a pointer for `cast` |
| `!T` errors | `!T`, `error(n)`, `expr!`, `or { }`, `err` | low | `!Struct`, `![]u8` probed OK. Errno maps 1:1 to `error(n)` (C6). `!` across `!T` types (`a()!` with `a(): !i64` inside a `!i32` function) builds since #351 (G12). An `or { }` block must end in a value — no `return` inside — so `main` calls `fn run(…): !i32` and does `let code = run(…) or { …; 1 }` |
| `defer` | block-scoped, LIFO | low | Covered by Klin goldens (`defer_*`) |
| Modules | `module`, `import`, `import path alias`, `pub` | low | Search paths `-I` are used for target selection (C6) |
| `$fn` generics | `$fn vec(name: name, T: type) { struct $name { data: [8]$T … } }`, `$vec(VecI32, i32)` | medium | Probed OK. Parameters are spliced with `$` (`$T`, `$name`). A free `fn` inside the body is declared once per expansion → `redeclaration of function` on the second `$vec(…)`; use methods on `$name`. Risk: error messages inside expansions. Use only for a few container shapes |
| Function pointers | `fn(T): R`, no capture | low | `h.cb(1)` calls a function field (D16, G7); a method of the same name is an `ambiguous call` error |
| Destructuring / multi-assign | `let { x, y } = p`, `a, b = b, a` | low | Optional; lowers to plain moves. Array destructuring is in C3 |
| Byte-string literal | `b"fn"` of type `[]u8` | low | Merged in #351 (G5, D10). Keyword table, messages, paths: `b"fn"`, `b"error: "`. Rules: `.len` counts bytes, no implicit trailing NUL (`b"/proc/self/cmdline\0"` has len 19); escapes `\n \t \\ \" \$ \0`; `\0` is one NUL byte, not octal (`b"\00"` = NUL + `'0'`); no interpolation. Bytes are read-only (C8.1): a direct write, a write through an immutable binding and a write through a `[]u8` param are checker errors; since #357 binding or assigning `b"…"` to a `let mut` slice is a checker error too (`let mut s = b"fn"`, `s = b"ab"`). Still UB: bytes that reach a mutable binding through a parameter or a return (`let mut t = id(b"fn"); t[0] = 1` compiles and crashes) |
| Module-level `const` | `const PAGE: i64 = 4096` | low | Merged in #351, extended in #352–#353 (G8, D11). `pub? const Name: Type = expr`, top level only. Types: integer prims, `bool`, `[]u8`. An integer initializer is an integer constant expression (literals, unary `-` / `~`, `+ - * / % << >> & \| ^`, other constants, `mod.NAME`); overflow is an error, not a wrap. Valid as an `[N]T` length (`[BUF]u8`). Imported as `mod.NAME` (`os.AT_FDCWD`). Immutable: `NAME = …` and `KW[0] = …` are errors; a local shadows a const |
| Module-level `let` / `let mut` | `let mut hits: i32`, `pub let mut n: i32 = 1` | low | Merged in #356 (D11). Type required; the initializer is a constant expression or omitted (zeroed); private = `static` in C; another module writes only a `pub let mut`. **Not used by the compiler source** while C7.3 stands — option in C9.1 (PROPOSED) |
| Strings for the compiler | `[]u8`, subslices, `i32` offsets in tables | low | All source text, identifiers and output buffers are `[]u8`; literals are `b"…"`; a token's text is `src[start:start + len]` (G6). `str` is not used in compiler code |

### Data model — PROPOSED

Klin has no tagged unions (payload enums are "not in the language",
`syntax.md`). Self-referential pointers (G1) and slices of structs (G3)
build on Klin main, but the table model stays the choice — it is the
fastest and simplest:

- **Compiler state in one context struct** passed as `*mut Ctx` (C7.3).
  Fixed values are module-level `const`. Fields are updated in place
  (`(*c).n = …`, `(*c).toks[i].kind = …`). Sub-structs are held by value
  and reached as places: `(*c).err.lit(…)`, `&(*c).arena` is
  `*mut arena.Arena` (G11). Module-level `let mut` now exists in Klin;
  whether Kliner uses it is open — C9.1 (PROPOSED).
- **Tables, not trees of pointers.** Tokens, AST nodes, types, IR ops
  live in arrays; references are `i32` indices.
- A table is a slice of structs (`toks: []Token`, `nodes: []Node`, G3).
  A node = `kind: u8` + a few `i32` fields (`a`, `b`, `c`, `extra`).
  Variable-length children go into a side array `[]i32` (start + count),
  read as a subslice `kids[start:start + count]` (G6).
- Growing tables = allocate a bigger slice and copy.

This is the Zig / Carbon "data-oriented AST" layout. It also makes
stage2 == stage3 easier: no pointer values end up in output.

### AST — DECIDED (2026-10-24, C11.2)

The stage 3 parser follows the data model above (`src/ast.kl`):

- `Node {kind: Nk, tok, a, b, c, extra: i32}` in `nodes: []Node`;
  children lists in `kids: []i32` as a count followed by the items (a
  list field holds the index of the count). Lists are built on a
  scratch stack and copied to `kids` when complete, so nested lists
  never interleave. Both tables double when full.
- **`tok` is one field more than `{kind, a, b, c, extra}`:** the index
  of the token whose `line:col` Klin reports for the node. Without it
  most kinds would spend one of `a`/`b`/`c` on the position, and a few
  (`Call`, `ForC`, `Let`) would need an extra list. Names are never
  copied: a name is the text of its token. Alternative: no `tok`, the
  position in `a` where needed — smaller nodes (20 instead of 24
  bytes), more irregular layouts. **Decided: keep `tok`** (C11.2).
- Types are nodes (`TName`, `TPtr`, `TSlice`, `TArray`, `TErr`,
  `TFn`); an array length keeps its token range for the checker.
- A declaration is wrapped in `Decl` (attributes, `pub`, `async`).
- Parser state is a struct reached as `*mut Parser` (lexer, AST,
  arena, diagnostics, flags such as "no struct literal here"); no
  globals (C7.3).
- Diagnostics (`src/diag.kl`, shared by the lexer and the parser):
  `Diag {path, src, lines, failed, off, msg, note}`; the first error
  wins (Klin's parser stops there too); printed as
  `path:line:col: message` plus an optional `note:` line. Lexer and
  parser messages are Klin's text, so the comparison can be exact;
  explanations for features Kliner does not have yet go to the note.

---

## C3. LATER

| Feature | Why later |
|---|---|
| `float` / `f32` / `f64` | The compiler does not need floats. Add with SSE2 / FP regs in stage 7+ |
| `pick` | Sugar over `if`; trivial once `match` exists |
| String interpolation `"$x"` / `${e}` | Lowers to `printf` / `snprintf` in Klin. Kliner needs its own formatter first |
| `printf` / `puts` builtins | libc. Kliner maps `puts(str)` to `out` (C6); full `printf` later or never |
| `fmt.write`, `time`, `math`, `slice`, `slice_alloc` (stdlib) | Rewritten as Kliner stdlib on syscalls (K6) |
| `async fn` / `.await` | Needs an executor; not needed for the compiler |
| `volatile` | MCU-oriented; harmless to add later |
| Destructuring of arrays `let [a, b] = xs` | Optional sugar. From an array variable or literal on Klin main; and from a call (`let [x, y] = pair()`, #357) |
| `@[cexport]`, `--emit-h` | Only with C interop (K7) |

---

## C4. NOT IN KLINER

Kliner reports a clear error, e.g.
`error: 'cimport' is not supported by Kliner (C-only, see docs/02-core-subset.md)`.

| Feature | Why |
|---|---|
| `@[cimport]`, `@[cheader]`, `@[cinclude]`, `@[codename]` | Import from C headers. Replaced later by `extern fn` (K7) |
| `asm("…")` | Becomes GNU inline `asm volatile` in C; Kliner has no inline assembler |
| `@[link]` with `.c` / `.s` / `.S` / `.a` / `-l` | External toolchain. `.o` + system linker only with K7 |
| `@[isr]` | Interrupt vectors — MCU only (K3) |
| `#line` | Artifact of C emission. Kliner gets DWARF `.debug_line` instead (K10) |
| SVD register access, board packs (`klin init`), `machine_*` | MCU only |
| `puts` / `printf` without declaration | libc builtins (see C3 — `puts` mapped, `printf` not) |

---

## C5. Gaps in Klin found by probes

These mattered because the compiler source must build with current Klin.
All of G1–G13 are **fixed on Klin main** (`d7625f1`, checked 2026-10-24
with `git log` and probes); the workarounds are gone from this document.
The "was" column is the result on `757b782`.

| # | Probe | Was | Now on Klin main | PR / merge commit |
|---|---|---|---|---|
| G1 | `struct Node { next: *mut Node }` | C error: incompatible pointer type (anonymous typedef) | Builds (named struct tag); test `test/self_ref_struct.kl` | #351 `76e1eb9` |
| G2 | `struct T { k: Tok }` (enum field) | `unknown type 'Tok'` | Builds | #351 `76e1eb9` |
| G3 | `[]Token`, `[]str`, `[][]u8` | `slice requires a primitive element type` | Any value element (D14). Still errors: `[]!T`, `[]void`, `[][N]Struct` (`rows[:]` of `[N][M]Token`) | #355 `824e4af` |
| G4 | `let s = xs[:]; s[0] = 7` | C error: `request for member 'ptr'` | Fixed. A write through an immutable binding or a slice param is now a checker error (`let mut s = xs[:]` writes, D5) | #351 `76e1eb9`, #353 `b7e8894`, #354 `db6bd2e` |
| G5 | `take("abc")` where `take(s: []u8)`; `"abc".len` | `str` is a C string pointer: no `.len`, no indexing | Byte-string literal `b"fn"` of type `[]u8` (D10, rules in C2) | #351 `76e1eb9` |
| G6 | `xs[1:3]` | parse error — only `xs[:]` | `xs[a:b]`, `xs[a:]`, `xs[:b]`; no bounds check, out of range is UB (D15) | #355 `824e4af` |
| G7 | `h.cb(1)` on an `fn` field | parsed as method call | Calls the field (D16) | #355 `824e4af` |
| G8 | top-level `let N: i32 = 3` | parse error — no globals / consts | `const` (#351), constant expressions and `[N]T` length (#352, #353), module-level `let` / `let mut` (#356) — D11 | #351 `76e1eb9`, #352 `eccb0e1`, #353 `b7e8894`, #356 `1282b1a` |
| G9 | `cast(usize, &x)` | `numeric cast requires an integer or float` | Via `uintptr_t` / `intptr_t` (D17). `cast(i64, s)` on a `str` is still that error | #355 `824e4af` |
| G10 | no `argc` / `argv` | `main()` takes no arguments | `fn main(args: []str)`, `args.len` = `argc` including `argv[0]` (D18). Elements are `str` — see C9.2 | #355 `824e4af` |
| G11 | `(*c).err.lit(b"x")`; `&(*c).err` | `mutating method requires a mutable variable`; `*Out`, not `*mut Out` | A `mut` method accepts any mutable place, through `*mut` too; `&place` is `*mut T` on a mutable place (D5) | #352 `eccb0e1` |
| G12 | `let w = a()!` with `a(): !i64` inside `fn f(): !i32` | C error: `klin_res_i64` from a `klin_res_i32` function | Builds; test `test/propagate_cross.kl` | #351 `76e1eb9` (`d3394e4`) |
| G13 | `let p = cast(*mut [8]u8, addr)` then `(*p)[:]` / `(*p)[0:n]` | Passes the checker, broken C (`uint8_t *` from `uint8_t`; struct element: `invalid operands to binary +`) | `(*p)[:]`, `[a:b]`, `[a:]`, `[:b]`, `(*p)[i]` for every slice element type; `*mut [N]T` is a mutable place, `*[N]T` immutable (D19). Probed with `u8`, a struct and `[]u8` elements | #358 `d7625f1` |
| — | `[65, 66]` as `[2]u8` initializer | typed as `[2]i32` | Takes the element type from context (D12) | #353 `b7e8894` |
| — | `const X: u8 = 300`, `let x: i64 = -1`, `1 << 40` as `i64` | silent wrap; `-1` / `~7` / `1 << 40` are `i32` | Range error; unary `-` / `~` and constant expressions take the expected type (D12; C8.2, C8.3) | #352 `eccb0e1`, #353 `b7e8894`, #354 `db6bd2e` |

Still open on Klin main (probed on `d7625f1`, updated for `a66ffbd`), none blocking:

- ~~An `or { }` block must end in a value (`or { return }` is an
  error).~~ Fixed in #359 `a66ffbd` (D21: `or { return … }`, `break`,
  `continue`); the checker uses it.
- ~~A free `fn` inside a `$fn` body is declared once per expansion
  (`redeclaration of function`).~~ Fixed in #359 (D20: unique helper
  names per expansion).
- `str` cannot be cast to an integer; since #359 (D22) it has
  `s.len`, `s[i]` and `cstr_u8(s)`. Kliner's checker supports `str`
  since stage 4 (C12.3); compiler code still uses `[]u8`.
- `b"…"` reaching a mutable binding through a parameter or a return is
  still UB (C8.1).

Found while writing the parser (stage 3, Klin `d7625f1`), none blocking:

- `f()!` is not a statement (``expected assignment `=` or call``), and
  `let _ = f()!` twice in a scope is ``redeclaration of `_` ``. The
  parser uses `let mut ok = 0` once per function and `ok = f()!`.
- `let mut x = b"fn"` is a checker error even if `x` is only
  reassigned, never written through (`cannot bind read-only bytes to a
  mutable slice`). Workaround: `src[0:0]` as the empty start value, or
  a table lookup.
- Diagnostics in an imported module carry the wrong file: a checker
  error in `m.kl` prints `main.kl:3:12: …`, a parse error prints
  `main.kl:/abs/path/m.kl:2:10: …` (two directories `a/`, `b/` with
  `module m` + `main.kl` importing it; `return true` in an `i32` fn,
  resp. a parameter named `module`).
- Language behaviour to know (not a bug): only `*` and a call's `(`
  must be on the operator's line. `log(err)` followed by `-1` on the
  next line is `log(err) - 1`, and `xs` followed by `{ x, y } = p` on
  the next line is a struct literal `xs{ x, y }`
  (`tests/parse/ok_lines.kl`).

---

## C6. Runtime — PROPOSED

The compiler needs: memory, read a whole file, write a file, print
bytes and integers, exit with a code, its own arguments. Nothing else.

### Two implementations, one API

The same modules must work in **stage1** (built by Klin, linked with
libc) and in **stage2+** (built by Kliner, no libc). Selection uses the
existing Klin `-I` search path — no conditional compilation:

```
rt/
  os.kl                 module os      portable: open/read/write/close, file size, read_file, exit, args
  arena.kl              module arena   bump allocator over sys.map / sys.unmap
  out.kl                module out     buffered stdout/stderr: bytes, str literal, i64, newline
  linux_x86_64/sys.kl   module sys     Kliner only: syscall numbers + intrinsics
  linux_arm64/sys.kl    module sys     later (generic numbers)
  linux_rv64/sys.kl     module sys     later (generic numbers)
  bootstrap/sys.kl      module sys     Klin only: same API over libc (`@[cimport]` + small shim)
  bootstrap/shim.c      klrt_syscall6 only (linked by `@[link]`, bootstrap only;
                        may depend on Klin's C layout of []T — decided, C7.5)
```

```sh
klin   run -I rt/bootstrap    -I rt src/main.kl     # stage1
kliner     -I rt/linux_x86_64 -I rt src/main.kl     # stage2+ (target dir added by kliner)
```

`os`, `arena`, `out` are written in the core and are identical in both
stages. Only `sys` differs. `bootstrap/sys.kl` uses `cimport` — allowed,
because Kliner never compiles it (K4).

The bootstrap shim converts libc's `-1` + `errno` into the kernel
convention (`-errno`), so everything above `sys` sees the same values in
both stages.

*Probed* with klin PR #351 (`d3394e4`, 2026-10-23): a sketch of `rt/bootstrap/sys.kl`
+ `shim.c`, `os`, `arena`, `out` and a `main` that maps an arena, reads a
file, prints to stdout/stderr and reports `ENOENT` for a missing file
builds and runs with `klin run -I rt/bootstrap -I rt`. The snippets below
follow that sketch, updated to Klin main: methods on `Out` and `Arena`
through `*mut Ctx`, subslices, `[]Token`, no `cast` on negative literals
(re-probed on `824e4af`, 2026-10-24).

### `sys` — the only target-specific module

Signatures only. `linux_*/sys.kl` declares the intrinsics as `pub fn`
without a body — not valid Klin (only `@[cimport]` functions have no
body); Kliner accepts a body-less `fn` in module `sys` as an intrinsic,
and Klin never compiles that file. `bootstrap/sys.kl` declares the same
names as `@[cimport]` over the shim:

```klin
module sys

// Raw syscall. Returns the kernel value: >= 0 ok, -4095..-1 = -errno.
// Kliner: intrinsic (lowered to `syscall` / `svc #0` / `ecall`).
// Bootstrap: shim around libc syscall(2).
pub fn call6(nr: i64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64): i64

// Syscall numbers for this target (module-level `const`, G8).
pub const NR_READ: i64 = 0
pub const NR_WRITE: i64 = 1
pub const NR_OPENAT: i64 = 257
pub const NR_CLOSE: i64 = 3
pub const NR_LSEEK: i64 = 8
pub const NR_FSTAT: i64 = 5
pub const NR_MMAP: i64 = 9
pub const NR_MUNMAP: i64 = 11
pub const NR_EXIT_GROUP: i64 = 231

// Slice → address, for syscall arguments (buffers, paths).
// Part of the runtime API — DECIDED (C8.4).
pub fn addr_u8(b: []u8): i64
```

```klin
// rt/bootstrap/sys.kl (Klin only)
@[link("shim.c")]
@[cimport, codename("klrt_syscall6")]
pub fn call6(nr: i64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64): i64

// Plain Klin since the pointer → integer cast (G9, D17). `&b[0]` is
// `b.ptr`: no bounds check, so an empty slice gives its pointer too.
pub fn addr_u8(b: []u8): i64 { return cast(i64, &b[0]) }
```

Kliner may compile the same body (it needs the pointer → integer cast
anyway) or keep `addr_u8` as an intrinsic — either way the API is C8.4.
Address → slice needs no `sys` function since klin #358 (D19): `cast`
the address to `*mut [MAX_LEN]T` and take `(*p)[:n]` (C6 `arena`). The
shim is one function, `klrt_syscall6`, a wrapper around libc
`syscall(2)`; C7.5 (shim may rely on Klin's C layout of `[]T`) is no
longer used by it.

Flag constants (`AT_FDCWD`, `O_*`, `SEEK_*`, `PROT_*`, `MAP_*`) are
`const` too. They are the same on all three targets, so they live in the
portable `os` module; only `NR_*` differ per target.

### Syscall numbers

Use **`openat(AT_FDCWD, …)`** everywhere: the generic table has no
`open`. `exit_group` instead of `exit` (ends all threads; same effect
for a single-threaded compiler).

| Syscall | x86-64 | ARM64 / RV64 (asm-generic) |
|---|---|---|
| `read` | 0 | 63 |
| `write` | 1 | 64 |
| `open` | 2 | — (use `openat`) |
| `close` | 3 | 57 |
| `fstat` | 5 | 80 |
| `lseek` | 8 | 62 |
| `mmap` | 9 | 222 |
| `munmap` | 11 | 215 |
| `exit` | 60 | 93 |
| `exit_group` | 231 | 94 |
| `openat` | 257 | 56 |

ARM64 and RV64 share the generic numbers (`include/uapi/asm-generic/unistd.h`).

Calling convention of the `syscall` instruction:

| | number | args 1–6 | return | clobbered |
|---|---|---|---|---|
| x86-64 | `rax` | `rdi rsi rdx r10 r8 r9` | `rax` | `rcx r11` |
| ARM64 (`svc #0`) | `x8` | `x0`–`x5` | `x0` | — |
| RV64 (`ecall`) | `a7` | `a0`–`a5` | `a0` | — |

Constants — `const` in `os` (same on all three targets for what we use):
`AT_FDCWD = -100`, `O_RDONLY = 0`, `O_WRONLY = 1`, `O_RDWR = 2`,
`O_CREAT = 0o100`, `O_TRUNC = 0o1000`, `SEEK_SET = 0`, `SEEK_END = 2`,
`PROT_READ = 1`, `PROT_WRITE = 2`, `MAP_PRIVATE = 2`, `MAP_ANONYMOUS = 0x20`.
`st_size` in `struct stat` is at offset 48 on x86-64 and asm-generic —
but file size via `lseek(fd, 0, SEEK_END)` avoids the struct entirely.

### `_start` — emitted by the Kliner backend

Not Klin source. A few instructions generated per target:

- x86-64: at entry `[rsp]` = `argc`, `[rsp+8]…` = `argv[0..argc]`, `NULL`,
  `envp…`, `NULL`, auxv. Clear `rbp`, align `rsp` to 16, `call main`,
  then `exit_group(0)` (or `main`'s value once `main` may return `i32`).
- ARM64 / RV64: same layout at `sp`; `bl main` / `call main`.

v0 reads arguments from **`/proc/self/cmdline`** (NUL-separated) in
`os.args` (C7.4) — identical in both stages, no backend magic. Klin main
now has `fn main(args: []str)` (G10, D18); since D22 its `str`
elements can be read with `s.len`, `s[i]` and `cstr_u8(s)`, and Kliner
checks them (C12.3). Switching to it is the option in C9.2 / C12.4;
v0 keeps `/proc` (C7.4). Later, `_start` passes
`argc` / `argv` and the `/proc` dependency goes away.

### Errors: errno → `!T`

`sys.call6` returns `-errno` on failure. `os` turns that into `!T`
directly — Klin's `error(n)` already carries an integer:

```klin
pub fn check(r: i64): !i64 {
    if r < 0 && r >= -4095 { return error(cast(i32, -r)) }
    return r
}
```

`-4095` takes the type `i64` from `r` (D12, C8.3). `-r` is a runtime
value, so the narrowing to `i32` is still a `cast`.

So `err` in an `or { }` block **is** the errno (`2` = ENOENT,
`9` = EBADF, `12` = ENOMEM, `13` = EACCES, `21` = EISDIR, `22` = EINVAL).
`out.errno_name(o, err)` prints the name for messages. Partial `write` and
`EINTR` (4) are retried inside `os.write_all`.

### `os`

```klin
module os
import sys
import arena

pub fn check(r: i64): !i64                   // -errno → error(errno), above
pub fn open_read(path: []u8): !i32           // path: NUL-terminated bytes
pub fn open_write(path: []u8): !i32          // O_WRONLY | O_CREAT | O_TRUNC, mode 0o755 (output is executable)
pub fn close(fd: i32): !i32
pub fn close_quiet(fd: i32)                  // close, ignore error (for `defer`)
pub fn read(fd: i32, buf: []u8): !i32        // up to buf.len bytes
pub fn write_all(fd: i32, buf: []u8): !i32
pub fn file_size(fd: i32): !i64              // lseek(SEEK_END) + lseek(SEEK_SET)
pub fn read_file(a: *mut arena.Arena, path: []u8): ![]u8
pub fn args(a: *mut arena.Arena): !Args       // v0: /proc/self/cmdline
pub fn exit(code: i32)                       // exit_group; does not return
```

Klin has no "never returns" type: code after `os.exit(…)` must still
type-check (a `return` follows it in a function with a result).
`exit_group` does not run `defer`s — flush `out` before calling it.

```klin
pub struct Args {
    bytes: []u8     // all arguments, NUL-separated
    list: [][]u8    // each argument: a subslice of `bytes`, without the NUL
}
```

Callers pass a subslice for a range: `os.write_all(fd, buf[off:off + n])`
(G6, D15). `args.list.len` is the count, `args.list[0]` the program name.
The `[][]u8` itself comes from the arena (`arena.alloc_slices_u8`).

### `arena` — bump allocator first

```klin
module arena
import sys

pub struct Arena {
    base: i64      // address of the current mmap chunk
    used: i64
    cap: i64
}

pub fn Arena.new(cap: i64): !Arena           // one mmap(PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS), fd = -1
pub fn alloc_u8(a: *mut Arena, n: i32): ![]u8     // 8-byte aligned, zeroed; ENOMEM (12) when full
pub fn alloc_i32(a: *mut Arena, n: i32): ![]i32
pub fn alloc_i64(a: *mut Arena, n: i32): ![]i64
pub fn alloc_slices_u8(a: *mut Arena, n: i32): ![][]u8     // for os.Args
pub fn alloc_addr(a: *mut Arena, size: i64): !i64  // raw zeroed block, for typed allocators
// pub fn alloc_tok(a: *mut Arena, n: i32): ![]Token — one per table type, declared next to that type
pub fn mark(a: *mut Arena): i64
pub fn reset(a: *mut Arena, m: i64)          // zeroes [m, used), then used = m (DECIDED, C8.4)
pub fn free_all(a: *mut Arena)               // munmap
```

`alloc_tok` stands for one allocator per table element type (`[]Token`,
`[]Node`, …, G3), plain Klin since #358 (D19, G13 fixed):

```klin
pub fn alloc_tok(a: *mut arena.Arena, n: i32): ![]Token {
    let p = cast(*mut [arena.MAX_LEN]Token, arena.alloc_addr(a, cast(i64, n) * 12)!)
    return (*p)[:n]
}
```

`MAX_LEN = 0x7fffffff` (`.len` is `i32`) is only the bound of the array
type; no memory of that size exists. Free functions on `*mut Arena` here,
because the arena is passed around as a pointer; a `mut` method works
too (`(*c).arena.alloc_u8(n)`, G11).

Signatures mirror Klin's `stdlib/mem` (`alloc_u8(a: *mut Allocator, n: i32)`),
so the code reads the same as host Klin. No `free` of single blocks —
a compiler allocates per phase and drops whole arenas. Reserve one large
range (e.g. 1 GiB; pages are committed lazily by the kernel) to avoid
chunk chaining in v0. Error = `ENOMEM` from `mmap`, or when `used`
reaches `cap`. Fresh `mmap` pages are zero; memory handed out again after
`reset` is not, so `reset` clears it — every `alloc_*` result is zeroed,
matching ZII (D6). Align with `(n + 7) & ~7` (`~7` takes the type of `n`, D12).

### `out`

```klin
module out
import os

const BUF: i32 = 4096

pub struct Out {
    fd: i32
    buf: [BUF]u8
    n: i32
}

pub fn Out.stdout(): Out
pub fn Out.stderr(): Out
pub fn (mut o: Out) lit(b: []u8)             // a whole slice: o.lit(b"error: "), o.lit(src[a:b])
pub fn (mut o: Out) dec(v: i64)
pub fn (mut o: Out) hex(v: u64)
pub fn (mut o: Out) nl()
pub fn (mut o: Out) flush(): !i32
pub fn (mut o: Out) flush_quiet()            // flush, ignore error (for `defer`)
pub fn (mut o: Out) errno_name(e: i32)       // "ENOENT", …; decimal if unknown
```

Explicit buffer, explicit `flush` — no hidden cost. Klin rejects an
ignored `!T`, so `defer o.flush()` does not build; use
`o.flush_quiet()`. `main` flushes explicitly before `os.exit(code)`,
because `exit_group` skips `defer`s:

```klin
fn main() {
    let mut o = out.Out.stdout()
    let mut e = out.Out.stderr()
    let code = run(&o, &e) or {
        e.lit(b"error: ")
        e.errno_name(err)
        e.nl()
        1
    }
    o.flush_quiet()
    e.flush_quiet()
    os.exit(code)
}
```

The buffer length is the constant `BUF` (D11). `Out` has `mut` methods:
the compiler reaches its outputs through `*mut Ctx` as
`(*c).err.lit(…)` — a mutable place (G11, D5). The struct has no
initializer for `buf`, so `Out.stdout()` is `let mut o: Out` (zeroed,
D6), then `o.fd = 1`.

### Intrinsics Kliner must provide

The complete list of things the core cannot express (stage 6). Address →
slice is core Klin since D19 (`cast(*mut [N]T, addr)`, `(*p)[:n]`): Kliner
must support that cast and the subslice, not an intrinsic.

| Intrinsic | Lowers to |
|---|---|
| `sys.call6` | `syscall` (x86-64), `svc #0` (ARM64), `ecall` (RV64) |
| `sys.addr_u8(b)` | `b.ptr` as an integer — no code (or the Klin body above, D17) |
| `_start` | emitted, not declared |

Everything else in `rt/` is plain core Klin — including the byte
helpers the compiler needs everywhere (compare / copy slices and
subslices, hash bytes): there is no slice `==` and no `memcpy` builtin.

---

## C7. Decisions — DECIDED (2026-10-23)

The open questions of this stage, answered by Marek.

1. **Bytes from literals (G5):** Klin gets a byte-string literal
   **`b"fn"` of type `[]u8`**. Compiler code uses `b"…"` for keywords,
   messages and paths; `str` is not used there. *Merged: klin #351.*
2. **G1 / G2 / G4 are fixed in Klin itself**, not worked around in Kliner
   source. *Merged: klin #351.*
3. **Module-level `const`** is added to Klin (`pub const PAGE: i64 = 4096`).
   Compiler state lives in a **context struct** passed as `*mut Ctx`;
   **no mutable globals**. *Merged: klin #351.* (In #351 a const
   initializer was a literal and not an `[N]T` length; since #352 /
   #353 it is a constant expression and a valid length.)
4. **Arguments in v0** come from `/proc/self/cmdline`. OK.
5. **The bootstrap C shim** (`rt/bootstrap/shim.c`) may depend on Klin's
   internal C layout of `[]T`. OK — bootstrap only.

**Klin main since then (2026-10-24):** module-level `let mut` exists
(#356) and `fn main(args: []str)` exists (#355). Decisions 3 and 4 are
unchanged; whether to revisit them is C9.1 and C9.2 (PROPOSED).

Example with the decided forms (Klin main `824e4af`, 2026-10-24):

```klin
module os
import sys
import arena

pub const AT_FDCWD: i64 = -100
pub const O_RDONLY: i64 = 0

pub fn args(a: *mut arena.Arena): !Args {
    let fd = open_read(b"/proc/self/cmdline\0")!
    defer close_quiet(fd)          // close, ignore error
    …                              // b"/proc/self/cmdline\0".len == 19
}
```

```klin
struct Token {
    kind: u8
    start: i32
    len: i32
}

struct Ctx {
    arena: arena.Arena             // by value: &(*c).arena is *mut (G11)
    err: out.Out
    src: []u8
    toks: []Token                  // slice of structs (G3)
}

fn report(c: *mut Ctx, pos: i32) {
    (*c).err.lit(b"error: unexpected token at ")
    (*c).err.dec(cast(i64, pos))
    (*c).err.nl()
}
```

---

## C8. Review decisions — DECIDED (2026-10-23)

Questions from the review of C1–C4 / C6 and klin PR #351, answered by
Marek. C1–C4 and C6 as a whole stay PROPOSED.

1. **`b"..."` bytes are read-only — documented only, for now.** The
   checker rejects a direct write (`b"fn"[0] = 1`, `KW[0] = 1`), and
   since #353 / #354 also a write through an immutable binding
   (`let s = b"fn"; s[0] = 1`) or a `[]u8` parameter (D5, D10). A write
   through a mutable place is undefined behavior. *Merged: klin #357
   (`a7e49ac`)* makes the direct cases checker errors: `let mut s = b"fn"`
   and `s = b"ab"` on a `let mut` slice ("cannot bind read-only bytes to
   a mutable slice"). Still UB, probed on `d7625f1`: bytes that reach a
   mutable binding through a parameter or a return
   (`let mut t = id(b"fn"); t[0] = 1` compiles and crashes; the bytes
   are in read-only memory). Compiler code copies into a `[N]u8`
   or an arena buffer before writing.
2. **Out-of-range integer literals are a compile error** in `const` and
   `let` (`const X: u8 = 300`, `let y: i8 = 200`). *Landed: klin #352
   (D12)* — also for a parameter, a return, a field, an array element
   and an enum variant.
3. **Unary `-` / `~` on a literal take the expected type**, like a bare
   literal: `f(-1)` for an `i64` param, `r >= -4095` with `r: i64`, no
   `cast(i64, -1)`. *Landed: klin #353 / #354 (D12)*, together with
   integer constant expressions (`let x: i64 = 1 << 40`). The casts are
   removed from the examples (C6 `check`, `Arena.new`, alignment).
   `match` / `pick` arms adopt the type too (#357, merged).
4. **`sys.addr_u8(b: []u8): i64` and zeroing `arena.reset`** are part of
   the runtime API (C6). `addr_u8` is a Kliner intrinsic and a shim
   function in bootstrap; `reset(a, m)` zeroes `[m, used)` so every
   `alloc_*` result is zeroed (ZII, D6). Since D17 the bootstrap body
   can be plain Klin (`cast(i64, &b[0])`, C6) instead of the shim — an
   implementation detail, the API is unchanged.

---

## C9. Sync with Klin main — PROPOSED

Klin main (`824e4af`) now allows things that decisions C7.3 and C7.4
ruled out or worked around. These are options for Marek; nothing here
changes C7 until he decides.

1. **Module-level globals for compiler state.** Klin has
   `let` / `let mut` / `pub let mut` at module scope (#356, D11): type
   required, constant initializer or zeroed, private is `static` in C.
   - *(a) Keep C7.3:* all state in `Ctx`, passed as `*mut Ctx`. Explicit
     data flow, no hidden state; with G11 fixed the cost is only the
     `c` parameter. Kliner does not need globals until a later stage.
   - *(b) Allow module-level `let mut`* for a few singletons (the
     `err` output, the arena, an interning table): fewer parameters.
     Cost: Kliner must support module-level `let` in the core from day
     one (stage2 == stage3) — `.data` / `.bss`, symbol addresses and
     their relocations in the backend — and state becomes implicit.
   - Suggestion: (a) for v0; reconsider (b) when the backend has a data
     section anyway.
2. **Arguments via `fn main(args: []str)`** (#355, D18) instead of
   `/proc/self/cmdline` (C7.4). Probed on `824e4af`: `args.len` is
   `argc`, but a `str` element had no `.len` and no indexing. *Update
   (`a66ffbd`, D22):* `s.len`, `s[i]` and the builtin `cstr_u8(s)` exist
   and Kliner accepts `str` and `main(args: []str)` (C12.3), so no shim
   function is needed any more — see C12.4. Gain: no `/proc` dependency, the same source in both
   stages once `_start` passes `argc` / `argv`. Suggestion: keep
   `/proc/self/cmdline` in v0; switch together with `_start` passing
   the arguments.
3. **Data model:** slices of structs (`toks: []Token`) instead of
   struct-of-arrays, sub-structs by value in `Ctx` with `mut` methods
   (C2 Data model, C6 `out`, C7 example). This document now uses that
   form. Allocating a `[]Token` in the arena is plain Klin since G13 is
   fixed (#358, C6 `arena`); struct-of-arrays (`[]u8` / `[]i32` columns)
   stays a valid fallback.

---

## C10. `$fn` and string interpolation — DECIDED (2026-10-24)

**Decided (Marek, 2026-10-24): both stay out of Kliner for now** —
1(c) and 2(b) below: Kliner sources use neither, the lexer keeps
rejecting `$`, the parser keeps rejecting interpolation. Revisit (1(b),
2(a)) when Kliner compiles user programs, after self-hosting.

Stage 3 parses Klin without these two features.
Today a file with `$` outside a string or comment fails in the lexer
with Klin's message (``unexpected character `$` ``) plus a note, and a
string with an unescaped `$` fails in the parser (`string
interpolation is not supported by Kliner yet` + note). `\$` is a
literal `$` and works.

1. **`$fn` generics, `$name(...)` expansion.** Klin rewrites the source
   text before lexing (`lib/preprocess.dart`: expands `$fn` per
   instantiation, also SVD / `ioc` rewrites).
   - *(a) Pre-pass like Klin:* text → text before the lexer. Same
     semantics and errors as Klin for free; positions after an
     expansion need a map back to the original; a second "language"
     inside the compiler.
   - *(b) `$` tokens + generic declarations in the AST:* `$fn` becomes
     a `Fn` with type parameters, instantiation happens in the checker
     (on demand, per type list). Proper positions and errors, no text
     rewriting; more checker work (stage 4), and the result must be
     identical to Klin's expansion.
   - *(c) Not in Kliner sources:* the compiler does not need generics
     (C1); keep rejecting `$` until after self-hosting.
   - Suggestion: (c) for the compiler itself, (b) when Kliner compiles
     user programs.
2. **String interpolation `"a $x ${e}"`.** Klin's lexer keeps the
   `$` in the string token; the parser splits it into parts
   (`InterpolatedStringExpr` with `InterpText` / `InterpSlot` parts).
   - *(a) Parser splits the token* into literal parts + expressions
     (sub-lexing the `${…}` text), node `Interp {extra = parts}`. Same
     as Klin; needs a formatting runtime (`out.dec`, …) in the backend.
   - *(b) Not in the core:* Kliner sources use `out.lit` / `out.dec`;
     interpolation only for user programs, after self-hosting.
   - Suggestion: (b) now, (a) together with a `fmt` runtime.

---

## C11. Stage 3 review — DECIDED (2026-10-24)

Marek accepted the five recommendations of the stage 3 report when
merging #4 (`8812306`):

1. **`$fn` and string interpolation** stay out of Kliner for now (C10).
2. **AST model:** `Node` keeps the `tok` field (C2 AST).
3. **`fn` without a body in `module sys`** (Kliner intrinsics,
   `rt/linux_x86_64/sys.kl`) stays a documented difference from Klin
   (tests/parse `div_sys`, tests/check `div_lib_sys`).
4. **`let mut ok = 0` … `ok = f()!`** stays the pattern for an ignored
   `!T` result while `f()!` is not a statement in Klin.
5. **Roadmap numbering:** 2 lexer, 3 parser, 4 checker; the later
   stages moved by two (IR 5, backend 6, fuller language 7,
   self-hosting 8, targets 9, after self-hosting 10) —
   [01-roadmap.md](01-roadmap.md).

## C12. Stage 4 review — DECIDED (2026-10-24)

Marek answered "yes" to the three points of the stage 4 report (PR #5):

1. **Partial port of the "complete type" check** (C typedefs of struct
   fields such as `[]*mut [2]Token`, an `fn` field returning an array of
   structs; Klin `error_175`, `error_207`–`209`) is enough. Kliner's
   backend emits no C typedefs; the difference stays documented
   ([04-checker.md](04-checker.md), tests/check `div_typedef`).
2. **Klin bugs K-B1 and K-B2** (04-checker.md) were reported to the Klin
   bot on 2026-10-24; nothing is changed in the Klin repo from here.
3. **`str` is in Kliner now** (D22, Klin main `a66ffbd`): string
   literals `"…"` have type `str`; `s.len` is `strlen` as `i32`
   (read-only); `s[i]` is `u8`, read-only (`cannot assign through a
   string`); no subslice; `cstr_u8(s)` is a read-only `[]u8` (builtin);
   `main(args: []str)`; `str` as a local, global, field, parameter or
   slice element. Not: `const X: str`, `cast` from / to `str`,
   arithmetic or `==` on `str`, `match` on `str` (same errors as Klin).
   String interpolation stays a parser error (C10). Compiler code keeps
   using `[]u8` / `b"…"` (C7.1).
4. **Arguments (option, not a change):** with (3), `fn main(args: []str)`
   plus `cstr_u8(args[i])` gives the argument bytes without
   `/proc/self/cmdline` and without a shim function. v0 keeps
   `/proc/self/cmdline` (C7.4); the switch happens together with
   `_start` passing `argc` / `argv` (C6), and needs only `os.args` to
   change.

## C13. Stage 5 IR — PROPOSED

Stage 5 ([05-ir.md](05-ir.md)) needed these choices; all are
PROPOSED, Marek decides:

1. **Flat instruction list with labels** instead of a block table: basic
   blocks are implicit (from a label to `jmp` / `br` / `ret` / `trap`).
   K9 holds (three-address, virtual registers, explicit widths, no
   SSA); the backend (stage 6) can split on labels.
2. **Every operation wraps at its type** (`u8 + u8` is a `u8`). Klin's C
   output does not (K-B4); Kliner follows the declared types. Shift
   counts ≥ the width give 0 / −1 (C: undefined).
3. **Memory layout = C's natural layout** (as Klin's C), slices
   `{ptr, len i32}` (16 bytes), `!T` = `{is_err u8 @0, err i32 @4,
   value @8}`.
4. **Calling convention in the IR**: aggregates by address; aggregate
   arguments copied by the caller into a temporary; aggregate results
   through a hidden first parameter (`sret`); `mut` receivers by
   address. Every local in a frame slot (the stage-6 codegen plan:
   "locals in stack slots").
5. **The checker records name resolution** (`File.rf`: global /
   constant / function + index) and the type of `let` / `for` /
   `match` subjects, so the lowering resolves nothing again.
6. **Interpreter on host memory** with pass-through syscalls; only
   `/proc/self/cmdline` is emulated (memfd). Traps: exit 134.
7. **Not supported yet** in the lowering: calls of body-less functions
   other than `sys.call6`, pointer arithmetic (the checker rejects it
   today anyway), > 60 call arguments, > 64 multi-assignment targets.
