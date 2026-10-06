#!/bin/zsh
# Run the assembly solver on every distance-11 state (tools/d11_states.txt)
# on RV32_ISS and report the worst --iret. Each run checks its own answer
# (11 moves, path reaches solved) and prints OK.
# Writes one line per state to all_d11.log, then a summary (about an hour).
set -u
cd ${0:A:h}
RIPES=${RIPES:-~/ca/Ripes.app/Contents/MacOS/Ripes}
exec > >(tee all_d11.log) 2>&1
echo "### environment"
date
echo "minirubik: $(git describe --always --dirty)"
echo "ripes sha256: $(shasum -a 256 $RIPES | cut -d' ' -f1)"
echo "### state iret result"
n=0 ok=0 max=0 worst="" sum=0
while read cube; do
    src=$(OUT=build/d11.s ./build_asm.sh $cube 11)
    out=$($RIPES --mode cli -t asm --proc RV32_ISS --src $src --iret 2>&1)
    iret=$(print -r -- "$out" | awk '/instructions retired/ {getline; print}')
    result=FAIL
    print -r -- "$out" | grep -qx OK && result=OK
    echo "$cube $iret $result"
    (( n++ ))
    [[ $result == OK ]] && (( ok++ ))
    (( sum += iret ))
    (( iret > max )) && { max=$iret; worst=$cube; }
done < ../tools/d11_states.txt
echo "### summary"
echo "states: $n, OK: $ok"
echo "max iret: $max ($worst)"
echo "mean iret: $(( sum / n ))"
echo "### done"
