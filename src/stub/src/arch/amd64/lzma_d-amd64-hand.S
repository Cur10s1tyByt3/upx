// Hand compiled Copyright (c) 2006-2007 John F. Reiser  (2007-06-18)
// from modified LzmaDecode.c.
// LZMA SDK 4.40 Copyright (c) 1999-2006 Igor Pavlov (2006-05-01)
//
// This file is licensed under either of these two licenses:
//   1) GNU Lesser General Public License (GNU LGPL)
//   2) Common Public License (CPL)
// See files LGPL.txt and CPL.html for the text of the licenses.

#ifndef DEBUG  //{
#define DEBUG 0
#endif  //}
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
kNumLenProbs= LenHigh + kLenNumHighSymbols

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
Literal=  (RepLenCoder + kNumLenProbs)

LZMA_BASE_SIZE= Literal  // 1846
LZMA_LIT_SIZE =  768

#define symbol_b %al
#define symbol  mi
#define mo  mi
#define mo_b    %al
#define t0b %cl
#define t0w %cx
#define t0q %rcx
#define t1w %dx

#define mi  %eax
#define t0  %ecx
#define t1  %edx
#define Range   %ebx

#define bit %esi
#define i   %edi

#define Code    %r8d
#define state   %r9d
#define posState %r10d
#define p_in    %r11

#define  inPtr  %r12
#define outPtr  %r13
#define prob    %r14
#define Probs   %r15

#define miQ %rax
#define moQ %rax
#define CodeB   %r8b
#define stateQ  %r9
#define p_inL   %r11d
#define  inPtrL %r12d
#define outPtrL %r13d

#define distance    bit
#define numDirectBits   bit
#define hibit       bit
#define matchB      i
#define matchBQ     %rdi
#define probLen     %rdi
#define probLit     %rdi

#define posSlot     posState

#define LOADCON(v,r) mov $v,r
#define LOADCON1(r)  mov $1,r

#define vs %rdi

/* LzmaDecode(%rdi=vs, %rsi=inStream, %rdx=inSize, %rcx= &inSizeProcessed,
    %r8= outStream, %r9= outSize, 8(%rsp)= &outSizeProcessed)
*/
    .balign 16
//LzmaDecode: .globl LzmaDecode
    push %r15; push %r14; push %r13; push %r12  # caller registers
    push %rbx
    push %rbp; mov %rsp,%rbp
#define outSizeProcessed 7*NBPW(%rbp)

    push %r8  # outStream
#define outBuf -1*NBPW(%rbp)
    add %r8,%r9; push %r9  # outLim
#define outLim -2*NBPW(%rbp)
    mov %r8,outPtr

    push %rcx  # inSizeProcessed
#define inSizeProcessed -3*NBPW(%rbp)
    push %rsi  # inStream
#define inBuf -4*NBPW(%rbp)
    add %rsi,%rdx; push %rdx  # inLim
#define inLim -5*NBPW(%rbp)

#define lc            -1*4 -5*NBPW(%rbp)
#define posStateMask  -2*4 -5*NBPW(%rbp)
#define litPosMask    -3*4 -5*NBPW(%rbp)
#define rep3          -4*4 -5*NBPW(%rbp)
#define rep2          -5*4 -5*NBPW(%rbp)
#define rep1          -6*4 -5*NBPW(%rbp)
#define rep0Q         -8*4 -5*NBPW(%rbp)
#define rep0          -8*4 -5*NBPW(%rbp)
#define m_len         -9*4 -5*NBPW(%rbp)
#define prevB        -10*4 -5*NBPW(%rbp)
    lea          -10*4 -5*NBPW(%rbp),%rsp  # 0 mod 16

#if !defined(PARAMETER_STYLE)  /*{*/
  #define  PARAMETER_STYLE 3
//  Possible choices:
//  1  /*   0 bytes;  1-byte encoding of pb,lp,lc  [default] */
//  2  /*  -8 bytes;  2-byte encoding requires no division */
//  3  /* -13 bytes;  separate bytes beginning at -4+ probs */
#endif  /*}*/

    cld

// -1*NBPW(%rsp) is for pc when calling rcGetBit
// -2*NBPW(%rsp) is for saving one register in rcGetBit

#if 1==PARAMETER_STYLE  /*{ [0]: pb*45 + lp*9 + lc */
    lodsb; mov $0,%ah  # pb*45 + lp*9 + lc
    mov $45,%cl; div %cl; xchg %eax,%ecx  # %ch= rem; %cl= pb
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,posStateMask
    mov %ch,%al; mov $0,%ah  # lp*9 + lc
    mov $9,%cl; div %cl; xchg %eax,%ecx  # %ch= lc; %cl=lp
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,litPosMask
    mov %rsi,inPtr
    mov %ch,%al; /*mov $8,%ah; sub %al,%ah;*/ mov %eax,lc  # lc in lo byte
    mov %rdi,p
    add %al,%cl  # lc + lp  ready for shift
#endif  /*}*/

#if 2==PARAMETER_STYLE  /*{ [0]: ((lc + lp)<<3) | pb;  [1]: (lp<<4) | lc */
    lodsb; mov $7,%cl; and %al,%cl  # pb
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,posStateMask
    lodsb; mov %al,%cl; shr $4,%cl  # lp
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,litPosMask
    mov %rsi,inPtr
    and $0xf,%al; /*mov $8,%ah; sub %al,%ah;*/ mov %eax,lc  // lc in lo byte
    mov %rdi,p
    add %al,%cl  # lc + lp  ready for shift
#endif  /*}*/

#if 3==PARAMETER_STYLE  /*{  lc,lp,pb,xx  in separate bytes before probs[] */
vs_ps= 2
vs_lp= 1
vs_lc= 0
    mov %rsi,inPtr
    mov /*vs_lc*/(%rdi),%eax; lea 4(%rdi),Probs  # %al= lc; %ah= lp;

    movb vs_ps(%rdi),%cl   # %cl=ps;
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,posStateMask
    movb %ah,%cl  # lp
    or $~0,%edx; shl %cl,%edx; not %edx; mov %edx,litPosMask
    add %al,%cl  # lc + lp
    /*mov $8,%ah; sub %al,%ah;*/ mov %eax,lc  # lo byte
#endif  /*}*/

    LOADCON1(%eax)
    mov %eax,rep3
    mov %eax,rep2
    mov %eax,rep1
    movq %rax,rep0Q

    sub state,state  # 0
    mov state,prevB  # 0
    or $~0,Range

    addb %dl,%cl; mov $LZMA_LIT_SIZE,%eax; shl %cl,%eax
    lea LZMA_BASE_SIZE(%rax),%rcx
    mov $((kBitModelTotal>>1)<<16)|(kBitModelTotal>>1),%eax
    mov Probs,%rdi; shr %ecx; rep; stosl

    LOADCON(5,%edi)
L20:
    call rcLoad
    dec %edi; jne L20
    jmp L200

#if DEBUG  //{
fmt: .ascii "rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG) //{
    .ascii "  prevB=%2x  rep0=%x"
#endif  //}
    .asciz "\n"
diagnose:
    push %r11; push %r10; push %r9; push %r8
    push %rdi; push %rsi; push %rcx; push %rdx; push %rax
    mov rep0,%ecx; push %rcx  # last param
    movl prevB,%ecx; push %rcx
    mov seq(%rip),%ecx; inc %ecx; mov %ecx,seq(%rip); push %rcx
    lea fmt(%rip),%rdi
    mov mi,%esi
#if (DEBUG < 2)  //{
    and $1,%esi
#endif  //}
    mov Range,%edx
    mov Code,%ecx
    mov p_in,%r8; sub Probs,%r8; shr %r8
    movzwl (p_in),%r9d
    call printf
    add $3*NBPW,%rsp  # toss 4 push
    pop %rax; pop %rdx; pop %rcx; pop %rsi; pop %rdi
    pop %r8; pop %r9; pop %r10; pop %r11
    test mo,mo  # set CC
diagret:
    ret

    .data
seq:    .int 0
#endif  //}

rcNormalize:
    cmpl $1<<kNumTopBits,Range; jb 0f
    ret
0:
    shl $8,Range
rcLoad:
    shl $8,Code; movzbl (inPtr),t0
    cmp inLim,inPtr; jae rcDataError1
    or t0,Code; inc inPtr
    ret

    .balign 16
rcGetBit_0:  // rcGetBit(0, p_in)
    sub mi,mi
rcGetBit_mi:  // rcGetBit(mi, mi + p_in)
    lea (p_in,miQ,2),p_in
/*rcGetBit:*/  // In: mi, p_in;  Out: mo, CC set, %rbp as frame
    movzwl (p_in),t1  # expect L1 datacache miss
                mov Range,t0

    cmp $1<<kNumTopBits,Range; jae 1f  # inline rcNormalize
    shl $8,Code; movzbl (inPtr),t0
    cmp inLim,inPtr; jae rcDataError2
    shl $8,Range; inc inPtr
    or t0,Code; mov Range,t0
1:
    shrl $kNumBitModelTotalBits,t0  # Range >> kNumBitModelTotalBits
    imull t1,t0  # t0= bound= (*p) * (Range >> kNumBitModelTotalBits)
    cmp t0,Code; jae rcGetBit1

rcGetBit0:
    mov t0,Range  # Range= bound;
    mov $1<<kNumBitModelTotalBits,t0
    sub t1,t0
    shr $kNumMoveBits,t0
    addw t0w,(p_in)  # *p + ((kBitModelTotal - *p) >> kNumMoveBits)
    add mo,mo  # (Code>=bound) + (mi<<1)  set CC
#if DEBUG  //{
    jmp diagnose
#else  //}{
    ret
#endif  //}

rcGetBit1:
    sub t0,Range  # Range -= bound;
    shr $kNumMoveBits,t1
    sub t0,Code   # Code  -= bound;
    subw t1w,(p_in)  # *p - (*p >> kNumMoveBits)
    add mo,mo
    add $1,mo  # (Code>=bound) + (mi<<1)  set CC
#if DEBUG  //{
    jmp diagnose
#else  //}{
    ret
#endif  //}

L200:  // main loop
#define nowPosQ     %rdi  /* temporary only */
#define nowPos      %edi  /* temporary only */
    mov outPtrL,nowPos
            mov state,mi
    sub outBuf,nowPos
            shl $kNumPosBitsMax,mi
    mov nowPos,     posState
    and posStateMask,posState
            add posState,mi
    lea /*(IsMatch<<1)*/ (Probs,miQ,2),p_in  # 0==IsMatch
    call rcGetBit_0; jne L270

                                       mov prevB,t1  # t0 is %ecx
    mov lc,%cl; and litPosMask,nowPos; shl %cl,nowPos
    sub $8,%cl; neg %cl;               shr %cl,t1
    add t1,nowPos
            LOADCON1(symbol)
    lea (nowPosQ,nowPosQ,2),nowPosQ  # *3
            mov $0x100,bit
    shl $8,nowPos  # *256;  768==LZMA_LIT_SIZE
            cmp $kNumLitStates,state
    lea (Literal<<1)(Probs,nowPosQ,2),prob
            jb L240
#undef nowPos
#undef nowPosQ

/*L205:*/
    mov outPtr,matchBQ
    sub rep0Q,matchBQ
    movzbl (matchBQ),matchB
L210:  // symbol === mi === mo;  0x100==bit
    shl matchB
    mov bit,p_inL
    and matchB,bit  # bit = (matchByte & 0x100);
    add bit,p_inL; lea (prob,p_in,2),p_in
    call rcGetBit_mi
    mov symbol,t0;  shr $8,bit
    and     $1,t0;  cmp t0,bit
    mov $0x100,bit; jne L243  # break
    cmp symbol,bit; ja L210
    jmp L245

L240:  // symbol === mi === mo;  0x100==bit
    mov prob,p_in
    call rcGetBit_mi
L243:
    cmp bit,symbol; jb L240
L245:
    mov outPtr,%rdi
    stosb  # %al remains live

#if 1  /*{*/
    mov state,t0;  cmp $4, state; jb 0f
    LOADCON(3,t0); cmp $10,state; jb 0f
    add  $6-3,t0
0:
#else  /*}{ no branches; but slower because less parallelism? */
    cmp $10,state;     sbb  t0,t0  # -1 or 0
                       and $-3,t0  # -3 or 0
                       add $ 6,t0  #  3 or 6
    cmp  $4,state; cmovb state,t0
#endif  /*}*/
    sub t0,state
    jmp L519

L270:
    lea (IsRep<<1)(Probs,stateQ,2),p_in
    call rcGetBit_0; jne L290

#if 1  /*{*/
    mov rep2,mi
        cmp $kNumLitStates,state
    mov mi,rep3
        sbb mi,mi  # -1 or  0
    mov rep1,t1
        not mi     #  0 or -1
    mov rep0,t0
        and $3,mi  #  0 or  3
    mov t1,rep2
        mov mi,state
    mov t0,rep1

#else  /*}{*/
    mov rep2,t0
    mov rep1,t1
    mov rep0,mi
    mov t0,rep3
    mov t1,rep2
    mov mi,rep1

    sub t0,t0; cmp $kNumLitStates,state; jb 0f
    add $3,t0
0:
    mov t0,state
#endif  /*}*/

    lea (LenCoder<<1)(Probs),prob
    jmp L350

L290:
    lea (IsRepG0<<1)(Probs,stateQ,2),p_in
    call rcGetBit_0; jne L300
L293:
    mov state,mi
    shl $kNumPosBitsMax,mi
    add posState,mi
    lea (IsRep0Long<<1)(Probs,miQ,2),p_in
    call rcGetBit_0; jne L340
L295:
    cmp $kNumLitStates,state
    LOADCON(9,t0); jb 0f
    add $11-9,t0
0:
    mov t0,state
L297:
    mov outPtr,%rdi
    sub  rep0Q,%rdi
    cmp outBuf,%rdi; jb lzmaDataError
        movb (%rdi),symbol_b
    add  rep0Q,%rdi
        stosb
    jmp L519
L300:
    lea (IsRepG1<<1)(Probs,stateQ,2),p_in
    call rcGetBit_0; mov rep1,distance; je L330
L310:
    lea (IsRepG2<<1)(Probs,stateQ,2),p_in
    call rcGetBit_0; mov rep2,distance; je L325
L320:
    mov rep2,t0; mov rep3,distance
    mov t0,rep3
L325:
    mov rep1,t0
    mov t0,rep2
L330:
    mov rep0,t0; mov t0,rep1
    mov distance,rep0
L340:
    cmp $kNumLitStates,state
    LOADCON(8,t0); jb 0f
    add $11-8,t0
0:
    mov t0,state

    lea (RepLenCoder<<1)(Probs),prob
L350:
    mov prob,p_in
    // add $LenChoice<<1,p_in  //0==LenChoice
    call rcGetBit_0; jne L360
    mov posState,mi
        sub t0,t0
    shl $kLenNumLowBits,mi
        LOADCON(1<<kLenNumLowBits,hibit)
    lea (LenLow<<1)(prob,miQ,2),probLen
    jmp L390
L360:
    lea (LenChoice2<<1)(prob),p_in
    call rcGetBit_0; jne L370
    mov posState,mi
        LOADCON(kLenNumLowSymbols,t0)
    shl $kLenNumMidBits,mi
        LOADCON(1<<kLenNumMidBits,hibit)
    lea (LenMid<<1)(prob,miQ,2),probLen
    jmp L390
L370:
    lea (LenHigh<<1)(prob),probLen
    LOADCON(kLenNumLowSymbols + kLenNumMidSymbols,t0)
    mov $1<<kLenNumHighBits,hibit
L390:
    mov t0,m_len
    LOADCON1(mi)
L395:  // RangeDecoderBitTreeDecode
    mov probLen,p_in
    call rcGetBit_mi; mov mo,t1; sub hibit,t1; jb L395
    add m_len,t1; cmp $4,state
    mov t1,m_len; jae L500
/*L400:*/
    add $kNumLitStates,state

    LOADCON(kNumLenToPosStates -1,t0)
#if 1  /*{*/
    cmp t1,t0; jb 0f
    mov t1,t0
0:
#else  /*}{*/
    cmp    t1,t0
    cmovae t1,t0
#endif  /*}*/
    shl $kNumPosSlotBits,t0
        LOADCON1(mi)
    lea (PosSlot<<1)(Probs,t0q,2),probLit
        LOADCON(1<<kNumPosSlotBits,hibit)
L403:  // RangeDecoderBitTreeDecode
    mov probLit,p_in
    call rcGetBit_mi; mov mo,posSlot; sub hibit,posSlot; jb L403

    cmp $kStartPosModelIndex,posSlot; jb L460
L405:
    mov posSlot,numDirectBits
        mov posSlot,rep0
    shr numDirectBits
        andl $1,rep0
    dec numDirectBits
        orl  $2,rep0
    cmp $kEndPosModelIndex,posSlot; jae L410
L407:
    mov numDirectBits,%ecx; shll %cl,rep0
    mov rep0,mi
    sub posSlot,mi
    lea ((SpecPos-1)<<1)(Probs,miQ,2),prob
    jmp L438

L410:
    sub $kNumAlignBits,numDirectBits
L420:
    call rcNormalize
    shr Range
    shll rep0
    cmp Range,Code; jb L430
    incl rep0
    sub Range,Code  // if (Code>=Range) Code-=Range;
L430:
    dec numDirectBits; jne L420
    lea (Align<<1)(Probs),prob
    shll $kNumAlignBits,rep0
    LOADCON(kNumAlignBits,numDirectBits)
L438:
    LOADCON1(i)
    mov i,mi
L440:
    mov prob,p_in
    call rcGetBit_mi
    testb $1,mo_b; je L445; or i,rep0
L445:
    shl i
    dec numDirectBits; jne L440
    jmp L465
L450:
L460:
    mov posSlot,rep0
L465:
    incl rep0
#if 0  /*{ only for the stream version */
    jne L470; mov $kLzmaStreamWasFinishedId,m_len
    jmp L530
L470:
#endif  /*}*/
L500:
#define lim %rdx
#define dst %rdi
#define src %rsi
#define cnt %ecx
    mov outPtr,dst; mov m_len,cnt
    mov dst,%rax;   add $kMatchMinLen,cnt
    sub outBuf,%rax; cmp %rax,rep0Q; ja lzmaDataError
    mov dst,src; sub rep0Q,src
    mov outLim,lim
L510:
    lodsb; stosb
    cmp lim,dst; jae L515
    dec cnt; jne L510
L515:
L519:  // common tail for prevB and outPtr
    mov dst,outPtr
    movb %al,prevB
/*L520:*/  // bottom of while loop
    cmp outLim,outPtr; jb L200
L530:
    call rcNormalize
    sub %eax,%eax; jmp lzmaExit  // success

rcDataError2:
    nop
rcDataError1:
    nop
lzmaDataError:
    LOADCON1(%eax)  // 1; failure
lzmaExit:
    mov inSizeProcessed,%rdx
    sub inBuf,inPtr; mov inPtrL,(%rdx)

    mov outSizeProcessed,%rdx
    sub outBuf,outPtr; mov outPtrL,(%rdx)

    mov %rbp,%rsp
    pop %rbp; pop %rbx
    pop %r12; pop %r13; pop %r14; pop %r15
#if !defined(LZMA_FALL_THROUGH) || !LZMA_FALL_THROUGH  //{
    ret
#endif //}


