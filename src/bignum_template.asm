; -----------------------------------------------------------------------------
; @file    bignum_template.asm
; @author  git@bayborodov.com
; @version 1.0.0
; @date    24.06.2026
;
; @brief   Низкоуровневая реализация логического сдвига bignum_t влево.
;
; @details
;   Эталонная ассемблерная реализация для Yasm x86-64 (System V ABI).
;
; @history
;   - rev. 1 (04.08.2025): Первоначальная реализация на ассемблере.
;   - rev. 2 (04.08.2025): Рефакторинг по результатам ревью.
;   - rev. 3 (04.08.2025): Исправлена ошибка "invalid effective address".
;   - rev. 4 (04.08.2025): Повторное исправление "invalid effective address".
;   - rev. 5 (04.08.2025): Финальное исправление синтаксической ошибки.
;   - rev. 6 (04.08.2025): Исправлена логическая ошибка в проверке на
;                         переполнение и предупреждение компиляции.
;   - rev. 7 (04.08.2025): Рефакторинг по ревью: заменен `rep movsq`,
;                         оптимизирован битовый сдвиг, улучшен стиль.
;   - rev. 8 (04.08.2025): Исправлена ошибка "invalid combination of opcode".
;   - rev. 9 (04.08.2025): Исправлена регрессия с "invalid effective address".
;   - rev. 10 (04.08.2025): Окончательное исправление ошибки "invalid
;                          effective address", код прошел все тесты.
;   - rev. 11 (04.08.2025): Финальный аудит документации. Восстановлена полная
;                          история ревизий, уточнены комментарии.
;   - rev. 12 (05.08.2025): Оптимизация (Этап 1): Минимизировано количество
;                          сохраняемых регистров. Убраны rbx, r12-r15.
;   - rev. 13 (05.08.2025): Исправлена регрессия в rev. 12: `rdi` портился
;                          инструкцией `rep stosq`. `rdi` теперь сохраняется
;                          в `r11` перед блоком `zero_fill`.
;   - rev. 14 (14.08.2025): Уточнение арифметики указателей блоке word-shift:
;                          расчёт rbx = r11 – (word_shift * 8) теперь через lea и neg.
;                          Сделано упрощение error-paths,
;                          сохраняются rbx и r11-r15 в прологе-епилоге,
;                          описаны @clobbers и @retval в документации функции.
;   - rev. 15 (15.08.2025): В ветке ПУТЬ ДЛЯ bit_shift == 0 оптимизирована
;                          прямая копия с распаковкой ×4 вместо rep movsq
;   - rev. 16 (15.08.2025): Заменили операцию деления div на дешевый вариант
;                          с комбинацией shr+and в расчете word_shift и bit_shift
;   - rev. 17 (29.09.2025): Оптимизация (Этап 2): оптимизированный подход,
;                          который объединяет сдвиг по словам и битам в один проход
;   - rev. 18 (07.11.2025): Removed version control functions and .data section
;   - rev. 19 (24.06.2026): COMPACT/CMOV/BRANCHLESS-вариант.
;                          Удалены .word_shift_only_path / .fill_zeros_only_path
;                          и `rep stosq`. Объединены word-shift и bit-shift в
;                          один проход. Тривиальные случаи и ограничение
;                          new_len выражены через cmov/setcc.
;   - rev. 20 (24.06.2026): Реальный branchless в word-shift: цикл разбит на
;                          два простых (copy + zero-fill), без ветвлений
;                          внутри итерации. Адрес назначения держится в r15
;                          и сдвигается через sub r15, 8 (без lea в цикле).
;                          Убран push/pop r11 (caller-saved, не нужен).
; -----------------------------------------------------------------------------

section .text

; =============================================================================
; @brief      Выполняет логический сдвиг большого числа влево.
;
; @details
;   **Алгоритм (rev. 19, CMOV/branchless):**
;   1.  Проверка указателя на NULL.
;   2.  Проверка на переполнение:
;       a. Если `shift_amount` >= 2048, вернуть OVERFLOW.
;       b. Если `len` == 32, старший бит старшего слова установлен и
;          `shift_amount` > 0, вернуть OVERFLOW.
;   3.  Branchless-проверка тривиальных случаев (len==0 или shift==0).
;   4.  Расчёт word_shift / bit_shift без div.
;   5.  Расчёт new_len и clamp к BIGNUM_CAPACITY через cmov.
;   6.  **Один проход**: одновременный word-shift + zero-fill старших слов.
;   7.  Bit-shift in-place справа налево с branchless carry.
;   8.  Нормализация: убираем ведущие нули.
;
; @abi        System V AMD64 ABI
; @param[in]  rdi: bignum_t* restrict num (указатель на структуру)
; @param[in]  rsi: size_t shift_amount (величина сдвига)
;
; @return     rax: bignum_template_status_t (0, -1 или -2)
; @retval 0  – success
; @retval -1 – null pointer
; @retval -2 – overflow
; @clobbers   rbx, rcx, rdx, r8–r15
; =============================================================================

; --- Константы ---
BIGNUM_CAPACITY         equ 32
BIGNUM_WORD_SIZE        equ 8
BIGNUM_BITS             equ BIGNUM_CAPACITY * 64
BIGNUM_OFFSET_WORDS     equ 0
BIGNUM_OFFSET_LEN       equ BIGNUM_CAPACITY * BIGNUM_WORD_SIZE
SUCCESS                 equ 0
ERROR_NULL_ARG          equ -1
ERROR_OVERFLOW          equ -2

global bignum_template
bignum_template:
    ; --- Пролог: сохраняем только callee-saved регистры (r11 — caller-saved) ---
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; rdi = num*, rsi = shift_amount

    ; 1. Проверка на NULL
    test    rdi, rdi
    jz      .error_null_arg

    ; -------------------------------------------------
    ;   Базовый адрес массива слов
    ; -------------------------------------------------
    lea     rbx, [rdi + BIGNUM_OFFSET_WORDS]   ; rbx = &num->words[0]

    ; 2. Проверка контракта на переполнение
    cmp     rsi, BIGNUM_BITS
    jae     .error_overflow

    movsxd  r8, dword [rdi + BIGNUM_OFFSET_LEN] ; r8 = num->len
    cmp     r8, BIGNUM_CAPACITY
    jne     .check_trivial_cases

    mov     r9, [rdi + BIGNUM_OFFSET_WORDS + (BIGNUM_CAPACITY - 1) * BIGNUM_WORD_SIZE]
    mov     r10, 0x8000000000000000
    test    r9, r10
    jz      .check_trivial_cases

    cmp     rsi, 0
    jne     .error_overflow

.check_trivial_cases:
    ; 3. Branchless: success, если len==0 ИЛИ shift==0
    test    r8, r8
    setz    al
    test    esi, esi
    setz    cl
    or      al, cl
    jnz     .success

    ; 4. word_shift = shift >> 6, bit_shift = shift & 63 (без div)
    mov     rax, rsi
    shr     rax, 6
    mov     r12, rax                       ; r12 = word_shift
    mov     r13d, esi
    and     r13d, 0x3F                     ; r13d = bit_shift (0..63)

    ; 5. new_len = old_len + word_shift + (bit_shift?1:0), clamp к CAPACITY
    lea     r9, [r8 + r12]                 ; r9 = old_len + word_shift
    xor     ecx, ecx
    test    r13d, r13d
    setnz   cl
    add     r9, rcx
    mov     edx, BIGNUM_CAPACITY
    cmp     r9, rdx
    cmovb   edx, r9d                       ; edx = min(new_len, CAPACITY)
    mov     r9d, edx

    ; -------------------------------------------------
    ; 6. Word-shift в ДВА простых branchless-цикла.
    ;    Сверху вниз, по убыванию индекса, чтобы src < dst и
    ;    источник не затирался раньше времени.
    ;    Адрес назначения держим в r15 и сдвигаем sub r15, 8.
    ;
    ;    6a) Копирование существующих слов:
    ;          for i = old_len-1 .. 0:
    ;              words[i + word_shift] = words[i]
    ;    6b) Zero-fill младших слов:
    ;          for i = word_shift-1 .. 0:
    ;              words[i] = 0
    ; -------------------------------------------------

    ; 6a) Копирование
    mov     r14, BIGNUM_CAPACITY           ; r14 = 32
    sub     r14, r12                       ; r14 = 32 - word_shift
    cmp     r14, r8                        ; сравниваем (32 - word_shift) и old_len
    cmova   r14, r8                        ; r14 = min(old_len, 32 - word_shift)
      
    lea     r15, [rbx + r14*8]             ; r15 = &words[copy_len]
    lea     r15, [r15 + r12*8]             ; r15 = &words[copy_len + word_shift]

.L_ws_copy:
    dec     r14
    sub     r15, 8
    mov     rax, [rbx + r14*8]             ; rax = words[i]  (источник)
    mov     [r15], rax                     ; words[i+word_shift] = words[i]
    test    r14, r14
    jnz     .L_ws_copy

    ; 6b) Zero-fill младших слов (от word_shift-1 до 0)
.L_ws_zfill:
    test    r12, r12
    jz      .L_bs_check                    ; word_shift == 0 → сразу к bit-shift
    mov     r14, r12                       ; r14 = word_shift
    xor     eax, eax                       ; пишем 0
.L_ws_zfill_loop:
    dec     r14
    mov     [rbx + r14*8], rax
    test    r14, r14
    jnz     .L_ws_zfill_loop

    ; -------------------------------------------------
    ; 7. Bit-shift in-place, справа налево, branchless carry.
    ;    Если bit_shift == 0 — пропускаем.
    ; -------------------------------------------------
.L_bs_check:
    test    r13d, r13d
    jz      .update_len_and_normalize

    xor     r14, r14                       ; carry = 0
    xor     r10, r10                       ; i = 0
    mov     ecx, r13d                      ; cl = bit_shift

.L_bit_shift:
    mov     rax, [rbx + r10*8]             ; текущее слово
    mov     rdx, rax                       ; сохраняем оригинал для carry
    shl     rax, cl
    or      rax, r14                       ; + carry из младшего слова
    mov     [rbx + r10*8], rax

    ; new_carry = top (64 - bit_shift) бит оригинала
    mov     r11d, 64
    sub     r11d, ecx                      ; r11d = 64 - cl
    mov     cl, r11b                       ; cl = 64 - bit_shift
    shr     rdx, cl                        ; rdx = original >> (64 - bit_shift)
    mov     r14, rdx                       ; carry для следующей итерации
    mov     cl, r13b                       ; восстановили bit_shift

    inc     r10
    cmp     r10, r9
    jb      .L_bit_shift

.update_len_and_normalize:
    ; 8. Сохраняем new_len и убираем ведущие нули.
    mov     [rdi + BIGNUM_OFFSET_LEN], r9d

.normalize_loop:
    cmp     r9, 1
    jle     .success
    cmp     qword [rdi + r9 * BIGNUM_WORD_SIZE - BIGNUM_WORD_SIZE], 0
    jne     .success
    dec     r9
    mov     [rdi + BIGNUM_OFFSET_LEN], r9d
    jmp     .normalize_loop

.error_null_arg:
    mov     eax, ERROR_NULL_ARG
    jmp     .epilogue

.error_overflow:
    mov     eax, ERROR_OVERFLOW
    jmp     .epilogue

.success:
    xor     eax, eax                       ; rax = 0 (SUCCESS), флаги сброшены

.epilogue:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .note.GNU-stack noalloc noexec nowrite progbits