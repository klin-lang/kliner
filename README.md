# Kliner

Kliner is a native, self-hosted compiler with
[Klin](https://github.com/klin-lang/klin) syntax. It writes machine code
and ELF64 binaries itself — no C, no libc, no LLVM in the default path.

> **Status: stage 2 (frontend), lexer done.** Runtime in Klin (`rt/`),
> lexer (`src/lex.kl`); no parser yet.

```sh
KLIN=/path/to/klin scripts/test.sh     # build + run tests/rt and tests/lex with Klin (Linux x86-64)
KLIN=/path/to/klin KLIN_SRC=/path/to/klin-checkout scripts/test.sh
                                       # + compare the lexer with Klin's own (needs dart)
```

- `rt/os.kl`, `rt/arena.kl`, `rt/out.kl` — portable runtime (files, args, exit, bump allocator, buffered output)
- `rt/bootstrap/` — `sys` for stage1 (Klin + small C shim over libc `syscall(2)`)
- `rt/linux_x86_64/sys.kl` — `sys` for stage2+ (Kliner intrinsics; not compiled by Klin)
- `src/lex.kl` — lexer: bytes → `[]Token` (kind, offset, length) + line table, in the arena
- `tools/kliner-lex/` — `kliner-lex FILE` token dump; `tools/klin-lex.dart` — the same dump with Klin's lexer
- `tests/lex/` — lexer goldens and known differences from Klin ([README](tests/lex/README.md))

- [Design decisions](docs/00-decisions.md)
- [Roadmap](docs/01-roadmap.md)
- [Core subset and runtime](docs/02-core-subset.md) (stage 1, proposal)
- Klin (compiles to C, bootstraps Kliner): https://github.com/klin-lang/klin
