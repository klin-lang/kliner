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
Items marked *pending in klin-lang/klin* are changes to Klin that the
compiler source relies on; until they land, the listed workaround applies.

---

## C1. Rule for the core — PROPOSED

A feature is **IN core** when all three hold:

- the compiler needs it (or it costs almost nothing to support),
- current Klin compiles it correctly today (or the fix in Klin is small),
- it lowers to the IR (K9) without a runtime beyond C5.

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
| Integers | `i8`…`i64`, `u8`…`u64`, `usize`/`isize`, `int` = `i32` | low | Widths matter (K8). `u64` literals and shifts probed OK |
| `bool` | `true` / `false`; `if` wants `bool` | low | No numeric truthiness |
| Literals | `0xFF`, `0b1010`, `0o755`, `1_000`, `'A'` | low | Char literal is an integer — the lexer lives on these |
| Numeric `cast` | `cast(i64, x)`, `cast(u8, 300)` | low | No implicit widen/narrow — good for IR widths |
| Operators | arithmetic, bitwise (D8), `&&` / `\|\|` (D9), compound `+=` … | low | Rust-like precedence |
| `let` / `let mut` / `:=` | | low | ZII: zeroed when no initializer (D6) |
| Control flow | `if` / `else if` / `while` / `for i in a..<b` / C-style `for` / `break` / `continue` / `return` | low | |
| `match` on integers and enums | value groups, `a..=b`, relational arms, `when`, `else` | low | Lexer/parser dispatch. Probed: `match c { 48..=57 {…} 32, 10 {…} else {…} }` |
| `enum` (named integer) | `enum Tok: u8 { … }`, `Tok.Ident`, `cast(u8, Tok.Ident)` | **high** as a field type | *Probed:* `struct T { k: Tok }` → `unknown type 'Tok'`. Locals/params/returns work. Fix *pending in klin-lang/klin* (G2); until then `u8` field + `cast` |
| `struct` + methods | `fn (v: T) f()`, `fn (mut v: T) f()`, `Type.fn` | low | Nested structs and `[N]T` fields probed OK |
| Fixed arrays | `[N]T`, `xs[i]`, `xs.len`, `[N]Struct` | low | Arrays of structs probed OK |
| Slices of primitives | `[]u8`, `[]i32`, `[]i64`, `xs[:]`, `xs.len` | medium | Params and fields OK. *Probed:* `let s = xs[:]; s[0] = 7` → broken C (G4). Fix *pending in klin-lang/klin*; until then pass `xs[:]` directly |
| Pointers | `*T` / `*mut T`, `&x`, `*p`, `(*p).f` | **high** for self-reference | *Probed:* `struct Node { next: *mut Node }` → broken C (anonymous `typedef struct`). Pointers to other structs OK. Fix *pending in klin-lang/klin* (G1) |
| `!T` errors | `!T`, `error(n)`, `expr!`, `or { }`, `err` | low | `!Struct` probed OK. Errno maps 1:1 to `error(n)` (C5) |
| `defer` | block-scoped, LIFO | low | Covered by Klin goldens (`defer_*`) |
| Modules | `module`, `import`, `import path alias`, `pub` | low | Search paths `-I` are used for target selection (C5) |
| `$fn` generics | `$fn vec(name: str, T: type) { … }`, `$vec("VecI32", i32)` | medium | Probed OK. Risk: error messages inside expansions. Use only for a few container shapes |
| Function pointers | `fn(T): R`, no capture | low/medium | *Probed:* `h.cb(1)` on a field parses as a method → bind first: `let f = h.cb; f(1)` (G7) |
| Destructuring / multi-assign | `let { x, y } = p`, `a, b = b, a` | low | Optional; lowers to plain moves |
| Byte-string literal | `b"fn"` of type `[]u8` | **high** until it lands | *Pending in klin-lang/klin* (G5). Keyword table, messages, paths: `b"fn"`, `b"error: "` |
| Module-level `const` | `const PAGE: i64 = 4096` | **high** until it lands | *Pending in klin-lang/klin* (G8). Immutable only — no mutable globals |
| Strings for the compiler | `[]u8` + `i32` offsets | low | All source text, identifiers and output buffers are `[]u8`; literals are `b"…"`. `str` is not used in compiler code |

### Data model this forces

Klin has no tagged unions (payload enums are "not in the language",
`syntax.md`), self-referential pointers do not build (G1) and slices of
structs are rejected (G3). G1 is being fixed in Klin, but the table
model stays the choice — it is also the fastest and simplest:

- **Compiler state in one context struct** passed as `*mut Ctx` — no
  mutable globals (C7.3). Fixed values are module-level `const`.
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
| `printf` / `puts` builtins | libc. Kliner maps `puts(str)` to `out` (C5); full `printf` later or never |
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
G1, G2, G4, G5 (`b"…"`) and G8 (`const`) are **pending in klin-lang/klin**
(decided 2026-10-23, handed to Klin maintainers). The others use the
workaround.

| # | Probe | Result | Workaround | Fix in Klin? |
|---|---|---|---|---|
| G1 | `struct Node { next: *mut Node }` | C error: incompatible pointer type (anonymous typedef) | Index-based tables (C2) | **Pending in klin-lang/klin** — bug, small (named struct tag) |
| G2 | `struct T { k: Tok }` (enum field) | `unknown type 'Tok'` | `k: u8` + `cast` until fixed | **Pending in klin-lang/klin** — bug |
| G3 | `[]Token` (slice of struct), `fn main(args: []str)` | `slice requires a primitive element type` | Struct-of-arrays, `[N]Struct` | Yes — feature, medium |
| G4 | `let s = xs[:]; s[0] = 7` | C error: `request for member 'ptr'` | Pass `xs[:]` directly until fixed | **Pending in klin-lang/klin** — bug |
| G5 | `take("abc")` where `take(s: []u8)`; `"abc".len` | `str` is a C string pointer: not `[]u8`, no `.len`, no indexing | — | **Pending in klin-lang/klin:** byte-string literal `b"fn"` of type `[]u8` |
| G6 | `xs[1:3]` | parse error — only `xs[:]` exists | `(slice, start, len)` triples | Yes — feature, small |
| G7 | `h.cb(1)` on an `fn` field | parsed as method call | `let f = h.cb; f(1)` | Optional |
| G8 | top-level `let N: i32 = 3` | parse error — no globals / consts | Context struct passed as `*mut Ctx` (state); `const` (values) | **Pending in klin-lang/klin:** module-level `const` only; mutable globals stay out |
| G9 | `cast(usize, &x)` (pointer → integer) | `numeric cast requires an integer or float`. Integer → pointer works | Not needed in the compiler; runtime only (intrinsic) | Optional |
| G10 | no `argc` / `argv` in Klin | `main()` takes no arguments | Read `/proc/self/cmdline` (C6) — decided for v0 | Not needed |
| — | `[65, 66]` as `[2]u8` initializer | literals typed as `[2]i32` | `cast(u8, 65)` per element or char literals | Optional |

G1, G2, G4, `b"…"` and `const` should land in Klin before stage 2 starts
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
  bootstrap/shim.c      klrt_syscall6, klrt_slice_u8 … (linked by `@[link]`, bootstrap only;
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

### `sys` — the only target-specific module

Signatures only — each implementation file has its own bodies (or
intrinsics).

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
```

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
fn check(r: i64): !i64 {
    if r < 0 && r >= -4095 { return error(cast(i32, -r)) }
    return r
}
```

So `err` in an `or { }` block **is** the errno (`2` = ENOENT,
`9` = EBADF, `12` = ENOMEM, `13` = EACCES, `21` = EISDIR, `22` = EINVAL).
`out.errno_name(err)` prints the name for messages. Partial `write` and
`EINTR` (4) are retried inside `os.write_all`.

### `os`

```klin
module os
import sys

pub fn open_read(path: []u8): !i32           // path: NUL-terminated bytes
pub fn open_write(path: []u8): !i32          // O_WRONLY | O_CREAT | O_TRUNC, mode 0o755 (output is executable)
pub fn close(fd: i32): !i32
pub fn read(fd: i32, buf: []u8, off: i32, n: i32): !i32
pub fn write_all(fd: i32, buf: []u8, off: i32, n: i32): !i32
pub fn file_size(fd: i32): !i64              // lseek(SEEK_END) + lseek(SEEK_SET)
pub fn read_file(a: *mut arena.Arena, path: []u8): ![]u8
pub fn args(a: *mut arena.Arena): !Args       // v0: /proc/self/cmdline
pub fn exit(code: i32)                       // exit_group; does not return
```

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

pub fn Arena.new(cap: i64): !Arena           // one mmap(PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS)
pub fn alloc_u8(a: *mut Arena, n: i32): ![]u8     // 8-byte aligned, zeroed (fresh mmap pages are zero)
pub fn alloc_i32(a: *mut Arena, n: i32): ![]i32
pub fn alloc_i64(a: *mut Arena, n: i32): ![]i64
pub fn mark(a: *mut Arena): i64
pub fn reset(a: *mut Arena, m: i64)
pub fn free_all(a: *mut Arena)               // munmap
```

Signatures mirror Klin's `stdlib/mem` (`alloc_u8(a: *mut Allocator, n: i32)`),
so the code reads the same as host Klin. No `free` of single blocks —
a compiler allocates per phase and drops whole arenas. Reserve one large
range (e.g. 1 GiB; pages are committed lazily by the kernel) to avoid
chunk chaining in v0. Error = `ENOMEM` from `mmap`.

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
pub fn (mut o: Out) bytes(b: []u8, off: i32, n: i32)
pub fn (mut o: Out) lit(b: []u8)             // whole slice, e.g. o.lit(b"error: ")
pub fn (mut o: Out) dec(v: i64)
pub fn (mut o: Out) hex(v: u64)
pub fn (mut o: Out) nl()
pub fn (mut o: Out) flush(): !i32
```

Explicit buffer, explicit `flush` — no hidden cost. `defer o.flush()`
at the end of `main`.

### Intrinsics Kliner must provide

The complete list of things the core cannot express (stage 4):

| Intrinsic | Lowers to |
|---|---|
| `sys.call6` | `syscall` (x86-64), `svc #0` (ARM64), `ecall` (RV64) |
| `sys.slice_u8/i32/i64(addr, len)` | build `{ptr, len}` — no code |
| `_start` | emitted, not declared |

Everything else in `rt/` is plain core Klin.

---

## C7. Decisions — DECIDED (2026-10-23)

The open questions of this stage, answered by Marek.

1. **Bytes from literals (G5):** Klin gets a byte-string literal
   **`b"fn"` of type `[]u8`**. Compiler code uses `b"…"` for keywords,
   messages and paths; `str` is not used there. *Pending in klin-lang/klin.*
2. **G1 / G2 / G4 are fixed in Klin itself**, not worked around in Kliner
   source. Handed to Klin maintainers. *Pending in klin-lang/klin.*
3. **Module-level `const`** is added to Klin (`pub const PAGE: i64 = 4096`).
   Compiler state lives in a **context struct** passed as `*mut Ctx`;
   **no mutable globals**. *Pending in klin-lang/klin.*
4. **Arguments in v0** come from `/proc/self/cmdline`. OK.
5. **The bootstrap C shim** (`rt/bootstrap/shim.c`) may depend on Klin's
   internal C layout of `[]T`. OK — bootstrap only.

Example with the decided forms:

```klin
module os
import sys

pub const AT_FDCWD: i64 = -100
pub const O_RDONLY: i64 = 0

pub fn args(a: *mut arena.Arena): !Args {
    let fd = open_read(b"/proc/self/cmdline\0")!
    defer close_quiet(fd)          // close, ignore error
    …
}
```

```klin
struct Ctx {
    arena: arena.Arena
    err: out.Out
    src: []u8
    tok_kind: []u8
    tok_start: []i32
}

fn report(c: *mut Ctx, pos: i32) {
    (*c).err.lit(b"error: unexpected token at ")
    (*c).err.dec(cast(i64, pos))
    (*c).err.nl()
}
```
