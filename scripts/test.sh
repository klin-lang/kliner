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
#   5. IR + interpreter (stage 5): tools/kliner-run runs the tests/rt
#      demos and the tests/ir programs (goldens: stdout + exit code, the
#      same as the Klin-built binaries), kliner-ir dumps tests/ir/only/dump,
#      and kliner-lex / kliner-parse / kliner-check / kliner-ir run under
#      kliner-run give the same output as their Klin-built binaries.
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
                    case $f in */rt/linux_x86_64/sys.kl|*/tests/ir/only/unsup/lib/sys.kl) if [ $b = 0 ]; then sys=$((sys + 1)); continue; fi ;; esac
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
                    case $f in */rt/linux_x86_64/sys.kl|*/tests/ir/only/unsup/lib/sys.kl) if [ $b = 0 ]; then sys=$((sys + 1)); continue; fi ;; esac
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
            vs_klin_check "kliner programs" "" "$ROOT"/tools/kliner-*/main.kl "$ROOT"/tests/rt/*/main.kl "$ROOT"/tests/ir/*/main.kl
            vs_klin_check "kliner modules (--lib)" --lib $(find "$ROOT/src" "$ROOT/rt" -name '*.kl' | sort)
            vs_klin_check "klin checkout" "" $(find "$KLIN_SRC" -name '*.kl' -not -path '*/out/*' -not -path '*/.dart_tool/*' | sort)
        else
            echo "FAIL build klin-check.dart"; sed 's/^/  /' "$TMP/dartc.build"; fail=$((fail + 1))
        fi
    else
        echo "skip check = klin (set KLIN_SRC to a Klin checkout with .dart_tool from \`dart pub get\`, dart on PATH or DART)"
    fi
fi

# --- stage 5: IR and interpreter --------------------------------------
# Interpreted programs use the real runtime (rt/linux_x86_64: sys.call6
# without a body = the Sys instruction), Klin builds use rt/bootstrap.
if build kliner-ir tools/kliner-ir -I "$ROOT/src"; then
    IRD=$BIN
    printf 'usage: kliner-ir [-I DIR]... FILE\n' >"$TMP/irusage.err"
    check ir-usage 2 "$TMP/empty" "$TMP/irusage.err" -- "$IRD"
    check ir-dump 0 "$ROOT/tests/ir/only/dump/out.ir" "$TMP/empty" -- "$IRD" "$ROOT/tests/ir/only/dump/main.kl"
fi
if build kliner-run tools/kliner-run -I "$ROOT/src"; then
    RUN=$BIN
    run() { "$RUN" -I "$ROOT/rt/linux_x86_64" -I "$ROOT/rt" -I "$ROOT/src" "$@"; }
    printf 'usage: kliner-run [-I DIR]... FILE.kl [ARG]...\n' >"$TMP/runusage.err"
    check run-usage 2 "$TMP/empty" "$TMP/runusage.err" -- "$RUN"
    # the stage-1 demos, same expectations as their compiled versions
    [ -f "$TMP/hello.out" ] && check run-hello 3 "$TMP/hello.out" "$TMP/hello.err" -- run "$ROOT/tests/rt/hello/main.kl"
    [ -f "$TMP/alloc.out" ] && check run-alloc 0 "$TMP/alloc.out" "$TMP/empty" -- run "$ROOT/tests/rt/alloc/main.kl"
    [ -f "$TMP/args.out" ] && check run-args 0 "$TMP/args.out" "$TMP/empty" -- run "$ROOT/tests/rt/args/main.kl" "a b" "" "zażółć" x
    if [ -f "$TMP/cat.err" ]; then
        check run-cat 0 "$TMP/in.txt" "$TMP/cat.err" -- run "$ROOT/tests/rt/cat/main.kl" "$TMP/in.txt"
        check run-cat-big 0 "$TMP/big.txt" "$TMP/big.err" -- run "$ROOT/tests/rt/cat/main.kl" "$TMP/big.txt"
        rm -f "$TMP/copy2"
        check run-cat-write 0 "$TMP/empty" "$TMP/cat.err" -- run "$ROOT/tests/rt/cat/main.kl" "$TMP/in.txt" "$TMP/copy2"
        if cmp -s "$TMP/in.txt" "$TMP/copy2"; then echo "ok   run-cat-copy"; pass=$((pass + 1)); else echo "FAIL run-cat-copy"; fail=$((fail + 1)); fi
        check run-cat-enoent 1 "$TMP/empty" "$TMP/enoent.err" -- run "$ROOT/tests/rt/cat/main.kl" "$TMP/no/such/file"
    fi
    # tests/ir/NAME/main.kl (arguments: x y): main.out is stdout plus
    # "exit N"; the Klin-built binary must give the same.
    for d in "$ROOT"/tests/ir/*/; do
        n=$(basename "$d")
        [ -f "$d/main.out" ] || continue
        run "$d/main.kl" x y >"$TMP/ir.out" 2>&1 </dev/null; echo "exit $?" >>"$TMP/ir.out"
        if cmp -s "$TMP/ir.out" "$d/main.out"; then echo "ok   run $n"; pass=$((pass + 1));
        else echo "FAIL run $n"; diff "$d/main.out" "$TMP/ir.out" | head -20 | sed 's/^/  /'; fail=$((fail + 1)); fi
        if build "ir-$n" "tests/ir/$n"; then
            "$BIN" x y >"$TMP/irk.out" 2>&1 </dev/null; echo "exit $?" >>"$TMP/irk.out"
            if cmp -s "$TMP/irk.out" "$d/main.out"; then echo "ok   klin $n = golden"; pass=$((pass + 1));
            else echo "FAIL klin $n = golden"; diff "$d/main.out" "$TMP/irk.out" | head -20 | sed 's/^/  /'; fail=$((fail + 1)); fi
        fi
    done
    # kliner-run only: division by zero traps; a body-less call is rejected
    printf 'before\n' >"$TMP/trap.out"
    printf 'kliner-run: trap: division by zero\n' >"$TMP/trap.err"
    check run-trap 134 "$TMP/trap.out" "$TMP/trap.err" -- run "$ROOT/tests/ir/only/trap/main.kl"
    : >"$TMP/deep.out"
    printf 'kliner-run: trap: stack overflow\n' >"$TMP/deep.err"
    check run-deep 134 "$TMP/deep.out" "$TMP/deep.err" -- run "$ROOT/tests/ir/only/deep/main.kl"
    printf '7:27: calling `sys.nope` (a function without a body) is not supported yet\n' >"$TMP/unsup.err"
    check run-unsup 1 "$TMP/empty" "$TMP/unsup.err" -- "$RUN" -I "$ROOT/tests/ir/only/unsup/lib" -I "$ROOT/rt" "$ROOT/tests/ir/only/unsup/main.kl"
    # Kliner's own tools under the interpreter = their Klin-built binaries
    self_run() { # label tool binary files...
        label=$1 tool=$2 bin=$3; shift 3
        bad=0 nf=0
        for f in "$@"; do
            nf=$((nf + 1))
            "$bin" "$f" >"$TMP/s1" 2>&1; a=$?
            run "$ROOT/tools/$tool/main.kl" "$f" >"$TMP/s2" 2>&1; b=$?
            if [ $a != $b ] || ! cmp -s "$TMP/s1" "$TMP/s2"; then bad=$((bad + 1)); echo "  differs: $f"; fi
        done
        if [ $bad = 0 ]; then echo "ok   self: $label ($nf files)"; pass=$((pass + 1));
        else echo "FAIL self: $label ($bad of $nf files differ)"; fail=$((fail + 1)); fi
    }
    SRCS=$(find "$ROOT/src" "$ROOT/rt" "$ROOT/tools" "$ROOT/tests/rt" "$ROOT/tests/ir" -name '*.kl' -not -path '*/out/*' | sort)
    [ -n "${LEX:-}" ] && self_run "kliner-lex under kliner-run" kliner-lex "$LEX" $SRCS "$ROOT"/tests/lex/*.kl
    [ -n "${PARSE:-}" ] && self_run "kliner-parse under kliner-run" kliner-parse "$PARSE" $SRCS "$ROOT"/tests/parse/*.kl
    if [ -n "${CHECK:-}" ]; then
        CI="-I $ROOT/src -I $ROOT/rt -I $ROOT/rt/bootstrap"
        "$CHECK" $CI "$ROOT/tools/kliner-run/main.kl" >"$TMP/s1" 2>&1; a=$?
        run "$ROOT/tools/kliner-check/main.kl" $CI "$ROOT/tools/kliner-run/main.kl" >"$TMP/s2" 2>&1; b=$?
        "$CHECK" "$ROOT/tests/check/err_01.kl" >"$TMP/s3" 2>&1; c=$?
        run "$ROOT/tools/kliner-check/main.kl" "$ROOT/tests/check/err_01.kl" >"$TMP/s4" 2>&1; d=$?
        if [ $a = $b ] && [ $c = $d ] && cmp -s "$TMP/s1" "$TMP/s2" && cmp -s "$TMP/s3" "$TMP/s4"; then
            echo "ok   self: kliner-check under kliner-run (kliner-run, err_01)"; pass=$((pass + 1));
        else echo "FAIL self: kliner-check under kliner-run"; fail=$((fail + 1)); fi
    fi
    if [ -n "${IRD:-}" ]; then
        RI="-I $ROOT/rt/linux_x86_64 -I $ROOT/rt -I $ROOT/src"
        "$IRD" $RI "$ROOT/tools/kliner-run/main.kl" >"$TMP/s1" 2>&1; a=$?
        run "$ROOT/tools/kliner-ir/main.kl" $RI "$ROOT/tools/kliner-run/main.kl" >"$TMP/s2" 2>&1; b=$?
        if [ $a = 0 ] && [ $b = 0 ] && cmp -s "$TMP/s1" "$TMP/s2"; then
            echo "ok   self: kliner-ir under kliner-run (IR of kliner-run, $(wc -l <"$TMP/s1" | tr -d ' ') lines)"; pass=$((pass + 1));
        else echo "FAIL self: kliner-ir under kliner-run"; fail=$((fail + 1)); fi
    fi
fi

echo "$pass passed, $fail failed"
[ $fail = 0 ]
