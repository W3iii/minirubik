# minirubik: optimal 2x2x2 solver in RV32I assembly (IDA*).
#
# Built by build_asm.sh, which prepends tables.s and substitutes the cube
# state and the expected length. Ripes has no .if, so the renderer sits
# between "# >>> RENDER" and "# <<< RENDER" lines, which build_asm.sh keeps
# for the GUI build and deletes for the CLI build.
#
# The search is unrolled: one block per face and turn, so every table
# offset is a constant. A permutation rank p is kept as the byte offset 8p
# into pblock, which holds the three next permutations and hperm[p]. A child
# that passes both tests calls expand with jal; the 24-byte frame keeps the
# node, the previous face, the resume address and the move, and pop returns
# with jr. The path is rebuilt from the frames when a solution is found.
#
# Search registers (no calls inside the search, so ra and tp hold data):
#   s0 bound      s2 g = depth of the child       s11 previous face (3 = none)
#   s3 child 8p   s4 child o      s5 child r      (child of the current block)
#   s6 node 8p    s7 node o       s8 node r       (node being expanded)
#   tp pblock     ra ori_q + 1458 a1 pair_q       a5 pdb
#   a2 constant 1 a3 constant 2   a4 resume address for expand
#   gp path - 1   sp frame stack in .data, 24 bytes per depth, 11 depths
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
    slli s6, s3, 3              # root node: permutation as byte offset 8p
    mv   s7, s4
    mv   s8, s5
    la   tp, pblock
    la   ra, ori_q
    addi ra, ra, 1458           # middle row, so faces are offsets -1458, 0, +1458
    la   a1, pair_q
    la   a5, pdb
    la   gp, path
    addi gp, gp, -1
    li   a2, 1
    li   a3, 2
    la   sp, frames_end         # frame stack sized at assembly time
    slli t3, s8, 10             # h(root) = max(pdb, hperm)
    add  t3, t3, s7
    add  t3, t3, a5
    lbu  t3, 0(t3)
    add  t4, tp, s6
    lbu  t4, 6(t4)
    bgeu t3, t4, root_max
    mv   t3, t4
root_max:
    li   s2, 0
    beqz t3, solved             # already solved: zero moves
    mv   s0, t3                 # bound = h(root)

iteration:
    li   s2, 1
    li   s11, 3                 # root has no previous face
    j    face0

    # ---- the nine children of a node, one block per face and turn ----
    # Each block turns the child once more and tests it. A child that
    # passes both tests calls expand with jal, so the frame records where
    # to resume: the block of the next turn.
face0:                         # face R: child starts as the node
    mv   s3, s6
    mv   s4, s7
    mv   s5, s8
f0t1:                          # R (move 0)
    add  t0, tp, s3
    lhu  s3, 0(t0)             # 8p' = pblock[8p + 0]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, -1458(t1)
    add  t2, a1, s5
    lbu  s5, 0(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f0t2
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f0t2
    li   t6, 0
    li   t2, 0
    jal  a4, expand
f0t2:                          # R2 (move 1)
    add  t0, tp, s3
    lhu  s3, 0(t0)             # 8p' = pblock[8p + 0]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, -1458(t1)
    add  t2, a1, s5
    lbu  s5, 0(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f0t3
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f0t3
    li   t6, 1
    li   t2, 0
    jal  a4, expand
f0t3:                          # R' (move 2)
    add  t0, tp, s3
    lhu  s3, 0(t0)             # 8p' = pblock[8p + 0]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, -1458(t1)
    add  t2, a1, s5
    lbu  s5, 0(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, face0_done
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, face0_done
    li   t6, 2
    li   t2, 0
    jal  a4, expand
face0_done:
    beq  s11, a2, face2         # skip face 1 if the move into this node was B
face1:                         # face B: child starts as the node
    mv   s3, s6
    mv   s4, s7
    mv   s5, s8
f1t1:                          # B (move 3)
    add  t0, tp, s3
    lhu  s3, 2(t0)             # 8p' = pblock[8p + 2]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 0(t1)
    add  t2, a1, s5
    lbu  s5, 42(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f1t2
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f1t2
    li   t6, 3
    li   t2, 1
    jal  a4, expand
f1t2:                          # B2 (move 4)
    add  t0, tp, s3
    lhu  s3, 2(t0)             # 8p' = pblock[8p + 2]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 0(t1)
    add  t2, a1, s5
    lbu  s5, 42(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f1t3
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f1t3
    li   t6, 4
    li   t2, 1
    jal  a4, expand
f1t3:                          # B' (move 5)
    add  t0, tp, s3
    lhu  s3, 2(t0)             # 8p' = pblock[8p + 2]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 0(t1)
    add  t2, a1, s5
    lbu  s5, 42(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, face1_done
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, face1_done
    li   t6, 5
    li   t2, 1
    jal  a4, expand
face1_done:
    beq  s11, a3, pop           # skip face 2 if the move into this node was D
face2:                         # face D: child starts as the node
    mv   s3, s6
    mv   s4, s7
    mv   s5, s8
f2t1:                          # D (move 6)
    add  t0, tp, s3
    lhu  s3, 4(t0)             # 8p' = pblock[8p + 4]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 1458(t1)
    add  t2, a1, s5
    lbu  s5, 84(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f2t2
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f2t2
    li   t6, 6
    li   t2, 2
    jal  a4, expand
f2t2:                          # D2 (move 7)
    add  t0, tp, s3
    lhu  s3, 4(t0)             # 8p' = pblock[8p + 4]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 1458(t1)
    add  t2, a1, s5
    lbu  s5, 84(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, f2t3
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, f2t3
    li   t6, 7
    li   t2, 2
    jal  a4, expand
f2t3:                          # D' (move 8)
    add  t0, tp, s3
    lhu  s3, 4(t0)             # 8p' = pblock[8p + 4]
    slli t1, s4, 1
    add  t1, t1, ra
    lhu  s4, 1458(t1)
    add  t2, a1, s5
    lbu  s5, 84(t2)
    add  t0, tp, s3
    lbu  t4, 6(t0)              # hperm[p']
    add  t5, t4, s2
    bltu s0, t5, face2_done
    slli t3, s5, 10
    add  t3, t3, s4
    add  t3, t3, a5
    lbu  t3, 0(t3)              # pdb[r << 10 | o]
    add  t5, t3, s2
    bltu s0, t5, face2_done
    li   t6, 8
    li   t2, 2
    jal  a4, expand
face2_done:
pop:                            # all faces done: back up one depth
    beq  s2, a2, iteration_done
    addi s2, s2, -1
    mv   s3, s6                 # parent's child is this depth's node
    mv   s4, s7
    mv   s5, s8
    lw   s6, 0(sp)
    lw   s7, 4(sp)
    lw   s8, 8(sp)
    lw   s11, 12(sp)
    lw   t0, 16(sp)
    addi sp, sp, 24
    jr   t0                     # resume at the next turn of the parent
iteration_done:                 # costs are integers, so the next bound
    addi s0, s0, 1              # is bound + 1; no minimum is tracked
    j    iteration

    # ---- expand a child: t3 pdb, t4 hperm, t6 move, t2 face, a4 resume ----
expand:
    bnez t4, descend            # both tables are 0 only at the solved state
    beqz t3, found
descend:
    addi sp, sp, -24
    sw   s6, 0(sp)
    sw   s7, 4(sp)
    sw   s8, 8(sp)
    sw   s11, 12(sp)
    sw   a4, 16(sp)
    sw   t6, 20(sp)
    mv   s6, s3
    mv   s7, s4
    mv   s8, s5
    mv   s11, t2
    addi s2, s2, 1
    beqz s11, face1             # same-face pruning: skip face 0 after R
    j    face0

    # ---- found: rebuild the path from the frame stack ----
    # Each frame holds the move into its child at 20(sp); the last move is t6.
found:                          # s2 = g = number of moves
    mv   t0, sp
    add  t1, gp, s2             # &path[g - 1]
path_loop:
    sb   t6, 0(t1)
    addi t1, t1, -1
    bge  gp, t1, solved         # wrote path[0]
    lw   t6, 20(t0)
    addi t0, t0, 24
    j    path_loop

    # ---- report: print the moves, then apply them and check (T5) ----
solved:                         # s2 = number of moves
    li   t6, 3                  # the search used t6 for the move
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
# >>> RENDER
    jal  render                 # the scrambled cube before the first move
# <<< RENDER
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

# >>> RENDER
    # ---- draw the cube on the LED Matrix as an unfolded net ----
    # 6 faces in a 4 x 3 grid of face slots, 2 x 2 facelets per face, each
    # facelet 4 x 3 LEDs, one LED of gap between face slots: 35 x 20 LEDs.
    # Reads perm_arr (s6) and ori_arr (s7); keeps s0, s2, s6-s11 and t6.
render:
    li   a0, LED_MATRIX_0_BASE
    li   a1, LED_MATRIX_0_WIDTH
    slli a1, a1, 2              # bytes per LED row, row-major y * WIDTH + x
    la   a2, facelet_xy
    la   a3, sticker
    la   a4, palette
    li   s1, 0                  # position P
r_pos:
    li   s3, 0                  # cubie at P (the fixed corner holds cubie 0)
    li   s4, 0                  # its twist
    beqz s1, r_fixed
    add  t0, s6, s1
    lbu  s3, -1(t0)             # perm_arr[P - 1] + 1
    addi s3, s3, 1
    add  t0, s7, s1
    lbu  s4, -1(t0)             # ori_arr[P - 1]
r_fixed:
    slli s5, s3, 1              # 3 * cubie: its row in sticker
    add  s5, s5, s3
    li   t5, 0                  # facelet k
r_facelet:
    sub  t0, t5, s4             # sticker j = (k - o) mod 3
    bgez t0, r_mod
    addi t0, t0, 3
r_mod:
    add  t0, t0, s5
    add  t0, a3, t0
    lbu  t0, 0(t0)
    slli t0, t0, 2
    add  t0, a4, t0
    lw   t1, 0(t0)              # colour
    lbu  t2, 0(a2)              # x
    lbu  t3, 1(a2)              # y
    addi a2, a2, 2
    slli t2, t2, 2
    add  t2, a0, t2
r_row:                          # + y rows; the renderer runs only in the GUI
    beqz t3, r_draw             # build, so a short loop beats a multiply
    add  t2, t2, a1
    addi t3, t3, -1
    j    r_row
r_draw:
    li   t3, 3                  # 3 rows of 4 LEDs
r_block:
    sw   t1, 0(t2)
    sw   t1, 4(t2)
    sw   t1, 8(t2)
    sw   t1, 12(t2)
    add  t2, t2, a1
    addi t3, t3, -1
    bnez t3, r_block
    addi t5, t5, 1
    bltu t5, t6, r_facelet      # t6 = 3
    addi s1, s1, 1
    li   t0, 8
    bltu s1, t0, r_pos
    ret
# <<< RENDER

    .data
expect:     .word @EXPECT@
frames:     .word 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0
            .word 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0
            .word 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0
frames_end:                     # 11 frames of 6 words: depth never exceeds 11
# >>> RENDER
palette:    .word 0xFFFFFF, 0xFFFF00, 0x00C000, 0x0000FF, 0xFF0000, 0xFF8000
                                # U white, D yellow, F green, B blue, R red, L orange
# For position P = 0..7 (0 is the fixed corner) and facelet k = 0..2, in
# clockwise order seen from outside starting at the U/D facelet: the pixel
# (x, y) of the facelet's top-left LED in the unfolded net.
facelet_xy: .byte 9,3, 4,7, 9,7,  13,3, 13,7, 18,7,  13,14, 18,10, 13,10
            .byte 9,14, 9,10, 4,10,  13,0, 22,7, 27,7,  13,17, 27,10, 22,10
            .byte 9,17, 0,10, 31,10,  9,0, 31,7, 0,7
# For cubie c = 0..7 and sticker j = 0..2 (same order, in its home slot):
# the palette index of its colour. With twist o, sticker j shows on facelet
# (j + o) mod 3, so facelet k shows sticker (k - o) mod 3.
sticker:    .byte 0,5,2, 0,2,4, 1,4,2, 1,2,5, 0,4,3, 1,3,4, 1,5,3, 0,3,5
# <<< RENDER
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
