/**
 * @file    test_bignum_template_runner.c
 * @author  git@bayborodov.com
 * @version 1.0.0
 * @date    03.12.2025
 *
 * @brief Интеграционный тест‑раннер для библиотеки libbignum_template.a.
 * @details Применяется для проверки достаточности сигнатур 
 *          в файле заголовка (header) при сборке и линковке
 *          статической библиотеки libbignum_template.a
 *
 * @history
 *   - rev. 1 (03.12.2025): Создание теста
 */  
#include "bignum_template.h"
#include <assert.h>
#include <stdio.h>  
int main() {
 printf("Running test: test_bignum_template_runner... "); 
 bignum_t num = {0}; 	
 bignum_template(&num, 5);  
 assert(1);
 printf("PASSED\n");   
 return 0;  
}