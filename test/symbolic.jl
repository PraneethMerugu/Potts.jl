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
