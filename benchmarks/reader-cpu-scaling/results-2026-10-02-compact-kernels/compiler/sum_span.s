_sum_span:                              ; @sum_span
Lfunc_begin187:
	.loc	0 1824 0                        ; numeric-payload.c:1824:0
	.cfi_startproc
; %bb.0:
	;DEBUG_VALUE: sum_span:span <- $x0
	;DEBUG_VALUE: sum_span:context <- $x2
	sub	sp, sp, #272
	stp	d15, d14, [sp, #112]            ; 16-byte Folded Spill
	stp	d13, d12, [sp, #128]            ; 16-byte Folded Spill
	stp	d11, d10, [sp, #144]            ; 16-byte Folded Spill
	stp	d9, d8, [sp, #160]              ; 16-byte Folded Spill
	stp	x28, x27, [sp, #176]            ; 16-byte Folded Spill
	stp	x26, x25, [sp, #192]            ; 16-byte Folded Spill
	stp	x24, x23, [sp, #208]            ; 16-byte Folded Spill
	stp	x22, x21, [sp, #224]            ; 16-byte Folded Spill
	stp	x20, x19, [sp, #240]            ; 16-byte Folded Spill
	stp	x29, x30, [sp, #256]            ; 16-byte Folded Spill
	add	x29, sp, #256
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	.cfi_offset w23, -56
	.cfi_offset w24, -64
	.cfi_offset w25, -72
	.cfi_offset w26, -80
	.cfi_offset w27, -88
	.cfi_offset w28, -96
	.cfi_offset b8, -104
	.cfi_offset b9, -112
	.cfi_offset b10, -120
	.cfi_offset b11, -128
	.cfi_offset b12, -136
	.cfi_offset b13, -144
	.cfi_offset b14, -152
	.cfi_offset b15, -160
Ltmp9622:
	;DEBUG_VALUE: sum_span:state <- $x2
	mov	x28, x2
Ltmp9623:
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: sum_span:state <- $x28
	mov	x20, x0
Ltmp9624:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:offset <- undef
	.loc	0 1829 19 prologue_end          ; numeric-payload.c:1829:19
	ldr	w8, [x0, #16]
	.loc	0 1829 5 is_stmt 0              ; numeric-payload.c:1829:5
	cmp	w8, #1
	b.gt	LBB187_10
Ltmp9625:
; %bb.1:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cbz	w8, LBB187_55
Ltmp9626:
; %bb.2:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #1
	b.ne	LBB187_1014
Ltmp9627:
; %bb.3:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- undef
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x21, [x20]
Ltmp9628:
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	ldr	w8, [x20, #20]
Ltmp9629:
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	ldr	d8, [x28, #8]
Ltmp9630:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #32]
	str	x28, [sp, #24]                  ; 8-byte Folded Spill
	cbz	x9, LBB187_149
Ltmp9631:
; %bb.4:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1831 63 is_stmt 1             ; numeric-payload.c:1831:63
	ldr	w11, [x28]
Ltmp9632:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	w10, [x20, #24]
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	ldr	x9, [x20, #8]
	cmp	w10, #111
	cbz	w11, LBB187_234
Ltmp9633:
; %bb.5:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.gt	LBB187_337
Ltmp9634:
; %bb.6:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w8, #1
	b.eq	LBB187_654
Ltmp9635:
; %bb.7:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_724
Ltmp9636:
; %bb.8:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp9637:
; %bb.9:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #8
	mov	w23, #65536                     ; =0x10000
	mov	w24, #32767                     ; =0x7fff
	mov	x25, #70368744177664            ; =0x400000000000
	movk	x25, #16527, lsl #48
	mov	x26, #2147483648                ; =0x80000000
	movk	x26, #53239, lsl #32
	movk	x26, #49586, lsl #48
	b	LBB187_20
Ltmp9638:
LBB187_10:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1829 5 is_stmt 1              ; numeric-payload.c:1829:5
	cmp	w8, #2
	str	x28, [sp, #24]                  ; 8-byte Folded Spill
	b.eq	LBB187_89
Ltmp9639:
; %bb.11:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #3
	b.ne	LBB187_1014
Ltmp9640:
; %bb.12:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x21, [x20]
Ltmp9641:
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	ldr	w8, [x20, #20]
Ltmp9642:
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	ldr	d8, [x28, #8]
Ltmp9643:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #32]
	cbz	x9, LBB187_171
Ltmp9644:
; %bb.13:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1833 67 is_stmt 1             ; numeric-payload.c:1833:67
	ldr	w11, [x28]
Ltmp9645:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	w10, [x20, #24]
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	ldr	x9, [x20, #8]
	cmp	w10, #111
	cbz	w11, LBB187_250
Ltmp9646:
; %bb.14:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.gt	LBB187_368
Ltmp9647:
; %bb.15:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w8, #1
	b.eq	LBB187_662
Ltmp9648:
; %bb.16:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_732
Ltmp9649:
; %bb.17:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp9650:
; %bb.18:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	x23, #70368744177664            ; =0x400000000000
	movk	x23, #16527, lsl #48
	mov	x24, #2147483648                ; =0x80000000
	movk	x24, #53239, lsl #32
	movk	x24, #49586, lsl #48
	mov	w25, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_47
Ltmp9651:
LBB187_19:                              ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x27, x8
Ltmp9652:
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp9653:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp9654:
LBB187_20:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_27 Depth 2
                                        ;     Child Loop BB187_30 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x27
Ltmp9655:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x28, x8, x23, lo
Ltmp9656:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_22
Ltmp9657:
; %bb.21:                               ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp9658:
LBB187_22:                              ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x28, x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp9659:
	;DEBUG_VALUE: i <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x8
	b.hs	LBB187_19
Ltmp9660:
; %bb.23:                               ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ands	x9, x28, #0x7
	b.ne	LBB187_27
Ltmp9661:
LBB187_24:                              ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sub	x9, x28, #1
	cmp	x9, #7
	b.lo	LBB187_19
Ltmp9662:
; %bb.25:                               ;   in Loop: Header=BB187_20 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x27, x28
	sub	x9, x9, x10
	add	x10, x22, x10, lsl #1
	b	LBB187_30
Ltmp9663:
LBB187_26:                              ;   in Loop: Header=BB187_27 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #1
Ltmp9664:
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
	b.eq	LBB187_24
Ltmp9665:
LBB187_27:                              ;   Parent Loop BB187_20 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w11, [x21, x10, lsl #1]
Ltmp9666:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_26
Ltmp9667:
; %bb.28:                               ;   in Loop: Header=BB187_27 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9668:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9669:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9670:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_26
Ltmp9671:
LBB187_29:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #16
	subs	x9, x9, #8
Ltmp9672:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.eq	LBB187_19
Ltmp9673:
LBB187_30:                              ;   Parent Loop BB187_20 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldurh	w11, [x10, #-8]
Ltmp9674:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_32
Ltmp9675:
; %bb.31:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9676:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9677:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9678:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_32:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldurh	w11, [x10, #-6]
Ltmp9679:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_34
Ltmp9680:
; %bb.33:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9681:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9682:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9683:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_34:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldurh	w11, [x10, #-4]
Ltmp9684:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_36
Ltmp9685:
; %bb.35:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9686:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9687:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9688:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_36:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldurh	w11, [x10, #-2]
Ltmp9689:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_38
Ltmp9690:
; %bb.37:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9691:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9692:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9693:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_38:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrh	w11, [x10]
Ltmp9694:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_40
Ltmp9695:
; %bb.39:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9696:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9697:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9698:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_40:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrh	w11, [x10, #2]
Ltmp9699:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_42
Ltmp9700:
; %bb.41:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9701:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9702:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9703:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_42:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrh	w11, [x10, #4]
Ltmp9704:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_44
Ltmp9705:
; %bb.43:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9706:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9707:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9708:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_44:                              ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrh	w11, [x10, #6]
Ltmp9709:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.eq	LBB187_29
Ltmp9710:
; %bb.45:                               ;   in Loop: Header=BB187_30 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sxth	w11, w11
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9711:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9712:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9713:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_29
Ltmp9714:
LBB187_46:                              ;   in Loop: Header=BB187_47 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp9715:
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp9716:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp9717:
LBB187_47:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_53 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp9718:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x26, x8, x22, lo
Ltmp9719:
	;DEBUG_VALUE: count <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_49
Ltmp9720:
; %bb.48:                               ;   in Loop: Header=BB187_47 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp9721:
LBB187_49:                              ;   in Loop: Header=BB187_47 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x26, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp9722:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_46
Ltmp9723:
; %bb.50:                               ;   in Loop: Header=BB187_47 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #2
	b	LBB187_53
Ltmp9724:
LBB187_51:                              ;   in Loop: Header=BB187_53 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp9725:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	fmov	d1, x23
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fdiv	d0, d0, d1
	fmov	d1, x24
	fadd	d0, d0, d1
Ltmp9726:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9727:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_52:                              ;   in Loop: Header=BB187_53 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x26, x26, #1
Ltmp9728:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_46
Ltmp9729:
LBB187_53:                              ;   Parent Loop BB187_47 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp9730:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_51
Ltmp9731:
; %bb.54:                               ;   in Loop: Header=BB187_53 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp9732:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s0
	ccmp	w10, w25, #0, vc
	b.le	LBB187_51
	b	LBB187_52
Ltmp9733:
LBB187_55:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x21, [x20]
Ltmp9734:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	ldr	w8, [x20, #20]
Ltmp9735:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	ldr	d8, [x28, #8]
Ltmp9736:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #32]
	cbz	x9, LBB187_123
Ltmp9737:
; %bb.56:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1830 65 is_stmt 1             ; numeric-payload.c:1830:65
	ldr	w11, [x28]
Ltmp9738:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	w10, [x20, #24]
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	ldr	x9, [x20, #8]
	cmp	w10, #111
	cbz	w11, LBB187_193
Ltmp9739:
; %bb.57:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.gt	LBB187_275
Ltmp9740:
; %bb.58:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w8, #1
	b.eq	LBB187_622
Ltmp9741:
; %bb.59:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_692
Ltmp9742:
; %bb.60:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp9743:
; %bb.61:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #3
	mov	w23, #65536                     ; =0x10000
	mov	x24, #70368744177664            ; =0x400000000000
	movk	x24, #16527, lsl #48
	mov	x25, #2147483648                ; =0x80000000
	movk	x25, #53239, lsl #32
	movk	x25, #49586, lsl #48
	b	LBB187_63
Ltmp9744:
LBB187_62:                              ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp9745:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp9746:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_943
Ltmp9747:
LBB187_63:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_70 Depth 2
                                        ;     Child Loop BB187_73 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x26
Ltmp9748:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp9749:
	;DEBUG_VALUE: count <- $x27
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_65
Ltmp9750:
; %bb.64:                               ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp9751:
LBB187_65:                              ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp9752:
	;DEBUG_VALUE: i <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x8
	b.hs	LBB187_62
Ltmp9753:
; %bb.66:                               ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ands	x9, x27, #0x7
	b.ne	LBB187_70
Ltmp9754:
LBB187_67:                              ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sub	x9, x27, #1
	cmp	x9, #7
	b.lo	LBB187_62
Ltmp9755:
; %bb.68:                               ;   in Loop: Header=BB187_63 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x22, x10
	b	LBB187_73
Ltmp9756:
LBB187_69:                              ;   in Loop: Header=BB187_70 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #1
Ltmp9757:
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
	b.eq	LBB187_67
Ltmp9758:
LBB187_70:                              ;   Parent Loop BB187_63 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w11, [x21, x10]
Ltmp9759:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_69
Ltmp9760:
; %bb.71:                               ;   in Loop: Header=BB187_70 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9761:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9762:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9763:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_69
Ltmp9764:
LBB187_72:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #8
	subs	x9, x9, #8
Ltmp9765:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.eq	LBB187_62
Ltmp9766:
LBB187_73:                              ;   Parent Loop BB187_63 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldurb	w11, [x10, #-3]
Ltmp9767:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_75
Ltmp9768:
; %bb.74:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9769:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9770:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9771:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_75:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldurb	w11, [x10, #-2]
Ltmp9772:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_77
Ltmp9773:
; %bb.76:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9774:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9775:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9776:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_77:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldurb	w11, [x10, #-1]
Ltmp9777:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_79
Ltmp9778:
; %bb.78:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9779:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9780:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9781:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_79:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrb	w11, [x10]
Ltmp9782:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_81
Ltmp9783:
; %bb.80:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9784:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9785:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9786:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_81:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrb	w11, [x10, #1]
Ltmp9787:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_83
Ltmp9788:
; %bb.82:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9789:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9790:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9791:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_83:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrb	w11, [x10, #2]
Ltmp9792:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_85
Ltmp9793:
; %bb.84:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9794:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9795:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9796:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_85:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrb	w11, [x10, #3]
Ltmp9797:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_87
Ltmp9798:
; %bb.86:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9799:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9800:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9801:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_87:                              ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrb	w11, [x10, #4]
Ltmp9802:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_72
Ltmp9803:
; %bb.88:                               ;   in Loop: Header=BB187_73 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d0, w11
	fmov	d1, x24
Ltmp9804:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp9805:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9806:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_72
Ltmp9807:
LBB187_89:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- undef
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x21, [x20]
Ltmp9808:
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	ldr	w10, [x20, #20]
Ltmp9809:
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	ldr	d8, [x28, #8]
Ltmp9810:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #32]
	cbz	x8, LBB187_127
Ltmp9811:
; %bb.90:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1832 65 is_stmt 1             ; numeric-payload.c:1832:65
	ldr	w11, [x28]
Ltmp9812:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w9, [x20, #24]
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	ldr	x8, [x20, #8]
	cmp	w9, #111
	cbz	w11, LBB187_209
Ltmp9813:
; %bb.91:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.gt	LBB187_306
Ltmp9814:
; %bb.92:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w10, #1
	b.eq	LBB187_630
Ltmp9815:
; %bb.93:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w10, #2
	b.ne	LBB187_700
Ltmp9816:
; %bb.94:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp9817:
; %bb.95:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #16
	mov	w23, #65536                     ; =0x10000
	mov	w24, #2147483647                ; =0x7fffffff
	mov	x25, #70368744177664            ; =0x400000000000
	movk	x25, #16527, lsl #48
	mov	x26, #2147483648                ; =0x80000000
	movk	x26, #53239, lsl #32
	movk	x26, #49586, lsl #48
	b	LBB187_97
Ltmp9818:
LBB187_96:                              ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x27, x9
Ltmp9819:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp9820:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp9821:
LBB187_97:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_104 Depth 2
                                        ;     Child Loop BB187_107 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x27
Ltmp9822:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x28, x9, x23, lo
Ltmp9823:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_99
Ltmp9824:
; %bb.98:                               ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp9825:
LBB187_99:                              ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x28, x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp9826:
	;DEBUG_VALUE: i <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x9
	b.hs	LBB187_96
Ltmp9827:
; %bb.100:                              ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ands	x8, x28, #0x7
	b.ne	LBB187_104
Ltmp9828:
LBB187_101:                             ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sub	x8, x28, #1
	cmp	x8, #7
	b.lo	LBB187_96
Ltmp9829:
; %bb.102:                              ;   in Loop: Header=BB187_97 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x27, x28
	sub	x8, x8, x10
	add	x10, x22, x10, lsl #2
	b	LBB187_107
Ltmp9830:
LBB187_103:                             ;   in Loop: Header=BB187_104 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x10, x10, #1
Ltmp9831:
	;DEBUG_VALUE: i <- $x10
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x8, x8, #1
	b.eq	LBB187_101
Ltmp9832:
LBB187_104:                             ;   Parent Loop BB187_97 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x21, x10, lsl #2]
Ltmp9833:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_103
Ltmp9834:
; %bb.105:                              ;   in Loop: Header=BB187_104 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9835:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9836:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9837:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_103
Ltmp9838:
LBB187_106:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x10, x10, #32
	subs	x8, x8, #8
Ltmp9839:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.eq	LBB187_96
Ltmp9840:
LBB187_107:                             ;   Parent Loop BB187_97 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldur	w11, [x10, #-16]
Ltmp9841:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_109
Ltmp9842:
; %bb.108:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9843:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9844:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9845:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_109:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-12]
Ltmp9846:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_111
Ltmp9847:
; %bb.110:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9848:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9849:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9850:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_111:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-8]
Ltmp9851:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_113
Ltmp9852:
; %bb.112:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9853:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9854:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9855:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_113:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-4]
Ltmp9856:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_115
Ltmp9857:
; %bb.114:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9858:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9859:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9860:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_115:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10]
Ltmp9861:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_117
Ltmp9862:
; %bb.116:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9863:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9864:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9865:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_117:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #4]
Ltmp9866:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_119
Ltmp9867:
; %bb.118:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9868:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9869:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9870:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_119:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #8]
Ltmp9871:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_121
Ltmp9872:
; %bb.120:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9873:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9874:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9875:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_121:                             ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #12]
Ltmp9876:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w24
	b.eq	LBB187_106
Ltmp9877:
; %bb.122:                              ;   in Loop: Header=BB187_107 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp9878:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp9879:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9880:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_106
Ltmp9881:
LBB187_123:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	cmp	w8, #1
	b.eq	LBB187_400
Ltmp9882:
; %bb.124:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_481
Ltmp9883:
; %bb.125:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp9884:
; %bb.126:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #32
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp9885:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #16527, lsl #48
	dup.2d	v16, x8
	mov	w23, #65536                     ; =0x10000
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	dup.2d	v17, x8
	fmov	d10, x8
	stp	q17, q16, [sp, #64]             ; 32-byte Folded Spill
	stp	d10, d9, [sp, #8]               ; 16-byte Folded Spill
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_383
Ltmp9886:
LBB187_127:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x9, [x20, #8]
	cmp	w10, #1
	b.eq	LBB187_421
Ltmp9887:
; %bb.128:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w10, #2
	b.ne	LBB187_501
Ltmp9888:
; %bb.129:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x9, LBB187_1012
Ltmp9889:
; %bb.130:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #32
	mov	x8, #70368744177664             ; =0x400000000000
	movk	x8, #16527, lsl #48
	dup.2d	v24, x8
	mov	w23, #65536                     ; =0x10000
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	dup.2d	v25, x8
	fmov	d10, x8
	stp	q25, q24, [sp, #64]             ; 32-byte Folded Spill
	b	LBB187_132
Ltmp9890:
LBB187_131:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp9891:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, x9
Ltmp9892:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp9893:
LBB187_132:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_140 Depth 2
                                        ;     Child Loop BB187_144 Depth 2
                                        ;     Child Loop BB187_148 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x9, x24
Ltmp9894:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp9895:
	;DEBUG_VALUE: count <- $x25
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_134
Ltmp9896:
; %bb.133:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp9897:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q25, q24, [sp, #64]             ; 32-byte Folded Reload
Ltmp9898:
LBB187_134:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp9899:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x8
	b.hs	LBB187_131
Ltmp9900:
; %bb.135:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_137
Ltmp9901:
; %bb.136:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_147
Ltmp9902:
LBB187_137:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_139
Ltmp9903:
; %bb.138:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_143
Ltmp9904:
LBB187_139:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp9905:
LBB187_140:                             ;   Parent Loop BB187_132 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	sshll2.2d	v4, v0, #0
	scvtf.2d	v4, v4
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	sshll2.2d	v5, v1, #0
	scvtf.2d	v5, v5
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll2.2d	v6, v2, #0
	scvtf.2d	v6, v6
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	sshll2.2d	v7, v3, #0
	scvtf.2d	v7, v7
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fdiv.2d	v0, v0, v24
	fdiv.2d	v4, v4, v24
	fdiv.2d	v1, v1, v24
	fdiv.2d	v5, v5, v24
	fdiv.2d	v2, v2, v24
	fdiv.2d	v6, v6, v24
	fdiv.2d	v3, v3, v24
	fdiv.2d	v7, v7, v24
	fadd.2d	v4, v4, v25
	mov	d16, v4[1]
	fadd.2d	v0, v0, v25
	mov	d17, v0[1]
	fadd.2d	v5, v5, v25
	mov	d18, v5[1]
	fadd.2d	v1, v1, v25
	mov	d19, v1[1]
	fadd.2d	v6, v6, v25
	mov	d20, v6[1]
	fadd.2d	v2, v2, v25
	mov	d21, v2[1]
	fadd.2d	v7, v7, v25
	mov	d22, v7[1]
	fadd.2d	v3, v3, v25
	mov	d23, v3[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d17
	fadd	d0, d0, d4
	fadd	d0, d0, d16
	fadd	d0, d0, d1
	fadd	d0, d0, d19
	fadd	d0, d0, d5
	fadd	d0, d0, d18
	fadd	d0, d0, d2
	fadd	d0, d0, d21
	fadd	d0, d0, d6
	fadd	d0, d0, d20
	fadd	d0, d0, d3
	fadd	d0, d0, d23
	fadd	d0, d0, d7
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_140
Ltmp9906:
; %bb.141:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x9
	b.eq	LBB187_131
Ltmp9907:
; %bb.142:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_146
Ltmp9908:
LBB187_143:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp9909:
LBB187_144:                             ;   Parent Loop BB187_132 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q0, [x9], #16
	sshll2.2d	v1, v0, #0
	scvtf.2d	v1, v1
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fdiv.2d	v0, v0, v24
	fdiv.2d	v1, v1, v24
	fadd.2d	v1, v1, v25
	mov	d2, v1[1]
	fadd.2d	v0, v0, v25
	mov	d3, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d3
	fadd	d0, d0, d1
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_144
Ltmp9910:
; %bb.145:                              ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x11
	b.eq	LBB187_131
	b	LBB187_147
Ltmp9911:
LBB187_146:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp9912:
LBB187_147:                             ;   in Loop: Header=BB187_132 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp9913:
LBB187_148:                             ;   Parent Loop BB187_132 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp9914:
	;DEBUG_VALUE: raw <- $w11
	scvtf	d0, w11
	fdiv	d0, d0, d9
	fadd	d0, d0, d10
Ltmp9915:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9916:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x9, x9, #1
Ltmp9917:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_148
	b	LBB187_131
Ltmp9918:
LBB187_149:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	cmp	w8, #1
	b.eq	LBB187_441
Ltmp9919:
; %bb.150:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_521
Ltmp9920:
; %bb.151:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	cbz	x9, LBB187_1012
Ltmp9921:
; %bb.152:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	mov	x24, #0                         ; =0x0
Ltmp9922:
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #32
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp9923:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	movk	x8, #16527, lsl #48
	dup.2d	v5, x8
	mov	w23, #65536                     ; =0x10000
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	dup.2d	v6, x8
	fmov	d10, x8
	stp	q6, q5, [sp, #64]               ; 32-byte Folded Spill
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_154
Ltmp9924:
LBB187_153:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp9925:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp9926:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp9927:
LBB187_154:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_162 Depth 2
                                        ;     Child Loop BB187_166 Depth 2
                                        ;     Child Loop BB187_170 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x19, x9, x24
Ltmp9928:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp9929:
	;DEBUG_VALUE: count <- $x25
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_156
Ltmp9930:
; %bb.155:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp9931:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q6, q5, [sp, #64]               ; 32-byte Folded Reload
Ltmp9932:
LBB187_156:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp9933:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_153
Ltmp9934:
; %bb.157:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_159
Ltmp9935:
; %bb.158:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_169
Ltmp9936:
LBB187_159:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_161
Ltmp9937:
; %bb.160:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_165
Ltmp9938:
LBB187_161:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x9, x25, #0x1ffe0
	add	x10, x22, x24, lsl #1
	mov	x11, x9
Ltmp9939:
LBB187_162:                             ;   Parent Loop BB187_154 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldp	q2, q0, [x10, #-32]
	sshll2.4s	v1, v2, #0
	sshll.4s	v2, v2, #0
	sshll.2d	v3, v2, #0
	scvtf.2d	v3, v3
	fdiv.2d	v3, v3, v5
	fadd.2d	v3, v3, v6
	fadd	d4, d8, d3
	mov	d3, v3[1]
	fadd	d3, d4, d3
	sshll2.2d	v4, v1, #0
	scvtf.2d	v4, v4
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fdiv.2d	v2, v2, v5
	fadd.2d	v2, v2, v6
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d2, d3, d2
	sshll.4s	v3, v0, #0
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	fadd	d2, d2, d1
	mov	d1, v1[1]
	fadd	d1, d2, d1
	sshll.2d	v2, v3, #0
	scvtf.2d	v2, v2
	fdiv.2d	v4, v4, v5
	fdiv.2d	v2, v2, v5
	fadd.2d	v4, v4, v6
	fadd	d1, d1, d4
	mov	d4, v4[1]
	fadd.2d	v2, v2, v6
	fadd	d1, d1, d4
	mov	d4, v2[1]
	fadd	d1, d1, d2
	fadd	d1, d1, d4
	ldp	q2, q4, [x10], #64
	sshll2.4s	v0, v0, #0
	sshll2.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fdiv.2d	v3, v3, v5
	fadd.2d	v3, v3, v6
	fadd	d1, d1, d3
	mov	d3, v3[1]
	fadd	d1, d1, d3
	sshll2.2d	v3, v0, #0
	scvtf.2d	v3, v3
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fdiv.2d	v0, v0, v5
	fadd.2d	v0, v0, v6
	fadd	d1, d1, d0
	mov	d0, v0[1]
	fadd	d0, d1, d0
	sshll.4s	v1, v2, #0
	fdiv.2d	v3, v3, v5
	fadd.2d	v3, v3, v6
	fadd	d0, d0, d3
	mov	d3, v3[1]
	fadd	d0, d0, d3
	sshll.2d	v3, v1, #0
	scvtf.2d	v3, v3
	fdiv.2d	v3, v3, v5
	fadd.2d	v3, v3, v6
	fadd	d0, d0, d3
	mov	d3, v3[1]
	fadd	d0, d0, d3
	sshll2.4s	v2, v2, #0
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.2d	v1, v2, #0
	scvtf.2d	v1, v1
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fdiv.2d	v2, v2, v5
	fadd.2d	v2, v2, v6
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll.4s	v2, v4, #0
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll.2d	v1, v2, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.4s	v1, v4, #0
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fdiv.2d	v2, v2, v5
	fadd.2d	v2, v2, v6
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll.2d	v2, v1, #0
	scvtf.2d	v2, v2
	fdiv.2d	v2, v2, v5
	fadd.2d	v2, v2, v6
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	subs	x11, x11, #32
	b.ne	LBB187_162
Ltmp9940:
; %bb.163:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x9
	b.eq	LBB187_153
Ltmp9941:
; %bb.164:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x1c
	b.eq	LBB187_168
Ltmp9942:
LBB187_165:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #1
Ltmp9943:
LBB187_166:                             ;   Parent Loop BB187_154 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	d0, [x9], #8
	sshll.4s	v0, v0, #0
	sshll2.2d	v1, v0, #0
	scvtf.2d	v1, v1
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fdiv.2d	v0, v0, v5
	fdiv.2d	v1, v1, v5
	fadd.2d	v1, v1, v6
	mov	d2, v1[1]
	fadd.2d	v0, v0, v6
	mov	d3, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d3
	fadd	d0, d0, d1
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_166
Ltmp9944:
; %bb.167:                              ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x11
	b.eq	LBB187_153
	b	LBB187_169
Ltmp9945:
LBB187_168:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp9946:
LBB187_169:                             ;   in Loop: Header=BB187_154 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #1
Ltmp9947:
LBB187_170:                             ;   Parent Loop BB187_154 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w11, [x10], #2
Ltmp9948:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
	fdiv	d0, d0, d9
	fadd	d0, d0, d10
Ltmp9949:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9950:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
Ltmp9951:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_170
	b	LBB187_153
Ltmp9952:
LBB187_171:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	cmp	w8, #1
	b.eq	LBB187_461
Ltmp9953:
; %bb.172:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_541
Ltmp9954:
; %bb.173:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	cbz	x9, LBB187_1012
Ltmp9955:
; %bb.174:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	mov	x24, #0                         ; =0x0
Ltmp9956:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x22, x21, #32
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp9957:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	movk	x8, #16527, lsl #48
	dup.2d	v24, x8
	mov	w23, #65536                     ; =0x10000
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	dup.2d	v25, x8
	fmov	d10, x8
	stp	q25, q24, [sp, #64]             ; 32-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_176
Ltmp9958:
LBB187_175:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp9959:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp9960:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp9961:
LBB187_176:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_184 Depth 2
                                        ;     Child Loop BB187_188 Depth 2
                                        ;     Child Loop BB187_192 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x24
Ltmp9962:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp9963:
	;DEBUG_VALUE: count <- $x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_178
Ltmp9964:
; %bb.177:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp9965:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q25, q24, [sp, #64]             ; 32-byte Folded Reload
Ltmp9966:
LBB187_178:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp9967:
	;DEBUG_VALUE: i <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x24, x8
	b.hs	LBB187_175
Ltmp9968:
; %bb.179:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_181
Ltmp9969:
; %bb.180:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_191
Ltmp9970:
LBB187_181:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_183
Ltmp9971:
; %bb.182:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_187
Ltmp9972:
LBB187_183:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp9973:
LBB187_184:                             ;   Parent Loop BB187_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	fcvtl2	v4.2d, v0.4s
	fcvtl	v0.2d, v0.2s
	fcvtl2	v5.2d, v1.4s
	fcvtl	v1.2d, v1.2s
	fcvtl2	v6.2d, v2.4s
	fcvtl	v2.2d, v2.2s
	fcvtl2	v7.2d, v3.4s
	fcvtl	v3.2d, v3.2s
	fdiv.2d	v0, v0, v24
	fdiv.2d	v4, v4, v24
	fdiv.2d	v1, v1, v24
	fdiv.2d	v5, v5, v24
	fdiv.2d	v2, v2, v24
	fdiv.2d	v6, v6, v24
	fdiv.2d	v3, v3, v24
	fdiv.2d	v7, v7, v24
	fadd.2d	v4, v4, v25
	mov	d16, v4[1]
	fadd.2d	v0, v0, v25
	mov	d17, v0[1]
	fadd.2d	v5, v5, v25
	mov	d18, v5[1]
	fadd.2d	v1, v1, v25
	mov	d19, v1[1]
	fadd.2d	v6, v6, v25
	mov	d20, v6[1]
	fadd.2d	v2, v2, v25
	mov	d21, v2[1]
	fadd.2d	v7, v7, v25
	mov	d22, v7[1]
	fadd.2d	v3, v3, v25
	mov	d23, v3[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d17
	fadd	d0, d0, d4
	fadd	d0, d0, d16
	fadd	d0, d0, d1
	fadd	d0, d0, d19
	fadd	d0, d0, d5
	fadd	d0, d0, d18
	fadd	d0, d0, d2
	fadd	d0, d0, d21
	fadd	d0, d0, d6
	fadd	d0, d0, d20
	fadd	d0, d0, d3
	fadd	d0, d0, d23
	fadd	d0, d0, d7
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_184
Ltmp9974:
; %bb.185:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x9
	b.eq	LBB187_175
Ltmp9975:
; %bb.186:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_190
Ltmp9976:
LBB187_187:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp9977:
LBB187_188:                             ;   Parent Loop BB187_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q0, [x9], #16
	fcvtl2	v1.2d, v0.4s
	fcvtl	v0.2d, v0.2s
	fdiv.2d	v0, v0, v24
	fdiv.2d	v1, v1, v24
	fadd.2d	v1, v1, v25
	mov	d2, v1[1]
	fadd.2d	v0, v0, v25
	mov	d3, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d3
	fadd	d0, d0, d1
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_188
Ltmp9978:
; %bb.189:                              ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x11
	b.eq	LBB187_175
	b	LBB187_191
Ltmp9979:
LBB187_190:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp9980:
LBB187_191:                             ;   in Loop: Header=BB187_176 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp9981:
LBB187_192:                             ;   Parent Loop BB187_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x10], #4
Ltmp9982:
	;DEBUG_VALUE: raw <- $s0
	fcvt	d0, s0
Ltmp9983:
	fdiv	d0, d0, d9
	fadd	d0, d0, d10
Ltmp9984:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp9985:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp9986:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.ne	LBB187_192
	b	LBB187_175
Ltmp9987:
LBB187_193:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.gt	LBB187_561
Ltmp9988:
; %bb.194:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w8, #1
	b.eq	LBB187_762
Ltmp9989:
; %bb.195:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_895
Ltmp9990:
; %bb.196:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp9991:
; %bb.197:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x25, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #3
	mov	w23, #65536                     ; =0x10000
Lloh1676:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1677:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp9992:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #16527, lsl #48
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	fmov	d10, x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_199
Ltmp9993:
LBB187_198:                             ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x25, x8
Ltmp9994:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp9995:
	;DEBUG_VALUE: start <- $x25
	b.hs	LBB187_943
Ltmp9996:
LBB187_199:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_207 Depth 2
                                        ;     Child Loop BB187_205 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x25
Ltmp9997:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x26, x8, x23, lo
Ltmp9998:
	;DEBUG_VALUE: count <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_201
Ltmp9999:
; %bb.200:                              ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10000:
LBB187_201:                             ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x26, x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10001:
	;DEBUG_VALUE: i <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x8
	b.hs	LBB187_198
Ltmp10002:
; %bb.202:                              ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	mov	x10, x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ands	x9, x26, #0x7
	b.ne	LBB187_207
Ltmp10003:
LBB187_203:                             ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sub	x9, x26, #1
	cmp	x9, #7
	b.lo	LBB187_198
Ltmp10004:
; %bb.204:                              ;   in Loop: Header=BB187_199 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x25, x26
	sub	x9, x9, x10
	add	x10, x22, x10
Ltmp10005:
LBB187_205:                             ;   Parent Loop BB187_199 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldurb	w11, [x10, #-3]
Ltmp10006:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d1, w11
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
	fcsel	d1, d0, d1, eq
Ltmp10007:
	;DEBUG_VALUE: element <- $d1
	fadd	d1, d8, d1
Ltmp10008:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldurb	w11, [x10, #-2]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10009:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10010:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldurb	w11, [x10, #-1]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10011:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10012:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10013:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldrb	w11, [x10]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10014:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10015:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10016:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldrb	w11, [x10, #1]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10017:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10018:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10019:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldrb	w11, [x10, #2]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10020:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10021:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10022:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldrb	w11, [x10, #3]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10023:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10024:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10025:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d1
	ldrb	w11, [x10, #4]
	cmp	w11, #127
	sxtb	w11, w11
	scvtf	d2, w11
Ltmp10026:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10027:
	;DEBUG_VALUE: element <- $d2
	fadd	d8, d1, d2
Ltmp10028:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #8
	subs	x9, x9, #8
Ltmp10029:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_205
	b	LBB187_198
Ltmp10030:
LBB187_206:                             ;   in Loop: Header=BB187_207 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: element <- $d1
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fadd	d8, d8, d1
Ltmp10031:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #1
Ltmp10032:
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
	b.eq	LBB187_203
Ltmp10033:
LBB187_207:                             ;   Parent Loop BB187_199 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w11, [x21, x10]
Ltmp10034:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov.16b	v1, v0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #127
	b.eq	LBB187_206
Ltmp10035:
; %bb.208:                              ;   in Loop: Header=BB187_207 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxtb	w11, w11
	scvtf	d1, w11
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
	b	LBB187_206
Ltmp10036:
LBB187_209:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.gt	LBB187_571
Ltmp10037:
; %bb.210:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w10, #1
	b.eq	LBB187_782
Ltmp10038:
; %bb.211:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w10, #2
	b.ne	LBB187_915
Ltmp10039:
; %bb.212:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp10040:
; %bb.213:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x28, #0                         ; =0x0
Ltmp10041:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x9, x21, #32
	str	x9, [sp, #48]                   ; 8-byte Folded Spill
	mov	w23, #65536                     ; =0x10000
Lloh1678:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1679:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	w25, #2147483647                ; =0x7fffffff
	mov	x26, #70368744177664            ; =0x400000000000
	movk	x26, #16527, lsl #48
	mov	x27, #2147483648                ; =0x80000000
	movk	x27, #53239, lsl #32
	movk	x27, #49586, lsl #48
	mvni.4s	v26, #128, lsl #24
	dup.2d	v27, x26
	dup.2d	v28, x27
	stp	q28, q27, [sp, #64]             ; 32-byte Folded Spill
	b	LBB187_215
Ltmp10042:
LBB187_214:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x28, x9
Ltmp10043:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp10044:
	;DEBUG_VALUE: start <- $x28
	b.hs	LBB187_1012
Ltmp10045:
LBB187_215:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_223 Depth 2
                                        ;     Child Loop BB187_227 Depth 2
                                        ;     Child Loop BB187_232 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x8, x28
Ltmp10046:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x22, x19, x23, lo
Ltmp10047:
	;DEBUG_VALUE: count <- $x22
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_217
Ltmp10048:
; %bb.216:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10049:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q28, q27, [sp, #64]             ; 32-byte Folded Reload
	mvni.4s	v26, #128, lsl #24
Ltmp10050:
LBB187_217:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x22, x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10051:
	;DEBUG_VALUE: i <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x28, x9
	b.hs	LBB187_214
Ltmp10052:
; %bb.218:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #4
	b.hs	LBB187_220
Ltmp10053:
; %bb.219:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_230
Ltmp10054:
LBB187_220:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	cmp	x19, #16
	b.hs	LBB187_222
Ltmp10055:
; %bb.221:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x8, #0                          ; =0x0
	b	LBB187_226
Ltmp10056:
LBB187_222:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x8, x22, #0x1fff0
	dup.2d	v1, v0[0]
	ldr	x10, [sp, #48]                  ; 8-byte Folded Reload
	add	x10, x10, x28, lsl #2
	mov	x11, x8
Ltmp10057:
LBB187_223:                             ;   Parent Loop BB187_215 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp10058:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v6, v2, v26
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmeq.4s	v16, v3, v26
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmeq.4s	v18, v4, v26
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmeq.4s	v20, v5, v26
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp10059:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v22, v2, #0
	scvtf.2d	v22, v22
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	sshll.2d	v23, v3, #0
	scvtf.2d	v23, v23
	sshll2.2d	v3, v3, #0
	scvtf.2d	v3, v3
	sshll.2d	v24, v4, #0
	scvtf.2d	v24, v24
	sshll2.2d	v4, v4, #0
	scvtf.2d	v4, v4
	sshll.2d	v25, v5, #0
	scvtf.2d	v25, v25
	sshll2.2d	v5, v5, #0
	scvtf.2d	v5, v5
	fdiv.2d	v2, v2, v27
	fdiv.2d	v22, v22, v27
	fdiv.2d	v3, v3, v27
	fdiv.2d	v23, v23, v27
	fdiv.2d	v4, v4, v27
	fdiv.2d	v24, v24, v27
	fdiv.2d	v5, v5, v27
	fdiv.2d	v25, v25, v27
	fadd.2d	v22, v22, v28
	fadd.2d	v2, v2, v28
	fadd.2d	v23, v23, v28
	fadd.2d	v3, v3, v28
	fadd.2d	v24, v24, v28
	fadd.2d	v4, v4, v28
	fadd.2d	v25, v25, v28
	fadd.2d	v5, v5, v28
	bit.16b	v2, v1, v6
	mov	d6, v2[1]
	bsl.16b	v7, v1, v22
	mov	d22, v7[1]
	bit.16b	v3, v1, v16
	mov	d16, v3[1]
	bsl.16b	v17, v1, v23
	mov	d23, v17[1]
	bit.16b	v4, v1, v18
	mov	d18, v4[1]
	bsl.16b	v19, v1, v24
	mov	d24, v19[1]
	bit.16b	v5, v1, v20
	mov	d20, v5[1]
	bsl.16b	v21, v1, v25
	mov	d25, v21[1]
	fadd	d7, d8, d7
	fadd	d7, d7, d22
	fadd	d2, d7, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d17
	fadd	d2, d2, d23
	fadd	d2, d2, d3
	fadd	d2, d2, d16
	fadd	d2, d2, d19
	fadd	d2, d2, d24
	fadd	d2, d2, d4
	fadd	d2, d2, d18
	fadd	d2, d2, d21
	fadd	d2, d2, d25
	fadd	d2, d2, d5
	fadd	d8, d2, d20
	subs	x11, x11, #16
	b.ne	LBB187_223
Ltmp10060:
; %bb.224:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x22, x8
	b.eq	LBB187_214
Ltmp10061:
; %bb.225:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	tst	x22, #0xc
	b.eq	LBB187_229
Ltmp10062:
LBB187_226:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x22, #0x1fffc
	add	x10, x28, x11
	dup.2d	v1, v0[0]
	sub	x12, x8, x11
	add	x8, x8, x28
	add	x8, x21, x8, lsl #2
Ltmp10063:
LBB187_227:                             ;   Parent Loop BB187_215 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q2, [x8], #16
Ltmp10064:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v3, v2, v26
	sshll.2d	v4, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp10065:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v5, v2, #0
	scvtf.2d	v5, v5
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fdiv.2d	v2, v2, v27
	fdiv.2d	v5, v5, v27
	fadd.2d	v5, v5, v28
	fadd.2d	v2, v2, v28
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	bsl.16b	v4, v1, v5
	mov	d5, v4[1]
	fadd	d4, d8, d4
	fadd	d4, d4, d5
	fadd	d2, d4, d2
	fadd	d8, d2, d3
	adds	x12, x12, #4
	b.ne	LBB187_227
Ltmp10066:
; %bb.228:                              ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x22, x11
	b.eq	LBB187_214
	b	LBB187_230
Ltmp10067:
LBB187_229:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x28, x8
Ltmp10068:
LBB187_230:                             ;   in Loop: Header=BB187_215 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x28, x22
	sub	x8, x8, x10
	add	x10, x21, x10, lsl #2
	b	LBB187_232
Ltmp10069:
LBB187_231:                             ;   in Loop: Header=BB187_232 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: element <- $d1
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fadd	d8, d8, d1
Ltmp10070:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x8, x8, #1
Ltmp10071:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.eq	LBB187_214
Ltmp10072:
LBB187_232:                             ;   Parent Loop BB187_215 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp10073:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov.16b	v1, v0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w25
	b.eq	LBB187_231
Ltmp10074:
; %bb.233:                              ;   in Loop: Header=BB187_232 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d1, w11
	fmov	d2, x26
	fdiv	d1, d1, d2
	fmov	d2, x27
	fadd	d1, d1, d2
	b	LBB187_231
Ltmp10075:
LBB187_234:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.gt	LBB187_586
Ltmp10076:
; %bb.235:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w8, #1
	b.eq	LBB187_823
Ltmp10077:
; %bb.236:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_952
Ltmp10078:
; %bb.237:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10079:
; %bb.238:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #8
Lloh1680:
	adrp	x23, _R_NaReal@GOTPAGE
Lloh1681:
	ldr	x23, [x23, _R_NaReal@GOTPAGEOFF]
	mov	w24, #65536                     ; =0x10000
	mov	w25, #32767                     ; =0x7fff
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp10080:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #16527, lsl #48
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	fmov	d10, x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_240
Ltmp10081:
LBB187_239:                             ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp10082:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10083:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp10084:
LBB187_240:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_248 Depth 2
                                        ;     Child Loop BB187_246 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x26
Ltmp10085:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x24, lo
Ltmp10086:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_242
Ltmp10087:
; %bb.241:                              ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10088:
LBB187_242:                             ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10089:
	;DEBUG_VALUE: i <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x26, x8
	b.hs	LBB187_239
Ltmp10090:
; %bb.243:                              ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x23]
	mov	x10, x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ands	x9, x27, #0x7
	b.ne	LBB187_248
Ltmp10091:
LBB187_244:                             ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sub	x9, x27, #1
	cmp	x9, #7
	b.lo	LBB187_239
Ltmp10092:
; %bb.245:                              ;   in Loop: Header=BB187_240 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x22, x10, lsl #1
Ltmp10093:
LBB187_246:                             ;   Parent Loop BB187_240 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldurh	w11, [x10, #-8]
Ltmp10094:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d1, w11
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
	fcsel	d1, d0, d1, eq
Ltmp10095:
	;DEBUG_VALUE: element <- $d1
	fadd	d1, d8, d1
Ltmp10096:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldurh	w11, [x10, #-6]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10097:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10098:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldurh	w11, [x10, #-4]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10099:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10100:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10101:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldurh	w11, [x10, #-2]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10102:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10103:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10104:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldrh	w11, [x10]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10105:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10106:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10107:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldrh	w11, [x10, #2]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10108:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10109:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10110:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldrh	w11, [x10, #4]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10111:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10112:
	;DEBUG_VALUE: element <- $d2
	fadd	d1, d1, d2
Ltmp10113:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d1
	ldrh	w11, [x10, #6]
	cmp	w11, w25
	sxth	w11, w11
	scvtf	d2, w11
Ltmp10114:
	fdiv	d2, d2, d9
	fadd	d2, d2, d10
	fcsel	d2, d0, d2, eq
Ltmp10115:
	;DEBUG_VALUE: element <- $d2
	fadd	d8, d1, d2
Ltmp10116:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #16
	subs	x9, x9, #8
Ltmp10117:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_246
	b	LBB187_239
Ltmp10118:
LBB187_247:                             ;   in Loop: Header=BB187_248 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: element <- $d1
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fadd	d8, d8, d1
Ltmp10119:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #1
Ltmp10120:
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
	b.eq	LBB187_244
Ltmp10121:
LBB187_248:                             ;   Parent Loop BB187_240 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w11, [x21, x10, lsl #1]
Ltmp10122:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov.16b	v1, v0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w25
	b.eq	LBB187_247
Ltmp10123:
; %bb.249:                              ;   in Loop: Header=BB187_248 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sxth	w11, w11
	scvtf	d1, w11
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
	b	LBB187_247
Ltmp10124:
LBB187_250:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.gt	LBB187_596
Ltmp10125:
; %bb.251:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w8, #1
	b.eq	LBB187_843
Ltmp10126:
; %bb.252:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_972
Ltmp10127:
; %bb.253:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10128:
; %bb.254:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x28, #0                         ; =0x0
Ltmp10129:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	w22, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x8, x21, #32
Ltmp10130:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	str	x8, [sp, #48]                   ; 8-byte Folded Spill
	mov	w24, #65536                     ; =0x10000
Lloh1682:
	adrp	x25, _R_NaReal@GOTPAGE
Lloh1683:
	ldr	x25, [x25, _R_NaReal@GOTPAGEOFF]
	mov	x26, #70368744177664            ; =0x400000000000
	movk	x26, #16527, lsl #48
	mov	x27, #2147483648                ; =0x80000000
	movk	x27, #53239, lsl #32
	movk	x27, #49586, lsl #48
	mvni.2s	v9, #129, lsl #24
	dup.2d	v26, x26
	dup.2d	v27, x27
	mvni.4s	v28, #129, lsl #24
	stp	q27, q26, [sp, #64]             ; 32-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_256
Ltmp10131:
LBB187_255:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x28, x8
Ltmp10132:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10133:
	;DEBUG_VALUE: start <- $x28
	b.hs	LBB187_1012
Ltmp10134:
LBB187_256:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_264 Depth 2
                                        ;     Child Loop BB187_268 Depth 2
                                        ;     Child Loop BB187_273 Depth 2
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x28
Ltmp10135:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x23, x19, x24, lo
Ltmp10136:
	;DEBUG_VALUE: count <- $x23
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_258
Ltmp10137:
; %bb.257:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10138:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.4s	v28, #129, lsl #24
	ldp	q27, q26, [sp, #64]             ; 32-byte Folded Reload
Ltmp10139:
LBB187_258:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x23, x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10140:
	;DEBUG_VALUE: i <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x28, x8
	b.hs	LBB187_255
Ltmp10141:
; %bb.259:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x25]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #2
	b.hs	LBB187_261
Ltmp10142:
; %bb.260:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_271
Ltmp10143:
LBB187_261:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	cmp	x19, #16
	b.hs	LBB187_263
Ltmp10144:
; %bb.262:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_267
Ltmp10145:
LBB187_263:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x23, #0x1fff0
	dup.2d	v1, v0[0]
	ldr	x10, [sp, #48]                  ; 8-byte Folded Reload
	add	x10, x10, x28, lsl #2
	mov	x11, x9
Ltmp10146:
LBB187_264:                             ;   Parent Loop BB187_256 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp10147:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.4s	v6, v2, v28
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmgt.4s	v16, v3, v28
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmgt.4s	v18, v4, v28
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmgt.4s	v20, v5, v28
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp10148:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v22.2d, v2.2s
	fcvtl2	v2.2d, v2.4s
	fcvtl	v23.2d, v3.2s
	fcvtl2	v3.2d, v3.4s
	fcvtl	v24.2d, v4.2s
	fcvtl2	v4.2d, v4.4s
	fcvtl	v25.2d, v5.2s
	fcvtl2	v5.2d, v5.4s
	fdiv.2d	v2, v2, v26
	fdiv.2d	v22, v22, v26
	fdiv.2d	v3, v3, v26
	fdiv.2d	v23, v23, v26
	fdiv.2d	v4, v4, v26
	fdiv.2d	v24, v24, v26
	fdiv.2d	v5, v5, v26
	fdiv.2d	v25, v25, v26
	fadd.2d	v22, v22, v27
	fadd.2d	v2, v2, v27
	fadd.2d	v23, v23, v27
	fadd.2d	v3, v3, v27
	fadd.2d	v24, v24, v27
	fadd.2d	v4, v4, v27
	fadd.2d	v25, v25, v27
	fadd.2d	v5, v5, v27
	bit.16b	v2, v1, v6
	mov	d6, v2[1]
	bsl.16b	v7, v1, v22
	mov	d22, v7[1]
	bit.16b	v3, v1, v16
	mov	d16, v3[1]
	bsl.16b	v17, v1, v23
	mov	d23, v17[1]
	bit.16b	v4, v1, v18
	mov	d18, v4[1]
	bsl.16b	v19, v1, v24
	mov	d24, v19[1]
	bit.16b	v5, v1, v20
	mov	d20, v5[1]
	bsl.16b	v21, v1, v25
	mov	d25, v21[1]
	fadd	d7, d8, d7
	fadd	d7, d7, d22
	fadd	d2, d7, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d17
	fadd	d2, d2, d23
	fadd	d2, d2, d3
	fadd	d2, d2, d16
	fadd	d2, d2, d19
	fadd	d2, d2, d24
	fadd	d2, d2, d4
	fadd	d2, d2, d18
	fadd	d2, d2, d21
	fadd	d2, d2, d25
	fadd	d2, d2, d5
	fadd	d8, d2, d20
	subs	x11, x11, #16
	b.ne	LBB187_264
Ltmp10149:
; %bb.265:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x23, x9
	b.eq	LBB187_255
Ltmp10150:
; %bb.266:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	tst	x23, #0xe
	b.eq	LBB187_270
Ltmp10151:
LBB187_267:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x23, #0x1fffe
	add	x10, x28, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x28
	add	x9, x21, x9, lsl #2
Ltmp10152:
LBB187_268:                             ;   Parent Loop BB187_256 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	d2, [x9], #8
Ltmp10153:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.2s	v3, v2, v9
	sshll.2d	v3, v3, #0
Ltmp10154:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v2.2d, v2.2s
	fdiv.2d	v2, v2, v26
	fadd.2d	v2, v2, v27
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	fadd	d2, d8, d2
	fadd	d8, d2, d3
	adds	x12, x12, #2
	b.ne	LBB187_268
Ltmp10155:
; %bb.269:                              ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x23, x11
	b.eq	LBB187_255
	b	LBB187_271
Ltmp10156:
LBB187_270:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x28, x9
Ltmp10157:
LBB187_271:                             ;   in Loop: Header=BB187_256 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x28, x23
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
	b	LBB187_273
Ltmp10158:
LBB187_272:                             ;   in Loop: Header=BB187_273 Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: element <- $d1
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d8, d8, d1
Ltmp10159:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp10160:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_255
Ltmp10161:
LBB187_273:                             ;   Parent Loop BB187_256 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s2, [x10], #4
Ltmp10162:
	;DEBUG_VALUE: raw <- $s2
	;DEBUG_VALUE: float_missing_offset:value <- $s2
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w11, s2
Ltmp10163:
	;DEBUG_VALUE: float_missing_offset:bits <- $w11
	;DEBUG_VALUE: missing <- undef
	.loc	0 0 5 is_stmt 0                 ; numeric-payload.c:0:5
	mov.16b	v1, v0
Ltmp10164:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w11, w22
	b.gt	LBB187_272
Ltmp10165:
; %bb.274:                              ;   in Loop: Header=BB187_273 Depth=2
	;DEBUG_VALUE: raw <- $s2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	fcvt	d1, s2
	fmov	d2, x26
Ltmp10166:
	fdiv	d1, d1, d2
	fmov	d2, x27
	fadd	d1, d1, d2
	b	LBB187_272
Ltmp10167:
LBB187_275:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w8, #1
	b.eq	LBB187_638
Ltmp10168:
; %bb.276:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_708
Ltmp10169:
; %bb.277:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10170:
; %bb.278:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #3
	mov	w23, #65536                     ; =0x10000
	mov	x24, #70368744177664            ; =0x400000000000
	movk	x24, #16527, lsl #48
	mov	x25, #2147483648                ; =0x80000000
	movk	x25, #53239, lsl #32
	movk	x25, #49586, lsl #48
	b	LBB187_280
Ltmp10171:
LBB187_279:                             ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp10172:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10173:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_943
Ltmp10174:
LBB187_280:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_287 Depth 2
                                        ;     Child Loop BB187_290 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x26
Ltmp10175:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp10176:
	;DEBUG_VALUE: count <- $x27
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_282
Ltmp10177:
; %bb.281:                              ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10178:
LBB187_282:                             ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10179:
	;DEBUG_VALUE: i <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x8
	b.hs	LBB187_279
Ltmp10180:
; %bb.283:                              ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ands	x9, x27, #0x7
	b.ne	LBB187_287
Ltmp10181:
LBB187_284:                             ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	sub	x9, x27, #1
	cmp	x9, #7
	b.lo	LBB187_279
Ltmp10182:
; %bb.285:                              ;   in Loop: Header=BB187_280 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x22, x10
	b	LBB187_290
Ltmp10183:
LBB187_286:                             ;   in Loop: Header=BB187_287 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #1
Ltmp10184:
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
	b.eq	LBB187_284
Ltmp10185:
LBB187_287:                             ;   Parent Loop BB187_280 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w11, [x21, x10]
Ltmp10186:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_286
Ltmp10187:
; %bb.288:                              ;   in Loop: Header=BB187_287 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10188:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10189:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10190:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_286
Ltmp10191:
LBB187_289:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x10, x10, #8
	subs	x9, x9, #8
Ltmp10192:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.eq	LBB187_279
Ltmp10193:
LBB187_290:                             ;   Parent Loop BB187_280 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldursb	w11, [x10, #-3]
Ltmp10194:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_292
Ltmp10195:
; %bb.291:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10196:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10197:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10198:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_292:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldursb	w11, [x10, #-2]
Ltmp10199:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_294
Ltmp10200:
; %bb.293:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10201:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10202:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10203:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_294:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldursb	w11, [x10, #-1]
Ltmp10204:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_296
Ltmp10205:
; %bb.295:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10206:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10207:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10208:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_296:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsb	w11, [x10]
Ltmp10209:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_298
Ltmp10210:
; %bb.297:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10211:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10212:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10213:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_298:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsb	w11, [x10, #1]
Ltmp10214:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_300
Ltmp10215:
; %bb.299:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10216:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10217:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10218:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_300:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsb	w11, [x10, #2]
Ltmp10219:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_302
Ltmp10220:
; %bb.301:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10221:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10222:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10223:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_302:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsb	w11, [x10, #3]
Ltmp10224:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_304
Ltmp10225:
; %bb.303:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10226:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10227:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10228:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
LBB187_304:                             ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsb	w11, [x10, #4]
Ltmp10229:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w11, #100
	b.gt	LBB187_289
Ltmp10230:
; %bb.305:                              ;   in Loop: Header=BB187_290 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	scvtf	d0, w11
	fmov	d1, x24
Ltmp10231:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10232:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10233:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_289
Ltmp10234:
LBB187_306:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w10, #1
	b.eq	LBB187_646
Ltmp10235:
; %bb.307:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w10, #2
	b.ne	LBB187_716
Ltmp10236:
; %bb.308:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp10237:
; %bb.309:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	mov	w22, #65508                     ; =0xffe4
	movk	w22, #32767, lsl #16
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x23, x21, #16
	mov	w24, #65536                     ; =0x10000
	mov	x25, #70368744177664            ; =0x400000000000
	movk	x25, #16527, lsl #48
	mov	x26, #2147483648                ; =0x80000000
	movk	x26, #53239, lsl #32
	movk	x26, #49586, lsl #48
	b	LBB187_311
Ltmp10238:
LBB187_310:                             ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x27, x9
Ltmp10239:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp10240:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp10241:
LBB187_311:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_318 Depth 2
                                        ;     Child Loop BB187_321 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x27
Ltmp10242:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x28, x9, x24, lo
Ltmp10243:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_313
Ltmp10244:
; %bb.312:                              ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10245:
LBB187_313:                             ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x28, x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10246:
	;DEBUG_VALUE: i <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x9
	b.hs	LBB187_310
Ltmp10247:
; %bb.314:                              ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ands	x8, x28, #0x7
	b.ne	LBB187_318
Ltmp10248:
LBB187_315:                             ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sub	x8, x28, #1
	cmp	x8, #7
	b.lo	LBB187_310
Ltmp10249:
; %bb.316:                              ;   in Loop: Header=BB187_311 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x27, x28
	sub	x8, x8, x10
	add	x10, x23, x10, lsl #2
	b	LBB187_321
Ltmp10250:
LBB187_317:                             ;   in Loop: Header=BB187_318 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x10, x10, #1
Ltmp10251:
	;DEBUG_VALUE: i <- $x10
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x8, x8, #1
	b.eq	LBB187_315
Ltmp10252:
LBB187_318:                             ;   Parent Loop BB187_311 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x21, x10, lsl #2]
Ltmp10253:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_317
Ltmp10254:
; %bb.319:                              ;   in Loop: Header=BB187_318 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10255:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10256:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10257:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_317
Ltmp10258:
LBB187_320:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x10, x10, #32
	subs	x8, x8, #8
Ltmp10259:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.eq	LBB187_310
Ltmp10260:
LBB187_321:                             ;   Parent Loop BB187_311 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldur	w11, [x10, #-16]
Ltmp10261:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_323
Ltmp10262:
; %bb.322:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10263:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10264:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10265:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_323:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-12]
Ltmp10266:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_325
Ltmp10267:
; %bb.324:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10268:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10269:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10270:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_325:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-8]
Ltmp10271:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_327
Ltmp10272:
; %bb.326:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10273:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10274:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10275:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_327:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldur	w11, [x10, #-4]
Ltmp10276:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_329
Ltmp10277:
; %bb.328:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10278:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10279:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10280:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_329:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10]
Ltmp10281:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_331
Ltmp10282:
; %bb.330:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10283:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10284:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10285:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_331:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #4]
Ltmp10286:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_333
Ltmp10287:
; %bb.332:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10288:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10289:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10290:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_333:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #8]
Ltmp10291:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_335
Ltmp10292:
; %bb.334:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10293:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10294:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10295:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
LBB187_335:                             ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldr	w11, [x10, #12]
Ltmp10296:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w22
	b.gt	LBB187_320
Ltmp10297:
; %bb.336:                              ;   in Loop: Header=BB187_321 Depth=2
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10298:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10299:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10300:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_320
Ltmp10301:
LBB187_337:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w8, #1
	b.eq	LBB187_673
Ltmp10302:
; %bb.338:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_743
Ltmp10303:
; %bb.339:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10304:
; %bb.340:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #8
	mov	w23, #65536                     ; =0x10000
	mov	w24, #32740                     ; =0x7fe4
	mov	x25, #70368744177664            ; =0x400000000000
	movk	x25, #16527, lsl #48
	mov	x26, #2147483648                ; =0x80000000
	movk	x26, #53239, lsl #32
	movk	x26, #49586, lsl #48
	b	LBB187_342
Ltmp10305:
LBB187_341:                             ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x27, x8
Ltmp10306:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10307:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp10308:
LBB187_342:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_349 Depth 2
                                        ;     Child Loop BB187_352 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x27
Ltmp10309:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x28, x8, x23, lo
Ltmp10310:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_344
Ltmp10311:
; %bb.343:                              ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10312:
LBB187_344:                             ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x28, x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10313:
	;DEBUG_VALUE: i <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x8
	b.hs	LBB187_341
Ltmp10314:
; %bb.345:                              ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ands	x9, x28, #0x7
	b.ne	LBB187_349
Ltmp10315:
LBB187_346:                             ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	sub	x9, x28, #1
	cmp	x9, #7
	b.lo	LBB187_341
Ltmp10316:
; %bb.347:                              ;   in Loop: Header=BB187_342 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x27, x28
	sub	x9, x9, x10
	add	x10, x22, x10, lsl #1
	b	LBB187_352
Ltmp10317:
LBB187_348:                             ;   in Loop: Header=BB187_349 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #1
Ltmp10318:
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
	b.eq	LBB187_346
Ltmp10319:
LBB187_349:                             ;   Parent Loop BB187_342 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- $x10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w11, [x21, x10, lsl #1]
Ltmp10320:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_348
Ltmp10321:
; %bb.350:                              ;   in Loop: Header=BB187_349 Depth=2
	;DEBUG_VALUE: i <- $x10
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10322:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10323:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10324:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_348
Ltmp10325:
LBB187_351:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x10, x10, #16
	subs	x9, x9, #8
Ltmp10326:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.eq	LBB187_341
Ltmp10327:
LBB187_352:                             ;   Parent Loop BB187_342 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldursh	w11, [x10, #-8]
Ltmp10328:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_354
Ltmp10329:
; %bb.353:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10330:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10331:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10332:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_354:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldursh	w11, [x10, #-6]
Ltmp10333:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_356
Ltmp10334:
; %bb.355:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10335:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10336:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10337:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_356:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldursh	w11, [x10, #-4]
Ltmp10338:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_358
Ltmp10339:
; %bb.357:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10340:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10341:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10342:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_358:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldursh	w11, [x10, #-2]
Ltmp10343:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_360
Ltmp10344:
; %bb.359:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10345:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10346:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10347:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_360:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsh	w11, [x10]
Ltmp10348:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_362
Ltmp10349:
; %bb.361:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10350:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10351:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10352:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_362:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsh	w11, [x10, #2]
Ltmp10353:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_364
Ltmp10354:
; %bb.363:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10355:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10356:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10357:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_364:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsh	w11, [x10, #4]
Ltmp10358:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_366
Ltmp10359:
; %bb.365:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10360:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10361:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10362:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
LBB187_366:                             ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	ldrsh	w11, [x10, #6]
Ltmp10363:
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w11, w24
	b.gt	LBB187_351
Ltmp10364:
; %bb.367:                              ;   in Loop: Header=BB187_352 Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	scvtf	d0, w11
	fmov	d1, x25
Ltmp10365:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d0, d0, d1
	fmov	d1, x26
	fadd	d0, d0, d1
Ltmp10366:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10367:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 0 1                           ; numeric-payload.c:0:1
	b	LBB187_351
Ltmp10368:
LBB187_368:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w8, #1
	b.eq	LBB187_681
Ltmp10369:
; %bb.369:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_751
Ltmp10370:
; %bb.370:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10371:
; %bb.371:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x28, #0                         ; =0x0
Ltmp10372:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	w22, #12287                     ; =0x2fff
	movk	w22, #33023, lsl #16
	mov	w23, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	x24, #70368744177664            ; =0x400000000000
	movk	x24, #16527, lsl #48
	mov	x25, #2147483648                ; =0x80000000
	movk	x25, #53239, lsl #32
	movk	x25, #49586, lsl #48
	mov	w26, #-53249                    ; =0xffff2fff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_373
Ltmp10373:
LBB187_372:                             ;   in Loop: Header=BB187_373 Depth=1
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x28, x8
Ltmp10374:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10375:
	;DEBUG_VALUE: start <- $x28
	b.hs	LBB187_1012
Ltmp10376:
LBB187_373:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_379 Depth 2
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x28
Ltmp10377:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp10378:
	;DEBUG_VALUE: count <- $x27
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_375
Ltmp10379:
; %bb.374:                              ;   in Loop: Header=BB187_373 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10380:
LBB187_375:                             ;   in Loop: Header=BB187_373 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10381:
	;DEBUG_VALUE: i <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x28, x8
	b.hs	LBB187_372
Ltmp10382:
; %bb.376:                              ;   in Loop: Header=BB187_373 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x21, x28, lsl #2
	b	LBB187_379
Ltmp10383:
LBB187_377:                             ;   in Loop: Header=BB187_379 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp10384:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	fmov	d1, x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fdiv	d0, d0, d1
	fmov	d1, x25
	fadd	d0, d0, d1
Ltmp10385:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10386:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_378:                             ;   in Loop: Header=BB187_379 Depth=2
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x27, x27, #1
Ltmp10387:
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_372
Ltmp10388:
LBB187_379:                             ;   Parent Loop BB187_373 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp10389:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_377
Ltmp10390:
; %bb.380:                              ;   in Loop: Header=BB187_379 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp10391:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w11, w10, w22
Ltmp10392:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w10
	.loc	0 0 37 is_stmt 0                ; numeric-payload.c:0:37
	tst	w10, #0x7ff
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ccmp	w11, w26, #0, eq
	cset	w10, lo
Ltmp10393:
	fcmp	s0, s0
	ccmp	w10, #0, #4, vc
	b.ne	LBB187_377
	b	LBB187_378
Ltmp10394:
LBB187_381:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 37                          ; numeric-payload.c:0:37
	ldp	d10, d9, [sp, #8]               ; 16-byte Folded Reload
Ltmp10395:
LBB187_382:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10396:
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10397:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_943
Ltmp10398:
LBB187_383:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_391 Depth 2
                                        ;     Child Loop BB187_395 Depth 2
                                        ;     Child Loop BB187_399 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x19, x9, x24
Ltmp10399:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10400:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_385
Ltmp10401:
; %bb.384:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10402:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q17, q16, [sp, #64]             ; 32-byte Folded Reload
Ltmp10403:
LBB187_385:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10404:
	;DEBUG_VALUE: i <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x24, x8
	b.hs	LBB187_382
Ltmp10405:
; %bb.386:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #8
	b.hs	LBB187_388
Ltmp10406:
; %bb.387:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_398
Ltmp10407:
LBB187_388:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #64
	b.hs	LBB187_390
Ltmp10408:
; %bb.389:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_394
Ltmp10409:
LBB187_390:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x9, x25, #0x1ffc0
	add	x10, x22, x24
	mov	x11, x9
Ltmp10410:
LBB187_391:                             ;   Parent Loop BB187_383 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldp	q2, q3, [x10, #-32]
	ldr	q6, [x10]
	ext.16b	v0, v2, v2, #8
	mov	b1, v0[6]
	mov	b5, v0[4]
	mov	b7, v2[6]
	mov.b	v7[4], v2[7]
	mov.b	v1[4], v0[7]
	mov	b4, v0[2]
	mov	b20, v2[4]
	mov.b	v20[4], v2[5]
	mov.b	v5[4], v0[5]
	stp	q5, q1, [sp, #32]               ; 32-byte Folded Spill
	mov	b17, v0[0]
	mov	b24, v2[2]
	mov.b	v24[4], v2[3]
	mov.b	v4[4], v0[3]
	mov	b1, v2[0]
	mov.b	v1[4], v2[1]
	ext.16b	v5, v3, v3, #8
	mov.b	v17[4], v0[1]
	mov	b2, v5[6]
	mov	b21, v3[6]
	mov.b	v21[4], v3[7]
	mov.b	v2[4], v5[7]
	mov	b16, v5[4]
	mov	b25, v3[4]
	mov.b	v25[4], v3[5]
	mov.b	v16[4], v5[5]
	mov	b22, v5[2]
	mov	b30, v3[2]
	mov.b	v30[4], v3[3]
	mov.b	v22[4], v5[3]
	mov	b26, v5[0]
	mov	b12, v3[0]
	mov.b	v12[4], v3[1]
	mov.b	v26[4], v5[1]
	ldr	q0, [x10, #16]
	ext.16b	v19, v6, v6, #8
	mov	b3, v19[6]
	mov	b5, v19[4]
	mov.b	v3[4], v19[7]
	mov	b18, v19[2]
	mov	b28, v6[6]
	mov.b	v28[4], v6[7]
	mov.b	v5[4], v19[5]
	mov	b27, v19[0]
	mov	b31, v6[4]
	mov.b	v31[4], v6[5]
	mov.b	v18[4], v19[3]
	mov	b13, v6[2]
	mov.b	v13[4], v6[3]
	mov	b15, v6[0]
	mov.b	v27[4], v19[1]
	mov.b	v15[4], v6[1]
	ext.16b	v9, v0, v0, #8
	mov	b6, v9[6]
	mov.b	v6[4], v9[7]
	mov	b19, v9[4]
	mov.b	v19[4], v9[5]
	mov	b23, v9[2]
	mov.b	v23[4], v9[3]
	mov	b29, v9[0]
	mov	b11, v0[6]
	mov.b	v11[4], v0[7]
	mov.b	v29[4], v9[1]
	mov	b14, v0[4]
	mov.b	v14[4], v0[5]
	mov	b9, v0[2]
	mov.b	v9[4], v0[3]
	mov	b10, v0[0]
	mov.b	v10[4], v0[1]
	shl.2s	v0, v1, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	ldr	q1, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v0, v0, v1
	ldr	q1, [sp, #64]                   ; 16-byte Folded Reload
	fadd.2d	v0, v0, v1
	fadd	d1, d8, d0
	mov	d0, v0[1]
	fadd	d0, d1, d0
	shl.2s	v1, v24, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q24, [sp, #80]                  ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v24
	ldr	q24, [sp, #64]                  ; 16-byte Folded Reload
	fadd.2d	v1, v1, v24
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v20, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldp	q20, q24, [sp, #64]             ; 32-byte Folded Reload
	fdiv.2d	v1, v1, v24
	fadd.2d	v1, v1, v20
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v7, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q7, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v7
	ldr	q7, [sp, #64]                   ; 16-byte Folded Reload
	fadd.2d	v1, v1, v7
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v17, #24
	ldp	q17, q7, [sp, #64]              ; 32-byte Folded Reload
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v7
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v4, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	ldr	q1, [sp, #32]                   ; 16-byte Folded Reload
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	ldr	q1, [sp, #48]                   ; 16-byte Folded Reload
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v12, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v30, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v25, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v21, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v26, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v22, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fdiv.2d	v1, v1, v4
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v16, #24
	ldr	q16, [sp, #80]                  ; 16-byte Folded Reload
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v2, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v15, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v13, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v31, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v28, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v27, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v18, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v5, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v3, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v10, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v9, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v14, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v11, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v29, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v23, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v19, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v6, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	add	x10, x10, #64
	subs	x11, x11, #64
	b.ne	LBB187_391
Ltmp10411:
; %bb.392:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x9
	b.eq	LBB187_381
Ltmp10412:
; %bb.393:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x38
	ldp	d10, d9, [sp, #8]               ; 16-byte Folded Reload
	b.eq	LBB187_397
Ltmp10413:
LBB187_394:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x11, x25, #0x1fff8
	add	x10, x24, x11
	add	x12, x9, x24
	add	x12, x21, x12
	sub	x9, x9, x11
Ltmp10414:
LBB187_395:                             ;   Parent Loop BB187_383 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	d0, [x12], #8
	mov	b1, v0[6]
	mov.b	v1[4], v0[7]
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	mov	b2, v0[4]
	mov.b	v2[4], v0[5]
	shl.2s	v2, v2, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov	b3, v0[2]
	mov.b	v3[4], v0[3]
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	mov	b4, v0[0]
	mov.b	v4[4], v0[1]
	shl.2s	v0, v4, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fdiv.2d	v0, v0, v16
	fdiv.2d	v3, v3, v16
	fdiv.2d	v2, v2, v16
	fdiv.2d	v1, v1, v16
	fadd.2d	v1, v1, v17
	mov	d4, v1[1]
	fadd.2d	v2, v2, v17
	mov	d5, v2[1]
	fadd.2d	v3, v3, v17
	mov	d6, v3[1]
	fadd.2d	v0, v0, v17
	mov	d7, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d7
	fadd	d0, d0, d3
	fadd	d0, d0, d6
	fadd	d0, d0, d2
	fadd	d0, d0, d5
	fadd	d0, d0, d1
	fadd	d8, d0, d4
	adds	x9, x9, #8
	b.ne	LBB187_395
Ltmp10415:
; %bb.396:                              ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x11
	b.eq	LBB187_382
	b	LBB187_398
Ltmp10416:
LBB187_397:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10417:
LBB187_398:                             ;   in Loop: Header=BB187_383 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10
Ltmp10418:
LBB187_399:                             ;   Parent Loop BB187_383 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w11, [x10], #1
Ltmp10419:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
	fdiv	d0, d0, d9
	fadd	d0, d0, d10
Ltmp10420:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10421:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
Ltmp10422:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_399
	b	LBB187_382
Ltmp10423:
LBB187_400:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10424:
; %bb.401:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10425:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v16, x8
	fmov	d9, x8
	str	q16, [sp, #80]                  ; 16-byte Folded Spill
	str	d9, [sp, #32]                   ; 8-byte Folded Spill
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_404
Ltmp10426:
LBB187_402:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d9, [sp, #32]                   ; 8-byte Folded Reload
Ltmp10427:
LBB187_403:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10428:
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10429:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_943
Ltmp10430:
LBB187_404:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_412 Depth 2
                                        ;     Child Loop BB187_416 Depth 2
                                        ;     Child Loop BB187_420 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x19, x9, x24
Ltmp10431:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10432:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_406
Ltmp10433:
; %bb.405:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10434:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	q16, [sp, #80]                  ; 16-byte Folded Reload
Ltmp10435:
LBB187_406:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10436:
	;DEBUG_VALUE: i <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x24, x8
	b.hs	LBB187_403
Ltmp10437:
; %bb.407:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #8
	b.hs	LBB187_409
Ltmp10438:
; %bb.408:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_419
Ltmp10439:
LBB187_409:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #64
	b.hs	LBB187_411
Ltmp10440:
; %bb.410:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_415
Ltmp10441:
LBB187_411:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x9, x25, #0x1ffc0
	add	x10, x22, x24
	mov	x11, x9
Ltmp10442:
LBB187_412:                             ;   Parent Loop BB187_404 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldp	q3, q21, [x10, #-32]
	ldp	q0, q27, [x10]
	ext.16b	v6, v3, v3, #8
	mov	b1, v6[0]
	mov	b5, v6[2]
	mov	b2, v6[4]
	mov	b13, v3[0]
	mov.b	v13[4], v3[1]
	mov	b7, v3[2]
	mov.b	v7[4], v3[3]
	mov	b4, v6[6]
	mov	b17, v3[4]
	mov.b	v17[4], v3[5]
	mov.b	v1[4], v6[1]
	mov	b18, v3[6]
	mov.b	v18[4], v3[7]
	ext.16b	v23, v21, v21, #8
	mov.b	v5[4], v6[3]
	stp	q5, q1, [sp, #48]               ; 32-byte Folded Spill
	mov	b3, v23[0]
	mov	b19, v21[0]
	mov.b	v19[4], v21[1]
	mov.b	v2[4], v6[5]
	mov	b5, v23[2]
	mov	b20, v21[2]
	mov.b	v20[4], v21[3]
	mov.b	v4[4], v6[7]
	mov	b6, v23[4]
	mov	b22, v21[4]
	mov.b	v22[4], v21[5]
	mov.b	v3[4], v23[1]
	mov	b16, v23[6]
	mov	b24, v21[6]
	mov.b	v24[4], v21[7]
	mov.b	v5[4], v23[3]
	ext.16b	v9, v0, v0, #8
	mov	b28, v0[0]
	mov.b	v28[4], v0[1]
	mov.b	v6[4], v23[5]
	mov	b21, v9[0]
	mov	b29, v0[2]
	mov.b	v29[4], v0[3]
	mov.b	v16[4], v23[7]
	mov	b23, v9[2]
	mov	b30, v0[4]
	mov.b	v30[4], v0[5]
	mov.b	v21[4], v9[1]
	mov	b25, v9[4]
	mov	b31, v0[6]
	mov.b	v31[4], v0[7]
	mov.b	v23[4], v9[3]
	mov	b26, v9[6]
	mov	b12, v27[0]
	mov.b	v12[4], v27[1]
	mov.b	v25[4], v9[5]
	ext.16b	v0, v27, v27, #8
	mov	b15, v27[2]
	mov.b	v15[4], v27[3]
	mov.b	v26[4], v9[7]
	mov	b10, v0[0]
	mov	b9, v27[4]
	mov.b	v9[4], v27[5]
	mov.b	v10[4], v0[1]
	mov	b1, v27[6]
	mov.b	v1[4], v27[7]
	mov	b14, v0[2]
	mov.b	v14[4], v0[3]
	mov	b11, v0[4]
	mov.b	v11[4], v0[5]
	mov	b27, v0[6]
	mov.b	v27[4], v0[7]
	shl.2s	v0, v13, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	ldr	q13, [sp, #80]                  ; 16-byte Folded Reload
	fadd.2d	v13, v0, v13
	fadd	d0, d8, d13
	mov	d8, v13[1]
	fadd	d0, d0, d8
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	ldr	q8, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v7, v7, v8
	fadd	d0, d0, d7
	mov	d7, v7[1]
	fadd	d0, d0, d7
	shl.2s	v7, v17, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	ldr	q17, [sp, #80]                  ; 16-byte Folded Reload
	fadd.2d	v7, v7, v17
	fadd	d0, d0, d7
	mov	d7, v7[1]
	fadd	d0, d0, d7
	shl.2s	v7, v18, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	ldr	q17, [sp, #80]                  ; 16-byte Folded Reload
	fadd.2d	v7, v7, v17
	fadd	d0, d0, d7
	mov	d7, v7[1]
	fadd	d0, d0, d7
	ldp	q7, q17, [sp, #64]              ; 32-byte Folded Reload
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	fadd.2d	v7, v7, v17
	fadd	d0, d0, d7
	mov	d7, v7[1]
	fadd	d0, d0, d7
	ldr	q7, [sp, #48]                   ; 16-byte Folded Reload
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	ldr	q17, [sp, #80]                  ; 16-byte Folded Reload
	fadd.2d	v7, v7, v17
	fadd	d0, d0, d7
	mov	d7, v7[1]
	fadd	d0, d0, d7
	shl.2s	v2, v2, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q7, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v7
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v4, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v4
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v19, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v4
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v20, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v4
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v22, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v4
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v24, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q4, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v4
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v3, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q3, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v3
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v5, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q3, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v3
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v6, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	ldr	q3, [sp, #80]                   ; 16-byte Folded Reload
	fadd.2d	v2, v2, v3
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v16, #24
	ldr	q16, [sp, #80]                  ; 16-byte Folded Reload
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v28, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v29, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v30, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v31, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v21, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v23, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v25, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v26, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v12, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v15, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v2, v9, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v10, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v14, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v11, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v27, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	add	x10, x10, #64
	subs	x11, x11, #64
	b.ne	LBB187_412
Ltmp10443:
; %bb.413:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x9
	b.eq	LBB187_402
Ltmp10444:
; %bb.414:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x38
	ldr	d9, [sp, #32]                   ; 8-byte Folded Reload
	b.eq	LBB187_418
Ltmp10445:
LBB187_415:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x11, x25, #0x1fff8
	add	x10, x24, x11
	add	x12, x9, x24
	add	x12, x21, x12
	sub	x9, x9, x11
Ltmp10446:
LBB187_416:                             ;   Parent Loop BB187_404 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	d0, [x12], #8
	mov	b1, v0[0]
	mov.b	v1[4], v0[1]
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	mov	b2, v0[2]
	mov.b	v2[4], v0[3]
	scvtf.2d	v1, v1
	shl.2s	v2, v2, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov	b3, v0[4]
	mov.b	v3[4], v0[5]
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	mov	b4, v0[6]
	mov.b	v4[4], v0[7]
	shl.2s	v0, v4, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd.2d	v0, v0, v16
	mov	d4, v0[1]
	fadd.2d	v3, v3, v16
	mov	d5, v3[1]
	fadd.2d	v2, v2, v16
	mov	d6, v2[1]
	fadd.2d	v1, v1, v16
	mov	d7, v1[1]
	fadd	d1, d8, d1
	fadd	d1, d1, d7
	fadd	d1, d1, d2
	fadd	d1, d1, d6
	fadd	d1, d1, d3
	fadd	d1, d1, d5
	fadd	d0, d1, d0
	fadd	d8, d0, d4
	adds	x9, x9, #8
	b.ne	LBB187_416
Ltmp10447:
; %bb.417:                              ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x11
	b.eq	LBB187_403
	b	LBB187_419
Ltmp10448:
LBB187_418:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10449:
LBB187_419:                             ;   in Loop: Header=BB187_404 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10
Ltmp10450:
LBB187_420:                             ;   Parent Loop BB187_404 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w11, [x10], #1
Ltmp10451:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
	fadd	d0, d0, d9
Ltmp10452:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10453:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
Ltmp10454:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_420
	b	LBB187_403
Ltmp10455:
LBB187_421:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x9, LBB187_1012
Ltmp10456:
; %bb.422:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
	movk	x8, #49324, lsl #48
	dup.2d	v24, x8
	fmov	d9, x8
	str	q24, [sp, #80]                  ; 16-byte Folded Spill
	b	LBB187_424
Ltmp10457:
LBB187_423:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10458:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, x9
Ltmp10459:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10460:
LBB187_424:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_432 Depth 2
                                        ;     Child Loop BB187_436 Depth 2
                                        ;     Child Loop BB187_440 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x9, x24
Ltmp10461:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10462:
	;DEBUG_VALUE: count <- $x25
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_426
Ltmp10463:
; %bb.425:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10464:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	q24, [sp, #80]                  ; 16-byte Folded Reload
Ltmp10465:
LBB187_426:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10466:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x8
	b.hs	LBB187_423
Ltmp10467:
; %bb.427:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_429
Ltmp10468:
; %bb.428:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_439
Ltmp10469:
LBB187_429:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_431
Ltmp10470:
; %bb.430:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_435
Ltmp10471:
LBB187_431:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp10472:
LBB187_432:                             ;   Parent Loop BB187_424 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	sshll.2d	v4, v0, #0
	scvtf.2d	v4, v4
	sshll2.2d	v0, v0, #0
	scvtf.2d	v0, v0
	sshll.2d	v5, v1, #0
	scvtf.2d	v5, v5
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll.2d	v6, v2, #0
	scvtf.2d	v6, v6
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	sshll.2d	v7, v3, #0
	scvtf.2d	v7, v7
	sshll2.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd.2d	v0, v0, v24
	mov	d16, v0[1]
	fadd.2d	v4, v4, v24
	mov	d17, v4[1]
	fadd.2d	v1, v1, v24
	mov	d18, v1[1]
	fadd.2d	v5, v5, v24
	mov	d19, v5[1]
	fadd.2d	v2, v2, v24
	mov	d20, v2[1]
	fadd.2d	v6, v6, v24
	mov	d21, v6[1]
	fadd.2d	v3, v3, v24
	mov	d22, v3[1]
	fadd.2d	v7, v7, v24
	mov	d23, v7[1]
	fadd	d4, d8, d4
	fadd	d4, d4, d17
	fadd	d0, d4, d0
	fadd	d0, d0, d16
	fadd	d0, d0, d5
	fadd	d0, d0, d19
	fadd	d0, d0, d1
	fadd	d0, d0, d18
	fadd	d0, d0, d6
	fadd	d0, d0, d21
	fadd	d0, d0, d2
	fadd	d0, d0, d20
	fadd	d0, d0, d7
	fadd	d0, d0, d23
	fadd	d0, d0, d3
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_432
Ltmp10473:
; %bb.433:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x9
	b.eq	LBB187_423
Ltmp10474:
; %bb.434:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_438
Ltmp10475:
LBB187_435:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp10476:
LBB187_436:                             ;   Parent Loop BB187_424 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q0, [x9], #16
	sshll.2d	v1, v0, #0
	scvtf.2d	v1, v1
	sshll2.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd.2d	v0, v0, v24
	mov	d2, v0[1]
	fadd.2d	v1, v1, v24
	mov	d3, v1[1]
	fadd	d1, d8, d1
	fadd	d1, d1, d3
	fadd	d0, d1, d0
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_436
Ltmp10477:
; %bb.437:                              ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x11
	b.eq	LBB187_423
	b	LBB187_439
Ltmp10478:
LBB187_438:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10479:
LBB187_439:                             ;   in Loop: Header=BB187_424 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp10480:
LBB187_440:                             ;   Parent Loop BB187_424 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp10481:
	;DEBUG_VALUE: raw <- $w11
	scvtf	d0, w11
	fadd	d0, d0, d9
Ltmp10482:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10483:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x9, x9, #1
Ltmp10484:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_440
	b	LBB187_423
Ltmp10485:
LBB187_441:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10486:
; %bb.442:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10487:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v16, x8
	fmov	d9, x8
	str	q16, [sp, #80]                  ; 16-byte Folded Spill
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_444
Ltmp10488:
LBB187_443:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10489:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10490:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10491:
LBB187_444:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_452 Depth 2
                                        ;     Child Loop BB187_456 Depth 2
                                        ;     Child Loop BB187_460 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x19, x9, x24
Ltmp10492:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10493:
	;DEBUG_VALUE: count <- $x25
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_446
Ltmp10494:
; %bb.445:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10495:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	q16, [sp, #80]                  ; 16-byte Folded Reload
Ltmp10496:
LBB187_446:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10497:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_443
Ltmp10498:
; %bb.447:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #8
	b.hs	LBB187_449
Ltmp10499:
; %bb.448:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_459
Ltmp10500:
LBB187_449:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_451
Ltmp10501:
; %bb.450:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_455
Ltmp10502:
LBB187_451:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x9, x25, #0x1ffe0
	add	x10, x22, x24, lsl #1
	mov	x11, x9
Ltmp10503:
LBB187_452:                             ;   Parent Loop BB187_444 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldp	q2, q0, [x10, #-32]
	sshll.4s	v1, v2, #0
	sshll.2d	v3, v1, #0
	scvtf.2d	v3, v3
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll2.4s	v2, v2, #0
	fadd.2d	v3, v3, v16
	fadd	d4, d8, d3
	mov	d3, v3[1]
	fadd	d3, d4, d3
	sshll.2d	v4, v2, #0
	scvtf.2d	v4, v4
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v1, v1, v16
	fadd	d3, d3, d1
	mov	d1, v1[1]
	fadd	d1, d3, d1
	sshll.4s	v3, v0, #0
	fadd.2d	v4, v4, v16
	fadd	d1, d1, d4
	mov	d4, v4[1]
	fadd	d1, d1, d4
	sshll.2d	v4, v3, #0
	scvtf.2d	v4, v4
	fadd.2d	v2, v2, v16
	fadd	d1, d1, d2
	mov	d2, v2[1]
	fadd.2d	v4, v4, v16
	fadd	d1, d1, d2
	mov	d2, v4[1]
	fadd	d1, d1, d4
	fadd	d1, d1, d2
	ldp	q2, q4, [x10], #64
	sshll2.2d	v3, v3, #0
	scvtf.2d	v3, v3
	sshll2.4s	v0, v0, #0
	fadd.2d	v3, v3, v16
	fadd	d1, d1, d3
	mov	d3, v3[1]
	fadd	d1, d1, d3
	sshll.2d	v3, v0, #0
	scvtf.2d	v3, v3
	sshll2.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd.2d	v3, v3, v16
	fadd	d1, d1, d3
	mov	d3, v3[1]
	fadd	d1, d1, d3
	sshll.4s	v3, v2, #0
	fadd.2d	v0, v0, v16
	fadd	d1, d1, d0
	mov	d0, v0[1]
	fadd	d0, d1, d0
	sshll.2d	v1, v3, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.2d	v1, v3, #0
	scvtf.2d	v1, v1
	sshll2.4s	v2, v2, #0
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll.2d	v1, v2, #0
	scvtf.2d	v1, v1
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll.4s	v1, v4, #0
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll.2d	v2, v1, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v16
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll2.4s	v2, v4, #0
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll.2d	v1, v2, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.2d	v1, v2, #0
	scvtf.2d	v1, v1
	fadd.2d	v1, v1, v16
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	subs	x11, x11, #32
	b.ne	LBB187_452
Ltmp10504:
; %bb.453:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x9
	b.eq	LBB187_443
Ltmp10505:
; %bb.454:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x18
	b.eq	LBB187_458
Ltmp10506:
LBB187_455:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x11, x25, #0x1fff8
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #1
Ltmp10507:
LBB187_456:                             ;   Parent Loop BB187_444 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	q0, [x9], #16
	sshll.4s	v1, v0, #0
	sshll.2d	v2, v1, #0
	scvtf.2d	v2, v2
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	sshll2.4s	v0, v0, #0
	sshll.2d	v3, v0, #0
	scvtf.2d	v3, v3
	sshll2.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd.2d	v0, v0, v16
	mov	d4, v0[1]
	fadd.2d	v3, v3, v16
	mov	d5, v3[1]
	fadd.2d	v1, v1, v16
	mov	d6, v1[1]
	fadd.2d	v2, v2, v16
	mov	d7, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d7
	fadd	d1, d2, d1
	fadd	d1, d1, d6
	fadd	d1, d1, d3
	fadd	d1, d1, d5
	fadd	d0, d1, d0
	fadd	d8, d0, d4
	adds	x12, x12, #8
	b.ne	LBB187_456
Ltmp10508:
; %bb.457:                              ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x11
	b.eq	LBB187_443
	b	LBB187_459
Ltmp10509:
LBB187_458:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10510:
LBB187_459:                             ;   in Loop: Header=BB187_444 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #1
Ltmp10511:
LBB187_460:                             ;   Parent Loop BB187_444 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w11, [x10], #2
Ltmp10512:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
	fadd	d0, d0, d9
Ltmp10513:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10514:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
Ltmp10515:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_460
	b	LBB187_443
Ltmp10516:
LBB187_461:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10517:
; %bb.462:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10518:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v24, x8
	fmov	d9, x8
	str	q24, [sp, #80]                  ; 16-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_464
Ltmp10519:
LBB187_463:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10520:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10521:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10522:
LBB187_464:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_472 Depth 2
                                        ;     Child Loop BB187_476 Depth 2
                                        ;     Child Loop BB187_480 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x24
Ltmp10523:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10524:
	;DEBUG_VALUE: count <- $x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_466
Ltmp10525:
; %bb.465:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10526:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	q24, [sp, #80]                  ; 16-byte Folded Reload
Ltmp10527:
LBB187_466:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10528:
	;DEBUG_VALUE: i <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x24, x8
	b.hs	LBB187_463
Ltmp10529:
; %bb.467:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_469
Ltmp10530:
; %bb.468:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_479
Ltmp10531:
LBB187_469:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_471
Ltmp10532:
; %bb.470:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_475
Ltmp10533:
LBB187_471:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp10534:
LBB187_472:                             ;   Parent Loop BB187_464 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	fcvtl	v4.2d, v0.2s
	fcvtl2	v0.2d, v0.4s
	fcvtl	v5.2d, v1.2s
	fcvtl2	v1.2d, v1.4s
	fcvtl	v6.2d, v2.2s
	fcvtl2	v2.2d, v2.4s
	fcvtl	v7.2d, v3.2s
	fcvtl2	v3.2d, v3.4s
	fadd.2d	v0, v0, v24
	mov	d16, v0[1]
	fadd.2d	v4, v4, v24
	mov	d17, v4[1]
	fadd.2d	v1, v1, v24
	mov	d18, v1[1]
	fadd.2d	v5, v5, v24
	mov	d19, v5[1]
	fadd.2d	v2, v2, v24
	mov	d20, v2[1]
	fadd.2d	v6, v6, v24
	mov	d21, v6[1]
	fadd.2d	v3, v3, v24
	mov	d22, v3[1]
	fadd.2d	v7, v7, v24
	mov	d23, v7[1]
	fadd	d4, d8, d4
	fadd	d4, d4, d17
	fadd	d0, d4, d0
	fadd	d0, d0, d16
	fadd	d0, d0, d5
	fadd	d0, d0, d19
	fadd	d0, d0, d1
	fadd	d0, d0, d18
	fadd	d0, d0, d6
	fadd	d0, d0, d21
	fadd	d0, d0, d2
	fadd	d0, d0, d20
	fadd	d0, d0, d7
	fadd	d0, d0, d23
	fadd	d0, d0, d3
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_472
Ltmp10535:
; %bb.473:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x9
	b.eq	LBB187_463
Ltmp10536:
; %bb.474:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_478
Ltmp10537:
LBB187_475:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp10538:
LBB187_476:                             ;   Parent Loop BB187_464 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q0, [x9], #16
	fcvtl	v1.2d, v0.2s
	fcvtl2	v0.2d, v0.4s
	fadd.2d	v0, v0, v24
	mov	d2, v0[1]
	fadd.2d	v1, v1, v24
	mov	d3, v1[1]
	fadd	d1, d8, d1
	fadd	d1, d1, d3
	fadd	d0, d1, d0
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_476
Ltmp10539:
; %bb.477:                              ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x11
	b.eq	LBB187_463
	b	LBB187_479
Ltmp10540:
LBB187_478:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10541:
LBB187_479:                             ;   in Loop: Header=BB187_464 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp10542:
LBB187_480:                             ;   Parent Loop BB187_464 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x10], #4
Ltmp10543:
	;DEBUG_VALUE: raw <- $s0
	fcvt	d0, s0
Ltmp10544:
	fadd	d0, d0, d9
Ltmp10545:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10546:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp10547:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.ne	LBB187_480
	b	LBB187_463
Ltmp10548:
LBB187_481:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10549:
; %bb.482:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	b	LBB187_484
Ltmp10550:
LBB187_483:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10551:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10552:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_943
Ltmp10553:
LBB187_484:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_492 Depth 2
                                        ;     Child Loop BB187_496 Depth 2
                                        ;     Child Loop BB187_500 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x19, x9, x24
Ltmp10554:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10555:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_486
Ltmp10556:
; %bb.485:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10557:
LBB187_486:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10558:
	;DEBUG_VALUE: i <- $x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x24, x8
	b.hs	LBB187_483
Ltmp10559:
; %bb.487:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_489
Ltmp10560:
; %bb.488:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_499
Ltmp10561:
LBB187_489:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #64
	b.hs	LBB187_491
Ltmp10562:
; %bb.490:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_495
Ltmp10563:
LBB187_491:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x9, x25, #0x1ffc0
	add	x10, x22, x24
	mov	x11, x9
Ltmp10564:
LBB187_492:                             ;   Parent Loop BB187_484 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldp	q1, q17, [x10, #-32]
	ldp	q24, q3, [x10]
	ext.16b	v0, v1, v1, #8
	mov	b4, v0[6]
	mov	b5, v0[4]
	mov	b2, v0[2]
	mov	b7, v1[6]
	mov.b	v7[4], v1[7]
	mov.b	v4[4], v0[7]
	mov	b6, v0[0]
	mov	b16, v1[4]
	mov.b	v16[4], v1[5]
	mov.b	v5[4], v0[5]
	stp	q5, q4, [sp, #64]               ; 32-byte Folded Spill
	mov	b18, v1[2]
	mov.b	v18[4], v1[3]
	mov	b21, v1[0]
	mov.b	v2[4], v0[3]
	mov.b	v21[4], v1[1]
	ext.16b	v1, v17, v17, #8
	mov	b4, v1[6]
	mov.b	v6[4], v0[1]
	mov	b5, v1[4]
	mov	b20, v17[6]
	mov.b	v20[4], v17[7]
	mov.b	v4[4], v1[7]
	mov	b19, v1[2]
	mov	b23, v17[4]
	mov.b	v23[4], v17[5]
	mov.b	v5[4], v1[5]
	mov	b22, v1[0]
	mov	b26, v17[2]
	mov.b	v26[4], v17[3]
	mov.b	v19[4], v1[3]
	mov	b30, v17[0]
	mov.b	v30[4], v17[1]
	ext.16b	v0, v24, v24, #8
	mov.b	v22[4], v1[1]
	mov	b17, v0[6]
	mov	b28, v24[6]
	mov.b	v28[4], v24[7]
	mov.b	v17[4], v0[7]
	mov	b25, v0[4]
	mov	b9, v24[4]
	mov.b	v9[4], v24[5]
	mov.b	v25[4], v0[5]
	mov	b29, v0[2]
	mov	b12, v24[2]
	mov.b	v12[4], v24[3]
	mov.b	v29[4], v0[3]
	mov	b10, v0[0]
	mov	b14, v24[0]
	mov.b	v14[4], v24[1]
	mov.b	v10[4], v0[1]
	ext.16b	v0, v3, v3, #8
	mov	b24, v0[6]
	mov	b27, v0[4]
	mov.b	v24[4], v0[7]
	mov.b	v27[4], v0[5]
	mov	b31, v0[2]
	mov	b11, v0[0]
	mov.b	v31[4], v0[3]
	mov.b	v11[4], v0[1]
	mov	b13, v3[6]
	mov	b15, v3[4]
	mov.b	v13[4], v3[7]
	mov.b	v15[4], v3[5]
	mov	b1, v3[2]
	mov.b	v1[4], v3[3]
	mov	b0, v3[0]
	mov.b	v0[4], v3[1]
	shl.2s	v3, v21, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d21, d8, d3
	mov	d3, v3[1]
	fadd	d3, d21, d3
	shl.2s	v18, v18, #24
	sshr.2s	v18, v18, #24
	sshll.2d	v18, v18, #0
	scvtf.2d	v18, v18
	fadd	d3, d3, d18
	mov	d18, v18[1]
	fadd	d3, d3, d18
	shl.2s	v16, v16, #24
	sshr.2s	v16, v16, #24
	sshll.2d	v16, v16, #0
	scvtf.2d	v16, v16
	fadd	d3, d3, d16
	mov	d16, v16[1]
	fadd	d3, d3, d16
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	fadd	d3, d3, d7
	mov	d7, v7[1]
	fadd	d3, d3, d7
	shl.2s	v6, v6, #24
	sshr.2s	v6, v6, #24
	sshll.2d	v6, v6, #0
	scvtf.2d	v6, v6
	fadd	d3, d3, d6
	mov	d6, v6[1]
	fadd	d3, d3, d6
	shl.2s	v2, v2, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d2, d3, d2
	ldr	q3, [sp, #64]                   ; 16-byte Folded Reload
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	ldr	q3, [sp, #80]                   ; 16-byte Folded Reload
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v30, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v26, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v23, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v20, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v22, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v19, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v5, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v4, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v14, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v12, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v9, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v28, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v10, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v29, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v25, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v3, v17, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	fadd	d2, d2, d3
	mov	d3, v3[1]
	fadd	d2, d2, d3
	shl.2s	v0, v0, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd	d2, d2, d0
	mov	d0, v0[1]
	fadd	d0, d2, d0
	shl.2s	v1, v1, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v15, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v13, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v11, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v31, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v27, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	shl.2s	v1, v24, #24
	sshr.2s	v1, v1, #24
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	add	x10, x10, #64
	subs	x11, x11, #64
	b.ne	LBB187_492
Ltmp10565:
; %bb.493:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x9
	b.eq	LBB187_483
Ltmp10566:
; %bb.494:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x30
	b.eq	LBB187_498
Ltmp10567:
LBB187_495:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x11, x25, #0x1fff0
	add	x10, x24, x11
	add	x12, x9, x24
	add	x12, x21, x12
	sub	x9, x9, x11
Ltmp10568:
LBB187_496:                             ;   Parent Loop BB187_484 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	q2, [x12], #16
	ext.16b	v7, v2, v2, #8
	mov	b0, v7[6]
	mov.b	v0[4], v7[7]
	shl.2s	v0, v0, #24
	sshr.2s	v0, v0, #24
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	mov	d1, v0[1]
	mov	b3, v7[4]
	mov.b	v3[4], v7[5]
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	mov	d4, v3[1]
	mov	b5, v7[2]
	mov.b	v5[4], v7[3]
	shl.2s	v5, v5, #24
	sshr.2s	v5, v5, #24
	sshll.2d	v5, v5, #0
	scvtf.2d	v5, v5
	mov	d6, v5[1]
	mov	b16, v7[0]
	mov.b	v16[4], v7[1]
	shl.2s	v7, v16, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	mov	d16, v7[1]
	mov	b17, v2[6]
	mov.b	v17[4], v2[7]
	shl.2s	v17, v17, #24
	sshr.2s	v17, v17, #24
	sshll.2d	v17, v17, #0
	scvtf.2d	v17, v17
	mov	d18, v17[1]
	mov	b19, v2[4]
	mov.b	v19[4], v2[5]
	shl.2s	v19, v19, #24
	sshr.2s	v19, v19, #24
	sshll.2d	v19, v19, #0
	scvtf.2d	v19, v19
	mov	d20, v19[1]
	mov	b21, v2[2]
	mov.b	v21[4], v2[3]
	shl.2s	v21, v21, #24
	sshr.2s	v21, v21, #24
	sshll.2d	v21, v21, #0
	scvtf.2d	v21, v21
	mov	d22, v21[1]
	mov	b23, v2[0]
	mov.b	v23[4], v2[1]
	shl.2s	v2, v23, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov	d23, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d23
	fadd	d2, d2, d21
	fadd	d2, d2, d22
	fadd	d2, d2, d19
	fadd	d2, d2, d20
	fadd	d2, d2, d17
	fadd	d2, d2, d18
	fadd	d2, d2, d7
	fadd	d2, d2, d16
	fadd	d2, d2, d5
	fadd	d2, d2, d6
	fadd	d2, d2, d3
	fadd	d2, d2, d4
	fadd	d0, d2, d0
	fadd	d8, d0, d1
	adds	x9, x9, #16
	b.ne	LBB187_496
Ltmp10569:
; %bb.497:                              ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x11
	b.eq	LBB187_483
	b	LBB187_499
Ltmp10570:
LBB187_498:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10571:
LBB187_499:                             ;   in Loop: Header=BB187_484 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10
Ltmp10572:
LBB187_500:                             ;   Parent Loop BB187_484 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w11, [x10], #1
Ltmp10573:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
Ltmp10574:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10575:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
Ltmp10576:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_500
	b	LBB187_483
Ltmp10577:
LBB187_501:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x9, LBB187_1012
Ltmp10578:
; %bb.502:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	b	LBB187_504
Ltmp10579:
LBB187_503:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10580:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, x9
Ltmp10581:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10582:
LBB187_504:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_512 Depth 2
                                        ;     Child Loop BB187_516 Depth 2
                                        ;     Child Loop BB187_520 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x9, x24
Ltmp10583:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10584:
	;DEBUG_VALUE: count <- $x25
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_506
Ltmp10585:
; %bb.505:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10586:
LBB187_506:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10587:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x8
	b.hs	LBB187_503
Ltmp10588:
; %bb.507:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_509
Ltmp10589:
; %bb.508:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_519
Ltmp10590:
LBB187_509:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_511
Ltmp10591:
; %bb.510:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_515
Ltmp10592:
LBB187_511:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp10593:
LBB187_512:                             ;   Parent Loop BB187_504 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	sshll2.2d	v4, v0, #0
	scvtf.2d	v4, v4
	mov	d5, v4[1]
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	mov	d6, v0[1]
	sshll2.2d	v7, v1, #0
	scvtf.2d	v7, v7
	mov	d16, v7[1]
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	mov	d17, v1[1]
	sshll2.2d	v18, v2, #0
	scvtf.2d	v18, v18
	mov	d19, v18[1]
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov	d20, v2[1]
	sshll2.2d	v21, v3, #0
	scvtf.2d	v21, v21
	mov	d22, v21[1]
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	mov	d23, v3[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d6
	fadd	d0, d0, d4
	fadd	d0, d0, d5
	fadd	d0, d0, d1
	fadd	d0, d0, d17
	fadd	d0, d0, d7
	fadd	d0, d0, d16
	fadd	d0, d0, d2
	fadd	d0, d0, d20
	fadd	d0, d0, d18
	fadd	d0, d0, d19
	fadd	d0, d0, d3
	fadd	d0, d0, d23
	fadd	d0, d0, d21
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_512
Ltmp10594:
; %bb.513:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x9
	b.eq	LBB187_503
Ltmp10595:
; %bb.514:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_518
Ltmp10596:
LBB187_515:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp10597:
LBB187_516:                             ;   Parent Loop BB187_504 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q0, [x9], #16
	sshll2.2d	v1, v0, #0
	scvtf.2d	v1, v1
	mov	d2, v1[1]
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	mov	d3, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d3
	fadd	d0, d0, d1
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_516
Ltmp10598:
; %bb.517:                              ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x25, x11
	b.eq	LBB187_503
	b	LBB187_519
Ltmp10599:
LBB187_518:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10600:
LBB187_519:                             ;   in Loop: Header=BB187_504 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp10601:
LBB187_520:                             ;   Parent Loop BB187_504 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp10602:
	;DEBUG_VALUE: raw <- $w11
	scvtf	d0, w11
Ltmp10603:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10604:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x9, x9, #1
Ltmp10605:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_520
	b	LBB187_503
Ltmp10606:
LBB187_521:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10607:
; %bb.522:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	b	LBB187_524
Ltmp10608:
LBB187_523:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10609:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10610:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10611:
LBB187_524:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_532 Depth 2
                                        ;     Child Loop BB187_536 Depth 2
                                        ;     Child Loop BB187_540 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x19, x9, x24
Ltmp10612:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10613:
	;DEBUG_VALUE: count <- $x25
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_526
Ltmp10614:
; %bb.525:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10615:
LBB187_526:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10616:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_523
Ltmp10617:
; %bb.527:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #8
	b.hs	LBB187_529
Ltmp10618:
; %bb.528:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_539
Ltmp10619:
LBB187_529:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_531
Ltmp10620:
; %bb.530:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_535
Ltmp10621:
LBB187_531:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x9, x25, #0x1ffe0
	add	x10, x22, x24, lsl #1
	mov	x11, x9
Ltmp10622:
LBB187_532:                             ;   Parent Loop BB187_524 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldp	q2, q0, [x10, #-32]
	sshll2.4s	v1, v2, #0
	sshll.4s	v2, v2, #0
	sshll.2d	v3, v2, #0
	scvtf.2d	v3, v3
	fadd	d4, d8, d3
	mov	d3, v3[1]
	fadd	d3, d4, d3
	sshll2.2d	v4, v1, #0
	scvtf.2d	v4, v4
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d2, d3, d2
	mov	d3, v4[1]
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d2, d2, d1
	mov	d1, v1[1]
	fadd	d1, d2, d1
	sshll.4s	v2, v0, #0
	fadd	d1, d1, d4
	sshll.2d	v4, v2, #0
	scvtf.2d	v4, v4
	fadd	d1, d1, d3
	mov	d3, v4[1]
	fadd	d1, d1, d4
	fadd	d1, d1, d3
	ldp	q3, q4, [x10], #64
	sshll2.4s	v0, v0, #0
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd	d1, d1, d2
	mov	d2, v2[1]
	fadd	d1, d1, d2
	sshll2.2d	v2, v0, #0
	scvtf.2d	v2, v2
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	fadd	d1, d1, d0
	mov	d0, v0[1]
	fadd	d0, d1, d0
	mov	d1, v2[1]
	fadd	d0, d0, d2
	sshll.4s	v2, v3, #0
	fadd	d0, d0, d1
	sshll.2d	v1, v2, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.4s	v1, v3, #0
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll2.2d	v2, v1, #0
	scvtf.2d	v2, v2
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	mov	d1, v2[1]
	fadd	d0, d0, d2
	sshll.4s	v2, v4, #0
	fadd	d0, d0, d1
	sshll.2d	v1, v2, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d0, d0, d1
	sshll2.4s	v1, v4, #0
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll.2d	v2, v1, #0
	scvtf.2d	v2, v2
	fadd	d0, d0, d2
	mov	d2, v2[1]
	fadd	d0, d0, d2
	sshll2.2d	v1, v1, #0
	scvtf.2d	v1, v1
	fadd	d0, d0, d1
	mov	d1, v1[1]
	fadd	d8, d0, d1
	subs	x11, x11, #32
	b.ne	LBB187_532
Ltmp10623:
; %bb.533:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x9
	b.eq	LBB187_523
Ltmp10624:
; %bb.534:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0x18
	b.eq	LBB187_538
Ltmp10625:
LBB187_535:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x11, x25, #0x1fff8
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #1
Ltmp10626:
LBB187_536:                             ;   Parent Loop BB187_524 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	q0, [x9], #16
	sshll2.4s	v1, v0, #0
	sshll2.2d	v2, v1, #0
	scvtf.2d	v2, v2
	mov	d3, v2[1]
	sshll.2d	v1, v1, #0
	scvtf.2d	v1, v1
	mov	d4, v1[1]
	sshll.4s	v0, v0, #0
	sshll2.2d	v5, v0, #0
	scvtf.2d	v5, v5
	mov	d6, v5[1]
	sshll.2d	v0, v0, #0
	scvtf.2d	v0, v0
	mov	d7, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d7
	fadd	d0, d0, d5
	fadd	d0, d0, d6
	fadd	d0, d0, d1
	fadd	d0, d0, d4
	fadd	d0, d0, d2
	fadd	d8, d0, d3
	adds	x12, x12, #8
	b.ne	LBB187_536
Ltmp10627:
; %bb.537:                              ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x25, x11
	b.eq	LBB187_523
	b	LBB187_539
Ltmp10628:
LBB187_538:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10629:
LBB187_539:                             ;   in Loop: Header=BB187_524 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #1
Ltmp10630:
LBB187_540:                             ;   Parent Loop BB187_524 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w11, [x10], #2
Ltmp10631:
	;DEBUG_VALUE: raw <- undef
	scvtf	d0, w11
Ltmp10632:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10633:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
Ltmp10634:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_540
	b	LBB187_523
Ltmp10635:
LBB187_541:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10636:
; %bb.542:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
	b	LBB187_544
Ltmp10637:
LBB187_543:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10638:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10639:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10640:
LBB187_544:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_552 Depth 2
                                        ;     Child Loop BB187_556 Depth 2
                                        ;     Child Loop BB187_560 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x24
Ltmp10641:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x25, x19, x23, lo
Ltmp10642:
	;DEBUG_VALUE: count <- $x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_546
Ltmp10643:
; %bb.545:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10644:
LBB187_546:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10645:
	;DEBUG_VALUE: i <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x24, x8
	b.hs	LBB187_543
Ltmp10646:
; %bb.547:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #4
	b.hs	LBB187_549
Ltmp10647:
; %bb.548:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_559
Ltmp10648:
LBB187_549:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_551
Ltmp10649:
; %bb.550:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_555
Ltmp10650:
LBB187_551:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x25, #0x1fff0
	add	x10, x22, x24, lsl #2
	mov	x11, x9
Ltmp10651:
LBB187_552:                             ;   Parent Loop BB187_544 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	fcvtl2	v4.2d, v0.4s
	mov	d5, v4[1]
	fcvtl	v0.2d, v0.2s
	mov	d6, v0[1]
	fcvtl2	v7.2d, v1.4s
	mov	d16, v7[1]
	fcvtl	v1.2d, v1.2s
	mov	d17, v1[1]
	fcvtl2	v18.2d, v2.4s
	mov	d19, v18[1]
	fcvtl	v2.2d, v2.2s
	mov	d20, v2[1]
	fcvtl2	v21.2d, v3.4s
	mov	d22, v21[1]
	fcvtl	v3.2d, v3.2s
	mov	d23, v3[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d6
	fadd	d0, d0, d4
	fadd	d0, d0, d5
	fadd	d0, d0, d1
	fadd	d0, d0, d17
	fadd	d0, d0, d7
	fadd	d0, d0, d16
	fadd	d0, d0, d2
	fadd	d0, d0, d20
	fadd	d0, d0, d18
	fadd	d0, d0, d19
	fadd	d0, d0, d3
	fadd	d0, d0, d23
	fadd	d0, d0, d21
	fadd	d8, d0, d22
	subs	x11, x11, #16
	b.ne	LBB187_552
Ltmp10652:
; %bb.553:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x9
	b.eq	LBB187_543
Ltmp10653:
; %bb.554:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x25, #0xc
	b.eq	LBB187_558
Ltmp10654:
LBB187_555:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	add	x9, x21, x9, lsl #2
Ltmp10655:
LBB187_556:                             ;   Parent Loop BB187_544 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q0, [x9], #16
	fcvtl2	v1.2d, v0.4s
	mov	d2, v1[1]
	fcvtl	v0.2d, v0.2s
	mov	d3, v0[1]
	fadd	d0, d8, d0
	fadd	d0, d0, d3
	fadd	d0, d0, d1
	fadd	d8, d0, d2
	adds	x12, x12, #4
	b.ne	LBB187_556
Ltmp10656:
; %bb.557:                              ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x25, x11
	b.eq	LBB187_543
	b	LBB187_559
Ltmp10657:
LBB187_558:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x24, x9
Ltmp10658:
LBB187_559:                             ;   in Loop: Header=BB187_544 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x24, x25
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp10659:
LBB187_560:                             ;   Parent Loop BB187_544 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x10], #4
Ltmp10660:
	;DEBUG_VALUE: raw <- $s0
	fcvt	d0, s0
Ltmp10661:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10662:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp10663:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.ne	LBB187_560
	b	LBB187_543
Ltmp10664:
LBB187_561:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	w8, #1
	b.eq	LBB187_802
Ltmp10665:
; %bb.562:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_935
Ltmp10666:
; %bb.563:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10667:
; %bb.564:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1684:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1685:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp10668:
	movk	x8, #16527, lsl #48
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	fmov	d10, x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_566
Ltmp10669:
LBB187_565:                             ;   in Loop: Header=BB187_566 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp10670:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10671:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_943
Ltmp10672:
LBB187_566:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_570 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x26
Ltmp10673:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x25, x8, x23, lo
Ltmp10674:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_568
Ltmp10675:
; %bb.567:                              ;   in Loop: Header=BB187_566 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10676:
LBB187_568:                             ;   in Loop: Header=BB187_566 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10677:
	;DEBUG_VALUE: i <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x8
	b.hs	LBB187_565
Ltmp10678:
; %bb.569:                              ;   in Loop: Header=BB187_566 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x9, x21, x26
Ltmp10679:
LBB187_570:                             ;   Parent Loop BB187_566 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w10, [x9], #1
Ltmp10680:
	;DEBUG_VALUE: raw <- $w10
	sxtb	w11, w10
Ltmp10681:
	;DEBUG_VALUE: byte_missing_offset:value <- $w10
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 204 25 is_stmt 1              ; numeric-payload.c:204:25 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sub	w10, w10, #101
Ltmp10682:
	cmp	w11, #100
Ltmp10683:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d1, w11
Ltmp10684:
	.loc	0 204 25                        ; numeric-payload.c:204:25 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	csinv	w10, w10, wzr, gt
Ltmp10685:
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	;DEBUG_VALUE: missing <- $w10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
Ltmp10686:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	add	w11, w10, #96
Ltmp10687:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp10688:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	fmov	d2, x11
Ltmp10689:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp10690:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp10691:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp10692:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x25, x25, #1
Ltmp10693:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_570
	b	LBB187_565
Ltmp10694:
LBB187_571:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w10, #1
	b.eq	LBB187_810
Ltmp10695:
; %bb.572:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w10, #2
	b.ne	LBB187_944
Ltmp10696:
; %bb.573:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp10697:
; %bb.574:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65508                     ; =0xffe4
	movk	w23, #32767, lsl #16
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x24, x21, #16
	mov	w25, #65536                     ; =0x10000
Lloh1686:
	adrp	x26, _R_NaReal@GOTPAGE
Lloh1687:
	ldr	x26, [x26, _R_NaReal@GOTPAGEOFF]
	mov	x9, #70368744177664             ; =0x400000000000
	movk	x9, #16527, lsl #48
	dup.2d	v26, x9
	fmov	d9, x9
	mov	x9, #2147483648                 ; =0x80000000
	movk	x9, #53239, lsl #32
	movk	x9, #49586, lsl #48
	dup.2d	v27, x9
	fmov	d10, x9
	mvni.2s	v0, #27
	fneg.2s	v11, v0
	mvni.2s	v0, #26
	fneg.2s	v12, v0
	movi.2s	v0, #123
	fneg.2s	v13, v0
	dup.2d	v28, x22
	stp	q27, q26, [sp, #64]             ; 32-byte Folded Spill
	str	q28, [sp, #48]                  ; 16-byte Folded Spill
	b	LBB187_576
Ltmp10698:
LBB187_575:                             ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x27, x9
Ltmp10699:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp10700:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp10701:
LBB187_576:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_582 Depth 2
                                        ;     Child Loop BB187_585 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x8, x27
Ltmp10702:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x28, x19, x25, lo
Ltmp10703:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_578
Ltmp10704:
; %bb.577:                              ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10705:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q28, q27, [sp, #48]             ; 32-byte Folded Reload
	ldr	q26, [sp, #80]                  ; 16-byte Folded Reload
Ltmp10706:
LBB187_578:                             ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x28, x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10707:
	;DEBUG_VALUE: i <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x9
	b.hs	LBB187_575
Ltmp10708:
; %bb.579:                              ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x26]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #8
	b.hs	LBB187_581
Ltmp10709:
; %bb.580:                              ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x8, x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_584
Ltmp10710:
LBB187_581:                             ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	and	x10, x28, #0x1fff8
	add	x8, x27, x10
	dup.2d	v1, v0[0]
	add	x11, x24, x27, lsl #2
	mov	x12, x10
Ltmp10711:
LBB187_582:                             ;   Parent Loop BB187_576 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	d2, d3, [x11, #-16]
	ldp	d4, d5, [x11], #32
Ltmp10712:
	.loc	0 214 41 is_stmt 1              ; numeric-payload.c:214:41 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	smax.2s	v6, v2, v11
	smax.2s	v7, v3, v11
	smax.2s	v16, v4, v11
	smax.2s	v17, v5, v11
Ltmp10713:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v18, v2, #0
	scvtf.2d	v18, v18
	sshll.2d	v19, v3, #0
	scvtf.2d	v19, v19
	sshll.2d	v20, v4, #0
	scvtf.2d	v20, v20
	sshll.2d	v21, v5, #0
	scvtf.2d	v21, v21
	fdiv.2d	v18, v18, v26
	fdiv.2d	v19, v19, v26
	fdiv.2d	v20, v20, v26
	fdiv.2d	v21, v21, v26
	fadd.2d	v18, v18, v27
	fadd.2d	v19, v19, v27
	fadd.2d	v20, v20, v27
	fadd.2d	v21, v21, v27
Ltmp10714:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.2s	v22, v2, v12
	sshll.2d	v22, v22, #0
	cmeq.2s	v23, v3, v12
	sshll.2d	v23, v23, #0
	cmeq.2s	v24, v4, v12
	sshll.2d	v24, v24, #0
	cmeq.2s	v25, v5, v12
	sshll.2d	v25, v25, #0
	cmgt.2s	v2, v2, v12
	sshll.2d	v2, v2, #0
	cmgt.2s	v3, v3, v12
	sshll.2d	v3, v3, #0
	cmgt.2s	v4, v4, v12
	sshll.2d	v4, v4, #0
	cmgt.2s	v5, v5, v12
	sshll.2d	v5, v5, #0
Ltmp10715:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add.2s	v6, v6, v13
	add.2s	v7, v7, v13
	add.2s	v16, v16, v13
	add.2s	v17, v17, v13
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	shll.2d	v6, v6, #32
	shll.2d	v7, v7, #32
	shll.2d	v16, v16, #32
	shll.2d	v17, v17, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	orr.16b	v6, v6, v28
	orr.16b	v7, v7, v28
	orr.16b	v16, v16, v28
	orr.16b	v17, v17, v28
Ltmp10716:
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	bsl.16b	v2, v6, v18
	bit.16b	v2, v1, v22
	mov	d6, v2[1]
	bsl.16b	v3, v7, v19
	bit.16b	v3, v1, v23
	mov	d7, v3[1]
	bsl.16b	v4, v16, v20
	bit.16b	v4, v1, v24
	mov	d16, v4[1]
	bsl.16b	v5, v17, v21
	bit.16b	v5, v1, v25
	mov	d17, v5[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d3
	fadd	d2, d2, d7
	fadd	d2, d2, d4
	fadd	d2, d2, d16
	fadd	d2, d2, d5
	fadd	d8, d2, d17
	subs	x12, x12, #8
	b.ne	LBB187_582
Ltmp10717:
; %bb.583:                              ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x28, x10
	b.eq	LBB187_575
Ltmp10718:
LBB187_584:                             ;   in Loop: Header=BB187_576 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x27, x28
	sub	x10, x10, x8
	add	x8, x21, x8, lsl #2
Ltmp10719:
LBB187_585:                             ;   Parent Loop BB187_576 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x8], #4
Ltmp10720:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 214 41 is_stmt 1              ; numeric-payload.c:214:41 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmp	w11, w23
	csel	w12, w11, w23, gt
Ltmp10721:
	;DEBUG_VALUE: missing <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] $w12
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d1, w11
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
Ltmp10722:
	;DEBUG_VALUE: numeric_missing_value:offset <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] $w12
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w13, w23, #1
	cmp	w11, w13
Ltmp10723:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w12, w23, w12
Ltmp10724:
	add	w12, w12, #151
Ltmp10725:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x12
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	orr	x12, x22, x12, lsl #32
Ltmp10726:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x12
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fmov	d2, x12
Ltmp10727:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fcsel	d2, d0, d2, eq
Ltmp10728:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w23
	fcsel	d1, d1, d2, le
Ltmp10729:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp10730:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x10, x10, #1
Ltmp10731:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_585
	b	LBB187_575
Ltmp10732:
LBB187_586:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	w8, #1
	b.eq	LBB187_863
Ltmp10733:
; %bb.587:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_992
Ltmp10734:
; %bb.588:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10735:
; %bb.589:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x28, #0                         ; =0x0
Ltmp10736:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1688:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1689:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	w25, #-32741                    ; =0xffff801b
	mov	w26, #32740                     ; =0x7fe4
	mov	x8, #70368744177664             ; =0x400000000000
Ltmp10737:
	movk	x8, #16527, lsl #48
	fmov	d9, x8
	mov	x8, #2147483648                 ; =0x80000000
	movk	x8, #53239, lsl #32
	movk	x8, #49586, lsl #48
	fmov	d10, x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_591
Ltmp10738:
LBB187_590:                             ;   in Loop: Header=BB187_591 Depth=1
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x28, x8
Ltmp10739:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10740:
	;DEBUG_VALUE: start <- $x28
	b.hs	LBB187_1012
Ltmp10741:
LBB187_591:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_595 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x28
Ltmp10742:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp10743:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_593
Ltmp10744:
; %bb.592:                              ;   in Loop: Header=BB187_591 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10745:
LBB187_593:                             ;   in Loop: Header=BB187_591 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10746:
	;DEBUG_VALUE: i <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x28, x8
	b.hs	LBB187_590
Ltmp10747:
; %bb.594:                              ;   in Loop: Header=BB187_591 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x9, x21, x28, lsl #1
Ltmp10748:
LBB187_595:                             ;   Parent Loop BB187_591 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w10, [x9], #2
Ltmp10749:
	;DEBUG_VALUE: raw <- $w10
	sxth	w11, w10
Ltmp10750:
	;DEBUG_VALUE: int_missing_offset:value <- $w10
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 209 27 is_stmt 1              ; numeric-payload.c:209:27 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w10, w10, w25
Ltmp10751:
	cmp	w11, w26
Ltmp10752:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d1, w11
Ltmp10753:
	.loc	0 209 27                        ; numeric-payload.c:209:27 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	csinv	w10, w10, wzr, gt
Ltmp10754:
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	;DEBUG_VALUE: missing <- $w10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	fdiv	d1, d1, d9
	fadd	d1, d1, d10
Ltmp10755:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w11, w10, #96
Ltmp10756:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp10757:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	fmov	d2, x11
Ltmp10758:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp10759:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp10760:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp10761:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x27, x27, #1
Ltmp10762:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_595
	b	LBB187_590
Ltmp10763:
LBB187_596:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w8, #1
	b.eq	LBB187_871
Ltmp10764:
; %bb.597:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	w8, #2
	b.ne	LBB187_1000
Ltmp10765:
; %bb.598:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10766:
; %bb.599:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	mov	x13, #1954                      ; =0x7a2
	movk	x13, #32752, lsl #48
	mov	w23, #-2130706432               ; =0x81000000
	mov	w24, #12287                     ; =0x2fff
	movk	w24, #33023, lsl #16
	movi.4s	v30, #129, lsl #24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x8, x21, #32
Ltmp10767:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	str	x8, [sp, #16]                   ; 8-byte Folded Spill
	mov	w14, #65536                     ; =0x10000
	mov	w8, #53249                      ; =0xd001
	dup.4s	v31, w8
	mov	w28, #-53249                    ; =0xffff2fff
Ltmp10768:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	x25, #70368744177664            ; =0x400000000000
	movk	x25, #16527, lsl #48
	movi.4s	v9, #7, msl #8
	mov	x27, #2147483648                ; =0x80000000
	movk	x27, #53239, lsl #32
	movk	x27, #49586, lsl #48
	dup.2d	v10, x13
	dup.2d	v11, x25
	dup.2d	v12, x27
	stp	q10, q31, [sp, #64]             ; 32-byte Folded Spill
	stp	q12, q11, [sp, #32]             ; 32-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_601
Ltmp10769:
LBB187_600:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp10770:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10771:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp10772:
LBB187_601:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_609 Depth 2
                                        ;     Child Loop BB187_613 Depth 2
                                        ;     Child Loop BB187_619 Depth 2
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x26
Ltmp10773:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x22, x19, x14, lo
Ltmp10774:
	;DEBUG_VALUE: count <- $x22
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_603
Ltmp10775:
; %bb.602:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp10776:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q12, q11, [sp, #32]             ; 32-byte Folded Reload
	ldp	q10, q31, [sp, #64]             ; 32-byte Folded Reload
	movi.4s	v9, #7, msl #8
	mov	w14, #65536                     ; =0x10000
	movi.4s	v30, #129, lsl #24
	mov	x13, #1954                      ; =0x7a2
	movk	x13, #32752, lsl #48
Ltmp10777:
LBB187_603:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x22, x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10778:
	;DEBUG_VALUE: i <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x26, x8
	b.hs	LBB187_600
Ltmp10779:
; %bb.604:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
Lloh1690:
	adrp	x9, _R_NaReal@GOTPAGE
Lloh1691:
	ldr	x9, [x9, _R_NaReal@GOTPAGEOFF]
Lloh1692:
	ldr	d0, [x9]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #4
	b.hs	LBB187_606
Ltmp10780:
; %bb.605:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_616
Ltmp10781:
LBB187_606:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	cmp	x19, #16
	b.hs	LBB187_608
Ltmp10782:
; %bb.607:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_612
Ltmp10783:
LBB187_608:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x22, #0x1fff0
	dup.2d	v1, v0[0]
	ldr	x10, [sp, #16]                  ; 8-byte Folded Reload
	add	x10, x10, x26, lsl #2
	mov	x11, x9
Ltmp10784:
LBB187_609:                             ;   Parent Loop BB187_601 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q23, q20, [x10, #-32]
	ldp	q16, q2, [x10]
Ltmp10785:
	.loc	0 225 37 is_stmt 1              ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add.4s	v5, v23, v30
	cmhi.4s	v3, v31, v5
	add.4s	v6, v20, v30
	cmhi.4s	v7, v31, v6
	add.4s	v17, v16, v30
	cmhi.4s	v18, v31, v17
	add.4s	v19, v2, v30
Ltmp10786:
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.16b	v4, v23, v9
	and.16b	v21, v20, v9
	and.16b	v22, v16, v9
	and.16b	v24, v2, v9
Ltmp10787:
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmhi.4s	v25, v31, v19
Ltmp10788:
	.loc	0 229 41                        ; numeric-payload.c:229:41 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v26, v4, #0
	cmeq.4s	v27, v21, #0
	cmeq.4s	v22, v22, #0
	cmeq.4s	v28, v24, #0
	.loc	0 229 12 is_stmt 0              ; numeric-payload.c:229:12 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ushr.4s	v29, v5, #11
	ushr.4s	v24, v6, #11
	ushr.4s	v21, v17, #11
	ushr.4s	v4, v19, #11
	and.16b	v3, v3, v26
	and.16b	v26, v7, v27
	and.16b	v27, v18, v22
	xtn.4h	v3, v3
	and.16b	v25, v25, v28
Ltmp10789:
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v5, v5, #0
	xtn.4h	v5, v5
	cmeq.4s	v6, v6, #0
	cmeq.4s	v7, v17, #0
	xtn.4h	v6, v6
	xtn.4h	v7, v7
	cmeq.4s	v17, v19, #0
	xtn.4h	v17, v17
	bic.8b	v22, v3, v5
Ltmp10790:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.4s	v29, #96
	xtn.4h	v18, v26
	orr.4s	v24, #96
	orr.4s	v21, #96
	orr.4s	v4, #96
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v29, #32
	shll2.2d	v28, v29, #32
	xtn.4h	v19, v27
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v26, v26, v10
Ltmp10791:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v27.2d, v23.2s
	fdiv.2d	v27, v27, v11
	fadd.2d	v27, v27, v12
	ushll.4s	v29, v22, #0
	ushll.2d	v22, v29, #0
	shl.2d	v22, v22, #63
	cmlt.2d	v22, v22, #0
	bsl.16b	v22, v26, v27
Ltmp10792:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v24, #32
	shll2.2d	v27, v24, #32
	xtn.4h	v24, v25
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v25, v28, v10
Ltmp10793:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v23.2d, v23.4s
	fcvtl	v28.2d, v20.2s
	fdiv.2d	v23, v23, v11
	fdiv.2d	v28, v28, v11
Ltmp10794:
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v26, v26, v10
Ltmp10795:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd.2d	v23, v23, v12
	ushll2.2d	v29, v29, #0
	shl.2d	v29, v29, #63
	cmlt.2d	v29, v29, #0
	bit.16b	v23, v25, v29
Ltmp10796:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v25, v18, v6
Ltmp10797:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd.2d	v28, v28, v12
	ushll.4s	v29, v25, #0
	ushll.2d	v25, v29, #0
	shl.2d	v25, v25, #63
	cmlt.2d	v25, v25, #0
	bsl.16b	v25, v26, v28
Ltmp10798:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v21, #32
	shll2.2d	v28, v21, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v21, v27, v10
	orr.16b	v26, v26, v10
Ltmp10799:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v20.2d, v20.4s
Ltmp10800:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v27, v19, v7
Ltmp10801:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fdiv.2d	v20, v20, v11
	fadd.2d	v20, v20, v12
	ushll2.2d	v29, v29, #0
	shl.2d	v29, v29, #63
	cmlt.2d	v29, v29, #0
	bit.16b	v20, v21, v29
	fcvtl	v21.2d, v16.2s
	fdiv.2d	v21, v21, v11
	fadd.2d	v21, v21, v12
	ushll.4s	v27, v27, #0
	ushll.2d	v29, v27, #0
	shl.2d	v29, v29, #63
	cmlt.2d	v29, v29, #0
	bit.16b	v21, v26, v29
Ltmp10802:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v4, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v28, v28, v10
	orr.16b	v26, v26, v10
Ltmp10803:
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v29, v24, v17
Ltmp10804:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v16.2d, v16.4s
	fdiv.2d	v16, v16, v11
	fadd.2d	v16, v16, v12
	ushll2.2d	v27, v27, #0
	shl.2d	v27, v27, #63
	cmlt.2d	v27, v27, #0
	bit.16b	v16, v28, v27
	fcvtl	v27.2d, v2.2s
	fdiv.2d	v27, v27, v11
	fadd.2d	v27, v27, v12
	ushll.4s	v28, v29, #0
	ushll.2d	v29, v28, #0
	shl.2d	v29, v29, #63
	cmlt.2d	v29, v29, #0
	bif.16b	v26, v27, v29
Ltmp10805:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll2.2d	v4, v4, #32
Ltmp10806:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v2.2d, v2.4s
Ltmp10807:
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v4, v4, v10
Ltmp10808:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fdiv.2d	v2, v2, v11
	fadd.2d	v2, v2, v12
	ushll2.2d	v27, v28, #0
	shl.2d	v27, v27, #63
	cmlt.2d	v27, v27, #0
	bit.16b	v2, v4, v27
Ltmp10809:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.8b	v3, v3, v5
	and.8b	v4, v18, v6
	and.8b	v5, v19, v7
	and.8b	v6, v24, v17
Ltmp10810:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ushll.4s	v3, v3, #0
	ushll2.2d	v7, v3, #0
	shl.2d	v7, v7, #63
	cmlt.2d	v7, v7, #0
	bsl.16b	v7, v1, v23
	ushll.2d	v3, v3, #0
	shl.2d	v3, v3, #63
	cmlt.2d	v3, v3, #0
	bsl.16b	v3, v1, v22
	ushll.4s	v4, v4, #0
	ushll2.2d	v17, v4, #0
	shl.2d	v17, v17, #63
	cmlt.2d	v17, v17, #0
	bsl.16b	v17, v1, v20
	ushll.2d	v4, v4, #0
	shl.2d	v4, v4, #63
	cmlt.2d	v4, v4, #0
	bsl.16b	v4, v1, v25
	ushll.4s	v5, v5, #0
	ushll2.2d	v18, v5, #0
	shl.2d	v18, v18, #63
	cmlt.2d	v18, v18, #0
	bit.16b	v16, v1, v18
	ushll.2d	v5, v5, #0
	shl.2d	v5, v5, #63
	cmlt.2d	v5, v5, #0
	bsl.16b	v5, v1, v21
	ushll.4s	v6, v6, #0
	ushll2.2d	v18, v6, #0
	shl.2d	v18, v18, #63
	cmlt.2d	v18, v18, #0
	bit.16b	v2, v1, v18
	ushll.2d	v6, v6, #0
	shl.2d	v6, v6, #63
	cmlt.2d	v6, v6, #0
	bsl.16b	v6, v1, v26
	fadd	d18, d8, d3
	mov	d3, v3[1]
	fadd	d3, d18, d3
	fadd	d3, d3, d7
	mov	d7, v7[1]
	fadd	d3, d3, d7
	fadd	d3, d3, d4
	mov	d4, v4[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d17
	mov	d4, v17[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d5
	mov	d4, v5[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d16
	mov	d4, v16[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d6
	mov	d4, v6[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d8, d3, d2
	add	x10, x10, #64
	subs	x11, x11, #16
	b.ne	LBB187_609
Ltmp10811:
; %bb.610:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x22, x9
	b.eq	LBB187_600
Ltmp10812:
; %bb.611:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	tst	x22, #0xc
	b.eq	LBB187_615
Ltmp10813:
LBB187_612:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x22, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #2
Ltmp10814:
LBB187_613:                             ;   Parent Loop BB187_601 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q2, [x9], #16
Ltmp10815:
	.loc	0 225 37 is_stmt 1              ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add.4s	v3, v2, v30
	cmhi.4s	v4, v31, v3
Ltmp10816:
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.16b	v5, v2, v9
	.loc	0 229 41 is_stmt 0              ; numeric-payload.c:229:41 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v5, v5, #0
	.loc	0 229 12                        ; numeric-payload.c:229:12 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ushr.4s	v6, v3, #11
	and.16b	v4, v4, v5
	xtn.4h	v4, v4
Ltmp10817:
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v3, v3, #0
	xtn.4h	v3, v3
	bic.8b	v5, v4, v3
Ltmp10818:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.4s	v6, #96
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v7, v6, #32
	shll2.2d	v6, v6, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v6, v6, v10
	orr.16b	v7, v7, v10
Ltmp10819:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v16.2d, v2.4s
	fcvtl	v2.2d, v2.2s
	fdiv.2d	v2, v2, v11
	fdiv.2d	v16, v16, v11
	fadd.2d	v16, v16, v12
	fadd.2d	v2, v2, v12
Ltmp10820:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.8b	v3, v4, v3
Ltmp10821:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ushll.4s	v4, v5, #0
	ushll.2d	v5, v4, #0
	shl.2d	v5, v5, #63
	cmlt.2d	v5, v5, #0
	bit.16b	v2, v7, v5
	ushll2.2d	v4, v4, #0
	shl.2d	v4, v4, #63
	cmlt.2d	v4, v4, #0
	bsl.16b	v4, v6, v16
	ushll.4s	v3, v3, #0
	ushll2.2d	v5, v3, #0
	shl.2d	v5, v5, #63
	cmlt.2d	v5, v5, #0
	bit.16b	v4, v1, v5
	mov	d5, v4[1]
	ushll.2d	v3, v3, #0
	shl.2d	v3, v3, #63
	cmlt.2d	v3, v3, #0
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d3
	fadd	d2, d2, d4
	fadd	d8, d2, d5
	adds	x12, x12, #4
	b.ne	LBB187_613
Ltmp10822:
; %bb.614:                              ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x22, x11
	b.eq	LBB187_600
	b	LBB187_616
Ltmp10823:
LBB187_615:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x26, x9
Ltmp10824:
LBB187_616:                             ;   in Loop: Header=BB187_601 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x26, x22
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
	b	LBB187_619
Ltmp10825:
LBB187_617:                             ;   in Loop: Header=BB187_619 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: missing <- -1
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d1, s1
Ltmp10826:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	fmov	d2, x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fdiv	d1, d1, d2
	fmov	d2, x27
	fadd	d1, d1, d2
Ltmp10827:
LBB187_618:                             ;   in Loop: Header=BB187_619 Depth=2
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: element <- $d1
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d8, d8, d1
Ltmp10828:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp10829:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_600
Ltmp10830:
LBB187_619:                             ;   Parent Loop BB187_601 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s1, [x10], #4
Ltmp10831:
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: float_missing_offset:value <- $s1
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w11, s1
Ltmp10832:
	;DEBUG_VALUE: float_missing_offset:bits <- $w11
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w12, w11, w24
	cmp	w12, w28
Ltmp10833:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w11
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and	w12, w11, #0x7ff
	ccmp	w12, #0, #0, hs
	b.ne	LBB187_617
Ltmp10834:
; %bb.620:                              ;   in Loop: Header=BB187_619 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 18 is_stmt 0                ; numeric-payload.c:0:18
	mov.16b	v1, v0
Ltmp10835:
	add	w11, w11, w23
Ltmp10836:
	;DEBUG_VALUE: missing <- undef
	;DEBUG_VALUE: numeric_missing_value:offset <- undef
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cbz	w11, LBB187_618
Ltmp10837:
; %bb.621:                              ;   in Loop: Header=BB187_619 Depth=2
	;DEBUG_VALUE: count <- $x22
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 0 is_stmt 0                 ; numeric-payload.c:0 @[ numeric-payload.c:1833:25 ]
	lsr	w11, w11, #11
Ltmp10838:
	;DEBUG_VALUE: missing <- $w11
	;DEBUG_VALUE: numeric_missing_value:offset <- $w11
	.loc	0 235 48 is_stmt 1              ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	w11, w11, #0x60
Ltmp10839:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	x11, x13, x11, lsl #32
Ltmp10840:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	d1, x11
Ltmp10841:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d1
	;DEBUG_VALUE: numeric_missing_value:value <- $d1
	.loc	0 0 5 is_stmt 0                 ; numeric-payload.c:0:5
	b	LBB187_618
Ltmp10842:
LBB187_622:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10843:
; %bb.623:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10844:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_625
Ltmp10845:
LBB187_624:                             ;   in Loop: Header=BB187_625 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp10846:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10847:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_943
Ltmp10848:
LBB187_625:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_629 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x19
Ltmp10849:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x23, x8, x22, lo
Ltmp10850:
	;DEBUG_VALUE: count <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_627
Ltmp10851:
; %bb.626:                              ;   in Loop: Header=BB187_625 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10852:
LBB187_627:                             ;   in Loop: Header=BB187_625 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x23, x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10853:
	;DEBUG_VALUE: i <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, x8
	b.hs	LBB187_624
Ltmp10854:
; %bb.628:                              ;   in Loop: Header=BB187_625 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19
Ltmp10855:
LBB187_629:                             ;   Parent Loop BB187_625 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w10, [x9], #1
Ltmp10856:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: byte_missing_offset:value <- $w10
	sxtb	w11, w10
Ltmp10857:
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d0, w11
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, #127
	fcsel	d8, d8, d0, eq
Ltmp10858:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x23, x23, #1
Ltmp10859:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_629
	b	LBB187_624
Ltmp10860:
LBB187_630:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp10861:
; %bb.631:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	x9, #151732604633088            ; =0x8a0000000000
	movk	x9, #49324, lsl #48
	fmov	d9, x9
	mov	w23, #2147483647                ; =0x7fffffff
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_633
Ltmp10862:
LBB187_632:                             ;   in Loop: Header=BB187_633 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x24, x9
Ltmp10863:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp10864:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10865:
LBB187_633:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_637 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x24
Ltmp10866:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x19, x9, x22, lo
Ltmp10867:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_635
Ltmp10868:
; %bb.634:                              ;   in Loop: Header=BB187_633 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10869:
LBB187_635:                             ;   in Loop: Header=BB187_633 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x19, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10870:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x9
	b.hs	LBB187_632
Ltmp10871:
; %bb.636:                              ;   in Loop: Header=BB187_633 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x21, x24, lsl #2
Ltmp10872:
LBB187_637:                             ;   Parent Loop BB187_633 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w10, [x8], #4
Ltmp10873:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: long_missing_offset:value <- $w10
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d0, w10
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, eq
Ltmp10874:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x19, x19, #1
Ltmp10875:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_637
	b	LBB187_632
Ltmp10876:
LBB187_638:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10877:
; %bb.639:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x23, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10878:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_641
Ltmp10879:
LBB187_640:                             ;   in Loop: Header=BB187_641 Depth=1
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x23, x8
Ltmp10880:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10881:
	;DEBUG_VALUE: start <- $x23
	b.hs	LBB187_943
Ltmp10882:
LBB187_641:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_645 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x23
Ltmp10883:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp10884:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_643
Ltmp10885:
; %bb.642:                              ;   in Loop: Header=BB187_641 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10886:
LBB187_643:                             ;   in Loop: Header=BB187_641 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10887:
	;DEBUG_VALUE: i <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x23, x8
	b.hs	LBB187_640
Ltmp10888:
; %bb.644:                              ;   in Loop: Header=BB187_641 Depth=1
	;DEBUG_VALUE: i <- $x23
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x23
Ltmp10889:
LBB187_645:                             ;   Parent Loop BB187_641 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w10, [x9], #1
Ltmp10890:
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d0, w10
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, #100
	fcsel	d8, d8, d0, gt
Ltmp10891:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x19, x19, #1
Ltmp10892:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_645
	b	LBB187_640
Ltmp10893:
LBB187_646:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp10894:
; %bb.647:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65508                     ; =0xffe4
	movk	w22, #32767, lsl #16
	mov	w23, #65536                     ; =0x10000
	mov	x9, #151732604633088            ; =0x8a0000000000
	movk	x9, #49324, lsl #48
	fmov	d9, x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_649
Ltmp10895:
LBB187_648:                             ;   in Loop: Header=BB187_649 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x24, x9
Ltmp10896:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp10897:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10898:
LBB187_649:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_653 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x24
Ltmp10899:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x19, x9, x23, lo
Ltmp10900:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_651
Ltmp10901:
; %bb.650:                              ;   in Loop: Header=BB187_649 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10902:
LBB187_651:                             ;   in Loop: Header=BB187_649 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x19, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp10903:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x9
	b.hs	LBB187_648
Ltmp10904:
; %bb.652:                              ;   in Loop: Header=BB187_649 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x21, x24, lsl #2
Ltmp10905:
LBB187_653:                             ;   Parent Loop BB187_649 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w10, [x8], #4
Ltmp10906:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: long_missing_offset:value <- $w10
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d0, w10
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, w22
	fcsel	d8, d8, d0, gt
Ltmp10907:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x19, x19, #1
Ltmp10908:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_653
	b	LBB187_648
Ltmp10909:
LBB187_654:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10910:
; %bb.655:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10911:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	mov	w23, #32767                     ; =0x7fff
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_657
Ltmp10912:
LBB187_656:                             ;   in Loop: Header=BB187_657 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp10913:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10914:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp10915:
LBB187_657:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_661 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x19
Ltmp10916:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x24, x8, x22, lo
Ltmp10917:
	;DEBUG_VALUE: count <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_659
Ltmp10918:
; %bb.658:                              ;   in Loop: Header=BB187_657 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10919:
LBB187_659:                             ;   in Loop: Header=BB187_657 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x24, x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10920:
	;DEBUG_VALUE: i <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, x8
	b.hs	LBB187_656
Ltmp10921:
; %bb.660:                              ;   in Loop: Header=BB187_657 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #1
Ltmp10922:
LBB187_661:                             ;   Parent Loop BB187_657 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w10, [x9], #2
Ltmp10923:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: int_missing_offset:value <- $w10
	sxth	w11, w10
Ltmp10924:
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d0, w11
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, eq
Ltmp10925:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x24, x24, #1
Ltmp10926:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_661
	b	LBB187_656
Ltmp10927:
LBB187_662:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10928:
; %bb.663:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	x23, #151732604633088           ; =0x8a0000000000
	movk	x23, #49324, lsl #48
	mov	w24, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_665
Ltmp10929:
LBB187_664:                             ;   in Loop: Header=BB187_665 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp10930:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10931:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp10932:
LBB187_665:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_671 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp10933:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x25, x8, x22, lo
Ltmp10934:
	;DEBUG_VALUE: count <- $x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_667
Ltmp10935:
; %bb.666:                              ;   in Loop: Header=BB187_665 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10936:
LBB187_667:                             ;   in Loop: Header=BB187_665 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10937:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_664
Ltmp10938:
; %bb.668:                              ;   in Loop: Header=BB187_665 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #2
	b	LBB187_671
Ltmp10939:
LBB187_669:                             ;   in Loop: Header=BB187_671 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp10940:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	fmov	d1, x23
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d0, d0, d1
Ltmp10941:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10942:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_670:                             ;   in Loop: Header=BB187_671 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x25, x25, #1
Ltmp10943:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_664
Ltmp10944:
LBB187_671:                             ;   Parent Loop BB187_665 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp10945:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_669
Ltmp10946:
; %bb.672:                              ;   in Loop: Header=BB187_671 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp10947:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s0
	ccmp	w10, w24, #0, vc
	b.le	LBB187_669
	b	LBB187_670
Ltmp10948:
LBB187_673:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp10949:
; %bb.674:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp10950:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	mov	w23, #32740                     ; =0x7fe4
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_676
Ltmp10951:
LBB187_675:                             ;   in Loop: Header=BB187_676 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp10952:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp10953:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp10954:
LBB187_676:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_680 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x24
Ltmp10955:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp10956:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_678
Ltmp10957:
; %bb.677:                              ;   in Loop: Header=BB187_676 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10958:
LBB187_678:                             ;   in Loop: Header=BB187_676 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp10959:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_675
Ltmp10960:
; %bb.679:                              ;   in Loop: Header=BB187_676 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x24, lsl #1
Ltmp10961:
LBB187_680:                             ;   Parent Loop BB187_676 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w10, [x9], #2
Ltmp10962:
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d0, w10
	fadd	d0, d0, d9
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, gt
Ltmp10963:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x19, x19, #1
Ltmp10964:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_680
	b	LBB187_675
Ltmp10965:
LBB187_681:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp10966:
; %bb.682:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #12287                     ; =0x2fff
	movk	w22, #33023, lsl #16
	mov	w23, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	x24, #151732604633088           ; =0x8a0000000000
	movk	x24, #49324, lsl #48
	mov	w25, #-53249                    ; =0xffff2fff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_684
Ltmp10967:
LBB187_683:                             ;   in Loop: Header=BB187_684 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp10968:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp10969:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp10970:
LBB187_684:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_690 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp10971:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x26, x8, x23, lo
Ltmp10972:
	;DEBUG_VALUE: count <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_686
Ltmp10973:
; %bb.685:                              ;   in Loop: Header=BB187_684 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10974:
LBB187_686:                             ;   in Loop: Header=BB187_684 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x26, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp10975:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_683
Ltmp10976:
; %bb.687:                              ;   in Loop: Header=BB187_684 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #2
	b	LBB187_690
Ltmp10977:
LBB187_688:                             ;   in Loop: Header=BB187_690 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp10978:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	fmov	d1, x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d0, d0, d1
Ltmp10979:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp10980:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_689:                             ;   in Loop: Header=BB187_690 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x26, x26, #1
Ltmp10981:
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_683
Ltmp10982:
LBB187_690:                             ;   Parent Loop BB187_684 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp10983:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_688
Ltmp10984:
; %bb.691:                              ;   in Loop: Header=BB187_690 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp10985:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w11, w10, w22
Ltmp10986:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w10
	.loc	0 0 37 is_stmt 0                ; numeric-payload.c:0:37
	tst	w10, #0x7ff
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ccmp	w11, w25, #0, eq
	cset	w10, lo
Ltmp10987:
	fcmp	s0, s0
	ccmp	w10, #0, #4, vc
	b.ne	LBB187_688
	b	LBB187_689
Ltmp10988:
LBB187_692:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp10989:
; %bb.693:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x23, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_695
Ltmp10990:
LBB187_694:                             ;   in Loop: Header=BB187_695 Depth=1
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x23, x8
Ltmp10991:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp10992:
	;DEBUG_VALUE: start <- $x23
	b.hs	LBB187_943
Ltmp10993:
LBB187_695:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_699 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x23
Ltmp10994:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp10995:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_697
Ltmp10996:
; %bb.696:                              ;   in Loop: Header=BB187_695 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp10997:
LBB187_697:                             ;   in Loop: Header=BB187_695 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp10998:
	;DEBUG_VALUE: i <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x23, x8
	b.hs	LBB187_694
Ltmp10999:
; %bb.698:                              ;   in Loop: Header=BB187_695 Depth=1
	;DEBUG_VALUE: i <- $x23
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x23
Ltmp11000:
LBB187_699:                             ;   Parent Loop BB187_695 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w10, [x9], #1
Ltmp11001:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: byte_missing_offset:value <- $w10
	sxtb	w11, w10
Ltmp11002:
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d0, w11
	fadd	d0, d8, d0
	cmp	w10, #127
	fcsel	d8, d8, d0, eq
Ltmp11003:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x19, x19, #1
Ltmp11004:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_699
	b	LBB187_694
Ltmp11005:
LBB187_700:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11006:
; %bb.701:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	w23, #2147483647                ; =0x7fffffff
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_703
Ltmp11007:
LBB187_702:                             ;   in Loop: Header=BB187_703 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x24, x9
Ltmp11008:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11009:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp11010:
LBB187_703:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_707 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x24
Ltmp11011:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x19, x9, x22, lo
Ltmp11012:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_705
Ltmp11013:
; %bb.704:                              ;   in Loop: Header=BB187_703 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11014:
LBB187_705:                             ;   in Loop: Header=BB187_703 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x19, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11015:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x9
	b.hs	LBB187_702
Ltmp11016:
; %bb.706:                              ;   in Loop: Header=BB187_703 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x21, x24, lsl #2
Ltmp11017:
LBB187_707:                             ;   Parent Loop BB187_703 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w10, [x8], #4
Ltmp11018:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: long_missing_offset:value <- $w10
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d0, w10
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, eq
Ltmp11019:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x19, x19, #1
Ltmp11020:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_707
	b	LBB187_702
Ltmp11021:
LBB187_708:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp11022:
; %bb.709:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x23, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_711
Ltmp11023:
LBB187_710:                             ;   in Loop: Header=BB187_711 Depth=1
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x23, x8
Ltmp11024:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp11025:
	;DEBUG_VALUE: start <- $x23
	b.hs	LBB187_943
Ltmp11026:
LBB187_711:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_715 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x23
Ltmp11027:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp11028:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_713
Ltmp11029:
; %bb.712:                              ;   in Loop: Header=BB187_711 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11030:
LBB187_713:                             ;   in Loop: Header=BB187_711 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp11031:
	;DEBUG_VALUE: i <- $x23
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x23, x8
	b.hs	LBB187_710
Ltmp11032:
; %bb.714:                              ;   in Loop: Header=BB187_711 Depth=1
	;DEBUG_VALUE: i <- $x23
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x23
Ltmp11033:
LBB187_715:                             ;   Parent Loop BB187_711 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x23
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrsb	w10, [x9], #1
Ltmp11034:
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: byte_missing_offset:value <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d0, w10
	fadd	d0, d8, d0
	cmp	w10, #100
	fcsel	d8, d8, d0, gt
Ltmp11035:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x19, x19, #1
Ltmp11036:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_715
	b	LBB187_710
Ltmp11037:
LBB187_716:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11038:
; %bb.717:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65508                     ; =0xffe4
	movk	w22, #32767, lsl #16
	mov	w23, #65536                     ; =0x10000
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_719
Ltmp11039:
LBB187_718:                             ;   in Loop: Header=BB187_719 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x24, x9
Ltmp11040:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11041:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp11042:
LBB187_719:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_723 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x24
Ltmp11043:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x19, x9, x23, lo
Ltmp11044:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_721
Ltmp11045:
; %bb.720:                              ;   in Loop: Header=BB187_719 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11046:
LBB187_721:                             ;   in Loop: Header=BB187_719 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x19, x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11047:
	;DEBUG_VALUE: i <- $x24
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x24, x9
	b.hs	LBB187_718
Ltmp11048:
; %bb.722:                              ;   in Loop: Header=BB187_719 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x21, x24, lsl #2
Ltmp11049:
LBB187_723:                             ;   Parent Loop BB187_719 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w10, [x8], #4
Ltmp11050:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: long_missing_offset:value <- $w10
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d0, w10
	fadd	d0, d8, d0
	cmp	w10, w22
	fcsel	d8, d8, d0, gt
Ltmp11051:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x19, x19, #1
Ltmp11052:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_723
	b	LBB187_718
Ltmp11053:
LBB187_724:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11054:
; %bb.725:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	w23, #32767                     ; =0x7fff
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_727
Ltmp11055:
LBB187_726:                             ;   in Loop: Header=BB187_727 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp11056:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11057:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp11058:
LBB187_727:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_731 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x24
Ltmp11059:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp11060:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_729
Ltmp11061:
; %bb.728:                              ;   in Loop: Header=BB187_727 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11062:
LBB187_729:                             ;   in Loop: Header=BB187_727 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11063:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_726
Ltmp11064:
; %bb.730:                              ;   in Loop: Header=BB187_727 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x24, lsl #1
Ltmp11065:
LBB187_731:                             ;   Parent Loop BB187_727 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w10, [x9], #2
Ltmp11066:
	;DEBUG_VALUE: raw <- $w10
	;DEBUG_VALUE: int_missing_offset:value <- $w10
	sxth	w11, w10
Ltmp11067:
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d0, w11
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, eq
Ltmp11068:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x19, x19, #1
Ltmp11069:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_731
	b	LBB187_726
Ltmp11070:
LBB187_732:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11071:
; %bb.733:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	w23, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_735
Ltmp11072:
LBB187_734:                             ;   in Loop: Header=BB187_735 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11073:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11074:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp11075:
LBB187_735:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_741 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp11076:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x24, x8, x22, lo
Ltmp11077:
	;DEBUG_VALUE: count <- $x24
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_737
Ltmp11078:
; %bb.736:                              ;   in Loop: Header=BB187_735 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11079:
LBB187_737:                             ;   in Loop: Header=BB187_735 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x24, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11080:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_734
Ltmp11081:
; %bb.738:                              ;   in Loop: Header=BB187_735 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #2
	b	LBB187_741
Ltmp11082:
LBB187_739:                             ;   in Loop: Header=BB187_741 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp11083:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp11084:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_740:                             ;   in Loop: Header=BB187_741 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x24, x24, #1
Ltmp11085:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_734
Ltmp11086:
LBB187_741:                             ;   Parent Loop BB187_735 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp11087:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_739
Ltmp11088:
; %bb.742:                              ;   in Loop: Header=BB187_741 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp11089:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s0
	ccmp	w10, w23, #0, vc
	b.le	LBB187_739
	b	LBB187_740
Ltmp11090:
LBB187_743:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11091:
; %bb.744:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x24, #0                         ; =0x0
	mov	w22, #65536                     ; =0x10000
	mov	w23, #32740                     ; =0x7fe4
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_746
Ltmp11092:
LBB187_745:                             ;   in Loop: Header=BB187_746 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp11093:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11094:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB187_1012
Ltmp11095:
LBB187_746:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_750 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x24
Ltmp11096:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x19, x8, x22, lo
Ltmp11097:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_748
Ltmp11098:
; %bb.747:                              ;   in Loop: Header=BB187_746 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11099:
LBB187_748:                             ;   in Loop: Header=BB187_746 Depth=1
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x19, x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11100:
	;DEBUG_VALUE: i <- $x24
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x24, x8
	b.hs	LBB187_745
Ltmp11101:
; %bb.749:                              ;   in Loop: Header=BB187_746 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x19
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x24, lsl #1
Ltmp11102:
LBB187_750:                             ;   Parent Loop BB187_746 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrsh	w10, [x9], #2
Ltmp11103:
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	;DEBUG_VALUE: raw <- undef
	;DEBUG_VALUE: int_missing_offset:value <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d0, w10
	fadd	d0, d8, d0
	cmp	w10, w23
	fcsel	d8, d8, d0, gt
Ltmp11104:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x19, x19, #1
Ltmp11105:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_750
	b	LBB187_745
Ltmp11106:
LBB187_751:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11107:
; %bb.752:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	w22, #12287                     ; =0x2fff
	movk	w22, #33023, lsl #16
	mov	w23, #65536                     ; =0x10000
	movi.2s	v9, #127, lsl #24
	mov	w24, #-53249                    ; =0xffff2fff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_754
Ltmp11108:
LBB187_753:                             ;   in Loop: Header=BB187_754 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11109:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11110:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp11111:
LBB187_754:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_760 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp11112:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x25, x8, x23, lo
Ltmp11113:
	;DEBUG_VALUE: count <- $x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_756
Ltmp11114:
; %bb.755:                              ;   in Loop: Header=BB187_754 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11115:
LBB187_756:                             ;   in Loop: Header=BB187_754 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11116:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_753
Ltmp11117:
; %bb.757:                              ;   in Loop: Header=BB187_754 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x21, x19, lsl #2
	b	LBB187_760
Ltmp11118:
LBB187_758:                             ;   in Loop: Header=BB187_760 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d0, s0
Ltmp11119:
	;DEBUG_VALUE: element <- $d0
	fadd	d8, d8, d0
Ltmp11120:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
LBB187_759:                             ;   in Loop: Header=BB187_760 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x25, x25, #1
Ltmp11121:
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_753
Ltmp11122:
LBB187_760:                             ;   Parent Loop BB187_754 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s0, [x9], #4
Ltmp11123:
	;DEBUG_VALUE: raw <- $s0
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcmp	s0, s9
	b.mi	LBB187_758
Ltmp11124:
; %bb.761:                              ;   in Loop: Header=BB187_760 Depth=2
	;DEBUG_VALUE: raw <- $s0
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: float_missing_offset:value <- $s0
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s0
Ltmp11125:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w11, w10, w22
Ltmp11126:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w10
	.loc	0 0 37 is_stmt 0                ; numeric-payload.c:0:37
	tst	w10, #0x7ff
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ccmp	w11, w24, #0, eq
	cset	w10, lo
Ltmp11127:
	fcmp	s0, s0
	ccmp	w10, #0, #4, vc
	b.ne	LBB187_758
	b	LBB187_759
Ltmp11128:
LBB187_762:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp11129:
; %bb.763:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x25, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #16
	mov	w23, #65536                     ; =0x10000
Lloh1693:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1694:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp11130:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v11, x8
	fmov	d9, x8
	movi.8b	v10, #127
	movi.16b	v12, #127
	str	q11, [sp, #80]                  ; 16-byte Folded Spill
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_765
Ltmp11131:
LBB187_764:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x25, x8
Ltmp11132:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp11133:
	;DEBUG_VALUE: start <- $x25
	b.hs	LBB187_943
Ltmp11134:
LBB187_765:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_773 Depth 2
                                        ;     Child Loop BB187_777 Depth 2
                                        ;     Child Loop BB187_781 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x19, x9, x25
Ltmp11135:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x26, x19, x23, lo
Ltmp11136:
	;DEBUG_VALUE: count <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_767
Ltmp11137:
; %bb.766:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11138:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movi.16b	v12, #127
	ldr	q11, [sp, #80]                  ; 16-byte Folded Reload
Ltmp11139:
LBB187_767:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x26, x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp11140:
	;DEBUG_VALUE: i <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x8
	b.hs	LBB187_764
Ltmp11141:
; %bb.768:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #8
	b.hs	LBB187_770
Ltmp11142:
; %bb.769:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_780
Ltmp11143:
LBB187_770:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_772
Ltmp11144:
; %bb.771:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_776
Ltmp11145:
LBB187_772:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x9, x26, #0x1ffe0
	dup.2d	v1, v0[0]
	add	x10, x22, x25
	mov	x11, x9
Ltmp11146:
LBB187_773:                             ;   Parent Loop BB187_765 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldp	q16, q2, [x10, #-16]
Ltmp11147:
	.loc	0 203 45 is_stmt 1              ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmeq.16b	v18, v16, v12
Ltmp11148:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ext.16b	v7, v16, v16, #8
	mov	b23, v7[6]
Ltmp11149:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.8h	v19, v18, #0
Ltmp11150:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov.b	v23[4], v7[7]
	mov	b3, v7[4]
	mov	b6, v7[2]
	mov.b	v3[4], v7[5]
	mov	b21, v7[0]
	mov	b22, v16[6]
	mov.b	v22[4], v16[7]
	mov.b	v6[4], v7[3]
	mov	b4, v16[4]
	mov.b	v4[4], v16[5]
	mov	b5, v16[2]
	mov.b	v21[4], v7[1]
	mov.b	v5[4], v16[3]
	mov	b7, v16[0]
	mov.b	v7[4], v16[1]
Ltmp11151:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.4s	v17, v19, #0
	sshll2.8h	v28, v18, #0
Ltmp11152:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ext.16b	v26, v2, v2, #8
	mov	b18, v26[6]
	mov.b	v18[4], v26[7]
Ltmp11153:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v25, v19, #0
	sshll.4s	v27, v28, #0
Ltmp11154:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov	b19, v26[4]
	mov.b	v19[4], v26[5]
	mov	b20, v26[2]
Ltmp11155:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v24, v17, #0
Ltmp11156:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov.b	v20[4], v26[3]
	mov	b16, v26[0]
	mov.b	v16[4], v26[1]
Ltmp11157:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v26, v25, #0
	sshll2.4s	v28, v28, #0
	sshll2.2d	v29, v28, #0
Ltmp11158:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v23, v23, #24
	sshr.2s	v23, v23, #24
	sshll.2d	v23, v23, #0
	scvtf.2d	v23, v23
	fadd.2d	v23, v23, v11
	bit.16b	v23, v1, v29
Ltmp11159:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v30, v27, #0
	sshll2.2d	v27, v27, #0
	sshll.2d	v28, v28, #0
Ltmp11160:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v3, v3, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	shl.2s	v6, v6, #24
	sshr.2s	v6, v6, #24
	shl.2s	v21, v21, #24
	sshll.2d	v6, v6, #0
	sshr.2s	v21, v21, #24
	sshll.2d	v21, v21, #0
	shl.2s	v22, v22, #24
	sshr.2s	v22, v22, #24
	sshll.2d	v22, v22, #0
	scvtf.2d	v3, v3
	fadd.2d	v3, v3, v11
	bit.16b	v3, v1, v28
	mov	b29, v2[6]
	mov.b	v29[4], v2[7]
	scvtf.2d	v6, v6
	fadd.2d	v6, v6, v11
	bit.16b	v6, v1, v27
	mov	b28, v2[4]
	mov.b	v28[4], v2[5]
	scvtf.2d	v21, v21
	fadd.2d	v21, v21, v11
	bit.16b	v21, v1, v30
	mov	b27, v2[2]
	mov.b	v27[4], v2[3]
	scvtf.2d	v22, v22
	fadd.2d	v22, v22, v11
	bit.16b	v22, v1, v26
	mov	b26, v2[0]
	mov.b	v26[4], v2[1]
Ltmp11161:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v25, v25, #0
	cmeq.16b	v2, v2, v12
Ltmp11162:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v4, v4, #24
	sshr.2s	v4, v4, #24
	sshll.2d	v4, v4, #0
	scvtf.2d	v4, v4
	fadd.2d	v4, v4, v11
	bit.16b	v4, v1, v25
Ltmp11163:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.8h	v25, v2, #0
	sshll2.8h	v30, v2, #0
Ltmp11164:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v2, v5, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v11
	bsl.16b	v24, v1, v2
Ltmp11165:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v5, v30, #0
Ltmp11166:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v2, v7, #24
Ltmp11167:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v7, v17, #0
Ltmp11168:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v11
	mov.16b	v17, v7
	bsl.16b	v17, v1, v2
Ltmp11169:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v2, v5, #0
Ltmp11170:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v7, v18, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	fadd.2d	v7, v7, v11
	bsl.16b	v2, v1, v7
Ltmp11171:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v31, v25, #0
	sshll.4s	v30, v30, #0
	sshll.2d	v5, v5, #0
Ltmp11172:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v7, v19, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	fadd.2d	v7, v7, v11
	bsl.16b	v5, v1, v7
Ltmp11173:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v7, v30, #0
Ltmp11174:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v18, v20, #24
	sshr.2s	v18, v18, #24
	sshll.2d	v18, v18, #0
	scvtf.2d	v18, v18
	fadd.2d	v18, v18, v11
	bsl.16b	v7, v1, v18
Ltmp11175:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v18, v31, #0
Ltmp11176:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v19, v29, #24
	sshr.2s	v19, v19, #24
	sshll.2d	v19, v19, #0
	scvtf.2d	v19, v19
	fadd.2d	v19, v19, v11
	bsl.16b	v18, v1, v19
Ltmp11177:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v19, v30, #0
Ltmp11178:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v16, v16, #24
	sshr.2s	v16, v16, #24
	sshll.2d	v16, v16, #0
	scvtf.2d	v16, v16
	fadd.2d	v16, v16, v11
	bit.16b	v16, v1, v19
Ltmp11179:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.4s	v19, v25, #0
	sshll.2d	v20, v31, #0
Ltmp11180:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v25, v28, #24
	sshr.2s	v25, v25, #24
	sshll.2d	v25, v25, #0
	scvtf.2d	v25, v25
	fadd.2d	v25, v25, v11
	bsl.16b	v20, v1, v25
Ltmp11181:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v25, v19, #0
Ltmp11182:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v27, v27, #24
	sshr.2s	v27, v27, #24
	sshll.2d	v27, v27, #0
	scvtf.2d	v27, v27
	fadd.2d	v27, v27, v11
	bsl.16b	v25, v1, v27
Ltmp11183:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v19, v19, #0
Ltmp11184:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v26, v26, #24
	sshr.2s	v26, v26, #24
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	fadd.2d	v26, v26, v11
	bsl.16b	v19, v1, v26
	fadd	d26, d8, d17
	mov	d17, v17[1]
	fadd	d17, d26, d17
	fadd	d17, d17, d24
	mov	d24, v24[1]
	fadd	d17, d17, d24
	fadd	d17, d17, d4
	mov	d4, v4[1]
	fadd	d4, d17, d4
	fadd	d4, d4, d22
	mov	d17, v22[1]
	fadd	d4, d4, d17
	fadd	d4, d4, d21
	mov	d17, v21[1]
	fadd	d4, d4, d17
	fadd	d4, d4, d6
	mov	d6, v6[1]
	fadd	d4, d4, d6
	fadd	d4, d4, d3
	mov	d3, v3[1]
	fadd	d3, d4, d3
	fadd	d3, d3, d23
	mov	d4, v23[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d19
	mov	d4, v19[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d25
	mov	d4, v25[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d20
	mov	d4, v20[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d18
	mov	d4, v18[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d16
	mov	d4, v16[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d7
	mov	d4, v7[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d5
	mov	d4, v5[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d8, d3, d2
	add	x10, x10, #32
	subs	x11, x11, #32
	b.ne	LBB187_773
Ltmp11185:
; %bb.774:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x9
	b.eq	LBB187_764
Ltmp11186:
; %bb.775:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x26, #0x18
	b.eq	LBB187_779
Ltmp11187:
LBB187_776:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x11, x26, #0x1fff8
	add	x10, x25, x11
	dup.2d	v1, v0[0]
	add	x12, x9, x25
	add	x12, x21, x12
	sub	x9, x9, x11
Ltmp11188:
LBB187_777:                             ;   Parent Loop BB187_765 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	d2, [x12], #8
Ltmp11189:
	.loc	0 203 45 is_stmt 1              ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmeq.8b	v3, v2, v10
	sshll.8h	v3, v3, #0
	sshll.4s	v4, v3, #0
	sshll.2d	v5, v4, #0
	sshll2.2d	v4, v4, #0
	sshll2.4s	v3, v3, #0
	sshll.2d	v6, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11190:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov	b7, v2[6]
	mov.b	v7[4], v2[7]
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	mov	b16, v2[4]
	mov.b	v16[4], v2[5]
	shl.2s	v16, v16, #24
	sshr.2s	v16, v16, #24
	sshll.2d	v16, v16, #0
	scvtf.2d	v16, v16
	mov	b17, v2[2]
	mov.b	v17[4], v2[3]
	shl.2s	v17, v17, #24
	sshr.2s	v17, v17, #24
	sshll.2d	v17, v17, #0
	scvtf.2d	v17, v17
	mov	b18, v2[0]
	mov.b	v18[4], v2[1]
	shl.2s	v2, v18, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v11
	fadd.2d	v17, v17, v11
	fadd.2d	v16, v16, v11
	fadd.2d	v7, v7, v11
	bsl.16b	v3, v1, v7
	mov	d7, v3[1]
	bsl.16b	v6, v1, v16
	mov	d16, v6[1]
	bsl.16b	v4, v1, v17
	mov	d17, v4[1]
	bit.16b	v2, v1, v5
	mov	d5, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d5
	fadd	d2, d2, d4
	fadd	d2, d2, d17
	fadd	d2, d2, d6
	fadd	d2, d2, d16
	fadd	d2, d2, d3
	fadd	d8, d2, d7
	adds	x9, x9, #8
	b.ne	LBB187_777
Ltmp11191:
; %bb.778:                              ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x11
	b.eq	LBB187_764
	b	LBB187_780
Ltmp11192:
LBB187_779:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x25, x9
Ltmp11193:
LBB187_780:                             ;   in Loop: Header=BB187_765 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x25, x26
	sub	x9, x9, x10
	add	x10, x21, x10
Ltmp11194:
LBB187_781:                             ;   Parent Loop BB187_765 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w11, [x10], #1
Ltmp11195:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: byte_missing_offset:value <- $w11
	sxtb	w12, w11
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
Ltmp11196:
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w12
	fadd	d1, d1, d9
	cmp	w11, #127
	fcsel	d1, d0, d1, eq
Ltmp11197:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11198:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
Ltmp11199:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_781
	b	LBB187_764
Ltmp11200:
LBB187_782:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11201:
; %bb.783:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
Lloh1695:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1696:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x9, #151732604633088            ; =0x8a0000000000
	movk	x9, #49324, lsl #48
	dup.2d	v26, x9
	fmov	d9, x9
	mov	w25, #2147483647                ; =0x7fffffff
	mvni.4s	v27, #128, lsl #24
	str	q26, [sp, #80]                  ; 16-byte Folded Spill
	b	LBB187_785
Ltmp11202:
LBB187_784:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x26, x9
Ltmp11203:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11204:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11205:
LBB187_785:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_793 Depth 2
                                        ;     Child Loop BB187_797 Depth 2
                                        ;     Child Loop BB187_801 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x8, x26
Ltmp11206:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x23, lo
Ltmp11207:
	;DEBUG_VALUE: count <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_787
Ltmp11208:
; %bb.786:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11209:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.4s	v27, #128, lsl #24
	ldr	q26, [sp, #80]                  ; 16-byte Folded Reload
Ltmp11210:
LBB187_787:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x27, x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11211:
	;DEBUG_VALUE: i <- $x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x26, x9
	b.hs	LBB187_784
Ltmp11212:
; %bb.788:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #4
	b.hs	LBB187_790
Ltmp11213:
; %bb.789:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_800
Ltmp11214:
LBB187_790:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_792
Ltmp11215:
; %bb.791:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x8, #0                          ; =0x0
	b	LBB187_796
Ltmp11216:
LBB187_792:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x8, x27, #0x1fff0
	dup.2d	v1, v0[0]
	add	x10, x22, x26, lsl #2
	mov	x11, x8
Ltmp11217:
LBB187_793:                             ;   Parent Loop BB187_785 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp11218:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v6, v2, v27
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmeq.4s	v16, v3, v27
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmeq.4s	v18, v4, v27
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmeq.4s	v20, v5, v27
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp11219:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll2.2d	v22, v2, #0
	scvtf.2d	v22, v22
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	sshll2.2d	v23, v3, #0
	scvtf.2d	v23, v23
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	sshll2.2d	v24, v4, #0
	scvtf.2d	v24, v24
	sshll.2d	v4, v4, #0
	scvtf.2d	v4, v4
	sshll2.2d	v25, v5, #0
	scvtf.2d	v25, v25
	sshll.2d	v5, v5, #0
	scvtf.2d	v5, v5
	fadd.2d	v2, v2, v26
	fadd.2d	v22, v22, v26
	fadd.2d	v3, v3, v26
	fadd.2d	v23, v23, v26
	fadd.2d	v4, v4, v26
	fadd.2d	v24, v24, v26
	fadd.2d	v5, v5, v26
	fadd.2d	v25, v25, v26
	bsl.16b	v6, v1, v22
	mov	d22, v6[1]
	bit.16b	v2, v1, v7
	mov	d7, v2[1]
	bsl.16b	v16, v1, v23
	mov	d23, v16[1]
	bit.16b	v3, v1, v17
	mov	d17, v3[1]
	bsl.16b	v18, v1, v24
	mov	d24, v18[1]
	bit.16b	v4, v1, v19
	mov	d19, v4[1]
	bsl.16b	v20, v1, v25
	mov	d25, v20[1]
	bit.16b	v5, v1, v21
	mov	d21, v5[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d7
	fadd	d2, d2, d6
	fadd	d2, d2, d22
	fadd	d2, d2, d3
	fadd	d2, d2, d17
	fadd	d2, d2, d16
	fadd	d2, d2, d23
	fadd	d2, d2, d4
	fadd	d2, d2, d19
	fadd	d2, d2, d18
	fadd	d2, d2, d24
	fadd	d2, d2, d5
	fadd	d2, d2, d21
	fadd	d2, d2, d20
	fadd	d8, d2, d25
	subs	x11, x11, #16
	b.ne	LBB187_793
Ltmp11220:
; %bb.794:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x8
	b.eq	LBB187_784
Ltmp11221:
; %bb.795:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0xc
	b.eq	LBB187_799
Ltmp11222:
LBB187_796:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x27, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x8, x11
	add	x8, x8, x26
	add	x8, x21, x8, lsl #2
Ltmp11223:
LBB187_797:                             ;   Parent Loop BB187_785 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q2, [x8], #16
Ltmp11224:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v3, v2, v27
	sshll.2d	v4, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11225:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll2.2d	v5, v2, #0
	scvtf.2d	v5, v5
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v26
	fadd.2d	v5, v5, v26
	bsl.16b	v3, v1, v5
	mov	d5, v3[1]
	bit.16b	v2, v1, v4
	mov	d4, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d4
	fadd	d2, d2, d3
	fadd	d8, d2, d5
	adds	x12, x12, #4
	b.ne	LBB187_797
Ltmp11226:
; %bb.798:                              ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x11
	b.eq	LBB187_784
	b	LBB187_800
Ltmp11227:
LBB187_799:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x8
Ltmp11228:
LBB187_800:                             ;   in Loop: Header=BB187_785 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x26, x27
	sub	x8, x8, x10
	add	x10, x21, x10, lsl #2
Ltmp11229:
LBB187_801:                             ;   Parent Loop BB187_785 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp11230:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w11
	fadd	d1, d1, d9
	cmp	w11, w25
	fcsel	d1, d0, d1, eq
Ltmp11231:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11232:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x8, x8, #1
Ltmp11233:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_801
	b	LBB187_784
Ltmp11234:
LBB187_802:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp11235:
; %bb.803:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1697:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1698:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp11236:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_805
Ltmp11237:
LBB187_804:                             ;   in Loop: Header=BB187_805 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11238:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp11239:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_943
Ltmp11240:
LBB187_805:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_809 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x19
Ltmp11241:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x25, x8, x23, lo
Ltmp11242:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_807
Ltmp11243:
; %bb.806:                              ;   in Loop: Header=BB187_805 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11244:
LBB187_807:                             ;   in Loop: Header=BB187_805 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp11245:
	;DEBUG_VALUE: i <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, x8
	b.hs	LBB187_804
Ltmp11246:
; %bb.808:                              ;   in Loop: Header=BB187_805 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x9, x21, x19
Ltmp11247:
LBB187_809:                             ;   Parent Loop BB187_805 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w10, [x9], #1
Ltmp11248:
	;DEBUG_VALUE: raw <- $w10
	sxtb	w11, w10
Ltmp11249:
	;DEBUG_VALUE: byte_missing_offset:value <- $w10
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 204 25 is_stmt 1              ; numeric-payload.c:204:25 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sub	w10, w10, #101
Ltmp11250:
	cmp	w11, #100
	csinv	w10, w10, wzr, gt
Ltmp11251:
	;DEBUG_VALUE: missing <- $w10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d1, w11
	fadd	d1, d1, d9
Ltmp11252:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	add	w11, w10, #96
Ltmp11253:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11254:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	fmov	d2, x11
Ltmp11255:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp11256:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp11257:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11258:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x25, x25, #1
Ltmp11259:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_809
	b	LBB187_804
Ltmp11260:
LBB187_810:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11261:
; %bb.811:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x27, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65508                     ; =0xffe4
	movk	w23, #32767, lsl #16
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x24, x21, #16
	mov	x9, #151732604633088            ; =0x8a0000000000
	movk	x9, #49324, lsl #48
	dup.2d	v26, x9
	mov	w25, #65536                     ; =0x10000
	fmov	d9, x9
Lloh1699:
	adrp	x26, _R_NaReal@GOTPAGE
Lloh1700:
	ldr	x26, [x26, _R_NaReal@GOTPAGEOFF]
	mvni.2s	v0, #27
	fneg.2s	v10, v0
	mvni.2s	v0, #26
	fneg.2s	v11, v0
	movi.2s	v0, #123
	fneg.2s	v12, v0
	dup.2d	v27, x22
	stp	q27, q26, [sp, #64]             ; 32-byte Folded Spill
	b	LBB187_813
Ltmp11262:
LBB187_812:                             ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x27, x9
Ltmp11263:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11264:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB187_1012
Ltmp11265:
LBB187_813:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_819 Depth 2
                                        ;     Child Loop BB187_822 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x8, x27
Ltmp11266:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x28, x19, x25, lo
Ltmp11267:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_815
Ltmp11268:
; %bb.814:                              ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp11269:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q27, q26, [sp, #64]             ; 32-byte Folded Reload
Ltmp11270:
LBB187_815:                             ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x28, x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11271:
	;DEBUG_VALUE: i <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x9
	b.hs	LBB187_812
Ltmp11272:
; %bb.816:                              ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x26]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #8
	b.hs	LBB187_818
Ltmp11273:
; %bb.817:                              ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x8, x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_821
Ltmp11274:
LBB187_818:                             ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	and	x10, x28, #0x1fff8
	add	x8, x27, x10
	dup.2d	v1, v0[0]
	add	x11, x24, x27, lsl #2
	mov	x12, x10
Ltmp11275:
LBB187_819:                             ;   Parent Loop BB187_813 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	d2, d3, [x11, #-16]
	ldp	d4, d5, [x11], #32
Ltmp11276:
	.loc	0 214 41 is_stmt 1              ; numeric-payload.c:214:41 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	smax.2s	v6, v2, v10
	smax.2s	v7, v3, v10
	smax.2s	v16, v4, v10
	smax.2s	v17, v5, v10
Ltmp11277:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v18, v2, #0
	scvtf.2d	v18, v18
	sshll.2d	v19, v3, #0
	scvtf.2d	v19, v19
	sshll.2d	v20, v4, #0
	scvtf.2d	v20, v20
	sshll.2d	v21, v5, #0
	scvtf.2d	v21, v21
	fadd.2d	v18, v18, v26
	fadd.2d	v19, v19, v26
	fadd.2d	v20, v20, v26
	fadd.2d	v21, v21, v26
Ltmp11278:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.2s	v22, v2, v11
	sshll.2d	v22, v22, #0
	cmeq.2s	v23, v3, v11
	sshll.2d	v23, v23, #0
	cmeq.2s	v24, v4, v11
	sshll.2d	v24, v24, #0
	cmeq.2s	v25, v5, v11
	sshll.2d	v25, v25, #0
	cmgt.2s	v2, v2, v11
	sshll.2d	v2, v2, #0
	cmgt.2s	v3, v3, v11
	sshll.2d	v3, v3, #0
	cmgt.2s	v4, v4, v11
	sshll.2d	v4, v4, #0
	cmgt.2s	v5, v5, v11
	sshll.2d	v5, v5, #0
Ltmp11279:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add.2s	v6, v6, v12
	add.2s	v7, v7, v12
	add.2s	v16, v16, v12
	add.2s	v17, v17, v12
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	shll.2d	v6, v6, #32
	shll.2d	v7, v7, #32
	shll.2d	v16, v16, #32
	shll.2d	v17, v17, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	orr.16b	v6, v6, v27
	orr.16b	v7, v7, v27
	orr.16b	v16, v16, v27
	orr.16b	v17, v17, v27
Ltmp11280:
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	bsl.16b	v2, v6, v18
	bit.16b	v2, v1, v22
	mov	d6, v2[1]
	bsl.16b	v3, v7, v19
	bit.16b	v3, v1, v23
	mov	d7, v3[1]
	bsl.16b	v4, v16, v20
	bit.16b	v4, v1, v24
	mov	d16, v4[1]
	bsl.16b	v5, v17, v21
	bit.16b	v5, v1, v25
	mov	d17, v5[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d3
	fadd	d2, d2, d7
	fadd	d2, d2, d4
	fadd	d2, d2, d16
	fadd	d2, d2, d5
	fadd	d8, d2, d17
	subs	x12, x12, #8
	b.ne	LBB187_819
Ltmp11281:
; %bb.820:                              ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x28, x10
	b.eq	LBB187_812
Ltmp11282:
LBB187_821:                             ;   in Loop: Header=BB187_813 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x27, x28
	sub	x10, x10, x8
	add	x8, x21, x8, lsl #2
Ltmp11283:
LBB187_822:                             ;   Parent Loop BB187_813 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x8], #4
Ltmp11284:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	.loc	0 214 41 is_stmt 1              ; numeric-payload.c:214:41 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmp	w11, w23
	csel	w12, w11, w23, gt
Ltmp11285:
	;DEBUG_VALUE: missing <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] $w12
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	scvtf	d1, w11
	fadd	d1, d1, d9
Ltmp11286:
	;DEBUG_VALUE: numeric_missing_value:offset <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] $w12
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w13, w23, #1
	cmp	w11, w13
Ltmp11287:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w12, w23, w12
Ltmp11288:
	add	w12, w12, #151
Ltmp11289:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x12
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	orr	x12, x22, x12, lsl #32
Ltmp11290:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x12
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fmov	d2, x12
Ltmp11291:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fcsel	d2, d0, d2, eq
Ltmp11292:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w11, w23
	fcsel	d1, d1, d2, le
Ltmp11293:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11294:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x10, x10, #1
Ltmp11295:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_822
	b	LBB187_812
Ltmp11296:
LBB187_823:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11297:
; %bb.824:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
Lloh1701:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1702:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp11298:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v29, x8
	fmov	d9, x8
	mov	w25, #32767                     ; =0x7fff
	mvni.8h	v30, #128, lsl #8
	str	q29, [sp, #80]                  ; 16-byte Folded Spill
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_826
Ltmp11299:
LBB187_825:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp11300:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11301:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11302:
LBB187_826:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_834 Depth 2
                                        ;     Child Loop BB187_838 Depth 2
                                        ;     Child Loop BB187_842 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x19, x9, x26
Ltmp11303:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x23, lo
Ltmp11304:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_828
Ltmp11305:
; %bb.827:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11306:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.8h	v30, #128, lsl #8
	ldr	q29, [sp, #80]                  ; 16-byte Folded Reload
Ltmp11307:
LBB187_828:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11308:
	;DEBUG_VALUE: i <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x26, x8
	b.hs	LBB187_825
Ltmp11309:
; %bb.829:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #8
	b.hs	LBB187_831
Ltmp11310:
; %bb.830:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_841
Ltmp11311:
LBB187_831:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_833
Ltmp11312:
; %bb.832:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_837
Ltmp11313:
LBB187_833:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x9, x27, #0x1ffe0
	dup.2d	v1, v0[0]
	add	x10, x22, x26, lsl #1
	mov	x11, x9
Ltmp11314:
LBB187_834:                             ;   Parent Loop BB187_826 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldp	q23, q6, [x10, #-32]
	ldp	q3, q2, [x10]
Ltmp11315:
	.loc	0 208 45 is_stmt 1              ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v4, v23, v30
	sshll.4s	v5, v4, #0
	sshll.2d	v20, v5, #0
	sshll2.2d	v21, v5, #0
	sshll2.4s	v4, v4, #0
	sshll.2d	v25, v4, #0
	sshll2.2d	v22, v4, #0
	cmeq.8h	v4, v6, v30
	sshll.4s	v5, v4, #0
	sshll.2d	v7, v5, #0
	sshll2.2d	v17, v5, #0
	sshll2.4s	v4, v4, #0
	sshll.2d	v19, v4, #0
	sshll2.2d	v24, v4, #0
	cmeq.8h	v16, v3, v30
	sshll.4s	v5, v16, #0
	sshll.2d	v4, v5, #0
	sshll2.2d	v5, v5, #0
	sshll2.4s	v18, v16, #0
	sshll.2d	v16, v18, #0
	sshll2.2d	v18, v18, #0
Ltmp11316:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll2.4s	v26, v23, #0
	sshll2.2d	v27, v26, #0
	scvtf.2d	v27, v27
	fadd.2d	v27, v27, v29
	bsl.16b	v22, v1, v27
Ltmp11317:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v27, v2, v30
Ltmp11318:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	sshll.4s	v28, v23, #0
	fadd.2d	v23, v26, v29
	bit.16b	v23, v1, v25
	sshll2.2d	v25, v28, #0
	scvtf.2d	v25, v25
	sshll.2d	v26, v28, #0
	scvtf.2d	v26, v26
	fadd.2d	v25, v25, v29
	bsl.16b	v21, v1, v25
	sshll2.4s	v28, v6, #0
	fadd.2d	v25, v26, v29
	bit.16b	v25, v1, v20
	sshll2.2d	v20, v28, #0
	scvtf.2d	v20, v20
	fadd.2d	v20, v20, v29
	bit.16b	v20, v1, v24
Ltmp11319:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll.4s	v24, v27, #0
	sshll2.4s	v26, v27, #0
Ltmp11320:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v27, v28, #0
	scvtf.2d	v27, v27
	sshll.4s	v28, v6, #0
	fadd.2d	v6, v27, v29
	bit.16b	v6, v1, v19
	sshll2.2d	v19, v28, #0
	scvtf.2d	v19, v19
	sshll.2d	v27, v28, #0
	scvtf.2d	v27, v27
	fadd.2d	v19, v19, v29
	bsl.16b	v17, v1, v19
	sshll2.4s	v28, v3, #0
	fadd.2d	v19, v27, v29
	bit.16b	v19, v1, v7
	sshll2.2d	v7, v28, #0
	scvtf.2d	v7, v7
	fadd.2d	v7, v7, v29
	bit.16b	v7, v1, v18
Ltmp11321:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll2.2d	v18, v26, #0
Ltmp11322:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v27, v28, #0
	scvtf.2d	v27, v27
	sshll.4s	v28, v3, #0
	fadd.2d	v3, v27, v29
	bit.16b	v3, v1, v16
	sshll2.2d	v16, v28, #0
	scvtf.2d	v16, v16
	sshll.2d	v27, v28, #0
	scvtf.2d	v27, v27
	fadd.2d	v16, v16, v29
	bsl.16b	v5, v1, v16
	sshll2.4s	v16, v2, #0
	fadd.2d	v27, v27, v29
	bit.16b	v27, v1, v4
	sshll2.2d	v4, v16, #0
	scvtf.2d	v4, v4
	fadd.2d	v4, v4, v29
	bit.16b	v4, v1, v18
Ltmp11323:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll2.2d	v18, v24, #0
	sshll.2d	v26, v26, #0
Ltmp11324:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v16, v16, #0
	scvtf.2d	v16, v16
	sshll.4s	v2, v2, #0
	fadd.2d	v16, v16, v29
	bit.16b	v16, v1, v26
	sshll2.2d	v26, v2, #0
	scvtf.2d	v26, v26
	fadd.2d	v26, v26, v29
	bsl.16b	v18, v1, v26
Ltmp11325:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll.2d	v24, v24, #0
Ltmp11326:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v29
	bit.16b	v2, v1, v24
	fadd	d24, d8, d25
	mov	d25, v25[1]
	fadd	d24, d24, d25
	fadd	d24, d24, d21
	mov	d21, v21[1]
	fadd	d21, d24, d21
	fadd	d21, d21, d23
	mov	d23, v23[1]
	fadd	d21, d21, d23
	fadd	d21, d21, d22
	mov	d22, v22[1]
	fadd	d21, d21, d22
	fadd	d21, d21, d19
	mov	d19, v19[1]
	fadd	d19, d21, d19
	fadd	d19, d19, d17
	mov	d17, v17[1]
	fadd	d17, d19, d17
	fadd	d17, d17, d6
	mov	d6, v6[1]
	fadd	d6, d17, d6
	fadd	d6, d6, d20
	mov	d17, v20[1]
	fadd	d6, d6, d17
	fadd	d6, d6, d27
	mov	d17, v27[1]
	fadd	d6, d6, d17
	fadd	d6, d6, d5
	mov	d5, v5[1]
	fadd	d5, d6, d5
	fadd	d5, d5, d3
	mov	d3, v3[1]
	fadd	d3, d5, d3
	fadd	d3, d3, d7
	mov	d5, v7[1]
	fadd	d3, d3, d5
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d2, d3, d2
	fadd	d2, d2, d18
	mov	d3, v18[1]
	fadd	d2, d2, d3
	fadd	d2, d2, d16
	mov	d3, v16[1]
	fadd	d2, d2, d3
	fadd	d2, d2, d4
	mov	d3, v4[1]
	fadd	d8, d2, d3
	add	x10, x10, #64
	subs	x11, x11, #32
	b.ne	LBB187_834
Ltmp11327:
; %bb.835:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x9
	b.eq	LBB187_825
Ltmp11328:
; %bb.836:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0x18
	b.eq	LBB187_840
Ltmp11329:
LBB187_837:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x11, x27, #0x1fff8
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #1
Ltmp11330:
LBB187_838:                             ;   Parent Loop BB187_826 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	q2, [x9], #16
Ltmp11331:
	.loc	0 208 45 is_stmt 1              ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v3, v2, v30
	sshll.4s	v4, v3, #0
	sshll.2d	v5, v4, #0
	sshll2.2d	v4, v4, #0
	sshll2.4s	v3, v3, #0
	sshll.2d	v6, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11332:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll2.4s	v7, v2, #0
	sshll2.2d	v16, v7, #0
	scvtf.2d	v16, v16
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	sshll.4s	v2, v2, #0
	sshll2.2d	v17, v2, #0
	scvtf.2d	v17, v17
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	fadd.2d	v2, v2, v29
	fadd.2d	v17, v17, v29
	fadd.2d	v7, v7, v29
	fadd.2d	v16, v16, v29
	bsl.16b	v3, v1, v16
	mov	d16, v3[1]
	bsl.16b	v6, v1, v7
	mov	d7, v6[1]
	bsl.16b	v4, v1, v17
	mov	d17, v4[1]
	bit.16b	v2, v1, v5
	mov	d5, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d5
	fadd	d2, d2, d4
	fadd	d2, d2, d17
	fadd	d2, d2, d6
	fadd	d2, d2, d7
	fadd	d2, d2, d3
	fadd	d8, d2, d16
	adds	x12, x12, #8
	b.ne	LBB187_838
Ltmp11333:
; %bb.839:                              ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x11
	b.eq	LBB187_825
	b	LBB187_841
Ltmp11334:
LBB187_840:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x9
Ltmp11335:
LBB187_841:                             ;   in Loop: Header=BB187_826 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #1
Ltmp11336:
LBB187_842:                             ;   Parent Loop BB187_826 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w11, [x10], #2
Ltmp11337:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: int_missing_offset:value <- $w11
	sxth	w12, w11
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
Ltmp11338:
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w12
	fadd	d1, d1, d9
	cmp	w11, w25
	fcsel	d1, d0, d1, eq
Ltmp11339:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11340:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
Ltmp11341:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_842
	b	LBB187_825
Ltmp11342:
LBB187_843:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11343:
; %bb.844:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	mov	w22, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x23, x21, #32
Lloh1703:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1704:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	w25, #65536                     ; =0x10000
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp11344:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movk	x8, #49324, lsl #48
	dup.2d	v26, x8
	fmov	d9, x8
	mvni.4s	v27, #129, lsl #24
	str	q26, [sp, #80]                  ; 16-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_846
Ltmp11345:
LBB187_845:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp11346:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11347:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11348:
LBB187_846:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_854 Depth 2
                                        ;     Child Loop BB187_858 Depth 2
                                        ;     Child Loop BB187_862 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x26
Ltmp11349:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x25, lo
Ltmp11350:
	;DEBUG_VALUE: count <- $x27
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_848
Ltmp11351:
; %bb.847:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11352:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.4s	v27, #129, lsl #24
	ldr	q26, [sp, #80]                  ; 16-byte Folded Reload
Ltmp11353:
LBB187_848:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11354:
	;DEBUG_VALUE: i <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x26, x8
	b.hs	LBB187_845
Ltmp11355:
; %bb.849:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #4
	b.hs	LBB187_851
Ltmp11356:
; %bb.850:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_861
Ltmp11357:
LBB187_851:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_853
Ltmp11358:
; %bb.852:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_857
Ltmp11359:
LBB187_853:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x27, #0x1fff0
	dup.2d	v1, v0[0]
	add	x10, x23, x26, lsl #2
	mov	x11, x9
Ltmp11360:
LBB187_854:                             ;   Parent Loop BB187_846 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp11361:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.4s	v6, v2, v27
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmgt.4s	v16, v3, v27
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmgt.4s	v18, v4, v27
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmgt.4s	v20, v5, v27
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp11362:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v22.2d, v2.4s
	fcvtl	v2.2d, v2.2s
	fcvtl2	v23.2d, v3.4s
	fcvtl	v3.2d, v3.2s
	fcvtl2	v24.2d, v4.4s
	fcvtl	v4.2d, v4.2s
	fcvtl2	v25.2d, v5.4s
	fcvtl	v5.2d, v5.2s
	fadd.2d	v2, v2, v26
	fadd.2d	v22, v22, v26
	fadd.2d	v3, v3, v26
	fadd.2d	v23, v23, v26
	fadd.2d	v4, v4, v26
	fadd.2d	v24, v24, v26
	fadd.2d	v5, v5, v26
	fadd.2d	v25, v25, v26
	bsl.16b	v6, v1, v22
	mov	d22, v6[1]
	bit.16b	v2, v1, v7
	mov	d7, v2[1]
	bsl.16b	v16, v1, v23
	mov	d23, v16[1]
	bit.16b	v3, v1, v17
	mov	d17, v3[1]
	bsl.16b	v18, v1, v24
	mov	d24, v18[1]
	bit.16b	v4, v1, v19
	mov	d19, v4[1]
	bsl.16b	v20, v1, v25
	mov	d25, v20[1]
	bit.16b	v5, v1, v21
	mov	d21, v5[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d7
	fadd	d2, d2, d6
	fadd	d2, d2, d22
	fadd	d2, d2, d3
	fadd	d2, d2, d17
	fadd	d2, d2, d16
	fadd	d2, d2, d23
	fadd	d2, d2, d4
	fadd	d2, d2, d19
	fadd	d2, d2, d18
	fadd	d2, d2, d24
	fadd	d2, d2, d5
	fadd	d2, d2, d21
	fadd	d2, d2, d20
	fadd	d8, d2, d25
	subs	x11, x11, #16
	b.ne	LBB187_854
Ltmp11363:
; %bb.855:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x9
	b.eq	LBB187_845
Ltmp11364:
; %bb.856:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0xc
	b.eq	LBB187_860
Ltmp11365:
LBB187_857:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x27, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #2
Ltmp11366:
LBB187_858:                             ;   Parent Loop BB187_846 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q2, [x9], #16
Ltmp11367:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.4s	v3, v2, v27
	sshll.2d	v4, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11368:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v5.2d, v2.4s
	fcvtl	v2.2d, v2.2s
	fadd.2d	v2, v2, v26
	fadd.2d	v5, v5, v26
	bsl.16b	v3, v1, v5
	mov	d5, v3[1]
	bit.16b	v2, v1, v4
	mov	d4, v2[1]
	fadd	d2, d8, d2
	fadd	d2, d2, d4
	fadd	d2, d2, d3
	fadd	d8, d2, d5
	adds	x12, x12, #4
	b.ne	LBB187_858
Ltmp11369:
; %bb.859:                              ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x11
	b.eq	LBB187_845
	b	LBB187_861
Ltmp11370:
LBB187_860:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x9
Ltmp11371:
LBB187_861:                             ;   in Loop: Header=BB187_846 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp11372:
LBB187_862:                             ;   Parent Loop BB187_846 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s1, [x10], #4
Ltmp11373:
	;DEBUG_VALUE: raw <- $s1
	fcvt	d2, s1
Ltmp11374:
	;DEBUG_VALUE: float_missing_offset:value <- $s1
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w11, s1
Ltmp11375:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: float_missing_offset:value <- $w11
	;DEBUG_VALUE: float_missing_offset:bits <- $w11
	;DEBUG_VALUE: missing <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d1, d2, d9
	cmp	w11, w22
	fcsel	d1, d0, d1, gt
Ltmp11376:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11377:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp11378:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.ne	LBB187_862
	b	LBB187_845
Ltmp11379:
LBB187_863:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11380:
; %bb.864:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x28, #0                         ; =0x0
Ltmp11381:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1705:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1706:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	w25, #-32741                    ; =0xffff801b
	mov	w26, #32740                     ; =0x7fe4
	mov	x8, #151732604633088            ; =0x8a0000000000
Ltmp11382:
	movk	x8, #49324, lsl #48
	fmov	d9, x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_866
Ltmp11383:
LBB187_865:                             ;   in Loop: Header=BB187_866 Depth=1
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x28, x8
Ltmp11384:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11385:
	;DEBUG_VALUE: start <- $x28
	b.hs	LBB187_1012
Ltmp11386:
LBB187_866:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_870 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x28
Ltmp11387:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp11388:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_868
Ltmp11389:
; %bb.867:                              ;   in Loop: Header=BB187_866 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp11390:
LBB187_868:                             ;   in Loop: Header=BB187_866 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11391:
	;DEBUG_VALUE: i <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x28, x8
	b.hs	LBB187_865
Ltmp11392:
; %bb.869:                              ;   in Loop: Header=BB187_866 Depth=1
	;DEBUG_VALUE: i <- $x28
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x9, x21, x28, lsl #1
Ltmp11393:
LBB187_870:                             ;   Parent Loop BB187_866 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w10, [x9], #2
Ltmp11394:
	;DEBUG_VALUE: raw <- $w10
	sxth	w11, w10
Ltmp11395:
	;DEBUG_VALUE: int_missing_offset:value <- $w10
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 209 27 is_stmt 1              ; numeric-payload.c:209:27 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w10, w10, w25
Ltmp11396:
	cmp	w11, w26
	csinv	w10, w10, wzr, gt
Ltmp11397:
	;DEBUG_VALUE: missing <- $w10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d1, w11
	fadd	d1, d1, d9
Ltmp11398:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w11, w10, #96
Ltmp11399:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11400:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	fmov	d2, x11
Ltmp11401:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp11402:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp11403:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11404:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x27, x27, #1
Ltmp11405:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_870
	b	LBB187_865
Ltmp11406:
LBB187_871:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11407:
; %bb.872:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #-2130706432               ; =0x81000000
	mov	w24, #12287                     ; =0x2fff
	movk	w24, #33023, lsl #16
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x8, x21, #32
Ltmp11408:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	str	x8, [sp, #32]                   ; 8-byte Folded Spill
	mov	w13, #65536                     ; =0x10000
	movi.4s	v31, #129, lsl #24
	mov	w8, #53249                      ; =0xd001
	dup.4s	v9, w8
	mov	w28, #-53249                    ; =0xffff2fff
Ltmp11409:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	mov	x25, #151732604633088           ; =0x8a0000000000
	movk	x25, #49324, lsl #48
	movi.4s	v10, #7, msl #8
	dup.2d	v11, x22
	dup.2d	v12, x25
	stp	q11, q9, [sp, #64]              ; 32-byte Folded Spill
	str	q12, [sp, #48]                  ; 16-byte Folded Spill
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_874
Ltmp11410:
LBB187_873:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp11411:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11412:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11413:
LBB187_874:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_882 Depth 2
                                        ;     Child Loop BB187_886 Depth 2
                                        ;     Child Loop BB187_892 Depth 2
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x26
Ltmp11414:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x13, lo
Ltmp11415:
	;DEBUG_VALUE: count <- $x27
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_876
Ltmp11416:
; %bb.875:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp11417:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldp	q12, q11, [sp, #48]             ; 32-byte Folded Reload
	movi.4s	v10, #7, msl #8
	ldr	q9, [sp, #80]                   ; 16-byte Folded Reload
	movi.4s	v31, #129, lsl #24
	mov	w13, #65536                     ; =0x10000
Ltmp11418:
LBB187_876:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11419:
	;DEBUG_VALUE: i <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x26, x8
	b.hs	LBB187_873
Ltmp11420:
; %bb.877:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
Lloh1707:
	adrp	x9, _R_NaReal@GOTPAGE
Lloh1708:
	ldr	x9, [x9, _R_NaReal@GOTPAGEOFF]
Lloh1709:
	ldr	d0, [x9]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #4
	b.hs	LBB187_879
Ltmp11421:
; %bb.878:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_889
Ltmp11422:
LBB187_879:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	cmp	x19, #16
	b.hs	LBB187_881
Ltmp11423:
; %bb.880:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_885
Ltmp11424:
LBB187_881:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x27, #0x1fff0
	dup.2d	v1, v0[0]
	ldr	x10, [sp, #32]                  ; 8-byte Folded Reload
	add	x10, x10, x26, lsl #2
	mov	x11, x9
Ltmp11425:
LBB187_882:                             ;   Parent Loop BB187_874 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q23, q20, [x10, #-32]
	ldp	q6, q2, [x10]
Ltmp11426:
	.loc	0 225 37 is_stmt 1              ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add.4s	v5, v23, v31
	cmhi.4s	v3, v9, v5
	add.4s	v7, v20, v31
	cmhi.4s	v16, v9, v7
	add.4s	v17, v6, v31
	cmhi.4s	v18, v9, v17
	add.4s	v19, v2, v31
Ltmp11427:
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.16b	v4, v23, v10
	and.16b	v21, v20, v10
Ltmp11428:
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmhi.4s	v24, v9, v19
Ltmp11429:
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.16b	v22, v6, v10
	and.16b	v25, v2, v10
	.loc	0 229 41 is_stmt 0              ; numeric-payload.c:229:41 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v26, v4, #0
	cmeq.4s	v21, v21, #0
	cmeq.4s	v27, v22, #0
	cmeq.4s	v28, v25, #0
	.loc	0 229 12                        ; numeric-payload.c:229:12 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ushr.4s	v29, v5, #11
	ushr.4s	v25, v7, #11
	ushr.4s	v22, v17, #11
	ushr.4s	v4, v19, #11
	and.16b	v3, v3, v26
	xtn.4h	v3, v3
	and.16b	v21, v16, v21
	and.16b	v26, v18, v27
Ltmp11430:
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v5, v5, #0
	xtn.4h	v5, v5
	cmeq.4s	v7, v7, #0
	and.16b	v24, v24, v28
	xtn.4h	v7, v7
	cmeq.4s	v16, v17, #0
	xtn.4h	v16, v16
	cmeq.4s	v17, v19, #0
	xtn.4h	v17, v17
	xtn.4h	v18, v21
	bic.8b	v21, v3, v5
Ltmp11431:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.4s	v29, #96
	orr.4s	v25, #96
	orr.4s	v22, #96
	orr.4s	v4, #96
	xtn.4h	v19, v26
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v29, #32
	shll2.2d	v27, v29, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v26, v26, v11
Ltmp11432:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v28.2d, v23.2s
	fadd.2d	v28, v28, v12
	ushll.4s	v29, v21, #0
	ushll.2d	v21, v29, #0
	shl.2d	v21, v21, #63
	cmlt.2d	v21, v21, #0
	bsl.16b	v21, v26, v28
Ltmp11433:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v25, #32
Ltmp11434:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v28, v18, v7
Ltmp11435:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll2.2d	v30, v25, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v25, v27, v11
	orr.16b	v26, v26, v11
Ltmp11436:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v23.2d, v23.4s
	fadd.2d	v23, v23, v12
	ushll2.2d	v27, v29, #0
	shl.2d	v27, v27, #63
	cmlt.2d	v27, v27, #0
	bit.16b	v23, v25, v27
	fcvtl	v25.2d, v20.2s
	fadd.2d	v25, v25, v12
	ushll.4s	v27, v28, #0
	ushll.2d	v28, v27, #0
	shl.2d	v28, v28, #63
	cmlt.2d	v28, v28, #0
	bit.16b	v25, v26, v28
Ltmp11437:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v26, v22, #32
	xtn.4h	v24, v24
	shll2.2d	v28, v22, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v22, v30, v11
Ltmp11438:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v20.2d, v20.4s
	fcvtl	v29.2d, v6.2s
	fadd.2d	v20, v20, v12
Ltmp11439:
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v26, v26, v11
Ltmp11440:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd.2d	v29, v29, v12
	ushll2.2d	v27, v27, #0
	shl.2d	v27, v27, #63
	cmlt.2d	v27, v27, #0
	bit.16b	v20, v22, v27
Ltmp11441:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v22, v19, v16
Ltmp11442:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ushll.4s	v27, v22, #0
	ushll.2d	v22, v27, #0
	shl.2d	v22, v22, #63
	cmlt.2d	v22, v22, #0
	bsl.16b	v22, v26, v29
Ltmp11443:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	bic.8b	v26, v24, v17
Ltmp11444:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v29, v4, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v28, v28, v11
	orr.16b	v29, v29, v11
Ltmp11445:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v6.2d, v6.4s
	fadd.2d	v6, v6, v12
	ushll2.2d	v27, v27, #0
	shl.2d	v27, v27, #63
	cmlt.2d	v27, v27, #0
	bit.16b	v6, v28, v27
	fcvtl	v27.2d, v2.2s
	fadd.2d	v27, v27, v12
	ushll.4s	v26, v26, #0
	ushll.2d	v28, v26, #0
	shl.2d	v28, v28, #63
	cmlt.2d	v28, v28, #0
	bit.16b	v27, v29, v28
Ltmp11446:
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll2.2d	v4, v4, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v4, v4, v11
Ltmp11447:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl2	v2.2d, v2.4s
	fadd.2d	v2, v2, v12
	ushll2.2d	v26, v26, #0
	shl.2d	v26, v26, #63
	cmlt.2d	v26, v26, #0
	bit.16b	v2, v4, v26
Ltmp11448:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.8b	v3, v3, v5
	and.8b	v4, v18, v7
	and.8b	v5, v19, v16
	and.8b	v7, v24, v17
Ltmp11449:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ushll.4s	v3, v3, #0
	ushll2.2d	v16, v3, #0
	shl.2d	v16, v16, #63
	cmlt.2d	v16, v16, #0
	bsl.16b	v16, v1, v23
	ushll.2d	v3, v3, #0
	shl.2d	v3, v3, #63
	cmlt.2d	v3, v3, #0
	bsl.16b	v3, v1, v21
	ushll.4s	v4, v4, #0
	ushll2.2d	v17, v4, #0
	shl.2d	v17, v17, #63
	cmlt.2d	v17, v17, #0
	bsl.16b	v17, v1, v20
	ushll.2d	v4, v4, #0
	shl.2d	v4, v4, #63
	cmlt.2d	v4, v4, #0
	bsl.16b	v4, v1, v25
	ushll.4s	v5, v5, #0
	ushll2.2d	v18, v5, #0
	shl.2d	v18, v18, #63
	cmlt.2d	v18, v18, #0
	bit.16b	v6, v1, v18
	ushll.2d	v5, v5, #0
	shl.2d	v5, v5, #63
	cmlt.2d	v5, v5, #0
	bsl.16b	v5, v1, v22
	ushll.4s	v7, v7, #0
	ushll2.2d	v18, v7, #0
	shl.2d	v18, v18, #63
	cmlt.2d	v18, v18, #0
	bit.16b	v2, v1, v18
	ushll.2d	v7, v7, #0
	shl.2d	v7, v7, #63
	cmlt.2d	v7, v7, #0
	bsl.16b	v7, v1, v27
	fadd	d18, d8, d3
	mov	d3, v3[1]
	fadd	d3, d18, d3
	fadd	d3, d3, d16
	mov	d16, v16[1]
	fadd	d3, d3, d16
	fadd	d3, d3, d4
	mov	d4, v4[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d17
	mov	d4, v17[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d5
	mov	d4, v5[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d6
	mov	d4, v6[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d7
	mov	d4, v7[1]
	fadd	d3, d3, d4
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d8, d3, d2
	add	x10, x10, #64
	subs	x11, x11, #16
	b.ne	LBB187_882
Ltmp11450:
; %bb.883:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x9
	b.eq	LBB187_873
Ltmp11451:
; %bb.884:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	tst	x27, #0xc
	b.eq	LBB187_888
Ltmp11452:
LBB187_885:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x27, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #2
Ltmp11453:
LBB187_886:                             ;   Parent Loop BB187_874 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q2, [x9], #16
Ltmp11454:
	.loc	0 225 37 is_stmt 1              ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add.4s	v3, v2, v31
	cmhi.4s	v4, v9, v3
Ltmp11455:
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.16b	v5, v2, v10
	.loc	0 229 41 is_stmt 0              ; numeric-payload.c:229:41 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v5, v5, #0
	.loc	0 229 12                        ; numeric-payload.c:229:12 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	ushr.4s	v6, v3, #11
	and.16b	v4, v4, v5
	xtn.4h	v4, v4
Ltmp11456:
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmeq.4s	v3, v3, #0
	xtn.4h	v3, v3
	bic.8b	v5, v4, v3
Ltmp11457:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.4s	v6, #96
	.loc	0 236 60                        ; numeric-payload.c:236:60 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	shll.2d	v7, v6, #32
	shll2.2d	v6, v6, #32
	.loc	0 236 50 is_stmt 0              ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr.16b	v6, v6, v11
	orr.16b	v7, v7, v11
Ltmp11458:
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v16.2d, v2.2s
	fcvtl2	v2.2d, v2.4s
	fadd.2d	v2, v2, v12
	fadd.2d	v16, v16, v12
Ltmp11459:
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and.8b	v3, v4, v3
Ltmp11460:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ushll.4s	v4, v5, #0
	ushll.2d	v5, v4, #0
	shl.2d	v5, v5, #63
	cmlt.2d	v5, v5, #0
	bsl.16b	v5, v7, v16
	ushll2.2d	v4, v4, #0
	shl.2d	v4, v4, #63
	cmlt.2d	v4, v4, #0
	bit.16b	v2, v6, v4
	ushll.4s	v3, v3, #0
	ushll2.2d	v4, v3, #0
	shl.2d	v4, v4, #63
	cmlt.2d	v4, v4, #0
	bit.16b	v2, v1, v4
	mov	d4, v2[1]
	ushll.2d	v3, v3, #0
	shl.2d	v3, v3, #63
	cmlt.2d	v3, v3, #0
	bsl.16b	v3, v1, v5
	mov	d5, v3[1]
	fadd	d3, d8, d3
	fadd	d3, d3, d5
	fadd	d2, d3, d2
	fadd	d8, d2, d4
	adds	x12, x12, #4
	b.ne	LBB187_886
Ltmp11461:
; %bb.887:                              ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x11
	b.eq	LBB187_873
	b	LBB187_889
Ltmp11462:
LBB187_888:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x10, x26, x9
Ltmp11463:
LBB187_889:                             ;   in Loop: Header=BB187_874 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
	b	LBB187_892
Ltmp11464:
LBB187_890:                             ;   in Loop: Header=BB187_892 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: missing <- -1
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d1, s1
Ltmp11465:
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	fmov	d2, x25
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d1, d1, d2
Ltmp11466:
LBB187_891:                             ;   in Loop: Header=BB187_892 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: element <- $d1
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d8, d8, d1
Ltmp11467:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp11468:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_873
Ltmp11469:
LBB187_892:                             ;   Parent Loop BB187_874 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s1, [x10], #4
Ltmp11470:
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: float_missing_offset:value <- $s1
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w11, s1
Ltmp11471:
	;DEBUG_VALUE: float_missing_offset:bits <- $w11
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w12, w11, w24
	cmp	w12, w28
Ltmp11472:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w11
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and	w12, w11, #0x7ff
	ccmp	w12, #0, #0, hs
	b.ne	LBB187_890
Ltmp11473:
; %bb.893:                              ;   in Loop: Header=BB187_892 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 18 is_stmt 0                ; numeric-payload.c:0:18
	mov.16b	v1, v0
Ltmp11474:
	add	w11, w11, w23
Ltmp11475:
	;DEBUG_VALUE: missing <- undef
	;DEBUG_VALUE: numeric_missing_value:offset <- undef
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cbz	w11, LBB187_891
Ltmp11476:
; %bb.894:                              ;   in Loop: Header=BB187_892 Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 0 is_stmt 0                 ; numeric-payload.c:0 @[ numeric-payload.c:1833:25 ]
	lsr	w11, w11, #11
Ltmp11477:
	;DEBUG_VALUE: missing <- $w11
	;DEBUG_VALUE: numeric_missing_value:offset <- $w11
	.loc	0 235 48 is_stmt 1              ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	w11, w11, #0x60
Ltmp11478:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11479:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	d1, x11
Ltmp11480:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d1
	;DEBUG_VALUE: numeric_missing_value:value <- $d1
	.loc	0 0 5 is_stmt 0                 ; numeric-payload.c:0:5
	b	LBB187_891
Ltmp11481:
LBB187_895:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp11482:
; %bb.896:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x25, #0                         ; =0x0
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x22, x21, #16
	mov	w23, #65536                     ; =0x10000
Lloh1710:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1711:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	movi.8b	v9, #127
	movi.16b	v10, #127
	b	LBB187_898
Ltmp11483:
LBB187_897:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x25, x8
Ltmp11484:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp11485:
	;DEBUG_VALUE: start <- $x25
	b.hs	LBB187_943
Ltmp11486:
LBB187_898:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_906 Depth 2
                                        ;     Child Loop BB187_910 Depth 2
                                        ;     Child Loop BB187_914 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x19, x9, x25
Ltmp11487:
	;DEBUG_VALUE: count <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x26, x19, x23, lo
Ltmp11488:
	;DEBUG_VALUE: count <- $x26
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_900
Ltmp11489:
; %bb.899:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11490:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	movi.16b	v10, #127
Ltmp11491:
LBB187_900:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x26, x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp11492:
	;DEBUG_VALUE: i <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x25, x8
	b.hs	LBB187_897
Ltmp11493:
; %bb.901:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, #8
	b.hs	LBB187_903
Ltmp11494:
; %bb.902:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_913
Ltmp11495:
LBB187_903:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_905
Ltmp11496:
; %bb.904:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_909
Ltmp11497:
LBB187_905:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x9, x26, #0x1ffe0
	dup.2d	v1, v0[0]
	add	x10, x22, x25
	mov	x11, x9
Ltmp11498:
LBB187_906:                             ;   Parent Loop BB187_898 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldp	q6, q2, [x10, #-16]
Ltmp11499:
	.loc	0 203 45 is_stmt 1              ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmeq.16b	v7, v6, v10
	sshll.8h	v16, v7, #0
Ltmp11500:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ext.16b	v17, v6, v6, #8
	mov	b3, v17[0]
	mov.b	v3[4], v17[1]
	mov	b4, v17[2]
	mov.b	v4[4], v17[3]
	mov	b5, v17[4]
	mov.b	v5[4], v17[5]
	mov	b26, v17[6]
	mov	b19, v6[0]
	mov.b	v19[4], v6[1]
	mov.b	v26[4], v17[7]
Ltmp11501:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.4s	v18, v16, #0
Ltmp11502:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov	b20, v6[2]
	mov.b	v20[4], v6[3]
	mov	b22, v6[4]
Ltmp11503:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v16, v16, #0
Ltmp11504:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov.b	v22[4], v6[5]
	mov	b25, v6[6]
	mov.b	v25[4], v6[7]
Ltmp11505:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v17, v18, #0
	sshll2.8h	v28, v7, #0
Ltmp11506:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ext.16b	v29, v2, v2, #8
	mov	b6, v29[0]
	mov.b	v6[4], v29[1]
Ltmp11507:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v23, v18, #0
	sshll.4s	v21, v28, #0
Ltmp11508:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov	b7, v29[2]
	mov.b	v7[4], v29[3]
	mov	b18, v29[4]
Ltmp11509:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v27, v16, #0
Ltmp11510:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov.b	v18[4], v29[5]
	mov	b24, v29[6]
	mov.b	v24[4], v29[7]
Ltmp11511:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v29, v16, #0
	sshll2.4s	v28, v28, #0
	sshll2.2d	v16, v28, #0
Ltmp11512:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v26, v26, #24
	sshr.2s	v26, v26, #24
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	bsl.16b	v16, v1, v26
Ltmp11513:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v30, v21, #0
Ltmp11514:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v19, v19, #24
	sshr.2s	v19, v19, #24
	sshll.2d	v31, v19, #0
	shl.2s	v19, v20, #24
	sshr.2s	v26, v19, #24
	shl.2s	v19, v22, #24
	sshr.2s	v20, v19, #24
	shl.2s	v19, v25, #24
	sshr.2s	v19, v19, #24
	sshll.2d	v19, v19, #0
	scvtf.2d	v19, v19
	bit.16b	v19, v1, v29
	mov	b22, v2[0]
	mov.b	v22[4], v2[1]
	sshll.2d	v20, v20, #0
	scvtf.2d	v20, v20
	bit.16b	v20, v1, v27
	mov	b25, v2[2]
	mov.b	v25[4], v2[3]
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	bsl.16b	v23, v1, v26
	mov	b26, v2[4]
	mov.b	v26[4], v2[5]
Ltmp11515:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v21, v21, #0
Ltmp11516:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf.2d	v27, v31
	bsl.16b	v17, v1, v27
	mov	b27, v2[6]
	mov.b	v27[4], v2[7]
Ltmp11517:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v28, v28, #0
	cmeq.16b	v29, v2, v10
Ltmp11518:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v2, v5, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov.16b	v5, v28
	bsl.16b	v5, v1, v2
Ltmp11519:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.8h	v28, v29, #0
Ltmp11520:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v2, v4, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov.16b	v4, v21
	bsl.16b	v4, v1, v2
Ltmp11521:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v31, v28, #0
Ltmp11522:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v2, v3, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	mov.16b	v21, v30
	bsl.16b	v21, v1, v2
Ltmp11523:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v2, v31, #0
Ltmp11524:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v3, v24, #24
	sshr.2s	v3, v3, #24
	sshll.2d	v3, v3, #0
	scvtf.2d	v3, v3
	bsl.16b	v2, v1, v3
Ltmp11525:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.8h	v24, v29, #0
	sshll.4s	v28, v28, #0
	sshll.2d	v3, v31, #0
Ltmp11526:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v18, v18, #24
	sshr.2s	v18, v18, #24
	sshll.2d	v18, v18, #0
	scvtf.2d	v18, v18
	bsl.16b	v3, v1, v18
Ltmp11527:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v18, v28, #0
Ltmp11528:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	scvtf.2d	v7, v7
	bit.16b	v7, v1, v18
Ltmp11529:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.4s	v18, v24, #0
	sshll.2d	v28, v28, #0
Ltmp11530:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v6, v6, #24
	sshr.2s	v6, v6, #24
	sshll.2d	v6, v6, #0
	scvtf.2d	v6, v6
	bit.16b	v6, v1, v28
Ltmp11531:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v28, v18, #0
Ltmp11532:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v27, v27, #24
	sshr.2s	v27, v27, #24
	sshll.2d	v27, v27, #0
	scvtf.2d	v27, v27
	bit.16b	v27, v1, v28
Ltmp11533:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.4s	v24, v24, #0
	sshll.2d	v18, v18, #0
Ltmp11534:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v26, v26, #24
	sshr.2s	v26, v26, #24
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	bsl.16b	v18, v1, v26
Ltmp11535:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll2.2d	v26, v24, #0
Ltmp11536:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v25, v25, #24
	sshr.2s	v25, v25, #24
	sshll.2d	v25, v25, #0
	scvtf.2d	v25, v25
	bit.16b	v25, v1, v26
Ltmp11537:
	.loc	0 203 45                        ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sshll.2d	v24, v24, #0
Ltmp11538:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	shl.2s	v22, v22, #24
	sshr.2s	v22, v22, #24
	sshll.2d	v22, v22, #0
	scvtf.2d	v22, v22
	bit.16b	v22, v1, v24
	fadd	d24, d8, d17
	mov	d17, v17[1]
	fadd	d17, d24, d17
	fadd	d17, d17, d23
	mov	d23, v23[1]
	fadd	d17, d17, d23
	fadd	d17, d17, d20
	mov	d20, v20[1]
	fadd	d17, d17, d20
	fadd	d17, d17, d19
	mov	d19, v19[1]
	fadd	d17, d17, d19
	fadd	d17, d17, d21
	mov	d19, v21[1]
	fadd	d17, d17, d19
	fadd	d17, d17, d4
	mov	d4, v4[1]
	fadd	d4, d17, d4
	fadd	d4, d4, d5
	mov	d5, v5[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d16
	mov	d5, v16[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d22
	mov	d5, v22[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d25
	mov	d5, v25[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d18
	mov	d5, v18[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d27
	mov	d5, v27[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d6
	mov	d5, v6[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d7
	mov	d5, v7[1]
	fadd	d4, d4, d5
	fadd	d4, d4, d3
	mov	d3, v3[1]
	fadd	d3, d4, d3
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d8, d3, d2
	add	x10, x10, #32
	subs	x11, x11, #32
	b.ne	LBB187_906
Ltmp11539:
; %bb.907:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x9
	b.eq	LBB187_897
Ltmp11540:
; %bb.908:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x26, #0x18
	b.eq	LBB187_912
Ltmp11541:
LBB187_909:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	and	x11, x26, #0x1fff8
	add	x10, x25, x11
	dup.2d	v1, v0[0]
	add	x12, x9, x25
	add	x12, x21, x12
	sub	x9, x9, x11
Ltmp11542:
LBB187_910:                             ;   Parent Loop BB187_898 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	d2, [x12], #8
Ltmp11543:
	.loc	0 203 45 is_stmt 1              ; numeric-payload.c:203:45 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmeq.8b	v3, v2, v9
	sshll.8h	v3, v3, #0
	sshll.4s	v4, v3, #0
	sshll.2d	v5, v4, #0
	sshll2.2d	v4, v4, #0
	sshll2.4s	v3, v3, #0
	sshll.2d	v6, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11544:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	mov	b7, v2[0]
	mov.b	v7[4], v2[1]
	shl.2s	v7, v7, #24
	sshr.2s	v7, v7, #24
	sshll.2d	v7, v7, #0
	mov	b16, v2[2]
	mov.b	v16[4], v2[3]
	scvtf.2d	v7, v7
	shl.2s	v16, v16, #24
	sshr.2s	v16, v16, #24
	sshll.2d	v16, v16, #0
	scvtf.2d	v16, v16
	mov	b17, v2[4]
	mov.b	v17[4], v2[5]
	shl.2s	v17, v17, #24
	sshr.2s	v17, v17, #24
	sshll.2d	v17, v17, #0
	scvtf.2d	v17, v17
	mov	b18, v2[6]
	mov.b	v18[4], v2[7]
	shl.2s	v2, v18, #24
	sshr.2s	v2, v2, #24
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	bsl.16b	v6, v1, v17
	mov	d17, v6[1]
	bsl.16b	v4, v1, v16
	mov	d16, v4[1]
	bsl.16b	v5, v1, v7
	mov	d7, v5[1]
	fadd	d5, d8, d5
	fadd	d5, d5, d7
	fadd	d4, d5, d4
	fadd	d4, d4, d16
	fadd	d4, d4, d6
	fadd	d4, d4, d17
	fadd	d2, d4, d2
	fadd	d8, d2, d3
	adds	x9, x9, #8
	b.ne	LBB187_910
Ltmp11545:
; %bb.911:                              ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x26, x11
	b.eq	LBB187_897
	b	LBB187_913
Ltmp11546:
LBB187_912:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x25, x9
Ltmp11547:
LBB187_913:                             ;   in Loop: Header=BB187_898 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x25, x26
	sub	x9, x9, x10
	add	x10, x21, x10
Ltmp11548:
LBB187_914:                             ;   Parent Loop BB187_898 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w11, [x10], #1
Ltmp11549:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: byte_missing_offset:value <- $w11
	sxtb	w12, w11
	;DEBUG_VALUE: byte_missing_offset:format_version <- 111
Ltmp11550:
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w12
	cmp	w11, #127
	fcsel	d1, d0, d1, eq
Ltmp11551:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11552:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x9, x9, #1
Ltmp11553:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_914
	b	LBB187_897
Ltmp11554:
LBB187_915:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11555:
; %bb.916:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
Lloh1712:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1713:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mvni.4s	v26, #128, lsl #24
	mov	w25, #2147483647                ; =0x7fffffff
	b	LBB187_918
Ltmp11556:
LBB187_917:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x26, x9
Ltmp11557:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11558:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11559:
LBB187_918:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_926 Depth 2
                                        ;     Child Loop BB187_930 Depth 2
                                        ;     Child Loop BB187_934 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x19, x8, x26
Ltmp11560:
	;DEBUG_VALUE: count <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x23, lo
Ltmp11561:
	;DEBUG_VALUE: count <- $x27
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_920
Ltmp11562:
; %bb.919:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11563:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.4s	v26, #128, lsl #24
Ltmp11564:
LBB187_920:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x27, x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11565:
	;DEBUG_VALUE: i <- $x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x26, x9
	b.hs	LBB187_917
Ltmp11566:
; %bb.921:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, #4
	b.hs	LBB187_923
Ltmp11567:
; %bb.922:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_933
Ltmp11568:
LBB187_923:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_925
Ltmp11569:
; %bb.924:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x8, #0                          ; =0x0
	b	LBB187_929
Ltmp11570:
LBB187_925:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x8, x27, #0x1fff0
	dup.2d	v1, v0[0]
	add	x10, x22, x26, lsl #2
	mov	x11, x8
Ltmp11571:
LBB187_926:                             ;   Parent Loop BB187_918 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp11572:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v6, v2, v26
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmeq.4s	v16, v3, v26
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmeq.4s	v18, v4, v26
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmeq.4s	v20, v5, v26
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp11573:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v22, v2, #0
	scvtf.2d	v22, v22
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	sshll.2d	v23, v3, #0
	scvtf.2d	v23, v23
	sshll2.2d	v3, v3, #0
	scvtf.2d	v3, v3
	sshll.2d	v24, v4, #0
	scvtf.2d	v24, v24
	sshll2.2d	v4, v4, #0
	scvtf.2d	v4, v4
	sshll.2d	v25, v5, #0
	scvtf.2d	v25, v25
	sshll2.2d	v5, v5, #0
	scvtf.2d	v5, v5
	bit.16b	v2, v1, v6
	mov	d6, v2[1]
	bsl.16b	v7, v1, v22
	mov	d22, v7[1]
	bit.16b	v3, v1, v16
	mov	d16, v3[1]
	bsl.16b	v17, v1, v23
	mov	d23, v17[1]
	bit.16b	v4, v1, v18
	mov	d18, v4[1]
	bsl.16b	v19, v1, v24
	mov	d24, v19[1]
	bit.16b	v5, v1, v20
	mov	d20, v5[1]
	bsl.16b	v21, v1, v25
	mov	d25, v21[1]
	fadd	d7, d8, d7
	fadd	d7, d7, d22
	fadd	d2, d7, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d17
	fadd	d2, d2, d23
	fadd	d2, d2, d3
	fadd	d2, d2, d16
	fadd	d2, d2, d19
	fadd	d2, d2, d24
	fadd	d2, d2, d4
	fadd	d2, d2, d18
	fadd	d2, d2, d21
	fadd	d2, d2, d25
	fadd	d2, d2, d5
	fadd	d8, d2, d20
	subs	x11, x11, #16
	b.ne	LBB187_926
Ltmp11574:
; %bb.927:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x8
	b.eq	LBB187_917
Ltmp11575:
; %bb.928:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0xc
	b.eq	LBB187_932
Ltmp11576:
LBB187_929:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	and	x11, x27, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x8, x11
	add	x8, x8, x26
	add	x8, x21, x8, lsl #2
Ltmp11577:
LBB187_930:                             ;   Parent Loop BB187_918 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	q2, [x8], #16
Ltmp11578:
	.loc	0 213 45 is_stmt 1              ; numeric-payload.c:213:45 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmeq.4s	v3, v2, v26
	sshll.2d	v4, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11579:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sshll.2d	v5, v2, #0
	scvtf.2d	v5, v5
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	bsl.16b	v4, v1, v5
	mov	d5, v4[1]
	fadd	d4, d8, d4
	fadd	d4, d4, d5
	fadd	d2, d4, d2
	fadd	d8, d2, d3
	adds	x12, x12, #4
	b.ne	LBB187_930
Ltmp11580:
; %bb.931:                              ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x27, x11
	b.eq	LBB187_917
	b	LBB187_933
Ltmp11581:
LBB187_932:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x8
Ltmp11582:
LBB187_933:                             ;   in Loop: Header=BB187_918 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x26, x27
	sub	x8, x8, x10
	add	x10, x21, x10, lsl #2
Ltmp11583:
LBB187_934:                             ;   Parent Loop BB187_918 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w11, [x10], #4
Ltmp11584:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: long_missing_offset:value <- $w11
	;DEBUG_VALUE: long_missing_offset:format_version <- 111
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w11
	cmp	w11, w25
	fcsel	d1, d0, d1, eq
Ltmp11585:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11586:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x8, x8, #1
Ltmp11587:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_934
	b	LBB187_917
Ltmp11588:
LBB187_935:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 655 1 is_stmt 1               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cbz	x9, LBB187_943
Ltmp11589:
; %bb.936:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_byte_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1714:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1715:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b	LBB187_938
Ltmp11590:
LBB187_937:                             ;   in Loop: Header=BB187_938 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11591:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, x9
Ltmp11592:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_943
Ltmp11593:
LBB187_938:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_942 Depth 2
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	sub	x8, x9, x19
Ltmp11594:
	;DEBUG_VALUE: count <- $x8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x25, x8, x23, lo
Ltmp11595:
	;DEBUG_VALUE: count <- $x25
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_940
Ltmp11596:
; %bb.939:                              ;   in Loop: Header=BB187_938 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11597:
LBB187_940:                             ;   in Loop: Header=BB187_938 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x25, x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
Ltmp11598:
	;DEBUG_VALUE: i <- $x19
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	cmp	x19, x8
	b.hs	LBB187_937
Ltmp11599:
; %bb.941:                              ;   in Loop: Header=BB187_938 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	add	x9, x21, x19
Ltmp11600:
LBB187_942:                             ;   Parent Loop BB187_938 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	ldrb	w10, [x9], #1
Ltmp11601:
	;DEBUG_VALUE: raw <- $w10
	sxtb	w11, w10
Ltmp11602:
	;DEBUG_VALUE: byte_missing_offset:value <- $w10
	;DEBUG_VALUE: byte_missing_offset:format_version <- 119
	.loc	0 204 25 is_stmt 1              ; numeric-payload.c:204:25 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	sub	w10, w10, #101
Ltmp11603:
	cmp	w11, #100
	csinv	w10, w10, wzr, gt
Ltmp11604:
	;DEBUG_VALUE: missing <- $w10
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	scvtf	d1, w11
Ltmp11605:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	add	w11, w10, #96
Ltmp11606:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11607:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	fmov	d2, x11
Ltmp11608:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp11609:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp11610:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11611:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1 is_stmt 0               ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	subs	x25, x25, #1
Ltmp11612:
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	b.ne	LBB187_942
	b	LBB187_937
Ltmp11613:
LBB187_943:
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_byte_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_byte_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_byte_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_byte_sum_accumulate:sum <- $d8
	.loc	0 655 1                         ; numeric-payload.c:655:1 @[ numeric-payload.c:1830:24 ]
	str	d8, [x28, #8]
	b	LBB187_1013
Ltmp11614:
LBB187_944:
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 657 1 is_stmt 1               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cbz	x8, LBB187_1012
Ltmp11615:
; %bb.945:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_long_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:temporal <- $w10
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65508                     ; =0xffe4
	movk	w23, #32767, lsl #16
	mov	w24, #65536                     ; =0x10000
Lloh1716:
	adrp	x25, _R_NaReal@GOTPAGE
Lloh1717:
	ldr	x25, [x25, _R_NaReal@GOTPAGEOFF]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b	LBB187_947
Ltmp11616:
LBB187_946:                             ;   in Loop: Header=BB187_947 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	x8, [x20, #8]
	mov	x19, x9
Ltmp11617:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, x8
Ltmp11618:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp11619:
LBB187_947:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_951 Depth 2
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	sub	x9, x8, x19
Ltmp11620:
	;DEBUG_VALUE: count <- $x9
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x9, #16, lsl #12                ; =65536
	csel	x26, x9, x24, lo
Ltmp11621:
	;DEBUG_VALUE: count <- $x26
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x8, #4, lsl #12                 ; =16384
	b.lo	LBB187_949
Ltmp11622:
; %bb.948:                              ;   in Loop: Header=BB187_947 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11623:
LBB187_949:                             ;   in Loop: Header=BB187_947 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x9, x26, x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
Ltmp11624:
	;DEBUG_VALUE: i <- $x19
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	x19, x9
	b.hs	LBB187_946
Ltmp11625:
; %bb.950:                              ;   in Loop: Header=BB187_947 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x25]
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	add	x8, x21, x19, lsl #2
Ltmp11626:
LBB187_951:                             ;   Parent Loop BB187_947 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_long_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_long_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_long_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	ldr	w10, [x8], #4
Ltmp11627:
	;DEBUG_VALUE: raw <- $w10
	scvtf	d1, w10
Ltmp11628:
	;DEBUG_VALUE: long_missing_offset:value <- $w10
	;DEBUG_VALUE: long_missing_offset:format_version <- 119
	;DEBUG_VALUE: missing <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] undef
	;DEBUG_VALUE: numeric_missing_value:offset <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] undef
	.loc	0 214 41 is_stmt 1              ; numeric-payload.c:214:41 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	cmp	w10, w23
	csel	w11, w10, w23, gt
Ltmp11629:
	;DEBUG_VALUE: missing <- [DW_OP_constu 2147483621, DW_OP_minus, DW_OP_stack_value] $w11
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w12, w23, #1
	cmp	w10, w12
Ltmp11630:
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	add	w11, w23, w11
Ltmp11631:
	add	w11, w11, #151
Ltmp11632:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11633:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fmov	d2, x11
Ltmp11634:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ] ]
	fcsel	d2, d0, d2, eq
Ltmp11635:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	cmp	w10, w23
	fcsel	d1, d1, d2, le
Ltmp11636:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11637:
	;DEBUG_VALUE: numeric_long_sum_accumulate:sum <- $d8
	.loc	0 657 1 is_stmt 0               ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	subs	x26, x26, #1
Ltmp11638:
	.loc	0 657 1                         ; numeric-payload.c:657:1 @[ numeric-payload.c:1832:24 ]
	b.ne	LBB187_951
	b	LBB187_946
Ltmp11639:
LBB187_952:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11640:
; %bb.953:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x22, x21, #32
	mov	w23, #65536                     ; =0x10000
Lloh1718:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1719:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mvni.8h	v29, #128, lsl #8
	mov	w25, #32767                     ; =0x7fff
	b	LBB187_955
Ltmp11641:
LBB187_954:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp11642:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11643:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11644:
LBB187_955:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_963 Depth 2
                                        ;     Child Loop BB187_967 Depth 2
                                        ;     Child Loop BB187_971 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x19, x9, x26
Ltmp11645:
	;DEBUG_VALUE: count <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x23, lo
Ltmp11646:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_957
Ltmp11647:
; %bb.956:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11648:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.8h	v29, #128, lsl #8
Ltmp11649:
LBB187_957:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11650:
	;DEBUG_VALUE: i <- $x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x26, x8
	b.hs	LBB187_954
Ltmp11651:
; %bb.958:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, #8
	b.hs	LBB187_960
Ltmp11652:
; %bb.959:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_970
Ltmp11653:
LBB187_960:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #32
	b.hs	LBB187_962
Ltmp11654:
; %bb.961:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_966
Ltmp11655:
LBB187_962:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x9, x27, #0x1ffe0
	dup.2d	v1, v0[0]
	add	x10, x22, x26, lsl #1
	mov	x11, x9
Ltmp11656:
LBB187_963:                             ;   Parent Loop BB187_955 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldp	q23, q6, [x10, #-32]
	ldp	q3, q2, [x10]
Ltmp11657:
	.loc	0 208 45 is_stmt 1              ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v4, v23, v29
	sshll.4s	v5, v4, #0
	sshll.2d	v19, v5, #0
	sshll2.2d	v22, v5, #0
	sshll2.4s	v4, v4, #0
	sshll.2d	v25, v4, #0
	sshll2.2d	v21, v4, #0
	cmeq.8h	v4, v6, v29
	sshll.4s	v5, v4, #0
	sshll.2d	v7, v5, #0
	sshll2.2d	v17, v5, #0
	sshll2.4s	v4, v4, #0
	sshll.2d	v20, v4, #0
	sshll2.2d	v24, v4, #0
	cmeq.8h	v16, v3, v29
	sshll.4s	v5, v16, #0
	sshll.2d	v4, v5, #0
	sshll2.2d	v5, v5, #0
	sshll2.4s	v18, v16, #0
	sshll.2d	v16, v18, #0
	sshll2.2d	v18, v18, #0
Ltmp11658:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll2.4s	v26, v23, #0
	sshll2.2d	v27, v26, #0
	scvtf.2d	v27, v27
	bsl.16b	v21, v1, v27
Ltmp11659:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v27, v2, v29
Ltmp11660:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.4s	v28, v23, #0
	sshll.2d	v23, v26, #0
	scvtf.2d	v23, v23
	bit.16b	v23, v1, v25
	sshll.2d	v25, v28, #0
	scvtf.2d	v25, v25
	sshll2.2d	v26, v28, #0
	scvtf.2d	v26, v26
	bsl.16b	v22, v1, v26
	sshll2.4s	v26, v6, #0
	bit.16b	v25, v1, v19
	sshll2.2d	v19, v26, #0
	scvtf.2d	v19, v19
	bit.16b	v19, v1, v24
Ltmp11661:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll.4s	v24, v27, #0
	sshll2.4s	v27, v27, #0
Ltmp11662:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.4s	v28, v6, #0
	sshll.2d	v6, v26, #0
	scvtf.2d	v6, v6
	bit.16b	v6, v1, v20
	sshll.2d	v20, v28, #0
	scvtf.2d	v20, v20
	sshll2.2d	v26, v28, #0
	scvtf.2d	v26, v26
	bsl.16b	v17, v1, v26
	sshll2.4s	v26, v3, #0
	bit.16b	v20, v1, v7
	sshll2.2d	v7, v26, #0
	scvtf.2d	v7, v7
	bit.16b	v7, v1, v18
Ltmp11663:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll2.2d	v18, v27, #0
Ltmp11664:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.4s	v28, v3, #0
	sshll.2d	v3, v26, #0
	scvtf.2d	v3, v3
	bit.16b	v3, v1, v16
	sshll.2d	v16, v28, #0
	scvtf.2d	v16, v16
	sshll2.2d	v26, v28, #0
	scvtf.2d	v26, v26
	bsl.16b	v5, v1, v26
	sshll2.4s	v26, v2, #0
	bit.16b	v16, v1, v4
	sshll2.2d	v4, v26, #0
	scvtf.2d	v4, v4
	bit.16b	v4, v1, v18
Ltmp11665:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll2.2d	v18, v24, #0
	sshll.2d	v27, v27, #0
Ltmp11666:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.4s	v2, v2, #0
	sshll.2d	v26, v26, #0
	scvtf.2d	v26, v26
	bit.16b	v26, v1, v27
	sshll2.2d	v27, v2, #0
	scvtf.2d	v27, v27
	bsl.16b	v18, v1, v27
Ltmp11667:
	.loc	0 208 45                        ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	sshll.2d	v24, v24, #0
Ltmp11668:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.2d	v2, v2, #0
	scvtf.2d	v2, v2
	bit.16b	v2, v1, v24
	fadd	d24, d8, d25
	mov	d25, v25[1]
	fadd	d24, d24, d25
	fadd	d24, d24, d22
	mov	d22, v22[1]
	fadd	d22, d24, d22
	fadd	d22, d22, d23
	mov	d23, v23[1]
	fadd	d22, d22, d23
	fadd	d22, d22, d21
	mov	d21, v21[1]
	fadd	d21, d22, d21
	fadd	d21, d21, d20
	mov	d20, v20[1]
	fadd	d20, d21, d20
	fadd	d20, d20, d17
	mov	d17, v17[1]
	fadd	d17, d20, d17
	fadd	d17, d17, d6
	mov	d6, v6[1]
	fadd	d6, d17, d6
	fadd	d6, d6, d19
	mov	d17, v19[1]
	fadd	d6, d6, d17
	fadd	d6, d6, d16
	mov	d16, v16[1]
	fadd	d6, d6, d16
	fadd	d6, d6, d5
	mov	d5, v5[1]
	fadd	d5, d6, d5
	fadd	d5, d5, d3
	mov	d3, v3[1]
	fadd	d3, d5, d3
	fadd	d3, d3, d7
	mov	d5, v7[1]
	fadd	d3, d3, d5
	fadd	d3, d3, d2
	mov	d2, v2[1]
	fadd	d2, d3, d2
	fadd	d2, d2, d18
	mov	d3, v18[1]
	fadd	d2, d2, d3
	fadd	d2, d2, d26
	mov	d3, v26[1]
	fadd	d2, d2, d3
	fadd	d2, d2, d4
	mov	d3, v4[1]
	fadd	d8, d2, d3
	add	x10, x10, #64
	subs	x11, x11, #32
	b.ne	LBB187_963
Ltmp11669:
; %bb.964:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x9
	b.eq	LBB187_954
Ltmp11670:
; %bb.965:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0x18
	b.eq	LBB187_969
Ltmp11671:
LBB187_966:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	and	x11, x27, #0x1fff8
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #1
Ltmp11672:
LBB187_967:                             ;   Parent Loop BB187_955 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	q2, [x9], #16
Ltmp11673:
	.loc	0 208 45 is_stmt 1              ; numeric-payload.c:208:45 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmeq.8h	v3, v2, v29
	sshll.4s	v4, v3, #0
	sshll.2d	v5, v4, #0
	sshll2.2d	v4, v4, #0
	sshll2.4s	v3, v3, #0
	sshll.2d	v6, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11674:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sshll.4s	v7, v2, #0
	sshll.2d	v16, v7, #0
	scvtf.2d	v16, v16
	sshll2.2d	v7, v7, #0
	scvtf.2d	v7, v7
	sshll2.4s	v2, v2, #0
	sshll.2d	v17, v2, #0
	scvtf.2d	v17, v17
	sshll2.2d	v2, v2, #0
	scvtf.2d	v2, v2
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	bsl.16b	v6, v1, v17
	mov	d17, v6[1]
	bsl.16b	v4, v1, v7
	mov	d7, v4[1]
	bsl.16b	v5, v1, v16
	mov	d16, v5[1]
	fadd	d5, d8, d5
	fadd	d5, d5, d16
	fadd	d4, d5, d4
	fadd	d4, d4, d7
	fadd	d4, d4, d6
	fadd	d4, d4, d17
	fadd	d2, d4, d2
	fadd	d8, d2, d3
	adds	x12, x12, #8
	b.ne	LBB187_967
Ltmp11675:
; %bb.968:                              ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x27, x11
	b.eq	LBB187_954
	b	LBB187_970
Ltmp11676:
LBB187_969:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x9
Ltmp11677:
LBB187_970:                             ;   in Loop: Header=BB187_955 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #1
Ltmp11678:
LBB187_971:                             ;   Parent Loop BB187_955 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w11, [x10], #2
Ltmp11679:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: int_missing_offset:value <- $w11
	sxth	w12, w11
	;DEBUG_VALUE: int_missing_offset:format_version <- 111
Ltmp11680:
	;DEBUG_VALUE: missing <- undef
	scvtf	d1, w12
	cmp	w11, w25
	fcsel	d1, d0, d1, eq
Ltmp11681:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11682:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x9, x9, #1
Ltmp11683:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_971
	b	LBB187_954
Ltmp11684:
LBB187_972:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11685:
; %bb.973:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x26, #0                         ; =0x0
	mov	w22, #2130706431                ; =0x7effffff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x23, x21, #32
	mov	w24, #65536                     ; =0x10000
	mvni.4s	v26, #129, lsl #24
Lloh1720:
	adrp	x25, _R_NaReal@GOTPAGE
Lloh1721:
	ldr	x25, [x25, _R_NaReal@GOTPAGEOFF]
	b	LBB187_975
Ltmp11686:
LBB187_974:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp11687:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11688:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB187_1012
Ltmp11689:
LBB187_975:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_983 Depth 2
                                        ;     Child Loop BB187_987 Depth 2
                                        ;     Child Loop BB187_991 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x19, x9, x26
Ltmp11690:
	;DEBUG_VALUE: count <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #16, lsl #12               ; =65536
	csel	x27, x19, x24, lo
Ltmp11691:
	;DEBUG_VALUE: count <- $x27
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_977
Ltmp11692:
; %bb.976:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11693:
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mvni.4s	v26, #129, lsl #24
Ltmp11694:
LBB187_977:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x8, x27, x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11695:
	;DEBUG_VALUE: i <- $x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x26, x8
	b.hs	LBB187_974
Ltmp11696:
; %bb.978:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x25]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, #4
	b.hs	LBB187_980
Ltmp11697:
; %bb.979:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x10, x26
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_990
Ltmp11698:
LBB187_980:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	cmp	x19, #16
	b.hs	LBB187_982
Ltmp11699:
; %bb.981:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	mov	x9, #0                          ; =0x0
	b	LBB187_986
Ltmp11700:
LBB187_982:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x9, x27, #0x1fff0
	dup.2d	v1, v0[0]
	add	x10, x23, x26, lsl #2
	mov	x11, x9
Ltmp11701:
LBB187_983:                             ;   Parent Loop BB187_975 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldp	q2, q3, [x10, #-32]
	ldp	q4, q5, [x10], #64
Ltmp11702:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.4s	v6, v2, v26
	sshll.2d	v7, v6, #0
	sshll2.2d	v6, v6, #0
	cmgt.4s	v16, v3, v26
	sshll.2d	v17, v16, #0
	sshll2.2d	v16, v16, #0
	cmgt.4s	v18, v4, v26
	sshll.2d	v19, v18, #0
	sshll2.2d	v18, v18, #0
	cmgt.4s	v20, v5, v26
	sshll.2d	v21, v20, #0
	sshll2.2d	v20, v20, #0
Ltmp11703:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v22.2d, v2.2s
	fcvtl2	v2.2d, v2.4s
	fcvtl	v23.2d, v3.2s
	fcvtl2	v3.2d, v3.4s
	fcvtl	v24.2d, v4.2s
	fcvtl2	v4.2d, v4.4s
	fcvtl	v25.2d, v5.2s
	fcvtl2	v5.2d, v5.4s
	bit.16b	v2, v1, v6
	mov	d6, v2[1]
	bsl.16b	v7, v1, v22
	mov	d22, v7[1]
	bit.16b	v3, v1, v16
	mov	d16, v3[1]
	bsl.16b	v17, v1, v23
	mov	d23, v17[1]
	bit.16b	v4, v1, v18
	mov	d18, v4[1]
	bsl.16b	v19, v1, v24
	mov	d24, v19[1]
	bit.16b	v5, v1, v20
	mov	d20, v5[1]
	bsl.16b	v21, v1, v25
	mov	d25, v21[1]
	fadd	d7, d8, d7
	fadd	d7, d7, d22
	fadd	d2, d7, d2
	fadd	d2, d2, d6
	fadd	d2, d2, d17
	fadd	d2, d2, d23
	fadd	d2, d2, d3
	fadd	d2, d2, d16
	fadd	d2, d2, d19
	fadd	d2, d2, d24
	fadd	d2, d2, d4
	fadd	d2, d2, d18
	fadd	d2, d2, d21
	fadd	d2, d2, d25
	fadd	d2, d2, d5
	fadd	d8, d2, d20
	subs	x11, x11, #16
	b.ne	LBB187_983
Ltmp11704:
; %bb.984:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x9
	b.eq	LBB187_974
Ltmp11705:
; %bb.985:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	tst	x27, #0xc
	b.eq	LBB187_989
Ltmp11706:
LBB187_986:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	and	x11, x27, #0x1fffc
	add	x10, x26, x11
	dup.2d	v1, v0[0]
	sub	x12, x9, x11
	add	x9, x9, x26
	add	x9, x21, x9, lsl #2
Ltmp11707:
LBB187_987:                             ;   Parent Loop BB187_975 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	q2, [x9], #16
Ltmp11708:
	.loc	0 222 45 is_stmt 1              ; numeric-payload.c:222:45 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cmgt.4s	v3, v2, v26
	sshll.2d	v4, v3, #0
	sshll2.2d	v3, v3, #0
Ltmp11709:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvtl	v5.2d, v2.2s
	fcvtl2	v2.2d, v2.4s
	bit.16b	v2, v1, v3
	mov	d3, v2[1]
	bsl.16b	v4, v1, v5
	mov	d5, v4[1]
	fadd	d4, d8, d4
	fadd	d4, d4, d5
	fadd	d2, d4, d2
	fadd	d8, d2, d3
	adds	x12, x12, #4
	b.ne	LBB187_987
Ltmp11710:
; %bb.988:                              ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x27, x11
	b.eq	LBB187_974
	b	LBB187_990
Ltmp11711:
LBB187_989:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x10, x26, x9
Ltmp11712:
LBB187_990:                             ;   in Loop: Header=BB187_975 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	add	x9, x26, x27
	sub	x9, x9, x10
	add	x10, x21, x10, lsl #2
Ltmp11713:
LBB187_991:                             ;   Parent Loop BB187_975 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s1, [x10], #4
Ltmp11714:
	;DEBUG_VALUE: raw <- $s1
	fcvt	d2, s1
Ltmp11715:
	;DEBUG_VALUE: float_missing_offset:value <- $s1
	;DEBUG_VALUE: float_missing_offset:format_version <- 111
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w11, s1
Ltmp11716:
	;DEBUG_VALUE: raw <- $w11
	;DEBUG_VALUE: float_missing_offset:value <- $w11
	;DEBUG_VALUE: float_missing_offset:bits <- $w11
	;DEBUG_VALUE: missing <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	w11, w22
	fcsel	d1, d0, d2, gt
Ltmp11717:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11718:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x9, x9, #1
Ltmp11719:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.ne	LBB187_991
	b	LBB187_974
Ltmp11720:
LBB187_992:
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 656 1 is_stmt 1               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cbz	x9, LBB187_1012
Ltmp11721:
; %bb.993:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_int_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #65536                     ; =0x10000
Lloh1722:
	adrp	x24, _R_NaReal@GOTPAGE
Lloh1723:
	ldr	x24, [x24, _R_NaReal@GOTPAGEOFF]
	mov	w25, #-32741                    ; =0xffff801b
	mov	w26, #32740                     ; =0x7fe4
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b	LBB187_995
Ltmp11722:
LBB187_994:                             ;   in Loop: Header=BB187_995 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11723:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, x9
Ltmp11724:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp11725:
LBB187_995:                             ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_999 Depth 2
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	sub	x8, x9, x19
Ltmp11726:
	;DEBUG_VALUE: count <- $x8
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x27, x8, x23, lo
Ltmp11727:
	;DEBUG_VALUE: count <- $x27
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_997
Ltmp11728:
; %bb.996:                              ;   in Loop: Header=BB187_995 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	bl	_R_CheckUserInterrupt
Ltmp11729:
LBB187_997:                             ;   in Loop: Header=BB187_995 Depth=1
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x27, x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
Ltmp11730:
	;DEBUG_VALUE: i <- $x19
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	cmp	x19, x8
	b.hs	LBB187_994
Ltmp11731:
; %bb.998:                              ;   in Loop: Header=BB187_995 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x27
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x24]
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	add	x9, x21, x19, lsl #1
Ltmp11732:
LBB187_999:                             ;   Parent Loop BB187_995 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_int_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_int_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	ldrh	w10, [x9], #2
Ltmp11733:
	;DEBUG_VALUE: raw <- $w10
	sxth	w11, w10
Ltmp11734:
	;DEBUG_VALUE: int_missing_offset:value <- $w10
	;DEBUG_VALUE: int_missing_offset:format_version <- 119
	.loc	0 209 27 is_stmt 1              ; numeric-payload.c:209:27 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w10, w10, w25
Ltmp11735:
	cmp	w11, w26
	csinv	w10, w10, wzr, gt
Ltmp11736:
	;DEBUG_VALUE: missing <- $w10
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	scvtf	d1, w11
Ltmp11737:
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48                        ; numeric-payload.c:235:48 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	add	w11, w10, #96
Ltmp11738:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x11
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	orr	x11, x22, x11, lsl #32
Ltmp11739:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x11
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	fmov	d2, x11
Ltmp11740:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d2
	;DEBUG_VALUE: numeric_missing_value:value <- $d2
	.loc	0 234 16                        ; numeric-payload.c:234:16 @[ numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ] ]
	cmp	w10, #0
	fcsel	d2, d0, d2, eq
Ltmp11741:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	tst	w10, #0x80000000
	fcsel	d1, d1, d2, ne
Ltmp11742:
	;DEBUG_VALUE: element <- $d1
	fadd	d8, d8, d1
Ltmp11743:
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	.loc	0 656 1 is_stmt 0               ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	subs	x27, x27, #1
Ltmp11744:
	.loc	0 656 1                         ; numeric-payload.c:656:1 @[ numeric-payload.c:1831:23 ]
	b.ne	LBB187_999
	b	LBB187_994
Ltmp11745:
LBB187_1000:
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	;DEBUG_VALUE: start <- 0
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cbz	x9, LBB187_1012
Ltmp11746:
; %bb.1001:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: numeric_float_sum_accumulate:na_rm <- $w11
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:temporal <- $w8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:accumulator <- [DW_OP_plus_uconst 8, DW_OP_stack_value] $x28
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 0 1 is_stmt 0                 ; numeric-payload.c:0:1
	mov	x19, #0                         ; =0x0
	mov	x22, #1954                      ; =0x7a2
	movk	x22, #32752, lsl #48
	mov	w23, #-2130706432               ; =0x81000000
	mov	w24, #12287                     ; =0x2fff
	movk	w24, #33023, lsl #16
	mov	w25, #65536                     ; =0x10000
Lloh1724:
	adrp	x26, _R_NaReal@GOTPAGE
Lloh1725:
	ldr	x26, [x26, _R_NaReal@GOTPAGEOFF]
	mov	w27, #-53249                    ; =0xffff2fff
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b	LBB187_1003
Ltmp11747:
LBB187_1002:                            ;   in Loop: Header=BB187_1003 Depth=1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	x9, [x20, #8]
	mov	x19, x8
Ltmp11748:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, x9
Ltmp11749:
	;DEBUG_VALUE: start <- $x19
	b.hs	LBB187_1012
Ltmp11750:
LBB187_1003:                            ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB187_1009 Depth 2
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: start <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	sub	x8, x9, x19
Ltmp11751:
	;DEBUG_VALUE: count <- $x8
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x8, #16, lsl #12                ; =65536
	csel	x28, x8, x25, lo
Ltmp11752:
	;DEBUG_VALUE: sum_span:context <- [DW_OP_LLVM_entry_value 1] $x2
	;DEBUG_VALUE: count <- $x28
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB187_1005
Ltmp11753:
; %bb.1004:                             ;   in Loop: Header=BB187_1003 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	bl	_R_CheckUserInterrupt
Ltmp11754:
LBB187_1005:                            ;   in Loop: Header=BB187_1003 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	add	x8, x28, x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
Ltmp11755:
	;DEBUG_VALUE: i <- $x19
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	cmp	x19, x8
	b.hs	LBB187_1002
Ltmp11756:
; %bb.1006:                             ;   in Loop: Header=BB187_1003 Depth=1
	;DEBUG_VALUE: i <- $x19
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 1                           ; numeric-payload.c:0:1
	ldr	d0, [x26]
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	add	x9, x21, x19, lsl #2
	b	LBB187_1009
Ltmp11757:
LBB187_1007:                            ;   in Loop: Header=BB187_1009 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: missing <- -1
	.loc	0 661 1 is_stmt 1               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fcvt	d1, s1
Ltmp11758:
LBB187_1008:                            ;   in Loop: Header=BB187_1009 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: element <- $d1
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	fadd	d8, d8, d1
Ltmp11759:
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1 is_stmt 0               ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	subs	x28, x28, #1
Ltmp11760:
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	b.eq	LBB187_1002
Ltmp11761:
LBB187_1009:                            ;   Parent Loop BB187_1003 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: i <- undef
	.loc	0 661 1                         ; numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ]
	ldr	s1, [x9], #4
Ltmp11762:
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: float_missing_offset:value <- $s1
	;DEBUG_VALUE: float_missing_offset:format_version <- 119
	.loc	0 220 5 is_stmt 1               ; numeric-payload.c:220:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	w10, s1
Ltmp11763:
	;DEBUG_VALUE: float_missing_offset:bits <- $w10
	.loc	0 225 37                        ; numeric-payload.c:225:37 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	add	w11, w10, w24
	cmp	w11, w27
Ltmp11764:
	;DEBUG_VALUE: float_missing_offset:delta <- [DW_OP_constu 2130706432, DW_OP_minus, DW_OP_stack_value] $w10
	.loc	0 229 18                        ; numeric-payload.c:229:18 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	and	w11, w10, #0x7ff
	ccmp	w11, #0, #0, hs
	b.ne	LBB187_1007
Ltmp11765:
; %bb.1010:                             ;   in Loop: Header=BB187_1009 Depth=2
	;DEBUG_VALUE: raw <- $s1
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 18 is_stmt 0                ; numeric-payload.c:0:18
	mov.16b	v1, v0
Ltmp11766:
	add	w10, w10, w23
Ltmp11767:
	;DEBUG_VALUE: missing <- undef
	;DEBUG_VALUE: numeric_missing_value:offset <- undef
	.loc	0 234 16 is_stmt 1              ; numeric-payload.c:234:16 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	cbz	w10, LBB187_1008
Ltmp11768:
; %bb.1011:                             ;   in Loop: Header=BB187_1009 Depth=2
	;DEBUG_VALUE: start <- $x19
	;DEBUG_VALUE: numeric_float_sum_accumulate:sum <- $d8
	;DEBUG_VALUE: numeric_float_sum_accumulate:bytes <- $x21
	;DEBUG_VALUE: numeric_float_sum_accumulate:data <- $x20
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 0 0 is_stmt 0                 ; numeric-payload.c:0 @[ numeric-payload.c:1833:25 ]
	lsr	w10, w10, #11
Ltmp11769:
	;DEBUG_VALUE: missing <- $w10
	;DEBUG_VALUE: numeric_missing_value:offset <- $w10
	.loc	0 235 48 is_stmt 1              ; numeric-payload.c:235:48 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	w10, w10, #0x60
Ltmp11770:
	;DEBUG_VALUE: numeric_missing_value:letter <- $x10
	.loc	0 236 50                        ; numeric-payload.c:236:50 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	orr	x10, x22, x10, lsl #32
Ltmp11771:
	;DEBUG_VALUE: numeric_missing_value:bits <- $x10
	.loc	0 238 5                         ; numeric-payload.c:238:5 @[ numeric-payload.c:661:1 @[ numeric-payload.c:1833:25 ] ]
	fmov	d1, x10
Ltmp11772:
	;DEBUG_VALUE: numeric_missing_value:bits <- $d1
	;DEBUG_VALUE: numeric_missing_value:value <- $d1
	.loc	0 0 5 is_stmt 0                 ; numeric-payload.c:0:5
	b	LBB187_1008
Ltmp11773:
LBB187_1012:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: numeric_int_sum_accumulate:sum <- $d8
	ldr	x8, [sp, #24]                   ; 8-byte Folded Reload
	str	d8, [x8, #8]
Ltmp11774:
LBB187_1013:
	;DEBUG_VALUE: sum_span:span <- $x20
	.loc	0 1836 1 epilogue_begin is_stmt 1 ; numeric-payload.c:1836:1
	ldp	x29, x30, [sp, #256]            ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #240]            ; 16-byte Folded Reload
Ltmp11775:
	;DEBUG_VALUE: sum_span:span <- [DW_OP_LLVM_entry_value 1] $x0
	ldp	x22, x21, [sp, #224]            ; 16-byte Folded Reload
	ldp	x24, x23, [sp, #208]            ; 16-byte Folded Reload
	ldp	x26, x25, [sp, #192]            ; 16-byte Folded Reload
	ldp	x28, x27, [sp, #176]            ; 16-byte Folded Reload
	ldp	d9, d8, [sp, #160]              ; 16-byte Folded Reload
	ldp	d11, d10, [sp, #144]            ; 16-byte Folded Reload
	ldp	d13, d12, [sp, #128]            ; 16-byte Folded Reload
	ldp	d15, d14, [sp, #112]            ; 16-byte Folded Reload
	add	sp, sp, #272
	ret
Ltmp11776:
LBB187_1014:
	;DEBUG_VALUE: sum_span:span <- $x20
	;DEBUG_VALUE: sum_span:state <- $x28
	;DEBUG_VALUE: sum_span:context <- $x28
	.loc	0 1834 14                       ; numeric-payload.c:1834:14
Lloh1726:
	adrp	x0, l_.str.37@PAGE
Lloh1727:
	add	x0, x0, l_.str.37@PAGEOFF
	bl	_Rf_error
Ltmp11777:
	.loh AdrpLdrGot	Lloh1676, Lloh1677
	.loh AdrpLdrGot	Lloh1678, Lloh1679
	.loh AdrpLdrGot	Lloh1680, Lloh1681
	.loh AdrpLdrGot	Lloh1682, Lloh1683
	.loh AdrpLdrGot	Lloh1684, Lloh1685
	.loh AdrpLdrGot	Lloh1686, Lloh1687
	.loh AdrpLdrGot	Lloh1688, Lloh1689
	.loh AdrpLdrGotLdr	Lloh1690, Lloh1691, Lloh1692
	.loh AdrpLdrGot	Lloh1693, Lloh1694
	.loh AdrpLdrGot	Lloh1695, Lloh1696
	.loh AdrpLdrGot	Lloh1697, Lloh1698
	.loh AdrpLdrGot	Lloh1699, Lloh1700
	.loh AdrpLdrGot	Lloh1701, Lloh1702
	.loh AdrpLdrGot	Lloh1703, Lloh1704
	.loh AdrpLdrGot	Lloh1705, Lloh1706
	.loh AdrpLdrGotLdr	Lloh1707, Lloh1708, Lloh1709
	.loh AdrpLdrGot	Lloh1710, Lloh1711
	.loh AdrpLdrGot	Lloh1712, Lloh1713
	.loh AdrpLdrGot	Lloh1714, Lloh1715
	.loh AdrpLdrGot	Lloh1716, Lloh1717
	.loh AdrpLdrGot	Lloh1718, Lloh1719
	.loh AdrpLdrGot	Lloh1720, Lloh1721
	.loh AdrpLdrGot	Lloh1722, Lloh1723
	.loh AdrpLdrGot	Lloh1724, Lloh1725
	.loh AdrpAdd	Lloh1726, Lloh1727
Lfunc_end187:
