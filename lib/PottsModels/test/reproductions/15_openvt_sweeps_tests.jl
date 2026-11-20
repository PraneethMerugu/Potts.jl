# the OpenVT monolayer benchmark's inhibition sweeps. Fig 6 shows the
# time to 10⁴ cells against β (γ = 0) and against γ (β = 0). Table 1 (T1) gives the thresholds
# at 1.1, 2, 5, 10 and 20× the uninhibited time. Fig 7 shows 10⁴-cell colonies at β = 0 for the
# T1 γ values.
# Protocol: spec 15 §4.0.1 cases (a), (c) and (d), §3.5 and §4.3. Targets: §4.1 V1, V2, V2b, V3
# and V3b (docs/design/research/model-specs/15_openvt_monolayer.md v3.3, which carries the
# sweeps V-target audit). Every grid, seed, lattice, run count, rule and negative control below
# is the test author's (see the D-entry).
#
# Reference numbers from G (54f375f, read only, never in git) are recorded below as constants.
# They were computed with this file's rules (`mrule`, `g_reference`) on the PC
# clone on 2026-10-08. The G tier recomputes them when OPENVT_MONOLAYER_REPO is set.
#
# Units. A run's time t is its stopping MCS / 775: the end of the first MCS with ≥ 10⁴ live
# cells, in cycles (5T, C1). This is M's "Time to 10k (5T)". The targets are multiples of M's
# uninhibited time, τ_m = 13.57 m, for m = 1.1, 2, 5, 10, 20: 14.927, 27.14, 67.85, 135.7, 271.4
# (Table 1 caption; Fig 6 dashed lines, spec §2.3).
#
# Cap (spec §4.3, "runs past 20× are capped"). A run ends at MCS CAP = 271.4 × 775 =
# 210 335. If it has not reached 10⁴ cells by then it is capped: t = Inf, read as "> 20×".
# A run that reaches 10⁴ cells at the cap itself has t = 271.4 = τ_20, so "capped" means
# exactly t > τ_20.
#
# Point mean. A point is (sweep, q), where q is the inhibition threshold in units of 10⁻⁴
# (β = q/10⁴ in the β sweep, γ = q/10⁴ in the γ sweep). Its runs are its replicates k = 1, 2, ….
# t̄ is the mean of their t, or Inf if any replicate is capped.
#
# Sampling: the TST/Artistoo way (spec §3.5, §4.3), as a deterministic adaptive protocol
# (`inhibition_protocol`) that the record tier replays.
# 1. Grid. Every point of GRID gets n₁ replicates:
#    - 10 at β = 0 (V1; C4's ≥ 10);
#    - 5 at the V2b points and at γ = 10⁻⁴ (V3b);
#    - 1 elsewhere (TST's single runs).
#    The γ sweep does not include γ = 0. That case is the β = 0 point, because β = γ = 0 is
#    one model.
# 2. Bracket. For each target (sweep, m) of TARGETS, take the first adjacent pair of
#    grid points (ascending q) with t̄(lo) ≤ τ_m < t̄(hi). The γ sweep scans only γ > 0. With
#    no such pair the threshold is "—".
# 3. Bisection, INHIBITION_K = 2 steps. mid = (lo + hi) ÷ 2 in q units, so β and γ are rounded down
#    to 10⁻⁴. The mid gets one replicate, unless it is already sampled. Then lo := mid if
#    t̄(mid) ≤ τ_m, else hi := mid. A step is skipped when mid equals lo or hi. Each step is
#    one batch over all targets.
# 4. Final points (Artistoo's repeats; spec §4.3 "repeat 6 runs at the final points"). Both
#    ends of each final bracket are topped up to NFINAL = 6 replicates. An end that is
#    already capped (t̄ = Inf) is not topped up: it stays "> 20×".
# 5. Threshold (M's rule, §3.5): the final end whose t̄ is nearest τ_m. Ties go to lo,
#    including when both ends are Inf. Information only: a log-linear interpolation of τ_m
#    between the ends; the thresholds relative to Potts' own uninhibited time (t̄(β = 0) × m,
#    by `mrule` over the sampled table).
#
# | Row          | Statistic                                                     | Lattice spread (spec §4.1) | Pass band                 |
# |--------------|---------------------------------------------------------------|----------------------------|---------------------------|
# | V1           | t̄ at β = γ = 0 (10 replicates)                                | 13.57 × 5T                 | [12.213, 14.927] (± 10 %) |
# | V2.1.1x      | β threshold at 1.1×                                           | 0.687–0.704                | [0.667, 0.724]            |
# | V2.2x        | β threshold at 2×                                             | 0.936–0.943                | [0.916, 0.963]            |
# | V2.5x        | β threshold at 5×                                             | 0.9867–0.9916              | [0.9817, 0.9966]          |
# | V2.10x       | β threshold at 10×                                            | 1.006–1.011                | [1.001, 1.016]            |
# | V2.20x       | β threshold at 20×                                            | 1.020–1.024                | [1.015, 1.029]            |
# | V2b.<β>      | t̄(β) / reference at β = 0.8727, 0.9, 0.9334, 0.95, 1.0       | Artistoo 18.59, TST 20.40, Artistoo 25.59, TST 32.11, TST 105.76 | [0.75, 1.25] (± 25 %) |
# | V3.1.1x, V3.2x | γ threshold at 1.1× and 2×                                  | "—" (the γ → 0⁺ jump)      | "—"                       |
# | V3.5x        | γ threshold at 5×                                             | 0.076–0.12                 | [0.026, 0.17]             |
# | V3.10x       | γ threshold at 10×                                            | 0.45–0.50                  | [0.40, 0.55]              |
# | V3.20x       | γ threshold at 20×                                            | 0.715–0.76                 | [0.665, 0.81]             |
# | V3b          | t̄ at γ = 10⁻⁴ (5 replicates)                                  | 61.4–63.1 (γ ≤ 0.02)       | [61, 70]                  |
# | F7.1         | min over the T1 γ thresholds (5×, 10×, 20×) of the inhibited  | TST 0.961, 0.978, 0.990    | ≥ 0.90                    |
# |              | fraction of replicate 1's final colony (O5)                   |                            |                           |
#
# A threshold row fails when its threshold is "—". V1 is kept as the spec states it. D-173
# measured 15.17 cycles for case (a), so V1 may fail. A failure is a D-154 deviation: it goes
# in `deviations.tsv`, and the band is not widened. The spread values come from Table 1 (M p.7,
# spec v3 log). G's TST and Artistoo rows reproduce them under mrule (constants below).
#
# Negative controls (D-048). Each is pre-registered to FAIL its row.
# - NC1 (V3b's own control, spec §4.1): γ = 0 (the β = 0 point, 10 replicates) lies outside
#   the V3b band. Without inhibition there is no γ → 0⁺ jump: t̄ ≈ 13.6, not 61–70.
# - NC2 (V2b's β resolution): the V2b statistic at a β offset of 0.05. That is Potts t̄(0.95)
#   against TST's 20.40 at 0.9, and Potts t̄(1.0) against TST's 32.11 at 0.95. Both must leave
#   [0.75, 1.25]. If the steep end of the Potts curve were flat, this control would pass.
# - NC3 (V1's discrimination): the V1 rule applied to the γ = 10⁻⁴ point (5 replicates) must
#   fail.
#
# Protocol. `OpenVTReferenceMonolayer` at its Table S1 defaults (σ_X = 0.4), with β and γ set
# per point, from one disc cell at the centre (`openvt_reference_state`). The algorithm is
# `BoundarySiteCPM(; proposal = Moore(1))`, equal in law to `SequentialCPM` (D-177; chosen
# before any FULL run, D-174 amendment). The lattice is closed, with
# `edge_guard(5; terminate = true)`, and a run that reaches the guard invalidates the record.
# The run stops at the end of the first MCS with ≥ 10⁴ cells (`stop_at_cells`), or at the cap.
#
# | Sweep | Fixed  | Lattice | Grid (GRID)                                                                    | Seeds                         |
# |-------|--------|---------|--------------------------------------------------------------------------------------|-------------------------------|
# | β     | γ = 0  | 1400²   | 0, 0.25, 0.5, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.8727, 0.9, 0.9334, 0.95, 0.96, 0.97, 0.98, 0.99, 1.0, 1.006, 1.01, 1.015, 1.02, 1.025, 1.03 | 160 000 000 + 100 q + k |
# | γ     | β = 0  | 1800²   | 10⁻⁴, 0.001, 0.01, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8 | 170 000 000 + 100 q + k |
#
# Lattices. Spec §4.3 has β ∈ [0, 1.03] and γ ∈ [0, 0.95]. The grid is dense at β ≥ 0.9 and
# γ ≥ 0.4, and includes γ = 10⁻⁴. γ stops at 0.8: in TST, γ ≥ 0.75 is already past 20× (278.8).
# Lattice sizes come from G's TST final snapshots (audit): the furthest centroid is 491 px at
# β = 1.02 and 602 px at γ = 0.75. Potts' (a) colony is about 10 % wider than TST's at the same
# β, and Potts' γ colonies are less compact than its uninhibited ones (the γ = 10⁻⁴ control of
# D-173 came within 33 sites of a 400² edge at 1000 cells; a 300-cell SMOKE draft hit the guard
# of 200² at 190 cells). So 1400² leaves about 150 sites at β = 1.02, and 1800² (TST: 1601²)
# leaves about 240 at γ = 0.75. The cost of a larger γ lattice is the medium sites (G9).
#
# Fig 7 (O5, spec §3.1). For each T1 γ threshold, the final state of replicate 1 is written
# as `Potts.jl_gamma_<γ>_<MCS>MCS.csv`, with `x_pos, y_pos, radius_i` in R and `inhibited =
# i > 0`. So are γ = 0 (β = 0, k = 1) and γ = 10⁻⁴ (k = 1): five panels, one per T1 entry, with
# γ = 0 and 10⁻⁴ standing in for the lattice "—" at 1.1× and 2×. This reading of M's five
# panels is [unverified].
#
# Tiers.
# - always: the rules and the protocol on synthetic sweeps with known answers (curves through
#   TST's Table 1 samples), including that the protocol resolves them within the bands;
#   replay checks; the G constants' premises.
# - SMOKE (the default; under a minute plus one model compilation): three jobs through the
#   FULL job function on 300² with a 250-cell stop. They are β = γ = 0, γ = 10⁻⁴ (the V3b
#   jump's mechanism: at least 1.3× slower), and β = 1.03 under a 1500-MCS cap (the cap path:
#   capped, t = Inf; run twice, the same). Plus the O5 rows of their final states.
# - G (OPENVT_MONOLAYER_REPO set): recompute the consortium constants.
# - FULL record (always, cheap): reads the one committed D-146 record directory
#   `reproductions/data/15/sweeps-*`:
#   - `runs.tsv`, `verdicts.tsv` and `provenance.toml`;
#   - `Potts.jl_time_to_10k_vs_{beta,gamma}.csv` (O3);
#   - `f7/` (O5).
#   It replays the protocol on the recorded times, requires the record to hold exactly the
#   replayed runs, and recomputes every row. A failing row must be in the record's
#   `deviations.tsv` (D-154) and is then `@test_broken`. The controls must fail. Until the
#   record exists this testset fails on its first check.
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full, offline on the PC; D-146, D-157):
#   reruns the protocol and requires every row and every control. Its cost (G9 profile): at most 160 runs and about 11 M MCS·runs, ≈ 125 core-hours on one uncontended
#   PC thread; the jobs of a stage run in parallel with `:greedy` scheduling (D-173).
#
# Record schema (tab-separated, one header line):
# - runs.tsv: sweep (beta | gamma), q, k, seed, stage (grid | bisect | final), beta, gamma,
#   lattice, retcode (Terminated | Success), mcs, N, capped (true | false), edge_gap, wall_s
# - verdicts.tsv: target (first token the row id), ours, band, result (PASS | FAIL), one line
#   per row of ROWS and CONTROLS
# - f7/: one O5 file per Fig 7 panel (five)

@testsetup module OpenVTSweepsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "shared", "openvt_sweeps.jl"))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "15 openvt sweeps rules and protocol on synthetic sweeps" setup = [OpenVTSweepsSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt sweeps rules and protocol on synthetic sweeps" begin
        @test [tau(m) for m in MULTS] == [14.927, 27.14, 67.85, 135.7, 271.4]
        @test CAP == round(Int, tau(20.0) * CYCLE)
        @test inhibition_seed(:beta, 0, 1) == 160_000_001 && inhibition_seed(:gamma, 1, 5) == 170_000_105
        @test params(:beta, 9334) == (0.9334, 0.0) && params(:gamma, 1) == (0.0, 1.0e-4)
        # every seed of every possible point is distinct across sweeps
        @test inhibition_seed(:beta, 10_300, NFINAL + 10) < inhibition_seed(:gamma, 0, 1)
        @test all(issorted, GRID) && all(in(GRID.beta), V2B) && 1 in GRID.gamma
        @test inhibition_mean([1.0, 3.0]) == 2 && inhibition_mean([1.0, Inf]) == Inf
        @test inhibition_band(:beta, 5.0) == (0.9817, 0.9966) && inhibition_band(:gamma, 10.0) == (0.4, 0.55)
        # the rules on a hand table
        S = Dict((:beta, 0) => [10.0], (:beta, 1) => [14.0], (:beta, 2) => [16.0], (:beta, 3) => [Inf])
        @test inhibition_bracket(S, :beta, 1.1) == (1, 2) && threshold(S, :beta, 1.1, (1, 2)) == 1   # |14 − 14.927| < |16 − 14.927|
        @test inhibition_bracket(S, :beta, 20.0) == (2, 3) && threshold(S, :beta, 20.0, (2, 3)) == 2
        @test threshold(Dict((:beta, 1) => [Inf], (:beta, 2) => [Inf]), :beta, 20.0, (1, 2)) == 1   # tie → lo
        @test inhibition_bracket(Dict((:beta, 0) => [15.0], (:beta, 1) => [16.0]), :beta, 1.1) === nothing  # "—"
        @test mrule([0.1, 0.2, 0.3], [10.0, 20.0, 30.0], 24.0) == 0.2
        @test mrule([0.1, 0.2], [10.0, 30.0], 20.0) == 0.1                                       # tie → lower
        @test mrule([0.1, 0.2], [30.0, 40.0], 20.0) === nothing
        @test group([0.5, 0.4, 0.5], [1.0, 2.0, 3.0]) == ([0.4, 0.5], [2.0, 2.0])

        # the protocol on the TST-shaped curves
        P = inhibition_protocol(syn_exec())
        @test inhibition_protocol(syn_exec()).log == P.log                                            # deterministic
        @test count(e -> e[1] === :grid, P.log) ==
            sum(inhibition_n1(sw, q) for sw in (:beta, :gamma) for q in GRID[sw])
        @test count(e -> e[1] === :bisect, P.log) <= INHIBITION_K * length(TARGETS)
        @test all(e -> e[4] <= NFINAL || (e[2], e[3]) == (:beta, 0), P.log)
        for tg in TARGETS
            b = P.br[tg]
            @test b !== nothing
            x = [P.S[(tg[1], q)] for q in b]
            @test all(v -> length(v) >= NFINAL || any(isinf, v), x)                               # final points
        end
        inhibition_inh(P, f) = Dict(q => f for q in inhibition_points(P.S, :gamma))
        ver = inhibition_verdicts(P, inhibition_inh(P, 0.97))
        @test sort(collect(keys(ver))) == sort([ROWS; CONTROLS])
        # the design resolves TST's own curve inside every band (the protocol's premise) …
        for r in ROWS
            r == "V1" && continue                                     # 13.7 ∈ band, checked below
            r in ("V2b.0.8727", "V2b.0.9334") && continue             # Artistoo references, not TST's curve
            @test ver[r][2]
        end
        @test ver["V1"][2] && ver["V3.1.1x"] == ("—", true) && ver["V3.2x"] == ("—", true)
        # … the controls fail on it …
        @test !ver["NC1"][2] && !ver["NC2"][2] && !ver["NC3"][2]
        # … and the bisection sharpens the grid: the 5× β threshold lies within 0.002 of TST's 0.9867
        @test abs(ver["V2.5x"][1] - 0.9867) < 0.002 && abs(ver["V2.10x"][1] - 1.006) < 0.002

        # each row can fail on its own
        Ps = inhibition_protocol(syn_exec(; scale = 1.118))                                         # D-173's 15.17 / 13.57
        slow = inhibition_verdicts(Ps, inhibition_inh(Ps, 0.97))
        @test !slow["V1"][2] && !slow["V2.1.1x"][2] && slow["V2.1.1x"][1] === NaN                      # "—": no crossing at 14.927
        Pd = inhibition_protocol(syn_exec(; shift = 0.02))                                          # curve 0.02 to the left
        shifted = inhibition_verdicts(Pd, inhibition_inh(Pd, 0.97))
        @test !shifted["V2.5x"][2] && !shifted["V2.10x"][2] && !shifted["V2.20x"][2] && shifted["V1"][2]
        @test !inhibition_verdicts(P, inhibition_inh(P, 0.5))["F7.1"][2]
        # a capped end is not topped up, and the 20× threshold is the finite end
        q20 = P.br[(:beta, 20.0)]
        @test any(isinf, P.S[(:beta, q20[2])]) && length(P.S[(:beta, q20[2])]) < NFINAL
        @test threshold(P.S, :beta, 20.0, q20) == q20[1]
        # information
        info = information(P)
        @test info.t0 == 13.7 && info.relative["V3.1.1x"] == "—" && isfinite(info.interp["V2.5x"])

        # replay: a record holding exactly the protocol's runs replays to the same log; an extra
        # or a missing run is detected
        times = Dict((e[2], e[3], e[4]) => syn(e[2], e[3]) for e in P.log)
        lookup = jobs -> [times[j] for j in jobs]
        R = inhibition_protocol(lookup)
        @test Set((e[2], e[3], e[4]) for e in R.log) == Set(keys(times)) && R.log == P.log
        missing_one = copy(times)
        delete!(missing_one, (P.log[end][2], P.log[end][3], P.log[end][4]))
        @test_throws KeyError inhibition_protocol(jobs -> [missing_one[j] for j in jobs])

        # the G constants have the rules' form, and G's own samples pass the bands (audit premises)
        @test length(INHIBITION_G.tst_beta) == length(INHIBITION_G.art_beta) == 5 && length(INHIBITION_G.v2b) == length(V2B)
        for (j, m) in enumerate(MULTS)
            @test inhibition_in(INHIBITION_G.tst_beta[j], inhibition_band(:beta, m)) && inhibition_in(INHIBITION_G.art_beta[j], inhibition_band(:beta, m))
        end
        for (j, m) in enumerate((5.0, 10.0, 20.0)), k in (:tst_gamma_runs, :tst_gamma_means, :art_gamma_runs, :art_gamma_means)
            @test inhibition_in(INHIBITION_G[k][j], inhibition_band(:gamma, m))
        end
        @test all(x -> inhibition_in(x, V3B_BAND), INHIBITION_G.v3b) && all(x -> inhibition_in(x, V1_BAND), INHIBITION_G.plateau)
        @test all(>=(F7_MIN), INHIBITION_G.tst_f7)
        @test 1.1 * INHIBITION_G.rmax_px.beta + GUARD + 10 < LATTICE.beta / 2
        @test 1.1 * INHIBITION_G.rmax_px.gamma + GUARD + 10 < LATTICE.gamma / 2
    end
end

@testitem "15 openvt sweeps SMOKE: uninhibited, γ = 1e-4 and a capped β = 1.03 job" setup = [OpenVTSweepsSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # SMOKE: three jobs through the FULL job function on 200², 300-cell stop
    # ---------------------------------------------------------------------------------------------
    if !INHIBITION_FULL
        @testset "15 openvt sweeps SMOKE: uninhibited, γ = 1e-4 and a capped β = 1.03 job" begin
            prob = problem(300; cells = 250, cap = 20_000)
            free = inhibition_job(prob, :beta, 0, 1; cells = 250, cap = 20_000)
            jump = inhibition_job(prob, :gamma, 1, 1; cells = 250, cap = 20_000)
            cap = inhibition_job(prob, :beta, 10_300, 1; cells = 250, cap = 1500)
            @info "15 openvt sweeps SMOKE" free.t jump.t cap.mcs cap.N
            @test free.retcode === :Terminated && free.N >= 250 && !free.capped && free.t == free.mcs / CYCLE
            @test free.seed == 160_000_001 && jump.seed == 170_000_101
            @test jump.retcode === :Terminated && jump.N >= 250
            @test jump.t >= 1.3 * free.t                         # the γ → 0⁺ jump's mechanism
            @test cap.capped && cap.t == Inf && cap.mcs == 1500 && cap.N < 250 && cap.retcode === :Success
            # same seed, same run
            again = inhibition_job(prob, :beta, 10_300, 1; cells = 250, cap = 1500)
            @test again.N == cap.N && Array(again.u.ownership) == Array(cap.u.ownership)
            # O5 rows: the uninhibited colony grows everywhere; γ = 1e-4 arrests the interior
            o_free = inhibition_o5(free.u; β = 0.0, γ = 0.0)
            o_jump = inhibition_o5(jump.u; β = 0.0, γ = 1.0e-4)
            @test length(o_free.x_pos) == free.N && all(==(0), o_free.inhibited)
            @test 0.3 < mean(o_jump.inhibited) < 1
            io = IOBuffer()
            write_openvt(io, :O5, o_jump)
            @test startswith(String(take!(io)), "x_pos,y_pos,radius_i,inhibited\n")
        end
    end
end

@testitem "15 openvt sweeps G: consortium constants from the TST and Artistoo sweeps" setup = [OpenVTSweepsSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt sweeps G: consortium constants from the TST and Artistoo sweeps" begin
        if isempty(REPO) || !isdir(joinpath(REPO, "results"))
            @test_skip "OPENVT_MONOLAYER_REPO not set"
        else
            g = g_reference(REPO)
            @info "15 openvt sweeps G" g
            for k in (:tst_beta, :art_beta, :tst_gamma_runs, :tst_gamma_means, :art_gamma_runs, :art_gamma_means, :v2b, :v3b)
                @test isapprox(g[k], INHIBITION_G[k]; rtol = 1.0e-6)
            end
            @test g.beta_runs == (g.tst_beta, g.art_beta)          # no repeated β rows: both rules agree
            @test isapprox(g.plateau, INHIBITION_G.plateau; atol = 0.005)
            @test isapprox(g.tst_f7, INHIBITION_G.tst_f7; atol = 1.0e-6)
            @test isapprox(g.rmax_px.beta, INHIBITION_G.rmax_px.beta; atol = 0.01) &&
                isapprox(g.rmax_px.gamma, INHIBITION_G.rmax_px.gamma; atol = 0.01)
            @test all(isnothing, g.dash)                           # lattice γ rows: "—" at 1.1× and 2×
        end
    end
end

@testitem "15 openvt sweeps FULL record: V1, V2, V2b, V3, V3b, F7 and the controls" setup = [OpenVTSweepsSetup] tags = [:pottsmodels, :reproductions] begin
    @testset "15 openvt sweeps FULL record: V1, V2, V2b, V3, V3b, F7 and the controls" begin
        dirs = if isdir(DATA)
            filter(d -> startswith(d, "sweeps-") && isdir(joinpath(DATA, d)), readdir(DATA))
        else
            String[]
        end
        length(dirs) == 1 || @info "15 openvt sweeps: no record yet (expected exactly one reproductions/data/15/sweeps-* directory)" dirs
        @test length(dirs) == 1
        if length(dirs) == 1
            D = joinpath(DATA, only(dirs))
            for f in (
                    "runs.tsv", "verdicts.tsv", "provenance.toml", "Potts.jl_time_to_10k_vs_beta.csv",
                    "Potts.jl_time_to_10k_vs_gamma.csv",
                )
                @test isfile(joinpath(D, f))
            end
            runs = inhibition_tsv(joinpath(D, "runs.tsv"))
            rec = Dict{Tuple{Symbol, Int, Int}, Dict{String, String}}()
            for r in runs
                sw, q, k = Symbol(r["sweep"]), parse(Int, r["q"]), parse(Int, r["k"])
                @test !haskey(rec, (sw, q, k))
                rec[(sw, q, k)] = r
                # each run is the pre-registered job
                β, γ = params(sw, q)
                @test parse(Int, r["seed"]) == inhibition_seed(sw, q, k)
                @test parse(Float64, r["beta"]) == β && parse(Float64, r["gamma"]) == γ
                @test parse(Int, r["lattice"]) == LATTICE[sw]
                m, N = parse(Int, r["mcs"]), parse(Int, r["N"])
                if r["capped"] == "true"
                    @test r["retcode"] == "Success" && m == CAP && N < CELLS
                else
                    @test r["retcode"] == "Terminated" && N >= CELLS && m <= CAP
                end
                @test parse(Int, r["edge_gap"]) >= GUARD
            end
            # replay: the record holds exactly the protocol's runs, with its stage labels
            P = inhibition_protocol(jobs -> [rtime(rec[j]) for j in jobs])
            @test Set((e[2], e[3], e[4]) for e in P.log) == Set(keys(rec))
            @test all(e -> rec[(e[2], e[3], e[4])]["stage"] == string(e[1]), P.log)
            # O3 tables: one row per run of each sweep, the same MCS (NaN when capped)
            for sw in (:beta, :gamma)
                o3 = read_openvt(joinpath(D, "Potts.jl_time_to_10k_vs_$(sw).csv"), :O3)
                mine = sort(
                    [
                        (q / 10_000, rec[(s, q, k)]["capped"] == "true" ? NaN : parse(Float64, rec[(s, q, k)]["mcs"]))
                            for (s, q, k) in keys(rec) if s === sw
                    ]; by = x -> (x[1], isnan(x[2]) ? Inf : x[2])
                )
                got = sort(collect(zip(o3[sw], o3.mcs)); by = x -> (x[1], isnan(x[2]) ? Inf : x[2]))
                @test length(got) == length(mine) && all(((a, b),) -> a[1] == b[1] && isequal(a[2], b[2]), zip(got, mine))
            end
            # Fig 7 panels: γ = 0, γ = 1e-4 and the three T1 γ thresholds, replicate 1
            qs = Int[
                threshold(P.S, :gamma, m, P.br[(:gamma, m)]) for m in (5.0, 10.0, 20.0)
                    if P.br[(:gamma, m)] !== nothing
            ]
            inh = Dict{Int, Float64}()
            f7 = joinpath(D, "f7")
            for (sw, q) in [(:beta, 0); (:gamma, 1); [(:gamma, q) for q in qs]]
                r = rec[(sw, q, 1)]
                γs = sw === :beta ? 0.0 : q / 10_000
                f = joinpath(f7, "Potts.jl_gamma_$(γs)_$(r["mcs"])MCS.csv")
                @test isfile(f)
                isfile(f) || continue
                o5 = read_openvt(f, :O5)
                @test length(o5.x_pos) == parse(Int, r["N"])
                sw === :gamma && (inh[q] = mean(o5.inhibited))
                sw === :beta && @test all(==(0), o5.inhibited)
            end
            for q in qs
                haskey(inh, q) || (inh[q] = NaN)
            end
            ver = inhibition_verdicts(P, inh)
            info = information(P)
            @info "15 openvt sweeps record" Dict(k => v[1] for (k, v) in ver) info
            dev_f = joinpath(D, "deviations.tsv")
            devs = isfile(dev_f) ? inhibition_tsv(dev_f) : Dict{String, String}[]
            check(ver, devs; broken_ok = true)
            # the committed verdicts agree with this recomputation
            vt = inhibition_tsv(joinpath(D, "verdicts.tsv"))
            for row in [ROWS; CONTROLS]
                rr = [r for r in vt if ver_id(r["target"]) == row]
                @test length(rr) == 1 && only(rr)["result"] == (ver[row][2] ? "PASS" : "FAIL")
            end
        end
    end
end

@testitem "15 openvt sweeps FULL: the sweeps, rerun" setup = [OpenVTSweepsSetup] tags = [:pottsmodels, :reproductions] begin
    # ---------------------------------------------------------------------------------------------
    # FULL: rerun the protocol (offline, on the PC; D-146, D-157)
    # ---------------------------------------------------------------------------------------------
    if INHIBITION_FULL
        @testset "15 openvt sweeps FULL: the sweeps, rerun" begin
            probs = Dict(sw => problem(LATTICE[sw]) for sw in (:beta, :gamma))
            inh = Dict{Int, Float64}()
            lk = ReentrantLock()
            function exec(jobs)
                out = Vector{Float64}(undef, length(jobs))
                Threads.@threads :greedy for j in eachindex(jobs)
                    sw, q, k = jobs[j]
                    r = inhibition_job(probs[sw], sw, q, k)
                    out[j] = r.t
                    if sw === :gamma && k == 1
                        f = mean(inhibition_o5(r.u; β = r.β, γ = r.γ).inhibited)
                        lock(() -> (inh[q] = f), lk)
                    end
                end
                return out
            end
            P = inhibition_protocol(exec)
            ver = inhibition_verdicts(P, inh)
            @info "15 openvt sweeps FULL" Dict(k => v[1] for (k, v) in ver) information(P)
            check(ver, Dict{String, String}[]; broken_ok = false)
        end
    end
end
