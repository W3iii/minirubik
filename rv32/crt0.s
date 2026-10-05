# Minimal start-up for the C reference build: Ripes begins at the first
# instruction of .text, so _start must come first.
    .section .text.start
    .globl _start
_start:
    call main
    li   a7, 10          # exit
    ecall
