/**
 * @file bignum_template_benchmark_adapter.c
 * @brief Deterministic bignum_template adapter implementation for benchmark-core.
 *
 * @details
 * The implementation owns only bignum domain semantics. benchmark-core owns
 * CLI/ENV parsing, source dataset allocation, ST/MT worker lifecycle, timing,
 * protocol publication, and reduction. This separation keeps the project
 * adapter independent of the byte-transform example and makes bignum profile
 * values explicit in source and JSON documentation.
 */
#include "bignum_template_benchmark_adapter.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <bignum.h>
#include "bignum_template.h"

/** @brief Stable FNV-1a offset basis used for observable benchmark checksums. */
#define BIGNUM_TEMPLATE_BENCHMARK_FNV_OFFSET UINT64_C(1469598103934665603)
/** @brief Stable FNV-1a prime used for observable benchmark checksums. */
#define BIGNUM_TEMPLATE_BENCHMARK_FNV_PRIME UINT64_C(1099511628211)

/**
 * @brief Enumerates bignum shift paths transported as `operation_kind`.
 *
 * @details
 * Each value maps one-to-one to the documented `shift-*` vocabulary. The
 * value is private to this adapter; generic benchmark-core sees only text.
 */
typedef enum {
    BIGNUM_TEMPLATE_SHIFT_ZERO = 0, /**< Always request a zero-bit shift. */
    BIGNUM_TEMPLATE_SHIFT_BIT = 1, /**< Request a non-zero sub-word shift. */
    BIGNUM_TEMPLATE_SHIFT_WORD = 2, /**< Request a whole-word shift when representable. */
    BIGNUM_TEMPLATE_SHIFT_COMBINED = 3, /**< Request a word-plus-bit shift when representable. */
    BIGNUM_TEMPLATE_SHIFT_RANDOM = 4, /**< Request a deterministic representable random shift. */
    BIGNUM_TEMPLATE_SHIFT_MIXED = 5 /**< Alternate deterministic shift classes by iteration. */
} bignum_template_shift_kind_t;

/**
 * @brief Compare two non-NULL C strings without leaking a scalar predicate result.
 * @param[in] left First C string.
 * @param[in] right Second C string.
 * @param[out] equal Receives BENCHMARK_BOOLEAN_TRUE when both strings are equal.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The helper validates all pointers, delegates byte comparison to strcmp, and
 * returns its predicate through an explicitly typed output parameter.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_string_equals(
    const char *left,
    const char *right,
    benchmark_boolean_t *equal)
{
    if (left == NULL || right == NULL || equal == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    *equal = strcmp(left, right) == 0
        ? BENCHMARK_BOOLEAN_TRUE
        : BENCHMARK_BOOLEAN_FALSE;
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Test whether a transport field belongs to a fixed domain vocabulary.
 * @param[in] value Transport string to validate.
 * @param[in] allowed Null-terminated array of allowed domain strings.
 * @param[out] accepted Receives BENCHMARK_BOOLEAN_TRUE for a member value.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The algorithm scans the small null-terminated vocabulary linearly. Profile
 * lists contain at most six stable values, so a dynamic lookup table would add
 * complexity without improving a benchmark control-path operation.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_value_is_allowed(
    const char *value,
    const char *const *allowed,
    benchmark_boolean_t *accepted)
{
    if (value == NULL || allowed == NULL || accepted == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    *accepted = BENCHMARK_BOOLEAN_FALSE;
    for (size_t index = 0U; allowed[index] != NULL; ++index) {
        benchmark_boolean_t equal;
        bignum_template_benchmark_status_t status;

        status = bignum_template_benchmark_string_equals(value, allowed[index], &equal);
        if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
            return status;
        }
        if (equal == BENCHMARK_BOOLEAN_TRUE) {
            *accepted = BENCHMARK_BOOLEAN_TRUE;
            return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
        }
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Validate one workload textual axis against a domain vocabulary.
 * @param[in] value Axis value to validate.
 * @param[in] allowed Null-terminated allowed vocabulary.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The helper converts the boolean output of value_is_allowed into the named
 * INVALID_PROFILE status used by the public validation function.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_validate_axis(
    const char *value,
    const char *const *allowed)
{
    benchmark_boolean_t accepted;
    bignum_template_benchmark_status_t status =
        bignum_template_benchmark_value_is_allowed(value, allowed, &accepted);

    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    return accepted == BENCHMARK_BOOLEAN_TRUE
        ? BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS
        : BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE;
}

/**
 * @brief Map a generic `operation_kind` transport string to a bignum shift kind.
 * @param[in] operation_kind Generic framework transport value.
 * @param[out] shift_kind Receives the corresponding bignum shift path.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The mapping deliberately accepts only `shift-*` values. This prevents a
 * bignum run from silently accepting unrelated generic example values such as
 * `xor` or `rotate`, which would make the recorded workload misleading.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_parse_shift_kind(
    const char *operation_kind,
    bignum_template_shift_kind_t *shift_kind)
{
    if (operation_kind == NULL || shift_kind == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    if (strcmp(operation_kind, "shift-zero") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_ZERO;
    } else if (strcmp(operation_kind, "shift-bit") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_BIT;
    } else if (strcmp(operation_kind, "shift-word") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_WORD;
    } else if (strcmp(operation_kind, "shift-combined") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_COMBINED;
    } else if (strcmp(operation_kind, "shift-random") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_RANDOM;
    } else if (strcmp(operation_kind, "shift-mixed") == 0) {
        *shift_kind = BIGNUM_TEMPLATE_SHIFT_MIXED;
    } else {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE;
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Advance a deterministic xorshift state.
 * @param[in,out] state Non-zero mutable pseudo-random state.
 * @param[out] value Receives the next deterministic value.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The algorithm uses three reversible xorshift steps. A zero incoming seed is
 * normalized to a fixed non-zero constant so every valid workload creates a
 * deterministic sequence and never remains in the all-zero xorshift state.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_next_value(
    uint64_t *state,
    uint64_t *value)
{
    if (state == NULL || value == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    if (*state == 0U) {
        *state = UINT64_C(0x9E3779B97F4A7C15);
    }
    *state ^= *state << 7U;
    *state ^= *state >> 9U;
    *state ^= *state << 8U;
    *value = *state;
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Count the leading zero bits in one non-zero 64-bit word.
 * @param[in] value Word whose high-order zero-bit count is needed.
 * @param[out] count Receives the number of leading zero bits.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The simple bounded loop is deterministic and portable under strict C11. A
 * zero input has no unique leading-zero value useful for capacity arithmetic,
 * so it is rejected as an invalid profile/state outcome.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_leading_zero_bits(
    uint64_t value,
    size_t *count)
{
    if (count == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    if (value == 0U) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE;
    }
    *count = 0U;
    while ((value & (UINT64_C(1) << 63U)) == 0U) {
        ++*count;
        value <<= 1U;
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Compute the maximum left shift that remains inside bignum capacity.
 * @param[in] number Valid normalized bignum source record.
 * @param[out] maximum Receives a non-overflowing shift bound.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * For zero values any shift below the complete storage width is safe. For a
 * non-zero record the algorithm combines unused whole words with high zero
 * bits in the most significant used word. Generated near-capacity records use
 * a cleared sign bit, preserving at least one safe growth bit.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_max_safe_shift(
    const bignum_t *number,
    size_t *maximum)
{
    size_t high_zeros;
    bignum_template_benchmark_status_t status;

    if (number == NULL || maximum == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    if (number->len > BIGNUM_CAPACITY) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE;
    }
    if (number->len == 0U) {
        *maximum = BIGNUM_CAPACITY * 64U - 1U;
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
    }
    status = bignum_template_benchmark_leading_zero_bits(
        number->words[number->len - 1U], &high_zeros);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    *maximum = (BIGNUM_CAPACITY - number->len) * 64U + high_zeros;
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Select a deterministic bignum length from the generic size/capacity profiles.
 * @param[in] workload Validated immutable workload descriptor.
 * @param[in,out] state Deterministic pseudo-random state for variable length.
 * @param[out] length Receives a valid source word count.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * near-capacity has priority over other size text because capacity pressure is
 * the purpose of that scenario. Variable lengths are bounded to the lower half
 * of capacity, leaving safe room for non-overflowing shift workloads.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_choose_length(
    const benchmark_workload_t *workload,
    uint64_t *state,
    size_t *length)
{
    uint64_t random_value;
    benchmark_boolean_t near_capacity;
    bignum_template_benchmark_status_t status;

    if (workload == NULL || state == NULL || length == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    near_capacity = (strcmp(workload->size_profile, "near-capacity") == 0 ||
        strcmp(workload->capacity_profile, "near-capacity") == 0)
        ? BENCHMARK_BOOLEAN_TRUE
        : BENCHMARK_BOOLEAN_FALSE;
    if (near_capacity == BENCHMARK_BOOLEAN_TRUE) {
        *length = BIGNUM_CAPACITY > 1U ? BIGNUM_CAPACITY - 1U : BIGNUM_CAPACITY;
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
    }
    if (strcmp(workload->size_profile, "one") == 0) {
        *length = 1U;
    } else if (strcmp(workload->size_profile, "quarter") == 0) {
        *length = BIGNUM_CAPACITY / 4U == 0U ? 1U : BIGNUM_CAPACITY / 4U;
    } else if (strcmp(workload->size_profile, "half") == 0) {
        *length = BIGNUM_CAPACITY / 2U == 0U ? 1U : BIGNUM_CAPACITY / 2U;
    } else {
        status = bignum_template_benchmark_next_value(state, &random_value);
        if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
            return status;
        }
        *length = 1U + (size_t)(random_value %
            (BIGNUM_CAPACITY / 2U == 0U ? 1U : BIGNUM_CAPACITY / 2U));
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Determine whether a generated row is a zero operand.
 * @param[in] input_kind Validated bignum input profile.
 * @param[in] sequence_index Stable deterministic dataset row index.
 * @param[out] zero Receives BENCHMARK_BOOLEAN_TRUE for a zero row.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * Mixed workloads alternate zero and non-zero rows by stable source index,
 * making the dataset reproducible across ST/MT runs and independent of worker
 * scheduling.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_row_is_zero(
    const char *input_kind,
    uint64_t sequence_index,
    benchmark_boolean_t *zero)
{
    if (input_kind == NULL || zero == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    if (strcmp(input_kind, "zero") == 0) {
        *zero = BENCHMARK_BOOLEAN_TRUE;
    } else if (strcmp(input_kind, "nonzero") == 0) {
        *zero = BENCHMARK_BOOLEAN_FALSE;
    } else if (strcmp(input_kind, "mixed") == 0) {
        *zero = (sequence_index % UINT64_C(2)) == 0U
            ? BENCHMARK_BOOLEAN_TRUE
            : BENCHMARK_BOOLEAN_FALSE;
    } else {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_INVALID_PROFILE;
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Initialize one deterministic immutable bignum source record.
 * @param[out] state Zeroed writable benchmark-core state record.
 * @param[in] sequence_index Stable source row index.
 * @param[in] workload Validated workload descriptor.
 * @param[in] adapter_context Unused project context; must be NULL.
 * @return A named benchmark_adapter_status_t result required by benchmark-core.
 *
 * @details
 * The callback validates profile fields, creates a row-specific xorshift seed,
 * and fills a `bignum_t` with either all zero words or a normalized non-zero
 * length. The top word always clears the sign bit so subsequent requested
 * shifts remain inside representable capacity.
 */
static benchmark_adapter_status_t bignum_template_benchmark_initialize(
    void *state,
    uint64_t sequence_index,
    const benchmark_workload_t *workload,
    void *adapter_context)
{
    bignum_t *number = state;
    uint64_t random_value;
    uint64_t random_state;
    size_t length;
    benchmark_boolean_t zero;
    bignum_template_benchmark_status_t status;

    (void)adapter_context;
    if (number == NULL || workload == NULL) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    status = bignum_template_benchmark_validate_workload(workload);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    memset(number, 0, sizeof(*number));
    status = bignum_template_benchmark_row_is_zero(workload->input_kind, sequence_index, &zero);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    if (zero == BENCHMARK_BOOLEAN_TRUE) {
        return BENCHMARK_ADAPTER_STATUS_SUCCESS;
    }
    random_state = workload->seed ^ (sequence_index + UINT64_C(0x9E3779B97F4A7C15));
    status = bignum_template_benchmark_choose_length(workload, &random_state, &length);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS || length == 0U || length > BIGNUM_CAPACITY) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    number->len = length;
    for (size_t word = 0U; word < length; ++word) {
        status = bignum_template_benchmark_next_value(&random_state, &random_value);
        if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
            return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
        }
        number->words[word] = random_value == 0U ? UINT64_C(1) : random_value;
    }
    number->words[length - 1U] = strcmp(workload->capacity_profile, "near-capacity") == 0 ||
        strcmp(workload->size_profile, "near-capacity") == 0
        ? UINT64_C(0x7FFFFFFFFFFFFFFF)
        : number->words[length - 1U] & UINT64_C(0x7FFFFFFFFFFFFFFF);
    if (number->words[length - 1U] == 0U) {
        number->words[length - 1U] = UINT64_C(1);
    }
    return BENCHMARK_ADAPTER_STATUS_SUCCESS;
}

/**
 * @brief Choose one representable bignum left-shift amount for an operation callback.
 * @param[in] number Immutable source state copied by benchmark-core.
 * @param[in] shift_kind Parsed bignum shift category.
 * @param[in] iteration Logical adapter operation iteration.
 * @param[in] seed Workload seed used to derive deterministic choices.
 * @param[out] shift_amount Receives a representable non-negative shift amount.
 * @return A named bignum_template_benchmark_status_t result.
 *
 * @details
 * The calculation first derives the maximum safe shift. Mixed profiles rotate
 * through zero, bit, word, and combined paths. Random selection is reproducible
 * from seed and iteration, so it does not depend on MT scheduling.
 */
static bignum_template_benchmark_status_t bignum_template_benchmark_choose_shift(
    const bignum_t *number,
    bignum_template_shift_kind_t shift_kind,
    uint64_t iteration,
    uint64_t seed,
    size_t *shift_amount)
{
    uint64_t random_state = seed ^ (iteration + UINT64_C(0xD1B54A32D192ED03));
    uint64_t random_value;
    size_t maximum;
    bignum_template_benchmark_status_t status;

    if (number == NULL || shift_amount == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    status = bignum_template_benchmark_max_safe_shift(number, &maximum);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    if (number->len == 0U || shift_kind == BIGNUM_TEMPLATE_SHIFT_ZERO || maximum == 0U) {
        *shift_amount = 0U;
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
    }
    if (shift_kind == BIGNUM_TEMPLATE_SHIFT_MIXED) {
        shift_kind = (bignum_template_shift_kind_t)(iteration % UINT64_C(4));
    }
    status = bignum_template_benchmark_next_value(&random_state, &random_value);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    if (shift_kind == BIGNUM_TEMPLATE_SHIFT_BIT) {
        *shift_amount = 1U + (size_t)(random_value % (maximum < 63U ? maximum : 63U));
    } else if (shift_kind == BIGNUM_TEMPLATE_SHIFT_WORD) {
        *shift_amount = maximum / 64U == 0U ? 0U :
            64U * (1U + (size_t)(random_value % (maximum / 64U)));
    } else if (shift_kind == BIGNUM_TEMPLATE_SHIFT_COMBINED) {
        const size_t words = maximum / 64U;
        *shift_amount = words == 0U ? (maximum < 2U ? 0U : 1U) :
            64U + 1U + (size_t)(random_value % (maximum - 64U));
    } else {
        *shift_amount = (size_t)(random_value % (maximum + 1U));
    }
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}

/**
 * @brief Execute bignum_template once on a benchmark-core mutable state copy.
 * @param[in,out] state Independent mutable bignum_t copy.
 * @param[in] iteration Logical operation iteration.
 * @param[in] workload Immutable transport workload descriptor.
 * @param[in] adapter_context Unused project context; must be NULL.
 * @return A named benchmark_adapter_status_t result required by benchmark-core.
 *
 * @details
 * The callback maps `shift-*` text to a domain enum, derives a safe deterministic
 * amount, invokes bignum_template in-place, and maps its named library status
 * to benchmark-core's named callback result.
 */
static benchmark_adapter_status_t bignum_template_benchmark_operation(
    void *state,
    uint64_t iteration,
    const benchmark_workload_t *workload,
    void *adapter_context)
{
    bignum_t *number = state;
    bignum_template_shift_kind_t shift_kind;
    size_t shift_amount;
    bignum_template_benchmark_status_t status;
    bignum_template_status_t operation_status;

    (void)adapter_context;
    if (number == NULL || workload == NULL) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    status = bignum_template_benchmark_parse_shift_kind(workload->operation_kind, &shift_kind);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    status = bignum_template_benchmark_choose_shift(
        number, shift_kind, iteration, workload->seed, &shift_amount);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return BENCHMARK_ADAPTER_STATUS_INPUT_ERROR;
    }
    operation_status = bignum_template(number, shift_amount);
    return operation_status == BIGNUM_TEMPLATE_SUCCESS
        ? BENCHMARK_ADAPTER_STATUS_SUCCESS
        : BENCHMARK_ADAPTER_STATUS_OPERATION_ERROR;
}

/**
 * @brief Produce a deterministic observable checksum for benchmark-core reduction.
 * @param[in] state Read-only post-operation bignum_t state.
 * @param[in] iteration Logical operation iteration.
 * @param[in] adapter_context Unused project context.
 * @return 64-bit checksum value required by benchmark-core's fixed callback ABI.
 *
 * @details
 * benchmark-core v1.0.0 defines benchmark_checksum_fn with a uint64_t return
 * type. This inherited callback ABI is the sole required bridge to its public
 * API; all project-owned construction, validation, generation, and operation
 * functions use named status return types. The algorithm hashes every capacity
 * word, logical length, and iteration with FNV-1a so the compiler cannot erase
 * the measured in-place operation as an unobservable side effect.
 */
static uint64_t bignum_template_benchmark_checksum(
    const void *state,
    uint64_t iteration,
    void *adapter_context)
{
    const bignum_t *number = state;
    uint64_t checksum = BIGNUM_TEMPLATE_BENCHMARK_FNV_OFFSET;

    (void)adapter_context;
    if (number == NULL) {
        return 0U;
    }
    for (size_t word = 0U; word < BIGNUM_CAPACITY; ++word) {
        checksum ^= number->words[word];
        checksum *= BIGNUM_TEMPLATE_BENCHMARK_FNV_PRIME;
    }
    checksum ^= (uint64_t)number->len;
    checksum *= BIGNUM_TEMPLATE_BENCHMARK_FNV_PRIME;
    checksum ^= iteration;
    checksum *= BIGNUM_TEMPLATE_BENCHMARK_FNV_PRIME;
    return checksum;
}

bignum_template_benchmark_status_t bignum_template_benchmark_validate_workload(
    const benchmark_workload_t *workload)
{
    static const char *const input_values[] = { "zero", "nonzero", "mixed", NULL };
    static const char *const operation_values[] = {
        "shift-zero", "shift-bit", "shift-word", "shift-combined", "shift-random", "shift-mixed", NULL
    };
    static const char *const measure_values[] = { "end-to-end", "kernel-only", NULL };
    static const char *const size_values[] = { "one", "quarter", "half", "variable", "near-capacity", NULL };
    static const char *const capacity_values[] = { "normal", "near-capacity", NULL };
    bignum_template_benchmark_status_t status;

    if (workload == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    status = bignum_template_benchmark_validate_axis(workload->input_kind, input_values);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    status = bignum_template_benchmark_validate_axis(workload->operation_kind, operation_values);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    status = bignum_template_benchmark_validate_axis(workload->measure_mode, measure_values);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    status = bignum_template_benchmark_validate_axis(workload->size_profile, size_values);
    if (status != BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS) {
        return status;
    }
    return bignum_template_benchmark_validate_axis(workload->capacity_profile, capacity_values);
}

bignum_template_benchmark_status_t bignum_template_benchmark_adapter_init(
    benchmark_adapter_t *adapter)
{
    if (adapter == NULL) {
        return BIGNUM_TEMPLATE_BENCHMARK_STATUS_NULL_ARGUMENT;
    }
    *adapter = (benchmark_adapter_t){
        .benchmark_name = "bignum_template",
        .state_size = sizeof(bignum_t),
        .success_code = BENCHMARK_ADAPTER_STATUS_SUCCESS,
        .adapter_context = NULL,
        .initialize = bignum_template_benchmark_initialize,
        .operation = bignum_template_benchmark_operation,
        .checksum = bignum_template_benchmark_checksum
    };
    return BIGNUM_TEMPLATE_BENCHMARK_STATUS_SUCCESS;
}
