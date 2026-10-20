---
status: proposed
---

# Read the current group through one set of mask bindings

Dibble verbs evaluate expressions in a data mask whose active bindings read
column slices. ADR 0034 built a new set of bindings for every group, each
fixed to that group, so a closure, promise, quosure, or pronoun captured in
one group kept reading that group's rows when called in another. On wide data
that costs a binding per column per group. On a 16,787-row, 5,360-column DHS
file with 400 clusters, building them took about 0.55 of the 0.7 to 0.8
seconds of `summarise(m = mean(v012), .by = v001)`, a third of it in garbage
collection.

The mask now builds one set of bindings and uses it for every group. Each
binding reads the group being evaluated at the time it is read, as dplyr's
bindings do. A capture made in group 1 and called while group 2 is evaluated
reads group 2's rows, which is what dplyr gives on a tibble. A promise forced
in group 1 keeps the value it read then. A capture called after the verb
returns still raises the obsolete data mask error.

Bindings still capture column generations. An expression that adds, replaces,
or removes a column retires the set, and the next mask builds a new one. A
capture therefore keeps reading each column as it was when the capture was
made, so ADR 0034's guarantee that later replacement cannot change an earlier
capture still holds. Here dibbles differ from dplyr, which replaces bindings
in place, so that a dplyr capture reads the new column.

Keeping fixed groups would need a binding per column per group, however each
binding is built. A cheaper construction could reduce that cost but not
remove it. Sharing the set removes it, so the grouped `summarise()` above
takes 0.17 seconds.

This replaces the sentences of ADR 0034 that fix each capture's group. Its
other decisions stand.
