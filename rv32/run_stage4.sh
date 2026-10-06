#!/bin/zsh
# Stage 4 measurements: hand-written assembly against the gcc -O2 build of
# the same algorithm (rv32/ida.c), on the same inputs, both RENDER=0.
#   code size        bytes of linked .text
#   retired instr.   Ripes --iret on RV32_ISS
# Test cases: solved, a 3-move scramble (R B' D2), the 11-move reference
# vector, and the two distance-11 states with the most search nodes.
# Each program checks its own answer and prints OK or FAIL. Ripes prints the
# NUL that ends each string; tr removes it so the log stays plain text.
# Writes everything to stage4.log next to this script (about a minute).
set -u
cd ${0:A:h}
RIPES=${RIPES:-~/ca/Ripes.app/Contents/MacOS/Ripes}
CROSS=${CROSS:-riscv64-unknown-elf-}
exec > >(tee stage4.log) 2>&1

echo "### environment"
date
echo "minirubik: $(git describe --always --dirty)"
echo "ripes sha256: $(shasum -a 256 $RIPES | cut -d' ' -f1)"
${CROSS}gcc --version | head -1

echo "### code size (bytes of linked .text, RENDER=0)"
asm=$(OUT=build/size.s ./build_asm.sh 21345671111111 11)
${CROSS}gcc -march=rv32i -mabi=ilp32 -nostdlib -Wl,-e,main -T link.ld -o build/asm.elf $asm
echo "asm: $(${CROSS}size -A build/asm.elf | awk '$1 == ".text" {print $2}')"
make -s CUBE=21345671111111 > /dev/null
echo "gcc: $(${CROSS}size -A ida-21345671111111.elf | awk '$1 == ".text" {print $2}')"

echo "### tests on RV32_ISS"
for cube expect in 12345671111111 0  24173562322133 3  21345671111111 11 \
                   14325671111111 11  54721631111111 11; do
    echo "--- asm $cube (expect $expect moves)"
    $RIPES --mode cli -t asm --proc RV32_ISS --src $(./build_asm.sh $cube $expect) --iret 2>&1 | tr -d '\000'
    echo "--- gcc $cube"
    make -s CUBE=$cube > /dev/null
    $RIPES --mode cli -t elf --proc RV32_ISS --src ida-$cube.elf --iret 2>&1 | tr -d '\000'
done
echo "### done"
