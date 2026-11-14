"""
    using Potts.Fields

The vocabulary for writing a field as a plain ModelingToolkit `PDESystem` that couples into a
model (`@fields`, `Potts.couple`): MTK's `PDESystem`, `Differential`, `@variables` and
`@parameters` (the ModelingToolkitBase bindings), `Interval` (DomainSets'), LatticePDE's
operators (`Δ`, `DivKGrad`, `Advect`, `Upwind1`, `at`, `at2`, `ismember`, `masked`,
`step_index`), `lattice_domain` and `pdesystem`, the time `t` (`Potts.t`, which is MTK's
`t_nounits`) and the lattice coordinates `x`, `y`, `z` (`Potts`' own, which a binding may read).

It is opt-in: `using Potts` alone does not bring in `t`, `x`, `y` or `z`. `t` is the same
variable as MTK's `t_nounits` (not MTK's `t`, which has units). `D` is not exported (a common
name for a diffusion coefficient).
"""
module Fields

using ..Potts: Potts
using LatticePDE: Interval, Δ, DivKGrad, Advect, Upwind1, at, at2, ismember, masked, step_index, lattice_domain, pdesystem
using ModelingToolkitBase: PDESystem, Differential, @variables, @parameters

"""Independent time variable (`Potts.t`, ModelingToolkitBase's unitless `t_nounits`)."""
const t = Potts.t
"""Lattice spatial coordinate `x` (first axis, site center from 0 at the low face)."""
const x = Potts.FIELD_NAMES.x
"""Lattice spatial coordinate `y` (second axis, site center from 0 at the low face)."""
const y = Potts.FIELD_NAMES.y
"""Lattice spatial coordinate `z` (third axis, site center from 0 at the low face)."""
const z = Potts.FIELD_NAMES.z

export PDESystem, Differential, @variables, @parameters, Interval
export Δ, DivKGrad, Advect, Upwind1, at, at2, ismember, masked, step_index, lattice_domain, pdesystem
export t, x, y, z

end
