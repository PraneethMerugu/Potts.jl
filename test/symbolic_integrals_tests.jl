# Split from test/symbolic_tests.jl

@testitem "history lags: Pre(x, k)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "history lags: Pre(x, k)" begin
        σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
        p = PottsProblem(Lags(; name = :l), [ownership => σ, kind => [1]], (0, 8))
        @test size(p.u0.history.n) == (1, 3) && size(p.u0.history.w) == (8, 8, 2)
        sol = solve(p, SequentialCPM(); saveat = 0:8)
        for m in 1:8                       # after m MCS: n = m; lag3 = n at the end of MCS m - 1 - 3
            u = sol.u[m + 1]
            @test u.model.n[1] == m
            @test u.model.lag3[1] == max(m - 3, 0)
            @test all(==(m == 1 ? 0 : -1), u.site.wlag)                 # w(end m - 3) - w(end m - 2)
        end
        @potts_model _BadLag begin
            @structural_parameters case = 1
            @kinds medium A
            @variables begin
                u(cell) = 0.0
                n(model) = 0.0
            end
            @lattice Lattice((8, 8))
            if case == 1
                @after_mcs u ~ Pre(u, 2)
            elseif case == 2
                @energy cells => Pre(volume, 2)
            else
                @observed q ~ Pre(n, 2)
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        for case in 1:3
            @test_throws ArgumentError mtkcompile(_BadLag(; name = :b, case))
        end
    end
end


@testitem "integral(x): per-cell site reductions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "integral(x): per-cell site reductions" begin
        σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
        w0 = [Float64(i + j) / 40 for i in 1:20, j in 1:20]
        p = PottsProblem(Integrals(; name = :i), [ownership => σ, kind => [1, 1], :w => w0], (0, 5))
        @test p[:cmass] ≈ [sum(w0[σ .== k]) for k in 1:2] && p[:occupied] == [16, 16]   # valid at t0
        sol = solve(p, SequentialCPM(); saveat = 0:5)
        for u in sol.u[2:end]
            @test u.cell.mass ≈ [sum(w0[u.σ .== k]) for k in 1:2]
            @test u.cell.hot ≈ [count(>(0.5), w0[u.σ .== k]) / count(==(k), u.σ) for k in 1:2]
        end
        @test sol[:occupied][end] == sol.u[end].cell.volume                              # integral(1) == volume
        uc = solve(p, CheckerboardCPM()).u[end]
        @test uc.cell.mass ≈ [sum(w0[uc.σ .== k]) for k in 1:2]
        @potts_model _BadIntegral begin
            @structural_parameters case = 1
            @kinds medium A
            @variables w(site) = 0.0 y(cell) = 0.0
            @lattice Lattice((8, 8))
            if case == 1
                @energy cells => integral(w)
            elseif case == 2
                @drive copy => integral(w)
            elseif case == 3
                @on_copy w[target] += integral(w)
            elseif case == 4
                @on_copy w[target] ~ sum(integral(w) for c in cells if c == new)
            elseif case == 5
                @on_copy w[ifelse(sum(integral(w) for c in cells if c == new) > 0, target, source)] ~ 1.0
            else
                @on_copy y[ifelse(sum(integral(w) for c in cells if c == new) > 0, new, old)] ~ 1.0
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        msgs = ("energies", "@before_mcs", "every accepted copy", "@on_copy", "every accepted copy", "every accepted copy")
        for (case, msg) in enumerate(msgs)
            err = try
                mtkcompile(_BadIntegral(; name = :b, case)); nothing
            catch e
                e
            end
            @test err isa ArgumentError && occursin("integral", sprint(showerror, err)) &&
                occursin(msg, sprint(showerror, err))
        end
    end
end


@testitem "integral and lag review regressions" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "integral and lag review regressions" begin
        σ = zeros(Int32, 16, 16); σ[3:8, 3:8] .= 1
        p = PottsProblem(Fresh(; name = :f), [ownership => σ, kind => [1]], (0, 4); capacity = 8)
        sol = solve(p, SequentialCPM(); saveat = 0:4)
        brute(u, x) = [sum(x[u.σ .== c]; init = 0.0) for c in eachindex(u.cell.volume)]
        names = [Potts._integral_name(x) for x in Potts._integrals(p.f.sys.csys.sys)]
        for (t, u) in zip(sol.t, sol.u)
            @test sol[:cmass][t + 1] ≈ brute(u, u.site.w)                 # observed: the saved state itself
            @test sol[:occ][t + 1] == u.cell.volume                        # after division too
            fresh = Potts._fresh_integrals(Float64, u, p.p, p.f.sys.ctx, t, Potts._integral_phases(p.f.sys.csys, Float64), names)
            @test all(n -> getfield(u.cell, n) ≈ getfield(fresh.cell, n), names)   # stored = recomputed at the boundary
        end
        @test sol.stats.lifecycle.divisions >= 1
        @test sol.u[3].model.n[1] == 2 && all(==(1), sol.u[3].site.d1)       # Pre(n, 1) - Pre(n, 2) = 1
        # before-MCS reads see the state at the MCS boundary (at init: the initial state), also after remake
        u1 = solve(remake(p; tspan = (0, 1)), SequentialCPM()).u[end]
        @test u1.cell.mb[1] ≈ 36
        q = remake(p; p = [:k => 5.0], u0 = [ownership => σ, kind => [1], :w => 2.0], tspan = (0, 1))
        @test q[:cmass] ≈ [72; zeros(7)]
        @test solve(q, SequentialCPM()).u[end].cell.mb[1] ≈ 5 * 72
    end
end


@testitem "integral(x) is fresh after a write in the same block (P6.0m, D-042)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "integral(x) is fresh after a write in the same block (P6.0m, D-042)" begin
        @potts_model FreshIntegrals begin
            @kinds medium A
            @variables begin
                w(site) = 0.0
                u(site) = 0.0
                sb(cell) = 0.0
                sa(cell) = 0.0
                s2(cell) = 0.0
                r(cell) = 0.0
            end
            @lattice Lattice((12, 12))
            @energy cells => (volume - 16)^2
            @before_mcs begin
                w ~ Pre(w) + 1
                sb ~ integral(w)
            end
            @after_mcs begin
                u ~ Pre(u) + 1
                sa ~ integral(u) + integral(w)
            end
            @after_mcs Every(2) s2 ~ integral(2u)
            @equations D(r) ~ integral(u)
            @sweep Metropolis(; temperature = 0.0)
        end

        # a 4×4 cell at T = 0 keeps its 16 sites (every copy costs +1); after MCS k, w = u = k
        σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(PottsProblem(FreshIntegrals(; name = :f), [ownership => σ, kind => [:A]], (0, 4)), alg; saveat = 0:4)
            k = 0:4
            @test [Array(u.cell.volume)[1] for u in sol.u] == fill(16, 5)
            @test [Array(u.cell.sb)[1] for u in sol.u] == 16.0 .* k                    # before block
            @test [Array(u.cell.sa)[1] for u in sol.u] == 32.0 .* k                    # after block, two integrals
            # gated reader (Every(2) runs in MCS 1, 3): 2·16k fresh; stale would be 0, 0, 0, 64, 64
            @test [Array(u.cell.s2)[1] for u in sol.u] == [0, 32, 32, 96, 96]
            # the equation (explicit Euler, dt = 1) integrates the fresh value: Σ_{j ≤ k} 16 j
            @test [Array(u.cell.r)[1] for u in sol.u] == [16.0 * sum(1:j; init = 0) for j in k]
            @test [16.0 * sum(0:(j - 1); init = 0) for j in k] != [16.0 * sum(1:j; init = 0) for j in k]   # stale differs
        end
        # no extra pass: w (not written after the sweep) once at the start of the after block;
        # u once before `sa` (which also serves the ODE); 2u gated with its reader; w once before `sb`
        c = mtkcompile(FreshIntegrals(; name = :f))
        ph = Potts._phases(
            c, Float64, Dict{Any, Any}(Potts._unwrap(x) => Potts.info(x).default for x in Potts.parameters(c.sys)),
            Potts._resolve_solvers(c)
        )
        reduces(t) = count(x -> x isa CorePotts.CellReduce || (x isa Potts._Gated && x.phase isa CorePotts.CellReduce), t)
        @test reduces(ph.before_mcs) == 1                  # w written, sb reads it
        @test reduces(ph.after_mcs) == 3
        @test count(x -> x isa Potts._Gated && x.phase isa CorePotts.CellReduce, ph.after_mcs) == 1
    end
end


@testitem "integral(Pre(w)) folds the block-start values (P6.0m3, D-042)" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "integral(Pre(w)) folds the block-start values (P6.0m3, D-042)" begin
        @potts_model IntegralPre begin
            @kinds medium A
            @variables begin
                w(site) = 0.0
                v(site) = 0.0
                x(site) = 0.0
                s(cell) = 0.0
                sb(cell) = 0.0
                f(cell) = 0.0
            end
            @lattice Lattice((12, 12))
            @energy cells => (volume - 16)^2
            @before_mcs begin
                sb ~ integral(Pre(x))
                x ~ Pre(x) + 1
            end
            @after_mcs begin
                v ~ Pre(w)                              # another update reads Pre(w): snapshots w
                s ~ integral(Pre(w)) + integral(Pre(v))
                w ~ Pre(w) + 1
                f ~ integral(w)
            end
            @sweep Metropolis(; temperature = 0.0)
        end

        σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
        c = mtkcompile(IntegralPre(; name = :ip))
        @test (:site, :w) in c.pre_snapshots[:after_mcs]                    # from `v`, not from `s`
        @test !any(t -> last(t) === :v, c.pre_snapshots[:after_mcs])       # `v` read only in an integral
        @test isempty(c.pre_snapshots[:before_mcs])
        # a snapshotted `Pre(w)` both outside and inside an integral: only the outside one is rewritten
        w = only(filter(x -> Potts.info(x).name === :w, Potts.variables(c.sys)))
        snap = Dict{Symbol, Any}(:w => Potts._standin(:site, :w__pre))
        iw = Potts._unwrap(Potts._integral(Potts.Pre(w)))
        @test isequal(Potts._to_snapshots(Potts._unwrap(Potts.Pre(w) + iw), snap, _ -> false), Potts._unwrap(snap[:w] + iw))
        ph = Potts._phases(c, Float64, Dict{Any, Any}(), Potts._resolve_solvers(c))
        reduces(t) = count(x -> x isa CorePotts.CellReduce, t)
        @test reduces(ph.before_mcs) == 0                  # the boundary refresh serves `sb`
        # Pre(w), Pre(v) at the start (read by the after block); w after its writer. Pre(x) is
        # read only by the before block: fresh from the previous boundary (D-120)
        @test reduces(ph.after_mcs) == 3
        i1 = findfirst(x -> x isa CorePotts.CellReduce, ph.after_mcs)
        @test i1 < findfirst(x -> x isa CorePotts.CopyPhase, ph.after_mcs)  # refreshed before the snapshot copy
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 4)), alg; saveat = 0:4)
            k = 0:4
            @test [Array(u.cell.volume)[1] for u in sol.u] == fill(16, 5)
            # s = Σ w_start + Σ v_start; w_start = k - 1, v_start = k - 2 (v lags w by one MCS)
            @test [Array(u.cell.s)[1] for u in sol.u] == [j == 0 ? 0.0 : 16.0 * ((j - 1) + max(j - 2, 0)) for j in k]
            @test [Array(u.cell.f)[1] for u in sol.u] == 16.0 .* k                       # fresh (D-076)
            @test [Array(u.cell.sb)[1] for u in sol.u] == [16.0 * max(j - 1, 0) for j in k]  # before block
        end
        integ = init(PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 100)), SequentialCPM())
        warm() = (step!(integ); @allocated step!(integ))
        @test minimum(warm() for _ in 1:5) == 0

        # misuse: an integral mixing Pre and bare reads of block-written variables; and
        # `integral(Pre(w))` outside update blocks, where Pre is the stored value
        @potts_model _BadIntegralPre begin
            @structural_parameters case = 1
            @kinds medium A
            @variables begin
                w(site) = 0.0
                f(site) = 0.0
                s(cell) = 0.0
                r(cell) = 0.0
            end
            @lattice Lattice((8, 8))
            @energy cells => (volume - 16)^2
            if case == 1
                @after_mcs begin
                    w ~ Pre(w) + 1
                    s ~ integral(Pre(w) + w)
                end
            elseif case == 2
                @after_mcs begin
                    w ~ Pre(w) + 1
                    s ~ integral(Pre(w) * f)
                    f ~ Pre(f)
                end
            elseif case == 3
                @equations D(r) ~ integral(Pre(w))
            elseif case == 4
                @divide cells(A) when = integral(Pre(w)) > 100
            else
                @observed q(cell) ~ integral(Pre(w))
            end
            @sweep Metropolis(; temperature = 1.0)
        end
        for case in 1:5
            @test_throws ArgumentError mtkcompile(_BadIntegralPre(; name = :b, case))
        end
        p = PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 1))
        @test_throws ArgumentError p[Potts._integral(Potts.Pre(w))]
    end
end


@testitem "P6.0ah: equal folds over different variables, independent of operator hashes" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0ah: equal folds over different variables, independent of operator hashes" begin
        @potts_model P60ahTieModel begin
            @kinds medium A
            @variables z(cell) = 1.0 g(model) = 0.5
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @equations D(g) ~ 0.01 * sum(z[c] for c in cells) + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3 - 0.1g
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model P60ahTieCell begin
            @kinds medium A
            @variables z(cell) = 1.0 y(cell) = 0.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @equations D(y) ~ 0.01 * sum(z[c] for c in cells) * y + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3 - 0.1y
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model P60ahTieUpd begin
            @kinds medium A
            @variables z(cell) = 1.0 y(cell) = 0.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @after_mcs y ~ 0.01 * sum(z[c] for c in cells) * y + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model P60ahTieIntegral begin
            @kinds medium A
            @variables c(site) = 1.0 y(cell) = 0.0 w(cell) = 0.0
            @lattice Lattice((12, 8))
            @energy cells => (volume - 16.0)^2
            @after_mcs begin
                y ~ integral(c * sum(volume[k] for k in cells))
                w ~ 2 * integral(c * sum(volume[k] for k in cells))
            end
            @sweep Metropolis(; temperature = 1.0)
        end

        function p60ah_tie_problem(M)
            s = zeros(Int32, 12, 8)
            s[3:6, 3:6] .= 1
            s[7:10, 3:6] .= 2
            return PottsProblem(M(; name = :x), [ownership => s, kind => [:A, :A]], (0, 3); seed = 7, ode_solver = Potts.RK4())
        end

        for M in (P60ahTieModel, P60ahTieCell, P60ahTieUpd, P60ahTieIntegral), solver in (Potts.ExplicitEuler(), Potts.RK4())
            base = p60ah_tie_code(M, solver)
            @test all(s -> p60ah_tie_salted(() -> p60ah_tie_code(M, solver), s) == base, 1:4)
        end
        state(u) = (Array(u.σ), map(Array, u.cell), map(Array, u.site), map(Array, u.model))
        for M in (P60ahTieModel, P60ahTieCell, P60ahTieUpd, P60ahTieIntegral)
            prob = p60ah_tie_problem(M)
            u = state(solve(prob, SequentialCPM()).u[end])
            for s in 1:4
                p = p60ah_tie_salted(() -> p60ah_tie_problem(M), s)
                @test p.f.fingerprint == prob.f.fingerprint
                @test state(solve(p, SequentialCPM()).u[end]) == u
            end
        end
        # the two integrals are distinct trackers (each fold, hoisted to its own slot, keeps its
        # bound variable's name in the key): integral(c · Σ volume) = (Σ_cell volume)², w = 2y
        xs = Potts._integrals(Potts.ModelingToolkitBase.mtkcompile(P60ahTieIntegral(; name = :x)).sys)
        @test length(xs) == 2 && Potts._integral_name(xs[1]) != Potts._integral_name(xs[2])
        s = zeros(Int32, 12, 8)
        s[3:6, 3:6] .= 1
        u = solve(PottsProblem(P60ahTieIntegral(; name = :x), Any[ownership => s, kind => [:A]], (0, 3)), SequentialCPM()).u[end]
        @test u.cell.y == [Float64(u.cell.volume[1])^2]
        @test u.cell.w == 2 .* u.cell.y
    end
end

# D-F2-1 (F2-15): a computed parameter is read-only and derived again from the base parameters
# after every write, transitively (the diamond p₁ → p₂ → p₄ ← p₃ → p₅). Before: settable, an
# explicit value kept (D-112).


@testitem "P6.0ai: integral folds are hoisted, fresh at every refresh (geom, nameof(typeof(alg)))" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @potts_model P60ai begin
        @structural_parameters geom = :square
        @kinds medium A
        @variables begin
            w(site) = 1.0
            v(cell) = 0.0
            s(cell) = 0.0
            bo(cell) = 0.0
            q(cell) = 0.0
            n(cell) = 0.0
            r(cell) = 0.0
        end
        if geom === :square
            @lattice Lattice((16, 16))
        elseif geom === :hex
            @lattice Lattice((16, 16); geometry = Hexagonal(), neighborhood = Hex(1))
        else
            @lattice Lattice((8, 8, 8))
        end
        @energy cells => (volume - 16.0)^2
        @after_mcs begin
            v ~ Pre(v) + 1
            s ~ integral(w * sum(v[c] for c in cells))                       # reads v, new this block
            bo ~ integral(w * (1 - 2 * any(volume[c] > 17 for c in cells)))   # a Boolean fold
            q ~ integral(w * sum(w for x in sites))                          # a fold over sites
            n ~ integral(sum(w * volume[c] for c in cells))                  # reads the site: per site
            r ~ integral(sum(rand() * volume[c] for c in cells) * 1.0e-300 + w) # draws per site: per site
        end
        @observed o(cell) ~ integral(w * mean(volume[c] for c in cells))
        @divide cells(A) when = mcs == 2, along = RandomPlane()
        @sweep Metropolis(; temperature = 2.0)
    end

    @testset "P6.0ai: integral folds are hoisted, fresh at every refresh ($geom, $(nameof(typeof(alg))))" for
        (geom, dims) in ((:square, (16, 16)), (:hex, (16, 16)), (:cube, (8, 8, 8))),
            alg in (SequentialCPM(), CheckerboardCPM())
        c = mtkcompile(P60ai(; name = :x, geom))
        xs = Potts._integrals(c.sys; observed = true)
        hoisted = [!Potts._has_op(x, Potts.population) for x in xs]
        @test count(hoisted) == 4                    # s, bo, q and the observed o; not n, r
        @test count(!, hoisted) == 2
        @test length(Potts._integrals(c.sys)) == 5    # o is read only by `@observed`: not stored (D-120)
        σ0, w0 = p60ai_init(dims)
        prob = PottsProblem(P60ai(; name = :x, geom), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 4); capacity = 8, seed = 3)
        @test count(n -> startswith(String(n), "__ifold_"), propertynames(prob.u0.model)) == 4
        @test !hasproperty(prob.u0.cell, Potts._integral_name(last(xs)))   # (o has its fold slot, no column)
        live(u) = findall(>(0), Array(u.cell.volume))
        per(u, f) = [sum((f(i) for i in findall(==(k), Array(u.σ))); init = 0.0) for k in eachindex(u.cell.volume)]
        obs(u) = (V = Array(u.cell.volume); L = live(u); mv = sum(V[L]) / length(L); per(u, i -> w0[i] * mv))
        @test prob[:o] ≈ obs(prob.u0)                                         # at init
        sol = solve(prob, alg; saveat = 0:4)
        names = [Potts._integral_name(x) for x in Potts._integrals(c.sys)]
        divided = false
        for t in 1:4
            u, prev = sol.u[t + 1], sol.u[t]
            V, v = Array(u.cell.volume), Array(u.cell.v)
            @test sol[:o][t + 1] ≈ obs(u)                                     # observed, after divisions too
            # stored = recomputed from the saved state (the MCS boundary refresh, after the lifecycle)
            fresh = Potts._fresh_integrals(
                Float64, u, sol.prob.p, sol.prob.f.sys.ctx, t,
                Potts._integral_phases(sol.prob.f.sys.csys, Float64), names
            )
            @test all(n -> getfield(u.cell, n) ≈ getfield(fresh.cell, n), names)
            if length(live(u)) != length(live(prev))                          # a division after the block
                divided = true
                continue
            end
            L = live(u)
            @test v[L] == fill(t, length(L))
            @test u.cell.s ≈ per(u, i -> w0[i] * sum(v[L]))                   # the fold sees the new v
            @test !(u.cell.s ≈ per(u, i -> w0[i] * sum(v[L] .- 1)))           # (the stale one differs)
            big = any(>(17), V[L])
            @test u.cell.bo ≈ per(u, i -> big ? -w0[i] : w0[i])
            @test u.cell.q ≈ per(u, i -> w0[i] * sum(w0))
            @test u.cell.n ≈ per(u, i -> w0[i] * sum(V[L]))
            @test u.cell.r ≈ per(u, i -> w0[i])
        end
        @test divided
    end
end


@testitem "P6.0ai: hoisted folds are fresh at every refresh point (nameof(typeof(alg)))" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0ai: hoisted folds are fresh at every refresh point ($(nameof(typeof(alg))))" for
        alg in (SequentialCPM(), CheckerboardCPM())
        σ0, w0 = p60ai_init((16, 16))
        prob = PottsProblem(P60aiRefresh(; name = :x), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 4); seed = 5)
        per(u, f) = [sum((f(i) for i in findall(==(k), Array(u.σ))); init = 0.0) for k in eachindex(u.cell.volume)]
        vsum(u) = sum(Array(u.cell.v)[Array(u.cell.volume) .> 0])
        # at init: the stored tracker of the before-MCS operand, and its reader in MCS 1
        names = [Potts._integral_name(x) for x in Potts._integrals(mtkcompile(P60aiRefresh(; name = :x)).sys)]
        sb0 = per(prob.u0, i -> w0[i] * 32)
        @test count(n -> getfield(prob.u0.cell, n) ≈ sb0, names) == 1      # the tracker, in u0
        sol = solve(prob, alg; saveat = 0:4)
        @test sol.u[2].cell.sb ≈ sb0                                     # MCS 1 reads the initial state
        @test !(sol.u[2].cell.sb ≈ sb0 .* 0)
        for t in 1:4
            u, prev = sol.u[t + 1], sol.u[t]
            @test vsum(u) == 2t
            # gated: fresh in MCS 1, 3 (mcs 0, 2), kept in MCS 2, 4
            @test u.cell.s2 ≈ (isodd(t) ? per(u, i -> w0[i] * vsum(u)) : prev.cell.s2)
            # the equation (explicit Euler, dt = 1) integrates the fresh integral of each MCS
            @test u.cell.r - prev.cell.r ≈ per(u, i -> sin(w0[i]) * vsum(u))
        end
        @test !(sol.u[2].cell.s2 ≈ per(sol.u[2], i -> w0[i] * 0))
        # a checkpoint continuation equals the uninterrupted run
        integ = init(prob, alg)
        foreach(_ -> step!(integ), 1:2)
        rest = solve!(init(prob, alg; checkpoint = checkpoint(integ))).u[end]
        @test rest.σ == sol.u[end].σ
        @test all(n -> getfield(rest.cell, n) == getfield(sol.u[end].cell, n), propertynames(rest.cell))
        @test all(n -> getfield(rest.model, n) == getfield(sol.u[end].model, n), propertynames(rest.model))
    end
end


@testitem "P6.0ai: observed integrals leave the state unchanged" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0ai: observed integrals leave the state unchanged" begin
        σ0, w0 = p60ai_init((16, 16))
        prob = PottsProblem(P60aiRefresh(; name = :x), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 2); seed = 5)
        slots = filter(n -> startswith(String(n), "__ifold_"), propertynames(prob.u0.model))
        @test length(slots) == 4
        mark!(u) = foreach(n -> fill!(getfield(u.model, n), -7.0), slots)
        unchanged(u, cell) = all(n -> all(==(-7.0), getfield(u.model, n)), slots) &&
            all(n -> getfield(u.cell, n) == getfield(cell, n), propertynames(cell))
        oracle(u) = (
            V = u.cell.volume; L = V .> 0; mv = sum(V[L]) / count(L);
            [sum((w0[i] * mv for i in findall(==(k), u.σ)); init = 0.0) for k in eachindex(V)]
        )
        mark!(prob.u0); c0 = deepcopy(prob.u0.cell)
        @test prob[:o] ≈ oracle(prob.u0)
        @test unchanged(prob.u0, c0)
        sol = solve(prob, SequentialCPM())
        mark!(sol.u[end]); c1 = deepcopy(sol.u[end].cell)
        @test sol[:o][end] ≈ oracle(sol.u[end])
        @test unchanged(sol.u[end], c1)
        integ = init(prob, SequentialCPM()); step!(integ)
        mark!(integ.state); c2 = deepcopy(integ.state.cell)
        @test integ[:o] ≈ oracle(integ.state)
        @test unchanged(integ.state, c2)
    end
end


@testitem "P6.0t: an integral read only in a tick's population fold is fresh (nameof(typeof(alg)))" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @named p60t_ctr = System([dn(_kd) ~ dn(_kd - 1) + dinc], _tc)

    @potts_model P60tTick begin
        @structural_parameters use_integral = true
        @kinds medium A
        @variables begin
            w(site) = 1.0
            u(site) = 0.0
            sa(cell) = 0.0
        end
        @components cells(A) ctr = p60t_ctr
        if use_integral
            @equations ctr.dinc ~ sum(integral(w)^2 for c in cells)
        else
            @equations ctr.dinc ~ sum(volume^2 for c in cells)
        end
        @after_mcs sa ~ integral(u)
        @lattice Lattice((16, 16))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 20.0)
    end

    @testset "P6.0t: an integral read only in a tick's population fold is fresh ($(nameof(typeof(alg))))" for
        alg in (SequentialCPM(), CheckerboardCPM())
        σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1; σ[10:12, 10:12] .= 2
        dn(use_integral) = (
            sol = solve(PottsProblem(P60tTick(; name = :x, use_integral), [ownership => σ, kind => [:A, :A]], (0, 12); seed = 1), alg; saveat = 0:12);
            [Array(u.cell.ctr₊dn)[1] for u in sol.u]
        )
        a, b = dn(true), dn(false)
        @test a == b
        @test length(unique(diff(b))) > 1                  # the volumes move: a lag would show
    end
end


@testitem "P6.0t: stored integrals keep their order without observed-only readers" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "P6.0t: stored integrals keep their order without observed-only readers" begin
        @named p60t_rctr = System([dn(_kd) ~ dn(_kd - 1) + dinc], _tc)

        @potts_model P60tOrder begin
            @kinds medium A
            @variables begin
                pa(site) = 1.0
                pb(site) = 1.0
            end
            @components cells(A) ctr = p60t_rctr
            @equations ctr.dinc ~ integral(pa)
            @observed o(cell) ~ integral(pa) + integral(pb)
            @lattice Lattice((16, 16))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = integral(pb) / 9)
        end

        c = mtkcompile(P60tOrder(; name = :x))
        @test [Potts.info(x).name for x in Potts._integrals(c.sys)] == [:pa, :pb]
        @test isequal(Potts._integrals(c.sys; observed = true), Potts._integrals(c.sys))
    end
end
