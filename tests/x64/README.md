# Backend goldens

`<name>/main.kl` + `main.out` (stdout, then `exit N`; run with `x y`).
The golden is `kliner-run`'s output; `scripts/test.sh` checks that the
native binary from `kliner-build` prints the same. These programs are
not in `tests/ir` because Klin's C output differs on them (K-B6:
shift counts ≥ the width of `i32` / `u32` / `i64` / `u64`).

- `c13` — C13.2 edges: shifts by ≥ the width, wrapping, `/ −1`,
  unsigned compares, casts.
