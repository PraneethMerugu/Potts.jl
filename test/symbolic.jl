# Symbolic front end (ROADMAP M3.1–M3.3): generated models equal the hand-written oracle
# ports proposal by proposal, and the derived ΔH equals H(after) − H(before) of the
# generated total energy.
using Random: Xoshiro
using InteractiveUtils: code_llvm

"""Random proposals (Moore(1) sources) on states along a trajectory of `prob`."""
function proposal_states(prob; mcs = (0, 5, 20), n = 400, rng = Xoshiro(11))
    sol = solve(remake(prob; tspan = (0, maximum(mcs))), SequentialCPM(; proposal = Moore(1)); saveat = collect(mcs))
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    out = Tuple{Any, Any}[]
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.σ)); x = CorePotts.coordinates(lat, t)
        d = rand(rng, 1:length(moore))
        ins, y = CorePotts.shift(lat, x, moore.offsets[d])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        push!(out, (u, CorePotts.Proposal(t, s, x, d, u.σ[t], u.σ[s])))
    end
    return out
end

ctx_of(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...)

@testset "symbolic models equal the hand-written ports: $name" for (name, sym, hand) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 20), () -> graner_problem(; nmcs = 20)),
        ("wortel", symbolic_wortel_problem, wortel_problem),
        ("merks", symbolic_merks_problem, merks_problem),
        ("openvt", symbolic_openvt_problem, openvt_problem))
    sp, hp = sym(), hand()
    ctx = merge(ctx_of(hp), ctx_of(sp))
    worst_h = 0.0; worst_e = 0.0
    agree_c = true; agree_commit = true
    for (u, prop) in proposal_states(sp)
        dHs = sp.f.delta_H(u, sp.p, prop, ctx)
        dHh = hp.f.delta_H(u, hp.p, prop, ctx)
        worst_h = max(worst_h, abs(dHs - dHh))
        agree_c &= sp.f.constraint(u, sp.p, prop, ctx) == hp.f.constraint(u, hp.p, prop, ctx)
        # commit: both applied to copies after the ownership write
        a = deepcopy(u); b = deepcopy(u)
        a.σ[prop.target] = prop.new; b.σ[prop.target] = prop.new
        sp.f.commit!(a, sp.p, prop, ctx); hp.f.commit!(b, hp.p, prop, ctx)
        agree_commit &= all(k -> getfield(a.cell, k) == getfield(b.cell, k), intersect(keys(a.cell), keys(b.cell))) &&
                        all(k -> getfield(a.site, k) == getfield(b.site, k), intersect(keys(a.site), keys(b.site)))
        # self-check: ΔE equals H(after) − H(before)
        H0 = total_energy(sp, u)
        H1 = total_energy(sp, a)
        worst_e = max(worst_e, abs(energy_change(sp, u, prop) - (H1 - H0)))
    end
    @test worst_h < 1e-9
    @test agree_c
    @test agree_commit
    @test worst_e < 1e-9
    # trajectories agree too (same address-keyed randomness, same functions)
    tspan = (0, 15)
    us = solve(remake(sp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    uh = solve(remake(hp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    @test us.σ == uh.σ
end

@testset "symbolic surface: generated code" begin
    ex = PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[]], (0, 1); expression = Val(true))
    s = string(ex.delta_H)
    @test occursin("p.J", s) && occursin("st.cell.volume", s)
    @test !occursin("^", s)                          # the volume term was expanded to closed form
    prob = symbolic_graner_problem(; nmcs = 5)
    @test remake(prob; p = [:λ => 2.0]).f === prob.f                  # parameters change, code does not
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 4, 4)], (0, 1))
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[],
        first(filter(x -> Potts.info(x).name === :J, SORTING.sys.parameters)) => [0 1 1; 2 0 1; 1 1 0]], (0, 1))
end

@testset "rebuilding a problem reuses the generated code" begin
    a = symbolic_wortel_problem(; seed = 1)
    b = symbolic_wortel_problem(; seed = 2)
    @test typeof(a.f) === typeof(b.f)
    @test a.f.fingerprint == b.f.fingerprint
end

@testset "remake with symbolic maps; the sweep law" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    λ = first(filter(x -> Potts.info(x).name === :λ, SORTING.sys.parameters))
    q = remake(prob; p = [λ => 3.0])
    @test q.p.λ == 3.0 && q.p.V₀ == prob.p.V₀ && q.f === prob.f
    @test remake(prob; p = Dict(:T => 2)).p.T === 2.0              # converted to the scalar type
    @test_throws ArgumentError remake(prob; p = [:nope => 1.0])
    σ, kinds = graner_state()
    r = remake(prob; u0 = [ownership => circshift(σ, (3, 0)), kind => kinds])
    @test r.u0.σ == circshift(σ, (3, 0)) && r.u0.cell.volume == prob.u0.cell.volume
    @test prob.f.acceptance === Metropolis()
end

@potts_model Spring begin
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        k = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - rest)^2
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model Tissue begin
    @kinds medium leader follower
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables age(edge) = 0.0
    @relationship bond(cell, cell) capacity = 8
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @link bond when = new_contact(a, b) && (kind[a] == leader), every = 100
    @unlink bond when = distance > 100.0
    @sweep Metropolis(; temperature = T)
end

@testset "relationships: springs and link rules" begin
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[40:45, 12:17] .= 2
    prob = PottsProblem(Spring(; name = :spring), [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000))
    @test CorePotts.linked(prob.u0.cell, 1, 2) && prob.u0.cell.link_rest[1, 1] == 12.0
    # self-check with edge energies (partner centroids move with the copy)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 5)); mcs = (0, 5), n = 300)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u))))
    end
    @test worst < 1e-9
    ds = map(1:4) do seed
        u = solve(remake(prob; seed), CheckerboardCPM()).u[end]
        CorePotts.centroid_distance(Float64, u.cell, prob.lattice, 1, 2)
    end
    @test abs(sum(ds) / 4 - 12.0) < 2.5                 # relaxes from 25 to the rest length

    σb = zeros(Int32, 30, 30)
    for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
        σb[i:(i + 4), j:(j + 4)] .= c
    end
    n = maximum(σb)
    kinds = [isodd(c) ? :leader : :follower for c in 1:n]
    tp = PottsProblem(Tissue(; name = :tissue), [ownership => σb, kind => kinds], (0, 1))
    u = solve(tp, SequentialCPM()).u[end]            # the rule ran once, after MCS 0's sweep
    g = CorePotts.contact_graph(u.σ, tp.lattice, tp.contact, n)
    nlinks = 0
    for a in 1:n, b in (a + 1):n
        touching = b in CorePotts.neighbors(g, a)
        led = isodd(a) || isodd(b)
        @test CorePotts.linked(u.cell, a, b) == (touching && led)
        nlinks += CorePotts.linked(u.cell, a, b)
    end
    @test nlinks > 20
end

# ---------------------------------------------------------------------------------------
# Regressions from the review of the symbolic layer

function selfcheck(prob; n = 300)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 3)); mcs = (0, 3), n)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u))))
    end
    return worst
end

function two_kind_blocks()
    σ = zeros(Int32, 24, 24)
    for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 2:6:20))
        σ[i:(i + 4), j:(j + 4)] .= c
    end
    return σ, [isodd(c) ? 1 : 2 for c in 1:maximum(σ)]
end

@potts_model CellVarContacts begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        T = 8.0
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables x(cell) = 1.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @relations near = Moore(1)
    @energy begin
        cells(A, B) => λ * (volume - 25)^2 + 0.3 * (surface - 20)^2
        contacts => J[kind, kind′] + x                      # bare cell variable: x[owner]
        contacts(near) => 0.5 * x[owner] * x[owner′]
    end
    @sweep Metropolis(; temperature = T)
end

@testset "review regressions" begin
    σ, kinds = two_kind_blocks()
    n = length(kinds)
    xs = collect(1.0:n)
    prob = PottsProblem(CellVarContacts(; name = :cv), [ownership => σ, kind => kinds,
        first(filter(v -> Potts.info(v).name === :x, CellVarContacts(; name = :cv).variables)) => xs], (0, 3))
    @test selfcheck(prob) < 1e-9           # cell variables mirrored; surface δ fused once
    ex = PottsProblem(CellVarContacts(; name = :cv), [ownership => σ, kind => kinds], (0, 1); expression = Val(true))
    @test count("δs_old +=", string(ex.delta_H)) == 1

    # quantities that change with the copy are rejected outside cell terms
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.contacts => Potts._index(Potts.B.volume, Potts.B.owner))],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.sites => 0.1 * Potts._index(Potts.B.volume, Potts.B.owner))],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.cells(0) => Potts.B.volume)],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
end

@potts_model TwoDivisions begin
    @kinds medium A B
    @parameters begin
        T = 5.0
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables begin
        m(cell) = 8.0
        q(cell) = 5.0
        y(cell) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @on_copy y[new] ~ 1.0                     # new may be the medium: nothing to write
    @divide cells(A) when = mcs == 0, m => Split()
    @divide cells(B) when = mcs == 1000, q => 0.0
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end

@testset "division rules are per kind; on-copy writes skip the medium" begin
    σ, kinds = two_kind_blocks()
    prob = PottsProblem(TwoDivisions(; name = :td), [ownership => σ, kind => kinds], (0, 2))
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]      # retractions happen: no BoundsError
    nA = count(==(1), kinds)
    @test count(>(0), u.cell.volume) == length(kinds) + nA
    @test all(==(5.0), u.cell.q[u.cell.volume .> 0])                  # B's rule never ran on A cells
    @test all(c -> u.cell.m[c] == (kinds[c] == 1 ? 4.0 : 8.0), 1:length(kinds))
end

@potts_model FloatModel begin
    @kinds medium A
    @parameters begin
        λ = 1.0
        T = 8.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy cells(A) => λ * (surface - 4 * sqrt(volume))^2 + log(2) * volume / 3
    @drive copy => -2 * (c[target] - c[source]) / 3
    @equations D(c) ~ 0.1 * Δ(c) - c / 10 + exp(-1) * (kind == A)
    @sweep Metropolis(; temperature = T)
end

@testset "Float32 models never touch Float64" begin
    σ = zeros(Int32, 16, 16); σ[5:10, 5:10] .= 1
    prob = PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2); T = Float32)
    ctx = ctx_of(prob)
    prop = CorePotts.Proposal(4 + 16 * 5, 5 + 16 * 5, (4, 6), 1, Int32(0), Int32(1))
    io = IOBuffer()
    code_llvm(io, prob.f.delta_H, typeof.((prob.u0, prob.p, prop, ctx)); debuginfo = :none)
    @test !occursin("double", String(take!(io)))
    @test prob.f.delta_H(prob.u0, prob.p, prop, ctx) isa Float32
    @test selfcheck(PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2))) < 1e-9
end

@potts_model Helpers begin
    @kinds medium A
    firstor0(v) = isempty(v) ? 0.0 : v[1]            # plain Julia: lazy ternary, real indexing
    w = zeros(2)
    w[1] = 3.0                                        # indexed assignment is not rewritten
    total = sum(w[i] for i in eachindex(w))           # an ordinary generator
    ok = w[1] > 0 && firstor0(Float64[]) == 0.0       # short-circuit on real values
    @parameters begin
        λ = firstor0(w) + total
        T = ok ? 5.0 : 1.0
    end
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy cells(A) => λ * volume
    @sweep Metropolis(; temperature = T)
end

@testset "macro: plain Julia stays plain; keyword overrides" begin
    sys = Helpers(; name = :h)
    vals = Dict(Potts.info(p).name => Potts.info(p).default for p in sys.parameters)
    @test vals[:λ] == 6.0 && vals[:T] == 5.0
    sys2 = Helpers(; name = :h, λ = 2.0)
    @test Potts.info(first(sys2.parameters)).default == 2.0
    # constructing a model twice yields the same generated code (gathers numbered per model)
    σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
    a = PottsProblem(WortelAct(; name = :w), [ownership => σ, kind => [1]], (0, 1))
    b = PottsProblem(WortelAct(; name = :w), [ownership => σ, kind => [1]], (0, 1))
    @test a.f.fingerprint == b.f.fingerprint && typeof(a.f) === typeof(b.f)
end

@potts_model Census begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables begin
        act(site) = 0.0
        total(model) = 0.0
        ndark(model) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - 25)^2
        contacts => J[kind, kind′]
    end
    @on_copy act[target] ~ 1.0
    @after_mcs begin
        total ~ sum(act[s] for s in sites)
        ndark ~ count(true for c in cells(dark))
    end
    @observed begin
        mean_volume ~ mean(volume for c in cells)
        dark_area ~ sum(volume for c in cells(dark))
        big ~ volume > 25
        excess ~ dark_area - 25 * ndark
    end
    @sweep Metropolis(; temperature = T)
end

@testset "model variables, populations, observed and SII" begin
    σ, kinds = two_kind_blocks()
    sys = Census(; name = :census)
    prob = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 6))
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = [2, 4, 6])
    named(n) = only(filter(x -> Potts.info(x).name === n, vcat(sys.variables, [o.var for o in sys.observed], sys.parameters)))
    live(u) = findall(>(0), u.cell.volume)
    @test sol[named(:total)] == [sum(u.site.act) for u in sol.u]
    @test sol[named(:ndark)][2:end] == [count(c -> kinds[c] == 1, live(u)) for u in sol.u[2:end]]   # t = 0: default
    @test sol[named(:ndark)][1] == 0
    @test sol[named(:mean_volume)] ≈ [sum(u.cell.volume[live(u)]) / length(live(u)) for u in sol.u]
    @test sol[named(:dark_area)] == [sum(u.cell.volume[c] for c in live(u) if kinds[c] == 1; init = 0) for u in sol.u]
    @test sol[named(:big)][end] == (sol.u[end].cell.volume .> 25)
    @test sol[named(:excess)] == sol[named(:dark_area)] .- 25 .* sol[named(:ndark)]
    @test prob.p isa Potts.PottsParameters && isbits(prob.p)
    @test sol[Potts.kind][1] == kinds                                   # built-ins observe too
    @test sol[named(:act)][end] == sol.u[end].site.act
    @test observe(prob, named(:mean_volume)) ≈ 25.0
    SII = Potts.SymbolicIndexingInterface
    @test SII.getp(prob, named(:λ))(prob) == 1.0
    @test SII.getp(sol, named(:T))(sol) == 10.0
end

@potts_model LibrarySorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((72, 72); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = V₀, strength = λ)
        Adhesion(J)
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model KindTemperature begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = 3.0, kinds = (dark,))
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end

@testset "library one-liners, per-kind temperature, frozen kinds" begin
    a = symbolic_graner_problem(; nmcs = 5)
    σ, kinds = graner_state()
    b = PottsProblem(LibrarySorting(; name = :lib), [ownership => σ, kind => kinds], (0, 5))
    @test all(((u, prop),) -> a.f.delta_H(u, a.p, prop, ctx_of(a)) == b.f.delta_H(u, b.p, prop, ctx_of(b)),
        proposal_states(a; mcs = (0, 5), n = 200))

    σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1                 # a wall along one side
    for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 6:6:18))
        σk[i:(i + 4), j:(j + 4)] .= c + 1
    end
    n = maximum(σk)
    kinds = [c == 1 ? :wall : isodd(c) ? :dark : :light for c in 1:n]
    prob = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => kinds], (0, 20))
    ctx = ctx_of(prob)
    Tof(old, new) = prob.f.temperature(prob.u0, prob.p, CorePotts.Proposal(1, 2, (1, 1), 1, Int32(old), Int32(new)), ctx)
    dark_cell = findfirst(==(:dark), kinds); light_cell = findfirst(==(:light), kinds)
    @test Tof(dark_cell, light_cell) == 5.0 && Tof(light_cell, dark_cell) == 5.0     # min of the two
    @test Tof(0, light_cell) == 20.0 && Tof(dark_cell, 0) == 5.0                     # medium never contributes
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
    @test u.σ[:, 1:2] == σk[:, 1:2] && u.cell.volume[1] == 48                       # the wall never moves
    @test u.σ != σk
end

# Compartments (D-036) in the authoring surface: the CorePotts nucleus/cytoplasm test model.
@potts_model Compartments begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0]
        λ = 1.0
        λc = 1.0
        Vc = 64.0
        λs = 0.1
        Sc = 32.0
        T = 10.0
    end
    @variables mass(cell) = 2.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2 + λs * (cluster_surface - Sc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end

function compartment_state()
    σ = zeros(Int32, 30, 30)
    n = 0
    for i in 1:10:21, j in 1:10:21
        n += 1
        σ[i:(i + 7), j:(j + 7)] .= n
    end
    for c in 1:n
        idx = findall(==(c), σ); lo = minimum(idx)
        σ[(lo[1] + 2):(lo[1] + 5), (lo[2] + 2):(lo[2] + 5)] .= n + c
    end
    return σ, vcat(fill(:cytoplasm, n), fill(:nucleus, n)), vcat(1:n, 1:n)
end

@testset "compartments in the authoring surface" begin
    σ, kinds, groups = compartment_state()
    prob = PottsProblem(Compartments(; name = :comp), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
    u0 = prob.u0
    @test Array(u0.cell.cluster)[1:18] == vcat(1:9, 1:9)
    @test Array(u0.cell.cluster_volume)[1:9] == fill(64, 9)
    @test Array(u0.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(σ, u0.cell.cluster, prob.lattice, Moore(1)) &&
          allequal(Array(u0.cell.cluster_surface)[1:9])      # nuclei are internal
    # the hand-written CorePotts model (lib/CorePotts/test/compartments.jl)
    Jt = [0 16 16; 16 14 30; 16 30 14]
    ki(st, a) = a == 0 ? 1 : Int(st.cell.kind[a]) + 1
    function hand(st, p, prop, ctx)
        J(a, b) = CorePotts.same_cluster(st.cell, a, b) ? 2.0 : Float64(Jt[ki(st, a), ki(st, b)])
        E(v, c) = (v - (48.0, 16.0)[st.cell.kind[c]])^2
        EC(v, k) = st.cell.kind[k] == 1 ? (v - 64.0)^2 : 0.0
        ES(s, k) = st.cell.kind[k] == 1 ? 0.1 * (s - 32.0)^2 : 0.0
        return CorePotts.contact_delta(st.σ, ctx, prop, J) + CorePotts.volume_delta(st.cell.volume, prop, E) +
               CorePotts.cluster_volume_delta(st.cell, prop, EC) +
               CorePotts.cluster_surface_delta(st.cell, prop, CorePotts.cluster_surface_change(st.σ, st.cell, ctx, prop), ES)
    end
    ctx = ctx_of(prob)
    states = proposal_states(remake(prob; tspan = (0, 1)); mcs = (0, 1), n = 400)
    @test maximum(((u, prop),) -> abs(prob.f.delta_H(u, prob.p, prop, ctx) - hand(u, prob.p, prop, ctx)), states) < 1e-9
    @test selfcheck(remake(prob; tspan = (0, 1))) < 1e-9
    # trackers stay exact through a run
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
    cl = Array(u.cell.cluster)
    @test Array(u.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(u.σ), cl)
    @test Array(u.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(u.σ), cl, prob.lattice, Moore(1))
    # checkerboard claims the clusters of old and new
    t = findfirst(==(Int32(10)), σ)      # a nucleus site of cluster 1
    @test prob.f.claims(u0, prob.p, CorePotts.Proposal(LinearIndices(σ)[t], 1, Tuple(t), 1, Int32(10), Int32(5)), ctx) == (1, 5)
    # a cluster divides as a unit: both daughters keep a nucleus and a cytoplasm
    sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = Moore(1)))
    v = sol.u[end]
    live = findall(>(0), Array(v.cell.volume))
    @test length(live) == 36
    roots = unique(Array(v.cell.cluster)[live])
    @test length(roots) == 18
    @test all(r -> sort(Array(v.cell.kind)[filter(c -> v.cell.cluster[c] == r, live)]) == [1, 2], roots)
    @test sum(Array(v.cell.mass)[live]) ≈ 36.0          # every member split its mass
    @test sort(Array(v.cell.mass)[live]) == fill(1.0, 36)
end

@testset "compartment validation" begin
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :a],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        energies = [Potts.EnergyTerm(Potts.CellDomain(Int[]), Potts.B.cluster_volume^2)]))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :a],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        energies = [Potts.EnergyTerm(Potts.ContactDomain(:contact), Potts.B.cluster_volume)]))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :a],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        divisions = [Potts.divide(Potts.cells(1); when = Potts.B.volume > 1),
            Potts.divide(Potts.clusters(1); when = Potts.B.volume > 1)]))
end

@testset "ensembles and callbacks of generated problems" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    alg = SequentialCPM(; proposal = Moore(1))
    ens = solve(EnsembleProblem(prob; output_func = (sol, ctx) -> (total_energy(prob, sol.u[end]), false)),
        alg, EnsembleThreads(); trajectories = 4)
    @test length(unique(ens.u)) == 4
    @test ens.u[3] == total_energy(prob, solve(remake(prob; replica = 3), alg).u[end])
    # a callback that quenches the temperature through a symbolic parameter map
    cold = remake(prob; p = [:T => 0.0])
    quench = DiscreteCallback((u, t, integ) -> t == 2, integ -> (integ.p = cold.p))
    integ = init(prob, alg; callback = quench)
    foreach(_ -> step!(integ), 1:3)
    @test integ.p.T == 0.0
end

@potts_model ClusterCensus begin
    @kinds medium cytoplasm nucleus
    @parameters T = 10.0
    @variables total(model) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy cells => (volume - 40.0)^2
    @after_mcs total ~ sum(cluster_volume for c in cells)
    @divide cells(nucleus) when = (cluster == id) && (mcs == 100), along = (1.0, 0.0)
    @sweep Metropolis(; temperature = T)
end

@testset "compartment review regressions" begin
    σ, kinds, groups = compartment_state()
    # populations read the bound cell's cluster trackers
    p = PottsProblem(ClusterCensus(; name = :cc), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
    u = solve(p, SequentialCPM(; proposal = Moore(1))).u[end]
    @test u.model.total[1] == sum(u.cell.cluster_volume[u.cell.cluster[c]] for c in 1:18 if u.cell.volume[c] > 0)
    # roots are chosen among the kinds that name clusters, whatever the numbering
    n = 9
    σn = map(s -> s == 0 ? s : Int32(s <= n ? s + n : s - n), σ)     # nuclei first
    pn = PottsProblem(Compartments(; name = :comp), [ownership => σn, kind => vcat(kinds[(n + 1):end], kinds[1:n]),
        cluster => groups], (0, 1))
    @test Array(pn.u0.cell.cluster)[1:18] == vcat(n + 1:2n, n + 1:2n)
    @test total_energy(pn) ≈ total_energy(PottsProblem(Compartments(; name = :comp),
        [ownership => σ, kind => kinds, cluster => groups], (0, 1)))
    # remake with a new state recomputes the frozen mask
    σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1; σk[10:14, 10:14] .= 2
    kt = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => [:wall, :dark]], (0, 5))
    σk2 = zeros(Int32, 24, 24); σk2[:, 23:24] .= 1; σk2[10:14, 10:14] .= 2
    kt2 = remake(kt; u0 = [ownership => σk2, kind => [:wall, :dark]])
    @test kt2.frozen == (σk2 .== 1)
    # clusters used only in a division condition or an observed quantity still get storage
    base = (; name = :x, kinds = [:medium, :a], lattice = Potts.lattice_spec((8, 8)),
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0))
    @test mtkcompile(Potts.PottsSystem(; base..., divisions = [Potts.divide(Potts.cells(1);
        when = Potts.B.cluster == Potts.B.id)])).uses_clusters
    @test mtkcompile(Potts.PottsSystem(; base..., observed = [Potts.ObservedEq(Potts.observed_var(:cv),
        Potts.B.cluster_volume)])).uses_clusters
end

@potts_model DiskSorting begin
    @kinds medium dark light
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables c(field) = 0.0
    @lattice Lattice((40, 40); boundary = Closed(), domain = x -> (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2)
    @energy begin
        Volume(dark, light; target = 25.0)
        Adhesion(J)
    end
    @equations D(c) ~ 0.2 * Δ(c) + 0.01 * (kind == dark)
    @sweep Metropolis(; temperature = T)
end

@testset "irregular lattice domains in the surface" begin
    sys = DiskSorting(; name = :disk)
    mask = sys.lattice.domain
    σ, kinds = two_kind_blocks()
    σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= σ
    @test all(mask[σd .> 0])
    prob = PottsProblem(sys, [ownership => σd, kind => kinds], (0, 30))
    @test count(prob.frozen) == count(!, mask)
    @test selfcheck(prob) < 1e-9
    u = solve(prob, CheckerboardCPM(; proposal = Moore(1))).u[end]
    @test all(u.σ[.!mask] .== 0) && all(u.site.c[.!mask] .== 0)
    @test sum(u.site.c) > 0
    σbad = copy(σd); σbad[1, 1] = 1
    @test_throws ArgumentError PottsProblem(sys, [ownership => σbad, kind => kinds], (0, 1))
end

# Composition: a chemotactic extension of the Graner model and an obstacle kind added to it.
@potts_model ChemoSorting begin
    @extend λ, V₀, dark = base = Sorting()
    @parameters χ = 50.0
    @variables c(field) = 0.0
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
    @equations D(c) ~ 0.1 * Δ(c) + 0.02 * (kind == dark) - 0.01 * c
    @observed mean_excess ~ sum((volume - V₀) for n in cells) * λ
end

@potts_model WalledSorting begin
    @extend base = Sorting(; lattice = (40, 40), T = 6.0)
    @kinds medium dark light wall[frozen]
    @parameters J[kind, kind] = [0 16 16 30; 16 2 11 30; 16 11 14 30; 30 30 30 0]
end

@testset "composition: extend and @extend" begin
    ext = ChemoSorting(; name = :chemo)
    @test ext.kinds == [:medium, :dark, :light]
    @test Set(Potts.info(x).name for x in ext.parameters) == Set([:λ, :V₀, :T, :J, :χ])
    @test length(ext.energies) == 2 && length(ext.drives) == 1 && ext.lattice == SORTING.sys.lattice
    σ, kinds = graner_state()
    a = symbolic_graner_problem(; nmcs = 5)
    b = PottsProblem(ext, [ownership => σ, kind => kinds], (0, 5))
    # without the drive the extension's energy is the base's
    @test all(((u, prop),) -> energy_change(a, u, prop) == energy_change(b, u, prop), proposal_states(a; mcs = (0, 5), n = 100))
    @test b.p.χ == 50.0 && haskey(b.u0.site, :c)
    @test selfcheck(b) < 1e-9
    sol = solve(b, SequentialCPM(; proposal = Moore(1)))
    @test length(sol[:mean_excess]) == length(sol.t)
    @test sol[:volume][end] == [Float64(v) for v in sol.u[end].cell.volume] && sol[:c][end] == sol.u[end].site.c
    # an added frozen kind and a redeclared (wider) contact table; base overrides by keyword
    w = WalledSorting(; name = :walled)
    @test w.kinds == [:medium, :dark, :light, :wall] && w.frozen_kinds == [3]
    @test count(x -> Potts.info(x).name === :J, w.parameters) == 1 && size(Potts.info(only(filter(x -> Potts.info(x).name === :J, w.parameters))).default) == (4, 4)
    @test w.lattice.dims == (40, 40)
    σw = zeros(Int32, 40, 40); σw[:, 1] .= 1; σw[10:15, 10:15] .= 2; σw[20:25, 20:25] .= 3
    pw = PottsProblem(w, [ownership => σw, kind => [:wall, :dark, :light]], (0, 10))
    @test pw.p.T == 6.0 && count(pw.frozen) == 40
    @test_throws ArgumentError extend(PottsSystem(; name = :x, kinds = [:medium, :light], lattice = SORTING.sys.lattice,
        sweep = SORTING.sys.sweep), SORTING.sys)
    @test_throws ArgumentError Potts.lookup(SORTING.sys, :nope)
end

@potts_model BadSiteVar begin
    @kinds medium A
    @parameters T = 1.0
    @variables x(site) = 0.0
    @lattice Lattice((8, 8))
    @energy begin
        cells(A) => (volume - 10.0)^2
        cells(A) => x                      # a site variable without a site
    end
    @sweep Metropolis(; temperature = T)
end
const BAD_ENERGY_LINE = @__LINE__() - 4

@potts_model BadDrive begin
    @kinds medium A
    @parameters T = 1.0
    @lattice Lattice((8, 8))
    @drive copy => volume                  # `volume` changes with the copy
    @sweep Metropolis(; temperature = T)
end
const BAD_DRIVE_LINE = @__LINE__() - 3

@testset "diagnostics name the statement and its source line" begin
    msg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    m = msg(() -> mtkcompile(BadSiteVar(; name = :bad)))
    @test occursin("needs a site", m) && occursin("in @energy cells(1) => x", m) &&
          occursin("symbolic.jl:$BAD_ENERGY_LINE", m)
    m = msg(() -> mtkcompile(BadDrive(; name = :bad)))
    @test occursin("`volume` is not available in a drive", m) && occursin("symbolic.jl:$BAD_DRIVE_LINE", m)
    # locations survive `extend`
    m = msg(() -> mtkcompile(extend(PottsSystem(; name = :e, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)), BadSiteVar(; name = :bad))))
    @test occursin("symbolic.jl:$BAD_ENERGY_LINE", m)
end

# Components (M4.1): MTK systems instantiated per cell, advanced by a batched cell ODE kernel.
using Potts.ModelingToolkitBase: System, @parameters
const _tc = Potts.t
Potts.ModelingToolkitBase.@variables y_c(_tc) = 1.0 m_c(_tc) = 0.0
@parameters k_c = 0.3 τ_c = 20.0 r_c = 1.0
@named decay = System([Potts.D(y_c) ~ -k_c * y_c], _tc)
@named clock = System([Potts.D(m_c) ~ r_c / τ_c], _tc)

function component_model(solver)
    @potts_model Decaying begin
        @kinds medium A B
        @parameters T = 1.0
        @components begin
            decay = decay
        end
        @components cells(A) clock = clock
        @equations clock.r_c ~ volume / 25
        @lattice Lattice((20, 20))
        @energy cells => (volume - 25.0)^2
        @divide cells(A) when = clock.m_c >= 1, along = (1.0, 0.0), clock.m_c => 0.0
        @sweep Metropolis(; temperature = T, ode_solver = solver)
    end
    return Decaying(; name = :decaying)
end

@testset "components: MTK systems per cell" begin
    σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    frozen(sys) = PottsProblem(sys, op, (0, 10); T = Float64)
    for (solver, exact, tol) in ((Potts.ExplicitEuler(), t -> (1 - 0.3)^t, 1e-12),
            (Potts.RK4(substeps = 2), t -> (1 + (z = -0.15) + z^2 / 2 + z^3 / 6 + z^4 / 24)^(2t), 1e-12))
        sys = component_model(solver)
        cs = mtkcompile(sys)
        @test Set(Potts.info(v).name for v in cs.sys.variables) == Set([:decay₊y_c, :clock₊m_c])
        @test Set(Potts.info(v).name for v in cs.sys.parameters) == Set([:T, :decay₊k_c, :clock₊τ_c])   # r_c is coupled
        # no copies (T = 0 and frozen cells) so the volume coupling is exact
        prob = remake(PottsProblem(cs, op, (0, 10)); p = [:T => 1e-9])
        sol = solve(prob, SequentialCPM(); saveat = 0:10)
        ys = [u.cell.decay₊y_c[1] for u in sol.u]
        @test maximum(abs.(ys .- exact.(0:10))) < tol
        @test all(u -> u.cell.decay₊y_c[2] == u.cell.decay₊y_c[1], sol.u)            # every kind
        @test sol.u[end].cell.clock₊m_c[2] == 0.0                                     # kind-scoped
        @test sol[:decay₊y_c][end] == sol.u[end].cell.decay₊y_c
    end
    # coupling and division: the clock runs at volume/25/τ per MCS and resets on division
    sys = component_model(Potts.ExplicitEuler())
    prob = remake(PottsProblem(sys, op, (0, 12)); p = [:T => 1e-9, Symbol("clock₊τ_c") => 8.0])
    sol = solve(prob, SequentialCPM(); saveat = 0:12)
    m = [u.cell.clock₊m_c[1] for u in sol.u]
    @test m[1:8] == (0:7) ./ 8                          # exact: 1/8 per MCS at volume 25
    @test m[9] == 0.0 && sol.u[9].cell.clock₊m_c[3] == 0.0 && count(>(0), sol.u[9].cell.volume) == 3
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        components = [Potts.ComponentSpec(:clock, clock, Potts.CellDomain(Int[]))],
        equations = [Potts.Symbolics.variable(Symbol("clock₊nope")) ~ 1.0]))
end

# First-class 3D: the same surface, N-generic generated code.
@potts_model Sorting3D begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 64.0
        λₛ = 0.01
        S₀ = 430.0                         # a 4³ cube has 432 NeighborOrder(2) bonds
        T = 12.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables begin
        c(field) = 0.0
        mass(cell) = 1.0
    end
    @lattice Lattice((24, 24, 24); boundary = Closed(), neighborhood = NeighborOrder(2),
        domain = x -> sum(abs2, x .- 12.5) <= 11.5^2)
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts => J[kind, kind′]
    end
    @drive copy => -2.0 * (c[target] - c[source]) * (kind[new] == dark)
    @equations D(c) ~ 0.1 * Δ(c) + 0.05 * (kind == dark) - 0.01 * c
    @divide cells(dark) when = (mcs == 3) && (volume >= 40), along = principal_axis(), mass => Split()
    @sweep Metropolis(; temperature = T)
end

@testset "3D models" begin
    σ = zeros(Int32, 24, 24, 24)
    n = 0
    for i in 8:5:13, j in 8:5:13, k in 8:5:13
        n += 1
        σ[i:(i + 3), j:(j + 3), k:(k + 3)] .= n
    end
    kinds = [isodd(c) ? :dark : :light for c in 1:n]
    prob = PottsProblem(Sorting3D(; name = :s3), [ownership => σ, kind => kinds], (0, 6))
    @test ndims(prob.lattice) == 3 && length(prob.contact) == 18                      # NeighborOrder(2) in 3D
    @test selfcheck(prob) < 1e-9
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        u = solve(prob, alg).u[end]
        live = findall(>(0), u.cell.volume)
        @test length(live) > n                                                      # dark cells divided in 3D
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
        @test u.cell.surface ≈ CorePotts.recompute_surface(u.σ, prob.lattice, prob.relations.surface, length(u.cell.volume);
            T = eltype(u.cell.surface))
        @test sum(u.cell.mass[live]) ≈ n
        @test all(u.σ[.!prob.lattice.mask] .== 0)
    end
end

@parameters k_nd
@named nodefault = System([Potts.D(y_c) ~ -k_nd * y_c], _tc)

@potts_model TwoClocks begin
    @kinds medium A B
    @parameters T = 1.0
    @components cells(A) fast = clock
    @components cells(B) slow = clock
    @components dec = decay
    @equations begin
        slow.r_c ~ 0.5
        dec.k_c ~ fast.m_c / 10                      # a coupling reading another component
    end
    @observed om(cell) ~ slow.m_c
    @lattice Lattice((20, 20))
    @energy cells => (volume - 25.0)^2
    @sweep Metropolis(; temperature = T)
end

@testset "component and domain review regressions" begin
    σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    # components are named by their binding, whatever the system is called
    p = remake(PottsProblem(TwoClocks(; name = :two), op, (0, 4)); p = [:T => 1e-9])
    @test Set(propertynames(p.p)) == Set([:T, :fast₊τ_c, :fast₊r_c, :slow₊τ_c])
    sol = solve(p, SequentialCPM(); saveat = 0:4)
    u = sol.u[end]
    @test u.cell.fast₊m_c ≈ [4 / 20, 0] && u.cell.slow₊m_c ≈ [0, 0.5 * 4 / 20]
    @test sol[:om][end] == u.cell.slow₊m_c
    @test u.cell.dec₊y_c[1] ≈ prod(1 - m / 10 for m in (0:3) ./ 20)             # Euler with k = m(t)/10
    # couplings target component parameters only
    @potts_model BadCoupling begin
        @kinds medium A
        @parameters T = 1.0
        @components clock = clock
        @equations clock.m_c ~ volume
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = T)
    end
    @test_throws ArgumentError mtkcompile(BadCoupling(; name = :b))
    # component values without defaults must be given
    @potts_model NoDefault begin
        @kinds medium A
        @parameters T = 1.0
        @components nd = nodefault
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = T)
    end
    σ8 = zeros(Int32, 8, 8); σ8[3:5, 3:5] .= 1
    @test_throws ArgumentError PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1]], (0, 1))
    pn = PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1], Symbol("nd₊k_nd") => 0.5], (0, 1))
    @test pn.p.nd₊k_nd == 0.5
    # kind tables must cover every kind (an extension adding kinds)
    @potts_model MoreKinds begin
        @extend base = Sorting()
        @kinds medium dark light extra
    end
    σg, kg = graner_state()
    @test_throws ArgumentError PottsProblem(MoreKinds(; name = :m), [ownership => σg, kind => kg], (0, 1))
    # models with domains fingerprint by content: checkpoints resume across rebuilds
    σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= first(two_kind_blocks())
    kd = last(two_kind_blocks())
    p1 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6))
    p2 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6))
    @test p1.f.fingerprint == p2.f.fingerprint && DiskSorting(; name = :a).lattice == DiskSorting(; name = :b).lattice
    integ = init(p1, SequentialCPM()); foreach(_ -> step!(integ), 1:3)
    ck = checkpoint(integ)
    @test solve!(init(p2, SequentialCPM(); checkpoint = ck)).u[end].σ == solve(p1, SequentialCPM()).u[end].σ
    # site populations stay inside the domain
    @test observe(p1, Potts._fold_iter(count, s -> true, Potts.sites, nothing)) == count(DiskSorting(; name = :d).lattice.domain)
end

module UserFunctions
using Potts
using Potts: Symbolics
hill(x, K) = x^2 / (K^2 + x^2)
Symbolics.@register_symbolic hill(x, K)
@potts_model Hill begin
    @kinds medium A
    @parameters T = 5.0
    @variables g(cell) = 0.5
    @lattice Lattice((16, 16))
    @energy cells => (volume - 20.0 * hill(g, 0.5))^2
    @after_mcs g ~ Pre(g) + 0.1 * hill(volume, 10.0)
    @sweep Metropolis(; temperature = T)
end
end

@testset "user-registered functions in generated code" begin
    σ = zeros(Int32, 16, 16); σ[5:9, 5:9] .= 1
    p = PottsProblem(UserFunctions.Hill(; name = :h), [ownership => σ, kind => [1]], (0, 5))
    @test selfcheck(p) < 1e-9
    u = solve(p, SequentialCPM()).u[end]
    @test u.cell.g[1] > 0.5
end

@potts_model Noisy begin
    @kinds medium A
    @parameters T = 1.0
    @variables begin
        u(cell) = 0.0
        w(site) = 0.0
        tally(model) = 0.0
    end
    @lattice Lattice((16, 16))
    @after_mcs begin
        u ~ rand()
        w ~ rand()
        tally ~ Pre(tally) + rand()
    end
    @divide cells(A) when = (mcs == 2) && (rand() < 0.5), along = RandomPlane()
    @sweep Metropolis(; temperature = T)
end

@testset "rand(): counter-based draws in updates and divisions" begin
    σ = zeros(Int32, 16, 16)
    for (c, (i, j)) in enumerate(Iterators.product(1:4:13, 1:4:13))
        σ[i:(i + 2), j:(j + 2)] .= c
    end
    p = PottsProblem(Noisy(; name = :n), [ownership => σ, kind => fill(1, 16)], (0, 4); seed = 3)
    s1 = solve(p, SequentialCPM(); saveat = 0:4)
    s2 = solve(p, CheckerboardCPM(); saveat = 0:4)
    live = findall(c -> s1.u[end].cell.volume[c] > 0 && s2.u[end].cell.volume[c] > 0, 1:16)
    @test s1.u[end].cell.u[live] == s2.u[end].cell.u[live] && s1.u[end].site.w == s2.u[end].site.w &&
          s1.u[end].model.tally == s2.u[end].model.tally                                # schedule-independent
    @test s1.u[2].cell.u != s1.u[3].cell.u                                                # fresh every MCS
    w = s1.u[end].site.w
    @test length(unique(w)) == length(w) && abs(sum(w) / length(w) - 0.5) < 0.05          # per site, uniform
    @test 0 < s1.stats.lifecycle.divisions < 16                                           # about half divide
    @test s1.u[end].cell.u != solve(remake(p; seed = 4), SequentialCPM()).u[end].cell.u
    @potts_model RandomEnergy begin
        @kinds medium A
        @parameters T = 1.0
        @lattice Lattice((8, 8))
        @energy cells => (volume - 10 * rand())^2
        @sweep Metropolis(; temperature = T)
    end
    @test_throws ArgumentError mtkcompile(RandomEnergy(; name = :r))
end

@potts_model Persistent begin
    @kinds medium A
    @parameters μ = 0.0 T = 2.0
    @variables begin
        px(cell) = 0.0
        py(cell) = 0.0
        cx(cell) = 0.0
        cy(cell) = 0.0
    end
    @lattice Lattice((48, 48); neighborhood = Moore(1))
    @energy begin
        Volume(A; target = 25.0, strength = 2.0)
        contacts => 4 * (kind != kind′)
    end
    @drive copy => -μ * (px[new] * displacement(new, 1) + py[new] * displacement(new, 2) +
                         px[old] * displacement(old, 1) + py[old] * displacement(old, 2))
    @after_mcs begin
        px ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(px) + 0.2 * (centroid(1) - Pre(cx)))
        py ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(py) + 0.2 * (centroid(2) - Pre(cy)))
        cx ~ centroid(1)
        cy ~ centroid(2)
    end
    @observed x(cell) ~ centroid(1)
    @sweep Metropolis(; temperature = T)
end

@testset "centroid/displacement: persistent motility" begin
    σ = zeros(Int32, 48, 48)
    σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 1); seed = 1)
    st, lat = p.u0, p.lattice
    mean_x(σ, d) = sum(i -> CorePotts.coordinates(lat, i)[d], findall(==(1), vec(σ))) / count(==(1), σ)
    @test CorePotts.centroid(Float64, st.cell, lat, 1) == (mean_x(σ, 1), mean_x(σ, 2))
    for (x, new, old) in (((27, 24), 1, 0), ((22, 23), 0, 1))           # add / remove a site
        prop = CorePotts.Proposal{2}(0, 0, x, 0, Int32(old), Int32(new))
        σ2 = copy(σ); σ2[x...] = new
        for k in 1:2
            @test Potts._displacement_axis(Float64, st.cell, lat, prop, 1, k) ≈ mean_x(σ2, k) - mean_x(σ, k)
            @test Potts._displacement_axis(Float64, st.cell, lat, prop, 2, k) == 0
        end
    end
    s = solve(p, SequentialCPM())
    @test s[:x][end][1] ≈ s.u[end].cell.cx[1]
    function travel(μ)
        d = map(1:6) do seed
            u = solve(remake(p; p = [:μ => μ], tspan = (0, 60), seed), SequentialCPM()).u[end]
            hypot(u.cell.cx[1] - 24, u.cell.cy[1] - 24)
        end
        return sum(d) / length(d)
    end
    @test travel(1000.0) > 2 * travel(0.0)
    @potts_model BadCentroid begin
        @kinds medium A
        @lattice Lattice((8, 8))
        @drive copy => centroid(1)
        @sweep Metropolis(; temperature = 1.0)
    end
    @test_throws Exception mtkcompile(BadCentroid(; name = :b))
end

@testset "symbolic setters: setp and setu on integrators" begin
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 6); seed = 2)
    integ = init(p, SequentialCPM())
    step!(integ)
    # parameters: same isbits type (nothing recompiles), effective from the next MCS
    P = typeof(integ.p)
    integ.ps[:μ] = 700
    @test integ.ps[:μ] === 700.0 && typeof(integ.p) === P
    setp(integ, :μ)(integ, 800.0)
    @test getp(integ, :μ)(integ) == 800.0
    @test_throws ArgumentError setp(p, :μ)(p, 1.0)                       # problems: remake
    # state: declared variables write through to the live state; built-ins are read-only
    integ[:px] = [0.5]
    @test integ.state.cell.px == [0.5] && integ[:px] == [0.5] && getu(integ, :px)(integ) == [0.5]
    setu(integ, :py)(integ, -0.25)
    @test integ.state.cell.py == [-0.25]
    @test_throws DimensionMismatch (integ[:px] = [1.0, 2.0])
    @test_throws Exception (integ[:volume] = [3])
    sol = solve!(integ)
    @test sol[:x][end][1] ≈ sol.u[end].cell.cx[1]                     # observed still derived
    @test sol[:px][end] == sol.u[end].cell.px
    SII = Potts.SymbolicIndexingInterface
    @test SII.is_variable(p.f.sys, :px) && !SII.is_variable(p.f.sys, :volume) && SII.is_observed(p.f.sys, :volume)
    @potts_model Counter begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        @after_mcs n ~ Pre(n) + 1
        @sweep Metropolis(; temperature = 1.0)
    end
    σc = zeros(Int32, 8, 8); σc[3:5, 3:5] .= 1
    ic = init(PottsProblem(Counter(; name = :c), [ownership => σc, kind => [1]], (0, 5)), SequentialCPM())
    step!(ic); step!(ic)
    @test ic[:n] == 2
    ic[:n] = 10
    step!(ic)
    @test ic[:n] == 11
end

@testset "centroid/displacement/rand review regressions" begin
    _bad(body) = eval(:(@potts_model _Bad begin
        @kinds medium A
        @variables cz(cell) = 0.0
        @lattice Lattice((8, 8))
        $(body)
        @sweep Metropolis(; temperature = 1.0)
    end))
    bad(body) = Base.invokelatest(_bad(body); name = :b)
    @test_throws ArgumentError mtkcompile(bad(:(@drive copy => -displacement(new, 3))))   # 2D: no axis 3
    @test_throws ArgumentError mtkcompile(bad(:(@after_mcs cz ~ centroid(3))))
    @test_throws ArgumentError mtkcompile(bad(:(@energy cells => 100 * (centroid(1) - 5)^2)))
    @test_throws ArgumentError mtkcompile(bad(:(@observed r ~ rand())))
    # empty cell slots observe a zero centroid, not NaN
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 2); capacity = 4)
    x = solve(p, SequentialCPM())[:x][end]
    @test length(x) == 4 && x[2:4] == zeros(3) && !any(isnan, x)
end

@potts_model Lags begin
    @kinds medium A
    @variables begin
        n(model) = 0.0
        lag3(model) = -1.0
        w(site) = 0.0
        wlag(site) = -1.0
        u(cell) = 0.0
    end
    @lattice Lattice((8, 8))
    @after_mcs begin
        n ~ Pre(n) + 1
        lag3 ~ Pre(n, 3)
        w ~ Pre(w) + 1
        wlag ~ Pre(w, 2) - Pre(w, 1)
    end
    @sweep Metropolis(; temperature = 1.0)
end

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
    for body in (:(@after_mcs u ~ Pre(u, 2)), :(@energy cells => Pre(volume, 2)), :(@observed q ~ Pre(n, 2)))
        m = eval(:(@potts_model _BadLag begin
            @kinds medium A
            @variables begin
                u(cell) = 0.0
                n(model) = 0.0
            end
            @lattice Lattice((8, 8))
            $(body)
            @sweep Metropolis(; temperature = 1.0)
        end))
        @test_throws ArgumentError mtkcompile(Base.invokelatest(m; name = :b))
    end
end

@potts_model Integrals begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        mass(cell) = 0.0
        hot(cell) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        mass ~ integral(w)
        hot ~ integral(w > 0.5) / volume
        n ~ Pre(n) + 1
    end
    @observed begin
        cmass(cell) ~ integral(w)
        occupied(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 2.0)
end

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
    for body in (:(@energy cells => integral(w)), :(@drive copy => integral(w)))
        m = eval(:(@potts_model _BadIntegral begin
            @kinds medium A
            @variables w(site) = 0.0
            @lattice Lattice((8, 8))
            $(body)
            @sweep Metropolis(; temperature = 1.0)
        end))
        @test_throws ArgumentError mtkcompile(Base.invokelatest(m; name = :b))
    end
end

@potts_model PersistentVec begin
    @kinds medium A
    @parameters μ = 0.0 T = 2.0
    @lattice Lattice((48, 48); neighborhood = Moore(1))
    @variables begin
        pol(cell)[1:2] = 0.0
        c(cell)[1:2] = 0.0
    end
    @energy begin
        Volume(A; target = 25.0, strength = 2.0)
        contacts => 4 * (kind != kind′)
    end
    @drive copy => -μ * (dot(pol[new], displacement(new)) + dot(pol[old], displacement(old)))
    @after_mcs begin
        pol ~ ifelse(mcs == 0, 0.0, 1.0) .* (0.8 * Pre(pol) + 0.2 * (centroid() - Pre(c)))
        c ~ centroid()
    end
    @observed speed(cell) ~ norm(pol)
    @sweep Metropolis(; temperature = T)
end

@potts_model VectorBits begin
    @kinds medium A
    @parameters begin
        d[1:2] = [1.0, 0.0]
        T = 1.0
    end
    @lattice Lattice((12, 12))
    @variables begin
        g(site)[1:2] = [0.5, -0.5]
        m(model)[1:2] = 0.0
        q(cell)[1:3] = [1.0, 2.0, 3.0]
    end
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ Pre(m) + d
        g ~ normalize(g)
    end
    @divide cells(A) when = mcs == 1, q => Split()
    @sweep Metropolis(; temperature = T)
end

@testset "vector quantities" begin
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    for μ in (0.0, 1000.0)
        a = solve(PottsProblem(Persistent(; name = :a, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
        b = solve(PottsProblem(PersistentVec(; name = :b, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
        @test a.u[end].σ == b.u[end].σ                                          # same model, same run
        @test a.u[end].cell.px ≈ b.u[end].cell.pol_1 && a.u[end].cell.cy ≈ b.u[end].cell.c_2
        @test b[:speed][end] ≈ hypot.(b.u[end].cell.pol_1, b.u[end].cell.pol_2)
    end
    σ2 = zeros(Int32, 12, 12); σ2[4:6, 4:6] .= 1
    p = PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1]], (0, 3); capacity = 4)
    @test p.p.d_1 == 1.0 && p.p.d_2 == 0.0 && p.u0.cell.q_3[1] == 3.0 && all(==(0.5), p.u0.site.g_1)
    u = solve(p, SequentialCPM()).u[end]
    @test u.model.m_1[1] == 3 && u.model.m_2[1] == 0
    @test all(x -> x ≈ sqrt(0.5), u.site.g_1) && all(x -> x ≈ -sqrt(0.5), u.site.g_2)
    live = findall(>(0), u.cell.volume)
    @test length(live) == 2 && sum(u.cell.q_2[live]) ≈ 2.0                    # Split() per component
    q = remake(p; p = [:d => [0.0, 2.0]])
    @test q.p.d_1 == 0.0 && q.p.d_2 == 2.0
    r = PottsProblem(VectorBits(; name = :v, d = [5.0, 6.0]), [ownership => σ2, kind => [1], :q => [(7.0, 8.0, 9.0)],
        :g => fill(1.0, 12, 12, 2)], (0, 1))
    @test r.p.d_2 == 6.0 && r.u0.cell.q_2[1] == 8.0 && all(==(1.0), r.u0.site.g_2)
    @test_throws ArgumentError PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1], :q => [1.0, 2.0]], (0, 1))
end

@potts_model Fresh begin
    @kinds medium A
    @parameters k = 1.0
    @variables begin
        w(site) = 1.0
        mb(cell) = 0.0
        n(model) = 0.0
        d1(site) = -1.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 44)^2
    @before_mcs mb ~ integral(k * w)
    @after_mcs begin
        w ~ Pre(w) + 1
        n ~ Pre(n) + 1
        d1 ~ Pre(n, 1) - Pre(n, 2)
    end
    @divide cells(A) when = volume > 40, along = RandomPlane()
    @observed begin
        cmass(cell) ~ integral(w)
        occ(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "integral and lag review regressions" begin
    σ = zeros(Int32, 16, 16); σ[3:8, 3:8] .= 1
    p = PottsProblem(Fresh(; name = :f), [ownership => σ, kind => [1]], (0, 4); capacity = 8)
    sol = solve(p, SequentialCPM(); saveat = 0:4)
    brute(u, x) = [sum(x[u.σ .== c]; init = 0.0) for c in eachindex(u.cell.volume)]
    names = [Potts._integral_name(x) for x in Potts._integrals(p.f.sys.csys.sys)]
    for (t, u) in zip(sol.t, sol.u)
        @test sol[:cmass][t + 1] ≈ brute(u, u.site.w)                 # observed: the saved state itself
        @test sol[:occ][t + 1] == u.cell.volume                        # after division too
        fresh = Potts._fresh_integrals(u, p.p, p.f.sys.ctx, t, Potts._integral_phases(p.f.sys.csys, Float64), names)
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

@potts_model Compound begin
    @kinds medium A
    @variables begin
        n(model) = 0.0
        g(model) = 1.0
        hits(site) = 0.0
        v(cell)[1:2] = 0.0
    end
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9)^2
    @on_copy hits[target] += 1
    @after_mcs begin
        n += 1
        n += 2
        n -= 0.5
        g *= 2
        v += [1.0, -1.0]
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CompoundBase begin
    @kinds medium A
    @variables n(model) = 0.0
    @lattice Lattice((10, 10))
    @after_mcs n += 1
    @observed twice ~ 2n
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CompoundExt begin
    @extend n = base = CompoundBase()
    @kinds medium A
    @after_mcs n += 10                 # replaces the base's update of `n`
    @observed twice ~ 3n               # and its observed `twice`
end

@testset "compound assignments, single writers, replacement" begin
    σ = zeros(Int32, 10, 10); σ[4:6, 4:6] .= 1
    sol = solve(PottsProblem(Compound(; name = :c), [ownership => σ, kind => [1]], (0, 4)), SequentialCPM())
    u = sol.u[end]
    @test u.model.n[1] == 4 * 2.5 && u.model.g[1] == 16
    @test u.cell.v_1[1] == 4 && u.cell.v_2[1] == -4
    @test sum(u.site.hits) == sol.stats.accepted                            # one per accepted copy
    s2 = solve(PottsProblem(CompoundExt(; name = :e), [ownership => σ, kind => [1]], (0, 3)), SequentialCPM())
    @test s2.u[end].model.n[1] == 30 && s2[:twice][end] == 90
    bad(body) = Base.invokelatest(eval(:(@potts_model _BadW begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        $(body)
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :b)
    @test_throws ArgumentError mtkcompile(bad(:(@after_mcs begin
        n ~ 1.0
        n ~ 2.0
    end)))                                                                  # two writers
    @test_throws LoadError bad(:(@after_mcs begin
        n ~ 1.0
        n += 2.0
    end))                                                                  # at macro expansion
    @test_throws LoadError bad(:(@after_mcs begin
        n += 1.0
        n *= 2.0
    end))                                                                  # at macro expansion
    ok = Base.invokelatest(eval(:(@potts_model _OkW begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        @after_mcs n += 1
        @after_mcs Every(5) n ~ 0.0
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :ok)
    @test mtkcompile(ok) isa CompiledPottsSystem                             # another cadence
end

Potts.ModelingToolkitBase.@variables drug_c(_tc) = 0.0
@parameters drug_k = 0.2 drug_dose = 0.0
@named drug = System([Potts.D(drug_c) ~ drug_dose - drug_k * drug_c], _tc)

@potts_model Systemic begin
    @kinds medium A
    @variables a(model) = 1.0
    @components model pk = drug
    @equations begin
        D(a) ~ -0.5 * a
        pk.drug_dose ~ count(true for c in cells)           # dosing ∝ the number of live cells
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, ode_solver = RK4(substeps = 4))
end

@testset "model-scope ODEs and components" begin
    σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1; σ[10:12, 10:12] .= 2; σ[15:17, 3:5] .= 3
    p = PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1]], (0, 10))
    @test :pk₊drug_c in propertynames(p.u0.model) && :pk₊drug_k in propertynames(p.p)
    for alg in (SequentialCPM(), CheckerboardCPM())
        u = solve(p, alg).u[end]
        x = 0.5 / 4
        @test u.model.a[1] ≈ (1 - x + x^2 / 2 - x^3 / 6 + x^4 / 24)^40 rtol = 1e-12  # RK4, 4 substeps per MCS
        @test u.model.pk₊drug_c[1] ≈ 3 / 0.2 * (1 - exp(-0.2 * 10)) rtol = 1e-5
    end
    @test_throws ArgumentError PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1], :a => nothing], (0, 1))
end

@potts_model HexSorting begin
    @kinds medium dark light
    @parameters begin
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        Dc = 0.1
    end
    @variables begin
        c(field) = 0.0
        cx(cell) = 0.0
    end
    @lattice Lattice((30, 30); geometry = Hexagonal(), neighborhood = Hex(2))
    @energy begin
        cells => (volume - 19)^2 + 0.2 * (surface - 60)^2
        contacts => J[kind, kind′]
    end
    @equations D(c) ~ Dc * Δ(c)
    @after_mcs cx ~ centroid(1)
    @sweep Metropolis(; temperature = 8.0)
end

@testset "hexagonal lattices in the surface" begin
    σ = zeros(Int32, 30, 30); c0 = zeros(30, 30); c0[15, 15] = 100.0
    n = 0
    for q in 4:6:26, r in 4:6:26
        n += 1
        for x in CartesianIndices(σ)
            CorePotts._hexdist(Tuple(x) .- (q, r)) <= 2 && (σ[x] = n)
        end
    end
    p = PottsProblem(HexSorting(; name = :h), [ownership => σ, kind => [isodd(k) ? :dark : :light for k in 1:n], :c => c0], (0, 20))
    @test p.lattice.geometry isa Hexagonal && length(p.contact) == 18
    for alg in (SequentialCPM(proposal = Hex(1)), CheckerboardCPM(proposal = Hex(1)))
        u = solve(p, alg).u[end]
        @test u.cell.volume == [count(==(k), u.σ) for k in 1:n]
        @test u.cell.surface ≈ CorePotts.recompute_surface(u.σ, p.lattice, p.relations.surface, n)
        @test sum(u.site.c) ≈ 100                                          # zero-sum 6-point Laplacian
        pos = [embed(p.lattice, Float64.(Tuple(x))) for x in CartesianIndices(u.σ)]
        k = findfirst(>(0), u.cell.volume)
        mine = pos[u.σ .== k]
        @test u.cell.cx[k] ≈ sum(first, mine) / length(mine) atol = 1e-9   # centroid() is Cartesian (no wrap here)
    end
end

@potts_model CadenceBase begin
    @kinds medium A
    @variables n(model) = 0.0
    @lattice Lattice((8, 8))
    @after_mcs n += 1
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CadenceExt begin
    @extend n = base = CadenceBase()
    @kinds medium A
    @after_mcs Every(5) n ~ 0.0             # another cadence: kept alongside the base's update
end

@testset "replacement respects cadence" begin
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    @test solve(PottsProblem(CadenceExt(; name = :c), [ownership => σ, kind => [1]], (0, 4)), SequentialCPM()).u[end].model.n[1] > 0
end
