MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 1024K
    RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 256K
}

SECTIONS
{
    .text :
    {
        /* Initial SP and reset vector */
        LONG(0x20040000);
        LONG(main + 1);

        *(.text*)
        *(.rodata*)
    } > FLASH

    .data :
    {
        __data_start__ = .;
        *(.data*)
        __data_end__ = .;
    } > RAM AT > FLASH

    .bss (NOLOAD) :
    {
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        __bss_end__ = .;
    } > RAM

    _end = .;
    end = .;
}
