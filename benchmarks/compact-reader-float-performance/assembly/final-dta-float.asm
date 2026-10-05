  56715c: b94001d1     	ldr	w17, [x14]
  567160: 5ac00a21     	rev	w1, w17
  567164: 7100017f     	cmp	w11, #0x0
  567168: 1a811231     	csel	w17, w17, w1, ne
  56716c: b8004511     	str	w17, [x8], #0x4
  567170: 0b0d0221     	add	w1, w17, w13
  567174: 72002a3f     	tst	w17, #0x7ff
  567178: 7a4f0022     	ccmp	w1, w15, #0x2, eq
  56717c: 12007a31     	and	w17, w17, #0x7fffffff
  567180: 7a508222     	ccmp	w17, w16, #0x2, hi
  567184: 9a8c958c     	cinc	x12, x12, hi
  567188: 8b0501ce     	add	x14, x14, x5
  56718c: f100054a     	subs	x10, x10, #0x1
  567190: 54fffe61     	b.ne	0x56715c <__RNvXsd_Cs6PmCChrtvwX_10dtatools_rNtB5_7RColumnNtNtCs5kn9AuZ5Mb3_9dta_tools4file13DtaColumnSink21try_push_numeric_rows+0xed4>
