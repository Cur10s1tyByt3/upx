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

NBPW= 4

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

#define mi  %eax
#define mo  mi
#define moB %al

#define t0  %ecx
#define t0w %cx
#define t0b %cl

#define t1  %edx
#define t1w %dx
#define Range   %ebx

#define p_in    %ebp
#define bit %esi
#define i   %edi

#define distance    bit
#define numDirectBits   bit
#define hibit       bit
#define matchB      i
#define probLen     %edi  /* i */
#define probLit     %edi  /* i */

#define posSlot     posState
#define posSlotF    posStateF

#define r_posSlot   t0

vs_ps= 2
vs_lp= 1
vs_lc= 0

#define LOADCON(v,r) mov $v,r
#define LOADCON1(r)  mov $1,r

#if !defined(PARAMETER_STYLE)  /*{*/
  #define  PARAMETER_STYLE 3
//  Possible choices:
//  1  /*   0 bytes;  1-byte encoding of pb,lp,lc */
//  2  /*  -8 bytes;  2-byte encoding requires no division */
//  3  /* -13 bytes;  separate bytes beginning at -4+ probs */
#endif  /*}*/

/* LzmaDecode(2=vs, 3=inStream, 4=inSize, 5= &inSizeProcessed,
    6= outStream, 7= outSize, 8= &outSizeProcessed)
*/
    .balign 16
LzmaDecode: .globl LzmaDecode
    push %edi; push %esi; push %ebx
    push %ebp; mov %esp,%ebp
#define vs      4*5(%ebp)
#define inStream    4*6(%ebp)
#define inSize      4*7(%ebp)
#define inSizeProcessed 4*8(%ebp)
#define outStream   4*9(%ebp)
#define outSize     4*10(%ebp)
#define outSizeProcessed 4*11(%ebp)

#define  inBuf   inStream
#define  inLim   frame+4*7(%esp)
#define  inLimF        4*7(%ebp)
#define outBuf  outStream
#define outLim   frame+4*10(%esp)
#define outLimF        4*10(%ebp)
#define outBufS  frame+4* 9(%esp)
#define outBufF        4* 9(%ebp)

frame= 16*NBPW
    mov outStream,%eax; addl %eax,outSize; push %eax  # ouPtr
//#define outPtr    frame-4*1(%esp)
#define outPtrF      -4*1(%ebp)
    push $0  # prevB
#define prevB   frame-4*2(%esp)
#define prevBF       -4*2(%ebp)

    cld
#if 1==PARAMETER_STYLE  /*{ [0]: pb*45 + lp*9 + lc */
    mov  inStream,%esi; addl %esi, inSize
    lodsb; mov $0,%ah  # pb*45 + lp*9 + lc
    mov $45,%cl; div %cl; xchg %eax,%ecx  # %ch= rem; %cl= pb
    or $~0,%edx; shl %cl,%edx; not %edx; push %edx
#define posStateMask    frame-4*3(%esp)
#define posStateMaskF        -4*3(%ebp)
    mov %ch,%al; mov $0,%ah  # lp*9 + lc
    mov $9,%cl; div %cl; xchg %eax,%ecx  # %ch= lc; %cl=lp
    or $~0,%edx; shl %cl,%edx; not %edx; push %edx
#define litPosMask  frame-4*NBPW(%esp)
#define litPosMaskF      -4*NBPW(%ebp)
    mov %ch,%al; push %eax  # lc in lo byte
#define lc      frame-4*5(%esp)
#define lcF          -4*5(%ebp)
    push %esi  # inPtr
#define inPtr   frame-4*6(%esp)
#define inPtrF       -4*6(%ebp)
    add %al,%cl  # lc + lp  ready for shift
    mov vs,%edi  # Probs
#endif  /*}*/

#if 2==PARAMETER_STYLE  /*{ [0]: ((lc + lp)<<3) | pb;  [1]: (lp<<4) | lc */
    mov  inStream,%esi; addl %esi, inSize
    lodsb; mov $7,%cl; and %al,%cl  # pb
    or $~0,%edx; shl %cl,%edx; not %edx; push %edx
#define posStateMask    frame-4*3(%esp)
#define posStateMaskF        -4*3(%ebp)
    lodsb; mov %al,%cl; shr $4,%cl  # lp
    or $~0,%edx; shl %cl,%edx; not %edx; push %edx
#define litPosMask  frame-4*NBPW(%esp)
#define litPosMaskF      -4*NBPW(%ebp)
    and $0xf,%al; push %eax  # lc in lo byte
#define lc      frame-4*5(%esp)
#define lcF          -4*5(%ebp)
    push %esi  # inPtr
#define inPtr   frame-4*6(%esp)
#define inPtrF       -4*6(%ebp)
    add %al,%cl  # lc + lp  ready for shift
    mov vs,%edi  # Probs
#endif  /*}*/

#if 3==PARAMETER_STYLE  /*{  lc,lp,pb,xx  in separate bytes before probs[] */
    mov  inStream,%esi; addl %esi, inSize; push %esi  # inPtr
#define inPtr       frame-4*3(%esp)
#define inPtrF           -4*3(%ebp)
    mov vs,%esi; lodsl; xchg %eax,%edx  # %dl=lc; %dh=lp
    push %edx  # lc  in lo byte
#define lc      frame-4*NBPW(%esp)
#define lcF          -4*NBPW(%ebp)
    movb vs_ps-4(%esi),%cl   # %cl=ps;
                  or $~0,%eax; shl %cl,%eax; not %eax; push %eax
#define posStateMask    frame-4*5(%esp)
#define posStateMaskF        -4*5(%ebp)
    movb %dh,%cl; or $~0,%eax; shl %cl,%eax; not %eax; push %eax  # %cl= lp
#define litPosMask  frame-4*6(%esp)
#define litPosMaskF      -4*6(%ebp)
    addb %dl,%cl  # lc + lp;   [%cl was lp for litPosMask]
    mov %esi,%edi  # Probs
#endif  /*}*/

    push $0
#define posState frame-4*7(%esp)
#define posStateF     -4*7(%ebp)
    push $0
#define m_len   frame-4*8(%esp)
#define m_lenF       -4*8(%ebp)
    push $0
#define Code    frame-4*9(%esp)
#define CodeF        -4*9(%ebp)

    LOADCON1(%eax)
    push %eax
#define rep0    frame-4*10(%esp)
#define rep0F        -4*10(%ebp)
// Next 6 (rep1, rep2, rep3, prob, Probs, state) are known for 'pop'
    push %eax
#define rep1    frame-4*11(%esp)
#define rep1F        -4*11(%ebp)
    push %eax
#define rep2    frame-4*12(%esp)
#define rep2F        -4*12(%ebp)
    push %eax
#define rep3    frame-4*13(%esp)
#define rep3F        -4*13(%ebp)
    push $0
#define prob    frame-4*14(%esp)
#define probF        -4*14(%ebp)
    push %edi  # Probs
#define Probs   frame-4*15(%esp)
#define ProbsF       -4*15(%ebp)
    push $0  # state
#define state   /* frame-4*16 */(%esp)
#define stateF          -4*16   (%ebp)

    or $~0,Range

    mov $LZMA_LIT_SIZE,%eax; shl %cl,%eax  # LZMA_LIT_SIZE << (lc + lp)
    lea LZMA_BASE_SIZE(%eax),%ecx
    mov $((kBitModelTotal>>1)<<16)|(kBitModelTotal>>1),%eax
    shr %ecx; rep; stosl  # p already in %edi

    LOADCON(5,%ecx)
L20:
    call rcLoad
    loop L20
    jmp L200

#if DEBUG  //{
fmt: .ascii "rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG) //{
    .ascii "  prevB=%2x  rep0=%x"
#endif  //}
    .asciz "\n"
diagnose:
    push %edi; push %esi; push %ebp; push %ebx; push %edx; push %ecx; push %eax
    mov mo,%edx  # save
    mov  (7+1)*NBPW+Probs,%ecx
    push (7+1)*NBPW+rep0  # last param
    push (8+1)*NBPW+prevB
    incl seq; push seq
    movzwl (p_in),%eax; push %eax
    mov p_in,%eax; sub %ecx,%eax; shr %eax; push %eax
    push (12+1)*NBPW+Code
    push Range
    push %edx  # mo
#if (DEBUG < 2)  //{
    andl $1,(%esp)
#endif  //}
    lea fmt,%eax; push %eax
    call printf
    add $9*NBPW,%esp
    pop %eax; pop %ecx; pop %edx; pop %ebx; pop %ebp; pop %esi; pop %edi

    test mo,mo  # set CC
    lea 1*NBPW+frame(%esp),%ebp
diagret:
    ret

    .data
    .balign 4
seq:    .int 0
#endif  //}

rcNormalize:
    cmpl $1<<kNumTopBits,Range; jb 0f
    ret
0:
    shl $8,Range
rcLoad:
    push %esi; mov inPtrF,%esi
               cmp inLimF,%esi; jae rcDataError2
    mov CodeF,%eax; shl $8,%eax; lodsb
    mov %eax,CodeF; mov %esi,inPtrF; pop %esi
    ret

rcNorm2:  // no-call rcNormalize for rcGetBit; In: t1 busy; Out: t0= Range
                    movl 1*NBPW+inPtr,t0
    shll $8,1*NBPW+Code
            cmpl 1*NBPW+inLim,t0; jae rcDataError1
            movb (t0),t0b; incl 1*NBPW+inPtr
    shll $8,Range
            movb t0b,1*NBPW+Code
    mov Range,t0; jmp rcGB2

rcGetBit_mi_pstateSH0:
        mov stateF,t0
    add posStateF,mi
        shl $kNumPosBitsMax,t0
    add t0,mi
    jmp rcGetBit_pmi0

rcGetBit_mi_pstate0:  // rcGetBit(0, state + mi + p)
    add stateF,mi
rcGetBit_pmi0:
    mov ProbsF,p_in
//rcGetBit_mi0:  // rcGetBit(0, mi + p_in)

    lea (p_in,mi,2),p_in  # Frame disappears!
rcGetBit_0:  // rcGetBit(0, p_in)
    subl mi,mi
    .balign 8
rcGetBit_mi:  // rcGetBit(mi, mi + p_in)
    movzwl (p_in,mi,2),t1; mov Range,t0
    lea    (p_in,mi,2),p_in
/*rcGetBit:*/  // In: mi, p_in, no frame, sp one word low; Out: mo, CC set, %ebp as frame
    cmpl $1<<kNumTopBits,Range; jb rcNorm2  # no-call rcNormalize
rcGB2:  // In: t1= *p_in; t0= Range
    shrl $kNumBitModelTotalBits,t0  # Range >> kNumBitModelTotalBits
    imull t1,t0  # t0= bound= (*p) * (Range >> kNumBitModelTotalBits)
    cmpl t0,1*NBPW+Code; jae rcGetBit1
rcGetBit0:
    mov t0,Range  # Range= bound;
    mov $1<<kNumBitModelTotalBits,t0
    subl t1,t0
    shrl $kNumMoveBits,t0
    addw t0w,(p_in)  # *p + ((kBitModelTotal - *p) >> kNumMoveBits)
    add mo,mo  #    (mi<<1)  set CC
#if DEBUG  /*{*/
    jmp diagnose
#endif  /*}*/
    lea 1*NBPW+frame(%esp),%ebp
    ret
rcGetBit1:
    subl t0,1*NBPW+Code  # Code -= bound;
    shrl $kNumMoveBits,t1
    subl t0,Range  # Range -= bound;
    subw t1w,(p_in)  # *p - (*p >> kNumMoveBits)
    add mo,mo
    add $1,mo  # 1+ (mi<<1)  set CC
#if DEBUG  /*{*/
    jmp diagnose
#endif  /*}*/
    lea 1*NBPW+frame(%esp),%ebp
    ret

    .balign 16
L200:  // main loop
#define nowPos %edi  /* temporary only */
    mov outPtrF,nowPos
        mov posStateMaskF,%eax
    sub outBufF,nowPos
    and nowPos,%eax; mov %eax,posStateF

    LOADCON(IsMatch,mi)
    call rcGetBit_mi_pstateSH0; jne L270

    movzbl prevBF,t1
    movzbl lcF,t0; and litPosMaskF,nowPos; shl t0b,nowPos
    sub     $8,t0; neg t0;                 shr t0b,t1
            pop %eax  # state
    add t1,nowPos  # + (prevB >> (8 - lc))
            pop %esi  # Probs
    lea (nowPos,nowPos,2),nowPos  # *3
    shl $8,nowPos  # *256;  768==LZMA_LIT_SIZE
        cmp $kNumLitStates,%eax
            pop t1    # prob [discard]
    lea (Literal<<1)(%esi,nowPos,2),t0
#undef nowPos
            push t0  # probF
            push %esi  # Probs
        mov $0x100,bit
            push %eax  # state
    LOADCON1(symbol)  # mi=symbol;  must not change condition code
        jb L240
L205:
    mov outPtrF,matchB
    sub rep0F,matchB
    movzbl (matchB),matchB
L210:  // symbol === mi === mo; 0x100==bit
    mov probF,p_in
    shl matchB
    mov bit,t0
    and matchB,bit  # bit = (matchByte & 0x100);
    add bit,t0
    lea (p_in,t0,2),p_in
    call rcGetBit_mi
    mov symbol,t0;  shr $8,bit
    and     $1,t0;  cmp t0,bit
    mov $0x100,bit; jne L243  # break
    cmp bit,symbol; jb L210
    jmp L245

L240:  // symbol === mi === mo
    mov probF,p_in
    call rcGetBit_mi
L243:
    cmp bit,symbol; jb L240
L245:  // %al still lives for L298
    pop     t1  # stateF
    cmp $10,t1; sbb  t0,t0  # -1 or 0
                and $-3,t0  # -3 or 0
                add $ 6,t0  #  3 or 6
    cmp $4,t1; cmovb t1,t0
0:
    sub t0,t1; push t1  // stateF
    jmp L298

L270:
    LOADCON(IsRep,mi)
    call rcGetBit_mi_pstate0; jne L290

    pop %eax  # state
    pop %edi  # Probs
    pop t1  # prob [discard]
    pop t0  # rep3 [discard]
    pop t1  # rep2
    pop t0  # rep1
    push (%esp)  # rep1 = old_rep0
    push t0    # rep2 = old_rep1
    push t1    # rep3 = old_rep2
    LOADCON(LenCoder<<1,t1); sub t0,t0  # 0
    jmp L350

L290:
    LOADCON(IsRepG0,mi)
    call rcGetBit_mi_pstate0; jne L300
L293:
    LOADCON(IsRep0Long,mi)
    call rcGetBit_mi_pstateSH0; jne L340
L295:
    pop %eax  # state
    cmp $kNumLitStates,%eax
    sbb %eax,%eax  # -1 or 0
    add %eax,%eax  # -2 or 0
    add  $11,%eax  # 9 or 11
    push %eax  # state
L297:
    mov outPtrF,%esi
    sub   rep0F,%esi
    cmp outBufF,%esi; jb lzmaDataError
    lodsb
L298:
    mov outPtrF,%edi; stosb
    jmp L519
L300:
    LOADCON(IsRepG1,mi)
    call rcGetBit_mi_pstate0; mov rep1F,distance; je L330
L310:
    LOADCON(IsRepG2,mi)
    call rcGetBit_mi_pstate0; mov rep2F,distance; je L325
L320:
    mov rep3F,distance
    mov rep2F,t0; mov t0,rep3F
L325:
    mov rep1F,t0; mov t0,rep2F
L330:
    mov rep0F,t0; mov t0,rep1F
    mov distance,rep0F
L340:
    pop %eax  # stateF
    pop %edi  # Probs
    pop t0    # prob [discard]
    LOADCON(RepLenCoder<<1,t1); LOADCON(8,t0)

L350:  # In: %eax= state; %edi= p; t1= xxxCoder<<1; t0= new base_state
    add %edi,t1; push t1  # prob
    push %edi  # Probs
    cmp $kNumLitStates,%eax; mov t0,%eax; jb 0f
                             add $3,%eax
0:
    push %eax  # stateF

    mov probF,p_in
    // add $LenChoice<<1,p_in  //0==LenChoice
    call rcGetBit_0; jne L360
    mov posStateF,mi
        mov probF,probLen
    shl $kLenNumLowBits,mi
    sub t0,t0  # 0
    LOADCON(1<<kLenNumLowBits,hibit)
    lea (LenLow<<1)(probLen,mi,2),probLen
    jmp L390
L360:
    mov probF,p_in; add $LenChoice2<<1,p_in
    call rcGetBit_0; jne L370
    mov posStateF,mi
        mov probF,probLen
    shl $kLenNumMidBits,mi
    LOADCON(kLenNumLowSymbols,t0)
    LOADCON(1<<kLenNumMidBits,hibit)
    lea (LenMid<<1)(probLen,mi,2),probLen
    jmp L390
L370:
    mov $LenHigh<<1,probLen; add probF,probLen
    LOADCON(kLenNumLowSymbols + kLenNumMidSymbols,t0)
    mov $1<<kLenNumHighBits,hibit
L390:
    mov t0,m_lenF
    LOADCON1(mi)
L395:  // RangeDecoderBitTreeDecode
    mov probLen,p_in
    call rcGetBit_mi; mov mo,t0; sub hibit,t0; jb L395
    add t0,m_lenF
    cmpl $4,stateF; jae L500
/*L400:*/
    addl $kNumLitStates,stateF

    mov m_lenF,t0; cmp $kNumLenToPosStates,   t0; jb 0f
    LOADCON(            kNumLenToPosStates -1,t0)
0:

    mov ProbsF,probLit
    shl $kNumPosSlotBits,t0
    LOADCON1(mi)
    LOADCON(1<<kNumPosSlotBits,hibit)
    lea (PosSlot<<1)(probLit,t0,2),probLit
L403:  // RangeDecoderBitTreeDecode
    mov probLit,p_in
    call rcGetBit_mi; mov mo,r_posSlot; sub hibit,r_posSlot; jb L403
    mov r_posSlot,posSlotF
        mov r_posSlot,rep0F
    cmp $kStartPosModelIndex,r_posSlot; jb L460
L405:
    mov r_posSlot,numDirectBits
        andl $1,rep0F
    shr numDirectBits
        orl  $2,rep0F
    dec numDirectBits
    cmp $kEndPosModelIndex,r_posSlot; jae L410
L407:
    mov $SpecPos-1,mi; sub r_posSlot,mi  // r_posSlot === %ecx
    mov numDirectBits,%ecx; shll %cl,rep0F; add rep0F,mi
    shl mi; add ProbsF,mi; mov mi,probF
    jmp L438

L410:
    sub $kNumAlignBits,numDirectBits
L420:
    call rcNormalize
    shr Range
    shll rep0F
    cmp Range,CodeF; jb L430
    incl rep0F
    sub Range,CodeF  // if (Code>=Range) Code-=Range;
L430:
    dec numDirectBits; jne L420
    mov $Align<<1,mi; add ProbsF,mi; mov mi,probF
    shll $kNumAlignBits,rep0F
    LOADCON(kNumAlignBits,numDirectBits)
L438:
    LOADCON1(i)
    mov i,mi
L440:
    mov probF,p_in
    call rcGetBit_mi
    testb $1,moB; je L445; or i,rep0F
L445:
    shl i
    dec numDirectBits; jne L440
    jmp L465
L450:
L460:
L465:
    incl rep0F
#if 0  /*{ only for the stream version */
    jne L470; mov $kLzmaStreamWasFinishedId,m_lenF
    jmp L530
L470:
#endif  /*}*/
L500:
#define lim %edx
#define dst %edi
#define src %esi
#define cnt %ecx
    mov m_lenF,cnt; add $kMatchMinLen,cnt
    mov outPtrF,dst; mov dst,%eax
    sub outBufF,%eax; cmp %eax,rep0F; ja lzmaDataError
    mov dst,src; sub rep0F,src
    mov outLimF,lim
L510:
    lodsb; stosb
    cmp lim,dst
#if 0  /*{*/
    loopne L510  # saves 3 bytes, but takes three times as long
#else  /*}{*/
    jae L515; dec cnt; jne L510
L515:
#endif  /*}*/
    //mov cnt,m_len  // needed only for streaming?
L519:  // common tail for prevB and outPtr
    mov dst,outPtrF
    movb %al,prevB
/*L520:*/  // bottom of while loop
    cmp outLimF,%edi; jb L200
L530:
    call rcNormalize
    sub %eax,%eax; jmp lzmaExit  // success

rcDataError2:
    pop %esi
rcDataError1:
    pop %eax  // discard return address
lzmaDataError:
    LOADCON1(%eax)  // 1; failure
lzmaExit:
    lea frame(%esp),%ebp

    mov inSizeProcessed,%edx
    mov  inPtrF,%esi
    sub inBuf,%esi
    mov %esi,(%edx)

    mov outSizeProcessed,%edx
    mov outPtrF,%edi
    sub outBuf,%edi
    mov %edi,(%edx)

    leave
    pop %ebx; pop %esi; pop %edi
#if !defined(LZMA_FALL_THROUGH) || !LZMA_FALL_THROUGH  //{
    ret
#endif //}

