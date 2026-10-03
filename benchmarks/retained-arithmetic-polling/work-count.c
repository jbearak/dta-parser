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
} numeric_data;
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
static size_t span_calls, interrupt_calls, completed_rows, last_poll_row, max_poll_gap;
static uint64_t span_trace, poll_trace;
#include "cadence.h"
static void trace_word(uint64_t value) {
    for (unsigned i=0;i<8;i++) { span_trace ^= value & 255; span_trace *= UINT64_C(1099511628211); value >>= 8; }
}
static SEXP allocated[4];
static size_t width(int kind) { return kind == 0 ? 1 : kind == 1 ? 2 : kind < 4 ? 4 : 8; }
static void R_CheckUserInterrupt(void) {
    if (phase != 1) abort(); /* This double-output pair has no scanning preflight. */
    interrupt_calls++;
    schedule_word(&poll_trace, completed_rows);
    size_t gap=completed_rows-last_poll_row;
    if (gap>max_poll_gap) max_poll_gap=gap;
    last_poll_row=completed_rows;
}
static const unsigned char *numeric_read_span(const numeric_data *data,
        size_t start, size_t count, size_t *available) {
    size_t requested=count;
    if (data->chunk_size && count > data->chunk_size - start % data->chunk_size)
        count = data->chunk_size - start % data->chunk_size;
    *available = count;
    span_rows[phase] += count;
    span_calls++;
    trace_word((uint64_t)data->kind); trace_word(start); trace_word(requested); trace_word(count);
    /* Completion is counted at the actual producer seam, after processing. */
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

enum { ORDINARY, SPARSE, PREFIX, SUFFIX, RANDOM_HALF, ALL_TAGS, ALTERNATING, EDGES };
static const char *patterns[] = {"ordinary", "sparse", "prefix256", "suffix256", "random_half", "all_tags", "alternating64", "edges"};
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
    if (pattern == EDGES) {
        const int32_t integers[]={INT32_MIN,-1,0,1,16777217,INT32_C(2147483620),INT32_C(2147483621),INT32_C(2147483646),INT32_MAX};
        const uint32_t floats[]={0,UINT32_C(0x80000000),1,UINT32_C(0x80000001),UINT32_C(0x7effffff),UINT32_C(0xfeffffff),UINT32_C(0x7f000001),UINT32_C(0xff000001),UINT32_C(0x7f7fffff),UINT32_C(0xff7fffff),UINT32_C(0x7f800000),UINT32_C(0xff800000),UINT32_C(0x7fc00001),UINT32_C(0xff800001)};
        /* Include every tag and every imported edge in a Cartesian grid. */
        size_t fy=i%(sizeof(floats)/sizeof(*floats)+27);
        *x=integers[(i/(sizeof(floats)/sizeof(*floats)+27))%(sizeof(integers)/sizeof(*integers))];
        *y=fy<sizeof(floats)/sizeof(*floats) ? floats[fy] : UINT32_C(0x7f000000)+(uint32_t)(fy-sizeof(floats)/sizeof(*floats))*2048U;
    }
    (void)legacy_y;
}
static int run_case(size_t length,int pattern,int legacy_x,int legacy_y,
        size_t xchunk,size_t ychunk,int reverse,int required) {
    phase=0; allocations=exact_integer_rows=exact_float_rows=0;
    span_calls=interrupt_calls=completed_rows=last_poll_row=max_poll_gap=0;
    span_trace=poll_trace=UINT64_C(14695981039346656037);
    memset(general_rows,0,sizeof general_rows); memset(result_checks,0,sizeof result_checks);
    memset(span_rows,0,sizeof span_rows);
    int32_t *x=malloc(length*4); uint32_t *y=malloc(length*4);
    if (!x || !y) abort();
    numeric_data xd={NUMERIC_LONG,0,legacy_x?111:118,0,xchunk,(const unsigned char *)x};
    numeric_data yd={NUMERIC_FLOAT,0,legacy_y?111:118,0,ychunk,(const unsigned char *)y};
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
    size_t tail=length-last_poll_row;
    if(tail>max_poll_gap)max_poll_gap=tail;
    if(completed_rows!=length || span_calls%2 || max_poll_gap>16384)semantic=4;
    int gated=1;
    expected_schedule model=model_complete_spans(length,xchunk,ychunk,reverse);
    size_t bound=model.interrupt_calls;
    int work_error=interrupt_calls!=model.interrupt_calls || span_calls!=model.span_calls ||
        span_trace!=model.span_trace || poll_trace!=model.poll_trace || max_poll_gap!=model.maximum_gap;
    int red=required && work_error;
    printf("%zu,%s,%d,%d,%zu,%zu,%d,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%d,%zu,%d,%zu,%zu,%zu,%016llx,%016llx,%zu,%016llx,%016llx,%zu,%d\n",
        length,patterns[pattern],legacy_x,legacy_y,xchunk,ychunk,reverse,selected,
        general_rows[0],general_rows[1],exact_integer_rows,exact_float_rows,
        xd.missing_count,yd.missing_count,overlap,wanted_missing,result->missing_count,allocations,
        gated,bound,semantic,span_calls,interrupt_calls,max_poll_gap,(unsigned long long)span_trace,
        (unsigned long long)poll_trace,model.span_calls,(unsigned long long)model.span_trace,
        (unsigned long long)model.poll_trace,model.maximum_gap,work_error);
    for(size_t i=0;i<allocations;i++){free(allocated[i]->raw);free(allocated[i]);}
    free(x);free(y);
    return semantic ? 2 : red ? 1 : 0;
}
static int semantic_failures,work_failures,cases;
static void record(size_t n,int pattern,int lx,int ly,size_t xc,size_t yc,int reverse,int required) {
    int status=run_case(n,pattern,lx,ly,xc,yc,reverse,required); cases++;
    if(status==1)work_failures++;else if(status)semantic_failures++;
}
int main(int argc,char **argv) {
    (void)argv;
    if(sizeof(float)!=4 || sizeof(double)!=8 || FLT_RADIX!=2 || FLT_MANT_DIG!=24 || DBL_MANT_DIG!=53) return 2;
    puts("length,pattern,legacy_long,legacy_float,long_chunk,float_chunk,reverse,output,preflight_rows,general_output_rows,exact_integer_rows,exact_float_rows,input_long_missing,input_float_missing,overlap,result_missing,stored_missing,allocations,work_gate,work_bound,semantic_error,span_calls,interrupt_calls,max_poll_gap,span_trace,poll_trace,expected_span_calls,expected_span_trace,expected_poll_trace,expected_max_poll_gap,work_error");
    const size_t chunks[][2]={{0,0},{8191,16385},{7,11}};
    for(int reverse=0;reverse<=1;reverse++)for(int pattern=ORDINARY;pattern<=SPARSE;pattern++)
        for(size_t c=0;c<3;c++)record(1000000,pattern,0,0,chunks[c][0],chunks[c][1],reverse,argc>1);
    for(int reverse=0;reverse<=1;reverse++)for(size_t n=16383;n<=16385;n++)
        record(n,ORDINARY,0,0,7,11,reverse,argc>1);
    fprintf(stderr,"%s: %d semantic failures, %d proved-work failures across %d cases\n",
        semantic_failures||work_failures?"FAIL":"PASS",semantic_failures,work_failures,cases);
    return semantic_failures||work_failures?1:0;
}
