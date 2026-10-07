# Generality guardrail (D-051 R0, review §6 (e)): for every published model, a sibling built
# only from public primitives. The sibling is another tool's variant of the model's defining
# mechanism. It must build, pass the ΔH self-check and show its mechanism. A published
# model without an entry in `SIBLINGS` fails.
using Statistics: mean

# Differential adhesion on a hexagonal lattice (Hex(2) contacts), Barker-free Metropolis
@potts_model HexSorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 20.0
        T = 4.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((30, 30); geometry = Hexagonal(), neighborhood = Hex(2))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

# Neighbourhood memory with Artistoo's arithmetic mean
@potts_model ActArithmetic begin
    @kinds medium cell
    @parameters begin
        λ = 5.0
        V₀ = 25.0
        λ_act = 200.0
        max_act = 20.0
        T = 20.0
        J[kind, kind] = [0.0 20.0; 20.0 100.0]
    end
    @variables act(site) = 0.0
    @lattice Lattice((24, 24); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    m(s) = mean(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
    @drive copy => -(λ_act / max_act) * (m(source) - m(target))
    @on_copy act[target] ~ ifelse(new != 0, max_act, 0.0)
    @after_mcs act ~ max(Pre(act) - 1, 0)
    @sweep Metropolis(; temperature = T)
end

# Chemotaxis with CompuCell3D's saturating response, in a static gradient
@potts_model SaturatingChemotaxis begin
    @kinds medium cell
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        χ = 400.0
        s = 0.5
        T = 6.0
    end
    @variables c(site) = 0.0
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy cells(cell) => λ * (volume - V₀)^2
    @drive Chemotaxis(c; strength = χ, response = saturating(s))
    @constraint connectivity(cell)
    @sweep Metropolis(; temperature = T)
end

# Soft connectivity (Artistoo / CC3D strength) with chemotaxis gated on copies involving a
# leader (either side), instead of Akeeb's hard one-arc veto
@potts_model SoftConnectedLeaders begin
    @kinds medium leader follower
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        μ = 30.0
        λ_conn = 1e4
        T = 10.0
        J[kind, kind] = [0.0 10.0 10.0; 10.0 4.0 4.0; 10.0 4.0 4.0]
    end
    @variables cue(site) = 0.0
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)
    @energy begin
        cells(leader, follower) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @drive Chemotaxis(cue; strength = μ, when = (kind[new] == leader) | (kind[old] == leader))
    @drive copy => λ_conn * (local_components > 1)
    @sweep Metropolis(; temperature = T)
end

# Growth to a target and division, along the major axis instead of a random plane
@potts_model MajorAxisGrowth begin
    @kinds medium cell
    @parameters begin
        A₀ = 16.0
        λ = 10.0
        g = 0.5
        T = 10.0
        J[kind, kind] = [0.0 10.0; 10.0 10.0]
    end
    @variables V_target(cell) = A₀
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @after_mcs V_target ~ Pre(V_target) + g
    @divide cells(cell) when = volume >= 2A₀, along = major_axis(), V_target => A₀
    @sweep Metropolis(; temperature = T)
end

# Compression release scheduled inside the model, CompuCell3D's way (a steppable doubles each
# cell's target at a fixed MCS; the chain's left end rests on a closed lattice edge), with a
# per-cell target variable instead of OpenVTChain's parameter switch by callback
@potts_model ScheduledRelease begin
    @kinds medium cell
    @parameters begin
        A_c = 16.0
        release = 20.0
        λ = 2.0
        T = 20.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables V_target(cell) = A_c
    @lattice Lattice((60, 4); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @after_mcs V_target ~ ifelse(mcs == release, 2A_c, Pre(V_target))
    @sweep Metropolis(; temperature = T)
end

# Contact inhibition Artistoo's way (the share of a cell's von Neumann contacts that are not
# with cells of the other kind), in a two-kind colony, with uniform division thresholds
# drawn per daughter: the contact fold over a named relation with a kind predicate
@potts_model KindInhibitedGrowth begin
    @kinds medium A B
    @parameters begin
        A₀ = 16.0
        λ = 4.0
        α = 0.4
        φ = 0.5
        T = 10.0
        J[kind, kind] = [0.0 10.0 10.0; 10.0 20.0 20.0; 10.0 20.0 20.0]
    end
    @variables begin
        A_star(cell) = A₀
        θ(cell) = 2.0
        free(cell) = 1.0
    end
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @relations begin
        proposal = Moore(1)
        vn = VonNeumann(1)
    end
    @energy begin
        cells(A, B) => λ * (volume - A_star)^2
        contacts => J[kind, kind′]
    end
    @after_mcs begin
        free ~ ifelse(count(true for _ in contacts(vn)) > 0,
            1 - ifelse(kind == A, count(kind′ == B for _ in contacts(vn)), count(kind′ == A for _ in contacts(vn))) /
                count(true for _ in contacts(vn)), 1.0)
        A_star ~ ifelse(free >= φ, Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(A, B) when = volume >= θ * A₀, along = RandomPlane(), A_star => Split(), θ => 1.5 + rand()
    @sweep Metropolis(; temperature = T)
end

# CompuCell3D's LengthConstraint (λ (l − L)², l from the inertia tensor) with its
# Connectivity plugin's hard one-arc veto, on a lattice with von Neumann copies and free
# closed walls, instead of Merks 2006's 8-neighbour copies, soft E₀ penalty and frozen
# border: isolated cells stretch to the target length
@potts_model ElongatedCells begin
    @kinds medium cell
    @parameters begin
        λ = 5.0
        V₀ = 36.0
        λ_L = 5.0
        L = 16.0
        T = 10.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)
    @energy begin
        cells(cell) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
        contacts => J[kind, kind′]
    end
    @constraint connectivity(cell)
    @sweep Metropolis(; temperature = T)
end

# CompuCell3D's `ChemotaxisByType … ChemotactTowards="Medium"` (chemotaxis only on a cell's
# extensions into the medium, a contact-inhibited form) through the `Chemotaxis` term with a
# `when` gate, in a static gradient, instead of Merks 2008's χ(c,M)/χ(c,c) drive on a
# secreted field with 20 neighbours
@potts_model MediumOnlyChemotaxis begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        χ = 300.0
        T = 8.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables c(site) = 0.0
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @drive Chemotaxis(c; strength = χ, when = (old == 0) & (new != 0))
    @sweep Metropolis(; temperature = T)
end

block(dims, blocks...) = (s = zeros(Int32, dims); foreach(((k, b),) -> s[b...] .= k, enumerate(blocks)); s)
# 4√λ_max of the covariance of cell `c`'s site coordinates (the inertia-tensor length)
function sib_length(σ, c)
    I = findall(==(c), σ)
    mx, my = mean(i[1] for i in I), mean(i[2] for i in I)
    sxx, syy = mean((i[1] - mx)^2 for i in I), mean((i[2] - my)^2 for i in I)
    sxy = mean((i[1] - mx) * (i[2] - my) for i in I)
    return 4 * sqrt((sxx + syy) / 2 + sqrt(((sxx - syy) / 2)^2 + sxy^2))
end

# published model => (sibling label, check); every check builds, self-checks and runs
const SIBLINGS = Dict(
    :GranerGlazier => ("hexagonal sorting", function ()
        σ = zeros(Int32, 30, 30); n = 0
        for i in 6:5:21, j in 6:5:21
            n += 1; σ[i:(i + 3), j:(j + 3)] .= n
        end
        p = PottsProblem(HexSorting(; name = :h), [ownership => σ, kind => [isodd(k) ? :dark : :light for k in 1:n]], (0, 40))
        @test selfcheck(p) < 1e-9
        H(u) = total_energy(p, u)
        @test H(solve(p, SequentialCPM(; proposal = Moore(1))).u[end]) < H(p.u0)
    end),
    :WortelAct => ("arithmetic-mean Act", function ()
        p = PottsProblem(ActArithmetic(; name = :a), [ownership => block((24, 24), (8:12, 8:12)), kind => [:cell]], (0, 30))
        @test selfcheck(p) < 1e-9
        u = solve(p, SequentialCPM()).u[end]
        @test any(>(0), u.site.act) && count(==(1), u.σ) > 0
    end),
    :MerksVasculogenesis => ("saturating chemotaxis", function ()
        cue = [0.05 * x for x in 1:40, y in 1:40]
        drift = map(1:4) do seed
            p = PottsProblem(SaturatingChemotaxis(; name = :s), [ownership => block((40, 40), (18:23, 18:23)),
                kind => [:cell], :c => copy(cue)], (0, 150); seed)
            seed == 1 && @test selfcheck(p) < 1e-9
            u = solve(p, SequentialCPM()).u[end]
            mean(i[1] for i in findall(==(1), u.σ)) - 20.5
        end
        @test mean(drift) > 3
    end),
    :Merks2006 => ("CC3D length constraint, hard connectivity, von Neumann copies", function ()
        σ = block((40, 40), (8:13, 8:13), (26:31, 8:13), (8:13, 26:31), (26:31, 26:31))
        len(λ_L, seed) = (p = PottsProblem(ElongatedCells(; name = :e), [ownership => σ, kind => fill(:cell, 4), :λ_L => λ_L],
                              (0, 300); seed);
                          seed == 1 && λ_L > 0 && @test(selfcheck(p) < 1e-9);
                          u = solve(p, SequentialCPM()).u[end];
                          mean(c -> sib_length(u.σ, c), 1:4))
        # seeds 1–3 at 300 MCS: 11.5–12.2 with λ_L = 5, 7.3–8.1 with λ_L = 0 (6.8 as squares)
        el, ro = mean(s -> len(5.0, s), 1:2), mean(s -> len(0.0, s), 1:2)
        @test el > 10 && el > ro + 2.5                        # cells stretch towards L = 16
    end),
    :Merks2008 => ("CC3D chemotaxis towards the medium only", function ()
        cue = [0.05 * x for x in 1:40, y in 1:40]
        drift(χ) = map(1:4) do seed
            p = PottsProblem(MediumOnlyChemotaxis(; name = :m), [ownership => block((40, 40), (18:22, 18:22)),
                kind => [:cell], :c => copy(cue), :χ => χ], (0, 150); seed)
            seed == 1 && χ > 0 && @test selfcheck(p) < 1e-9
            u = solve(p, SequentialCPM()).u[end]
            mean(i[1] for i in findall(==(1), u.σ)) - 20.0
        end
        @test mean(drift(300.0)) > 3 && abs(mean(drift(0.0))) < 2.5     # extensions alone carry the cell up the cue
    end),
    :AkeebInvasion => ("soft connectivity, leader-gated chemotaxis", function ()
        cue = [0.1 * y for x in 1:40, y in 1:30]
        σ = block((40, 30), (10:14, 5:9), (15:19, 5:9), (20:24, 5:9))
        p = PottsProblem(SoftConnectedLeaders(; name = :l), [ownership => σ, kind => [:leader, :follower, :follower],
            :cue => cue], (0, 60))
        @test selfcheck(p) < 1e-9
        u = solve(p, SequentialCPM(; proposal = VonNeumann(1))).u[end]
        @test split_cells(u.σ, (false, false)) == 0                     # the penalty keeps cells whole
        @test mean(i[2] for i in findall(==(1), u.σ)) > 7                # the leader climbs the cue
    end),
    :OpenVTGrowingMonolayer => ("major-axis division", function ()
        p = PottsProblem(MajorAxisGrowth(; name = :g), [ownership => block((40, 40), (18:21, 18:21)), kind => [:cell]], (0, 120);
            capacity = 64)
        @test selfcheck(p) < 1e-9
        sol = solve(p, SequentialCPM())
        @test sol.stats.lifecycle.divisions >= 2
    end),
    :SingleDivisionFixture => ("major-axis division", () -> SIBLINGS[:OpenVTGrowingMonolayer][2]()),
    :OpenVTReferenceMonolayer => ("von Neumann inhibition by the other kind, uniform thresholds per daughter", function ()
        σ = block((40, 40), (14:17, 14:17), (18:21, 14:17), (14:17, 18:21), (18:21, 18:21))
        p = PottsProblem(KindInhibitedGrowth(; name = :k), [ownership => σ, kind => [:A, :B, :B, :A]], (0, 150);
            capacity = 128, seed = 2)
        @test selfcheck(p) < 1e-9
        sol = solve(p, SequentialCPM(; proposal = Moore(1)); saveat = 1)
        @test sol.stats.lifecycle.divisions >= 4
        # the fold is exact: free = (medium or same-kind pairs) / pairs over von Neumann, from σ
        bad = 0
        for i in 2:length(sol.u)
            u, v = sol.u[i], sol.u[i - 1]
            count(>(0), u.cell.volume) == count(>(0), v.cell.volume) || continue    # quiet MCS only
            for c in findall(>(0), u.cell.volume)
                n = m = 0
                for I in findall(==(c), u.σ), o in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    J = Tuple(I) .+ o
                    all(1 .<= J .<= size(u.σ)) || continue
                    q = u.σ[J...]
                    q == c && continue
                    n += 1
                    m += q == 0 || u.cell.kind[q] == u.cell.kind[c]
                end
                bad += !isapprox(u.cell.free[c], m / n; atol = 1e-12)       # 1 - (n - m)/n vs m/n
            end
        end
        @test bad == 0
        θs = sol.u[end].cell.θ[sol.u[end].cell.volume .> 0]
        @test all(x -> 1.5 < x < 2.5, θs) && length(unique(θs)) == length(θs)      # one draw per daughter
    end),
    :OpenVTChain => ("compression released by a scheduled per-cell target", function ()
        σ = block((60, 4), [((1 + 4(c - 1)):(4c), 1:4) for c in 1:6]...)       # 6 cells of 16 sites from x = 1
        p = PottsProblem(ScheduledRelease(; name = :r), [ownership => σ, kind => fill(:cell, 6)], (0, 300); seed = 3)
        @test selfcheck(p) < 1e-9
        sol = solve(p, SequentialCPM(; proposal = Moore(1)); saveat = [20, 300], save_start = false)
        span(u) = (x = [c[1] for c in PottsModels.Analysis.centroids(u.σ)]; maximum(x) - minimum(x))
        @test sol.u[1].cell.V_target == fill(16.0, 6) && sol.u[2].cell.V_target == fill(32.0, 6)
        @test span(sol.u[1]) < 24 && span(sol.u[2]) > 32                  # the chain lengthens after the release
    end),
)

@testset "siblings from public primitives" begin
    models = filter(n -> (f = getfield(PottsModels, n); f isa Function && isuppercase(first(string(n)))), names(PottsModels))
    @test Set(models) == Set(keys(SIBLINGS))          # every published model has a sibling
    @testset "$m: $label" for (m, (label, check)) in SIBLINGS
        check()
    end
end

# P6.2a primitives outside their first model (Akeeb's seeding and code metrics): seed light
# cells into a dark tiling on the hexagonal sorting sibling with `InsertUntil`, run it, and
# read the result with the analysis functions on the hex lattice.
@testset "InsertUntil and Analysis on the hexagonal sorting sibling" begin
    sys = HexSorting(; name = :hs)
    l = overlay(Tiling((5, 5); region = (1:30, 1:15), kinds = [:dark]),
        InsertUntil(:light; into = [:dark], fraction = 1 // 3, seed = 11, misses = :count, region = (1:30, 1:20)))
    op, report = Base.CoreLogging.with_logger(() -> layout(l, sys; report = true), Base.CoreLogging.NullLogger())
    t = only(r for r in report if r.type === :InsertUntil)
    ks = last(op[2])
    @test count(==(:light), ks) == t.painted && t.painted + t.misses == t.counted
    @test 3 * t.counted >= 18 + t.counted                   # 18 dark tiles: at least 9 counted
    prob = PottsProblem(sys, op, (0, 20))
    @test selfcheck(prob) < 1e-9
    u = solve(prob, SequentialCPM()).u[end]
    σ = reshape(u.σ, prob.lattice.dims)
    g = PottsModels.Analysis.cell_graph(σ, prob.lattice; neighborhood = Hex(1))
    @test all(c -> all(d -> c in g[d], g[c]), eachindex(g))          # symmetric
    comps = PottsModels.Analysis.components(g, eachindex(g))
    @test sort!(reduce(vcat, comps)) == collect(eachindex(g))
    @test all(c -> PottsModels.Analysis.reachable(g, [first(c)]) == c, comps)
    com = PottsModels.Analysis.centroids(σ)
    @test all(c -> all(isfinite, com[c]), eachindex(g))
    # negative control: square Moore(1) adjacency sees the axial (1, 1) diagonal that hex does not
    @test PottsModels.Analysis.cell_graph(σ; neighborhood = Moore(1)) != g
end

# P6.1b (D-139) outside its first model (Graner–Glazier's sorting analysis): the boundary
# split by kind pair and the annealed copy on the hexagonal sorting sibling (Hex(2) contacts,
# a volume term besides the contacts).
@testset "boundary_lengths and anneal on the hexagonal sorting sibling" begin
    σ = zeros(Int32, 30, 30); n = 0
    for i in 6:5:21, j in 6:5:21
        n += 1; σ[i:(i + 3), j:(j + 3)] .= n
    end
    prob = PottsProblem(HexSorting(; name = :hb), [ownership => σ, kind => [isodd(k) ? :dark : :light for k in 1:n]], (0, 30); seed = 3)
    L = Potts.boundary_lengths(prob)
    @test Set(keys(L)) == Set([(:medium, :medium), (:medium, :dark), (:medium, :light), (:dark, :dark), (:dark, :light), (:light, :light)])
    @test L[(:medium, :medium)] == 0 && all(>(0), (L[k] for k in keys(L) if k != (:medium, :medium)))
    # Hex(2) bonds include second neighbours: more than the Hex(1) boundary of the same state
    @test sum(values(L)) > sum(values(Potts.boundary_lengths(prob; relation = Hex(1))))
    # the 4×4 blocks are far from the T = 0 minimum (V₀ = 20, rough Hex(2) edges): annealing lowers H
    a = Potts.anneal(prob; mcs = 8, seed = 1)
    @test total_energy(prob, a) < total_energy(prob)
    @test a.σ == Potts.anneal(prob; mcs = 8, seed = 1).σ && prob.u0.σ == σ
    # negative control: no MCS, no change
    @test total_energy(prob, Potts.anneal(prob; mcs = 0)) == total_energy(prob)
    # no drive, offset 0: H never rises along the annealing (the same seed extends the same
    # path; a killing copy pays λ·V₀² > 0 more in ΔH than in H, so it also lowers H)
    Hs = [total_energy(prob, Potts.anneal(prob; mcs = m, seed = 4)) for m in (0, 1, 2, 4, 8)]
    @test issorted(Hs; rev = true) && Hs[end] < Hs[1]
    # and from a state the run has moved (T = 4), H falls again
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
    @test total_energy(prob, Potts.anneal(prob, u; mcs = 8, seed = 2)) < total_energy(prob, u)
end

# P6.1a5 primitives outside their first model (the Graner–Glazier aggregate on a closed square
# lattice): a centroidal `Voronoi` of `RandomPoints` filling the periodic hexagonal sorting
# sibling, wrapping through its edges, with kinds cycled; it runs and its cells start compact.
@testset "Voronoi and RandomPoints on the periodic hexagonal sorting sibling" begin
    sys = HexSorting(; name = :hs)
    v = Voronoi(RandomPoints(45; seed = 3); lloyd = 20, kinds = [:dark, :light])
    op, report = layout(v, sys; report = true)
    row = only(report)
    @test (row.type, row.painted, row.dropped, row.clipped) == (:Voronoi, 45, 0, 0)
    σ0, ks = op[1].second, op[2].second
    @test all(>(0), σ0) && count(==(:dark), ks) == 23
    sd(a) = sqrt(sum(abs2, a .- mean(a)) / (length(a) - 1))
    areas = [count(==(c), σ0) for c in 1:45]
    @test sum(areas) == 900 && sd(areas) < 4                          # 20 sites each, SD ≈ 3 (seeds 1–5)
    # cells cross the periodic edges (the wrap is used), yet every cell is one Hex(1) piece
    @test any(c -> c in σ0[1, :] && c in σ0[30, :], 1:45)
    hex1 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
    nb(q, o) = CartesianIndex(mod1(q[1] + o[1], 30), mod1(q[2] + o[2], 30))
    function pieces(σ, c)                     # Hex(1) pieces of cell c, wrapping on both axes
        idx = findall(==(c), σ)
        seen, st = Set([idx[1]]), [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for o in hex1
                p = nb(q, o)
                σ[p] == c && !(p in seen) && (push!(seen, p); push!(st, p))
            end
        end
        return length(seen) == length(idx) ? 1 : 2
    end
    @test all(c -> pieces(σ0, c) == 1, 1:45)
    # control: a site of another cell, not touching cell 1, given to cell 1 splits it
    far = findfirst(x -> σ0[x] != 1 && all(o -> σ0[nb(x, o)] != 1, hex1), CartesianIndices(σ0))
    split = copy(σ0); split[far] = 1
    @test pieces(split, 1) == 2
    # negative control: without Lloyd the areas spread more
    σr = layout(remake(v; lloyd = 0), sys)[1].second
    ar = [count(==(c), σr) for c in 1:45]
    @test sd(ar) > 2sd(areas)                                         # SD ≈ 8.5–11 without
    prob = PottsProblem(sys, op, (0, 20))
    @test selfcheck(prob) < 1e-9
    u = solve(prob, SequentialCPM()).u[end]
    @test count(>(0), unique(u.σ)) >= 30          # the tessellation runs (a few small cells shrink away)
end

# P6.3c (D-141) primitives outside their first model (Merks 2008's TST seeding on a closed
# square lattice): Eden seeding with replacement (`shortfall = :allow`, its code consumer)
# and host-side Splits on the periodic hexagonal sorting sibling, growing under its own
# Hex(2) neighbourhood and wrapping through its edges.
struct SibSites <: AbstractLayout          # one cell of :dark on the given sites
    sites::Vector{NTuple{2, Int}}
end
function Potts.paint!(op::Potts.LayoutState, l::SibSites, lat)
    id = Potts.new_cell!(op, :dark)
    foreach(x -> Potts.assign!(op, x, id), l.sites)
    return nothing
end
@testset "Eden and Splits on the periodic hexagonal sorting sibling" begin
    sys = HexSorting(; name = :he)
    seeds = RandomPoints(60; replace = true, seed = 2)
    distinct = length(unique(Potts.points(seeds, sys)))
    @test distinct < 60                                               # this seed draws a coinciding pair
    denovo(sf) = Eden(seeds; rounds = 4, kinds = [:dark, :light], seed = 7, shortfall = sf)
    @test_throws ArgumentError layout(denovo(:error), sys)            # merged seeds are a shortfall
    op, report = layout(denovo(:allow), sys; report = true)
    row = only(report)
    @test (row.type, row.requested, row.painted, row.misses, row.dropped) == (:Eden, 60, distinct, 60 - distinct, 0)
    σ0, ks = op[1].second, op[2].second
    @test maximum(σ0) == distinct && ks == [isodd(c) ? :dark : :light for c in 1:distinct]
    # every cell is one piece under the growth neighbourhood (Hex(2), wrapping on both axes)
    hex2 = [Tuple(Int.(o)) for o in CorePotts.relation(Hex(2), Potts.core_lattice(Potts._layout_spec(sys))).offsets]
    nb(q, o) = CartesianIndex(mod1(q[1] + o[1], 30), mod1(q[2] + o[2], 30))
    function onepiece(σ, c, offs)
        idx = findall(==(c), σ)
        seen, st = Set([idx[1]]), [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for o in offs
                p = nb(q, o)
                σ[p] == c && !(p in seen) && (push!(seen, p); push!(st, p))
            end
        end
        return length(seen) == length(idx)
    end
    @test all(c -> onepiece(σ0, c, hex2), 1:distinct)
    # four rounds of Hex(2) growth from 50-odd seeds cover about half of the 900 sites
    @test 350 < count(>(0), σ0) < 900
    # a sprout: one blob through the corner of the periodic lattice, divided 3 times
    blob = Eden(Potts.Point(1.0, 1.0); rounds = 8, kinds = [:dark], seed = 3)
    nblob = count(>(0), layout(blob, sys)[1].second)
    sop, srep = layout(Splits(blob, 3; splits = :allow), sys; report = true)
    σs = sop[1].second
    @test (only(srep).requested, only(srep).painted) == (8, 8) && count(>(0), σs) == nblob
    @test any(c -> c in σs[1, :] && c in σs[30, :], 1:8) || any(c -> c in σs[:, 1] && c in σs[:, 30], 1:8)
    # the cut is translation-equivariant through the wrap: the blob's sites moved to the
    # centre divide into the moved cells. (The unwrap takes each site's image nearest the
    # cell's first site, so this holds while the blob spans less than half the lattice.)
    S = Tuple.(findall(>(0), layout(blob, sys)[1].second))
    moved = [(mod1(x[1] + 15, 30), mod1(x[2] + 15, 30)) for x in S]
    @test all(d -> maximum(getindex.(moved, d)) - minimum(getindex.(moved, d)) < 15, 1:2)
    cut(sites, target) = layout(Splits(SibSites(sites), 3; splits = :allow), target)[1].second
    @test circshift(cut(S, sys), (15, 15)) == cut(moved, sys)
    # negative control: on a closed lattice the corner pieces are cut in index space
    closed = Lattice((30, 30); geometry = Hexagonal(), boundary = Closed())
    @test circshift(cut(S, closed), (15, 15)) != cut(moved, closed)
    for u0 in (op, sop)
        prob = PottsProblem(sys, u0, (0, 10); seed = 1)
        @test selfcheck(prob) < 1e-9
        @test count(>(0), unique(solve(prob, SequentialCPM()).u[end].σ)) >= 1
    end
end
