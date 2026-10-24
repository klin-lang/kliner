# Kliner

Kliner is a native, self-hosted compiler with
[Klin](https://github.com/klin-lang/klin) syntax. It writes machine code
and ELF64 binaries itself — no C, no libc, no LLVM in the default path.

> **Status: stage 1.** Runtime in Klin (`rt/`), no compiler code yet.

```sh
KLIN=/path/to/klin scripts/test.sh     # build + run tests/rt with Klin (Linux x86-64)
```

- `rt/os.kl`, `rt/arena.kl`, `rt/out.kl` — portable runtime (files, args, exit, bump allocator, buffered output)
- `rt/bootstrap/` — `sys` for stage1 (Klin + small C shim over libc `syscall(2)`)
- `rt/linux_x86_64/sys.kl` — `sys` for stage2+ (Kliner intrinsics; not compiled by Klin)

- [Design decisions](docs/00-decisions.md)
- [Roadmap](docs/01-roadmap.md)
- [Core subset and runtime](docs/02-core-subset.md) (stage 1, proposal)
- Klin (compiles to C, bootstraps Kliner): https://github.com/klin-lang/klin
