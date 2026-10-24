# Kliner — decision register

One list of every decision Marek has taken for Kliner, in English.
Each entry has the original ID, the date, the decision, a short reason
and a link to the source section (which has the full text and the
alternatives that were rejected). If this register and a source section
disagree, the source section wins. Fix the register in that case.

Status words: **DECIDED** means accepted by Marek. **DEFERRED** means
the decision is "not now, later", also accepted by Marek. Anything still
open is in [Still proposed](#still-proposed) at the end. This file does
not change its status.

Sources: [00-decisions.md](00-decisions.md) (K1–K11),
[02-core-subset.md](02-core-subset.md) (C1–C14),
[01-roadmap.md](01-roadmap.md), [04-checker.md](04-checker.md),
[05-ir.md](05-ir.md), [06-x86-64.md](06-x86-64.md).
Kliner PRs: [#1](https://github.com/klin-lang/kliner/pull/1) to
[#7](https://github.com/klin-lang/kliner/pull/7).

Total: **40** entries (38 DECIDED, 2 DEFERRED).

---

## K — design (2026-10-23)

Source: [00-decisions.md](00-decisions.md), commit `0408fff`.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| K1 | 2026-10-23 | Kliner is a native, self-hosted compiler with Klin syntax. It writes machine code and ELF64 itself. The default path has no C, no libc, no LLVM, no external assembler and no external linker. | Klin goes to readable C. Kliner is the other road from the same source model straight to a binary. | [K1](00-decisions.md#k1-what-kliner-is--decided) |
| K2 | 2026-10-23 | Kliner is written in Klin. Bootstrap: stage1 is built by Klin, stage2 by stage1, stage3 by stage2. The check is stage2 == stage3 byte for byte. Klin stays the fallback bootstrap and the test reference. | Written in Klin it is self-hosted and portable. Assembly would lock it to x86-64, and C or Dart would not be self-hosted. | [K2](00-decisions.md#k2-implementation-language-and-bootstrap--decided) |
| K3 | 2026-10-23 | Targets are PCs and laptops only, no MCUs. Linux x86-64 first and alone until self-hosting. Then Linux ARM64 and RV64. Later macOS and Windows. | Linux has a stable syscall ABI, so a static binary works without libc. MCUs stay with Klin → C. | [K3](00-decisions.md#k3-targets--decided) |
| K4 | 2026-10-23 | Kliner shares Klin's core syntax and types but is not 100% compatible. C-specific features (`cimport`, `asm`, `@[link]` with `.S`, `#line`) give a clear compile error. Every difference is documented. | The core behaves the same in both. C-only features have no meaning without C, and a clear error beats odd behaviour. | [K4](00-decisions.md#k4-compatibility-with-klin--decided) |
| K5 | 2026-10-23 | Modules and imports work as in Klin. Files stay `.kl`. The binary is named `kliner`. | Same source model as Klin. | [K5](00-decisions.md#k5-modules-files-binary-name--decided) |
| K6 | 2026-10-23 | Kliner has its own stdlib, with no libc, written in Klin on Linux syscalls (memory, files, output, errors, math). An optional `--link-libc` comes later. | The compiler needs only a few hundred lines of runtime, so self-hosting does not need libc. | [K6](00-decisions.md#k6-standard-library--decided) |
| K7 | 2026-10-23 | **DEFERRED** until after self-hosting: C interop. The order is manual `extern fn` declarations, then per-target C calling conventions, then ELF `.o` plus the system linker, and maybe `.h` parsing. | Not needed to self-host. Struct passing is the usual source of bugs, so it is done carefully and later. | [K7](00-decisions.md#k7-c-interop--later-after-self-hosting) |
| K8 | 2026-10-23 | Compile speed and simplicity come first. Start with locals in stack slots, constant folding, immediates and fused compare + branch. Linear scan register allocation comes later. No graph colouring and no big optimizer pipelines. | Rubix-lang's lesson: most of its gap to `gcc -O2` came from data widths, not from codegen. Klin already has correct widths. | [K8](00-decisions.md#k8-optimizations--decided) |
| K9 | 2026-10-23 | The IR is linear three-address code with virtual registers, basic blocks and an explicit width on every op. No SSA. An IR interpreter is used for golden tests. | Simple to build and to interpret, and it keeps the widths that matter (K8). | [K9](00-decisions.md#k9-ir--decided) |
| K10 | 2026-10-23 | **DEFERRED** until after self-hosting: debug info (DWARF `.debug_line`). | Not needed to self-host. Until then `gdb` sees addresses only (stage 6 adds `.symtab` names). | [K10](00-decisions.md#k10-debug-info--later) |

## C7 — stage 1 questions (2026-10-23)

Source: [C7](02-core-subset.md#c7-decisions--decided-2026-10-23), recorded in `4cda337` and PR #1.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C7.1 | 2026-10-23 | Klin gets the byte-string literal `b"…"` of type `[]u8`. Compiler code uses it for keywords, messages and paths, and does not use `str`. | The compiler works on bytes. A literal of the right type avoids conversions. Merged in klin #351. | [C7](02-core-subset.md#c7-decisions--decided-2026-10-23) |
| C7.2 | 2026-10-23 | Klin gaps G1, G2 and G4 are fixed in Klin itself, not worked around in Kliner source. | That keeps Kliner source plain core Klin. Merged in klin #351. | [C7](02-core-subset.md#c7-decisions--decided-2026-10-23) |
| C7.3 | 2026-10-23 | Klin gets module-level `const`. Compiler state lives in a context struct passed as `*mut Ctx`, with no mutable globals. | Explicit data flow and no hidden state. Constants cover the fixed values. | [C7](02-core-subset.md#c7-decisions--decided-2026-10-23) |
| C7.4 | 2026-10-23 | In v0, arguments come from `/proc/self/cmdline`. | It needs no `_start` support in stage 1. | [C7](02-core-subset.md#c7-decisions--decided-2026-10-23) |
| C7.5 | 2026-10-23 | The bootstrap C shim (`rt/bootstrap/shim.c`) may depend on Klin's internal C layout of `[]T`. | It is bootstrap only and never part of a native build. | [C7](02-core-subset.md#c7-decisions--decided-2026-10-23) |

## C8 — stage 1 review (2026-10-23)

Source: [C8](02-core-subset.md#c8-review-decisions--decided-2026-10-23), PR #1.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C8.1 | 2026-10-23 | `b"…"` bytes are read-only. For now this is documented only. The checker rejects the direct cases (klin #353, #354, #357). Writing through a mutable place is UB, so compiler code copies into a `[N]u8` or an arena buffer before writing. | The literals live in read-only memory. A full check would need more type machinery than it is worth now. | [C8](02-core-subset.md#c8-review-decisions--decided-2026-10-23) |
| C8.2 | 2026-10-23 | An out-of-range integer literal is a compile error (`const X: u8 = 300`). | Silent truncation hides bugs. Landed as klin #352 (D12). | [C8](02-core-subset.md#c8-review-decisions--decided-2026-10-23) |
| C8.3 | 2026-10-23 | Unary `-` and `~` on a literal take the expected type, like a bare literal (`f(-1)` for an `i64` parameter). | This removes the `cast(i64, -1)` noise. Landed as klin #353 and #354 (D12). | [C8](02-core-subset.md#c8-review-decisions--decided-2026-10-23) |
| C8.4 | 2026-10-23 | `sys.addr_u8(b): i64` and a zeroing `arena.reset(a, m)` are part of the runtime API. | The runtime needs a buffer's address for syscalls. Zeroing makes every `alloc_*` result zeroed (ZII, Klin D6). | [C8](02-core-subset.md#c8-review-decisions--decided-2026-10-23), [C6](02-core-subset.md#c6-runtime--proposed) |

## C10, C11 — stage 3 (2026-10-24)

Sources: [C10](02-core-subset.md#c10-fn-and-string-interpolation--decided-2026-10-24) and [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24). Decided when PR #4 was merged (`8812306`) and recorded in PR #5.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C10.1 | 2026-10-24 | `$fn` generics and `$name(…)` stay out of Kliner for now. The lexer rejects `$` with Klin's message plus a note. Revisit after self-hosting (checker-side generics). | The compiler does not need generics. A text pre-pass would be a second language inside the compiler. | [C10](02-core-subset.md#c10-fn-and-string-interpolation--decided-2026-10-24) |
| C10.2 | 2026-10-24 | String interpolation stays out of Kliner for now and is a parser error. `\$` is a literal `$`. Revisit with a `fmt` runtime. | Kliner source uses `out.lit` and `out.dec`. Interpolation needs a formatting runtime in the backend. | [C10](02-core-subset.md#c10-fn-and-string-interpolation--decided-2026-10-24) |
| C11.1 | 2026-10-24 | Confirms C10: `$fn` and interpolation stay out. | This is the stage 3 recommendation. | [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24) |
| C11.2 | 2026-10-24 | AST model: `Node {kind, tok, a, b, c, extra}` in tables, with children in `kids: []i32`. The node keeps the `tok` field for its `line:col`. | Positions stay regular, and names are never copied. 24 bytes per node instead of 20 is cheap. | [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24), [C2 AST](02-core-subset.md#ast--decided-2026-10-24-c112) |
| C11.3 | 2026-10-24 | A `fn` without a body in `module sys` (Kliner intrinsics, `rt/linux_x86_64/sys.kl`) stays a documented difference from Klin. | The native runtime needs intrinsics. Klin never compiles that file. | [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24) |
| C11.4 | 2026-10-24 | The `ok = f()!` pattern for an ignored `!T` result, kept while `f()!` was not a statement. Update: since Klin #360 (`f9f5471`), ignored results are plain `f()!` statements (not in `main`). | It followed what Klin accepted at each point. | [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24) |
| C11.5 | 2026-10-24 | Roadmap numbering: 2 lexer, 3 parser, 4 checker, 5 IR, 6 backend, 7 fuller language, 8 self-hosting, 9 targets, 10 after self-hosting. | One stage per frontend part gives reviewable PRs. | [C11](02-core-subset.md#c11-stage-3-review--decided-2026-10-24), [roadmap](01-roadmap.md) |

## C12 — stage 4 (2026-10-24)

Source: [C12](02-core-subset.md#c12-stage-4-review--decided-2026-10-24), PR #5.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C12.1 | 2026-10-24 | A partial port of Klin's "complete type" check is enough (Klin `error_175`, `error_207`–`209`). The difference stays documented (`div_typedef`). | Kliner's backend emits no C typedefs, so the check guards nothing there. | [C12](02-core-subset.md#c12-stage-4-review--decided-2026-10-24), [04-checker.md](04-checker.md#known-differences-from-klin) |
| C12.2 | 2026-10-24 | Klin bugs K-B1 and K-B2 are reported to the Klin bot. Nothing is changed in the Klin repo from Kliner's side. | Klin fixes its own bugs (as in C7.2). Both were fixed in `f9f5471`. | [C12](02-core-subset.md#c12-stage-4-review--decided-2026-10-24), [04-checker.md](04-checker.md#klin-bugs-repros) |
| C12.3 | 2026-10-24 | `str` is in Kliner, as Klin D22: literal type, `s.len`, read-only `s[i]`, `cstr_u8(s)`, `main(args: []str)`. Not allowed: `const X: str`, casts, `==` and `match` on `str` (same errors as Klin). Compiler code keeps `[]u8` (C7.1). | User programs use `str`, so the checker must match Klin. | [C12](02-core-subset.md#c12-stage-4-review--decided-2026-10-24) |

## C13 — stage 5 IR (2026-10-24, items 1–4)

Source: [C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24), [05-ir.md](05-ir.md), PR #6.

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C13.1 | 2026-10-24 | The IR is a flat instruction list with labels. Basic blocks are implicit, from a label to `jmp`, `br`, `ret` or `trap`. | It is simpler than a block table, keeps K9, and the backend can split on labels. | [C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24) |
| C13.2 | 2026-10-24 | Every operation wraps at its type (`u8 + u8` is a `u8`). A shift count ≥ the width gives 0, or −1 for a negative signed `>>`. | The declared types are the semantics, not C's promotion or the hardware's count masking. Klin agrees since `e6058dc` (D26). | [C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24) |
| C13.3 | 2026-10-24 | Memory layout is C's natural layout, as in Klin's C. Slices are `{ptr, len i32}` (16 bytes). `!T` is `{is_err u8 @0, err i32 @4, value @8}`. | The same data in both compilers, and the bootstrap shim relies on it (C7.5). | [C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24), [05-ir.md](05-ir.md#memory-layout) |
| C13.4 | 2026-10-24 | IR calling convention: aggregates go by address, the caller copies aggregate arguments into a temporary, aggregate results go through a hidden `sret` parameter, and `mut` receivers go by address. Every local has a frame slot. | One rule for all aggregates. It matches the "locals in stack slots" plan (K8). | [C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24) |

## C14 — stage 6 x86-64 backend (2026-10-24)

Source: [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24), [06-x86-64.md](06-x86-64.md), PR [#7](https://github.com/klin-lang/kliner/pull/7). Marek accepted all seven after merging #7 (`5d31ba4`).

| ID | Date | Decision | Why | Source |
|---|---|---|---|---|
| C14.1 | 2026-10-24 | Kliner uses its own calling convention, not SysV: all arguments on the stack (`[rsp + 8j]`), the result in `rax`, and no callee-saved registers except `rbp`. SysV comes with C interop. | It is the simplest form with no register allocator. Nothing calls C yet (K7). | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.2 | 2026-10-24 | `_start` maps a 1 GiB `MAP_NORESERVE` stack with a 1 MiB guard and a `SIGSEGV` handler on an alternate stack. If the `mmap` fails, the program falls back to the kernel stack. | Deep recursion works, and a stack overflow becomes a clear trap instead of a bare SIGSEGV. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.3 | 2026-10-24 | A trap prints `kliner: trap: MESSAGE` on stderr and exits with 134. Integer `MIN / −1` wraps and does not trap. | Same behaviour as `kliner-run`, and the wrapping follows C13.2. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.4 | 2026-10-24 | Only functions reachable from `main` and `$init` are emitted. | hello went from 53 KB to 18 KB. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.5 | 2026-10-24 | Output is a static `ET_EXEC` at `0x400000`, with data at `0x10000000` and a `.symtab`. No PIE and no debug info. | It is the simplest valid executable, and objdump and gdb still show names. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.6 | 2026-10-24 | The tool is `kliner-build FILE.kl -o OUT` (one `kliner` driver later). Backend goldens where Klin's C differs go in `tests/x64`, with `kliner-run` as the reference. | Klin stays the reference wherever it agrees. The directory is empty since Klin `e6058dc`. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24) |
| C14.7 | 2026-10-24 | Stage 6 has no register allocator and no folding: every IR value lives in a frame slot. Linear scan, constant folding, immediates and fused compare + branch move to stage 7. | Correctness and the self-compilation fixpoint first. This is the cause of the 2.5–3.8× gap to `gcc -O0`. | [C14](02-core-subset.md#c14-stage-6-x86-64-backend--decided-2026-10-24), [roadmap](01-roadmap.md) |

Roadmap consequence (2026-10-24): stage 8 "stage2 == stage3, byte
for byte" is ticked. The `kliner-build` fixpoint was reached in PR #7
([01-roadmap.md](01-roadmap.md#8-self-hosting)).

---

## Still proposed

Not decided. The statuses are unchanged here, and Marek decides.

- **C1–C4, C6 as a whole:** the core rule, the IN / LATER / NOT IN
  lists and the runtime design
  ([02-core-subset.md](02-core-subset.md)). The C8.4 API parts are
  decided.
- **C2 Data model:** compiler state in tables (slices of structs,
  `i32` indices) ([02-core-subset.md](02-core-subset.md#data-model--proposed)).
- **C9.1–C9.3:** module-level `let mut` for compiler state, arguments
  via `main(args: []str)`, slices of structs instead of
  struct-of-arrays
  ([C9](02-core-subset.md#c9-sync-with-klin-main--proposed)).
- **C12.4:** switch `os.args` to `main(args: []str)` together with
  `_start` passing argc / argv. This is an option, not a change; v0
  keeps C7.4 ([C12](02-core-subset.md#c12-stage-4-review--decided-2026-10-24)).
- **C13.5–C13.8:** the checker records name resolution, the
  interpreter runs on host memory with pass-through syscalls (exit
  134), the "not supported yet" list in the lowering, and `argv[0]`
  being the `.kl` path under `kliner-run` with the 10 000-call depth cap
  ([C13](02-core-subset.md#c13-stage-5-ir--partly-decided-2026-10-24)).
- **K11:** the exact core-subset feature list, the format of the
  documented Klin ↔ Kliner differences, and macOS / Windows details
  ([K11](00-decisions.md#k11-to-decide-later)).
