test_that("grouped native gen publishes and declines after a staged source change", {
    if (!.dtatools_child_native(.libPaths())) skip_if_not_installed("callr")
    native_expected <- .dtatools_public_mutation_build_expected()
    observed <- .dtatools_child_r("grouped-gen-native-clean-session", function(native_expected) {
        library(dtatools)
        library(tibble)
        options(dtatools.generate_type = "double")
        probe <- function(name, ...) {
            .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
        }
        with_mode <- function(enabled, action) {
            prior <- probe("C_dtatools_probe_grouped_gen_mode", enabled)
            on.exit(probe("C_dtatools_probe_grouped_gen_mode", prior))
            action()
        }
        make <- function() {
            values <- list(region = rep(c(-3L, 9L, 0L), length.out = 317L),
                           spare = rep(7, 317L),
                           amount = rep(c(1, 2, 3, 4), length.out = 317L))
            data <- as_dibble(tibble::as_tibble(values))
            probe("C_dtatools_patch_slot", data, 3L, NULL,
                  values$amount, TRUE)
            holder <- new.env(parent = globalenv())
            holder$d <- data
            holder
        }
        same <- function(actual, expected) {
            stopifnot(identical(names(actual), names(expected)),
                      identical(class(actual), class(expected)),
                      identical(attr(actual, "row.names"),
                                attr(expected, "row.names")))
            for (name in names(actual))
                stopifnot(identical(as.double(actual[[name]]),
                                    as.double(expected[[name]])),
                          identical(attributes(actual[[name]]),
                                    attributes(expected[[name]])))
        }

        ordinary <- with_mode(FALSE, function() {
            holder <- make()
            evalq(gen(d, adjusted = amount + 2.5, by = region), holder)
        })
        first <- with_mode(TRUE, function() {
            holder <- make()
            before <- probe("C_dtatools_probe_grouped_gen_stats", FALSE)
            result <- evalq(gen(d, adjusted = amount + 2.5, by = region),
                            holder)
            after <- probe("C_dtatools_probe_grouped_gen_stats", FALSE)
            list(result = result, counts = as.integer(after - before))
        })
        same(first$result, ordinary)
        stopifnot(identical(dta_storage_type(first$result$adjusted), "double"))

        changed_ordinary <- with_mode(FALSE, function() {
            holder <- make()
            evalq(repl(d, amount = 99), holder)
            evalq(gen(d, adjusted = amount + 1, by = region), holder)
        })
        changed_native <- with_mode(TRUE, function() {
            holder <- make()
            hook_hits <- 0L
            if (native_expected) {
                probe("C_dtatools_probe_grouped_gen_after_stage", function() {
                    hook_hits <<- hook_hits + 1L
                    evalq(repl(d, amount = 99), holder)
                })
            } else {
                evalq(repl(d, amount = 99), holder)
            }
            on.exit(probe("C_dtatools_probe_grouped_gen_after_stage", NULL))
            before <- probe("C_dtatools_probe_grouped_gen_stats", FALSE)
            result <- evalq(gen(d, adjusted = amount + 1, by = region),
                            holder)
            after <- probe("C_dtatools_probe_grouped_gen_stats", FALSE)
            list(result = result, counts = as.integer(after - before),
                 hook_hits = hook_hits)
        })
        same(changed_native$result, changed_ordinary)
        list(first = first$counts, changed = changed_native$counts,
             hook_hits = changed_native$hook_hits)
    }, args = list(native_expected = native_expected), libpath = .libPaths())
    expect_identical(observed$first, if (native_expected) c(1L, 1L, 1L) else c(1L, 0L, 0L))
    expect_identical(observed$changed, if (native_expected) c(1L, 1L, 0L) else c(1L, 0L, 0L))
    expect_identical(observed$hook_hits, as.integer(native_expected))
})
