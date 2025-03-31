/*
  jfrLzmaDecode.c
  LZMA Decoder (optimized for Speed version)
  
  LZMA SDK 4.40 Copyright (c) 1999-2006 Igor Pavlov (2006-05-01)
  http://www.7-zip.org/

  LZMA SDK is licensed under two licenses:
  1) GNU Lesser General Public License (GNU LGPL)
  2) Common Public License (CPL)
  It means that you can select one of these two licenses and 
  follow rules of that license.

  SPECIAL EXCEPTION:
  Igor Pavlov, as the author of this Code, expressly permits you to 
  statically or dynamically link your Code (or bind by name) to the 
  interfaces of this file without subjecting your linked Code to the 
  terms of the CPL or GNU LGPL. Any modifications or additions 
  to this file, however, are subject to the LGPL or CPL terms.
*/

#ifndef DEBUG  //{
    #define DEBUG 0
#endif  //}
/*
  Modified 2007-06-19 by John F. Reiser to add labels ("L200")
  for cross-reference to hand-compiled versions.  
  Two labels ("L200 - L530") indicate begin and end;
  Three labels ("L203 - L270 - L520") indicate if-then-else.
*/
/*
  Modified 2006-09-16 by John F. Reiser for flexibility and to facilitate
  hand tuning.  Source was lzma443-1.tar.bz2 (LzmaDecode.c 2006-05-01)

  The goal is to retain most of the speed of the original LzmaDecode.c
  but with better space savings than the original LzmaDecodeSize.c.
  Take advantage of gcc extensions to C.  The primary target platforms
  have gcc native; but the code can be compiled for Win32 under mingw.

0) For clarity, use 'const' as much as possible.  Also use brace-matching
   comments on conditional compilation directives.

1) Replace macros RC_GET_BIT, RC_GET_BIT2, IfBit0, UpdateBit0, UpdateBit1
   with inline nested function rcGetBit for clarity, space, and flexibility.
   [This also avoids torturous macro syntax.]  The state variables Range
   and Code can be accessed via the frame and/or stack pointer, instead
   of the additional pointer CRangeDecoder *.  Also, hand tuning may put
   one or both of these into fixed registers to save more space and time.
   Adding "inline" to the declaration of rcGetBit goes back to maximum speed,
   but costs code size.  For maximum compile-time flexibility: duplicate
   the definition under another name, using 'inline' for one case
   and not for the other.

   These changes were motivated by noticing that IfBit0 was always followed
   by UpdateBit0 and UpdateBit1 in separate branches, and that gcc can
   track control flow (remember which branch) with "accumulator style"
   usage of the 'mi' parameter and the result.

2) Replace macro RangeDecoderBitTreeDecode with inline nested function.
   Inline makes all calls of rcGetBit from the same nesting level, which
   allows further hand optimizations of assembly code.

3) Define __label__ ResultDataError to retain correctness of C code,
   but note obvious tweaks of  "return LZMA_RESULT_DATA_ERROR;"
   to prepare for hand-modifying the compiler-generated assembly code.
   [Remember to change all the uses of RC_TEST, nested in RC_NORMALIZE.]
   Also introduce another syntax block level (braces {}) in the hope
   that gcc would not get scared upon seeing the "non-local" goto.
   However, this was not totally effective, and stack usage grows
   by around 50%, which hurts beyond 128 bytes on x86.
   Hand tuning (after tricking the compiler with the 'return's)
   is needed for best optimization when using gcc-4.1.0 or gcc-3.4.6.


   Net space savings: about 1200 bytes of code (2950 ==> 1750) in C;
   another 130 bytes when recoding by hand the compiler-generated assembly
   language for rcGetBit (190 ==> 110) and calls to it (50 bytes.)
   gcc has difficulty when registers are tightly constrained, and
   does not hoist instructions to create new fall-through entry points.
   Original LzmaDecodeSize.c saved about 800 bytes (2950 ==> 2150).
   So the changes beat LzmaDecodeSize.c by 50% (-800 ==> -1200 bytes)
   yet retain most of the speed of LzmaDecode.c.

   Using one dedicated register for 'Range' seems to be a good trade-off
   (saves space and time in rcGetBit, without creating too much trouble
   for register allocation in the rest of the code) but it requires hand
   modification of the generated code in order to preserve the register
   over calls to LzmaDecode.  gcc-4.1.0 and gcc-3.4.6 do not support
   dedicating a register to a non-static local variable.  Instead, a
   register may be dedicated only to a file-scope global variable.  Other
   files rely on that register being preserved when they call LzmaDecode.

   Compilation flags for hand tuning on x86:
	gcc-4.1.1 -S -O2 -m32 -march=i386 -nostdinc \
	-Wall -W -Wcast-align -Wcast-qual -Wwrite-strings -Werror -mtune=k6 \
	-fno-exceptions -fno-asynchronous-unwind-tables -fno-omit-frame-pointer \
	-fno-align-functions -fno-align-jumps -fno-align-labels -fno-align-loops \
	-fweb -ffunction-sections \
	-momit-leaf-frame-pointer -mpreferred-stack-boundary=2 \
	-DN_REGISTER_VARS=1 \
	-DLZMA_DATA_ERROR_ACTION="return LZMA_RESULT_DATA_ERROR" \
	-DUSE_RESULT_DATA_ERROR_LABEL=0 \
	jfrLzmaDecode.c
*/

#ifndef USE_RESULT_DATA_ERROR_LABEL  /*{*/
#define USE_RESULT_DATA_ERROR_LABEL 1
#endif  /*}*/

/* 0 < N_REGISTER_VARS requires hand compensation to save+restore at entry+exit */
#ifndef N_REGISTER_VARS  /*{*/
#define N_REGISTER_VARS 0
#endif  /*}*/

#ifndef REGISTER_VAR_DECL1  /*{*/
#define REGISTER_VAR_DECL1 __asm__("%edi")
#endif  /*}*/

#ifndef REGISTER_VAR_DECL2  /*{*/
#define REGISTER_VAR_DECL2 __asm__("%ebx")
#endif  /*}*/

#include "LzmaDecode.h"

#define kNumTopBits 24
#define kTopValue ((UInt32)1 << kNumTopBits)

#define kNumBitModelTotalBits 11
#define kBitModelTotal (1 << kNumBitModelTotalBits)
#define kNumMoveBits 5

#define RC_READ_BYTE (*Buffer++)

#define RC_INIT2 Code = 0; Range = 0xFFFFFFFF; \
  { int i; for(i = 0; i < 5; i++) { RC_TEST; Code = (Code << 8) | RC_READ_BYTE; }}

#ifndef LZMA_DATA_ERROR_ACTION  /*{*/
#define LZMA_DATA_ERROR_ACTION goto ResultDataError  /* return LZMA_RESULT_DATA_ERROR */
#endif  /*}*/

#ifdef _LZMA_IN_CB  /*{*/

#define RC_TEST { if (Buffer == BufferLim) \
  { SizeT size; int result = InCallback->Read(InCallback, &Buffer, &size); \
    if (result != LZMA_RESULT_OK) return result; \
  BufferLim = Buffer + size; if (size == 0) LZMA_DATA_ERROR_ACTION;}}

#define RC_INIT Buffer = BufferLim = 0; RC_INIT2

#else  /*}{*/

#define RC_TEST { if (Buffer == BufferLim) LZMA_DATA_ERROR_ACTION;}

#define RC_INIT(buffer, bufferSize) Buffer = buffer; BufferLim = buffer + bufferSize; RC_INIT2
 
#endif  /*}*/

#define RC_NORMALIZE if (Range < kTopValue) { RC_TEST; Range <<= 8; Code = (Code << 8) | RC_READ_BYTE; }


#define kNumPosBitsMax 4
#define kNumPosStatesMax (1 << kNumPosBitsMax)

#define kLenNumLowBits 3
#define kLenNumLowSymbols (1 << kLenNumLowBits)
#define kLenNumMidBits 3
#define kLenNumMidSymbols (1 << kLenNumMidBits)
#define kLenNumHighBits 8
#define kLenNumHighSymbols (1 << kLenNumHighBits)

#define LenChoice 0
#define LenChoice2 (LenChoice + 1)
#define LenLow (LenChoice2 + 1)
#define LenMid (LenLow + (kNumPosStatesMax << kLenNumLowBits))
#define LenHigh (LenMid + (kNumPosStatesMax << kLenNumMidBits))
#define kNumLenProbs (LenHigh + kLenNumHighSymbols) 


#define kNumStates 12
#define kNumLitStates 7

#define kStartPosModelIndex 4
#define kEndPosModelIndex 14
#define kNumFullDistances (1 << (kEndPosModelIndex >> 1))

#define kNumPosSlotBits 6
#define kNumLenToPosStates 4

#define kNumAlignBits 4
#define kAlignTableSize (1 << kNumAlignBits)

#define kMatchMinLen 2

#define IsMatch 0
#define IsRep (IsMatch + (kNumStates << kNumPosBitsMax))
#define IsRepG0 (IsRep + kNumStates)
#define IsRepG1 (IsRepG0 + kNumStates)
#define IsRepG2 (IsRepG1 + kNumStates)
#define IsRep0Long (IsRepG2 + kNumStates)
#define PosSlot (IsRep0Long + (kNumStates << kNumPosBitsMax))
#define SpecPos (PosSlot + (kNumLenToPosStates << kNumPosSlotBits))
#define Align (SpecPos + kNumFullDistances - kEndPosModelIndex)
#define LenCoder (Align + kAlignTableSize)
#define RepLenCoder (LenCoder + kNumLenProbs)
#define Literal (RepLenCoder + kNumLenProbs)

#if Literal != LZMA_BASE_SIZE  /*{*/
StopCompilingDueBUG
#endif  /*}*/

int LzmaDecodeProperties(CLzmaProperties *propsRes, const unsigned char *propsData, int size)
{
  unsigned char prop0;
  if (size < LZMA_PROPERTIES_SIZE)
    return LZMA_RESULT_DATA_ERROR;
  prop0 = propsData[0];
  if (prop0 >= (9 * 5 * 5))
    return LZMA_RESULT_DATA_ERROR;
  {
    for (propsRes->pb = 0; prop0 >= (9 * 5); propsRes->pb++, prop0 -= (9 * 5));
    for (propsRes->lp = 0; prop0 >= 9; propsRes->lp++, prop0 -= 9);
    propsRes->lc = prop0;
    /*
    unsigned char remainder = (unsigned char)(prop0 / 9);
    propsRes->lc = prop0 % 9;
    propsRes->pb = remainder / 5;
    propsRes->lp = remainder % 5;
    */
  }

  #ifdef _LZMA_OUT_READ  /*{*/
  {
    int i;
    propsRes->DictionarySize = 0;
    for (i = 0; i < 4; i++)
      propsRes->DictionarySize += (UInt32)(propsData[1 + i]) << (i * 8);
    if (propsRes->DictionarySize == 0)
      propsRes->DictionarySize = 1;
  }
  #endif  /*}*/
  return LZMA_RESULT_OK;
}

#define kLzmaStreamWasFinishedId (-1)

#if DEBUG  //{
#include <stdio.h>
#endif  //}

#if 1<=N_REGISTER_VARS  /*{*/
  register UInt32 Range REGISTER_VAR_DECL1;
#endif  /*}*/
#if 2<=N_REGISTER_VARS  /*{*/
  register UInt32 Code REGISTER_VAR_DECL2;
#endif  /*}*/

int LzmaDecode(CLzmaDecoderState *const vs,
    unsigned char const *const inStream,  SizeT const inSize,  SizeT *const inSizeProcessed,
    unsigned char       *const outStream, SizeT const outSize, SizeT *const outSizeProcessed)
{
#if 0!=USE_RESULT_DATA_ERROR_LABEL  /*{*/
  __label__ ResultDataError;
#endif  /*}*/
 {
  CProb *const p = vs->Probs;
  SizeT nowPos = 0;
  Byte previousByte = 0;
  UInt32 const posStateMask = (1 << (vs->Properties.pb)) - 1;
  UInt32 const literalPosMask = (1 << (vs->Properties.lp)) - 1;
  int const lc = vs->Properties.lc;

  #ifdef _LZMA_OUT_READ  /*{*/
  
#if 1 > N_REGISTER_VARS  /*{*/
  UInt32 Range = vs->Range;
#endif  /*}*/
#if 2 > N_REGISTER_VARS  /*{*/
  UInt32 Code = vs->Code;
#endif  /*}*/
  #ifdef _LZMA_IN_CB  /*{*/
  const Byte *Buffer = vs->Buffer;
  const Byte *BufferLim = vs->BufferLim;
  #else  /*}{*/
  const Byte *Buffer = inStream;
  const Byte *BufferLim = inStream + inSize;
  #endif  /*}*/
  int state = vs->State;
  UInt32 rep0 = vs->Reps[0], rep1 = vs->Reps[1], rep2 = vs->Reps[2], rep3 = vs->Reps[3];
  int len = vs->RemainLen;
  UInt32 globalPos = vs->GlobalPos;
  UInt32 distanceLimit = vs->DistanceLimit;

  Byte *const dictionary = vs->Dictionary;
  UInt32 dictionarySize = vs->Properties.DictionarySize;
  UInt32 dictionaryPos = vs->DictionaryPos;

  Byte tempDictionary[4];

  #ifndef _LZMA_IN_CB  /*{*/
  *inSizeProcessed = 0;
  #endif  /*}*/
  *outSizeProcessed = 0;
  if (len == kLzmaStreamWasFinishedId)
    return LZMA_RESULT_OK;

  if (dictionarySize == 0)
  {
    dictionary = tempDictionary;
    dictionarySize = 1;
    tempDictionary[0] = vs->TempDictionary[0];
  }

  if (len == kLzmaNeedInitId)
  {
    {
      UInt32 numProbs = Literal + ((UInt32)LZMA_LIT_SIZE << (lc + vs->Properties.lp));
      UInt32 i;
      for (i = 0; i < numProbs; i++)
        p[i] = kBitModelTotal >> 1; 
      rep0 = rep1 = rep2 = rep3 = 1;
      state = 0;
      globalPos = 0;
      distanceLimit = 0;
      dictionaryPos = 0;
      dictionary[dictionarySize - 1] = 0;
      #ifdef _LZMA_IN_CB  /*{*/
      RC_INIT;
      #else  /*}{*/
      RC_INIT(inStream, inSize);
      #endif  /*}*/
    }
    len = 0;
  }
  while(len != 0 && nowPos < outSize) {
    UInt32 pos = dictionaryPos - rep0;
    if (pos >= dictionarySize)
      pos += dictionarySize;
    outStream[nowPos++] = dictionary[dictionaryPos] = dictionary[pos];
    if (++dictionaryPos == dictionarySize)
      dictionaryPos = 0;
    len--;
  }
  if (dictionaryPos == 0)
    previousByte = dictionary[dictionarySize - 1];
  else
    previousByte = dictionary[dictionaryPos - 1];

  #else /*}{*/ /* if !_LZMA_OUT_READ */

#if 1 > N_REGISTER_VARS  /*{*/
  UInt32 Range;
#endif  /*}*/
#if 2 > N_REGISTER_VARS  /*{*/
  UInt32 Code;
#endif  /*}*/
  int state = 0;
  UInt32 rep0 = 1, rep1 = 1, rep2 = 1, rep3 = 1;
  int len = 0;
  const Byte *Buffer;
  const Byte *BufferLim;

  #ifndef _LZMA_IN_CB  /*{*/
  *inSizeProcessed = 0;
  #endif  /*}*/
  *outSizeProcessed = 0;

  {
    UInt32 i;
    UInt32 numProbs = Literal + ((UInt32)LZMA_LIT_SIZE << (lc + vs->Properties.lp));
    for (i = 0; i < numProbs; i++)
      p[i] = kBitModelTotal >> 1;
  }
  
  #ifdef _LZMA_IN_CB  /*{*/
  RC_INIT;
  #else  /*}{*/
  RC_INIT(inStream, inSize);
  #endif  /*}*/

  #endif  /*}*/ /* _LZMA_OUT_READ */

  /*__attribute__((regparm(2)))*/  /* pass both arguments in registers */
  unsigned rcGetBit(unsigned /*const*/ mi, unsigned short *const p)
  {
    RC_NORMALIZE;
    unsigned const bound = *p * (Range >> kNumBitModelTotalBits);
    if (Code < bound) {
      Range = bound;
      *p += (kBitModelTotal - *p) >> kNumMoveBits;
      mi=    (mi<<1);
    }
    else {
      Code  -= bound;
      Range -= bound;
      *p -= *p >> kNumMoveBits;
      mi= 1+ (mi<<1);
    }
#if DEBUG  //{
    static unsigned seq;
    printf("rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG)  //{
            "  prevB=%2x  rep0=%x"
#endif  //}
            "\n",
#if (2 <= DEBUG)  //{
        mi,
#else  //}{
       1& mi,
#endif  //}
                 Range, Code, p - vs->Probs, *p, ++seq, previousByte, rep0);
#endif  //}
      return mi;
  };

  inline  /* inline so that rcGetBit is called only at nesting level 1 */
  unsigned RangeDecoderBitTreeDecode(
    int const numLevels,
    unsigned short *const probs
  ) {
    int i = numLevels;
    unsigned res = 1;
    do {
      res = rcGetBit(res, res + probs);
    } while(--i != 0);
    return res - (1 << numLevels);
  };

  while(nowPos < outSize) { /* the top-level outer loop; n1  L200 - L530 */
    int posState = (int)(
        (nowPos 
        #ifdef _LZMA_OUT_READ  /*{*/
        + globalPos
        #endif  /*}*/
        )
        & posStateMask);

    if (0==rcGetBit(0, p + IsMatch + (state << kNumPosBitsMax) + posState))
    { /* n2 */  /* L203 - L270 - L520 */
      int symbol = 1;
      CProb *prob1 = p + Literal + (LZMA_LIT_SIZE *   /* used L210, L240 */
        (((
        (nowPos 
        #ifdef _LZMA_OUT_READ  /*{*/
        + globalPos
        #endif  /*}*/
        )
        & literalPosMask) << lc) + (previousByte >> (8 - lc))));

      /* previousByte is dead; so is nowPos as a "control" (state) input. */

      if (state >= kNumLitStates)
      { /* n3 */  /* L205 - L240 */
        #ifdef _LZMA_OUT_READ  /*{*/
        UInt32 pos = dictionaryPos - rep0;
        if (pos >= dictionarySize)
          pos += dictionarySize;
        int matchByte = dictionary[pos];
        #else  /*}{*/
        int matchByte = outStream[nowPos - rep0];
        #endif  /*}*/
        do { /* n4 */ /* L210 - L230 */
          int bit;
          matchByte <<= 1;
          bit = (matchByte & 0x100);
          symbol= rcGetBit(symbol, prob1 + 0x100 + bit + symbol);
          if ((1& symbol)!=(bit>>8))
            break;  /* goto L240 */
        } while (symbol < 0x100);
      } /* L240 */
      while (symbol < 0x100) { /* n3 */
        symbol = rcGetBit(symbol, prob1 + symbol);
      } /* L245 */
      previousByte = (Byte)symbol;  /* subtracts 0x100 */

      outStream[nowPos++] = previousByte;
      #ifdef _LZMA_OUT_READ  /*{*/
      if (distanceLimit < dictionarySize)
        distanceLimit++;

      dictionary[dictionaryPos] = previousByte;
      if (++dictionaryPos == dictionarySize)
        dictionaryPos = 0;
      #endif  /*}*/
      if (state < 4) state = 0;
      else if (state < 10) state -= 3;
      else state -= 6;
    }
    else             
    { /* n2 */ /* L270 - L520 */
      CProb *prob2;
      if (0==rcGetBit(0, p + IsRep + state))
      { /* n3 */ /* L275 - L290 - L350 */
        rep3 = rep2;
        rep2 = rep1;
        rep1 = rep0;
        state = state < kNumLitStates ? 0 : 3;
        prob2 = p + LenCoder;  /* used L350, L360(2), L370 */
      }
      else
      { /* n3 */ /* L290 - L350 */
        if (0==rcGetBit(0, p + IsRepG0 + state))
        { /* n4 */ /* L293 - L300 - L340 */
          if (0==rcGetBit(0, p + IsRep0Long + (state << kNumPosBitsMax) + posState))
          { /* n5 */ /* L295 - L340 */
            #ifdef _LZMA_OUT_READ  /*{*/
            UInt32 pos;
            #endif  /*}*/
            
            #ifdef _LZMA_OUT_READ  /*{*/
            if (distanceLimit == 0)
            #else  /*}{*/
            if (nowPos == 0)
            #endif  /*}*/
              return LZMA_RESULT_DATA_ERROR;
            
            state = state < kNumLitStates ? 9 : 11;  /* L297 */
            #ifdef _LZMA_OUT_READ  /*{*/
            pos = dictionaryPos - rep0;
            if (pos >= dictionarySize)
              pos += dictionarySize;
            previousByte = dictionary[pos];
            dictionary[dictionaryPos] = previousByte;
            if (++dictionaryPos == dictionarySize)
              dictionaryPos = 0;
            #else  /*}{*/
            previousByte = outStream[nowPos - rep0];
            #endif  /*}*/
            outStream[nowPos++] = previousByte;
            #ifdef _LZMA_OUT_READ  /*{*/
            if (distanceLimit < dictionarySize)
              distanceLimit++;
            #endif  /*}*/

            continue;  /* goto L520 */
          }
        }
        else
        { /* n4 */ /* L300 - L340 */
          UInt32 distance;
          if (0==rcGetBit(0, p + IsRepG1 + state))
          { /* L305 - L310 - L330 */
            distance = rep1;
          }
          else 
          { /* L310  - L330 */
            if (0==rcGetBit(0,  p + IsRepG2 + state))
            { /* L315 - L320 - L325 */
              distance = rep2;
            }
            else
            { /* L320  - L325 */
              distance = rep3;
              rep3 = rep2;
            } /* L325 */
            rep2 = rep1;
          } /* L330 */
          rep1 = rep0;
          rep0 = distance;
        } /* L340 */
        state = state < kNumLitStates ? 8 : 11;  /* L345 */
        prob2 = p + RepLenCoder;  /* used L350, L360(2), L370 */
      }
      { /* n3 */ /* L350 - L395 */
        int numBits, offset;
        CProb *probLen;
        if (0==rcGetBit(0, prob2 + LenChoice))
        { /* L355 - L360 - L390 */
          probLen = prob2 + LenLow + (posState << kLenNumLowBits);  /* used L390 */
          offset = 0;
          numBits = kLenNumLowBits;
        }
        else
        { /* L360 - L390 */
          if (0==rcGetBit(0, prob2 + LenChoice2))
          {
            probLen = prob2 + LenMid + (posState << kLenNumMidBits);  /* used L390 */
            offset = kLenNumLowSymbols;
            numBits = kLenNumMidBits;
          }
          else
          { /* L370 - L380 */
            probLen = prob2 + LenHigh;  /* used L390 */
            offset = kLenNumLowSymbols + kLenNumMidSymbols;
            numBits = kLenNumHighBits;
          } /* L380 */
        } /* L390 */
        len = offset + RangeDecoderBitTreeDecode(numBits, probLen);
      } /* L395 */

      if (state < 4)
      { /* n3 */ /* L400 - L500 */
        CProb *prob3;
        int posSlot;
        state += kNumLitStates;
        posSlot = RangeDecoderBitTreeDecode(kNumPosSlotBits, p + PosSlot +
            ((len < kNumLenToPosStates ? len : kNumLenToPosStates - 1) << 
            kNumPosSlotBits));
        if (posSlot >= kStartPosModelIndex)
        { /* n4 */ /* L405 - L460 - L465 */
          int numDirectBits = ((posSlot >> 1) - 1);
          rep0 = (2 | ((UInt32)posSlot & 1));
          if (posSlot < kEndPosModelIndex)
          { /* L407 - L410 - L438 */
            rep0 <<= numDirectBits;
            prob3 = p + SpecPos + rep0 - posSlot - 1;  /* used L440 */
          }
          else
          { /* n5 */ /* L410 - L438 */
            numDirectBits -= kNumAlignBits;
            do { /* L420 */
              RC_NORMALIZE;
              Range >>= 1;
              rep0 <<= 1;
              if (Code >= Range)
              {
                Code -= Range;
                rep0 |= 1;
              } /* L430 */
            } while (--numDirectBits != 0);

            prob3 = p + Align;  /* used L440 */
            rep0 <<= kNumAlignBits;
            numDirectBits = kNumAlignBits;
          } /* L438 */
          { /* n5 */
            /* Equivalent to
                 rep0 |= BitReverse(numDirectBits,
                   RangeDecoderBitTreeDecode(numDirectBits, prob3) );
               Note that the bit reversal could have been avoided
               by reversing the encoding; the bits are "data," not
               "control."  Doing so would save a register at decode.
            */
            int i = 1;
            int mi = 1;
            do { /* L440 */
              if (1& (mi= rcGetBit(mi, mi + prob3))) {
                rep0 |= i;
              } /* L445 */
              i <<= 1;
            } while(--numDirectBits != 0);
          } /* L450 */
        }
        else /* L460 */
          rep0 = posSlot;  /* L465 */
        if (++rep0 == (UInt32)(0))
        {
          /* it's for stream version */
          len = kLzmaStreamWasFinishedId;
          break;
        } /* L470 */
      } /* L500 */

      len += kMatchMinLen;
      #ifdef _LZMA_OUT_READ  /*{*/
      if (rep0 > distanceLimit) 
      #else  /*}{*/
      if (rep0 > nowPos)
      #endif  /*}*/
        return LZMA_RESULT_DATA_ERROR;

      #ifdef _LZMA_OUT_READ  /*{*/
      if (dictionarySize - distanceLimit > (UInt32)len)
        distanceLimit += len;
      else
        distanceLimit = dictionarySize;
      #endif  /*}*/

      do { /* L510 */
        #ifdef _LZMA_OUT_READ  /*{*/
        UInt32 pos = dictionaryPos - rep0;
        if (pos >= dictionarySize)
          pos += dictionarySize;
        previousByte = dictionary[pos];
        dictionary[dictionaryPos] = previousByte;
        if (++dictionaryPos == dictionarySize)
          dictionaryPos = 0;
        #else  /*}{*/
        previousByte = outStream[nowPos - rep0];
        #endif  /*}*/
        len--;
        outStream[nowPos++] = previousByte;
      } while(len != 0 && nowPos < outSize);
    } /* L520 */
  } /* L530 */
  RC_NORMALIZE;

  #ifdef _LZMA_OUT_READ  /*{*/
  vs->Range = Range;
  vs->Code = Code;
  vs->DictionaryPos = dictionaryPos;
  vs->GlobalPos = globalPos + (UInt32)nowPos;
  vs->DistanceLimit = distanceLimit;
  vs->Reps[0] = rep0;
  vs->Reps[1] = rep1;
  vs->Reps[2] = rep2;
  vs->Reps[3] = rep3;
  vs->State = state;
  vs->RemainLen = len;
  vs->TempDictionary[0] = tempDictionary[0];
  #endif  /*}*/

  #ifdef _LZMA_IN_CB  /*{*/
  vs->Buffer = Buffer;
  vs->BufferLim = BufferLim;
  #else  /*}{*/
  *inSizeProcessed = (SizeT)(Buffer - inStream);
  #endif  /*}*/
  *outSizeProcessed = nowPos;
  return LZMA_RESULT_OK;
 }
#if 0!=USE_RESULT_DATA_ERROR_LABEL  /*{*/
ResultDataError:
  return LZMA_RESULT_DATA_ERROR;
#endif  /*}*/
}
