/* This includes the actual production result, preflight, and producer bodies.
   Only the R allocation/reader/interrupt boundary is mocked. The private
   Python driver inserts counters into copies, never the package headers. */
#include <float.h>
#include <fenv.h>
/* Match the production translation unit: no FENV_ACCESS pragma. */
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
typedef struct {
    const numeric_data *storage;
    const double *real_values;
    const int *integer_values;
} numeric_reader;
typedef struct { numeric_reader reader; R_xlen_t length; } arithmetic_operand;
typedef struct allocation { unsigned char *raw; size_t missing_count; int kind; } *SEXP;
typedef int PROTECT_INDEX;
static double r_na_real(void) {
    uint64_t bits=UINT64_C(0x7ff00000000007a2); double value;
    memcpy(&value,&bits,sizeof value); return value;
}
#define NA_REAL r_na_real()
#define NA_INTEGER INT_MIN
#define R_FINITE isfinite
#define PROTECT(x) (x)
#define UNPROTECT(x) ((void)(x))
#define PROTECT_WITH_INDEX(x, i) ((void)(*(i) = 0), (void)(x))
#define REPROTECT(x, i) ((void)(i), (void)(x))
#define RAW(x) ((x)->raw)
#define REAL(x) ((double *)(void *)(x)->raw)
static int domain_mode;
static size_t canonical_attempt_rows, canonical_committed_rows, whole_write_rows;
static int phase;
static size_t general_rows[2], result_checks[2], integer_loads[2], span_rows[2];
static size_t fit_rows, float_loads, scalar_reads, allocations;
static size_t reciprocal_proof_rows, reciprocal_fast_rows, reciprocal_exact_rows, reciprocal_fit_rows, reciprocal_threshold_calls;
static size_t reciprocal_prepare_rows, reciprocal_scratch_bytes, reciprocal_prepared_rows, reciprocal_prepared_divisions, reciprocal_fill_rows, reciprocal_all_missing_rows;
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
#include "production-domain.h"
#include "production-common.h"
#include "numeric-arithmetic-general.h"

static uint32_t to_bits(float value) {
    uint32_t bits; memcpy(&bits,&value,4); return bits;
}
static float from_bits(uint32_t bits) {
    float value; memcpy(&value,&bits,4); return value;
}
/* The oracle does not call the production missing or result predicates. */
static int input_missing(uint32_t bits, int legacy) {
    const uint32_t magnitude=bits & UINT32_C(0x7fffffff);
    if (magnitude>UINT32_C(0x7f800000)) return 1;
    if (legacy) return bits>=UINT32_C(0x7f000000) && bits<=UINT32_C(0x7fffffff);
    return bits>=UINT32_C(0x7f000000) && bits<=UINT32_C(0x7f00d000) &&
        (bits & UINT32_C(0x7ff))==0;
}
static double quotient(double scalar, float source) {
    volatile double numerator=scalar, denominator=(double)source;
    return numerator/denominator;
}
static int result_valid(double value) {
    return isfinite(value) && fabs(value)<=0x1.fffffffffffffp1022;
}
static uint32_t fixture(size_t i, int pattern, size_t length, double scalar) {
    if (pattern >= 15 && pattern <= 17) {
        if (pattern == 17 && i % 3 == 2)
            return UINT32_C(0x7f000000) + (uint32_t)(i % 27) * 0x800U;
        if (pattern == 17 || (pattern == 16 && i % 4 == 2))
            return i % 2 ? UINT32_C(0x80000000) : 0;
        if (pattern == 16 && i % 4 == 3)
            return UINT32_C(0x7f000000) + (uint32_t)(i % 27) * 0x800U;
        if (pattern == 15 && i % 4 >= 2)
            return i % 2 ? UINT32_C(0x80000000) : 0;
        return to_bits(i % 2 ? -0.125f : 0.125f);
    }
    if (pattern==13 || pattern==14) {
        if (pattern==14 && i+1==length) return 1U;
        if ((i*UINT64_C(104729))%length < length/2)
            return UINT32_C(0x7f000000)+(uint32_t)(i%27)*0x800U;
        if (pattern==14) return to_bits(i%2 ? -0.125f : 0.125f);
        const uint32_t values[]={0,UINT32_C(0x80000000),1,UINT32_C(0x80000001),
            UINT32_C(0x7effffff),UINT32_C(0xfeffffff),UINT32_C(0x3eaaaaab),
            UINT32_C(0xbeaaaaab),UINT32_C(0x3f800000),UINT32_C(0xbf800000)};
        return values[i%(sizeof(values)/sizeof(*values))];
    }
    if (pattern==11 || pattern==12) {
        size_t prefix=pattern==11 ? 256 : length/2;
        return i<prefix ? UINT32_C(0x7f000000)+(uint32_t)(i%27)*0x800U :
            to_bits(i%2 ? -0.125f : 0.125f);
    }
    if (pattern==8) {
        /* Coprime permutation gives exactly half missing at n=1m. */
        if ((i*UINT64_C(104729))%length < length/2)
            return UINT32_C(0x7f000000)+(uint32_t)(i%27)*0x800U;
        return to_bits(i%2 ? -0.125f : 0.125f);
    }
    if (pattern==9) return UINT32_C(0x7f000000)+(uint32_t)(i%27)*0x800U;
    if (pattern==10) {
        const uint32_t values[]={0,UINT32_C(0x80000000),UINT32_C(0x7f000000),
            UINT32_C(0x7f00d000),UINT32_C(0x7f000001),UINT32_C(0xff000001),
            UINT32_C(0x7f7fffff),UINT32_C(0xff7fffff),UINT32_C(0x7f800000),
            UINT32_C(0xff800000),UINT32_C(0x7fc00001),UINT32_C(0xff800001),
            UINT32_C(0x3e000000),UINT32_C(0xbe000000)};
        return values[i%(sizeof(values)/sizeof(*values))];
    }
    if (pattern<=1) {
        if (pattern==1 && i>=12 && (i-12)%997==0) return UINT32_C(0x7f000000);
        return to_bits((float)((int32_t)((13*(i+1))%10001)-5000)/8.0f);
    }
    if (pattern==2) {
        const uint32_t values[]={0,UINT32_C(0x80000000),1,UINT32_C(0x80000001),
            UINT32_C(0x7effffff),UINT32_C(0xfeffffff),UINT32_C(0x7f000001),
            UINT32_C(0x7f00d001),UINT32_C(0x7f7fffff),UINT32_C(0xff7fffff),
            UINT32_C(0x7f800000),UINT32_C(0xff800000),UINT32_C(0x7fc00000),
            UINT32_C(0xffc00000),UINT32_C(0x7f800001),UINT32_C(0xff800001),
            UINT32_C(0x3eaaaaab),UINT32_C(0xbeaaaaab)};
        size_t index=i%(sizeof(values)/sizeof(*values)+27);
        return index<sizeof(values)/sizeof(*values) ? values[index] :
            UINT32_C(0x7f000000)+(uint32_t)(index-sizeof(values)/sizeof(*values))*0x800U;
    }
    if (pattern==3) return i+1==length ? 1U : to_bits(i%2 ? -0.125f : 0.125f);
    if (pattern==4) return i%3==0 ? 0U : to_bits(i%3==1 ? 1.0f : -1.0f);
    if (pattern==5) return i%2 ? UINT32_C(0xff800000) : UINT32_C(0x7f800000);
    if (pattern==6) {
        /* Algebraic estimates only choose neighbors. The expected result
           always comes from the original binary64 division, not a search. */
        volatile double divisor=i%2 ? 0x1.fffffep126 : 0x1.fffffffffffffp1022;
        volatile double estimate=fabs(scalar)/divisor;
        uint32_t center=estimate>=FLT_MAX ? UINT32_C(0x7f7fffff) : to_bits((float)estimate);
        int64_t nearby=(int64_t)center+(int64_t)((i/2)%9)-4;
        if (nearby<0) nearby=0;
        if (nearby>INT64_C(0x7f7fffff)) nearby=INT64_C(0x7f7fffff);
        return (uint32_t)nearby | (i/18%2 ? UINT32_C(0x80000000) : 0U);
    }
    return to_bits(i%2 ? -0.125f : 0.125f);
}
static int run_case(size_t length, int pattern, double scalar, int legacy,
        size_t chunks, int minimum_kind, int rounding, int required) {
    if (fesetround(rounding) || fegetround()!=rounding) return 2;
    canonical_attempt_rows=canonical_committed_rows=whole_write_rows=0;
    phase=0; fit_rows=float_loads=scalar_reads=allocations=0;
    reciprocal_proof_rows=reciprocal_fast_rows=reciprocal_exact_rows=reciprocal_fit_rows=reciprocal_threshold_calls=0;
    reciprocal_prepare_rows=reciprocal_scratch_bytes=reciprocal_prepared_rows=reciprocal_prepared_divisions=reciprocal_fill_rows=reciprocal_all_missing_rows=0;
    memset(general_rows,0,sizeof general_rows); memset(result_checks,0,sizeof result_checks);
    memset(integer_loads,0,sizeof integer_loads); memset(span_rows,0,sizeof span_rows);
    unsigned char *raw=malloc(length*4);
    if (!raw) return 2;
    numeric_data data={.kind=NUMERIC_FLOAT, .length=length,
        .format_version=legacy ? 111 : 118, .chunk_size=chunks, .raw=raw,
        .domain_flags=(uint32_t)domain_mode,
        .float_min_nonzero_magnitude_bound=UINT32_MAX};
    size_t want_missing=0;
    int wanted=minimum_kind;
    for (size_t i=0;i<length;i++) {
        uint32_t bits=fixture(i,pattern,length,scalar); memcpy(raw+4*i,&bits,4);
        int inherited=input_missing(bits,legacy); data.missing_count+=inherited;
        if (!inherited) {
            uint32_t magnitude=bits & UINT32_C(0x7fffffff);
            if (magnitude > data.float_max_magnitude_bound)
                data.float_max_magnitude_bound=magnitude;
            if (magnitude == 0) data.zero_count++;
            else if (magnitude < data.float_min_nonzero_magnitude_bound)
                data.float_min_nonzero_magnitude_bound=magnitude;
        }
        double value=inherited ? NAN : quotient(scalar,from_bits(bits));
        int valid=result_valid(value); want_missing+=!valid;
        if (valid && fabs(value)>0x1.fffffep126) wanted=NUMERIC_DOUBLE;
    }
    /* A conservative lower bound remains true but cannot prove safe input. */
    if (domain_mode == 15) data.float_min_nonzero_magnitude_bound=1;
    arithmetic_operand left={{NULL,&scalar,NULL},1},right={{&data,NULL,NULL},(R_xlen_t)length};
    int selected=-1;
    SEXP result=arithmetic_general_result(&left,&right,(R_xlen_t)length,'/',minimum_kind,&selected);
    int failure=selected!=wanted || result->missing_count!=want_missing || scalar_reads!=1 ? 3 : 0;
    for (size_t i=0;i<length && !failure;i++) {
        uint32_t bits=fixture(i,pattern,length,scalar),actual_source;
        memcpy(&actual_source,raw+4*i,4); if (actual_source!=bits) { failure=4; break; }
        double value=input_missing(bits,legacy) ? NAN : quotient(scalar,from_bits(bits));
        int valid=result_valid(value);
        if (selected==NUMERIC_FLOAT) {
            volatile double exact=value;
            float want=valid ? (float)exact : 0x1p127f;
            if (memcmp(result->raw+4*i,&want,4)) failure=5;
        } else if (selected==NUMERIC_DOUBLE) {
            double actual; memcpy(&actual,result->raw+8*i,8);
            double want=valid ? value : NA_REAL;
            if (memcmp(&actual,&want,8)) failure=6;
        } else failure=7;
    }
    int whole_gate=domain_mode == 7 && !legacy && pattern != 14 &&
        pattern != 17 && (scalar == 1.01 || scalar == 0);
    int red=required && ((pattern==8 && domain_mode && !legacy && !chunks &&
        reciprocal_prepare_rows>256) ||
        ((!domain_mode || legacy) && canonical_attempt_rows!=0) ||
        (whole_gate && (whole_write_rows != length || reciprocal_prepare_rows != 0 ||
            canonical_attempt_rows != 0)) ||
        ((domain_mode == 0 || domain_mode == 1 || domain_mode == 3 || domain_mode == 5 ||
            legacy || (domain_mode == 15 && selected == NUMERIC_FLOAT && scalar == 1.01)) &&
            whole_write_rows != 0));
    printf("%d,%zu,%d,%a,%d,%zu,%d,%d,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%d,%d,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu\n",
        domain_mode,length,pattern,scalar,legacy,chunks,minimum_kind,rounding,selected,
        general_rows[0],general_rows[1],result_checks[0],result_checks[1],fit_rows,
        float_loads,span_rows[0],span_rows[1],want_missing,failure,red,reciprocal_proof_rows,reciprocal_fast_rows,reciprocal_exact_rows,reciprocal_fit_rows,reciprocal_threshold_calls,reciprocal_prepare_rows,reciprocal_scratch_bytes,reciprocal_prepared_rows,reciprocal_prepared_divisions,reciprocal_fill_rows,reciprocal_all_missing_rows,canonical_attempt_rows,canonical_committed_rows,whole_write_rows);
    for (size_t i=0;i<allocations;i++) { free(allocated[i]->raw);free(allocated[i]); }
    free(raw);
    return failure ? failure : red ? 1 : 0;
}
static int rounding_witness(int mode, size_t index) {
    static const uint64_t expected[4][4]={
        {UINT64_C(0x3fd5555555555555),UINT64_C(0xbfd5555555555555),UINT64_C(0x3fb999999999999a),UINT64_C(0xbfb999999999999a)},
        {UINT64_C(0x3fd5555555555555),UINT64_C(0xbfd5555555555556),UINT64_C(0x3fb9999999999999),UINT64_C(0xbfb999999999999a)},
        {UINT64_C(0x3fd5555555555556),UINT64_C(0xbfd5555555555555),UINT64_C(0x3fb999999999999a),UINT64_C(0xbfb9999999999999)},
        {UINT64_C(0x3fd5555555555555),UINT64_C(0xbfd5555555555555),UINT64_C(0x3fb9999999999999),UINT64_C(0xbfb9999999999999)}
    };
    if (fesetround(mode) || fegetround()!=mode) return 0;
    for (size_t i=0;i<4;i++) {
        double value=quotient(i%2 ? -1.0 : 1.0,i<2 ? 3.0f : 10.0f);
        uint64_t bits; memcpy(&bits,&value,8);
        if (bits!=expected[index][i]) return 0;
    }
    /* Divide-by-zero is distinct from finite overflow under directed rounding. */
    for (unsigned sign=0;sign<2;sign++) for (unsigned zero_sign=0;zero_sign<2;zero_sign++) {
        float zero=from_bits(zero_sign ? UINT32_C(0x80000000) : 0U);
        double value=quotient(sign ? -1.0 : 1.0,zero); uint64_t bits;
        memcpy(&bits,&value,8);
        uint64_t expected_inf=UINT64_C(0x7ff0000000000000) |
            ((uint64_t)(sign^zero_sign)<<63);
        if(bits!=expected_inf || !isnan(quotient(sign ? -0.0 : 0.0,zero))) return 0;
    }
    const uint64_t positive_overflow[]={UINT64_C(0x7ff0000000000000),UINT64_C(0x7fefffffffffffff),UINT64_C(0x7ff0000000000000),UINT64_C(0x7fefffffffffffff)};
    const uint64_t negative_overflow[]={UINT64_C(0xfff0000000000000),UINT64_C(0xfff0000000000000),UINT64_C(0xffefffffffffffff),UINT64_C(0xffefffffffffffff)};
    double over=quotient(DBL_MAX,0.5f),under=quotient(-DBL_MAX,0.5f);uint64_t ob,ub;
    memcpy(&ob,&over,8);memcpy(&ub,&under,8);
    if(ob!=positive_overflow[index] || ub!=negative_overflow[index]) return 0;
    fprintf(stderr,"ZERO_OVERFLOW,%zu,%d,PASS\n",index,mode);
    fprintf(stderr,"ROUNDING,%zu,%d,PASS\n",index,mode);
    return 1;
}
static size_t semantic_failures,work_failures,cases;
static void record_case(size_t n,int pattern,double scalar,int legacy,size_t chunks,
        int minimum,int rounding,int required) {
    cases++;
    int status=run_case(n,pattern,scalar,legacy,chunks,minimum,rounding,required);
    if (status==1) work_failures++;
    else if (status) {
        semantic_failures++;
        fprintf(stderr,"Semantic failure %d: domain=%d n=%zu pattern=%d scalar=%a legacy=%d chunks=%zu kind=%d rounding=%d\n",
            status,domain_mode,n,pattern,scalar,legacy,chunks,minimum,rounding);
    }
}
int main(int argc,char **argv) {
    (void)argv;
    if (sizeof(float)!=4 || sizeof(double)!=8 || FLT_RADIX!=2 ||
            FLT_MANT_DIG!=24 || DBL_MANT_DIG!=53) return 2;
    puts("domain,length,pattern,scalar,legacy,chunk,minimum,rounding,output,preflight_rows,generic_output_rows,preflight_result_checks,output_result_checks,float_fit_rows,float_loads,preflight_span_rows,output_span_rows,result_missing,semantic_failure,work_failure,reciprocal_proof_rows,reciprocal_fast_rows,reciprocal_exact_rows,reciprocal_fit_rows,reciprocal_threshold_calls,reciprocal_prepare_rows,reciprocal_scratch_bytes,reciprocal_prepared_rows,reciprocal_prepared_divisions,reciprocal_fill_rows,reciprocal_all_missing_rows,canonical_attempt_rows,canonical_committed_rows,whole_write_rows");
    const int modes[]={FE_TONEAREST,FE_DOWNWARD,FE_UPWARD,FE_TOWARDZERO};
    const double scalars[]={0.0,-0.0,1.01,-1.01,0x1.0000000000001p0,
        0x1p-1074,-0x1p-1074,0x1.fffffep126,-0x1.fffffep126,
        0x1p127,-0x1p127,0x1.fffffffffffffp1022,-0x1.fffffffffffffp1022,DBL_MAX,-DBL_MAX};
    for (size_t m=0;m<4;m++) {
        if (!rounding_witness(modes[m],m)) { fprintf(stderr,"Rounding witness failed for mode %zu\n",m); return 2; }
        for (int domain=0;domain<=1;domain++) {
            domain_mode=domain;
            for (int legacy=0;legacy<=1;legacy++) for(int minimum=NUMERIC_FLOAT;minimum<=NUMERIC_DOUBLE;minimum++) {
                record_case(16384,8,1.01,legacy,0,minimum,modes[m],argc>1);
                record_case(16385,8,1.01,legacy,7,minimum,modes[m],argc>1);
                record_case(16385,11,1.01,legacy,0,minimum,modes[m],0);
                record_case(16385,12,1.01,legacy,0,minimum,modes[m],0);
                record_case(1025,9,1.01,legacy,0,minimum,modes[m],0);
                for (size_t s=0;s<sizeof(scalars)/sizeof(*scalars);s++) {
                    record_case(1025,13,scalars[s],legacy,0,minimum,modes[m],0);
                    record_case(1025,14,scalars[s],legacy,0,minimum,modes[m],0);
                }
            }
        }
        domain_mode=0;
        for(int minimum=NUMERIC_FLOAT;minimum<=NUMERIC_DOUBLE;minimum++) {
            record_case(1025,2,1.01,0,0,minimum,modes[m],0);
            record_case(1025,10,1.01,1,0,minimum,modes[m],0);
        }
        const int fact_domains[]={3,5,7,15};
        const int fact_patterns[]={7,8,14,15,16,17};
        const double fact_scalars[]={1.01,-0.0,0x1.fffffffffffffp1022,DBL_MAX};
        for (size_t d=0;d<sizeof(fact_domains)/sizeof(*fact_domains);d++) {
            domain_mode=fact_domains[d];
            for (int minimum=NUMERIC_FLOAT;minimum<=NUMERIC_DOUBLE;minimum++)
                for (size_t chunk=0;chunk<2;chunk++)
                    for (size_t p=0;p<sizeof(fact_patterns)/sizeof(*fact_patterns);p++)
                        for (size_t s=0;s<sizeof(fact_scalars)/sizeof(*fact_scalars);s++)
                            record_case(1025,fact_patterns[p],fact_scalars[s],0,
                                chunk ? 7 : 0,minimum,modes[m],argc>1);
        }
    }
    fesetround(FE_TONEAREST);
    fprintf(stderr,"%s: %zu semantic failures, %zu work failures across %zu cases\n",
        semantic_failures || work_failures ? "FAIL" : "PASS",semantic_failures,work_failures,cases);
    return semantic_failures ? 2 : work_failures ? 1 : 0;
}
