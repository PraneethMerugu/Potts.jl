# integral refreshes only for readers after the sweep.
# Decision: D-120. Related: D-042/D-076 (update blocks read fresh
# integrals), `integral_pre_tests.jl` (`integral(Pre(w))` slots), D-110 (`integral_fold_hoist_tests.jl`: hoisted fold slots before
# the refreshes), D-016/D-118 (fingerprint).
#
# The waste (found in the `integral_pre_tests.jl` review; measured on 432a0a74). `_phases_parts` in
# src/codegen.jl refreshes, once any integral is read after the sweep, EVERY integral not
# dirtied by the after block at the start of the after block: also those read only by the
# before block or the temperature (fresh from the previous `end_mcs`, read before this
# point) and those read only by `@observed` (observed queries recompute their integrals from
# the saved state, `_fresh_integrals`). `end_mcs` and `at_init` refresh every integral too,
# observed-only ones included, and each observed-only integral has a cell column. On the
# `PWaste` probe (/tmp/refresh_test/rv1/probe.jl, Waste below) today:
#     after_mcs = (CellReduce Pre(w), CellReduce u, CellPhase, SitePhase)
#     end_mcs = at_init = (CellReduce Pre(w), CellReduce u, CellReduce 2w)
#     cell layout: 3 `integral_*` columns (Pre(w), u, 2w)
# Needed: 1 CellReduce (u) at the start of the after block; 2w (observed only) no column and
# no refresh anywhere. On a 128×128 model with 8 observed-only integrals a warm MCS costs
# ≈ 3.6× the same model without the `@observed` block (2.17 vs 0.61 ms, both algorithms).
#
# Pinned here:
#  1. Phases. The after block refreshes at its start only the integrals read after the sweep
#     (after-block updates, equations, lifecycle, discrete, link rules). An integral read
#     only by `@observed` has no `integral_*` column and no CellReduce in any phase tuple
#     (before_mcs, after_mcs, end_mcs, at_init). A model whose observed integrals are all
#     observed-only has the phase structure of the same model without the `@observed` block.
#  2. Values (Sequential and Checkerboard, moving cells): every reader sees what it saw
#     before, against oracles computed from the saved states — before block (σ and site
#     values at the end of the previous MCS), after block (σ after the sweep), `@observed`
#     (`sol[:x]`, `observe(sol, :x)`, `observe(prob, :x)`; σ and sites of each saved state),
#     and the temperature (trajectory identical to a twin that reads the same quantity
#     without an integral; a constant-temperature control shows the trajectory depends on it).
#  3. Cost: observed-only integrals add no per-MCS refresh and no cell column (structural,
#     both algorithms), with a paired-timing backstop of at most 1.5× (amended, D-131).
#  4. Fingerprints unchanged (recorded on 432a0a74) for the PottsModels systems (no
#     integrals) and for an integral model whose integrals are all read after the sweep.
#
# Not pinned: whether `end_mcs` keeps refreshing integrals read only after the sweep (their
# saved columns are not part of the user-facing state); the ordering of refreshes.

@testsetup module IntegralRefreshSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Fixtures

# the PWaste probe: sb reads Pre(w) before the sweep only; sa reads u after it; ob is
# observed only
@potts_model Waste begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        sb(cell) = 0.0
        sa(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @before_mcs sb ~ integral(Pre(w))
    @after_mcs begin
        w ~ Pre(w) + 1
        sa ~ integral(u)
    end
    @observed ob(cell) ~ integral(2w)
    @sweep Metropolis(; temperature = 0.0)
end
# every kind of reader, moving cells. Integrals:
#   Pre(w)  before block only (w written after the sweep)
#   y       before block and after block (y never written)
#   u       after block and @observed (`oc`)
#   v       temperature only (v rewritten after the sweep: dirty, refreshed at the boundary)
#   2w      @observed only (dirty)
#   y^2     @observed only (clean)
@potts_model Readers begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        y(site) = 0.0
        v(site) = 1.0
        sb(cell) = 0.0
        sy(cell) = 0.0
        sa(cell) = 0.0
        ay(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @before_mcs begin
        sb ~ integral(Pre(w))
        sy ~ integral(y)
    end
    @after_mcs begin
        w ~ Pre(w) + 1
        v ~ 1.0
        sa ~ integral(u)
        ay ~ integral(y)
    end
    @observed begin
        ob(cell) ~ integral(2w)
        oq(cell) ~ integral(y^2)
        oc(cell) ~ integral(u) + integral(2w)
    end
    @sweep Metropolis(; temperature = integral(v)^2 / 64)
end
# temperature twin: integral(v) with v ≡ 1 is the cell's volume at the end of the previous
# MCS, which the before block records in `vol0` without an integral
@potts_model ReadersTwin begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        y(site) = 0.0
        v(site) = 1.0
        sb(cell) = 0.0
        sy(cell) = 0.0
        sa(cell) = 0.0
        ay(cell) = 0.0
        vol0(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @before_mcs begin
        sb ~ integral(Pre(w))
        sy ~ integral(y)
        vol0 ~ volume
    end
    @after_mcs begin
        w ~ Pre(w) + 1
        v ~ 1.0
        sa ~ integral(u)
        ay ~ integral(y)
    end
    @sweep Metropolis(; temperature = vol0^2 / 64)
end
# sensitivity control: the constant temperature 4 (= 16^2/64 at the target volume 16)
@potts_model ReadersConstT begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        y(site) = 0.0
        v(site) = 1.0
        sb(cell) = 0.0
        sy(cell) = 0.0
        sa(cell) = 0.0
        ay(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @before_mcs begin
        sb ~ integral(Pre(w))
        sy ~ integral(y)
    end
    @after_mcs begin
        w ~ Pre(w) + 1
        v ~ 1.0
        sa ~ integral(u)
        ay ~ integral(y)
    end
    @sweep Metropolis(; temperature = 4.0)
end
# an integral model with no integral read only before the sweep, by the temperature or by
# @observed: Pre(w) and w after the block's write, u in the after block and an equation,
# x before AND after the sweep.
@potts_model AfterOnly begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        x(site) = 0.0
        sx(cell) = 0.0
        s(cell) = 0.0
        f(cell) = 0.0
        g(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @before_mcs sx ~ integral(x)
    @after_mcs begin
        s ~ integral(Pre(w))
        w ~ Pre(w) + 1
        f ~ integral(w) + integral(x)
        g ~ integral(u)
    end
    @equations D(r) ~ integral(u) / 100
    @sweep Metropolis(; temperature = 2.0)
end
# cost: 8 observed-only integrals of a clean operand (today refreshed at the start of the
# after block, at the boundary and at init) on top of one after-block integral
@potts_model CostObserved begin
    @kinds medium A
    @variables begin
        y(site) = 0.0
        sa(cell) = 0.0
    end
    @lattice Lattice((128, 128))
    @energy cells => (volume - 64)^2
    @after_mcs sa ~ integral(y)
    @observed begin
        o1(cell) ~ integral(y^2)
        o2(cell) ~ integral(y^3)
        o3(cell) ~ integral(sin(y))
        o4(cell) ~ integral(cos(y))
        o5(cell) ~ integral(exp(-y))
        o6(cell) ~ integral(sqrt(1 + y))
        o7(cell) ~ integral(log(2 + y))
        o8(cell) ~ integral(y^4)
    end
    @sweep Metropolis(; temperature = 2.0)
end
# the same without the @observed block
@potts_model CostLean begin
    @kinds medium A
    @variables begin
        y(site) = 0.0
        sa(cell) = 0.0
    end
    @lattice Lattice((128, 128))
    @energy cells => (volume - 64)^2
    @after_mcs sa ~ integral(y)
    @sweep Metropolis(; temperature = 2.0)
end
const ALGS = (SequentialCPM(), CheckerboardCPM())
# ---------------------------------------------------------------------------------------
# Helpers
"""Compiled system and phases (`Potts._phases`) of model `M`."""
function refresh_phases(M)
    c = mtkcompile(M(; name = :m))
    return c, Potts._phases(
            c, Float64, Dict{Any, Any}(Potts._unwrap(x) => Potts.info(x).default for x in Potts.declared_parameters(getfield(c, :sys))),
            Potts._resolve_solvers(c)
        )
end
# a refresh phase, gated or not, and the cell column it writes
refresh_reduce(x) = x isa CorePotts.CellReduce ? x : x isa Potts._Gated && x.phase isa CorePotts.CellReduce ? x.phase : nothing
refresh_dst(r) = typeof(r.dst).parameters[2]
"""Names of the integral columns refreshed by the phases `t`, in order (with repeats)."""
refresh_refreshed(t) = Symbol[refresh_dst(r) for r in map(refresh_reduce, collect(t)) if r !== nothing]
tuples(ph) = (ph.before_mcs, ph.after_mcs, ph.end_mcs, ph.at_init)
"""Column name of `integral(f(vars...))` for the model's variables named `names`."""
function iname(c, f, names...)
    vs = [only(filter(x -> Potts.info(x).name === n, Potts.declared_variables(getfield(c, :sys)))) for n in names]
    return Potts._integral_name(Potts._unwrap(f(vs...)))
end
"""The `integral_*` cell columns of a problem's state."""
refresh_columns(prob) = sort!([n for n in propertynames(prob.u0.cell) if startswith(String(n), "integral_")])
# moving cells: two 4×4 cells on 16×16; site fields varying in space
const SIGMA = (s = zeros(Int32, 16, 16); s[3:6, 3:6] .= 1; s[9:12, 9:12] .= 2; s)
const REFRESH_W0 = [Float64(j) for i in 1:16, j in 1:16]
const REFRESH_U0 = [Float64(3i - j) for i in 1:16, j in 1:16]
const REFRESH_Y0 = [Float64(i + 2j) for i in 1:16, j in 1:16]
refresh_op() = [ownership => SIGMA, kind => [:A, :A], :w => REFRESH_W0, :u => REFRESH_U0, :y => REFRESH_Y0]
refresh_problem(M, K = 8) = PottsProblem(M(; name = :m), refresh_op(), (0, K))
"""Per cell 1:2, Σ over the sites of cell c in σ of `x`."""
fold(σ, x) = [sum(x[i] for i in eachindex(σ) if σ[i] == c; init = 0.0) for c in 1:2]
refresh_cell(sol, n) = [Array(getproperty(u.cell, n)) for u in sol.u]
# ---------------------------------------------------------------------------------------
# 3. Cost: observed-only integrals are free
const COST_SIGMA = (
    s = zeros(Int32, 128, 128); for a in 0:15, b in 0:15
        s[(8a + 1):(8a + 8), (8b + 1):(8b + 8)] .= 16a + b + 1
    end; s
)
const COST_Y0 = [Float64(i + j) / 64 for i in 1:128, j in 1:128]
cost_problem(M) = PottsProblem(M(; name = :m), [ownership => COST_SIGMA, kind => fill(:A, 256), :y => COST_Y0], (0, 10^6))
"""Minimum over `reps` of the mean wall time (s) of `n` warm MCS of `integ`."""
function refresh_time(integ; n = 20, reps = 7)
    return minimum(1:reps) do _
        t = time_ns()
        for _ in 1:n
            step!(integ)
        end
        (time_ns() - t) / n / 1.0e9
    end
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "integral refresh: the PWaste probe refreshes only what is read after the sweep" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Phases
    @testset "integral refresh: the PWaste probe refreshes only what is read after the sweep" begin
        c, ph = refresh_phases(Waste)
        n_u = iname(c, identity, :u)
        n_pre = iname(c, Potts.Pre, :w)
        n_ob = iname(c, w -> 2w, :w)
        @test length(unique([n_u, n_pre, n_ob])) == 3                        # fixture: three integrals
        after = refresh_refreshed(ph.after_mcs)
        @test after == [n_u]                                                  # DEFECT CHECK (today Pre(w), u)
        # at the start: before the after block's first update
        i1 = findfirst(x -> refresh_reduce(x) !== nothing, ph.after_mcs)
        @test i1 !== nothing && i1 < findfirst(x -> x isa CorePotts.CellPhase || x isa CorePotts.SitePhase, ph.after_mcs)
        # the observed-only integral: no refresh anywhere, no column
        @testset "no refresh of the observed-only integral in $k" for (k, t) in zip((:before_mcs, :after_mcs, :end_mcs, :at_init), tuples(ph))
            @test !(n_ob in refresh_refreshed(t))                                # DEFECT CHECK (end_mcs, at_init)
        end
        σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
        prob = PottsProblem(Waste(; name = :m), [ownership => σ, kind => [:A]], (0, 4))
        cols = refresh_columns(prob)
        @test !(n_ob in cols)                                                 # DEFECT CHECK (slot)
        @test n_pre in cols && n_u in cols                                    # the read ones keep theirs
        # the before block's integral is still fresh at every boundary and at init
        @test n_pre in refresh_refreshed(ph.end_mcs) && n_pre in refresh_refreshed(ph.at_init)
        # every refresh writes an existing column
        @test all(n -> n in cols, reduce(vcat, map(refresh_refreshed, tuples(ph))))
        # values (T = 0, the cell never moves; w = k after MCS k): sb = 16(k-1), sa = 0, ob = 32k
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:4)
            @test [x[1] for x in refresh_cell(sol, :volume)] == fill(16, 5)
            @test [x[1] for x in refresh_cell(sol, :sb)] == [16.0 * max(k - 1, 0) for k in 0:4]
            @test [x[1] for x in refresh_cell(sol, :sa)] == zeros(5)
            @test [x[1] for x in sol[:ob]] == [32.0 * k for k in 0:4]
            @test [x[1] for x in observe(sol, :ob)] == [32.0 * k for k in 0:4]
        end
    end
end

@testitem "integral refresh: refresh phases of every reader kind" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "integral refresh: refresh phases of every reader kind" begin
        c, ph = refresh_phases(Readers)
        n = (
            pre = iname(c, Potts.Pre, :w), y = iname(c, identity, :y), u = iname(c, identity, :u),
            v = iname(c, identity, :v), w2 = iname(c, w -> 2w, :w), y2 = iname(c, y -> y^2, :y),
        )
        @test length(unique(values(n))) == 6                                  # fixture: six integrals
        # the after block refreshes y and u (read after the sweep, clean) and nothing else:
        # not Pre(w) (before only), v (temperature only), 2w or y^2 (observed only)
        @test sort(refresh_refreshed(ph.after_mcs)) == sort([n.y, n.u])          # DEFECT CHECK (today + Pre(w), y^2)
        @test allunique(refresh_refreshed(ph.after_mcs))
        @test isempty(refresh_refreshed(ph.before_mcs))                          # nothing written before the sweep
        for (k, t) in zip((:before_mcs, :after_mcs, :end_mcs, :at_init), tuples(ph)), m in (n.w2, n.y2)
            @test !(m in refresh_refreshed(t))                                   # DEFECT CHECK (end_mcs, at_init)
        end
        # before-block and temperature integrals stay fresh at the boundary and at init
        for m in (n.pre, n.y, n.v)
            @test m in refresh_refreshed(ph.end_mcs) && m in refresh_refreshed(ph.at_init)
        end
        cols = refresh_columns(refresh_problem(Readers))
        @test cols == sort([n.pre, n.y, n.u, n.v])                            # DEFECT CHECK (+ 2w, y^2 today)
        @test all(m -> m in cols, reduce(vcat, map(refresh_refreshed, tuples(ph))))
    end
end

@testitem "integral refresh: observed-only integrals cost no phase" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "integral refresh: observed-only integrals cost no phase" begin
        _, pw = refresh_phases(CostObserved)
        _, pl = refresh_phases(CostLean)
        for (tw, tl) in zip(tuples(pw), tuples(pl))
            @test map(x -> nameof(typeof(x)), collect(tw)) == map(x -> nameof(typeof(x)), collect(tl))   # DEFECT CHECK
            @test refresh_refreshed(tw) == refresh_refreshed(tl)                                                # DEFECT CHECK
        end
    end
end

@testitem "integral refresh: every integral reader sees the same values" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Values against oracles from the saved states
    @testset "integral refresh: every integral reader sees the same values ($(nameof(typeof(alg))))" for alg in ALGS
        K = 8
        prob = refresh_problem(Readers, K)
        sol = solve(prob, alg; saveat = 0:K)
        σs = [Array(u.ownership) for u in sol.u]
        ws = [Array(u.site.w) for u in sol.u]
        # the saved state: w = w0 + k after MCS k, u and y untouched, v ≡ 1
        @test all(k -> ws[k + 1] == REFRESH_W0 .+ k, 0:K)
        @test all(u -> Array(u.site.u) == REFRESH_U0 && Array(u.site.y) == REFRESH_Y0 && all(==(1.0), Array(u.site.v)), sol.u)
        # negative control: the cells moved, so the pre-sweep and post-sweep σ fold differently
        @test any(k -> fold(σs[k], REFRESH_Y0) != fold(σs[k + 1], REFRESH_Y0), 1:K)
        @test any(k -> fold(σs[k], REFRESH_U0) != fold(σs[k + 1], REFRESH_U0), 1:K)
        @test any(k -> fold(σs[k], ws[k]) != fold(σs[k + 1], ws[k]), 1:K)
        @test all(k -> all(>(0), fold(σs[k + 1], ones(16, 16))), 0:K)   # both cells live
        # before block: σ and w at the end of the previous MCS
        @test refresh_cell(sol, :sb)[2:end] ≈ [fold(σs[k], ws[k]) for k in 1:K]
        @test refresh_cell(sol, :sy)[2:end] ≈ [fold(σs[k], REFRESH_Y0) for k in 1:K]
        # after block: σ after the sweep
        @test refresh_cell(sol, :sa)[2:end] ≈ [fold(σs[k + 1], REFRESH_U0) for k in 1:K]
        @test refresh_cell(sol, :ay)[2:end] ≈ [fold(σs[k + 1], REFRESH_Y0) for k in 1:K]
        # observed: each saved state, including the initial one
        ob = [fold(σs[k + 1], 2 .* ws[k + 1]) for k in 0:K]
        oq = [fold(σs[k + 1], REFRESH_Y0 .^ 2) for k in 0:K]
        oc = [fold(σs[k + 1], REFRESH_U0 .+ 2 .* ws[k + 1]) for k in 0:K]
        @test Array.(sol[:ob]) ≈ ob
        @test Array.(observe(sol, :ob)) ≈ ob
        @test Array.(sol[:oq]) ≈ oq
        @test Array.(observe(sol, :oq)) ≈ oq
        @test Array.(sol[:oc]) ≈ oc
        @test Array.(observe(sol, :oc)) ≈ oc
        @test Array(observe(prob, :ob)) ≈ ob[1]
        @test Array(observe(prob, :oq)) ≈ oq[1]
        @test Array(observe(prob, :oc)) ≈ oc[1]
        # querying leaves the solution as it was (the observed integrals are computed on the side)
        @test [Array(u.ownership) for u in sol.u] == σs && [Array(u.site.w) for u in sol.u] == ws
        # temperature: the same trajectory as the twin reading the volume without an integral
        twin = solve(refresh_problem(ReadersTwin, K), alg; saveat = 0:K)
        @test [Array(u.ownership) for u in twin.u] == σs
        for x in (:sb, :sy, :sa, :ay)
            @test refresh_cell(twin, x) == refresh_cell(sol, x)
        end
        # control: the trajectory depends on the temperature
        flat = solve(refresh_problem(ReadersConstT, K), alg; saveat = 0:K)
        @test [Array(u.ownership) for u in flat.u] != σs
    end
end

@testitem "integral refresh: warm steps allocate nothing" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "integral refresh: warm steps allocate nothing" begin
        integ = init(refresh_problem(Readers, 100), SequentialCPM(); save_everystep = false)
        warm() = (step!(integ); @allocated step!(integ))
        @test minimum(warm() for _ in 1:5) == 0
    end
end

@testitem "integral refresh: observed-only integrals cost nothing per MCS" setup = [IntegralRefreshSetup] tags = [:pottsmodels, :acceptance] begin
    # Amended under D-131: the D-120 bound `to <= 1.1 * tl` failed under parallel
    # load (1.854 vs 1.545 ms) and passed alone. The primary check is now structural, on what
    # the problem actually runs: the 8 observed-only integrals add no phase, no refresh and no
    # cell column to the problem built for `init` (`prob.f.phases`, `prob.u0`), so a warm MCS
    # does the same work as without them. The timing check stays as a loose backstop: paired
    # rounds (each pair timed back to back, so load hits both alike), the minimum ratio over
    # the rounds, at most 1.5× (≈ 3.6× with the waste).
    @testset "integral refresh: observed-only integrals cost nothing per MCS ($(nameof(typeof(alg))))" for alg in ALGS
        po, pl = cost_problem(CostObserved), cost_problem(CostLean)
        # structural: the problem's own phases, as `init` runs them
        for (k, tw, tn) in zip((:before_mcs, :after_mcs, :end_mcs, :at_init), tuples(po.f.phases), tuples(pl.f.phases))
            @test map(x -> nameof(typeof(x)), collect(tw)) == map(x -> nameof(typeof(x)), collect(tn))   # DEFECT CHECK
            @test refresh_refreshed(tw) == refresh_refreshed(tn)                                                # DEFECT CHECK
        end
        @test length(refresh_refreshed(po.f.phases.after_mcs)) == 1          # the one after-block integral
        @test refresh_columns(po) == refresh_columns(pl)                          # DEFECT CHECK (+8 columns today)
        @test length(refresh_columns(pl)) == 1
        # timing backstop: paired rounds, the minimum ratio
        io, il = init(po, alg), init(pl, alg)
        foreach(_ -> (step!(io); step!(il)), 1:5)
        rs = map(1:15) do r
            to, tl = isodd(r) ? (refresh_time(io; reps = 3), refresh_time(il; reps = 3)) :
                reverse((refresh_time(il; reps = 3), refresh_time(io; reps = 3)))
            to / tl
        end
        ok = minimum(rs) <= 1.5
        @test ok                                                            # DEFECT CHECK (≈ 3.6× with the waste)
        ok || @info "integral refresh: per-MCS time ratio with/without 8 observed-only integrals, paired rounds: $(round.(rs; digits = 2))"
    end
end
