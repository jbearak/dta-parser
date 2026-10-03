/**
 * @name Private preview extracted source paths
 * @description Lists extracted files under the source root for a separate coverage check.
 * @kind table
 * @id dta/private-preview-extracted-paths
 */
import cpp

from File f
where exists(f.getRelativePath()) and f.fromSource()
select f.getRelativePath()
