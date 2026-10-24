#!/bin/sh
# Build Kliner pieces with Klin (stage1: -I rt/bootstrap -I rt) and check
# them. Linux x86-64.
#   1. runtime demos in tests/rt (stage 1)
#   2. lexer (stage 2): tools/kliner-lex against the goldens in tests/lex,
#      and — when a Klin checkout and dart are available — against Klin's
#      own lexer (tools/klin-lex.dart) on every .kl file of Kliner and of
#      the Klin checkout.
#   3. parser (stage 3): tools/kliner-parse against the goldens in
#      tests/parse and — same conditions — against Klin's own parser
#      (tools/klin-parse.dart) on the same files.
#   4. checker (stage 4): tools/kliner-check against the goldens in
#      tests/check and — same conditions, plus KLIN_SRC/.dart_tool — against
#      Klin's own checker (tools/klin-check.dart).
#
#   scripts/test.sh                 # klin from PATH, no Klin comparison
#   KLIN=/path/to/klin KLIN_SRC=/path/to/klin-checkout scripts/test.sh
#   DART=/path/to/dart              # default: dart from PATH
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

build() { # name [dir [klin args...]]
    name=$1
    dir="$ROOT/tests/rt/$1"
    [ $# -ge 2 ] && { dir="$ROOT/$2"; shift; }
    shift
    rm -rf "$dir/out"
    (cd "$dir" && "$KLIN" -I "$ROOT/rt/bootstrap" -I "$ROOT/rt" "$@" main.kl) >"$TMP/$name.build" 2>&1
    if [ ! -x "$dir/out/main" ]; then
        echo "FAIL build $name"; sed 's/^/  /' "$TMP/$name.build"; fail=$((fail + 1)); return 1
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

# --- stage 2: lexer ---------------------------------------------------
# Goldens: tests/lex/NAME.kl -> NAME.tok. ok_* / err_* were written by
# Klin's lexer (tools/klin-lex.dart); err_* exit 1. div_* are known
# differences from Klin (README in tests/lex): the golden is Kliner's
# output and they are left out of the Klin comparison.
if build kliner-lex tools/kliner-lex -I "$ROOT/src"; then
    LEX=$BIN
    for f in "$ROOT"/tests/lex/*.kl; do
        n=$(basename "$f" .kl)
        rc=0
        case $n in err_*) rc=1 ;; esac
        check "lex $n" $rc "$ROOT/tests/lex/$n.tok" "$TMP/empty" -- "$LEX" "$f"
    done
    printf 'usage: kliner-lex FILE\n' >"$TMP/lexusage.err"
    check "lex usage" 2 "$TMP/empty" "$TMP/lexusage.err" -- "$LEX"
    printf 'error: ENOENT\n' >"$TMP/lexenoent.err"
    check "lex enoent" 2 "$TMP/empty" "$TMP/lexenoent.err" -- "$LEX" "$TMP/no/such.kl"

    # Same files through Klin's lexer: identical dump and exit code.
    DART=${DART:-dart}
    if [ -n "${KLIN_SRC:-}" ] && [ -f "$KLIN_SRC/lib/lexer.dart" ] && command -v "$DART" >/dev/null 2>&1; then
        printf '{"configVersion":2,"packages":[{"name":"klin","rootUri":"file://%s/lib/","packageUri":"./"}]}\n' \
            "$(cd "$KLIN_SRC" && pwd)" >"$TMP/pkg.json"
        if "$DART" compile exe --packages="$TMP/pkg.json" "$ROOT/tools/klin-lex.dart" -o "$TMP/klin-lex" >"$TMP/dart.build" 2>&1; then
            # vs_klin LABEL FILE...: one check over many files
            vs_klin() {
                label=$1; shift
                nf=0 bad=0
                for f in "$@"; do
                    case $(basename "$f") in div_*.kl) continue ;; esac
                    nf=$((nf + 1))
                    "$TMP/klin-lex" "$f" >"$TMP/d.tok" 2>&1; a=$?
                    "$LEX" "$f" >"$TMP/k.tok" 2>&1; b=$?
                    if [ $a != $b ] || ! cmp -s "$TMP/d.tok" "$TMP/k.tok"; then
                        bad=$((bad + 1))
                        echo "  differs: $f (exit klin $a, kliner $b)"
                        diff "$TMP/d.tok" "$TMP/k.tok" | head -6 | sed 's/^/    /'
                    fi
                done
                if [ $bad = 0 ]; then echo "ok   lex = klin: $label ($nf files)"; pass=$((pass + 1));
                else echo "FAIL lex = klin: $label ($bad of $nf files differ)"; fail=$((fail + 1)); fi
            }
            # Kliner's own sources, including tests/lex
            vs_klin "kliner sources" $(find "$ROOT" -name '*.kl' -not -path '*/out/*' | sort)
            # Klin's tests, examples, stdlib
            vs_klin "klin checkout" $(find "$KLIN_SRC" -name '*.kl' -not -path '*/out/*' -not -path '*/.dart_tool/*' | sort)
        else
            echo "FAIL build klin-lex.dart"; sed 's/^/  /' "$TMP/dart.build"; fail=$((fail + 1))
        fi
    else
        echo "skip lex = klin (set KLIN_SRC to a Klin checkout, dart on PATH or DART)"
    fi
fi

# --- stage 3: parser --------------------------------------------------
# Goldens: tests/parse/NAME.kl -> NAME.ast (stdout) and, if present,
# NAME.err (stderr: the `note:` for features Kliner does not support
# yet). ok_* / err_* stdout was written by Klin's parser
# (tools/klin-parse.dart); err_* exit 1. div_* are known differences
# from Klin (README in tests/parse); div_interp* exit 1.
if build kliner-parse tools/kliner-parse -I "$ROOT/src"; then
    PARSE=$BIN
    for f in "$ROOT"/tests/parse/*.kl; do
        n=$(basename "$f" .kl)
        rc=0
        case $n in err_*|div_interp*) rc=1 ;; esac
        want_err="$TMP/empty"
        [ -f "$ROOT/tests/parse/$n.err" ] && want_err="$ROOT/tests/parse/$n.err"
        check "parse $n" $rc "$ROOT/tests/parse/$n.ast" "$want_err" -- "$PARSE" "$f"
    done
    printf 'usage: kliner-parse FILE\n' >"$TMP/parseusage.err"
    check "parse usage" 2 "$TMP/empty" "$TMP/parseusage.err" -- "$PARSE"
    printf 'error: ENOENT\n' >"$TMP/parseenoent.err"
    check "parse enoent" 2 "$TMP/empty" "$TMP/parseenoent.err" -- "$PARSE" "$TMP/no/such.kl"

    # Same files through Klin's parser: identical stdout and exit code.
    # Expected differences, counted but not failures:
    #  - Kliner rejects string interpolation (exit 1 + note, Klin parses);
    #  - rt/linux_x86_64/sys.kl: fns without a body in `module sys`
    #    (Kliner parses, Klin: "expected `{`");
    #  - div_* goldens (tests/lex, tests/parse).
    # Files with `$fn` / `$name(...)` fail in both at the same `$`.
    DART=${DART:-dart}
    if [ -n "${KLIN_SRC:-}" ] && [ -f "$KLIN_SRC/lib/parser.dart" ] && command -v "$DART" >/dev/null 2>&1; then
        printf '{"configVersion":2,"packages":[{"name":"klin","rootUri":"file://%s/lib/","packageUri":"./"}]}\n' \
            "$(cd "$KLIN_SRC" && pwd)" >"$TMP/pkg.json"
        if "$DART" compile exe --packages="$TMP/pkg.json" "$ROOT/tools/klin-parse.dart" -o "$TMP/klin-parse" >"$TMP/dartp.build" 2>&1; then
            vs_klin_parse() {
                label=$1; shift
                nf=0 bad=0 interp=0 sys=0
                for f in "$@"; do
                    case $(basename "$f") in div_*.kl) continue ;; esac
                    nf=$((nf + 1))
                    "$TMP/klin-parse" "$f" >"$TMP/d.ast" 2>&1; a=$?
                    "$PARSE" "$f" >"$TMP/k.ast" 2>/dev/null; b=$?
                    if [ $a = $b ] && cmp -s "$TMP/d.ast" "$TMP/k.ast"; then continue; fi
                    if [ $a = 0 ] && [ $b = 1 ] && grep -q ': string interpolation is not supported by Kliner yet$' "$TMP/k.ast"; then
                        interp=$((interp + 1)); continue
                    fi
                    case $f in */rt/linux_x86_64/sys.kl) if [ $b = 0 ]; then sys=$((sys + 1)); continue; fi ;; esac
                    bad=$((bad + 1))
                    echo "  differs: $f (exit klin $a, kliner $b)"
                    diff "$TMP/d.ast" "$TMP/k.ast" | head -6 | sed 's/^/    /'
                done
                extra="$interp interpolation"
                [ $sys != 0 ] && extra="$extra, $sys body-less sys"
                if [ $bad = 0 ]; then echo "ok   parse = klin: $label ($nf files; expected differences: $extra)"; pass=$((pass + 1));
                else echo "FAIL parse = klin: $label ($bad of $nf files differ)"; fail=$((fail + 1)); fi
            }
            vs_klin_parse "kliner sources" $(find "$ROOT" -name '*.kl' -not -path '*/out/*' | sort)
            vs_klin_parse "klin checkout" $(find "$KLIN_SRC" -name '*.kl' -not -path '*/out/*' -not -path '*/.dart_tool/*' | sort)
        else
            echo "FAIL build klin-parse.dart"; sed 's/^/  /' "$TMP/dartp.build"; fail=$((fail + 1))
        fi
    else
        echo "skip parse = klin (set KLIN_SRC to a Klin checkout, dart on PATH or DART)"
    fi
fi

# --- stage 4: checker -------------------------------------------------
# Goldens: tests/check/NAME.kl, tests/check/klin/NAME.kl (snippets from
# Klin's test/pipeline_*_test.dart) and tests/check/NAME/main.kl (several
# modules) -> NAME.out: `ok` (exit 0) or the first error `L:C: message`
# (exit 1). *lib_* run with --lib (no `main` required). ok_*, err_*,
# mod_* and klin/* were written by Klin's checker (tools/klin-check.dart);
# div_* are known differences from Klin (docs/04-checker.md).
if build kliner-check tools/kliner-check -I "$ROOT/src"; then
    CHECK=$BIN
    check_flags() { case $(basename "$1") in *lib_*) echo --lib ;; esac; }
    for f in "$ROOT"/tests/check/*.kl "$ROOT"/tests/check/klin/*.kl "$ROOT"/tests/check/*/main.kl; do
        case $f in */main.kl) n=${f%/main.kl} ;; *) n=${f%.kl} ;; esac
        rc=1
        [ "$(cat "$n.out")" = ok ] && rc=0
        check "check ${n#"$ROOT"/tests/check/}" $rc "$n.out" "$TMP/empty" -- "$CHECK" $(check_flags "$n") "$f"
    done
    printf 'usage: kliner-check [--lib] [-I DIR]... FILE\n' >"$TMP/checkusage.err"
    check "check usage" 2 "$TMP/empty" "$TMP/checkusage.err" -- "$CHECK"

    # Same files through Klin's loader and checker: identical stdout and
    # exit code. Expected differences, counted but not failures:
    #  - Kliner rejects what it does not support yet (floats,
    #    `pick`, `async`, interpolation, `asm`, remote imports): exit 1
    #    with "... is not supported by Kliner yet";
    #  - `$fn` / `$name(...)` (C10): Kliner stops at the `$`, Klin expands;
    #  - rt/linux_x86_64/sys.kl: fns without a body in `module sys`;
    #  - div_* goldens.
    # Klin's checker imports packages beyond the parser's (crypto, xml):
    # it builds with the checkout's .dart_tool/package_config.json
    # (`dart pub get` in KLIN_SRC).
    DART=${DART:-dart}
    if [ -n "${KLIN_SRC:-}" ] && [ -f "$KLIN_SRC/.dart_tool/package_config.json" ] && command -v "$DART" >/dev/null 2>&1; then
        if "$DART" compile exe --packages="$KLIN_SRC/.dart_tool/package_config.json" "$ROOT/tools/klin-check.dart" -o "$TMP/klin-check" >"$TMP/dartc.build" 2>&1; then
            # vs_klin_check LABEL FLAGS FILE...
            vs_klin_check() {
                label=$1 flags=$2; shift 2
                nf=0 bad=0 uns=0 mac=0 sys=0
                for f in "$@"; do
                    case $(basename "$f") in div_*) continue ;; esac
                    nf=$((nf + 1))
                    fl=$flags
                    [ -z "$fl" ] && fl=$(check_flags "$f")
                    "$TMP/klin-check" $fl -I "$ROOT/src" -I "$ROOT/rt" -I "$ROOT/rt/bootstrap" "$f" >"$TMP/d.chk" 2>&1; a=$?
                    "$CHECK" $fl -I "$ROOT/src" -I "$ROOT/rt" -I "$ROOT/rt/bootstrap" "$f" >"$TMP/k.chk" 2>&1; b=$?
                    if [ $a = $b ] && cmp -s "$TMP/d.chk" "$TMP/k.chk"; then continue; fi
                    if [ $b = 1 ] && grep -q 'not supported by Kliner yet' "$TMP/k.chk"; then uns=$((uns + 1)); continue; fi
                    if [ $b = 1 ] && grep -q 'unexpected character `\$`' "$TMP/k.chk"; then mac=$((mac + 1)); continue; fi
                    case $f in */rt/linux_x86_64/sys.kl) if [ $b = 0 ]; then sys=$((sys + 1)); continue; fi ;; esac
                    bad=$((bad + 1))
                    echo "  differs: $f (exit klin $a, kliner $b)"
                    echo "    klin:   $(head -1 "$TMP/d.chk")"
                    echo "    kliner: $(head -1 "$TMP/k.chk")"
                done
                extra="$uns unsupported, $mac \$-macro"
                [ $sys != 0 ] && extra="$extra, $sys body-less sys"
                if [ $bad = 0 ]; then echo "ok   check = klin: $label ($nf files; expected differences: $extra)"; pass=$((pass + 1));
                else echo "FAIL check = klin: $label ($bad of $nf files differ)"; fail=$((fail + 1)); fi
            }
            vs_klin_check "goldens" "" "$ROOT"/tests/check/*.kl "$ROOT"/tests/check/klin/*.kl "$ROOT"/tests/check/*/main.kl
            vs_klin_check "kliner programs" "" "$ROOT"/tools/kliner-*/main.kl "$ROOT"/tests/rt/*/main.kl
            vs_klin_check "kliner modules (--lib)" --lib $(find "$ROOT/src" "$ROOT/rt" -name '*.kl' | sort)
            vs_klin_check "klin checkout" "" $(find "$KLIN_SRC" -name '*.kl' -not -path '*/out/*' -not -path '*/.dart_tool/*' | sort)
        else
            echo "FAIL build klin-check.dart"; sed 's/^/  /' "$TMP/dartc.build"; fail=$((fail + 1))
        fi
    else
        echo "skip check = klin (set KLIN_SRC to a Klin checkout with .dart_tool from \`dart pub get\`, dart on PATH or DART)"
    fi
fi

echo "$pass passed, $fail failed"
[ $fail = 0 ]
