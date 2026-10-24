# Kliner — roadmap

Stages in order. Decisions behind them: [00-decisions.md](00-decisions.md).
Status: **stage 2 — frontend: lexer (`src/lex.kl`) done; runtime (`rt/`) from stage 1. Both built by Klin.**

---

## 1. Core subset + runtime

Proposal: [02-core-subset.md](02-core-subset.md).

- [ ] Define the Klin subset used to write the compiler (no `cimport`, no `asm`)
- [ ] Document what is in the shared core and what is Klin-only
- [ ] Mini runtime on Linux syscalls: `_start`, exit, memory/allocator
  (exit + arena done in `rt/`; `_start` is emitted by the backend, stage 4)
- [x] Runtime: files (open/read/write/close), output, errors — `rt/`, tests: `scripts/test.sh`

## 2. Frontend in Klin

- [x] Lexer — `src/lex.kl`, dump tool `tools/kliner-lex`; same token stream as
  Klin's lexer on all `.kl` files of Kliner and Klin (`scripts/test.sh`,
  differences: [tests/lex/README.md](../tests/lex/README.md))
- [ ] Parser
- [ ] Checker (types)
- [ ] `$fn` generics (Klin expands `$fn` / `$name(…)` before lexing; the
  lexer rejects `$` like Klin's does — needs a pre-pass or a `$` token)
- [ ] Built by current Klin
- [ ] Compared against the Dart compiler on the same inputs

## 3. IR + IR interpreter

- [ ] Linear three-address IR: virtual registers, basic blocks, explicit width per op, no SSA
- [ ] Lowering from the checked AST to IR
- [ ] IR interpreter
- [ ] Golden tests (expected output per input)

## 4. x86-64 backend + ELF64 writer

- [ ] x86-64 instruction encoder
- [ ] Codegen: locals in stack slots, constant folding, immediates, fused compare + branch
- [ ] ELF64 writer (static executable, no libc)
- [ ] **Milestone: hello world without libc**

## 5. Fuller language

- [ ] Structs
- [ ] `!T`
- [ ] `defer`
- [ ] Slices
- [ ] Linear scan register allocation

## 6. Self-hosting

- [ ] stage1: Kliner built by current Klin
- [ ] stage2: built by stage1
- [ ] stage3: built by stage2
- [ ] **stage2 == stage3, byte for byte**

## 7. More targets

- [ ] Linux ARM64
- [ ] Linux RV64 (Orange Pi RV2)
- [ ] Later: macOS (Mach-O, `libSystem`, codesign)
- [ ] Later: Windows (PE, `kernel32`)

## 8. After self-hosting

- [ ] C interop: manual `extern fn` declarations
- [ ] C calling conventions: SysV x86-64, AAPCS64, RISC-V psABI
- [ ] ELF `.o` output + system linker
- [ ] `--link-libc`
- [ ] DWARF `.debug_line`
