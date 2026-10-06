#!/bin/zsh
# Gate T7: the test cases reproduce on a pipelined model, RV32_5S, with the
# same output as on RV32_ISS (stage4.log). Each program checks its own
# answer and prints OK. Also reports --cycles to show the pipeline cost.
# Writes everything to t7.log next to this script (a few minutes).
set -u
cd ${0:A:h}
RIPES=${RIPES:-~/ca/Ripes.app/Contents/MacOS/Ripes}
exec > >(tee t7.log) 2>&1
echo "### environment"
date
echo "minirubik: $(git describe --always --dirty)"
echo "ripes sha256: $(shasum -a 256 $RIPES | cut -d' ' -f1)"
echo "### tests on RV32_5S"
for cube expect in 12345671111111 0  24173562322133 3  21345671111111 11 \
                   14325671111111 11  54721631111111 11; do
    echo "--- asm $cube (expect $expect moves)"
    $RIPES --mode cli -t asm --proc RV32_5S --src $(./build_asm.sh $cube $expect) \
        --iret --cycles --exectime 2>&1 | tr -d '\000'
done
echo "### done"
