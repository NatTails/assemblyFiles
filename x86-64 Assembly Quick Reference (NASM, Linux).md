# x86-64 Assembly Quick Reference (NASM, Linux)

*NASM syntax, Intel operand order (`destination, source`), Linux x86-64, System V ABI. Built as a lookup sheet: scan the tables first, read the notes when something surprises you.*

## 1. Build, run, inspect

```bash
nasm -f elf64 -g -F dwarf prog.asm -o prog.o   # assemble (-g -F dwarf = debug info for gdb)
ld prog.o -o prog                              # link: program has _start, no libc
gcc -no-pie prog.o -o prog                     # link instead if it has main / calls libc
gcc -no-pie -nostartfiles prog.o -o prog       # has _start AND calls libc
./prog; echo $?                                # run, then show exit status
```

| Command | Purpose |
| --- | --- |
| `nasm -f elf64 -l prog.lst prog.asm` | Listing file: source next to the machine code it produced |
| `objdump -d -M intel prog` | Disassemble in Intel syntax |
| `readelf -S prog` | Show sections (.text, .data, .bss) |
| `nm prog` | Show symbols and their addresses |
| `strace ./prog` | Print every syscall the program makes, with arguments and return value |

## 2. Minimal program skeleton

```nasm
section .data
msg:    db 'Hello, world!', 10      ; 10 = newline
len:    equ $ - msg                 ; length computed by the assembler

section .bss
buf:    resb 64                     ; uninitialised space

section .text
global _start
_start:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; fd 1 = stdout
    mov rsi, msg        ; address of the data
    mov rdx, len        ; byte count  (length goes in RDX!)
    syscall

    mov rax, 60         ; sys_exit
    xor edi, edi        ; status 0
    syscall
```

## 3. Registers and flags

| 64-bit | 32 | 16 | 8 (low) | Typical role |
| --- | --- | --- | --- | --- |
| `rax` | `eax` | `ax` | `al` (`ah` = bits 8-15) | Return value, syscall number, implicit operand of mul/div |
| `rbx` | `ebx` | `bx` | `bl` | General purpose, callee-saved |
| `rcx` | `ecx` | `cx` | `cl` | 4th function arg, shift count (`cl`), `rep` counter. Clobbered by `syscall` |
| `rdx` | `edx` | `dx` | `dl` | 3rd arg (function and syscall), high half in mul/div |
| `rsi` | `esi` | `si` | `sil` | 2nd arg, source pointer for string ops |
| `rdi` | `edi` | `di` | `dil` | 1st arg, destination pointer for string ops |
| `rbp` | `ebp` | `bp` | `bpl` | Frame pointer, callee-saved |
| `rsp` | `esp` | `sp` | `spl` | Stack pointer |
| `r8`-`r15` | `r8d`-`r15d` | `r8w`-`r15w` | `r8b`-`r15b` | `r8`/`r9` = 5th/6th arg; `r10` = 4th syscall arg; `r11` clobbered by `syscall`; `r12`-`r15` callee-saved |
| `rip` |  |  |  | Instruction pointer (use `[rel label]` to address relative to it) |
| `xmm0`-`xmm15` |  |  |  | 128-bit SSE registers for floats/doubles (`ymm` = 256-bit AVX) |

- Writing a **32-bit** register **zero-extends** into the full 64-bit register (`mov eax, 5` clears the upper half, which is why `xor eax, eax` zeroes `rax`).
- Writing an 8-bit or 16-bit part leaves the rest of the register unchanged.
- `ah`/`bh`/`ch`/`dh` cannot be used in the same instruction as `sil`, `dil`, `r8`-`r15`.

| Flag | Bit | Meaning |
| --- | --- | --- |
| CF | 0 | Carry / borrow (unsigned overflow) |
| PF | 2 | Parity of the low byte of the result |
| AF | 4 | Auxiliary carry (BCD) |
| ZF | 6 | Result was zero |
| SF | 7 | Sign: top bit of the result |
| DF | 10 | Direction: 0 = string ops move upward (must be 0 when calling functions) |
| OF | 11 | Signed overflow |

Unsigned comparisons use CF/ZF. Signed comparisons use SF/OF/ZF.

## 4. Calling conventions

|  | Function call (System V, `call`) | Linux syscall (`syscall`) |
| --- | --- | --- |
| Number | n/a | `rax` |
| Integer/pointer args | `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` | `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9` |
| Float args | `xmm0`-`xmm7` | n/a |
| Extra args | Pushed on the stack, right to left | Max 6 args |
| Return | `rax` (`rdx:rax` for 128-bit), `xmm0` for floats | `rax`; values from -4095 to -1 mean error (-errno) |
| Destroyed | `rax rcx rdx rsi rdi r8-r11 xmm0-15` | `rax rcx r11` |
| Preserved | `rbx rbp r12-r15 rsp` | Everything else |

Note the 4th argument: **`rcx` for functions, `r10` for syscalls.**

Function rules: `rsp` must be 16-byte aligned at the moment of `call` (so it is 8 mod 16 on function entry). Variadic functions like `printf` need `al` = number of vector registers used (0 if no floats). `DF` must be 0. Leaf functions may use the 128 bytes below `rsp` (red zone).

```nasm
func:                       ; template for your own function
    push rbp
    mov rbp, rsp
    sub rsp, 32             ; space for locals, keep it a multiple of 16
    ; body: args arrive in rdi, rsi, rdx, rcx, r8, r9
    leave                   ; = mov rsp, rbp / pop rbp
    ret
```

```nasm
extern printf               ; calling libc (link with gcc -no-pie)
global main
section .data
fmt: db 'n = %d', 10, 0
section .text
main:
    push rbp                ; also realigns rsp to 16
    mov rbp, rsp
    lea rdi, [rel fmt]
    mov esi, 42
    xor eax, eax            ; 0 vector registers used
    call printf
    xor eax, eax            ; return 0
    pop rbp
    ret
```

## 5. NASM syntax

| Section | Contents |
| --- | --- |
| `.text` | Code (read + execute) |
| `.data` | Initialised read/write data |
| `.rodata` | Read-only data (constants, strings) |
| `.bss` | Uninitialised space, reserved with `resb`/`resw`/`resd`/`resq` |

| Directive | Meaning |
| --- | --- |
| `db` `dw` `dd` `dq` | Define 1, 2, 4, 8 bytes of data |
| `resb` `resw` `resd` `resq` n | Reserve n bytes/words/dwords/qwords (`.bss`) |
| `equ` | Define a constant |
| `times n db 0` | Repeat n times |
| `$` / `$$` | Current address / start of the current section |
| `global` / `extern` | Export a symbol / import one |
| `default rel` | Make `[label]` RIP-relative everywhere |

```nasm
bytes:  db 1, 2, 3
str:    db 'text', 10, 0           ; 10 = newline, 0 = terminator
num:    dd 100
big:    dq 0xDEADBEEFCAFEBABE
zeros:  times 16 db 0
buf:    resb 256                   ; .bss only
len:    equ $ - str                ; length of str (counts the 10 and 0 too)
```

**Literals:** decimal `10`, hex `0x1F` or `1Fh`, binary `0b1010`, octal `0o17` or `17q`, character `'A'` (= 65).

**Addressing:** `[base + index*scale + disp]`, scale is 1, 2, 4 or 8.

```nasm
mov rax, msg            ; rax = ADDRESS of msg
mov rax, [msg]          ; rax = the 8 bytes stored AT msg
mov al, [rbx+rcx]       ; byte at rbx+rcx
mov eax, [rsi+rdi*4+8]  ; element of a dword array
mov [rel var], eax      ; RIP-relative store
```

**Size keywords** `byte` (8), `word` (16), `dword` (32), `qword` (64) are required when no register fixes the size: `mov byte [buf], 0`, `add dword [x], 1`, `cmp qword [rsp], 0`.

**Other rules:** labels end in a colon. `.loop` is a local label belonging to the previous normal label. No memory-to-memory operands: go through a register. Immediates are 32-bit sign-extended, except `mov reg64, imm64`.

```nasm
%define N 10                   ; text substitution
%include 'common.inc'          ; include another file
%macro exit 1                  ; macro with 1 parameter
    mov rax, 60
    mov rdi, %1
    syscall
%endmacro                      ; use as:  exit 0
```

## 6. Instruction reference

Notation: `r` register, `m` memory, `imm` immediate, `r/m` register or memory.

### 6.1 Data movement

| Instruction | Effect | Flags |
| --- | --- | --- |
| `mov d, s` | Copy s to d (no memory-to-memory) | none |
| `movzx d, r/m` | Zero-extend a smaller value, e.g. `movzx eax, byte [buf]` | none |
| `movsx d, r/m` | Sign-extend a smaller value | none |
| `movsxd rax, r/m32` | Sign-extend 32 to 64 bits | none |
| `xchg a, b` | Swap (with memory it is implicitly locked, so slow) | none |
| `lea r, [addr]` | Compute the address and store it in r (no memory access) | none |
| `push s` / `pop d` | `rsp -= 8` then store / load then `rsp += 8` | none |
| `pushfq` / `popfq` | Push / pop RFLAGS | all |
| `cmovcc r, r/m` | Move only if condition cc is true (cc table in 6.4) | none |
| `setcc r/m8` | Set byte to 1 if cc true, else 0 | none |
| `bswap r` | Reverse byte order (endianness swap) | none |

### 6.2 Arithmetic

| Instruction | Operation | Notes |
| --- | --- | --- |
| `add d, s` | d = d + s | sets OF SF ZF AF CF PF |
| `adc d, s` | d = d + s + CF | multi-word addition |
| `sub d, s` | d = d - s | same flags as add |
| `sbb d, s` | d = d - s - CF | multi-word subtraction |
| `inc d` / `dec d` | d += 1 / d -= 1 | **does not change CF** |
| `neg d` | d = -d | CF = 1 unless d was 0 |
| `cmp a, b` | Computes a - b, keeps only the flags | same flags as sub |
| `mul r/m` | Unsigned: `rdx:rax = rax * src` (8-bit: `ax = al * src`; 32-bit: `edx:eax = eax * src`) | CF=OF=1 if the upper half is non-zero |
| `imul r/m` | Signed version of the above | same |
| `imul r, r/m` | r = r \* r/m (truncated to r's size) |  |
| `imul r, r/m, imm` | r = r/m \* imm |  |
| `div r/m` | Unsigned: `rax = rdx:rax / src`, `rdx = remainder` (8-bit: `al` quotient, `ah` remainder from `ax`) | flags undefined; divide by 0 or quotient overflow = SIGFPE |
| `idiv r/m` | Signed version, same registers | same |
| `lea r, [a+b*c+d]` | Arithmetic without touching flags | `lea rax, [rdi+rdi*4]` = rdi \* 5 |

| Sign-extension helper | Effect |
| --- | --- |
| `cbw` / `cwde` / `cdqe` | `al` to `ax` / `ax` to `eax` / `eax` to `rax` |
| `cwd` / `cdq` / `cqo` | `ax` to `dx:ax` / `eax` to `edx:eax` / `rax` to `rdx:rax` |

```nasm
; unsigned: rax / rbx
xor edx, edx            ; upper half = 0
div rbx                 ; rax = quotient, rdx = remainder

; signed: -17 / 5
mov rax, -17
cqo                     ; sign-extend into rdx (NOT xor edx, edx)
mov rbx, 5
idiv rbx                ; rax = -3, rdx = -2 (truncates toward zero)
```

Shortcuts: x \* 2^n is `shl x, n`. Unsigned x / 2^n is `shr x, n`. Zero a register with `xor eax, eax`. Test for zero with `test rax, rax`. Multiply by 3, 5 or 9 with `lea`.

### 6.3 Logic, shifts, bit operations

| Instruction | Effect |
| --- | --- |
| `and d, s` / `or d, s` / `xor d, s` | Bitwise operations (clear CF and OF, set SF ZF PF) |
| `not d` | Flip all bits (no flags) |
| `test a, b` | AND that only sets flags; `test rax, rax` checks zero/sign |
| `shl d, n` / `sal d, n` | Shift left (x2^n). CF = last bit shifted out |
| `shr d, n` | Logical shift right (unsigned / 2^n) |
| `sar d, n` | Arithmetic shift right (signed / 2^n, keeps the sign bit) |
| `rol d, n` / `ror d, n` | Rotate left / right |
| `rcl d, n` / `rcr d, n` | Rotate through carry |
| `bt a, n` | CF = bit n of a (`bts`/`btr`/`btc` also set/clear/flip it) |
| `bsf r, r/m` / `bsr r, r/m` | Index of lowest / highest set bit (ZF=1 if source is 0) |
| `popcnt r, r/m` | Count set bits (needs CPU support) |
| `lzcnt` / `tzcnt` | Count leading / trailing zeros (newer CPUs) |

Shift count `n` is an immediate or the register `cl`, never another register.

Bit masks: set bit n `or rax, 1<<n`, clear `and rax, ~(1<<n)`, flip `xor rax, 1<<n`, test `test rax, 1<<n` then `jnz`/`jz`. NASM evaluates `<<` and `~` itself.

### 6.4 Compare and conditional jumps

Use `cmp a, b` and then a `jcc`. The condition reads as "a ? b". The same suffixes work for `cmovcc` and `setcc`.

| Condition (after `cmp a, b`) | Jump | Flags tested |
| --- | --- | --- |
| a == b | `je` / `jz` | ZF=1 |
| a != b | `jne` / `jnz` | ZF=0 |
| a > b unsigned | `ja` / `jnbe` | CF=0 and ZF=0 |
| a >= b unsigned | `jae` / `jnb` / `jnc` | CF=0 |
| a < b unsigned | `jb` / `jnae` / `jc` | CF=1 |
| a <= b unsigned | `jbe` / `jna` | CF=1 or ZF=1 |
| a > b signed | `jg` / `jnle` | ZF=0 and SF=OF |
| a >= b signed | `jge` / `jnl` | SF=OF |
| a < b signed | `jl` / `jnge` | SF!=OF |
| a <= b signed | `jle` / `jng` | ZF=1 or SF!=OF |
| negative / non-negative | `js` / `jns` | SF=1 / SF=0 |
| overflow / no overflow | `jo` / `jno` | OF=1 / OF=0 |
| parity even / odd | `jp` / `jnp` | PF=1 / PF=0 |
| rcx is zero | `jrcxz` | rcx == 0 (short range only) |

Memory aid: **unsigned = above/below (a, b), signed = greater/less (g, l).**

### 6.5 Control flow

| Instruction | Effect |
| --- | --- |
| `jmp label` / `jmp r/m` | Unconditional jump (direct or indirect) |
| `call target` | Push return address, jump |
| `ret` | Pop return address into `rip` |
| `leave` | `mov rsp, rbp` then `pop rbp` |
| `loop label` | `dec rcx`, jump if rcx != 0 (slow, prefer `dec` + `jnz`) |
| `syscall` | Enter the kernel |
| `nop` / `int3` / `ud2` | Do nothing / breakpoint / deliberate crash |
| `cpuid` / `rdtsc` | CPU info / cycle counter |

```nasm
    mov rbx, 10             ; counted loop; rbx survives syscalls (rcx does not)
.again:
    ; ... body ...
    dec rbx
    jnz .again

    cmp rax, 5              ; if / else
    jne .else
    ; then-part
    jmp .end
.else:
    ; else-part
.end:

.top:                       ; while (rax < rbx), signed
    cmp rax, rbx
    jge .done
    ; body
    jmp .top
.done:
```

### 6.6 The stack

Grows downward. `push x`: `rsp -= 8; [rsp] = x`. `pop x`: `x = [rsp]; rsp += 8`. Locals: `sub rsp, n` on entry and `add rsp, n` (or `leave`) on exit. With the standard prologue: `[rbp+8]` is the return address, `[rbp+16]` the 7th argument, `[rbp-8]` the first local.

### 6.7 String instructions

| Instruction | Effect (size suffix b/w/d/q) |
| --- | --- |
| `movsb` | `[rdi] = [rsi]`, both pointers advance |
| `stosb` | `[rdi] = al` (or `ax`/`eax`/`rax`), `rdi` advances |
| `lodsb` | `al = [rsi]`, `rsi` advances |
| `scasb` | Compare `al` with `[rdi]`, `rdi` advances |
| `cmpsb` | Compare `[rsi]` with `[rdi]`, both advance |

Prefixes: `rep` repeats `rcx` times, `repe`/`repz` repeats while equal, `repne`/`repnz` repeats while not equal. `DF=0` (`cld`) moves pointers up, `std` moves them down.

```nasm
cld
mov rsi, src
mov rdi, dst
mov rcx, 100
rep movsb               ; memcpy of 100 bytes

xor eax, eax
mov rdi, buf
mov rcx, 64
rep stosb               ; memset(buf, 0, 64)

mov rdi, str            ; strlen of a 0-terminated string
xor eax, eax
mov rcx, -1
repne scasb
not rcx
dec rcx                 ; rcx = length
```

### 6.8 Flag control

`clc` / `stc` / `cmc` clear / set / flip CF. `cld` / `std` clear / set DF. `lahf` / `sahf` copy flags to / from `ah`.

### 6.9 Floating point (SSE basics)

| Instruction | Effect |
| --- | --- |
| `movsd` / `movss` | Move scalar double / single |
| `addsd` `subsd` `mulsd` `divsd` `sqrtsd` | Scalar double arithmetic (`ss` for single) |
| `ucomisd a, b` | Compare, sets ZF/PF/CF; follow with `ja`/`jb`/`je` |
| `cvtsi2sd xmm, r/m` | Integer to double |
| `cvttsd2si r, xmm/m` | Double to integer (truncate) |
| `movaps` / `movups` | Move 128 bits (aligned / unaligned). `movaps` crashes on misaligned memory |
| `addpd` `mulpd` `addps` `mulps` ... | Packed (SIMD) operations |

Float/double arguments go in `xmm0`-`xmm7`, the result comes back in `xmm0`.

## 7. Linux syscalls

`rax` = number, arguments in `rdi, rsi, rdx, r10, r8, r9`, then `syscall`. The result is in `rax`; a value from -4095 to -1 is `-errno`. `rcx` and `r11` are destroyed. Do not use `int 0x80` (that is the 32-bit ABI). The complete number list is in Appendix A.

| # | Name | Arguments | Notes |
| --- | --- | --- | --- |
| 0 | `read` | fd, buf, count | Returns bytes read, 0 = EOF. Includes the newline typed |
| 1 | `write` | fd, buf, count | Returns bytes written |
| 2 | `open` | path, flags, mode | Returns fd. Path must be 0-terminated |
| 3 | `close` | fd |  |
| 4 | `stat` | path, statbuf |  |
| 5 | `fstat` | fd, statbuf |  |
| 8 | `lseek` | fd, offset, whence | whence: 0 = SET, 1 = CUR, 2 = END |
| 9 | `mmap` | addr, length, prot, flags, fd, offset | 4th arg is `r10`, 5th `r8`, 6th `r9` |
| 10 | `mprotect` | addr, len, prot |  |
| 11 | `munmap` | addr, len |  |
| 12 | `brk` | addr | 0 = query the current break |
| 16 | `ioctl` | fd, request, arg |  |
| 21 | `access` | path, mode |  |
| 22 | `pipe` | fds (int\[2\]) |  |
| 32 / 33 | `dup` / `dup2` | oldfd / oldfd, newfd |  |
| 35 | `nanosleep` | req, rem | `timespec`: 8-byte seconds + 8-byte nanoseconds |
| 39 | `getpid` |  |  |
| 41 | `socket` | domain, type, protocol |  |
| 42 | `connect` | fd, addr, addrlen |  |
| 43 | `accept` | fd, addr, addrlen |  |
| 44 / 45 | `sendto` / `recvfrom` | fd, buf, len, flags, addr, addrlen |  |
| 49 | `bind` | fd, addr, addrlen |  |
| 50 | `listen` | fd, backlog |  |
| 56 | `clone` | flags, stack, ptid, ctid, tls |  |
| 57 | `fork` |  | Child pid in parent, 0 in child |
| 59 | `execve` | path, argv, envp | Only returns on error |
| 60 | `exit` | status | Ends the calling thread |
| 61 | `wait4` | pid, wstatus, options, rusage |  |
| 62 | `kill` | pid, sig |  |
| 63 | `uname` | buf |  |
| 79 | `getcwd` | buf, size |  |
| 80 | `chdir` | path |  |
| 82 | `rename` | old, new |  |
| 83 / 84 | `mkdir` / `rmdir` | path, mode / path |  |
| 85 | `creat` | path, mode |  |
| 87 | `unlink` | path |  |
| 90 | `chmod` | path, mode |  |
| 96 | `gettimeofday` | tv, tz |  |
| 102 / 104 | `getuid` / `getgid` |  |  |
| 201 | `time` | tloc | Seconds since 1970 |
| 217 | `getdents64` | fd, dirp, count | Read directory entries |
| 228 | `clock_gettime` | clockid, timespec\* | CLOCK\_REALTIME = 0, CLOCK\_MONOTONIC = 1 |
| 231 | `exit_group` | status | Ends the whole process (what libc `exit` uses) |
| 257 | `openat` | dirfd, path, flags, mode | `AT_FDCWD` = -100 |
| 318 | `getrandom` | buf, buflen, flags |  |

**File descriptors:** 0 = stdin, 1 = stdout, 2 = stderr.

| `open` flag | Octal | Decimal |
| --- | --- | --- |
| `O_RDONLY` | 0 | 0 |
| `O_WRONLY` | 1 | 1 |
| `O_RDWR` | 2 | 2 |
| `O_CREAT` | 0o100 | 64 |
| `O_EXCL` | 0o200 | 128 |
| `O_TRUNC` | 0o1000 | 512 |
| `O_APPEND` | 0o2000 | 1024 |
| `O_NONBLOCK` | 0o4000 | 2048 |
| `O_DIRECTORY` | 0o200000 | 65536 |
| `O_CLOEXEC` | 0o2000000 | 524288 |

Combine with OR: create + write-only + truncate = 1 + 64 + 512 = **577**. File modes: `0o644` = 420, `0o755` = 493.

**mmap:** `PROT_READ` 1, `PROT_WRITE` 2, `PROT_EXEC` 4. `MAP_SHARED` 1, `MAP_PRIVATE` 2, `MAP_ANONYMOUS` 0x20. Allocate memory: flags = 0x22, fd = -1, offset = 0.

| Signal | # | Signal | # | Signal | # |
| --- | --- | --- | --- | --- | --- |
| SIGHUP | 1 | SIGBUS | 7 | SIGALRM | 14 |
| SIGINT | 2 | SIGFPE | 8 | SIGTERM | 15 |
| SIGQUIT | 3 | SIGKILL | 9 | SIGCHLD | 17 |
| SIGILL | 4 | SIGUSR1 | 10 | SIGCONT | 18 |
| SIGTRAP | 5 | SIGSEGV | 11 | SIGSTOP | 19 |
| SIGABRT | 6 | SIGPIPE | 13 |  |  |

| errno | # | errno | # | errno | # |
| --- | --- | --- | --- | --- | --- |
| EPERM | 1 | EAGAIN | 11 | EISDIR | 21 |
| ENOENT | 2 | ENOMEM | 12 | EINVAL | 22 |
| ESRCH | 3 | EACCES | 13 | EMFILE | 24 |
| EINTR | 4 | EFAULT | 14 | ENOSPC | 28 |
| EIO | 5 | EEXIST | 17 | EPIPE | 32 |
| EBADF | 9 | ENOTDIR | 20 | ENOSYS | 38 |

```nasm
; read up to 64 bytes from stdin
mov rax, 0
mov rdi, 0
mov rsi, buf
mov rdx, 64
syscall                 ; rax = bytes read

; open a file and check for an error
mov rax, 2
mov rdi, path           ; 0-terminated string
xor esi, esi            ; O_RDONLY
syscall
test rax, rax
js .error               ; negative = -errno
mov rbx, rax            ; keep the fd in rbx (survives syscalls)
```

## 8. Code patterns

**Command-line arguments** (at `_start`, before anything is pushed):

```nasm
_start:
    mov rdi, [rsp]          ; argc
    lea rsi, [rsp+8]        ; argv: array of pointers, argv[0] first, ends in 0
    ; envp follows the argv terminator
```

**Print an unsigned number in decimal:**

```nasm
section .bss
buf: resb 21
section .text
print_uint:                 ; in: rax = number. Prints it plus a newline
    mov rbx, 10
    lea rsi, [buf + 20]
    mov byte [rsi], 10      ; newline at the end
.next:
    xor edx, edx
    div rbx                 ; rax = rax / 10, rdx = rax % 10
    add dl, '0'             ; digit to ASCII
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .next
    lea rdx, [buf + 21]
    sub rdx, rsi            ; length = end - start
    mov rdi, 1
    mov rax, 1
    syscall
    ret
```

**Parse a decimal string into a number:**

```nasm
atoi:                       ; in: rsi -> digits. out: rax = value
    xor eax, eax
.next:
    movzx ecx, byte [rsi]
    sub ecx, '0'
    cmp ecx, 9
    ja .done                ; unsigned compare also rejects chars below '0'
    imul rax, rax, 10
    add rax, rcx
    inc rsi
    jmp .next
.done:
    ret
```

**ASCII essentials:** `'0'`-`'9'` = 48-57, `'A'`-`'Z'` = 65-90, `'a'`-`'z'` = 97-122, space = 32, newline = 10, NUL = 0. Upper to lower case: `or al, 0x20`. Digit to character: `add al, '0'`. Character to digit: `sub al, '0'`.

## 9. Common mistakes

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Nothing prints | Length put in `rax` or `rdi` instead of `rdx`, or `rax` is not 1 | `rax` = 1, `rdi` = 1, `rsi` = buffer, `rdx` = length |
| Segfault right after your last instruction | No exit syscall, so execution runs off the end of the code | End with `mov rax, 60`, `xor edi, edi`, `syscall` |
| `ld: cannot find entry symbol _start` | `global _start` missing or misspelled (it needs the space) | Write `global _start` |
| `nasm: operation size not specified` | No register fixes the size of the operand | Add `byte` / `word` / `dword` / `qword` |
| Loop counter changes after a syscall | `syscall` destroys `rcx` and `r11` | Keep counters in `rbx` or `r12`-`r15` |
| `Floating point exception` | Divide by 0, `rdx` not prepared before `div`/`idiv`, or quotient too large | `xor edx, edx` (unsigned) or `cqo` (signed) first, check the divisor |
| Prints an address or garbage instead of the value | `mov rax, msg` vs `mov rax, [msg]` mixed up | Brackets read memory, no brackets is the address |
| Upper bits of a register are not what you expect | 8/16-bit writes leave the rest unchanged | `xor eax, eax` first, or use `movzx` |
| Wrong branch taken | Signed vs unsigned jump mismatch | `ja`/`jb` for unsigned, `jg`/`jl` for signed |
| Crash inside `printf` | Stack not 16-byte aligned at `call` | Adjust with `push` or `sub rsp`, and set `al` = 0 |
| `ret` jumps to garbage | Unbalanced push/pop, or the return address was overwritten | Balance the stack, use `leave` |
| Extra line break or odd trailing bytes | `read` includes the newline, and a fixed length prints leftover bytes | Use the byte count returned in `rax` (minus 1 to drop the newline) |
| `mov [a], [b]` is rejected | No memory-to-memory operands | Go through a register |
| Segfault when writing to a string | Data is in `.rodata` or `.text`, which are read-only | Put it in `.data` or `.bss` |
| Linker error about `R_X86_64_32` or PIE | gcc builds position-independent code by default | `gcc -no-pie`, or `default rel` and `[rel label]` |
| String functions run past the end | No 0 terminator | Add `, 0` to the `db` |
| Initial value in `.bss` is ignored or rejected | `.bss` is uninitialised | Use `.data` for initialised values |

## 10. gdb quick reference

```bash
nasm -f elf64 -g -F dwarf prog.asm -o prog.o && ld prog.o -o prog
gdb ./prog
```

| Command | Meaning |
| --- | --- |
| `break _start` / `b label` | Set a breakpoint |
| `run` / `r` | Start the program |
| `stepi` / `si` | Execute one instruction |
| `nexti` / `ni` | One instruction, stepping over `call` |
| `continue` / `c` | Run to the next breakpoint |
| `info registers` / `i r` | Show all registers (`i r rax` for one) |
| `p/x $rax`, `p/d $rax`, `p/t $rax` | Print a register in hex, decimal, binary |
| `p $eflags` | Show which flags are set |
| `x/s &msg` | Print a string at an address |
| `x/16xb &buf` | 16 bytes in hex |
| `x/4gx $rsp` | 4 qwords from the top of the stack |
| `x/5i $rip` | Disassemble the next 5 instructions |
| `display/i $rip` | Show the next instruction after every step |
| `set disassembly-flavor intel` | Intel syntax (put it in `~/.gdbinit` to keep it) |
| `layout asm` / `layout regs` | Text UI with code and registers (`Ctrl+x a` leaves it) |
| `info breakpoints` / `delete` | List / remove breakpoints |
| `quit` / `q` | Exit |

`x` format is `x/<count><format><size>`. Formats: `x` hex, `d` decimal, `u` unsigned, `t` binary, `c` char, `s` string, `i` instruction. Sizes: `b` 1 byte, `h` 2, `w` 4, `g` 8.

## Appendix A: complete syscall list (x86-64 Linux)

Taken from the kernel headers on this system (`/usr/include/x86_64-linux-gnu/asm/unistd_64.h`). Use `man 2 <name>` for arguments and `man 2 syscalls` for an overview. Numbers 335-423 are unassigned on x86-64. Newer kernels may add entries above 461, so check the header on your machine. Several old entries are obsolete or unimplemented and normally return `-ENOSYS`: `uselib`, `_sysctl`, `create_module`, `get_kernel_syms`, `query_module`, `nfsservctl`, `getpmsg`, `putpmsg`, `afs_syscall`, `tuxcall`, `security`, `vserver`, `epoll_ctl_old`, `epoll_wait_old`.

| # | Name | # | Name | # | Name | # | Name |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | read | 1 | write | 2 | open | 3 | close |
| 4 | stat | 5 | fstat | 6 | lstat | 7 | poll |
| 8 | lseek | 9 | mmap | 10 | mprotect | 11 | munmap |
| 12 | brk | 13 | rt\_sigaction | 14 | rt\_sigprocmask | 15 | rt\_sigreturn |
| 16 | ioctl | 17 | pread64 | 18 | pwrite64 | 19 | readv |
| 20 | writev | 21 | access | 22 | pipe | 23 | select |
| 24 | sched\_yield | 25 | mremap | 26 | msync | 27 | mincore |
| 28 | madvise | 29 | shmget | 30 | shmat | 31 | shmctl |
| 32 | dup | 33 | dup2 | 34 | pause | 35 | nanosleep |
| 36 | getitimer | 37 | alarm | 38 | setitimer | 39 | getpid |
| 40 | sendfile | 41 | socket | 42 | connect | 43 | accept |
| 44 | sendto | 45 | recvfrom | 46 | sendmsg | 47 | recvmsg |
| 48 | shutdown | 49 | bind | 50 | listen | 51 | getsockname |
| 52 | getpeername | 53 | socketpair | 54 | setsockopt | 55 | getsockopt |
| 56 | clone | 57 | fork | 58 | vfork | 59 | execve |
| 60 | exit | 61 | wait4 | 62 | kill | 63 | uname |
| 64 | semget | 65 | semop | 66 | semctl | 67 | shmdt |
| 68 | msgget | 69 | msgsnd | 70 | msgrcv | 71 | msgctl |
| 72 | fcntl | 73 | flock | 74 | fsync | 75 | fdatasync |
| 76 | truncate | 77 | ftruncate | 78 | getdents | 79 | getcwd |
| 80 | chdir | 81 | fchdir | 82 | rename | 83 | mkdir |
| 84 | rmdir | 85 | creat | 86 | link | 87 | unlink |
| 88 | symlink | 89 | readlink | 90 | chmod | 91 | fchmod |
| 92 | chown | 93 | fchown | 94 | lchown | 95 | umask |
| 96 | gettimeofday | 97 | getrlimit | 98 | getrusage | 99 | sysinfo |
| 100 | times | 101 | ptrace | 102 | getuid | 103 | syslog |
| 104 | getgid | 105 | setuid | 106 | setgid | 107 | geteuid |
| 108 | getegid | 109 | setpgid | 110 | getppid | 111 | getpgrp |
| 112 | setsid | 113 | setreuid | 114 | setregid | 115 | getgroups |
| 116 | setgroups | 117 | setresuid | 118 | getresuid | 119 | setresgid |
| 120 | getresgid | 121 | getpgid | 122 | setfsuid | 123 | setfsgid |
| 124 | getsid | 125 | capget | 126 | capset | 127 | rt\_sigpending |
| 128 | rt\_sigtimedwait | 129 | rt\_sigqueueinfo | 130 | rt\_sigsuspend | 131 | sigaltstack |
| 132 | utime | 133 | mknod | 134 | uselib | 135 | personality |
| 136 | ustat | 137 | statfs | 138 | fstatfs | 139 | sysfs |
| 140 | getpriority | 141 | setpriority | 142 | sched\_setparam | 143 | sched\_getparam |
| 144 | sched\_setscheduler | 145 | sched\_getscheduler | 146 | sched\_get\_priority\_max | 147 | sched\_get\_priority\_min |
| 148 | sched\_rr\_get\_interval | 149 | mlock | 150 | munlock | 151 | mlockall |
| 152 | munlockall | 153 | vhangup | 154 | modify\_ldt | 155 | pivot\_root |
| 156 | \_sysctl | 157 | prctl | 158 | arch\_prctl | 159 | adjtimex |
| 160 | setrlimit | 161 | chroot | 162 | sync | 163 | acct |
| 164 | settimeofday | 165 | mount | 166 | umount2 | 167 | swapon |
| 168 | swapoff | 169 | reboot | 170 | sethostname | 171 | setdomainname |
| 172 | iopl | 173 | ioperm | 174 | create\_module | 175 | init\_module |
| 176 | delete\_module | 177 | get\_kernel\_syms | 178 | query\_module | 179 | quotactl |
| 180 | nfsservctl | 181 | getpmsg | 182 | putpmsg | 183 | afs\_syscall |
| 184 | tuxcall | 185 | security | 186 | gettid | 187 | readahead |
| 188 | setxattr | 189 | lsetxattr | 190 | fsetxattr | 191 | getxattr |
| 192 | lgetxattr | 193 | fgetxattr | 194 | listxattr | 195 | llistxattr |
| 196 | flistxattr | 197 | removexattr | 198 | lremovexattr | 199 | fremovexattr |
| 200 | tkill | 201 | time | 202 | futex | 203 | sched\_setaffinity |
| 204 | sched\_getaffinity | 205 | set\_thread\_area | 206 | io\_setup | 207 | io\_destroy |
| 208 | io\_getevents | 209 | io\_submit | 210 | io\_cancel | 211 | get\_thread\_area |
| 212 | lookup\_dcookie | 213 | epoll\_create | 214 | epoll\_ctl\_old | 215 | epoll\_wait\_old |
| 216 | remap\_file\_pages | 217 | getdents64 | 218 | set\_tid\_address | 219 | restart\_syscall |
| 220 | semtimedop | 221 | fadvise64 | 222 | timer\_create | 223 | timer\_settime |
| 224 | timer\_gettime | 225 | timer\_getoverrun | 226 | timer\_delete | 227 | clock\_settime |
| 228 | clock\_gettime | 229 | clock\_getres | 230 | clock\_nanosleep | 231 | exit\_group |
| 232 | epoll\_wait | 233 | epoll\_ctl | 234 | tgkill | 235 | utimes |
| 236 | vserver | 237 | mbind | 238 | set\_mempolicy | 239 | get\_mempolicy |
| 240 | mq\_open | 241 | mq\_unlink | 242 | mq\_timedsend | 243 | mq\_timedreceive |
| 244 | mq\_notify | 245 | mq\_getsetattr | 246 | kexec\_load | 247 | waitid |
| 248 | add\_key | 249 | request\_key | 250 | keyctl | 251 | ioprio\_set |
| 252 | ioprio\_get | 253 | inotify\_init | 254 | inotify\_add\_watch | 255 | inotify\_rm\_watch |
| 256 | migrate\_pages | 257 | openat | 258 | mkdirat | 259 | mknodat |
| 260 | fchownat | 261 | futimesat | 262 | newfstatat | 263 | unlinkat |
| 264 | renameat | 265 | linkat | 266 | symlinkat | 267 | readlinkat |
| 268 | fchmodat | 269 | faccessat | 270 | pselect6 | 271 | ppoll |
| 272 | unshare | 273 | set\_robust\_list | 274 | get\_robust\_list | 275 | splice |
| 276 | tee | 277 | sync\_file\_range | 278 | vmsplice | 279 | move\_pages |
| 280 | utimensat | 281 | epoll\_pwait | 282 | signalfd | 283 | timerfd\_create |
| 284 | eventfd | 285 | fallocate | 286 | timerfd\_settime | 287 | timerfd\_gettime |
| 288 | accept4 | 289 | signalfd4 | 290 | eventfd2 | 291 | epoll\_create1 |
| 292 | dup3 | 293 | pipe2 | 294 | inotify\_init1 | 295 | preadv |
| 296 | pwritev | 297 | rt\_tgsigqueueinfo | 298 | perf\_event\_open | 299 | recvmmsg |
| 300 | fanotify\_init | 301 | fanotify\_mark | 302 | prlimit64 | 303 | name\_to\_handle\_at |
| 304 | open\_by\_handle\_at | 305 | clock\_adjtime | 306 | syncfs | 307 | sendmmsg |
| 308 | setns | 309 | getcpu | 310 | process\_vm\_readv | 311 | process\_vm\_writev |
| 312 | kcmp | 313 | finit\_module | 314 | sched\_setattr | 315 | sched\_getattr |
| 316 | renameat2 | 317 | seccomp | 318 | getrandom | 319 | memfd\_create |
| 320 | kexec\_file\_load | 321 | bpf | 322 | execveat | 323 | userfaultfd |
| 324 | membarrier | 325 | mlock2 | 326 | copy\_file\_range | 327 | preadv2 |
| 328 | pwritev2 | 329 | pkey\_mprotect | 330 | pkey\_alloc | 331 | pkey\_free |
| 332 | statx | 333 | io\_pgetevents | 334 | rseq |  |  |

The newer block, starting at 424:

| # | Name | # | Name | # | Name | # | Name |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 424 | pidfd\_send\_signal | 425 | io\_uring\_setup | 426 | io\_uring\_enter | 427 | io\_uring\_register |
| 428 | open\_tree | 429 | move\_mount | 430 | fsopen | 431 | fsconfig |
| 432 | fsmount | 433 | fspick | 434 | pidfd\_open | 435 | clone3 |
| 436 | close\_range | 437 | openat2 | 438 | pidfd\_getfd | 439 | faccessat2 |
| 440 | process\_madvise | 441 | epoll\_pwait2 | 442 | mount\_setattr | 443 | quotactl\_fd |
| 444 | landlock\_create\_ruleset | 445 | landlock\_add\_rule | 446 | landlock\_restrict\_self | 447 | memfd\_secret |
| 448 | process\_mrelease | 449 | futex\_waitv | 450 | set\_mempolicy\_home\_node | 451 | cachestat |
| 452 | fchmodat2 | 453 | map\_shadow\_stack | 454 | futex\_wake | 455 | futex\_wait |
| 456 | futex\_requeue | 457 | statmount | 458 | listmount | 459 | lsm\_get\_self\_attr |
| 460 | lsm\_set\_self\_attr | 461 | lsm\_list\_modules |  |  |  |  |
