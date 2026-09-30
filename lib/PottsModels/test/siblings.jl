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

block(dims, blocks...) = (s = zeros(Int32, dims); foreach(((k, b),) -> s[b...] .= k, enumerate(blocks)); s)

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
    op, tallies = Base.CoreLogging.with_logger(() -> layout_tally(l, sys), Base.CoreLogging.NullLogger())
    t = only(tallies)
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
