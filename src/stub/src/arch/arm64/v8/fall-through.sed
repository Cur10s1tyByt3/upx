# Take the compiler-generated assembly code for subroutine LzmaDecode(),
# and edit it to become a fall-through block.
# The exit epilog:
#   ldp x19, x20, [sp]
#   ldp x21, x22, [sp,16]
#   ldp x23, x24, [sp,32]
#   ldp x25, x26, [sp,48]
#   ldp x27, x28, [sp,64]
#   add sp, sp, 80
#   ret
# might appear twice, and in the middle of the code.
# Move it to the end, delete the 'ret',
# and 'jmp' to the moved epilog.
/ldp\tx19, x20, \[sp]/{
    h
    c \
    b Exit_LzmaDecode
}
/ldp\tx21, x22, \[sp,16]/,/add\tsp, sp, 80/{
    H
    d
}
/ret$/d
/\.size\tLzmaDecode, \.-LzmaDecode/{
    H
    i \
Exit_LzmaDecode:
    g
}
