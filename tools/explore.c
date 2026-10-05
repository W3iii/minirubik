/* Stage 2 design exploration (host only).
 *
 * Builds the exact BFS distance table as ground truth, builds candidate
 * heuristic tables (pattern databases over abstractions of the state),
 * checks each for admissibility over all 3,674,160 states, and runs IDA*
 * with each on all 2,644 distance-11 states, reporting nodes visited.
 * Candidates: max(permutation table, orientation table), and the positions
 * of every pair and triple of cubies combined with the full orientation,
 * alone and maxed with the permutation table.
 *
 * The cube model (source, twist, Lehmer rank) is copied from solver.c.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, NPERM = 5040, NORI = 729, NSTATE = NPERM * NORI, MOVES = 9 };

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

typedef struct { uint8_t p[CUBIES], o[CUBIES]; } state_t;

static state_t quarter(state_t s, int f)
{
    state_t r;
    for (int i = 0; i < CUBIES; i++) {
        r.p[i] = s.p[source[f][i]];
        r.o[i] = (uint8_t) ((s.o[source[f][i]] + twist[f][i]) % 3);
    }
    return r;
}
static state_t apply(state_t s, int m)
{
    for (int t = 0; t <= m % 3; t++) s = quarter(s, m / 3);
    return s;
}
static int perm_rank(const uint8_t *p)
{
    int r = 0;
    for (int i = 0; i < CUBIES; i++) {
        int c = 0;
        for (int j = i + 1; j < CUBIES; j++) c += p[j] < p[i];
        r = r * (CUBIES - i) + c;
    }
    return r;
}
static void perm_unrank(int r, uint8_t *p)
{
    uint8_t avail[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    int f = 720;
    for (int i = 0; i < CUBIES; i++) {
        int q = r / f;
        r %= f;
        p[i] = avail[q];
        for (int j = q; j + 1 < CUBIES - i; j++) avail[j] = avail[j + 1];
        if (i < 6) f /= 6 - i;
    }
}
static int ori_rank(const uint8_t *o)
{
    int r = 0;
    for (int i = 0; i < 6; i++) r = r * 3 + o[i];
    return r;
}
static void ori_unrank(int r, uint8_t *o)
{
    int s = 0;
    for (int i = 5; i >= 0; i--) { o[i] = (uint8_t) (r % 3); s += o[i]; r /= 3; }
    o[6] = (uint8_t) ((3 - s % 3) % 3);
}

static uint16_t pmv[MOVES][NPERM], omv[MOVES][NORI];
static uint8_t *dist; /* exact distance, index p * 729 + o */

static void build_moves(void)
{
    state_t s;
    memset(&s, 0, sizeof s);
    for (int r = 0; r < NPERM; r++) {
        perm_unrank(r, s.p);
        for (int m = 0; m < MOVES; m++) pmv[m][r] = (uint16_t) perm_rank(apply(s, m).p);
    }
    for (int i = 0; i < CUBIES; i++) s.p[i] = (uint8_t) i;
    for (int r = 0; r < NORI; r++) {
        ori_unrank(r, s.o);
        for (int m = 0; m < MOVES; m++) omv[m][r] = (uint16_t) ori_rank(apply(s, m).o);
    }
}

/* Generic BFS over a space of n abstract states given a successor function. */
typedef uint32_t (*succ_fn)(uint32_t, int);
static uint8_t *bfs(uint32_t n, uint32_t goal, succ_fn succ, int *maxd)
{
    uint8_t *d = malloc(n);
    uint32_t *q = malloc((size_t) n * sizeof *q), head = 0, tail = 0;
    memset(d, 0xFF, n);
    d[goal] = 0;
    q[tail++] = goal;
    *maxd = 0;
    while (head < tail) {
        uint32_t u = q[head++];
        for (int m = 0; m < MOVES; m++) {
            uint32_t v = succ(u, m);
            if (d[v] == 0xFF) {
                d[v] = (uint8_t) (d[u] + 1);
                if (d[v] > *maxd) *maxd = d[v];
                q[tail++] = v;
            }
        }
    }
    if (tail != n) { fprintf(stderr, "bfs: reached %u of %u\n", tail, n); exit(1); }
    free(q);
    return d;
}
static uint32_t succ_full(uint32_t u, int m) { return pmv[m][u / NORI] * NORI + omv[m][u % NORI]; }
static uint32_t succ_perm(uint32_t u, int m) { return pmv[m][u]; }
static uint32_t succ_ori(uint32_t u, int m) { return omv[m][u]; }

/* Abstraction "positions of a subset of k cubies x full orientation".
 * sub_of_perm maps a permutation rank to the rank of the ordered tuple of
 * positions occupied by the chosen cubies (7*6 = 42 or 7*6*5 = 210 values). */
static int k_sub, nsub;
static uint16_t sub_of_perm[NPERM];
static uint16_t smv[MOVES][210];
static void build_subset(const int *cubies, int k)
{
    uint8_t p[CUBIES];
    k_sub = k;
    nsub = k == 2 ? 42 : 210;
    for (int r = 0; r < NPERM; r++) {
        perm_unrank(r, p);
        int pos[3], used[CUBIES] = {0}, idx = 0;
        for (int c = 0; c < k; c++)
            for (int i = 0; i < CUBIES; i++)
                if (p[i] == cubies[c]) pos[c] = i;
        /* rank ordered tuple of distinct positions: mixed radix 7,6,5 */
        for (int c = 0; c < k; c++) {
            int smaller = 0;
            for (int i = 0; i < pos[c]; i++) smaller += !used[i];
            used[pos[c]] = 1;
            idx = idx * (CUBIES - c) + smaller;
        }
        sub_of_perm[r] = (uint16_t) idx;
    }
    for (int r = 0; r < NPERM; r++)
        for (int m = 0; m < MOVES; m++) smv[m][sub_of_perm[r]] = sub_of_perm[pmv[m][r]];
}
static uint32_t succ_sub(uint32_t u, int m) { return smv[m][u / NORI] * NORI + omv[m][u % NORI]; }

/* Heuristic configurations */
static uint8_t *hperm, *hori, *hsub;
enum { H_PERM_ORI, H_SUB, H_SUB_PERM };
static int hmode;
static inline int heur(int p, int o)
{
    int a, b;
    switch (hmode) {
    case H_PERM_ORI: a = hperm[p]; b = hori[o]; return a > b ? a : b;
    case H_SUB: return hsub[sub_of_perm[p] * NORI + o];
    default: a = hsub[sub_of_perm[p] * NORI + o]; b = hperm[p]; return a > b ? a : b;
    }
}

/* IDA* with same-face pruning. Counts every node visited. */
static uint64_t nodes;
static int path[16];
static int dfs(int p, int o, int g, int bound, int last_face)
{
    nodes++;
    int f = g + heur(p, o);
    if (f > bound) return f;
    if (p == 0 && o == 0) return -1;
    int next = 255;
    for (int m = 0; m < MOVES; m++) {
        if (m / 3 == last_face) continue;
        path[g] = m;
        int t = dfs(pmv[m][p], omv[m][o], g + 1, bound, m / 3);
        if (t < 0) return -1;
        if (t < next) next = t;
    }
    return next;
}
static int ida(int p, int o)
{
    for (int bound = heur(p, o);;) {
        int t = dfs(p, o, 0, bound, -1);
        if (t < 0) return bound;
        bound = t;
    }
}

static uint32_t hard[2644];
static int nhard;

static void evaluate(const char *name, size_t entries)
{
    /* admissibility over the whole space (H1) */
    uint64_t sum_h = 0;
    for (uint32_t s = 0; s < NSTATE; s++) {
        int h = heur(s / NORI, s % NORI);
        if (h > dist[s]) { printf("%s: INADMISSIBLE at %u\n", name, s); exit(1); }
        sum_h += h;
    }
    uint64_t worst = 0, total = 0;
    uint32_t worst_s = 0;
    for (int i = 0; i < nhard; i++) {
        nodes = 0;
        int len = ida(hard[i] / NORI, hard[i] % NORI);
        if (len != 11) { printf("%s: length %d at %u\n", name, len, hard[i]); exit(1); }
        total += nodes;
        if (nodes > worst) { worst = nodes; worst_s = hard[i]; }
    }
    printf("%-34s %7zu entries %8.1f KiB(4b)  mean h %.3f  d11 nodes mean %9.0f max %9llu (state %u)\n",
           name, entries, entries / 2048.0, (double) sum_h / NSTATE,
           (double) total / nhard, (unsigned long long) worst, worst_s);
    fflush(stdout);
}

static void try_subset(const int *c, int k)
{
    int maxd;
    char name[64];
    build_subset(c, k);
    free(hsub);
    hsub = bfs((uint32_t) nsub * NORI, (uint32_t) sub_of_perm[0] * NORI, succ_sub, &maxd);
    if (k == 2)
        snprintf(name, sizeof name, "pos{%d,%d} x ori (max %d)", c[0], c[1], maxd);
    else
        snprintf(name, sizeof name, "pos{%d,%d,%d} x ori (max %d)", c[0], c[1], c[2], maxd);
    hmode = H_SUB;
    evaluate(name, (size_t) nsub * NORI);
    hmode = H_SUB_PERM;
    evaluate("  max(above, perm)", (size_t) nsub * NORI + NPERM);
}

int main(void)
{
    int maxd, c[3];
    build_moves();
    dist = bfs(NSTATE, 0, succ_full, &maxd);
    for (uint32_t s = 0; s < NSTATE; s++)
        if (dist[s] == 11) hard[nhard++] = s;
    printf("exact BFS: diameter %d, %d states at distance 11\n", maxd, nhard);

    hperm = bfs(NPERM, 0, succ_perm, &maxd);
    printf("permutation table: max %d\n", maxd);
    hori = bfs(NORI, 0, succ_ori, &maxd);
    printf("orientation table: max %d\n", maxd);

    hmode = H_PERM_ORI;
    evaluate("max(perm, ori)", NPERM + NORI);

    for (c[0] = 0; c[0] < CUBIES; c[0]++)        /* all 21 pairs */
        for (c[1] = c[0] + 1; c[1] < CUBIES; c[1]++)
            try_subset(c, 2);
    for (c[0] = 0; c[0] < CUBIES; c[0]++)        /* all 35 triples */
        for (c[1] = c[0] + 1; c[1] < CUBIES; c[1]++)
            for (c[2] = c[1] + 1; c[2] < CUBIES; c[2]++)
                try_subset(c, 3);
    return 0;
}
