/* IDA* solver for the 2x2x2 cube, written for RV32I.
 *
 * No heap, no recursion, no floating point, and no multiply or divide in
 * the search: every index is a shift, an add, or a table lookup.
 *
 * Heuristic: max(pdb[pair << 10 | o], hperm[p]). Both tables hold exact
 * distances in abstractions of the cube, so the heuristic never
 * overestimates and IDA* returns a shortest solution. Both tables are 0
 * only at the solved state, which doubles as the goal test. The search
 * tests the two tables one after the other instead of taking the maximum,
 * and raises the bound by one per iteration.
 */
#include "ida.h"
#include "tables.h"

#ifdef IDA_COUNT_NODES
unsigned long long ida_nodes;
#define COUNT_NODE() (ida_nodes++)
#else
#define COUNT_NODE() ((void) 0)
#endif

/* Base of each face's row, so the search never computes face * NPERM. */
static const uint16_t *const perm_face[3] = {perm_q, perm_q + NPERM, perm_q + 2 * NPERM};
static const uint16_t *const ori_face[3] = {ori_q, ori_q + NORI, ori_q + 2 * NORI};
static const uint8_t *const pair_face[3] = {pair_q, pair_q + NPAIR, pair_q + 2 * NPAIR};

static inline uint32_t heuristic(uint32_t p, uint32_t o, uint32_t r)
{
    uint32_t a = pdb[(r << 10) + o], b = hperm[p];
    return a > b ? a : b;
}

int ida_solve(const ida_state_t *start, uint8_t *path)
{
    /* Explicit stack, one frame per depth. node_* is the node being
     * expanded; child_* is its child under face[d] turned turn[d] times. */
    uint32_t node_p[IDA_MAX_DEPTH], node_o[IDA_MAX_DEPTH], node_r[IDA_MAX_DEPTH];
    uint32_t child_p[IDA_MAX_DEPTH], child_o[IDA_MAX_DEPTH], child_r[IDA_MAX_DEPTH];
    uint8_t face[IDA_MAX_DEPTH], turn[IDA_MAX_DEPTH], last[IDA_MAX_DEPTH];
    uint32_t bound = heuristic(start->p, start->o, start->r);

    if (bound == 0)
        return 0;
    for (;;) {
        int d = 0;
        node_p[0] = child_p[0] = start->p;
        node_o[0] = child_o[0] = start->o;
        node_r[0] = child_r[0] = start->r;
        face[0] = turn[0] = 0;
        last[0] = 3; /* no previous face */
        while (d >= 0) {
            if (turn[d] == 3) { /* all three turns of this face done */
                face[d]++;
                turn[d] = 0;
                child_p[d] = node_p[d];
                child_o[d] = node_o[d];
                child_r[d] = node_r[d];
            }
            if (turn[d] == 0 && face[d] == last[d]) /* same-face pruning */
                face[d]++;
            if (face[d] >= 3) {
                d--;
                continue;
            }
            uint32_t f = face[d];
            child_p[d] = perm_face[f][child_p[d]];
            child_o[d] = ori_face[f][child_o[d]];
            child_r[d] = pair_face[f][child_r[d]];
            turn[d]++;
            COUNT_NODE();

            /* hperm first: on its own it prunes about half of all nodes,
             * which then skip the pdb lookup */
            uint32_t g = (uint32_t) d + 1;
            uint32_t hp = hperm[child_p[d]];
            if (g + hp > bound)
                continue;
            uint32_t hd = pdb[(child_r[d] << 10) + child_o[d]];
            if (g + hd > bound)
                continue;
            path[d] = (uint8_t) ((f << 1) + f + turn[d] - 1); /* 3f + turn - 1 */
            if ((hp | hd) == 0) /* both are 0 only at the solved state */
                return (int) g;
            d++; /* h >= 1 and g + h <= bound <= 11 keep d below 11 */
            node_p[d] = child_p[d] = child_p[d - 1];
            node_o[d] = child_o[d] = child_o[d - 1];
            node_r[d] = child_r[d] = child_r[d - 1];
            face[d] = turn[d] = 0;
            last[d] = (uint8_t) f;
        }
        bound++; /* costs are integers; no minimum over pruned nodes is kept */
    }
}

/* ---- setup and checking: run once per query, outside the search ---- */

/* x * k for small k without a multiply instruction. */
static uint32_t mul_small(uint32_t x, uint32_t k)
{
    uint32_t r = 0;
    while (k) {
        if (k & 1)
            r += x;
        x <<= 1;
        k >>= 1;
    }
    return r;
}

int ida_parse(const char *s, ida_state_t *st, uint8_t perm[7], uint8_t ori[7])
{
    uint32_t p = 0, o = 0, sum = 0, a = 0, b = 0;
    for (int i = 0; i < 7; i++) {
        if (s[i] < '1' || s[i] > '7' || s[i + 7] < '1' || s[i + 7] > '3')
            return 0;
        perm[i] = (uint8_t) (s[i] - '1');
        ori[i] = (uint8_t) (s[i + 7] - '1');
        for (int j = 0; j < i; j++)
            if (perm[j] == perm[i])
                return 0;
        sum += ori[i];
    }
    if (s[14] != '\0')
        return 0;
    while (sum >= 3) /* sum % 3 without a divide; sum <= 14 */
        sum -= 3;
    if (sum != 0)
        return 0;
    for (int i = 0; i < 7; i++) {
        uint32_t c = 0;
        for (int j = i + 1; j < 7; j++)
            c += perm[j] < perm[i];
        p = mul_small(p, (uint32_t) (7 - i)) + c; /* Lehmer rank, Horner form */
        if (i < 6)
            o = (o << 1) + o + ori[i]; /* base 3 */
        if (perm[i] == 3)
            a = (uint32_t) i;
        if (perm[i] == 6)
            b = (uint32_t) i;
    }
    st->p = p;
    st->o = o;
    st->r = (a << 2) + (a << 1) + b - (b > a); /* 6a + b - (b > a) */
    return 1;
}

static const uint8_t source[3][7] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][7] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

int ida_check(const uint8_t perm[7], const uint8_t ori[7], const uint8_t *path, int n)
{
    uint8_t p[7], o[7], np[7], no[7];
    for (int i = 0; i < 7; i++) {
        p[i] = perm[i];
        o[i] = ori[i];
    }
    for (int k = 0; k < n; k++) {
        uint32_t f = 0, t = path[k];
        while (t >= 3) { /* f = move / 3, t = move % 3 */
            t -= 3;
            f++;
        }
        for (uint32_t q = 0; q <= t; q++) {
            for (int i = 0; i < 7; i++) {
                uint32_t v = (uint32_t) o[source[f][i]] + twist[f][i];
                np[i] = p[source[f][i]];
                no[i] = (uint8_t) (v >= 3 ? v - 3 : v);
            }
            for (int i = 0; i < 7; i++) {
                p[i] = np[i];
                o[i] = no[i];
            }
        }
    }
    for (int i = 0; i < 7; i++)
        if (p[i] != i || o[i] != 0)
            return 0;
    return 1;
}
