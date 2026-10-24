# Backend goldens

`<name>/main.kl` + `main.out` (stdout, then `exit N`; run with `x y`),
for programs whose golden is `kliner-run`'s output because Klin's C
output differs (C14.6). `scripts/test.sh` checks that the native binary
from `kliner-build` prints the same.

Empty for now: `c13` (shift counts ≥ the width, wrapping, `/ −1`,
unsigned compares, casts) moved to [`tests/ir/c13`](../ir/c13) once
Klin main `e6058dc` (#361, D26) fixed K-B6 and K-B5, so the Klin build
now gives the same output.
