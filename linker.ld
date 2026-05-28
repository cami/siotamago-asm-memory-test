MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 1024K
    RAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 256K
}

SECTIONS
{
    .text :
    {
        /* Initial SP and vector table */
        LONG(0x20040000);
        LONG(main + 1);
        LONG(fault_handler + 1);  /* NMI */
        LONG(fault_handler + 1);  /* HardFault */
        LONG(fault_handler + 1);  /* MemManage */
        LONG(fault_handler + 1);  /* BusFault */
        LONG(fault_handler + 1);  /* UsageFault */
        LONG(0);
        LONG(0);
        LONG(0);
        LONG(0);
        LONG(fault_handler + 1);  /* SVC */
        LONG(fault_handler + 1);  /* DebugMon */
        LONG(0);
        LONG(fault_handler + 1);  /* PendSV */
        LONG(fault_handler + 1);  /* SysTick */

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
