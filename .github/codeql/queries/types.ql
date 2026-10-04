/**
 * @name Current native interface type witnesses
 * @description Bounded typedef, descriptor-field and original-function type facts; not complete semantic coverage.
 * @kind table
 * @id local/current-native-type-witnesses
 */
import cpp

private predicate selectedAlias(TypedefType t) {
  t.getName() = ["SEXP", "R_xlen_t", "numeric_data", "numeric_reader", "arithmetic_general_output", "dtatools_bracket_live_cache"]
}

private predicate selectedFunction(Function f) {
  f.getName() = ["numeric_length", "numeric_payload_root", "numeric_strict_modern_float"]
}

private predicate witness(File source, string owner, string slot, Type t) {
  exists(TypedefType alias, TypeDeclarationEntry decl |
    selectedAlias(alias) and decl = alias.getADeclarationEntry() and
    source = decl.getFile() and owner = alias.getName() and slot = "typedef" and t = alias
  )
  or
  exists(TypedefType alias, TypeDeclarationEntry decl, Field member |
    alias.getName() = ["numeric_data", "numeric_reader", "arithmetic_general_output", "dtatools_bracket_live_cache"] and
    decl = alias.getADeclarationEntry() and source = decl.getFile() and
    member = alias.getUnderlyingType().(Class).getAField() and
    owner = alias.getName() and slot = "field:" + member.getName() and t = member.getType()
  )
  or
  exists(Function f |
    selectedFunction(f) and source = f.getBlock().getFile() and
    owner = f.getName() and slot = "return" and t = f.getType()
  )
  or
  exists(Function f, int index |
    selectedFunction(f) and source = f.getBlock().getFile() and
    owner = f.getName() and slot = "parameter:" + index.toString() and
    t = f.getParameter(index).getType()
  )
  or
  exists(Function f, FunctionDeclarationEntry decl |
    f.getName() = ["dtatools_probe_bracket_live_cache_init", "dtatools_probe_bracket_live_cache_check"] and
    decl = f.getADeclarationEntry() and source = decl.getFile() and owner = f.getName() and
    slot = "declaration-return" and t = f.getType()
  )
  or
  exists(Function f, FunctionDeclarationEntry decl, int index |
    f.getName() = ["dtatools_probe_bracket_live_cache_init", "dtatools_probe_bracket_live_cache_check"] and
    decl = f.getADeclarationEntry() and source = decl.getFile() and owner = f.getName() and
    slot = "declaration-parameter:" + index.toString() and t = f.getParameter(index).getType()
  )
}

from File source, string owner, string slot, Type t, string category, int size,
  string unknown
where
  witness(source, owner, slot, t) and
  (if t.getUnspecifiedType() instanceof PointerType then category = "pointer"
   else if t.getUnspecifiedType() instanceof IntegralType then category = "integral"
   else if t.getUnspecifiedType() instanceof FloatingPointType then category = "floating"
   else if t.getUnspecifiedType() instanceof Class then category = "class"
   else category = "other") and
  (if exists(t.getSize()) then size = t.getSize() else size = -1) and
  (if exists(UnknownType bad | t.getUnspecifiedType().refersTo(bad)) then unknown = "yes" else unknown = "no")
select source.getAbsolutePath() as file, owner, slot,
  t.toString() as declared_type, t.getUnspecifiedType().toString() as resolved_type,
  category, size, unknown
