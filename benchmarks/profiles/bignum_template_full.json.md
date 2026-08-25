# How-to: `bignum_template_full.json`

## Назначение

`bignum_template_full.json` — расширенная domain-specific matrix для анализа производительности in-place left shift. Она предназначена для подготовленного controlled run, а не для быстрого CI smoke. Manifest сохраняет все meaningful bignum axes: zero/mixed input, zero/bit/word/combined/random/mixed shift amount, operand word length, measurement boundary and near-capacity state.

The C11 `bench_matrix` runner from pinned `benchmark-framework v1.0.0` accepts the JSON document and launches project-owned ST/MT bignum adapter binaries. The runner writes a raw samples document; the C11 `benchmark_stats` tool parses it through public `json-lib` and emits a metrics/regression summary.

## Coverage

| Family | Profiles | What it isolates |
|---|---:|---|
| Zero path | 1 | No-op left shift over a zero source record |
| One-word paths | 2 | Zero and sub-word shifts without length expansion |
| Quarter/half lengths | 4 | Bit, word and combined shift costs at bounded multi-word sizes |
| Variable/mixed | 2 | Reproducible randomized and branch-diverse workload behavior |
| Near-capacity | 3 | Valid growth near storage capacity for bit and word shifts |

The document declares **12 profiles**. A run with `R` repetitions therefore produces `12 × 2 × R` samples: one ST and one MT process per profile/repetition.

## Controlled full run

Use fixed seed, thread count, data-count and iteration counts when a result will become a baseline. The following command shows the expected C11 runner contract; Makefile integration will expose the same parameters after its separate approval.

```bash
libs/benchmark-framework/build/tools/bench_matrix \
  --manifest benchmarks/profiles/bignum_template_full.json \
  --output benchmarks/reports/bignum_template_full_matrix.json \
  --st-binary bin/bench_bignum_template \
  --mt-binary bin/bench_bignum_template_mt \
  --repetitions 7 \
  --iterations 200000000 \
  --mt-total-iterations 320000000 \
  --threads 2 \
  --warmup 10000 \
  --data-count 4096 \
  --seed 11400714819323198485 \
  --timeout-seconds 1800
```

Do not compare this result to data collected with different manifest contents, compiler configuration, CPU affinity, thread count or benchmark boundary. The JSON report records profile text, command/protocol outputs and individual timing samples so the conditions remain auditable.

## Review candidate metrics

Create a candidate summary first:

```bash
libs/benchmark-framework/build/tools/benchmark_stats \
  --input benchmarks/reports/bignum_template_full_matrix.json \
  --output benchmarks/reports/bignum_template_full_summary.json
```

After review, preserve the raw matrix JSON as the baseline because it contains all repetitions and profile metadata. Compare a later candidate as follows:

```bash
libs/benchmark-framework/build/tools/benchmark_stats \
  --input benchmarks/reports/candidate_full_matrix.json \
  --baseline benchmarks/reports/reviewed_full_matrix.json \
  --output benchmarks/reports/candidate_full_summary.json \
  --threshold-pct 5
```

A `regression:true` field means the candidate median exceeded both the configured threshold and robust MAD-based noise floor. A non-zero result with `missing_profiles` means the documents do not share complete profile/mode coverage and must not be treated as a valid comparison.

## Bignum transport vocabulary

`operation_kind` must begin with `shift-`. It is not legal to substitute generic example values such as `xor` or `rotate`. The adapter validates these values before it initializes bignum state, therefore malformed profiles fail before their data become benchmark samples.

| `operation_kind` | Adapter shift path |
|---|---|
| `shift-zero` | Always zero shift amount |
| `shift-bit` | Deterministic representable sub-word amount |
| `shift-word` | Deterministic representable whole-word amount |
| `shift-combined` | Deterministic representable whole-word-plus-bit amount |
| `shift-random` | Deterministic representable amount derived from seed/iteration |
| `shift-mixed` | Stable rotation through zero, bit, word and combined paths |
