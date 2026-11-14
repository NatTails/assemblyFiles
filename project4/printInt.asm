section .data

section .bss
	number resb 100
	numberPos resb 8
section .text
	global _start
_start:
	mov rax, 123
	call _printRAX
	mov rax, 60
	mov rdi, 0
	syscall

_printRAX:
	mov rcx, number
	mov rbx, 10
	mov [rcx], rbx
	inc rcx
	mov [numberPos], rcx

_printRAXLoop:
	mov rdx, 0
	mov rbx, 10
	div rbx
	push rax
	add rdx, 48

	mov rcx, [numberPos]
	mov [rcx], dl
	inc rcx
	mov [numberPos], rcx

	pop rax
	cmp rax, 0
	jne _printRAXLoop

_printForward:
	mov rcx, [numberPos]

	mov rax, 1
	mov rdi, 1
	mov rsi, rcx
	mov rdx, 1
	syscall

	mov rcx, [numberPos]
	dec rcx
	mov [numberPos], rcx

	cmp rcx, numberPos
	jge _printForward
	ret
	
