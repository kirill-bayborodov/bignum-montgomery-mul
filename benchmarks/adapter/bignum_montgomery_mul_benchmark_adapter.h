#ifndef BIGNUM_MONTGOMERY_MUL_BENCHMARK_ADAPTER_H
#define BIGNUM_MONTGOMERY_MUL_BENCHMARK_ADAPTER_H
#include <benchmark_framework.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef enum {
    BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_SUCCESS = 0,
    BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_NULL_ARGUMENT = 1,
    BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_INVALID_PROFILE = 2,
    BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_OPERATION_ERROR = 3
} bignum_montgomery_mul_benchmark_status_t;
bignum_montgomery_mul_benchmark_status_t bignum_montgomery_mul_benchmark_adapter_init(benchmark_adapter_t *adapter);
bignum_montgomery_mul_benchmark_status_t bignum_montgomery_mul_benchmark_validate_workload(const benchmark_workload_t *workload);
#ifdef __cplusplus
}
#endif
#endif
