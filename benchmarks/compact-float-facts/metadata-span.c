/* The controller extracts the production descriptor, fact predicates and
   numeric_for_each_span verbatim. Only ownership and R boundaries are mocked. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { NUMERIC_BYTE, NUMERIC_INT, NUMERIC_LONG, NUMERIC_FLOAT, NUMERIC_DOUBLE };
#include "production-descriptor.h"

#if UINTPTR_MAX == UINT64_MAX
_Static_assert(offsetof(numeric_data, domain_flags) == 72, "64-bit flags layout");
_Static_assert(offsetof(numeric_data, float_max_magnitude_bound) == 76, "64-bit maximum layout");
_Static_assert(offsetof(numeric_data, float_min_nonzero_magnitude_bound) == 80, "64-bit minimum layout");
_Static_assert(offsetof(numeric_data, zero_count) == 88, "64-bit count layout");
_Static_assert(sizeof(numeric_data) == 96, "64-bit descriptor size");
#elif UINTPTR_MAX == UINT32_MAX
_Static_assert(offsetof(numeric_data, domain_flags) == 40, "32-bit flags layout");
_Static_assert(offsetof(numeric_data, float_max_magnitude_bound) == 44, "32-bit maximum layout");
_Static_assert(offsetof(numeric_data, float_min_nonzero_magnitude_bound) == 48, "32-bit minimum layout");
_Static_assert(offsetof(numeric_data, zero_count) == 52, "32-bit count layout");
_Static_assert(sizeof(numeric_data) == 56, "32-bit descriptor size");
#endif

typedef struct { const unsigned char *values; size_t chunk_rows; } owner;
static size_t numeric_kind_width(int kind) {
    return kind == NUMERIC_BYTE ? 1 : kind == NUMERIC_INT ? 2 : 4;
}
static void Rf_error(const char *message) { fprintf(stderr, "%s\n", message); abort(); }
static void R_CheckUserInterrupt(void) {}
static const void *numeric_read_span(const numeric_data *data, size_t start,
        size_t requested, size_t *count) {
    const owner *source = data->native_owner;
    size_t available = source->chunk_rows - start % source->chunk_rows;
    *count = requested < available ? requested : available;
    if (*count > data->length - start) *count = data->length - start;
    return source->values + start * numeric_kind_width(data->kind);
}
#include "production-span.h"

typedef struct { size_t rows, calls; int exact; } visit_context;
static void check(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}
static void visit(const numeric_data *span, size_t offset, void *raw) {
    visit_context *context = raw;
    check(offset == context->rows, "span offsets must be contiguous");
    check(numeric_float_bounds_known(span), "subset must retain conservative bounds");
    check(span->float_max_magnitude_bound == UINT32_C(0x40400000), "maximum changed");
    check(span->float_min_nonzero_magnitude_bound == 1, "minimum changed");
    check(numeric_zero_count_known(span) == context->exact, "wrong exact-count validity");
    if (context->exact) check(span->zero_count == 2, "full count changed");
    context->rows += span->length;
    context->calls++;
}
static void run(const numeric_data *data, size_t start, size_t length,
        int exact, size_t calls) {
    visit_context context = {0, 0, exact};
    numeric_for_each_span(data, start, length, visit, &context);
    check(context.rows == length && context.calls == calls, "wrong visited region");
}
int main(void) {
    uint32_t values[8] = {0};
    numeric_data data = {
        .values = values, .length = 8, .kind = NUMERIC_FLOAT,
        .temporal = 0, .format_version = 119, .missing_count = 1,
        .domain_flags = 7, .float_max_magnitude_bound = UINT32_C(0x40400000),
        .float_min_nonzero_magnitude_bound = 1, .zero_count = 2
    };
    run(&data, 0, 8, 1, 1);
    run(&data, 2, 4, 0, 1);
    run(&data, 0, 0, 0, 1);
    owner backing = {(const unsigned char *) values, 3};
    data.native_owner = &backing;
    data.values = NULL;
    run(&data, 0, 8, 0, 3);
    run(&data, 1, 3, 0, 2);
    run(&data, 0, 0, 0, 0);
    backing.chunk_rows = 8;
    run(&data, 0, 8, 1, 1);
    data.temporal = 1;
    check(!numeric_float_bounds_known(&data) && !numeric_zero_count_known(&data),
          "temporal values must decline facts");
    data.temporal = 0;
    data.format_version = 111;
    check(!numeric_float_bounds_known(&data), "legacy float must decline bounds");
    data.format_version = 119;
    data.domain_flags = NUMERIC_DOMAIN_FLOAT_BOUNDS_KNOWN;
    check(!numeric_float_bounds_known(&data), "bounds require strict domain");
    data.kind = NUMERIC_INT;
    data.domain_flags = NUMERIC_DOMAIN_ZERO_COUNT_KNOWN;
    check(!numeric_float_bounds_known(&data) && numeric_zero_count_known(&data),
          "integer zero facts are independent of float bounds");
    check(!numeric_float_bounds_known(NULL) && !numeric_zero_count_known(NULL),
          "missing descriptors must decline facts");
    puts("PASS: full and partial plain/retained spans preserve only valid facts");
    return 0;
}
