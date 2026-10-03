
<compatible-copy-evidence>/candidate-v1/library/dtatools/libs/dtatools.so:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000004ed088 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer>:
  4ed088: d10283ff     	sub	sp, sp, #0xa0
  4ed08c: a9046ffc     	stp	x28, x27, [sp, #0x40]
  4ed090: a90567fa     	stp	x26, x25, [sp, #0x50]
  4ed094: a9065ff8     	stp	x24, x23, [sp, #0x60]
  4ed098: a90757f6     	stp	x22, x21, [sp, #0x70]
  4ed09c: a9084ff4     	stp	x20, x19, [sp, #0x80]
  4ed0a0: a9097bfd     	stp	x29, x30, [sp, #0x90]
  4ed0a4: 910243fd     	add	x29, sp, #0x90
  4ed0a8: aa0203f5     	mov	x21, x2
  4ed0ac: aa0103f4     	mov	x20, x1
  4ed0b0: aa0003f3     	mov	x19, x0
  4ed0b4: 39446028     	ldrb	w8, [x1, #0x118]
  4ed0b8: 71000d1f     	cmp	w8, #0x3
  4ed0bc: 540009ed     	b.le	0x4ed1f8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x170>
  4ed0c0: 7100111f     	cmp	w8, #0x4
  4ed0c4: 54001320     	b.eq	0x4ed328 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x2a0>
  4ed0c8: 7100191f     	cmp	w8, #0x6
  4ed0cc: 54001cc0     	b.eq	0x4ed464 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x3dc>
  4ed0d0: 71001d1f     	cmp	w8, #0x7
  4ed0d4: 54003061     	b.ne	0x4ed6e0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x658>
  4ed0d8: f9401688     	ldr	x8, [x20, #0x28]
  4ed0dc: b4002dc8     	cbz	x8, 0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed0e0: d2800017     	mov	x23, #0x0               ; =0
  4ed0e4: f9401298     	ldr	x24, [x20, #0x20]
  4ed0e8: 8b081319     	add	x25, x24, x8, lsl #4
  4ed0ec: d29613fa     	mov	x26, #0xb09f            ; =45215
  4ed0f0: f2a41d5a     	movk	x26, #0x20ea, lsl #16
  4ed0f4: f2c3aeda     	movk	x26, #0x1d76, lsl #32
  4ed0f8: f2e9967a     	movk	x26, #0x4cb3, lsl #48
  4ed0fc: d2928d5b     	mov	x27, #0x946a            ; =37994
  4ed100: f2a0ae1b     	movk	x27, #0x570, lsl #16
  4ed104: f2c8a91b     	movk	x27, #0x4548, lsl #32
  4ed108: f2ee681b     	movk	x27, #0x7340, lsl #48
  4ed10c: f00015fc     	adrp	x28, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4ed110: f9403f9c     	ldr	x28, [x28, #0x78]
  4ed114: 14000004     	b	0x4ed124 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x9c>
  4ed118: 91004318     	add	x24, x24, #0x10
  4ed11c: eb19031f     	cmp	x24, x25
  4ed120: 54002ba0     	b.eq	0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed124: a9402708     	ldp	x8, x9, [x24]
  4ed128: f940092a     	ldr	x10, [x9, #0x10]
  4ed12c: d100054a     	sub	x10, x10, #0x1
  4ed130: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4ed134: 8b0a0108     	add	x8, x8, x10
  4ed138: f9401129     	ldr	x9, [x9, #0x20]
  4ed13c: 91004100     	add	x0, x8, #0x10
  4ed140: d63f0120     	blr	x9
  4ed144: aa0003f6     	mov	x22, x0
  4ed148: f9400c29     	ldr	x9, [x1, #0x18]
  4ed14c: 910083e8     	add	x8, sp, #0x20
  4ed150: d63f0120     	blr	x9
  4ed154: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4ed158: eb1a013f     	cmp	x9, x26
  4ed15c: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4ed160: 54002a01     	b.ne	0x4ed6a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x618>
  4ed164: f94016c8     	ldr	x8, [x22, #0x28]
  4ed168: d341fd08     	lsr	x8, x8, #1
  4ed16c: b4fffd68     	cbz	x8, 0x4ed118 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x90>
  4ed170: d2800009     	mov	x9, #0x0                ; =0
  4ed174: 14000007     	b	0x4ed190 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x108>
  4ed178: b940038a     	ldr	w10, [x28]
  4ed17c: 91000529     	add	x9, x9, #0x1
  4ed180: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed184: 910006f7     	add	x23, x23, #0x1
  4ed188: eb09011f     	cmp	x8, x9
  4ed18c: 54fffc60     	b.eq	0x4ed118 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x90>
  4ed190: f9401aca     	ldr	x10, [x22, #0x30]
  4ed194: b40001aa     	cbz	x10, 0x4ed1c8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x140>
  4ed198: f9402aca     	ldr	x10, [x22, #0x50]
  4ed19c: eb0a013f     	cmp	x9, x10
  4ed1a0: 54002e02     	b.hs	0x4ed760 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6d8>
  4ed1a4: f9401eca     	ldr	x10, [x22, #0x38]
  4ed1a8: f94026cb     	ldr	x11, [x22, #0x48]
  4ed1ac: 8b0b012b     	add	x11, x9, x11
  4ed1b0: d343fd6c     	lsr	x12, x11, #3
  4ed1b4: 386c694a     	ldrb	w10, [x10, x12]
  4ed1b8: 52001d4a     	eor	w10, w10, #0xff
  4ed1bc: 9240096b     	and	x11, x11, #0x7
  4ed1c0: 1acb254a     	lsr	w10, w10, w11
  4ed1c4: 3707fdaa     	tbnz	w10, #0x0, 0x4ed178 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0xf0>
  4ed1c8: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4ed1cc: f90003e9     	str	x9, [sp]
  4ed1d0: d341fd6b     	lsr	x11, x11, #1
  4ed1d4: eb0b013f     	cmp	x9, x11
  4ed1d8: 54002aa2     	b.hs	0x4ed72c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6a4>
  4ed1dc: 7869794a     	ldrh	w10, [x10, x9, lsl #1]
  4ed1e0: 91000529     	add	x9, x9, #0x1
  4ed1e4: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed1e8: 910006f7     	add	x23, x23, #0x1
  4ed1ec: eb09011f     	cmp	x8, x9
  4ed1f0: 54fffd01     	b.ne	0x4ed190 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x108>
  4ed1f4: 17ffffc9     	b	0x4ed118 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x90>
  4ed1f8: 7100091f     	cmp	w8, #0x2
  4ed1fc: 54001c00     	b.eq	0x4ed57c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x4f4>
  4ed200: 71000d1f     	cmp	w8, #0x3
  4ed204: 540026e1     	b.ne	0x4ed6e0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x658>
  4ed208: f9401688     	ldr	x8, [x20, #0x28]
  4ed20c: b4002448     	cbz	x8, 0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed210: d2800017     	mov	x23, #0x0               ; =0
  4ed214: f9401298     	ldr	x24, [x20, #0x20]
  4ed218: 8b081319     	add	x25, x24, x8, lsl #4
  4ed21c: d291a41a     	mov	x26, #0x8d20            ; =36128
  4ed220: f2ae3c9a     	movk	x26, #0x71e4, lsl #16
  4ed224: f2d6d5ba     	movk	x26, #0xb6ad, lsl #32
  4ed228: f2e9d1da     	movk	x26, #0x4e8e, lsl #48
  4ed22c: d294d17b     	mov	x27, #0xa68b            ; =42635
  4ed230: f2be933b     	movk	x27, #0xf499, lsl #16
  4ed234: f2cb571b     	movk	x27, #0x5ab8, lsl #32
  4ed238: f2e1eefb     	movk	x27, #0xf77, lsl #48
  4ed23c: f00015fc     	adrp	x28, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4ed240: f9403f9c     	ldr	x28, [x28, #0x78]
  4ed244: 14000004     	b	0x4ed254 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x1cc>
  4ed248: 91004318     	add	x24, x24, #0x10
  4ed24c: eb19031f     	cmp	x24, x25
  4ed250: 54002220     	b.eq	0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed254: a9402708     	ldp	x8, x9, [x24]
  4ed258: f940092a     	ldr	x10, [x9, #0x10]
  4ed25c: d100054a     	sub	x10, x10, #0x1
  4ed260: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4ed264: 8b0a0108     	add	x8, x8, x10
  4ed268: f9401129     	ldr	x9, [x9, #0x20]
  4ed26c: 91004100     	add	x0, x8, #0x10
  4ed270: d63f0120     	blr	x9
  4ed274: aa0003f6     	mov	x22, x0
  4ed278: f9400c29     	ldr	x9, [x1, #0x18]
  4ed27c: 910083e8     	add	x8, sp, #0x20
  4ed280: d63f0120     	blr	x9
  4ed284: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4ed288: eb1a013f     	cmp	x9, x26
  4ed28c: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4ed290: 54002081     	b.ne	0x4ed6a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x618>
  4ed294: f94016c8     	ldr	x8, [x22, #0x28]
  4ed298: d341fd08     	lsr	x8, x8, #1
  4ed29c: b4fffd68     	cbz	x8, 0x4ed248 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x1c0>
  4ed2a0: d2800009     	mov	x9, #0x0                ; =0
  4ed2a4: 14000007     	b	0x4ed2c0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x238>
  4ed2a8: b940038a     	ldr	w10, [x28]
  4ed2ac: 91000529     	add	x9, x9, #0x1
  4ed2b0: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed2b4: 910006f7     	add	x23, x23, #0x1
  4ed2b8: eb09011f     	cmp	x8, x9
  4ed2bc: 54fffc60     	b.eq	0x4ed248 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x1c0>
  4ed2c0: f9401aca     	ldr	x10, [x22, #0x30]
  4ed2c4: b40001aa     	cbz	x10, 0x4ed2f8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x270>
  4ed2c8: f9402aca     	ldr	x10, [x22, #0x50]
  4ed2cc: eb0a013f     	cmp	x9, x10
  4ed2d0: 54002482     	b.hs	0x4ed760 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6d8>
  4ed2d4: f9401eca     	ldr	x10, [x22, #0x38]
  4ed2d8: f94026cb     	ldr	x11, [x22, #0x48]
  4ed2dc: 8b0b012b     	add	x11, x9, x11
  4ed2e0: d343fd6c     	lsr	x12, x11, #3
  4ed2e4: 386c694a     	ldrb	w10, [x10, x12]
  4ed2e8: 52001d4a     	eor	w10, w10, #0xff
  4ed2ec: 9240096b     	and	x11, x11, #0x7
  4ed2f0: 1acb254a     	lsr	w10, w10, w11
  4ed2f4: 3707fdaa     	tbnz	w10, #0x0, 0x4ed2a8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x220>
  4ed2f8: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4ed2fc: f90003e9     	str	x9, [sp]
  4ed300: d341fd6b     	lsr	x11, x11, #1
  4ed304: eb0b013f     	cmp	x9, x11
  4ed308: 54002122     	b.hs	0x4ed72c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6a4>
  4ed30c: 78e9794a     	ldrsh	w10, [x10, x9, lsl #1]
  4ed310: 91000529     	add	x9, x9, #0x1
  4ed314: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed318: 910006f7     	add	x23, x23, #0x1
  4ed31c: eb09011f     	cmp	x8, x9
  4ed320: 54fffd01     	b.ne	0x4ed2c0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x238>
  4ed324: 17ffffc9     	b	0x4ed248 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x1c0>
  4ed328: d2800017     	mov	x23, #0x0               ; =0
  4ed32c: a9422298     	ldp	x24, x8, [x20, #0x20]
  4ed330: 8b081319     	add	x25, x24, x8, lsl #4
  4ed334: d2832c1a     	mov	x26, #0x1960            ; =6496
  4ed338: f2b709da     	movk	x26, #0xb84e, lsl #16
  4ed33c: f2cdd31a     	movk	x26, #0x6e98, lsl #32
  4ed340: f2f6e93a     	movk	x26, #0xb749, lsl #48
  4ed344: d2928cfb     	mov	x27, #0x9467            ; =37991
  4ed348: f2a291bb     	movk	x27, #0x148d, lsl #16
  4ed34c: f2c2da7b     	movk	x27, #0x16d3, lsl #32
  4ed350: f2e4e71b     	movk	x27, #0x2738, lsl #48
  4ed354: f00015fc     	adrp	x28, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4ed358: f9403f9c     	ldr	x28, [x28, #0x78]
  4ed35c: eb19031f     	cmp	x24, x25
  4ed360: 540019a0     	b.eq	0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed364: a8c12708     	ldp	x8, x9, [x24], #0x10
  4ed368: f940092a     	ldr	x10, [x9, #0x10]
  4ed36c: d100054a     	sub	x10, x10, #0x1
  4ed370: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4ed374: 8b0a0108     	add	x8, x8, x10
  4ed378: f9401129     	ldr	x9, [x9, #0x20]
  4ed37c: 91004100     	add	x0, x8, #0x10
  4ed380: d63f0120     	blr	x9
  4ed384: aa0003f6     	mov	x22, x0
  4ed388: f9400c29     	ldr	x9, [x1, #0x18]
  4ed38c: 910083e8     	add	x8, sp, #0x20
  4ed390: d63f0120     	blr	x9
  4ed394: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4ed398: eb1a013f     	cmp	x9, x26
  4ed39c: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4ed3a0: 54001801     	b.ne	0x4ed6a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x618>
  4ed3a4: f94016c9     	ldr	x9, [x22, #0x28]
  4ed3a8: d342fd28     	lsr	x8, x9, #2
  4ed3ac: b4fffd88     	cbz	x8, 0x4ed35c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x2d4>
  4ed3b0: f9401aca     	ldr	x10, [x22, #0x30]
  4ed3b4: b40004aa     	cbz	x10, 0x4ed448 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x3c0>
  4ed3b8: f9402eca     	ldr	x10, [x22, #0x58]
  4ed3bc: b400046a     	cbz	x10, 0x4ed448 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x3c0>
  4ed3c0: d2800009     	mov	x9, #0x0                ; =0
  4ed3c4: 14000007     	b	0x4ed3e0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x358>
  4ed3c8: b940038a     	ldr	w10, [x28]
  4ed3cc: 91000529     	add	x9, x9, #0x1
  4ed3d0: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed3d4: 910006f7     	add	x23, x23, #0x1
  4ed3d8: eb09011f     	cmp	x8, x9
  4ed3dc: 54fffc00     	b.eq	0x4ed35c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x2d4>
  4ed3e0: f9401aca     	ldr	x10, [x22, #0x30]
  4ed3e4: b40001aa     	cbz	x10, 0x4ed418 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x390>
  4ed3e8: f9402aca     	ldr	x10, [x22, #0x50]
  4ed3ec: eb0a013f     	cmp	x9, x10
  4ed3f0: 54001b82     	b.hs	0x4ed760 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6d8>
  4ed3f4: f9401eca     	ldr	x10, [x22, #0x38]
  4ed3f8: f94026cb     	ldr	x11, [x22, #0x48]
  4ed3fc: 8b0b012b     	add	x11, x9, x11
  4ed400: d343fd6c     	lsr	x12, x11, #3
  4ed404: 386c694a     	ldrb	w10, [x10, x12]
  4ed408: 52001d4a     	eor	w10, w10, #0xff
  4ed40c: 9240096b     	and	x11, x11, #0x7
  4ed410: 1acb254a     	lsr	w10, w10, w11
  4ed414: 3707fdaa     	tbnz	w10, #0x0, 0x4ed3c8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x340>
  4ed418: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4ed41c: f90003e9     	str	x9, [sp]
  4ed420: d342fd6b     	lsr	x11, x11, #2
  4ed424: eb0b013f     	cmp	x9, x11
  4ed428: 54001822     	b.hs	0x4ed72c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6a4>
  4ed42c: b869794a     	ldr	w10, [x10, x9, lsl #2]
  4ed430: 91000529     	add	x9, x9, #0x1
  4ed434: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed438: 910006f7     	add	x23, x23, #0x1
  4ed43c: eb09011f     	cmp	x8, x9
  4ed440: 54fffd01     	b.ne	0x4ed3e0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x358>
  4ed444: 17ffffc6     	b	0x4ed35c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x2d4>
  4ed448: f94012c1     	ldr	x1, [x22, #0x20]
  4ed44c: 8b170aa0     	add	x0, x21, x23, lsl #2
  4ed450: 927ef522     	and	x2, x9, #0xfffffffffffffffc
  4ed454: 94064999     	bl	0x67fab8 <dyld_stub_binder+0x67fab8>
  4ed458: f94016c8     	ldr	x8, [x22, #0x28]
  4ed45c: 8b480af7     	add	x23, x23, x8, lsr #2
  4ed460: 17ffffbf     	b	0x4ed35c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x2d4>
  4ed464: f9401688     	ldr	x8, [x20, #0x28]
  4ed468: b4001168     	cbz	x8, 0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed46c: d2800017     	mov	x23, #0x0               ; =0
  4ed470: f9401298     	ldr	x24, [x20, #0x20]
  4ed474: 8b081319     	add	x25, x24, x8, lsl #4
  4ed478: d28d641a     	mov	x26, #0x6b20            ; =27424
  4ed47c: f2a64c7a     	movk	x26, #0x3263, lsl #16
  4ed480: f2c9dada     	movk	x26, #0x4ed6, lsl #32
  4ed484: f2fdb31a     	movk	x26, #0xed98, lsl #48
  4ed488: d29fa71b     	mov	x27, #0xfd38            ; =64824
  4ed48c: f2a0a4fb     	movk	x27, #0x527, lsl #16
  4ed490: f2d956db     	movk	x27, #0xcab6, lsl #32
  4ed494: f2f4fa9b     	movk	x27, #0xa7d4, lsl #48
  4ed498: f00015fc     	adrp	x28, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4ed49c: f9403f9c     	ldr	x28, [x28, #0x78]
  4ed4a0: 14000004     	b	0x4ed4b0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x428>
  4ed4a4: 91004318     	add	x24, x24, #0x10
  4ed4a8: eb19031f     	cmp	x24, x25
  4ed4ac: 54000f40     	b.eq	0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed4b0: a9402708     	ldp	x8, x9, [x24]
  4ed4b4: f940092a     	ldr	x10, [x9, #0x10]
  4ed4b8: d100054a     	sub	x10, x10, #0x1
  4ed4bc: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4ed4c0: 8b0a0108     	add	x8, x8, x10
  4ed4c4: f9401129     	ldr	x9, [x9, #0x20]
  4ed4c8: 91004100     	add	x0, x8, #0x10
  4ed4cc: d63f0120     	blr	x9
  4ed4d0: aa0003f6     	mov	x22, x0
  4ed4d4: f9400c29     	ldr	x9, [x1, #0x18]
  4ed4d8: 910083e8     	add	x8, sp, #0x20
  4ed4dc: d63f0120     	blr	x9
  4ed4e0: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4ed4e4: eb1a013f     	cmp	x9, x26
  4ed4e8: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4ed4ec: 54000da1     	b.ne	0x4ed6a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x618>
  4ed4f0: f94016c8     	ldr	x8, [x22, #0x28]
  4ed4f4: b4fffd88     	cbz	x8, 0x4ed4a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x41c>
  4ed4f8: d2800009     	mov	x9, #0x0                ; =0
  4ed4fc: 14000007     	b	0x4ed518 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x490>
  4ed500: b940038a     	ldr	w10, [x28]
  4ed504: 91000529     	add	x9, x9, #0x1
  4ed508: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed50c: 910006f7     	add	x23, x23, #0x1
  4ed510: eb09011f     	cmp	x8, x9
  4ed514: 54fffc80     	b.eq	0x4ed4a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x41c>
  4ed518: f9401aca     	ldr	x10, [x22, #0x30]
  4ed51c: b40001aa     	cbz	x10, 0x4ed550 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x4c8>
  4ed520: f9402aca     	ldr	x10, [x22, #0x50]
  4ed524: eb0a013f     	cmp	x9, x10
  4ed528: 540011c2     	b.hs	0x4ed760 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6d8>
  4ed52c: f9401eca     	ldr	x10, [x22, #0x38]
  4ed530: f94026cb     	ldr	x11, [x22, #0x48]
  4ed534: 8b0b012b     	add	x11, x9, x11
  4ed538: d343fd6c     	lsr	x12, x11, #3
  4ed53c: 386c694a     	ldrb	w10, [x10, x12]
  4ed540: 52001d4a     	eor	w10, w10, #0xff
  4ed544: 9240096b     	and	x11, x11, #0x7
  4ed548: 1acb254a     	lsr	w10, w10, w11
  4ed54c: 3707fdaa     	tbnz	w10, #0x0, 0x4ed500 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x478>
  4ed550: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4ed554: f90003e9     	str	x9, [sp]
  4ed558: eb0b013f     	cmp	x9, x11
  4ed55c: 54000e82     	b.hs	0x4ed72c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6a4>
  4ed560: 3869694a     	ldrb	w10, [x10, x9]
  4ed564: 91000529     	add	x9, x9, #0x1
  4ed568: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed56c: 910006f7     	add	x23, x23, #0x1
  4ed570: eb09011f     	cmp	x8, x9
  4ed574: 54fffd21     	b.ne	0x4ed518 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x490>
  4ed578: 17ffffcb     	b	0x4ed4a4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x41c>
  4ed57c: f9401688     	ldr	x8, [x20, #0x28]
  4ed580: b40008a8     	cbz	x8, 0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed584: d2800017     	mov	x23, #0x0               ; =0
  4ed588: f9401298     	ldr	x24, [x20, #0x20]
  4ed58c: 8b081319     	add	x25, x24, x8, lsl #4
  4ed590: d29fdbfa     	mov	x26, #0xfedf            ; =65247
  4ed594: f2b690fa     	movk	x26, #0xb487, lsl #16
  4ed598: f2cf5a9a     	movk	x26, #0x7ad4, lsl #32
  4ed59c: f2fd369a     	movk	x26, #0xe9b4, lsl #48
  4ed5a0: d290519b     	mov	x27, #0x828c            ; =33420
  4ed5a4: f2ad473b     	movk	x27, #0x6a39, lsl #16
  4ed5a8: f2c5c8db     	movk	x27, #0x2e46, lsl #32
  4ed5ac: f2fd0c5b     	movk	x27, #0xe862, lsl #48
  4ed5b0: f00015fc     	adrp	x28, 0x7ac000 <dyld_stub_binder+0x7ac000>
  4ed5b4: f9403f9c     	ldr	x28, [x28, #0x78]
  4ed5b8: 14000004     	b	0x4ed5c8 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x540>
  4ed5bc: 91004318     	add	x24, x24, #0x10
  4ed5c0: eb19031f     	cmp	x24, x25
  4ed5c4: 54000680     	b.eq	0x4ed694 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x60c>
  4ed5c8: a9402708     	ldp	x8, x9, [x24]
  4ed5cc: f940092a     	ldr	x10, [x9, #0x10]
  4ed5d0: d100054a     	sub	x10, x10, #0x1
  4ed5d4: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4ed5d8: 8b0a0108     	add	x8, x8, x10
  4ed5dc: f9401129     	ldr	x9, [x9, #0x20]
  4ed5e0: 91004100     	add	x0, x8, #0x10
  4ed5e4: d63f0120     	blr	x9
  4ed5e8: aa0003f6     	mov	x22, x0
  4ed5ec: f9400c29     	ldr	x9, [x1, #0x18]
  4ed5f0: 910083e8     	add	x8, sp, #0x20
  4ed5f4: d63f0120     	blr	x9
  4ed5f8: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4ed5fc: eb1a013f     	cmp	x9, x26
  4ed600: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4ed604: 540004e1     	b.ne	0x4ed6a0 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x618>
  4ed608: f94016c8     	ldr	x8, [x22, #0x28]
  4ed60c: b4fffd88     	cbz	x8, 0x4ed5bc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x534>
  4ed610: d2800009     	mov	x9, #0x0                ; =0
  4ed614: 14000007     	b	0x4ed630 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x5a8>
  4ed618: b940038a     	ldr	w10, [x28]
  4ed61c: 91000529     	add	x9, x9, #0x1
  4ed620: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed624: 910006f7     	add	x23, x23, #0x1
  4ed628: eb09011f     	cmp	x8, x9
  4ed62c: 54fffc80     	b.eq	0x4ed5bc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x534>
  4ed630: f9401aca     	ldr	x10, [x22, #0x30]
  4ed634: b40001aa     	cbz	x10, 0x4ed668 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x5e0>
  4ed638: f9402aca     	ldr	x10, [x22, #0x50]
  4ed63c: eb0a013f     	cmp	x9, x10
  4ed640: 54000902     	b.hs	0x4ed760 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6d8>
  4ed644: f9401eca     	ldr	x10, [x22, #0x38]
  4ed648: f94026cb     	ldr	x11, [x22, #0x48]
  4ed64c: 8b0b012b     	add	x11, x9, x11
  4ed650: d343fd6c     	lsr	x12, x11, #3
  4ed654: 386c694a     	ldrb	w10, [x10, x12]
  4ed658: 52001d4a     	eor	w10, w10, #0xff
  4ed65c: 9240096b     	and	x11, x11, #0x7
  4ed660: 1acb254a     	lsr	w10, w10, w11
  4ed664: 3707fdaa     	tbnz	w10, #0x0, 0x4ed618 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x590>
  4ed668: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4ed66c: f90003e9     	str	x9, [sp]
  4ed670: eb0b013f     	cmp	x9, x11
  4ed674: 540005c2     	b.hs	0x4ed72c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x6a4>
  4ed678: 38e9694a     	ldrsb	w10, [x10, x9]
  4ed67c: 91000529     	add	x9, x9, #0x1
  4ed680: b8377aaa     	str	w10, [x21, x23, lsl #2]
  4ed684: 910006f7     	add	x23, x23, #0x1
  4ed688: eb09011f     	cmp	x8, x9
  4ed68c: 54fffd21     	b.ne	0x4ed630 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x5a8>
  4ed690: 17ffffcb     	b	0x4ed5bc <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x534>
  4ed694: 92800008     	mov	x8, #-0x1               ; =-1
  4ed698: f9000268     	str	x8, [x19]
  4ed69c: 1400001c     	b	0x4ed70c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x684>
  4ed6a0: a940a688     	ldp	x8, x9, [x20, #0x8]
  4ed6a4: a90027e8     	stp	x8, x9, [sp]
  4ed6a8: 910003e8     	mov	x8, sp
  4ed6ac: d0000469     	adrp	x9, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4ed6b0: 9111e129     	add	x9, x9, #0x478
  4ed6b4: a90127e8     	stp	x8, x9, [sp, #0x10]
  4ed6b8: b0000d20     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4ed6bc: 911ab800     	add	x0, x0, #0x6ae
  4ed6c0: 910083e8     	add	x8, sp, #0x20
  4ed6c4: 910043e1     	add	x1, sp, #0x10
  4ed6c8: 97f573f7     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4ed6cc: 3dc00be0     	ldr	q0, [sp, #0x20]
  4ed6d0: f9401be8     	ldr	x8, [sp, #0x30]
  4ed6d4: 3d800260     	str	q0, [x19]
  4ed6d8: f9000a68     	str	x8, [x19, #0x10]
  4ed6dc: 1400000c     	b	0x4ed70c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi12fill_integer+0x684>
  4ed6e0: a940a688     	ldp	x8, x9, [x20, #0x8]
  4ed6e4: a90127e8     	stp	x8, x9, [sp, #0x10]
  4ed6e8: 910043e8     	add	x8, sp, #0x10
  4ed6ec: d0000469     	adrp	x9, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4ed6f0: 9111e129     	add	x9, x9, #0x478
  4ed6f4: a90227e8     	stp	x8, x9, [sp, #0x20]
  4ed6f8: b0000d20     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4ed6fc: 911ab800     	add	x0, x0, #0x6ae
  4ed700: 910083e1     	add	x1, sp, #0x20
  4ed704: aa1303e8     	mov	x8, x19
  4ed708: 97f573e7     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4ed70c: a9497bfd     	ldp	x29, x30, [sp, #0x90]
  4ed710: a9484ff4     	ldp	x20, x19, [sp, #0x80]
  4ed714: a94757f6     	ldp	x22, x21, [sp, #0x70]
  4ed718: a9465ff8     	ldp	x24, x23, [sp, #0x60]
  4ed71c: a94567fa     	ldp	x26, x25, [sp, #0x50]
  4ed720: a9446ffc     	ldp	x28, x27, [sp, #0x40]
  4ed724: 910283ff     	add	sp, sp, #0xa0
  4ed728: d65f03c0     	ret
  4ed72c: f9000beb     	str	x11, [sp, #0x10]
  4ed730: 90fff948     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4ed734: 9134e108     	add	x8, x8, #0xd38
  4ed738: 910003e9     	mov	x9, sp
  4ed73c: a90223e9     	stp	x9, x8, [sp, #0x20]
  4ed740: 910043e9     	add	x9, sp, #0x10
  4ed744: a90323e9     	stp	x9, x8, [sp, #0x30]
  4ed748: 90000d00     	adrp	x0, 0x68d000 <_anon.04010db0aab7d3349d43ab88d34c8e7b.11+0x55>
  4ed74c: 9129f000     	add	x0, x0, #0xa7c
  4ed750: b00016e2     	adrp	x2, 0x7ca000 <_anon.b63903f8fb6c95fa4c48e6984aabea60.16+0x538>
  4ed754: 91218042     	add	x2, x2, #0x860
  4ed758: 910083e1     	add	x1, sp, #0x20
  4ed75c: 94060627     	bl	0x66eff8 <__RNvNtCsedRpiqSkYaQ_4core9panicking9panic_fmt>
  4ed760: 90000e60     	adrp	x0, 0x6b9000 <_anon.890451a7770732c097b206d6a5e0f5a0.79+0x1f52>
  4ed764: 91299400     	add	x0, x0, #0xa65
  4ed768: 90001702     	adrp	x2, 0x7cd000 <_anon.17c5721064fd339e09f2c53fa27ae168.33+0x6b0>
  4ed76c: 9104a042     	add	x2, x2, #0x128
  4ed770: 52800481     	mov	w1, #0x24               ; =36
  4ed774: 9406061c     	bl	0x66efe4 <__RNvNtCsedRpiqSkYaQ_4core9panicking5panic>
