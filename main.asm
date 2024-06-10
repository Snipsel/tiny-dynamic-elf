use64
org 0x10000
PAGE_SIZE  = 0x1000
include 'elf64.asm'

align 4
rocopy.start: ; read-only data that's copied into the read-write segment
rocopy.x11createwin:
.op          db        1
.depth       db        0
.size        dw      8+1
.window      dd        0
.win_parent  dd        0
.x           dw        0
.y           dw        0
.w           dw     1920
.h           dw     1080
.border      dw        0
.group       dw        1 ; window class input-output
.visual      dd        0
.value_mask  dd   0x0800 ; backing_pixel=0x0100 | event_mask=0x0800
.event_mask  dd        0
.len = $-rocopy.x11createwin
rocopy.x11mapwindow:
.op          dw        8
.size        dw        2
.window      dd        0
.len = $-rocopy.x11mapwindow
rocopy.len = $-rocopy.start

align 8
iov1 dq con_req, con_req_len
iov2 dq bss.buffer, 16

align 2
sockaddr db 1,0,"/tmp/.X11-unix/X0",0
sockaddr_len = $-sockaddr

con_req  db "l",0,11,0,0,0,18,0,16,0,0,0,"MIT-MAGIC-COOKIE-1",0,0
con_req_len = $-con_req

msg_exit db "exit %lu cy", 10, 0
xauth db "XAUTHORITY="
.len = $-xauth

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
    mov dword [bss.timestamp.start],   eax
    mov dword [bss.timestamp.start+4], edx

    ; copy ro data into rw segment
    mov     ecx, rocopy.len
    mov     esi, rocopy.start
    mov     edi, bss.rwcopy.start
    rep movsb

    ; read XAUTHORITY environment variable
    mov     rax, [rsp]          ; read argc
    lea     rax, [rsp+rax*8+16] ; locate env pointer
.loop_outer: ; iterates over the array of strings
    mov     rdi, [rax]
    test	rdi, rdi
    jz      err_getenv  ; we've found the end of the env array without finding xauth
    xor     edx, edx
.loop_inner: ; iterates over chars of string
    mov     sil, byte [xauth + rdx]
    cmp     byte [rdi + rdx], sil
    je      .exit_inner
    add     rax, 8
    jmp	    .loop_outer
.exit_inner:
    inc	    rdx
    cmp	    rdx, xauth.len
    jne	    .loop_inner
    add	    rdi, xauth.len ; skip past the equals sign

    ; open the xauthority file
    xor     esi, esi ; flags
    xor     edx, edx ; mode
    mov     eax, SYS_OPEN
    syscall
    test    eax, eax
    jna     err_open

    ; get xauthority file size
    mov     edi, eax
    mov     esi, bss.buffer
    mov     eax, SYS_FSTAT
    syscall
    test    eax, eax
    js      err_stat
    
    ; read final 16 bytes for the key
    mov     rdx, 16
    mov     r10, [bss.buffer+48] ; filesize offset in stat struct
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
    mov     edx, bss.len-(bss.buffer-bss)
    mov     esi, bss.buffer
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
    mov     eax, [bss.buffer+12] ; setup.id_base
    mov     ecx, [bss.buffer+16] ; setup.id_mask
    not     ecx
    and     eax, ecx

    ; write window id to the required places
    mov     [bss.x11createwin.window], eax
    mov     [bss.x11mapwindow.window], eax

    ; set the root[0].window_id
    mov eax, [esi+bss.buffer+0]    
    mov [bss.x11createwin.win_parent], eax

    ; root[0].visual_id
    mov     eax, [esi+bss.buffer+32] 
    mov     [bss.x11createwin.visual], eax

    ; write window request struct
    mov     rdx, rocopy.len
    mov     rsi, bss.x11createwin
    mov     rax, SYS_WRITE
    syscall

    ; read out cycle counter
    lfence
    rdtsc
    lfence
    mov dword [bss.timestamp.win_open],   eax
    mov dword [bss.timestamp.win_open+4], edx

    ; restore message length
    mov     rsi, r13

    ; read window request response
    mov     rdx, (bss+bss.len)
    sub     rdx, rsi
    add     rsi, bss.buffer
    mov     rax, SYS_READ
    syscall

    ; hang until next message (should be window close event)
    mov     rdx, 4096
    add     rsi, bss.buffer
    mov     rax, SYS_READ
    syscall

exit_success:
    mov     rsi, [bss.timestamp.win_open]
    sub     rsi, [bss.timestamp.start]
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


FILE.len=$-$$

align PAGE_SIZE
bss:
printf   dq ?

bss.timestamp:
.start    dq ?
.win_open dq ?

align 8
bss.rwcopy.start:
bss.x11createwin:
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
.event_mask  dd ?
bss.x11mapwindow:
.op          dw ?
.size        dw ?
.window      dd ?

align 8
bss.buffer:
.len=bss.len-bss.buffer

bss.len = 0x10000

