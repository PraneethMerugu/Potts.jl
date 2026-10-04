# P6.0t (ROADMAP Phase 6, step 0): integral refreshes only for readers after the sweep.
# Decision: D-120. Frozen (AUTONOMY §7.3). Related: D-042/D-076 (update blocks read fresh
# integrals), P6.0m3 (`integral(Pre(w))` slots), D-110 (P6.0ai: hoisted fold slots before
# the refreshes), D-016/D-118 (fingerprint).
#
# The waste (found in the P6.0m3 review; measured on 432a0a74). `_phases_parts` in
# src/codegen.jl refreshes, once any integral is read after the sweep, EVERY integral not
# dirtied by the after block at the start of the after block: also those read only by the
# before block or the temperature (fresh from the previous `end_mcs`, read before this
# point) and those read only by `@observed` (observed queries recompute their integrals from
# the saved state, `_fresh_integrals`). `end_mcs` and `at_init` refresh every integral too,
# observed-only ones included, and each observed-only integral has a cell column. On the
# `PWaste` probe (/tmp/p60m3/rv1/probe.jl, P60tWaste below) today:
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
#  3. Cost: with only observed-only integrals added, a warm MCS takes at most 1.1× the same
#     model without them (min over repetitions, both algorithms).
#  4. Fingerprints unchanged (recorded on 432a0a74) for the PottsModels systems (no
#     integrals) and for an integral model whose integrals are all read after the sweep.
#
# Not pinned: whether `end_mcs` keeps refreshing integrals read only after the sweep (their
# saved columns are not part of the user-facing state); the ordering of refreshes.

using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures

# the PWaste probe: sb reads Pre(w) before the sweep only; sa reads u after it; ob is
# observed only
@potts_model P60tWaste begin
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
@potts_model P60tReaders begin
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
@potts_model P60tReadersTwin begin
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
@potts_model P60tReadersConstT begin
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
# x before AND after the sweep. Its phases (so its fingerprint) must not change.
@potts_model P60tAfterOnly begin
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
@potts_model P60tCostObserved begin
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
@potts_model P60tCostLean begin
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

const P60T_ALGS = (SequentialCPM(), CheckerboardCPM())

# ---------------------------------------------------------------------------------------
# Helpers

"""Compiled system and phases (`Potts._phases`) of model `M`."""
function p60t_phases(M)
    c = mtkcompile(M(; name = :m))
    return c, Potts._phases(c, Float64, Dict{Any, Any}(Potts._unwrap(x) => Potts.info(x).default for x in c.sys.parameters),
        Potts._resolve_solvers(c))
end

# a refresh phase, gated or not, and the cell column it writes
p60t_reduce(x) = x isa CorePotts.CellReduce ? x : x isa Potts._Gated && x.phase isa CorePotts.CellReduce ? x.phase : nothing
p60t_dst(r) = typeof(r.dst).parameters[2]
"""Names of the integral columns refreshed by the phases `t`, in order (with repeats)."""
p60t_refreshed(t) = Symbol[p60t_dst(r) for r in map(p60t_reduce, collect(t)) if r !== nothing]
p60t_tuples(ph) = (ph.before_mcs, ph.after_mcs, ph.end_mcs, ph.at_init)

"""Column name of `integral(f(vars...))` for the model's variables named `names`."""
function p60t_iname(c, f, names...)
    vs = [only(filter(x -> Potts.info(x).name === n, c.sys.variables)) for n in names]
    return Potts._integral_name(Potts._unwrap(f(vs...)))
end

"""The `integral_*` cell columns of a problem's state."""
p60t_columns(prob) = sort!([n for n in propertynames(prob.u0.cell) if startswith(String(n), "integral_")])

# moving cells: two 4×4 cells on 16×16; site fields varying in space
const P60T_SIGMA = (s = zeros(Int32, 16, 16); s[3:6, 3:6] .= 1; s[9:12, 9:12] .= 2; s)
const P60T_W0 = [Float64(j) for i in 1:16, j in 1:16]
const P60T_U0 = [Float64(3i - j) for i in 1:16, j in 1:16]
const P60T_Y0 = [Float64(i + 2j) for i in 1:16, j in 1:16]
p60t_op() = [ownership => P60T_SIGMA, kind => [:A, :A], :w => P60T_W0, :u => P60T_U0, :y => P60T_Y0]
p60t_problem(M, K = 8) = PottsProblem(M(; name = :m), p60t_op(), (0, K))

"""Per cell 1:2, Σ over the sites of cell c in σ of `x`."""
p60t_fold(σ, x) = [sum(x[i] for i in eachindex(σ) if σ[i] == c; init = 0.0) for c in 1:2]
p60t_cell(sol, n) = [Array(getproperty(u.cell, n)) for u in sol.u]

# ---------------------------------------------------------------------------------------
# 1. Phases

@testset "P6.0t: the PWaste probe refreshes only what is read after the sweep" begin
    c, ph = p60t_phases(P60tWaste)
    n_u = p60t_iname(c, identity, :u)
    n_pre = p60t_iname(c, Potts.Pre, :w)
    n_ob = p60t_iname(c, w -> 2w, :w)
    @test length(unique([n_u, n_pre, n_ob])) == 3                        # fixture: three integrals
    after = p60t_refreshed(ph.after_mcs)
    @test after == [n_u]                                                  # DEFECT CHECK (today Pre(w), u)
    # at the start: before the after block's first update
    i1 = findfirst(x -> p60t_reduce(x) !== nothing, ph.after_mcs)
    @test i1 !== nothing && i1 < findfirst(x -> x isa CorePotts.CellPhase || x isa CorePotts.SitePhase, ph.after_mcs)
    # the observed-only integral: no refresh anywhere, no column
    @testset "no refresh of the observed-only integral in $k" for (k, t) in zip((:before_mcs, :after_mcs, :end_mcs, :at_init), p60t_tuples(ph))
        @test !(n_ob in p60t_refreshed(t))                                # DEFECT CHECK (end_mcs, at_init)
    end
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    prob = PottsProblem(P60tWaste(; name = :m), [ownership => σ, kind => [:A]], (0, 4))
    cols = p60t_columns(prob)
    @test !(n_ob in cols)                                                 # DEFECT CHECK (slot)
    @test n_pre in cols && n_u in cols                                    # the read ones keep theirs
    # the before block's integral is still fresh at every boundary and at init
    @test n_pre in p60t_refreshed(ph.end_mcs) && n_pre in p60t_refreshed(ph.at_init)
    # every refresh writes an existing column
    @test all(n -> n in cols, reduce(vcat, map(p60t_refreshed, p60t_tuples(ph))))
    # values (T = 0, the cell never moves; w = k after MCS k): sb = 16(k-1), sa = 0, ob = 32k
    for alg in P60T_ALGS
        sol = solve(prob, alg; saveat = 0:4)
        @test [x[1] for x in p60t_cell(sol, :volume)] == fill(16, 5)
        @test [x[1] for x in p60t_cell(sol, :sb)] == [16.0 * max(k - 1, 0) for k in 0:4]
        @test [x[1] for x in p60t_cell(sol, :sa)] == zeros(5)
        @test [x[1] for x in sol[:ob]] == [32.0 * k for k in 0:4]
        @test [x[1] for x in observe(sol, :ob)] == [32.0 * k for k in 0:4]
    end
end

@testset "P6.0t: refresh phases of every reader kind" begin
    c, ph = p60t_phases(P60tReaders)
    n = (pre = p60t_iname(c, Potts.Pre, :w), y = p60t_iname(c, identity, :y), u = p60t_iname(c, identity, :u),
        v = p60t_iname(c, identity, :v), w2 = p60t_iname(c, w -> 2w, :w), y2 = p60t_iname(c, y -> y^2, :y))
    @test length(unique(values(n))) == 6                                  # fixture: six integrals
    # the after block refreshes y and u (read after the sweep, clean) and nothing else:
    # not Pre(w) (before only), v (temperature only), 2w or y^2 (observed only)
    @test sort(p60t_refreshed(ph.after_mcs)) == sort([n.y, n.u])          # DEFECT CHECK (today + Pre(w), y^2)
    @test allunique(p60t_refreshed(ph.after_mcs))
    @test isempty(p60t_refreshed(ph.before_mcs))                          # nothing written before the sweep
    for (k, t) in zip((:before_mcs, :after_mcs, :end_mcs, :at_init), p60t_tuples(ph)), m in (n.w2, n.y2)
        @test !(m in p60t_refreshed(t))                                   # DEFECT CHECK (end_mcs, at_init)
    end
    # before-block and temperature integrals stay fresh at the boundary and at init
    for m in (n.pre, n.y, n.v)
        @test m in p60t_refreshed(ph.end_mcs) && m in p60t_refreshed(ph.at_init)
    end
    cols = p60t_columns(p60t_problem(P60tReaders))
    @test cols == sort([n.pre, n.y, n.u, n.v])                            # DEFECT CHECK (+ 2w, y^2 today)
    @test all(m -> m in cols, reduce(vcat, map(p60t_refreshed, p60t_tuples(ph))))
end

@testset "P6.0t: observed-only integrals cost no phase" begin
    _, pw = p60t_phases(P60tCostObserved)
    _, pl = p60t_phases(P60tCostLean)
    for (tw, tl) in zip(p60t_tuples(pw), p60t_tuples(pl))
        @test map(x -> nameof(typeof(x)), collect(tw)) == map(x -> nameof(typeof(x)), collect(tl))   # DEFECT CHECK
        @test p60t_refreshed(tw) == p60t_refreshed(tl)                                                # DEFECT CHECK
    end
end

# ---------------------------------------------------------------------------------------
# 2. Values against oracles from the saved states

@testset "P6.0t: every integral reader sees the same values ($(nameof(typeof(alg))))" for alg in P60T_ALGS
    K = 8
    prob = p60t_problem(P60tReaders, K)
    sol = solve(prob, alg; saveat = 0:K)
    σs = [Array(u.σ) for u in sol.u]
    ws = [Array(u.site.w) for u in sol.u]
    # the saved state: w = w0 + k after MCS k, u and y untouched, v ≡ 1
    @test all(k -> ws[k + 1] == P60T_W0 .+ k, 0:K)
    @test all(u -> Array(u.site.u) == P60T_U0 && Array(u.site.y) == P60T_Y0 && all(==(1.0), Array(u.site.v)), sol.u)
    # negative control: the cells moved, so the pre-sweep and post-sweep σ fold differently
    @test any(k -> p60t_fold(σs[k], P60T_Y0) != p60t_fold(σs[k + 1], P60T_Y0), 1:K)
    @test any(k -> p60t_fold(σs[k], P60T_U0) != p60t_fold(σs[k + 1], P60T_U0), 1:K)
    @test any(k -> p60t_fold(σs[k], ws[k]) != p60t_fold(σs[k + 1], ws[k]), 1:K)
    @test all(k -> all(>(0), p60t_fold(σs[k + 1], ones(16, 16))), 0:K)   # both cells live
    # before block: σ and w at the end of the previous MCS
    @test p60t_cell(sol, :sb)[2:end] ≈ [p60t_fold(σs[k], ws[k]) for k in 1:K]
    @test p60t_cell(sol, :sy)[2:end] ≈ [p60t_fold(σs[k], P60T_Y0) for k in 1:K]
    # after block: σ after the sweep
    @test p60t_cell(sol, :sa)[2:end] ≈ [p60t_fold(σs[k + 1], P60T_U0) for k in 1:K]
    @test p60t_cell(sol, :ay)[2:end] ≈ [p60t_fold(σs[k + 1], P60T_Y0) for k in 1:K]
    # observed: each saved state, including the initial one
    ob = [p60t_fold(σs[k + 1], 2 .* ws[k + 1]) for k in 0:K]
    oq = [p60t_fold(σs[k + 1], P60T_Y0 .^ 2) for k in 0:K]
    oc = [p60t_fold(σs[k + 1], P60T_U0 .+ 2 .* ws[k + 1]) for k in 0:K]
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
    @test [Array(u.σ) for u in sol.u] == σs && [Array(u.site.w) for u in sol.u] == ws
    # temperature: the same trajectory as the twin reading the volume without an integral
    twin = solve(p60t_problem(P60tReadersTwin, K), alg; saveat = 0:K)
    @test [Array(u.σ) for u in twin.u] == σs
    for x in (:sb, :sy, :sa, :ay)
        @test p60t_cell(twin, x) == p60t_cell(sol, x)
    end
    # control: the trajectory depends on the temperature
    flat = solve(p60t_problem(P60tReadersConstT, K), alg; saveat = 0:K)
    @test [Array(u.σ) for u in flat.u] != σs
end

@testset "P6.0t: warm steps allocate nothing" begin
    integ = init(p60t_problem(P60tReaders, 100), SequentialCPM())
    warm() = (step!(integ); @allocated step!(integ))
    @test minimum(warm() for _ in 1:5) == 0
end

# ---------------------------------------------------------------------------------------
# 3. Cost: observed-only integrals are free

const P60T_COST_SIGMA = (s = zeros(Int32, 128, 128); for a in 0:15, b in 0:15
    s[8a+1:8a+8, 8b+1:8b+8] .= 16a + b + 1
end; s)
const P60T_COST_Y0 = [Float64(i + j) / 64 for i in 1:128, j in 1:128]
p60t_cost_problem(M) = PottsProblem(M(; name = :m), [ownership => P60T_COST_SIGMA, kind => fill(:A, 256), :y => P60T_COST_Y0], (0, 10^6))

"""Minimum over `reps` of the mean wall time (s) of `n` warm MCS of `integ`."""
function p60t_time(integ; n = 20, reps = 7)
    return minimum(1:reps) do _
        t = time_ns()
        for _ in 1:n
            step!(integ)
        end
        (time_ns() - t) / n / 1e9
    end
end

@testset "P6.0t: observed-only integrals cost nothing per MCS ($(nameof(typeof(alg))))" for alg in P60T_ALGS
    io = init(p60t_cost_problem(P60tCostObserved), alg)
    il = init(p60t_cost_problem(P60tCostLean), alg)
    foreach(_ -> (step!(io); step!(il)), 1:5)
    # interleaved rounds, the best of each
    to, tl = Inf, Inf
    for _ in 1:3
        to = min(to, p60t_time(io))
        tl = min(tl, p60t_time(il))
    end
    ok = to <= 1.1 * tl
    @test ok                                                            # DEFECT CHECK (today ≈ 3.6×)
    ok || @info "P6.0t: per-MCS time with 8 observed-only integrals $(round(1e3to; digits = 3)) ms, without $(round(1e3tl; digits = 3)) ms"
end

# ---------------------------------------------------------------------------------------
# 4. Fingerprints that must not change (recorded on 432a0a74)

p60t_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
p60t_published() = (
    (:GranerGlazier, () -> (g = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => g[1], kind => g[2]], (0, 10)))),
    (:WortelAct, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => p60t_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:WortelActConnected, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [ownership => p60t_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:MerksVasculogenesis, () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
    (:SingleDivisionFixture, () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10))),
    (:OpenVTGrowingMonolayer, () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10))),
    (:AkeebInvasion, () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), akeeb_state(; lattice = (99, 60)), (0, 10);
        capacity = 1000)),
    (:P60tAfterOnly, () -> PottsProblem(P60tAfterOnly(; name = :m), [ownership => P60T_SIGMA, kind => [:A, :A]], (0, 10))),
)
const P60T_FINGERPRINTS = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x04a4528dcdf3fcb8,  # re-pinned under D-122
    :WortelAct => 0xd6d4f8e4e7850c5e,  # re-pinned under D-122
    :WortelActConnected => 0xa2b5702602b1e8f9,  # re-pinned under D-122
    :MerksVasculogenesis => 0x984e2ad5906fc999,  # re-pinned under D-122
    :SingleDivisionFixture => 0x13a4ddc2bb677287,
    :OpenVTGrowingMonolayer => 0xfcecc4612f387b5e,  # re-pinned under D-122
    :AkeebInvasion => 0x2753e2b233bda47b,
    :P60tAfterOnly => 0xa1935accc26c00ef,
)

@testset "P6.0t: fingerprints unchanged" begin
    for (name, build) in p60t_published()
        fp = build().f.fingerprint
        @test fp == P60T_FINGERPRINTS[name]
        fp == P60T_FINGERPRINTS[name] || @info "P6.0t: fingerprint $name = $(repr(fp))"
    end
end
