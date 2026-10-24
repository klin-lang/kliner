#!/bin/sh
# Build and run the runtime demos in tests/rt with Klin (stage1:
# -I rt/bootstrap -I rt) and check their output. Linux x86-64.
#
#   scripts/test.sh                 # klin from PATH
#   KLIN=/path/to/klin scripts/test.sh
#
# Each demo is tests/rt/<name>/main.kl (one directory each: Klin merges
# the files of a directory into one module). `klin main.kl` builds
# tests/rt/<name>/out/main and runs it once without arguments; that run
# is discarded and the binary is then run with the test's arguments.
set -u
KLIN=${KLIN:-klin}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
pass=0

build() { # name
    dir="$ROOT/tests/rt/$1"
    rm -rf "$dir/out"
    (cd "$dir" && "$KLIN" -I "$ROOT/rt/bootstrap" -I "$ROOT/rt" main.kl) >"$TMP/$1.build" 2>&1
    if [ ! -x "$dir/out/main" ]; then
        echo "FAIL build $1"; sed 's/^/  /' "$TMP/$1.build"; fail=$((fail + 1)); return 1
    fi
    BIN="$dir/out/main"
}

# check NAME WANT_RC WANT_STDOUT_FILE WANT_STDERR_FILE -- cmd...
check() {
    name=$1 want_rc=$2 want_out=$3 want_err=$4; shift 5
    "$@" >"$TMP/out" 2>"$TMP/err" </dev/null
    rc=$?
    ok=1
    [ "$rc" = "$want_rc" ] || { echo "FAIL $name: exit $rc, want $want_rc"; ok=0; }
    cmp -s "$TMP/out" "$want_out" || { echo "FAIL $name: stdout"; diff "$want_out" "$TMP/out" | sed 's/^/  /'; ok=0; }
    cmp -s "$TMP/err" "$want_err" || { echo "FAIL $name: stderr"; diff "$want_err" "$TMP/err" | sed 's/^/  /'; ok=0; }
    if [ $ok = 1 ]; then echo "ok   $name"; pass=$((pass + 1)); else fail=$((fail + 1)); fi
}

want() { cat >"$TMP/$1"; }
: >"$TMP/empty"

# hello: out (lit, dec incl. i64 min, hex, stderr, errno_name), exit code
if build hello; then
    want hello.out <<'X'
hello, kliner
0 42 -7 -9223372036854775808
0x0 0xff 0xffffffffffffffff
X
    want hello.err <<'X'
to stderr ENOENT errno 999
X
    check hello 3 "$TMP/hello.out" "$TMP/hello.err" -- "$BIN"
fi

# alloc: alignment, zeroing, reset clears, ENOMEM, [][]u8
if build alloc; then
    want alloc.out <<'X'
u8 len 3 used 8
used 64 sum 12344
after reset 0 0 kept 9
full ENOMEM
slices 4
X
    check alloc 0 "$TMP/alloc.out" "$TMP/empty" -- "$BIN"
fi

# args: /proc/self/cmdline, empty and UTF-8 arguments
if build args; then
    want args.out <<'X'
argc 5
1 [a b] z4
2 [] z1
3 [zażółć] z11
4 [x] z2
X
    check args 0 "$TMP/args.out" "$TMP/empty" -- "$BIN" "a b" "" "zażółć" x
fi

# cat: read_file, open_write + write_all, errors
if build cat; then
    CAT=$BIN
    printf 'line 1\nline 2\n' >"$TMP/in.txt"
    printf 'read 14\n' >"$TMP/cat.err"
    check cat-stdout 0 "$TMP/in.txt" "$TMP/cat.err" -- "$CAT" "$TMP/in.txt"
    check cat-write 0 "$TMP/empty" "$TMP/cat.err" -- "$CAT" "$TMP/in.txt" "$TMP/copy"
    if cmp -s "$TMP/in.txt" "$TMP/copy" && [ -x "$TMP/copy" ]; then echo "ok   cat-copy (0755)"; pass=$((pass + 1));
    else echo "FAIL cat-copy"; fail=$((fail + 1)); fi
    # larger than the 4096-byte out buffer and the first read buffer
    seq 1 30000 >"$TMP/big.txt"
    printf 'read %s\n' "$(wc -c <"$TMP/big.txt" | tr -d ' ')" >"$TMP/big.err"
    check cat-big 0 "$TMP/big.txt" "$TMP/big.err" -- "$CAT" "$TMP/big.txt"
    # not seekable (pipe): size unknown, buffer grows
    seq 1 30000 | "$CAT" /dev/stdin >"$TMP/pipe.out" 2>"$TMP/pipe.err"
    if [ $? = 0 ] && cmp -s "$TMP/big.txt" "$TMP/pipe.out" && cmp -s "$TMP/big.err" "$TMP/pipe.err"; then
        echo "ok   cat-pipe"; pass=$((pass + 1)); else echo "FAIL cat-pipe"; fail=$((fail + 1)); fi
    printf 'error: ENOENT\n' >"$TMP/enoent.err"
    check cat-enoent 1 "$TMP/empty" "$TMP/enoent.err" -- "$CAT" "$TMP/no/such/file"
    printf 'error: EISDIR\n' >"$TMP/eisdir.err"
    check cat-eisdir 1 "$TMP/empty" "$TMP/eisdir.err" -- "$CAT" "$TMP"
    printf 'usage: cat IN [OUT]\n' >"$TMP/usage.err"
    check cat-usage 2 "$TMP/empty" "$TMP/usage.err" -- "$CAT"
fi

echo "$pass passed, $fail failed"
[ $fail = 0 ]
