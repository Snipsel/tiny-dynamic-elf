PT_LOAD    =  1
PT_DYNAMIC =  2
PT_INTERP  =  3
PF_RO      =  4
PF_RW      =  6
PF_RX      =  5
DT_NEEDED  =  1
DT_STRTAB  =  5
DT_SYMTAB  =  6
DT_STRSZ   = 10
DT_SYMENT  = 11
DT_RELA    =  7
DT_RELASZ  =  8
DT_RELAENT =  9
DT_NULL    =  0
ET_EXEC    =  2
ET_X86_64  = 62

elf64.ehdr:
db 0x7F, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
dw ET_EXEC
dw ET_X86_64
dd 1
dq _start
dq elf64.phdr - $$
dq 0
dd 0
dw elf64.ehdr.len
dw elf64.phdr.entry_len
dw elf64.phdr.len/elf64.phdr.entry_len
dw 0, 0, 0
.len=$-elf64.ehdr


elf64.phdr:
dd PT_INTERP
dd PF_RO
dq elf64.interp - $$
dq elf64.interp, 0
dq elf64.interp.len, elf64.interp.len
dq 1
.entry_len=$-elf64.phdr

dd PT_DYNAMIC
dd PF_RO
dq elf64.dynamic - $$
dq elf64.dynamic, 0
dq elf64.dynamic.len, elf64.dynamic.len
dq 8

dd PT_LOAD
dd PF_RX
dq elf64.ehdr - $$
dq $$, 0
dq FILE.len, FILE.len
dq PAGE_SIZE

dd PT_LOAD
dd PF_RW
dq bss - $$
dq bss, 0
dq 0, bss.len
dq PAGE_SIZE
.len=$-elf64.phdr

align 8
elf64.dynamic:
dq DT_NEEDED,  elf64.strtab.libc
dq DT_STRTAB,  elf64.strtab
dq DT_SYMTAB,  elf64.symtab
dq DT_STRSZ,   elf64.strtab.len
dq DT_SYMENT,  24
dq DT_RELA,    elf64.rela
dq DT_RELASZ,  elf64.rela.len
dq DT_RELAENT, 24
dq DT_NULL,     0
.len=$-elf64.dynamic

align 4
elf64.symtab:
.null=($-elf64.symtab)/24
    rb 24
.printf=($-elf64.symtab)/24
    dd elf64.strtab.printf  ; strtab_index
    db 1 shl 4 + 2          ; info=GLOBAL,STT_FUNCTION
    db 0                    ; other
    dw 0                    ; shndx=SHN_UNDEF
    dq 0, 0                 ; value=unknown,size=unknown
.len=$-elf64.symtab

align 8
elf64.rela:
.printf:
    dq printf                         ;reloc addess
    dq elf64.symtab.printf shl 32 + 1 ;symtab_index << 32 + type
    dq 0                              ;addend
.len=$-elf64.rela

elf64.interp:
    db "/lib64/ld-linux-x86-64.so.2",0
.len=$-elf64.interp

elf64.strtab:
.null=$-elf64.strtab
    db 0
.libc=$-elf64.strtab
    db "libc.so.6", 0
.printf=$-elf64.strtab
    db "printf", 0
.len=$-elf64.strtab

