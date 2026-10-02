_numeric_missing_mask_span:             ; @numeric_missing_mask_span
Lfunc_begin37:
	.loc	0 759 0 is_stmt 1               ; numeric-payload.c:759:0
	.cfi_startproc
; %bb.0:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x0
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x2
	sub	sp, sp, #176
	stp	d9, d8, [sp, #64]               ; 16-byte Folded Spill
	stp	x28, x27, [sp, #80]             ; 16-byte Folded Spill
	stp	x26, x25, [sp, #96]             ; 16-byte Folded Spill
	stp	x24, x23, [sp, #112]            ; 16-byte Folded Spill
	stp	x22, x21, [sp, #128]            ; 16-byte Folded Spill
	stp	x20, x19, [sp, #144]            ; 16-byte Folded Spill
	stp	x29, x30, [sp, #160]            ; 16-byte Folded Spill
	add	x29, sp, #160
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
Ltmp573:
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x2
	mov	x19, x2
Ltmp574:
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	mov	x20, x0
Ltmp575:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	.loc	0 761 24 prologue_end           ; numeric-payload.c:761:24
	ldr	w8, [x0, #24]
Ltmp576:
	;DEBUG_VALUE: numeric_missing_mask_span:legacy <- undef
	.loc	0 762 19                        ; numeric-payload.c:762:19
	ldr	w9, [x0, #16]
	.loc	0 762 5 is_stmt 0               ; numeric-payload.c:762:5
	cmp	w9, #1
	b.gt	LBB37_45
Ltmp577:
; %bb.1:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	cbz	w9, LBB37_88
Ltmp578:
; %bb.2:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	cmp	w9, #1
	b.ne	LBB37_334
Ltmp579:
; %bb.3:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 0                           ; numeric-payload.c:0
	ldr	x10, [x19]
	ldp	x21, x9, [x20]
	.loc	0 768 13 is_stmt 1              ; numeric-payload.c:768:13
	cmp	w8, #111
	b.gt	LBB37_252
Ltmp580:
; %bb.4:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	cbz	x9, LBB37_333
Ltmp581:
; %bb.5:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x26, #0                         ; =0x0
	.loc	0 768 21                        ; numeric-payload.c:768:21
	add	x22, x10, x1, lsl #2
	add	x10, x22, #32
Ltmp582:
	add	x8, x21, #16
	stp	x8, x10, [sp, #24]              ; 16-byte Folded Spill
	add	x10, x21, #32
	add	x8, x22, #64
	stp	x8, x10, [sp, #8]               ; 16-byte Folded Spill
	mov	w27, #65536                     ; =0x10000
	mov	w28, #32767                     ; =0x7fff
	mvni.4h	v8, #128, lsl #8
	movi.4s	v26, #1
	mvni.8h	v27, #128, lsl #8
	mov	w25, #1                         ; =0x1
	dup.2d	v28, x25
	str	q28, [sp, #48]                  ; 16-byte Folded Spill
	b	LBB37_9
Ltmp583:
LBB37_6:                                ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, #0                         ; =0x0
Ltmp584:
LBB37_7:                                ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp585:
LBB37_8:                                ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp586:
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x8, x9
Ltmp587:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB37_333
Ltmp588:
LBB37_9:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_28 Depth 2
                                        ;     Child Loop BB37_32 Depth 2
                                        ;     Child Loop BB37_18 Depth 2
                                        ;     Child Loop BB37_35 Depth 2
                                        ;     Child Loop BB37_39 Depth 2
                                        ;     Child Loop BB37_44 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x26
	.loc	0 768 21                        ; numeric-payload.c:768:21
	sub	x24, x9, x26
Ltmp589:
	;DEBUG_VALUE: count <- $x24
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x24, #16, lsl #12               ; =65536
	csel	x23, x24, x27, lo
Ltmp590:
	;DEBUG_VALUE: count <- $x23
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_11
Ltmp591:
; %bb.10:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp592:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	ldr	q28, [sp, #48]                  ; 16-byte Folded Reload
	mvni.8h	v27, #128, lsl #8
	movi.4s	v26, #1
Ltmp593:
LBB37_11:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	ldr	w9, [x19, #8]
	add	x8, x23, x26
	;DEBUG_VALUE: i <- $x26
	cmp	x26, x8
	cbz	w9, LBB37_19
Ltmp594:
; %bb.12:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	b.hs	LBB37_6
Ltmp595:
; %bb.13:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x24, #3
	b.ls	LBB37_16
Ltmp596:
; %bb.14:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x26, lsl #2
	add	x9, x26, x23
	add	x11, x21, x9, lsl #1
	cmp	x10, x11
	b.hs	LBB37_25
Ltmp597:
; %bb.15:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	add	x9, x22, x9, lsl #2
	add	x10, x21, x26, lsl #1
	cmp	x10, x9
	b.hs	LBB37_25
Ltmp598:
LBB37_16:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x26
Ltmp599:
LBB37_17:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	add	x9, x26, x23
	sub	x9, x9, x11
	add	x12, x22, x11, lsl #2
	add	x11, x21, x11, lsl #1
Ltmp600:
LBB37_18:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: added <- $x10
	;DEBUG_VALUE: i <- undef
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	ldrh	w13, [x11], #2
Ltmp601:
	;DEBUG_VALUE: raw <- $w13
	cmp	w13, w28
	cset	w13, eq
Ltmp602:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x12]
Ltmp603:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x12], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp604:
	add	x10, x10, x13
Ltmp605:
	;DEBUG_VALUE: added <- $x10
	.loc	0 768 21                        ; numeric-payload.c:768:21
	subs	x9, x9, #1
Ltmp606:
	.loc	0 768 21                        ; numeric-payload.c:768:21
	b.ne	LBB37_18
	b	LBB37_7
Ltmp607:
LBB37_19:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	b.hs	LBB37_8
Ltmp608:
; %bb.20:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, x26
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x24, #3
	b.ls	LBB37_43
Ltmp609:
; %bb.21:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x26, lsl #2
	add	x9, x26, x23
	add	x11, x21, x9, lsl #1
	cmp	x10, x11
	b.hs	LBB37_23
Ltmp610:
; %bb.22:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	add	x9, x22, x9, lsl #2
	add	x11, x21, x26, lsl #1
	mov	x10, x26
	cmp	x11, x9
	b.lo	LBB37_43
Ltmp611:
LBB37_23:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	cmp	x24, #32
	b.hs	LBB37_34
Ltmp612:
; %bb.24:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21 is_stmt 0                ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	b	LBB37_38
Ltmp613:
LBB37_25:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	cmp	x24, #16
	b.hs	LBB37_27
Ltmp614:
; %bb.26:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21 is_stmt 0                ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_31
Ltmp615:
LBB37_27:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	movi.2d	v0, #0000000000000000
	.loc	0 768 21                        ; numeric-payload.c:768:21
	and	x9, x23, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x11, x10, [sp, #24]             ; 16-byte Folded Reload
	add	x10, x10, x26, lsl #2
	add	x11, x11, x26, lsl #1
	mov	x12, x9
	movi.2d	v2, #0000000000000000
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v6, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v7, #0000000000000000
Ltmp616:
LBB37_28:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	ldp	q16, q17, [x11, #-16]
	cmeq.8h	v16, v16, v27
	ushll2.4s	v18, v16, #0
	and.16b	v18, v18, v26
	ushll.4s	v19, v16, #0
	and.16b	v19, v19, v26
	cmeq.8h	v17, v17, v27
	ushll2.4s	v20, v17, #0
	and.16b	v20, v20, v26
	ushll.4s	v21, v17, #0
	and.16b	v21, v21, v26
	ldp	q23, q22, [x10, #-32]
	ldp	q25, q24, [x10]
	orr.16b	v19, v23, v19
	orr.16b	v18, v22, v18
	orr.16b	v21, v25, v21
	orr.16b	v20, v24, v20
	stp	q19, q18, [x10, #-32]
	stp	q21, q20, [x10], #64
	cmeq.4s	v18, v22, #0
	cmeq.4s	v19, v23, #0
	uzp1.8h	v18, v19, v18
	cmeq.4s	v19, v24, #0
	cmeq.4s	v20, v25, #0
	uzp1.8h	v19, v20, v19
	and.16b	v16, v16, v18
	xtn.8b	v20, v16
	and.16b	v16, v17, v19
	xtn.8b	v16, v16
	mov	b17, v20[0]
	mov.b	v17[4], v20[1]
	dup.2d	v18, x25
	ushll.2d	v17, v17, #0
	and.16b	v17, v17, v18
	mov	b19, v20[2]
	mov.b	v19[4], v20[3]
	ushll.2d	v19, v19, #0
	and.16b	v19, v19, v18
	mov	b21, v20[4]
	mov.b	v21[4], v20[5]
	ushll.2d	v21, v21, #0
	and.16b	v21, v21, v18
	mov	b22, v20[6]
	mov.b	v22[4], v20[7]
	ushll.2d	v20, v22, #0
	and.16b	v20, v20, v18
	mov	b22, v16[0]
	mov.b	v22[4], v16[1]
	ushll.2d	v22, v22, #0
	mov	b23, v16[2]
	mov.b	v23[4], v16[3]
	and.16b	v22, v22, v18
	ushll.2d	v23, v23, #0
	and.16b	v23, v23, v18
	mov	b24, v16[4]
	mov.b	v24[4], v16[5]
	ushll.2d	v24, v24, #0
	and.16b	v24, v24, v18
	mov	b25, v16[6]
	mov.b	v25[4], v16[7]
	ushll.2d	v16, v25, #0
	and.16b	v16, v16, v18
	add.2d	v3, v3, v20
	add.2d	v2, v2, v21
	add.2d	v1, v1, v19
	add.2d	v0, v0, v17
	add.2d	v7, v7, v16
	add.2d	v5, v5, v24
	add.2d	v6, v6, v23
	add.2d	v4, v4, v22
	add	x11, x11, #32
	subs	x12, x12, #16
	b.ne	LBB37_28
Ltmp617:
; %bb.29:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	add.2d	v1, v6, v1
	add.2d	v3, v7, v3
	add.2d	v0, v4, v0
	add.2d	v2, v5, v2
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x23, x9
	b.eq	LBB37_7
Ltmp618:
; %bb.30:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x23, #0xc
	b.eq	LBB37_41
Ltmp619:
LBB37_31:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	and	x12, x23, #0x1fffc
	add	x11, x26, x12
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	mov.d	v1[0], x10
	sub	x10, x9, x12
	add	x13, x9, x26
	add	x9, x22, x13, lsl #2
	add	x13, x21, x13, lsl #1
Ltmp620:
LBB37_32:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	ldr	d2, [x13], #8
	cmeq.4h	v2, v2, v8
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ldr	q4, [x9]
	orr.16b	v3, v4, v3
	str	q3, [x9], #16
	cmeq.4s	v3, v4, #0
	xtn.4h	v3, v3
	and.8b	v2, v2, v3
	ushll.4s	v2, v2, #0
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v28
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v28
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	adds	x10, x10, #4
	b.ne	LBB37_32
Ltmp621:
; %bb.33:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	add.2d	v0, v1, v0
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x23, x12
	b.eq	LBB37_7
	b	LBB37_17
Ltmp622:
LBB37_34:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	and	x9, x23, #0x1ffe0
	ldp	x11, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x26, lsl #1
	add	x11, x11, x26, lsl #2
	mov	x12, x9
Ltmp623:
LBB37_35:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	cmeq.8h	v0, v0, v27
	ushll.4s	v4, v0, #0
	and.16b	v4, v4, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	cmeq.8h	v1, v1, v27
	ushll.4s	v5, v1, #0
	and.16b	v5, v5, v26
	ushll2.4s	v1, v1, #0
	and.16b	v1, v1, v26
	cmeq.8h	v2, v2, v27
	ushll.4s	v6, v2, #0
	and.16b	v6, v6, v26
	ushll2.4s	v2, v2, #0
	and.16b	v2, v2, v26
	cmeq.8h	v3, v3, v27
	ushll.4s	v7, v3, #0
	and.16b	v7, v7, v26
	stp	q4, q0, [x11, #-64]
	ushll2.4s	v0, v3, #0
	stp	q5, q1, [x11, #-32]
	stp	q6, q2, [x11]
	and.16b	v0, v0, v26
	stp	q7, q0, [x11, #32]
	add	x11, x11, #128
	subs	x12, x12, #32
	b.ne	LBB37_35
Ltmp624:
; %bb.36:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x23, x9
	b.eq	LBB37_8
Ltmp625:
; %bb.37:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x23, #0x1c
	b.eq	LBB37_42
Ltmp626:
LBB37_38:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	and	x11, x23, #0x1fffc
	add	x10, x26, x11
	sub	x12, x9, x11
	add	x13, x9, x26
	add	x9, x22, x13, lsl #2
	add	x13, x21, x13, lsl #1
Ltmp627:
LBB37_39:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	ldr	d0, [x13], #8
	cmeq.4h	v0, v0, v8
	ushll.4s	v0, v0, #0
	and.16b	v0, v0, v26
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_39
Ltmp628:
; %bb.40:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	cmp	x23, x11
	b.eq	LBB37_8
	b	LBB37_43
Ltmp629:
LBB37_41:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	add	x11, x26, x9
	b	LBB37_17
Ltmp630:
LBB37_42:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21                        ; numeric-payload.c:768:21
	add	x10, x26, x9
Ltmp631:
LBB37_43:                               ;   in Loop: Header=BB37_9 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 768 21 is_stmt 1              ; numeric-payload.c:768:21
	add	x9, x26, x23
	sub	x9, x9, x10
	add	x11, x22, x10, lsl #2
	add	x10, x21, x10, lsl #1
Ltmp632:
LBB37_44:                               ;   Parent Loop BB37_9 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 768 21 is_stmt 0              ; numeric-payload.c:768:21
	ldrh	w12, [x10], #2
Ltmp633:
	;DEBUG_VALUE: raw <- $w12
	cmp	w12, w28
	cset	w12, eq
Ltmp634:
	str	w12, [x11], #4
Ltmp635:
	.loc	0 768 21                        ; numeric-payload.c:768:21
	subs	x9, x9, #1
	b.ne	LBB37_44
	b	LBB37_8
Ltmp636:
LBB37_45:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 762 5 is_stmt 1               ; numeric-payload.c:762:5
	cmp	w9, #2
	b.eq	LBB37_130
Ltmp637:
; %bb.46:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	cmp	w9, #3
	b.ne	LBB37_334
Ltmp638:
; %bb.47:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 0 is_stmt 0                 ; numeric-payload.c:0
	ldr	x10, [x19]
	ldp	x21, x9, [x20]
	.loc	0 776 13 is_stmt 1              ; numeric-payload.c:776:13
	cmp	w8, #111
	b.gt	LBB37_293
Ltmp639:
; %bb.48:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cbz	x9, LBB37_333
Ltmp640:
; %bb.49:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 13 is_stmt 0                ; numeric-payload.c:0:13
	mov	x26, #0                         ; =0x0
	mov	w22, #2130706431                ; =0x7effffff
	.loc	0 777 13                        ; numeric-payload.c:777:13
	add	x23, x10, x1, lsl #2
	sub	x8, x23, x21
	str	x8, [sp, #24]                   ; 8-byte Folded Spill
	add	x10, x21, #32
Ltmp641:
	add	x8, x23, #32
	stp	x8, x10, [sp, #8]               ; 16-byte Folded Spill
	mov	w16, #65536                     ; =0x10000
	mov	w28, #2139095040                ; =0x7f800000
	mvni.4s	v28, #129, lsl #24
	mvni.4s	v0, #127, msl #16
	fneg.4s	v29, v0
	movi.4s	v30, #1
	mov	w25, #1                         ; =0x1
	dup.2d	v31, x25
	stp	q31, q29, [sp, #32]             ; 32-byte Folded Spill
	b	LBB37_53
Ltmp642:
LBB37_50:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, #0                         ; =0x0
Ltmp643:
LBB37_51:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 1              ; numeric-payload.c:777:13
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp644:
LBB37_52:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 777 13 is_stmt 0              ; numeric-payload.c:777:13
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp645:
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x8, x9
Ltmp646:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB37_333
Ltmp647:
LBB37_53:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_78 Depth 2
                                        ;     Child Loop BB37_82 Depth 2
                                        ;     Child Loop BB37_62 Depth 2
                                        ;     Child Loop BB37_71 Depth 2
                                        ;     Child Loop BB37_75 Depth 2
                                        ;     Child Loop BB37_86 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x26
	.loc	0 777 13                        ; numeric-payload.c:777:13
	sub	x27, x9, x26
Ltmp648:
	;DEBUG_VALUE: count <- $x27
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x27, #16, lsl #12               ; =65536
	csel	x24, x27, x16, lo
Ltmp649:
	;DEBUG_VALUE: count <- $x24
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_55
Ltmp650:
; %bb.54:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp651:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 13                          ; numeric-payload.c:0:13
	ldp	q31, q29, [sp, #32]             ; 32-byte Folded Reload
	movi.4s	v30, #1
	mvni.4s	v28, #129, lsl #24
	mov	w16, #65536                     ; =0x10000
Ltmp652:
LBB37_55:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	ldr	w9, [x19, #8]
	add	x8, x24, x26
	;DEBUG_VALUE: i <- $x26
	cmp	x26, x8
	cbz	w9, LBB37_63
Ltmp653:
; %bb.56:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	b.hs	LBB37_50
Ltmp654:
; %bb.57:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x27, #3
	b.ls	LBB37_60
Ltmp655:
; %bb.58:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	lsl	x11, x26, #2
	add	x10, x23, x11
	add	x9, x26, x24
	lsl	x9, x9, #2
	add	x12, x21, x9
	cmp	x10, x12
	b.hs	LBB37_68
Ltmp656:
; %bb.59:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	add	x9, x23, x9
	add	x10, x21, x11
	cmp	x10, x9
	b.hs	LBB37_68
Ltmp657:
LBB37_60:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x26
Ltmp658:
LBB37_61:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 1              ; numeric-payload.c:777:13
	add	x9, x26, x24
	sub	x9, x9, x11
	lsl	x12, x11, #2
	add	x11, x23, x12
	add	x12, x21, x12
Ltmp659:
LBB37_62:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	;DEBUG_VALUE: added <- $x10
	.loc	0 777 13 is_stmt 0              ; numeric-payload.c:777:13
	ldr	w13, [x12], #4
Ltmp660:
	;DEBUG_VALUE: raw <- $w13
	ldr	w14, [x11]
Ltmp661:
	;DEBUG_VALUE: previous <- $w14
	cmp	w14, #0
	cset	w15, eq
	cmp	w13, w22
	and	w13, w13, #0x7fffffff
Ltmp662:
	ccmp	w13, w28, #2, le
	cset	w13, hi
Ltmp663:
	;DEBUG_VALUE: missing <- $w13
	orr	w13, w14, w13
Ltmp664:
	str	w13, [x11], #4
	csel	w13, wzr, w15, ls
	add	x10, x10, x13
Ltmp665:
	;DEBUG_VALUE: added <- $x10
	.loc	0 777 13                        ; numeric-payload.c:777:13
	subs	x9, x9, #1
Ltmp666:
	.loc	0 777 13                        ; numeric-payload.c:777:13
	b.ne	LBB37_62
	b	LBB37_51
Ltmp667:
LBB37_63:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	b.hs	LBB37_52
Ltmp668:
; %bb.64:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, x26
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x27, #4
	b.lo	LBB37_85
Ltmp669:
; %bb.65:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, x26
	ldr	x9, [sp, #24]                   ; 8-byte Folded Reload
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x9, #63
	b.ls	LBB37_85
Ltmp670:
; %bb.66:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x27, #16
	b.hs	LBB37_70
Ltmp671:
; %bb.67:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x9, #0                          ; =0x0
	b	LBB37_74
Ltmp672:
LBB37_68:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 1              ; numeric-payload.c:777:13
	cmp	x27, #16
	b.hs	LBB37_77
Ltmp673:
; %bb.69:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13 is_stmt 0                ; numeric-payload.c:0:13
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_81
Ltmp674:
LBB37_70:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	and	x9, x24, #0x1fff0
	lsl	x11, x26, #2
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
Ltmp675:
LBB37_71:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	cmgt.4s	v4, v0, v28
	cmgt.4s	v5, v1, v28
	cmgt.4s	v6, v2, v28
	cmgt.4s	v7, v3, v28
	bic.4s	v0, #128, lsl #24
	bic.4s	v1, #128, lsl #24
	bic.4s	v2, #128, lsl #24
	bic.4s	v3, #128, lsl #24
	cmhi.4s	v0, v0, v29
	cmhi.4s	v1, v1, v29
	cmhi.4s	v2, v2, v29
	cmhi.4s	v3, v3, v29
	orr.16b	v0, v4, v0
	orr.16b	v1, v5, v1
	orr.16b	v2, v6, v2
	orr.16b	v3, v7, v3
	and.16b	v0, v0, v30
	and.16b	v1, v1, v30
	and.16b	v2, v2, v30
	stp	q0, q1, [x11, #-32]
	and.16b	v0, v3, v30
	stp	q2, q0, [x11], #64
	subs	x12, x12, #16
	b.ne	LBB37_71
Ltmp676:
; %bb.72:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x24, x9
	b.eq	LBB37_52
Ltmp677:
; %bb.73:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x24, #0xc
	b.eq	LBB37_84
Ltmp678:
LBB37_74:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 1              ; numeric-payload.c:777:13
	and	x11, x24, #0x1fffc
	add	x10, x26, x11
	sub	x12, x9, x11
	add	x9, x9, x26
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp679:
LBB37_75:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 0              ; numeric-payload.c:777:13
	ldr	q0, [x13], #16
	cmgt.4s	v1, v0, v28
	bic.4s	v0, #128, lsl #24
	cmhi.4s	v0, v0, v29
	orr.16b	v0, v1, v0
	and.16b	v0, v0, v30
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_75
Ltmp680:
; %bb.76:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	cmp	x24, x11
	b.eq	LBB37_52
	b	LBB37_85
Ltmp681:
LBB37_77:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	movi.2d	v0, #0000000000000000
Ltmp682:
	.loc	0 777 13                        ; numeric-payload.c:777:13
	and	x9, x24, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v6, #0000000000000000
Ltmp683:
LBB37_78:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	ldp	q16, q17, [x10, #-32]
	cmgt.4s	v18, v16, v28
	cmgt.4s	v19, v17, v28
	ldp	q20, q21, [x10], #64
	cmgt.4s	v22, v20, v28
	cmgt.4s	v23, v21, v28
	bic.4s	v16, #128, lsl #24
	bic.4s	v17, #128, lsl #24
	bic.4s	v20, #128, lsl #24
	bic.4s	v21, #128, lsl #24
	cmhi.4s	v16, v16, v29
	cmhi.4s	v17, v17, v29
	cmhi.4s	v20, v20, v29
	cmhi.4s	v21, v21, v29
	orr.16b	v16, v18, v16
	orr.16b	v17, v19, v17
	orr.16b	v18, v22, v20
	orr.16b	v19, v23, v21
	and.16b	v20, v16, v30
	and.16b	v21, v17, v30
	and.16b	v22, v18, v30
	and.16b	v23, v19, v30
	ldp	q24, q25, [x11, #-32]
	ldp	q26, q27, [x11]
	orr.16b	v20, v24, v20
	orr.16b	v21, v25, v21
	orr.16b	v22, v26, v22
	orr.16b	v23, v27, v23
	stp	q20, q21, [x11, #-32]
	stp	q22, q23, [x11], #64
	cmeq.4s	v20, v24, #0
	cmeq.4s	v21, v25, #0
	cmeq.4s	v22, v26, #0
	cmeq.4s	v23, v27, #0
	and.16b	v16, v20, v16
	and.16b	v17, v21, v17
	and.16b	v18, v22, v18
	and.16b	v19, v23, v19
	ushll.2d	v20, v16, #0
	dup.2d	v21, x25
	and.16b	v20, v20, v21
	ushll2.2d	v16, v16, #0
	and.16b	v16, v16, v21
	ushll.2d	v22, v17, #0
	and.16b	v22, v22, v21
	ushll2.2d	v17, v17, #0
	and.16b	v17, v17, v21
	ushll.2d	v23, v18, #0
	and.16b	v23, v23, v21
	ushll2.2d	v18, v18, #0
	and.16b	v18, v18, v21
	ushll.2d	v24, v19, #0
	and.16b	v24, v24, v21
	ushll2.2d	v19, v19, #0
	and.16b	v19, v19, v21
	add.2d	v1, v1, v16
	add.2d	v0, v0, v20
	add.2d	v4, v4, v17
	add.2d	v3, v3, v22
	add.2d	v7, v7, v18
	add.2d	v2, v2, v23
	add.2d	v6, v6, v19
	add.2d	v5, v5, v24
	subs	x12, x12, #16
	b.ne	LBB37_78
Ltmp684:
; %bb.79:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	add.2d	v0, v3, v0
	add.2d	v1, v4, v1
	add.2d	v1, v7, v1
	add.2d	v0, v2, v0
	add.2d	v0, v5, v0
	add.2d	v1, v6, v1
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x24, x9
	b.eq	LBB37_51
Ltmp685:
; %bb.80:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x24, #0xc
	b.eq	LBB37_87
Ltmp686:
LBB37_81:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 1              ; numeric-payload.c:777:13
	and	x12, x24, #0x1fffc
	add	x11, x26, x12
	movi.2d	v0, #0000000000000000
	mov.d	v0[0], x10
	movi.2d	v1, #0000000000000000
	sub	x10, x9, x12
	add	x9, x9, x26
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp687:
LBB37_82:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13 is_stmt 0              ; numeric-payload.c:777:13
	ldr	q2, [x13], #16
	cmgt.4s	v3, v2, v28
	bic.4s	v2, #128, lsl #24
	cmhi.4s	v2, v2, v29
	orr.16b	v2, v3, v2
	and.16b	v3, v2, v30
	ldr	q4, [x9]
	orr.16b	v3, v4, v3
	str	q3, [x9], #16
	cmeq.4s	v3, v4, #0
	and.16b	v2, v3, v2
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v31
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v31
	add.2d	v1, v1, v2
	add.2d	v0, v0, v3
	adds	x10, x10, #4
	b.ne	LBB37_82
Ltmp688:
; %bb.83:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x24, x12
	b.eq	LBB37_51
	b	LBB37_61
Ltmp689:
LBB37_84:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	add	x10, x26, x9
Ltmp690:
LBB37_85:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x26, x24
	sub	x9, x9, x10
	lsl	x11, x10, #2
	add	x10, x23, x11
	add	x11, x21, x11
Ltmp691:
LBB37_86:                               ;   Parent Loop BB37_53 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 777 13                        ; numeric-payload.c:777:13
	ldr	w12, [x11], #4
Ltmp692:
	;DEBUG_VALUE: raw <- $w12
	cmp	w12, w22
	and	w12, w12, #0x7fffffff
Ltmp693:
	ccmp	w12, w28, #2, le
	cset	w12, hi
	str	w12, [x10], #4
Ltmp694:
	.loc	0 777 13                        ; numeric-payload.c:777:13
	subs	x9, x9, #1
	b.ne	LBB37_86
	b	LBB37_52
Ltmp695:
LBB37_87:                               ;   in Loop: Header=BB37_53 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 777 13                        ; numeric-payload.c:777:13
	add	x11, x26, x9
	b	LBB37_61
Ltmp696:
LBB37_88:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 0                           ; numeric-payload.c:0
	ldr	x10, [x19]
	ldp	x21, x9, [x20]
	.loc	0 764 13 is_stmt 1              ; numeric-payload.c:764:13
	cmp	w8, #111
	b.gt	LBB37_171
Ltmp697:
; %bb.89:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	cbz	x9, LBB37_333
Ltmp698:
; %bb.90:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x27, #0                         ; =0x0
	.loc	0 764 21                        ; numeric-payload.c:764:21
	add	x22, x10, x1, lsl #2
	add	x8, x21, #32
	str	x8, [sp, #32]                   ; 8-byte Folded Spill
	add	x24, x22, #128
	mov	w25, #65536                     ; =0x10000
	movi.8b	v8, #127
	movi.4s	v26, #1
	movi.16b	v27, #127
	movi.4h	v9, #127
	mov	w26, #1                         ; =0x1
	dup.2d	v28, x26
	str	q28, [sp, #48]                  ; 16-byte Folded Spill
	b	LBB37_94
Ltmp699:
LBB37_91:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, #0                         ; =0x0
Ltmp700:
LBB37_92:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp701:
LBB37_93:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	ldr	x9, [x20, #8]
	mov	x27, x8
Ltmp702:
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x8, x9
Ltmp703:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB37_333
Ltmp704:
LBB37_94:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_113 Depth 2
                                        ;     Child Loop BB37_117 Depth 2
                                        ;     Child Loop BB37_103 Depth 2
                                        ;     Child Loop BB37_120 Depth 2
                                        ;     Child Loop BB37_124 Depth 2
                                        ;     Child Loop BB37_129 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x27
	.loc	0 764 21                        ; numeric-payload.c:764:21
	sub	x23, x9, x27
Ltmp705:
	;DEBUG_VALUE: count <- $x23
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x23, #16, lsl #12               ; =65536
	csel	x28, x23, x25, lo
Ltmp706:
	;DEBUG_VALUE: count <- $x28
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_96
Ltmp707:
; %bb.95:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp708:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	ldr	q28, [sp, #48]                  ; 16-byte Folded Reload
	movi.16b	v27, #127
	movi.4s	v26, #1
Ltmp709:
LBB37_96:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	ldr	w9, [x19, #8]
	add	x8, x28, x27
	;DEBUG_VALUE: i <- $x27
	cmp	x27, x8
	cbz	w9, LBB37_104
Ltmp710:
; %bb.97:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	b.hs	LBB37_91
Ltmp711:
; %bb.98:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x23, #3
	b.ls	LBB37_101
Ltmp712:
; %bb.99:                               ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x27, lsl #2
	add	x9, x21, x8
	cmp	x10, x9
	b.hs	LBB37_110
Ltmp713:
; %bb.100:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	add	x9, x27, x28
	add	x9, x22, x9, lsl #2
	add	x11, x21, x27
	cmp	x11, x9
	b.hs	LBB37_110
Ltmp714:
LBB37_101:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x27
Ltmp715:
LBB37_102:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	add	x9, x27, x28
	sub	x9, x9, x11
	add	x12, x21, x11
	add	x11, x22, x11, lsl #2
Ltmp716:
LBB37_103:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: added <- $x10
	;DEBUG_VALUE: i <- undef
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	ldrb	w13, [x12], #1
Ltmp717:
	;DEBUG_VALUE: raw <- $w13
	cmp	w13, #127
	cset	w13, eq
Ltmp718:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x11]
Ltmp719:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x11], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp720:
	add	x10, x10, x13
Ltmp721:
	;DEBUG_VALUE: added <- $x10
	.loc	0 764 21                        ; numeric-payload.c:764:21
	subs	x9, x9, #1
Ltmp722:
	.loc	0 764 21                        ; numeric-payload.c:764:21
	b.ne	LBB37_103
	b	LBB37_92
Ltmp723:
LBB37_104:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	b.hs	LBB37_93
Ltmp724:
; %bb.105:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, x27
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x23, #7
	b.ls	LBB37_128
Ltmp725:
; %bb.106:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x22, x27, lsl #2
	add	x10, x21, x8
	cmp	x9, x10
	b.hs	LBB37_108
Ltmp726:
; %bb.107:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	add	x9, x27, x28
	add	x9, x22, x9, lsl #2
	add	x10, x21, x27
	cmp	x10, x9
	mov	x10, x27
	b.lo	LBB37_128
Ltmp727:
LBB37_108:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	cmp	x23, #64
	b.hs	LBB37_119
Ltmp728:
; %bb.109:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21 is_stmt 0                ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	b	LBB37_123
Ltmp729:
LBB37_110:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	cmp	x23, #16
	b.hs	LBB37_112
Ltmp730:
; %bb.111:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21 is_stmt 0                ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_116
Ltmp731:
LBB37_112:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	movi.2d	v0, #0000000000000000
	.loc	0 764 21                        ; numeric-payload.c:764:21
	and	x9, x28, #0x1fff0
	movi.2d	v1, #0000000000000000
	add	x11, x21, x27
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v6, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v5, #0000000000000000
Ltmp732:
LBB37_113:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	ldr	q16, [x11], #16
	cmeq.16b	v16, v16, v27
	ushll2.8h	v17, v16, #0
	ushll2.4s	v18, v17, #0
	and.16b	v18, v18, v26
	ushll.4s	v17, v17, #0
	and.16b	v17, v17, v26
	ushll.8h	v19, v16, #0
	ushll2.4s	v20, v19, #0
	and.16b	v20, v20, v26
	ushll.4s	v19, v19, #0
	and.16b	v19, v19, v26
	ldp	q22, q21, [x10, #32]
	ldp	q24, q23, [x10]
	orr.16b	v19, v24, v19
	orr.16b	v20, v23, v20
	orr.16b	v17, v22, v17
	orr.16b	v18, v21, v18
	stp	q17, q18, [x10, #32]
	stp	q19, q20, [x10], #64
	cmeq.4s	v17, v21, #0
	cmeq.4s	v18, v22, #0
	uzp1.8h	v17, v18, v17
	cmeq.4s	v18, v23, #0
	cmeq.4s	v19, v24, #0
	uzp1.8h	v18, v19, v18
	uzp1.16b	v17, v18, v17
	and.16b	v16, v16, v17
	mov	b17, v16[0]
	mov.b	v17[4], v16[1]
	ushll.2d	v17, v17, #0
	dup.2d	v18, x26
	and.16b	v17, v17, v18
	mov	b19, v16[2]
	mov.b	v19[4], v16[3]
	ushll.2d	v19, v19, #0
	and.16b	v19, v19, v18
	mov	b20, v16[4]
	mov.b	v20[4], v16[5]
	ushll.2d	v20, v20, #0
	and.16b	v20, v20, v18
	mov	b21, v16[6]
	mov.b	v21[4], v16[7]
	ushll.2d	v21, v21, #0
	and.16b	v21, v21, v18
	mov	b22, v16[8]
	mov.b	v22[4], v16[9]
	ushll.2d	v22, v22, #0
	and.16b	v22, v22, v18
	mov	b23, v16[10]
	mov.b	v23[4], v16[11]
	ushll.2d	v23, v23, #0
	mov	b24, v16[12]
	mov.b	v24[4], v16[13]
	and.16b	v23, v23, v18
	ushll.2d	v24, v24, #0
	and.16b	v24, v24, v18
	mov	b25, v16[14]
	mov.b	v25[4], v16[15]
	ushll.2d	v16, v25, #0
	and.16b	v16, v16, v18
	add.2d	v5, v5, v16
	add.2d	v7, v7, v24
	add.2d	v4, v4, v23
	add.2d	v6, v6, v22
	add.2d	v2, v2, v21
	add.2d	v3, v3, v20
	add.2d	v1, v1, v19
	add.2d	v0, v0, v17
	subs	x12, x12, #16
	b.ne	LBB37_113
Ltmp733:
; %bb.114:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	add.2d	v0, v0, v6
	add.2d	v3, v3, v7
	add.2d	v0, v0, v3
	add.2d	v1, v1, v4
	add.2d	v2, v2, v5
	add.2d	v1, v1, v2
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x28, x9
	b.eq	LBB37_92
Ltmp734:
; %bb.115:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x28, #0xc
	b.eq	LBB37_126
Ltmp735:
LBB37_116:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	and	x12, x28, #0x1fffc
	add	x11, x27, x12
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	mov.d	v1[0], x10
	sub	x10, x9, x12
	add	x13, x9, x27
	add	x9, x21, x13
	add	x13, x22, x13, lsl #2
Ltmp736:
LBB37_117:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	ldr	s2, [x9], #4
	ushll.8h	v2, v2, #0
	cmeq.4h	v2, v2, v9
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ldr	q4, [x13]
	orr.16b	v3, v4, v3
	str	q3, [x13], #16
	cmeq.4s	v3, v4, #0
	xtn.4h	v3, v3
	and.8b	v2, v2, v3
	ushll.4s	v2, v2, #0
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v28
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v28
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	adds	x10, x10, #4
	b.ne	LBB37_117
Ltmp737:
; %bb.118:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	add.2d	v0, v1, v0
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x28, x12
	b.eq	LBB37_92
	b	LBB37_102
Ltmp738:
LBB37_119:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	and	x9, x28, #0x1ffc0
	ldr	x10, [sp, #32]                  ; 8-byte Folded Reload
	add	x10, x10, x27
	add	x11, x24, x27, lsl #2
	mov	x12, x9
Ltmp739:
LBB37_120:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	ldp	q0, q1, [x10, #-32]
	cmeq.16b	v0, v0, v27
	ushll.8h	v2, v0, #0
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ushll2.4s	v2, v2, #0
	and.16b	v2, v2, v26
	ldp	q4, q5, [x10], #64
	ushll2.8h	v0, v0, #0
	ushll.4s	v6, v0, #0
	and.16b	v6, v6, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	cmeq.16b	v1, v1, v27
	ushll.8h	v7, v1, #0
	ushll.4s	v16, v7, #0
	and.16b	v16, v16, v26
	ushll2.4s	v7, v7, #0
	and.16b	v7, v7, v26
	ushll2.8h	v1, v1, #0
	ushll.4s	v17, v1, #0
	and.16b	v17, v17, v26
	ushll2.4s	v1, v1, #0
	and.16b	v1, v1, v26
	cmeq.16b	v4, v4, v27
	ushll.8h	v18, v4, #0
	ushll.4s	v19, v18, #0
	and.16b	v19, v19, v26
	ushll2.4s	v18, v18, #0
	and.16b	v18, v18, v26
	ushll2.8h	v4, v4, #0
	ushll.4s	v20, v4, #0
	and.16b	v20, v20, v26
	ushll2.4s	v4, v4, #0
	and.16b	v4, v4, v26
	stp	q6, q0, [x11, #-96]
	cmeq.16b	v0, v5, v27
	ushll.8h	v5, v0, #0
	ushll.4s	v6, v5, #0
	and.16b	v6, v6, v26
	stp	q3, q2, [x11, #-128]
	stp	q17, q1, [x11, #-32]
	ushll2.8h	v0, v0, #0
	ushll.4s	v1, v0, #0
	and.16b	v1, v1, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	stp	q16, q7, [x11, #-64]
	stp	q20, q4, [x11, #32]
	stp	q19, q18, [x11]
	stp	q1, q0, [x11, #96]
	ushll2.4s	v0, v5, #0
	and.16b	v0, v0, v26
	stp	q6, q0, [x11, #64]
	add	x11, x11, #256
	subs	x12, x12, #64
	b.ne	LBB37_120
Ltmp740:
; %bb.121:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x28, x9
	b.eq	LBB37_93
Ltmp741:
; %bb.122:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x28, #0x38
	b.eq	LBB37_127
Ltmp742:
LBB37_123:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	and	x11, x28, #0x1fff8
	add	x10, x27, x11
	sub	x12, x9, x11
	add	x13, x9, x27
	add	x9, x21, x13
	add	x13, x22, x13, lsl #2
Ltmp743:
LBB37_124:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	ldr	d0, [x9], #8
	cmeq.8b	v0, v0, v8
	ushll.8h	v0, v0, #0
	ushll.4s	v1, v0, #0
	and.16b	v1, v1, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	stp	q1, q0, [x13], #32
	adds	x12, x12, #8
	b.ne	LBB37_124
Ltmp744:
; %bb.125:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	cmp	x28, x11
	b.eq	LBB37_93
	b	LBB37_128
Ltmp745:
LBB37_126:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	add	x11, x27, x9
	b	LBB37_102
Ltmp746:
LBB37_127:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21                        ; numeric-payload.c:764:21
	add	x10, x27, x9
Ltmp747:
LBB37_128:                              ;   in Loop: Header=BB37_94 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 764 21 is_stmt 1              ; numeric-payload.c:764:21
	add	x9, x27, x28
	sub	x9, x9, x10
	add	x11, x21, x10
	add	x10, x22, x10, lsl #2
Ltmp748:
LBB37_129:                              ;   Parent Loop BB37_94 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 764 21 is_stmt 0              ; numeric-payload.c:764:21
	ldrb	w12, [x11], #1
Ltmp749:
	;DEBUG_VALUE: raw <- $w12
	cmp	w12, #127
	cset	w12, eq
Ltmp750:
	str	w12, [x10], #4
Ltmp751:
	.loc	0 764 21                        ; numeric-payload.c:764:21
	subs	x9, x9, #1
	b.ne	LBB37_129
	b	LBB37_93
Ltmp752:
LBB37_130:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 0                           ; numeric-payload.c:0
	ldr	x10, [x19]
	ldp	x21, x9, [x20]
	.loc	0 772 13 is_stmt 1              ; numeric-payload.c:772:13
	cmp	w8, #111
	b.gt	LBB37_212
Ltmp753:
; %bb.131:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 772 21 is_stmt 0              ; numeric-payload.c:772:21
	cbz	x9, LBB37_333
Ltmp754:
; %bb.132:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x24, #0                         ; =0x0
	.loc	0 772 21                        ; numeric-payload.c:772:21
	add	x22, x10, x1, lsl #2
	sub	x8, x22, x21
	str	x8, [sp, #32]                   ; 8-byte Folded Spill
	add	x10, x21, #32
Ltmp755:
	add	x8, x22, #32
	stp	x8, x10, [sp, #16]              ; 16-byte Folded Spill
	mov	w26, #65536                     ; =0x10000
	mov	w27, #2147483647                ; =0x7fffffff
	mvni.4s	v28, #128, lsl #24
	movi.4s	v29, #1
	mov	w28, #1                         ; =0x1
	dup.2d	v30, x28
	str	q30, [sp, #48]                  ; 16-byte Folded Spill
	b	LBB37_136
Ltmp756:
LBB37_133:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, #0                         ; =0x0
Ltmp757:
LBB37_134:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 1              ; numeric-payload.c:772:21
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp758:
LBB37_135:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 772 21 is_stmt 0              ; numeric-payload.c:772:21
	ldr	x9, [x20, #8]
	mov	x24, x8
Ltmp759:
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x8, x9
Ltmp760:
	;DEBUG_VALUE: start <- $x24
	b.hs	LBB37_333
Ltmp761:
LBB37_136:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_161 Depth 2
                                        ;     Child Loop BB37_165 Depth 2
                                        ;     Child Loop BB37_145 Depth 2
                                        ;     Child Loop BB37_154 Depth 2
                                        ;     Child Loop BB37_158 Depth 2
                                        ;     Child Loop BB37_169 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x24
	.loc	0 772 21                        ; numeric-payload.c:772:21
	sub	x23, x9, x24
Ltmp762:
	;DEBUG_VALUE: count <- $x23
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x23, #16, lsl #12               ; =65536
	csel	x25, x23, x26, lo
Ltmp763:
	;DEBUG_VALUE: count <- $x25
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_138
Ltmp764:
; %bb.137:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp765:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 21                          ; numeric-payload.c:0:21
	ldr	q30, [sp, #48]                  ; 16-byte Folded Reload
	movi.4s	v29, #1
	mvni.4s	v28, #128, lsl #24
Ltmp766:
LBB37_138:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	ldr	w9, [x19, #8]
	add	x8, x25, x24
	;DEBUG_VALUE: i <- $x24
	cmp	x24, x8
	cbz	w9, LBB37_146
Ltmp767:
; %bb.139:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	b.hs	LBB37_133
Ltmp768:
; %bb.140:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x23, #3
	b.ls	LBB37_143
Ltmp769:
; %bb.141:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	lsl	x11, x24, #2
	add	x10, x22, x11
	add	x9, x24, x25
	lsl	x9, x9, #2
	add	x12, x21, x9
	cmp	x10, x12
	b.hs	LBB37_151
Ltmp770:
; %bb.142:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	add	x9, x22, x9
	add	x10, x21, x11
	cmp	x10, x9
	b.hs	LBB37_151
Ltmp771:
LBB37_143:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x24
Ltmp772:
LBB37_144:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 1              ; numeric-payload.c:772:21
	add	x9, x24, x25
	sub	x9, x9, x11
	lsl	x12, x11, #2
	add	x11, x22, x12
	add	x12, x21, x12
Ltmp773:
LBB37_145:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	;DEBUG_VALUE: added <- $x10
	.loc	0 772 21 is_stmt 0              ; numeric-payload.c:772:21
	ldr	w13, [x12], #4
Ltmp774:
	;DEBUG_VALUE: raw <- $w13
	cmp	w13, w27
	cset	w13, eq
Ltmp775:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x11]
Ltmp776:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x11], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp777:
	add	x10, x10, x13
Ltmp778:
	;DEBUG_VALUE: added <- $x10
	.loc	0 772 21                        ; numeric-payload.c:772:21
	subs	x9, x9, #1
Ltmp779:
	.loc	0 772 21                        ; numeric-payload.c:772:21
	b.ne	LBB37_145
	b	LBB37_134
Ltmp780:
LBB37_146:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	b.hs	LBB37_135
Ltmp781:
; %bb.147:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, x24
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x23, #4
	b.lo	LBB37_168
Ltmp782:
; %bb.148:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x10, x24
	ldr	x9, [sp, #32]                   ; 8-byte Folded Reload
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x9, #63
	b.ls	LBB37_168
Ltmp783:
; %bb.149:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x23, #16
	b.hs	LBB37_153
Ltmp784:
; %bb.150:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	b	LBB37_157
Ltmp785:
LBB37_151:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 1              ; numeric-payload.c:772:21
	cmp	x23, #16
	b.hs	LBB37_160
Ltmp786:
; %bb.152:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21 is_stmt 0                ; numeric-payload.c:0:21
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_164
Ltmp787:
LBB37_153:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	and	x9, x25, #0x1fff0
	lsl	x11, x24, #2
	ldp	x12, x10, [sp, #16]             ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
Ltmp788:
LBB37_154:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	cmeq.4s	v0, v0, v28
	and.16b	v0, v0, v29
	cmeq.4s	v1, v1, v28
	and.16b	v1, v1, v29
	cmeq.4s	v2, v2, v28
	and.16b	v2, v2, v29
	cmeq.4s	v3, v3, v28
	and.16b	v3, v3, v29
	stp	q0, q1, [x11, #-32]
	stp	q2, q3, [x11], #64
	subs	x12, x12, #16
	b.ne	LBB37_154
Ltmp789:
; %bb.155:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x25, x9
	b.eq	LBB37_135
Ltmp790:
; %bb.156:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x25, #0xc
	b.eq	LBB37_167
Ltmp791:
LBB37_157:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 1              ; numeric-payload.c:772:21
	and	x11, x25, #0x1fffc
	add	x10, x24, x11
	sub	x12, x9, x11
	add	x9, x9, x24
	lsl	x13, x9, #2
	add	x9, x22, x13
	add	x13, x21, x13
Ltmp792:
LBB37_158:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 0              ; numeric-payload.c:772:21
	ldr	q0, [x13], #16
	cmeq.4s	v0, v0, v28
	and.16b	v0, v0, v29
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_158
Ltmp793:
; %bb.159:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	cmp	x25, x11
	b.eq	LBB37_135
	b	LBB37_168
Ltmp794:
LBB37_160:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 21                          ; numeric-payload.c:0:21
	movi.2d	v0, #0000000000000000
Ltmp795:
	.loc	0 772 21                        ; numeric-payload.c:772:21
	and	x9, x25, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x12, x10, [sp, #16]             ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v6, #0000000000000000
Ltmp796:
LBB37_161:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	ldp	q16, q17, [x10, #-32]
	ldp	q18, q19, [x10], #64
	cmeq.4s	v16, v16, v28
	and.16b	v20, v16, v29
	cmeq.4s	v17, v17, v28
	and.16b	v21, v17, v29
	cmeq.4s	v18, v18, v28
	and.16b	v22, v18, v29
	cmeq.4s	v19, v19, v28
	and.16b	v23, v19, v29
	ldp	q24, q25, [x11, #-32]
	orr.16b	v20, v24, v20
	orr.16b	v21, v25, v21
	ldp	q26, q27, [x11]
	orr.16b	v22, v26, v22
	orr.16b	v23, v27, v23
	stp	q20, q21, [x11, #-32]
	stp	q22, q23, [x11], #64
	cmeq.4s	v20, v24, #0
	cmeq.4s	v21, v25, #0
	cmeq.4s	v22, v26, #0
	cmeq.4s	v23, v27, #0
	and.16b	v16, v16, v20
	and.16b	v17, v17, v21
	and.16b	v18, v18, v22
	and.16b	v19, v19, v23
	ushll.2d	v20, v16, #0
	dup.2d	v21, x28
	and.16b	v20, v20, v21
	ushll2.2d	v16, v16, #0
	and.16b	v16, v16, v21
	ushll.2d	v22, v17, #0
	and.16b	v22, v22, v21
	ushll2.2d	v17, v17, #0
	and.16b	v17, v17, v21
	ushll.2d	v23, v18, #0
	and.16b	v23, v23, v21
	ushll2.2d	v18, v18, #0
	and.16b	v18, v18, v21
	ushll.2d	v24, v19, #0
	and.16b	v24, v24, v21
	ushll2.2d	v19, v19, #0
	and.16b	v19, v19, v21
	add.2d	v1, v1, v16
	add.2d	v0, v0, v20
	add.2d	v4, v4, v17
	add.2d	v3, v3, v22
	add.2d	v7, v7, v18
	add.2d	v2, v2, v23
	add.2d	v6, v6, v19
	add.2d	v5, v5, v24
	subs	x12, x12, #16
	b.ne	LBB37_161
Ltmp797:
; %bb.162:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	add.2d	v0, v3, v0
	add.2d	v1, v4, v1
	add.2d	v1, v7, v1
	add.2d	v0, v2, v0
	add.2d	v0, v5, v0
	add.2d	v1, v6, v1
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x25, x9
	b.eq	LBB37_134
Ltmp798:
; %bb.163:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x25, #0xc
	b.eq	LBB37_170
Ltmp799:
LBB37_164:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 1              ; numeric-payload.c:772:21
	and	x12, x25, #0x1fffc
	add	x11, x24, x12
	movi.2d	v0, #0000000000000000
	mov.d	v0[0], x10
	movi.2d	v1, #0000000000000000
	sub	x10, x9, x12
	add	x9, x9, x24
	lsl	x13, x9, #2
	add	x9, x22, x13
	add	x13, x21, x13
Ltmp800:
LBB37_165:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21 is_stmt 0              ; numeric-payload.c:772:21
	ldr	q2, [x13], #16
	cmeq.4s	v2, v2, v28
	and.16b	v3, v2, v29
	ldr	q4, [x9]
	orr.16b	v3, v4, v3
	str	q3, [x9], #16
	cmeq.4s	v3, v4, #0
	and.16b	v2, v2, v3
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v30
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v30
	add.2d	v1, v1, v2
	add.2d	v0, v0, v3
	adds	x10, x10, #4
	b.ne	LBB37_165
Ltmp801:
; %bb.166:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x25, x12
	b.eq	LBB37_134
	b	LBB37_144
Ltmp802:
LBB37_167:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	add	x10, x24, x9
Ltmp803:
LBB37_168:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: i <- $x24
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x24, x25
	sub	x9, x9, x10
	lsl	x11, x10, #2
	add	x10, x22, x11
	add	x11, x21, x11
Ltmp804:
LBB37_169:                              ;   Parent Loop BB37_136 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 772 21                        ; numeric-payload.c:772:21
	ldr	w12, [x11], #4
Ltmp805:
	;DEBUG_VALUE: raw <- $w12
	cmp	w12, w27
	cset	w12, eq
Ltmp806:
	str	w12, [x10], #4
Ltmp807:
	.loc	0 772 21                        ; numeric-payload.c:772:21
	subs	x9, x9, #1
	b.ne	LBB37_169
	b	LBB37_135
Ltmp808:
LBB37_170:                              ;   in Loop: Header=BB37_136 Depth=1
	;DEBUG_VALUE: count <- $x25
	;DEBUG_VALUE: start <- $x24
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 772 21                        ; numeric-payload.c:772:21
	add	x11, x24, x9
	b	LBB37_144
Ltmp809:
LBB37_171:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	cbz	x9, LBB37_333
Ltmp810:
; %bb.172:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x27, #0                         ; =0x0
	.loc	0 765 14                        ; numeric-payload.c:765:14
	add	x22, x10, x1, lsl #2
	add	x8, x21, #32
	str	x8, [sp, #32]                   ; 8-byte Folded Spill
	add	x24, x22, #128
	mov	w25, #65536                     ; =0x10000
	movi.8b	v8, #100
	movi.4s	v26, #1
	movi.16b	v27, #100
	movi.4h	v9, #100
	mov	w26, #1                         ; =0x1
	dup.2d	v28, x26
	str	q28, [sp, #48]                  ; 16-byte Folded Spill
	b	LBB37_176
Ltmp811:
LBB37_173:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, #0                         ; =0x0
Ltmp812:
LBB37_174:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp813:
LBB37_175:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 765 14 is_stmt 0              ; numeric-payload.c:765:14
	ldr	x9, [x20, #8]
	mov	x27, x8
Ltmp814:
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x8, x9
Ltmp815:
	;DEBUG_VALUE: start <- $x27
	b.hs	LBB37_333
Ltmp816:
LBB37_176:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_195 Depth 2
                                        ;     Child Loop BB37_199 Depth 2
                                        ;     Child Loop BB37_185 Depth 2
                                        ;     Child Loop BB37_202 Depth 2
                                        ;     Child Loop BB37_206 Depth 2
                                        ;     Child Loop BB37_211 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x27
	.loc	0 765 14                        ; numeric-payload.c:765:14
	sub	x23, x9, x27
Ltmp817:
	;DEBUG_VALUE: count <- $x23
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x23, #16, lsl #12               ; =65536
	csel	x28, x23, x25, lo
Ltmp818:
	;DEBUG_VALUE: count <- $x28
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_178
Ltmp819:
; %bb.177:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp820:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 14                          ; numeric-payload.c:0:14
	ldr	q28, [sp, #48]                  ; 16-byte Folded Reload
	movi.16b	v27, #100
	movi.4s	v26, #1
Ltmp821:
LBB37_178:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	ldr	w9, [x19, #8]
	add	x8, x28, x27
	;DEBUG_VALUE: i <- $x27
	cmp	x27, x8
	cbz	w9, LBB37_186
Ltmp822:
; %bb.179:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	b.hs	LBB37_173
Ltmp823:
; %bb.180:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x23, #3
	b.ls	LBB37_183
Ltmp824:
; %bb.181:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x27, lsl #2
	add	x9, x21, x8
	cmp	x10, x9
	b.hs	LBB37_192
Ltmp825:
; %bb.182:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	add	x9, x27, x28
	add	x9, x22, x9, lsl #2
	add	x11, x21, x27
	cmp	x11, x9
	b.hs	LBB37_192
Ltmp826:
LBB37_183:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x27
Ltmp827:
LBB37_184:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	add	x9, x27, x28
	sub	x9, x9, x11
	add	x12, x21, x11
	add	x11, x22, x11, lsl #2
Ltmp828:
LBB37_185:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: added <- $x10
	;DEBUG_VALUE: i <- undef
	.loc	0 765 14 is_stmt 0              ; numeric-payload.c:765:14
	ldrsb	w13, [x12], #1
Ltmp829:
	;DEBUG_VALUE: raw <- undef
	cmp	w13, #100
	cset	w13, gt
Ltmp830:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x11]
Ltmp831:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x11], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp832:
	add	x10, x10, x13
Ltmp833:
	;DEBUG_VALUE: added <- $x10
	.loc	0 765 14                        ; numeric-payload.c:765:14
	subs	x9, x9, #1
Ltmp834:
	.loc	0 765 14                        ; numeric-payload.c:765:14
	b.ne	LBB37_185
	b	LBB37_174
Ltmp835:
LBB37_186:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	b.hs	LBB37_175
Ltmp836:
; %bb.187:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, x27
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x23, #7
	b.ls	LBB37_210
Ltmp837:
; %bb.188:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x22, x27, lsl #2
	add	x10, x21, x8
	cmp	x9, x10
	b.hs	LBB37_190
Ltmp838:
; %bb.189:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	add	x9, x27, x28
	add	x9, x22, x9, lsl #2
	add	x10, x21, x27
	cmp	x10, x9
	mov	x10, x27
	b.lo	LBB37_210
Ltmp839:
LBB37_190:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	cmp	x23, #64
	b.hs	LBB37_201
Ltmp840:
; %bb.191:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	b	LBB37_205
Ltmp841:
LBB37_192:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	cmp	x23, #16
	b.hs	LBB37_194
Ltmp842:
; %bb.193:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_198
Ltmp843:
LBB37_194:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	movi.2d	v0, #0000000000000000
	.loc	0 765 14                        ; numeric-payload.c:765:14
	and	x9, x28, #0x1fff0
	movi.2d	v1, #0000000000000000
	add	x11, x21, x27
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v6, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v5, #0000000000000000
Ltmp844:
LBB37_195:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	ldr	q16, [x11], #16
	cmgt.16b	v16, v16, v27
	ushll2.8h	v17, v16, #0
	ushll2.4s	v18, v17, #0
	and.16b	v18, v18, v26
	ushll.4s	v17, v17, #0
	and.16b	v17, v17, v26
	ushll.8h	v19, v16, #0
	ushll2.4s	v20, v19, #0
	and.16b	v20, v20, v26
	ushll.4s	v19, v19, #0
	and.16b	v19, v19, v26
	ldp	q22, q21, [x10, #32]
	ldp	q24, q23, [x10]
	orr.16b	v19, v24, v19
	orr.16b	v20, v23, v20
	orr.16b	v17, v22, v17
	orr.16b	v18, v21, v18
	stp	q17, q18, [x10, #32]
	stp	q19, q20, [x10], #64
	cmeq.4s	v17, v21, #0
	cmeq.4s	v18, v22, #0
	uzp1.8h	v17, v18, v17
	cmeq.4s	v18, v23, #0
	cmeq.4s	v19, v24, #0
	uzp1.8h	v18, v19, v18
	uzp1.16b	v17, v18, v17
	and.16b	v16, v16, v17
	mov	b17, v16[0]
	mov.b	v17[4], v16[1]
	ushll.2d	v17, v17, #0
	dup.2d	v18, x26
	and.16b	v17, v17, v18
	mov	b19, v16[2]
	mov.b	v19[4], v16[3]
	ushll.2d	v19, v19, #0
	and.16b	v19, v19, v18
	mov	b20, v16[4]
	mov.b	v20[4], v16[5]
	ushll.2d	v20, v20, #0
	and.16b	v20, v20, v18
	mov	b21, v16[6]
	mov.b	v21[4], v16[7]
	ushll.2d	v21, v21, #0
	and.16b	v21, v21, v18
	mov	b22, v16[8]
	mov.b	v22[4], v16[9]
	ushll.2d	v22, v22, #0
	and.16b	v22, v22, v18
	mov	b23, v16[10]
	mov.b	v23[4], v16[11]
	ushll.2d	v23, v23, #0
	mov	b24, v16[12]
	mov.b	v24[4], v16[13]
	and.16b	v23, v23, v18
	ushll.2d	v24, v24, #0
	and.16b	v24, v24, v18
	mov	b25, v16[14]
	mov.b	v25[4], v16[15]
	ushll.2d	v16, v25, #0
	and.16b	v16, v16, v18
	add.2d	v5, v5, v16
	add.2d	v7, v7, v24
	add.2d	v4, v4, v23
	add.2d	v6, v6, v22
	add.2d	v2, v2, v21
	add.2d	v3, v3, v20
	add.2d	v1, v1, v19
	add.2d	v0, v0, v17
	subs	x12, x12, #16
	b.ne	LBB37_195
Ltmp845:
; %bb.196:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	add.2d	v0, v0, v6
	add.2d	v3, v3, v7
	add.2d	v0, v0, v3
	add.2d	v1, v1, v4
	add.2d	v2, v2, v5
	add.2d	v1, v1, v2
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x28, x9
	b.eq	LBB37_174
Ltmp846:
; %bb.197:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x28, #0xc
	b.eq	LBB37_208
Ltmp847:
LBB37_198:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	and	x12, x28, #0x1fffc
	add	x11, x27, x12
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	mov.d	v1[0], x10
	sub	x10, x9, x12
	add	x13, x9, x27
	add	x9, x21, x13
	add	x13, x22, x13, lsl #2
Ltmp848:
LBB37_199:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 0              ; numeric-payload.c:765:14
	ldr	s2, [x9], #4
	sshll.8h	v2, v2, #0
	cmgt.4h	v2, v2, v9
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ldr	q4, [x13]
	orr.16b	v3, v4, v3
	str	q3, [x13], #16
	cmeq.4s	v3, v4, #0
	xtn.4h	v3, v3
	and.8b	v2, v2, v3
	ushll.4s	v2, v2, #0
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v28
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v28
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	adds	x10, x10, #4
	b.ne	LBB37_199
Ltmp849:
; %bb.200:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	add.2d	v0, v1, v0
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x28, x12
	b.eq	LBB37_174
	b	LBB37_184
Ltmp850:
LBB37_201:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	and	x9, x28, #0x1ffc0
	ldr	x10, [sp, #32]                  ; 8-byte Folded Reload
	add	x10, x10, x27
	add	x11, x24, x27, lsl #2
	mov	x12, x9
Ltmp851:
LBB37_202:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	ldp	q0, q1, [x10, #-32]
	cmgt.16b	v0, v0, v27
	ushll.8h	v2, v0, #0
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ushll2.4s	v2, v2, #0
	and.16b	v2, v2, v26
	ldp	q4, q5, [x10], #64
	ushll2.8h	v0, v0, #0
	ushll.4s	v6, v0, #0
	and.16b	v6, v6, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	cmgt.16b	v1, v1, v27
	ushll.8h	v7, v1, #0
	ushll.4s	v16, v7, #0
	and.16b	v16, v16, v26
	ushll2.4s	v7, v7, #0
	and.16b	v7, v7, v26
	ushll2.8h	v1, v1, #0
	ushll.4s	v17, v1, #0
	and.16b	v17, v17, v26
	ushll2.4s	v1, v1, #0
	and.16b	v1, v1, v26
	cmgt.16b	v4, v4, v27
	ushll.8h	v18, v4, #0
	ushll.4s	v19, v18, #0
	and.16b	v19, v19, v26
	ushll2.4s	v18, v18, #0
	and.16b	v18, v18, v26
	ushll2.8h	v4, v4, #0
	ushll.4s	v20, v4, #0
	and.16b	v20, v20, v26
	ushll2.4s	v4, v4, #0
	and.16b	v4, v4, v26
	stp	q6, q0, [x11, #-96]
	cmgt.16b	v0, v5, v27
	ushll.8h	v5, v0, #0
	ushll.4s	v6, v5, #0
	and.16b	v6, v6, v26
	stp	q3, q2, [x11, #-128]
	stp	q17, q1, [x11, #-32]
	ushll2.8h	v0, v0, #0
	ushll.4s	v1, v0, #0
	and.16b	v1, v1, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	stp	q16, q7, [x11, #-64]
	stp	q20, q4, [x11, #32]
	stp	q19, q18, [x11]
	stp	q1, q0, [x11, #96]
	ushll2.4s	v0, v5, #0
	and.16b	v0, v0, v26
	stp	q6, q0, [x11, #64]
	add	x11, x11, #256
	subs	x12, x12, #64
	b.ne	LBB37_202
Ltmp852:
; %bb.203:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x28, x9
	b.eq	LBB37_175
Ltmp853:
; %bb.204:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x28, #0x38
	b.eq	LBB37_209
Ltmp854:
LBB37_205:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	and	x11, x28, #0x1fff8
	add	x10, x27, x11
	sub	x12, x9, x11
	add	x13, x9, x27
	add	x9, x21, x13
	add	x13, x22, x13, lsl #2
Ltmp855:
LBB37_206:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 0              ; numeric-payload.c:765:14
	ldr	d0, [x9], #8
	cmgt.8b	v0, v0, v8
	ushll.8h	v0, v0, #0
	ushll.4s	v1, v0, #0
	and.16b	v1, v1, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	stp	q1, q0, [x13], #32
	adds	x12, x12, #8
	b.ne	LBB37_206
Ltmp856:
; %bb.207:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	cmp	x28, x11
	b.eq	LBB37_175
	b	LBB37_210
Ltmp857:
LBB37_208:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	add	x11, x27, x9
	b	LBB37_184
Ltmp858:
LBB37_209:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14                        ; numeric-payload.c:765:14
	add	x10, x27, x9
Ltmp859:
LBB37_210:                              ;   in Loop: Header=BB37_176 Depth=1
	;DEBUG_VALUE: i <- $x27
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 765 14 is_stmt 1              ; numeric-payload.c:765:14
	add	x9, x27, x28
	sub	x9, x9, x10
	add	x11, x21, x10
	add	x10, x22, x10, lsl #2
Ltmp860:
LBB37_211:                              ;   Parent Loop BB37_176 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x28
	;DEBUG_VALUE: start <- $x27
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 765 14 is_stmt 0              ; numeric-payload.c:765:14
	ldrsb	w12, [x11], #1
Ltmp861:
	;DEBUG_VALUE: raw <- undef
	cmp	w12, #100
	cset	w12, gt
	str	w12, [x10], #4
Ltmp862:
	.loc	0 765 14                        ; numeric-payload.c:765:14
	subs	x9, x9, #1
	b.ne	LBB37_211
	b	LBB37_175
Ltmp863:
LBB37_212:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	cbz	x9, LBB37_333
Ltmp864:
; %bb.213:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x25, #0                         ; =0x0
	mov	w22, #65508                     ; =0xffe4
	movk	w22, #32767, lsl #16
	.loc	0 773 14                        ; numeric-payload.c:773:14
	add	x23, x10, x1, lsl #2
	sub	x8, x23, x21
	str	x8, [sp, #24]                   ; 8-byte Folded Spill
	add	x10, x21, #32
Ltmp865:
	add	x8, x23, #32
	stp	x8, x10, [sp, #8]               ; 16-byte Folded Spill
	mov	w27, #65536                     ; =0x10000
	mvni.4s	v0, #27
	fneg.4s	v28, v0
	movi.4s	v29, #1
	mov	w28, #1                         ; =0x1
	dup.2d	v30, x28
	stp	q30, q28, [sp, #32]             ; 32-byte Folded Spill
	b	LBB37_217
Ltmp866:
LBB37_214:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, #0                         ; =0x0
Ltmp867:
LBB37_215:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp868:
LBB37_216:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 773 14 is_stmt 0              ; numeric-payload.c:773:14
	ldr	x9, [x20, #8]
	mov	x25, x8
Ltmp869:
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x8, x9
Ltmp870:
	;DEBUG_VALUE: start <- $x25
	b.hs	LBB37_333
Ltmp871:
LBB37_217:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_242 Depth 2
                                        ;     Child Loop BB37_246 Depth 2
                                        ;     Child Loop BB37_226 Depth 2
                                        ;     Child Loop BB37_235 Depth 2
                                        ;     Child Loop BB37_239 Depth 2
                                        ;     Child Loop BB37_250 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x25
	.loc	0 773 14                        ; numeric-payload.c:773:14
	sub	x24, x9, x25
Ltmp872:
	;DEBUG_VALUE: count <- $x24
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x24, #16, lsl #12               ; =65536
	csel	x26, x24, x27, lo
Ltmp873:
	;DEBUG_VALUE: count <- $x26
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_219
Ltmp874:
; %bb.218:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp875:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 14                          ; numeric-payload.c:0:14
	ldp	q30, q28, [sp, #32]             ; 32-byte Folded Reload
	movi.4s	v29, #1
Ltmp876:
LBB37_219:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	ldr	w9, [x19, #8]
	add	x8, x26, x25
	;DEBUG_VALUE: i <- $x25
	cmp	x25, x8
	cbz	w9, LBB37_227
Ltmp877:
; %bb.220:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	b.hs	LBB37_214
Ltmp878:
; %bb.221:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x24, #3
	b.ls	LBB37_224
Ltmp879:
; %bb.222:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	lsl	x11, x25, #2
	add	x10, x23, x11
	add	x9, x25, x26
	lsl	x9, x9, #2
	add	x12, x21, x9
	cmp	x10, x12
	b.hs	LBB37_232
Ltmp880:
; %bb.223:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	add	x9, x23, x9
	add	x10, x21, x11
	cmp	x10, x9
	b.hs	LBB37_232
Ltmp881:
LBB37_224:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x25
Ltmp882:
LBB37_225:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	add	x9, x25, x26
	sub	x9, x9, x11
	lsl	x12, x11, #2
	add	x11, x23, x12
	add	x12, x21, x12
Ltmp883:
LBB37_226:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	;DEBUG_VALUE: added <- $x10
	.loc	0 773 14 is_stmt 0              ; numeric-payload.c:773:14
	ldr	w13, [x12], #4
Ltmp884:
	;DEBUG_VALUE: raw <- $w13
	cmp	w13, w22
	cset	w13, gt
Ltmp885:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x11]
Ltmp886:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x11], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp887:
	add	x10, x10, x13
Ltmp888:
	;DEBUG_VALUE: added <- $x10
	.loc	0 773 14                        ; numeric-payload.c:773:14
	subs	x9, x9, #1
Ltmp889:
	.loc	0 773 14                        ; numeric-payload.c:773:14
	b.ne	LBB37_226
	b	LBB37_215
Ltmp890:
LBB37_227:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	b.hs	LBB37_216
Ltmp891:
; %bb.228:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, x25
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x24, #4
	b.lo	LBB37_249
Ltmp892:
; %bb.229:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, x25
	ldr	x9, [sp, #24]                   ; 8-byte Folded Reload
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x9, #63
	b.ls	LBB37_249
Ltmp893:
; %bb.230:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x24, #16
	b.hs	LBB37_234
Ltmp894:
; %bb.231:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	b	LBB37_238
Ltmp895:
LBB37_232:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	cmp	x24, #16
	b.hs	LBB37_241
Ltmp896:
; %bb.233:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_245
Ltmp897:
LBB37_234:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	and	x9, x26, #0x1fff0
	lsl	x11, x25, #2
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
Ltmp898:
LBB37_235:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	cmgt.4s	v0, v0, v28
	and.16b	v0, v0, v29
	cmgt.4s	v1, v1, v28
	and.16b	v1, v1, v29
	cmgt.4s	v2, v2, v28
	and.16b	v2, v2, v29
	cmgt.4s	v3, v3, v28
	and.16b	v3, v3, v29
	stp	q0, q1, [x11, #-32]
	stp	q2, q3, [x11], #64
	subs	x12, x12, #16
	b.ne	LBB37_235
Ltmp899:
; %bb.236:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x26, x9
	b.eq	LBB37_216
Ltmp900:
; %bb.237:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x26, #0xc
	b.eq	LBB37_248
Ltmp901:
LBB37_238:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	and	x11, x26, #0x1fffc
	add	x10, x25, x11
	sub	x12, x9, x11
	add	x9, x9, x25
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp902:
LBB37_239:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 0              ; numeric-payload.c:773:14
	ldr	q0, [x13], #16
	cmgt.4s	v0, v0, v28
	and.16b	v0, v0, v29
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_239
Ltmp903:
; %bb.240:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	cmp	x26, x11
	b.eq	LBB37_216
	b	LBB37_249
Ltmp904:
LBB37_241:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	movi.2d	v0, #0000000000000000
Ltmp905:
	.loc	0 773 14                        ; numeric-payload.c:773:14
	and	x9, x26, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v6, #0000000000000000
Ltmp906:
LBB37_242:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	ldp	q16, q17, [x10, #-32]
	ldp	q18, q19, [x10], #64
	cmgt.4s	v16, v16, v28
	and.16b	v20, v16, v29
	cmgt.4s	v17, v17, v28
	and.16b	v21, v17, v29
	cmgt.4s	v18, v18, v28
	and.16b	v22, v18, v29
	cmgt.4s	v19, v19, v28
	and.16b	v23, v19, v29
	ldp	q24, q25, [x11, #-32]
	orr.16b	v20, v24, v20
	orr.16b	v21, v25, v21
	ldp	q26, q27, [x11]
	orr.16b	v22, v26, v22
	orr.16b	v23, v27, v23
	stp	q20, q21, [x11, #-32]
	stp	q22, q23, [x11], #64
	cmeq.4s	v20, v24, #0
	cmeq.4s	v21, v25, #0
	cmeq.4s	v22, v26, #0
	cmeq.4s	v23, v27, #0
	and.16b	v16, v16, v20
	and.16b	v17, v17, v21
	and.16b	v18, v18, v22
	and.16b	v19, v19, v23
	ushll.2d	v20, v16, #0
	dup.2d	v21, x28
	and.16b	v20, v20, v21
	ushll2.2d	v16, v16, #0
	and.16b	v16, v16, v21
	ushll.2d	v22, v17, #0
	and.16b	v22, v22, v21
	ushll2.2d	v17, v17, #0
	and.16b	v17, v17, v21
	ushll.2d	v23, v18, #0
	and.16b	v23, v23, v21
	ushll2.2d	v18, v18, #0
	and.16b	v18, v18, v21
	ushll.2d	v24, v19, #0
	and.16b	v24, v24, v21
	ushll2.2d	v19, v19, #0
	and.16b	v19, v19, v21
	add.2d	v1, v1, v16
	add.2d	v0, v0, v20
	add.2d	v4, v4, v17
	add.2d	v3, v3, v22
	add.2d	v7, v7, v18
	add.2d	v2, v2, v23
	add.2d	v6, v6, v19
	add.2d	v5, v5, v24
	subs	x12, x12, #16
	b.ne	LBB37_242
Ltmp907:
; %bb.243:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	add.2d	v0, v3, v0
	add.2d	v1, v4, v1
	add.2d	v1, v7, v1
	add.2d	v0, v2, v0
	add.2d	v0, v5, v0
	add.2d	v1, v6, v1
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x26, x9
	b.eq	LBB37_215
Ltmp908:
; %bb.244:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x26, #0xc
	b.eq	LBB37_251
Ltmp909:
LBB37_245:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 1              ; numeric-payload.c:773:14
	and	x12, x26, #0x1fffc
	add	x11, x25, x12
	movi.2d	v0, #0000000000000000
	mov.d	v0[0], x10
	movi.2d	v1, #0000000000000000
	sub	x10, x9, x12
	add	x9, x9, x25
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp910:
LBB37_246:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14 is_stmt 0              ; numeric-payload.c:773:14
	ldr	q2, [x13], #16
	cmgt.4s	v2, v2, v28
	and.16b	v3, v2, v29
	ldr	q4, [x9]
	orr.16b	v3, v4, v3
	str	q3, [x9], #16
	cmeq.4s	v3, v4, #0
	and.16b	v2, v2, v3
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v30
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v30
	add.2d	v1, v1, v2
	add.2d	v0, v0, v3
	adds	x10, x10, #4
	b.ne	LBB37_246
Ltmp911:
; %bb.247:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x26, x12
	b.eq	LBB37_215
	b	LBB37_225
Ltmp912:
LBB37_248:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	add	x10, x25, x9
Ltmp913:
LBB37_249:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: i <- $x25
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x25, x26
	sub	x9, x9, x10
	lsl	x11, x10, #2
	add	x10, x23, x11
	add	x11, x21, x11
Ltmp914:
LBB37_250:                              ;   Parent Loop BB37_217 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 773 14                        ; numeric-payload.c:773:14
	ldr	w12, [x11], #4
Ltmp915:
	;DEBUG_VALUE: raw <- $w12
	cmp	w12, w22
	cset	w12, gt
Ltmp916:
	str	w12, [x10], #4
Ltmp917:
	.loc	0 773 14                        ; numeric-payload.c:773:14
	subs	x9, x9, #1
	b.ne	LBB37_250
	b	LBB37_216
Ltmp918:
LBB37_251:                              ;   in Loop: Header=BB37_217 Depth=1
	;DEBUG_VALUE: count <- $x26
	;DEBUG_VALUE: start <- $x25
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 773 14                        ; numeric-payload.c:773:14
	add	x11, x25, x9
	b	LBB37_225
Ltmp919:
LBB37_252:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	cbz	x9, LBB37_333
Ltmp920:
; %bb.253:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x26, #0                         ; =0x0
	.loc	0 769 14                        ; numeric-payload.c:769:14
	add	x22, x10, x1, lsl #2
	add	x10, x22, #32
Ltmp921:
	add	x8, x21, #16
	stp	x8, x10, [sp, #16]              ; 16-byte Folded Spill
	add	x10, x21, #32
	add	x8, x22, #64
	stp	x8, x10, [sp]                   ; 16-byte Folded Spill
	mov	w27, #65536                     ; =0x10000
	mov	w28, #32740                     ; =0x7fe4
	mvni.4h	v0, #27
	fneg.4h	v8, v0
	movi.4s	v26, #1
	mvni.8h	v0, #27
	fneg.8h	v27, v0
	mov	w25, #1                         ; =0x1
	dup.2d	v28, x25
	stp	q28, q27, [sp, #32]             ; 32-byte Folded Spill
	b	LBB37_257
Ltmp922:
LBB37_254:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, #0                         ; =0x0
Ltmp923:
LBB37_255:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp924:
LBB37_256:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 769 14 is_stmt 0              ; numeric-payload.c:769:14
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp925:
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x8, x9
Ltmp926:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB37_333
Ltmp927:
LBB37_257:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_276 Depth 2
                                        ;     Child Loop BB37_280 Depth 2
                                        ;     Child Loop BB37_266 Depth 2
                                        ;     Child Loop BB37_283 Depth 2
                                        ;     Child Loop BB37_287 Depth 2
                                        ;     Child Loop BB37_292 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x26
	.loc	0 769 14                        ; numeric-payload.c:769:14
	sub	x24, x9, x26
Ltmp928:
	;DEBUG_VALUE: count <- $x24
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x24, #16, lsl #12               ; =65536
	csel	x23, x24, x27, lo
Ltmp929:
	;DEBUG_VALUE: count <- $x23
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_259
Ltmp930:
; %bb.258:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp931:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 14                          ; numeric-payload.c:0:14
	ldp	q28, q27, [sp, #32]             ; 32-byte Folded Reload
	movi.4s	v26, #1
Ltmp932:
LBB37_259:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	ldr	w9, [x19, #8]
	add	x8, x23, x26
	;DEBUG_VALUE: i <- $x26
	cmp	x26, x8
	cbz	w9, LBB37_267
Ltmp933:
; %bb.260:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	b.hs	LBB37_254
Ltmp934:
; %bb.261:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x24, #3
	b.ls	LBB37_264
Ltmp935:
; %bb.262:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x26, lsl #2
	add	x9, x26, x23
	add	x11, x21, x9, lsl #1
	cmp	x10, x11
	b.hs	LBB37_273
Ltmp936:
; %bb.263:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	add	x9, x22, x9, lsl #2
	add	x10, x21, x26, lsl #1
	cmp	x10, x9
	b.hs	LBB37_273
Ltmp937:
LBB37_264:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x26
Ltmp938:
LBB37_265:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	add	x9, x26, x23
	sub	x9, x9, x11
	add	x12, x22, x11, lsl #2
	add	x11, x21, x11, lsl #1
Ltmp939:
LBB37_266:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: added <- $x10
	;DEBUG_VALUE: i <- undef
	.loc	0 769 14 is_stmt 0              ; numeric-payload.c:769:14
	ldrsh	w13, [x11], #2
Ltmp940:
	;DEBUG_VALUE: raw <- undef
	cmp	w13, w28
	cset	w13, gt
Ltmp941:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x12]
Ltmp942:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x12], #4
	cmp	w14, #0
	csel	w13, wzr, w13, ne
Ltmp943:
	add	x10, x10, x13
Ltmp944:
	;DEBUG_VALUE: added <- $x10
	.loc	0 769 14                        ; numeric-payload.c:769:14
	subs	x9, x9, #1
Ltmp945:
	.loc	0 769 14                        ; numeric-payload.c:769:14
	b.ne	LBB37_266
	b	LBB37_255
Ltmp946:
LBB37_267:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	b.hs	LBB37_256
Ltmp947:
; %bb.268:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	mov	x10, x26
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x24, #3
	b.ls	LBB37_291
Ltmp948:
; %bb.269:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x10, x22, x26, lsl #2
	add	x9, x26, x23
	add	x11, x21, x9, lsl #1
	cmp	x10, x11
	b.hs	LBB37_271
Ltmp949:
; %bb.270:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14                          ; numeric-payload.c:0:14
	add	x9, x22, x9, lsl #2
	add	x11, x21, x26, lsl #1
	mov	x10, x26
	cmp	x11, x9
	b.lo	LBB37_291
Ltmp950:
LBB37_271:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	cmp	x24, #32
	b.hs	LBB37_282
Ltmp951:
; %bb.272:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	b	LBB37_286
Ltmp952:
LBB37_273:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	cmp	x24, #16
	b.hs	LBB37_275
Ltmp953:
; %bb.274:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 14 is_stmt 0                ; numeric-payload.c:0:14
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_279
Ltmp954:
LBB37_275:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	movi.2d	v0, #0000000000000000
	.loc	0 769 14                        ; numeric-payload.c:769:14
	and	x9, x23, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x11, x10, [sp, #16]             ; 16-byte Folded Reload
	add	x10, x10, x26, lsl #2
	add	x11, x11, x26, lsl #1
	mov	x12, x9
	movi.2d	v2, #0000000000000000
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v6, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v7, #0000000000000000
Ltmp955:
LBB37_276:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	ldp	q16, q17, [x11, #-16]
	cmgt.8h	v16, v16, v27
	ushll2.4s	v18, v16, #0
	and.16b	v18, v18, v26
	ushll.4s	v19, v16, #0
	and.16b	v19, v19, v26
	cmgt.8h	v17, v17, v27
	ushll2.4s	v20, v17, #0
	and.16b	v20, v20, v26
	ushll.4s	v21, v17, #0
	and.16b	v21, v21, v26
	ldp	q23, q22, [x10, #-32]
	ldp	q25, q24, [x10]
	orr.16b	v19, v23, v19
	orr.16b	v18, v22, v18
	orr.16b	v21, v25, v21
	orr.16b	v20, v24, v20
	stp	q19, q18, [x10, #-32]
	stp	q21, q20, [x10], #64
	cmeq.4s	v18, v22, #0
	cmeq.4s	v19, v23, #0
	uzp1.8h	v18, v19, v18
	cmeq.4s	v19, v24, #0
	cmeq.4s	v20, v25, #0
	uzp1.8h	v19, v20, v19
	and.16b	v16, v16, v18
	xtn.8b	v20, v16
	and.16b	v16, v17, v19
	xtn.8b	v16, v16
	mov	b17, v20[0]
	mov.b	v17[4], v20[1]
	dup.2d	v18, x25
	ushll.2d	v17, v17, #0
	and.16b	v17, v17, v18
	mov	b19, v20[2]
	mov.b	v19[4], v20[3]
	ushll.2d	v19, v19, #0
	and.16b	v19, v19, v18
	mov	b21, v20[4]
	mov.b	v21[4], v20[5]
	ushll.2d	v21, v21, #0
	and.16b	v21, v21, v18
	mov	b22, v20[6]
	mov.b	v22[4], v20[7]
	ushll.2d	v20, v22, #0
	and.16b	v20, v20, v18
	mov	b22, v16[0]
	mov.b	v22[4], v16[1]
	ushll.2d	v22, v22, #0
	mov	b23, v16[2]
	mov.b	v23[4], v16[3]
	and.16b	v22, v22, v18
	ushll.2d	v23, v23, #0
	and.16b	v23, v23, v18
	mov	b24, v16[4]
	mov.b	v24[4], v16[5]
	ushll.2d	v24, v24, #0
	and.16b	v24, v24, v18
	mov	b25, v16[6]
	mov.b	v25[4], v16[7]
	ushll.2d	v16, v25, #0
	and.16b	v16, v16, v18
	add.2d	v3, v3, v20
	add.2d	v2, v2, v21
	add.2d	v1, v1, v19
	add.2d	v0, v0, v17
	add.2d	v7, v7, v16
	add.2d	v5, v5, v24
	add.2d	v6, v6, v23
	add.2d	v4, v4, v22
	add	x11, x11, #32
	subs	x12, x12, #16
	b.ne	LBB37_276
Ltmp956:
; %bb.277:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	add.2d	v1, v6, v1
	add.2d	v3, v7, v3
	add.2d	v0, v4, v0
	add.2d	v2, v5, v2
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x23, x9
	b.eq	LBB37_255
Ltmp957:
; %bb.278:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x23, #0xc
	b.eq	LBB37_289
Ltmp958:
LBB37_279:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	and	x12, x23, #0x1fffc
	add	x11, x26, x12
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	mov.d	v1[0], x10
	sub	x10, x9, x12
	add	x13, x9, x26
	add	x9, x22, x13, lsl #2
	add	x13, x21, x13, lsl #1
Ltmp959:
LBB37_280:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 0              ; numeric-payload.c:769:14
	ldr	d2, [x13], #8
	cmgt.4h	v2, v2, v8
	ushll.4s	v3, v2, #0
	and.16b	v3, v3, v26
	ldr	q4, [x9]
	orr.16b	v3, v4, v3
	str	q3, [x9], #16
	cmeq.4s	v3, v4, #0
	xtn.4h	v3, v3
	and.8b	v2, v2, v3
	ushll.4s	v2, v2, #0
	ushll.2d	v3, v2, #0
	and.16b	v3, v3, v28
	ushll2.2d	v2, v2, #0
	and.16b	v2, v2, v28
	add.2d	v0, v0, v2
	add.2d	v1, v1, v3
	adds	x10, x10, #4
	b.ne	LBB37_280
Ltmp960:
; %bb.281:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	add.2d	v0, v1, v0
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x23, x12
	b.eq	LBB37_255
	b	LBB37_265
Ltmp961:
LBB37_282:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	and	x9, x23, #0x1ffe0
	ldp	x11, x10, [sp]                  ; 16-byte Folded Reload
	add	x10, x10, x26, lsl #1
	add	x11, x11, x26, lsl #2
	mov	x12, x9
Ltmp962:
LBB37_283:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	cmgt.8h	v0, v0, v27
	ushll.4s	v4, v0, #0
	and.16b	v4, v4, v26
	ushll2.4s	v0, v0, #0
	and.16b	v0, v0, v26
	cmgt.8h	v1, v1, v27
	ushll.4s	v5, v1, #0
	and.16b	v5, v5, v26
	ushll2.4s	v1, v1, #0
	and.16b	v1, v1, v26
	cmgt.8h	v2, v2, v27
	ushll.4s	v6, v2, #0
	and.16b	v6, v6, v26
	ushll2.4s	v2, v2, #0
	and.16b	v2, v2, v26
	cmgt.8h	v3, v3, v27
	ushll.4s	v7, v3, #0
	and.16b	v7, v7, v26
	stp	q4, q0, [x11, #-64]
	ushll2.4s	v0, v3, #0
	stp	q5, q1, [x11, #-32]
	stp	q6, q2, [x11]
	and.16b	v0, v0, v26
	stp	q7, q0, [x11, #32]
	add	x11, x11, #128
	subs	x12, x12, #32
	b.ne	LBB37_283
Ltmp963:
; %bb.284:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x23, x9
	b.eq	LBB37_256
Ltmp964:
; %bb.285:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x23, #0x1c
	b.eq	LBB37_290
Ltmp965:
LBB37_286:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	and	x11, x23, #0x1fffc
	add	x10, x26, x11
	sub	x12, x9, x11
	add	x13, x9, x26
	add	x9, x22, x13, lsl #2
	add	x13, x21, x13, lsl #1
Ltmp966:
LBB37_287:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 0              ; numeric-payload.c:769:14
	ldr	d0, [x13], #8
	cmgt.4h	v0, v0, v8
	ushll.4s	v0, v0, #0
	and.16b	v0, v0, v26
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_287
Ltmp967:
; %bb.288:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	cmp	x23, x11
	b.eq	LBB37_256
	b	LBB37_291
Ltmp968:
LBB37_289:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	add	x11, x26, x9
	b	LBB37_265
Ltmp969:
LBB37_290:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14                        ; numeric-payload.c:769:14
	add	x10, x26, x9
Ltmp970:
LBB37_291:                              ;   in Loop: Header=BB37_257 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 769 14 is_stmt 1              ; numeric-payload.c:769:14
	add	x9, x26, x23
	sub	x9, x9, x10
	add	x11, x22, x10, lsl #2
	add	x10, x21, x10, lsl #1
Ltmp971:
LBB37_292:                              ;   Parent Loop BB37_257 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x23
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 769 14 is_stmt 0              ; numeric-payload.c:769:14
	ldrsh	w12, [x10], #2
Ltmp972:
	;DEBUG_VALUE: raw <- undef
	cmp	w12, w28
	cset	w12, gt
	str	w12, [x11], #4
Ltmp973:
	.loc	0 769 14                        ; numeric-payload.c:769:14
	subs	x9, x9, #1
	b.ne	LBB37_292
	b	LBB37_256
Ltmp974:
LBB37_293:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: start <- 0
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	cbz	x9, LBB37_333
Ltmp975:
; %bb.294:
	;DEBUG_VALUE: start <- 0
	;DEBUG_VALUE: output <- [DW_OP_LLVM_arg 0, DW_OP_LLVM_arg 1, DW_OP_constu 4, DW_OP_mul, DW_OP_plus, DW_OP_stack_value] $x10, $x1
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 0 13 is_stmt 0                ; numeric-payload.c:0:13
	mov	x26, #0                         ; =0x0
	mov	w22, #-2130706432               ; =0x81000000
	.loc	0 781 13                        ; numeric-payload.c:781:13
	add	x23, x10, x1, lsl #2
	sub	x8, x23, x21
	str	x8, [sp, #24]                   ; 8-byte Folded Spill
	add	x10, x21, #32
Ltmp976:
	add	x8, x23, #32
	stp	x8, x10, [sp, #8]               ; 16-byte Folded Spill
	mov	w16, #65536                     ; =0x10000
	mov	w28, #53248                     ; =0xd000
	mov	w8, #53249                      ; =0xd001
	dup.4s	v28, w8
	mov	w25, #2139095040                ; =0x7f800000
	movi.4s	v29, #129, lsl #24
	movi.4s	v30, #7, msl #8
	mvni.4s	v0, #127, msl #16
	fneg.4s	v31, v0
	movi.4s	v8, #1
	stp	q31, q28, [sp, #32]             ; 32-byte Folded Spill
	b	LBB37_298
Ltmp977:
LBB37_295:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, #0                         ; =0x0
Ltmp978:
LBB37_296:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	ldr	x9, [x19, #16]
	add	x9, x9, x10
	str	x9, [x19, #16]
Ltmp979:
LBB37_297:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x8
	.loc	0 781 13 is_stmt 0              ; numeric-payload.c:781:13
	ldr	x9, [x20, #8]
	mov	x26, x8
Ltmp980:
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x8, x9
Ltmp981:
	;DEBUG_VALUE: start <- $x26
	b.hs	LBB37_333
Ltmp982:
LBB37_298:                              ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB37_323 Depth 2
                                        ;     Child Loop BB37_327 Depth 2
                                        ;     Child Loop BB37_307 Depth 2
                                        ;     Child Loop BB37_316 Depth 2
                                        ;     Child Loop BB37_320 Depth 2
                                        ;     Child Loop BB37_331 Depth 2
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: start <- $x26
	.loc	0 781 13                        ; numeric-payload.c:781:13
	sub	x27, x9, x26
Ltmp983:
	;DEBUG_VALUE: count <- $x27
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x27, #16, lsl #12               ; =65536
	csel	x24, x27, x16, lo
Ltmp984:
	;DEBUG_VALUE: count <- $x24
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x9, #4, lsl #12                 ; =16384
	b.lo	LBB37_300
Ltmp985:
; %bb.299:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	bl	_R_CheckUserInterrupt
Ltmp986:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loc	0 0 13                          ; numeric-payload.c:0:13
	movi.4s	v8, #1
	ldp	q31, q28, [sp, #32]             ; 32-byte Folded Reload
	movi.4s	v30, #7, msl #8
	movi.4s	v29, #129, lsl #24
	mov	w16, #65536                     ; =0x10000
Ltmp987:
LBB37_300:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	ldr	w9, [x19, #8]
	add	x8, x24, x26
	;DEBUG_VALUE: i <- $x26
	cmp	x26, x8
	cbz	w9, LBB37_308
Ltmp988:
; %bb.301:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	b.hs	LBB37_295
Ltmp989:
; %bb.302:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x27, #3
	b.ls	LBB37_305
Ltmp990:
; %bb.303:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	lsl	x11, x26, #2
	add	x10, x23, x11
	add	x9, x26, x24
	lsl	x9, x9, #2
	add	x12, x21, x9
	cmp	x10, x12
	b.hs	LBB37_313
Ltmp991:
; %bb.304:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	add	x9, x23, x9
	add	x10, x21, x11
	cmp	x10, x9
	b.hs	LBB37_313
Ltmp992:
LBB37_305:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	mov	x10, #0                         ; =0x0
	mov	x11, x26
Ltmp993:
LBB37_306:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	add	x9, x26, x24
	sub	x9, x9, x11
	lsl	x12, x11, #2
	add	x11, x23, x12
	add	x12, x21, x12
Ltmp994:
LBB37_307:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	;DEBUG_VALUE: added <- $x10
	.loc	0 781 13 is_stmt 0              ; numeric-payload.c:781:13
	ldr	w13, [x12], #4
Ltmp995:
	;DEBUG_VALUE: raw <- $w13
	add	w14, w13, w22
	tst	w13, #0x7ff
	ccmp	w14, w28, #2, eq
	and	w13, w13, #0x7fffffff
Ltmp996:
	ccmp	w13, w25, #2, hi
	cset	w13, hi
Ltmp997:
	;DEBUG_VALUE: missing <- $w13
	ldr	w14, [x11]
Ltmp998:
	;DEBUG_VALUE: previous <- $w14
	orr	w15, w14, w13
	str	w15, [x11], #4
	cmp	w14, #0
	csel	w13, w13, wzr, eq
Ltmp999:
	add	x10, x10, x13
Ltmp1000:
	;DEBUG_VALUE: added <- $x10
	.loc	0 781 13                        ; numeric-payload.c:781:13
	subs	x9, x9, #1
Ltmp1001:
	.loc	0 781 13                        ; numeric-payload.c:781:13
	b.ne	LBB37_307
	b	LBB37_296
Ltmp1002:
LBB37_308:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	b.hs	LBB37_297
Ltmp1003:
; %bb.309:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, x26
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x27, #4
	b.lo	LBB37_330
Ltmp1004:
; %bb.310:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x10, x26
	ldr	x9, [sp, #24]                   ; 8-byte Folded Reload
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x9, #63
	b.ls	LBB37_330
Ltmp1005:
; %bb.311:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	cmp	x27, #16
	b.hs	LBB37_315
Ltmp1006:
; %bb.312:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	mov	x9, #0                          ; =0x0
	b	LBB37_319
Ltmp1007:
LBB37_313:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	cmp	x27, #16
	b.hs	LBB37_322
Ltmp1008:
; %bb.314:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13 is_stmt 0                ; numeric-payload.c:0:13
	mov	x9, #0                          ; =0x0
	mov	x10, #0                         ; =0x0
	b	LBB37_326
Ltmp1009:
LBB37_315:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	and	x9, x24, #0x1fff0
	lsl	x11, x26, #2
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
Ltmp1010:
LBB37_316:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	add.4s	v4, v0, v29
	add.4s	v5, v1, v29
	add.4s	v6, v2, v29
	add.4s	v7, v3, v29
	cmhi.4s	v4, v28, v4
	cmhi.4s	v5, v28, v5
	cmhi.4s	v6, v28, v6
	cmhi.4s	v7, v28, v7
	and.16b	v16, v0, v30
	and.16b	v17, v1, v30
	and.16b	v18, v2, v30
	and.16b	v19, v3, v30
	cmeq.4s	v16, v16, #0
	cmeq.4s	v17, v17, #0
	cmeq.4s	v18, v18, #0
	cmeq.4s	v19, v19, #0
	and.16b	v4, v4, v16
	and.16b	v5, v5, v17
	and.16b	v6, v6, v18
	and.16b	v7, v7, v19
	bic.4s	v0, #128, lsl #24
	bic.4s	v1, #128, lsl #24
	bic.4s	v2, #128, lsl #24
	bic.4s	v3, #128, lsl #24
	cmhi.4s	v0, v0, v31
	cmhi.4s	v1, v1, v31
	cmhi.4s	v2, v2, v31
	cmhi.4s	v3, v3, v31
	orr.16b	v0, v0, v4
	orr.16b	v1, v1, v5
	orr.16b	v2, v2, v6
	orr.16b	v3, v3, v7
	and.16b	v0, v0, v8
	and.16b	v1, v1, v8
	and.16b	v2, v2, v8
	stp	q0, q1, [x11, #-32]
	and.16b	v0, v3, v8
	stp	q2, q0, [x11], #64
	subs	x12, x12, #16
	b.ne	LBB37_316
Ltmp1011:
; %bb.317:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x24, x9
	b.eq	LBB37_297
Ltmp1012:
; %bb.318:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x24, #0xc
	b.eq	LBB37_329
Ltmp1013:
LBB37_319:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	and	x11, x24, #0x1fffc
	add	x10, x26, x11
	sub	x12, x9, x11
	add	x9, x9, x26
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp1014:
LBB37_320:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 0              ; numeric-payload.c:781:13
	ldr	q0, [x13], #16
	add.4s	v1, v0, v29
	cmhi.4s	v1, v28, v1
	and.16b	v2, v0, v30
	cmeq.4s	v2, v2, #0
	and.16b	v1, v1, v2
	bic.4s	v0, #128, lsl #24
	cmhi.4s	v0, v0, v31
	orr.16b	v0, v0, v1
	and.16b	v0, v0, v8
	str	q0, [x9], #16
	adds	x12, x12, #4
	b.ne	LBB37_320
Ltmp1015:
; %bb.321:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	cmp	x24, x11
	b.eq	LBB37_297
	b	LBB37_330
Ltmp1016:
LBB37_322:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 0 13                          ; numeric-payload.c:0:13
	movi.2d	v0, #0000000000000000
Ltmp1017:
	.loc	0 781 13                        ; numeric-payload.c:781:13
	and	x9, x24, #0x1fff0
	movi.2d	v1, #0000000000000000
	ldp	x12, x10, [sp, #8]              ; 16-byte Folded Reload
	add	x10, x10, x11
	add	x11, x12, x11
	mov	x12, x9
	movi.2d	v3, #0000000000000000
	movi.2d	v4, #0000000000000000
	movi.2d	v5, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v7, #0000000000000000
	movi.2d	v6, #0000000000000000
Ltmp1018:
LBB37_323:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	ldp	q16, q17, [x10, #-32]
	add.4s	v18, v16, v29
	add.4s	v19, v17, v29
	ldp	q20, q21, [x10], #64
	add.4s	v22, v20, v29
	add.4s	v23, v21, v29
	cmhi.4s	v18, v28, v18
	cmhi.4s	v19, v28, v19
	cmhi.4s	v22, v28, v22
	cmhi.4s	v23, v28, v23
	and.16b	v24, v16, v30
	and.16b	v25, v17, v30
	and.16b	v26, v20, v30
	and.16b	v27, v21, v30
	cmeq.4s	v24, v24, #0
	cmeq.4s	v25, v25, #0
	cmeq.4s	v26, v26, #0
	cmeq.4s	v27, v27, #0
	and.16b	v18, v18, v24
	and.16b	v19, v19, v25
	and.16b	v22, v22, v26
	and.16b	v23, v23, v27
	bic.4s	v16, #128, lsl #24
	bic.4s	v17, #128, lsl #24
	bic.4s	v20, #128, lsl #24
	bic.4s	v21, #128, lsl #24
	cmhi.4s	v16, v16, v31
	cmhi.4s	v17, v17, v31
	cmhi.4s	v20, v20, v31
	cmhi.4s	v21, v21, v31
	orr.16b	v16, v16, v18
	orr.16b	v17, v17, v19
	orr.16b	v18, v20, v22
	orr.16b	v19, v21, v23
	and.16b	v16, v16, v8
	and.16b	v17, v17, v8
	and.16b	v18, v18, v8
	and.16b	v19, v19, v8
	ldp	q20, q21, [x11, #-32]
	ldp	q22, q23, [x11]
	orr.16b	v24, v20, v16
	orr.16b	v25, v21, v17
	orr.16b	v26, v22, v18
	orr.16b	v27, v23, v19
	stp	q24, q25, [x11, #-32]
	stp	q26, q27, [x11], #64
	cmeq.4s	v20, v20, #0
	cmeq.4s	v21, v21, #0
	cmeq.4s	v22, v22, #0
	cmeq.4s	v23, v23, #0
	and.16b	v16, v20, v16
	and.16b	v17, v21, v17
	and.16b	v18, v22, v18
	and.16b	v19, v23, v19
	uaddw2.2d	v1, v1, v16
	uaddw.2d	v0, v0, v16
	uaddw2.2d	v4, v4, v17
	uaddw.2d	v3, v3, v17
	uaddw2.2d	v2, v2, v18
	uaddw.2d	v5, v5, v18
	uaddw2.2d	v6, v6, v19
	uaddw.2d	v7, v7, v19
	subs	x12, x12, #16
	b.ne	LBB37_323
Ltmp1019:
; %bb.324:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	add.2d	v0, v3, v0
	add.2d	v1, v4, v1
	add.2d	v3, v7, v5
	add.2d	v0, v3, v0
	add.2d	v2, v6, v2
	add.2d	v1, v2, v1
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x24, x9
	b.eq	LBB37_296
Ltmp1020:
; %bb.325:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	tst	x24, #0xc
	b.eq	LBB37_332
Ltmp1021:
LBB37_326:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 1              ; numeric-payload.c:781:13
	and	x12, x24, #0x1fffc
	add	x11, x26, x12
	movi.2d	v0, #0000000000000000
	mov.d	v0[0], x10
	movi.2d	v1, #0000000000000000
	sub	x10, x9, x12
	add	x9, x9, x26
	lsl	x13, x9, #2
	add	x9, x23, x13
	add	x13, x21, x13
Ltmp1022:
LBB37_327:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13 is_stmt 0              ; numeric-payload.c:781:13
	ldr	q2, [x13], #16
	add.4s	v3, v2, v29
	cmhi.4s	v3, v28, v3
	and.16b	v4, v2, v30
	cmeq.4s	v4, v4, #0
	and.16b	v3, v3, v4
	bic.4s	v2, #128, lsl #24
	cmhi.4s	v2, v2, v31
	orr.16b	v2, v2, v3
	and.16b	v2, v2, v8
	ldr	q3, [x9]
	orr.16b	v4, v3, v2
	str	q4, [x9], #16
	cmeq.4s	v3, v3, #0
	and.16b	v2, v3, v2
	uaddw2.2d	v1, v1, v2
	uaddw.2d	v0, v0, v2
	adds	x10, x10, #4
	b.ne	LBB37_327
Ltmp1023:
; %bb.328:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	add.2d	v0, v0, v1
	addp.2d	d0, v0
	fmov	x10, d0
	cmp	x24, x12
	b.eq	LBB37_296
	b	LBB37_306
Ltmp1024:
LBB37_329:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	add	x10, x26, x9
Ltmp1025:
LBB37_330:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: i <- $x26
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	add	x9, x26, x24
	sub	x9, x9, x10
	lsl	x11, x10, #2
	add	x10, x23, x11
	add	x11, x21, x11
Ltmp1026:
LBB37_331:                              ;   Parent Loop BB37_298 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: i <- undef
	.loc	0 781 13                        ; numeric-payload.c:781:13
	ldr	w12, [x11], #4
Ltmp1027:
	;DEBUG_VALUE: raw <- $w12
	add	w13, w12, w22
	tst	w12, #0x7ff
	ccmp	w13, w28, #2, eq
	and	w12, w12, #0x7fffffff
Ltmp1028:
	ccmp	w12, w25, #2, hi
	cset	w12, hi
	str	w12, [x10], #4
Ltmp1029:
	.loc	0 781 13                        ; numeric-payload.c:781:13
	subs	x9, x9, #1
	b.ne	LBB37_331
	b	LBB37_297
Ltmp1030:
LBB37_332:                              ;   in Loop: Header=BB37_298 Depth=1
	;DEBUG_VALUE: count <- $x24
	;DEBUG_VALUE: start <- $x26
	;DEBUG_VALUE: bytes <- $x21
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 781 13                        ; numeric-payload.c:781:13
	add	x11, x26, x9
	b	LBB37_306
Ltmp1031:
LBB37_333:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	.loc	0 790 1 epilogue_begin is_stmt 1 ; numeric-payload.c:790:1
	ldp	x29, x30, [sp, #160]            ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #144]            ; 16-byte Folded Reload
Ltmp1032:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- [DW_OP_LLVM_entry_value 1] $x0
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- [DW_OP_LLVM_entry_value 1] $x2
	ldp	x22, x21, [sp, #128]            ; 16-byte Folded Reload
	ldp	x24, x23, [sp, #112]            ; 16-byte Folded Reload
	ldp	x26, x25, [sp, #96]             ; 16-byte Folded Reload
	ldp	x28, x27, [sp, #80]             ; 16-byte Folded Reload
	ldp	d9, d8, [sp, #64]               ; 16-byte Folded Reload
	add	sp, sp, #176
	ret
Ltmp1033:
LBB37_334:
	;DEBUG_VALUE: numeric_missing_mask_span:span <- $x20
	;DEBUG_VALUE: numeric_missing_mask_span:context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:raw_context <- $x19
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- $x1
	.loc	0 788 9                         ; numeric-payload.c:788:9
Lloh176:
	adrp	x0, l_.str.37@PAGE
Lloh177:
	add	x0, x0, l_.str.37@PAGEOFF
	bl	_Rf_error
Ltmp1034:
	;DEBUG_VALUE: numeric_missing_mask_span:offset <- [DW_OP_LLVM_entry_value 1] $x1
	.loh AdrpAdd	Lloh176, Lloh177
Lfunc_end37:
