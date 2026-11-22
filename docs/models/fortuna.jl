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
# - G. L. Thomas, I. Fortuna, G. C. Perrone, F. Graner and R. M. C. de Almeida,
#   "Shape–velocity correlation defines polarization in migrating cell simulations",
#   *Physica A* **587**, 126511 (2022),
#   doi:[10.1016/j.physa.2021.126511](https://doi.org/10.1016/j.physa.2021.126511). The
#   [polarization study](@ref fortuna-polarization) below.
#
# ## Running it
#
# A cell of radius R = 10 sites with a lamellipodium fraction φ_l = 0.05, on an
# 80 × 80 × 21 lattice, periodic in x and y. It starts as in the paper's supplement: a
# ball of radius R resting on the substrate, with a concentric ball of nucleus inside.
# The lid cuts the top layer of the ball. The volumes then relax to their targets. The
# run is 6000 MCS long, and the F-actin field takes one explicit Euler step per MCS.

using Potts, PottsModels
using PottsModels.Analysis: unwrap_track
using CairoMakie

R, φ_l = 10, 0.05
sys = FortunaMigration(; name = :fortuna, lattice = fortuna_lattice(R, φ_l))
op = [fortuna_layout(R, sys); :R => Float64(R); :φ_l => φ_l]
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
# | Start | concentric spheres centered at ``(L_x/2, L_y/2, L_z/2)`` (supplement S1, p. 6), sizes not stated | the same; the outer ball of radius R (the whole cell volume) and the nucleus ball of 216 sites, strict inside, with the center R above the substrate's top face so that the lowest layer is z = 2 for every R (tangent in the continuum; the center at L_z/2 + 1 left an empty layer at R = 20); the lid cuts the top layer at R = 10 and 15; the volumes relax to the fixed targets (the authors' code puts a cube nucleus in a ball resting on the substrate) |
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

#
# ## [The polarization study](@id fortuna-polarization)
#
# Thomas et al. (2022) ask which polarization vector of the same model best predicts where
# the cell moves next. Their choice is ``Π_{CN-N}``, from the nucleus to the center of mass
# of cytoplasm and nucleus together (the `Πx`, `Πy` observables). Their variant puts the
# F-actin source on every lamellipodium site and starts from a cubic nucleus. Both are
# options of the same model:

sys_p = FortunaMigration(;
    name = :fortuna, lattice = fortuna_lattice(R, φ_l), factin_source = :all_lamellipodium,
)
op_p = [fortuna_layout(R, sys_p; nucleus = :cube); :R => Float64(R); :φ_l => φ_l]
prob_p = PottsProblem(
    sys_p, op_p, (0, 4000); seed = 2, field_solver = ExplicitEuler(substeps = 1)
)
integ = init(prob_p, SequentialCPM(); save_everystep = false)
obs(name) = observe(prob_p, name, integ.u)[1]
n_xy, Π = NTuple{2, Float64}[], NTuple{2, Float64}[]
for t in 1:4000
    step!(integ)
    t > 1000 || continue                  # the paper's 1000-MCS warm-up
    push!(n_xy, (obs(:nx), obs(:ny)))
    push!(Π, (obs(:Πx), obs(:Πy)) ./ R)
end
nothing #hide

# The interval matters. Over a short interval the lattice noise hides the motion and the
# mean speed ``⟨u⟩_δ`` diverges as ``δ → 0``. The speed along the polarization,
# ``⟨u_∥⟩_δ = ⟨Π \cdot u⟩``, stays finite (Thomas et al., Figs. 3B and 7D).
# `polarization_statistics` gives both, and the correlation index ``ξ`` (Eq. 14), for one
# interval. The paper's interval is ``Δτ_\text{opt}``, where the slope of the modified
# Fürth MSD is steepest (Eq. 12): `optimal_interval(S)` returns it in units of the
# persistence time ``P``. This run is short and in lattice units, so the plot only shows
# the shape; it plots ``Π̂ \cdot u`` (`unit = true`) so that both curves are speeds.

using PottsModels.Analysis: polarization_statistics
track_p = [p ./ R for p in unwrap_track(n_xy, (L, L), true)]
lags = unique(round.(Int, exp10.(range(0, 3; length = 13))))
stats = [polarization_statistics(Π, track_p, l) for l in lags]
nothing #hide

#-
fig_p = Figure(size = (720, 300))
ax = Axis(
    fig_p[1, 1]; xscale = log10, yscale = log10, xlabel = "δ (MCS)", ylabel = "R / MCS"
)
lines!(ax, lags, [s.u for s in stats]; label = "⟨u⟩")
along = [polarization_statistics(Π, track_p, l; unit = true).u_parallel for l in lags]
lines!(ax, lags, abs.(along); label = "|⟨Π̂ · u⟩|")
axislegend(ax; position = :lb)
lines(
    fig_p[1, 2], lags, [s.ξ for s in stats];
    axis = (; xscale = log10, xlabel = "δ (MCS)", ylabel = "ξ (CN−N)")
)
fig_p

# ```@raw html
# <details><summary>The polarization study: analysis, protocol and differences (click to open)</summary>
# ```
#
# ### Analysis
#
# The functions are in `PottsModels.Analysis` and take plain vectors of 2D points.
# `furth_exponent(Δτ, S)` is the MSD slope ``α`` of Eq. 12, `optimal_interval(S)` its
# maximum ``(Δτ_\text{opt}, α_\text{opt})``, and `max_slope_interval(Δt, m)` the steepest
# slope of a measured MSD without a fit. `mean_velocity` is Eq. 13, and
# `polarization_statistics` gives ``⟨u⟩``, ``ε`` (Eq. 15), ``ξ`` (Eq. 14), ``σ_θ`` and
# ``⟨u_∥⟩`` (Eq. 16) for one interval, pooled over the replicates. ``Π_{L-N}`` and
# ``Π_{L-CN} = Π_{L-N} - Π_{CN-N}`` come from the centroid observables `lx`, `ly`, `nx`,
# `ny` by minimum image.
#
# ### Reproduction
#
# The protocol is `lib/PottsModels/reproductions/data/14/polarization_protocol.jl`: the 36
# sets of the paper (``λ_F \in \{150, 175, 200\}``, ``φ_l \in \{0.05, 0.10, 0.20, 0.30\}``,
# ``R \in \{10, 15, 20\}``), 10 replicates of ``10^5`` MCS each, every MCS recorded, and
# the bands for Figs. 3–7, fixed before the runs. `run_polarization.jl` makes the tracks
# and `analyze_polarization.jl` the record. The record and its videos come later. The
# ``Δτ_\text{opt}`` rows pass within the sampling spread of both fits (a bootstrap over our
# replicates and the spread of one ideal fit at the set's ``S``), and the ``u_∥`` rows within
# 10 % or the replicate standard error; the record also gives ``u_∥`` on the CN track.
#
# ### Differences from the paper
#
# | | Paper | Here |
# |:--|:--|:--|
# | F-actin source (Eq. 9) | every lamellipodium site | the same, `factin_source = :all_lamellipodium` (Fortuna et al. and the authors' code restrict it to lamellipodium sites on the substrate, the default) |
# | Start | a spherical cell resting on the substrate with a cubic nucleus, no lamellipodium; cube size not stated | the outer ball of the model above with a 6³ nucleus cube (`fortuna_layout(R, sys; nucleus = :cube)`), the size of the authors' cube; with ``m = L/2 + 1`` it spans ``m-3{:}m+2`` in ``x`` and ``y`` (half a site off center) and ``R-1{:}R+4`` in ``z``; the authors' code centers it with `range(-3, 3)` on an integer point on all three axes, so ``z`` differs by half a site |
# | Drive (Eq. 8) | on the lamellipodium–medium boundary, direction not stated | extensions only, as Eq. 7 of Fortuna et al.; `drive = :extension_retraction` adds retractions |
# | Other parameters | "as in Ref. [9]" | those of the model above, ``c`` included (the reproduction uses the calibrated ``c``) |
# | Warm-up | 1000 MCS | the same, in the protocol |
# | Tracked point ``ρ`` | "the cell position", not defined | the nucleus center of mass in ``x`` and ``y``, the point Fortuna et al. fit ``S``, ``P``, ``D`` on |
# | Natural units | ``τ = t/P``, ``ρ = r/\sqrt{2DP/(1-S)}`` with the fit of each set | the same, with the modified Fürth fit of the Fortuna reproduction |
# | ``ξ`` (Eq. 14) | ``⟨\cos θ⟩/⟨\sin θ⟩`` | ``θ \in [0, π]`` unsigned, so ``\sin θ \ge 0``; ``σ_θ`` uses the signed angle |
# | ``u_∥`` (Eq. 16) | ``Π \cdot Δρ/δ`` | the same, not divided by ``\lvert Π \rvert``; `unit = true` divides |
# | Fig. 5 power laws | fitted over the ``S`` of every simulation of Fortuna et al. | `optimal_interval` matches the ``α_\text{opt}`` law within 1 % at the ``S`` of their Table 2; the ``Δτ_\text{opt}`` law differs by up to 16 % at the smallest ``S``: it is a least-squares fit in linear space over the same ``S``, which weights the large ``Δτ`` (our refit gives ``1.948\,S^{0.4575}``, ``R^2 = 0.9993``); the tests use 3 % for the ``α_\text{opt}`` law and 20 % for the ``Δτ_\text{opt}`` law, while both printed values (0.048, 0.672) agree to 0.001 |
#
# ```@raw html
# </details>
# ```
