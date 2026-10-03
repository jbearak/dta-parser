/* This includes the actual production result, preflight, and producer bodies.
   Only the R allocation/reader/interrupt boundary is mocked. The private
   Python driver inserts counters into copies, never the package headers. */
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef ptrdiff_t R_xlen_t;
enum { NUMERIC_BYTE, NUMERIC_INT, NUMERIC_LONG, NUMERIC_FLOAT, NUMERIC_DOUBLE };
typedef struct {
    int kind, temporal, format_version;
    size_t missing_count, chunk_size;
    const unsigned char *raw;
    uint32_t domain_flags;
} numeric_data;
enum { NUMERIC_DOMAIN_STRICT_MODERN_FLOAT = 1U };
typedef struct {
    const numeric_data *storage;
    const double *real_values;
    const int *integer_values;
} numeric_reader;
typedef struct { numeric_reader reader; R_xlen_t length; } arithmetic_operand;
typedef struct allocation { unsigned char *raw; size_t missing_count; int kind; } *SEXP;
typedef int PROTECT_INDEX;
#define NA_REAL NAN
#define NA_INTEGER INT_MIN
#define R_FINITE isfinite
#define PROTECT(x) (x)
#define UNPROTECT(x) ((void)(x))
#define PROTECT_WITH_INDEX(x, i) ((void)(*(i) = 0), (void)(x))
#define REPROTECT(x, i) ((void)(i), (void)(x))
#define RAW(x) ((x)->raw)
#define REAL(x) ((double *)(void *)(x)->raw)
static int phase;
static size_t general_rows[2], result_checks[2], integer_loads[2], span_rows[2];
static size_t fit_rows, scalar_reads, allocations;
static SEXP allocated[4];
static size_t width(int kind) { return kind == 0 ? 1 : kind == 1 ? 2 : kind < 4 ? 4 : 8; }
static void R_CheckUserInterrupt(void) {}
static const unsigned char *numeric_read_span(const numeric_data *data,
        size_t start, size_t count, size_t *available) {
    if (data->chunk_size && count > data->chunk_size - start % data->chunk_size)
        count = data->chunk_size - start % data->chunk_size;
    *available = count;
    span_rows[phase] += count;
    return data->raw + start * width(data->kind);
}
static void numeric_reader_region(const numeric_reader *reader, size_t start,
        size_t count, double *value, int *code) {
    if (count != 1 || !reader->real_values) abort();
    scalar_reads++;
    *value = reader->real_values[start]; *code = isnan(*value) ? 0 : -1;
}
static SEXP arithmetic_backing(R_xlen_t length, int kind) {
    phase = 1;
    if (allocations == 4) abort();
    SEXP result = malloc(sizeof(*result));
    if (!result) abort();
    result->raw = calloc((size_t)length, width(kind));
    if (!result->raw) abort();
    allocated[allocations++] = result;
    return result;
}
static SEXP arithmetic_adopt_backing(SEXP backing, R_xlen_t length, int kind, size_t missing) {
    (void)length; backing->kind = kind; backing->missing_count = missing; return backing;
}
#include "production-common.h"
#include "numeric-arithmetic-general.h"

static void store_integer(unsigned char *raw, size_t i, int kind, int32_t x) {
    if (kind == NUMERIC_BYTE) { int8_t v = (int8_t)x; memcpy(raw+i, &v, 1); }
    else if (kind == NUMERIC_INT) { int16_t v = (int16_t)x; memcpy(raw+2*i, &v, 2); }
    else memcpy(raw+4*i, &x, 4);
}
static int32_t fixture(size_t i, int kind, int pattern, size_t length) {
    int32_t limit = kind == 0 ? 101 : kind == 1 ? 32741 : 2147483621;
    if (pattern == 1 && i >= 12 && (i-12) % 997 == 0) return limit;
    if (pattern == 2) return i+1 == length ? 3 : 1;
    if (pattern == 3) {
        int32_t cases[] = {0,1,-1,INT32_MIN,limit-1,limit,limit+1,limit+26};
        int32_t value = cases[i%8];
        if (value == INT32_MIN) value = kind == 0 ? INT8_MIN : kind == 1 ? INT16_MIN : INT32_MIN;
        return value;
    }
    /* int16/long use the original throughput panel's exact denominator grid;
       byte adds a width-safe control with the same zero/missing semantics. */
    return kind == NUMERIC_BYTE ? (int32_t)((13*(i+1))%101)-50 :
        (int32_t)((13*(i+1))%10001)-5000;
}
static int run_case(size_t length, int kind, int pattern, double scalar,
        int legacy, size_t chunks, int required) {
    phase = 0; fit_rows = scalar_reads = allocations = 0;
    memset(general_rows,0,sizeof general_rows); memset(result_checks,0,sizeof result_checks);
    memset(integer_loads,0,sizeof integer_loads); memset(span_rows,0,sizeof span_rows);
    unsigned char *raw = malloc(length * width(kind));
    if (!raw) return 2;
    numeric_data data = {kind,0,legacy ? 111 : 118,0,chunks,raw,0};
    const int32_t missing_minimum = arithmetic_integer_missing(&data);
    size_t want_missing = 0;
    double minimum = 0, maximum = 0; unsigned fractional = 0;
    for (size_t i=0;i<length;i++) {
        int32_t x=fixture(i,kind,pattern,length); store_integer(raw,i,kind,x);
        int inherited = x >= missing_minimum;
        data.missing_count += inherited;
        double result = inherited ? NA_REAL : scalar / (double)x;
        int valid = uncounted_result_valid(result); want_missing += !valid;
        double observed = valid ? result : 0;
        if (observed < minimum) minimum = observed;
        if (observed > maximum) maximum = observed;
        fractional |= observed != trunc(observed);
    }
    arithmetic_operand left = {{NULL,&scalar,NULL},1}, right = {{&data,NULL,NULL},(R_xlen_t)length};
    int selected = -1;
    SEXP result = arithmetic_general_result(&left,&right,(R_xlen_t)length,'/',kind,&selected);
    int wanted = NUMERIC_DOUBLE;
    if (!fractional) {
        const double lows[] = {-127,-32767,-2147483647.0};
        const double highs[] = {100,32740,2147483620.0};
        for (int k=kind;k<=NUMERIC_LONG;k++) if (minimum >= lows[k] && maximum <= highs[k]) {
            wanted=k; break;
        }
    }
    if (wanted == NUMERIC_DOUBLE && kind != NUMERIC_LONG &&
            minimum >= -numeric_float_observed_limit() && maximum <= numeric_float_observed_limit())
        wanted=NUMERIC_FLOAT;
    if (selected != wanted || result->missing_count != want_missing || scalar_reads != 1) return 3;
    for (size_t i=0;i<length;i++) {
        int32_t x=fixture(i,kind,pattern,length);
        double value = x>=missing_minimum ? NA_REAL : scalar/(double)x;
        int valid = uncounted_result_valid(value);
        if (selected == NUMERIC_FLOAT) {
            float want = valid ? (float)value : 0x1p127f;
            if (memcmp(result->raw+4*i,&want,4)) return 4;
        } else if (selected == NUMERIC_DOUBLE) {
            double actual; memcpy(&actual,result->raw+8*i,8);
            if (valid ? memcmp(&actual,&value,8)!=0 : !isnan(actual)) return 5;
        } else {
            unsigned char bytes[4]; int32_t want = valid ? (int32_t)value : selected==0 ? 101 : selected==1 ? 32741 : 2147483621;
            store_integer(bytes,0,selected,want);
            if (memcmp(result->raw+width(selected)*i,bytes,width(selected))) return 6;
        }
    }
    printf("%zu,%d,%d,%a,%d,%zu,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu\n",
        length,kind,pattern,scalar,legacy,chunks,selected,general_rows[0],general_rows[1],
        result_checks[0],result_checks[1],fit_rows,integer_loads[0],integer_loads[1],span_rows[0],span_rows[1],want_missing);
    int admitted_bound = selected == NUMERIC_DOUBLE ? uncounted_result_valid(scalar) :
        selected == NUMERIC_FLOAT && fabs(scalar) <= numeric_float_observed_limit();
    int red = required && admitted_bound && general_rows[1] != 0;
    for (size_t i=0;i<allocations;i++) {free(allocated[i]->raw);free(allocated[i]);}
    free(raw);
    return red ? 1 : 0;
}
static int semantic_failures, work_failures;
static void record_case(size_t n, int kind, int pattern, double scalar, int legacy, size_t chunks, int required) {
    int status=run_case(n,kind,pattern,scalar,legacy,chunks,required);
    if (status==1) work_failures++;
    else if (status!=0) {
        semantic_failures++;
        fprintf(stderr,"Semantic error %d: length=%zu kind=%d pattern=%d scalar=%a legacy=%d\n",status,n,kind,pattern,scalar,legacy);
    }
}
int main(int argc, char **argv) {
    (void)argv;
    puts("length,kind,pattern,scalar,legacy,chunk,output,preflight_rows,generic_output_rows,preflight_result_checks,output_result_checks,float_fit_rows,preflight_integer_loads,output_integer_loads,preflight_span_rows,output_span_rows,result_missing");
    const size_t lengths[] = {16383,16384,16385,1000000};
    for (int kind=0;kind<=2;kind++) for (int p=0;p<=1;p++)
        record_case(1000000,kind,p,1.01,0,0,argc>1);
    for (size_t j=0;j<4;j++)
        record_case(lengths[j],NUMERIC_INT,2,1.0,0,0,argc>1);
    const double scalars[] = {0.0,-0.0,1.01,-1.01,0x1.fffffep126,-0x1.fffffep126,0x1p127,DBL_MAX/2,DBL_MAX};
    for (int kind=0;kind<=2;kind++) for (int legacy=0;legacy<=1;legacy++)
        for (size_t j=0;j<sizeof(scalars)/sizeof(*scalars);j++)
            record_case(128,kind,3,scalars[j],legacy,7,argc>1);
    fprintf(stderr,"%s: %d semantic failures, %d proved-work failures across 64 cases\n",
        semantic_failures || work_failures ? "FAIL" : "PASS",semantic_failures,work_failures);
    return semantic_failures || work_failures ? 1 : 0;
}
