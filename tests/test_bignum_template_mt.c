/**
 * @file    test_bignum_template_mt.c
 * @author  git@bayborodov.com
 * @version 1.0.0
 * @date    03.10.2025
 *
 * @brief   Тест на потокобезопасность для модуля bignum_template.
 *
 * @details
 *   Тест создает несколько потоков, каждый из которых многократно
 *   выполняет операцию сдвига над своим собственным, уникальным
 *   экземпляром `bignum_t`. После завершения всех потоков проверяется,
 *   что конечный результат в каждом `bignum_t` соответствует ожидаемому.
 *   Это доказывает, что функция является reentrant и не использует
 *   глобальное или статическое состояние, которое могло бы привести
 *   к гонке данных.
 *
 * @history
 *   - rev. 1 (02.08.2025): Первоначальное создание теста.
 */

#include "bignum_template.h"
#include <stdio.h>
#include <pthread.h>
#include <assert.h>
#include <string.h>

#define NUM_THREADS 8
#define NUM_ITERATIONS 10000

typedef struct {
    bignum_t num;
    bignum_t expected;
    int thread_id;
} thread_data_t;

// Вспомогательная функция для сравнения
static int bignum_are_equal(const bignum_t* a, const bignum_t* b) {
    if (a->len != b->len) return 0;
    if (a->len == 0) return 1;
    return memcmp(a->words, b->words, a->len * sizeof(uint64_t)) == 0;
}

void* worker_thread(void* arg) {
    thread_data_t* data = (thread_data_t*)arg;

    for (int i = 0; i < NUM_ITERATIONS; ++i) {
        // Каждый поток сдвигает на 1 бит
        bignum_template(&data->num, 1);
    }

    return NULL;
}

int main() {
    printf("--- Starting MT test for bignum_template 1.0.0 ---\n");

    pthread_t threads[NUM_THREADS];
    thread_data_t thread_data[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; ++i) {
        thread_data[i].thread_id = i;
        // Уникальное начальное значение для каждого потока
        thread_data[i].num.len = 1;
        thread_data[i].num.words[0] = (uint64_t)(i + 1);
        memset(thread_data[i].num.words + 1, 0, (BIGNUM_CAPACITY - 1) * sizeof(uint64_t));

        // Рассчитываем ожидаемый результат
        //thread_data[i].expected = thread_data[i].num;
        //bignum_template(&thread_data[i].expected, NUM_ITERATIONS);

        // Рассчитываем ожидаемый результат так же, как это делает поток
        thread_data[i].expected = thread_data[i].num;
        for (int j = 0; j < NUM_ITERATIONS; ++j) {
            bignum_template(&thread_data[i].expected, 1);
        }


        pthread_create(&threads[i], NULL, worker_thread, &thread_data[i]);
    }

    for (int i = 0; i < NUM_THREADS; ++i) {
        pthread_join(threads[i], NULL);
    }

    // Проверка результатов
    for (int i = 0; i < NUM_THREADS; ++i) {
        assert(bignum_are_equal(&thread_data[i].num, &thread_data[i].expected));
    }

    printf("--- MT test for bignum_template 1.0.0 passed ---\n");
    return 0;
}
