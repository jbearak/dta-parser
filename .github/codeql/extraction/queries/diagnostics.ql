/**
 * @name Preserved extraction diagnostics
 * @description Raw recorded diagnostics including build-none warnings, with their translation units.
 * @kind table
 * @id local/preserved-extraction-diagnostics
 */
import cpp

from Diagnostic d, string unit
where unit = d.getCompilation().getAFileCompiled().getAbsolutePath()
  or not exists(d.getCompilation().getAFileCompiled()) and unit = ""
select d.getFile().getAbsolutePath() as file,
  d.getLocation().getStartLine() as line,
  d.getSeverity() as severity, d.getTag() as tag,
  d.getFullMessage() as message, unit as translation_unit
