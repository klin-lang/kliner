# Kliner

Kliner is a native, self-hosted compiler with
[Klin](https://github.com/klin-lang/klin) syntax. It writes machine code
and ELF64 binaries itself — no C, no libc, no LLVM in the default path.

> **Status: stage 7, RV64 backend done** (Linux RISC-V 64, tested
> under `qemu-riscv64`; stage 6: x86-64). Runtime in Klin (`rt/`),
> lexer (`src/lex.kl`), parser (`src/parse.kl`), checker (`src/check/`)
> — Klin without `$fn`, string interpolation, floats, `pick`,
> `async` (`str` is supported, C12.3); linear IR (`src/ir/`) and its
> interpreter (`src/vm/`); x86-64 code generator and static ELF64
> writer (`src/x64/`, no libc, no linker), RISC-V 64 code generator
> (`src/rv64/`): `kliner-build` compiles Kliner's own tools for both —
> and itself, to a byte-identical fixpoint, also across targets.

```sh
KLIN=/path/to/klin scripts/test.sh     # build + run tests/rt, tests/lex, tests/parse, tests/check, tests/ir, tests/x64 with Klin (Linux x86-64; + rv64 under qemu-riscv64 if installed)
KLIN=/path/to/klin KLIN_SRC=/path/to/klin-checkout scripts/test.sh
                                       # + compare lexer, parser and checker with Klin's own (needs dart)
```

- `rt/os.kl`, `rt/arena.kl`, `rt/out.kl` — portable runtime (files, args, exit, bump allocator, buffered output)
- `rt/bootstrap/` — `sys` for stage1 (Klin + small C shim over libc `syscall(2)`)
- `rt/linux_x86_64/sys.kl`, `rt/linux_riscv64/sys.kl` — `sys` for stage2+ per target (Kliner intrinsics, syscall numbers; not compiled by Klin)
- `src/diag.kl` — diagnostics `path:line:col: message` (+ `note:`), shared by lexer and parser
- `src/lex.kl` — lexer: bytes → `[]Token` (kind, offset, length) + line table, in the arena
- `src/ast.kl`, `src/parse.kl` — parser: tokens → AST in tables (`Node` + `[]i32` children)
- `tools/kliner-lex/` — `kliner-lex FILE` token dump; `tools/klin-lex.dart` — the same dump with Klin's lexer
- `tests/lex/` — lexer goldens and known differences from Klin ([README](tests/lex/README.md))
- `tools/kliner-parse/` — `kliner-parse FILE` AST dump ([format](docs/03-ast-dump.md)); `tools/klin-parse.dart` — the same dump with Klin's parser
- `tests/parse/` — parser goldens and known differences from Klin ([README](tests/parse/README.md))
- `src/load.kl` — project loader (entry file, siblings, imports; port of Klin's `loadProject`)
- `src/types.kl`, `src/tab.kl` — interned types, name tables
- `src/check/` — checker: names, module imports, types ([docs](docs/04-checker.md))
- `tools/kliner-check/` — `kliner-check [--lib] [-I DIR]... FILE`; `tools/klin-check.dart` — the same with Klin's checker
- `tests/check/` — checker goldens and known differences ([README](tests/check/README.md))
- `src/ir/` — linear IR and the lowering from the checked AST ([docs](docs/05-ir.md)); `src/vm/` — IR interpreter
- `tools/kliner-ir/` — `kliner-ir [-I DIR]... FILE` IR dump; `tools/kliner-run/` — `kliner-run [-I DIR]... FILE.kl [ARG]...` (interprets, e.g. `-I rt/linux_x86_64 -I rt -I src`)
- `tests/ir/` — program goldens (stdout + exit code), compared with the Klin-built binaries
- `src/back/` — shared backend parts and the ELF64 writer; `src/x64/` — x86-64 encoder and code generator ([docs](docs/06-x86-64.md)); `src/rv64/` — RV64IM encoder and code generator ([docs](docs/07-rv64.md))
- `tools/kliner-build/` — `kliner-build [--target x64|rv64] [-I DIR]... FILE.kl -o OUT` (e.g. `-I rt/linux_x86_64 -I rt -I src`; for rv64 `-I rt/linux_riscv64 …`)
- `tests/x64/` — backend goldens where Klin's C differs (reference `kliner-run`; empty since Klin `e6058dc`)

```sh
tools/kliner-build/out/main -I rt/linux_x86_64 -I rt tests/rt/hello/main.kl -o hello && ./hello
tools/kliner-build/out/main --target rv64 -I rt/linux_riscv64 -I rt tests/rt/hello/main.kl -o hello-rv && qemu-riscv64 ./hello-rv
```

- [All decisions (register, English)](docs/decisions.md)
- [Design decisions](docs/00-decisions.md)
- [Roadmap](docs/01-roadmap.md)
- [Core subset and runtime](docs/02-core-subset.md) (stage 1, proposal)
- [AST dump format](docs/03-ast-dump.md)
- [Checker](docs/04-checker.md)
- [IR and interpreter](docs/05-ir.md)
- [x86-64 backend and ELF64](docs/06-x86-64.md)
- [RV64 backend, Orange Pi RV2 test](docs/07-rv64.md)
- Klin (compiles to C, bootstraps Kliner): https://github.com/klin-lang/klin
