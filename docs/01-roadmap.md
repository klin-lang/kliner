# Kliner — roadmap

Stages in order. Decisions behind them: [00-decisions.md](00-decisions.md).
Status: **stage 7 — RV64 backend (`src/rv64/`, shared `src/back/`) done; x86-64 backend (`src/x64/`, stage 6), IR and interpreter (stage 5), checker, parser, lexer and runtime (stages 1–4). All built by Klin (`e6058dc`).**

Numbering (**DECIDED 2026-10-24**, [C11.5](02-core-subset.md#c11-stage-3-review--decided-2026-10-24)): the frontend used to be one stage (2: lexer, parser,
checker). It is now split so that each stage ends in one tested
piece: 2 lexer, 3 parser, 4 checker; the later stages moved by two
(IR was 3, now 5; backend 4 → 6; fuller language 5 → 7; self-hosting
6 → 8; targets 7 → 9; after self-hosting 8 → 10). "Stage N" with a
space is a roadmap stage; **stage1 / stage2 / stage3** (no space) are
the bootstrap builds of stage 9 (self-hosting).

Order (**DECIDED 2026-10-24**, [C15.1](02-core-subset.md#c15-stage-7-rv64-backend--partly-decided-2026-10-24)):
the RV64 backend comes right after the x86-64 one, before the
optimizations; the stages after 6 moved by one (fuller language +
optimizations 7 → 8, self-hosting 8 → 9, more targets 9 → 10, after
self-hosting 10 → 11).

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
- [ ] Decisions C13: 1–4 DECIDED (2026-10-24: labels, wrapping, C layout, calling convention / frame slots); 5–8 PROPOSED

## 6. x86-64 backend + ELF64 writer

- [x] x86-64 instruction encoder — `src/x64/enc.kl` ([06-x86-64.md](06-x86-64.md))
- [x] Codegen from the IR: locals in stack slots, no register allocator — `src/x64/gen.kl`; small copies / zeroing inline, fall-through jumps dropped
- [ ] Constant folding, immediates, fused compare + branch — moved to stage 8 (with the register allocator)
- [x] ELF64 writer (static executable, no libc, no external linker; `.symtab` for objdump / gdb) — `src/back/elf.kl` (shared with RV64 since stage 7), `tools/kliner-build`
- [x] **Milestone: hello world without libc** (`tests/rt/hello`: 18 KB static ELF64, no `PT_INTERP`, no dynamic section)
- [x] Backend goldens: `tests/ir` (= Klin = kliner-run), `tests/x64` (C13 edges), `tests/rt` hello / alloc / args / cat, traps
- [x] Kliner's lexer, parser, checker, IR dump, interpreter and `kliner-build` compiled by `kliner-build`: output identical to the Klin-built tools; `kliner-build` rebuilds itself byte for byte
- [x] Decisions C14 (backend): DECIDED 2026-10-24

## 7. RV64 backend (Linux RISC-V 64)

Plan: [07-rv64.md](07-rv64.md). Target board: Orange Pi RV2.

- [x] Shared backend part — `src/back/`: reachable functions, helper / trap list, constant normalization, the static ELF64 writer (x86-64 output unchanged byte for byte)
- [x] RV64IM encoder — `src/rv64/enc.kl` (no compressed instructions, no floats)
- [x] Codegen from the same IR — `src/rv64/gen.kl`: locals in stack slots as on x86-64; C13 / C14 kept (wrapping, shifts, traps with exit 134, 1 GiB stack with a guard)
- [x] `_start`, syscalls from the generic table — `rt/linux_riscv64/sys.kl`; ELF64 `EM_RISCV`
- [x] `kliner-build --target x64|rv64` (default: the host the compiler was built for)
- [x] Tests under `qemu-riscv64` (user mode): `tests/ir` goldens, hello / alloc / args / cat, traps; Kliner's lexer, parser, checker, IR dump and interpreter for rv64 = the Klin-built tools
- [x] **Cross fixpoint:** `kliner-build` for rv64 rebuilds itself under qemu byte for byte, and equals what the x86-64 `kliner-build` makes
- [ ] Run on a real board (Orange Pi RV2) — instructions in [07-rv64.md](07-rv64.md#test-on-an-orange-pi-rv2), for Marek
- [ ] Decisions C15: 1 DECIDED (2026-10-24: RV64 before the optimizations); 2–8 PROPOSED

## 8. Fuller language + optimizations

- [ ] Structs
- [ ] `!T`
- [ ] `defer`
- [ ] Slices
- [ ] Linear scan register allocation
- [ ] Constant folding, immediate operands, fused compare + branch (from stage 6; on both backends)

(Structs, `!T`, `defer` and slices already go through the IR and the
x86-64 / RV64 backends since stages 5–7; what stays open here is the rest of
Klin — floats, `$fn`, interpolation, `pick`, `async`.)

## 9. Self-hosting

- [ ] stage1: Kliner built by current Klin
- [ ] stage2: built by stage1
- [ ] stage3: built by stage2
- [x] **stage2 == stage3, byte for byte**

(Reached in stage 6, PR #7, for `kliner-build`: Klin-built stage 1 →
native stage 2 → stage 3, stage 2 == stage 3 byte for byte, checked by
`scripts/test.sh`. Ticked 2026-10-24 on Marek's approval. The
stage1–stage3 builds above exist for `kliner-build` as well; those
boxes are left for Marek, since K5 names the compiler `kliner`.)

## 10. More targets

- [ ] Linux ARM64 (same generic syscall table as RV64: `rt/linux_riscv64/sys.kl` is a start)
- [x] Linux RV64 (Orange Pi RV2) — moved forward to stage 7
- [ ] Later: macOS (Mach-O, `libSystem`, codesign)
- [ ] Later: Windows (PE, `kernel32`)

## 11. After self-hosting

- [ ] C interop: manual `extern fn` declarations
- [ ] C calling conventions: SysV x86-64, AAPCS64, RISC-V psABI
- [ ] ELF `.o` output + system linker
- [ ] `--link-libc`
- [ ] DWARF `.debug_line`
