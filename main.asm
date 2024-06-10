use64
BASE=0x10000
OFFSETOF equ -BASE+
ELF64_PHEADER_ENTRY_SIZE = 56
org BASE

PAGE_ALIGN = 0x1000
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

Elf64_EHdr:
db 0x7F, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
dw ET_EXEC
dw ET_X86_64
dd 1
dq _start
dq OFFSETOF Elf64_PHdr                                   
dq 0
dd 0
dw Elf64_EHdr.len
dw ELF64_PHEADER_ENTRY_SIZE
dw Elf64_PHdr.len/ELF64_PHEADER_ENTRY_SIZE
dw 0, 0, 0
.len=$-Elf64_EHdr


Elf64_PHdr:
dd PT_INTERP
dd PF_RO
dq OFFSETOF interp                           
dq interp, 0
dq interp.len, interp.len
dq 1

dd PT_DYNAMIC
dd PF_RO
dq OFFSETOF dynamic
dq dynamic, 0
dq dynamic.len, dynamic.len
dq 8

dd PT_LOAD
dd PF_RX
dq OFFSETOF Elf64_EHdr
dq BASE, 0
dq FILE.len, FILE.len
dq PAGE_ALIGN

dd PT_LOAD
dd PF_RW
dq OFFSETOF bss
dq bss, 0
dq 0, bss.len
dq PAGE_ALIGN
.len=$-Elf64_PHdr

align 8
dynamic:
dq DT_NEEDED,  strtab.libc
dq DT_STRTAB,  strtab
dq DT_SYMTAB,  symtab
dq DT_STRSZ,   strtab.len
dq DT_SYMENT,  24
dq DT_RELA,    rela
dq DT_RELASZ,  rela.len
dq DT_RELAENT, 24
dq DT_NULL,     0
.len=$-dynamic

align 4
symtab:
.null=($-symtab)/24
    rb 24
.printf=($-symtab)/24
    dd strtab.printf      ;strtab_index
    db 1 shl 4 + 2          ;info=GLOBAL,STT_FUNCTION
    db 0                    ;other
    dw 0                    ;shndx=SHN_UNDEF
    dq 0, 0                 ;value=unknown,size=unknown
.getenv=($-symtab)/24
    dd strtab.getenv      ;strtab_index
    db 1 shl 4 + 2          ;info=GLOBAL,STT_FUNCTION
    db 0                    ;other
    dw 0                    ;shndx=SHN_UNDEF
    dq 0, 0                 ;value=unknown,size=unknown
.len=$-symtab

align 8
rela:
.printf:
    dq printf                             ;reloc addess
    dq symtab.printf shl 32 + 1           ;symtab_index shl 32 + type
    dq 0                                    ;addend
.getenv:
    dq getenv                             ;reloc addess
    dq symtab.getenv shl 32 + 1           ;symtab_index shl 32 + type
    dq 0                                    ;addend
.len=$-rela

align 8
iov1 dq con_req, con_req_len
iov2 dq stat, 16

align 8
ro.start:
ro.x11createwin:
.op          db        1
.depth       db        0
.size        dw        8
.window      dd        0
.win_parent  dd        0
.x           dw        0
.y           dw        0
.w           dw     1920
.h           dw     1080
.border      dw        0
.group       dw        1 ; window class input-output
.visual      dd        0
.value_mask  dd        0
;0x0900 ; backing_pixel=0x0100 | event_mask=0x0800
; .back_pixel  dd 0x2233FF
; .event_mask  dd        0
.len = $-ro.x11createwin
ro.x11mapwindow:
.op          dw        8
.size        dw        2
.window      dd        0
.len = $-ro.x11mapwindow
ro.len = $-ro.start

interp db "/lib64/ld-linux-x86-64.so.2",0
.len=$-interp


strtab:
.null=$-strtab
    db 0
.libc=$-strtab
    db "libc.so.6", 0
.printf=$-strtab
    db "printf", 0
.getenv=$-strtab
    db "getenv", 0
.len=$-strtab

con_req  db "l",0,11,0,0,0,18,0,16,0,0,0,"MIT-MAGIC-COOKIE-1",0,0
con_req_len = $-con_req

sockaddr db 1,0,"/tmp/.X11-unix/X0",0

sockaddr_len = $-sockaddr
msg db "offset = %d", 10, 0
msg_exit db "exit %lu cy", 10, 0
xauth db "XAUTHORITY",0

; ccall:
; int args:   rdi, rsi, rdx, rcx, r8, r9
; float args: xmm0-7
SYS_EXIT    = 60
SYS_OPEN    =  2
SYS_CLOSE   =  3
SYS_FSTAT   =  5
SYS_READ    =  0
SYS_PREAD   = 17
SYS_SOCKET  = 41
SYS_CONNECT = 42
SYS_WRITE   =  1
SYS_WRITEV  = 20
AF_UNIX     =  1
SOCK_STREAM =  1

_start:
    ; mark entry timestamp
    rdtsc
    lfence
    mov dword [timestamp_start],   eax
    mov dword [timestamp_start+4], edx

    ; copy ro data into rw segment
    mov     ecx, ro.len
    mov     esi, ro.start
    mov     edi, rw.start
    rep movsb

    ; read get XAUTHORITY
    mov     rdi, xauth
    call    [getenv]
    test    eax, eax
    jna     err_getenv

    ; open the xauthority file
    mov     rdi, rax ; filename
    xor     esi, esi ; flags
    xor     edx, edx ; mode
    mov     eax, SYS_OPEN
    syscall
    test    eax, eax
    jna     err_open

    ; get its size
    mov     edi, eax  ; fd
    mov     esi, stat ; statbuf
    mov     eax, SYS_FSTAT
    syscall
    test    eax, eax
    js      err_stat
    
    ; read final 16 bytes for the key
    mov     rdx, 16
    mov     r10, [stat.len] 
    sub     r10, rdx
    mov     eax, SYS_PREAD ; re-use edi and esi from last syscall
    syscall
    test    eax, eax
    js      err_pread

    ; close xauthority
    mov     rax, SYS_CLOSE
    syscall

    ; create socket
    mov     rdi, AF_UNIX
    mov     rsi, SOCK_STREAM
    xor     edx, edx
    mov     eax, SYS_SOCKET
    syscall
    test    eax, eax
    js      err_socket

    ; connect
    mov     edi, eax
    mov     esi, sockaddr
    mov     edx, sockaddr_len
    mov     eax, SYS_CONNECT
    syscall
    test    eax, eax
    jnz     err_connect

    ; write handshake
    mov     esi, iov1
    mov     edx, 2
    mov     eax, SYS_WRITEV
    syscall
    test    eax, eax
    js      err_handshake_writev

    ; read initial message
    mov     edx, bss.len-(stat-bss)
    mov     esi, stat
    xor     eax, eax
    syscall
    test    eax, eax
    js      err_handshake_read

    ; TODO: check status, now just assuming it succeeds

    ; save message length
    mov     r13, rax 

    ; find the location of the root array
    movzx   edx, WORD [esi+24] ; vendor string length
    movzx   ecx, BYTE [esi+29] ; format count
    lea     esi, [edx+40]      ; format offset = vendor string length + size of X11ConSetup
    lea     esi, [esi+ecx*8]   ; root offset   = format_offset + format count * format size

    ; generate window id
    mov     eax, [stat+12] ; setup.id_base
    mov     ecx, [stat+16] ; setup.id_mask
    not     ecx
    and     eax, ecx

    ; write window id to the required places
    mov     [x11createwin.window], eax
    mov     [x11mapwindow.window], eax

    ; set the root[0].window_id
    mov eax, [esi+stat]    
    mov [x11createwin.win_parent], eax

    ; root[0].visual_id
    mov     eax, [esi+32+stat] 
    mov     [x11createwin.visual], eax

    ; write window request struct
    mov     rdx, ro.len
    mov     rsi, x11createwin
    mov     rax, SYS_WRITE
    syscall

    ; restore message length
    mov     rsi, r13

    ; read window request response
    mov     rdx, (bss+bss.len)
    sub     rdx, rsi
    add     rsi, stat
    mov     rax, SYS_READ
    syscall

    ; hang for now
read_loop:
    mov     rdx, 4096
    add     rsi, stat
    mov     rax, SYS_READ
    syscall

exit_success:
    ; read out cycle counter
    lfence
    rdtsc
    lfence
    mov     esi, edx
    shl     rsi, 32
    or      rsi, rax
    sub     rsi, [timestamp_start]
    mov     edi, msg_exit
    call    [printf]

    xor     edi, edi
    jmp exit_edi
err_getenv:
    mov     dil, 1
    jmp exit_edi
err_open:
    mov     dil, 2
    jmp exit_edi
err_stat:
    mov     dil, 3
    jmp exit_edi
err_pread:
    mov     dil, 4
    jmp exit_edi
err_socket:
    mov     dil, 5
    jmp exit_edi
err_connect:
    mov     dil, 6
    jmp exit_edi
err_handshake_writev:
    mov     dil, 7
    jmp exit_edi
err_handshake_read:
    mov     dil, 8
exit_edi:
    movzx   edi, dil
    mov     eax, SYS_EXIT
    syscall


FILE.len=$-BASE

align PAGE_ALIGN
bss:
printf   dq ?
getenv   dq ?

timestamp_start dq ?

align 8
rw.start:
x11createwin:
.op          db ?
.depth       db ?
.size        dw ?
.window      dd ?
.win_parent  dd ?
.x           dw ?
.y           dw ?
.w           dw ?
.h           dw ?
.border      dw ?
.group       dw ?
.visual      dd ?
.value_mask  dd ?
x11mapwindow:
.op          dw ?
.size        dw ?
.window      dd ?

align 8
stat:
times 48 db ?
.len     dq ?

bss.len = 0x10000

