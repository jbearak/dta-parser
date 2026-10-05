  5de3a8: b8404790     	ldr	w16, [x28], #0x4
  5de3ac: 12007a0f     	and	w15, w16, #0x7fffffff
  5de3b0: 53187a11     	ubfx	w17, w16, #24, #7
  5de3b4: 7101fe3f     	cmp	w17, #0x7f
  5de3b8: 1a9f27e0     	cset	w0, lo
  5de3bc: 0b1a0201     	add	w1, w16, w26
  5de3c0: 72002a1f     	tst	w16, #0x7ff
  5de3c4: 7a560022     	ccmp	w1, w22, #0x2, eq
  5de3c8: 1a9f87f0     	cset	w16, ls
  5de3cc: 1a9f8400     	csinc	w0, w0, wzr, hi
  5de3d0: 0a0001ad     	and	w13, w13, w0
  5de3d4: 6b0b01ff     	cmp	w15, w11
  5de3d8: 1a8b81e0     	csel	w0, w15, w11, hi
  5de3dc: 6b0c01ff     	cmp	w15, w12
  5de3e0: 1a8c31e1     	csel	w1, w15, w12, lo
  5de3e4: 710001ff     	cmp	w15, #0x0
  5de3e8: 1a810181     	csel	w1, w12, w1, eq
  5de3ec: 1a9f17e2     	cset	w2, eq
  5de3f0: 7101fa3f     	cmp	w17, #0x7e
  5de3f4: 1a80816b     	csel	w11, w11, w0, hi
  5de3f8: 1a81818c     	csel	w12, w12, w1, hi
  5de3fc: 9a8283f1     	csel	x17, xzr, x2, hi
  5de400: 8b0a022a     	add	x10, x17, x10
  5de404: 6b1801ff     	cmp	w15, w24
  5de408: 1a9f960f     	csinc	w15, w16, wzr, ls
  5de40c: 0b0f0129     	add	w9, w9, w15
  5de410: f10011ce     	subs	x14, x14, #0x4
  5de414: 54fffca1     	b.ne	0x5de3a8 <__RINvNtCs6PmCChrtvwX_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0xeb8>
