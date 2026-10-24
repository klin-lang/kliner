# Kliner — AST dump format (stage 3)

`tools/kliner-parse FILE` (Kliner's parser) and `tools/klin-parse.dart
FILE` (Klin's `lib/parser.dart`) print the same canonical text, so
`scripts/test.sh` can compare them byte for byte.

```
TAG @LINE:COL key=value ...
```

- One node per line; children follow, indented two more spaces.
- `@LINE:COL` is the position Klin's parser stores for the node (1-based;
  columns count code points in Kliner, UTF-16 units in Klin — see
  tests/lex/README.md). `unit` and `arm` have none.
- Values: strings in `"…"` — `\` is `\\`, `"` is `\x22`, bytes outside
  printable ASCII are `\xHH` (UTF-8 bytes); absent is `-`; flags `0` / `1`.
- Types are Klin's type strings: `i32`, `m.T`, `*u8`, `*mut volatile T`,
  `[]T`, `[N * 2]T` (length tokens joined by spaces, none around `.`),
  `!T`, `fn(a,b):r` (`void` without a return type).
- Lexical or syntax error: only `LINE:COL: message` (Klin's text) on
  stdout, exit 1. Kliner adds a `note:` line on stderr for features it
  does not support yet (`$`, string interpolation — 02-core-subset.md C10).

## Tags

Declarations (children: `attr` first, then the parts listed):

| Tag | Keys | Children |
|---|---|---|
| `unit` | `module` | `import`…, declarations… |
| `import` | `spec` `path` (1 = string spec) `alias` | — |
| `attr` | `name` `arg` | — |
| `struct` | `name` `npos` (position of the name) `pub` | `field`… |
| `field` | `name` `type` | — |
| `enum` | `name` `npos` `pub` `base` | `variant`… (child: value) |
| `const` | `name` `npos` `pub` `type` | value |
| `global` | `name` `npos` `pub` `mut` `type` | value? |
| `fn` | `name` `npos` `pub` `async` `assoc` `ret` | `recv`? `param`… `block`? |
| `recv` / `param` | `name` (`mut`) `type` | — |

Statements: `block`; `asm code=`; `let name= mut= short= type=` (value);
`let-struct mut= binds="field:binding,…"`; `let-array mut= names="a,_"`;
`assign op=` (`-` for `=`, else the operator without `=`; target,
value); `multi-assign n=` (targets, values); `struct-assign fields=`
(targets, source); `if` (cond, then, else?); `while`; `for-range name=`
(start, end, body); `for-c init= decl= cond= post= op=` (init?, cond?,
post?, body); `return` (value?); `break`; `continue`; `defer` (stmt);
`match` / `match-expr` (subject, `arm guard=`…: pattern, guard?, body).
A call or method call used as a statement prints as the expression.

Patterns: `pat-lit` (values), `pat-range` (low, high), `pat-rel op=`,
`pat-wild`, `pat-else`.

Expressions: `int v=`, `float v=`, `bool v=`, `str v=` (decoded; `\$` is
`$`), `bytes v=`, `interp` (Klin only), `name v=`, `get name=` (object),
`mcall name=` (receiver, args), `struct-lit mod= type= named= fields=`,
`call mod= name=` (args), `unary op=`, `binary op=`, `index`,
`slice start= end=`, `array`, `cast type=`, `group`, `error`,
`propagate` (`!`), `await`, `or` (value, `or-block n=`: statements then
the final value), `pick` (cond, then, else).
