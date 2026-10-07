# P6.1h (ROADMAP Phase 6; D-151 outcome): reproduction 09, Graner & Glazier, V-PRE7, the
# sorting temperature regimes of PRE Fig. 15 (09c p.2143–2144). The pre-registered target is
# spec 09 §9.1 V-PRE7 (docs/design/research/model-specs/09_cell_sorting.md), copied verbatim:
#
#   F_dl vs t for T ∈ {0, 2, 5, 10, 15, 20, 40, 80}, ≥ 5 replicates per T, FULL.
#   T = 0: |F_dl(2000) − F_dl(100)| < 0.02. Order at 10³: F_dl(T=2) > F_dl(T=5) > F_dl(T=10).
#   T = 40: F_dl > 0.07 at every save in [10³, 10⁴]. T = 80: > 50% of cells gone (volume 0)
#   by 500.
#
# Definitions (spec §9.0): times are paper MCS (16 of our MCS); F_dl is the heterotypic share
# of all mismatched Moore bonds (each once, medium included) on a copy annealed 2 paper MCS
# at T = 0 with the run's J, λ and V₀ (seed 1); a verdict uses the mean over replicates. A
# save with no mismatched bond left (every cell gone) has F_dl = 0. "Gone" is volume 0 on the
# raw state.
#
# Tiers.
# - RECORD (always; cheap). The committed FULL record `reproductions/data/09/vpre7-2026-10-07/`
#   (D-146): its shape (the 8 temperatures, ≥ 5 replicates at every save, the saves the rules
#   read), and its `verdicts.tsv` equals the four verdicts recomputed here from
#   `timeseries.tsv`.
# - SMOKE (always; ≈ 1 min on 4 threads). The reduced build's 64-cell `graner_glazier_state`
#   on 72², n = 4 (seed 1, replicas 1:4), T ∈ {0, 2, 5, 10, 80}. Only the size-free parts bind:
#   T = 0 freezes (the T = 0 rule as stated); F_dl(T = 2) above F_dl(T = 5) and F_dl(T = 10) at
#   10³ (the small aggregate levels off by 10³, so T = 5 against T = 10 is not resolved at this
#   size and is left to FULL); T = 80 loses cells by 500 (the 50% bar is FULL only).
#   Negative controls (D-048): at T = 10 the same T = 0 statistic exceeds 0.02 (it can fail),
#   and T = 10 loses no cell by 500 (the loss count is not vacuous).
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full). The four criteria on the committed
#   record, as stated. The record is produced offline on an idle machine (D-146, D-157); a
#   criterion that fails here is a deviations-table row on the page (D-154), not a tolerance.
#   The 2026-10-07 record passes T = 0, the order and T = 40, and fails T = 80
#   (`@test_broken`).
using Statistics: mean

const P61H_FULLREPRO = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P61H_REC = joinpath(pkgdir(PottsModels), "reproductions", "data", "09", "vpre7-2026-10-07")
const P61H_TS = (0.0, 2.0, 5.0, 10.0, 15.0, 20.0, 40.0, 80.0)

p61h_rows(file) = (l = split.(readlines(file), '\t'); [Dict(zip(l[1], r)) for r in l[2:end]])
p61h_num(r, k) = parse(Float64, r[k])
p61h_frac(r, key) = p61h_num(r, "mismatched_bonds") == 0 ? 0.0 : p61h_num(r, "F_" * key)
p61h_gone(r) = 1 - (p61h_num(r, "alive_dark") + p61h_num(r, "alive_light")) /
                   (p61h_num(r, "cells_dark") + p61h_num(r, "cells_light"))

# the four V-PRE7 statistics and verdicts of a record (spec §9.1, verbatim rules)
function p61h_verdicts(rows)
    sel(T, t) = filter(r -> p61h_num(r, "T") == T && p61h_num(r, "paper_mcs") == t, rows)
    m(T, t) = mean(p61h_frac(r, "dl") for r in sel(T, t))
    late = sort(unique(t for t in p61h_num.(rows, "paper_mcs") if 1000 <= t <= 10_000))
    d0 = abs(m(0.0, 2000) - m(0.0, 100))
    o = (m(2.0, 1000), m(5.0, 1000), m(10.0, 1000))
    f40 = minimum(m(40.0, t) for t in late)
    g80 = mean(p61h_gone.(sel(80.0, 500)))
    return (; d0, o, f40, g80, late,
        ok = (frozen = d0 < 0.02, order = o[1] > o[2] > o[3], plateau = f40 > 0.07, disintegration = g80 > 0.5))
end

@testset "09 V-PRE7 record (data/09/vpre7-2026-10-07)" begin
    rows = p61h_rows(joinpath(P61H_REC, "timeseries.tsv"))
    @test Set(p61h_num.(rows, "T")) == Set(P61H_TS)
    saves = sort(unique(p61h_num.(rows, "paper_mcs")))
    @test all(t -> t in saves, (100.0, 500.0, 1000.0, 2000.0, 10_000.0))
    # ≥ 5 replicates per T at every save, the same paired start seeds at every T
    seeds(T) = Set(p61h_num(r, "start_seed") for r in rows if p61h_num(r, "T") == T)
    @test all(T -> length(seeds(T)) >= 5 && seeds(T) == seeds(0.0), P61H_TS)
    @test all(T -> all(t -> count(r -> p61h_num(r, "T") == T && p61h_num(r, "paper_mcs") == t, rows) == length(seeds(T)), saves), P61H_TS)
    @test all(r -> p61h_num(r, "cells_dark") + p61h_num(r, "cells_light") == 1000, rows)
    # verdicts.tsv is what the record's time series gives
    v = p61h_verdicts(rows)
    written = Dict(r["criterion"] => r["result"] == "PASS" for r in p61h_rows(joinpath(P61H_REC, "verdicts.tsv")))
    @test written == Dict("T = 0 frozen" => v.ok.frozen, "order at 10³" => v.ok.order,
        "T = 40 plateau" => v.ok.plateau, "T = 80 disintegration" => v.ok.disintegration)
    @test isfile(joinpath(P61H_REC, "provenance.toml"))
end

@testset "09 V-PRE7 SMOKE (64 cells, n = 4)" begin
    σ, k = graner_glazier_state()
    # the page's `annealed`: cells are the labels 1:maximum(σ), so vanished top labels are dropped
    anneal(σa, run) = maximum(σa) == 0 ? copy(σa) : ownership(solve(PottsProblem(GranerGlazier(; name = :p61h_anneal, lattice = size(σa)),
        [ownership => copy(σa), kind => k[1:maximum(σa)], :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 32); seed = 1), SequentialCPM(); saveat = 32).u[end])
    function hetero(σa)
        dl = total = 0
        nx, ny = size(σa)
        for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
            a, b = σa[x, y], σa[mod1(x + dx, nx), mod1(y + dy, ny)]
            a == b && continue
            total += 1
            a != 0 && b != 0 && k[a] != k[b] && (dl += 1)
        end
        return total == 0 ? 0.0 : dl / total
    end
    gone(σa) = 1 - length(setdiff(unique(σa), 0)) / length(k)
    base = PottsProblem(GranerGlazier(; name = :p61h_gg), [ownership => σ, kind => k], (0, 16 * 2000); seed = 1)
    ts = [100, 500, 1000, 2000]
    F, G = Dict{Float64, Matrix{Float64}}(), Dict{Float64, Matrix{Float64}}()
    for T in (0.0, 2.0, 5.0, 10.0, 80.0)
        q = remake(base; p = [:T => T])
        ens = solve(EnsembleProblem(q), SequentialCPM(; proposal = Moore(1)), EnsembleThreads();
            trajectories = 4, saveat = 16 .* ts)
        raw = [ownership(sol.u[findfirst(==(16t), sol.t)]) for sol in ens.u, t in ts]
        F[T] = hetero.(anneal.(raw, Ref(q)))
        G[T] = gone.(raw)
    end
    mF(T, t) = mean(F[T][:, findfirst(==(t), ts)])
    mG(T, t) = mean(G[T][:, findfirst(==(t), ts)])
    @test abs(mF(0.0, 2000) - mF(0.0, 100)) < 0.02                  # T = 0 freezes
    @test abs(mF(10.0, 2000) - mF(10.0, 100)) > 0.02                 # control: T = 10 does not
    @test mF(2.0, 1000) > mF(5.0, 1000) && mF(2.0, 1000) > mF(10.0, 1000)
    @test mG(80.0, 500) > 0                                          # T = 80 loses cells
    @test mG(10.0, 500) == 0                                         # control: T = 10 keeps them all
end

if P61H_FULLREPRO
    @testset "09 FULL: V-PRE7 temperature regimes (committed record)" begin
        v = p61h_verdicts(p61h_rows(joinpath(P61H_REC, "timeseries.tsv")))
        @test v.ok.frozen
        @test v.ok.order
        @test v.ok.plateau
        # FAIL in the 2026-10-07 record (0.076 of cells gone at 500): a deviations-table row on
        # the page (D-154), not a tolerance. Marked broken so that a record that meets the
        # target shows up as an unexpected pass.
        @test_broken v.ok.disintegration
    end
end
