#include "bignum_montgomery_mul_benchmark_adapter.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    benchmark_adapter_t adapter;
    benchmark_workload_t w = {"custom", "nonzero", "montgomery", "kernel-only", "half", "normal", 7, 1, 2};
    assert(bignum_montgomery_mul_benchmark_adapter_init(&adapter) == 0);
    assert(adapter.initialize != NULL && adapter.operation != NULL && adapter.checksum != NULL);
    assert(bignum_montgomery_mul_benchmark_validate_workload(&w) == 0);
    unsigned char state[4096]; memset(state, 0, sizeof(state));
    assert(adapter.initialize(state, 0, &w, adapter.adapter_context) == BENCHMARK_ADAPTER_STATUS_SUCCESS);
    assert(adapter.operation(state, 0, &w, adapter.adapter_context) == BENCHMARK_ADAPTER_STATUS_SUCCESS);
    assert(adapter.checksum(state, 0, adapter.adapter_context) != 0);
    puts("bignum_montgomery_mul benchmark adapter tests: OK"); return 0;
}
