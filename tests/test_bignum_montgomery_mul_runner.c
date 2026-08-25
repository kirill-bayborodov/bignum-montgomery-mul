#include "bignum_montgomery_mul.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void set1(bignum_t *x, uint64_t v) { memset(x, 0, sizeof(*x)); x->len = v ? 1 : 0; x->words[0] = v; }
static int eq(const bignum_t *x, const bignum_t *y) { return memcmp(x, y, sizeof(*x)) == 0; }
static uint64_t step(uint64_t *s) { *s = *s * UINT64_C(6364136223846793005) + UINT64_C(1442695040888963407); return *s; }

static void test_known(void)
{
    bignum_t out, a, b, m, expected;
    set1(&a, 3); set1(&b, 4); set1(&m, 17);
    assert(bignum_montgomery_mul_c11(&out, &a, &b, &m) == 0);
    memset(&expected, 0, sizeof(expected));
    set1(&expected, (uint64_t)((((__uint128_t)3 * 4) << 64) % 17));
    assert(eq(&out, &expected));
}

static void test_contract(void)
{
    bignum_t out, before, a, b, m, bad;
    set1(&out, UINT64_C(0x55)); before = out; set1(&a, 2); set1(&b, 3); set1(&m, 16);
    assert(bignum_montgomery_mul_c11(&out, &a, &b, &m) == BIGNUM_MONTGOMERY_MUL_ERROR_MODULUS);
    assert(eq(&out, &before));
    set1(&m, 17); set1(&bad, 17); before = out;
    assert(bignum_montgomery_mul_c11(&out, &bad, &b, &m) == BIGNUM_MONTGOMERY_MUL_ERROR_RANGE);
    assert(eq(&out, &before));
    assert(bignum_montgomery_mul_c11(NULL, &a, &b, &m) == BIGNUM_MONTGOMERY_MUL_ERROR_NULL_ARG);
}

static void test_random(void)
{
    uint64_t seed = 7;
    for (size_t k = 1; k <= 8; ++k) {
        bignum_t a = {0}, b = {0}, m = {0}, out = {0}, asm_out = {0};
        m.len = k; for (size_t i = 0; i < k; ++i) m.words[i] = step(&seed);
        m.words[k - 1] |= UINT64_C(1) << 63; m.words[0] |= 1;
        a.len = b.len = 1; a.words[0] = step(&seed) % m.words[0]; b.words[0] = step(&seed) % m.words[0];
        assert(bignum_montgomery_mul_c11(&out, &a, &b, &m) == 0);
        assert(bignum_montgomery_mul(&asm_out, &a, &b, &m) == 0);
        assert(eq(&out, &asm_out));
    }
}

int main(void) { test_known(); test_contract(); test_random(); puts("=== Summary: 0 / 3 failed ==="); return 0; }
