# Independent test oracle: a disabled production record cannot make positive
# native-admission tests pass by selecting their unsupported-runtime branch.
.dtatools_bytecode_execution_expected <- function() {
    private <- new.env(parent = baseenv())
    probe <- function() vector("list", 1L)
    environment(probe) <- private
    probe <- compiler::cmpfun(probe, options = list(optimize = 3L))
    private$vector <- function(...) FALSE
    identical(probe(), list(NULL))
}

.dtatools_execution_profile_expected <- function() {
    identical(as.character(getRversion()), "4.6.1") &&
        identical(as.character(R.version[["svn rev"]]), "90187") &&
        .dtatools_bytecode_execution_expected()
}

# Success counters describe actual publication from canonical production
# bodies. Explicit-frame kernel diagnostics do not increment these counters.
.dtatools_numeric_entry_counts <- function(reset = FALSE) {
    .Primitive(".Call")(get("C_dtatools_numeric_entry_stats", asNamespace("dtatools")), reset)
}

.dtatools_numeric_entry_observe <- function(operation) {
    invisible(.dtatools_numeric_entry_counts(TRUE))
    result <- operation()
    list(result = result, counts = .dtatools_numeric_entry_counts(FALSE))
}

.dtatools_numeric_entry_expected <- function(route = NULL) {
    if (identical(route, "holds")) return(.dtatools_execution_profile_expected())
    .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
}

# This independent oracle checks external build identity and the package's
# audited closure attribute shape. It never reads a production admission flag,
# so disabling a supported route still fails its positive regression.
# Other builds exercise the ordinary fallback.
.dtatools_public_mutation_build_expected <- function() {
    if (!.dtatools_numeric_entry_expected()) return(FALSE)
    paths <- c(
        system.file("R", "base.rdb", package = "base"),
        system.file("R", "rlang.rdb", package = "rlang"),
        system.file("R", "vctrs.rdb", package = "vctrs"),
        file.path(R.home("lib"), "libR.dylib"),
        system.file("libs", paste0("rlang", .Platform$dynlib.ext),
                    package = "rlang"),
        system.file("libs", paste0("vctrs", .Platform$dynlib.ext),
                    package = "vctrs")
    )
    expected <- c(
        "021f0beae727b3a819484ec49390f3e5",
        "76538dba869773487446c5f4b12ddc51",
        "edb81a62bca8cbd01de4a978fc733456",
        "bfbd266353f98efd4ac8bc487fd7d45c",
        "d44ef6f686048db191bb0a7b1d6a7eb1",
        "bc58bbeb3ec490b263b937e23c3971a5"
    )
    if (!all(nzchar(paths)) || !all(file.exists(paths)) ||
        !identical(unname(tools::md5sum(paths)), expected)) return(FALSE)

    # The audited public closures and their bodies have no attributes. An
    # install with --with-keep.source adds source references, which differs
    # from the frozen wrapper/proxy dependencies of these two routes.
    # Read canonical installed code so earlier live traces cannot change the
    # oracle. These literal expectations do not use production profile assets.
    canonical <- new.env(parent = emptyenv())
    base::lazyLoad(system.file("R", "dtatools", package = "dtatools"),
                   envir = canonical)
    all(vapply(c("replace_values", "vec_proxy.dta_numeric",
                 "Ops.dta_numeric", "vec_arith.dta_numeric"), function(name) {
        code <- get0(name, envir = canonical, inherits = FALSE)
        identical(typeof(code), "closure") &&
            is.null(attributes(code)) && is.null(attributes(body(code)))
    }, logical(1)))
}

# Test-owned build records, copied once from the reviewed external artifacts.
# This oracle does not read installed admission manifests or native flags.
.dtatools_ungrouped_dplyr_build_expected <- function() {
    if (!.dtatools_numeric_entry_expected()) return(FALSE)
    profile <- utils::read.csv(text = "scope,package,version,relative_path,md5
r,base,4.6.1,library/base/DESCRIPTION,eeaa0679f2c89ce2f9e572c956dd4e46
r,base,4.6.1,library/base/R/Rprofile,71a9fb64b0619da940691de589ee6a29
r,base,4.6.1,library/base/R/base,505f588c95afa0f68881831a0883c9b4
r,base,4.6.1,library/base/R/base.rdb,021f0beae727b3a819484ec49390f3e5
r,base,4.6.1,library/base/R/base.rdx,cbd9eb7da9110d651a2730c2de758765
r,base,4.6.1,lib/libR.dylib,bfbd266353f98efd4ac8bc487fd7d45c
r,base,4.6.1,bin/exec/R,bddccfa6b400e6b10beedc8391e2691c
package,dplyr,1.2.1,DESCRIPTION,1371a61274b5b2ba64aff4ca992f01f9
package,dplyr,1.2.1,Meta/nsInfo.rds,b84718c83a355e0f2509e18bbac88d4a
package,dplyr,1.2.1,NAMESPACE,88e3340c6cccd4ddf36c1e6b39daf2f1
package,dplyr,1.2.1,R/dplyr,d6c68f1fe41ced6e98a766a3757313da
package,dplyr,1.2.1,R/dplyr.rdb,afbfb9f6928508f9e085de76bf008a2a
package,dplyr,1.2.1,R/dplyr.rdx,7002f81a19db1868d26ac3d18f045a44
package,dplyr,1.2.1,libs/dplyr.so,efbcc8a4e143b71b789fce76d32d52c7
package,vctrs,0.7.3,DESCRIPTION,5baa6e706454a956a05418f4711759b6
package,vctrs,0.7.3,Meta/nsInfo.rds,62132e619be1ce068fb7e58dae5fa3f0
package,vctrs,0.7.3,NAMESPACE,dc3f838ef66b256caca5df59b42deb4a
package,vctrs,0.7.3,R/vctrs,d6c68f1fe41ced6e98a766a3757313da
package,vctrs,0.7.3,R/vctrs.rdb,edb81a62bca8cbd01de4a978fc733456
package,vctrs,0.7.3,R/vctrs.rdx,8d896865b08e30b3be6084a8025d6b86
package,vctrs,0.7.3,libs/vctrs.so,bc58bbeb3ec490b263b937e23c3971a5
package,rlang,1.3.0,DESCRIPTION,b4dbb758a43577f1d57c1f5d42a17cff
package,rlang,1.3.0,Meta/nsInfo.rds,ade86959498c6d33c06269c0c2c2a0b2
package,rlang,1.3.0,NAMESPACE,aee4485d7866884894016981c7b2f517
package,rlang,1.3.0,R/rlang,d6c68f1fe41ced6e98a766a3757313da
package,rlang,1.3.0,R/rlang.rdb,76538dba869773487446c5f4b12ddc51
package,rlang,1.3.0,R/rlang.rdx,83699832dc4a80e24fc441a5056a81af
package,rlang,1.3.0,libs/rlang.so,d44ef6f686048db191bb0a7b1d6a7eb1
package,tidyselect,1.2.1,DESCRIPTION,1e9f8b32883b612c25d5263074b64761
package,tidyselect,1.2.1,Meta/nsInfo.rds,f67f6cc005650f58e904b86193eb7f35
package,tidyselect,1.2.1,NAMESPACE,bb0487b56562a51a1ed2b1d6c6f6616f
package,tidyselect,1.2.1,R/tidyselect,d6c68f1fe41ced6e98a766a3757313da
package,tidyselect,1.2.1,R/tidyselect.rdb,340abd17fa393bf9a1e8cb93524d0e35
package,tidyselect,1.2.1,R/tidyselect.rdx,722ae7724938015a0d655d197c4adf43
package,tibble,3.3.1,DESCRIPTION,5023484ee1f1f39d2af792ff1835a94c
package,tibble,3.3.1,Meta/nsInfo.rds,7b66b53721b649be0be0eb46ac9437c0
package,tibble,3.3.1,NAMESPACE,f7c86eac5877c047a84d961f97fd2447
package,tibble,3.3.1,R/tibble,d6c68f1fe41ced6e98a766a3757313da
package,tibble,3.3.1,R/tibble.rdb,5ec7ab0c14bc62d5adda718dbf385991
package,tibble,3.3.1,R/tibble.rdx,8921d8a362c6762962b0b49b26a96a5d
package,tibble,3.3.1,libs/tibble.so,e12e73161f96ba3f1b6818b873c9f5e7
package,stats,4.6.1,DESCRIPTION,d0829455511bb9e4e99cc68768092917
package,stats,4.6.1,Meta/nsInfo.rds,01ca16b27f0a823304b273f96116883f
package,stats,4.6.1,NAMESPACE,4fdff0882c642d94e451415911f72991
package,stats,4.6.1,R/stats,d6c68f1fe41ced6e98a766a3757313da
package,stats,4.6.1,R/stats.rdb,33bc36090a8459ce5a6034c1921ddc66
package,stats,4.6.1,R/stats.rdx,8aaf900b431794c452186c553bede14b
package,stats,4.6.1,libs/stats.so,2a37e6b1f9ffcd10550ef11de9aa9a7f
package,withr,3.0.3,DESCRIPTION,d18eb544d8c89d684e43eb794204cdd7
package,withr,3.0.3,Meta/nsInfo.rds,ef532117f337bf812f118585cf8b890a
package,withr,3.0.3,NAMESPACE,3604c48113b02b685fdd0eba1ee3e4d9
package,withr,3.0.3,R/withr,d6c68f1fe41ced6e98a766a3757313da
package,withr,3.0.3,R/withr.rdb,66d2bd00c41772a82b4247a81ea4b70b
package,withr,3.0.3,R/withr.rdx,4ecf5be3d060ff28bd55d501a4e98068", stringsAsFactors = FALSE)
    r_rows <- profile[profile$scope == "r", ]
    r_paths <- file.path(R.home(), r_rows$relative_path)
    if (!all(file.exists(r_paths)) ||
        !identical(unname(tools::md5sum(r_paths)), r_rows$md5))
        return(FALSE)
    packages <- profile[profile$scope == "package", ]
    for (pkg in unique(packages$package)) {
        entries <- packages[packages$package == pkg, ]
        root <- find.package(pkg, quiet = TRUE)
        if (length(root) != 1L ||
            !identical(as.character(utils::packageVersion(pkg)),
                       entries$version[[1L]])) return(FALSE)
        paths <- file.path(root, entries$relative_path)
        if (!all(file.exists(paths)) ||
            !identical(unname(tools::md5sum(paths)), entries$md5))
            return(FALSE)
    }
    TRUE
}
