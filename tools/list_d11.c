/* Print every state at exact distance 11 (2,644 of them), one per line,
 * as the 14-digit strings the solvers take. Used by rv32/run_all_d11.sh. */
#include "model.h"

int main(void)
{
    int diameter, n = 0;
    char text[15];
    state_t st;
    build_transitions();
    uint8_t *dist = exact_distances(&diameter);
    for (uint32_t s = 0; s < NSTATE; s++)
        if (dist[s] == 11) {
            unrank_state(s, &st);
            state_string(&st, text);
            puts(text);
            n++;
        }
    fprintf(stderr, "%d states at distance 11\n", n);
    return 0;
}
