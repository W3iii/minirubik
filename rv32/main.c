/* Ripes entry point for the C reference build.
 * The cube state is fixed at build time: make CUBE=14325671111111 */
#include "ida.h"

#ifndef CUBE
#define CUBE "21345671111111"
#endif

static void ecall_print_string(const char *s)
{
    register const char *a0 __asm__("a0") = s;
    register int a7 __asm__("a7") = 4;
    __asm__ volatile("ecall" : : "r"(a0), "r"(a7) : "memory");
}

static void ecall_print_int(int v)
{
    register int a0 __asm__("a0") = v;
    register int a7 __asm__("a7") = 1;
    __asm__ volatile("ecall" : : "r"(a0), "r"(a7) : "memory");
}

static const char move_text[9][4] = {"R ", "R2 ", "R' ", "B ", "B2 ", "B' ", "D ", "D2 ", "D' "};

int main(void)
{
    ida_state_t st;
    uint8_t perm[7], ori[7], path[IDA_MAX_DEPTH];

    if (!ida_parse(CUBE, &st, perm, ori)) {
        ecall_print_string("invalid cube state\n");
        return 2;
    }
    int n = ida_solve(&st, path);
    for (int i = 0; i < n; i++)
        ecall_print_string(move_text[path[i]]);
    ecall_print_string("\nmoves: ");
    ecall_print_int(n);
    if (!ida_check(perm, ori, path, n)) {
        ecall_print_string("\nFAIL: path does not solve the cube\n");
        return 1;
    }
    ecall_print_string("\nOK\n");
    return 0;
}
