#ifndef IDA_H
#define IDA_H
#include <stdint.h>

enum { IDA_MAX_DEPTH = 11 };

/* A cube state as the three coordinates the search works on. */
typedef struct {
    uint32_t p; /* permutation rank, 0..5039 */
    uint32_t o; /* orientation rank, 0..728 */
    uint32_t r; /* rank of the positions of cubies 3 and 6, 0..41 */
} ida_state_t;

/* Parse a 14-character state; fills the coordinates and the raw arrays.
 * Returns 0 if the string is not a valid cube state. */
int ida_parse(const char *s, ida_state_t *st, uint8_t perm[7], uint8_t ori[7]);

/* Optimal solution: writes moves 0..8 (R R2 R' B B2 B' D D2 D') into path
 * and returns the number of moves. */
int ida_solve(const ida_state_t *start, uint8_t *path);

/* Apply path to the raw arrays; returns 1 if that reaches the solved state. */
int ida_check(const uint8_t perm[7], const uint8_t ori[7], const uint8_t *path, int n);

#ifdef IDA_COUNT_NODES
extern unsigned long long ida_nodes;
#endif
#endif
