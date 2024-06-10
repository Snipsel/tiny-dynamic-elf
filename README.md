# Small dynamically linked Elf64 executable

Educational experiment to understand elf executables.

Tiny executable that opens an X11 window and waits until the window is closed.

Read [main.asm](main.asm) for more info.

## Layout
The entire executable is directly mapped into memory as a single segment with read-only+execute permissions.
This is to avoid having to page-align segments in our file.

A second read-write zero-initialized segment is allocated on the pages directly after the executable.
The first portion of this segment is where the loader writes the function pointers to.

## Safety
Nothing about this program is safe.
In order to be as simple (and small) as possible, no effort has been made to harden the executable.

Non-exhaustive list of security issues to be aware of:
1) The stack is executable. This can be fixed by adding a PT_GNU_STACK segment.
2) The read-only data (including the elf headers) are marked executable.
3) The link table is writable. This can be fixed by adding a PT_GNU_RELRO segment.
4) I'm not great at writing assembly.

# Build
This project uses [fasm](https://flatassembler.net/).
```sh
fasm main.asm
```

