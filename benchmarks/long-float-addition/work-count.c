/* Actual production result/preflight/producer headers; only the R allocation,
   reader, retained-span and interrupt boundaries are mocked. Private copies
   add counters at existing general-loop and pair-loader entry points. */
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
    uint32_t float_max_magnitude_bound, float_min_nonzero_magnitude_bound;
    size_t zero_count;
    size_t length;
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
static const union { uint64_t bits; double value; } mock_na = { UINT64_C(0x7ff00000000007a2) };
#define NA_REAL (mock_na.value)
#define NA_INTEGER INT_MIN
#define R_FINITE isfinite
#define PROTECT(x) (x)
#define UNPROTECT(x) ((void)(x))
#define PROTECT_WITH_INDEX(x, i) ((void)(*(i) = 0), (void)(x))
#define REPROTECT(x, i) ((void)(i), (void)(x))
#define RAW(x) ((x)->raw)
#define REAL(x) ((double *)(void *)(x)->raw)
static int phase;
static size_t general_rows[2], result_checks[2], span_rows[2];
static size_t exact_integer_rows, exact_float_rows, allocations;
static size_t proof_rows, interrupt_calls;
static SEXP allocated[4];
static size_t width(int kind) { return kind == 0 ? 1 : kind == 1 ? 2 : kind < 4 ? 4 : 8; }
static void R_CheckUserInterrupt(void) { interrupt_calls++; }
/* R_alloc's per-call scratch is modelled by one reusable arena. No probe
   result or input aliases it; only the ephemeral reciprocal table uses it. */
static void *mock_scratch;
static void release_mock_scratch(void) { free(mock_scratch); }
static char *R_alloc(size_t count, int size) {
    if (size <= 0 || count > SIZE_MAX / (size_t) size) abort();
    if (mock_scratch == NULL && atexit(release_mock_scratch) != 0) abort();
    void *next = realloc(mock_scratch, count * (size_t) size);
    if (next == NULL) abort();
    mock_scratch = next;
    return next;
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
    (void)reader; (void)start; (void)count; (void)value; (void)code;
    abort(); /* All fixtures are full-length pairs with at least two rows. */
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

enum { ORDINARY, SPARSE, PREFIX, SUFFIX, RANDOM_HALF, ALL_TAGS, ALTERNATING, EDGES, ALL_LONG, ALL_FLOAT };
static const char *patterns[] = {"ordinary", "sparse", "prefix256", "suffix256", "random_half", "all_tags", "alternating64", "edges", "all_long_missing", "all_float_missing"};
static int missing_position(size_t i, size_t n, int pattern, int side) {
    if (pattern == SPARSE) return side ? i >= 18 && (i-18)%991 == 0 : i >= 12 && (i-12)%997 == 0;
    if (pattern == PREFIX) return side && i < 256;
    if (pattern == SUFFIX) return side && i >= n-256;
    if (pattern == RANDOM_HALF) {
        uint32_t v=(uint32_t)i + (side ? UINT32_C(0x9e3779b9) : UINT32_C(0x7f4a7c15));
        v ^= v>>16; v *= UINT32_C(0x7feb352d); v ^= v>>15;
        return (int)(v & 1U);
    }
    if (pattern == ALL_TAGS) return 1;
    if (pattern == ALL_LONG) return !side;
    if (pattern == ALL_FLOAT) return side;
    if (pattern == ALTERNATING) return (i/64)%2 == 0;
    return 0;
}
/* This oracle does not reuse production classifiers. Integer threshold and
   exact float bits are enumerated independently, including permissive imports. */
static int integer_missing(int32_t value, int legacy) {
    return value >= (legacy ? INT32_MAX : INT32_C(2147483621));
}
static int float_missing(uint32_t bits, int legacy) {
    uint32_t magnitude=bits & UINT32_C(0x7fffffff);
    if (magnitude > UINT32_C(0x7f800000)) return 1;
    if (legacy) return bits >= UINT32_C(0x7f000000) && bits <= UINT32_C(0x7fffffff);
    for (uint32_t code=0;code<=26;code++)
        if (bits == UINT32_C(0x7f000000)+code*2048U) return 1;
    return 0;
}
static void fixture(size_t i,size_t n,int pattern,int legacy_x,int legacy_y,
        int32_t *x,uint32_t *y) {
    *x=(int32_t)((13*(i+1))%10001)-5000;
    float f=(float)((int32_t)((19*(i+1))%1001)-500)/8.0f;
    memcpy(y,&f,4);
    if (missing_position(i,n,pattern,0))
        *x=legacy_x ? INT32_MAX : INT32_C(2147483621)+(int32_t)(i%27);
    if (missing_position(i,n,pattern,1)) *y=UINT32_C(0x7f000000)+(uint32_t)(i%27)*2048U;
    if (pattern == EDGES || pattern == ALL_LONG || pattern == ALL_FLOAT) {
        const int32_t integers[]={INT32_MIN,-1,0,1,16777217,INT32_C(2147483620),INT32_C(2147483621),INT32_C(2147483646),INT32_MAX};
        const uint32_t floats[]={0,UINT32_C(0x80000000),1,UINT32_C(0x80000001),UINT32_C(0x7effffff),UINT32_C(0xfeffffff),UINT32_C(0x7f000001),UINT32_C(0xff000001),UINT32_C(0x7f7fffff),UINT32_C(0xff7fffff),UINT32_C(0x7f800000),UINT32_C(0xff800000),UINT32_C(0x7fc00001),UINT32_C(0xff800001)};
        /* Include every tag and every imported edge in a Cartesian grid. */
        size_t fy=i%(sizeof(floats)/sizeof(*floats)+27);
        *x=integers[(i/(sizeof(floats)/sizeof(*floats)+27))%(sizeof(integers)/sizeof(*integers))];
        *y=fy<sizeof(floats)/sizeof(*floats) ? floats[fy] : UINT32_C(0x7f000000)+(uint32_t)(fy-sizeof(floats)/sizeof(*floats))*2048U;
        if (pattern == ALL_LONG) *x=legacy_x ? INT32_MAX : INT32_C(2147483621)+(int32_t)(i%27);
        if (pattern == ALL_FLOAT) *y=UINT32_C(0x7f000000)+(uint32_t)(i%27)*2048U;
    }
    (void)legacy_y;
}
static int run_case(size_t length,int pattern,int legacy_x,int legacy_y,
        size_t xchunk,size_t ychunk,int reverse,int required) {
    phase=0; allocations=exact_integer_rows=exact_float_rows=0;
    proof_rows=interrupt_calls=0;
    memset(general_rows,0,sizeof general_rows); memset(result_checks,0,sizeof result_checks);
    memset(span_rows,0,sizeof span_rows);
    int32_t *x=malloc(length*4); uint32_t *y=malloc(length*4);
    if (!x || !y) abort();
    numeric_data xd={NUMERIC_LONG,0,legacy_x?111:118,0,xchunk,(const unsigned char *)x,0,0,0,0,length};
    numeric_data yd={NUMERIC_FLOAT,0,legacy_y?111:118,0,ychunk,(const unsigned char *)y,0,0,0,0,length};
    size_t wanted_missing=0,overlap=0;
    for (size_t i=0;i<length;i++) {
        fixture(i,length,pattern,legacy_x,legacy_y,x+i,y+i);
        int xm=integer_missing(x[i],legacy_x),ym=float_missing(y[i],legacy_y);
        xd.missing_count+=xm; yd.missing_count+=ym; overlap+=(xm && ym);
        wanted_missing += xm || ym || (y[i]&UINT32_C(0x7fffffff)) == UINT32_C(0x7f800000);
    }
    arithmetic_operand xo={{&xd,NULL,NULL},(R_xlen_t)length}, yo={{&yd,NULL,NULL},(R_xlen_t)length};
    int selected=-1;
    int minimum=arithmetic_promoted_kind(reverse?NUMERIC_FLOAT:NUMERIC_LONG,reverse?NUMERIC_LONG:NUMERIC_FLOAT);
    SEXP result=arithmetic_general_result(reverse?&yo:&xo,reverse?&xo:&yo,(R_xlen_t)length,'+',minimum,&selected);
    int semantic=0;
    if (selected!=NUMERIC_DOUBLE || result->kind!=NUMERIC_DOUBLE || result->missing_count!=wanted_missing ||
        general_rows[0] || general_rows[1] || allocations!=1) semantic=1;
    for (size_t i=0;i<length;i++) {
        int32_t original_x; uint32_t original_y;
        fixture(i,length,pattern,legacy_x,legacy_y,&original_x,&original_y);
        if (x[i]!=original_x || y[i]!=original_y) semantic=2;
        float f; memcpy(&f,&original_y,4);
        int invalid=integer_missing(original_x,legacy_x) || float_missing(original_y,legacy_y) ||
            (original_y&UINT32_C(0x7fffffff)) == UINT32_C(0x7f800000);
        double wanted=invalid ? NA_REAL : reverse ? (double)f+(double)original_x : (double)original_x+(double)f;
        if (memcmp(result->raw+i*8,&wanted,8)) semantic=3;
    }
    /* Meaningful structural gates, independent of an exact chosen tile size.
       Fallback must count the union; inherited counts can overlap. A proved
       ordinary block has zero missing output and needs no per-row union count. */
    int all_missing=xd.missing_count==length || yd.missing_count==length;
    int gated=length==1000000 && (pattern==ORDINARY || pattern==SPARSE || pattern==PREFIX);
    size_t bound=pattern==ORDINARY ? 0 : pattern==SPARSE ? length/5 : length/10;
    int red=required && gated && exact_float_rows>bound;
    int all_work=all_missing && (exact_float_rows || exact_integer_rows || proof_rows || span_rows[1]);
    if (all_missing && interrupt_calls < (length+16383)/16384) semantic=4;
    printf("%zu,%s,%d,%d,%zu,%zu,%d,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%d,%zu,%d,%d,%d,%zu,%zu,%zu\n",
        length,patterns[pattern],legacy_x,legacy_y,xchunk,ychunk,reverse,selected,
        general_rows[0],general_rows[1],exact_integer_rows,exact_float_rows,
        xd.missing_count,yd.missing_count,overlap,wanted_missing,result->missing_count,allocations,
        gated,bound,semantic,all_missing,all_work,proof_rows,span_rows[1],interrupt_calls);
    for(size_t i=0;i<allocations;i++){free(allocated[i]->raw);free(allocated[i]);}
    free(x);free(y);
    return semantic ? 2 : red || (required && all_work) ? 1 : 0;
}
static int semantic_failures,work_failures,cases;
static void record(size_t n,int pattern,int lx,int ly,size_t xc,size_t yc,int reverse,int required) {
    int status=run_case(n,pattern,lx,ly,xc,yc,reverse,required); cases++;
    if(status==1)work_failures++;else if(status)semantic_failures++;
}
int main(int argc,char **argv) {
    (void)argv;
    if(sizeof(float)!=4 || sizeof(double)!=8 || FLT_RADIX!=2 || FLT_MANT_DIG!=24 || DBL_MANT_DIG!=53) return 2;
    puts("length,pattern,legacy_long,legacy_float,long_chunk,float_chunk,reverse,output,preflight_rows,general_output_rows,exact_integer_rows,exact_float_rows,input_long_missing,input_float_missing,overlap,result_missing,stored_missing,allocations,work_gate,work_bound,semantic_error,all_missing_gate,all_missing_work_failure,proof_rows,source_span_rows,interrupt_calls");
    for(int reverse=0;reverse<=1;reverse++)for(int pattern=ORDINARY;pattern<=ALL_TAGS;pattern++)
        record(1000000,pattern,0,0,0,0,reverse,argc>1);
    for(int reverse=0;reverse<=1;reverse++)for(int pattern=ORDINARY;pattern<=PREFIX;pattern++)
        record(1000000,pattern,0,0,8191,16385,reverse,argc>1);
    const size_t lengths[]={2,63,64,65,255,256,257,16383,16384,16385,32767,32768,32769};
    for(int lx=0;lx<=1;lx++)for(int ly=0;ly<=1;ly++)for(int reverse=0;reverse<=1;reverse++) {
        record(369,EDGES,lx,ly,7,11,reverse,argc>1);
        for(size_t j=0;j<sizeof(lengths)/sizeof(*lengths);j++)
            record(lengths[j],ALTERNATING,lx,ly,7,11,reverse,argc>1);
    }
    for(int reverse=0;reverse<=1;reverse++) {
        record(1000000,ALL_TAGS,0,0,8191,16385,reverse,argc>1);
        record(1000000,ALL_TAGS,0,0,7,11,reverse,argc>1);
        for(int pattern=ALL_LONG;pattern<=ALL_FLOAT;pattern++) {
            record(1000000,pattern,0,0,0,0,reverse,argc>1);
            record(1000000,pattern,0,0,8191,16385,reverse,argc>1);
            record(1000000,pattern,0,0,7,11,reverse,argc>1);
            for(int lx=0;lx<=1;lx++)for(int ly=0;ly<=1;ly++)
                record(128,pattern,lx,ly,7,11,reverse,argc>1);
        }
    }
    fprintf(stderr,"%s: %d semantic failures, %d proved-work failures across %d cases\n",
        semantic_failures||work_failures?"FAIL":"PASS",semantic_failures,work_failures,cases);
    return semantic_failures||work_failures?1:0;
}
