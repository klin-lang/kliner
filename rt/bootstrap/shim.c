/* Bootstrap shim for rt/bootstrap/sys.kl (stage1 only, built by Klin).
 *
 * Kliner never compiles this file. It is the only C in the runtime:
 * one raw syscall. Address -> slice is plain Klin since klin #358 (D19):
 * cast(*mut [N]T, addr) and (*p)[:n].
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <unistd.h>

/* libc returns -1 and sets errno; return the kernel convention (-errno)
 * so everything above `sys` sees the same values as in stage2+. */
int64_t klrt_syscall6(int64_t nr, int64_t a, int64_t b, int64_t c,
                      int64_t d, int64_t e, int64_t f) {
    long r = syscall((long)nr, a, b, c, d, e, f);
    if (r == -1) return -(int64_t)errno;
    return (int64_t)r;
}
