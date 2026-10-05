# ALU-only loop, 50,000,000 iterations. Expected --iret: 100,000,004
    .text
main:
    li   t0, 50000000       # lui + addi = 2
loop:
    addi t0, t0, -1         # 2 per iteration
    bnez t0, loop
    li   a7, 10             # exit
    ecall
