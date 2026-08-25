/**
 * @file test_bignum_template_benchmark_adapter.c
 * @brief Deterministic unit tests for the bignum_template benchmark-core adapter.
 *
 * @details
 * The tests verify the public project-owned adapter contract without launching
 * a timed benchmark. They cover valid transport mapping, invalid/null inputs,
 * deterministic state initialization, successful in-place bignum operation,
 * and non-zero observable checksum creation.
 */
#include <stdint.h>
#include <stdio.h>

#include <bignum.h>
#include <benchmark_framework.h>

#include "bignum_template_benchmark_adapter.h"

/**
 * @brief Named outcomes returned by deterministic adapter test helpers.
 */
typedef enum {
    BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS = 0, /**< The test helper's assertions succeeded. */
    BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE = 1 /**< An observed adapter outcome differed from its contract. */
} bignum_template_adapter_test_status_t;

/**
 * @brief Construct a valid baseline bignum workload descriptor.
 * @param[out] workload Receives a complete immutable test workload.
 * @return A named bignum_template_adapter_test_status_t result.
 *
 * @details
 * The helper initializes every transport axis with a valid bignum-specific
 * value. The constant seed and small data count model a reproducible matrix
 * smoke configuration rather than a performance measurement configuration.
 */
static bignum_template_adapter_test_status_t bignum_template_adapter_test_make_workload(
    benchmark_workload_t *workload)
{
    if (workload == NULL) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    *workload = (benchmark_workload_t){
        .data_mode = "custom", /**< Adapter profile is explicitly selected. */
        .input_kind = "nonzero", /**< Generate normalized non-zero operands. */
        .operation_kind = "shift-bit", /**< Exercise a representable bit shift. */
        .measure_mode = "kernel-only", /**< Exclude preparation copies from timed work. */
        .size_profile = "quarter", /**< Generate a quarter-capacity operand length. */
        .capacity_profile = "normal", /**< Avoid boundary capacity pressure. */
        .seed = UINT64_C(11400714819323198485), /**< Stable deterministic source seed. */
        .warmup = UINT64_C(5), /**< Small unmeasured lifecycle warm-up count. */
        .data_count = 16U /**< Small deterministic cyclic source dataset. */
    };
    return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS;
}

/**
 * @brief Test accepted and rejected bignum transport vocabularies.
 * @return A named bignum_template_adapter_test_status_t result.
 *
 * @details
 * The algorithm validates a known-good workload, changes only operation_kind
 * to a generic byte-transform value, and verifies that the public validator
 * rejects it. It also verifies the documented NULL argument status.
 */
static bignum_template_adapter_test_status_t bignum_template_adapter_test_validation(void)
{
    benchmark_workload_t workload;
    benchmark_workload_t invalid_workload;

    if (bignum_template_adapter_test_make_workload(&workload) !=
        BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (bignum_template_benchmark_validate_workload(&workload) !=
        BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    invalid_workload = workload;
    invalid_workload.operation_kind = "xor";
    if (bignum_template_benchmark_validate_workload(&invalid_workload) !=
        BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (bignum_template_benchmark_validate_workload(NULL) !=
        BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS;
}

/**
 * @brief Test adapter callback construction and one deterministic operation lifecycle.
 * @return A named bignum_template_adapter_test_status_t result.
 *
 * @details
 * The helper builds the public benchmark-core binding, initializes one state
 * from the baseline workload, invokes the measured operation callback, and
 * obtains its observable checksum. It repeats initialization with the same
 * sequence index and compares complete bignum_t records for reproducibility.
 */
static bignum_template_adapter_test_status_t bignum_template_adapter_test_callbacks(void)
{
    benchmark_adapter_t adapter;
    benchmark_workload_t workload;
    bignum_t first_state;
    bignum_t second_state;
    uint64_t checksum;

    if (bignum_template_benchmark_adapter_init(NULL) !=
        BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (bignum_template_benchmark_adapter_init(&adapter) !=
        BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS || adapter.initialize == NULL ||
        adapter.operation == NULL || adapter.checksum == NULL ||
        adapter.state_size != sizeof(bignum_t)) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (bignum_template_adapter_test_make_workload(&workload) !=
        BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (adapter.initialize(&first_state, UINT64_C(3), &workload, adapter.adapter_context) !=
        BENCHMARK_ADAPTER_STATUS_SUCCESS ||
        adapter.initialize(&second_state, UINT64_C(3), &workload, adapter.adapter_context) !=
        BENCHMARK_ADAPTER_STATUS_SUCCESS) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    if (first_state.len == 0U || first_state.len != second_state.len) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    for (size_t word = 0U; word < BIGNUM_CAPACITY; ++word) {
        if (first_state.words[word] != second_state.words[word]) {
            return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
        }
    }
    if (adapter.operation(&first_state, UINT64_C(7), &workload, adapter.adapter_context) !=
        BENCHMARK_ADAPTER_STATUS_SUCCESS) {
        return BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE;
    }
    checksum = adapter.checksum(&first_state, UINT64_C(7), adapter.adapter_context);
    return checksum == 0U
        ? BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_FAILURE
        : BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS;
}

/**
 * @brief Run all deterministic adapter assertions.
 * @return EXIT_SUCCESS when all named test helpers succeed; EXIT_FAILURE otherwise.
 *
 * @details
 * ISO C main is the sole function returning int. It invokes each test helper
 * sequentially, prints a concise diagnostic on the first failure, and keeps
 * every non-main project function within the named-status convention.
 */
int main(void)
{
    if (bignum_template_adapter_test_validation() !=
        BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS) {
        fputs("bignum_template benchmark adapter validation test failed\n", stderr);
        return 1;
    }
    if (bignum_template_adapter_test_callbacks() !=
        BIGNUM_TEMPLATE_ADAPTER_TEST_STATUS_SUCCESS) {
        fputs("bignum_template benchmark adapter callback test failed\n", stderr);
        return 1;
    }
    puts("bignum_template benchmark adapter tests: OK");
    return 0;
}
