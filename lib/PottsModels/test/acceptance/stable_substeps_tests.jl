# the automatic explicit-Euler field substep count is
# strictly inside the stability region and counts the linear reaction rate.
#
# The scheme. `ExplicitEuler()` without `substeps` advances `∂c/∂t = D Δc + f(c)` over one
# MCS of length `dt` (`mcs_duration`) in `n` substeps of `τ = dt/n`:
#     c ← c + τ (D Δ_h c + f(c)),   Δ_h = Σ_d (c[x+e_d] − 2c[x] + c[x−e_d]) / h_d².
# On a periodic lattice a Fourier mode with Laplacian eigenvalue μ ≤ 0 is multiplied per
# substep, for a linear decay f = −k c, by the exact discrete amplification factor
#     g = 1 + τ (D μ − k).
# The most negative eigenvalue is the checkerboard's (θ_d = π on every axis),
#     μ_max = −Σ_d 4/h_d²,
# so, with Λ = D Σ_d 4/h_d² + k (the spectral radius of the linear operator −D Δ_h + k),
# every mode is stable iff |1 − τ Λ| ≤ 1, i.e.
#     ρ := τ Λ = (dt/n) (D Σ_d 4/h_d² + k) ≤ 2.
# For pure diffusion that is `τ D Σ_d 1/h_d² ≤ 1/2` (2D 5-point FTCS: `τ D (1/h₁² + 1/h₂²) ≤ 1/2`).
# Today's `CorePotts.stable_substeps(D, dt, h) = max(1, ceil(Int, dt·D·Σ 2/h_d²))` gives
# `τ D Σ 2/h_d² ≤ 1`, i.e. ρ ≤ 2 with equality whenever `dt·D·Σ2/h²` is a whole number (the
# checkerboard then has g = −1 exactly: neutral, never damped), and it ignores k, so any
# decay on top of an edge case gives |g| > 1 and the field blows up in sign-alternating
# checkerboard growth.
#
# Criterion pinned here (the implementer must meet it):
#   (M) margin: ρ ≤ 1.8 = 0.9 × the edge 2, i.e. every mode's per-substep factor satisfies
#       |g| ≤ 0.8. The highest mode is damped by at least 20 % per substep (it is the
#       grid-scale noise explicit diffusion must remove, not keep ringing at |g| ≈ 1), the
#       count is robust to rounding and to a reaction bound that is not tight, and it costs
#       at most ceil(dtΛ/1.8) substeps, about 10 % over the edge count, not the doubling of
#       the positivity-preserving bound ρ ≤ 1 (performance over exactness).
#   (K) the reaction rate counts: Λ includes a bound on |∂f/∂c|. For `−k c` that is k; for
#       Merks' matrix-only decay `−k c (kind == medium)` (Eq. 6, `ε c (1 − δ_cell)`) it is also
#       k (the indicator is at most 1). The fixtures choose D and k so that the margin alone
#       (ceil(dt D Σ4/h² / 1.8)) is still unstable once k is added.
#   (C) cost cap: n ≤ max(1, ceil(dt Λ)), the count for ρ ≤ 1 (non-oscillatory, positivity
#       preserving). Any margin between ρ ≤ 1 and ρ ≤ 1.8 passes; a much larger safety factor
#       does not (the field step dominates field models' MCS time).
#
# Observable. The count is not read from internals: it is identified from the dynamics. A
# zero-cell lattice (cells are irrelevant to the field) starts from c₀ = A·checkerboard +
# B·smooth mode (cos(2π x₁/N), eigenvalue μ_s = (2cos(2π/N) − 2)/h₁²). After one MCS the
# smooth mode is multiplied by (1 − a_s/n)^n with a_s = dt(D|μ_s| + k); the unique n ≤ 20000
# that reproduces the measured factor to 1e-10 relative is the count used (distinct n differ
# by ≳ 1e-6 relative at these parameters). Then the whole field must equal the closed-form
# discrete solution for that n (both modes, every MCS), which is the analytic per-substep
# amplification check, and (M), (K), (C) are checked on n.
#
# Testsets:
#  1. Pure diffusion (`D(c) ~ Dc laplacian(c)`, no reaction term), 1D/2D/3D periodic square lattices,
#     spacing h ∈ {1, 0.5}, dt ∈ {1, 0.5, 2} (mcs_duration), D over a grid that hits today's
#     edge (dt·D·Σ2/h² whole) and points between: (M) and (C). Fails today at every edge
#     point (ρ = 2).
#  2. Diffusion with decay, uniform (`− k c`) and matrix-only (`− k c (kind == medium)`, all
#     sites medium so the oracle is still exact), at parameters where today's count is
#     unstable: (M), (K), (C), the closed-form oracle over 30 MCS, and the L2 norm never
#     grows. Today: the checkerboard grows (numbers in the report of the first version). A second
#     fixture with a live cell (the decay mask is then not uniform): no closed form, but the
#     step matrix I − τ(−DΔ_h + K), 0 ≤ K ≤ k, is symmetric with spectrum in [1 − ρ, 1], so
#     under (M) the L2 norm of the field is non-increasing every MCS (Weyl), and today it
#     grows.
#  3. An explicit `substeps = n` is a minimum that is never lowered, and where it is above
#     any count (C) allows it is the count used: field values after 4 MCS bitwise equal to
#     values recorded on the base tree (d5bfd3dc, Julia 1.12), plus an independent FTCS
#     reference to 1e-13 (which pins n without depending on operand order). Fingerprints are
#     NOT pinned: they hash the generated substep function, which the fix rewrites.
#  4. Merks (`MerksVasculogenesis`) with its recommended `ExplicitEuler(substeps = 15,
#     lower_bound = 0.0)`, zero cells (all matrix, so decay δc everywhere and no secretion), closed
#     (zero-flux) boundary: values after 3 MCS bitwise as recorded, plus the FTCS reference
#     with 15 substeps. (15 ≥ (C)'s cap ceil(0.75·8 + 0.0054) = 7, so any compliant fix
#     keeps 15.)
# Not here: hexagonal lattices, Metal, `RK4`/`Adaptive` (not field solvers).

@testsetup module StableSubstepsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const substep_EE = Potts.ExplicitEuler
const EDGE = 2.0
const MARGIN = 0.9 * EDGE
# (M): ρ ≤ 1.8
const NMAX = 20_000
# the field `c` of Field as a plain MTK PDESystem on `dims` sites of spacing `h`:
# `Dc Δc − k c` (`:uniform`), `Dc Δc − k c [medium]` (`:offcell`, its 0/1 input `medium` bound
# at `@fields`) or `Dc Δc` (`:none`); its parameters are `Dc` and `k` in every case
function field_pde(dims, h, reaction)
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y z Dc = 0.5 k = 0.0
    Potts.ModelingToolkitBase.@variables c(..) medium(..)::Bool [input = true]
    xs = (x, y, z)[1:length(dims)]
    C, M = c(t, xs...), medium(t, xs...)
    rate = reaction === :uniform ? Dc * L.laplacian(C) - k * C : reaction === :offcell ? Dc * L.laplacian(C) - k * C * M : Dc * L.laplacian(C)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(C) ~ rate], [c(0, xs...) ~ 0.0],
        L.lattice_domain(t, xs, dims; spacing = h), [t, xs...], reaction === :offcell ? [C, M] : [C], [Dc, k];
        name = :field
    )
end
# a field-only model: `reaction` ∈ (:none, :uniform, :offcell)
@potts_model Field begin
    @structural_parameters begin
        dims = (8, 8)
        h = 1.0
        dt = 1.0
        reaction = :none
    end
    @kinds medium A
    @lattice Lattice(dims; spacing = ntuple(_ -> h, length(dims)))
    if reaction === :offcell
        @fields field_pde(dims, h, reaction) (:medium => kind == medium)
    else
        @fields field_pde(dims, h, reaction)
    end
    @energy cells => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0, mcs_duration = dt)
end
substep_dot(a, b) = sum(a .* b)
substep_norm(a) = sqrt(substep_dot(a, a))
substep_cb(dims) = [iseven(sum(Tuple(I))) ? 1.0 : -1.0 for I in CartesianIndices(dims)]
smooth(dims) = [cos(2π * I[1] / dims[1]) for I in CartesianIndices(dims)]
Λdiff(D, h, nd) = D * nd * 4 / h^2
# D Σ_d 4/h² on a square lattice
substep_μs(N, h) = (2cos(2π / N) - 2) / h^2
const substep_A = 1.0
const substep_B = 0.7
substep_c0(dims) = substep_A .* substep_cb(dims) .+ substep_B .* smooth(dims)
function substep_run(
        sys, dims, T; σ = zeros(Int32, dims), kinds = Symbol[], p = (), c0 = substep_c0(dims),
        solver = substep_EE(), seed = 1
    )
    op = [ownership => σ, kind => kinds, :c => c0, p...]
    prob = PottsProblem(sys, op, (0, T); seed, field_solver = solver)
    return [Array(u.site.c) for u in solve(prob, SequentialCPM(); saveat = 1).u]
end
# the unique n ≤ NMAX with (1 − a/n)^n ≈ r (rtol 1e-10), or `nothing`
function infer(r, a)
    hits = [n for n in 1:NMAX if isapprox((1 - a / n)^n, r; rtol = 1.0e-10, atol = 1.0e-15)]
    return length(hits) == 1 ? only(hits) : nothing
end
# One fixture: identify n from MCS 1, check the closed form over every saved MCS, and return
# (n, ρ, cap, worst oracle error, growth of the L2 norm).
function case(sys, dims, h, dt, D, k, T)
    us = substep_run(sys, dims, T; p = (:Dc => D, :k => k))
    cb, s = substep_cb(dims), smooth(dims)
    Λ = Λdiff(D, h, length(dims)) + k
    a_s = dt * (D * abs(substep_μs(dims[1], h)) + k)
    r_s = substep_dot(us[2], s) / substep_dot(s, s) / substep_B
    n = infer(r_s, a_s)
    norms = substep_norm.(us)
    growth = maximum(norms[t + 1] / norms[t] for t in 1:T)
    n === nothing && return (; n, ρ = NaN, cap = 0, err = Inf, growth, r_s)
    τ = dt / n
    g_cb, g_s = 1 - τ * Λ, 1 - τ * (D * abs(substep_μs(dims[1], h)) + k)
    err = maximum(0:T) do t
        ref = substep_A * g_cb^(n * t) .* cb .+ substep_B * g_s^(n * t) .* s
        maximum(abs, us[t + 1] .- ref) / max(1.0, maximum(abs, ref))
    end
    return (; n, ρ = τ * Λ, cap = max(1, ceil(Int, dt * Λ * (1 - 1.0e-12))), err, growth, r_s)
end
const DIFF_SETUPS = [
    ((16,), 1.0, 1.0), ((16,), 0.5, 1.0), ((8, 8), 1.0, 1.0), ((8, 8), 0.5, 1.0),
    ((8, 8), 1.0, 0.5), ((8, 8), 1.0, 2.0), ((6, 6, 6), 1.0, 1.0), ((6, 6, 6), 0.5, 1.0),
]
const substep_DS = (0.05, 0.125, 0.25, 0.3, 0.5, 0.75, 1.0, 1.7, 2.5)
# (dims, h, dt, D, k, kcase): today's count is unstable at each; `kcase`: the margin alone
# (n = ceil(dt D Σ4/h² / 1.8), ignoring k) is unstable too, so (K) is what makes it pass
const DECAY_CASES = [
    ((8, 8), 1.0, 1.0, 0.5, 0.2, false),     # the ROADMAP case: today n = 2, ρ = 2.1
    ((8, 8), 1.0, 1.0, 0.45, 1.0, true),                             # today n = 2, ρ = 2.3; margin-only n = 2, ρ = 2.3
    ((16,), 1.0, 1.0, 0.5, 0.2, false),                              # today n = 1, ρ = 2.2
    ((6, 6, 6), 1.0, 1.0, 0.25, 1.2, true),                          # today n = 2, ρ = 2.1; margin-only n = 2, ρ = 2.1
    ((8, 8), 0.5, 1.0, 0.125, 1.6, true),
]
# FTCS reference: n substeps of τ = dt/n of D Δ_h c − k c·mask, periodic or zero-flux
# (the missing neighbour mirrors the site), optional clip at `lower`
function ftcs(c0, D, k, h, dt, n, T; periodic = true, mask = ones(size(c0)), lower = nothing)
    c = copy(c0); dims = size(c); τ = dt / n
    CI = CartesianIndices(dims)
    for _ in 1:(T * n)
        new = similar(c)
        for I in CI
            lap = 0.0
            for d in 1:length(dims)
                e = CartesianIndex(ntuple(j -> j == d ? 1 : 0, length(dims)))
                nb(J) = J in CI ? c[J] : periodic ? c[CartesianIndex(mod1.(Tuple(J), dims))] : c[I]
                lap += (nb(I + e) - 2c[I] + nb(I - e)) / h^2
            end
            v = c[I] + τ * (D * lap - k * c[I] * mask[I])
            new[I] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end
# a deterministic field with every mode present
substep_rich(dims) = [
    1.0 + 0.5 * (iseven(sum(Tuple(I))) ? 1 : -1) + 0.3 * cos(2π * I[1] / dims[1]) +
        0.2 * sin(1.3 * I[1] + 0.7 * I[2]^2) for I in CartesianIndices(dims)
]
# (D, k, n): an explicit substep count above any count the stability rule allows
const EXPLICIT = [(0.1, 0.1, 3), (0.1, 0.1, 5), (0.5, 0.2, 6)]
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "stable substeps: pure diffusion — the automatic count is inside the margin (ρ ≤ 1.8)" setup = [StableSubstepsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "stable substeps: pure diffusion — the automatic count is inside the margin (ρ ≤ 1.8)" begin
        for (dims, h, dt) in DIFF_SETUPS
            sys = Field(; name = :f, dims, h, dt, reaction = :none)
            for D in substep_DS
                r = case(sys, dims, h, dt, D, 0.0, 3)
                @testset "dims=$dims h=$h dt=$dt D=$D" begin
                    @test r.n !== nothing                                   # a single count explains the run
                    @test r.err ≤ 1.0e-10                                     # exact discrete amplification
                    @test r.ρ ≤ MARGIN * (1 + 1.0e-12)                   # (M)
                    @test r.n ≤ r.cap                                       # (C)
                    @test r.growth ≤ 1 + 1.0e-12
                end
            end
        end
    end
end

@testitem "stable substeps: diffusion with decay stays stable and matches the discrete oracle" setup = [StableSubstepsSetup] tags = [:pottsmodels, :acceptance] begin
    # today n = 2, ρ = 2.8; margin-only n = 3, ρ ≈ 1.87
    @testset "stable substeps: diffusion with decay stays stable and matches the discrete oracle" begin
        for reaction in (:uniform, :offcell), (dims, h, dt, D, k, kcase) in DECAY_CASES
            sys = Field(; name = :f, dims, h, dt, reaction)
            r = case(sys, dims, h, dt, D, k, 30)
            @testset "$reaction dims=$dims h=$h D=$D k=$k" begin
                # the fixture really is past the margin without k (K)
                nd = length(dims)
                @test (
                    ceil(Int, dt * Λdiff(D, h, nd) / MARGIN) * MARGIN <
                        dt * (Λdiff(D, h, nd) + k)
                ) == kcase
                @test dt * (Λdiff(D, h, nd) + k) / max(1, ceil(Int, dt * D * nd * 2 / h^2)) > EDGE   # today unstable
                @test r.n !== nothing
                @test r.err ≤ 1.0e-10
                @test r.ρ ≤ MARGIN * (1 + 1.0e-12)                       # (M) with k counted (K)
                @test r.n ≤ r.cap                                           # (C)
                @test r.growth ≤ 1 + 1.0e-12                                  # bounded: the L2 norm never grows
            end
        end
        # matrix-only decay with a live cell (non-uniform mask): the L2 norm is non-increasing
        for (dims, h, dt, D, k, _) in DECAY_CASES[1:2]
            sys = Field(; name = :f, dims, h, dt, reaction = :offcell)
            σ = zeros(Int32, dims); σ[3:4, 3:4] .= 1
            us = substep_run(sys, dims, 30; σ, kinds = [:A], p = (:Dc => D, :k => k), c0 = substep_cb(dims), seed = 7)
            norms = substep_norm.(us)
            @testset "offcell with a cell D=$D k=$k" begin
                @test all(t -> norms[t + 1] ≤ norms[t] * (1 + 1.0e-12), 1:30)
                @test norms[end] ≤ norms[1]
            end
        end
    end
end

@testitem "stable substeps: an explicit substeps = n matches the FTCS oracle" setup = [StableSubstepsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "stable substeps: an explicit substeps = n matches the FTCS oracle" begin
        dims = (8, 8)
        sys = Field(; name = :f, dims, reaction = :uniform)
        for (D, k, n) in EXPLICIT
            @test n > max(1, ceil(Int, Λdiff(D, 1.0, 2) + k))          # above any count (C) allows
            us = substep_run(sys, dims, 4; p = (:Dc => D, :k => k), c0 = substep_rich(dims), solver = substep_EE(substeps = n))
            @test us[end] ≈ ftcs(substep_rich(dims), D, k, 1.0, 1.0, n, 4) rtol = 1.0e-13
        end
    end
end

@testitem "stable substeps: Merks with ExplicitEuler(substeps = 15, lower_bound = 0.0) matches the FTCS oracle" setup = [StableSubstepsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "stable substeps: Merks with ExplicitEuler(substeps = 15, lower_bound = 0.0) matches the FTCS oracle" begin
        N = 8
        sys = MerksVasculogenesis(; name = :m, lattice = (N, N))
        v(m, x) = cos(π * m * (x - 0.5) / N)                   # zero-flux eigenvectors
        c0 = [1.0 + 0.4 * v(N - 1, x) * v(N - 1, y) + 0.3 * v(1, x) + 0.05 * sin(1.3x + 0.7y^2) for x in 1:N, y in 1:N]
        op = [ownership => zeros(Int32, N, N), kind => Symbol[], :c => c0]
        prob = PottsProblem(sys, op, (0, 3); field_solver = substep_EE(substeps = 15, lower_bound = 0.0))
        c = Array(solve(prob, SequentialCPM(); saveat = 1).u[end].site.c)
        @test c ≈ ftcs(c0, 0.75, 5.4e-3, 1.0, 1.0, 15, 3; periodic = false, lower = 0.0) rtol = 1.0e-13
    end
end
