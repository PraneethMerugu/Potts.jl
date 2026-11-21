# The F-actin field of `FortunaMigration` (Fortuna et al. 2020, Eq 6) against Base-Julia
# oracles, on the copy-blocked twin (shared/fortuna.jl) so that σ stays fixed:
# - the source recurrence F = 1 − 0.1ⁿ at a source site (k_decay = k_source = 0.9);
# - the whole lattice after each MCS equals one explicit Euler step of Eq 6 with the
#   7-point Laplacian, x and y periodic, zero flux in z;
# - negative controls: no periodic wrap, the source without the substrate test, two
#   substeps per MCS, and the secrete-then-diffuse order all give other values;
# - the split update (diffuse and decay, then add the source: CompuCell3D's order) and the
#   unsplit update agree to rounding with one step per MCS.

@testsetup module FortunaFieldSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
include(joinpath(@__DIR__, "shared", "fortuna.jl"))

# A 12 × 12 × 6 hand state: substrate at z = 1, lid at z = 6, a lamellipodium (cell 3) at
# the x seam with sites at z = 2 (sources) and z = 3 (no substrate neighbor), and a
# cytoplasm (cell 4) at z = 2 (not a lamellipodium: no source).
const SMALL = (12, 12, 6)
function small_op()
    σ = zeros(Int, SMALL)
    σ[:, :, 1] .= 1
    σ[:, :, 6] .= 2
    σ[1:3, 4:6, 2] .= 3
    σ[1:2, 4:5, 3] .= 3
    σ[11:12, 8:9, 2] .= 4
    return [
        ownership => σ, kind => [:substrate, :lid, :lamellipodium, :cytoplasm],
        cluster => [1, 2, 3, 4],
    ]
end
# kind codes of the small state's cells
const SMALL_KINDS = [SUBSTRATE, LID, LAMELLIPODIUM, CYTOPLASM]
# The field after each of `n` MCS of the twin. D_F = 0.05 and k_decay = 0.3 make the
# diffusion visible after a few steps (the explicit step stays stable: 1 − 6D_F − k > 0).
function field_run(n; D = 0.05, k = 0.3, ks = 0.9, solver = ONE_STEP)
    prob = PottsProblem(
        twin_sys(SMALL),
        [
            small_op(); :R => 3.0; :φ_l => 0.05; :c => 0.0; :D_F => D; :k_decay => k;
            :k_source => ks
        ],
        (0, n); seed = 1, field_solver = solver
    )
    integ = init(
        prob, SequentialCPM(); save_everystep = false, save_start = false, save_end = false
    )
    out = Array{Float64, 3}[]
    for _ in 1:n
        step!(integ)
        push!(out, copy(observe(prob, :F, integ.u)))
        Array(ownership(integ.u)) == entry(small_op(), ownership) ||
            error("the twin moved a site")
    end
    return out
end
# the oracle's fields after each of `n` MCS (`m` steps of dt = 1/m per MCS)
function oracle_run(n; D = 0.05, k = 0.3, ks = 0.9, m = 1, substrate = true, kw...)
    S = source_mask(entry(small_op(), ownership), SMALL_KINDS; substrate)
    F = zeros(SMALL)
    out = Array{Float64, 3}[]
    for _ in 1:n
        for _ in 1:m
            F = euler_step(F, S; D, k, ks, dt = 1 / m, kw...)
        end
        push!(out, F)
    end
    return out
end
maxdiff(a, b) = maximum(i -> maximum(abs, a[i] .- b[i]), eachindex(a))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "Fortuna field: the source recurrence" setup = [FortunaFieldSetup] tags = [
    :pottsmodels, :core,
] begin
    σ = entry(small_op(), ownership)
    src = findall(source_mask(σ, SMALL_KINDS) .== 1)
    @test length(src) == 9                          # the lamellipodium sites at z = 2
    # D_F = 0: F_n = 1 − 0.1ⁿ at each source site and nothing elsewhere, to rounding
    Fs = field_run(3; D = 0.0, k = 0.9)
    for (n, F) in enumerate(Fs)
        @test all(I -> F[I] ≈ 1 - 0.1^n, src)
        @test maximum(abs, F[setdiff(CartesianIndices(F), src)]) == 0
    end
    # the model's D_F = 1e-4: the same values within 1e-3
    Fd = field_run(3; D = 1.0e-4, k = 0.9)
    @test all(n -> all(I -> abs(Fd[n][I] - (1 - 0.1^n)) < 1.0e-3, src), 1:3)
    # the steady value of an isolated source site, 0.9/(0.9 + 6D_F), bounds every site
    @test maximum(last(field_run(40; D = 1.0e-4, k = 0.9))) < 1
end

@testitem "Fortuna field: whole-lattice explicit Euler oracle" setup = [
    FortunaFieldSetup,
] tags = [:pottsmodels, :core] begin
    n = 6
    ours = field_run(n)
    want = oracle_run(n)
    @test maxdiff(ours, want) < 1.0e-12
    # the field reached across the x seam (x = 12 next to the source at x = 1) and up to
    # the lid plane, so the periodic and closed faces are both exercised
    @test last(ours)[12, 5, 2] > 1.0e-3 && last(ours)[1, 5, 6] > 0
    # negative controls
    @test maxdiff(ours, oracle_run(n; periodic = (false, false, false))) > 1.0e-3
    @test maxdiff(ours, oracle_run(n; periodic = (true, true, true))) > 1.0e-6
    @test maxdiff(ours, oracle_run(n; substrate = false)) > 0.1
    two = field_run(n; solver = ExplicitEuler(substeps = 2))
    @test maxdiff(two, oracle_run(n; m = 2)) < 1.0e-12
    @test maxdiff(two, want) > 1.0e-3
end

@testitem "Fortuna field: split and unsplit updates agree" setup = [
    FortunaFieldSetup,
] tags = [:pottsmodels, :core] begin
    # One explicit step per MCS: diffuse and decay, then add the source (CompuCell3D's
    # DiffusionSolverFE) is F + D ΔF − kF + k_s S, the same sum as the unsplit step, so
    # the two differ by rounding only. The model's parameters, 20 MCS.
    p = (; D = 1.0e-4, k = 0.9)
    ours = field_run(20; p...)
    split = oracle_run(20; p..., order = :split)
    gap = maxdiff(ours, split)
    @info "Fortuna field: split against unsplit over 20 MCS" max_abs_difference = gap
    @test gap < 1.0e-14
    # negative control: secreting first and then diffusing gives the fixed point
    # (1 − k)k_s/k = 0.1 at an isolated source site instead of k_s/(k + 6D) ≈ 1
    late = oracle_run(20; p..., order = :secrete_first)
    @test maxdiff(ours, late) > 0.8
    @test maximum(last(late)) < 0.11 && maximum(last(ours)) > 0.99
end
