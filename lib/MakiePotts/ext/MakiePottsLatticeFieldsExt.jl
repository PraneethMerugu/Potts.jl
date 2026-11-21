# The field recipe's reads of LatticeFields solutions: the solution of a problem from
# `LatticePDE.discretize` (`LatticeSolution`, from a field algorithm or an OrdinaryDiffEq
# solver) and a `FieldSolution` of a `FieldProblem` solved directly. Both read a field
# through `field_series`, so a field, an aux field or an input plots the same way.
module MakiePottsLatticeFieldsExt

using LatticeFields.Problems: FieldSolution, LatticeSolution, field_series
using MakiePotts: MakiePotts, FieldFrames

function MakiePotts.field_frames(sol::Union{FieldSolution, LatticeSolution}, field)
    return FieldFrames(sol.t, field_series(sol, field))
end

end
