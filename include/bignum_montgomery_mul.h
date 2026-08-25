#ifndef BIGNUM_MONTGOMERY_MUL_H
#define BIGNUM_MONTGOMERY_MUL_H

#include <stddef.h>
#include "bignum.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BIGNUM_MONTGOMERY_MUL_SUCCESS = 0,
    BIGNUM_MONTGOMERY_MUL_ERROR_NULL_ARG = -1,
    BIGNUM_MONTGOMERY_MUL_ERROR_LENGTH = -2,
    BIGNUM_MONTGOMERY_MUL_ERROR_MODULUS = -3,
    BIGNUM_MONTGOMERY_MUL_ERROR_RANGE = -4
} bignum_montgomery_mul_status_t;

/**
 * Computes out = a*b*R^-1 mod modulus, where R=2^(64*k) and
 * k=modulus->len. The modulus must be normalized, odd, and non-zero.
 * Inputs must be normalized and strictly smaller than modulus.
 * The output is committed only after successful validation and reduction;
 * on every error out is left byte-for-byte unchanged. Inputs may alias out.
 */
bignum_montgomery_mul_status_t bignum_montgomery_mul(
    bignum_t *restrict out,
    const bignum_t *a,
    const bignum_t *b,
    const bignum_t *modulus);

/** C11 reference entry point used for differential testing and benchmarks. */
bignum_montgomery_mul_status_t bignum_montgomery_mul_c11(
    bignum_t *restrict out,
    const bignum_t *a,
    const bignum_t *b,
    const bignum_t *modulus);

#ifdef __cplusplus
}
#endif
#endif /* BIGNUM_MONTGOMERY_MUL_H */
