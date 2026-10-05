  566580: 0b0d0221     	add	w1, w17, w13
  566584: 7140343f     	cmp	w1, #0xd, lsl #12       ; =0xd000
  566588: 530b3e21     	ubfx	w1, w17, #11, #5
  56658c: 7a5b9822     	ccmp	w1, #0x1b, #0x2, ls
  566590: 1a9f27e1     	cset	w1, lo
  566594: 72002a3f     	tst	w17, #0x7ff
  566598: 1a8113f1     	csel	w17, wzr, w1, ne
  56659c: 8b050063     	add	x3, x3, x5
  5665a0: 8b31414a     	add	x10, x10, w17, uxtw
  5665a4: 91001108     	add	x8, x8, #0x4
  5665a8: f1000442     	subs	x2, x2, #0x1
  5665ac: 5400daa0     	b.eq	0x568100 <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x1f40>
  5665b0: b9400071     	ldr	w17, [x3]
  5665b4: 5ac00a21     	rev	w1, w17
  5665b8: 7100017f     	cmp	w11, #0x0
  5665bc: 1a811231     	csel	w17, w17, w1, ne
  5665c0: b9000111     	str	w17, [x8]
  5665c4: 1e270220     	fmov	s0, w17
  5665c8: 1e202000     	fcmp	s0, s0
  5665cc: 54000126     	b.vs	0x5665f0 <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x430>
  5665d0: 7100199f     	cmp	w12, #0x6
  5665d4: 54fffd68     	b.hi	0x566580 <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x3c0>
  5665d8: 1acc21c1     	lsl	w1, w14, w12
  5665dc: 6a0f003f     	tst	w1, w15
  5665e0: 54fffd00     	b.eq	0x566580 <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x3c0>
  5665e4: 6b10023f     	cmp	w17, w16
  5665e8: 1a9fd7f1     	cset	w17, gt
  5665ec: 17ffffec     	b	0x56659c <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x3dc>
  5665f0: 52800031     	mov	w17, #0x1               ; =1
  5665f4: 17ffffea     	b	0x56659c <__RNvXsd_CsfKb3QaXQt7u_10dtatools_rNtB5_7RColumnNtNtCsj8z43JjVsAT_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0x3dc>
