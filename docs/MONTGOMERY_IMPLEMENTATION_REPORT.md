# Montgomery Multiplication Implementation Report

## Scope

The module implements fixed-capacity Montgomery multiplication for `bignum_t` values with a normalized odd modulus. The public operation is transactional and accepts output aliasing with either input.

## C11 reference

`src/bignum_montgomery_mul.c` validates all object lengths and normalized top words, rejects zero/even moduli, checks operand range, computes a schoolbook product in a private `2 * BIGNUM_CAPACITY + 2` limb buffer, performs radix-2^64 Montgomery reduction, conditionally subtracts the modulus, normalizes the candidate, and commits the complete object only on success.

## YASM implementation

`src/bignum_montgomery_mul.asm` implements an independent System V AMD64 path. It uses a fixed stack workspace, explicit callee-saved register preservation, schoolbook multiply-accumulate loops, Newton iteration for the low-limb negative inverse, limb-wise REDC, conditional subtraction, full-capacity output clearing, and final normalization. No call to the C11 implementation is used by the production arithmetic path.

## Validation evidence

| Gate | Result |
|---|---|
| C11 release unit suite | Passed: `0 / 3 failed` |
| YASM release unit suite | Passed: `0 / 3 failed` |
| C11 AddressSanitizer suite | Passed: 3 tests, 0 failures, 0 sanitizer issues |
| C11 UndefinedBehaviorSanitizer suite | Passed: 3 tests, 0 failures, 0 sanitizer issues |
| YASM differential limb coverage | Passed for one through eight limb modulus cases in the deterministic test suite |
| Adapter validation | Passed with Montgomery operation vocabulary and deterministic callbacks |
| Static analysis | Completed; only vendor `json_lib.h` discovery informational messages remain |

The tests cover known vectors, invalid pointers, even/zero modulus, range errors, transactional preservation, input/output aliasing, and deterministic cross-checking of C11 and YASM results.
