// Hand compiled Copyright (c) 2006-2007 John F. Reiser  (2007-05-26)
// from modified LzmaDecode.c.
// LZMA SDK 4.40 Copyright (c) 1999-2006 Igor Pavlov (2006-05-01)

#ifndef DEBUG  /*{*/
  #define DEBUG 1
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
Literal=  (RepLenCoder + kNumLenProbs)

#define hi8(x) ((x) - lo8(x))
#define lo8(x) (0xff&(x))
//#define lo8(x) ((0xff & ((x) >> lg4(x))) << lg4(x))

LZMA_BASE_SIZE= Literal
LZMA_LIT_SIZE =  768


#define call bl  /* subroutine call */
#define ret  mov pc,lr  /* arm.v4 lacks "bx lr" */
#define bkpt .long 0xe7f001f0  /* reserved instr; Linux GNU eabi breakpoint */

#define symbol  mi
#define mo  mi

#define mi  r0
#define p_in    r1
#define t1  r2
#define t0  r3

#define bit r4
#define i   r5
#define state   r6
#define Range   r7

#define rep0    r8
#define outPtr  r9
#define prob1   r10
#define prob2   r10
#define prob3   r10
#define Probs   r11

#define Code    r12

#define distance    bit
#define numDirectBits   bit
#define hibit       i
#define matchB      i
#define probLen     prob2
#define probLit     prob3
#define posSlot     posState
#define r_posSlot   t0

#define r_len       i
#define r_inPtr     r8

#define vs r0
vs_ps= 2
vs_lp= 1
vs_lc= 0

#if !defined(PARAMETER_STYLE)  /*{*/
  #define  PARAMETER_STYLE 3
//  Possible choices:
//  1  /*   0 bytes;  1-byte encoding of pb,lp,lc  [default] */
//  2  /* -24 bytes;  2-byte encoding requires no division */
//  3  /* -32 bytes;  separate bytes lc,lp,pb,xx at -4+ probs */
#endif  /*}*/

/* LzmaDecode(r0=vs, r1=inStream, r2=inSize, r3= &inSizeProcessed,
    [sp,#0]= outStream, [sp,#4]= outSize, [sp,#8]= &outSizeProcessed)
*/
    .arm
    .type   LzmaDecode, %function
//LzmaDecode: .globl LzmaDecode
        // save &inSizeProcesesed and caller registers
    stmdb sp!,{r3, r4,r5,r6,r7, r8,r9,r10,r11, lr}
    add r12,r2,r1  // inLim
    ldr outPtr,[sp, #10*NBPW + 0*NBPW]  // outStream
    ldr r7,[sp, #10*NBPW + 1*NBPW]  // outSize
    mov r_inPtr,r1
    add r10,r7,outPtr  // outLim

#if 1==PARAMETER_STYLE  /*{ [0]: pb*45 + lp*9 + lc */
    mov p,vs
    ldrb r6,[r_inPtr],#1

    mov r4,#0  // r4= pb;
1:
    cmp r6,#45; subhs r6,r6,#45; addhs r4,r4,#1; bhs 1b

    mov r5,#0  // r5= lp;
1:
    cmp r6,#9; subhs r6,r6, #9; addhs r5,r5,#1; bhs 1b  // r6= lc;
#endif  /*}*/

#if 2==PARAMETER_STYLE  /*{ [0]: ((lc + lp)<<3) | pb;  [1]: (lp<<4) | lc */
    mov p,vs
    ldrb r4,[r_inPtr],#1; and r4,r4,#7  // pb
    ldrb r6,[r_inPtr],#1; mov r5,r6,lsr #4  // lp
                        and r6,r6,#0xf  // lc
#endif  /*}*/

#if 3==PARAMETER_STYLE  /*{  lc,lp,pb,xx  in separate bytes before probs[] */
    add Probs,vs,#4
    ldrb r6,[vs, #vs_lc]
    ldrb r5,[vs, #vs_lp]
    ldrb r4,[vs, #vs_ps]
#endif  /*}*/
#undef vs

    add r14,r5,r6  // lp + lc
    mvn Range,#0  // ~0
    mvn r5,Range,lsl r5  // ~(~0<<lp) == litPosMask
    mvn r4,Range,lsl r4  // ~(~0<<ps) == posStateMask
    mov r3,#1
    mov r2,#1
    mov r1,#1
    stmdb sp!,{r0,r1,r2,r3, r4,r5,r6,r7, r8,r9,r10,r11, r12,r14}
#define stk_tmp [sp, #0*NBPW]
#define rep1    [sp, #1*NBPW]
#define rep2    [sp, #2*NBPW]
#define rep3    [sp, #3*NBPW]

#define posStateMask    [sp, #   4*NBPW]
//unused lp     [sp, #   5*NBPW]
#define lc      [sp, #0+ 6*NBPW]
#define lc8     [sp, #1+ 6*NBPW]  // 8 - lc
    rsb r6,r6,#8; strb r6,lc8
#define prevB       [sp, #2+ 6*NBPW]
#define litPosMask  [sp, #3+ 6*NBPW]
    strb r5,litPosMask
#define inPtr       [sp, #   7*NBPW]

#define inBuf   [sp, #8*NBPW]
#define outBuf  [sp, #9*NBPW]
#define outLim  [sp, #10*NBPW]
#define posState [sp, #11*NBPW]

#define inLim   [sp, #12*NBPW]
#define m_len   [sp, #13*NBPW]
    str r_inPtr,inPtr
    mov rep0,#1

#define  inSizeProcessed [sp, #(14     )*NBPW]
#define outSizeProcessed [sp, #(14+10+2)*NBPW]

    mov state,#0

    mov r2,#LZMA_LIT_SIZE
    mov r2,r2, lsl r14  // LZMA_LIT_SIZE << (lp + lc)
    add r2,r2,#lo8(LZMA_BASE_SIZE)
    add r2,r2,#hi8(LZMA_BASE_SIZE)  // nProbs
    mov r1,Probs
    mov r0,   #(kBitModelTotal>>1)
    orr r0,r0,#(kBitModelTotal>>1)<<16
L10:
    str r0,[r1],#4
    subs r2,r2,#2; bgt L10

    mov i,#5
L20:
    call rcInit2
    subs i,i,#1; bgt L20
    b L200

#if DEBUG  /*{*/
    .balign 4
fmt: .ascii "rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG) //{
    .ascii "  prevB=%2x  rep0=%x"
#endif  //}
    .asciz "\n"

    .arm; .balign 4
diagnose:
    stmdb sp!,{r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,lr}
    mov r0,p_in
    sub r0,r0,Probs
    mov r0,r0,lsr #1  // arg5  p[] index
#define starp t0
    mov r1,starp  // arg6  r2
#undef starp
    ldr r3,adr_seq; ldr r2,[r3]; add r2,r2,#1; str r2,[r3]  // arg7  seq
    ldrb r3,[sp, #2+ 6*NBPW + 14*NBPW]  // arg8  prevB
    mov r4,rep0  // arg9
    stmdb sp!,{r0,r1,r2,r3,r4}  // arg5,6,7,8,9: p[&], starp, seq, prevB, rep0
    mov r3,Code  // arg4
    mov r2,Range  // arg3
    ldr r1,[sp,#5*NBPW]  // arg2  mo === orig_r0
#if (DEBUG < 2)  //{
    and r1,r1,#1  // bottom bit only
#endif  //}
    adr r0,fmt  // arg1
    call printf
    add sp,sp,#5*NBPW  // remove arg5,6,7,8,9
    ldmia sp!,{r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,lr}
diagret:
    tst mo,mo
    ret

    .balign 4
adr_seq: .word seq
        .data
seq:    .int 0
    .text
#endif  /*}*/


rcNormalize:
    cmp Range,#kTopValue; movhs pc,lr
    b rcLoad
gbLoad:
    str lr,stk_tmp
    adr lr,gbCont
rcLoad:
    mov Range,Range, lsl #8
rcInit2:
    ldr t0,inLim
    ldr t1,inPtr
    cmp t0,t1; bls lzmaDataError  // input underflow
    ldrb t0,[t1],#1
    str t1,inPtr
    orr Code,t0,Code, lsl #8
    mov t1,lr
    ldr lr,stk_tmp  // for benefit of gbLoad
    mov pc,t1

rcGetBit_state0:  // rcGetBit(0, state + p_in)
    add p_in,p_in,state, lsl #1
rcGetBit_0:  // rcGetBit(0, p_in)
    mov mi,#0
rcGetBit:  // Out: CC set on mo
    cmp Range,#kTopValue; blo gbLoad  // inline the test of rcNormalize
gbCont:
#define starp t0
#define bound t1
#define y0tmp t1
    ldrh starp,[p_in]
    mov y0tmp,Range, lsr #kNumBitModelTotalBits
    mul bound,starp,y0tmp
    cmp Code,bound; bhs rcGetBit1
rcGetBit0:
    mov Range,      bound
    rsb y0tmp,starp,#kBitModelTotal
    add starp,starp,y0tmp, lsr #kNumMoveBits

    adcs mo,mi,mi  // mo = (mi<<1) | (Code >= bound);  set CC
    strh starp,[p_in]
#if DEBUG  //{
    b diagnose
#endif  //}
    ret
rcGetBit1:
    sub Range,Range,bound
    sub Code, Code, bound
    sub starp,starp,starp, lsr #kNumMoveBits

    adcs mo,mi,mi  // mo = (mi<<1) | (Code >= bound);  set CC
    strh starp,[p_in]
#if DEBUG  //{
    b diagnose
#endif  //}
    ret
#undef y0tmp
#undef bound
#undef starp

L200:  // main loop; In: prevB
    ldr t0,outBuf
    ldr t1,posStateMask
#define nowPos i  /* temporary only */
    sub nowPos,outPtr,t0
    and mi,nowPos,t1
    str mi,posState
    add mi,mi,state, lsl #kNumPosBitsMax
    add p_in ,Probs,#IsMatch<<1
    add p_in,p_in   ,mi, lsl #1;  call rcGetBit_0; bne L270

    ldr t1,lc  // litPosMask, prevB, (8 - lc), lc
#define t2 r1
    mov t0,t1,lsr #24  // litPosMask
    mov t2,t1,lsr #16  // ,prevB
    and t0,t0,nowPos
#undef nowPos
    and t2,t2,#0xff    // prevB
    mov t0,t0,lsl t1  // (nowPos & litPosMask)<<lc
    mov t1,t1,lsr #8  // 8 - lc
    add t0,t0,t2,lsr t1  // + (prevB >> (8- lc));  prevB dead
#undef t2
    add prob1,Probs,#lo8(Literal<<1)
    add t0,t0,t0,lsl #1  // *3
    add prob1,prob1,#hi8(Literal<<1)
    mov symbol,#1
    add prob1,prob1,t0,lsl #1+ 8  // *768 *2

    cmp state,#kNumLitStates; blo L240
L205:
    ldrb matchB,[outPtr, -rep0]
L210:  // symbol === mi === mo
    mov matchB,matchB,lsl #1
    add p_in,prob1,#0x100<<1
    and bit,matchB,#0x100
    add p_in,p_in,bit,lsl #1
    add p_in,p_in   ,mi, lsl #1;  call rcGetBit
    and t0,symbol,#1
    cmp t0,bit,lsr #8; bne L243  // break
    cmp symbol,#0x100; blo L210
    b L245
L240:  // symbol === mi === mo
    add p_in,prob1   ,mi, lsl #1;  call rcGetBit
L243:
    cmp symbol,#0x100; blo L240
L245:
                   mov   t0,#6
    cmp state,#10; movlo t0,#3
        strb symbol,[outPtr],#1
    cmp state,# 4; movlo t0,state
        strb symbol,prevB  // subtract 0x100
    sub state,state,t0
    b L520
L270:
    add p_in,Probs ,#IsRep  <<1;  call rcGetBit_state0; bne L290
    ldr t0,rep2
    ldr t1,rep1
    str t0,rep3
    str t1,rep2
    str rep0,rep1
    cmp state,#kNumLitStates
    mov   state,#3
    movlo state,#0
    add prob2,Probs,#lo8(LenCoder<<1)
    add prob2,prob2,#hi8(LenCoder<<1)
    b L350
L290:
    add p_in,Probs ,#IsRepG0<<1;  call rcGetBit_state0; bne L300
L293:
    ldr t0,posState
    add p_in,Probs ,#IsRep0Long<<1
    add mi,t0,state,lsl #kNumPosBitsMax
    add p_in,p_in   ,mi, lsl #1;  call rcGetBit_0; bne L340
L295:
    cmp state,#kNumLitStates
    mov   state,#11
    movlo state,#9
L297:
    ldr t0,outBuf
#define nowPos t0
    sub nowPos,outPtr,t0
    cmp nowPos,rep0; blo lzmaDataError  // backward offset too large
#undef nowPos
    ldrb t0,[outPtr, -rep0]
    strb t0,[outPtr],#1
    strb t0,prevB
    b L520
L300:
    add p_in,Probs ,#IsRepG1<<1;  call rcGetBit_state0; ldr distance,rep1; beq L330
L310:
    add p_in,Probs ,#IsRepG2<<1;  call rcGetBit_state0; ldr distance,rep2; beq L325
L320:
    ldr t0,rep2
    ldr distance,rep3
    str t0,rep3
L325:
    ldr t0,rep1
    str t0,rep2
L330:
    str rep0,rep1
    mov rep0,distance
L340:
    cmp state,#kNumLitStates
    mov   state,#11
    movlo state,#8
    add prob2,Probs,#lo8(RepLenCoder<<1)
    add prob2,prob2,#hi8(RepLenCoder<<1)
L350:
    add p_in,prob2,#LenChoice <<1; call rcGetBit_0; bne L360
    ldr t0,posState
    add probLen,prob2,#LenLow<<1
    mov t1,#0
    add probLen,probLen,t0,lsl #1+ kLenNumLowBits
    mov hibit,#1<<kLenNumLowBits
    b L390
L360:
    add p_in,prob2,#LenChoice2<<1; call rcGetBit_0; bne L370
    ldr t0,posState
    add probLen,prob2,#LenMid<<1
    mov t1,#kLenNumLowSymbols
    add probLen,probLen,t0,lsl #1+ kLenNumMidBits
    mov hibit,#1<<kLenNumMidBits
    b L390
L370:
    add probLen,prob2,#LenHigh<<1
    mov t1,#kLenNumLowSymbols + kLenNumMidSymbols
    mov hibit,$1<<kLenNumHighBits
L390:
    str t1,m_len
    mov mi,#1
L395:  // RangeDecoderBitTreeDecode
    add p_in,probLen,mi, lsl #1;  call rcGetBit; subs        t0,mo,hibit; blo L395
    ldr r_len,m_len
    add r_len,r_len,t0
    str r_len,m_len
    cmp state,#4; bhs L500
/*L400:*/
    add state,state,#kNumLitStates
    cmp   r_len,#kNumLenToPosStates
    movhs r_len,#kNumLenToPosStates -1
    add probLit,Probs,r_len,lsl #1+ kNumPosSlotBits
    add probLit,probLit,#PosSlot<<1
    mov mi,#1
    mov hibit,#1<<kNumPosSlotBits
L403:  // RangeDecoderBitTreeDecode
    add p_in,probLit,mi, lsl #1;  call rcGetBit; subs r_posSlot,mo,hibit; blo L403
    str r_posSlot,posSlot

    cmp r_posSlot,#kStartPosModelIndex; blo L460
L405:
    mov numDirectBits,r_posSlot,lsr #1
    sub numDirectBits,numDirectBits,#1
    and rep0,r_posSlot,#1
    orr rep0,rep0,#2
    cmp r_posSlot,#kEndPosModelIndex; bhs L410
L407:
    mov rep0,rep0,lsl numDirectBits
    add prob3,Probs,#lo8((SpecPos -1)<<1)
    sub t0,rep0,r_posSlot  // r_posSlot dies
    add prob3,prob3,#hi8((SpecPos -1)<<1)
    add prob3,prob3,t0,lsl #1
    b L438
L410:
    sub numDirectBits,numDirectBits,#kNumAlignBits
L420:
    cmp Range,#kTopValue; bllo rcLoad  // conditional subroutine call
    mov Range,Range,lsr #1
    cmp        Code,Range
    subhs Code,Code,Range  // if (Code>=Range) Code-=Range;
    adc rep0,rep0,rep0  // rep0 = (rep0<<1) + (Code>=Range)
L430:
    subs numDirectBits,numDirectBits,#1; bne L420
    add prob3,Probs,#lo8(Align<<1)
    add prob3,prob3,#hi8(Align<<1)
    mov rep0,rep0,lsl #kNumAlignBits
    mov numDirectBits,#kNumAlignBits
L438:
    mov i,#1
    mov mi,#1
L440:
    add p_in,prob3   ,mi, lsl #1;  call rcGetBit
    tst mo,#1; orrne rep0,rep0,i
    mov i,i,lsl #1
    subs numDirectBits,numDirectBits,#1; bne L440
    b L465
L450:
L460:
    ldr rep0,posSlot
L465:
    adds rep0,rep0,#1
#if 0  /*{ only for the stream version */
    bne L470
    mov t0,#kLzmaStreamWasFinishedId
    str t0,m_len
    b L530
L470:
#endif  /*}*/
    ldr r_len,m_len
L500:
    ldr t0,outBuf
    ldr t1,outLim
//cache ldrb prevB,[outPtr, r_len]
    add r_len,r_len,#kMatchMinLen
#define nowPos t0
    sub nowPos,outPtr,t0
    cmp nowPos,rep0; blo lzmaDataError  // backward offset too large
#undef nowPos
    sub t1,t1,outPtr  // headway in outBuf
    subs t0,r_len,t1
    //strhi t0,m_len  // unsatisfied count; needed only for stream version
    movhi r_len,t1  // clip r_len to headway
L510:
    ldrb t0,[outPtr, -rep0]
    strb t0,[outPtr],#1
    subs r_len,r_len,#1; bne L510
    strb t0,prevB
//cache pld [outPtr,#31]
L520:  // bottom of while loop
    ldr t1,outLim
    cmp outPtr,t1; blo L200
L530:
    call rcNormalize
    mov r0,#0; b lzmaExit  // success
lzmaDataError:
    mov r0,#1  // failure
lzmaExit:
    ldr t0,inPtr
    ldr t1,inBuf
    sub t0,t0,t1
    ldr t1,inSizeProcessed
    str t0,[t1]

    ldr t1,outBuf
    sub t0,outPtr,t1
    ldr t1,outSizeProcessed
    str t0,[t1]

    add sp,sp,#(14+1)*NBPW
#if !defined(LZMA_FALL_THROUGH) || !LZMA_FALL_THROUGH  //{
    ldmia sp!,{r4,r5,r6,r7, r8,r9,r10,r11, pc}  // subroutine return
#else  //}{
    ldmia sp!,{r4,r5,r6,r7, r8,r9,r10,r11}
    add sp,sp,#NBPW  // discard return address
#endif  //{
