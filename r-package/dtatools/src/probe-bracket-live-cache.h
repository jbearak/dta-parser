#ifndef DTATOOLS_PROBE_BRACKET_LIVE_CACHE_H
#define DTATOOLS_PROBE_BRACKET_LIVE_CACHE_H
#include <Rinternals.h>
typedef struct {
    SEXP snapshots, tables, live, namespaces, primitives, length_method;
} dtatools_bracket_live_cache;
int dtatools_probe_bracket_live_cache_init(SEXP profile,
    dtatools_bracket_live_cache *cache);
int dtatools_probe_bracket_live_cache_check(
    const dtatools_bracket_live_cache *cache, SEXP caller);
#endif
