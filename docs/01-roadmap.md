# Kliner — roadmap

Stages in order. Decisions behind them: [00-decisions.md](00-decisions.md).
Status: **stage 5 — IR (`src/ir/`) and IR interpreter (`src/vm/`) done; checker (`src/check/`, stage 4), parser (`src/parse.kl`, stage 3), lexer (`src/lex.kl`, stage 2) and runtime (`rt/`, stage 1). All built by Klin (main `a66ffbd`).**

Numbering (**DECIDED 2026-10-24**, [C11.5](02-core-subset.md#c11-stage-3-review--decided-2026-10-24)): the frontend used to be one stage (2: lexer, parser,
checker). It is now split so that each stage ends in one tested
piece: 2 lexer, 3 parser, 4 checker; the later stages moved by two
(IR was 3, now 5; backend 4 → 6; fuller language 5 → 7; self-hosting
6 → 8; targets 7 → 9; after self-hosting 8 → 10). "Stage N" with a
space is a roadmap stage; **stage1 / stage2 / stage3** (no space) are
the bootstrap builds of stage 8.

---

## 1. Core subset + runtime

Proposal: [02-core-subset.md](02-core-subset.md).

- [ ] Define the Klin subset used to write the compiler (no `cimport`, no `asm`)
- [ ] Document what is in the shared core and what is Klin-only
- [ ] Mini runtime on Linux syscalls: `_start`, exit, memory/allocator
  (exit + arena done in `rt/`; `_start` is emitted by the backend, stage 6)
- [x] Runtime: files (open/read/write/close), output, errors — `rt/`, tests: `scripts/test.sh`

## 2. Frontend in Klin: lexer

- [x] Lexer — `src/lex.kl`, dump tool `tools/kliner-lex`; same token stream as
  Klin's lexer on all `.kl` files of Kliner and Klin (`scripts/test.sh`,
  differences: [tests/lex/README.md](../tests/lex/README.md))

## 3. Frontend in Klin: parser

- [x] Parser — `src/parse.kl` → AST in tables (`src/ast.kl`, data model:
  [02-core-subset.md C2](02-core-subset.md#ast--proposed)); diagnostics
  `path:line:col` shared with the lexer (`src/diag.kl`)
- [x] Dump tool `tools/kliner-parse` ([format](03-ast-dump.md)); the same
  dump from Klin's parser in `tools/klin-parse.dart`; identical on all
  `.kl` files of Kliner and Klin except the known differences
  ([tests/parse/README.md](../tests/parse/README.md))
- [x] Built by current Klin
- [x] String interpolation `"…$x…"` — rejected with a clear error; stays
  out of Kliner for now ([C10, DECIDED](02-core-subset.md#c10-fn-and-string-interpolation--decided-2026-10-24))

## 4. Frontend in Klin: checker

- [x] Checker — `src/check/` (names, module imports, types), loader
  `src/load.kl`, types `src/types.kl` ([04-checker.md](04-checker.md))
- [x] `$fn` generics — not in Kliner for now; the lexer rejects `$` like
  Klin's raw lexer ([C10, DECIDED](02-core-subset.md#c10-fn-and-string-interpolation--decided-2026-10-24))
- [x] Built by current Klin
- [x] Compared against Klin's checker on the same inputs (`tools/kliner-check`
  vs `tools/klin-check.dart`; differences: [04-checker.md](04-checker.md#known-differences-from-klin))

## 5. IR + IR interpreter

- [x] Linear three-address IR: virtual registers, basic blocks (implicit, between labels), explicit width per op, no SSA — `src/ir/`, dump `tools/kliner-ir` ([05-ir.md](05-ir.md))
- [x] Lowering from the checked AST to IR (the whole checker subset; the rest is "not supported yet")
- [x] IR interpreter — `src/vm/`, `tools/kliner-run`; runs the runtime demos and Kliner's own lexer, parser, checker and IR dump with output identical to the Klin-built tools
- [x] Golden tests (stdout + exit code, `tests/ir/`), each also checked against the Klin-built binary
- [ ] Decisions C13 (PROPOSED)

## 6. x86-64 backend + ELF64 writer

- [ ] x86-64 instruction encoder
- [ ] Codegen: locals in stack slots, constant folding, immediates, fused compare + branch
- [ ] ELF64 writer (static executable, no libc)
- [ ] **Milestone: hello world without libc**

## 7. Fuller language

- [ ] Structs
- [ ] `!T`
- [ ] `defer`
- [ ] Slices
- [ ] Linear scan register allocation

## 8. Self-hosting

- [ ] stage1: Kliner built by current Klin
- [ ] stage2: built by stage1
- [ ] stage3: built by stage2
- [ ] **stage2 == stage3, byte for byte**

## 9. More targets

- [ ] Linux ARM64
- [ ] Linux RV64 (Orange Pi RV2)
- [ ] Later: macOS (Mach-O, `libSystem`, codesign)
- [ ] Later: Windows (PE, `kernel32`)

## 10. After self-hosting

- [ ] C interop: manual `extern fn` declarations
- [ ] C calling conventions: SysV x86-64, AAPCS64, RISC-V psABI
- [ ] ELF `.o` output + system linker
- [ ] `--link-libc`
- [ ] DWARF `.debug_line`
