# Memory loop (lw/addi/sw), 10,000,000 iterations. Expected --iret: 50,000,006
    .data
buf: .word 0
    .text
main:
    li   t0, 10000000       # lui + addi = 2
    la   t1, buf            # auipc + addi = 2
loop:
    lw   t2, 0(t1)          # 5 per iteration
    addi t2, t2, 1
    sw   t2, 0(t1)
    addi t0, t0, -1
    bnez t0, loop
    li   a7, 10             # exit
    ecall
