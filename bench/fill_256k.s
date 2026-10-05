# Store 262144 words (1,048,576 bytes of guest memory) at consecutive addresses.
# run_stage1.sh compares max RSS across the fill_*.s sizes.
    .text
main:
    li   t0, 0x10000000     # start of the data segment
    li   t1, 0x5a5a5a5a     # value stored
    li   t2, 262144
loop:
    sw   t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, loop
    li   a7, 10
    ecall
