/**
 * @file bench_bignum_montgomery_mul_mt.c
 * @brief ISO C entry point for the multi-thread bignum_montgomery_mul benchmark.
 *
 * @details
 * The entry point creates the project-owned bignum adapter and delegates the
 * complete MT lifecycle, independent source copies, barriers, timing, and
 * protocol publication to benchmark-core from the pinned
 * benchmark-framework v1.0.0 submodule.
 */
#include <stdlib.h>

#include <benchmark_framework.h>

#include "adapter/bignum_montgomery_mul_benchmark_adapter.h"

/**
 * @brief Map named adapter/core outcomes to the ISO C process exit convention.
 * @param argc Number of process arguments.
 * @param argv Process argument vector.
 * @return EXIT_SUCCESS for a completed run or help request; EXIT_FAILURE otherwise.
 *
 * @details
 * ISO C defines main as the only function in this executable that returns an
 * int. All project-owned non-main functions return named status enums. The
 * algorithm initializes a complete adapter binding and asks benchmark-core to
 * allocate isolated per-worker copies before executing the bignum operation.
 */
int main(int argc, char **argv)
{
    benchmark_adapter_t adapter;
    bignum_montgomery_mul_benchmark_status_t adapter_status;
    benchmark_core_status_t core_status;

    adapter_status = bignum_montgomery_mul_benchmark_adapter_init(&adapter);
    if (adapter_status != BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_SUCCESS) {
        return EXIT_FAILURE;
    }
    core_status = benchmark_core_run_mt(argc, argv, &adapter);
    return core_status == BENCHMARK_CORE_STATUS_SUCCESS ||
        core_status == BENCHMARK_CORE_STATUS_HELP
        ? EXIT_SUCCESS
        : EXIT_FAILURE;
}
