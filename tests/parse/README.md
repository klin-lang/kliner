# Parser tests

`scripts/test.sh` runs `kliner-parse` (tools/kliner-parse, built by
Klin) on every `NAME.kl` here: stdout must equal `NAME.ast`, stderr
`NAME.err` (empty if there is none). With `KLIN_SRC` set it also
compares `kliner-parse` with Klin's own parser (`tools/klin-parse.dart`
→ klin `lib/parser.dart`) on every `.kl` file of Kliner and of the Klin
checkout. Format: [docs/03-ast-dump.md](../../docs/03-ast-dump.md).

Files:

- `ok_*.kl` — declarations, statements, expressions, line rules.
- `err_*.kl` — one syntax error each (exit 1); `err_34` checks the `match` retry in `or { }` (D21); `err_33` is a `$fn`
  (lexer error + `note:` on stderr).
- `div_*.kl` — known differences from Klin; the golden is Kliner's
  output, the Klin comparison skips them.

The `ok_*` / `err_*` stdout goldens were written by Klin's parser (main
d7625f1; `ok_or_diverge`, `err_26` and `err_34` by main a66ffbd, D21).

## Known differences from Klin's parser

| Case | Klin (Dart) | Kliner | File |
|---|---|---|---|
| String interpolation `"…$x…"` / `"${e}"` | `InterpolatedStringExpr` | error `string interpolation is not supported by Kliner yet` at the string + note (exit 1) | `div_interp.kl`, `div_interp2.kl`; 4 files in Klin |
| `fn` without a body in `module sys` (Kliner intrinsics, `rt/linux_x86_64/sys.kl`) | ``expected `{` `` | parsed, `fn` node without `block` | `div_sys.kl` |
| Columns after a character outside the BMP | UTF-16 units | code points | tests/lex `div_astral.kl` |
| `$fn`, `$name(...)` | Klin expands them before lexing; raw source: ``unexpected character `$` `` | the same error + note | `err_33.kl` |

Everything else (nodes, positions, error messages and their
positions) is identical on all files compared. Both tools parse the
file as is, without Klin's preprocessing (`$fn`, SVD / `ioc`
rewrites).
