BITS 64
default rel

%define WORDS 0
%define LEN 256
%define CAP 32
%define SUCCESS 0
%define NULL_ARG -1
%define LENGTH -2
%define MODULUS -3
%define RANGE -4

global bignum_montgomery_mul
global bignum_montgomery_mul_c11

section .text
bignum_montgomery_mul_c11:
bignum_montgomery_mul:
    test rdi, rdi
    jz .null_leaf
    test rsi, rsi
    jz .null_leaf
    test rdx, rdx
    jz .null_leaf
    test rcx, rcx
    jz .null_leaf
    cmp qword [rcx + LEN], 1
    jne .full_entry
    cmp qword [rsi + LEN], 1
    ja .length_leaf
    cmp qword [rdx + LEN], 1
    ja .length_leaf
    mov r8, [rcx + WORDS]
    test r8b, 1
    jz .modulus_leaf
    mov r9, [rsi + WORDS]
    cmp r9, r8
    jae .range_leaf
    mov r10, [rdx + WORDS]
    cmp r10, r8
    jae .range_leaf
    mov rax, r9
    mul r10
    mov r11, rdx
    mov r9, rax
    mov r10, r8
    mov rax, r10
    imul rax, r10
    mov rdx, 2
    sub rdx, rax
    imul r10, rdx
    mov rax, r10
    imul rax, r8
    mov rdx, 2
    sub rdx, rax
    imul r10, rdx
    mov rax, r10
    imul rax, r8
    mov rdx, 2
    sub rdx, rax
    imul r10, rdx
    mov rax, r10
    imul rax, r8
    mov rdx, 2
    sub rdx, rax
    imul r10, rdx
    mov rax, r10
    imul rax, r8
    mov rdx, 2
    sub rdx, rax
    imul r10, rdx
    neg r10
    mov rax, r9
    imul rax, r10
    mul r8
    add rax, r9
    adc rdx, r11
    jc .leaf_sub
    cmp rdx, r8
    jb .leaf_store
.leaf_sub:
    sub rdx, r8
.leaf_store:
    mov r10, rdx
    xor eax, eax
    lea r8, [rdi + WORDS]
    mov r9d, CAP
.leaf_zero:
    mov [r8], rax
    add r8, 8
    dec r9d
    jnz .leaf_zero
    mov [rdi + WORDS], r10
    mov qword [rdi + LEN], 1
    xor eax, eax
    ret
.null_leaf:
    mov eax, NULL_ARG
    ret
.length_leaf:
    mov eax, LENGTH
    ret
.modulus_leaf:
    mov eax, MODULUS
    ret
.range_leaf:
    mov eax, RANGE
    ret
.full_entry:
    push rbp
    mov rbp, rsp
    sub rsp, 544
    push rbx
    push r12
    push r13
    push r14
    push r15

    test rdi, rdi
    jz .null
    test rsi, rsi
    jz .null
    test rdx, rdx
    jz .null
    test rcx, rcx
    jz .null

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov r8, [r15 + LEN]
    test r8, r8
    jz .modulus
    cmp r8, CAP
    ja .length
    mov r9, [r15 + WORDS + r8*8 - 8]
    test r9, r9
    jz .length
    test byte [r15 + WORDS], 1
    jz .modulus
    mov r9, [r13 + LEN]
    cmp r9, CAP
    ja .length
    test r9, r9
    jz .inputs_ok_a
    cmp qword [r13 + WORDS + r9*8 - 8], 0
    jz .length
.inputs_ok_a:
    mov r9, [r14 + LEN]
    cmp r9, CAP
    ja .length
    test r9, r9
    jz .inputs_ok_b
    cmp qword [r14 + WORDS + r9*8 - 8], 0
    jz .length
.inputs_ok_b:
    mov rbx, r8

    ; Check a < modulus and b < modulus, comparing normalized lengths/words.
    mov r8, [r13 + LEN]
    cmp r8, rbx
    ja .range
    mov r8, [r14 + LEN]
    cmp r8, rbx
    ja .range

    ; t[0..2*CAP] at [rbp-544], initially zero.
    lea r8, [rbp-544]
    xor eax, eax
    mov r9d, 65
.zero_t:
    mov [r8], rax
    add r8, 8
    dec r9d
    jnz .zero_t

    ; Schoolbook t = a*b with carry propagation.
    xor r8d, r8d
.outer_i:
    mov r9, [r13 + WORDS + r8*8]
    xor r10d, r10d
    xor r11d, r11d
.inner_j:
    mov rax, r9
    mul qword [r14 + WORDS + r10*8]
    mov rsi, rdx
    lea rdx, [rbp-544 + r8*8]
    lea rdx, [rdx + r10*8]
    add rax, [rdx]
    adc r11, rsi
    mov [rdx], rax
    inc r10
    mov rcx, [r14 + LEN]
    cmp r10, rcx
    jb .inner_j
    lea rdx, [rbp-544 + r8*8]
    lea rdx, [rdx + r10*8]
.carry_mul:
    test r11, r11
    jz .next_i
    add [rdx], r11
    setc al
    movzx r11d, al
    inc r10
    add rdx, 8
    cmp r10, 65
    jb .carry_mul
.next_i:
    inc r8
    mov rcx, [r13 + LEN]
    cmp r8, rcx
    jb .outer_i

    ; n0' = -modulus[0] inverse modulo 2^64.
    mov r9, [r15 + WORDS]
    mov r10, 1
    mov ecx, 6
.inv_loop:
    mov rax, r10
    imul rax, r9
    mov r11, 2
    sub r11, rax
    imul r10, r11
    dec ecx
    jnz .inv_loop
    neg r10

    ; Montgomery reduction: for each low limb, add m*modulus shifted by i.
    xor r8d, r8d
.red_i:
    lea rdx, [rbp-544]
    mov rax, [rdx + r8*8]
    imul rax, r10
    mov r9, rax
    xor r11d, r11d
    xor ecx, ecx
.red_j:
    mov rax, r9
    mul qword [r15 + WORDS + rcx*8]
    mov rsi, rdx
    lea rdx, [rbp-544 + r8*8]
    lea rdx, [rdx + rcx*8]
    add rax, [rdx]
    adc r11, rsi
    mov [rdx], rax
    inc rcx
    cmp rcx, rbx
    jb .red_j
    lea rdx, [rbp-544 + r8*8]
    lea rdx, [rdx + rbx*8]
.red_carry:
    test r11, r11
    jz .red_next
    add [rdx], r11
    setc al
    movzx r11d, al
    inc rcx
    add rdx, 8
    cmp rcx, 65
    jb .red_carry
.red_next:
    inc r8
    cmp r8, rbx
    jb .red_i

    ; Candidate is t[k..2k], with t[2k] as an extra high limb.
    lea r8, [rbp-544]
    mov r9, [r8 + rbx*8*1]
    mov r10, rbx
.copy_candidate:
    mov rax, [r8 + r10*8]
    mov [rbp-288 + r10*8], rax
    inc r10
    cmp r10, rbx
    jb .copy_candidate
    lea rdx, [r8 + rbx*8]
    mov r10, [rdx + rbx*8]

    ; If candidate >= modulus, subtract modulus in the private workspace.
    test r10, r10
    jnz .do_sub
    mov r10, rbx
.compare:
    dec r10
    mov rax, [rbp-288 + r10*8]
    cmp rax, [r15 + WORDS + r10*8]
    ja .do_sub
    jb .commit
    test r10, r10
    jnz .compare
    jmp .do_sub
.do_sub:
    xor r11d, r11d
    xor r10d, r10d
.sub_loop:
    mov rax, [rbp-288 + r10*8]
    sub rax, [r15 + WORDS + r10*8]
    sbb r11, 0
    mov [rbp-288 + r10*8], rax
    inc r10
    cmp r10, rbx
    jb .sub_loop
.commit:
    ; Transactional full-capacity output commit.
    xor eax, eax
    lea r8, [r12 + WORDS]
    mov r9d, CAP
.zero_out:
    mov [r8], rax
    add r8, 8
    dec r9d
    jnz .zero_out
    xor r10d, r10d
.commit_words:
    mov rax, [rbp-288 + r10*8]
    mov [r12 + WORDS + r10*8], rax
    inc r10
    cmp r10, rbx
    jb .commit_words
    mov [r12 + LEN], rbx
.normalize:
    cmp qword [r12 + WORDS + rbx*8 - 8], 0
    jne .success
    dec rbx
    test rbx, rbx
    jnz .normalize
    mov qword [r12 + LEN], 0
.success:
    xor eax, eax
    jmp .epilogue
.null:
    mov eax, NULL_ARG
    jmp .epilogue
.length:
    mov eax, LENGTH
    jmp .epilogue
.modulus:
    mov eax, MODULUS
    jmp .epilogue
.range:
    mov eax, RANGE
.epilogue:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 544
    pop rbp
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
