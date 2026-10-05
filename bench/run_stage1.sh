#!/bin/zsh
# Stage 1 measurements for minirubik on RV32I.
# Writes everything to stage1.log next to this script. Run on AC power.
# Takes about 30 minutes, almost all of it RV32_5S.
# Override the Ripes binary with RIPES=/path/to/Ripes if it lives elsewhere.
#   1. multest.s       : confirm the default ISA is plain RV32I (mul must fail)
#   2. simulation rate : --iret and --exectime, RV32_ISS and RV32_5S
#   3. host memory     : max RSS of fill_*.s at four sizes (slope = host bytes
#                        per guest byte; four points check that it is linear)
set -u
RIPES=${RIPES:-~/ca/Ripes.app/Contents/MacOS/Ripes}
N=3                                  # repetitions per measurement
cd ${0:A:h}                          # directory of this script
TMP=$(mktemp)
trap 'rm -f $TMP' EXIT
exec > >(tee stage1.log) 2>&1

sim() {  # sim <proc> <file>: full Ripes output
  $RIPES --mode cli -t asm --proc $1 --src $2 --iret --exectime 2>&1
}

rss() {  # rss <file>: max RSS in bytes of one RV32_ISS run
  /usr/bin/time -l $RIPES --mode cli -t asm --proc RV32_ISS --src $1 \
    > /dev/null 2> $TMP
  awk '/maximum resident set size/ {print $1}' $TMP
}

echo "### environment"
date
sw_vers | tr '\n' ' '; echo
pmset -g batt | head -1
echo "ripes sha256: $(shasum -a 256 $RIPES | cut -d' ' -f1)"
echo "minirubik: $(git rev-parse HEAD)"

echo "### 1. ISA check (multest.s must fail to assemble)"
sim RV32_ISS multest.s

echo "### 2. simulation rate"
for i in $(seq $N); do echo "--- RV32_ISS alu_loop.s run $i"; sim RV32_ISS alu_loop.s; done
for p in RV32_ISS RV32_5S; do               # same program on both models
  for i in $(seq $N); do echo "--- $p mem_loop.s run $i"; sim $p mem_loop.s; done
done

echo "### 3. host bytes per guest byte (max RSS, bytes)"
for i in $(seq $N); do
  for f in fill_1k.s fill_64k.s fill_256k.s fill_1m.s; do
    echo "run $i  $f  $(rss $f)"
  done
done
echo "### done"
