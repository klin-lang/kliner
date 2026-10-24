# Checker tests

`scripts/test.sh` runs `kliner-check` (tools/kliner-check, built by Klin)
on every `NAME.kl` here (and `mod_N/main.kl`): stdout must equal
`NAME.out` — `ok` (exit 0) or `L:C: message` (exit 1). Files named
`*lib_*` are checked with `--lib` (no `main`). With `KLIN_SRC` set the
same files are also checked with Klin's checker (`tools/klin-check.dart`)
and must give the same line. Docs: [docs/04-checker.md](../../docs/04-checker.md).

- `ok_*`, `err_*` — own cases (one error each); goldens written by
  Klin's checker (main `a66ffbd`).
- `mod_N/` — projects with imports (`util/`, `other/`): private
  symbols, wrong module, module globals / consts / structs / enums,
  errors inside an imported module; golden `mod_N.out`.
- `klin/` — 277 snippets from Klin's `test/pipeline_*_test.dart`, kept
  where both checkers agree; goldens by Klin.
- `div_*` — known differences; the golden is Kliner's output, the Klin
  comparison skips them.
