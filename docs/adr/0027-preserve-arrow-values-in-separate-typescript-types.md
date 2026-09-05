---
status: accepted
---

# Preserve Arrow values in separate TypeScript types

The TypeScript Arrow reader preserves exact supported values through Arrow
cell and metadata types, while retaining the existing DTA types for current
callers. Arrow nulls remain distinct from Stata missing objects, 64-bit integers
use `bigint`, temporal values retain their ticks and metadata, and dictionaries
retain codes, levels, and orderedness. Converting everything to DTA cells or
display strings would discard distinctions; widening the existing DTA cell
union would instead make current callers handle values their files cannot
contain. Consumers take responsibility for display conversion and JSON handling
of `bigint`.
