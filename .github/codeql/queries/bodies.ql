/**
 * @name Preserved function-body presence by file
 * @description Recorded function definitions and bodies, not a proof of complete body semantics.
 * @kind table
 * @id local/preserved-function-body-presence
 */
import cpp
from File source, string source_metric
where exists(source.getRelativePath()) and
  (if source.fromSource() then source_metric = "present" else source_metric = "absent")
select source.getRelativePath() as file, source_metric,
  count(Function f | f.getDefinition().getFile() = source) as function_definitions,
  count(Function f | f.getBlock().getFile() = source) as function_bodies
