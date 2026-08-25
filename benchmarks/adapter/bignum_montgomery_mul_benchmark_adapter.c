#include "bignum_montgomery_mul_benchmark_adapter.h"
#include "bignum_montgomery_mul.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>

typedef struct { bignum_t a, b, modulus, out; } montgomery_state_t;
static uint64_t mix(uint64_t x) { x ^= x >> 30; x *= UINT64_C(0xbf58476d1ce4e5b9); x ^= x >> 27; x *= UINT64_C(0x94d049bb133111eb); return x ^ (x >> 31); }
static int text_is(const char *s, const char *v) { return s != NULL && strcmp(s, v) == 0; }

bignum_montgomery_mul_benchmark_status_t bignum_montgomery_mul_benchmark_validate_workload(const benchmark_workload_t *w)
{
    if (w == NULL) return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_NULL_ARGUMENT;
    if (!text_is(w->operation_kind, "montgomery") && !text_is(w->operation_kind, "montgomery-random") && !text_is(w->operation_kind, "montgomery-mixed")) return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_INVALID_PROFILE;
    if (!text_is(w->size_profile, "one") && !text_is(w->size_profile, "quarter") && !text_is(w->size_profile, "half") && !text_is(w->size_profile, "variable") && !text_is(w->size_profile, "near-capacity")) return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_INVALID_PROFILE;
    return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_SUCCESS;
}

static benchmark_adapter_status_t initialize(void *state, uint64_t index, const benchmark_workload_t *w, void *ctx)
{
    montgomery_state_t *s = state; size_t k = 1; uint64_t seed; (void)ctx;
    if (s == NULL || w == NULL || bignum_montgomery_mul_benchmark_validate_workload(w) != BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_SUCCESS) return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    if (text_is(w->size_profile, "quarter")) k = BIGNUM_CAPACITY / 4;
    else if (text_is(w->size_profile, "half")) k = BIGNUM_CAPACITY / 2;
    else if (text_is(w->size_profile, "near-capacity")) k = BIGNUM_CAPACITY;
    else if (text_is(w->size_profile, "variable")) k = 1 + (index % BIGNUM_CAPACITY);
    memset(s, 0, sizeof(*s)); seed = mix(w->seed + index + 1); s->modulus.len = k;
    for (size_t i = 0; i < k; ++i) { seed = mix(seed + i); s->modulus.words[i] = seed; }
    s->modulus.words[k - 1] |= UINT64_C(1) << 63; s->modulus.words[0] |= 1;
    s->a.len = s->b.len = 1; s->a.words[0] = mix(seed + 1) % s->modulus.words[0]; s->b.words[0] = mix(seed + 2) % s->modulus.words[0];
    return BENCHMARK_ADAPTER_STATUS_SUCCESS;
}
static benchmark_adapter_status_t operation(void *state, uint64_t iteration, const benchmark_workload_t *w, void *ctx)
{
    montgomery_state_t *s = state; (void)iteration; (void)w; (void)ctx;
    if (s == NULL) return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    return bignum_montgomery_mul(&s->out, &s->a, &s->b, &s->modulus) == 0 ? BENCHMARK_ADAPTER_STATUS_SUCCESS : BENCHMARK_ADAPTER_STATUS_OPERATION_ERROR;
}
static uint64_t checksum(const void *state, uint64_t iteration, void *ctx)
{
    const montgomery_state_t *s = state; uint64_t h = mix(iteration + 1); (void)ctx; if (s == NULL) return 0;
    for (size_t i = 0; i < s->out.len; ++i) { h = mix(h ^ s->out.words[i]); } return h ^ s->out.len;
}
bignum_montgomery_mul_benchmark_status_t bignum_montgomery_mul_benchmark_adapter_init(benchmark_adapter_t *adapter)
{
    if (adapter == NULL) return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_NULL_ARGUMENT;
    memset(adapter, 0, sizeof(*adapter)); adapter->benchmark_name = "bignum_montgomery_mul"; adapter->state_size = sizeof(montgomery_state_t); adapter->success_code = BENCHMARK_ADAPTER_STATUS_SUCCESS; adapter->initialize = initialize; adapter->operation = operation; adapter->checksum = checksum;
    return BIGNUM_MONTGOMERY_MUL_BENCHMARK_STATUS_SUCCESS;
}
