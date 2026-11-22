# # [Nucleus migration in a crawling cell](@id model-fortuna)
#
# A crawling cell pushes a thin sheet of actin, the lamellipodium, out over the substrate,
# and the nucleus follows. Fortuna et al. (2020) modeled this in 3D with one cell made of
# three compartments: a cytoplasm, a nucleus and a lamellipodium. The lamellipodium makes
# F-actin where it touches the substrate. The F-actin field biases the lamellipodium's
# copies toward high F-actin, so the cell crawls. Cytoplasm sites on the substrate turn
# into lamellipodium at a rate that falls as the lamellipodium nears its target volume.
# PottsModels ships the model as `FortunaMigration`, and this page runs it.
#
# The F-actin field is an ordinary ModelingToolkit `PDESystem` (`FortunaField.factin` in
# the model source), coupled into the model with `@fields`. LatticePDE solves it on the
# model's lattice.
#
# - I. Fortuna, G. C. Perrone, M. S. Krug, E. Susin, J. M. Belmonte, G. L. Thomas, J. A.
#   Glazier and R. M. C. de Almeida, "CompuCell3D Simulations Reproduce Mesenchymal Cell
#   Migration on Flat Substrates", *Biophys. J.* **118**, 2801–2815 (2020),
#   doi:[10.1016/j.bpj.2020.04.024](https://doi.org/10.1016/j.bpj.2020.04.024).
#
# ## Running it
#
# A cell of radius R = 10 sites with a lamellipodium fraction φ_l = 0.05, on an
# 80 × 80 × 21 lattice, periodic in x and y. It starts as a ball of cytoplasm with a
# concentric ball of nucleus, halfway between the substrate and the lid, as in the paper's
# supplement. The cell settles onto the substrate by itself. The run is 6000 MCS long, and
# the F-actin field takes one explicit Euler step per MCS.

using Potts, PottsModels
using PottsModels.Analysis: unwrap_track
using CairoMakie

R, φ_l = 10, 0.05
sys = FortunaMigration(; name = :fortuna, lattice = fortuna_lattice(R, φ_l))
op = [fortuna_layout(R, φ_l, sys); :R => Float64(R); :φ_l => φ_l]
prob = PottsProblem(
    sys, op, (0, 6000); seed = 1, field_solver = ExplicitEuler(substeps = 1)
)
sol = solve(prob, SequentialCPM(); saveat = 0:50:6000)
nothing #hide

# The nucleus track seen from above, from its start (unwrapped across the periodic edges),
# and the lamellipodium volume relative to its target ``φ_l V``, ``V = 4πR^3/3``. The
# lamellipodium is kind 4 (the substrate is 1, the lid 2, the cytoplasm 3 and the
# nucleus 5); the model has no lookup by name. The code prints two numbers of this run: the
# first saved MCS with the lamellipodium at 90 % of its target, and the net nucleus
# displacement in units of R (the paper's runs are 10⁵ MCS long).

CairoMakie.activate!(type = "png")
L = fortuna_lattice(R, φ_l)[1]
xy = [(observe(prob, :nx, u)[1], observe(prob, :ny, u)[1]) for u in sol.u]
track = unwrap_track(xy, (L, L), true)
lam_volume(u) = sum(
    v for (v, k) in zip(volumes(u), cell_kinds(u)) if v > 0 && k == 4; init = 0
)
target = φ_l * 4π / 3 * R^3
i90 = findfirst(u -> lam_volume(u) >= 0.9 * target, sol.u)
(;
    at_90_percent = i90 === nothing ? missing : sol.t[i90],
    displacement_R = round(hypot((track[end] .- track[1])...) / R; digits = 2),
)

#-
fig = Figure(size = (720, 300))
x0, y0 = track[1]
lines(
    fig[1, 1], (first.(track) .- x0) ./ R, (last.(track) .- y0) ./ R;
    axis = (;
        xlabel = "Δx / R", ylabel = "Δy / R", aspect = DataAspect(),
        xticks = LinearTicks(3), yticks = LinearTicks(3),
    )
)
lines(
    fig[1, 2], sol.t, lam_volume.(sol.u) ./ target;
    axis = (; xlabel = "MCS", ylabel = "lamellipodium volume / target")
)
fig

# ```@raw html
# <details><summary>The model, its differences from the paper and the reference (click to open)</summary>
# ```
#
# ### The model
#
# The energy is a volume constraint per compartment (Eq. 5) with targets fixed from the
# start, ``(1 - φ_n - φ_l)V``, ``φ_n V`` and ``φ_l V``, and contact energies over the 32
# neighbors up to the fourth shell (Eq. 4, Table 1). Copies go between face neighbors.
#
# The F-actin field obeys Eq. 6,
#
# ```math
# \frac{\partial F}{\partial t} = D_F \nabla^2 F - k_\text{decay} F
#   + k_\text{source}\,[\text{lamellipodium site with a substrate face neighbor}] ,
# ```
#
# on the whole lattice, periodic in ``x`` and ``y`` with zero flux at the substrate and the
# lid planes. A copy of the lamellipodium into the medium (an extension) adds
# ``λ_F (F(\text{target}) - F(\text{source}))`` to ``ΔH`` (Eq. 7). The option
# `drive = :extension_retraction` also applies it to copies of the medium into the
# lamellipodium (retractions), as the authors' code does. Once per MCS, after
# the sweep and the field step, each cytoplasm site with a substrate face neighbor turns
# into lamellipodium with probability ``p = c\,(1 - V_3/(φ_l V))``, where ``V_3`` is the
# lamellipodium volume at the start of that pass.
#
# The observables `nx`, `ny` (the nucleus centroid), `lx`, `ly` (the lamellipodium
# centroid), `Πx`, `Πy` (the cytoplasm–nucleus polarization) and `lam_cyto` (lamellipodium
# sites touching the cytoplasm) are read on the cytoplasm cell, as in the plot above.
#
# ### Differences from the paper
#
# | | Paper | Here |
# |:--|:--|:--|
# | Protrusion rate ``c`` | not stated | 0.1, the constant of the authors' code; provisional until the reproduction calibrates it |
# | ``V_3`` in ``p`` | the lamellipodium volume | the actual volume at the start of each protrusion pass |
# | Contact energy cytoplasm–lamellipodium | 20 (Table 1) | 20 (the authors' code uses 10) |
# | Lid | no lid | a frozen lid plane at ``z = L_z`` with the contact row of the authors' code |
# | Field solver | not stated | one explicit Euler step per MCS, as in the authors' code |
# | Field boundary conditions | not stated | periodic in ``x`` and ``y``, zero flux in ``z``, on the whole lattice including the substrate and lid planes, as in the authors' code |
# | Update order | not stated | sweep, then field step, then protrusion. The field step is the same update as the authors' code (CompuCell3D diffuses and decays, then secretes; with one explicit step per MCS and a source that does not depend on ``F`` the two are identical). Secreting first would give ``F ≈ 0.1`` |
# | Drive (Eq. 7) | extensions of the lamellipodium into the medium | the same (default); `drive = :extension_retraction` adds retractions, as in the authors' code |
# | Targets | ``(1 - φ_n - φ_l)V``, ``φ_n V``, ``φ_l V`` | the same, fixed from ``t = 0`` |
# | Start | concentric spheres centered at ``(L_x/2, L_y/2, L_z/2)`` (supplement S1, p. 6), sizes not stated | the same; the cytoplasm ball sized to its target plus 216 nucleus sites, the nucleus ball to 216 sites, strict inside (the authors' code puts a cube nucleus in a ball resting on the substrate) |
# | Lattice | ``L \in [8R, 14R]``, ``L_z = 2.1R`` | ``8R``, or ``10R`` when ``R \ge 20`` and ``φ_l \ge 0.2``, truncated (the rule of the authors' code) |
# | Nucleus track | the nucleus center of mass | the same, in ``x`` and ``y`` |
#
# ### Reference
#
# ```@docs
# FortunaMigration
# fortuna_lattice
# fortuna_layout
# ```
#
# ```@raw html
# </details>
# ```
