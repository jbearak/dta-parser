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

/* The admissions run once or twice per call of mean() or range(), often
   once per group. Installing a name hashes it and searches the symbol
   table, so each name is installed once. Symbols are never collected. */
static SEXP summary_symbol(SEXP *slot, const char *name) {
    if (*slot == NULL) *slot = Rf_install(name);
    return *slot;
}

static int summary_flag_known(SEXP frame) {
    static SEXP na_rm = NULL;
    SEXP expression = summary_symbol(&na_rm, "na.rm"), env = frame;
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
   environment and the base namespace share bindings, and each method chain
   passes through them. No R code runs between these comparisons, so no binding
   or closure can change, and a closure already found the same as an
   expectation in this call is not walked again. Across calls, the
   comparator's own proof memo skips the walk. A builtin is compared by
   address and needs no record. */
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

/* Sets *global when the walk passes the global environment, whose own walk
   would then repeat this one's tail. */
static int mean_method_chain(admission_same *same, SEXP env, SEXP symbol, SEXP expected,
                             int *global) {
    for (int depth = 0; depth < 32; depth++) {
        if (env == R_EmptyEnv) return 1;
        if (env == R_GlobalEnv) *global = 1;
        SEXP value = R_NilValue;
        int status = mean_peek_frame(env, symbol, &value);
        if (status < 0 || (status == 1 &&
            (expected == R_NilValue ||
             !admission_function_same(same, value, expected)))) return 0;
        env = R_ParentEnv(env);
    }
    return 0;
}

/* Whether mean(value, na.rm = na.rm) in frame reaches the frozen generic
   and mean.default(), with na.rm settled. With helpers, every base function
   mean.default() calls must be unchanged too, and a captured value must be
   a bare double. The compact mean in C_dtatools_mean_computed() checks the
   generic and the methods only (ADR 0057). */
static int mean_admission(SEXP frame, int helpers) {
    if (!summary_flag_known(frame)) return 0;
    static const char *functions[] = {
        "mean", "mean.default", "isTRUE", "is.numeric", "is.complex",
        "is.logical", "is.na", "length", "!", "[", "&&", "||", "if",
        "{", "<-", ">", "!=", "==", ".Internal", "UseMethod"
    };
    static SEXP symbols[20], dependency_symbol, value_symbol, table_symbol, method_symbols[3];
    SEXP dependencies = PROTECT(mean_lookup(frame,
        summary_symbol(&dependency_symbol, ".numeric_mean_dependencies")));
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 20) {
        UNPROTECT(1);
        return 0;
    }
    admission_same same = {.count = 0};
    int admitted = 1;
    for (int i = 0; i < (helpers ? 20 : 1) && admitted; i++) {
        SEXP symbol = summary_symbol(&symbols[i], functions[i]);
        SEXP current = mean_lookup(i == 0 ? frame : R_BaseEnv, symbol);
        admitted = admission_function_same(&same, current, VECTOR_ELT(dependencies, i)) &&
            admission_function_same(&same, mean_lookup(R_BaseNamespace, symbol),
                                    VECTOR_ELT(dependencies, i));
    }
    SEXP value = R_NilValue;
    int captured = helpers ?
        mean_peek_frame(frame, summary_symbol(&value_symbol, "value"), &value) : 0;
    if (captured < 0 || (captured == 1 &&
        (TYPEOF(value) != REALSXP || Rf_isObject(value) || Rf_isS4(value) ||
         Rf_getAttrib(value, R_ClassSymbol) != R_NilValue ||
         Rf_getAttrib(value, R_DimSymbol) != R_NilValue))) admitted = 0;
    SEXP table = mean_lookup(R_BaseNamespace,
        summary_symbol(&table_symbol, ".__S3MethodsTable__."));
    if (TYPEOF(table) != ENVSXP) admitted = 0;
    static const char *methods[] = {"mean.double", "mean.numeric", "mean.default"};
    for (int i = 0; i < 3 && admitted; i++) {
        SEXP symbol = summary_symbol(&method_symbols[i], methods[i]);
        SEXP expected = i == 2 ? VECTOR_ELT(dependencies, 1) : R_NilValue;
        SEXP method = R_NilValue;
        int status = mean_peek_frame(table, symbol, &method);
        admitted = status >= 0 && (status == 0 ||
            (expected != R_NilValue && admission_function_same(&same, method, expected)));
        int global = 0;
        if (admitted) admitted = mean_method_chain(&same, frame, symbol, expected, &global) &&
            (global || mean_method_chain(&same, R_GlobalEnv, symbol, expected, &global));
    }
    UNPROTECT(1);
    return admitted;
}

SEXP C_dtatools_mean_admitted(SEXP frame) {
    return Rf_ScalarLogical(mean_admission(frame, 1));
}

SEXP C_dtatools_range_admitted(SEXP frame) {
    if (!summary_flag_known(frame)) return Rf_ScalarLogical(FALSE);
    static const char *functions[] = {
        "range", "range.default", ".rangeNum", "is.numeric", "is.finite",
        "is.na", "c", "min", "max", "!", "[", "if", "{", "<-"
    };
    static SEXP symbols[14], dependency_symbol, operation_symbol, arguments_symbol;
    SEXP dependencies = PROTECT(mean_lookup(frame,
        summary_symbol(&dependency_symbol, ".numeric_range_dependencies")));
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 14) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    admission_same same = {.count = 0};
    int admitted = 1;
    for (int i = 0; i < 14 && admitted; i++) {
        SEXP symbol = summary_symbol(&symbols[i], functions[i]);
        admitted = admission_function_same(&same, mean_lookup(R_BaseEnv, symbol),
                                           VECTOR_ELT(dependencies, i)) &&
            admission_function_same(&same, mean_lookup(R_BaseNamespace, symbol),
                                    VECTOR_ELT(dependencies, i));
    }
    SEXP operation = R_NilValue;
    if (mean_peek_frame(frame, summary_symbol(&operation_symbol, "operation"),
                        &operation) != 1 ||
        !admission_function_same(&same, operation, VECTOR_ELT(dependencies, 0)))
        admitted = 0;
    SEXP arguments = R_NilValue;
    if (mean_peek_frame(frame, summary_symbol(&arguments_symbol, "arguments"),
                        &arguments) != 1 ||
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
   path and correction pass. Missing removal is fused into each read pass.
   Set *result and return 1, or return 0 for a vector the scan does not
   read. */
static int numeric_mean_value(SEXP x, int remove, double *result) {
    if (TYPEOF(x) != REALSXP || !summary_scan_supported(x)) return 0;
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
        *result = count == 0 && (remove || !missing) ? R_NaN : NA_REAL;
        return 1;
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
    *result = (double) sum;
    return 1;
}

SEXP C_dtatools_numeric_mean(SEXP x, SEXP na_rm) {
    double result;
    return numeric_mean_value(x, Rf_asLogical(na_rm), &result) ?
        Rf_ScalarReal(result) : R_NilValue;
}

/* Forces na.rm, as the R code does, once summary_flag_known() has shown
   that settling it runs no R code. NULL for anything but TRUE or FALSE. */
static SEXP summary_flag(SEXP frame) {
    static SEXP na_rm = NULL;
    SEXP flag = R_getVar(summary_symbol(&na_rm, "na.rm"), frame, TRUE);
    return TYPEOF(flag) == LGLSXP && !ALTREP(flag) && !ANY_ATTRIB(flag) &&
        XLENGTH(flag) == 1 && LOGICAL(flag)[0] != NA_LOGICAL ? flag : NULL;
}

/* `.collapse_missing()` and then `.dta_computed()` at the storage x
   declares, for a fresh scalar. */
static SEXP summary_computed_result(SEXP value, SEXP x) {
    static SEXP storage = NULL;
    if (ISNAN(REAL(value)[0])) REAL(value)[0] = NA_REAL;
    return numeric_computed_small(value,
        Rf_getAttrib(x, summary_symbol(&storage, "stata.storage")));
}

static int summary_class_is(SEXP classes, R_xlen_t i, const char *expected) {
    SEXP name = STRING_ELT(classes, i);
    return name != NA_STRING && strcmp(CHAR(name), expected) == 0;
}

/* The R code's capture calls `names()`, which dispatches on x's class, and
   sets the names it gets on the captured values, which reads their length.
   It runs no R code when x has the classes the package gives a compact
   Stata numeric, with haven_labelled when it carries value labels, and
   names that are not ALTREP. A subclass can define a `names()` method, and
   an ALTREP class or names vector runs its provider's code, either of which
   could change what the R code does next, so the calls decline them. */
static int summary_capture_inert(SEXP x) {
    static const char *storages[] = {"dta_byte", "dta_int", "dta_long", "dta_float"};
    SEXP classes = Rf_getAttrib(x, R_ClassSymbol);
    R_xlen_t count = TYPEOF(classes) == STRSXP && !ALTREP(classes) ? XLENGTH(classes) : 0;
    if ((count != 4 && count != 5) || !summary_class_is(classes, 0, "dta_numeric") ||
        (count == 5 && !summary_class_is(classes, 2, "haven_labelled")) ||
        !summary_class_is(classes, count - 2, "vctrs_vctr") ||
        !summary_class_is(classes, count - 1, "double") ||
        ALTREP(Rf_getAttrib(x, R_NamesSymbol))) return 0;
    for (int i = 0; i < 4; i++) if (summary_class_is(classes, 1, storages[i])) return 1;
    return 0;
}

/* x is a vector the compact mean reads: a compact Stata numeric, read
   directly or through metadata proxies, that summary_capture_inert() holds
   for. */
static int mean_chunk_supported(SEXP x) {
    return TYPEOF(x) == REALSXP && numeric_base_source(x) != R_NilValue &&
        summary_capture_inert(x);
}

/* The compact mean of such an x for a settled flag: the mean, then
   `.collapse_missing()` and `.dta_computed()`. R_NilValue where the R code
   computes it. */
static SEXP mean_chunk(SEXP x, SEXP flag) {
    SEXP value = PROTECT(C_dtatools_numeric_mean(x, flag));
    SEXP result = value == R_NilValue ? R_NilValue : summary_computed_result(value, x);
    UNPROTECT(1);
    return result;
}

/* mean() of a compact Stata numeric, read directly or through metadata
   proxies. It gives what mean.dta_numeric() builds from its capture: the
   mean, then `.collapse_missing()` and `.dta_computed()`. It admits the call
   when the mean generic and methods are the frozen ones, without the base
   functions mean.default() calls (ADR 0057). Capturing such a vector runs
   no R code, so the admission the R code repeats after its capture would
   still hold. It reads x from the frame and declines while x is a promise,
   as in a direct call of the method, since forcing x could change what the
   admission saw, and unless summary_capture_inert() holds. R_NilValue
   leaves the call to the R code (ADR 0054). */
SEXP C_dtatools_mean_computed(SEXP frame) {
    static SEXP x_symbol = NULL;
    SEXP x = R_NilValue;
    if (mean_peek_frame(frame, summary_symbol(&x_symbol, "x"), &x) != 1 ||
        !mean_chunk_supported(x) || !mean_admission(frame, 0)) return R_NilValue;
    SEXP flag = summary_flag(frame);
    if (flag == NULL) return R_NilValue;
    return mean_chunk(x, flag);
}

/* 0, 1 or 2 for "sum", "min" or "max", and -1 for anything else. */
static int summary_operation(SEXP generic) {
    if (TYPEOF(generic) != STRSXP || ALTREP(generic) || ANY_ATTRIB(generic) ||
        XLENGTH(generic) != 1) return -1;
    const char *name = CHAR(STRING_ELT(generic, 0));
    return strcmp(name, "sum") == 0 ? 0 : strcmp(name, "min") == 0 ? 1 :
        strcmp(name, "max") == 0 ? 2 : -1;
}

/* x is a vector whose min(), max() or sum() the kernel reads: a compact
   Stata numeric that is not a metadata proxy and that
   summary_capture_inert() holds for. */
static int summary_chunk_supported(SEXP x) {
    return TYPEOF(x) == REALSXP && ALTREP(x) &&
        R_altrep_inherits(x, dtatools_numeric_class) && R_altrep_data2(x) == R_NilValue &&
        summary_capture_inert(x);
}

/* The kernel's result for such an x, then `.collapse_missing()` and
   `.dta_computed()`. R_NilValue for an empty vector and for one with no
   observed value under na.rm, which the R code computes. */
static SEXP summary_chunk(SEXP x, int operation, Rboolean remove) {
    SEXP value = operation == 0 ? numeric_sum(x, remove) :
        operation == 1 ? numeric_min(x, remove) : numeric_max(x, remove);
    if (value == NULL) return R_NilValue;
    PROTECT(value);
    SEXP result = summary_computed_result(value, x);
    UNPROTECT(1);
    return result;
}

/* min(), max() or sum() of one compact Stata numeric. The R code captures x
   in a metadata view, and the primitive calls the view's ALTREP method,
   which reads x with the kernel called here. The result then takes
   `.collapse_missing()` and `.dta_computed()`. R_NilValue leaves the call to
   the R code: for a metadata proxy, whose view the method reads another
   way, unless summary_capture_inert() holds, for an empty vector, whose min()
   and max() warn, and for a vector with no observed value under na.rm
   (ADR 0054). */
SEXP C_dtatools_summary_computed(SEXP x, SEXP generic, SEXP frame) {
    int operation = summary_operation(generic);
    if (operation < 0 || !summary_chunk_supported(x) || !summary_flag_known(frame))
        return R_NilValue;
    SEXP flag = summary_flag(frame);
    if (flag == NULL) return R_NilValue;
    return summary_chunk(x, operation, (Rboolean) LOGICAL(flag)[0]);
}

/* Walks from env to stop, inclusive, as R looks up a function: the first
   binding that holds a function ends the walk and sets *found, and a binding
   that holds anything else is passed over. *found stays R_NilValue when no
   binding holds one. Returns 0 when the lookup would run R code, for a
   promise or an active binding, or signal an error, for a missing argument
   where a function call looks for its function. */
static int plan_walk(SEXP env, SEXP stop, SEXP symbol, int call, SEXP *found) {
    *found = R_NilValue;
    for (int depth = 0; depth < 128; depth++) {
        if (env == R_EmptyEnv) return stop == R_EmptyEnv;
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env)) return 0;
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if (kind == R_BindingTypeValue || kind == R_BindingTypeForced) {
            SEXP value = R_getVarEx(symbol, env, FALSE, R_NilValue);
            if (call && value == R_MissingArg) return 0;
            if (Rf_isFunction(value)) {
                *found = value;
                return 1;
            }
        } else if (kind != R_BindingTypeUnbound) return 0;
        if (env == stop) return 1;
        env = R_ParentEnv(env);
    }
    return 0;
}

/* The method R_LookupMethod() finds for a call from env, whose topenv() is
   top: a function bound from env through top, else the base S3 table's
   entry, else a function bound after top. Past top this walks every
   environment to the empty one, which covers both orders R can search them
   in, so a function found there can only mean the plan declines. */
static int plan_method(SEXP env, SEXP top, SEXP table, SEXP symbol, SEXP *found) {
    if (!plan_walk(env, top, symbol, 0, found)) return 0;
    if (*found != R_NilValue) return 1;
    R_BindingType_t kind = R_GetBindingType(symbol, table);
    if (kind == R_BindingTypeValue || kind == R_BindingTypeForced) {
        *found = R_getVarEx(symbol, table, FALSE, R_NilValue);
        return 1;
    }
    if (kind != R_BindingTypeUnbound) return 0;
    return plan_walk(R_ParentEnv(top), R_EmptyEnv, symbol, 0, found);
}

/* Whether every group's evaluation of `generic(column)`, with na.rm as frame
   binds it, would end in the package method's native result, with no R
   code on the way (ADR 0061). The generic found from env must be base's, as
   the frozen copies have it: the closure for mean, and for the others the
   primitive their name gave when the package was built. Dispatch on a
   chunk's first class must find the frozen mean.dta_numeric(), or, for the
   Summary group, no method for the generic itself and then the frozen
   Summary.dta_numeric(). The mean method then makes the admission its
   native call makes. found[0] and found[1] get the generic and the method,
   whose debugging the caller checks. */
static int summary_plan_admission(SEXP generic, SEXP env, SEXP top, SEXP frame, SEXP *found) {
    static SEXP dependency_symbol, mean_dependency_symbol, table_symbol;
    int operation = summary_operation(generic), mean = 0;
    if (operation < 0) {
        if (TYPEOF(generic) != STRSXP || ALTREP(generic) || ANY_ATTRIB(generic) ||
            XLENGTH(generic) != 1 || strcmp(CHAR(STRING_ELT(generic, 0)), "mean") != 0)
            return 0;
        mean = 1;
    }
    if (TYPEOF(env) != ENVSXP || TYPEOF(top) != ENVSXP || !summary_flag_known(frame)) return 0;
    SEXP dependencies = PROTECT(mean_lookup(frame,
        summary_symbol(&dependency_symbol, ".summary_plan_dependencies")));
    SEXP mean_dependencies = PROTECT(mean_lookup(frame,
        summary_symbol(&mean_dependency_symbol, ".numeric_mean_dependencies")));
    SEXP table = mean_lookup(R_BaseNamespace,
        summary_symbol(&table_symbol, ".__S3MethodsTable__."));
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 5 ||
        TYPEOF(mean_dependencies) != VECSXP || ALTREP(mean_dependencies) ||
        XLENGTH(mean_dependencies) < 1 || TYPEOF(table) != ENVSXP) {
        UNPROTECT(2);
        return 0;
    }
    SEXP symbol = Rf_installChar(STRING_ELT(generic, 0));
    SEXP expected = mean ? VECTOR_ELT(mean_dependencies, 0) :
        VECTOR_ELT(dependencies, 2 + operation);
    admission_same same = {.count = 0};
    int admitted = (mean || TYPEOF(expected) == BUILTINSXP) &&
        plan_walk(env, R_EmptyEnv, symbol, 1, &found[0]) &&
        found[0] != R_NilValue && admission_function_same(&same, found[0], expected);
    char name[32];
    if (admitted && !mean) {
        snprintf(name, sizeof(name), "%s.dta_numeric", CHAR(STRING_ELT(generic, 0)));
        SEXP own = R_NilValue;
        admitted = plan_method(env, top, table, Rf_install(name), &own) && own == R_NilValue;
    }
    if (admitted) {
        found[1] = R_NilValue;
        admitted = plan_method(env, top, table,
            Rf_install(mean ? "mean.dta_numeric" : "Summary.dta_numeric"), &found[1]) &&
            found[1] != R_NilValue &&
            admission_function_same(&same, found[1], VECTOR_ELT(dependencies, mean ? 0 : 1));
    }
    if (admitted && mean) admitted = mean_admission(frame, 0);
    UNPROTECT(2);
    return admitted;
}

/* The generic and method a planned summary would call, for the caller to
   check before it reads the column, or NULL when summary_plan_admission()
   declines. */
SEXP C_dtatools_summary_plan_admitted(SEXP generic, SEXP env, SEXP top, SEXP frame) {
    SEXP found[2] = {R_NilValue, R_NilValue};
    if (!summary_plan_admission(generic, env, top, frame, found)) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(result, 0, found[0]);
    SET_VECTOR_ELT(result, 1, found[1]);
    UNPROTECT(1);
    return result;
}

/* `generic(column)` for every group of a grouped summary after the first,
   which the loop has evaluated, at once (ADR 0061). For each of the
   column's later group chunks it computes what the method's native call
   returns, then the size and the capture the group loop takes:
   C_dtatools_chunk_size() and `.capture_dibble_nested()`, which for these
   results is C_dtatools_capture_atomic(). It repeats the admission, since
   the caller's checks run R code, and returns list(chunks, known) for the
   later groups as the loop builds them, or NULL, with nothing computed
   that the loop would not also compute, when the admission declines or any
   chunk would leave its group to the R code. */
/* What a later chunk's result reads back as and its compact storage, as
   mean_chunk() or summary_chunk() would build it, or -1 where it would be a
   double vector, or -2 where those calls, and so the plan, decline. */
static int plan_chunk_value(SEXP x, int operation, Rboolean remove, double *decoded) {
    static SEXP storage = NULL;
    double value;
    int computed = operation < 0 ?
        mean_chunk_supported(x) && numeric_mean_value(x, remove, &value) :
        summary_chunk_supported(x) && (operation == 0 ?
            numeric_sum_value(x, remove, &value) :
            numeric_extreme_value(x, remove, operation == 1, &value));
    if (!computed) return -2;
    /* `.collapse_missing()` */
    if (ISNAN(value)) value = NA_REAL;
    return computed_scalar_compact(value,
        computed_storage_kind_of(Rf_getAttrib(x, summary_symbol(&storage, "stata.storage"))),
        decoded);
}

/* The combined vector of a summary's results when the first group's result
   and every later one is compact (ADR 0062), or R_NilValue, with nothing
   built, when one is not or summary_planned_combine() declines. Its checks
   that read no later result come first, so a decline there computes none.
   *declined is set when a later chunk's call declines, so the whole plan
   does. */
static SEXP plan_combined(SEXP chunks, int operation, Rboolean remove, SEXP first,
                          SEXP caller, SEXP states, int *declined) {
    R_xlen_t count = XLENGTH(chunks);
    if (!summary_planned_combine_admitted(caller, first, count, states)) return R_NilValue;
    SEXP values = PROTECT(Rf_allocVector(REALSXP, count));
    unsigned kinds = 0;
    for (R_xlen_t i = 1; i < count; i++) {
        if (i % 4096 == 4095) R_CheckUserInterrupt();
        int kind = plan_chunk_value(VECTOR_ELT(chunks, i), operation, remove, REAL(values) + i);
        if (kind < 0) {
            *declined = kind == -2;
            UNPROTECT(1);
            return R_NilValue;
        }
        kinds |= 1U << kind;
    }
    SEXP result = summary_planned_combine(caller, first, values, kinds, states);
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_summary_plan(SEXP chunks, SEXP generic, SEXP env, SEXP top, SEXP frame,
                             SEXP first, SEXP caller, SEXP states) {
    SEXP found[2] = {R_NilValue, R_NilValue};
    if (TYPEOF(chunks) != VECSXP || ALTREP(chunks) ||
        !summary_plan_admission(generic, env, top, frame, found)) return R_NilValue;
    int operation = summary_operation(generic);
    SEXP flag = summary_flag(frame);
    if (flag == NULL) return R_NilValue;
    PROTECT(flag);
    Rboolean remove = (Rboolean) LOGICAL(flag)[0];
    R_xlen_t count = XLENGTH(chunks) - 1;
    if (count < 1) {
        UNPROTECT(1);
        return R_NilValue;
    }
    if (first != R_NilValue) {
        int declined = 0;
        SEXP combined = PROTECT(plan_combined(chunks, operation, remove, first, caller,
                                              states, &declined));
        if (declined || combined != R_NilValue) {
            SEXP result = R_NilValue;
            if (!declined) {
                result = PROTECT(Rf_allocVector(VECSXP, 1));
                SET_VECTOR_ELT(result, 0, combined);
                Rf_setAttrib(result, R_NamesSymbol, Rf_mkString("result"));
                UNPROTECT(1);
            }
            UNPROTECT(2);
            return result;
        }
        UNPROTECT(1);
    }
    SEXP results = PROTECT(Rf_allocVector(VECSXP, count));
    SEXP known = PROTECT(Rf_allocVector(INTSXP, count));
    for (R_xlen_t i = 0; i < count; i++) {
        if (i % 4096 == 4095) R_CheckUserInterrupt();
        SEXP x = VECTOR_ELT(chunks, i + 1);
        SEXP value = R_NilValue;
        /* An S4 object's methods dispatch before the S3 method the plan
           stands in for. */
        if (!Rf_isS4(x) && (operation < 0 ? mean_chunk_supported(x) :
                            summary_chunk_supported(x)))
            value = operation < 0 ? mean_chunk(x, flag) : summary_chunk(x, operation, remove);
        if (value == R_NilValue) {
            UNPROTECT(3);
            return R_NilValue;
        }
        PROTECT(value);
        SEXP size = C_dtatools_chunk_size(value);
        if (size != R_NilValue) INTEGER(known)[i] = INTEGER(size)[0];
        SEXP captured = size == R_NilValue ? R_NilValue : C_dtatools_capture_atomic(value);
        if (captured == R_NilValue) {
            UNPROTECT(4);
            return R_NilValue;
        }
        SET_VECTOR_ELT(results, i, captured);
        UNPROTECT(1);
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(names, 0, Rf_mkChar("chunks"));
    SET_STRING_ELT(names, 1, Rf_mkChar("known"));
    SET_VECTOR_ELT(result, 0, results);
    SET_VECTOR_ELT(result, 1, known);
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(5);
    return result;
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

/* An unweighted summ() passes weights of exactly 1. Each such weight adds 1
   to the compensated total, which therefore stays the exact count, and
   multiplying a value or a moment term by it changes nothing, so the scans
   need not read the weights at all. */
static int summary_unit_weights(SEXP weights) {
    if (TYPEOF(weights) != REALSXP || ALTREP(weights)) return 0;
    const double *w = REAL(weights);
    R_xlen_t length = XLENGTH(weights);
    /* Each block is checked whole, so the compiler can vectorize it. */
    for (R_xlen_t start = 0; start < length; start += SUMMARY_BLOCK) {
        R_xlen_t end = length - start < SUMMARY_BLOCK
            ? length : start + SUMMARY_BLOCK;
        int other = 0;
        for (R_xlen_t i = start; i < end; i++) other |= w[i] != 1.0;
        if (other) return 0;
    }
    return 1;
}

/* Byte, int and long storage holds integers, and a raw value at or above
   the storage's first missing code is missing. When the row count times
   the largest magnitude the storage holds is at most 2^53, every partial
   sum of observed values is an integer a double holds exactly. Each
   compensated step is then exact and the total is the integer sum, so
   under unit weights the first pass sums in integers. Both passes read
   the raw storage rather than decoding blocks of doubles and codes. */
typedef struct {
    int moments;
    int detailed;
    double mean;
    int64_t count, sum, minimum, maximum;
    summary_accumulator m2, m3, m4;
} summary_integer_scan;

#define SUMMARY_INTEGER_ROWS(TYPE, LIMIT)                                    \
    do {                                                                    \
        const unsigned char *bytes = span->values;                           \
        TYPE limit = (LIMIT);                                                \
        for (size_t begin = 0; begin < span->length; ) {                     \
            size_t size = span->length - begin;                             \
            if (size > 65536) size = 65536;                                 \
            R_CheckUserInterrupt();                                         \
            if (!scan->moments) {                                           \
                int64_t count = 0, sum = 0;                                 \
                int64_t minimum = scan->minimum, maximum = scan->maximum;   \
                for (size_t i = begin; i < begin + size; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    int64_t value = raw;                                    \
                    int observed = raw < limit;                             \
                    count += observed;                                      \
                    sum += observed ? value : 0;                            \
                    minimum = observed && value < minimum ? value : minimum;\
                    maximum = observed && value > maximum ? value : maximum;\
                }                                                           \
                scan->count += count;                                       \
                scan->sum += sum;                                           \
                scan->minimum = minimum;                                    \
                scan->maximum = maximum;                                    \
            } else {                                                        \
                double mean = scan->mean;                                   \
                int detailed = scan->detailed;                              \
                summary_accumulator m2 = scan->m2, m3 = scan->m3;           \
                summary_accumulator m4 = scan->m4;                          \
                for (size_t i = begin; i < begin + size; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    if (raw >= limit) continue;                             \
                    double centered = (double) raw - mean;                  \
                    summary_accumulate(&m2, centered * centered);           \
                    if (detailed) {                                         \
                        summary_accumulate(&m3, R_pow(centered, 3.0));      \
                        summary_accumulate(&m4, R_pow(centered, 4.0));      \
                    }                                                       \
                }                                                           \
                scan->m2 = m2;                                              \
                scan->m3 = m3;                                              \
                scan->m4 = m4;                                              \
            }                                                               \
            begin += size;                                                  \
        }                                                                   \
    } while (0)

static void summary_integer_span(
    const numeric_data *span, size_t offset, void *context
) {
    (void) offset;
    summary_integer_scan *scan = context;
    int legacy = span->format_version <= 111;
    switch (span->kind) {
    case NUMERIC_BYTE:
        SUMMARY_INTEGER_ROWS(int8_t, legacy ? 127 : 101);
        break;
    case NUMERIC_INT:
        SUMMARY_INTEGER_ROWS(int16_t, legacy ? 32767 : 32741);
        break;
    default:
        SUMMARY_INTEGER_ROWS(int32_t,
            legacy ? INT32_MAX : INT32_C(2147483621));
        break;
    }
}
#undef SUMMARY_INTEGER_ROWS

static int summary_integer_storage(
    const numeric_data *storage, R_xlen_t length
) {
    if (storage == NULL || storage->temporal != 0) return 0;
    double magnitude = storage->kind == NUMERIC_BYTE ? 128.0
        : storage->kind == NUMERIC_INT ? 32768.0
        : storage->kind == NUMERIC_LONG ? 2147483648.0 : 0.0;
    return magnitude != 0.0 &&
        (double) length * magnitude <= 9007199254740992.0;
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
    int unit = summary_unit_weights(weights);
    numeric_reader x_reader, w_reader;
    numeric_data x_storage, w_storage;
    PROTECT(summary_reader_capture(x, &x_reader, &x_storage));
    PROTECT(summary_reader_capture(weights, &w_reader, &w_storage));
    summary_accumulator total = {0}, sum = {0};
    double count = 0, minimum = R_PosInf, maximum = R_NegInf;
    double values[SUMMARY_BLOCK], w[SUMMARY_BLOCK];
    int codes[SUMMARY_BLOCK], w_codes[SUMMARY_BLOCK];
    int detailed = Rf_asLogical(detail);
    int integer = unit && summary_integer_storage(x_reader.storage, length);
    summary_integer_scan scan = {
        0, detailed, 0, 0, 0, INT64_MAX, INT64_MIN, {0}, {0}, {0}
    };
    if (integer) {
        numeric_for_each_span(x_reader.storage, 0, (size_t) length,
                              summary_integer_span, &scan);
        count = (double) scan.count;
        sum.sum = (double) scan.sum;
        if (scan.count) {
            minimum = (double) scan.minimum;
            maximum = (double) scan.maximum;
        }
    }
    for (R_xlen_t start = integer ? length : 0; start < length; ) {
        R_CheckUserInterrupt();
        R_xlen_t size = length - start < SUMMARY_BLOCK
            ? length - start : SUMMARY_BLOCK;
        numeric_reader_region(&x_reader, start, size, values, codes);
        if (unit) {
            for (R_xlen_t i = 0; i < size; i++) {
                if (codes[i] < 0 && !R_FINITE(values[i]))
                    Rf_errorcall(R_NilValue, "summary inputs must be finite or missing");
                if (codes[i] >= 0) continue;
                count++;
                summary_accumulate(&sum, values[i]);
                if (values[i] < minimum) minimum = values[i];
                if (values[i] > maximum) maximum = values[i];
            }
            start += size;
            continue;
        }
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
    double total_value = unit ? count : summary_total(&total);
    double sum_value = summary_total(&sum);
    double mean = sum_value / total_value;
    summary_accumulator m2 = {0}, m3 = {0}, m4 = {0};
    if (count && total_value != 0 && R_FINITE(mean) &&
        !Rf_asLogical(meanonly) && integer) {
        scan.moments = 1;
        scan.mean = mean;
        numeric_for_each_span(x_reader.storage, 0, (size_t) length,
                              summary_integer_span, &scan);
        m2 = scan.m2;
        m3 = scan.m3;
        m4 = scan.m4;
    } else if (count && total_value != 0 && R_FINITE(mean) &&
        !Rf_asLogical(meanonly)) {
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t size = length - start < SUMMARY_BLOCK
                ? length - start : SUMMARY_BLOCK;
            numeric_reader_region(&x_reader, start, size, values, codes);
            if (unit) {
                for (R_xlen_t i = 0; i < size; i++) {
                    if (codes[i] >= 0) continue;
                    double centered = values[i] - mean;
                    summary_accumulate(&m2, centered * centered);
                    if (detailed) {
                        summary_accumulate(&m3, R_pow(centered, 3.0));
                        summary_accumulate(&m4, R_pow(centered, 4.0));
                    }
                }
                start += size;
                continue;
            }
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

/* A detailed summary under unit weights sorts the observed values and gives
   each a weight of 1. Integer storage whose observed values span a range
   not much larger than their count is sorted by counting each value, which
   reads the raw storage twice and orders nothing. */
typedef struct {
    int counting;
    int64_t count, minimum, maximum;
    R_xlen_t *counts;
} summary_sort_scan;

#define SUMMARY_SORT_ROWS(TYPE, LIMIT)                                       \
    do {                                                                    \
        const unsigned char *bytes = span->values;                           \
        TYPE limit = (LIMIT);                                                \
        for (size_t begin = 0; begin < span->length; ) {                     \
            size_t size = span->length - begin;                             \
            if (size > 65536) size = 65536;                                 \
            R_CheckUserInterrupt();                                         \
            if (!scan->counting) {                                          \
                int64_t count = 0;                                          \
                int64_t minimum = scan->minimum, maximum = scan->maximum;   \
                for (size_t i = begin; i < begin + size; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    int64_t value = raw;                                    \
                    int observed = raw < limit;                             \
                    count += observed;                                      \
                    minimum = observed && value < minimum ? value : minimum;\
                    maximum = observed && value > maximum ? value : maximum;\
                }                                                           \
                scan->count += count;                                       \
                scan->minimum = minimum;                                    \
                scan->maximum = maximum;                                    \
            } else {                                                        \
                R_xlen_t *counts = scan->counts;                            \
                int64_t minimum = scan->minimum;                            \
                for (size_t i = begin; i < begin + size; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    if (raw < limit) counts[(int64_t) raw - minimum]++;     \
                }                                                           \
            }                                                               \
            begin += size;                                                  \
        }                                                                   \
    } while (0)

static void summary_sort_span(
    const numeric_data *span, size_t offset, void *context
) {
    (void) offset;
    summary_sort_scan *scan = context;
    int legacy = span->format_version <= 111;
    switch (span->kind) {
    case NUMERIC_BYTE:
        SUMMARY_SORT_ROWS(int8_t, legacy ? 127 : 101);
        break;
    case NUMERIC_INT:
        SUMMARY_SORT_ROWS(int16_t, legacy ? 32767 : 32741);
        break;
    default:
        SUMMARY_SORT_ROWS(int32_t, legacy ? INT32_MAX : INT32_C(2147483621));
        break;
    }
}
#undef SUMMARY_SORT_ROWS

SEXP C_dtatools_summary_sorted(SEXP x, SEXP weights) {
    if (TYPEOF(x) != REALSXP || !summary_scan_supported(x)) return R_NilValue;
    R_xlen_t length = XLENGTH(x);
    if (XLENGTH(weights) != length || !summary_unit_weights(weights))
        return R_NilValue;
    numeric_reader reader;
    numeric_data storage;
    PROTECT(summary_reader_capture(x, &reader, &storage));
    if (!summary_integer_storage(reader.storage, length)) {
        UNPROTECT(1);
        return R_NilValue;
    }
    summary_sort_scan scan = {0, 0, INT64_MAX, INT64_MIN, NULL};
    numeric_for_each_span(reader.storage, 0, (size_t) length,
                          summary_sort_span, &scan);
    int64_t range = scan.count ? scan.maximum - scan.minimum + 1 : 0;
    if (range > scan.count + 65536) {
        UNPROTECT(1);
        return R_NilValue;
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) scan.count));
    if (scan.count) {
        scan.counts = (R_xlen_t *) R_alloc((size_t) range, sizeof(R_xlen_t));
        memset(scan.counts, 0, (size_t) range * sizeof(R_xlen_t));
        scan.counting = 1;
        numeric_for_each_span(reader.storage, 0, (size_t) length,
                              summary_sort_span, &scan);
        double *out = REAL(result);
        R_xlen_t position = 0;
        for (int64_t value = 0; value < range; value++) {
            double observed = (double) (scan.minimum + value);
            for (R_xlen_t k = scan.counts[value]; k > 0; k--)
                out[position++] = observed;
        }
    }
    UNPROTECT(2);
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

/* The first row of each level: for each code 1 to `count`, the 1-based
   position of the first element of the integer codes `x` equal to it, or NA.
   This is match(seq_len(count), x) without hashing every code, and it stops
   once each level has a row. A long vector returns NULL, and the caller
   matches as before. */
SEXP C_dtatools_first_codes(SEXP x, SEXP count_value) {
    if (TYPEOF(x) != INTSXP) Rf_error("Expected integer codes");
    int count = Rf_asInteger(count_value);
    if (count == NA_INTEGER || count < 0) Rf_error("Expected a level count");
    R_xlen_t n = XLENGTH(x);
    if (n > INT_MAX) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(INTSXP, count));
    int *first = INTEGER(result);
    for (int level = 0; level < count; ++level) first[level] = NA_INTEGER;
    int remaining = count;
    int buffer[4096];
    R_xlen_t next_interrupt = 0;
    for (R_xlen_t start = 0; start < n && remaining > 0;) {
        if (start >= next_interrupt) {
            R_CheckUserInterrupt();
            next_interrupt = start + 1048576;
        }
        /* An ALTREP class may copy less than the region asked for. Advance
           by what it copied, and read one element when it copies none. */
        R_xlen_t size = INTEGER_GET_REGION(x, start, 4096, buffer);
        if (size <= 0) {
            buffer[0] = INTEGER_ELT(x, start);
            size = 1;
        }
        for (R_xlen_t offset = 0; offset < size && remaining > 0; ++offset) {
            int code = buffer[offset];
            if (code >= 1 && code <= count && first[code - 1] == NA_INTEGER) {
                first[code - 1] = (int) (start + offset + 1);
                --remaining;
            }
        }
        start += size;
    }
    UNPROTECT(1);
    return result;
}
