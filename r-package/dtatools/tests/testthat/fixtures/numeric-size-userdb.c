/* Diagnostic only: a genuine object table attached through base::attach().
   R_ext/ObjectTable.h is an experimental R interface, not production code. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/ObjectTable.h>
#include <string.h>

typedef struct {
    R_ObjectTable table;
    SEXP value, later, symbol;
    int changes, gets;
} numeric_size_userdb;
static SEXP userdb_get(const char * const name, Rboolean *cache, R_ObjectTable *table) {
    numeric_size_userdb *db = (numeric_size_userdb *) table;
    if (cache) *cache = FALSE;
    if (strcmp(name, CHAR(PRINTNAME(db->symbol))) != 0) return R_UnboundValue;
    db->gets++;
    return db->changes && db->gets > 1 ? db->later : db->value;
}
static Rboolean userdb_exists(const char * const name, Rboolean *cache, R_ObjectTable *table) {
    numeric_size_userdb *db = (numeric_size_userdb *) table;
    if (cache) *cache = FALSE;
    return strcmp(name, CHAR(PRINTNAME(db->symbol))) == 0;
}
static Rboolean userdb_cache(const char * const name, R_ObjectTable *table) {
    (void) name; (void) table; return FALSE;
}
static SEXP userdb_objects(R_ObjectTable *table) {
    numeric_size_userdb *db = (numeric_size_userdb *) table;
    return Rf_ScalarString(PRINTNAME(db->symbol));
}
static void userdb_finalizer(SEXP pointer) {
    numeric_size_userdb *db = R_ExternalPtrAddr(pointer);
    if (db) { R_Free(db); R_ClearExternalPtr(pointer); }
}
SEXP numeric_size_userdb_create(SEXP value) {
    numeric_size_userdb *db = R_Calloc(1, numeric_size_userdb);
    db->value = value; db->symbol = Rf_install("operand"); db->table.active = TRUE;
    db->table.get = userdb_get; db->table.exists = userdb_exists;
    db->table.objects = userdb_objects; db->table.canCache = userdb_cache;
    SEXP pointer = PROTECT(R_MakeExternalPtr(db, R_NilValue, value));
    SEXP classes = PROTECT(Rf_mkString("UserDefinedDatabase"));
    Rf_setAttrib(pointer, R_ClassSymbol, classes);
    R_RegisterCFinalizerEx(pointer, userdb_finalizer, TRUE);
    UNPROTECT(2); return pointer;
}
SEXP numeric_size_userdb_create_changing(SEXP first, SEXP later) {
    SEXP pointer = PROTECT(numeric_size_userdb_create(first));
    numeric_size_userdb *db = R_ExternalPtrAddr(pointer);
    SEXP roots = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(roots, 0, first); SET_VECTOR_ELT(roots, 1, later);
    R_SetExternalPtrProtected(pointer, roots);
    db->later = later; db->changes = 1;
    UNPROTECT(2); return pointer;
}
SEXP numeric_size_userdb_create_named(SEXP value, SEXP name) {
    SEXP pointer = PROTECT(numeric_size_userdb_create(value));
    numeric_size_userdb *db = R_ExternalPtrAddr(pointer);
    db->symbol = Rf_installTrChar(STRING_ELT(name, 0));
    UNPROTECT(1); return pointer;
}
SEXP numeric_size_userdb_gets(SEXP pointer, SEXP reset) {
    numeric_size_userdb *db = R_ExternalPtrAddr(pointer);
    if (!db) Rf_error("dead diagnostic database");
    SEXP result = Rf_ScalarInteger(db->gets);
    if (Rf_asLogical(reset) == TRUE) db->gets = 0;
    return result;
}
