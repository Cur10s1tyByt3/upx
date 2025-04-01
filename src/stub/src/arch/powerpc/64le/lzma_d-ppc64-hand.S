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

// WARNING:  "addi rN,r0,constant" actually is "li rN,constant"
// THE ASSEMBLER DOES NOT TELL YOU.

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

#define v0 3
/* Subroutine arguments; not saved by callee */
#define a0 3
#define a1 4
#define a2 5
#define a3 6
#define a4 7
#define a5 8
#define a6 9
#define a7 10
#define a8 11
#define a9 12
#define a10 13

/* Scratch (temporary) registers; not saved by callee */
//#define t0  2
//#define t1 11
//#define t2 12
//#define t3 13

/* branch and link */
#define call bl

/* branch to link register */
#define ret  blr

#define mov mr

#define r0  0
#define sp  1  /* stack pointer */
#define r2  2
#define r3  3
#define r4  4
#define r5  5
#define r6  6
#define r7  7
#define r8  8
#define r9  9
#define r10 10
#define r11 11
#define r12 12
#define r13 13
#define r14 14
#define r15 15
#define r16 16
#define r17 17
#define r18 18
#define r19 19
#define r20 20
#define r21 21
#define r22 22
#define r23 23
#define r24 24
#define r25 25
#define r26 26
#define r27 27
#define r28 28
#define r29 29
#define r30 30
#define r31 31

#define t0  r0
//STACK     r1
//MODULE    r2
#define mi  a0  /* r3 */
#define p_in    a1
#define bit r5
#define i   r6
#define len r7

//#define AVAIL r8
//#define AVAIL r9
#define prevB   r10
#define t1  r11
#define t2  r12
//#define AVAIL r13
#define posState r14
#define state   r15

#define rep0    r16
#define rep1    r17
#define rep2    r18
#define rep3    r19
#define Range   r20
#define Code    r21
#define prob    r22
#define outBuf  r23

#define inPtr   r24
#define inLim   r25
#define outPtr  r26
#define outLim  r27
#define litPosMask    r28
#define posStateMask  r29
#define lc  r30
#define Probs   r31

#define mo  mi  /* mask out,  mask in */
#define symbol  mi
#define bound   t1
#define starp   t2
#define offset  len  /* forward to only use */

#define distance      bit  /* disjoint lifetimes */
#define numDirectBits bit  /* disjoint lifetimes */
#define hibit         bit  /* disjoint lifetimes */
#define r_nowPos      i
#define matchB        i    /* disjoint lifetimes */
#define probLen       i    /* disjoint lifetimes */
#define probLit       i    /* disjoint lifetimes */
#define posSlot   posState  /* disjoint lifetimes */

#define vs a0

NBPW= 8
SZ_SAVAREA= 6*NBPW  // (sp,cr,lr, xx,yy,zz) OUTGOING save area per calling convention

#if !defined(PARAMETER_STYLE)  /*{*/
  #define  PARAMETER_STYLE 3
//  Possible choices:
//  1  /*   0 bytes;  1-byte encoding of pb,lp,lc  [default] */
//  2  /* -20 bytes;  2-byte encoding requires no division */
//  3  /* -28 bytes;  separate bytes beginning at -4+ probs */
#endif  /*}*/

/* LzmaDecode(a0=vs, a1=inStream, a2=inSize, a3= &inSizeProcessed,
    a4= outStream, a5= outSize, a6= &outSizeProcessed)
*/
LzmaDecode: .globl LzmaDecode
  teq r0,r0
#if 3==PARAMETER_STYLE  /*{*/
vs_ps= 2
vs_lp= 1
vs_lc= 0
    lbz a7,vs_lc(vs)
    lbz a8,vs_lp(vs)
    lbz a9,vs_ps(vs)
    addi a0,vs,4
#undef vs
#endif  /*}*/

/* LzmaDecode_UPX(a0=probs, a1=inStream, a2=inSize, a3= &inSizeProcessed,
    a4=outStream, a5=outSize, a6=&outSizeProcessed,
    a7=lc, a8=lp, a9=ps)
*/
LzmaDecode_UPX:
    mflr r0; std r0,2*NBPW(sp)  // ret_addr: ppc64 convention
    stdu sp,-SZ_SAVAREA-32*NBPW(sp)  // allocate and chain the frame
    std  r2, 0*NBPW+SZ_SAVAREA(sp)  // save all registers
    std  r3, 1*NBPW+SZ_SAVAREA(sp)  // a0= vs
    std  r4, 2*NBPW+SZ_SAVAREA(sp)  // a1= inStream
    std  r5, 3*NBPW+SZ_SAVAREA(sp)  // a2= inSize
    std  r6, 4*NBPW+SZ_SAVAREA(sp)  // a3= &inSizeProcessed
    std  r7, 5*NBPW+SZ_SAVAREA(sp)  // a4= outStream
    std  r8, 6*NBPW+SZ_SAVAREA(sp)  // a5= outSize
    std  r9, 7*NBPW+SZ_SAVAREA(sp)  // a6= &outSizeProcessed
    std r10, 8*NBPW+SZ_SAVAREA(sp)  // a7= lc
    std r11, 9*NBPW+SZ_SAVAREA(sp)  // a8= lp
    std r12,10*NBPW+SZ_SAVAREA(sp)  // a9= ps
    std r13,11*NBPW+SZ_SAVAREA(sp)
    std r14,12*NBPW+SZ_SAVAREA(sp)
    std r15,13*NBPW+SZ_SAVAREA(sp)
    std r16,14*NBPW+SZ_SAVAREA(sp)
    std r17,15*NBPW+SZ_SAVAREA(sp)
    std r18,16*NBPW+SZ_SAVAREA(sp)
    std r19,17*NBPW+SZ_SAVAREA(sp)
    std r20,18*NBPW+SZ_SAVAREA(sp)
    std r21,19*NBPW+SZ_SAVAREA(sp)
    std r22,20*NBPW+SZ_SAVAREA(sp)
    std r23,21*NBPW+SZ_SAVAREA(sp)
    std r24,22*NBPW+SZ_SAVAREA(sp)
    std r25,23*NBPW+SZ_SAVAREA(sp)
    std r26,24*NBPW+SZ_SAVAREA(sp)
    std r27,25*NBPW+SZ_SAVAREA(sp)
    std r28,26*NBPW+SZ_SAVAREA(sp)
    std r29,27*NBPW+SZ_SAVAREA(sp)
    std r30,28*NBPW+SZ_SAVAREA(sp)
    std r31,29*NBPW+SZ_SAVAREA(sp)

        inStream= 2*NBPW+SZ_SAVAREA
       outStream= 5*NBPW+SZ_SAVAREA
 inSizeProcessed= 4*NBPW+SZ_SAVAREA
outSizeProcessed= 7*NBPW+SZ_SAVAREA


    mov Probs,a0
    add outLim,a5,a4  // outSize + outStream
    mov outPtr,a4
    add inLim,a2,a1  // inSize + inStream
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

    mov lc,a7
    li t0,~0
    slw posStateMask,t0,a9
    not posStateMask,posStateMask
    slw litPosMask,t0,a8
    not litPosMask,litPosMask

    add a10,a7,a8  // lc + lp
    li t0,LZMA_LIT_SIZE
    slw a10,t0,a10  // LZMA_LIT_SIZE << (lc + lp)
    addi a10,a10,LZMA_BASE_SIZE

    srwi t0,a10,1  // 2 at a time
    mtctr t0
    mov t1,Probs
    lis    t0,(kBitModelTotal>>1)
    ori t0,t0,(kBitModelTotal>>1)
L10:
    stw t0,0(t1); addi t1,t1,2*2  // 2 ushort
    bdnz L10

    li t0,5; mtctr t0
L20:
    call rcInit2; bdnz L20

    li Range,~0
    li prevB,0
    li state,0
    li rep0,1
    li rep1,1
    li rep2,1
    li rep3,1
    b L200

#if 1==PARAMETER_STYLE  /*{*/
divwu_a7_r0:  // In: a7= dividend; r0= divisor; Out: a8= quo; a7= rem
    divwu a8,a7,r0
    mullw r0,a8,r0
    subf a7,r0,a7
    ret
#endif  /*}*/

#if DEBUG  /*{*/
        .data; .balign 4
seq:    .int 0

        .text
fmt: .ascii "rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG) //{
    .ascii "  prevB=%2x  rep0=%x"
#endif  //}
    .asciz "\n"

        .balign 4
diagnose:
    mflr r0; std r0,2*NBPW(sp)  // ret_addr: ppc64 convention
    stdu sp,-SZ_SAVAREA-32*NBPW(sp)  // allocate and chain the frame
    mfctr t1  // count register is live
    //stmd r2,SZ_SAVAREA(sp)
    std  r2, 0*NBPW+SZ_SAVAREA(sp)
    std  r3, 1*NBPW+SZ_SAVAREA(sp)
    std  r4, 2*NBPW+SZ_SAVAREA(sp)
    std  r5, 3*NBPW+SZ_SAVAREA(sp)
    std  r6, 4*NBPW+SZ_SAVAREA(sp)
    std  r7, 5*NBPW+SZ_SAVAREA(sp)
    std  r8, 6*NBPW+SZ_SAVAREA(sp)
    std  r9, 7*NBPW+SZ_SAVAREA(sp)
    std r10, 8*NBPW+SZ_SAVAREA(sp)
    std r11, 9*NBPW+SZ_SAVAREA(sp)
    std r12,10*NBPW+SZ_SAVAREA(sp)
    std r13,11*NBPW+SZ_SAVAREA(sp)
    std r14,12*NBPW+SZ_SAVAREA(sp)
    std r15,13*NBPW+SZ_SAVAREA(sp)
    std r16,14*NBPW+SZ_SAVAREA(sp)
    std r17,15*NBPW+SZ_SAVAREA(sp)
    std r18,16*NBPW+SZ_SAVAREA(sp)
    std r19,17*NBPW+SZ_SAVAREA(sp)
    std r20,18*NBPW+SZ_SAVAREA(sp)
    std r21,19*NBPW+SZ_SAVAREA(sp)
    std r22,20*NBPW+SZ_SAVAREA(sp)
    std r23,21*NBPW+SZ_SAVAREA(sp)
    std r24,22*NBPW+SZ_SAVAREA(sp)
    std r25,23*NBPW+SZ_SAVAREA(sp)
    std r26,24*NBPW+SZ_SAVAREA(sp)
    std r27,25*NBPW+SZ_SAVAREA(sp)
    std r28,26*NBPW+SZ_SAVAREA(sp)
    std r29,27*NBPW+SZ_SAVAREA(sp)
    std r30,28*NBPW+SZ_SAVAREA(sp)
    std r31,29*NBPW+SZ_SAVAREA(sp)

    lhz a5,0(p_in)
    subf a4,Probs,p_in; srwi a4,a4,1
    mov a3,Code
    mov a2,Range
    mov a1,mo
#if (DEBUG < 2)  //{
    andi. a1,a1,1
#endif  //}
    lis a0,fmt@ha
    la  a0,fmt@l(a0)
    lwz a6,-4(a0); addi a6,a6,1; stw a6,-4(a0)  // seq
    mov a7,prevB
    mov a8,rep0
    call printf

    //lmw  r2,SZ_SAVAREA(sp)
    ld  r2, 0*NBPW + SZ_SAVAREA(sp)
    ld  r3, 1*NBPW + SZ_SAVAREA(sp)
    ld  r4, 2*NBPW + SZ_SAVAREA(sp)
    ld  r5, 3*NBPW + SZ_SAVAREA(sp)
    ld  r6, 4*NBPW + SZ_SAVAREA(sp)
    ld  r7, 5*NBPW + SZ_SAVAREA(sp)
    ld  r8, 6*NBPW + SZ_SAVAREA(sp)
    ld  r9, 7*NBPW + SZ_SAVAREA(sp)
    ld r10, 8*NBPW + SZ_SAVAREA(sp)
    ld r11, 9*NBPW + SZ_SAVAREA(sp)
    ld r12,10*NBPW + SZ_SAVAREA(sp)
    ld r13,11*NBPW + SZ_SAVAREA(sp)
    ld r14,12*NBPW + SZ_SAVAREA(sp)
    ld r15,13*NBPW + SZ_SAVAREA(sp)
    ld r16,14*NBPW + SZ_SAVAREA(sp)
    ld r17,15*NBPW + SZ_SAVAREA(sp)
    ld r18,16*NBPW + SZ_SAVAREA(sp)
    ld r19,17*NBPW + SZ_SAVAREA(sp)
    ld r20,18*NBPW + SZ_SAVAREA(sp)
    ld r21,19*NBPW + SZ_SAVAREA(sp)
    ld r22,20*NBPW + SZ_SAVAREA(sp)
    ld r23,21*NBPW + SZ_SAVAREA(sp)
    ld r24,22*NBPW + SZ_SAVAREA(sp)
    ld r25,23*NBPW + SZ_SAVAREA(sp)
    ld r26,24*NBPW + SZ_SAVAREA(sp)
    ld r27,25*NBPW + SZ_SAVAREA(sp)
    ld r28,26*NBPW + SZ_SAVAREA(sp)
    ld r29,27*NBPW + SZ_SAVAREA(sp)
    ld r30,28*NBPW + SZ_SAVAREA(sp)
    ld r31,29*NBPW + SZ_SAVAREA(sp)
    addi sp,sp,SZ_SAVAREA+32*NBPW
    ld  r0,    2*NBPW(sp)  // return address
    mtlr r0
    mtctr t1
diagret:
    cmpwi mo,0  // set CC
    ret

#endif  /*}*/
rcGBNorm:
    cmpl cr7,inLim,inPtr
        slwi Range,Range,8
    beq- cr7,lzmaDataError
    lbz t0,0(inPtr); addi inPtr,inPtr,1
    slwi Code,Code,8
    or Code,Code,t0
    b rcGB_10

rcNormalize:
    srwi. t1,Range,kNumTopBits
    bnelr cr0  // conditional return
rcNorm2:
    slwi Range,Range,8
rcInit2:
    cmpl cr0,inLim,inPtr; beq cr0,lzmaDataError
    lbz t0,0(inPtr); addi inPtr,inPtr,1
    slwi Code,Code,8
    or Code,Code,t0
    ret

rcGetBit_state:  # rcGetBit(0, state + p_in)
    mov mi,state
rcGetBit_mi0:  # rcGetBit(0, mi + p_in)
    slwi t0,mi,1
    add p_in,p_in,t0
rcGetBit_0:  # rcGetBit(0, p_in)
    li mi,0
rcGetBit_mi:  # rcGetBit(mi, mi + p_in)
    slwi t0,mi,1
    add p_in,p_in,t0
rcGetBit:  # mo= (*)(mi, probs); CC set on mo; uses t0,t1,t2
    lhz starp,0(p_in)  // likely cache miss
            srwi. t0,Range,kNumTopBits
        beq- cr0,rcGBNorm
rcGB_10:  // bound===t1, starp===t2
    srwi bound,Range,kNumBitModelTotalBits
        subfic t0,starp,kBitModelTotal  // speculate for rcGetBit0
    mullw bound,bound,starp  // bound= *p_in * (Range >> kNumBitModelTotalBits)
        add. mo,mi,mi  // set CC for low bit 0
        srwi t0,t0,kNumMoveBits  # (kBitModelTotal - *p_in)>>kNumMoveBits
    cmpl cr7,Code,bound
        add t0,t0,starp  // *p_in + ((kBitModelTotal - *p_in)>>kNumMoveBits)
    bge cr7,rcGetBit1
        mov Range,bound
    sth t0,0(p_in)
#if DEBUG  /*{*/
    b diagnose
#endif  /*}*/
    ret
rcGetBit1:
    srwi t0,starp,kNumMoveBits
    subf Code ,bound,Code   // Code  -= bound;
    subf t0,t0,starp  // *p_in - (*p_in >> kNumMoveBits)
    subf Range,bound,Range  // Range -= bound;
    addic. mo,mo,1  // set CC for low bit 1
    sth t0,0(p_in)
#if DEBUG  /*{*/
    b diagnose
#endif  /*}*/
    ret

    .balign 32
L200:  # main loop
    subf r_nowPos,outBuf,outPtr
    slwi mi,state,kNumPosBitsMax
    and posState,r_nowPos,posStateMask
    addi p_in,Probs,IsMatch<<1
    add mi,mi,posState
    call rcGetBit_mi0; bne cr0,L270

    and t0,r_nowPos,litPosMask  # last read of r_nowPos
    subfic t1,lc,8
    slw t0,t0,lc
    srw t1,prevB,t1  # last read of prevB
    add t1,t1,t0
    cmpli cr0,state,kNumLitStates
    slwi t0,t1,1    # t0= t1 *2
    li symbol,1
    add t0,t0,t1      # t0= t1 *3
    addi prob,Probs,LZMA_BASE_SIZE<<1
    slwi t1,t0,1+ 8  # t1= t1 *768 *2;  768==LZMA_LIT_SIZE
    add prob,prob,t1
    blt cr0,L240

    sub t1,outPtr,rep0
    lbz matchB,0(t1)
L210:  # symbol === mi === mo
    slwi matchB,matchB,1
    addi p_in,prob,0x100<<1
    andi. bit,matchB,0x100
    slwi t0,bit,1
    add p_in,p_in,t0
    call rcGetBit_mi
    andi. t0,symbol,1; srwi bit,bit,8
    cmpl cr7,t0,bit; cmpli cr0,symbol,0x100
    bne  cr7,L244;   blt   cr0,L210
    b L245

    .balign 32
L240:  # symbol === mi === mo
    mov p_in,prob
    call rcGetBit_mi
L243:
    cmpli cr0,symbol,0x100
L244:
    blt L240
L245:
    cmpli cr0,state,4; stb symbol,0(outPtr); addi outPtr,outPtr,1
    cmpli cr7,state,10; addi prevB,symbol,-0x100

    mov t0,state;  blt cr0,L249
    li  t0,3;      blt cr7,L249
    li  t0,6
L249:
    subf state,t0,state  // state -= {state, 3, 6}
    b L520

L270:
    addi p_in,Probs,IsRep<<1
    call rcGetBit_state; bne cr0,L290

    cmpli cr0,state,kNumLitStates
    mov rep3,rep2
    mov rep2,rep1
    mov rep1,rep0
    addi prob,Probs,LenCoder<<1

    li state,0; blt cr0,L350
    li state,3; b L350

L290:
    addi p_in,Probs,IsRepG0<<1
    call rcGetBit_state; bne cr0,L300
L293:
    slwi mi,state,kNumPosBitsMax
    add mi,mi,posState
    addi p_in,Probs,IsRep0Long<<1
    call rcGetBit_mi0; bne cr0,L340
L295:
    cmpli cr0,state,kNumLitStates
    li state, 9; blt cr0,L297
    li state,11
L297:
    cmpl cr0,outBuf,outPtr; beq lzmaDataError
    subf t1,rep0,outPtr
    lbz prevB,0(t1)
    stb prevB,0(outPtr); addi outPtr,outPtr,1
    b L520
L300:
    addi p_in,Probs,IsRepG1<<1
    call rcGetBit_state; mov distance,rep1; beq cr0,L330
L310:
    addi p_in,Probs,IsRepG2<<1
    call rcGetBit_state; mov distance,rep2; beq cr0,L325
L320:
    mov distance,rep3
    mov rep3,rep2
L325:
    mov rep2,rep1
L330:
    mov rep1,rep0
    mov rep0,distance
L340:
    cmpli cr0,state,kNumLitStates
    li state,8;  blt cr0,L345
    li state,11
L345:
    addi prob,Probs,RepLenCoder<<1
L350:
    addi p_in,prob,LenChoice<<1
    call rcGetBit_0; bne cr0,L360

    slwi t1,posState,1+ kLenNumLowBits
    addi t1,t1,LenLow<<1
    add probLen,t1,prob
    li offset,0
    li hibit,1<<kLenNumLowBits
    b L390
L360:
    addi p_in,prob,LenChoice2<<1
    call rcGetBit_0; bne cr0,L370

    slwi t1,posState,1+ kLenNumMidBits
    addi t1,t1,LenMid<<1
    add probLen,t1,prob
    li offset,kLenNumLowSymbols
    li hibit,1<<kLenNumMidBits
    b L390
L370:
    addi probLen,prob,LenHigh<<1
    li offset,kLenNumLowSymbols + kLenNumMidSymbols
    li hibit,1<<kLenNumHighBits
L390:
    li mi,1
1:  # RangeDecoderBitTreeDecode
    mov p_in,probLen
    call rcGetBit_mi; subf. t0,hibit,mo; blt cr0,1b
    add len,t0,offset  # len === offset
L395:
    cmpli cr0,state,4; bge L500
    li hibit,1<<kNumPosSlotBits
L400:
    cmpli cr0,len,kNumLenToPosStates
    addi state,state,kNumLitStates

    slwi t1,len,                      1+ kNumPosSlotBits; blt cr0,0f
    li   t1,(kNumLenToPosStates -1)<<(1+ kNumPosSlotBits)
0:
    addi t1,t1,PosSlot<<1
    li mi,1
    add probLit,Probs,t1
1:  # RangeDecoderBitTreeDecode
    mov p_in,probLit
    call rcGetBit_mi; subf. posSlot,hibit,mo; blt cr0,1b

    cmpli cr0,posSlot,kStartPosModelIndex; blt L460
L405:
    cmpli cr7,posSlot,kEndPosModelIndex
    srwi numDirectBits,posSlot,1
    andi. rep0,posSlot,1  // cr0; ignored
    addi numDirectBits,numDirectBits,-1
    ori rep0,rep0,2
    bge cr7,L410
L407:
    slw rep0,rep0,numDirectBits
    subf t1,posSlot,rep0
    addi t1,t1,SpecPos -1
    slwi t1,t1,1
    add prob,t1,Probs
    b L438
L410:
    addi numDirectBits,numDirectBits,-kNumAlignBits
    mtctr numDirectBits
L420:
    call rcNormalize
    srwi Range,Range,1
    subfc t0,Range,Code;  cmpl cr0,Code,Range
     adde rep0,rep0,rep0; blt  cr0,0f; mov Code,t0
0:
    bdnz L420

    addi prob,Probs,Align<<1
    li numDirectBits,kNumAlignBits
    slwi rep0,rep0,kNumAlignBits
L438:
    mtctr numDirectBits
    li i,1
    li mi,1
L440:
    mov p_in,prob
    call rcGetBit_mi
    andi. t0,mo,1; beq cr0,L445; or rep0,rep0,i
L445:
    slwi i,i,1
    bdnz L440

    b L465
L450:
L460:
    mov rep0,posSlot
L465:
    addic. rep0,rep0,1; bne cr0,L470
    li len,kLzmaStreamWasFinishedId
    b L530
L470:
L500:
    subf t0,outBuf,outPtr  # nowPos
    cmpl cr0,rep0,t0; bgt cr0,lzmaDataError
    addi len,len,kMatchMinLen
    mtctr len
L510:
    subf t1,rep0,outPtr
    lbz prevB,0(t1)
        addi outPtr,outPtr,1
        cmpl cr0,outPtr,outLim
    stb prevB,-1(outPtr)
        bge- cr0,L530  // destination is full
    bdnz L510  // 'len' is dead after loop
L520:
    cmpl cr0,outPtr,outLim; blt cr0,L200
L530:
    call rcNormalize
    li v0,0; b lzmaExit  # success
lzmaDataError:
    li v0,1  # failure
lzmaExit:
  teq r0,r0
    ld t0,inStream(sp)
    ld t1,inSizeProcessed(sp)
    subf t0,t0,inPtr
    stw t0,0(t1)

    ld t0,outStream(sp)
    ld t1,outSizeProcessed(sp)
    subf t0,t0,outPtr
    stw t0,0(t1)

    ld  r2, 0*NBPW + SZ_SAVAREA(sp)
    //ld  r3, 1*NBPW + SZ_SAVAREA(sp)  v0 return value
    ld  r4, 2*NBPW + SZ_SAVAREA(sp)
    ld  r5, 3*NBPW + SZ_SAVAREA(sp)
    ld  r6, 4*NBPW + SZ_SAVAREA(sp)
    ld  r7, 5*NBPW + SZ_SAVAREA(sp)
    ld  r8, 6*NBPW + SZ_SAVAREA(sp)
    ld  r9, 7*NBPW + SZ_SAVAREA(sp)
    ld r10, 8*NBPW + SZ_SAVAREA(sp)
    ld r11, 9*NBPW + SZ_SAVAREA(sp)
    ld r12,10*NBPW + SZ_SAVAREA(sp)
    ld r13,11*NBPW + SZ_SAVAREA(sp)
    ld r14,12*NBPW + SZ_SAVAREA(sp)
    ld r15,13*NBPW + SZ_SAVAREA(sp)
    ld r16,14*NBPW + SZ_SAVAREA(sp)
    ld r17,15*NBPW + SZ_SAVAREA(sp)
    ld r18,16*NBPW + SZ_SAVAREA(sp)
    ld r19,17*NBPW + SZ_SAVAREA(sp)
    ld r20,18*NBPW + SZ_SAVAREA(sp)
    ld r21,19*NBPW + SZ_SAVAREA(sp)
    ld r22,20*NBPW + SZ_SAVAREA(sp)
    ld r23,21*NBPW + SZ_SAVAREA(sp)
    ld r24,22*NBPW + SZ_SAVAREA(sp)
    ld r25,23*NBPW + SZ_SAVAREA(sp)
    ld r26,24*NBPW + SZ_SAVAREA(sp)
    ld r27,25*NBPW + SZ_SAVAREA(sp)
    ld r28,26*NBPW + SZ_SAVAREA(sp)
    ld r29,27*NBPW + SZ_SAVAREA(sp)
    ld r30,28*NBPW + SZ_SAVAREA(sp)
    ld r31,29*NBPW + SZ_SAVAREA(sp)
    addi sp,sp,SZ_SAVAREA+32*NBPW
    ld  r0,    2*NBPW(sp)  // return address
    mtlr r0
#if !defined(LZMA_FALL_THROUGH) || !LZMA_FALL_THROUGH  //{
    ret
#endif  //}

