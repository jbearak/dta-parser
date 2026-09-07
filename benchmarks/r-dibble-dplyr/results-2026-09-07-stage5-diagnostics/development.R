library(dtatools, lib.loc = '/private/tmp/dta-direct-stage4-validation/candidate-c8ca0a4-library')
library(dplyr)
root <- '/private/tmp/dta-direct-stage5'
e <- new.env(parent = asNamespace('dtatools'))
for (f in c('mutate-data.R', 'dibble-dplyr-context.R', 'dibble-expressions.R')) sys.source(file.path(root, 'r-package/dtatools/R', f), e)
for (generic in c('mutate', 'transmute', 'group_by', 'rowwise', 'ungroup')) registerS3method(generic, 'dtatools_ref_data', get(paste0(generic, '.dtatools_ref_data'), e), asNamespace('dplyr'))
for (name in ls(e, all.names = TRUE)) {
    if (exists(name, asNamespace('dtatools'), inherits = FALSE)) {
        unlockBinding(name, asNamespace('dtatools')); assign(name, get(name, e), asNamespace('dtatools')); lockBinding(name, asNamespace('dtatools'))
    }
}
setwd(file.path(root, 'r-package/dtatools'))
testthat::test_local('.', filter = 'dibble(-expressions)?$', load_package = 'installed', env = e, reporter = 'summary', stop_on_failure = TRUE)
