section .data
	hello db "Hello, what is your name?", 10
	message db " ,what a lovely name.", 10
section .bss
	name resb  16
section .text
	global _start
_start:
	call _askName
	call _getName
	call _sayName
	call _sayLast

	mov rax, 60
	mov rdi, 0
	syscall

_askName:
	mov rax, 1
	mov rdi, 1
	mov rsi, hello
	mov rdx, 26
	syscall
	ret

_getName:
	mov rax, 0
	mov rdi, 0
	mov rsi, name
	mov rdx, 16
	syscall
	ret

_sayName:
	mov rax, 1
	mov rdi, 1
	mov rsi, name
	mov rdx, 16
	syscall
	ret

_sayLast:
	mov rax, 1
	mov rdi, 1
	mov rsi, message
	mov rdx, 22
	syscall
	ret
