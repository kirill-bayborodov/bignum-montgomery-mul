# How-to: `bignum_template_standard.json`

## Назначение

`bignum_template_standard.json` — компактная versioned matrix для функциональной проверки и регрессионного baseline операции `bignum_template`. Manifest использует schema version `1`, которую читает C11-инструмент `bench_matrix` из pinned `benchmark-framework v1.0.0`.

> Manifest не описывает generic byte-transform. Он переносит bignum semantics через нейтральные transport fields benchmark framework.

| JSON field | Значение в manifest | Bignum interpretation |
|---|---|---|
| `input_kind` | `zero`, `nonzero`, `mixed` | Форма исходного `bignum_t` dataset |
| `operation_kind` | `shift-zero`, `shift-bit`, `shift-word`, `shift-combined`, `shift-random`, `shift-mixed` | Выбор representable left-shift amount |
| `measure_mode` | `end-to-end`, `kernel-only` | Включает либо исключает preparation copy из timed interval |
| `size_profile` | `one`, `quarter`, `half`, `variable`, `near-capacity` | Logical word length of input `bignum_t` |
| `capacity_profile` | `normal`, `near-capacity` | Storage-boundary workload condition |

## Пошаговый smoke run

После approved Makefile wiring adapter binaries будут передаваться C11 runner напрямую. Эквивалентная команда имеет следующую форму:

```bash
libs/benchmark-framework/build/tools/bench_matrix \
  --manifest benchmarks/profiles/bignum_template_standard.json \
  --output benchmarks/reports/bignum_template_standard_matrix.json \
  --st-binary bin/bench_bignum_template \
  --mt-binary bin/bench_bignum_template_mt \
  --repetitions 1 \
  --iterations 1001 \
  --mt-total-iterations 2000 \
  --threads 2 \
  --warmup 10 \
  --data-count 32 \
  --seed 11400714819323198485 \
  --timeout-seconds 30
```

The expected matrix contains **8 profiles × 2 modes × repetitions** samples. Every accepted sample has exactly one `benchmark=...` line before its `Benchmark finished.` marker.

## Aggregation and baseline comparison

Aggregate a candidate without a baseline first:

```bash
libs/benchmark-framework/build/tools/benchmark_stats \
  --input benchmarks/reports/bignum_template_standard_matrix.json \
  --output benchmarks/reports/bignum_template_standard_summary.json
```

After human review, compare a later candidate to the approved matrix using identical manifests and measurement conditions:

```bash
libs/benchmark-framework/build/tools/benchmark_stats \
  --input benchmarks/reports/candidate_matrix.json \
  --baseline benchmarks/reports/reviewed_baseline_matrix.json \
  --output benchmarks/reports/candidate_summary.json \
  --threshold-pct 5
```

A changed profile set is intentionally not a valid baseline. The statistics tool returns non-zero and reports `missing_profiles` rather than treating a partial comparison as success.

## Boundary case

`near-capacity` uses a valid source operand with a cleared high bit. It measures representable growth near `BIGNUM_CAPACITY`; it does not intentionally time the overflow error path. Overflow behavior belongs in deterministic API tests, not performance aggregates.
