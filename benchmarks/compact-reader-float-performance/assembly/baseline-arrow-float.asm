  5a155c: f94053e8     	ldr	x8, [sp, #0xa0]
  5a1560: bc404500     	ldr	s0, [x8], #0x4
  5a1564: f90053e8     	str	x8, [sp, #0xa0]
  5a1568: 1e202000     	fcmp	s0, s0
  5a156c: 54000166     	b.vs	0x5a1598 <__RINvNtCsfKb3QaXQt7u_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x1308>
  5a1570: 1e260000     	fmov	w0, s0
  5a1574: aa1403e1     	mov	x1, x20
  5a1578: 97fcbc0d     	bl	0x4d05ac <__RNvNtCsj8z43JjVsAT_9dta_tools7missing39classify_float_missing_bits_for_version>
  5a157c: 52801fe8     	mov	w8, #0xff               ; =255
  5a1580: 6a20011f     	bics	wzr, w8, w0
  5a1584: 1a9f07e8     	cset	w8, ne
  5a1588: 0b1c011c     	add	w28, w8, w28
  5a158c: f100075a     	subs	x26, x26, #0x1
  5a1590: 54fffe61     	b.ne	0x5a155c <__RINvNtCsfKb3QaXQt7u_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x12cc>
  5a1594: 17ffffe1     	b	0x5a1518 <__RINvNtCsfKb3QaXQt7u_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x1288>
  5a1598: 52800028     	mov	w8, #0x1                ; =1
  5a159c: 0b1c011c     	add	w28, w8, w28
  5a15a0: f100075a     	subs	x26, x26, #0x1
  5a15a4: 54fffdc1     	b.ne	0x5a155c <__RINvNtCsfKb3QaXQt7u_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x12cc>
  5a15a8: 17ffffdc     	b	0x5a1518 <__RINvNtCsfKb3QaXQt7u_10dtatools_r13owned_numeric18prepare_from_arrowNvB4_16coarse_interruptEB4_+0x1288>
