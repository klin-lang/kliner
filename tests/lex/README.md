# Lexer tests

`scripts/test.sh` runs `kliner-lex` (tools/kliner-lex, built by Klin) on
every `NAME.kl` here and compares the output with `NAME.tok`; with
`KLIN_SRC` set it also compares `kliner-lex` with Klin's own lexer
(`tools/klin-lex.dart` → klin `lib/lexer.dart`) on every `.kl` file of
Kliner and of the Klin checkout.

Dump format, one token per line:

    LINE:COL KIND TEXT

- `LINE:COL` from 1; `KIND` is Klin's `TokenKind` name (`fn`, `enum_`,
  `intLit`, `lessLessEqual`, `eof`, …).
- `TEXT` is the source text; for `string` / `byteString` the value
  between the quotes with escapes resolved (in a `string`, `\$` stays
  `\$`). Bytes outside printable ASCII are `\xHH`, `\` is `\\`.
- A lexical error prints only `LINE:COL: message` (Klin's message text)
  and exits 1.

Files:

- `ok_*.kl` — valid token streams: all operators, keywords, numbers,
  char literals, strings, CRLF, no final newline, empty file, UTF-8.
- `err_*.kl` — one lexical error each (exit 1).
- `div_*.kl` — known differences from Klin; the golden is Kliner's
  output, the Klin comparison skips them.

The `ok_*` / `err_*` goldens were written by Klin's lexer (main
d7625f1).

## Known differences from Klin's lexer

| Case | Klin (Dart) | Kliner | File |
|---|---|---|---|
| Column after a character outside the BMP (emoji) in a string or comment | counts UTF-16 units (2 per such character) | counts code points (1) | `div_astral.kl` |
| Source that is not valid UTF-8 | file read fails | lexed as bytes (bad bytes only matter inside strings / comments, elsewhere `unexpected character`) | — |
| `//` comments | kept in a side list (for `klin fmt`) | skipped | — |

Everything else (token kinds, text, positions, error messages and their
positions, `$` rejected) is the same on the 400+ files compared.
