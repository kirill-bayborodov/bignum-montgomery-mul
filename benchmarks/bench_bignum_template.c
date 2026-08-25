/**
 * @file bench_bignum_template.c
 * @brief ISO C entry point for the single-thread bignum_template benchmark.
 *
 * @details
 * The entry point creates the project-owned bignum adapter and delegates the
 * complete ST lifecycle to benchmark-core from the pinned
 * benchmark-framework v1.0.0 submodule. benchmark-core prints the required
 * machine-readable `benchmark=` line followed by `Benchmark finished.` only
 * after a successful run.
 */
#include <stdlib.h>

#include <benchmark_core.h>

#include "adapter/bignum_template_benchmark_adapter.h"

/**
 * @brief Map named adapter/core outcomes to the ISO C process exit convention.
 * @param argc Number of process arguments.
 * @param argv Process argument vector.
 * @return EXIT_SUCCESS for a completed run or help request; EXIT_FAILURE otherwise.
 *
 * @details
 * ISO C defines main as the only function in this executable that returns an
 * int. All project-owned non-main functions return named status enums. The
 * algorithm initializes an all-fields-valid benchmark_adapter_t, invokes the
 * benchmark-core ST lifecycle, and maps only its public SUCCESS/HELP results
 * to a successful process exit.
 */
int main(int argc, char **argv)
{
    benchmark_adapter_t adapter;
    bignum_template_benchmark_status_t adapter_status;
    benchmark_core_status_t core_status;

    adapter_status = bignum_template_benchmark_adapter_init(&adapter);
    if (adapter_status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return EXIT_FAILURE;
    }
    core_status = benchmark_core_run_st(argc, argv, &adapter);
    return core_status == BENCHMARK_CORE_STATUS_SUCCESS ||
        core_status == BENCHMARK_CORE_STATUS_HELP
        ? EXIT_SUCCESS
        : EXIT_FAILURE;
}
