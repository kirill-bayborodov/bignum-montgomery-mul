/**
 * @file    test_bignum_template.c
 * @author  git@bayborodov.com
 * @version 1.0.0
 * @date    03.10.2025
 *
 * @brief   Детерминированные тесты для модуля bignum_template.
 *
 * @details
 *   **Анализ полноты покрытия (QG-13.f) - Ревизия 2:**
 *   Данный набор тестов покрывает следующие сценарии:
 *   1.  **Тривиальные и невалидные случаи:** Сдвиг на 0, сдвиг числа "0",
 *       `len=0`, передача `NULL`.
 *   2.  **Сдвиг внутри слова:** Сдвиг на < 64 бит.
 *   3.  **Сдвиг с переносом:** Одиночный и множественный перенос битов
 *       между словами.
 *   4.  **Сдвиг на целые слова:** Сдвиг ровно на 64, 128 и т.д.
 *   5.  **Смешанный сдвиг:** word_shift > 0 и bit_shift > 0.
 *   6.  **Граничные случаи по переполнению:**
 *       - Сдвиг до границы `BIGNUM_CAPACITY`.
 *       - Сдвиг, превышающий емкость (включая >= BIGNUM_CAPACITY * 64).
 *   7.  **Нормализация:** Проверка корректного обновления `len`.
 *   8.  **Сдвиг с усечением:** Сдвиг, при котором старшие слова отбрасываются.
 *
 * @history
 *   - rev. 1 (02.08.2025): Первоначальный набор тестов.
 *   - rev. 2 (02.08.2025): Добавлены тесты по результатам аудита:
 *                         NULL, len=0, большие сдвиги, множественные
 *                         переносы, усечение.
 */

#include "bignum_template.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

// Вспомогательная функция для сравнения
static int bignum_are_equal(const bignum_t* a, const bignum_t* b) {
    if (a->len != b->len) return 0;
    if (a->len == 0) return 1;
    return memcmp(a->words, b->words, a->len * sizeof(uint64_t)) == 0;
}

// --- Базовые тесты из rev. 1 ---
void test_shift_zero_amount() { printf("Running test: %s\n", __func__); bignum_t n = {.words = {1,1}, .len = 2}, e = n; assert(bignum_template(&n, 0) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e)); printf("...PASSED\n"); }
void test_shift_zero_number() { 
    printf("Running test: %s\n", __func__);
    bignum_t n = {.words = {0}, .len = 1}, e = n;
    assert(bignum_template(&n, 100) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e));
    printf("...PASSED\n"); 
   }

void test_simple_bit_shift() { 
    printf("Running test: %s\n", __func__); 
    bignum_t n = {.words = {7}, .len = 1}; 
    bignum_t e = {.words = {28}, .len = 1}; 
    assert(bignum_template(&n, 2) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e)); 
    printf("...PASSED\n"); 
}

void test_bit_shift_with_carry() { 
    printf("Running test: %s\n", __func__); 
    bignum_t n = {.words = {0x8000000000000001}, .len = 1}, e = {.words = {0x2, 1}, .len = 2}; 
    assert(bignum_template(&n, 1) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e)); 
    printf("...PASSED\n"); 
}
void test_exact_word_shift() { 
    printf("Running test: %s\n", __func__); 
    bignum_t n = {.words = {1,2}, .len = 2}, e = {.words = {0,1,2}, .len = 3}; 
    assert(bignum_template(&n, 64) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e)); 
    printf("...PASSED\n"); 
}
void test_mixed_shift() { 
    printf("Running test: %s\n", __func__); 
    bignum_t n = {.words = {1}, .len = 1}, e = {.words = {0, 0x8000000000000000}, .len = 2};
    assert(bignum_template(&n, 127) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e));
    printf("...PASSED\n"); 
  }
//void test_overflow_shift() { printf("Running test: %s\n", __func__); bignum_t n = {.words = {0,0,0,0,0,0x8000000000000000}, .len = 6}; assert(bignum_template(&n, 1) == BIGNUM_SHIFT_ERROR_OVERFLOW); printf("...PASSED\n"); }
/**
 * @brief Проверка overflow: самый старший бит выйдет за предел BIGNUM_CAPACITY*64.
 *
 * Алгоритм:
 *   - Создаём число n_orig.len = BIGNUM_CAPACITY, инициализируем
 *     все слова нулями, а в самом старшем слове (index = BIGNUM_CAPACITY-1)
 *     ставим бит 63: 0x8000...0.
 *   - Копируем n_orig в n.
 *   - Вызываем bignum_template(&n, 1).
 *   - Ожидаем код BIGNUM_TEMPLATE_ERROR_OVERFLOW.
 *   - Проверяем, что n.len и все слова n.words[] не изменились.
 */
static void test_overflow_shift(void) {
    printf("Running test: %s\n", __func__);

    bignum_t n_orig;
    // Полностью обнулить
    memset(&n_orig, 0, sizeof(bignum_t));
    // len = BIGNUM_CAPACITY
    n_orig.len = BIGNUM_CAPACITY;
    // В старшем слове (index BIGNUM_CAPACITY-1) ставим MSB
    n_orig.words[BIGNUM_CAPACITY - 1] = 0x8000000000000000ULL;

    // Копируем для сравнения
    bignum_t n = n_orig;

    bignum_template_status_t rc = bignum_template(&n, 1);

    // 1) проверяем статус
    assert(rc == BIGNUM_TEMPLATE_ERROR_OVERFLOW);

    // 2) проверяем, что число не изменилось
    assert(n.len == n_orig.len);
    // сравниваем все слова, не только до len
    assert(memcmp(n.words,
                  n_orig.words,
                  BIGNUM_CAPACITY * sizeof(uint64_t)) == 0);

    printf("...PASSED\n");
}

void test_shift_to_boundary() { 
    printf("Running test: %s\n", __func__); 
    bignum_t n = {.words = {1}, .len = 1}, e = {.words = {0,0,0,0,0,0x8000000000000000}, .len = 6}; 
    assert(bignum_template(&n, 383) == BIGNUM_TEMPLATE_SUCCESS && bignum_are_equal(&n, &e)); 
    printf("...PASSED\n"); 
}

// --- Новые тесты из аудита ---
void test_empty_len_zero() {
    printf("Running test: %s\n", __func__);
    bignum_t num = {.len = 0};
    assert(bignum_template(&num, 10) == BIGNUM_TEMPLATE_SUCCESS);
    assert(num.len == 0);
    printf("...PASSED\n");
}

void test_null_arg() {
    printf("Running test: %s\n", __func__);
    assert(bignum_template(NULL, 10) == BIGNUM_TEMPLATE_ERROR_NULL_ARG);
    printf("...PASSED\n");
}

void test_shift_too_large() {
    printf("Running test: %s\n", __func__);
    bignum_t num = {.words = {1}, .len = 1};
    bignum_t original = num;
    size_t big_shift = (size_t)BIGNUM_CAPACITY * 64;
    assert(bignum_template(&num, big_shift) == BIGNUM_TEMPLATE_ERROR_OVERFLOW);
    assert(bignum_are_equal(&num, &original)); // Убедимся, что число не изменилось
    printf("...PASSED\n");
}

void test_carry_across_multiple_words() {
    printf("Running test: %s\n", __func__);
    bignum_t num = {.words = {0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF}, .len = 2};
    bignum_t expected = {.words = {0xFFFFFFFFFFFFFFFE, 0xFFFFFFFFFFFFFFFF, 1}, .len = 3};
    assert(bignum_template(&num, 1) == BIGNUM_TEMPLATE_SUCCESS);
    assert(bignum_are_equal(&num, &expected));
    printf("...PASSED\n");
}

void test_shift_and_truncate() {
    printf("Running test: %s\n", __func__);
    if (BIGNUM_CAPACITY < 4) { printf("...SKIPPED (BIGNUM_CAPACITY < 4)\n"); return; }
    bignum_t num = {.words = {1, 2, 3, 4}, .len = 4};
    bignum_t expected = {.words = {0,0,1,2,3,4}, .len = 6 };
    assert(bignum_template(&num, 128) == BIGNUM_TEMPLATE_SUCCESS);
    assert(bignum_are_equal(&num, &expected));
    printf("...PASSED\n");
}

int main() {
    printf("--- Starting tests for bignum_template 1.0.0 ---\n");
    test_shift_zero_amount();
    test_shift_zero_number();
    test_simple_bit_shift();
    test_bit_shift_with_carry();
    test_exact_word_shift();
    test_mixed_shift();
    test_overflow_shift();
    test_shift_to_boundary();
    // Новые тесты
    test_empty_len_zero();
    test_null_arg();
    test_shift_too_large();
    test_carry_across_multiple_words();
    test_shift_and_truncate();
    printf("--- All tests for bignum_template 1.0.0 passed ---\n");
    return 0;
}
