.syntax unified
.thumb

.section .text
.global main
.global fault_handler

.equ GPIO_P1_BASE,   0x50000300
.equ LED_BLUE_PIN,   33
.equ LED_RED_PIN,    34

.equ REG_OUTSET,     0x508
.equ REG_OUTCLR,     0x50C
.equ REG_DIRSET,     0x518

.equ RAM_START,      0x20000000
.equ RAM_TEST_END,   0x2003D000
.equ RAM_END,        0x20040000

.equ FLASH_START,    0x00000000
.equ FLASH_END,      0x00100000
.equ FLASH_PAGE_SIZE,        0x00001000
.equ FLASH_PAGE_WORDS,       1024
.equ FLASH_PATTERN,          0xA5A5A5A5

.equ NVMC_BASE,      0x4001E000
.equ NVMC_READY,     0x400
.equ NVMC_CONFIG,    0x504
.equ NVMC_ERASEPAGE, 0x508
.equ NVMC_ICACHECNF, 0x540

.equ NVMC_MODE_REN,  0
.equ NVMC_MODE_WEN,  1
.equ NVMC_MODE_EEN,  2

.equ ACL_BASE,       0x4001E000
.equ ACL_STRIDE,     0x10
.equ ACL_ADDR,       0x800
.equ ACL_SIZE,       0x804
.equ ACL_PERM,       0x808
.equ ACL_REGION_COUNT, 8
.equ ACL_PERM_WRITE_DISABLE, 0x1
.equ ACL_PERM_READ_DISABLE,  0x2

.equ RAM_VECTOR_BASE, 0x2003D000
.equ RAM_STAGE_BASE,  0x2003E000
.equ SCB_VTOR,        0xE000ED08

.equ WDT_BASE,        0x40010000
.equ WDT_RR0,         0x600
.equ WDT_RR_MAGIC,    0x6E524635

.equ RTT_CB_BASE,     0x2003B000
.equ RTT_UP_DESC,     (RTT_CB_BASE + 0x18)
.equ RTT_UP_BUFFER,   0x2003B100
.equ RTT_UP_SIZE,     256
.equ FLASH_CURSOR_RAM, 0x2003B200
.equ TEST_STATE_RAM,   0x2003B204
.equ TEST_STATE_RUNNING, 0
.equ TEST_STATE_PASS,    1
.equ TEST_STATE_FAIL,    2

main:
    cpsid i

    ldr r6, =TEST_STATE_RAM
    movs r0, #TEST_STATE_RUNNING
    str r0, [r6]

    ldr r8, =GPIO_P1_BASE

    ldr r9, =(1 << (LED_BLUE_PIN - 32))
    ldr r10, =(1 << (LED_RED_PIN - 32))

    orrs r11, r9, r10

    str r11, [r8, #REG_DIRSET]
    bl led_all_off

    bl startup_led_test

    bl ram_test_all
    cmp r0, #0
    bne fail_red_solid

    ldr r2, =flash_stage_start
    ldr r3, =flash_stage_end
    ldr r4, =RAM_STAGE_BASE
    mov r5, r4

copy_stage_loop:
    cmp r2, r3
    bcs jump_stage
    ldrb r6, [r2]
    strb r6, [r5]
    adds r2, r2, #1
    adds r5, r5, #1
    b copy_stage_loop

jump_stage:
    ldr r2, =flash_stage_start
    rsb r3, r2, r4
    mov r0, r8
    mov r1, r9
    mov r2, r10
    mov r6, r4
    adds r6, r6, #1
    bx r6

startup_led_test:
    push {lr}
    bl led_blue_on
    ldr r2, =6000000
    bl delay
    bl led_blue_off

    ldr r2, =3000000
    bl delay

    bl led_red_on
    ldr r2, =6000000
    bl delay
    bl led_red_off

    ldr r2, =6000000
    bl delay
    pop {pc}

ram_test_all:
    ldr r4, =RAM_START
    ldr r5, =0xAAAAAAAA
    ldr r6, =0x55555555
    ldr r7, =RAM_TEST_END

ram_test_loop:
    cmp r4, r7
    bcs ram_test_ok

    str r5, [r4]
    ldr r0, [r4]
    cmp r0, r5
    bne ram_test_ng

    str r6, [r4]
    ldr r0, [r4]
    cmp r0, r6
    bne ram_test_ng

    str r4, [r4]
    ldr r0, [r4]
    cmp r0, r4
    bne ram_test_ng

    adds r4, r4, #4
    b ram_test_loop

ram_test_ok:
    movs r0, #0
    bx lr

ram_test_ng:
    movs r0, #1
    bx lr

fail_red_solid:
    bl led_blue_off
    bl led_red_on
fail_red_loop:
    b fail_red_loop

delay:
delay_loop:
    subs r2, r2, #1
    bne delay_loop
    bx lr

fault_handler:
    ldr r8, =GPIO_P1_BASE
    ldr r9, =(1 << (LED_BLUE_PIN - 32))
    ldr r10, =(1 << (LED_RED_PIN - 32))
    bl led_blue_off
fault_blink_loop:
    bl led_red_off
    ldr r2, =6000000
    bl delay
    bl led_red_on
    ldr r2, =6000000
    bl delay
    b fault_blink_loop
fault_loop:
    b fault_loop

.ltorg

flash_stage_start:
flash_stage_entry:
    mov r8, r0
    mov r9, r1
    mov r10, r2
    mov r11, r3

    bl led_red_off

    bl rtt_init
    ldr r0, =rtt_msg_start
    bl rtt_write_str

    bl stage_setup_vectors
    bl nvmc_disable_icache

    ldr r6, =TEST_STATE_RAM
    movs r0, #TEST_STATE_RUNNING
    str r0, [r6]

    ldr r0, =FLASH_START
    ldr r1, =FLASH_END
    bl flash_test_range
    cmp r0, #0
    bne stage_fail

stage_pass:
    bl led_red_off
    bl led_blue_on
    ldr r6, =TEST_STATE_RAM
    movs r0, #TEST_STATE_PASS
    str r0, [r6]
stage_pass_loop:
    ldr r2, =800000
    bl delay_stage
    b stage_pass_loop

stage_fail:
    bl led_blue_off
    bl led_red_on
    ldr r6, =TEST_STATE_RAM
    movs r0, #TEST_STATE_FAIL
    str r0, [r6]
stage_fail_loop:
    b stage_fail_loop

flash_test_range:
    push {lr}

    ldr r6, =FLASH_CURSOR_RAM
    str r0, [r6]

flash_page_loop:
    ldr r6, =FLASH_CURSOR_RAM
    ldr r0, [r6]
    ldr r1, =FLASH_END
    cmp r0, r1
    bcs flash_test_ok

    bl feed_wdt
    bl led_red_off
    bl flash_progress_pulse

    ldr r6, =FLASH_CURSOR_RAM
    ldr r0, [r6]
    lsrs r1, r0, #12
    ands r1, r1, #0x0F
    b flash_page_log_skip
flash_page_log_skip:
    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    ldr r1, =FLASH_END
    cmp r12, r1
    bcs flash_test_ok
    mov r0, r12
    bl flash_page_acl_mode

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    ldr r1, =FLASH_END
    cmp r12, r1
    bcs flash_test_ok

    cmp r0, #1
    beq flash_page_read_only
    cmp r0, #2
    beq flash_page_skip

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    mov r0, r12
    bl flash_erase_page
    cmp r0, #0
    bne flash_test_ng_erase

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    mov r0, r12
    bl flash_verify_erased_page
    cmp r0, #0
    bne flash_test_ng_verify_erased

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    mov r0, r12
    bl flash_program_page_pattern
    cmp r0, #0
    bne flash_test_ng_program

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    mov r0, r12
    bl flash_verify_page_pattern
    cmp r0, #0
    bne flash_test_ng_verify_pattern

    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    ldr r6, =FLASH_PAGE_SIZE
    adds r12, r12, r6
    ldr r6, =FLASH_CURSOR_RAM
    str r12, [r6]
    b flash_page_loop

flash_page_read_only:
    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    mov r0, r12
    bl flash_read_page_probe
    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    ldr r6, =FLASH_PAGE_SIZE
    adds r12, r12, r6
    ldr r6, =FLASH_CURSOR_RAM
    str r12, [r6]
    b flash_page_loop

flash_page_skip:
    ldr r6, =FLASH_CURSOR_RAM
    ldr r12, [r6]
    ldr r6, =FLASH_PAGE_SIZE
    adds r12, r12, r6
    ldr r6, =FLASH_CURSOR_RAM
    str r12, [r6]
    b flash_page_loop

flash_test_ok:
    b stage_pass

flash_test_ng:
    movs r0, #1
    b flash_test_ret

flash_test_ng_erase:
    movs r0, #11
    ldr r6, =FLASH_CURSOR_RAM
    ldr r1, [r6]
    bl rtt_log_error
    b flash_test_ret

flash_test_ng_verify_erased:
    movs r0, #12
    ldr r6, =FLASH_CURSOR_RAM
    ldr r1, [r6]
    bl rtt_log_error
    b flash_test_ret

flash_test_ng_program:
    movs r0, #13
    ldr r6, =FLASH_CURSOR_RAM
    ldr r1, [r6]
    bl rtt_log_error
    b flash_test_ret

flash_test_ng_verify_pattern:
    movs r0, #14
    ldr r6, =FLASH_CURSOR_RAM
    ldr r1, [r6]
    bl rtt_log_error

flash_test_ret:
    pop {pc}

rtt_init:
    push {r0-r7, lr}
    ldr r0, =rtt_id_string
    ldr r1, =RTT_CB_BASE
    movs r2, #16
rtt_init_copy_id:
    ldrb r3, [r0]
    strb r3, [r1]
    adds r0, r0, #1
    adds r1, r1, #1
    subs r2, r2, #1
    bne rtt_init_copy_id

    ldr r1, =RTT_CB_BASE
    movs r0, #1
    str r0, [r1, #0x10]
    movs r0, #0
    str r0, [r1, #0x14]

    adds r1, r1, #0x18
    str r0, [r1, #0x00]
    ldr r2, =RTT_UP_BUFFER
    str r2, [r1, #0x04]
    ldr r2, =RTT_UP_SIZE
    str r2, [r1, #0x08]
    str r0, [r1, #0x0C]
    str r0, [r1, #0x10]
    str r0, [r1, #0x14]

    ldr r1, =RTT_UP_BUFFER
    ldr r2, =RTT_UP_SIZE
rtt_init_clear_buf:
    strb r0, [r1]
    adds r1, r1, #1
    subs r2, r2, #1
    bne rtt_init_clear_buf
    pop {r0-r7, pc}

rtt_write_char:
    push {r1-r7, lr}
    mov r1, r0
    ldr r2, =RTT_UP_DESC
    ldr r3, [r2, #0x04]
    ldr r4, [r2, #0x08]
    ldr r5, [r2, #0x0C]
    ldr r6, [r2, #0x10]
    cmp r4, #0
    beq rtt_write_char_done
    adds r7, r5, #1
    cmp r7, r4
    bcc rtt_write_char_check
    movs r7, #0
rtt_write_char_check:
    cmp r7, r6
    beq rtt_write_char_done
    adds r3, r3, r5
    strb r1, [r3]
    str r7, [r2, #0x0C]
rtt_write_char_done:
    pop {r1-r7, pc}

rtt_write_str:
    push {r1-r2, lr}
rtt_write_str_loop:
    ldrb r1, [r0]
    cmp r1, #0
    beq rtt_write_str_done
    mov r2, r0
    mov r0, r1
    bl rtt_write_char
    adds r0, r2, #1
    b rtt_write_str_loop
rtt_write_str_done:
    pop {r1-r2, pc}

rtt_write_hex32:
    push {r1-r4, lr}
    mov r1, r0
    ldr r2, =hex_chars
    movs r3, #8
rtt_write_hex32_loop:
    lsrs r4, r1, #28
    ldrb r0, [r2, r4]
    bl rtt_write_char
    lsls r1, r1, #4
    subs r3, r3, #1
    bne rtt_write_hex32_loop
    pop {r1-r4, pc}

rtt_log_page:
    push {r0-r2, lr}
    mov r1, r0
    ldr r0, =rtt_msg_page
    bl rtt_write_str
    mov r0, r1
    bl rtt_write_hex32
    movs r0, #10
    bl rtt_write_char
    pop {r0-r2, pc}

rtt_log_error:
    push {r0-r2, lr}
    mov r2, r1
    mov r1, r0
    ldr r0, =rtt_msg_err
    bl rtt_write_str
    mov r0, r1
    bl rtt_write_hex32
    ldr r0, =rtt_msg_page_short
    bl rtt_write_str
    mov r0, r2
    bl rtt_write_hex32
    movs r0, #10
    bl rtt_write_char
    pop {r0-r2, pc}

flash_page_acl_mode:
    movs r0, #0
    bx lr

flash_read_page_probe:
    mov r2, r0
    ldr r3, =FLASH_PAGE_WORDS

flash_read_page_probe_loop:
    ldr r1, [r2]
    adds r2, r2, #4
    subs r3, r3, #1
    bne flash_read_page_probe_loop

    movs r0, #0
    bx lr

flash_erase_page:
    push {r4, lr}
    mov r4, r0

    movs r0, #NVMC_MODE_EEN
    bl flash_set_mode

    ldr r1, =NVMC_BASE
    str r4, [r1, #NVMC_ERASEPAGE]
    bl flash_wait_ready

    movs r0, #NVMC_MODE_REN
    bl flash_set_mode

    movs r0, #0
    pop {r4, pc}

flash_verify_erased_page:
    mov r2, r0
    ldr r3, =FLASH_PAGE_WORDS
    ldr r4, =0xFFFFFFFF

flash_verify_erased_loop:
    ldr r5, [r2]
    cmp r5, r4
    bne flash_verify_erased_ng
    adds r2, r2, #4
    subs r3, r3, #1
    bne flash_verify_erased_loop

    movs r0, #0
    bx lr

flash_verify_erased_ng:
    movs r0, #1
    bx lr

flash_program_page_pattern:
    push {lr}
    mov r2, r0
    ldr r3, =FLASH_PAGE_WORDS
    ldr r6, =FLASH_PATTERN

    movs r0, #NVMC_MODE_WEN
    bl flash_set_mode

flash_program_loop:
    eors r7, r2, r6
    str r7, [r2]
    bl flash_wait_ready
    adds r2, r2, #4
    subs r3, r3, #1
    bne flash_program_loop

    movs r0, #NVMC_MODE_REN
    bl flash_set_mode

    movs r0, #0
    pop {pc}

flash_verify_page_pattern:
    mov r2, r0
    ldr r3, =FLASH_PAGE_WORDS
    ldr r6, =FLASH_PATTERN

flash_verify_pattern_loop:
    eors r7, r2, r6
    ldr r1, [r2]
    cmp r1, r7
    bne flash_verify_pattern_ng
    adds r2, r2, #4
    subs r3, r3, #1
    bne flash_verify_pattern_loop

    movs r0, #0
    bx lr

flash_verify_pattern_ng:
    movs r0, #1
    bx lr

flash_set_mode:
    ldr r1, =NVMC_BASE
    str r0, [r1, #NVMC_CONFIG]
    dsb
    isb
    b flash_wait_ready

flash_wait_ready:
    push {r4, lr}
    ldr r1, =NVMC_BASE
flash_wait_ready_loop:
    ldr r4, [r1, #NVMC_READY]
    cmp r4, #0
    beq flash_wait_ready_loop
    bl feed_wdt
    dsb
    pop {r4, pc}

nvmc_disable_icache:
    push {r0, r1, lr}
    ldr r1, =NVMC_BASE
    movs r0, #0
    str r0, [r1, #NVMC_ICACHECNF]
    dsb
    isb
    pop {r0, r1, pc}

flash_progress_pulse:
    push {r0, r1, r2, lr}
    bl led_blue_on
    ldr r2, =40000
    bl delay_stage
    bl led_blue_off
    ldr r2, =40000
    bl delay_stage
    pop {r0, r1, r2, pc}

led_blue_on:
    str r9, [r8, #REG_OUTSET]
    bx lr

led_blue_off:
    str r9, [r8, #REG_OUTCLR]
    bx lr

led_red_on:
    str r10, [r8, #REG_OUTSET]
    bx lr

led_red_off:
    str r10, [r8, #REG_OUTCLR]
    bx lr

led_all_off:
    str r11, [r8, #REG_OUTCLR]
    bx lr

delay_stage:
    push {lr}
    bl feed_wdt
delay_stage_loop:
    subs r2, r2, #1
    bne delay_stage_loop
    pop {pc}

feed_wdt:
    push {r0, r1, r2, lr}
    ldr r0, =WDT_BASE
    ldr r1, =WDT_RR_MAGIC
    str r1, [r0, #WDT_RR0]
    str r1, [r0, #(WDT_RR0 + 4)]
    str r1, [r0, #(WDT_RR0 + 8)]
    str r1, [r0, #(WDT_RR0 + 12)]
    str r1, [r0, #(WDT_RR0 + 16)]
    str r1, [r0, #(WDT_RR0 + 20)]
    str r1, [r0, #(WDT_RR0 + 24)]
    str r1, [r0, #(WDT_RR0 + 28)]
    pop {r0, r1, r2, pc}

stage_setup_vectors:
    ldr r4, =RAM_VECTOR_BASE
    ldr r5, =RAM_END
    str r5, [r4, #0]

    ldr r5, =stage_fault_handler
    adds r5, r5, r11
    adds r5, r5, #1

    str r5, [r4, #4]
    str r5, [r4, #8]
    str r5, [r4, #12]
    str r5, [r4, #16]
    str r5, [r4, #20]
    str r5, [r4, #24]
    str r5, [r4, #44]
    str r5, [r4, #48]
    str r5, [r4, #56]
    str r5, [r4, #60]
    str r5, [r4, #128]

    ldr r5, =SCB_VTOR
    str r4, [r5]
    dsb
    isb
    bx lr

stage_fault_handler:
    bl led_blue_off
    bl led_red_on
stage_fault_loop:
    b stage_fault_loop

rtt_id_string:
    .ascii "SEGGER RTT"
    .byte 0, 0, 0, 0, 0, 0

hex_chars:
    .ascii "0123456789ABCDEF"

rtt_msg_start:
    .asciz "START\n"

rtt_msg_pass:
    .asciz "PASS\n"

rtt_msg_page:
    .asciz "PAGE="

rtt_msg_err:
    .asciz "ERR="

rtt_msg_page_short:
    .asciz " PAGE="

.ltorg
flash_stage_end:
