# minirubik: optimal 2x2x2 solver in RV32I assembly (IDA*).
#
# Built by build_asm.sh, which prepends tables.s and substitutes the cube
# state and the expected length. Ripes has no .if, so the renderer sits
# between "# >>> RENDER" and "# <<< RENDER" lines, which build_asm.sh keeps
# for the GUI build and deletes for the CLI build.
#
# Search registers (no calls inside the search, so ra and tp hold data):
#   s0 bound                      s2 g = depth of the child
#   s3 child 2p   s4 child o      s5 child r      (child under face f, t turns)
#   s6 node 2p    s7 node o       s8 node r       (node being expanded)
# A permutation rank p is kept as the byte offset 2p into perm_q; tables.s
# stores perm_q as 2p' and indexes hperm by 2p, so no shift is needed.
#   s9 face f     s10 turns t     s11 previous face (3 = none)
#   a2 perm_q row for f   a3 ori_q row   a4 pair_q row
#   a5 pdb        a6 hperm        a7 perm_q row stride (10080 bytes)
#   tp perm_q     ra ori_q        a1 pair_q       gp path - 1
#   t6 constant 3 sp frame stack, 36 bytes per depth
    .text
    .globl main
main:
    la   s6, perm_arr
    la   s7, ori_arr
    la   a0, cube

    # ---- parse: digits, distinct permutation, twist sum divisible by 3 ----
    li   t6, 3
    li   a2, 7
    li   t0, 0                  # i
    li   t4, 0                  # orientation sum
parse_loop:
    add  t1, a0, t0
    lbu  t2, 0(t1)              # permutation digit
    addi t2, t2, -49            # - '1'
    bgeu t2, a2, invalid        # unsigned compare also rejects < '1'
    lbu  t3, 7(t1)              # orientation digit
    addi t3, t3, -49
    bgeu t3, t6, invalid
    add  t4, t4, t3
    li   t5, 0                  # j
dup_loop:
    bgeu t5, t0, dup_done
    add  t1, s6, t5
    lbu  t1, 0(t1)
    beq  t1, t2, invalid
    addi t5, t5, 1
    j    dup_loop
dup_done:
    add  t1, s6, t0
    sb   t2, 0(t1)
    add  t1, s7, t0
    sb   t3, 0(t1)
    addi t0, t0, 1
    bltu t0, a2, parse_loop
    lbu  t1, 14(a0)             # string must end after 14 digits
    bnez t1, invalid
mod3:
    bltu t4, t6, mod3_done      # sum % 3 by subtraction, sum <= 14
    addi t4, t4, -3
    j    mod3
mod3_done:
    bnez t4, invalid

    # ---- ranks: Lehmer permutation, base-3 orientation, pair position ----
    li   t0, 0                  # i
    li   s3, 0                  # p
    li   s4, 0                  # o
    li   a3, 0                  # position of cubie 3
    li   a4, 0                  # position of cubie 6
rank_loop:
    add  t1, s6, t0
    lbu  t2, 0(t1)              # perm[i]
    li   t3, 0                  # c = #{ j > i : perm[j] < perm[i] }
    addi t5, t0, 1
count_loop:
    bgeu t5, a2, count_done
    add  t1, s6, t5
    lbu  t1, 0(t1)
    sltu t1, t1, t2
    add  t3, t3, t1
    addi t5, t5, 1
    j    count_loop
count_done:
    sub  t5, a2, t0             # p = p * (7 - i) + c, multiply by repeated add
    li   a0, 0
mul_loop:
    beqz t5, mul_done
    add  a0, a0, s3
    addi t5, t5, -1
    j    mul_loop
mul_done:
    add  s3, a0, t3
    li   t1, 6
    bgeu t0, t1, ori_done       # o = 3o + ori[i] for i < 6
    add  t1, s7, t0
    lbu  t1, 0(t1)
    slli t5, s4, 1
    add  s4, s4, t5
    add  s4, s4, t1
ori_done:
    bne  t2, t6, not3
    mv   a3, t0
not3:
    li   t1, 6
    bne  t2, t1, not6
    mv   a4, t0
not6:
    addi t0, t0, 1
    bltu t0, a2, rank_loop
    slli t1, a3, 2              # r = 6a + b - (b > a)
    slli t2, a3, 1
    add  s5, t1, t2
    add  s5, s5, a4
    sltu t1, a3, a4
    sub  s5, s5, t1

    # ---- search setup ----
    slli s6, s3, 1              # root node, permutation as byte offset 2p
    mv   s7, s4
    mv   s8, s5
    la   tp, perm_q
    la   ra, ori_q
    la   a1, pair_q
    la   a5, pdb
    la   a6, hperm
    li   a7, 10080
    la   gp, path
    addi gp, gp, -1
    slli t3, s8, 10             # h(root)
    add  t3, t3, s7
    add  t3, t3, a5
    lbu  t3, 0(t3)
    add  t4, a6, s6
    lbu  t4, 0(t4)
    bgeu t3, t4, root_max
    mv   t3, t4
root_max:
    li   s2, 0
    beqz t3, solved             # already solved: zero moves
    mv   s0, t3                 # bound = h(root)

iteration:
    li   s2, 1
    mv   s3, s6
    mv   s4, s7
    mv   s5, s8
    li   s9, 0
    li   s10, 0
    li   s11, 3
    mv   a2, tp
    mv   a3, ra
    mv   a4, a1
    j    face_check

    # ---- one quarter turn of face f applied to the child ----
turn_loop:
    add  t0, a2, s3             # s3 is already the byte offset 2p
    lhu  s3, 0(t0)
    slli t1, s4, 1
    add  t1, a3, t1
    lhu  s4, 0(t1)
    add  t2, a4, s5
    lbu  s5, 0(t2)
    addi s10, s10, 1
    add  t4, a6, s3             # hperm first: it alone prunes about half
    lbu  t4, 0(t4)
    add  t5, t4, s2
    bltu s0, t5, after_child    # g + hperm > bound
    slli t3, s5, 10             # then pdb[r << 10 | o]
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)
    add  t5, t3, s2
    bltu s0, t5, after_child    # g + pdb > bound
    slli t0, s9, 1              # path[g - 1] = 3f + t - 1
    add  t0, t0, s9
    add  t0, t0, s10
    addi t0, t0, -1
    add  t1, gp, s2
    sb   t0, 0(t1)
    or   t0, t3, t4             # both tables are 0 only at the solved state
    beqz t0, solved
    addi sp, sp, -36            # descend: save this depth
    sw   s6, 0(sp)
    sw   s7, 4(sp)
    sw   s8, 8(sp)
    sw   s9, 12(sp)
    sw   s10, 16(sp)
    sw   s11, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    mv   s6, s3
    mv   s7, s4
    mv   s8, s5
    mv   s11, s9
    li   s9, 0
    li   s10, 0
    addi s2, s2, 1
    mv   a2, tp
    mv   a3, ra
    mv   a4, a1
    j    face_check
after_child:
    bne  s10, t6, turn_loop     # more turns of this face
next_face:
    addi s9, s9, 1
    li   s10, 0
    mv   s3, s6
    mv   s4, s7
    mv   s5, s8
    add  a2, a2, a7
    addi a3, a3, 1458
    addi a4, a4, 42
face_check:
    bne  s9, s11, face_ok       # same-face pruning
    addi s9, s9, 1
    add  a2, a2, a7
    addi a3, a3, 1458
    addi a4, a4, 42
face_ok:
    bltu s9, t6, turn_loop
    li   t0, 1                  # all faces done: back up one depth
    beq  s2, t0, iteration_done
    addi s2, s2, -1
    mv   s3, s6                 # parent's child is this depth's node
    mv   s4, s7
    mv   s5, s8
    lw   s6, 0(sp)
    lw   s7, 4(sp)
    lw   s8, 8(sp)
    lw   s9, 12(sp)
    lw   s10, 16(sp)
    lw   s11, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    addi sp, sp, 36
    j    after_child
iteration_done:                 # costs are integers, so the next bound
    addi s0, s0, 1              # is bound + 1; no minimum is tracked
    j    iteration

    # ---- report: print the moves, then apply them and check (T5) ----
solved:                         # s2 = number of moves
    li   s0, 0                  # k
print_loop:
    bgeu s0, s2, print_done
    la   t0, path
    add  t0, t0, s0
    lbu  t0, 0(t0)
    slli t0, t0, 2
    la   a0, move_names
    add  a0, a0, t0
    li   a7, 4
    ecall
    addi s0, s0, 1
    j    print_loop
print_done:
    la   a0, msg_moves
    li   a7, 4
    ecall
    mv   a0, s2
    li   a7, 1
    ecall

    la   s6, perm_arr
    la   s7, ori_arr
    la   s8, tmp_arr
    li   s0, 0                  # k
apply_loop:
    bgeu s0, s2, apply_done
    la   t0, path
    add  t0, t0, s0
    lbu  t1, 0(t0)              # move
    li   t2, 0                  # face = move / 3, t1 = move % 3
div3:
    bltu t1, t6, div3_done
    addi t1, t1, -3
    addi t2, t2, 1
    j    div3
div3_done:
    slli t3, t2, 3              # row offset 7 * face
    sub  t3, t3, t2
    la   t4, source_t
    add  s9, t4, t3             # source row
    la   t4, twist_t
    add  s10, t4, t3            # twist row
    addi s11, t1, 1             # quarter turns to apply
quarter_loop:
    li   t0, 0
qt_build:
    add  t1, s9, t0
    lbu  t1, 0(t1)              # from = source[f][i]
    add  t2, s6, t1
    lbu  t2, 0(t2)
    add  t3, s8, t0
    sb   t2, 0(t3)              # tmp_p[i] = perm[from]
    add  t2, s7, t1
    lbu  t2, 0(t2)
    add  t3, s10, t0
    lbu  t3, 0(t3)
    add  t2, t2, t3             # ori[from] + twist[f][i]
    bltu t2, t6, qt_mod
    addi t2, t2, -3
qt_mod:
    add  t3, s8, t0
    sb   t2, 8(t3)              # tmp_o[i]
    addi t0, t0, 1
    li   t1, 7
    bltu t0, t1, qt_build
    li   t0, 0
qt_copy:
    add  t1, s8, t0
    lbu  t2, 0(t1)
    lbu  t3, 8(t1)
    add  t1, s6, t0
    sb   t2, 0(t1)
    add  t1, s7, t0
    sb   t3, 0(t1)
    addi t0, t0, 1
    li   t1, 7
    bltu t0, t1, qt_copy
    addi s11, s11, -1
    bnez s11, quarter_loop
# >>> RENDER
    jal  render                 # redraw after every move the solver emitted
# <<< RENDER
    addi s0, s0, 1
    j    apply_loop
apply_done:
    li   t0, 0                  # solved means perm[i] == i and ori[i] == 0
check_loop:
    add  t1, s6, t0
    lbu  t1, 0(t1)
    bne  t1, t0, fail
    add  t1, s7, t0
    lbu  t1, 0(t1)
    bnez t1, fail
    addi t0, t0, 1
    li   t1, 7
    bltu t0, t1, check_loop
    la   t0, expect             # expected length, or -1 when unknown
    lw   t0, 0(t0)
    bltz t0, pass
    bne  t0, s2, fail
pass:
    la   a0, msg_ok
    j    finish
fail:
    la   a0, msg_fail
    j    finish
invalid:
    la   a0, msg_invalid
finish:
    li   a7, 4
    ecall
    li   a7, 10
    ecall

    .data
expect:     .word @EXPECT@
path:       .byte 0,0,0,0,0,0,0,0,0,0,0,0
perm_arr:   .byte 0,0,0,0,0,0,0,0
ori_arr:    .byte 0,0,0,0,0,0,0,0
tmp_arr:    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
source_t:   .byte 1,4,2,0,3,5,6, 0,1,2,4,5,6,3, 0,2,5,3,1,4,6
twist_t:    .byte 1,2,0,2,1,0,0, 0,0,0,1,2,1,2, 0,0,0,0,0,0,0
move_names: .byte 82,32,0,0, 82,50,32,0, 82,39,32,0
            .byte 66,32,0,0, 66,50,32,0, 66,39,32,0
            .byte 68,32,0,0, 68,50,32,0, 68,39,32,0
cube:        .string "@CUBE@"
msg_moves:   .string "\nmoves: "
msg_ok:      .string "\nOK\n"
msg_fail:    .string "\nFAIL\n"
msg_invalid: .string "invalid cube state\n"
