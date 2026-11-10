"""
    using Potts.Fields

The vocabulary for writing a field as a plain ModelingToolkit `PDESystem` that couples into a
model (`@fields`, `Potts.couple`): MTK's `PDESystem`, `Differential`, `@variables` and
`@parameters` (the ModelingToolkitBase bindings), `Interval` (DomainSets'), LatticePDE's
operators (`Δ`, `DivKGrad`, `Advect`, `Upwind1`, `at`, `at2`, `ismember`, `masked`,
`step_index`), `lattice_domain`, the time `t` (`Potts.t`, which is MTK's
`t_nounits`) and the lattice coordinates `x`, `y`, `z` (`Potts`' own, which a binding may read).

It is opt-in: `using Potts` alone does not bring in `t`, `x`, `y` or `z`. With `using
ModelingToolkit` as well, `t` is ambiguous (MTK exports its units `t`); `t_nounits` is the same
variable as this `t`. `D` is not exported (a common name for a diffusion coefficient).
"""
module Fields

using ..Potts: Potts
using LatticePDE: Interval, Δ, DivKGrad, Advect, Upwind1, at, at2, ismember, masked, step_index, lattice_domain
using ModelingToolkitBase: PDESystem, Differential, @variables, @parameters

const t = Potts.t
const x = Potts.FIELD_NAMES.x
const y = Potts.FIELD_NAMES.y
const z = Potts.FIELD_NAMES.z

export PDESystem, Differential, @variables, @parameters, Interval
export Δ, DivKGrad, Advect, Upwind1, at, at2, ismember, masked, step_index, lattice_domain
export t, x, y, z

end
