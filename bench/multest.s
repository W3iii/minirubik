# Uses mul, which plain RV32I lacks: assembly must fail.
    .text
main:
    li   t0, 3
    mul  t0, t0, t0
    li   a7, 10
    ecall
