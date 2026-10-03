  18bb00: 52800008     	mov	w8, #0x0                ; =0
  18bb04: 140001a6     	b	0x18c19c <_arithmetic_general_produce+0x113c>
  18bb08: 6f03f600     	fmov.2d	v0, #1.00000000
  18bb0c: f100413f     	cmp	x9, #0x10
  18bb10: 540038e2     	b.hs	0x18c22c <_arithmetic_general_produce+0x11cc>
  18bb14: d280000b     	mov	x11, #0x0               ; =0
  18bb18: 52800008     	mov	w8, #0x0                ; =0
  18bb1c: 14000251     	b	0x18c460 <_arithmetic_general_produce+0x1400>
  18bb20: f100413f     	cmp	x9, #0x10
  18bb24: 54007642     	b.hs	0x18c9ec <_arithmetic_general_produce+0x198c>
  18bb28: d280000b     	mov	x11, #0x0               ; =0
  18bb2c: 52800008     	mov	w8, #0x0                ; =0
  18bb30: 14000416     	b	0x18cb88 <_arithmetic_general_produce+0x1b28>
  18bb34: f100413f     	cmp	x9, #0x10
  18bb38: 54009802     	b.hs	0x18ce38 <_arithmetic_general_produce+0x1dd8>
  18bb3c: d280000b     	mov	x11, #0x0               ; =0
  18bb40: 52800008     	mov	w8, #0x0                ; =0
  18bb44: 14000517     	b	0x18cfa0 <_arithmetic_general_produce+0x1f40>
  18bb48: f100413f     	cmp	x9, #0x10
  18bb4c: 5400a6e2     	b.hs	0x18d028 <_arithmetic_general_produce+0x1fc8>
  18bb50: d280000b     	mov	x11, #0x0               ; =0
  18bb54: 52800008     	mov	w8, #0x0                ; =0
  18bb58: 140006d8     	b	0x18d6b8 <_arithmetic_general_produce+0x2658>
  18bb5c: 927ced2b     	and	x11, x9, #0xfffffffffffffff0
  18bb60: 91004008     	add	x8, x0, #0x10
  18bb64: 9100818c     	add	x12, x12, #0x20
  18bb68: 6f00e400     	movi.2d	v0, #0000000000000000
  18bb6c: aa0b03ed     	mov	x13, x11
  18bb70: 6f00e401     	movi.2d	v1, #0000000000000000
  18bb74: 6f00e402     	movi.2d	v2, #0000000000000000
  18bb78: 6f00e403     	movi.2d	v3, #0000000000000000
  18bb7c: 4f00043e     	movi.4s	v30, #0x1
  18bb80: 6d7f1507     	ldp	d7, d5, [x8, #-0x10]
  18bb84: 0f10a4f7     	sshll.4s	v23, v7, #0x0
  18bb88: 0f10a4b6     	sshll.4s	v22, v5, #0x0
  18bb8c: 6cc21106     	ldp	d6, d4, [x8], #0x20
  18bb90: 0f10a4d5     	sshll.4s	v21, v6, #0x0
  18bb94: 0f10a493     	sshll.4s	v19, v4, #0x0
  18bb98: 4eab3ef0     	cmge.4s	v16, v23, v11
  18bb9c: 4eab3ed1     	cmge.4s	v17, v22, v11
  18bba0: 4eab3eb2     	cmge.4s	v18, v21, v11
  18bba4: 4eab3e74     	cmge.4s	v20, v19, v11
  18bba8: 2f10a4f8     	ushll.4s	v24, v7, #0x0
  18bbac: 4ea09b18     	cmeq.4s	v24, v24, #0
  18bbb0: 2f10a4b9     	ushll.4s	v25, v5, #0x0
  18bbb4: 4ea09b39     	cmeq.4s	v25, v25, #0
  18bbb8: 2f10a4da     	ushll.4s	v26, v6, #0x0
  18bbbc: 4ea09b5a     	cmeq.4s	v26, v26, #0
  18bbc0: 2f10a49b     	ushll.4s	v27, v4, #0x0
  18bbc4: 4ea09b7b     	cmeq.4s	v27, v27, #0
  18bbc8: 4eb01f10     	orr.16b	v16, v24, v16
  18bbcc: 4f20a618     	sshll2.2d	v24, v16, #0x0
  18bbd0: 0f20a61c     	sshll.2d	v28, v16, #0x0
  18bbd4: 4eb11f31     	orr.16b	v17, v25, v17
  18bbd8: 4f20a639     	sshll2.2d	v25, v17, #0x0
  18bbdc: 0f20a63d     	sshll.2d	v29, v17, #0x0
  18bbe0: 4eb21f52     	orr.16b	v18, v26, v18
  18bbe4: 4eb41f74     	orr.16b	v20, v27, v20
  18bbe8: 0f20a6fa     	sshll.2d	v26, v23, #0x0
  18bbec: 4e61db5a     	scvtf.2d	v26, v26
  18bbf0: 6f03f61b     	fmov.2d	v27, #1.00000000
  18bbf4: 6ebc1f7a     	bit.16b	v26, v27, v28
  18bbf8: 4f20a65c     	sshll2.2d	v28, v18, #0x0
  18bbfc: 4f20a6f7     	sshll2.2d	v23, v23, #0x0
  18bc00: 4e61daf7     	scvtf.2d	v23, v23
  18bc04: 6eb81f77     	bit.16b	v23, v27, v24
  18bc08: 0f20a6d8     	sshll.2d	v24, v22, #0x0
  18bc0c: 4e61db18     	scvtf.2d	v24, v24
  18bc10: 6ebd1f78     	bit.16b	v24, v27, v29
  18bc14: 0f20a65d     	sshll.2d	v29, v18, #0x0
  18bc18: 4f20a6d6     	sshll2.2d	v22, v22, #0x0
  18bc1c: 4e61dad6     	scvtf.2d	v22, v22
  18bc20: 6eb91f76     	bit.16b	v22, v27, v25
  18bc24: 0f20a6b9     	sshll.2d	v25, v21, #0x0
  18bc28: 4e61db39     	scvtf.2d	v25, v25
  18bc2c: 6ebd1f79     	bit.16b	v25, v27, v29
  18bc30: 0f20a69d     	sshll.2d	v29, v20, #0x0
  18bc34: 4f20a6b5     	sshll2.2d	v21, v21, #0x0
  18bc38: 4e61dab5     	scvtf.2d	v21, v21
  18bc3c: 6ebc1f75     	bit.16b	v21, v27, v28
  18bc40: 0f20a67c     	sshll.2d	v28, v19, #0x0
  18bc44: 4e61db9c     	scvtf.2d	v28, v28
  18bc48: 6ebd1f7c     	bit.16b	v28, v27, v29
  18bc4c: 4f20a69d     	sshll2.2d	v29, v20, #0x0
  18bc50: 4f20a673     	sshll2.2d	v19, v19, #0x0
  18bc54: 4e61da73     	scvtf.2d	v19, v19
  18bc58: 6ebd1f73     	bit.16b	v19, v27, v29
  18bc5c: 6e77fd97     	fdiv.2d	v23, v12, v23
  18bc60: 6e7afd9a     	fdiv.2d	v26, v12, v26
  18bc64: 0e616b5a     	fcvtn	v26.2s, v26.2d
  18bc68: 4e616afa     	fcvtn2	v26.4s, v23.2d
  18bc6c: 6e76fd96     	fdiv.2d	v22, v12, v22
  18bc70: 6e78fd97     	fdiv.2d	v23, v12, v24
  18bc74: 0e616af7     	fcvtn	v23.2s, v23.2d
  18bc78: 4e616ad7     	fcvtn2	v23.4s, v22.2d
  18bc7c: 6e75fd95     	fdiv.2d	v21, v12, v21
  18bc80: 6e79fd96     	fdiv.2d	v22, v12, v25
  18bc84: 0e616ad6     	fcvtn	v22.2s, v22.2d
  18bc88: 4e616ab6     	fcvtn2	v22.4s, v21.2d
  18bc8c: 6e73fd93     	fdiv.2d	v19, v12, v19
  18bc90: 6e7cfd95     	fdiv.2d	v21, v12, v28
  18bc94: 0e616ab5     	fcvtn	v21.2s, v21.2d
  18bc98: 4e616a75     	fcvtn2	v21.4s, v19.2d
  18bc9c: 6e7a1ff0     	bsl.16b	v16, v31, v26
  18bca0: 6e771ff1     	bsl.16b	v17, v31, v23
  18bca4: 6e761ff2     	bsl.16b	v18, v31, v22
  18bca8: 4eb41e93     	mov.16b	v19, v20
  18bcac: 6e751ff3     	bsl.16b	v19, v31, v21
  18bcb0: ad3f4590     	stp	q16, q17, [x12, #-0x20]
  18bcb4: ac824d92     	stp	q18, q19, [x12], #0x40
  18bcb8: 0e6098e7     	cmeq.4h	v7, v7, #0
  18bcbc: 2f10a4e7     	ushll.4s	v7, v7, #0x0
  18bcc0: 4e3e1ce7     	and.16b	v7, v7, v30
  18bcc4: 4ea78400     	add.4s	v0, v0, v7
  18bcc8: 0e6098a5     	cmeq.4h	v5, v5, #0
  18bccc: 2f10a4a5     	ushll.4s	v5, v5, #0x0
  18bcd0: 4e3e1ca5     	and.16b	v5, v5, v30
  18bcd4: 4ea58421     	add.4s	v1, v1, v5
  18bcd8: 0e6098c5     	cmeq.4h	v5, v6, #0
  18bcdc: 2f10a4a5     	ushll.4s	v5, v5, #0x0
  18bce0: 4e3e1ca5     	and.16b	v5, v5, v30
  18bce4: 4ea58442     	add.4s	v2, v2, v5
  18bce8: 0e609884     	cmeq.4h	v4, v4, #0
  18bcec: 2f10a484     	ushll.4s	v4, v4, #0x0
  18bcf0: 4e3e1c84     	and.16b	v4, v4, v30
  18bcf4: 4ea48463     	add.4s	v3, v3, v4
  18bcf8: f10041ad     	subs	x13, x13, #0x10
  18bcfc: 54fff421     	b.ne	0x18bb80 <_arithmetic_general_produce+0xb20>
  18bd00: 4ea08420     	add.4s	v0, v1, v0
  18bd04: 4ea08440     	add.4s	v0, v2, v0
  18bd08: 4ea08460     	add.4s	v0, v3, v0
  18bd0c: 4eb1b800     	addv.4s	s0, v0
  18bd10: 1e260008     	fmov	w8, s0
  18bd14: eb0b013f     	cmp	x9, x11
  18bd18: 54ffae60     	b.eq	0x18b2e4 <_arithmetic_general_produce+0x284>
  18bd1c: f27e053f     	tst	x9, #0xc
  18bd20: 54ffbda0     	b.eq	0x18b4d4 <_arithmetic_general_produce+0x474>
  18bd24: aa0b03ed     	mov	x13, x11
  18bd28: 6f00e400     	movi.2d	v0, #0000000000000000
  18bd2c: 4e041d00     	mov.s	v0[0], w8
  18bd30: 927ef52b     	and	x11, x9, #0xfffffffffffffffc
  18bd34: cb0b01a8     	sub	x8, x13, x11
  18bd38: d37ef6ac     	lsl	x12, x21, #2
  18bd3c: 8b0d098c     	add	x12, x12, x13, lsl #2
  18bd40: 8b0c014c     	add	x12, x10, x12
  18bd44: 8b0d040d     	add	x13, x0, x13, lsl #1
  18bd48: 4f000430     	movi.4s	v16, #0x1
  18bd4c: fc4085a1     	ldr	d1, [x13], #0x8
  18bd50: 0f10a422     	sshll.4s	v2, v1, #0x0
  18bd54: 4eab3c43     	cmge.4s	v3, v2, v11
  18bd58: 0e609824     	cmeq.4h	v4, v1, #0
  18bd5c: 2f10a484     	ushll.4s	v4, v4, #0x0
  18bd60: 4e301c84     	and.16b	v4, v4, v16
  18bd64: 2f10a421     	ushll.4s	v1, v1, #0x0
  18bd68: 4ea09821     	cmeq.4s	v1, v1, #0
  18bd6c: 4ea31c21     	orr.16b	v1, v1, v3
  18bd70: 4f20a423     	sshll2.2d	v3, v1, #0x0
  18bd74: 0f20a425     	sshll.2d	v5, v1, #0x0
  18bd78: 4f20a446     	sshll2.2d	v6, v2, #0x0
  18bd7c: 4e61d8c6     	scvtf.2d	v6, v6
  18bd80: 0f20a442     	sshll.2d	v2, v2, #0x0
  18bd84: 4e61d842     	scvtf.2d	v2, v2
  18bd88: 6f03f607     	fmov.2d	v7, #1.00000000
  18bd8c: 6ea51ce2     	bit.16b	v2, v7, v5
  18bd90: 6e661ce3     	bsl.16b	v3, v7, v6
  18bd94: 6e63fd83     	fdiv.2d	v3, v12, v3
  18bd98: 6e62fd82     	fdiv.2d	v2, v12, v2
  18bd9c: 0e616842     	fcvtn	v2.2s, v2.2d
  18bda0: 4e616862     	fcvtn2	v2.4s, v3.2d
  18bda4: 6e621fe1     	bsl.16b	v1, v31, v2
  18bda8: 3c810581     	str	q1, [x12], #0x10
  18bdac: 4ea48400     	add.4s	v0, v0, v4
  18bdb0: b1001108     	adds	x8, x8, #0x4
  18bdb4: 54fffcc1     	b.ne	0x18bd4c <_arithmetic_general_produce+0xcec>
  18bdb8: 4eb1b800     	addv.4s	s0, v0
  18bdbc: 1e260008     	fmov	w8, s0
  18bdc0: eb0b013f     	cmp	x9, x11
  18bdc4: 54ffa900     	b.eq	0x18b2e4 <_arithmetic_general_produce+0x284>
  18bdc8: 17fffdc3     	b	0x18b4d4 <_arithmetic_general_produce+0x474>
  18bdcc: 927ced2b     	and	x11, x9, #0xfffffffffffffff0
  18bdd0: 91010188     	add	x8, x12, #0x40
  18bdd4: 9100400c     	add	x12, x0, #0x10
  18bdd8: 6f00e400     	movi.2d	v0, #0000000000000000
  18bddc: aa0b03ed     	mov	x13, x11
  18bde0: 6f00e401     	movi.2d	v1, #0000000000000000
  18bde4: 6f00e402     	movi.2d	v2, #0000000000000000
  18bde8: 6f00e403     	movi.2d	v3, #0000000000000000
  18bdec: 4f000428     	movi.4s	v8, #0x1
  18bdf0: ad7f9d84     	ldp	q4, q7, [x12, #-0x10]
  18bdf4: 4f10a490     	sshll2.4s	v16, v4, #0x0
  18bdf8: 0f10a491     	sshll.4s	v17, v4, #0x0
  18bdfc: 4f10a4f2     	sshll2.4s	v18, v7, #0x0
