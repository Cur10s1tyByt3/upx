/*  amd64-linux.elf-entry.S -- Linux program entry point & decompressor (Elf binary)
*
*  This file is part of the UPX executable compressor.
*
*  Copyright (C) 1996-2025 Markus Franz Xaver Johannes Oberhumer
*  Copyright (C) 1996-2025 Laszlo Molnar
*  Copyright (C) 2000-2025 John F. Reiser
*  All Rights Reserved.
*
*  UPX and the UCL library are free software; you can redistribute them
*  and/or modify them under the terms of the GNU General Public License as
*  published by the Free Software Foundation; either version 2 of
*  the License, or (at your option) any later version.
*
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with this program; see the file COPYING.
*  If not, write to the Free Software Foundation, Inc.,
*  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*
*  Markus F.X.J. Oberhumer              Laszlo Molnar
*  <markus@oberhumer.com>               <ezerotven+github@gmail.com>
*
*  John F. Reiser
*  <jreiser@users.sourceforge.net>
*/

#include "arch/amd64/macros.S"
#include "arch/amd64/regs.h"
NBPW= 8
.macro          jmps    target
                .byte   0xeb, \target - . - 1
.endm

/* These from /usr/include/unistd_64.h */
__NR_memfd_create= 319  // 0x13f
__NR_ftruncate= 77
__NR_exit=     60
__NR_mprotect= 10
__NR_mmap=      9
__NR_msync=    26  // 0x1a
__NR_close=     3
__NR_open=      2
__NR_write=     1

sz_Ehdr= 64
e_phnum= 56
sz_Phdr= 56

sz_l_info= 12
  l_lsize= 8

sz_p_info= 12

sz_b_info= 12
  sz_unc= 0
  sz_cpr= 4
  b_method= 8

AT_PAGESZ= 6

PROT_READ=  1
PROT_WRITE= 2
PROT_EXEC=  4

MAP_SHARED=  1
MAP_PRIVATE= 2
MAP_FIXED=     0x10
MAP_ANONYMOUS= 0x20

MFD_EXEC= 0x0010

SYS_mmap= 9  // 64-bit mode only!

FD_stderr= 2

M_NRV2B_LE32=2  // ../conf.h
M_NRV2D_LE32=5
M_NRV2E_LE32=8


// https://www.uclibc.org/docs/psABI-x86_64.pdf
  section ELFMAINX
sz_pack2= .-4
_start: .globl _start
        endbr64
////    nop; int3  # uncomment for debugging

        pop %rcx  // argc
        push %rsp; pop %rdi  // argv
        push %rcx  // argc
        push %rdx  // param for atexit()

// install SIGSEGV handler for debugging
SIGSEGV= 11
SA_SIGINFO= 4  // /usr/include/bits/sigaction.h
SA_RESTORER= 0x04000000
__NR_rt_sigaction= 13  // /usr/include/asm/unistd_64.h
        push %rdi  // save reg
        sub %edx,%edx  // arg3= 0 ==> do not save old sigaction
        push %rdx  // .sa_mask: 64 bits (8 bytes) of flags for signals
        lea __restore_rt(%rip),%rax; push %rax  // .sa_restorer
        push $SA_RESTORER | SA_SIGINFO  // .sa_flags
        lea sigsegv_sigaction(%rip),%rax; push %rax  // .sa_sigaction
        push %rsp; pop %rsi  // arg2= &new struct sigaction
        push $SIGSEGV; pop %rdi  // arg1= signum
        push $8; pop %r10  // sys4= sizeof(__sigset_t) ==> 64 bits
        push $__NR_rt_sigaction; pop %rax; syscall
        add $(3 + 1) * NBPW,%rsp  // toss struct sigaction
        pop %rdi  // restore reg

#define old_sp %rbp
F_FRAME= 7*NBPW
F_ENTR= 6*NBPW; F_PMASK= F_ENTR
F_RDX=  5*NBPW
F_LENU= 4*NBPW
F_ADRU= 3*NBPW
F_ELFA= 2*NBPW
F_LENX= 1*NBPW
F_ADRX= 0*NBPW

D_FOLD=  1*NBPW  // .data space at start of unfold
D_PMASK= 0*NBPW

// find auxv
        xor %eax,%eax  // 0
0:      scasq; jne 0b;  // skip argv
0:      scasq; jne 0b;  // skip env

// find AT_PAGESZ in auxv
        push %rdi; mov $0x1000,%edx  // default PAGE_SIZE
        pop %rsi
1:
        lodsq; test %eax,%eax; je 2f
        cmp $AT_PAGESZ,%eax; lodsq; jne 1b
        xchg %eax,%edx
2:
        pop %rax  // atexit
        neg %rdx  // PAGE_MASK
        push %rdx  // F_PMASK
        push %rax  // atexit,pmask,argc


#define arg2l esi
#define arg3l edx
// Create anonymous temporary file on mfd; like upxfd_create
        push $'u'|('p'<<8)|('X'<<16)|(0<<24)  // MATCH_22
        push %rsp; pop %arg1  // "upX"
        push $MFD_EXEC; pop %arg2
0: // try memfd_create
        movl $__NR_memfd_create,%eax; syscall
        test %eax,%eax; jns ok_memfd  // success
        test %arg2l,%arg2l; jz no_memfd  // memfd_create failed twice
        xor %arg2l,%arg2l; jmp 0b  // try again without MFD_EXEC
no_memfd:  // so try /dev/shm
O_RDWR= 2
O_DIRECTORY= 0200000  // 0x010000
O_TMPFILE= 020000000  // 0x400000
        lea shm_param(%rip),%rsi
        lodsl;            xchg %eax,%arg3l
        lodsl; push %rsi; xchg %eax,%arg2l
               pop %arg1
        push $__NR_open; pop %rax; call sys_check
ok_memfd:
        mov %rax,%r12  // mfd
        pop %rcx  // MATCH_22  discard "upx"

        lea sz_pack2(%rip),%rdi
        mov (%rdi),%ecx  // sz_pack2: length before stub
        sub %rcx,%rdi  // elfaddr
        lea o_binfo(%rip),%rsi
        lodsl; xchg %eax,%ebx; mov %ebx,%r13d  // O_BINFO; advance to &b_info
INSURANCE= 0x10
        lodsl; xchg %eax,%edx
        add $INSURANCE,%edx; push %rdx  // F_LENU = sz_unc + x86_overrun + insurance
        push $-1  // space for F_ADRU
        push %rdi  // F_ELFA
        sub %rbx,%rcx; push %rcx  // F_LENX = sz_pack2 - O_BINFO
        add %rdi,%rbx; push %rbx  // F_ADRX =  elfaddr + O_BINFO

        push %rsp; pop old_sp
// alloca()
        sub %rdx,%rsp  // F_LENU space
CACHELINE= 8 * NBPW
        and $-CACHELINE,%rsp  // align

// Decompress the rest of this loader, and jump to it.

#define dst  %rdi
#define src  %rsi
#define lsrc %rcx
        push %rsp; pop dst  // dst= decompress onto stack
        lodsl; push %rax  // MATCH_11  .sz_cpr
        lodsl; cmpw $M_NRV2B_LE32|(0<<8),%ax; je 0f; hlt; 0:  // check method and filter bytes
        pop %rax; add src,%rax; push %rax  // MATCH_11  input_eof
        push old_sp  // MATCH_10


// This is nrv2b_d32, inlined and optimized for small space (about 160 bytes).
// The task is to de-compress the folded pieces for shared library init:
// the de-compressor(s) of the PT_LOAD pieces, and the C-code supervisor
// which adjusts the placement and mapping of the address space.
// The output length is a couple KB for NRV, a few KB for Lzma, 64KB for Zstd.
// This is motivated by the possibility of using multiple de-compressors
// depending on the characteristics of each PT_LOAD, and by the increased size
// and compressability of C-coded de-compressors for Lzma and Zstd
// in contrast to the simple and small assembly-coded NRV.

//%rsp:
//  MATCH_10  old_sp
//  MATCH_11  &input_eof

//%rbp  === old_sp:  array of F_FRAME

/* Working registers */
#define off  %eax  /* XXX: 2GB */
#define bits %ebx
#define len  %ecx  /* XXX: 2GB */
#define lenq %rcx
#define dispq %rbp
#define displ %ebp

#define GETBIT call *%rdx
#define jnextb0 GETBIT; jnc
#define jnextb1 GETBIT; jc

/* rotate next bit into bottom bit of reg */
#define getnextb(reg) GETBIT; adcl reg,reg

        xor bits,bits  // empty; force refill
        xor len,len  // create loop invariant
        lea getbit(%rip),%rdx
        push $-1; pop dispq  // initial displacement
        cld  // paranoia
        .byte 0xa8  // "testb $... ,%al" ==> "jmp top_n2b"
lit_n2b:
        movsb  // *dst++ = *src++;
top_n2b:
        jnextb1 lit_n2b
        lea 1(lenq),off  # [len= 0] off= 1
offmore_n2b:
        getnextb(off)
        jnextb0 offmore_n2b

        subl $ 3,off; jc len_n2b  # use previous offset
        shll $ 8,off; lodsb  # off is %eax, so 'lodsb' is "off |= *src++;"
        xorl $~0,off; jz eof_n2b
        movslq off,dispq  # XXX: 2GB; (note propagation of negative sign!)
// for 4GB, replace the 'movslq' with:
//      pushq $~0  # 64 bits all '1'
//      movl off,(%rsp)  # replace lo-order 32 bits
//      popq dispq
len_n2b:
        lea 1(lenq),off  # [len= 0] off= 1
        getnextb(len); getnextb(len)  # two bits; cc set on result
        jnz gotlen_n2b  # raw 1,2,3 ==> 2,3,4
        movl off,len  # len= 1, the msb
        addl $3-1,off  # raw 2.. ==> 5..
lenmore_n2b:
        getnextb(len)
        jnextb0 lenmore_n2b
gotlen_n2b:
        cmpl $-0xd00,displ  # XXX: 2GB;  for 4GB: use 'cmpq'
        adcl off,len  # len += off + (disp < -0xd00)

        push %rsi  // MATCH_06
          lea (%rdi,dispq),%rsi
          rep; movsb
        pop %rsi  // MATCH_06

        jmp top_n2b

eof_n2b:
        pop old_sp   // MATCH_10
        pop %rcx  // MATCH_11  &input_eof
        cmp %rcx,%rsi; je 0f; hlt; 0:  // test for ending in correct place
        //FIXME: check dst, too

// Write de-compressed 'fold' to file
        mov F_PMASK(old_sp),%rax; mov %rax,/*D_PMASK*/(%rsp)  // propagate PAGE_MASK
        mov F_LENU(old_sp),%arg3  // LENU
        sub $INSURANCE,%arg3  // memcheck limit
        push %rsp; pop %arg2  // buffer
        mov %r12,%arg1  // mfd
        push %arg3  // MATCH_21  save LENU
0:  // /dev/shm might be restricted to 8KiB at a time!
        push $__NR_write; pop %rax; call sys_check
        add %rax,%arg2  // advance ptr
        sub %eax,%arg3l; jnz 0b  // decrement count
        pop %arg2  // MATCH_21 restore LENU to mmap.len
// de-alloca()
        push old_sp; pop %rsp

// Map unfolded code the SELinux way
        xor %arg6,%arg6  // 0  offset
        mov %r12,%arg5  // mfd
        push $MAP_SHARED; pop %sys4
        push $PROT_READ|PROT_EXEC; pop %arg3  // FIXME: add PROT_WRITE for DEBUG only
        subl %edi,%edi  // (%arg1)dst = 0;  // kernel chooses addr
        push $__NR_mmap; pop %rax; call sys_check
        push %rax  // MATCH_12
        mov %rax,F_ADRU(old_sp)

        push %arg5; pop %arg1  // mfd
        push $__NR_close; pop %rax; syscall

// Use the copy.
        pop %rax  // MATCH_12  ADRU
        add $D_FOLD,%rax  // beyond .data
        jmp *%rax  // goto unfolded stub

__NR_rt_sigreturn= 15
        .balign 16
__restore_rt:
        endbr64
        mov $__NR_rt_sigreturn,%eax
        syscall

        .balign 16
sigsegv_sigaction:
        endbr64
__NR_fork= 57
        push $__NR_fork; pop %rax; call sys_check
        test %eax,%eax; je child
parent:
        jmp parent  // spin; paused by gdb

proc_self_cmdline:
        .asciz "/proc/self/cmdline"
minus_q:
        .asciz "-q"
path_gdb:
        .asciz "/usr/bin/gdb"
commands_gdb:
        .ascii "info inferiors\n"
        .ascii "bt\n"
        .ascii "up\n"
        .ascii "x/i $pc\n"
        .ascii "x/24i $pc-0x20\n",
        .ascii "info reg\n"
        .ascii "kill\n"
        .ascii "quit 1"
        .byte 0
commands_gdb_end:

unsimal:  // (dst, value)
        push $10; pop %rcx  // radix
        mov %esi,%eax  // value
        call 0f
        movb $0,(%rdi)  // terminator
        ret
0:
        xor %edx,%edx; div %ecx; push %rdx  // eax= quo(%edx:%eax / %ecx); edx= rem
        // 'div' undefines all flags!
        test %eax,%eax; je 1f; call 0b
1:
        pop %rax; add $'0',%eax
        stosb
        ret

child:
PATH_MAX= 4096
        sub $PATH_MAX,%rsp
        lea proc_self_cmdline(%rip),%arg1
O_RDONLY= 0
        push $O_RDONLY; pop %arg2
        push $__NR_open; pop %rax; call sys_check
        push %rax; pop %arg1  // fd
        push %rsp; pop %arg2  // buffer
        push $PATH_MAX; pop %arg3
__NR_read= 0
        push $__NR_read; pop %rax; call sys_check
        push $__NR_close; pop %eax; call sys_check

__NR_getppid= 110
        push $__NR_getppid; pop %eax; syscall
        push %rax; pop %rsi
        xor %eax,%eax; push %rax; push %rax  // decimal(pid) fits in 16 bytes
        push %rsp; pop %rdi; call unsimal
// argv
        push %rsp; pop %rsi  // fence post: &pid.unsimal
        push $0  // argv[4]
        push %rsi  // arg3 pid
        add $16,%rsi; push %rsi  // arg2 exename
        lea minus_q(%rip),%rax; push %rax  // arg1 "-q"
        add $(path_gdb - minus_q),%rax; push %rax  // arg[0] "/usr/bin/gdb"

        xor %edi,%edi; push $__NR_close; pop %rax; syscall
        push %rax; push %rsp; pop %rdi  // &fd_pipe[2]; 4 bytes each
__NR_pipe= 22
        push $__NR_pipe; pop %rax; call sys_check
        pop %rdi; shr $32,%rdi  // arg1  write side of pipe

        push $commands_gdb_end - commands_gdb; pop %arg3
        lea commands_gdb(%rip),%arg2
__NR_write= 1
        push $__NR_write; pop %rax; call sys_check
        push $__NR_close; pop %rax; syscall

        push $0; pop %arg3  // _environ  BUG
        push %rsp; pop %arg2  // argv
        movq (%arg2),%arg1  // "/usr/bin/gdb"
__NR_execve= 59
        push $__NR_execve; pop %rax; call sys_check
        hlt

sys_check:
        push %rax  // save __NR_ for debug
        syscall
        pop %rcx  // recover __NR_ for debug
        cmp $-1<<12,%rax; jb 0f; hlt; 0:
        ret

shm_param:
        .int 0700, O_RDWR|O_DIRECTORY|O_TMPFILE; .asciz "/dev/shm"

getbit:
        endbr64  // from "call *%rdx"
        addl bits,bits; jz refill  // Carry= next bit
        rep; ret
refill:
        movl (%rsi),bits; subq $-4,%rsi  // next 32 bits; set Carry
        adcl bits,bits  // LSB= 1 (CarryIn); CarryOut= next bit
        rep; ret

        // IDENTSTR goes here

  section ELFMAINZ
        .balign 4
o_binfo:
        .long O_BINFO  // offset of b_info for .text | is_ptinerp | unmap_all_pages
FOLD:
        // { b_info={sz_unc, sz_cpr, {4 char}}, folded_loader...}

/*__XTHEENDX__*/

/* vim:set ts=8 sw=8 et: */
