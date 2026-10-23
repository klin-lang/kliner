# Kliner — core subset and runtime (stage 1)

Roadmap stage 1 ([01-roadmap.md](01-roadmap.md)). Decisions this builds
on: [00-decisions.md](00-decisions.md) K2 (bootstrap), K4 (compatibility),
K6 (stdlib).

Two questions:

1. **Which Klin features form the core** — the subset the Kliner
   compiler is written in, and which Kliner supports from day one?
2. **What is the minimal runtime** on Linux syscalls?

Basis: [klin-lang/klin](https://github.com/klin-lang/klin) at `757b782`
(2026-09-01, Klin 0.1.4) — `docs/`, `lib/` (lexer, parser, checker,
types), `stdlib/`, `test/`, `examples/`. Every "bootstrap risk" below
marked *probed* was checked on 2026-10-23 by compiling a small program
with that Klin (Dart 3.13.7 → C → gcc).

Status: C1–C4 and C6 **PROPOSED**. The five stage-1 questions are
**DECIDED (2026-10-23)** — see [C7](#c7-decisions--decided-2026-10-23).
Four review questions (read-only bytes, literal range, literal typing,
runtime API) are **DECIDED (2026-10-23)** — see
[C8](#c8-review-decisions--decided-2026-10-23).
Items marked *in klin PR #351 (not merged)* are changes to Klin that the
compiler source relies on. They are implemented in
[klin-lang/klin#351](https://github.com/klin-lang/klin/pull/351) (branch
`cursor/kliner-bootstrap-gaps-2073`); the examples here were compiled with
that branch on 2026-10-23. Until #351 is merged, the listed workaround
applies.

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
| Integers | `i8`…`i64`, `u8`…`u64`, `usize`/`isize`, `int` = `i32` | low | Widths matter (K8). `u64` literals and shifts probed OK. *Probed:* a bare literal adapts to the expected type (`f(0)` for an `i64` param), but `-1`, `~7` and `1 << 40` are `i32` expressions → `cast(i64, -1)`, `cast(i64, 1) << 40`. `xs.len` is `i32`. **DECIDED (C8.2, C8.3), pending in Klin:** unary `-` / `~` on a literal take the expected type; an out-of-range literal in `const` / `let` is a compile error. Examples keep `cast(i64, -1)` until that lands |
| `bool` | `true` / `false`; `if` wants `bool` | low | No numeric truthiness |
| Literals | `0xFF`, `0b1010`, `0o755`, `1_000`, `'A'` | low | Char literal is an integer — the lexer lives on these |
| Numeric `cast` | `cast(i64, x)`, `cast(u8, 300)` | low | No implicit widen/narrow — good for IR widths |
| Operators | arithmetic, bitwise (D8), `&&` / `\|\|` (D9), compound `+=` … | low | Rust-like precedence |
| `let` / `let mut` / `:=` | | low | ZII: zeroed when no initializer (D6) |
| Control flow | `if` / `else if` / `while` / `for i in a..<b` / C-style `for` / `break` / `continue` / `return` | low | |
| `match` on integers and enums | value groups, `a..=b`, relational arms, `when`, `else` | low | Lexer/parser dispatch. Probed: `match c { 48..=57 {…} 32, 10 {…} < 32 {…} _ when x > 3 {…} else {…} }` |
| `enum` (named integer) | `enum Tok: u8 { … }`, `Tok.Ident`, `cast(u8, Tok.Ident)` | **high** as a field type | *Probed:* `struct T { k: Tok }` → `unknown type 'Tok'`. Locals/params/returns work. Fix *in klin PR #351 (not merged)* (G2); until merged `u8` field + `cast` |
| `struct` + methods | `fn (v: T) f()`, `fn (mut v: T) f()`, `fn T.new(): T` called as `T.new()` / `mod.T.new()` | low | Nested structs and `[N]T` fields probed OK. `fn (mut v: T)` needs a plain `let mut` local as receiver — not `(*p).f` (G11); state behind `*mut` uses free functions |
| Fixed arrays | `[N]T`, `xs[i]`, `xs.len`, `[N]Struct` | low | Arrays of structs probed OK |
| Slices of primitives | `[]u8`, `[]i32`, `[]i64`, `xs[:]`, `xs.len` | medium | Params and fields OK. *Probed:* `let s = xs[:]; s[0] = 7` → broken C (G4). Fix *in klin PR #351 (not merged)*; until merged pass `xs[:]` directly |
| Pointers | `*T` / `*mut T`, `&x`, `*p`, `(*p).f` | **high** for self-reference | *Probed:* `struct Node { next: *mut Node }` → broken C (anonymous `typedef struct`). Pointers to other structs OK. Fix *in klin PR #351 (not merged)* (G1) |
| `!T` errors | `!T`, `error(n)`, `expr!`, `or { }`, `err` | **high** for `!` across types | `!Struct`, `![]u8` probed OK. Errno maps 1:1 to `error(n)` (C6). *Probed:* `a()!` with `a(): !i64` inside a `!i32` function → broken C on Klin main; fix *in klin PR #351 (not merged)* (`d3394e4`); until merged keep one `!T` per call chain. An `or { }` block must end in a value — no `return` inside — so `main` calls `fn run(…): !i32` and does `let code = run(…) or { …; 1 }` |
| `defer` | block-scoped, LIFO | low | Covered by Klin goldens (`defer_*`) |
| Modules | `module`, `import`, `import path alias`, `pub` | low | Search paths `-I` are used for target selection (C6) |
| `$fn` generics | `$fn vec(name: name, T: type) { struct $name { data: [8]$T … } }`, `$vec(VecI32, i32)` | medium | Probed OK. Parameters are spliced with `$` (`$T`, `$name`). A free `fn` inside the body is declared once per expansion → `redeclaration of function` on the second `$vec(…)`; use methods on `$name`. Risk: error messages inside expansions. Use only for a few container shapes |
| Function pointers | `fn(T): R`, no capture | low/medium | *Probed:* `h.cb(1)` on a field parses as a method → bind first: `let f = h.cb; f(1)` (G7) |
| Destructuring / multi-assign | `let { x, y } = p`, `a, b = b, a` | low | Optional; lowers to plain moves |
| Byte-string literal | `b"fn"` of type `[]u8` | **high** until #351 is merged | *In klin PR #351 (not merged)* (G5). Keyword table, messages, paths: `b"fn"`, `b"error: "`. Rules: `.len` counts bytes, no implicit trailing NUL (`b"/proc/self/cmdline\0"` has len 19); escapes `\n \t \\ \" \$ \0`; `\0` is one NUL byte, not octal (`b"\00"` = NUL + `'0'`); no interpolation; bytes are read-only, checked only on the literal / constant itself (`b"fn"[0] = 1` is an error; a write through a copy or a `[]u8` param compiles and faults — **DECIDED (C8.1)**: documented as UB for now, type-level enforcement later) |
| Module-level `const` | `const PAGE: i64 = 4096` | **high** until #351 is merged | *In klin PR #351 (not merged)* (G8). `pub? const Name: Type = literal`, top level only. Types: integer prims, `bool`, `[]u8`. Initializer is a literal (`-100`, hex, `'A'`, `true`, `b"…"`) — no expressions, no other const. Imported as `mod.NAME` (`os.AT_FDCWD`). Immutable: `NAME = …` and `KW[0] = …` are errors; a local shadows a const. **Not usable as an `[N]T` length** (`[N]u8` → parse error) — array lengths stay integer literals. No mutable globals |
| Strings for the compiler | `[]u8` + `i32` offsets | low | All source text, identifiers and output buffers are `[]u8`; literals are `b"…"`. `str` is not used in compiler code |

### Data model this forces

Klin has no tagged unions (payload enums are "not in the language",
`syntax.md`), self-referential pointers do not build on Klin main (G1) and slices of
structs are rejected (G3). G1 is fixed in klin PR #351 (not merged), but the table
model stays the choice — it is also the fastest and simplest:

- **Compiler state in one context struct** passed as `*mut Ctx` — no
  mutable globals (C7.3). Fixed values are module-level `const`.
  Plain fields are updated in place (`(*c).n = …`, `(*c).tok_kind[i] = …`).
  A sub-struct that is passed on as `*mut` (arena, output) is held as a
  `*mut` field: `&(*c).arena` has type `*Arena`, not `*mut Arena` (G11).
- **Tables, not trees of pointers.** Tokens, AST nodes, types, IR ops
  live in arrays; references are `i32` indices.
- A node = `kind: u8` + a few `i32` fields (`a`, `b`, `c`, `extra`).
  Variable-length children go into a side array `[]i32` (start + count).
- Growing tables = allocate a bigger `[]i32` / `[]u8` and copy.
- Struct-of-arrays where slices are needed (`tok_kind: []u8`,
  `tok_start: []i32`, `tok_len: []i32`) until G3 is fixed.

This is the Zig / Carbon "data-oriented AST" layout. It also makes
stage2 == stage3 easier: no pointer values end up in output.

---

## C3. LATER

| Feature | Why later |
|---|---|
| `float` / `f32` / `f64` | The compiler does not need floats. Add with SSE2 / FP regs in stage 5+ |
| `pick` | Sugar over `if`; trivial once `match` exists |
| String interpolation `"$x"` / `${e}` | Lowers to `printf` / `snprintf` in Klin. Kliner needs its own formatter first |
| `printf` / `puts` builtins | libc. Kliner maps `puts(str)` to `out` (C6); full `printf` later or never |
| `fmt.write`, `time`, `math`, `slice`, `slice_alloc` (stdlib) | Rewritten as Kliner stdlib on syscalls (K6) |
| `async fn` / `.await` | Needs an executor; not needed for the compiler |
| `volatile` | MCU-oriented; harmless to add later |
| Destructuring of arrays `let [a, b] = xs` | Optional sugar |
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

## C5. Gaps in current Klin found by probes

These matter because the compiler source must build with current Klin.
G1, G2, G4, G5 (`b"…"`), G8 (`const`) and G12 are **in klin PR #351 (not
merged)** ([klin-lang/klin#351](https://github.com/klin-lang/klin/pull/351),
decided 2026-10-23). Their workaround applies until #351 is merged. The
others (G3, G6, G7, G9, G10, G11, mutable globals) keep the workaround.

| # | Probe | Result | Workaround | Fix in Klin? |
|---|---|---|---|---|
| G1 | `struct Node { next: *mut Node }` | C error: incompatible pointer type (anonymous typedef) | Index-based tables (C2) | **In klin PR #351 (not merged)** — bug (named struct tag); test `test/self_ref_struct.kl` |
| G2 | `struct T { k: Tok }` (enum field) | `unknown type 'Tok'` | `k: u8` + `cast` until #351 is merged | **In klin PR #351 (not merged)** — bug |
| G3 | `[]Token` (slice of struct), `fn main(args: []str)` | `slice requires a primitive element type` | Struct-of-arrays, `[N]Struct` | Yes — feature, medium |
| G4 | `let s = xs[:]; s[0] = 7` | C error: `request for member 'ptr'` | Pass `xs[:]` directly until #351 is merged | **In klin PR #351 (not merged)** — bug; test `test/slice_view_write.kl` |
| G5 | `take("abc")` where `take(s: []u8)`; `"abc".len` | `str` is a C string pointer: not `[]u8`, no `.len`, no indexing | — | **In klin PR #351 (not merged):** byte-string literal `b"fn"` of type `[]u8` (rules in C2) |
| G6 | `xs[1:3]` | parse error — only `xs[:]` exists | `(slice, start, len)` triples | Yes — feature, small |
| G7 | `h.cb(1)` on an `fn` field | parsed as method call | `let f = h.cb; f(1)` | Optional |
| G8 | top-level `let N: i32 = 3` | parse error — no globals / consts | Context struct passed as `*mut Ctx` (state); `const` (values) | **In klin PR #351 (not merged):** module-level `const` only (literal initializer, not an `[N]T` length); mutable globals stay out (D11: no `let` at module scope) |
| G9 | `cast(usize, &x)` (pointer → integer) | `numeric cast requires an integer or float`. Integer → pointer works | Not needed in the compiler; runtime only (intrinsic) | Optional |
| G10 | no `argc` / `argv` in Klin | `main()` takes no arguments | Read `/proc/self/cmdline` (C6) — decided for v0 | Not needed |
| G11 | `(*c).err.lit(b"x")` (mutating method on a field via `*mut Ctx`); `&(*c).err` | `mutating method requires a mutable variable`; `&(*c).err` is `*Out`, not `*mut Out` (also on #351) | `out` uses free functions on `*mut Out`; `Ctx` holds `err: *mut out.Out` (C6, C7) | Optional |
| G12 | `let w = a()!` with `a(): !i64` inside `fn f(): !i32` | C error: returns `klin_res_i64` from a `klin_res_i32` function | One `!T` per call chain until #351 is merged | **In klin PR #351 (not merged)** — bug, `d3394e4`; test `test/propagate_cross.kl` |
| — | `[65, 66]` as `[2]u8` initializer | literals typed as `[2]i32` | `cast(u8, 65)` per element or char literals | Optional |

G1, G2, G4, G12, `b"…"` and `const` (klin PR #351) should be merged into Klin before stage 2 starts
— the frontend is written against them. G3, G6, G7, G9 keep their
workarounds.

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
  bootstrap/shim.c      klrt_syscall6, klrt_slice_u8, klrt_addr_u8 … (linked by `@[link]`, bootstrap only;
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

*Probed* with klin PR #351 (`d3394e4`): a sketch of `rt/bootstrap/sys.kl`
+ `shim.c`, `os`, `arena`, `out` and a `main` that maps an arena, reads a
file, prints to stdout/stderr and reports `ENOENT` for a missing file
builds and runs with `klin run -I rt/bootstrap -I rt`. The code snippets
below follow that sketch.

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

// Raw memory → slice. Kliner: intrinsic. Bootstrap: shim.
pub fn slice_u8(addr: i64, len: i64): []u8
pub fn slice_i32(addr: i64, len: i64): []i32
pub fn slice_i64(addr: i64, len: i64): []i64

// Slice → address, for syscall arguments (buffers, paths). Klin has no
// pointer → integer cast (G9). Kliner: intrinsic. Bootstrap: shim.
// Part of the runtime API — DECIDED (C8.4).
pub fn addr_u8(b: []u8): i64
```

```klin
// rt/bootstrap/sys.kl (Klin only)
@[link("shim.c")]
@[cimport, codename("klrt_syscall6")]
pub fn call6(nr: i64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64): i64

@[cimport, codename("klrt_slice_u8")]
pub fn slice_u8(addr: i64, len: i64): []u8

@[cimport, codename("klrt_addr_u8")]
pub fn addr_u8(b: []u8): i64
```

`shim.c` declares its own `typedef struct { uint8_t *ptr; size_t len; }`
with Klin's layout of `[]u8` (C7.5) and calls libc `syscall(2)`.

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

Because there are no mutable globals (C7.3) and `main()` takes no
arguments (G10), v0 reads arguments from **`/proc/self/cmdline`** (NUL-separated) in
`os.args` — identical in both stages, no backend magic. Later, `_start`
saves `argc`/`argv` in a backend-owned slot and `os.args` reads it via
an intrinsic (no `/proc` dependency).

### Errors: errno → `!T`

`sys.call6` returns `-errno` on failure. `os` turns that into `!T`
directly — Klin's `error(n)` already carries an integer:

```klin
pub fn check(r: i64): !i64 {
    if r < 0 && r >= cast(i64, -4095) { return error(cast(i32, -r)) }
    return r
}
```

`-4095` alone is an `i32` expression (C2, Integers), so it is cast.
Once C8.3 lands in Klin, `r >= -4095` is enough; the cast stays in the
examples until then.

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
pub fn read(fd: i32, buf: []u8, off: i32, n: i32): !i32
pub fn write_all(fd: i32, buf: []u8, off: i32, n: i32): !i32
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
    starts: []i32   // offset of each argument in `bytes`
    count: i32
}
```

`(buf, off, n)` instead of sub-slices until G6 is fixed.

### `arena` — bump allocator first

```klin
module arena
import sys

pub struct Arena {
    base: i64      // address of the current mmap chunk
    used: i64
    cap: i64
}

pub fn Arena.new(cap: i64): !Arena           // one mmap(PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS), fd = cast(i64, -1)
pub fn alloc_u8(a: *mut Arena, n: i32): ![]u8     // 8-byte aligned, zeroed; ENOMEM (12) when full
pub fn alloc_i32(a: *mut Arena, n: i32): ![]i32
pub fn alloc_i64(a: *mut Arena, n: i32): ![]i64
pub fn mark(a: *mut Arena): i64
pub fn reset(a: *mut Arena, m: i64)          // zeroes [m, used), then used = m (DECIDED, C8.4)
pub fn free_all(a: *mut Arena)               // munmap
```

Signatures mirror Klin's `stdlib/mem` (`alloc_u8(a: *mut Allocator, n: i32)`),
so the code reads the same as host Klin. No `free` of single blocks —
a compiler allocates per phase and drops whole arenas. Reserve one large
range (e.g. 1 GiB; pages are committed lazily by the kernel) to avoid
chunk chaining in v0. Error = `ENOMEM` from `mmap`, or when `used`
reaches `cap`. Fresh `mmap` pages are zero; memory handed out again after
`reset` is not, so `reset` clears it — every `alloc_*` result is zeroed,
matching ZII (D6). Align with `(n + 7) / 8 * 8` (`~7` is `i32`).

### `out`

```klin
module out
import os

pub struct Out {
    fd: i32
    buf: [4096]u8
    n: i32
}

pub fn Out.stdout(): Out
pub fn Out.stderr(): Out
pub fn bytes(o: *mut Out, b: []u8, off: i32, n: i32)
pub fn lit(o: *mut Out, b: []u8)             // whole slice, e.g. out.lit(o, b"error: ")
pub fn dec(o: *mut Out, v: i64)
pub fn hex(o: *mut Out, v: u64)
pub fn nl(o: *mut Out)
pub fn flush(o: *mut Out): !i32
pub fn flush_quiet(o: *mut Out)              // flush, ignore error (for `defer`)
pub fn errno_name(o: *mut Out, e: i32)       // "ENOENT", …; decimal if unknown
```

Explicit buffer, explicit `flush` — no hidden cost. Klin rejects an
ignored `!T`, so `defer out.flush(&o)` does not build; use
`out.flush_quiet`. `main` flushes explicitly before `os.exit(code)`,
because `exit_group` skips `defer`s:

```klin
fn main() {
    let mut o = out.Out.stdout()
    let mut e = out.Out.stderr()
    let code = run(&o, &e) or {
        out.lit(&e, b"error: ")
        out.errno_name(&e, err)
        out.nl(&e)
        1
    }
    out.flush_quiet(&o)
    out.flush_quiet(&e)
    os.exit(code)
}
```
 The buffer length is the literal
`4096`: a `const` cannot be an `[N]T` length. Free functions on
`*mut Out`, not `(mut o: Out)` methods, because a mutating method only
accepts a plain `let mut` local as receiver (G11) — the compiler reaches
its outputs through `*mut Ctx`.

### Intrinsics Kliner must provide

The complete list of things the core cannot express (stage 4):

| Intrinsic | Lowers to |
|---|---|
| `sys.call6` | `syscall` (x86-64), `svc #0` (ARM64), `ecall` (RV64) |
| `sys.slice_u8/i32/i64(addr, len)` | build `{ptr, len}` — no code |
| `sys.addr_u8(b)` | `b.ptr` as an integer — no code |
| `_start` | emitted, not declared |

Everything else in `rt/` is plain core Klin — including the byte
helpers the compiler needs everywhere (compare / copy `(slice, off, n)`
ranges, hash bytes): there is no slice `==` and no `memcpy` builtin.

---

## C7. Decisions — DECIDED (2026-10-23)

The open questions of this stage, answered by Marek.

1. **Bytes from literals (G5):** Klin gets a byte-string literal
   **`b"fn"` of type `[]u8`**. Compiler code uses `b"…"` for keywords,
   messages and paths; `str` is not used there. *In klin PR #351 (not merged).*
2. **G1 / G2 / G4 are fixed in Klin itself**, not worked around in Kliner
   source. *In klin PR #351 (not merged)*; workarounds (C5) until merged.
3. **Module-level `const`** is added to Klin (`pub const PAGE: i64 = 4096`).
   Compiler state lives in a **context struct** passed as `*mut Ctx`;
   **no mutable globals**. *In klin PR #351 (not merged).* A const
   initializer is a literal and a const is not an `[N]T` length.
4. **Arguments in v0** come from `/proc/self/cmdline`. OK.
5. **The bootstrap C shim** (`rt/bootstrap/shim.c`) may depend on Klin's
   internal C layout of `[]T`. OK — bootstrap only.

Example with the decided forms (compiled with the #351 branch, 2026-10-23):

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
struct Ctx {
    arena: *mut arena.Arena        // pointer: see G11
    err: *mut out.Out              // pointer: see G11
    src: []u8
    tok_kind: []u8
    tok_start: []i32
}

fn report(c: *mut Ctx, pos: i32) {
    out.lit((*c).err, b"error: unexpected token at ")
    out.dec((*c).err, cast(i64, pos))
    out.nl((*c).err)
}
```

---

## C8. Review decisions — DECIDED (2026-10-23)

Questions from the review of C1–C4 / C6 and klin PR #351, answered by
Marek. C1–C4 and C6 as a whole stay PROPOSED.

1. **`b"..."` bytes are read-only — documented only, for now.** The
   checker rejects a direct write (`b"fn"[0] = 1`, `KW[0] = 1`). A write
   through a copy (`let s = b"fn"; s[0] = 1`) or a `[]u8` parameter is
   undefined behavior (in practice a crash: the bytes are in read-only
   memory). Type-level enforcement (a read-only `[]u8`) comes later.
   Compiler code copies into a `[N]u8` or an arena buffer before writing.
2. **Out-of-range integer literals are a compile error** in `const` and
   `let` (`const X: u8 = 300`, `let y: i8 = 200`). Today Klin wraps
   silently (`300` → `44`). *Pending in Klin.*
3. **Unary `-` / `~` on a literal take the expected type**, like a bare
   literal: `f(-1)` for an `i64` param, `r >= -4095` with `r: i64`, no
   `cast(i64, -1)`. *Pending in Klin.* Until it lands, examples here keep
   the `cast` (C2 Integers, C6 `check`).
4. **`sys.addr_u8(b: []u8): i64` and zeroing `arena.reset`** are part of
   the runtime API (C6). `addr_u8` is a Kliner intrinsic and a shim
   function in bootstrap; `reset(a, m)` zeroes `[m, used)` so every
   `alloc_*` result is zeroed (ZII, D6).
