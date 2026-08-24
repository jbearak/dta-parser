#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)

if test -n "${CI:-}${GITHUB_ACTIONS:-}${GITHUB_RUN_ID:-}${GITHUB_WORKFLOW:-}"; then
    echo "aww-cache differential is a local, manual workflow and refuses CI" >&2
    exit 2
fi

for command in R Rscript shasum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "required command is unavailable: $command" >&2
        exit 2
    fi
done

if ! Rscript --vanilla -e 'quit(status = !all(vapply(c("callr", "fs", "haven", "openssl", "processx", "rlang", "tibble", "tidyselect"), requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))))'; then
    echo "required R packages are unavailable" >&2
    exit 2
fi

state="$checkout/target/aww-cache-differential"
mkdir -p "$state/builds" "$state/tmp"
chmod 700 "$state" "$state/builds" "$state/tmp"
export TMPDIR
TMPDIR=$(mktemp -d "$state/tmp/run.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM

build_id=$(Rscript --vanilla - "$checkout/r-package/dtaparser" "$script_dir" <<'RS'
args <- commandArgs(TRUE)
files <- c(
    list.files(args[[1L]], all.files = TRUE, full.names = TRUE, recursive = TRUE,
               include.dirs = FALSE, no.. = TRUE),
    list.files(args[[2L]], pattern = "\\.(R|do|sh)$", all.files = TRUE,
               full.names = TRUE, recursive = TRUE, include.dirs = FALSE, no.. = TRUE)
)
files <- sort(files[file.info(files)$isdir %in% FALSE], method = "radix")
hashes <- vapply(files, function(path) {
    con <- file(path, "rb")
    on.exit(close(con), add = TRUE)
    as.character(openssl::sha256(con))
}, character(1))
cat(as.character(openssl::sha256(charToRaw(paste(hashes, collapse = "\n")))))
RS
)

build="$state/builds/$build_id"
library="$build/library"
package="$library/dtaparser"
if ! test -d "$package"; then
    stage="$TMPDIR/build"
    staged_library="$TMPDIR/library"
    mkdir -p "$stage" "$staged_library"
    cp -R "$checkout/r-package/dtaparser" "$stage/dtaparser"
    version=$(sed -n 's/^Version: //p' "$stage/dtaparser/DESCRIPTION")
    (cd "$stage" && R CMD build dtaparser >/dev/null)
    R CMD INSTALL --library="$staged_library" "$stage/dtaparser_${version}.tar.gz"
    mkdir -p "$build"
    mv "$staged_library" "$library"
    chmod -R u=rwX,go= "$build"
fi

export AWW_PACKAGE_LIBRARY="$library"
export AWW_PACKAGE_PATH="$package"
export AWW_BUILD_ID="$build_id"
export R_ENVIRON_USER=/dev/null
export R_PROFILE_USER=/dev/null

cd "$checkout"
set +e
Rscript --vanilla "$script_dir/run.R" "$@"
status=$?
set -e
exit "$status"
