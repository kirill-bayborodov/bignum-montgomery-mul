#include "bignum_montgomery_mul.h"

#include <stdint.h>
#include <string.h>

static int normalized(const bignum_t *x)
{
    if (x->len > BIGNUM_CAPACITY) return 0;
    if (x->len == 0) return 1;
    return x->words[x->len - 1] != 0;
}

static int cmp_words(const uint64_t *a, size_t alen,
                     const uint64_t *b, size_t blen)
{
    while (alen > 0 && a[alen - 1] == 0) --alen;
    while (blen > 0 && b[blen - 1] == 0) --blen;
    if (alen != blen) return alen < blen ? -1 : 1;
    while (alen > 0) {
        --alen;
        if (a[alen] != b[alen]) return a[alen] < b[alen] ? -1 : 1;
    }
    return 0;
}

static uint64_t neg_inv64(uint64_t n)
{
    uint64_t x = n;
    x *= 2U - n * x;
    x *= 2U - n * x;
    x *= 2U - n * x;
    x *= 2U - n * x;
    x *= 2U - n * x;
    x *= 2U - n * x;
    return (uint64_t)(0U - x);
}

static void normalize(bignum_t *x)
{
    while (x->len > 0 && x->words[x->len - 1] == 0) --x->len;
}

bignum_montgomery_mul_status_t bignum_montgomery_mul_c11(
    bignum_t *restrict out, const bignum_t *a, const bignum_t *b,
    const bignum_t *modulus)
{
    uint64_t t[2 * BIGNUM_CAPACITY + 2] = {0};
    uint64_t reduced[BIGNUM_CAPACITY] = {0};
    bignum_t candidate = {0};
    size_t k;

    if (out == NULL || a == NULL || b == NULL || modulus == NULL)
        return BIGNUM_MONTGOMERY_MUL_ERROR_NULL_ARG;
    if (!normalized(a) || !normalized(b) || !normalized(modulus))
        return BIGNUM_MONTGOMERY_MUL_ERROR_LENGTH;
    k = modulus->len;
    if (k == 0 || (modulus->words[0] & 1U) == 0)
        return BIGNUM_MONTGOMERY_MUL_ERROR_MODULUS;
    if (a->len > k || b->len > k ||
        cmp_words(a->words, a->len, modulus->words, k) >= 0 ||
        cmp_words(b->words, b->len, modulus->words, k) >= 0)
        return BIGNUM_MONTGOMERY_MUL_ERROR_RANGE;

    for (size_t i = 0; i < a->len; ++i) {
        __uint128_t carry = 0;
        for (size_t j = 0; j < b->len; ++j) {
            __uint128_t v = (__uint128_t)a->words[i] * b->words[j]
                          + t[i + j] + carry;
            t[i + j] = (uint64_t)v;
            carry = v >> 64;
        }
        for (size_t p = i + b->len; carry != 0 && p < 2 * k + 1; ++p) {
            __uint128_t v = (__uint128_t)t[p] + carry;
            t[p] = (uint64_t)v;
            carry = v >> 64;
        }
    }

    uint64_t inv = neg_inv64(modulus->words[0]);
    for (size_t i = 0; i < k; ++i) {
        uint64_t m = t[i] * inv;
        __uint128_t carry = 0;
        for (size_t j = 0; j < k; ++j) {
            __uint128_t v = (__uint128_t)m * modulus->words[j]
                          + t[i + j] + carry;
            t[i + j] = (uint64_t)v;
            carry = v >> 64;
        }
        for (size_t p = i + k; carry != 0 && p < 2 * k + 1; ++p) {
            __uint128_t v = (__uint128_t)t[p] + carry;
            t[p] = (uint64_t)v;
            carry = v >> 64;
        }
    }

    for (size_t i = 0; i <= k; ++i)
        candidate.words[i] = (i < k) ? t[k + i] : t[2 * k];
    candidate.len = k;
    if (candidate.words[k] != 0 ||
        cmp_words(candidate.words, k, modulus->words, k) >= 0) {
        uint64_t borrow = 0;
        for (size_t i = 0; i < k; ++i) {
            uint64_t m = modulus->words[i];
            uint64_t x = candidate.words[i];
            uint64_t y = x - m - borrow;
            borrow = (x < m) || (borrow && x == m);
            reduced[i] = y;
        }
        memcpy(candidate.words, reduced, k * sizeof(uint64_t));
    }
    normalize(&candidate);
    memcpy(out, &candidate, sizeof(candidate));
    return BIGNUM_MONTGOMERY_MUL_SUCCESS;
}

#ifndef BIGNUM_MONTGOMERY_MUL_ASM
bignum_montgomery_mul_status_t bignum_montgomery_mul(
    bignum_t *restrict out, const bignum_t *a, const bignum_t *b,
    const bignum_t *modulus)
{
    return bignum_montgomery_mul_c11(out, a, b, modulus);
}
#endif
