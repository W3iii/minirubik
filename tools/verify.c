/* H3: run the RV32I solver (rv32/ida.c, compiled for the host) on every one
 * of the 3,674,160 states and check that each returned solution
 *   - has exactly the length of the exact BFS distance, and
 *   - reaches the solved state when applied (the same check as T5).
 * Also reports the nodes the search visits, per exact distance.
 *
 * Build: cc -O2 -DIDA_COUNT_NODES -I../rv32 verify.c ../rv32/ida.c ../rv32/tables.c
 */
#include <time.h>
#include "model.h"
#include "ida.h"

int main(void)
{
    int diameter;
    clock_t t0 = clock();
    build_transitions();
    uint8_t *dist = exact_distances(&diameter);
    unsigned long long total[12] = {0}, worst[12] = {0}, count[12] = {0};
    uint32_t worst_s[12] = {0};
    uint8_t path[16], perm[7], ori[7];
    char text[15];
    state_t st;
    ida_state_t is;

    for (uint32_t s = 0; s < NSTATE; s++) {
        unrank_state(s, &st);
        state_string(&st, text);
        if (!ida_parse(text, &is, perm, ori)) { printf("FAIL: parse %s\n", text); return 1; }
        if (is.p != s / NORI || is.o != s % NORI) { printf("FAIL: rank %s\n", text); return 1; }
        ida_nodes = 0;
        int n = ida_solve(&is, path);
        int d = dist[s];
        if (n != d) { printf("FAIL: %s length %d, exact %d\n", text, n, d); return 1; }
        if (!ida_check(perm, ori, path, n)) { printf("FAIL: %s path does not solve\n", text); return 1; }
        count[d]++;
        total[d] += ida_nodes;
        if (ida_nodes > worst[d]) { worst[d] = ida_nodes; worst_s[d] = s; }
    }
    printf("H3: all %d states solved, every length equals the exact distance, every path solves\n", NSTATE);
    printf("distance  states    mean nodes  max nodes  hardest state\n");
    for (int d = 0; d <= diameter; d++) {
        unrank_state(worst_s[d], &st);
        state_string(&st, text);
        printf("%8d %8llu %12.1f %10llu  %s\n", d, count[d],
               count[d] ? (double) total[d] / count[d] : 0.0, worst[d], text);
    }
    printf("wall clock: %.1f s\n", (double) (clock() - t0) / CLOCKS_PER_SEC);
    return 0;
}
