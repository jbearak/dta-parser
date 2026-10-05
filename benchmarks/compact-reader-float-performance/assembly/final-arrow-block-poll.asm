  5de370: aa0803fc     	mov	x28, x8
  5de374: f14042bf     	cmp	x21, #0x10, lsl #12     ; =0x10000
  5de378: 52a00028     	mov	w8, #0x10000            ; =65536
  5de37c: 9a8832bb     	csel	x27, x21, x8, lo
  5de380: 97f3ad26     	bl	0x2c9818 <_dtatools_check_interrupt>
  5de384: 35003900     	cbnz	w0, 0x5deaa4 <__RINvNtCs6PmCChrtvwX_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x15b4>
  5de388: 52800009     	mov	w9, #0x0                ; =0
  5de38c: 5280000b     	mov	w11, #0x0               ; =0
  5de390: d280000a     	mov	x10, #0x0               ; =0
  5de394: cb1b02b5     	sub	x21, x21, x27
  5de398: d37ef76e     	lsl	x14, x27, #2
  5de39c: 1280000c     	mov	w12, #-0x1              ; =-1
  5de3a0: 5280002d     	mov	w13, #0x1               ; =1
  5de3a4: 8b1b0b88     	add	x8, x28, x27, lsl #2
