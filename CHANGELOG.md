# Changelog

## [0.1.0] - 2026-08-26

### Added

- Added a documented C11 reference implementation of fixed-capacity Montgomery multiplication.
- Added an independent x86-64 YASM Montgomery REDC implementation with stack workspace, carry propagation, conditional subtraction, normalization, and transactional output commit.
- Added explicit status codes for null arguments, invalid lengths, invalid moduli, and out-of-range operands.
- Added deterministic unit, distribution-runner, and benchmark adapter tests.
- Added C11/YASM differential coverage for one through eight limb modulus cases.
- Added AddressSanitizer and UndefinedBehaviorSanitizer validation commands.
- Added Montgomery-specific benchmark adapter vocabulary and standard/full JSON matrix manifests.
- Added implementation and benchmark evidence reports.

### Performance

- Added reproducible benchmark-framework workflows for comparing C11 and YASM paths over one, quarter, half, variable, and near-capacity profiles.
- Short controlled measurements show the YASM path ahead of C11 for one, quarter, and half-size workloads, with near-capacity results within short-run measurement noise.

### Constraints

- The protected Makefile and CI workflow files were not modified.
- The benchmark-framework distribution remains vendored under `libs/benchmark-framework/dist`.
