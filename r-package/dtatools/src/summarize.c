#include "dtatools-internal.h"
#include <Rmath.h>

#define SUMMARY_BLOCK 4096

/* Admission observes only settled ordinary environment bindings. In
   particular it must not force na.rm, a delayed S3 method, or an active
   binding while deciding whether the original R dispatch can be omitted. */
static int mean_peek_frame(SEXP env, SEXP symbol, SEXP *value) {
    if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env)) return -1;
    R_BindingType_t kind = R_GetBindingType(symbol, env);
    if (kind == R_BindingTypeUnbound) return 0;
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced) return -1;
    *value = R_getVarEx(symbol, env, FALSE, R_NilValue);
    return 1;
}

static SEXP mean_lookup(SEXP env, SEXP symbol) {
    for (int depth = 0; depth < 32 && env != R_EmptyEnv; depth++) {
        SEXP value = R_NilValue;
        int status = mean_peek_frame(env, symbol, &value);
        if (status != 0) return status == 1 ? value : R_NilValue;
        env = R_ParentEnv(env);
    }
    return R_NilValue;
}

static int summary_flag_known(SEXP frame) {
    SEXP expression = Rf_install("na.rm"), env = frame;
    for (int depth = 0; depth < 64; depth++) {
        if (TYPEOF(expression) != SYMSXP) {
            return TYPEOF(expression) == LGLSXP && !ALTREP(expression) &&
                !Rf_isObject(expression) && !Rf_isS4(expression) &&
                !ANY_ATTRIB(expression) && XLENGTH(expression) == 1 &&
                LOGICAL(expression)[0] != NA_LOGICAL;
        }
        if (TYPEOF(env) != ENVSXP || env == R_EmptyEnv ||
            Rf_isObject(env) || Rf_isS4(env)) return 0;
        R_BindingType_t kind = R_GetBindingType(expression, env);
        if (kind == R_BindingTypeValue || kind == R_BindingTypeForced) {
            expression = R_getVarEx(expression, env, FALSE, R_NilValue);
        } else if (kind == R_BindingTypeDelayed) {
            SEXP next = R_DelayedBindingExpression(expression, env);
            env = R_DelayedBindingEnvironment(expression, env);
            expression = next;
        } else if (kind == R_BindingTypeUnbound) {
            env = R_ParentEnv(env);
        } else return 0;
    }
    return 0;
}

/* One admission reaches the same live closure several times: the base
   environment and the base namespace share bindings, and both method chains
   pass through them. No R code runs between these comparisons, so no binding
   or closure can change, and a closure already found the same as an
   expectation in this call is not walked again. Nothing is kept between
   calls. A builtin is compared by address and needs no record. */
#define ADMISSION_SAME_SLOTS 8

typedef struct {
    SEXP actual[ADMISSION_SAME_SLOTS], expected[ADMISSION_SAME_SLOTS];
    int count;
} admission_same;

static int admission_function_same(admission_same *same, SEXP actual, SEXP expected) {
    for (int i = 0; i < same->count; i++) {
        if (same->actual[i] == actual && same->expected[i] == expected) return 1;
    }
    if (!dtatools_execution_function_same(actual, expected)) return 0;
    if (TYPEOF(actual) == CLOSXP && same->count < ADMISSION_SAME_SLOTS) {
        same->actual[same->count] = actual;
        same->expected[same->count] = expected;
        same->count++;
    }
    return 1;
}

static int mean_method_chain(admission_same *same, SEXP env, SEXP symbol, SEXP expected) {
    for (int depth = 0; depth < 32; depth++) {
        if (env == R_EmptyEnv) return 1;
        SEXP value = R_NilValue;
        int status = mean_peek_frame(env, symbol, &value);
        if (status < 0 || (status == 1 &&
            (expected == R_NilValue ||
             !admission_function_same(same, value, expected)))) return 0;
        env = R_ParentEnv(env);
    }
    return 0;
}

SEXP C_dtatools_mean_admitted(SEXP frame) {
    if (!summary_flag_known(frame)) return Rf_ScalarLogical(FALSE);
    static const char *functions[] = {
        "mean", "mean.default", "isTRUE", "is.numeric", "is.complex",
        "is.logical", "is.na", "length", "!", "[", "&&", "||", "if",
        "{", "<-", ">", "!=", "==", ".Internal", "UseMethod"
    };
    SEXP dependencies = PROTECT(mean_lookup(frame,
        Rf_install(".numeric_mean_dependencies")));
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 20) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    admission_same same = {.count = 0};
    int admitted = 1;
    for (int i = 0; i < 20 && admitted; i++) {
        SEXP symbol = Rf_install(functions[i]);
        SEXP current = mean_lookup(i == 0 ? frame : R_BaseEnv, symbol);
        admitted = admission_function_same(&same, current, VECTOR_ELT(dependencies, i)) &&
            admission_function_same(&same, mean_lookup(R_BaseNamespace, symbol),
                                    VECTOR_ELT(dependencies, i));
    }
    SEXP value = R_NilValue;
    int captured = mean_peek_frame(frame, Rf_install("value"), &value);
    if (captured < 0 || (captured == 1 &&
        (TYPEOF(value) != REALSXP || Rf_isObject(value) || Rf_isS4(value) ||
         Rf_getAttrib(value, R_ClassSymbol) != R_NilValue ||
         Rf_getAttrib(value, R_DimSymbol) != R_NilValue))) admitted = 0;
    SEXP table = mean_lookup(R_BaseNamespace, Rf_install(".__S3MethodsTable__."));
    if (TYPEOF(table) != ENVSXP) admitted = 0;
    static const char *methods[] = {"mean.double", "mean.numeric", "mean.default"};
    for (int i = 0; i < 3 && admitted; i++) {
        SEXP symbol = Rf_install(methods[i]);
        SEXP expected = i == 2 ? VECTOR_ELT(dependencies, 1) : R_NilValue;
        SEXP method = R_NilValue;
        int status = mean_peek_frame(table, symbol, &method);
        admitted = status >= 0 && (status == 0 ||
            (expected != R_NilValue && admission_function_same(&same, method, expected)));
        if (admitted) admitted = mean_method_chain(&same, frame, symbol, expected) &&
            mean_method_chain(&same, R_GlobalEnv, symbol, expected);
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(admitted);
}

SEXP C_dtatools_range_admitted(SEXP frame) {
    if (!summary_flag_known(frame)) return Rf_ScalarLogical(FALSE);
    static const char *functions[] = {
        "range", "range.default", ".rangeNum", "is.numeric", "is.finite",
        "is.na", "c", "min", "max", "!", "[", "if", "{", "<-"
    };
    SEXP dependencies = PROTECT(mean_lookup(frame,
        Rf_install(".numeric_range_dependencies")));
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 14) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    admission_same same = {.count = 0};
    int admitted = 1;
    for (int i = 0; i < 14 && admitted; i++) {
        SEXP symbol = Rf_install(functions[i]);
        admitted = admission_function_same(&same, mean_lookup(R_BaseEnv, symbol),
                                           VECTOR_ELT(dependencies, i)) &&
            admission_function_same(&same, mean_lookup(R_BaseNamespace, symbol),
                                    VECTOR_ELT(dependencies, i));
    }
    SEXP operation = R_NilValue;
    if (mean_peek_frame(frame, Rf_install("operation"), &operation) != 1 ||
        !admission_function_same(&same, operation, VECTOR_ELT(dependencies, 0)))
        admitted = 0;
    SEXP arguments = R_NilValue;
    if (mean_peek_frame(frame, Rf_install("arguments"), &arguments) != 1 ||
        TYPEOF(arguments) != VECSXP || ALTREP(arguments)) admitted = 0;
    if (admitted) for (R_xlen_t i = 0; i < XLENGTH(arguments); i++) {
        SEXP value = VECTOR_ELT(arguments, i);
        if (Rf_isObject(value) || Rf_isS4(value) ||
            Rf_getAttrib(value, R_ClassSymbol) != R_NilValue ||
            Rf_getAttrib(value, R_DimSymbol) != R_NilValue) admitted = 0;
    }
    /* Primitive range on these classless inputs invokes the namespace
       default directly. Its S3 table is not consulted on this route. */
    UNPROTECT(1);
    return Rf_ScalarLogical(admitted);
}

static int summary_scan_supported(SEXP value) {
    while (ALTREP(value) &&
           R_altrep_inherits(value, dtatools_metadata_real_class)) {
        if (R_altrep_data2(value) != R_NilValue) return 1;
        value = metadata_proxy_source(value);
    }
    return !ALTREP(value) || owned_column(value) ||
        R_altrep_inherits(value, dtatools_numeric_class);
}

/* Lets summ() pass a full sample to the moments scan without a copy only
   when the scan reads it directly rather than through the R fallback. */
SEXP C_dtatools_summary_scan_supported(SEXP value) {
    return Rf_ScalarLogical(summary_scan_supported(value));
}

/* A private compact capture outlives callbacks from another reader. Ordinary
   backing is rooted separately before any foreign ALTREP region is read. */
static SEXP summary_reader_capture(
    SEXP value, numeric_reader *reader, numeric_data *storage
) {
    SEXP root = PROTECT(numeric_missing_mask_capture(value, storage));
    if (root != R_NilValue) {
        *reader = (numeric_reader) {value, storage, NULL, NULL, TYPEOF(value)};
    } else {
        UNPROTECT(1);
        root = PROTECT(numeric_payload_root(value));
        *reader = numeric_reader_create(value, XLENGTH(value));
    }
    UNPROTECT(1);
    return root;
}

/* Keep R's ordered extended-precision mean, including its rescaled overflow
   path and correction pass. Missing removal is fused into each read pass. */
SEXP C_dtatools_numeric_mean(SEXP x, SEXP na_rm) {
    if (TYPEOF(x) != REALSXP || !summary_scan_supported(x)) return R_NilValue;
    int remove = Rf_asLogical(na_rm);
    numeric_reader reader;
    numeric_data storage;
    PROTECT(summary_reader_capture(x, &reader, &storage));
    R_xlen_t length = XLENGTH(x), count = 0;
    long double sum = 0.0;
    int missing = 0;
    double values[SUMMARY_BLOCK];
    int codes[SUMMARY_BLOCK];
    for (R_xlen_t start = 0; start < length; ) {
        R_CheckUserInterrupt();
        R_xlen_t size = length - start < SUMMARY_BLOCK
            ? length - start : SUMMARY_BLOCK;
        numeric_reader_region(&reader, start, size, values, codes);
        for (R_xlen_t i = 0; i < size; i++) {
            if (codes[i] >= 0) { missing = 1; continue; }
            count++;
            sum += values[i];
        }
        start += size;
    }
    if ((!remove && missing) || count == 0) {
        UNPROTECT(1);
        return Rf_ScalarReal(count == 0 && (remove || !missing) ? R_NaN : NA_REAL);
    }
    int finite_sum = R_FINITE((double) sum);
    if (finite_sum) {
        sum /= count;
    } else {
        sum = 0.0;
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t size = length - start < SUMMARY_BLOCK
                ? length - start : SUMMARY_BLOCK;
            numeric_reader_region(&reader, start, size, values, codes);
            for (R_xlen_t i = 0; i < size; i++)
                if (codes[i] < 0) sum += values[i] / count;
            start += size;
        }
    }
    if (R_FINITE((double) sum)) {
        long double correction = 0.0;
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t size = length - start < SUMMARY_BLOCK
                ? length - start : SUMMARY_BLOCK;
            numeric_reader_region(&reader, start, size, values, codes);
            for (R_xlen_t i = 0; i < size; i++) {
                if (codes[i] >= 0) continue;
                long double residual = values[i] - sum;
                correction += finite_sum ? residual : residual / count;
            }
            start += size;
        }
        sum += finite_sum ? correction / count : correction;
    }
    UNPROTECT(1);
    return Rf_ScalarReal((double) sum);
}

SEXP C_dtatools_numeric_range(SEXP inputs, SEXP na_rm) {
    if (TYPEOF(inputs) != VECSXP) return R_NilValue;
    R_xlen_t count = XLENGTH(inputs);
    for (R_xlen_t i = 0; i < count; i++) {
        int type = TYPEOF(VECTOR_ELT(inputs, i));
        if (type != REALSXP && type != INTSXP && type != LGLSXP &&
            type != NILSXP) return R_NilValue;
        if (!summary_scan_supported(VECTOR_ELT(inputs, i))) return R_NilValue;
    }
    int nonempty = 0;
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP input = VECTOR_ELT(inputs, i);
        if (input != R_NilValue) nonempty |= XLENGTH(input) != 0;
    }
    if (!nonempty) return R_NilValue;
    SEXP roots = PROTECT(Rf_allocVector(VECSXP, count));
    numeric_reader *readers = (numeric_reader *) R_alloc(count, sizeof(numeric_reader));
    numeric_data *storage = (numeric_data *) R_alloc(count, sizeof(numeric_data));
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP input = VECTOR_ELT(inputs, i);
        if (input != R_NilValue)
            SET_VECTOR_ELT(roots, i,
                summary_reader_capture(input, readers + i, storage + i));
    }
    int remove = Rf_asLogical(na_rm), missing = 0;
    double minimum = R_PosInf, maximum = R_NegInf;
    double values[SUMMARY_BLOCK];
    int codes[SUMMARY_BLOCK];
    for (R_xlen_t input = 0; input < count; input++) {
        if (VECTOR_ELT(inputs, input) == R_NilValue) continue;
        R_xlen_t length = XLENGTH(VECTOR_ELT(inputs, input));
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t size = length - start < SUMMARY_BLOCK
                ? length - start : SUMMARY_BLOCK;
            numeric_reader_region(readers + input, start, size, values, codes);
            for (R_xlen_t i = 0; i < size; i++) {
                if (codes[i] >= 0) { missing = 1; continue; }
                if (values[i] < minimum) minimum = values[i];
                if (values[i] > maximum) maximum = values[i];
            }
            start += size;
        }
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 2));
    REAL(result)[0] = !remove && missing ? NA_REAL : minimum;
    REAL(result)[1] = !remove && missing ? NA_REAL : maximum;
    UNPROTECT(2);
    return result;
}

typedef struct {
    double sum;
    double correction;
    int stopped;
} summary_accumulator;

static void summary_accumulate(summary_accumulator *state, double value) {
    if (state->stopped) return;
    double next = state->sum + value;
    if (!R_FINITE(next)) {
        state->sum = next;
        state->correction = 0;
        state->stopped = 1;
        return;
    }
    state->correction += fabs(state->sum) >= fabs(value)
        ? (state->sum - next) + value : (value - next) + state->sum;
    state->sum = next;
}

static double summary_total(const summary_accumulator *state) {
    return state->sum + state->correction;
}

/* Return count, weight total, weighted sum, extrema, and centered moment
   totals. R retains weight policy, percentile selection and result assembly. */
SEXP C_dtatools_summarize_moments(
    SEXP x, SEXP weights, SEXP detail, SEXP meanonly
) {
    if (!summary_scan_supported(x) || !summary_scan_supported(weights))
        return R_NilValue;
    R_xlen_t length = XLENGTH(x);
    if (XLENGTH(weights) != length)
        Rf_error("summary weights must match the value count");
    numeric_reader x_reader, w_reader;
    numeric_data x_storage, w_storage;
    PROTECT(summary_reader_capture(x, &x_reader, &x_storage));
    PROTECT(summary_reader_capture(weights, &w_reader, &w_storage));
    summary_accumulator total = {0}, sum = {0};
    double count = 0, minimum = R_PosInf, maximum = R_NegInf;
    double values[SUMMARY_BLOCK], w[SUMMARY_BLOCK];
    int codes[SUMMARY_BLOCK], w_codes[SUMMARY_BLOCK];
    for (R_xlen_t start = 0; start < length; ) {
        R_CheckUserInterrupt();
        R_xlen_t size = length - start < SUMMARY_BLOCK
            ? length - start : SUMMARY_BLOCK;
        numeric_reader_region(&x_reader, start, size, values, codes);
        numeric_reader_region(&w_reader, start, size, w, w_codes);
        for (R_xlen_t i = 0; i < size; i++) {
            if (codes[i] < 0 && !R_FINITE(values[i]))
                Rf_errorcall(R_NilValue, "summary inputs must be finite or missing");
            if (codes[i] >= 0 || w_codes[i] >= 0 || w[i] == 0) continue;
            count++;
            summary_accumulate(&total, w[i]);
            summary_accumulate(&sum, w[i] * values[i]);
            if (values[i] < minimum) minimum = values[i];
            if (values[i] > maximum) maximum = values[i];
        }
        start += size;
    }
    double total_value = summary_total(&total), sum_value = summary_total(&sum);
    double mean = sum_value / total_value;
    summary_accumulator m2 = {0}, m3 = {0}, m4 = {0};
    int detailed = Rf_asLogical(detail);
    if (count && total_value != 0 && R_FINITE(mean) &&
        !Rf_asLogical(meanonly)) {
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t size = length - start < SUMMARY_BLOCK
                ? length - start : SUMMARY_BLOCK;
            numeric_reader_region(&x_reader, start, size, values, codes);
            numeric_reader_region(&w_reader, start, size, w, w_codes);
            for (R_xlen_t i = 0; i < size; i++) {
                if (codes[i] >= 0 || w_codes[i] >= 0 || w[i] == 0) continue;
                double centered = values[i] - mean;
                double square = centered * centered;
                summary_accumulate(&m2, w[i] * square);
                if (detailed) {
                    summary_accumulate(&m3, w[i] * R_pow(centered, 3.0));
                    summary_accumulate(&m4, w[i] * R_pow(centered, 4.0));
                }
            }
            start += size;
        }
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 8));
    double *out = REAL(result);
    out[0] = count;
    out[1] = total_value;
    out[2] = sum_value;
    out[3] = minimum;
    out[4] = maximum;
    out[5] = summary_total(&m2);
    out[6] = summary_total(&m3);
    out[7] = summary_total(&m4);
    UNPROTECT(3);
    return result;
}

/* Compensated accumulation is needed even on platforms where long double
   has double precision. In particular, 1e16 + 1 - 1e16 must retain the 1. */
SEXP C_dtatools_summarize_sum(SEXP x) {
    if (TYPEOF(x) != REALSXP) Rf_error("Expected a double summary vector");
    double sum = 0.0, correction = 0.0;
    R_xlen_t n = XLENGTH(x);
    for (R_xlen_t i = 0; i < n; ++i) {
        if (i % 65536 == 0) R_CheckUserInterrupt();
        double value = REAL_ELT(x, i);
        double next = sum + value;
        if (!R_FINITE(next)) return Rf_ScalarReal(next);
        correction += fabs(sum) >= fabs(value)
            ? (sum - next) + value : (value - next) + sum;
        sum = next;
    }
    return Rf_ScalarReal(sum + correction);
}
