#include <R.h>
#include <Rinternals.h>
#include <string.h>
typedef struct { int count; SEXP tag[8]; SEXP value[8]; } closure_attrs;
static int plain_attr_tree(SEXP x, int *budget, int depth);
typedef struct { int *budget; int depth; int count; } attr_walk;
static SEXP validate_nested_attr(SEXP tag, SEXP value, void *context) {
    attr_walk *walk = (attr_walk *)context;
    if (++walk->count > 16 || TYPEOF(tag)!=SYMSXP || ANY_ATTRIB(tag) ||
        !plain_attr_tree(value,walk->budget,walk->depth+1)) return R_NilValue;
    return NULL;
}
static int plain_attr_tree(SEXP x, int *budget, int depth) {
    if (--*budget < 0 || depth > 64 || ALTREP(x)) return 0;
    if (TYPEOF(x)==SYMSXP) {
        if (ANY_ATTRIB(x)) return 0;
    } else if (TYPEOF(x)!=CHARSXP) {
        attr_walk walk = {.budget=budget,.depth=depth,.count=0};
        if (R_mapAttrib(x,validate_nested_attr,&walk) != NULL) return 0;
    }
    switch(TYPEOF(x)) {
    case NILSXP: case SYMSXP: case CHARSXP: case BUILTINSXP:
    case SPECIALSXP: case ENVSXP: return 1;
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP: case RAWSXP:
        return XLENGTH(x) <= 4096;
    case STRSXP:
        if (XLENGTH(x)>4096) return 0;
        for (R_xlen_t i=0;i<XLENGTH(x);++i)
            if (!plain_attr_tree(STRING_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return plain_attr_tree(TAG(x),budget,depth+1) &&
            plain_attr_tree(CAR(x),budget,depth+1) &&
            plain_attr_tree(CDR(x),budget,depth+1);
    case CLOSXP:
        return plain_attr_tree(R_ClosureFormals(x),budget,depth+1) &&
            plain_attr_tree(R_ClosureBody(x),budget,depth+1) &&
            plain_attr_tree(R_ClosureEnv(x),budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(x)>4096) return 0;
        for (R_xlen_t i=0;i<XLENGTH(x);++i)
            if (!plain_attr_tree(VECTOR_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    default: return 0;
    }
}

SEXP C_probe_public48_plain(SEXP fn) {
    int budget=32768;
    return Rf_ScalarLogical(TYPEOF(fn)==CLOSXP &&
                            plain_attr_tree(fn,&budget,0));
}

SEXP C_probe_public48_ident_flags(SEXP a, SEXP b) {
    if (TYPEOF(a)!=CLOSXP || TYPEOF(b)!=CLOSXP)
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocMatrix(LGLSXP,4,8));
    SEXP ax[4] = {a,R_ClosureFormals(a),R_ClosureBody(a),R_ClosureExpr(a)};
    SEXP bx[4] = {b,R_ClosureFormals(b),R_ClosureBody(b),R_ClosureExpr(b)};
    for (int j=0;j<8;j++) {
        int flags=(j&1 ? IDENT_USE_BYTECODE : 0) |
            (j&2 ? IDENT_USE_CLOENV : 0) |
            (j&4 ? IDENT_USE_SRCREF : 0);
        for (int i=0;i<4;i++)
            LOGICAL(out)[i+4*j] = R_compute_identical(ax[i],bx[i],flags);
    }
    UNPROTECT(1);
    return out;
}
static SEXP capture_closure_attr(SEXP tag, SEXP value, void *context) {
    closure_attrs *out = (closure_attrs *)context;
    if (out->count >= 8 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag))
        return R_NilValue;
    out->tag[out->count] = tag;
    out->value[out->count++] = value;
    return NULL;
}
static SEXP body_source_file(SEXP expression) {
    closure_attrs a = {.count=0};
    if (R_mapAttrib(expression,capture_closure_attr,&a) != NULL)
        return R_NilValue;
    SEXP tag = Rf_install("srcfile"), value = R_NilValue;
    for (int i=0;i<a.count;++i)
        if (a.tag[i]==tag) {
            if (value!=R_NilValue) return R_NilValue;
            value=a.value[i];
        }
    return value;
}
static int exact_source_tree(SEXP a, SEXP b, SEXP source_a, SEXP source_b,
                             int *budget, int depth) {
    if (--*budget<0 || depth>96 || TYPEOF(a)!=TYPEOF(b) ||
        ALTREP(a) || ALTREP(b) || Rf_isObject(a)!=Rf_isObject(b) ||
        Rf_isS4(a)!=Rf_isS4(b)) return 0;
    if (a==b) return 1;
    closure_attrs aa={.count=0}, ab={.count=0};
    if (TYPEOF(a)!=CHARSXP && TYPEOF(a)!=SYMSXP) {
        if (R_mapAttrib(a,capture_closure_attr,&aa)!=NULL ||
            R_mapAttrib(b,capture_closure_attr,&ab)!=NULL ||
            aa.count!=ab.count) return 0;
        for (int i=0;i<aa.count;++i)
            if (aa.tag[i]!=ab.tag[i] ||
                !exact_source_tree(aa.value[i],ab.value[i],source_a,source_b,
                                   budget,depth+1)) return 0;
    } else if (TYPEOF(a)==SYMSXP && (ANY_ATTRIB(a)||ANY_ATTRIB(b))) return 0;
    switch(TYPEOF(a)) {
    case NILSXP: case SYMSXP: case BUILTINSXP: case SPECIALSXP:
        return a==b;
    case ENVSXP:
        return (a==source_a && b==source_b) || a==b;
    case CHARSXP:
        return R_compute_identical(a,b,IDENT_USE_BYTECODE|
                                   IDENT_USE_CLOENV|IDENT_USE_SRCREF);
    case LGLSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(LOGICAL(a),LOGICAL(b),(size_t)XLENGTH(a)*sizeof(int))==0;
    case INTSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(INTEGER(a),INTEGER(b),(size_t)XLENGTH(a)*sizeof(int))==0;
    case REALSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(REAL(a),REAL(b),(size_t)XLENGTH(a)*sizeof(double))==0;
    case CPLXSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(COMPLEX(a),COMPLEX(b),(size_t)XLENGTH(a)*sizeof(Rcomplex))==0;
    case RAWSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(RAW(a),RAW(b),(size_t)XLENGTH(a))==0;
    case STRSXP:
        if (XLENGTH(a)!=XLENGTH(b)) return 0;
        for (R_xlen_t i=0;i<XLENGTH(a);++i)
            if (!exact_source_tree(STRING_ELT(a,i),STRING_ELT(b,i),
                                   source_a,source_b,budget,depth+1)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return exact_source_tree(TAG(a),TAG(b),source_a,source_b,budget,depth+1) &&
            exact_source_tree(CAR(a),CAR(b),source_a,source_b,budget,depth+1) &&
            exact_source_tree(CDR(a),CDR(b),source_a,source_b,budget,depth+1);
    case CLOSXP:
        return exact_source_tree(R_ClosureFormals(a),R_ClosureFormals(b),
                                 source_a,source_b,budget,depth+1) &&
            exact_source_tree(R_ClosureBody(a),R_ClosureBody(b),
                                 source_a,source_b,budget,depth+1) &&
            exact_source_tree(R_ClosureEnv(a),R_ClosureEnv(b),
                                 source_a,source_b,budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(a)!=XLENGTH(b) || XLENGTH(a)>*budget) return 0;
        for (R_xlen_t i=0;i<XLENGTH(a);++i)
            if (!exact_source_tree(VECTOR_ELT(a,i),VECTOR_ELT(b,i),
                                   source_a,source_b,budget,depth+1)) return 0;
        return 1;
    default: return 0;
    }
}
SEXP C_probe_public48_source_qualification(SEXP current, SEXP frozen) {
    if (TYPEOF(current)!=CLOSXP || TYPEOF(frozen)!=CLOSXP)
        return R_NilValue;
    int plain_a=32768,plain_b=32768;
    if (!plain_attr_tree(current,&plain_a,0) ||
        !plain_attr_tree(frozen,&plain_b,0)) return R_NilValue;
    SEXP ca=R_ClosureExpr(current), cb=R_ClosureExpr(frozen);
    SEXP sa=body_source_file(ca), sb=body_source_file(cb);
    if (!((TYPEOF(sa)==ENVSXP && TYPEOF(sb)==ENVSXP) ||
          (sa==R_NilValue && sb==R_NilValue)) ||
        R_ClosureEnv(current)!=R_ClosureEnv(frozen)) return R_NilValue;
    SEXP out=PROTECT(Rf_allocVector(LGLSXP,4));
    int budget=32768;
    LOGICAL(out)[0]=exact_source_tree(R_ClosureFormals(current),
        R_ClosureFormals(frozen),sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[1]=exact_source_tree(ca,cb,sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[2]=exact_source_tree(R_ClosureBody(current),
        R_ClosureBody(frozen),sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[3]=exact_source_tree(current,frozen,sa,sb,&budget,0);
    UNPROTECT(1);
    return out;
}
