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

# Sentinel tests of the read scan (P6.0v2 review): every leaf outside the computed reads is
# overwritten with a sentinel (NaN, `true`, and 1 for integers: wrong but in range, so a missed
# read through an unchecked index fails the test instead of crashing); the outputs must not
# change. Negative controls poison one leaf the scan does list and expect a change.
_sentinel(a::AbstractArray{<:AbstractFloat}) = fill!(similar(a), NaN)
_sentinel(a::AbstractArray{Bool}) = fill!(similar(a), true)
_sentinel(a::AbstractArray{<:Integer}) = fill!(similar(a), one(eltype(a)))
_sentinel(a) = a
_keep_only(nt::NamedTuple, keep) =
    NamedTuple{keys(nt)}(map(n -> n in keep ? deepcopy(getfield(nt, n)) : _sentinel(getfield(nt, n)), keys(nt)))

@testset "the cell helpers read only the columns _CELL_HELPER_READS lists" begin
    lat = CorePotts.Lattice((20, 20))
    σ = zeros(Int32, 20, 20); σ[3:7, 4:6] .= 1; σ[12:15, 9:16] .= 2
    mom = CorePotts.init_moments(σ, lat, 2)
    cell = (; kind = Int32[1, 2], volume = Int32[count(==(c), σ) for c in 1:2], anchor = mom.anchor, m1 = mom.m1,
        m2 = mom.m2, cluster = Int32[2, 2], surface = Int32[16, 24], z = [1.0, 2.0])
    prop = CorePotts.Proposal{2}(1, 2, (2, 7), 1, Int32(0), Int32(1))
    calls = Dict(
        "CorePotts.centroid_distance" => c -> CorePotts.centroid_distance(Float64, c, lat, 1, 2),
        "CorePotts.centroid" => c -> CorePotts.centroid(Float64, c, lat, 2),
        "CorePotts.centroid_position" => c -> CorePotts.centroid_position(Float64, c, lat, 2),
        "Potts._centroid_axis" => c -> Potts._centroid_axis(Float64, c, lat, 2, 1),
        "Potts._displacement_axis" => c -> Potts._displacement_axis(Float64, c, lat, prop, 1, 1),
        "CorePotts.major_length" => c -> CorePotts.major_length(Float64, c, lat, 2),
        "CorePotts.cluster_of" => c -> CorePotts.cluster_of(c, 1))
    @test Set(keys(calls)) == Set(keys(Potts._CELL_HELPER_READS))       # every listed helper is pinned
    for (name, f) in calls
        listed = Potts._CELL_HELPER_READS[name]
        @test isequal(f(_keep_only(cell, listed)), f(cell))
        # negative control: each listed column is really read
        for n in listed
            @test !isequal(f(_keep_only(cell, setdiff(listed, (n,)))), f(cell))
        end
    end
    # `_cellkind` reads `kind`; `owner_kind` reads σ and `kind`
    st = CorePotts.CPMState(σ, cell)
    st_k = CorePotts.CPMState(σ, _keep_only(cell, (:kind,)))
    @test Potts._cellkind(st_k, 2) == Potts._cellkind(st, 2) == 2
    @test CorePotts.owner_kind(st_k, LinearIndices(σ)[13, 10]) == CorePotts.owner_kind(st, LinearIndices(σ)[13, 10]) == 2
end

function _sentinel_state(st, ph; drop = nothing)
    r = ph.reads
    cell = setdiff((r.cell..., (ph.scope === :cell ? (ph.names..., :volume) : ())...), (drop,))
    model = setdiff((r.model..., (ph.scope === :model ? ph.names : ())...), (drop,))
    return CorePotts.CPMState(r.σ && drop !== :σ ? deepcopy(st.σ) : _sentinel(st.σ), _keep_only(st.cell, cell),
        _keep_only(st.site, setdiff(r.site, (drop,))), _keep_only(st.model, model), _keep_only(st.history, r.history))
end
# Runs every adaptive phase of `prob` on the state after 3 MCS, on a copy and on a sentinel
# state; returns (equal outputs, the phase) per phase, and with `drop`, also poisons that leaf.
function _sentinel_probe(prob; drop = nothing)
    integ = init(prob, SequentialCPM())
    foreach(_ -> step!(integ), 1:3)
    out = []
    for ph in prob.f.phases.after_mcs
        ph isa Potts._AdaptiveODE || continue
        @test ph.reads !== nothing
        a, b = deepcopy(integ.state), _sentinel_state(integ.state, ph; drop)
        ph(a, integ.p, integ.ctx, integ.key, 3, CorePotts.CPU())
        ok = try
            ph(b, integ.p, integ.ctx, integ.key, 3, CorePotts.CPU())
            part(s) = ph.scope === :cell ? s.cell : s.model
            all(n -> isequal(getfield(part(a), n), getfield(part(b), n)), ph.outs)
        catch
            false
        end
        push!(out, (ok, ph))
    end
    return out
end

@potts_model SentinelA begin                     # helpers, kind tables, integrals, gathers, folds
    @kinds medium A B
    @parameters begin
        k = 0.3
        J[kind] = [0.0, 1.0, 2.0]
    end
    @variables begin
        y(cell) = 1.0
        w(cell) = 2.0
        u(cell) = 0.0
        h(site) = 0.5
        g(model) = 1.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * J[kind] * y + 0.01 * centroid(1) + 0.001 * integral(h) + 0.01 * w[max(id - 1, 1)] +
               0.001 * g + 0.001 * surface + 0.001 * major_length
        D(g) ~ -0.1 * g + 0.001 * sum(h for s in sites) + 0.01 * count(true for c in cells(B))
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model SentinelB begin                     # a population fold reading time, history, owner gathers
    @kinds medium A B
    @variables begin
        y(cell) = 1.0
        z(cell) = 0.5
        v(cell) = 0.3
        gm(model) = 1.0
        g(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -0.1 * y + 0.01 * sum(z[c] for c in cells) * (1 + 0 * time) + 0.01 * y[max(id - 1, 1)] +
               0.01 * sum(v[owner[n]] * kind[n] for n in Moore(1)(64) if owner[n] != id)
        D(z) ~ -0.2 * z
        D(g) ~ -0.1 * g + 0.01 * Pre(gm, 1) + 0.001 * sum(kind == 1 for s in sites)
    end
    @after_mcs gm ~ gm + 1
    @sweep Metropolis(; temperature = 1.0)
end

@testset "adaptive phases: leaves outside the scanned reads do not matter" begin
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[7:10, 3:6] .= 2; σ[12:15, 12:15] .= 3
    op = [ownership => σ, kind => [:A, :B, :A]]
    AD = Adaptive(Tsit5(); reltol = 1e-8)
    pa = PottsProblem(SentinelA(; name = :a), op, (0, 5); ode_solver = AD)
    pb = PottsProblem(SentinelB(; name = :b), op, (0, 5); ode_solver = AD)
    for prob in (pa, pb), (ok, ph) in _sentinel_probe(prob)
        @test ok
    end
    rs = Dict(ph.scope => ph.reads for (_, ph) in _sentinel_probe(pa))
    @test issubset((:anchor, :m1, :m2, :w, :surface, :kind, :volume), rs[:cell].cell) && rs[:cell].model == (:g,)
    @test rs[:model].site == (:h,) && !rs[:model].σ
    rs = Dict(ph.scope => ph.reads for (_, ph) in _sentinel_probe(pb))
    @test rs[:cell].σ && issubset((:kind, :v), rs[:cell].cell)       # the owner gather
    @test rs[:model].history == (:gm,) && rs[:model].σ                # `Pre(gm, 1)`; the site fold's kinds
    # negative controls: poisoning a leaf the scan lists changes the result
    @test !all(first, _sentinel_probe(pa; drop = :w))
    @test !all(first, _sentinel_probe(pa; drop = :m1))
    @test !all(first, _sentinel_probe(pb; drop = :σ))
    @test !all(first, _sentinel_probe(pb; drop = :v))
end
