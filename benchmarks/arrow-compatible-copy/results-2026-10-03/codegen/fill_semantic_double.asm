
<compatible-copy-evidence>/candidate-v1/library/dtatools/libs/dtatools.so:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000004face8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double>:
  4face8: d10383ff     	sub	sp, sp, #0xe0
  4facec: 6d062beb     	stp	d11, d10, [sp, #0x60]
  4facf0: 6d0723e9     	stp	d9, d8, [sp, #0x70]
  4facf4: a9086ffc     	stp	x28, x27, [sp, #0x80]
  4facf8: a90967fa     	stp	x26, x25, [sp, #0x90]
  4facfc: a90a5ff8     	stp	x24, x23, [sp, #0xa0]
  4fad00: a90b57f6     	stp	x22, x21, [sp, #0xb0]
  4fad04: a90c4ff4     	stp	x20, x19, [sp, #0xc0]
  4fad08: a90d7bfd     	stp	x29, x30, [sp, #0xd0]
  4fad0c: 910343fd     	add	x29, sp, #0xd0
  4fad10: aa0203f4     	mov	x20, x2
  4fad14: aa0103f5     	mov	x21, x1
  4fad18: 39446028     	ldrb	w8, [x1, #0x118]
  4fad1c: 71001d1f     	cmp	w8, #0x7
  4fad20: 5400028d     	b.le	0x4fad70 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x88>
  4fad24: 7100291f     	cmp	w8, #0xa
  4fad28: 540017ec     	b.gt	0x4fb024 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x33c>
  4fad2c: 7100211f     	cmp	w8, #0x8
  4fad30: 54002d00     	b.eq	0x4fb2d0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x5e8>
  4fad34: 7100251f     	cmp	w8, #0x9
  4fad38: 54002b41     	b.ne	0x4fb2a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x5b8>
  4fad3c: f90007e0     	str	x0, [sp, #0x8]
  4fad40: f94016a8     	ldr	x8, [x21, #0x28]
  4fad44: b4004fe8     	cbz	x8, 0x4fb740 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa58>
  4fad48: d2800017     	mov	x23, #0x0               ; =0
  4fad4c: f94012b8     	ldr	x24, [x21, #0x20]
  4fad50: 8b081308     	add	x8, x24, x8, lsl #4
  4fad54: f90003e8     	str	x8, [sp]
  4fad58: a940eeb9     	ldp	x25, x27, [x21, #0x8]
  4fad5c: 92f70208     	mov	x8, #0x47efffffffffffff ; =5183643171103440895
  4fad60: 9e670109     	fmov	d9, x8
  4fad64: 90000cd5     	adrp	x21, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4fad68: 91220eb5     	add	x21, x21, #0x883
  4fad6c: 14000055     	b	0x4faec0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x1d8>
  4fad70: 7100111f     	cmp	w8, #0x4
  4fad74: 54002000     	b.eq	0x4fb174 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x48c>
  4fad78: 7100151f     	cmp	w8, #0x5
  4fad7c: 54003f80     	b.eq	0x4fb56c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x884>
  4fad80: 71001d1f     	cmp	w8, #0x7
  4fad84: 540028e1     	b.ne	0x4fb2a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x5b8>
  4fad88: aa0003fc     	mov	x28, x0
  4fad8c: f94016a8     	ldr	x8, [x21, #0x28]
  4fad90: b4003c88     	cbz	x8, 0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fad94: d2800013     	mov	x19, #0x0               ; =0
  4fad98: f94012b7     	ldr	x23, [x21, #0x20]
  4fad9c: 8b0812f8     	add	x24, x23, x8, lsl #4
  4fada0: d29613f9     	mov	x25, #0xb09f            ; =45215
  4fada4: f2a41d59     	movk	x25, #0x20ea, lsl #16
  4fada8: f2c3aed9     	movk	x25, #0x1d76, lsl #32
  4fadac: f2e99679     	movk	x25, #0x4cb3, lsl #48
  4fadb0: d2928d5a     	mov	x26, #0x946a            ; =37994
  4fadb4: f2a0ae1a     	movk	x26, #0x570, lsl #16
  4fadb8: f2c8a91a     	movk	x26, #0x4548, lsl #32
  4fadbc: f2ee681a     	movk	x26, #0x7340, lsl #48
  4fadc0: d000159b     	adrp	x27, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fadc4: f940477b     	ldr	x27, [x27, #0x88]
  4fadc8: 14000004     	b	0x4fadd8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xf0>
  4fadcc: 910042f7     	add	x23, x23, #0x10
  4fadd0: eb1802ff     	cmp	x23, x24
  4fadd4: 54003a60     	b.eq	0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fadd8: a94026e8     	ldp	x8, x9, [x23]
  4faddc: f940092a     	ldr	x10, [x9, #0x10]
  4fade0: d100054a     	sub	x10, x10, #0x1
  4fade4: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fade8: 8b0a0108     	add	x8, x8, x10
  4fadec: f9401129     	ldr	x9, [x9, #0x20]
  4fadf0: 91004100     	add	x0, x8, #0x10
  4fadf4: d63f0120     	blr	x9
  4fadf8: aa0003f6     	mov	x22, x0
  4fadfc: f9400c29     	ldr	x9, [x1, #0x18]
  4fae00: 910103e8     	add	x8, sp, #0x40
  4fae04: d63f0120     	blr	x9
  4fae08: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fae0c: eb19013f     	cmp	x9, x25
  4fae10: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fae14: 540038c1     	b.ne	0x4fb52c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x844>
  4fae18: f94016c8     	ldr	x8, [x22, #0x28]
  4fae1c: d341fd08     	lsr	x8, x8, #1
  4fae20: b4fffd68     	cbz	x8, 0x4fadcc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xe4>
  4fae24: d2800009     	mov	x9, #0x0                ; =0
  4fae28: 14000007     	b	0x4fae44 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x15c>
  4fae2c: fd400360     	ldr	d0, [x27]
  4fae30: 91000529     	add	x9, x9, #0x1
  4fae34: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fae38: 91000673     	add	x19, x19, #0x1
  4fae3c: eb09011f     	cmp	x8, x9
  4fae40: 54fffc60     	b.eq	0x4fadcc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xe4>
  4fae44: f9401aca     	ldr	x10, [x22, #0x30]
  4fae48: b40001aa     	cbz	x10, 0x4fae7c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x194>
  4fae4c: f9402aca     	ldr	x10, [x22, #0x50]
  4fae50: eb0a013f     	cmp	x9, x10
  4fae54: 54004902     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fae58: f9401eca     	ldr	x10, [x22, #0x38]
  4fae5c: f94026cb     	ldr	x11, [x22, #0x48]
  4fae60: 8b0b012b     	add	x11, x9, x11
  4fae64: d343fd6c     	lsr	x12, x11, #3
  4fae68: 386c694a     	ldrb	w10, [x10, x12]
  4fae6c: 52001d4a     	eor	w10, w10, #0xff
  4fae70: 9240096b     	and	x11, x11, #0x7
  4fae74: 1acb254a     	lsr	w10, w10, w11
  4fae78: 3707fdaa     	tbnz	w10, #0x0, 0x4fae2c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x144>
  4fae7c: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4fae80: f9001be9     	str	x9, [sp, #0x30]
  4fae84: d341fd6b     	lsr	x11, x11, #1
  4fae88: eb0b013f     	cmp	x9, x11
  4fae8c: 54004802     	b.hs	0x4fb78c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xaa4>
  4fae90: 7c697940     	ldr	h0, [x10, x9, lsl #1]
  4fae94: 7e61d800     	ucvtf	d0, d0
  4fae98: 91000529     	add	x9, x9, #0x1
  4fae9c: fc337a80     	str	d0, [x20, x19, lsl #3]
  4faea0: 91000673     	add	x19, x19, #0x1
  4faea4: eb09011f     	cmp	x8, x9
  4faea8: 54fffce1     	b.ne	0x4fae44 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x15c>
  4faeac: 17ffffc8     	b	0x4fadcc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xe4>
  4faeb0: 91004318     	add	x24, x24, #0x10
  4faeb4: f94003e8     	ldr	x8, [sp]
  4faeb8: eb08031f     	cmp	x24, x8
  4faebc: 54004420     	b.eq	0x4fb740 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa58>
  4faec0: a9402708     	ldp	x8, x9, [x24]
  4faec4: f940092a     	ldr	x10, [x9, #0x10]
  4faec8: d100054a     	sub	x10, x10, #0x1
  4faecc: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4faed0: 8b0a0108     	add	x8, x8, x10
  4faed4: f9401129     	ldr	x9, [x9, #0x20]
  4faed8: 91004100     	add	x0, x8, #0x10
  4faedc: d63f0120     	blr	x9
  4faee0: aa0003f6     	mov	x22, x0
  4faee4: f9400c29     	ldr	x9, [x1, #0x18]
  4faee8: 910103e8     	add	x8, sp, #0x40
  4faeec: d63f0120     	blr	x9
  4faef0: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4faef4: d29d9e6a     	mov	x10, #0xecf3            ; =60659
  4faef8: f2ae798a     	movk	x10, #0x73cc, lsl #16
  4faefc: f2c2afaa     	movk	x10, #0x157d, lsl #32
  4faf00: f2e89fea     	movk	x10, #0x44ff, lsl #48
  4faf04: eb0a013f     	cmp	x9, x10
  4faf08: d2894f29     	mov	x9, #0x4a79             ; =19065
  4faf0c: f2a38ee9     	movk	x9, #0x1c77, lsl #16
  4faf10: f2cf1b89     	movk	x9, #0x78dc, lsl #32
  4faf14: f2f241e9     	movk	x9, #0x920f, lsl #48
  4faf18: fa490100     	ccmp	x8, x9, #0x0, eq
  4faf1c: 54004521     	b.ne	0x4fb7c0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xad8>
  4faf20: f94016c8     	ldr	x8, [x22, #0x28]
  4faf24: d343fd13     	lsr	x19, x8, #3
  4faf28: b4fffc53     	cbz	x19, 0x4faeb0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x1c8>
  4faf2c: d280001a     	mov	x26, #0x0               ; =0
  4faf30: 14000009     	b	0x4faf54 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x26c>
  4faf34: d0001588     	adrp	x8, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4faf38: f9404508     	ldr	x8, [x8, #0x88]
  4faf3c: fd400108     	ldr	d8, [x8]
  4faf40: 9100075a     	add	x26, x26, #0x1
  4faf44: fc377a88     	str	d8, [x20, x23, lsl #3]
  4faf48: 910006f7     	add	x23, x23, #0x1
  4faf4c: eb1a027f     	cmp	x19, x26
  4faf50: 54fffb00     	b.eq	0x4faeb0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x1c8>
  4faf54: f9401ac8     	ldr	x8, [x22, #0x30]
  4faf58: b40001a8     	cbz	x8, 0x4faf8c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x2a4>
  4faf5c: f9402ac8     	ldr	x8, [x22, #0x50]
  4faf60: eb08035f     	cmp	x26, x8
  4faf64: 54004082     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4faf68: f9401ec8     	ldr	x8, [x22, #0x38]
  4faf6c: f94026c9     	ldr	x9, [x22, #0x48]
  4faf70: 8b090349     	add	x9, x26, x9
  4faf74: d343fd2a     	lsr	x10, x9, #3
  4faf78: 386a6908     	ldrb	w8, [x8, x10]
  4faf7c: 52001d08     	eor	w8, w8, #0xff
  4faf80: 92400929     	and	x9, x9, #0x7
  4faf84: 1ac92508     	lsr	w8, w8, w9
  4faf88: 3707fd68     	tbnz	w8, #0x0, 0x4faf34 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x24c>
  4faf8c: a94226c8     	ldp	x8, x9, [x22, #0x20]
  4faf90: f90017fa     	str	x26, [sp, #0x28]
  4faf94: d343fd29     	lsr	x9, x9, #3
  4faf98: eb09035f     	cmp	x26, x9
  4faf9c: 54004342     	b.hs	0x4fb804 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xb1c>
  4fafa0: f87a791c     	ldr	x28, [x8, x26, lsl #3]
  4fafa4: a902e7fc     	stp	x28, x25, [sp, #0x28]
  4fafa8: f9001ffb     	str	x27, [sp, #0x38]
  4fafac: 9e630388     	ucvtf	d8, x28
  4fafb0: 4ea81d00     	mov.16b	v0, v8
  4fafb4: 9405c146     	bl	0x66b4cc <___fixunsdfti>
  4fafb8: 1e602108     	fcmp	d8, #0.0
  4fafbc: 9a80b3e8     	csel	x8, xzr, x0, lt
  4fafc0: 9a81b3e9     	csel	x9, xzr, x1, lt
  4fafc4: 1e692100     	fcmp	d8, d9
  4fafc8: da9fd129     	csinv	x9, x9, xzr, le
  4fafcc: da9fd108     	csinv	x8, x8, xzr, le
  4fafd0: ca1c0108     	eor	x8, x8, x28
  4fafd4: aa090108     	orr	x8, x8, x9
  4fafd8: b4fffb48     	cbz	x8, 0x4faf40 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x258>
  4fafdc: 9100c3e8     	add	x8, sp, #0x30
  4fafe0: f90023e8     	str	x8, [sp, #0x40]
  4fafe4: b0000408     	adrp	x8, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4fafe8: 9111e109     	add	x9, x8, #0x478
  4fafec: 9100a3e8     	add	x8, sp, #0x28
  4faff0: a904a3e9     	stp	x9, x8, [sp, #0x48]
  4faff4: f0fff8c8     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4faff8: 9134e108     	add	x8, x8, #0xd38
  4faffc: f9002fe8     	str	x8, [sp, #0x58]
  4fb000: 910043e8     	add	x8, sp, #0x10
  4fb004: 910103e1     	add	x1, sp, #0x40
  4fb008: aa1503e0     	mov	x0, x21
  4fb00c: 97f53da6     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4fb010: f9400be8     	ldr	x8, [sp, #0x10]
  4fb014: fd400fe8     	ldr	d8, [sp, #0x18]
  4fb018: b100051f     	cmn	x8, #0x1
  4fb01c: 54fff920     	b.eq	0x4faf40 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x258>
  4fb020: 140001c2     	b	0x4fb728 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa40>
  4fb024: 71002d1f     	cmp	w8, #0xb
  4fb028: 54001e80     	b.eq	0x4fb3f8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x710>
  4fb02c: 7100311f     	cmp	w8, #0xc
  4fb030: 54001381     	b.ne	0x4fb2a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x5b8>
  4fb034: aa0003fc     	mov	x28, x0
  4fb038: d2800013     	mov	x19, #0x0               ; =0
  4fb03c: a94222b7     	ldp	x23, x8, [x21, #0x20]
  4fb040: 8b0812f8     	add	x24, x23, x8, lsl #4
  4fb044: d2826099     	mov	x25, #0x1304            ; =4868
  4fb048: f2aabcb9     	movk	x25, #0x55e5, lsl #16
  4fb04c: f2d07719     	movk	x25, #0x83b8, lsl #32
  4fb050: f2f6ccb9     	movk	x25, #0xb665, lsl #48
  4fb054: d290e75a     	mov	x26, #0x873a            ; =34618
  4fb058: f2b57aba     	movk	x26, #0xabd5, lsl #16
  4fb05c: f2c149fa     	movk	x26, #0xa4f, lsl #32
  4fb060: f2ee05fa     	movk	x26, #0x702f, lsl #48
  4fb064: b000159b     	adrp	x27, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fb068: f940477b     	ldr	x27, [x27, #0x88]
  4fb06c: eb1802ff     	cmp	x23, x24
  4fb070: 54002580     	b.eq	0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb074: a8c126e8     	ldp	x8, x9, [x23], #0x10
  4fb078: f940092a     	ldr	x10, [x9, #0x10]
  4fb07c: d100054a     	sub	x10, x10, #0x1
  4fb080: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fb084: 8b0a0108     	add	x8, x8, x10
  4fb088: f9401129     	ldr	x9, [x9, #0x20]
  4fb08c: 91004100     	add	x0, x8, #0x10
  4fb090: d63f0120     	blr	x9
  4fb094: aa0003f6     	mov	x22, x0
  4fb098: f9400c29     	ldr	x9, [x1, #0x18]
  4fb09c: 910103e8     	add	x8, sp, #0x40
  4fb0a0: d63f0120     	blr	x9
  4fb0a4: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fb0a8: eb19013f     	cmp	x9, x25
  4fb0ac: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fb0b0: 540023e1     	b.ne	0x4fb52c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x844>
  4fb0b4: f94016c9     	ldr	x9, [x22, #0x28]
  4fb0b8: d343fd28     	lsr	x8, x9, #3
  4fb0bc: b4fffd88     	cbz	x8, 0x4fb06c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x384>
  4fb0c0: f9401aca     	ldr	x10, [x22, #0x30]
  4fb0c4: b40004aa     	cbz	x10, 0x4fb158 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x470>
  4fb0c8: f9402eca     	ldr	x10, [x22, #0x58]
  4fb0cc: b400046a     	cbz	x10, 0x4fb158 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x470>
  4fb0d0: d2800009     	mov	x9, #0x0                ; =0
  4fb0d4: 14000007     	b	0x4fb0f0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x408>
  4fb0d8: fd400360     	ldr	d0, [x27]
  4fb0dc: 91000529     	add	x9, x9, #0x1
  4fb0e0: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb0e4: 91000673     	add	x19, x19, #0x1
  4fb0e8: eb09011f     	cmp	x8, x9
  4fb0ec: 54fffc00     	b.eq	0x4fb06c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x384>
  4fb0f0: f9401aca     	ldr	x10, [x22, #0x30]
  4fb0f4: b40001aa     	cbz	x10, 0x4fb128 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x440>
  4fb0f8: f9402aca     	ldr	x10, [x22, #0x50]
  4fb0fc: eb0a013f     	cmp	x9, x10
  4fb100: 540033a2     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fb104: f9401eca     	ldr	x10, [x22, #0x38]
  4fb108: f94026cb     	ldr	x11, [x22, #0x48]
  4fb10c: 8b0b012b     	add	x11, x9, x11
  4fb110: d343fd6c     	lsr	x12, x11, #3
  4fb114: 386c694a     	ldrb	w10, [x10, x12]
  4fb118: 52001d4a     	eor	w10, w10, #0xff
  4fb11c: 9240096b     	and	x11, x11, #0x7
  4fb120: 1acb254a     	lsr	w10, w10, w11
  4fb124: 3707fdaa     	tbnz	w10, #0x0, 0x4fb0d8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x3f0>
  4fb128: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4fb12c: f9001be9     	str	x9, [sp, #0x30]
  4fb130: d343fd6b     	lsr	x11, x11, #3
  4fb134: eb0b013f     	cmp	x9, x11
  4fb138: 540032a2     	b.hs	0x4fb78c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xaa4>
  4fb13c: fc697940     	ldr	d0, [x10, x9, lsl #3]
  4fb140: 91000529     	add	x9, x9, #0x1
  4fb144: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb148: 91000673     	add	x19, x19, #0x1
  4fb14c: eb09011f     	cmp	x8, x9
  4fb150: 54fffd01     	b.ne	0x4fb0f0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x408>
  4fb154: 17ffffc6     	b	0x4fb06c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x384>
  4fb158: f94012c1     	ldr	x1, [x22, #0x20]
  4fb15c: 8b130e80     	add	x0, x20, x19, lsl #3
  4fb160: 927df122     	and	x2, x9, #0xfffffffffffffff8
  4fb164: 94061255     	bl	0x67fab8 <dyld_stub_binder+0x67fab8>
  4fb168: f94016c8     	ldr	x8, [x22, #0x28]
  4fb16c: 8b480e73     	add	x19, x19, x8, lsr #3
  4fb170: 17ffffbf     	b	0x4fb06c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x384>
  4fb174: aa0003fc     	mov	x28, x0
  4fb178: f94016a8     	ldr	x8, [x21, #0x28]
  4fb17c: b4001d28     	cbz	x8, 0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb180: d2800013     	mov	x19, #0x0               ; =0
  4fb184: f94012b7     	ldr	x23, [x21, #0x20]
  4fb188: 8b0812f8     	add	x24, x23, x8, lsl #4
  4fb18c: d2832c19     	mov	x25, #0x1960            ; =6496
  4fb190: f2b709d9     	movk	x25, #0xb84e, lsl #16
  4fb194: f2cdd319     	movk	x25, #0x6e98, lsl #32
  4fb198: f2f6e939     	movk	x25, #0xb749, lsl #48
  4fb19c: d2928cfa     	mov	x26, #0x9467            ; =37991
  4fb1a0: f2a291ba     	movk	x26, #0x148d, lsl #16
  4fb1a4: f2c2da7a     	movk	x26, #0x16d3, lsl #32
  4fb1a8: f2e4e71a     	movk	x26, #0x2738, lsl #48
  4fb1ac: b000159b     	adrp	x27, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fb1b0: f940477b     	ldr	x27, [x27, #0x88]
  4fb1b4: 14000004     	b	0x4fb1c4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x4dc>
  4fb1b8: 910042f7     	add	x23, x23, #0x10
  4fb1bc: eb1802ff     	cmp	x23, x24
  4fb1c0: 54001b00     	b.eq	0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb1c4: a94026e8     	ldp	x8, x9, [x23]
  4fb1c8: f940092a     	ldr	x10, [x9, #0x10]
  4fb1cc: d100054a     	sub	x10, x10, #0x1
  4fb1d0: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fb1d4: 8b0a0108     	add	x8, x8, x10
  4fb1d8: f9401129     	ldr	x9, [x9, #0x20]
  4fb1dc: 91004100     	add	x0, x8, #0x10
  4fb1e0: d63f0120     	blr	x9
  4fb1e4: aa0003f6     	mov	x22, x0
  4fb1e8: f9400c29     	ldr	x9, [x1, #0x18]
  4fb1ec: 910103e8     	add	x8, sp, #0x40
  4fb1f0: d63f0120     	blr	x9
  4fb1f4: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fb1f8: eb19013f     	cmp	x9, x25
  4fb1fc: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fb200: 54001961     	b.ne	0x4fb52c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x844>
  4fb204: f94016c8     	ldr	x8, [x22, #0x28]
  4fb208: d342fd08     	lsr	x8, x8, #2
  4fb20c: b4fffd68     	cbz	x8, 0x4fb1b8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x4d0>
  4fb210: d2800009     	mov	x9, #0x0                ; =0
  4fb214: 14000007     	b	0x4fb230 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x548>
  4fb218: fd400360     	ldr	d0, [x27]
  4fb21c: 91000529     	add	x9, x9, #0x1
  4fb220: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb224: 91000673     	add	x19, x19, #0x1
  4fb228: eb09011f     	cmp	x8, x9
  4fb22c: 54fffc60     	b.eq	0x4fb1b8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x4d0>
  4fb230: f9401aca     	ldr	x10, [x22, #0x30]
  4fb234: b40001aa     	cbz	x10, 0x4fb268 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x580>
  4fb238: f9402aca     	ldr	x10, [x22, #0x50]
  4fb23c: eb0a013f     	cmp	x9, x10
  4fb240: 540029a2     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fb244: f9401eca     	ldr	x10, [x22, #0x38]
  4fb248: f94026cb     	ldr	x11, [x22, #0x48]
  4fb24c: 8b0b012b     	add	x11, x9, x11
  4fb250: d343fd6c     	lsr	x12, x11, #3
  4fb254: 386c694a     	ldrb	w10, [x10, x12]
  4fb258: 52001d4a     	eor	w10, w10, #0xff
  4fb25c: 9240096b     	and	x11, x11, #0x7
  4fb260: 1acb254a     	lsr	w10, w10, w11
  4fb264: 3707fdaa     	tbnz	w10, #0x0, 0x4fb218 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x530>
  4fb268: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4fb26c: f9001be9     	str	x9, [sp, #0x30]
  4fb270: d342fd6b     	lsr	x11, x11, #2
  4fb274: eb0b013f     	cmp	x9, x11
  4fb278: 540028a2     	b.hs	0x4fb78c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xaa4>
  4fb27c: bc697940     	ldr	s0, [x10, x9, lsl #2]
  4fb280: 0f20a400     	sshll.2d	v0, v0, #0x0
  4fb284: 5e61d800     	scvtf	d0, d0
  4fb288: 91000529     	add	x9, x9, #0x1
  4fb28c: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb290: 91000673     	add	x19, x19, #0x1
  4fb294: eb09011f     	cmp	x8, x9
  4fb298: 54fffcc1     	b.ne	0x4fb230 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x548>
  4fb29c: 17ffffc7     	b	0x4fb1b8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x4d0>
  4fb2a0: a940a6a8     	ldp	x8, x9, [x21, #0x8]
  4fb2a4: a90127e8     	stp	x8, x9, [sp, #0x10]
  4fb2a8: 910043e8     	add	x8, sp, #0x10
  4fb2ac: 90000409     	adrp	x9, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4fb2b0: 9111e129     	add	x9, x9, #0x478
  4fb2b4: a90427e8     	stp	x8, x9, [sp, #0x40]
  4fb2b8: aa0003e8     	mov	x8, x0
  4fb2bc: f0000ca0     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4fb2c0: 911ab800     	add	x0, x0, #0x6ae
  4fb2c4: 910103e1     	add	x1, sp, #0x40
  4fb2c8: 97f53cf7     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4fb2cc: 14000120     	b	0x4fb74c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa64>
  4fb2d0: aa0003fc     	mov	x28, x0
  4fb2d4: f94016a8     	ldr	x8, [x21, #0x28]
  4fb2d8: b4001248     	cbz	x8, 0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb2dc: d2800013     	mov	x19, #0x0               ; =0
  4fb2e0: f94012b7     	ldr	x23, [x21, #0x20]
  4fb2e4: 8b0812f8     	add	x24, x23, x8, lsl #4
  4fb2e8: d286c9d9     	mov	x25, #0x364e            ; =13902
  4fb2ec: f2af1ef9     	movk	x25, #0x78f7, lsl #16
  4fb2f0: f2cdd459     	movk	x25, #0x6ea2, lsl #32
  4fb2f4: f2fb48f9     	movk	x25, #0xda47, lsl #48
  4fb2f8: d28c4bba     	mov	x26, #0x625d            ; =25181
  4fb2fc: f2beafba     	movk	x26, #0xf57d, lsl #16
  4fb300: f2c6d8da     	movk	x26, #0x36c6, lsl #32
  4fb304: f2fe347a     	movk	x26, #0xf1a3, lsl #48
  4fb308: b000159b     	adrp	x27, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fb30c: f940477b     	ldr	x27, [x27, #0x88]
  4fb310: 14000004     	b	0x4fb320 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x638>
  4fb314: 910042f7     	add	x23, x23, #0x10
  4fb318: eb1802ff     	cmp	x23, x24
  4fb31c: 54001020     	b.eq	0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb320: a94026e8     	ldp	x8, x9, [x23]
  4fb324: f940092a     	ldr	x10, [x9, #0x10]
  4fb328: d100054a     	sub	x10, x10, #0x1
  4fb32c: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fb330: 8b0a0108     	add	x8, x8, x10
  4fb334: f9401129     	ldr	x9, [x9, #0x20]
  4fb338: 91004100     	add	x0, x8, #0x10
  4fb33c: d63f0120     	blr	x9
  4fb340: aa0003f6     	mov	x22, x0
  4fb344: f9400c29     	ldr	x9, [x1, #0x18]
  4fb348: 910103e8     	add	x8, sp, #0x40
  4fb34c: d63f0120     	blr	x9
  4fb350: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fb354: eb19013f     	cmp	x9, x25
  4fb358: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fb35c: 54000e81     	b.ne	0x4fb52c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x844>
  4fb360: f94016c8     	ldr	x8, [x22, #0x28]
  4fb364: d342fd08     	lsr	x8, x8, #2
  4fb368: b4fffd68     	cbz	x8, 0x4fb314 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x62c>
  4fb36c: d2800009     	mov	x9, #0x0                ; =0
  4fb370: 14000007     	b	0x4fb38c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x6a4>
  4fb374: fd400360     	ldr	d0, [x27]
  4fb378: 91000529     	add	x9, x9, #0x1
  4fb37c: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb380: 91000673     	add	x19, x19, #0x1
  4fb384: eb09011f     	cmp	x8, x9
  4fb388: 54fffc60     	b.eq	0x4fb314 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x62c>
  4fb38c: f9401aca     	ldr	x10, [x22, #0x30]
  4fb390: b40001aa     	cbz	x10, 0x4fb3c4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x6dc>
  4fb394: f9402aca     	ldr	x10, [x22, #0x50]
  4fb398: eb0a013f     	cmp	x9, x10
  4fb39c: 54001ec2     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fb3a0: f9401eca     	ldr	x10, [x22, #0x38]
  4fb3a4: f94026cb     	ldr	x11, [x22, #0x48]
  4fb3a8: 8b0b012b     	add	x11, x9, x11
  4fb3ac: d343fd6c     	lsr	x12, x11, #3
  4fb3b0: 386c694a     	ldrb	w10, [x10, x12]
  4fb3b4: 52001d4a     	eor	w10, w10, #0xff
  4fb3b8: 9240096b     	and	x11, x11, #0x7
  4fb3bc: 1acb254a     	lsr	w10, w10, w11
  4fb3c0: 3707fdaa     	tbnz	w10, #0x0, 0x4fb374 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x68c>
  4fb3c4: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4fb3c8: f9001be9     	str	x9, [sp, #0x30]
  4fb3cc: d342fd6b     	lsr	x11, x11, #2
  4fb3d0: eb0b013f     	cmp	x9, x11
  4fb3d4: 54001dc2     	b.hs	0x4fb78c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xaa4>
  4fb3d8: bc697940     	ldr	s0, [x10, x9, lsl #2]
  4fb3dc: 7e61d800     	ucvtf	d0, d0
  4fb3e0: 91000529     	add	x9, x9, #0x1
  4fb3e4: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb3e8: 91000673     	add	x19, x19, #0x1
  4fb3ec: eb09011f     	cmp	x8, x9
  4fb3f0: 54fffce1     	b.ne	0x4fb38c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x6a4>
  4fb3f4: 17ffffc8     	b	0x4fb314 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x62c>
  4fb3f8: aa0003fc     	mov	x28, x0
  4fb3fc: f94016a8     	ldr	x8, [x21, #0x28]
  4fb400: b4000908     	cbz	x8, 0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb404: d2800013     	mov	x19, #0x0               ; =0
  4fb408: f94012b7     	ldr	x23, [x21, #0x20]
  4fb40c: 8b0812f8     	add	x24, x23, x8, lsl #4
  4fb410: d2802719     	mov	x25, #0x138             ; =312
  4fb414: f2abe9d9     	movk	x25, #0x5f4e, lsl #16
  4fb418: f2cab1b9     	movk	x25, #0x558d, lsl #32
  4fb41c: f2f8f299     	movk	x25, #0xc794, lsl #48
  4fb420: d28828ba     	mov	x26, #0x4145            ; =16709
  4fb424: f2a2d0ba     	movk	x26, #0x1685, lsl #16
  4fb428: f2c555da     	movk	x26, #0x2aae, lsl #32
  4fb42c: f2f8ccfa     	movk	x26, #0xc667, lsl #48
  4fb430: b000159b     	adrp	x27, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fb434: f940477b     	ldr	x27, [x27, #0x88]
  4fb438: 14000004     	b	0x4fb448 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x760>
  4fb43c: 910042f7     	add	x23, x23, #0x10
  4fb440: eb1802ff     	cmp	x23, x24
  4fb444: 540006e0     	b.eq	0x4fb520 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x838>
  4fb448: a94026e8     	ldp	x8, x9, [x23]
  4fb44c: f940092a     	ldr	x10, [x9, #0x10]
  4fb450: d100054a     	sub	x10, x10, #0x1
  4fb454: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fb458: 8b0a0108     	add	x8, x8, x10
  4fb45c: f9401129     	ldr	x9, [x9, #0x20]
  4fb460: 91004100     	add	x0, x8, #0x10
  4fb464: d63f0120     	blr	x9
  4fb468: aa0003f6     	mov	x22, x0
  4fb46c: f9400c29     	ldr	x9, [x1, #0x18]
  4fb470: 910103e8     	add	x8, sp, #0x40
  4fb474: d63f0120     	blr	x9
  4fb478: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fb47c: eb19013f     	cmp	x9, x25
  4fb480: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fb484: 54000541     	b.ne	0x4fb52c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x844>
  4fb488: f94016c8     	ldr	x8, [x22, #0x28]
  4fb48c: d342fd08     	lsr	x8, x8, #2
  4fb490: b4fffd68     	cbz	x8, 0x4fb43c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x754>
  4fb494: d2800009     	mov	x9, #0x0                ; =0
  4fb498: 14000007     	b	0x4fb4b4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x7cc>
  4fb49c: fd400360     	ldr	d0, [x27]
  4fb4a0: 91000529     	add	x9, x9, #0x1
  4fb4a4: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb4a8: 91000673     	add	x19, x19, #0x1
  4fb4ac: eb09011f     	cmp	x8, x9
  4fb4b0: 54fffc60     	b.eq	0x4fb43c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x754>
  4fb4b4: f9401aca     	ldr	x10, [x22, #0x30]
  4fb4b8: b40001aa     	cbz	x10, 0x4fb4ec <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x804>
  4fb4bc: f9402aca     	ldr	x10, [x22, #0x50]
  4fb4c0: eb0a013f     	cmp	x9, x10
  4fb4c4: 54001582     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fb4c8: f9401eca     	ldr	x10, [x22, #0x38]
  4fb4cc: f94026cb     	ldr	x11, [x22, #0x48]
  4fb4d0: 8b0b012b     	add	x11, x9, x11
  4fb4d4: d343fd6c     	lsr	x12, x11, #3
  4fb4d8: 386c694a     	ldrb	w10, [x10, x12]
  4fb4dc: 52001d4a     	eor	w10, w10, #0xff
  4fb4e0: 9240096b     	and	x11, x11, #0x7
  4fb4e4: 1acb254a     	lsr	w10, w10, w11
  4fb4e8: 3707fdaa     	tbnz	w10, #0x0, 0x4fb49c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x7b4>
  4fb4ec: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4fb4f0: f9001be9     	str	x9, [sp, #0x30]
  4fb4f4: d342fd6b     	lsr	x11, x11, #2
  4fb4f8: eb0b013f     	cmp	x9, x11
  4fb4fc: 54001482     	b.hs	0x4fb78c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xaa4>
  4fb500: bc697940     	ldr	s0, [x10, x9, lsl #2]
  4fb504: 1e22c000     	fcvt	d0, s0
  4fb508: 91000529     	add	x9, x9, #0x1
  4fb50c: fc337a80     	str	d0, [x20, x19, lsl #3]
  4fb510: 91000673     	add	x19, x19, #0x1
  4fb514: eb09011f     	cmp	x8, x9
  4fb518: 54fffce1     	b.ne	0x4fb4b4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x7cc>
  4fb51c: 17ffffc8     	b	0x4fb43c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x754>
  4fb520: 92800008     	mov	x8, #-0x1               ; =-1
  4fb524: f9000388     	str	x8, [x28]
  4fb528: 14000089     	b	0x4fb74c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa64>
  4fb52c: a940a6a8     	ldp	x8, x9, [x21, #0x8]
  4fb530: a90327e8     	stp	x8, x9, [sp, #0x30]
  4fb534: 9100c3e8     	add	x8, sp, #0x30
  4fb538: 90000409     	adrp	x9, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4fb53c: 9111e129     	add	x9, x9, #0x478
  4fb540: a90127e8     	stp	x8, x9, [sp, #0x10]
  4fb544: f0000ca0     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4fb548: 911ab800     	add	x0, x0, #0x6ae
  4fb54c: 910103e8     	add	x8, sp, #0x40
  4fb550: 910043e1     	add	x1, sp, #0x10
  4fb554: 97f53c54     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4fb558: 3dc013e0     	ldr	q0, [sp, #0x40]
  4fb55c: f9402be8     	ldr	x8, [sp, #0x50]
  4fb560: 3d800380     	str	q0, [x28]
  4fb564: f9000b88     	str	x8, [x28, #0x10]
  4fb568: 14000079     	b	0x4fb74c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa64>
  4fb56c: f90007e0     	str	x0, [sp, #0x8]
  4fb570: f94016a8     	ldr	x8, [x21, #0x28]
  4fb574: b4000e68     	cbz	x8, 0x4fb740 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa58>
  4fb578: d2800017     	mov	x23, #0x0               ; =0
  4fb57c: f94012b8     	ldr	x24, [x21, #0x20]
  4fb580: 8b081308     	add	x8, x24, x8, lsl #4
  4fb584: f90003e8     	str	x8, [sp]
  4fb588: a940eeb9     	ldp	x25, x27, [x21, #0x8]
  4fb58c: d2f8fc08     	mov	x8, #-0x3820000000000000 ; =-4044232465378705408
  4fb590: 9e670109     	fmov	d9, x8
  4fb594: 92f70408     	mov	x8, #0x47dfffffffffffff ; =5179139571476070399
  4fb598: 9e67010a     	fmov	d10, x8
  4fb59c: 92f00013     	mov	x19, #0x7fffffffffffffff ; =9223372036854775807
  4fb5a0: 14000005     	b	0x4fb5b4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x8cc>
  4fb5a4: 91004318     	add	x24, x24, #0x10
  4fb5a8: f94003e8     	ldr	x8, [sp]
  4fb5ac: eb08031f     	cmp	x24, x8
  4fb5b0: 54000c80     	b.eq	0x4fb740 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa58>
  4fb5b4: a9402708     	ldp	x8, x9, [x24]
  4fb5b8: f940092a     	ldr	x10, [x9, #0x10]
  4fb5bc: d100054a     	sub	x10, x10, #0x1
  4fb5c0: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4fb5c4: 8b0a0108     	add	x8, x8, x10
  4fb5c8: f9401129     	ldr	x9, [x9, #0x20]
  4fb5cc: 91004100     	add	x0, x8, #0x10
  4fb5d0: d63f0120     	blr	x9
  4fb5d4: aa0003f6     	mov	x22, x0
  4fb5d8: f9400c29     	ldr	x9, [x1, #0x18]
  4fb5dc: 910103e8     	add	x8, sp, #0x40
  4fb5e0: d63f0120     	blr	x9
  4fb5e4: a94427e8     	ldp	x8, x9, [sp, #0x40]
  4fb5e8: d28c3c0a     	mov	x10, #0x61e0            ; =25056
  4fb5ec: f2ac3bca     	movk	x10, #0x61de, lsl #16
  4fb5f0: f2d0896a     	movk	x10, #0x844b, lsl #32
  4fb5f4: f2f5f7ea     	movk	x10, #0xafbf, lsl #48
  4fb5f8: eb0a013f     	cmp	x9, x10
  4fb5fc: d29b43c9     	mov	x9, #0xda1e             ; =55838
  4fb600: f2baa4a9     	movk	x9, #0xd525, lsl #16
  4fb604: f2d868a9     	movk	x9, #0xc345, lsl #32
  4fb608: f2f16e09     	movk	x9, #0x8b70, lsl #48
  4fb60c: fa490100     	ccmp	x8, x9, #0x0, eq
  4fb610: 54000d81     	b.ne	0x4fb7c0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xad8>
  4fb614: f94016c8     	ldr	x8, [x22, #0x28]
  4fb618: d343fd1c     	lsr	x28, x8, #3
  4fb61c: b4fffc5c     	cbz	x28, 0x4fb5a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x8bc>
  4fb620: d2800015     	mov	x21, #0x0               ; =0
  4fb624: 14000009     	b	0x4fb648 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x960>
  4fb628: b0001588     	adrp	x8, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4fb62c: f9404508     	ldr	x8, [x8, #0x88]
  4fb630: fd400108     	ldr	d8, [x8]
  4fb634: 910006b5     	add	x21, x21, #0x1
  4fb638: fc377a88     	str	d8, [x20, x23, lsl #3]
  4fb63c: 910006f7     	add	x23, x23, #0x1
  4fb640: eb15039f     	cmp	x28, x21
  4fb644: 54fffb00     	b.eq	0x4fb5a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x8bc>
  4fb648: f9401ac8     	ldr	x8, [x22, #0x30]
  4fb64c: b40001a8     	cbz	x8, 0x4fb680 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x998>
  4fb650: f9402ac8     	ldr	x8, [x22, #0x50]
  4fb654: eb0802bf     	cmp	x21, x8
  4fb658: 540008e2     	b.hs	0x4fb774 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa8c>
  4fb65c: f9401ec8     	ldr	x8, [x22, #0x38]
  4fb660: f94026c9     	ldr	x9, [x22, #0x48]
  4fb664: 8b0902a9     	add	x9, x21, x9
  4fb668: d343fd2a     	lsr	x10, x9, #3
  4fb66c: 386a6908     	ldrb	w8, [x8, x10]
  4fb670: 52001d08     	eor	w8, w8, #0xff
  4fb674: 92400929     	and	x9, x9, #0x7
  4fb678: 1ac92508     	lsr	w8, w8, w9
  4fb67c: 3707fd68     	tbnz	w8, #0x0, 0x4fb628 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x940>
  4fb680: a94226c8     	ldp	x8, x9, [x22, #0x20]
  4fb684: f90017f5     	str	x21, [sp, #0x28]
  4fb688: d343fd29     	lsr	x9, x9, #3
  4fb68c: eb0902bf     	cmp	x21, x9
  4fb690: 54000ba2     	b.hs	0x4fb804 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xb1c>
  4fb694: f875791a     	ldr	x26, [x8, x21, lsl #3]
  4fb698: a902e7fa     	stp	x26, x25, [sp, #0x28]
  4fb69c: f9001ffb     	str	x27, [sp, #0x38]
  4fb6a0: 9e620348     	scvtf	d8, x26
  4fb6a4: 4ea81d00     	mov.16b	v0, v8
  4fb6a8: 9405bfa4     	bl	0x66b538 <___fixdfti>
  4fb6ac: 1e692100     	fcmp	d8, d9
  4fb6b0: 9a80b3e8     	csel	x8, xzr, x0, lt
  4fb6b4: d2f00009     	mov	x9, #-0x8000000000000000 ; =-9223372036854775808
  4fb6b8: 9a81b129     	csel	x9, x9, x1, lt
  4fb6bc: 1e6a2100     	fcmp	d8, d10
  4fb6c0: 9a89c269     	csel	x9, x19, x9, gt
  4fb6c4: da9fd108     	csinv	x8, x8, xzr, le
  4fb6c8: 1e682100     	fcmp	d8, d8
  4fb6cc: 9a8863e8     	csel	x8, xzr, x8, vs
  4fb6d0: 9a8963e9     	csel	x9, xzr, x9, vs
  4fb6d4: eb9afd3f     	cmp	x9, x26, asr #63
  4fb6d8: fa5a0100     	ccmp	x8, x26, #0x0, eq
  4fb6dc: 54fffac0     	b.eq	0x4fb634 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x94c>
  4fb6e0: 9100c3e8     	add	x8, sp, #0x30
  4fb6e4: f90023e8     	str	x8, [sp, #0x40]
  4fb6e8: 90000408     	adrp	x8, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4fb6ec: 9111e109     	add	x9, x8, #0x478
  4fb6f0: 9100a3e8     	add	x8, sp, #0x28
  4fb6f4: a904a3e9     	stp	x9, x8, [sp, #0x48]
  4fb6f8: d0fff8c8     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4fb6fc: 91383108     	add	x8, x8, #0xe0c
  4fb700: f9002fe8     	str	x8, [sp, #0x58]
  4fb704: 910043e8     	add	x8, sp, #0x10
  4fb708: 910103e1     	add	x1, sp, #0x40
  4fb70c: f0000ca0     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4fb710: 9120b000     	add	x0, x0, #0x82c
  4fb714: 97f53be4     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4fb718: f9400be8     	ldr	x8, [sp, #0x10]
  4fb71c: fd400fe8     	ldr	d8, [sp, #0x18]
  4fb720: b100051f     	cmn	x8, #0x1
  4fb724: 54fff880     	b.eq	0x4fb634 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0x94c>
  4fb728: f94013e9     	ldr	x9, [sp, #0x20]
  4fb72c: f94007ea     	ldr	x10, [sp, #0x8]
  4fb730: f9000148     	str	x8, [x10]
  4fb734: fd000548     	str	d8, [x10, #0x8]
  4fb738: f9000949     	str	x9, [x10, #0x10]
  4fb73c: 14000004     	b	0x4fb74c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa64>
  4fb740: 92800008     	mov	x8, #-0x1               ; =-1
  4fb744: f94007e9     	ldr	x9, [sp, #0x8]
  4fb748: f9000128     	str	x8, [x9]
  4fb74c: a94d7bfd     	ldp	x29, x30, [sp, #0xd0]
  4fb750: a94c4ff4     	ldp	x20, x19, [sp, #0xc0]
  4fb754: a94b57f6     	ldp	x22, x21, [sp, #0xb0]
  4fb758: a94a5ff8     	ldp	x24, x23, [sp, #0xa0]
  4fb75c: a94967fa     	ldp	x26, x25, [sp, #0x90]
  4fb760: a9486ffc     	ldp	x28, x27, [sp, #0x80]
  4fb764: 6d4723e9     	ldp	d9, d8, [sp, #0x70]
  4fb768: 6d462beb     	ldp	d11, d10, [sp, #0x60]
  4fb76c: 910383ff     	add	sp, sp, #0xe0
  4fb770: d65f03c0     	ret
  4fb774: d0000de0     	adrp	x0, 0x6b9000 <_anon.890451a7770732c097b206d6a5e0f5a0.79+0x1f52>
  4fb778: 91299400     	add	x0, x0, #0xa65
  4fb77c: d0001682     	adrp	x2, 0x7cd000 <_anon.17c5721064fd339e09f2c53fa27ae168.33+0x6b0>
  4fb780: 9104a042     	add	x2, x2, #0x128
  4fb784: 52800481     	mov	w1, #0x24               ; =36
  4fb788: 9405ce17     	bl	0x66efe4 <__RNvNtCsedRpiqSkYaQ_4core9panicking5panic>
  4fb78c: f9000beb     	str	x11, [sp, #0x10]
  4fb790: d0fff8c8     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4fb794: 9134e108     	add	x8, x8, #0xd38
  4fb798: 9100c3e9     	add	x9, sp, #0x30
  4fb79c: a90423e9     	stp	x9, x8, [sp, #0x40]
  4fb7a0: 910043e9     	add	x9, sp, #0x10
  4fb7a4: a90523e9     	stp	x9, x8, [sp, #0x50]
  4fb7a8: d0000c80     	adrp	x0, 0x68d000 <_anon.04010db0aab7d3349d43ab88d34c8e7b.11+0x55>
  4fb7ac: 9129f000     	add	x0, x0, #0xa7c
  4fb7b0: f0001662     	adrp	x2, 0x7ca000 <_anon.b63903f8fb6c95fa4c48e6984aabea60.16+0x538>
  4fb7b4: 91218042     	add	x2, x2, #0x860
  4fb7b8: 910103e1     	add	x1, sp, #0x40
  4fb7bc: 9405ce0f     	bl	0x66eff8 <__RNvNtCsedRpiqSkYaQ_4core9panicking9panic_fmt>
  4fb7c0: a9036ff9     	stp	x25, x27, [sp, #0x30]
  4fb7c4: 9100c3e8     	add	x8, sp, #0x30
  4fb7c8: f9000be8     	str	x8, [sp, #0x10]
  4fb7cc: 90000408     	adrp	x8, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4fb7d0: 9111e108     	add	x8, x8, #0x478
  4fb7d4: f9000fe8     	str	x8, [sp, #0x18]
  4fb7d8: f0000ca0     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4fb7dc: 911ab800     	add	x0, x0, #0x6ae
  4fb7e0: 910103e8     	add	x8, sp, #0x40
  4fb7e4: 910043e1     	add	x1, sp, #0x10
  4fb7e8: 97f53baf     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4fb7ec: 3dc013e0     	ldr	q0, [sp, #0x40]
  4fb7f0: f9402be8     	ldr	x8, [sp, #0x50]
  4fb7f4: f94007e9     	ldr	x9, [sp, #0x8]
  4fb7f8: 3d800120     	str	q0, [x9]
  4fb7fc: f9000928     	str	x8, [x9, #0x10]
  4fb800: 17ffffd3     	b	0x4fb74c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xa64>
  4fb804: f9001be9     	str	x9, [sp, #0x30]
  4fb808: d0fff8c8     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4fb80c: 9134e108     	add	x8, x8, #0xd38
  4fb810: 9100a3e9     	add	x9, sp, #0x28
  4fb814: a90423e9     	stp	x9, x8, [sp, #0x40]
  4fb818: 9100c3e9     	add	x9, sp, #0x30
  4fb81c: 17ffffe2     	b	0x4fb7a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi20fill_semantic_double+0xabc>
