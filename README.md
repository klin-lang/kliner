# Kliner

Kliner is a native, self-hosted compiler with
[Klin](https://github.com/klin-lang/klin) syntax. It writes machine code
and ELF64 binaries itself — no C, no libc, no LLVM in the default path.

> **Status: design phase.** No compiler code yet.

- [Design decisions](docs/00-decisions.md)
- [Roadmap](docs/01-roadmap.md)
- [Core subset and runtime](docs/02-core-subset.md) (stage 1, proposal)
- Klin (compiles to C, bootstraps Kliner): https://github.com/klin-lang/klin
