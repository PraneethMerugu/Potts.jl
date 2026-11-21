# Reproduction 14, Fortuna et al. (2020): the protocol in
# `lib/PottsModels/reproductions/data/14/protocol.jl` (every band, seed and run length) and
# its checks.
#
# Tiers:
# - always: the S-resolution oracle at Fortuna's sampling with both fits, the collapse
#   calibration, the persistence verdict's controls, the run set and the bands on hand
#   rows, and the reference transcriptions (host only, no simulation);
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full; on the PC): the short qualitative
#   tier and the calibration of c (about 1 h on 3+ threads);
# - FULL record (always): reads the one directory `reproductions/data/14/full-YYYY-MM-DD/`
#   and recomputes every row. A failing gating row must be listed in its deviations.tsv
#   and is then `@test_broken`. With no record yet the item is `@test_broken` (pending).
#   `reproductions/data/14/run_full.jl` makes the record.

@testsetup module FortunaProtocolSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using PottsModels: PottsModels
using Random: shuffle
using StableRNGs: StableRNG
using Statistics: median, std
include(joinpath(pkgdir(PottsModels), "reproductions", "data", "14", "protocol.jl"))
const P = FortunaProtocol
const A = P.A
const FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" ||
    get(ENV, "REPRO", "") == "full"
oracle_tracks(seed; kw...) = P.ou_tracks(
    StableRNG(seed); S = 0.0212, D = P.ORACLE_D, P = 8327.0, kw...
)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "Fortuna protocol: the S = 0.02 oracle with both fits" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    rows = P.oracle()
    @test length(rows) == 5 * 16 * 2
    @test length(only(oracle_tracks(1; ntracks = 1))) == 2001
    for method in P.METHODS
        for p in (8327.0, 11987.0)
            s = P.select_S(rows, method, 0.0212, p)
            @test median(abs.(s .- 0.0212)) <= 0.005
            @test std(s) <= 0.005                       # SE(S) ≪ 0.02 at N = 30
            @test median(abs.(P.select_S(rows, method, 0.0, p))) <= 0.01   # S = 0 data
        end
        s1 = P.select_S(rows, method, 0.1, 8327.0)
        @test 0.08 <= median(s1) <= 0.13                # S = 0.1 is resolved
        @test median(s1) > median(P.select_S(rows, method, 0.0212, 8327.0)) + 0.05
        @test P.method_passes(rows, method)
    end
    @test P.replicates(P.PERSISTENCE_SET) == P.N_ORACLE
    # negative control: shuffling the samples destroys the persistence and the S estimate
    for seed in 1:4
        tr = oracle_tracks(seed)
        m = A.mean_squared_displacement(tr; lags = P.FIT_LAGS)
        ms = A.mean_squared_displacement(
            [shuffle(StableRNG(100 + seed), t) for t in tr]; lags = P.FIT_LAGS
        )
        @test abs(ms[end] / ms[1] - 1) < 0.05 && m[end] / m[1] > 1000
        for method in P.METHODS
            @test !(abs(P.fit(P.FIT_DT, ms, method).S - 0.0212) <= 0.005)
        end
    end
end

@testitem "Fortuna protocol: the collapse bound on ideal and saturating MSDs" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    fails = Dict(m => 0 for m in P.METHODS)
    for seed in 1:40
        m = A.mean_squared_displacement(oracle_tracks(seed); lags = P.FIT_LAGS)
        for method in P.METHODS
            fails[method] += !P.collapse_ok(P.FIT_DT, m, P.fit(P.FIT_DT, m, method))
        end
    end
    @info "Fortuna protocol: collapse false failures of 40 ideal synthetics" fails
    @test fails[:lsq] <= 2 && fails[:paper] <= 2
    # negative control: a saturating MSD (a confined cell) fitted as Fürth fails
    exact = A.furth_mean_squared_displacement(P.FIT_DT, 0.02, 1.13e-4, 8327.0)
    cap = only(A.furth_mean_squared_displacement([2500.0], 0.02, 1.13e-4, 8327.0))
    for seed in 1:4
        m = min.(exact, cap) .* (1 .+ 0.01 .* randn(StableRNG(seed), 200))
        for method in P.METHODS
            @test !P.collapse_ok(P.FIT_DT, m, P.fit(P.FIT_DT, m, method))
        end
        fl = P.fit(P.FIT_DT, m, :lsq)
        @test P.resolved(fl) && P.collapse(P.FIT_DT, m, fl) > 0.4
    end
    # control: the exact Eq 1 curve collapses
    @test P.collapse(P.FIT_DT, exact, P.fit(P.FIT_DT, exact, :lsq)) < 1.0e-3
end

@testitem "Fortuna protocol: persistence rejects diffusion and ballistics" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    # pure diffusion must fail on S > 0.04, long-P ballistic motion on S < 0.01; a method
    # that cannot fit a case gives "not resolved", which fails too
    cases = (
        diffusion = P.replicate_msds(P.brownian_tracks(StableRNG(201); D = 1.0e-4)),
        ballistic = P.replicate_msds(
            P.ou_tracks(StableRNG(202); S = 0.0, D = 1.0e-4, P = 1.0e7)
        ),
    )
    for (name, reps) in pairs(cases), method in P.METHODS
        b = P.persistence_verdict(reps, method)
        @test !b.ok
        if P.resolved(b.f)
            @test name === :diffusion ? b.f.S > 0.04 : b.f.S < 0.01
        else
            @test !b.okS
        end
    end
    # control: the ideal synthetic at the persistence set passes
    ideal = P.replicate_msds(oracle_tracks(1))
    @test all(method -> P.persistence_verdict(ideal, method).ok, P.METHODS)
end

@testitem "Fortuna protocol: the run set, seeds and cadence" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    S = P.SETS
    @test length(S) == 68 && allunique(S)
    @test [count(s -> s[1] == R, S) for R in (10, 15, 20)] == [21, 27, 20]
    @test sum(P.replicates, S) == 700
    seeds = [P.seed(i, k) for (i, s) in enumerate(S) for k in 1:P.replicates(s)]
    @test allunique(seeds) && all(<(typemax(Int32)), seeds)
    @test count(s -> P.every(s) == 1, S) == 36
    @test length(P.FIG5_SETS) == 59 && P.FIG5_SETS ⊆ S && (10, 0.05, 200) ∉ P.FIG5_SETS
    @test P.LOOSE_ROWS ⊆ S && P.D_INFO_ROWS ⊆ S && keys(P.TABLE2_QUOTED) ⊆ S
    @test P.gates(P.PERSISTENCE_SET, :paper) && P.gates(P.PERSISTENCE_SET, :lsq)
    @test !P.gates((15, 0.1, 150), :paper) && P.gates((15, 0.1, 150), :lsq)
    @test length(P.REGIME_MAP) == 20 && all(k -> (15, k...) in S, keys(P.REGIME_MAP))
    @test count(==("confined"), values(P.REGIME_MAP)) == 3
    @test count(==("detachment"), values(P.REGIME_MAP)) == 5
    @test length(P.LOG_LAGS) == 49 && last(P.LOG_LAGS) == 1000 && length(P.LAGS) == 214
    @test all(s -> P.dims(s[1], s[2]) == fortuna_lattice(s[1], s[2]), S)
end

@testitem "Fortuna protocol: the regime rule and the bands on hand rows" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    @test P.regime([fill(true, 5); fill(false, 5)], fill(10.0, 10)) == "detachment"
    @test P.regime([fill(true, 4); fill(false, 6)], fill(10.0, 10)) == "migrating"
    @test P.regime(fill(false, 10), [fill(1.0, 9); 10.0]) == "confined"     # mean 1.9
    @test P.regime(fill(false, 10), [fill(1.0, 9); 12.0]) == "migrating"    # mean 2.1
    # a replicate detaches at zero contact while alive, after MCS 10
    @test P.detached([0, 50, 100], [0, 5, 0], [false, true, true])
    @test !P.detached([0, 50, 100], [0, 5, 0], [true, true, false])
    @test !P.detached([0, 10, 50], [5, 0, 5], [true, true, true])
    @test P.displacement_ok(9.0, 10.0, 0.4) && P.displacement_ok(19.9, 10.0, 0.1)
    @test !P.displacement_ok(21.0, 10.0, 0.1)
    ref = (S = 0.01, P = 1000.0, D = 1.0e-3)
    @test P.table2_ok((S = 0.019, P = 1490.0, D = 0.6e-3), ref)
    @test !P.table2_ok((S = 0.019, P = 1510.0, D = 0.6e-3), ref)
    @test !P.table2_ok((S = 0.021, P = 1000.0, D = 1.0e-3), ref)
    @test P.table2_ok((S = 0.01, P = 2900.0, D = 3.9e-3), ref; loose = true)
    @test !P.table2_ok((S = 0.01, P = 2900.0, D = 3.9e-3), ref)
    @test !P.table2_ok((S = NaN, P = 1000.0, D = 1.0e-3), ref)
    @test !P.table2_ok((S = 0.01, P = 1000.0, D = 1.0e-2), ref)
    @test P.table2_ok((S = 0.01, P = 1000.0, D = 1.0e-2), ref; d_info = true)
    # an unresolved fit gives NaN or false everywhere and never throws
    Δt = P.FIT_DT
    m = A.furth_mean_squared_displacement(Δt, 0.02, 1.0e-4, 5000.0)
    bad_fits = (
        (S = -0.1, P = 5000.0, D = 1.0e-4, offset = 0.0),
        (S = 1.0, P = 5000.0, D = 1.0e-4, offset = 0.0),
        (S = NaN, P = NaN, D = NaN, offset = NaN),
        (S = 0.02, P = -1.0, D = 1.0e-4, offset = 0.0),
    )
    for bad in bad_fits
        @test !P.resolved(bad)
        @test isnan(P.curve_rms(Δt, m, bad)) && isnan(P.collapse(Δt, m, bad))
        @test !P.collapse_ok(Δt, m, bad)
        @test !P.table2_ok(bad, (S = 0.02, P = 5000.0, D = 1.0e-4))
    end
    good = (S = 0.02, P = 5000.0, D = 1.0e-4, offset = 0.0)
    @test P.resolved(good) && P.curve_rms(Δt, m, good) < 1.0e-12
    # D_fast·R⁴ at R = 15, φ 0.10, λ 150, and the band around 0.127
    @test 2.83e-4 * 9.68e-3 / (1 - 9.68e-3) * 15^4 ≈ 0.14 atol = 0.001
    @test P.dfast_ok(0.14) && P.dfast_ok(0.09) && !P.dfast_ok(0.08) && !P.dfast_ok(NaN)
    @test P.eq2(50.0, 0.02) ≈ 50 - 0.98 rtol = 1.0e-12
end

@testitem "Fortuna protocol: the reference transcriptions" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    rows = P.read_tsv(joinpath(P.REFS, "table2.tsv"))
    @test length(rows) == 40
    keys2 = P.set_key.(rows)
    @test allunique(keys2) && keys2 ⊆ P.SETS
    @test all(r -> all(k -> isfinite(P.pf(r[k])) && P.pf(r[k]) > 0, ("S", "P", "D")), rows)
    row(k) = only(filter(r -> P.set_key(r) == k, rows))
    for (k, v) in P.TABLE2_QUOTED, name in (:S, :P, :D)
        want = getfield(v, name)
        want === nothing || @test P.pf(row(k)[string(name)]) == want
    end
    @test (P.LOOSE_ROWS..., P.D_INFO_ROWS...) ⊆ keys2
    # the printed 2DP/(1 − S) disagrees with S, P, D on these rows (README.md)
    last_column(k) = (r = row(k); 2 * P.pf(r["D"]) * P.pf(r["P"]) / (1 - P.pf(r["S"])))
    @test round(last_column((10, 0.2, 150)); digits = 2) == 3.66
    @test round(last_column((10, 0.2, 175)); digits = 2) == 2.8
    @test round(last_column((15, 0.3, 160)); digits = 2) == 1.92
    rows5 = P.read_tsv(joinpath(P.REFS, "fig5.tsv"))
    @test length(rows5) == 59 && sort(P.set_key.(rows5)) == sort(P.FIG5_SETS)
    @test all(r -> P.pf(r["disp"]) > 0 && P.pf(r["se"]) >= 0, rows5)
end

@testitem "Fortuna protocol FULL: the short qualitative tier and c" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions, :full] begin
    if FULL
        cal = P.qtier_calibration()
        @info "Fortuna: calibration of c" cal.scal cal.c
        ctl = isfinite(cal.c) ? P.qtier_controls(cal.c, cal.q1_disp) : (; checks = [])
        for (label, ok) in [cal.checks; ctl.checks]
            ok || @error "Fortuna short tier: check failed" label
            @test ok
        end
        isfinite(cal.c) && @info "Fortuna: ns per copy attempt" P.qtier_timing(cal.c)
    else
        @test_skip FULL
    end
end

@testitem "Fortuna protocol: the FULL record in reproductions/data/14/full-*" setup = [
    FortunaProtocolSetup,
] tags = [:pottsmodels, :reproductions] begin
    dirs = P.full_records()
    if isempty(dirs)
        @test_broken !isempty(dirs)                     # pending: the FULL runs
    else
        @test length(dirs) == 1
        length(dirs) == 1 && P.check_record(joinpath(P.DATA, only(dirs)))
    end
end
