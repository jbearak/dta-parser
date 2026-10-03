
<compatible-copy-evidence>/candidate-v1/library/dtatools/libs/dtatools.so:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000004f97f4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double>:
  4f97f4: d10283ff     	sub	sp, sp, #0xa0
  4f97f8: a9046ffc     	stp	x28, x27, [sp, #0x40]
  4f97fc: a90567fa     	stp	x26, x25, [sp, #0x50]
  4f9800: a9065ff8     	stp	x24, x23, [sp, #0x60]
  4f9804: a90757f6     	stp	x22, x21, [sp, #0x70]
  4f9808: a9084ff4     	stp	x20, x19, [sp, #0x80]
  4f980c: a9097bfd     	stp	x29, x30, [sp, #0x90]
  4f9810: 910243fd     	add	x29, sp, #0x90
  4f9814: aa0203f5     	mov	x21, x2
  4f9818: aa0103f4     	mov	x20, x1
  4f981c: aa0003f3     	mov	x19, x0
  4f9820: d2800017     	mov	x23, #0x0               ; =0
  4f9824: a9422038     	ldp	x24, x8, [x1, #0x20]
  4f9828: 8b081319     	add	x25, x24, x8, lsl #4
  4f982c: d282609a     	mov	x26, #0x1304            ; =4868
  4f9830: f2aabcba     	movk	x26, #0x55e5, lsl #16
  4f9834: f2d0771a     	movk	x26, #0x83b8, lsl #32
  4f9838: f2f6ccba     	movk	x26, #0xb665, lsl #48
  4f983c: d290e75b     	mov	x27, #0x873a            ; =34618
  4f9840: f2b57abb     	movk	x27, #0xabd5, lsl #16
  4f9844: f2c149fb     	movk	x27, #0xa4f, lsl #32
  4f9848: f2ee05fb     	movk	x27, #0x702f, lsl #48
  4f984c: eb19031f     	cmp	x24, x25
  4f9850: 54000580     	b.eq	0x4f9900 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x10c>
  4f9854: a8c12708     	ldp	x8, x9, [x24], #0x10
  4f9858: f940092a     	ldr	x10, [x9, #0x10]
  4f985c: d100054a     	sub	x10, x10, #0x1
  4f9860: 927ced4a     	and	x10, x10, #0xfffffffffffffff0
  4f9864: 8b0a0108     	add	x8, x8, x10
  4f9868: f9401129     	ldr	x9, [x9, #0x20]
  4f986c: 91004100     	add	x0, x8, #0x10
  4f9870: d63f0120     	blr	x9
  4f9874: aa0003f6     	mov	x22, x0
  4f9878: f9400c29     	ldr	x9, [x1, #0x18]
  4f987c: 910083e8     	add	x8, sp, #0x20
  4f9880: d63f0120     	blr	x9
  4f9884: a94227e8     	ldp	x8, x9, [sp, #0x20]
  4f9888: eb1a013f     	cmp	x9, x26
  4f988c: fa5b0100     	ccmp	x8, x27, #0x0, eq
  4f9890: 540003e1     	b.ne	0x4f990c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x118>
  4f9894: f94016c9     	ldr	x9, [x22, #0x28]
  4f9898: d343fd28     	lsr	x8, x9, #3
  4f989c: b4fffd88     	cbz	x8, 0x4f984c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x58>
  4f98a0: f9401aca     	ldr	x10, [x22, #0x30]
  4f98a4: b400020a     	cbz	x10, 0x4f98e4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0xf0>
  4f98a8: f9402eca     	ldr	x10, [x22, #0x58]
  4f98ac: b40001ca     	cbz	x10, 0x4f98e4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0xf0>
  4f98b0: d2800009     	mov	x9, #0x0                ; =0
  4f98b4: a9422eca     	ldp	x10, x11, [x22, #0x20]
  4f98b8: f90003e9     	str	x9, [sp]
  4f98bc: d343fd6b     	lsr	x11, x11, #3
  4f98c0: eb0b013f     	cmp	x9, x11
  4f98c4: 54000522     	b.hs	0x4f9968 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x174>
  4f98c8: fc697940     	ldr	d0, [x10, x9, lsl #3]
  4f98cc: 91000529     	add	x9, x9, #0x1
  4f98d0: fc377aa0     	str	d0, [x21, x23, lsl #3]
  4f98d4: 910006f7     	add	x23, x23, #0x1
  4f98d8: eb09011f     	cmp	x8, x9
  4f98dc: 54fffec1     	b.ne	0x4f98b4 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0xc0>
  4f98e0: 17ffffdb     	b	0x4f984c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x58>
  4f98e4: f94012c1     	ldr	x1, [x22, #0x20]
  4f98e8: 8b170ea0     	add	x0, x21, x23, lsl #3
  4f98ec: 927df122     	and	x2, x9, #0xfffffffffffffff8
  4f98f0: 94061872     	bl	0x67fab8 <dyld_stub_binder+0x67fab8>
  4f98f4: f94016c8     	ldr	x8, [x22, #0x28]
  4f98f8: 8b480ef7     	add	x23, x23, x8, lsr #3
  4f98fc: 17ffffd4     	b	0x4f984c <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x58>
  4f9900: 92800008     	mov	x8, #-0x1               ; =-1
  4f9904: f9000268     	str	x8, [x19]
  4f9908: 14000010     	b	0x4f9948 <__RNvNtCs69X5pnBqK1V_10dtatools_r9arrow_ffi19fill_payload_double+0x154>
  4f990c: a940a688     	ldp	x8, x9, [x20, #0x8]
  4f9910: a90027e8     	stp	x8, x9, [sp]
  4f9914: 910003e8     	mov	x8, sp
  4f9918: d0000409     	adrp	x9, 0x57b000 <__RNCINvNtCscW1MftiIkNN_9dta_tools5write23write_metadata_sectionsINtNtNtNtCskP2HG43Jt7g_3std2io8buffered9bufwriter9BufWriterNtNtB18_2fs4FileENtCs69X5pnBqK1V_10dtatools_r23RWriteObservationSourceNtB4_26DtaWriteValueLabelRegistryEs0_0B2f_+0x450>
  4f991c: 9111e129     	add	x9, x9, #0x478
  4f9920: a90127e8     	stp	x8, x9, [sp, #0x10]
  4f9924: b0000cc0     	adrp	x0, 0x692000 <_anon.add9ad889c62dd6a08d60c61082fd7dd.63+0x9>
  4f9928: 911ab800     	add	x0, x0, #0x6ae
  4f992c: 910083e8     	add	x8, sp, #0x20
  4f9930: 910043e1     	add	x1, sp, #0x10
  4f9934: 97f5435c     	bl	0x24a6a4 <__RNvNvNtCs26gtQGs340n_5alloc3fmt6format12format_inner>
  4f9938: 3dc00be0     	ldr	q0, [sp, #0x20]
  4f993c: f9401be8     	ldr	x8, [sp, #0x30]
  4f9940: 3d800260     	str	q0, [x19]
  4f9944: f9000a68     	str	x8, [x19, #0x10]
  4f9948: a9497bfd     	ldp	x29, x30, [sp, #0x90]
  4f994c: a9484ff4     	ldp	x20, x19, [sp, #0x80]
  4f9950: a94757f6     	ldp	x22, x21, [sp, #0x70]
  4f9954: a9465ff8     	ldp	x24, x23, [sp, #0x60]
  4f9958: a94567fa     	ldp	x26, x25, [sp, #0x50]
  4f995c: a9446ffc     	ldp	x28, x27, [sp, #0x40]
  4f9960: 910283ff     	add	sp, sp, #0xa0
  4f9964: d65f03c0     	ret
  4f9968: f9000beb     	str	x11, [sp, #0x10]
  4f996c: 90fff8e8     	adrp	x8, 0x415000 <__RNvXs3_NtNtNtCsedRpiqSkYaQ_4core3fmt3num3imptNtB9_7Display3fmt+0x4>
  4f9970: 9134e108     	add	x8, x8, #0xd38
  4f9974: 910003e9     	mov	x9, sp
  4f9978: a90223e9     	stp	x9, x8, [sp, #0x20]
  4f997c: 910043e9     	add	x9, sp, #0x10
  4f9980: a90323e9     	stp	x9, x8, [sp, #0x30]
  4f9984: 90000ca0     	adrp	x0, 0x68d000 <_anon.04010db0aab7d3349d43ab88d34c8e7b.11+0x55>
  4f9988: 9129f000     	add	x0, x0, #0xa7c
  4f998c: b0001682     	adrp	x2, 0x7ca000 <_anon.b63903f8fb6c95fa4c48e6984aabea60.16+0x538>
  4f9990: 91218042     	add	x2, x2, #0x860
  4f9994: 910083e1     	add	x1, sp, #0x20
  4f9998: 9405d598     	bl	0x66eff8 <__RNvNtCsedRpiqSkYaQ_4core9panicking9panic_fmt>
