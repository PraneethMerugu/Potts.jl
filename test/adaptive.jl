# Adaptive host integration of cell and model ODEs (`PottsProblem(…; ode_solver = Adaptive(alg))`,
# M4.1; the solver is a problem keyword, D-075).
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P

function adaptive_model()
    @potts_model AdaptiveODEs begin
        @kinds medium A B
        @parameters k = 0.3
        @variables begin
            y(cell) = 1.0
            s(cell) = 0.0
            g(model) = 1.0
        end
        @lattice Lattice((20, 20))
        @energy cells => (volume - 16.0)^2
        @equations begin
            D(y) ~ -k * y                                    # cell ODE
            D(s) ~ -1000 * (s - cos(time))                   # stiff cell ODE
            D(g) ~ -0.5 * g + count(true for c in cells(B))  # model ODE with a population input
        end
        @sweep Metropolis(; temperature = 1.0)
    end
    return AdaptiveODEs(; name = :ad)
end

@testset "adaptive ODE integration (SciML solvers)" begin
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    t = 5.0
    sa(t) = (1000 * (1000 * cos(t) + sin(t)) - 1000^2 * exp(-1000t)) / (1000^2 + 1)   # s(0) = 0
    for solver in (Adaptive(Tsit5(); reltol = 1e-10, abstol = 1e-12), Adaptive(Rodas5P(); reltol = 1e-8, abstol = 1e-10))
        p = PottsProblem(adaptive_model(), op, (0, 5); ode_solver = solver)
        for alg in (SequentialCPM(), CheckerboardCPM())
            u = solve(p, alg).u[end]
            @test u.cell.y[1:2] ≈ fill(exp(-0.3t), 2) rtol = 1e-6
            @test u.model.g[1] ≈ 2 + (1 - 2) * exp(-0.5t) rtol = 1e-6            # one B cell: g → 2
            @test u.cell.s[1:2] ≈ fill(sa(t), 2) rtol = 1e-4
        end
    end
    # the integrator is created once and reused (init-once), and remake keeps working
    p = PottsProblem(adaptive_model(), op, (0, 3); ode_solver = Adaptive(Tsit5(); reltol = 1e-8))
    q = remake(p; p = [:k => 0.0])
    @test solve(q, SequentialCPM()).u[end].cell.y[1] ≈ 1.0
end

@potts_model RndBase begin
    @kinds medium A
    @variables rb(cell) = 0.0
    @lattice Lattice((6, 6, 6))
    @after_mcs rb ~ rand()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model RndOuter begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @variables begin
        ra(cell) = 0.0
        pos(cell)[1:2] = 0.0
    end
    @after_mcs ra ~ rand()
    @extend base = RndBase()
    @after_mcs pos ~ centroid()             # the outer 2D lattice, not the base's 3D one
    @sweep Metropolis(; temperature = 1.0)
end

@testset "review 5 regressions" begin
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    p = PottsProblem(adaptive_model(), op, (0, 3); ode_solver = Adaptive(Tsit5(); reltol = 1e-8))
    # one integrator per trajectory (ensembles), rebuilt for another parameter-tuple type
    ens = solve(EnsembleProblem(p), SequentialCPM(), EnsembleThreads(); trajectories = 8)
    @test all(s -> s.u[end].cell.y[1] ≈ exp(-0.9), ens.u)
    @test solve(p, CheckerboardCPM(; proposal = Moore(1))).u[end].cell.y[1] ≈ exp(-0.9) rtol = 1e-6
    # a failing solve is an error, not a silent truncation
    bad = PottsProblem(adaptive_model(), op, (0, 1); ode_solver = Adaptive(Tsit5(); maxiters = 5))
    @test_throws ErrorException solve(bad, SequentialCPM())
    # nested @extend: numbering continues (independent draws), the outer lattice dimension is kept
    σ2 = zeros(Int32, 16, 16); σ2[4:8, 4:8] .= 1
    u = solve(PottsProblem(RndOuter(; name = :o), [ownership => σ2, kind => [1]], (0, 1)), SequentialCPM()).u[end]
    @test u.cell.ra[1] != u.cell.rb[1]
    @test u.cell.pos_1[1] ≈ 6.0 atol = 1.5
    # replacement respects cadence; reinit! refreshes integrals
    @test_throws ArgumentError PottsProblem(VectorBits(; name = :v), [ownership => zeros(Int32, 12, 12), kind => Int[],
        :q => [1.0, 2.0]], (0, 1))
    r = PottsProblem(VectorBits(; name = :v), [ownership => (s = zeros(Int32, 12, 12); s[4:6, 4:6] .= 1; s), kind => [1],
        :q => [4.0, 5.0, 6.0]], (0, 1))
    @test r.u0.cell.q_2[1] == 5.0                                       # a flat vector: the vector itself
    σf = zeros(Int32, 16, 16); σf[3:8, 3:8] .= 1
    integ = init(PottsProblem(Fresh(; name = :f), [ownership => σf, kind => [1]], (0, 4); capacity = 8), SequentialCPM())
    step!(integ); m1 = integ.u.cell.mb[1]
    reinit!(integ); step!(integ)
    @test integ.u.cell.mb[1] == m1 == 36
end

# D-092 (P6.0v2): host phases copy only the state leaves their generated code reads
@testset "state reads of generated host code" begin
    R = Potts._state_reads
    @test R([:(st.cell.r[c] * p.k)]) == (; σ = false, cell = (:r,), site = (), model = (), history = ())
    @test R([:(Potts._cellkind(st, c) + st.model.g[1] + st.site.h[i])]).cell == (:kind,)
    @test R([:(CorePotts.owner_kind(st, i))]) == (; σ = true, cell = (:kind,), site = (), model = (), history = ())
    @test R([:(length(st.cell.kind) + size(cell.links, 1))]; alias = :cell).cell == ()        # shape only
    @test R([:(CorePotts.centroid_distance(T, cell, ctx.lattice, a, b))]; alias = :cell).cell == (:anchor, :m1, :volume)
    # uses the scan does not follow: everything (negative controls)
    @test R([:(f(st))]) === nothing
    @test R([:(f(st.cell))]) === nothing
    @test R([:(f(cell))]; alias = :cell) === nothing
    @test R([:(f(cell))]) == (; σ = false, cell = (), site = (), model = (), history = ())      # `cell` is no alias here
    # the adaptive phases of a model: the cell ODEs read nothing else; the model ODE's
    # population fold reads `volume` and `kind`
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
    p = PottsProblem(adaptive_model(), [ownership => σ, kind => [:A, :B]], (0, 1); ode_solver = Adaptive(Tsit5()))
    phs = [ph for ph in p.f.phases.after_mcs if ph isa Potts._AdaptiveODE]
    @test Set(ph.scope for ph in phs) == Set([:cell, :model])
    for ph in phs
        @test ph.reads !== nothing && !ph.reads.σ
        ph.scope === :model && @test issubset((:kind, :volume), ph.reads.cell)
    end
end

@testset "@link phases declare their reads and writes" begin
    @potts_model DeclLink begin
        @kinds medium A
        @variables begin
            rest(bond) = 3.0
            w(cell) = 1.0
        end
        @relationship bond(cell, cell) capacity = 2
        @lattice Lattice((16, 16); neighborhood = Moore(1))
        @energy cells => 100 * (volume - 16)^2
        @link bond when = new_contact(a, b) && w[a] > 0
        @unlink bond when = distance > 10.0
        @sweep Metropolis(; temperature = 0.0)
    end
    σ = zeros(Int32, 16, 16); σ[3:6, 3:6] .= 1; σ[7:10, 3:6] .= 2
    p = PottsProblem(DeclLink(; name = :d), [ownership => σ, kind => [:A, :A]], (0, 2))
    link, unlink = [ph for ph in p.f.phases.after_mcs if ph isa CorePotts.HostPhase]
    @test link.writes == unlink.writes == (:links__bond, :link_rest)
    @test Set(link.reads) == Set([:σ, :volume, :anchor, :m1, :w])           # `w[a]` in `when`
    @test Set(unlink.reads) == Set([:volume, :anchor, :m1])                 # no contact graph: no σ
    u = solve(p, SequentialCPM()).u[end]
    @test CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)
end
