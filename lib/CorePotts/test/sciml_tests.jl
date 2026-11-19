# SciML integration: ensembles vary the replica stream; DiscreteCallbacks run at MCS
# boundaries.

@testsetup module CP_sciml
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake, solve, solve!, init, step!, reinit!
const SII = CorePotts.SymbolicIndexingInterface
using ForwardDiff: ForwardDiff, Dual
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
using SciMLBase: ContinuousCallback

# P6.15m m3: a CallbackSet of two differently typed DiscreteCallbacks with `saveat` segfaulted
# on the host CheckerboardCPM path (GC heap corruption, found in a later `_save!`). The
# integrator looped `for cb in integ.callbacks`, which carries a `Union` of the callback types
# (closures and a BitVector next to bits fields), and Julia 1.12's optimized code for that
# loop corrupted the heap; it depends on the heap layout, so the crash itself reproduces only
# in a full model run (the OpenVT chain test in PottsModels). Here: the callback paths hold
# no such `Union`, and every hook of every callback still runs, in order.
struct AtMCS{K} end                     # a condition type per MCS: distinct callback types
(::AtMCS{K})(u, t, integ) where {K} = t == K

# D-009 (P6.0cc): without an algorithm, SequentialCPM() on the CPU; a device backend has no
# default and says to pass CheckerboardCPM
struct P60ccDevice <: CorePotts.KernelAbstractions.Backend end
include("shared/export_all.jl")
end

@testitem "SciML ensembles and callbacks" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "SciML ensembles and callbacks" begin
        σ, kinds = blocks((40, 40), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((40, 40)), (0, 10), gg_params(); seed = 3)
        alg = SequentialCPM(; proposal = Moore(1))

        @testset "ensembles: trajectory i is replica i" begin
            ens = solve(EnsembleProblem(prob), alg, EnsembleSerial(); trajectories = 3)
            @test length(ens.u) == 3
            @test ens.u[1].u[end].ownership != ens.u[2].u[end].ownership
            @test ens.u[2].u[end].ownership == solve(remake(prob; replica = 2), alg).u[end].ownership
            thr = solve(EnsembleProblem(prob), alg, EnsembleThreads(); trajectories = 3)
            @test all(i -> thr.u[i].u[end].ownership == ens.u[i].u[end].ownership, 1:3)        # reproducible, any scheduler
            # a prob_func that changes parameters still gets distinct replicas
            pf(q, ctx) = remake(q; p = merge(q.p, (; T = 5.0)))
            e2 = solve(EnsembleProblem(prob; prob_func = pf), alg, EnsembleSerial(); trajectories = 2)
            @test e2.u[1].u[end].ownership != e2.u[2].u[end].ownership && e2.u[1].prob.p.T == 5.0
            # … unless it chooses the seed or replica itself
            pinned(q, ctx) = remake(q; replica = 7)
            e3 = solve(EnsembleProblem(prob; prob_func = pinned), alg, EnsembleSerial(); trajectories = 2)
            @test e3.u[1].u[end].ownership == e3.u[2].u[end].ownership
        end

        @testset "DiscreteCallback at MCS boundaries" begin
            seen = Int[]
            log = DiscreteCallback((u, t, integ) -> iseven(t), integ -> push!(seen, integ.t))
            stop = DiscreteCallback((u, t, integ) -> t == 4, integ -> terminate!(integ))
            sol = solve(prob, alg; callback = CallbackSet(log, stop))
            @test seen == [2, 4]
            @test sol.t[end] == 4 && sol.retcode == ReturnCode.Terminated
            # affect! may change the live state and parameters; saved states see it
            heat = DiscreteCallback((u, t, integ) -> t == 3, integ -> (integ.p = merge(integ.p, (; T = 1.0e6))))
            s2 = solve(prob, alg; callback = heat, saveat = [3, 10])
            @test s2.t == [0, 3, 3, 10]                # the `saveat` save before the affect, one after
            integ = init(prob, alg; callback = heat)
            foreach(_ -> step!(integ), 1:3)
            @test integ.p.T == 1.0e6
        @test_throws ArgumentError init(prob, alg; callback = ContinuousCallback((u, t, i) -> t - 1, i -> nothing))
            # initialize/finalize hooks run once
            calls = Int[]
            cb = DiscreteCallback(
                (u, t, i) -> false, i -> nothing;
                initialize = (c, u, t, i) -> push!(calls, 1), finalize = (c, u, t, i) -> push!(calls, 2)
            )
            solve(prob, alg; callback = cb)
            @test calls == [1, 2]
        end
    end
end

@testitem "CallbackSet of differently typed callbacks with saveat" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "CallbackSet of differently typed callbacks with saveat" begin
        σ, kinds = blocks((30, 30), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((30, 30)), (0, 12), gg_params(); seed = 5)
        # a Union of callback types, or (beyond the union-splitting limit) an abstract one
        is_cb_union(T) = T !== Union{} && T <: DiscreteCallback && !isconcretetype(T)
        cb_unions(f, types) = count(
            is_cb_union ∘ CorePotts.Core.Compiler.widenconst,
            only(code_typed(f, types; optimize = true)).first.ssavaluetypes
        )
        @testset "$(nameof(typeof(alg)))" for alg in (CheckerboardCPM(; proposal = Moore(1)), SequentialCPM(; proposal = Moore(1)))
            calls = Tuple{Symbol, Int}[]
            snap = Ref(0)
            mark = DiscreteCallback(
                (u, t, integ) -> t == 4, integ -> (snap[] = integ.stats.mcs; nothing);
                save_positions = (false, false), initialize = (c, u, t, i) -> push!(calls, (:init, 1)),
                finalize = (c, u, t, i) -> push!(calls, (:final, 1))
            )
            heat = DiscreteCallback(
                (u, t, integ) -> t == 4, integ -> (integ.ps[:T] = 2 * integ.ps[:T]; nothing);
                initialize = (c, u, t, i) -> push!(calls, (:init, 2)), finalize = (c, u, t, i) -> push!(calls, (:final, 2))
            )
            integ = init(prob, alg; saveat = 0:12, callback = CallbackSet(mark, heat))
            T = typeof(integ)
            @test typeof(integ.callbacks) === Tuple{typeof(mark), typeof(heat)}       # two distinct types
            @test cb_unions(CorePotts._apply_callbacks!, (T,)) == 0
            @test cb_unions(CorePotts.CommonSolve.step!, (T,)) == 0
            @test cb_unions(CorePotts.CommonSolve.solve!, (T,)) == 0
            sol = solve!(integ)
            # MCS 4: the `saveat` save, then `heat`'s saves before and after its affect (`save_positions`)
            @test sol.t == sort!([0:12; 4; 4]) && length(sol.u) == 15
            @test snap[] == 4 && sol.prob.p.T == gg_params().T && integ.p.T == 2 * gg_params().T
            @test calls == [(:init, 1), (:init, 2), (:final, 1), (:final, 2)]
            # stress: many solves with saves, then a full collection (the crash surfaced in GC)
            for s in 1:20
                r = solve(remake(prob; seed = s), alg; saveat = 0:12, callback = CallbackSet(mark, heat))
                @test length(r.u) == 15
            end
            GC.gc(true)
            @test true
        end
        # negative control: a plain `for` loop over the same tuple does carry the Union
        loop(cbs) = (
            for cb in cbs
                cb.condition(nothing, 0, nothing)
            end; nothing
        )
        m = DiscreteCallback((u, t, i) -> t == 1, i -> nothing; save_positions = (false, false))
        h = DiscreteCallback((u, t, i) -> t == 2, i -> nothing)
        @test cb_unions(loop, (Tuple{typeof(m), typeof(h)},)) > 0
        # 33 differently typed callbacks: past `Base.afoldl`'s 31 unrolled elements, which would
        # fall back to a loop carrying an abstract callback type (negative control below)
        @testset "33 callbacks, $(nameof(typeof(alg)))" for alg in (CheckerboardCPM(; proposal = Moore(1)), SequentialCPM(; proposal = Moore(1)))
            long = remake(prob; tspan = (0, 40))
            hits = zeros(Int, 33)
            cbs = ntuple(k -> DiscreteCallback(AtMCS{k}(), integ -> (hits[k] += 1; nothing)), 33)
            @test allunique(map(typeof, cbs))
            integ = init(long, alg; saveat = 0:40, callback = CallbackSet(cbs...))
            T = typeof(integ)
            @test cb_unions(CorePotts._apply_callbacks!, (T,)) == 0
            @test cb_unions(CorePotts.CommonSolve.step!, (T,)) == 0
            @test cb_unions(CorePotts.CommonSolve.solve!, (T,)) == 0
            # each callback specialized: a warm check of all 33 allocates nothing (a dynamic call
            # per callback would box)
            CorePotts._apply_callbacks!(integ)
            @test @allocated(CorePotts._apply_callbacks!(integ)) == 0
            sol = solve!(integ)
            @test sol.t == sort!([0:40; 1:33]) && hits == ones(Int, 33)     # each fires once, saved after
            GC.gc(true)
        end
        # negative control: `Base.afoldl` over the same 33 callbacks goes dynamic and allocates
        cbs = ntuple(k -> DiscreteCallback(AtMCS{k}(), i -> nothing), 33)
        folded(t) = (Base.afoldl((_, cb) -> (cb.condition(nothing, 0, nothing); nothing), nothing, t...); nothing)
        eached(t) = CorePotts._each(cb -> (cb.condition(nothing, 0, nothing); nothing), t)
        folded(cbs), eached(cbs)
        @test @allocated(folded(cbs)) > 0
        @test @allocated(eached(cbs)) == 0
    end
end

# D-116: a problem without a model whose parameter object is a NamedTuple has its fields as
# parameter names; `remake_buffer` (and `setp_oop`, which calls it) returns a new NamedTuple.
@testitem "remake_buffer on a NamedTuple parameter object" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "remake_buffer on a NamedTuple parameter object" begin
        SII = CorePotts.SymbolicIndexingInterface
        σ, kinds = blocks((20, 20), 5)
        gp = PottsProblem(GG, initial_state(σ, kinds), Lattice((20, 20)), (0, 2), gg_params(); seed = 3)
        gi = init(gp, SequentialCPM())
        # without a CorePotts method, SII's untyped fallback and its deprecated `Dict` method call
        # each other forever: check the method instead of risking the test process
        # (`setp_oop` calls it on the root container, with tuples)
        m = which(SII.remake_buffer, Tuple{typeof(gp), typeof(gp.p), Vector{Symbol}, Vector{Float64}})
        mo = which(SII.remake_buffer, Tuple{typeof(SII.symbolic_container(gi)), typeof(gp.p), Tuple{Any}, Tuple{Int}})
        @test m.module === CorePotts && mo.module === CorePotts
        if m.module === CorePotts && mo.module === CorePotts
            r = SII.remake_buffer(gp, gp.p, [:T, :λ], [3.0, 2])
            @test typeof(r) === typeof(gp.p) && r == merge(gp.p, (; T = 3.0, λ = 2.0))
            @test gp.p == gg_params()                                         # the original untouched
            @test SII.remake_buffer(gi, gi.p, [:V0], [7]).V0 === 7.0
            @test SII.setp_oop(gi, :T)(gi, 4) == merge(gp.p, (; T = 4.0))
            @test gi.p == gg_params()
            # negative controls: an unknown field; keys and values of different lengths
            @test_throws ArgumentError SII.remake_buffer(gp, gp.p, [:T, :zz], [1.0, 2.0])
            @test_throws DimensionMismatch SII.remake_buffer(gp, gp.p, [:T], [1.0, 2.0])
        end
    end
end

@testitem "default algorithm (D-009)" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "default algorithm (D-009)" begin
        σ, kinds = blocks((20, 20), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((20, 20)), (0, 4), gg_params(); seed = 3)
        @test solve(prob).u[end].ownership == solve(prob, SequentialCPM()).u[end].ownership
        @test init(prob).alg isa SequentialCPM
        @test_throws ArgumentError solve(prob; backend = P60ccDevice())
        @test_throws ArgumentError init(prob; backend = P60ccDevice())
    end
end

@testitem "TS2-2: PottsProblem SciML conformance (solve, init, step!, reinit!, remake, SII, negative controls)" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "TS2-2: PottsProblem SciML conformance" begin
        σ, kinds = blocks((24, 24), 5)
        lat = Lattice((24, 24))
        prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 8), gg_params(); seed = 11)
        for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
            @testset "$(nameof(typeof(alg)))" begin
                s_direct = solve(prob, alg; saveat = 2)
                s_init = solve!(init(prob, alg; saveat = 2))
                @test SciMLBase.successful_retcode(s_direct)
                @test s_direct.t == s_init.t
                @test s_direct.u[end].ownership == s_init.u[end].ownership

                integ = init(prob, alg)
                @test SII.current_time(integ) == 0
                step!(integ)
                @test SII.current_time(integ) == 1
                reinit!(integ)
                @test SII.current_time(integ) == 0
                @test integ.state.ownership == prob.u0.ownership
                s_re = solve!(integ)
                @test s_re.u[end].ownership == s_direct.u[end].ownership

                # reinit! with new state u0
                σ_alt = copy(σ)
                σ_alt[1:4, 1:4] .= 0
                st_alt = initial_state(σ_alt, kinds)
                reinit!(integ, st_alt)
                @test integ.state.ownership == st_alt.ownership
                s_alt = solve!(integ)
                @test s_alt.u[end].ownership == solve(remake(prob; u0 = st_alt), alg).u[end].ownership

                # remake matches fresh PottsProblem
                p2 = merge(gg_params(), (; T = 12.0))
                r_prob = remake(prob; p = p2, tspan = (0, 4), seed = 22)
                f_prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 4), p2; seed = 22)
                @test solve(r_prob, alg).u[end].ownership == solve(f_prob, alg).u[end].ownership
            end
        end

        @testset "SII state_values, parameter_values, current_time, getp/setp" begin
            @test SII.state_values(prob) === prob.u0
            @test SII.parameter_values(prob) === prob.p
            @test SII.current_time(prob) == 0
            @test SII.getp(prob, :T)(prob) == gg_params().T
            integ = init(prob, SequentialCPM())
            @test SII.getp(integ, :T)(integ) == gg_params().T
            SII.setp(integ, :T)(integ, 15.0)
            @test integ.p.T == 15.0
        end

        @testset "negative controls" begin
            integ = init(prob, SequentialCPM())
            # reinit! with different cell capacity is refused
            st_bad = with_capacity(initial_state(σ, kinds), length(kinds) + 5)
            @test_throws ArgumentError reinit!(integ, st_bad)
            # unknown remake keyword
            @test_throws ArgumentError remake(prob; unknown_kw = 1)
            # unknown SII parameter
            @test_throws ArgumentError SII.getp(prob, :no_such_param)
            # ContinuousCallback is refused
            @test_throws ArgumentError init(
                prob, SequentialCPM();
                callback = ContinuousCallback((u, t, i) -> t - 1, i -> nothing)
            )
        end
    end
end

@testitem "TS2-7 (Q7): CorePotts ForwardDiff.Dual refusal messages" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "TS2-7 (Q7): CorePotts ForwardDiff.Dual refusal messages" begin
        # 1. Passing Dual parameters into a plain PottsProblem/SequentialCPM: CorePotts keeps CPM on
        #    concrete floats (derivative parts run through fields only); Dual in cell/temperature
        #    arithmetic or TrackEnergyChange is rejected cleanly.
        σ, kinds = blocks((16, 16), 3)
        lat = Lattice((16, 16))
        dT = Dual{Nothing}(10.0, 1.0)

        # Dual temperature on plain CPMFunction: refused by uniform(::Type{Float...}, ::UInt32)
        f_track = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackEnergyChange{Float64}())
        p_dual_T = PottsProblem(f_track, initial_state(σ, kinds), lat, (0, 2), merge(gg_params(), (; T = dT)))
        @test_throws MethodError solve(p_dual_T, SequentialCPM())

        # 2. CellReduce on a non-CPU device backend refuses Dual / BigFloat columns
        st_dual_col = initial_state(
            σ, kinds; cell = merge(
                init_moments(σ, lat, length(kinds)),
                (; w = fill(Dual{Nothing}(1.0, 0.5), length(kinds)))
            )
        )
        @test_throws ArgumentError CorePotts._cell_reduce!(
            +, (st, p, ctx, key, mcs, i) -> Dual{Nothing}(1.0, 0.5),
            fill(Dual{Nothing}(0.0, 0.0), length(kinds)), CorePotts.Part{:cell, :w},
            st_dual_col, gg_params(), nothing, RNGKey(1), 0, P60ccDevice()
        )
        @test_throws ArgumentError CorePotts._cell_reduce!(
            +, (st, p, ctx, key, mcs, i) -> BigFloat(1.0),
            fill(BigFloat(0.0), length(kinds)), CorePotts.Part{:cell, :w},
            st_dual_col, gg_params(), nothing, RNGKey(1), 0, P60ccDevice()
        )
    end
end

# `DiscreteCallback.save_positions` as SciML (DiffEqBase `apply_discrete_callback!`): a save
# before the affect and one after, each when flagged; a `saveat` MCS at which a callback fires
# is saved before the affect and not saved again by the `saveat` rule
@testitem "DiscreteCallback save_positions: saves before and after the affect" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "DiscreteCallback save_positions: saves before and after the affect" begin
        σ, kinds = blocks((20, 20), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((20, 20)), (0, 6), gg_params(); seed = 4)
        at3(pos) = DiscreteCallback((u, t, integ) -> t == 3, integ -> nothing; save_positions = pos)
        for alg in (SequentialCPM(), CheckerboardCPM())
            solve_at3(pos, saveat) = solve(prob, alg; callback = at3(pos), saveat, save_start = false)
            # oracle: SciML's saves for each flag pair
            @test solve_at3((true, true), [6]).t == [3, 3, 6]
            @test solve_at3((true, false), [6]).t == [3, 6]
            @test solve_at3((false, true), [6]).t == [3, 6]
            @test solve_at3((false, false), [6]).t == [6]
            @test solve_at3((true, true), [3, 6]).t == [3, 3, 6]
            @test solve_at3((false, false), [3, 6]).t == [3, 6]
            # the saved state is the run's state at MCS 3 (the affect changes nothing; same seed)
            ref = solve(prob, alg; saveat = [3], save_start = false, save_end = false)
            s = solve_at3((true, true), [6])
            @test s.u[1].ownership == ref.u[1].ownership && s.u[2].ownership == ref.u[1].ownership
        end
    end
end

# `derivative_discontinuity!` is Potts' method (SciMLBase forwards the deprecated
# `u_modified!` to it); `check_error` is `Success` while the run is healthy, and a
# non-finite energy change ends the run with `Unstable`
@testitem "derivative_discontinuity!, check_error while healthy, Unstable on a non-finite energy" setup = [CP_sciml] tags = [:corepotts, :sciml] begin
    @testset "derivative_discontinuity!, check_error while healthy, Unstable on a non-finite energy" begin
        σ, kinds = blocks((20, 20), 5)
        prob = PottsProblem(GG, initial_state(σ, kinds), Lattice((20, 20)), (0, 4), gg_params(); seed = 4)
        T = typeof(init(prob, SequentialCPM()))
        @test which(SciMLBase.derivative_discontinuity!, (T, Bool)).module === CorePotts
        @test which(SciMLBase.u_modified!, (T, Bool)).module === SciMLBase     # no own alias
        @test !(:u_modified! in names(CorePotts))                                 # no own export
        for alg in (SequentialCPM(), CheckerboardCPM())
            integ = init(prob, alg)
            @test integ.retcode == ReturnCode.Default
            @test SciMLBase.check_error(integ) == ReturnCode.Success
            step!(integ)
            @test SciMLBase.check_error(integ) == ReturnCode.Success
            sol = solve!(integ)
            @test sol.retcode == ReturnCode.Success && SciMLBase.check_error(integ) == ReturnCode.Success
            terminate!(integ)
            @test SciMLBase.check_error(integ) == ReturnCode.Terminated
        end
        bad = PottsProblem(
            CPMFunction((st, p, prop, ctx) -> NaN; temperature = gg_temperature),
            initial_state(σ, kinds), Lattice((20, 20)), (0, 4), gg_params()
        )
        integ = init(bad, SequentialCPM())
        step!(integ)
        @test integ.retcode == ReturnCode.Unstable && SciMLBase.check_error(integ) == ReturnCode.Unstable
        @test_throws ArgumentError step!(integ)                                    # a finished run
    end
end
