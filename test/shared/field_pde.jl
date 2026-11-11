# The names the PDESystems of the Potts test models use (F4-B4t): a test file defines its
# PDESystems in a module of its own, `module XxPDE; using ..FieldPDE; … end`, and couples them
# into its models with `@fields`. `pdesys(eqs, bcs, dims, dvs, ps)` is MTK's `PDESystem` on the
# domain of a lattice of `dims` sites (`lattice_domain`, axis `d` spanning `[0, dims[d] ·
# spacing[d]]`), with the time and one coordinate per axis as its independent variables.
module FieldPDE
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, Shift, @variables, @parameters
using Potts.LatticePDE: Δ, masked, lattice_domain, pdesystem, DivKGrad, Advect, Upwind1, Coarse, step_index, ismember
const t = Potts.t
const Dt = Differential(t)
@parameters x y z

"""
    pdesys(eqs, bcs, dims, dvs, ps = []; spacing = 1, name = :fields)

`PDESystem(eqs, bcs, lattice_domain(t, xs, dims; spacing), [t; xs], dvs, ps; name)`, with `xs`
the first `length(dims)` of `x`, `y`, `z`.
"""
function pdesys(eqs, bcs, dims, dvs, ps = Any[]; spacing = 1, name = :fields)
    xs = (x, y, z)[1:length(dims)]
    return PDESystem(eqs, bcs, lattice_domain(t, xs, dims; spacing), [t; collect(xs)], dvs, ps; name)
end

export PDESystem, Differential, Shift, @variables, @parameters, Δ, masked, lattice_domain, pdesystem, DivKGrad, Advect, Upwind1,
       Coarse, step_index, ismember, t, Dt, x, y, z, pdesys
end
