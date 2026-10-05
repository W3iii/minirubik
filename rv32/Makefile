# C reference build for Ripes.
#   make                         build ida-21345671111111.elf
#   make CUBE=14325671111111     build ida-14325671111111.elf
# The state is part of the file name, so changing CUBE always rebuilds.
CROSS  ?= riscv64-unknown-elf-
CUBE   ?= 21345671111111
CFLAGS  = -O2 -march=rv32i -mabi=ilp32 -ffreestanding -fno-builtin -nostdlib \
          -Wall -Wextra '-DCUBE="$(CUBE)"'
SRCS    = crt0.s main.c ida.c tables.c
ELF     = ida-$(CUBE).elf

$(ELF): $(SRCS) ida.h tables.h link.ld
	$(CROSS)gcc $(CFLAGS) -T link.ld -o $@ $(SRCS)
	$(CROSS)size -A $@ | grep -E '^\.(text|rodata|data|bss) '
	@if $(CROSS)objdump -d $@ | grep -Eq '__(mul|div|udiv|mod|umod)si3|\s(mul|mulh|mulhu|mulhsu|div|divu|rem|remu)\s'; \
	then echo "ERROR: multiply or divide in $@"; exit 1; \
	else echo "no multiply or divide instructions or helper calls"; fi

clean:
	rm -f ida-*.elf

.PHONY: clean
