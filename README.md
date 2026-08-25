# bignum-montgomery-mul

`bignum-montgomery-mul` is a standalone C11/x86-64 YASM module for Montgomery multiplication of fixed-capacity unsigned `bignum_t` values. The production operation computes

```text
out = a * b * R^-1 mod modulus,  R = 2^(64 * modulus.len)
```

using a normalized odd modulus. The implementation includes a portable C11 reference and an independent System V AMD64 YASM implementation with a stack-resident temporary workspace.

## Contract

The public API is declared by `include/bignum_montgomery_mul.h`:

```c
bignum_montgomery_mul_status_t bignum_montgomery_mul(
    bignum_t *restrict out,
    const bignum_t *a,
    const bignum_t *b,
    const bignum_t *modulus);
```

The modulus must be non-zero, normalized, odd, and no longer than `BIGNUM_CAPACITY`. Both operands must be normalized and strictly smaller than the modulus. The output is transactional: invalid arguments, invalid lengths, an even or zero modulus, and out-of-range operands leave the complete `out` object unchanged. Input/output aliasing is supported through private workspace and a final commit.

| Condition | Status |
|---|---|
| Any required pointer is `NULL` | `BIGNUM_MONTGOMERY_MUL_ERROR_NULL_ARG` |
| Non-normalized or over-capacity value | `BIGNUM_MONTGOMERY_MUL_ERROR_LENGTH` |
| Zero or even modulus | `BIGNUM_MONTGOMERY_MUL_ERROR_MODULUS` |
| Operand is not strictly smaller than modulus | `BIGNUM_MONTGOMERY_MUL_ERROR_RANGE` |
| Valid Montgomery multiplication | `BIGNUM_MONTGOMERY_MUL_SUCCESS` |

## Architecture

The C11 reference uses schoolbook multiplication followed by radix-2^64 Montgomery reduction. The YASM path independently implements the same mathematical contract with fixed-size stack workspace, carry propagation, conditional subtraction, normalization, and transactional output commit. The implementation uses no mutable global state and follows the System V AMD64 calling convention.

The repository preserves the template build contract. `Makefile` and CI workflows are intentionally unchanged. The pinned benchmark-framework distribution is stored under `libs/benchmark-framework/dist`; the matrix tools are available under `libs/benchmark-framework/build/tools` for the protected Makefile targets.

## Dependencies

The project uses GCC with C11 support, YASM, `cppcheck`, Valgrind for optional race checks, the `bignum-core` submodule, and benchmark-framework v1.0.0. Initialize the core submodule with:

```bash
git submodule update --init --recursive
```

## Build and tests

Build the C11 reference:

```bash
make clean
make build USE_ASM=no CONFIG=release
```

Build the YASM implementation:

```bash
make clean
make build USE_ASM=yes CONFIG=release
```

Run the full deterministic unit, distribution-runner, and adapter suite:

```bash
make test USE_ASM=yes CONFIG=release
```

The current suite covers known Montgomery vectors, invalid modulus and range handling, transactional output preservation, aliasing, and differential checks across one through eight limbs.

Run C11 sanitizer checks:

```bash
make clean
make test_sanitize USE_ASM=no SAN=address CONFIG=debug
make clean
make test_sanitize USE_ASM=no SAN=undefined CONFIG=debug
```

Run static analysis:

```bash
make lint CONFIG=release
```

## Benchmarks

The benchmark adapter uses Montgomery operation vocabulary: `montgomery`, `montgomery-random`, and `montgomery-mixed`. Supported size profiles are `one`, `quarter`, `half`, `variable`, and `near-capacity`.

A direct smoke benchmark is:

```bash
make clean
make bin/bench_bignum_montgomery_mul USE_ASM=yes CONFIG=release
./bin/bench_bignum_montgomery_mul \
  --data-mode all_nonzero \
  --operation-kind montgomery \
  --size-profile half \
  --iterations 100000 \
  --warmup 1000 \
  --data-count 64 \
  --seed 7
```

Run the reproducible JSON matrix with:

```bash
make bench_matrix USE_ASM=yes CONFIG=release \
  BENCH_MATRIX_PROFILE=benchmarks/profiles/bignum_montgomery_mul_standard.json \
  BENCH_MATRIX_REPETITIONS=7 \
  BENCH_MATRIX_ITERATIONS=200000 \
  BENCH_MATRIX_MT_TOTAL_ITERATIONS=320000 \
  REPORT_NAME=montgomery_asm
```

The C11 baseline uses the same command with `USE_ASM=no` and a different `REPORT_NAME`. Matrix artifacts are written to `benchmarks/reports/`.

## Repository layout

| Path | Purpose |
|---|---|
| `include/bignum_montgomery_mul.h` | Public API and status contract |
| `src/bignum_montgomery_mul.c` | C11 reference implementation |
| `src/bignum_montgomery_mul.asm` | Independent YASM implementation |
| `tests/` | Deterministic unit, runner, and adapter tests |
| `benchmarks/adapter/` | benchmark-framework domain adapter |
| `benchmarks/profiles/` | Standard and full Montgomery matrices |
| `docs/` | Implementation and benchmark evidence |

## License

This project is distributed under the license in `LICENSE`.
