/* This includes the actual production result, preflight, and producer bodies.
   Only the R allocation/reader/interrupt boundary is mocked. The private
   Python driver inserts counters into copies, never the package headers. */
#include <float.h>
#include <fenv.h>
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
    size_t length, missing_count, chunk_size;
    const unsigned char *raw;
    uint32_t domain_flags;
    uint32_t float_max_magnitude_bound, float_min_nonzero_magnitude_bound;
    size_t zero_count;
} numeric_data;
enum { NUMERIC_DOMAIN_STRICT_MODERN_FLOAT = 1U,
    NUMERIC_DOMAIN_FLOAT_BOUNDS_KNOWN = 2U, NUMERIC_DOMAIN_ZERO_COUNT_KNOWN = 4U };
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
static size_t integer_zero_test_rows, integer_zero_reduction_rows, integer_cached_rows;
static size_t lookup_table_entries, lookup_table_divisions, lookup_rows, integer_row_divisions;
static size_t scratch_allocations, scratch_bytes;
static int facts_mode, minimum_mode = -1, direct_mode;
static SEXP allocated[4];
static void *scratch[4];
static size_t width(int kind) { return kind == 0 ? 1 : kind == 1 ? 2 : kind < 4 ? 4 : 8; }
static void R_CheckUserInterrupt(void) {}
static char *R_alloc(size_t count, int size) {
    if (scratch_allocations == 4 || size <= 0 || count > SIZE_MAX / (size_t)size) abort();
    char *result = malloc(count * (size_t)size);
    if (!result) abort();
    scratch[scratch_allocations++] = result;
    scratch_bytes += count * (size_t)size;
    return result;
}
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
    if (pattern == 4) return i % 3 == 0 ? 0 : i % 3 == 1 ? 3 : -3;
    if (pattern == 5) return i % 3 == 0 ? limit + (int32_t)(i % 27) : i % 3 == 1 ? 3 : -3;
    if (pattern == 6) {
        if (kind == NUMERIC_BYTE) {
            uint8_t code = (uint8_t)i; int8_t value;
            memcpy(&value, &code, sizeof(value)); return value;
        }
        uint16_t code = (uint16_t)i; int16_t value;
        memcpy(&value, &code, sizeof(value)); return value;
    }
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
static double quotient(double scalar, int32_t source) {
    volatile double numerator=scalar, denominator=(double)source;
    return numerator/denominator;
}
static int run_case(size_t length, int kind, int pattern, double scalar,
        int legacy, size_t chunks, int required) {
    phase = 0; fit_rows = scalar_reads = allocations = 0;
    integer_zero_test_rows=integer_zero_reduction_rows=integer_cached_rows=0;
    lookup_table_entries=lookup_table_divisions=lookup_rows=integer_row_divisions=0;
    scratch_allocations=scratch_bytes=0;
    memset(general_rows,0,sizeof general_rows); memset(result_checks,0,sizeof result_checks);
    memset(integer_loads,0,sizeof integer_loads); memset(span_rows,0,sizeof span_rows);
    unsigned char *raw = malloc(length * width(kind));
    if (!raw) return 2;
    numeric_data data = {.kind=kind, .length=length,
        .format_version=legacy ? 111 : 118, .chunk_size=chunks, .raw=raw,
        .domain_flags=(uint32_t)facts_mode};
    const int32_t missing_minimum = arithmetic_integer_missing(&data);
    size_t want_missing = 0;
    double minimum = 0, maximum = 0; unsigned fractional = 0;
    for (size_t i=0;i<length;i++) {
        int32_t x=fixture(i,kind,pattern,length); store_integer(raw,i,kind,x);
        int inherited = x >= missing_minimum;
        data.missing_count += inherited;
        data.zero_count += x == 0;
        double result = inherited ? NA_REAL : quotient(scalar,x);
        int valid = uncounted_result_valid(result); want_missing += !valid;
        double observed = valid ? result : 0;
        if (observed < minimum) minimum = observed;
        if (observed > maximum) maximum = observed;
        fractional |= observed != trunc(observed);
    }
    arithmetic_operand left = {{NULL,&scalar,NULL},1}, right = {{&data,NULL,NULL},(R_xlen_t)length};
    int selected = -1;
    const int minimum_kind = minimum_mode < 0 ? kind : minimum_mode;
    const int used_direct = direct_mode && uncounted_result_valid(scalar) &&
        (minimum_kind == NUMERIC_DOUBLE || fabs(scalar) <= numeric_float_observed_limit());
    SEXP result;
    if (used_direct) {
        arithmetic_general_source x, y;
        if (!arithmetic_general_source_create(&left,&x) ||
            !arithmetic_general_source_create(&right,&y) ||
            !arithmetic_integer_reciprocal_proved(&x,&y,(R_xlen_t)length,'/',minimum_kind)) return 7;
        SEXP backing = arithmetic_backing((R_xlen_t)length, minimum_kind);
        const int known = numeric_zero_count_known(&data);
        arithmetic_general_output output = {.kind=minimum_kind,
            .raw=minimum_kind == NUMERIC_FLOAT ? RAW(backing) : NULL,
            .real=minimum_kind == NUMERIC_DOUBLE ? REAL(backing) : NULL,
            .missing_count=data.missing_count + (known ? data.zero_count : 0)};
#ifdef HAVE_INTEGER_LOOKUP_KERNEL
        if (kind == NUMERIC_BYTE) {
            if (minimum_kind == NUMERIC_FLOAT)
                arithmetic_integer_reciprocal_lookup_byte_float(&y,scalar,(R_xlen_t)length,&output,known);
            else arithmetic_integer_reciprocal_lookup_byte_double(&y,scalar,(R_xlen_t)length,&output,known);
        } else {
            if (minimum_kind == NUMERIC_FLOAT)
                arithmetic_integer_reciprocal_lookup_int_float(&y,scalar,(R_xlen_t)length,&output,known);
            else arithmetic_integer_reciprocal_lookup_int_double(&y,scalar,(R_xlen_t)length,&output,known);
        }
#else
        arithmetic_integer_reciprocal_write(&y,scalar,(R_xlen_t)length,&output);
#endif
        selected = minimum_kind;
        result = arithmetic_adopt_backing(backing,(R_xlen_t)length,selected,output.missing_count);
    } else result = arithmetic_general_result(&left,&right,(R_xlen_t)length,'/',minimum_kind,&selected);
    int wanted = NUMERIC_DOUBLE;
    if (!fractional && minimum_kind < NUMERIC_FLOAT) {
        const double lows[] = {-127,-32767,-2147483647.0};
        const double highs[] = {100,32740,2147483620.0};
        for (int k=minimum_kind;k<=NUMERIC_LONG;k++) if (minimum >= lows[k] && maximum <= highs[k]) {
            wanted=k; break;
        }
    }
    if (wanted == NUMERIC_DOUBLE && minimum_kind != NUMERIC_LONG && minimum_kind != NUMERIC_DOUBLE &&
            minimum >= -numeric_float_observed_limit() && maximum <= numeric_float_observed_limit())
        wanted=NUMERIC_FLOAT;
    if (selected != wanted || result->missing_count != want_missing || scalar_reads != 1) return 3;
    for (size_t i=0;i<length;i++) {
        int32_t x=fixture(i,kind,pattern,length);
        double value = x>=missing_minimum ? NA_REAL : quotient(scalar,x);
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
    int admitted_bound = selected == NUMERIC_DOUBLE ? uncounted_result_valid(scalar) :
        selected == NUMERIC_FLOAT && fabs(scalar) <= numeric_float_observed_limit();
    const int want_lookup = admitted_bound && kind <= NUMERIC_INT &&
        (length >= 262144 || used_direct);
    const size_t codes = kind == NUMERIC_BYTE ? 256 : 65536;
    const size_t divisions = (size_t)missing_minimum + codes/2 - 1;
    const int initial_bound = minimum_kind != NUMERIC_FLOAT ||
        fabs(scalar) <= numeric_float_observed_limit();
    int red = required && admitted_bound && ((initial_bound && general_rows[1] != 0) ||
        (facts_mode ? (integer_cached_rows != length || integer_zero_reduction_rows != 0 ||
            (data.zero_count == 0 && integer_zero_test_rows != 0)) :
            (integer_cached_rows != 0 || integer_zero_reduction_rows != length)));
    if (required && (want_lookup ?
            (lookup_table_entries != codes || lookup_table_divisions != divisions ||
             lookup_rows != length || integer_row_divisions != 0 || scratch_allocations != 1 ||
             scratch_bytes != codes*width(selected)) :
            (lookup_table_entries != 0 || lookup_table_divisions != 0 || lookup_rows != 0 || scratch_allocations != 0))) red=1;
    printf("%d,%zu,%d,%d,%a,%d,%zu,%d,%d,%d,%d,%d,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%d\n",
        facts_mode,length,kind,pattern,scalar,legacy,chunks,fegetround(),selected,
        minimum_mode,direct_mode,used_direct,admitted_bound,general_rows[0],general_rows[1],result_checks[0],result_checks[1],
        fit_rows,integer_loads[0],integer_loads[1],span_rows[0],span_rows[1],want_missing,
        integer_zero_test_rows,integer_zero_reduction_rows,integer_cached_rows,
        lookup_table_entries,lookup_table_divisions,lookup_rows,integer_row_divisions,
        scratch_allocations,scratch_bytes,red);
    for (size_t i=0;i<allocations;i++) {free(allocated[i]->raw);free(allocated[i]);}
    for (size_t i=0;i<scratch_allocations;i++) free(scratch[i]);
    free(raw);
    return red ? 1 : 0;
}
static int semantic_failures, work_failures, cases;
static void record_case(size_t n, int kind, int pattern, double scalar, int legacy, size_t chunks, int required) {
    int status=run_case(n,kind,pattern,scalar,legacy,chunks,required);
    cases++;
    if (status==1) work_failures++;
    else if (status!=0) {
        semantic_failures++;
        fprintf(stderr,"Semantic error %d: length=%zu kind=%d pattern=%d scalar=%a legacy=%d\n",status,n,kind,pattern,scalar,legacy);
    }
}
int main(int argc, char **argv) {
    (void)argv;
    if (sizeof(float)!=4 || sizeof(double)!=8 || FLT_RADIX!=2 ||
        FLT_MANT_DIG!=24 || DBL_MANT_DIG!=53) return 2;
    puts("facts,length,kind,pattern,scalar,legacy,chunk,rounding,output,minimum_kind,direct,used_direct,admitted_bound,preflight_rows,generic_output_rows,preflight_result_checks,output_result_checks,float_fit_rows,preflight_integer_loads,output_integer_loads,preflight_span_rows,output_span_rows,result_missing,zero_test_rows,zero_reduction_rows,cached_rows,lookup_table_entries,lookup_table_divisions,lookup_rows,row_divisions,scratch_allocations,scratch_bytes,work_failure");
    if (fesetround(FE_TONEAREST)) return 2;
    const size_t lengths[] = {16383,16384,16385,1000000};
    for (int kind=0;kind<=2;kind++) for (int p=0;p<=1;p++)
        record_case(1000000,kind,p,1.01,0,0,argc>1);
    for (size_t j=0;j<4;j++)
        record_case(lengths[j],NUMERIC_INT,2,1.0,0,0,argc>1);
    const double scalars[] = {0.0,-0.0,1.01,-1.01,0x1.fffffep126,-0x1.fffffep126,0x1p127,DBL_MAX/2,DBL_MAX};
    for (int kind=0;kind<=2;kind++) for (int legacy=0;legacy<=1;legacy++)
        for (size_t j=0;j<sizeof(scalars)/sizeof(*scalars);j++)
            record_case(128,kind,3,scalars[j],legacy,7,argc>1);
    const int modes[]={FE_TONEAREST,FE_DOWNWARD,FE_UPWARD,FE_TOWARDZERO};
    const uint64_t positive[]={UINT64_C(0x3fd5555555555555),UINT64_C(0x3fd5555555555555),
        UINT64_C(0x3fd5555555555556),UINT64_C(0x3fd5555555555555)};
    const uint64_t negative[]={UINT64_C(0xbfd5555555555555),UINT64_C(0xbfd5555555555556),
        UINT64_C(0xbfd5555555555555),UINT64_C(0xbfd5555555555555)};
    const int patterns[]={0,3,4,5};
    const double fact_scalars[]={1.01,-1.01,-0.0};
    for (size_t m=0;m<4;m++) {
        if (fesetround(modes[m]) || fegetround()!=modes[m]) return 2;
        double plus=quotient(1.0,3),minus=quotient(-1.0,3);uint64_t p,n;
        memcpy(&p,&plus,8);memcpy(&n,&minus,8);
        if (p!=positive[m] || n!=negative[m]) return 2;
        fprintf(stderr,"ROUNDING,%zu,%d,PASS\n",m,modes[m]);
        for (int facts=0;facts<=4;facts+=4) {
            facts_mode=facts;
            for (int kind=0;kind<=2;kind++) for (int legacy=0;legacy<=1;legacy++)
                for (size_t j=0;j<sizeof(patterns)/sizeof(*patterns);j++)
                    for (size_t s=0;s<sizeof(fact_scalars)/sizeof(*fact_scalars);s++)
                        record_case(129,kind,patterns[j],fact_scalars[s],legacy,7,argc>1);
        }
        /* Direct calls qualify all physical codes, including the legacy
           negative endpoints unavailable through strict public constructors.
           The unchanged general-result route separately proves admission. */
        const double lookup_scalars[] = {0.0,-0.0,1.01,-1.01,0x1p-1074,-0x1p-1074,
            0x1.fffffep126,-0x1.fffffep126,0x1.fffffffffffffp1022,-0x1.fffffffffffffp1022};
        for (int facts=0;facts<=4;facts+=4) {
            facts_mode=facts;
            for (int kind=0;kind<=1;kind++) for (int legacy=0;legacy<=1;legacy++)
                for (int destination=NUMERIC_FLOAT;destination<=NUMERIC_DOUBLE;destination++) {
                    minimum_mode=destination; direct_mode=1;
                    for (size_t s=0;s<sizeof(lookup_scalars)/sizeof(*lookup_scalars);s++)
                        record_case(kind == NUMERIC_BYTE ? 256 : 65536,kind,6,
                            lookup_scalars[s],legacy,4093,argc>1);
                    direct_mode=0;
                    const size_t threshold_lengths[]={262143,262144,262145};
                    for (size_t j=0;j<3;j++)
                        record_case(threshold_lengths[j],kind,6,1.01,legacy,4093,argc>1);
                }
        }
        minimum_mode=-1;
    }
    fesetround(FE_TONEAREST);
    fprintf(stderr,"%s: %d semantic failures, %d proved-work failures across %d cases\n",
        semantic_failures || work_failures ? "FAIL" : "PASS",semantic_failures,work_failures,cases);
    return semantic_failures || work_failures ? 1 : 0;
}
