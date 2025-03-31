// Hand compiled Copyright (c) 2006-2007 John F. Reiser  (2007-06-18)
// from modified LzmaDecode.c.
// LZMA SDK 4.40 Copyright (c) 1999-2006 Igor Pavlov (2006-05-01)
//
// This file is licensed under either of these two licenses:
//   1) GNU Lesser General Public License (GNU LGPL)
//   2) Common Public License (CPL)
// See files LGPL.txt and CPL.html for the text of the licenses.

#ifndef DEBUG  /*{*/
  #define DEBUG 0
#endif  /*}*/

NBPW= 8

kLzmaStreamWasFinishedId= (-1)

kNumTopBits= 24
kTopValue= 1<<kNumTopBits

kNumBitModelTotalBits= 11
kBitModelTotal= (1 << kNumBitModelTotalBits)
kNumMoveBits= 5

kNumPosBitsMax= 4
kNumPosStatesMax= (1 << kNumPosBitsMax)

kLenNumLowBits= 3
kLenNumLowSymbols= (1 << kLenNumLowBits)
kLenNumMidBits= 3
kLenNumMidSymbols= (1 << kLenNumMidBits)
kLenNumHighBits= 8
kLenNumHighSymbols= (1 << kLenNumHighBits)

LenChoice= 0
LenChoice2= (LenChoice + 1)
LenLow= (LenChoice2 + 1)
LenMid= (LenLow + (kNumPosStatesMax << kLenNumLowBits))
LenHigh= (LenMid + (kNumPosStatesMax << kLenNumMidBits))
kNumLenProbs= (LenHigh + kLenNumHighSymbols)

kNumStates= 12
kNumLitStates= 7

kStartPosModelIndex= 4
kEndPosModelIndex= 14
kNumFullDistances= (1 << (kEndPosModelIndex >> 1))

kNumPosSlotBits= 6
kNumLenToPosStates= 4

kNumAlignBits= 4
kAlignTableSize= (1 << kNumAlignBits)

kMatchMinLen= 2

IsMatch= 0
IsRep= (IsMatch + (kNumStates << kNumPosBitsMax))
IsRepG0= (IsRep + kNumStates)
IsRepG1= (IsRepG0 + kNumStates)
IsRepG2= (IsRepG1 + kNumStates)
IsRep0Long= (IsRepG2 + kNumStates)
PosSlot= (IsRep0Long + (kNumStates << kNumPosBitsMax))
SpecPos= (PosSlot + (kNumLenToPosStates << kNumPosSlotBits))
Align= (SpecPos + kNumFullDistances - kEndPosModelIndex)
LenCoder= (Align + kAlignTableSize)
RepLenCoder= (LenCoder + kNumLenProbs)
Literal= (RepLenCoder + kNumLenProbs)

LZMA_BASE_SIZE= Literal  // 1846
LZMA_LIT_SIZE =  (3*256)

/* Subroutine arguments; not saved by callee */
a0	.req x0
a1	.req x1
a1w	.req w1
a2	.req x2
a2w	.req w2
a3	.req x3
a3w	.req w3
a4	.req x4
a4w	.req w4
a5	.req x5
a5w	.req w5
a6	.req x6
a6w	.req w6
a7	.req x7
a7w	.req w7
a8	.req x8
a8w	.req w8
a9	.req x9
a9w	.req w9
a10	.req x10
a10w	.req w10

#include "macros.S"
fp	.req x29  // frame pointer (not used as such)

/* branch and link */
#define call bl

/* branch to link register */
#define ret  br lr

mi	.req w0
mix	.req x0
p_in	.req x1
t0	.req w2
t0x	.req x2
t1	.req w3
t1x	.req x3
t2	.req w4
#define Bit	w5
Bitx	.req x5
i	.req w6
ix	.req x6
len	.req w7

prevB	    .req w8
//AVAIL 	.req w9
//AVAIL 	.req w10
lc	        .req w11
litPosMask	.req w12
posStateMask .req w13
posState	.req w14
state	    .req w15

rep0	.req w16
rep1	.req w17
rep2	.req w18
rep3	.req w19
Range	.req w20
Code	.req w21
prob	.req x22
outBuf	.req x23

inPtr	.req x24
inLim	.req x25
outPtr	.req x26
outLim	.req x27
Probs	.req x28

#define mo	mi  /* mask out,  mask in */
#define symbol	mi
#define bound	t1
#define starp	t2
#define offset	len  /* forward to only use */

#define distance      Bit  /* disjoint lifetimes */
#define numDirectBits Bit  /* disjoint lifetimes */
#define hiBit         Bit  /* disjoint lifetimes */
#define r_nowPos      i
#define r_nowPosx     ix
#define matchB        i    /* disjoint lifetimes */
#define probLen       ix   /* disjoint lifetimes */
#define probLit       ix   /* disjoint lifetimes */
#define posSlot   posState /* disjoint lifetimes */

#define vs x0

#if !defined(PARAMETER_STYLE)  /*{*/
  #define  PARAMETER_STYLE 3
//  Possible choices:
//	1  /*   0 bytes;  1-byte encoding of pb,lp,lc  [default] */
//	2  /* -20 bytes;  2-byte encoding requires no division */
//	3  /* -28 bytes;  separate bytes beginning at -4+ probs */
#endif  /*}*/

/* LzmaDecode(x0=vs, x1=inStream,  w2=inSize,  x3= &inSizeProcessed,
	             x4=outStream, w5=outSize, x6=&outSizeProcessed)
*/
LzmaDecode: .globl LzmaDecode
#if 3==PARAMETER_STYLE  /*{*/
vs_ps= 2
vs_lp= 1
vs_lc= 0
	ldrb w7,[vs,#vs_lc]
	ldrb w8,[vs,#vs_lp]
	ldrb w9,[vs,#vs_ps]
	add x0,vs,#4
#undef vs
#endif  /*}*/

/* LzmaDecode_UPX(x0=probs, x1=inStream,  w2=inSize,  x3= &inSizeProcessed,
	                    x4=outStream, w5=outSize, x6=&outSizeProcessed,
                            w7=lc, w8=lp, w9=ps)
*/
LzmaDecode_UPX:
	stp  fp, lr,[sp,#-16*NBPW]!
	stp x19,x20,[sp,#  2*NBPW]
	stp x21,x22,[sp,#  4*NBPW]
	stp x23,x24,[sp,#  6*NBPW]
	stp x25,x26,[sp,#  8*NBPW]
	stp x27,x28,[sp,# 10*NBPW]

inStream=        12*NBPW
inSizeProcessed= 13*NBPW
	stp  x1, x3,[sp,# 12*NBPW]
outStream=       14*NBPW
outSizeProcessed=15*NBPW
	stp  x4, x6,[sp,# 14*NBPW]

	mov Probs,a0
	add outLim,a4,w5,uxtw  // outSize + outStream
	mov outPtr,a4
	add inLim, a1,w2,uxtw  // inSize + inStream
	mov inPtr,a1
	mov outBuf,a4

#if 1==PARAMETER_STYLE  /*{ [0]: pb*45 + lp*9 + lc */
	lbz a7,0(inPtr); addi inPtr,inPtr,1
	li r0,45; call divwu_a7_r0; mov a9,a8  // pb
	li r0, 9; call divwu_a7_r0  // a8= lp; a7= lc;
#endif  /*}*/

#if 2==PARAMETER_STYLE  /*{ [0]: ((lc + lp)<<3) | pb;  [1]: (lp<<4) | lc */
	lbz a9,0(inPtr);    andi. a9,a9,7  // pb
	lbz a7,1(inPtr);    srwi  a8,a7,4  // lp
	addi inPtr,inPtr,2; andi. a7,a7,0xf  // lc
#endif  /*}*/

	mov lc,a7w
	mov t0,#~0
	lsl posStateMask,t0,a9w
	mvn posStateMask,posStateMask
	lsl litPosMask,t0,a8w
	mvn litPosMask,litPosMask

	add a10w,a7w,a8w  // lc + lp
	mov t0,#LZMA_LIT_SIZE
	lsl a10w,t0,a10w  // LZMA_LIT_SIZE << (lc + lp)
	add a10w,a10w,#LZMA_BASE_SIZE

	lsr t2,a10w,#1  // 2 at a time
	mov t1x,Probs
	mov t0,#(kBitModelTotal>>1)
	orr t0,t0,t0,lsl 16
L10:
	str t0,[t1x],#2*2  // 2 ushort
	sub t2,t2,#1; cbnz t2,L10

	mov t2,#5
L20:
	call rcInit2
	sub t2,t2,#1; cbnz t2,L20

	mov Range,#~0
	mov prevB,#0
	mov state,#0
	mov rep0,#1
	mov rep1,#1
	mov rep2,#1
	mov rep3,#1
	b L200

#if DEBUG  /*{*/
fmt: .ascii "rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG) //{
    .ascii "  prevB=%2x  rep0=%x"
#endif  //}
    .asciz "\n"

diagnose:
	stp  fp, lr,[sp,#-32*NBPW]!
	stp  x0, x1,[sp,#  2*NBPW]
	stp  x2, x3,[sp,#  4*NBPW]
	stp  x4, x5,[sp,#  6*NBPW]
	stp  x6, x7,[sp,#  8*NBPW]
	stp  x8, x9,[sp,# 10*NBPW]
	stp x10,x11,[sp,# 12*NBPW]
	stp x12,x13,[sp,# 14*NBPW]
	stp x14,x15,[sp,# 16*NBPW]
	stp x16,x17,[sp,# 18*NBPW]
	stp x18,x19,[sp,# 20*NBPW]
	stp x20,x21,[sp,# 22*NBPW]
	stp x22,x23,[sp,# 24*NBPW]
	stp x24,x25,[sp,# 26*NBPW]
	stp x26,x27,[sp,# 28*NBPW]
	stp x28,x29,[sp,# 30*NBPW]

	ldrh a5w,[p_in]
	sub a4,p_in,Probs; lsr a4,a4,#1
	mov a3w,Code
	mov a2w,Range
	mov a1w,mo
#if (DEBUG < 2)  //{
    and a1w,a1w,#1
#endif  //}
	adr a0,fmt
	ldr a6w,[a0,#-4]; add a6w,a6w,#1; str a6w,[a0,#-4]  // seq
	mov a7w,prevB

	str rep0,[sp,#-2*NBPW]!
	call printf
	add sp,sp,#2*NBPW

	ldp  x0, x1,[sp,#  2*NBPW]
	ldp  x2, x3,[sp,#  4*NBPW]
	ldp  x4, x5,[sp,#  6*NBPW]
	ldp  x6, x7,[sp,#  8*NBPW]
	ldp  x8, x9,[sp,# 10*NBPW]
	ldp x10,x11,[sp,# 12*NBPW]
	ldp x12,x13,[sp,# 14*NBPW]
	ldp x14,x15,[sp,# 16*NBPW]
	ldp x16,x17,[sp,# 18*NBPW]
	ldp x18,x19,[sp,# 20*NBPW]
	ldp x20,x21,[sp,# 22*NBPW]
	ldp x22,x23,[sp,# 24*NBPW]
	ldp x24,x25,[sp,# 26*NBPW]
	ldp x26,x27,[sp,# 28*NBPW]
	ldp x28,x29,[sp,# 30*NBPW]
	ldp  fp, lr,[sp],#32*NBPW
diagret:
	cmp mo,#0  // set CC
	ret

        .data
        .balign 4
seq:    .int 0
        .text

#endif  /*}*/
rcGBNorm:
	cmp inPtr,inLim
	lsl Range,Range,#8
	bhs lzmaDataError  // branch if Hi or Same
	ldrb t0,[inPtr],#1
	lsl Code,Code,#8
	orr Code,Code,t0
	b rcGB_10

#if 1==PARAMETER_STYLE  /*{*/
divwu_a7_r0:  // In: a7= dividend; r0= divisor; Out: a8= quo; a7= rem
	divwu a8,a7,r0
	mullw r0,a8,r0
	subf a7,r0,a7
	ret
#endif  /*}*/

rcNormalize:
	lsr t1,Range,#kNumTopBits
	cbz t1,rcNorm2
	ret
rcNorm2:
	lsl Range,Range,#8
rcInit2:
	cmp inLim,inPtr; beq lzmaDataError
	ldrb t0,[inPtr],#1
	lsl Code,Code,#8
	orr Code,Code,t0
	ret

rcGetBit_state:  # rcGetBit(0, state + p_in)
	mov mi,state
rcGetBit_mi0:  # rcGetBit(0, mi + p_in)
	add p_in,p_in,mix,lsl 1
rcGetBit_0:  # rcGetBit(0, p_in)
	mov mi,#0
rcGetBit_mi:  # rcGetBit(mi, mi + p_in)
	add p_in,p_in,mix,lsl 1
rcGetBit:  # mo= (*)(mi, probs); CC set on mo; uses t0,t1,t2
	ldrh starp,[p_in]  // likely cache miss
	        lsr t0,Range,#kNumTopBits
	cbz t0,rcGBNorm
rcGB_10:  // bound===t1, starp===t2
	lsr t0,Range,#kNumBitModelTotalBits  // 'mul' has no input shifter
	mul bound,starp,t0  // bound= *p_in * (Range >> kNumBitModelTotalBits)
	mov t0,#kBitModelTotal
	sub t0,t0,starp  // kBitModelTotal - *p_in
	cmp Code,bound
	bhs rcGetBit1
rcGetBit0:
	adcs mo,mi,mi  // shift-in Carry(0), set CC
	mov Range,bound
	add starp,starp,t0,lsr #kNumMoveBits  // *p_in + (...)>>kNumMoveBits
	strh starp,[p_in]
#if DEBUG  /*{*/
    b diagnose
#endif  /*}*/
	ret
rcGetBit1:
	adcs mo,mi,mi  // shift-in Carry(1), set CC
	sub Code ,Code, bound
	sub Range,Range,bound
	sub starp,starp,starp,lsr #kNumMoveBits  // *p_in - (*p_in >> kNumMoveBits)
	strh starp,[p_in]
#if DEBUG  /*{*/
    b diagnose
#endif  /*}*/
	ret

	.balign 32
L200:  # main loop
	sub r_nowPosx,outPtr,outBuf
	lsl mi,state,#kNumPosBitsMax
	and posState,r_nowPos,posStateMask
	add p_in,Probs,#(IsMatch<<1)
	add mi,mi,posState
	call rcGetBit_mi0; bne L270

	mov t1,#8; sub t1,t1,lc  // t1= 8 - lc
	and t0,r_nowPos,litPosMask  // last read of r_nowPos
	lsl t0,t0,lc
	lsr t1,prevB,t1  // last read of prevB
	add t1,t1,t0
	cmp state,#kNumLitStates
	add t0,t1,t1,lsl 1      // t0= t1 *3
	add prob,Probs,#(LZMA_BASE_SIZE<<1)
	mov symbol,#1
	add prob,prob,t0x,lsl (1+ 8)  // 768==LZMA_LIT_SIZE
	blt L240

	sub t1x,outPtr,rep0,uxtw
	ldrb matchB,[t1x]
L210:  // symbol === mi === mo
	lsl matchB,matchB,#1
	add p_in,prob,#(0x100<<1)
	and Bit,matchB,#0x100
	add p_in,p_in,Bitx,lsl 1
	call rcGetBit_mi
	and  t0,symbol,#1; lsr Bit,Bit,#8
	sub  t0,t0,Bit; cmp symbol,#0x100
	cbnz t0,L244;   blt L210
	b L245

	.balign 32
L240:  # symbol === mi === mo
	mov p_in,prob
	call rcGetBit_mi
L243:
	cmp symbol,#0x100
L244:
	blt L240
L245:
	strb symbol,[outPtr],#1
	sub prevB,symbol,#0x100

	cmp state,#4;  mov t0,state;  blt L249
	cmp state,#10; mov t0,#3;     blt L249
	               mov t0,#6
L249:
	sub state,state,t0  // state -= {state, 3, 6}
	b L520

L270:
	add p_in,Probs,#(IsRep<<1)
	call rcGetBit_state; bne L290

	cmp state,#kNumLitStates
	mov rep3,rep2
	mov rep2,rep1
	mov rep1,rep0
	add prob,Probs,#(LenCoder<<1)

	mov state,#0; blt L350
	mov state,#3; b   L350

L290:
	add p_in,Probs,#(IsRepG0<<1)
	call rcGetBit_state; bne L300
L293:
	lsl mi,state,#kNumPosBitsMax
	add mi,mi,posState
	add p_in,Probs,#(IsRep0Long<<1)
	call rcGetBit_mi0; bne L340
L295:
	cmp state,#kNumLitStates
	mov state,# 9; blt L297
	mov state,#11
L297:
	sub t1x,outPtr,rep0,uxtw
	ldrb prevB,[t1x]
	cmp outBuf,outPtr; beq lzmaDataError
	strb prevB,[outPtr],#1
	b L520
L300:
	add p_in,Probs,#(IsRepG1<<1)
	call rcGetBit_state; mov distance,rep1; beq L330
L310:
	add p_in,Probs,#(IsRepG2<<1)
	call rcGetBit_state; mov distance,rep2; beq L325
L320:
	mov distance,rep3
	mov rep3,rep2
L325:
	mov rep2,rep1
L330:
	mov rep1,rep0
	mov rep0,distance
L340:
	cmp state,#kNumLitStates
	mov state,#8;  blt L345
	mov state,#11
L345:
	add prob,Probs,#(RepLenCoder<<1)
L350:
	add p_in,prob,#(LenChoice<<1)
	call rcGetBit_0; bne L360

	lsl t1,posState,#(1+ kLenNumLowBits)
	add t1,t1,#(LenLow<<1)
	add probLen,prob,t1,uxtw
	mov offset,#0
	mov hiBit,#(1<<kLenNumLowBits)
	b L390
L360:
	add p_in,prob,#(LenChoice2<<1)
	call rcGetBit_0; bne L370

	lsl t1,posState,#(1+ kLenNumMidBits)
	add t1,t1,#(LenMid<<1)
	add probLen,prob,t1,uxtw
	mov offset,#kLenNumLowSymbols
	mov hiBit,#(1<<kLenNumMidBits)
	b L390
L370:
	add probLen,prob,#(LenHigh<<1)
	mov offset,#(kLenNumLowSymbols + kLenNumMidSymbols)
	mov hiBit,#(1<<kLenNumHighBits)
L390:
	mov mi,#1
1:  # RangeDecoderBitTreeDecode
	mov p_in,probLen
	call rcGetBit_mi; subs t0,mo,hiBit; blt 1b
	add len,t0,offset  // len === offset
L395:
	cmp state,#4; bge L500
	mov hiBit,#(1<<kNumPosSlotBits)
L400:
	cmp len,#kNumLenToPosStates
	add state,state,#kNumLitStates
	
	lsl t1,len,                      #(1+ kNumPosSlotBits); blt 0f
	mov t1,#((kNumLenToPosStates -1)<<(1+ kNumPosSlotBits))
0:
	add t1,t1,#(PosSlot<<1)
	mov mi,#1
	add probLit,Probs,t1,uxtw
1:  # RangeDecoderBitTreeDecode
	mov p_in,probLit
	call rcGetBit_mi; subs posSlot,mo,hiBit; blt 1b

	cmp posSlot,#kStartPosModelIndex; blt L460
L405:
	cmp posSlot,#kEndPosModelIndex
	lsr numDirectBits,posSlot,#1
	and rep0,posSlot,#1
	sub numDirectBits,numDirectBits,#1
	orr rep0,rep0,#2
	bge L410
L407:
	lsl rep0,rep0,numDirectBits
	sub t1,rep0,posSlot
	add t1,t1,#(SpecPos -1)
	add prob,Probs,t1x,lsl 1
	b L438
L410:
	sub numDirectBits,numDirectBits,#kNumAlignBits
L420:
	call rcNormalize
	lsr Range,Range,#1
	lsl rep0,rep0,#1
	cmp Code,Range; blo 0f
	orr rep0,rep0,#1
	sub Code,Code,Range
0:
	sub numDirectBits,numDirectBits,#1; cbnz numDirectBits,L420

	add prob,Probs,#(Align<<1)
	mov numDirectBits,#kNumAlignBits
	lsl rep0,rep0,#kNumAlignBits
L438:
	mov i,#1
	mov mi,#1
L440:
	mov p_in,prob
	call rcGetBit_mi
    tbz mo,#0,L445; orr rep0,rep0,i
L445:
	lsl i,i,#1
	sub numDirectBits,numDirectBits,#1; cbnz numDirectBits,L440

	b L465
L450:
L460:
	mov rep0,posSlot
L465:
	add rep0,rep0,#1; cbnz rep0,L470
	mov len,#kLzmaStreamWasFinishedId
	b L530
L470:
L500:
	sub t0x,outPtr,outBuf  // nowPos
	cmp rep0,t0; bgt lzmaDataError
	add len,len,#kMatchMinLen
L510:
	sub t1x,outPtr,rep0,uxtw
	ldrb prevB,[t1x]
	cmp outPtr,outLim; bhs L530  // destination is full
	strb prevB,[outPtr],#1
	sub len,len,#1; cbnz len,L510  // 'len' is dead after loop
L520:
	cmp outPtr,outLim; blo L200
L530:
	call rcNormalize
	mov w0,#0; b lzmaExit  // success

lzmaDataError:
	mov w0,#1  // failure

lzmaExit:
	ldr t0x,[sp,#inStream]
	ldr t1x,[sp,#inSizeProcessed]
	sub t0x,inPtr,t0x
	str t0,[t1x]

	ldr t0x,[sp,#outStream]
	ldr t1x,[sp,#outSizeProcessed]
	sub t0x,outPtr,t0x
	str t0,[t1x]

	ldp x19,x20,[sp,#  2*NBPW]
	ldp x21,x22,[sp,#  4*NBPW]
	ldp x23,x24,[sp,#  6*NBPW]
	ldp x25,x26,[sp,#  8*NBPW]
	ldp x27,x28,[sp,# 10*NBPW]
	ldp  fp, lr,[sp],#16*NBPW
	ret

    .unreq fp
