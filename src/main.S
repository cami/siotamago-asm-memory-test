.syntax unified
.thumb

.section .text
.global main

.equ GPIO_P0_BASE,   0x50000000
.equ GPIO_P1_BASE,   0x50000300
.equ PIN_LED,        33

.equ REG_OUTSET,     0x508
.equ REG_OUTCLR,     0x50C
.equ REG_DIRSET,     0x518

.equ RAM_START,      0x20000000
.equ RAM_END,        0x20040000

main:
    cpsid i

    movs r2, #PIN_LED
    lsrs r3, r2, #5
    ands r2, r2, #31

    cmp r3, #0
    beq use_port0
    ldr r0, =GPIO_P1_BASE
    b make_mask

use_port0:
    ldr r0, =GPIO_P0_BASE

make_mask:
    movs r1, #1
    lsls r1, r1, r2

    @ LED pin as output
    str r1, [r0, #REG_DIRSET]

    @ Active-low LED off at boot
    str r1, [r0, #REG_OUTSET]

    ldr r4, =RAM_START
    ldr r5, =0xAAAAAAAA
    ldr r6, =0x55555555

ram_test_loop:
    ldr r7, =RAM_END
    cmp r4, r7
    bcs ram_test_pass

    str r5, [r4]
    ldr r7, [r4]
    cmp r7, r5
    bne ram_test_fail

    str r6, [r4]
    ldr r7, [r4]
    cmp r7, r6
    bne ram_test_fail

    str r4, [r4]
    ldr r7, [r4]
    cmp r7, r4
    bne ram_test_fail

    adds r4, r4, #4
    b ram_test_loop

ram_test_pass:
    @ Slow blink means RAM test passed.
    str r1, [r0, #REG_OUTCLR]
    ldr r2, =12000000
    bl delay
    str r1, [r0, #REG_OUTSET]
    ldr r2, =12000000
    bl delay
    b ram_test_pass

ram_test_fail:
    @ Fast blink means RAM test failed.
    str r1, [r0, #REG_OUTCLR]
    ldr r2, =1200000
    bl delay
    str r1, [r0, #REG_OUTSET]
    ldr r2, =1200000
    bl delay
    b ram_test_fail

delay:
delay_loop:
    subs r2, r2, #1
    bne delay_loop
    bx lr
