/* cw-decoy — a forgeable stand-in for a wedged headless claude.
 *
 * The real wedge is not reproducible, so every test synthesises one. This decoy
 * exercises bin/claude-watchdog end to end — classification, the sustained
 * window, the forensic bundle, the notification, and (from phase 3) the kill
 * ladder — with zero risk to a real session.
 *
 * Usage:  <binary> [hold_mb] [grow_mb_per_sec]
 *
 *   2.1.220 0 0        spin at ~100% CPU, negligible RSS   (CPU path)
 *   2.1.220 20 2       hold 20 MB, grow 2 MB/s, spin       (full pipeline, cheap)
 *   2.1.220 1500 8     the 2026-07-28 shape                (calibration)
 *
 * Runs until killed.
 *
 * THREE THINGS THAT MADE EARLIER VERSIONS OF THIS SILENTLY DO NOTHING. All three
 * were caught only because `ps -o rss` was checked against what the decoy claimed
 * to have allocated — worth repeating for anything that tries to move RSS on
 * purpose on macOS:
 *
 *   1. `cp /bin/sh <name>` does not work at all. /bin/sh is an Apple-signed
 *      platform binary; a copy is SIGKILLed at exec (rc=137) while `codesign -dv`
 *      still reports Identifier=com.apple.sh. Hence a compiled decoy.
 *   2. memset(p, 1, MB) is invisible. macOS's memory compressor collapses uniform
 *      pages, so 1.5 GB of identical bytes reported 464 KB resident. Pages must
 *      be filled with incompressible data.
 *   3. A non-escaping allocation is deleted outright. At -O1, filling a buffer
 *      that is never read and never escapes is a dead store; LLVM removed the
 *      fill and the malloc with it, and 500 MB "touched" showed 1408 KB resident.
 *      The buffer must escape (global volatile pointer) and be read back.
 *
 * And one property of macOS itself: pages written once and never referenced again
 * get reclaimed — RSS was observed decaying 39 MB -> 12 MB while the process held
 * 1.5 GB. A real leaking heap stays resident because the GC keeps walking it, so
 * the decoy re-touches its pages continuously to model that. Without the
 * re-touch, no allocation size produces a stable resident set.
 *
 * The detector keys on three forgeable properties (bin/claude-watchdog §G1-G5):
 *   ucomm       — executable basename. Forged by naming the binary `2.1.220`.
 *   argv[0]     — must also basename to a claude executable. Free, from invoking
 *                 it by that path.
 *   tty == "??" — inherited. Anything spawned from a Claude Code Bash tool or a
 *                 launchd job already lacks a controlling terminal. macOS has no
 *                 `setsid`, and redirecting stdio does NOT detach a controlling
 *                 tty, so inheritance is the only route.
 */
#include <stdlib.h>
#include <time.h>

#define MB (1024UL * 1024UL)
#define WORDS_PER_MB (MB / sizeof(unsigned long))
#define MAX_BLOCKS 8192 /* 8 GB ceiling — a runaway test must not swap the machine */

static unsigned long rng_state = 88172645463325252UL;

static unsigned long xorshift(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

static unsigned long *blocks[MAX_BLOCKS];
static long nblocks = 0;

/* Global + volatile so the allocation escapes and cannot be optimised away. */
static unsigned long *volatile keep;
static volatile unsigned long sink;

static void take(long mb) {
    for (long i = 0; i < mb && nblocks < MAX_BLOCKS; i++) {
        unsigned long *p = malloc(MB);
        if (!p) return;
        for (size_t j = 0; j < WORDS_PER_MB; j++) p[j] = xorshift();
        keep = p;
        sink += p[WORDS_PER_MB / 2];
        blocks[nblocks++] = p;
    }
}

/* Walk every block, reading one word per 4 KB page. This is what keeps the
 * resident set resident — model of a GC repeatedly walking a live heap. */
static void warm(void) {
    for (long b = 0; b < nblocks; b++) {
        unsigned long *p = blocks[b];
        for (size_t j = 0; j < WORDS_PER_MB; j += 4096 / sizeof(unsigned long))
            sink += p[j];
    }
}

int main(int argc, char **argv) {
    long hold_mb = (argc > 1) ? atol(argv[1]) : 0;
    long grow_mb = (argc > 2) ? atol(argv[2]) : 0;

    take(hold_mb);

    time_t last = time(NULL);
    volatile double x = 0;
    for (;;) {
        /* Burn a core. `volatile` stops the optimiser deleting the loop. */
        for (long i = 0; i < 2000000L; i++) x += (double)i;

        warm();

        if (grow_mb > 0) {
            time_t now = time(NULL);
            if (now != last) {
                last = now;
                take(grow_mb);
            }
        }
    }
    return 0;
}
