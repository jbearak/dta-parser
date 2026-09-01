# Report current R data and complete file metadata

`labelbook()` reports only value-label tables assigned to columns in an R data frame, because the object represents its current variables rather than the history of the file from which it came. A direct `.dta` or `.arrow` path may report the complete on-disk registry, including unassigned tables. This keeps column selection and ordinary R transformations honest without turning the imported registry into the editable source of truth planned for the named-table authoring API.
