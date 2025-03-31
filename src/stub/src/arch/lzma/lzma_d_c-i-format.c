__extension__ typedef long long acc_llong_t;
__extension__ typedef unsigned long long acc_ullong_t;
typedef void (*acc_sighandler_t)(int);
typedef struct {
  volatile unsigned short int v __attribute__((__packed__));
} __acc_ua16_t;

typedef struct {
  volatile unsigned long int v __attribute__((__packed__));
} __acc_ua32_t;
typedef unsigned char Byte;

typedef unsigned short UInt16;

typedef unsigned int UInt32;
typedef UInt32 SizeT;
typedef struct _CLzmaProperties {
  int lc;
  int lp;
  int pb;

} CLzmaProperties;

int LzmaDecodeProperties(CLzmaProperties *propsRes,
                         const unsigned char *propsData, int size);

typedef struct _CLzmaDecoderState {
  CLzmaProperties Properties;
  UInt16 *Probs;
} CLzmaDecoderState_dummy;

int LzmaDecode_dummy(CLzmaDecoderState_dummy *vs,

                     const unsigned char *inStream, SizeT inSize,
                     SizeT *inSizeProcessed,

                     unsigned char *outStream, SizeT outSize,
                     SizeT *outSizeProcessed);

typedef struct {
  struct {
    unsigned char lc, lp, pb, dummy;
  } Properties;
  UInt16 Probs[6];

} CLzmaDecoderState;
extern int __acc_cta[1 - 2 * !(sizeof(CLzmaDecoderState) == 16)];

int LzmaDecodeProperties(CLzmaProperties *propsRes,
                         const unsigned char *propsData, int size) {
  unsigned char prop0;
  if (size < 5)
    return 1;
  prop0 = propsData[0];
  if (prop0 >= (9 * 5 * 5))
    return 1;
  {
    for (propsRes->pb = 0; prop0 >= (9 * 5); propsRes->pb++, prop0 -= (9 * 5))
      ;
    for (propsRes->lp = 0; prop0 >= 9; propsRes->lp++, prop0 -= 9)
      ;
    propsRes->lc = prop0;
  }
  return 0;
}

#if DEBUG  //{
#include <stdio.h>
unsigned seq;  // visible for debugging
static UInt16 *vsProbs;
static int debug_LzmaDecode(unsigned mo, unsigned Range, unsigned Code, UInt16 *prob,
        unsigned prevB, unsigned rep0)
{
    ++seq;
    mo = 1 - mo;  // invert Carry from "if (Code < bound)"
    printf("rcGetBit=%3x  Range=%8.8x  Code=%8.8x  p[%4x]=%4.4x  seq=%4u"
#if (2 <= DEBUG)  //{
            "  prevB=%2x  rep0=%x"
#endif  //}
            "\n",
                 mo, Range, Code, prob - vsProbs, *prob, seq, prevB, rep0);
    return mo;
}
#else  //}{
  #define debug_LzmaDecode(...) /*empty*/;
#endif  //}

int LzmaDecode(const CLzmaDecoderState *vs,

               const unsigned char *inStream, SizeT inSize,
               SizeT *inSizeProcessed,

               unsigned char *outStream, SizeT outSize,
               SizeT *outSizeProcessed)
{
#if DEBUG  //{
  vsProbs = (UInt16 *)vs->Probs;  // vsProbs is not 'const'
#endif  //}
  UInt16 *p = (UInt16 *)vs->Probs;  // p is not 'const'
  SizeT nowPos = 0;
  Byte previousByte = 0;
  UInt32 posStateMask = (1 << (vs->Properties.pb)) - 1;
  UInt32 literalPosMask = (1 << (vs->Properties.lp)) - 1;
  int lc = vs->Properties.lc;
  int state = 0;
  UInt32 rep0 = 1, rep1 = 1, rep2 = 1, rep3 = 1;
  int len = 0;
  const Byte *Buffer;
  const Byte *BufferLim;
  UInt32 Range;
  UInt32 Code;

  *inSizeProcessed = 0;

  *outSizeProcessed = 0;

  {
    UInt32 i;
    UInt32 numProbs =
        (((((((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
             (4 << 6)) +
            (1 << (14 >> 1)) - 14) +
           (1 << 4)) +
          (((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3)) + (1 << 8))) +
         (((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3)) + (1 << 8))) +
        ((UInt32)768 << (lc + vs->Properties.lp));
    for (i = 0; i < numProbs; i++)
      p[i] = (1 << 11) >> 1;
  }

  Buffer = inStream;
  BufferLim = inStream + inSize;
  Code = 0;
  Range = 0xFFFFFFFF;
  {
    int i;
    for (i = 0; i < 5; i++) {
      {
        if (Buffer == BufferLim)
          return 1;
      };
      Code = (Code << 8) | (*Buffer++);
    }
  };

  while (nowPos < outSize) {
    int posState = (int)((nowPos

                          )&posStateMask);

    UInt16 *prob = p + 0 + (state << 4) + posState;
    if (Range < ((UInt32)1 << 24)) {
      {
        if (Buffer == BufferLim)
          return 1;
      };
      Range <<= 8;
      Code = (Code << 8) | (*Buffer++);
    };
    UInt32 bound = (Range >> 11) * *(prob);
    int const m0 = Code < bound; if (m0) {
      int symbol = 1;
      Range = bound;
      *(prob) += ((1 << 11) - *(prob)) >> 5;
      debug_LzmaDecode(m0, Range, Code, prob, previousByte, rep0);
      prob =
          p +
          (((((((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
               (4 << 6)) +
              (1 << (14 >> 1)) - 14) +
             (1 << 4)) +
            (((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3)) +
             (1 << 8))) +
           (((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3)) + (1 << 8))) +
          (768 * ((((nowPos

                     )&literalPosMask)
                   << lc) +
                  (previousByte >> (8 - lc))));

      if (state >= 7) {
        int matchByte = outStream[nowPos - rep0];

        do {
          if (Range < ((UInt32)1 << 24)) {
            {
              if (Buffer == BufferLim)
                return 1;
            };
            Range <<= 8;
            Code = (Code << 8) | (*Buffer++);
          };
          matchByte <<= 1;
          int const bit = (matchByte & 0x100);
          UInt16 *const probLit = prob + 0x100 + bit + symbol;
          bound = (Range >> 11) * *(probLit);
          int const m1 = Code < bound; if (m1) {
            Range = bound;
            *(probLit) += ((1 << 11) - *(probLit)) >> 5;
            debug_LzmaDecode(m1, Range, Code, probLit, previousByte, rep0);
            ;
            symbol <<= 1;
            if (bit != 0)
              break;
          } else {
            Range -= bound;
            Code -= bound;
            *(probLit) -= (*(probLit)) >> 5;
            debug_LzmaDecode(m1, Range, Code, probLit, previousByte, rep0);
            ;
            symbol = (symbol + symbol) + 1;
            if (bit == 0)
              break;
          }
        } while (symbol < 0x100);
      }
      while (symbol < 0x100) {
        UInt16 *const probLit = prob + symbol;
        if (Range < ((UInt32)1 << 24)) {
          {
            if (Buffer == BufferLim)
              return 1;
          };
          Range <<= 8;
          Code = (Code << 8) | (*Buffer++);
        };
        bound = (Range >> 11) * *(probLit);
        int const m2 = Code < bound; if (m2) {
          Range = bound;
          *(probLit) += ((1 << 11) - *(probLit)) >> 5;
          ;
          symbol <<= 1;
          ;
          ;
        } else {
          Range -= bound;
          Code -= bound;
          *(probLit) -= (*(probLit)) >> 5;
          ;
          symbol = (symbol + symbol) + 1;
          ;
          ;
        }
        debug_LzmaDecode(m2, Range, Code, probLit, previousByte, rep0);
      }
      previousByte = (Byte)symbol;

      outStream[nowPos++] = previousByte;
      if (state < 4)
        state = 0;
      else if (state < 10)
        state -= 3;
      else
        state -= 6;
    } else {
      Range -= bound;
      Code -= bound;
      *(prob) -= (*(prob)) >> 5;
      debug_LzmaDecode(m0, Range, Code, prob, previousByte, rep0);
      ;
      prob = p + (0 + (12 << 4)) + state;
      if (Range < ((UInt32)1 << 24)) {
        {
          if (Buffer == BufferLim)
            return 1;
        };
        Range <<= 8;
        Code = (Code << 8) | (*Buffer++);
      };
      bound = (Range >> 11) * *(prob);
      int const m3 = Code < bound; if (m3) {
        Range = bound;
        *(prob) += ((1 << 11) - *(prob)) >> 5;
        ;
        debug_LzmaDecode(m3, Range, Code, prob, previousByte, rep0);
        rep3 = rep2;
        rep2 = rep1;
        rep1 = rep0;
        state = state < 7 ? 0 : 3;
        prob =
            p + (((((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
                   (4 << 6)) +
                  (1 << (14 >> 1)) - 14) +
                 (1 << 4));
      } else {
        Range -= bound;
        Code -= bound;
        *(prob) -= (*(prob)) >> 5;
        debug_LzmaDecode(m3, Range, Code, prob, previousByte, rep0);
        ;
        prob = p + ((0 + (12 << 4)) + 12) + state;
        if (Range < ((UInt32)1 << 24)) {
          {
            if (Buffer == BufferLim)
              return 1;
          };
          Range <<= 8;
          Code = (Code << 8) | (*Buffer++);
        };
        bound = (Range >> 11) * *(prob);
        int const m4 = Code < bound; if (m4) {
          Range = bound;
          *(prob) += ((1 << 11) - *(prob)) >> 5;
          debug_LzmaDecode(m4, Range, Code, prob, previousByte, rep0);
          ;
          prob = p + (((((0 + (12 << 4)) + 12) + 12) + 12) + 12) +
                 (state << 4) + posState;
          if (Range < ((UInt32)1 << 24)) {
            {
              if (Buffer == BufferLim)
                return 1;
            };
            Range <<= 8;
            Code = (Code << 8) | (*Buffer++);
          };
          bound = (Range >> 11) * *(prob);
          int const m5 = Code < bound; if (m5) {
            Range = bound;
            *(prob) += ((1 << 11) - *(prob)) >> 5;
            ;

            if (nowPos == 0)

              return 1;

            state = state < 7 ? 9 : 11;
            previousByte = outStream[nowPos - rep0];

            outStream[nowPos++] = previousByte;

            debug_LzmaDecode(m5, Range, Code, prob, previousByte, rep0);
            continue;
          } else {
            Range -= bound;
            Code -= bound;
            *(prob) -= (*(prob)) >> 5;
            debug_LzmaDecode(m5, Range, Code, prob, previousByte, rep0);
            ;
          }
        } else {
          UInt32 distance;
          Range -= bound;
          Code -= bound;
          *(prob) -= (*(prob)) >> 5;
          debug_LzmaDecode(m4, Range, Code, prob, previousByte, rep0);
          ;
          prob = p + (((0 + (12 << 4)) + 12) + 12) + state;
          if (Range < ((UInt32)1 << 24)) {
            {
              if (Buffer == BufferLim)
                return 1;
            };
            Range <<= 8;
            Code = (Code << 8) | (*Buffer++);
          };
          bound = (Range >> 11) * *(prob);
          int const m6 = Code < bound; if (m6) {
            Range = bound;
            *(prob) += ((1 << 11) - *(prob)) >> 5;
            debug_LzmaDecode(m6, Range, Code, prob, previousByte, rep0);
            ;
            distance = rep1;
          } else {
            Range -= bound;
            Code -= bound;
            *(prob) -= (*(prob)) >> 5;
            debug_LzmaDecode(m6, Range, Code, prob, previousByte, rep0);
            ;
            prob = p + ((((0 + (12 << 4)) + 12) + 12) + 12) + state;
            if (Range < ((UInt32)1 << 24)) {
              {
                if (Buffer == BufferLim)
                  return 1;
              };
              Range <<= 8;
              Code = (Code << 8) | (*Buffer++);
            };
            bound = (Range >> 11) * *(prob);
            int const m7 =Code < bound; if (m7) {
              Range = bound;
              *(prob) += ((1 << 11) - *(prob)) >> 5;
              ;
              distance = rep2;
            } else {
              Range -= bound;
              Code -= bound;
              *(prob) -= (*(prob)) >> 5;
              ;
              distance = rep3;
              rep3 = rep2;
            }
            debug_LzmaDecode(m7, Range, Code, prob, previousByte, rep0);
            rep2 = rep1;
          }
          rep1 = rep0;
          rep0 = distance;
        }
        state = state < 7 ? 8 : 11;
        prob =
            p + ((((((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
                    (4 << 6)) +
                   (1 << (14 >> 1)) - 14) +
                  (1 << 4)) +
                 (((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3)) +
                  (1 << 8)));
      }
      {
        int numBits, offset;
        UInt16 *probLen = prob + 0;
        if (Range < ((UInt32)1 << 24)) {
          {
            if (Buffer == BufferLim)
              return 1;
          };
          Range <<= 8;
          Code = (Code << 8) | (*Buffer++);
        };
        bound = (Range >> 11) * *(probLen);
        int const m8 =Code < bound; if (m8) {
          Range = bound;
          *(probLen) += ((1 << 11) - *(probLen)) >> 5;
          debug_LzmaDecode(m8, Range, Code, probLen, previousByte, rep0);
          ;
          probLen = prob + ((0 + 1) + 1) + (posState << 3);
          offset = 0;
          numBits = 3;
        } else {
          Range -= bound;
          Code -= bound;
          *(probLen) -= (*(probLen)) >> 5;
          debug_LzmaDecode(m8, Range, Code, probLen, previousByte, rep0);
          ;
          probLen = prob + (0 + 1);
          if (Range < ((UInt32)1 << 24)) {
            {
              if (Buffer == BufferLim)
                return 1;
            };
            Range <<= 8;
            Code = (Code << 8) | (*Buffer++);
          };
          bound = (Range >> 11) * *(probLen);
          int const m9 = Code < bound; if (m9) {
            Range = bound;
            *(probLen) += ((1 << 11) - *(probLen)) >> 5;
            debug_LzmaDecode(m9, Range, Code, probLen, previousByte, rep0);
            ;
            probLen =
                prob + (((0 + 1) + 1) + ((1 << 4) << 3)) + (posState << 3);
            offset = (1 << 3);
            numBits = 3;
          } else {
            Range -= bound;
            Code -= bound;
            *(probLen) -= (*(probLen)) >> 5;
            debug_LzmaDecode(m9, Range, Code, probLen, previousByte, rep0);
            ;
            probLen =
                prob + ((((0 + 1) + 1) + ((1 << 4) << 3)) + ((1 << 4) << 3));
            offset = (1 << 3) + (1 << 3);
            numBits = 8;
          }
        }
        {
          int i = numBits;
          len = 1;
          do {
            UInt16 *const p = probLen + len;
            if (Range < ((UInt32)1 << 24)) {
              {
                if (Buffer == BufferLim)
                  return 1;
              };
              Range <<= 8;
              Code = (Code << 8) | (*Buffer++);
            };
            bound = (Range >> 11) * *(p);
            int const m10 = Code < bound; if (m10) {
              Range = bound;
              *(p) += ((1 << 11) - *(p)) >> 5;
              ;
              len <<= 1;
              ;
              ;
            } else {
              Range -= bound;
              Code -= bound;
              *(p) -= (*(p)) >> 5;
              ;
              len = (len + len) + 1;
              ;
              ;
            }
            debug_LzmaDecode(m10, Range, Code, p, previousByte, rep0);
          } while (--i != 0);
          len -= (1 << numBits);
        };
        len += offset;
      }

      if (state < 4) {
        int posSlot;
        state += 7;
        prob = p + ((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
               ((len < 4 ? len : 4 - 1) << 6);
        {
          int i = 6;
          posSlot = 1;
          do {
            UInt16 *const p = prob + posSlot;
            if (Range < ((UInt32)1 << 24)) {
              {
                if (Buffer == BufferLim)
                  return 1;
              };
              Range <<= 8;
              Code = (Code << 8) | (*Buffer++);
            };
            bound = (Range >> 11) * *(p);
            int const m11 = Code < bound; if (m11) {
              Range = bound;
              *(p) += ((1 << 11) - *(p)) >> 5;
              ;
              posSlot <<= 1;
              ;
              ;
            } else {
              Range -= bound;
              Code -= bound;
              *(p) -= (*(p)) >> 5;
              ;
              posSlot = (posSlot + posSlot) + 1;
              ;
              ;
            }
            debug_LzmaDecode(m11, Range, Code, p, previousByte, rep0);
          } while (--i != 0);
          posSlot -= (1 << 6);
        };
        if (posSlot >= 4) {
          int numDirectBits = ((posSlot >> 1) - 1);
          rep0 = (2 | ((UInt32)posSlot & 1));
          if (posSlot < 14) {
            rep0 <<= numDirectBits;
            prob = p +
                   (((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
                    (4 << 6)) +
                   rep0 - posSlot - 1;
          } else {
            numDirectBits -= 4;
            do {
              if (Range < ((UInt32)1 << 24)) {
                {
                  if (Buffer == BufferLim)
                    return 1;
                };
                Range <<= 8;
                Code = (Code << 8) | (*Buffer++);
              }
              Range >>= 1;
              rep0 <<= 1;
              if (Code >= Range) {
                Code -= Range;
                rep0 |= 1;
              }
            } while (--numDirectBits != 0);
            prob = p +
                   ((((((((0 + (12 << 4)) + 12) + 12) + 12) + 12) + (12 << 4)) +
                     (4 << 6)) +
                    (1 << (14 >> 1)) - 14);
            rep0 <<= 4;
            numDirectBits = 4;
          }
          {
            int i = 1;
            int mi = 1;
            do {
              UInt16 *const prob3 = prob + mi;
              if (Range < ((UInt32)1 << 24)) {
                {
                  if (Buffer == BufferLim)
                    return 1;
                };
                Range <<= 8;
                Code = (Code << 8) | (*Buffer++);
              };
              bound = (Range >> 11) * *(prob3);
              int const m12 = Code < bound; if (m12) {
                Range = bound;
                *(prob3) += ((1 << 11) - *(prob3)) >> 5;
                ;
                mi <<= 1;
                ;
                ;
              } else {
                Range -= bound;
                Code -= bound;
                *(prob3) -= (*(prob3)) >> 5;
                ;
                mi = (mi + mi) + 1;
                rep0 |= i;
              };
              debug_LzmaDecode(m12, Range, Code, prob3, previousByte, rep0);
              i <<= 1;
            } while (--numDirectBits != 0);
          }
        } else
          rep0 = posSlot;
        if (++rep0 == (UInt32)(0)) {

          len = (-1);
          break;
        }
      }

      len += 2;

      if (rep0 > nowPos)

        return 1;
      do {
        previousByte = outStream[nowPos - rep0];

        len--;
        outStream[nowPos++] = previousByte;
      } while (len != 0 && nowPos < outSize);
    }
  }
  if (Range < ((UInt32)1 << 24)) {
    {
      if (Buffer == BufferLim)
        return 1;
    };
    Range <<= 8;
    Code = (Code << 8) | (*Buffer++);
  };
  *inSizeProcessed = (SizeT)(Buffer - inStream);

  *outSizeProcessed = nowPos;
  return 0;
}
