/* Diagnostic only: a genuine object table attached through base::attach().
   R_ext/ObjectTable.h is an experimental R interface, not production code. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/ObjectTable.h>
#include <string.h>

typedef struct { R_ObjectTable table; SEXP value; int gets; } initial_capture_userdb;
static SEXP userdb_get(const char * const name, Rboolean *cache, R_ObjectTable *table) {
    initial_capture_userdb *db = (initial_capture_userdb *) table;
    if (cache) *cache = FALSE;
    if (strcmp(name, "operand") != 0) return R_UnboundValue;
    db->gets++;
    return db->value;
}
static Rboolean userdb_exists(const char * const name, Rboolean *cache, R_ObjectTable *table) {
    (void) table;
    if (cache) *cache = FALSE;
    return strcmp(name, "operand") == 0;
}
static Rboolean userdb_cache(const char * const name, R_ObjectTable *table) {
    (void) name; (void) table; return FALSE;
}
static SEXP userdb_objects(R_ObjectTable *table) {
    (void) table; return Rf_mkString("operand");
}
static void userdb_finalizer(SEXP pointer) {
    initial_capture_userdb *db = R_ExternalPtrAddr(pointer);
    if (db) { R_Free(db); R_ClearExternalPtr(pointer); }
}
SEXP initial_capture_userdb_create(SEXP value) {
    initial_capture_userdb *db = R_Calloc(1, initial_capture_userdb);
    db->value = value; db->table.active = TRUE;
    db->table.get = userdb_get; db->table.exists = userdb_exists;
    db->table.objects = userdb_objects; db->table.canCache = userdb_cache;
    SEXP pointer = PROTECT(R_MakeExternalPtr(db, R_NilValue, value));
    SEXP classes = PROTECT(Rf_mkString("UserDefinedDatabase"));
    Rf_setAttrib(pointer, R_ClassSymbol, classes);
    R_RegisterCFinalizerEx(pointer, userdb_finalizer, TRUE);
    UNPROTECT(2); return pointer;
}
SEXP initial_capture_userdb_gets(SEXP pointer, SEXP reset) {
    initial_capture_userdb *db = R_ExternalPtrAddr(pointer);
    if (!db) Rf_error("dead diagnostic database");
    SEXP result = Rf_ScalarInteger(db->gets);
    if (Rf_asLogical(reset) == TRUE) db->gets = 0;
    return result;
}
