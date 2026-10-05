# Store 1048576 words (4,194,304 bytes of guest memory) at consecutive addresses.
# run_stage1.sh compares max RSS across the fill_*.s sizes.
    .text
main:
    li   t0, 0x10000000     # start of the data segment
    li   t1, 0x5a5a5a5a     # value stored
    li   t2, 1048576
loop:
    sw   t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, loop
    li   a7, 10
    ecall
