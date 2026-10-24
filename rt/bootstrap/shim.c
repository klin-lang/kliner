/* Bootstrap shim for rt/bootstrap/sys.kl (stage1 only, built by Klin).
 *
 * Kliner never compiles this file. It is the only C in the runtime:
 * one raw syscall and the address -> slice constructors that core Klin
 * cannot express. It depends on Klin's C layout of []T, { T *ptr; size_t len; }
 * (docs/02-core-subset.md C7.5).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <unistd.h>

typedef struct { uint8_t *ptr; size_t len; } klrt_slice_u8_t;
typedef struct { int32_t *ptr; size_t len; } klrt_slice_i32_t;
typedef struct { int64_t *ptr; size_t len; } klrt_slice_i64_t;
typedef struct { klrt_slice_u8_t *ptr; size_t len; } klrt_slice_slice_u8_t;

/* libc returns -1 and sets errno; return the kernel convention (-errno)
 * so everything above `sys` sees the same values as in stage2+. */
int64_t klrt_syscall6(int64_t nr, int64_t a, int64_t b, int64_t c,
                      int64_t d, int64_t e, int64_t f) {
    long r = syscall((long)nr, a, b, c, d, e, f);
    if (r == -1) return -(int64_t)errno;
    return (int64_t)r;
}

klrt_slice_u8_t klrt_slice_u8(int64_t addr, int64_t len) {
    klrt_slice_u8_t s = { (uint8_t *)(intptr_t)addr, (size_t)len };
    return s;
}

klrt_slice_i32_t klrt_slice_i32(int64_t addr, int64_t len) {
    klrt_slice_i32_t s = { (int32_t *)(intptr_t)addr, (size_t)len };
    return s;
}

klrt_slice_i64_t klrt_slice_i64(int64_t addr, int64_t len) {
    klrt_slice_i64_t s = { (int64_t *)(intptr_t)addr, (size_t)len };
    return s;
}

/* TODO(G13): one constructor per element type, because Klin cannot take
 * (*cast(*mut [N]T, addr))[0:n] yet (broken C). Drop these when G13 is
 * fixed and build the slice in Klin. */
klrt_slice_slice_u8_t klrt_slice_slice_u8(int64_t addr, int64_t len) {
    klrt_slice_slice_u8_t s = { (klrt_slice_u8_t *)(intptr_t)addr, (size_t)len };
    return s;
}
