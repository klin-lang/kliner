# Kliner

Kliner is a native, self-hosted compiler with
[Klin](https://github.com/klin-lang/klin) syntax. It writes machine code
and ELF64 binaries itself — no C, no libc, no LLVM in the default path.

> **Status: stage 4 (frontend), checker done.** Runtime in Klin (`rt/`),
> lexer (`src/lex.kl`), parser (`src/parse.kl`), checker (`src/check/`)
> — Klin without `$fn`, string interpolation, `str`, floats, `pick`,
> `async`; no IR / backend yet.

```sh
KLIN=/path/to/klin scripts/test.sh     # build + run tests/rt, tests/lex, tests/parse, tests/check with Klin (Linux x86-64)
KLIN=/path/to/klin KLIN_SRC=/path/to/klin-checkout scripts/test.sh
                                       # + compare lexer, parser and checker with Klin's own (needs dart)
```

- `rt/os.kl`, `rt/arena.kl`, `rt/out.kl` — portable runtime (files, args, exit, bump allocator, buffered output)
- `rt/bootstrap/` — `sys` for stage1 (Klin + small C shim over libc `syscall(2)`)
- `rt/linux_x86_64/sys.kl` — `sys` for stage2+ (Kliner intrinsics; not compiled by Klin)
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

- [Design decisions](docs/00-decisions.md)
- [Roadmap](docs/01-roadmap.md)
- [Core subset and runtime](docs/02-core-subset.md) (stage 1, proposal)
- [AST dump format](docs/03-ast-dump.md)
- [Checker](docs/04-checker.md)
- Klin (compiles to C, bootstraps Kliner): https://github.com/klin-lang/klin
