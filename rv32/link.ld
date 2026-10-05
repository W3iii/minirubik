/* Ripes memory map: text at 0, data segment at 0x10000000. */
ENTRY(_start)
SECTIONS
{
    . = 0x00000000;
    .text : { *(.text.start) *(.text .text.*) }
    . = 0x10000000;
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
    .data : { *(.data .data.* .sdata .sdata.*) }
    .bss : { *(.bss .bss.* .sbss .sbss.* COMMON) }
}
