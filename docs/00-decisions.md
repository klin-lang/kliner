# Kliner — design decisions

This is the decision log (K1–K11) for Kliner, decided on 2026-10-23.
No compiler code exists yet. For the stage plan see
[01-roadmap.md](01-roadmap.md). For the language itself see
[Klin](https://github.com/klin-lang/klin) and its
[00-idea.md](https://github.com/klin-lang/klin/blob/main/docs/00-idea.md) /
[01-decisions.md](https://github.com/klin-lang/klin/blob/main/docs/01-decisions.md).

---

## K1. What Kliner is — DECIDED

**Choice: a native, self-hosted compiler with Klin syntax.**

Kliner generates machine code directly and writes ELF64 files itself.
The default path has **no C, no libc, no LLVM, no external assembler and
no external linker**.

Klin compiles to readable C and that stays its goal. Kliner is the
other road: the same source model, straight to a binary.

---

## K2. Implementation language and bootstrap — DECIDED

**Choice: Kliner is written in Klin.**

Bootstrap:

1. **stage1** — Kliner sources compiled by current Klin
   (Dart → C → `gcc`/`clang`).
2. **stage2** — stage1 compiles Kliner sources.
3. **stage3** — stage2 compiles Kliner sources.

Check: **stage2 == stage3, byte for byte.**

After that, each new Kliner is built by the previous Kliner. Current Klin
stays as the **fallback bootstrap path** (rebuilding Kliner from zero)
and as the **reference for tests** (same inputs, compare behaviour).

Rejected:
- **ASM** — the whole compiler in assembly locks it to x86-64, as in
  Rubix-lang. ARM64 and RISC-V would mean a rewrite. Assembly is allowed
  only for the minimum, if needed at all (`_start`, syscall stubs).
- **C / Dart as the long-term implementation** — not self-hosted.

---

## K3. Targets — DECIDED

**Choice: PCs and laptops only. No microcontrollers.**

MCUs stay with Klin → C (vendor toolchains, Thumb-2, AVR, RV32, …).
Kliner targets 64-bit desktop/server CPUs only.

Order:

1. **Linux x86-64**, ELF64 — first and only target until self-hosting.
2. **Linux ARM64** and **Linux RV64** (Orange Pi RV2).
3. Later: **macOS** (Mach-O; must link `libSystem`, binaries must be
   codesigned) and **Windows** (PE; goes through `kernel32`).

Linux is first because it has a stable syscall ABI: a static binary
works with no libc at all.

---

## K4. Compatibility with Klin — DECIDED

**Choice: shared core syntax and types; not 100% compatible.**

- The core (syntax, types, modules, `!T`, `defer`, slices, `$fn`, …)
  behaves the same in Klin and Kliner.
- C-specific features are **not supported** in Kliner and give a
  **clear compile error**, not odd behaviour:
  - `cimport`
  - `asm("...")`
  - `@[link]` with `.S` files
  - `#line`
- Every difference is documented explicitly.
- The Kliner compiler itself is written in the shared core, so current
  Klin can build it (K2).

---

## K5. Modules, files, binary name — DECIDED

- Imports of `.kl` modules work as in Klin
  ([12-modules.md](https://github.com/klin-lang/klin/blob/main/docs/12-modules.md)).
- Source files stay `.kl`.
- The compiler binary is named `kliner`.

---

## K6. Standard library — DECIDED

**Choice: own stdlib, no libc, written in Klin on top of Linux syscalls.**

Contents (first pass):
- memory / allocator (explicit allocator, as in Klin D1)
- files
- output
- errors
- math done in Klin: `sqrt` as a CPU instruction; `sin`, `cos`, `exp`,
  `log` via polynomial approximations

The compiler needs little: memory, files, text output, errors. That is
a few hundred lines on syscalls, so self-hosting does not need libc.

Later: optional **`--link-libc`** for calling C libraries. macOS and
Windows will need system libraries anyway (no stable syscalls there).

---

## K7. C interop — LATER (after self-hosting)

Order:

1. Manual declarations in Klin, e.g. `extern fn sin(x: f64): f64`.
2. C calling convention per target: SysV x86-64, AAPCS64, RISC-V psABI.
   Struct passing is the usual source of bugs.
3. ELF `.o` output, linked by the system linker.
4. Parsing `.h` headers — maybe later (needs a C preprocessor + parser).

---

## K8. Optimizations — DECIDED

**Choice: compile speed and simplicity first.**

Lesson from Rubix-lang: on the sieve benchmark it was **6.6× slower than
`gcc -O2`**, but only **~22%** of that was weaker codegen. The rest came
from **8-byte array elements**. Correct data widths (`u8`, `i32`) matter
more than an optimizer — and Klin already has them.

Start:
- locals in stack slots
- constant folding
- immediates in instructions
- fused compare + branch

Later:
- linear scan register allocation

Rejected:
- graph-coloring register allocation
- large optimizer pipelines

---

## K9. IR — DECIDED

**Choice: linear three-address code.**

- virtual registers
- basic blocks
- explicit width on every op (`u8`, `i32`, `i64`, …)
- **no SSA**

An IR interpreter is used for golden tests (see roadmap stage 5).

---

## K10. Debug info — LATER

DWARF `.debug_line` (source line ↔ address), after self-hosting.
Without it `gdb` sees only addresses.

---

## K11. To decide later

- Exact list of core-subset features used by the compiler (roadmap stage 1).
- Format of the documented Klin ↔ Kliner differences.
- macOS / Windows details.
