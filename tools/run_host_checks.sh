#!/bin/zsh
# Host-side correctness gates for the RV32I solver.
#   gen_tables: writes rv32/tables.{c,s}, checks H1 and H2
#   verify    : runs rv32/ida.c on all 3,674,160 states, checks H3
# H4 does not apply: no table is packed, every entry is one byte or halfword.
# Writes everything to host_checks.log next to this script (about a minute).
set -eu
cd ${0:A:h}
exec > >(tee host_checks.log) 2>&1
echo "### environment"
date
cc --version | head -1
echo "minirubik: $(git describe --always --dirty)"
echo "### gen_tables (H1, H2)"
cc -O2 -Wall -Wextra -o gen_tables gen_tables.c
./gen_tables
echo "### verify (H3)"
cc -O2 -Wall -Wextra -DIDA_COUNT_NODES -I../rv32 -o verify verify.c ../rv32/ida.c ../rv32/tables.c
./verify
echo "### done"
