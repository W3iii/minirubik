/* Cube model shared by the host tools; copied from solver.c. */
#ifndef MODEL_H
#define MODEL_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, NPERM = 5040, NORI = 729, NSTATE = NPERM * NORI, MOVES = 9 };
enum { NPAIR = 42, PAIR_A = 3, PAIR_B = 6, PDB_STRIDE = 1024 };

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
/* Rank of the ordered pair (position of cubie PAIR_A, position of PAIR_B). */
static int pair_rank(const uint8_t *p)
{
    int a = 0, b = 0;
    for (int i = 0; i < CUBIES; i++) {
        if (p[i] == PAIR_A) a = i;
        if (p[i] == PAIR_B) b = i;
    }
    return a * 6 + b - (b > a);
}
static void unrank_state(uint32_t rank, state_t *s)
{
    perm_unrank((int) (rank / NORI), s->p);
    ori_unrank((int) (rank % NORI), s->o);
}
/* 14-character input string for a state, digits 1-based as in solver.c. */
static inline void state_string(const state_t *s, char *out)
{
    for (int i = 0; i < CUBIES; i++) {
        out[i] = (char) ('1' + s->p[i]);
        out[i + CUBIES] = (char) ('1' + s->o[i]);
    }
    out[14] = '\0';
}

/* Quarter-turn transition tables over the three coordinates. */
static uint16_t perm_q[3][NPERM], ori_q[3][NORI];
static uint8_t pair_q[3][NPAIR];

static void build_transitions(void)
{
    state_t s;
    memset(&s, 0, sizeof s);
    for (int r = 0; r < NPERM; r++) {
        perm_unrank(r, s.p);
        for (int f = 0; f < 3; f++) {
            state_t t = quarter(s, f);
            perm_q[f][r] = (uint16_t) perm_rank(t.p);
            pair_q[f][pair_rank(s.p)] = (uint8_t) pair_rank(t.p);
        }
    }
    for (int i = 0; i < CUBIES; i++) s.p[i] = (uint8_t) i;
    for (int r = 0; r < NORI; r++) {
        ori_unrank(r, s.o);
        for (int f = 0; f < 3; f++) ori_q[f][r] = (uint16_t) ori_rank(quarter(s, f).o);
    }
}

/* Exact distance of every state by BFS from solved, index p * 729 + o. */
static uint8_t *exact_distances(int *diameter)
{
    uint8_t *d = malloc(NSTATE);
    uint32_t *q = malloc((size_t) NSTATE * sizeof *q), head = 0, tail = 0;
    memset(d, 0xFF, NSTATE);
    d[0] = 0;
    q[tail++] = 0;
    *diameter = 0;
    while (head < tail) {
        uint32_t u = q[head++], p = u / NORI, o = u % NORI;
        for (int f = 0; f < 3; f++) {
            uint32_t np = p, no = o;
            for (int t = 0; t < 3; t++) {
                np = perm_q[f][np];
                no = ori_q[f][no];
                uint32_t v = np * NORI + no;
                if (d[v] == 0xFF) {
                    d[v] = (uint8_t) (d[u] + 1);
                    if (d[v] > *diameter) *diameter = d[v];
                    q[tail++] = v;
                }
            }
        }
    }
    free(q);
    if (tail != NSTATE) { fprintf(stderr, "BFS reached %u states\n", tail); exit(1); }
    return d;
}
#endif
