---
status: accepted
---

# Remember proven dependency functions across calls

A native route that does work R code would have done runs only after it
proves that every R function it skips is still the one the package was built
against. A traced, replaced, or redefined helper fails the proof, the route
declines, and the R code runs instead. Until now each call proved every
function again, walking its formals, source, and bytecode against a build-time
copy, and kept nothing afterward. Code comments stated the rule: a profile
descriptor held "never a successful verdict about a live function", and the
summary admission kept nothing between calls. Calls repeated once per group
paid for the walks every time. In `mutate(b, m = mean(b2), .by = caseid)` over
the 42,739 women in the first 100,000 rows of the India 2021 DHS births file,
the twenty-function proof behind each `mean()` took more than a quarter of the
3.2 seconds.

The comparators now keep each proven pair of live function and expectation in
a table, and a later call that finds the same live object skips the walk. R
code cannot change a closure or bytecode object in place while another
reference holds it. Replacement, `trace()`, `body<-`, `formals<-`, `attr<-`,
and `environment<-` all bind or copy a new object, and the table holds a
reference to every object it keeps. The table also keeps each expectation
alive, so neither address can be reused while its entry stands. A traced
helper is a new object, so it is walked, fails, and the route declines as
before. `untrace()` restores the original object, which the table admits
again.

An edit inside an existing object binds nothing new. C code can make one, and
so can `data.table::set()` on a constant that a helper returned. Before, the
next call's walk caught such an edit. Now a kept proof hides it. These edits
are outside the compatibility contract, which the grouped dplyr admission
already stated for edits inside bytecode. A package function edited this way
gives wrong answers on the R path too. Tests that make such edits first forget
the kept proofs through a test seam, so they still check that a fresh walk
catches the edit.

Every call still looks up each binding, checks environments and settled
promises, and compares builtins by address. Only the walks are skipped. Three
comparators keep separate tables, since a source proof does not imply a
bytecode proof: the bounded source comparison, the source and bytecode
comparison, and the bytecode body comparison that the numeric helper profiles
use. Each table has 512 slots of one pair, so a collision costs one fresh walk.

The size floor below which the numeric routes decline, 2,048 elements, is
unchanged. Without the walks the scalar and computed routes beat R from about
128 elements, while construction still loses below about 2,048, so the floor
can be revisited per route.

The maintainer approved this change on 2026-10-22, along with changing other
decisions that block measured speedups.
