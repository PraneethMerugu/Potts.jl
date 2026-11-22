# `FortunaMigration` (Fortuna et al. 2020, Biophys. J. 118:2801): the model, its start and
# its mechanisms against oracles that read σ alone (shared/fortuna.jl). The F-actin field
# has its own file, fortuna_field_tests.jl.
# - build: the lattice rule, the compiled model and its copy-blocked twin;
# - Table 1: the parameters and the contact matrix (J_cytoplasm–lamellipodium = 20);
# - the start: the concentric balls of the supplement, sized to the cytoplasm target plus
#   the 216 nucleus sites, for the twelve (R, φ_l) of the paper;
# - the protrusion pass equals a counter-addressed draw oracle; p > 1, V₃ ≥ φ_l V and the
#   φ_l = 0 NaN path; the field step comes before the protrusion pass;
# - the drive is λ_F (F(target) − F(source)) on lamellipodium extensions into the medium
#   (and on retractions in the `:extension_retraction` variant), 0 otherwise;
# - a short run: fixed targets, volumes against σ, the brute-force ΔH, determinism, and the
#   controls c = 0 and φ_l = 0 (no lamellipodium);
# - the observables across the periodic seam.

@testsetup module FortunaModelSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
include(joinpath(@__DIR__, "shared", "selfcheck.jl"))
include(joinpath(@__DIR__, "shared", "fortuna.jl"))
using PottsModels.Analysis: unwrap_track

const R10 = fortuna_lattice(10, 0.05)                 # (80, 80, 21)
default_op(sys = model_sys(R10)) = fortuna_layout(10, 0.05, sys)
default_problem(; kw...) = fortuna_problem(model_sys(R10), default_op(), 10, 0.05; kw...)

# the default run, seed 1, 500 MCS saved every 50: shared by the run items
const RUN = Dict{Symbol, Any}()
function default_run()
    return get!(RUN, :sol) do
        RUN[:prob] = default_problem(; tspan = (0, 500), seed = 1)
        solve(RUN[:prob], SequentialCPM(); saveat = 50)
    end
end

# The start by hand: the strict balls of radius r₀ (cytoplasm) and r_n (nucleus) around
# (L/2 + 1, L/2 + 1, L_z/2 + 1)
start_radius(R, φ_l) = cbrt(((1 - 0.15 - φ_l) * ball_volume(R) + 216) / (4π / 3))
function oracle_ball(R, φ_l, r)
    L, _, Lz = fortuna_lattice(R, φ_l)
    c = (L / 2 + 1, L / 2 + 1, Lz / 2 + 1)
    return Set(
        (x, y, z) for x in 1:L, y in 1:L, z in 1:Lz
            if sqrt((x - c[1])^2 + (y - c[2])^2 + (z - c[3])^2) < r * (1 - 1.0e-12)
    )
end
# the twelve (R, φ_l) of the paper (Table 2, Fig 5)
const START = [(R, φ_l) for R in (10, 15, 20) for φ_l in (0.05, 0.1, 0.2, 0.3)]
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "FortunaMigration builds; the lattice rule" setup = [FortunaModelSetup] tags = [
    :pottsmodels, :core,
] begin
    @test fortuna_lattice(10, 0.05) == (80, 80, 21)
    @test fortuna_lattice(15, 0.3) == (120, 120, 31)
    @test fortuna_lattice(20, 0.1) == (160, 160, 42)
    @test fortuna_lattice(20, 0.2) == (200, 200, 42)    # int(10R) when R ≥ 20, φ_l ≥ 0.2
    @test fortuna_lattice(10, 0.3) == (80, 80, 21)
    @test mtkcompile(model_sys(R10)) isa CompiledPottsSystem
    @test mtkcompile(twin_sys(R10)) isa CompiledPottsSystem
    @test Potts.lattice(FortunaMigration(; name = :d)).dims == (120, 120, 31)
    @test_throws ArgumentError FortunaMigration(; name = :d, drive = :retraction_only)
    @test occursin("Fortuna", string(@doc FortunaMigration))
end

@testitem "FortunaMigration: Table 1 parameters and contacts" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    prob = default_problem()
    p = prob.p
    @test (p.φ_n, p.T, p.λ, p.λ_F, p.c) == (0.15, 100.0, 10.0, 150.0, 0.1)
    @test (p.D_F, p.k_decay, p.k_source) == (1.0e-4, 0.9, 0.9)
    @test p.R == 10.0 && p.φ_l == 0.05
    # the hand matrix in the @kinds order; unlisted pairs (the diagonal too) are 0
    ix = Dict(k => i for (i, k) in enumerate(KINDS))
    J = zeros(6, 6)
    for ((a, b), v) in (
            (:medium, :substrate) => 20, (:medium, :cytoplasm) => 20,
            (:medium, :lamellipodium) => 40 / 3, (:medium, :nucleus) => 100,
            (:substrate, :cytoplasm) => 20, (:substrate, :lamellipodium) => 20 / 3,
            (:substrate, :nucleus) => 100, (:cytoplasm, :lamellipodium) => 20,
            (:cytoplasm, :nucleus) => 20, (:lamellipodium, :nucleus) => 40,
            (:medium, :lid) => -20, (:lid, :cytoplasm) => 20,
            (:lid, :lamellipodium) => 40 / 3, (:lid, :nucleus) => 100,
        )
        J[ix[a], ix[b]] = J[ix[b], ix[a]] = v
    end
    @test Matrix(p.J) == J
    # Table 1's J_cytoplasm–lamellipodium, not the authors' code's 10
    @test p.J[ix[:cytoplasm], ix[:lamellipodium]] == 20
    @test length(prob.contact) == 32                    # the fourth neighbor shell
    @test prob.lattice.periodic == (true, true, false)
end

@testitem "FortunaMigration: the start at the paper's twelve (R, φ_l)" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    @testset "R = $R, φ_l = $φ_l" for (R, φ_l) in START
        dims = fortuna_lattice(R, φ_l)
        L, _, Lz = dims
        ball = oracle_ball(R, φ_l, start_radius(R, φ_l))
        nucleus = oracle_ball(R, φ_l, cbrt(216 / (4π / 3)))
        @test nucleus ⊆ ball && 200 <= length(nucleus) <= 216
        ncyto = length(ball) - length(nucleus)
        # sized to the target: within the protocol's 2 % volume band (the lattice count of
        # a ball off the site grid differs from its volume by up to about 1.7 % here)
        tcyto = (1 - 0.15 - φ_l) * ball_volume(R)
        @test abs(ncyto - tcyto) < 0.02 * tcyto
        # the ball sits between the planes without touching either
        @test 2 < minimum(x[3] for x in ball) && maximum(x[3] for x in ball) < Lz
        # the layout against the oracle
        sys = FortunaMigration(; name = :fortuna, lattice = dims)
        op = fortuna_layout(R, φ_l, sys)
        σ = entry(op, ownership)
        @test size(σ) == dims
        @test entry(op, kind) == [:cytoplasm, :nucleus, :substrate, :lid]
        @test entry(op, cluster) == [1, 1, 3, 4]
        @test Set(Tuple.(findall(==(1), σ))) == setdiff(ball, nucleus)
        @test Set(Tuple.(findall(==(2), σ))) == nucleus
        @test all(==(3), view(σ, :, :, 1)) && all(==(4), view(σ, :, :, Lz))
        @test count(==(0), σ) == prod(dims) - length(ball) - 2 * L^2
        # concentric: both centroids sit on the center
        c = (L / 2 + 1, L / 2 + 1, Lz / 2 + 1)
        @test all(isapprox.(oracle_centroid(σ, (1,)), c; atol = 1.0e-9))
        @test all(isapprox.(oracle_centroid(σ, (2,)), c; atol = 1.0e-9))
    end
    # negative control: a ball of radius R (the authors' code) is far above the cytoplasm
    # target at R = 10
    @test length(oracle_ball(10, 0.05, 10.0)) - 216 - 0.8 * ball_volume(10) > 500
    # the problem: targets from the kinds, no lamellipodium yet
    u0 = default_problem().u0
    @test volumes(u0)[2:4] == [216, 6400, 6400]
    @test cell_kinds(u0)[1:4] == [CYTOPLASM, NUCLEUS, SUBSTRATE, LID]
    @test isempty(alive(u0, LAMELLIPODIUM))
    @test u0.cell.V_target[1] ≈ 0.8 * ball_volume(10) rtol = 1.0e-12
    @test u0.cell.V_target[2] ≈ 0.15 * ball_volume(10) rtol = 1.0e-12
    @test observe(default_problem(), :lam_births, u0)[1] == 0
end

@testitem "FortunaMigration: the protrusion pass equals the draw oracle" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    sys = twin_sys(R10)
    op = resting_op(sys, 10, 0.05)
    # the shipped start has no candidate: the ball does not touch the substrate
    shipped = fortuna_problem(sys, default_op(sys), 10, 0.05).u0
    @test isempty(oracle_pass(shipped, 0, 1; c = 0.1, φ_l = 0.05, R = 10)[2])
    for seed in 1:4
        prob = fortuna_problem(sys, op, 10, 0.05; tspan = (0, 4), seed)
        sol = solve(prob, SequentialCPM(); saveat = 1)
        total = 0
        for t in 0:3
            u, w = sol.u[t + 1], sol.u[t + 2]
            want, cand, p = oracle_pass(u, t, seed; c = 0.1, φ_l = 0.05, R = 10)
            t == 0 && @test p == 0.1 && length(cand) == 57
            moved = findall(vec(Array(ownership(u)) .!= Array(ownership(w))))
            @test Set(moved) == Set(want)
            total += length(want)
            lam = alive(w, LAMELLIPODIUM)
            if total > 0
                @test length(lam) == 1 && volumes(w)[only(lam)] == total
                @test w.cell.cluster[only(lam)] == w.cell.cluster[1]
                @test w.cell.V_target[only(lam)] ≈ 0.05 * ball_volume(10) rtol = 1.0e-12
            end
            # one creation, then the same cell grows
            @test observe(prob, :lam_births, w)[1] == (total > 0)
        end
    end
    # the oracle is not vacuous: the seed changes the converted set, and p = 0.1 converts
    # some candidates but not all
    u0 = fortuna_problem(sys, op, 10, 0.05).u0
    pass_sites(seed) = Set(first(oracle_pass(u0, 0, seed; c = 0.1, φ_l = 0.05, R = 10)))
    sets = [pass_sites(seed) for seed in 1:4]
    @test allunique(sets) && all(s -> 0 < length(s) < 57, sets)
end

@testitem "FortunaMigration: p above 1, V₃ at the target and φ_l = 0" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    sys = twin_sys(R10)
    op = resting_op(sys, 10, 0.05)
    go(o, tend; p) = solve(
        fortuna_problem(sys, o, 10, 0.05; tspan = (0, tend), p), SequentialCPM();
        saveat = 1
    )
    cytoplasm_at_z2(u) = count(==(1), view(Array(ownership(u)), :, :, 2))
    # c = 2.5: p is above 1 at the first pass, so every candidate converts
    s = go(op, 1; p = (:c => 2.5,))
    @test cytoplasm_at_z2(s.u[2]) == 0
    @test volumes(s.u[2])[only(alive(s.u[2], LAMELLIPODIUM))] == 57
    # V₃ ≥ φ_l V gives p ≤ 0: nothing converts, even at c = 2.5
    σ = copy(entry(op, ownership))
    up = [I for I in CartesianIndices(σ) if σ[I] == 1 && 3 <= I[3] <= 5]
    @test length(up) > 0.05 * ball_volume(10)
    σ[up] .= 5
    full = [
        ownership => σ, kind => [:cytoplasm, :nucleus, :substrate, :lid, :lamellipodium],
        cluster => [1, 1, 3, 4, 1],
    ]
    sh = go(full, 3; p = (:c => 2.5,))
    @test all(u -> Array(ownership(u)) == σ, sh.u)
    # φ_l = 0 and no lamellipodium: p = c (1 − 0/0) is NaN, which converts nothing
    s0 = go(op, 3; p = (:c => 2.5, :φ_l => 0.0))
    @test all(u -> Array(ownership(u)) == Array(ownership(s0.u[1])), s0.u)
    # control: a small φ_l converts every candidate
    sε = go(op, 1; p = (:c => 2.5, :φ_l => 1.0e-3))
    @test cytoplasm_at_z2(sε.u[2]) == 0
end

@testitem "FortunaMigration: the field step comes before the protrusion pass" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    # the twin at c = 2.5 converts every cytoplasm site at z = 2 in the first pass. The
    # field step of MCS 1 runs before it, with no source, so F = 0 there after MCS 1; the
    # step of MCS 2 adds k_source = 0.9 to F = 0. Protrusion first would give 0.9 after
    # MCS 1.
    sys = twin_sys(R10)
    prob = fortuna_problem(
        sys, resting_op(sys, 10, 0.05), 10, 0.05; tspan = (0, 2), p = (:c => 2.5,)
    )
    sol = solve(prob, SequentialCPM(); saveat = 1)
    lam(u) = findall(==(only(alive(u, LAMELLIPODIUM))), vec(Array(ownership(u))))
    sites = lam(sol.u[2])
    @test !isempty(sites) && all(i -> CartesianIndices(R10)[i][3] == 2, sites)
    @test lam(sol.u[3]) == sites                        # no candidate is left at MCS 2
    @test all(==(0), vec(observe(prob, :F, sol.u[2]))[sites])
    @test all(≈(0.9; atol = 1.0e-12), vec(observe(prob, :F, sol.u[3]))[sites])
end

@testitem "FortunaMigration: the F-actin drive" setup = [FortunaModelSetup] tags = [
    :pottsmodels, :core,
] begin
    # a hand lamellipodium, 3 MCS without protrusion, so F is about 1 on the
    # lamellipodium sites at z = 2 and small elsewhere
    sys = model_sys(R10)
    op = hand_op(resting_op(sys, 10, 0.05))
    prob = fortuna_problem(sys, op, 10, 0.05; p = (:c => 0.0,))
    u = solve(remake(prob; tspan = (0, 3)), SequentialCPM()).u[end]
    F = observe(prob, :F, u)
    @test maximum(F) > 0.99
    kd = cell_kinds(u)
    lam(c) = c != 0 && kd[c] == LAMELLIPODIUM
    props = boundary_proposals(prob, u)
    extension(p) = lam(p.new) && p.old == 0
    retraction(p) = lam(p.old) && p.new == 0
    gain(p) = 150.0 * (F[p.target] - F[p.source])
    # the default, Eq 7 as printed: extensions only
    @test maximum(p -> abs(drive(prob, u, p) - extension(p) * gain(p)), props) < 1.0e-6
    # extension down the F gradient is favored; retractions and other copies get 0
    ext = filter(p -> extension(p) && F[p.source] - F[p.target] > 0.5, props)
    ret = filter(p -> retraction(p) && F[p.target] - F[p.source] > 0.5, props)
    other = filter(p -> !lam(p.old) && !lam(p.new), props)
    @test !isempty(ext) && !isempty(ret) && !isempty(other)
    @test all(p -> drive(prob, u, p) < -75, ext)
    @test all(p -> abs(drive(prob, u, p)) < 1.0e-6, [ret; other])
    # λ_F scales it and λ_F = 0 removes it
    p0 = remake(prob; p = [:λ_F => 0.0])
    @test all(p -> abs(drive(p0, u, p)) < 1.0e-6, ext)
    p75 = remake(prob; p = [:λ_F => 75.0])
    @test all(p -> drive(p75, u, p) ≈ drive(prob, u, p) / 2, ext)
    # the variant (the authors' code) also opposes retractions up the gradient
    sys_er = FortunaMigration(;
        name = :fortuna, lattice = R10, drive = :extension_retraction
    )
    per = fortuna_problem(sys_er, op, 10, 0.05; p = (:c => 0.0,))
    both(p) = (extension(p) || retraction(p)) * gain(p)
    @test maximum(p -> abs(drive(per, u, p) - both(p)), props) < 1.0e-6
    @test all(p -> drive(per, u, p) > 75, ret)
    @test all(p -> abs(drive(per, u, p)) < 1.0e-6, other)
end

@testitem "FortunaMigration: a short run" setup = [FortunaModelSetup] tags = [
    :pottsmodels, :core,
] begin
    sol = default_run()
    prob = RUN[:prob]
    @test Symbol(sol.retcode) === :Success && sol.t[end] == 500
    # the targets stay at their t = 0 values (no transfer)
    @test all(u -> u.cell.V_target[1:2] == sol.u[1].cell.V_target[1:2], sol.u)
    # a lamellipodium by MCS 50, in the cell's cluster, with the target φ_l V
    @test sol.t[2] == 50 && length(alive(sol.u[2], LAMELLIPODIUM)) == 1
    u = sol.u[end]
    l = only(alive(u, LAMELLIPODIUM))
    @test u.cell.cluster[l] == u.cell.cluster[1]
    @test u.cell.V_target[l] ≈ 0.05 * ball_volume(10) rtol = 1.0e-12
    @test observe(prob, :lam_births, u)[1] >= 1
    # volumes against σ; the planes never move
    σ = Array(ownership(u))
    v = volumes(u)
    @test v == [count(==(c), σ) for c in eachindex(v)]
    @test v[3] == v[4] == 6400
    @test length(alive(u, CYTOPLASM)) == 1 && length(alive(u, NUCLEUS)) == 1
    # volumes near their targets after 500 MCS (within 10 %)
    @test all(c -> abs(v[c] / u.cell.V_target[c] - 1) < 0.1, (1, 2))
    # the derived ΔH against the brute-force energy difference
    @test selfcheck(prob; n = 100) < 1.0e-9
    # the same seed gives the same run; another seed another
    long = remake(prob; tspan = (0, 300))
    b = solve(long, SequentialCPM(); save_everystep = false).u[end]
    @test Array(ownership(sol.u[7])) == Array(ownership(b))
    @test observe(prob, :F, sol.u[7]) == observe(prob, :F, b)
    c = solve(
        remake(prob; tspan = (0, 300), seed = 2), SequentialCPM(); save_everystep = false
    ).u[end]
    @test Array(ownership(sol.u[7])) != Array(ownership(c))
end

@testitem "FortunaMigration: c = 0 and φ_l = 0 make no lamellipodium" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    for p in ((:c => 0.0,), (:φ_l => 0.0,))
        s = solve(default_problem(; tspan = (0, 300), p), SequentialCPM(); saveat = 50)
        @test Symbol(s.retcode) === :Success
        @test all(u -> isempty(alive(u, LAMELLIPODIUM)), s.u)
        @test observe(s, :lam_births)[end][1] == 0
    end
end

@testitem "FortunaMigration: observables across the seam" setup = [
    FortunaModelSetup,
] tags = [:pottsmodels, :core] begin
    sys = model_sys(R10)
    op = hand_op(resting_op(sys, 10, 0.05); shift = 3)  # Π ≠ 0
    σ0 = entry(op, ownership)
    base = fortuna_problem(sys, op, 10, 0.05)
    Πh = oracle_polarization(σ0, 1, 2)
    @test abs(Πh[1]) > 1.5
    frames = NTuple{2, Float64}[]
    for k in 0:15                                       # x crosses the seam (105 > 80)
        σ = circshift(σ0, (7k, 3k, 0))
        prob = remake(base; u0 = [ownership => σ; op[2:3]])
        u = prob.u0
        o(x) = observe(prob, x, u)[1]
        push!(frames, (o(:nx), o(:ny)))
        @test all(isapprox.(frames[end], oracle_centroid(σ, (2,))[1:2]; atol = 1.0e-9))
        @test all(
            isapprox.((o(:lx), o(:ly)), oracle_centroid(σ, (5,))[1:2]; atol = 1.0e-9)
        )
        @test all(isapprox.((o(:Πx), o(:Πy)), Πh; atol = 1.0e-9))
        @test o(:lam_cyto) == oracle_lam_cyto(σ, 5, 1)
    end
    @test any(k -> frames[k + 1][1] < frames[k][1], 1:15)   # the raw track jumps
    tr = unwrap_track(frames, (80, 80), true)
    @test all(k -> all(isapprox.(tr[k + 1] .- tr[1], (7.0k, 3.0k); atol = 1.0e-9)), 0:15)
    # the shipped start: the balls are concentric, so Π = 0
    prob0 = default_problem()
    @test observe(prob0, :Πx)[1] ≈ 0 atol = 1.0e-9
    @test observe(prob0, :Πy)[1] ≈ 0 atol = 1.0e-9
    # a lamellipodium cut off from the cytoplasm reads lam_cyto = 0
    σd = copy(σ0)
    σd[σd .== 5] .= 1
    σd[60:62, 40:42, 2] .= 5
    @test all(==(0), σ0[59:63, 39:43, 2:3])            # control: medium around it
    pd = remake(base; u0 = [ownership => σd; op[2:3]])
    @test observe(pd, :lam_cyto)[1] == 0 == oracle_lam_cyto(σd, 5, 1)
    @test oracle_lam_cyto(σ0, 5, 1) > 0                 # control: attached
end
