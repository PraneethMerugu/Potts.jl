# D-139: `Potts.boundary_lengths` against an independent brute-force count over all site
# pairs, and `Potts.anneal`'s contract (T = 0 whatever the temperature, the run's own ΔH with
# drives and acceptance law, copy attempts only), each claim with a negative control. The
# frozen acceptance file (lib/PottsModels/test/acceptance/p6_1b_boundary_anneal.jl) has the
# hand-counted fixtures and the agreement with reproduction 09.

@testsetup module AnalysisSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Test, Potts

using Potts: CorePotts

using Random: Xoshiro


# ---------------------------------------------------------------------------------------
# boundary_lengths

# The oracle: every unordered pair of sites {x, y} (both in the domain) whose displacement
# y − x is an offset of the relation, up to whole periods on the periodic axes. It shares
# nothing with `shift`, `coordinates` or the forward-offset half of the implementation.
function an_boundary_oracle(σ, kinds, lat, r)
    names = (:medium, :A, :B)
    offs = Dict(Tuple(Int.(o)) => (r.weights === nothing ? 1 : Float64(r.weights[k])) for (k, o) in enumerate(r.offsets))
    L = Dict((names[a], names[b]) => 0.0 for a in 1:3 for b in a:3)
    sites = vec(collect(CartesianIndices(lat.dims)))
    indom(x) = lat.mask === nothing || lat.mask[x]
    slot(c) = c == 0 ? 1 : (kinds[c] === :A ? 2 : 3)
    for i in eachindex(sites), j in (i + 1):length(sites)
        x, y = sites[i], sites[j]
        (indom(x) && indom(y)) || continue
        a, b = σ[x], σ[y]
        a == b && continue
        cands = [lat.periodic[d] ? unique((y[d] - x[d], y[d] - x[d] - lat.dims[d], y[d] - x[d] + lat.dims[d])) : (y[d] - x[d],)
                 for d in 1:length(lat.dims)]
        hits = [offs[o] for o in Iterators.product(cands...) if haskey(offs, o)]
        isempty(hits) && continue
        @assert length(hits) == 1 || allequal(hits)        # o and −o both reach y only on a period-2 axis
        ka, kb = minmax(slot(a), slot(b))
        L[(names[ka], names[kb])] += first(hits)
    end
    return L
end


const AN_LATTICES = (
    sq_periodic = () -> Potts.lattice_spec((7, 6); boundary = Periodic(), neighborhood = Moore(1)),
    sq_disk = () -> Potts.lattice_spec(
        (9, 8); boundary = Closed(), neighborhood = Moore(1),
        domain = x -> (x[1] - 5)^2 + (x[2] - 4.5)^2 <= 12
    ),
    hex_periodic = () -> Potts.lattice_spec((6, 6); boundary = Periodic(), geometry = Hexagonal()),
    cube_mixed = () -> Potts.lattice_spec((5, 4, 4); boundary = (Periodic(), Closed(), Periodic()), neighborhood = Moore(1)),
)

@potts_model AnContact begin
    @structural_parameters begin
        lat = AN_LATTICES[:sq_periodic]
    end
    @kinds medium A B
    @parameters J[kind, kind] = [0.0 3.0 5.0; 3.0 7.0 11.0; 5.0 11.0 13.0]
    @lattice lat()
    @energy contacts => J[kind, neighbor_kind]
    @sweep Metropolis(; temperature = 4.0)
end


function an_random_problem(key, seed)
    sys = AnContact(; name = Symbol(:an_, key), lat = AN_LATTICES[key])
    lat = Potts.core_lattice(Potts.lattice(sys))
    rng = Xoshiro(seed)
    σ = Int32.(rand(rng, 0:5, lat.dims))
    lat.mask === nothing || (σ[.!lat.mask] .= 0)
    ncell = maximum(σ)
    σ[findfirst(σ .== 0)] == 0 || error("no medium")
    for c in 1:ncell                                   # every label present (labels 1:ncell)
        any(==(c), σ) || (σ[findfirst(i -> σ[i] == 0 && (lat.mask === nothing || lat.mask[i]), eachindex(σ))] = c)
    end
    kinds = [isodd(c) ? :A : :B for c in 1:ncell]
    return PottsProblem(sys, [ownership => σ, kind => kinds], (0, 3); seed), kinds
end


# ---------------------------------------------------------------------------------------
# anneal

# Two stripes on a periodic 8×8 lattice, cell 1 (A) on x = 1:4, cell 2 (B) on x = 5:8, contact
# J(A, B) = 1 only, Moore contacts and proposals. A copy across a flat interface turns 3
# heterotypic bonds of the target into 5: ΔH = +2; every other copy is between equal owners.
# So the stripes are a strict local minimum at T = 0, unless the drive `−μ` (every copy)
# or the acceptance offset brings ΔH − offset below 0.
@potts_model AnStripes begin
    @kinds medium A B
    @parameters begin
        μ = 0.0
        T = 5.0
        J[kind, kind] = [0.0 0.0 0.0; 0.0 0.0 1.0; 0.0 1.0 0.0]
    end
    @variables ticks(cell) = 0.0
    @lattice Lattice((8, 8); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy contacts => J[kind, neighbor_kind]
    @drive copy => -μ
    @after_mcs ticks ~ Pre(ticks) + 1
    @sweep Metropolis(; temperature = T)
end

@potts_model AnStripesOffset begin
    @kinds medium A B
    @parameters J[kind, kind] = [0.0 0.0 0.0; 0.0 0.0 1.0; 0.0 1.0 0.0]
    @lattice Lattice((8, 8); boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy contacts => J[kind, neighbor_kind]
    @sweep Barker(; temperature = 5.0, offset = 3.0)
end

const AN_STRIPES = Int32[x <= 4 ? 1 : 2 for x in 1:8, y in 1:8]

an_stripes(sys; kw...) = PottsProblem(sys, [ownership => copy(AN_STRIPES), kind => [:A, :B]], (0, 8); kw...)


# A cell at its division volume: the run divides it, the annealed copy does not.
@potts_model AnDividing begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        A₀ = 12.0
        T = 10.0
        J[kind, kind] = [0.0 10.0; 10.0 10.0]
    end
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - 2A₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @divide cells(cell) when = volume >= 2A₀, along = major_axis()
    @sweep Metropolis(; temperature = T)
end


# An energy reading a population fold (D-041): its snapshot `mean(volume for c in cells)` is
# refreshed before every MCS of a run, and of the annealed copy (the at-init phase).
@potts_model AnPopFold begin
    @kinds medium A
    @parameters begin
        T = 5.0
        λ = 1.0
    end
    @lattice Lattice((24, 24); boundary = Periodic())
    @relations proposal = Moore(1)
    @energy begin
        cells => λ * (volume - 3 * mean(volume for c in cells))^2
        contacts => 1.0
    end
    @sweep Metropolis(; temperature = T)
end


# A non-finite ΔH stops a run (retcode Failure); the annealed copy is an error, not a partial state.
@potts_model AnBlowup begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Periodic())
    @relations proposal = Moore(1)
    @energy cells => 1 / (volume - 9)^2
    @sweep Metropolis(; temperature = 5.0)
end
function an_throws(T, pats, f)
    err = try
        f(); nothing
    catch e
        e
    end
    @test err isa T
    return err
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "boundary_lengths against the all-pairs oracle" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "boundary_lengths against the all-pairs oracle" begin
        relations = Dict(:sq_periodic => (nothing, VonNeumann(2), Moore(2), Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))),
            :sq_disk => (nothing, EuclideanBall(2), Weighted(NeighborOrder(2), o -> 2.0 + abs(o[1]))),
            :hex_periodic => (nothing, Hex(2)),
            :cube_mixed => (nothing, VonNeumann(1), NeighborOrder(2)))
        for key in keys(AN_LATTICES), seed in 1:2, rel in relations[key]
            prob, kinds = an_random_problem(key, seed)
            lat = prob.lattice
            r = rel === nothing ? prob.contact : CorePotts.relation(rel, lat)
            # the initial state and a state the run has moved
            for u in (prob.u0, solve(prob, SequentialCPM(; proposal = Moore(1))).u[end])
                L = Potts.boundary_lengths(prob, u; relation = rel)
                want = an_boundary_oracle(u.ownership, kinds, lat, r)
                @test Set(keys(L)) == Set(keys(want))
                @test all(isapprox(L[k], want[k]; rtol = 1.0e-12) for k in keys(want))
                @test sum(values(want)) > 0                         # the fixture has boundaries
                r.weights === nothing && @test valtype(L) === Int
            end
            # negative control: one site given to the medium changes the counts, and both agree
            u = deepcopy(prob.u0)
            u.ownership[findfirst(!iszero, u.ownership)] = 0
            L1 = Potts.boundary_lengths(prob, u; relation = rel)
            @test L1 != Potts.boundary_lengths(prob; relation = rel)
            want1 = an_boundary_oracle(u.ownership, kinds, lat, r)
            @test all(isapprox(L1[k], want1[k]; rtol = 1.0e-12) for k in keys(want1))
        end
        # the energy identity on every lattice (contact energy only)
        J = Dict((:medium, :medium) => 0.0, (:medium, :A) => 3.0, (:medium, :B) => 5.0, (:A, :A) => 7.0, (:A, :B) => 11.0, (:B, :B) => 13.0)
        for key in keys(AN_LATTICES)
            prob, _ = an_random_problem(key, 9)
            @test sum(J[k] * v for (k, v) in Potts.boundary_lengths(prob)) ≈ total_energy(prob)
        end
    end
end

@testitem "boundary_lengths: relations and rejections" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "boundary_lengths: relations and rejections" begin
        prob, kinds = an_random_problem(:sq_periodic, 3)
        # a two-offset stencil counts the horizontal bonds only, once each
        h = Potts.boundary_lengths(prob; relation = Stencil([[1, 0], [-1, 0]]))
        @test h == an_boundary_oracle(prob.u0.ownership, kinds, prob.lattice, CorePotts.relation(Stencil([[1, 0], [-1, 0]]), prob.lattice))
        v = Potts.boundary_lengths(prob; relation = Stencil([[0, 1], [0, -1]]))
        @test Dict(k => h[k] + v[k] for k in keys(h)) == Potts.boundary_lengths(prob; relation = VonNeumann(1))
        # an asymmetric relation has no unordered bonds, and non-model problems are refused
        an_throws(
            ArgumentError, ["the relation is not symmetric", "pass a symmetric relation"],
            () -> Potts.boundary_lengths(prob; relation = Stencil([[1, 0]]))
        )
        an_throws(
            ArgumentError, ["the relation is not symmetric", "pass a symmetric relation"],
            () -> Potts.boundary_lengths(prob; relation = Weighted(Moore(1), o -> 1.0 + o[1]))
        )
        raw_f = CorePotts.CPMFunction(
            prob.f.delta_H; prob.f.commit!, prob.f.constraint,
            prob.f.temperature, prob.f.bias, prob.f.acceptance, prob.f.footprint,
            prob.f.fingerprint, sys = nothing
        )
        non_potts = remake(prob; f = raw_f)
        an_throws(
            ArgumentError, ["not a problem of a Potts model", "with `PottsProblem`"],
            () -> Potts.boundary_lengths(non_potts)
        )
        # the input is not modified
        σ0 = copy(prob.u0.ownership)
        Potts.boundary_lengths(prob)
        @test prob.u0.ownership == σ0
    end
end

@testitem "anneal: T = 0 with the run's ΔH, drives and acceptance law" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: T = 0 with the run's ΔH, drives and acceptance law" begin
        prob = an_stripes(AnStripes(; name = :an_s); seed = 4)
        for alg in (SequentialCPM(), CheckerboardCPM())
            # the stripes are a T = 0 local minimum: the annealed copy is the input
            @test Potts.anneal(prob, 10; seed = 1, alg).ownership == AN_STRIPES
            # negative control: the run itself (T = 5) roughens the interface
            @test solve(prob, alg).u[end].ownership != AN_STRIPES
            # the drive is part of ΔH: μ = 3 makes every interface copy downhill
            driven = remake(prob; p = [:μ => 3.0])
            @test Potts.anneal(driven, 2; seed = 1, alg).ownership != AN_STRIPES
            # oracle: the same copies as a run of the problem with T = 0 and the same seed (its
            # after-MCS update does not feed ΔH); negative control: the run at T = 5 differs
            for s in 1:3
                a = Potts.anneal(driven, 3; seed = s, alg)
                @test a.ownership == solve(remake(driven; p = [:T => 0.0], seed = s, tspan = (0, 3)), alg).u[end].ownership
                @test a.ownership != solve(remake(driven; seed = s, tspan = (0, 3)), alg).u[end].ownership
            end
        end
        # the model's acceptance law: offset 3 > ΔH = 2, so interface copies pass at T = 0 ...
        off = an_stripes(AnStripesOffset(; name = :an_o); seed = 4)
        @test Potts.anneal(off, 2; seed = 1).ownership != AN_STRIPES
        # ... and the algorithm's law overrides it as in a run (offset 0: none pass)
        @test Potts.anneal(off, 10; seed = 1, alg = SequentialCPM(; acceptance = Barker())).ownership == AN_STRIPES
        @test Potts.anneal(off, 2; seed = 1, alg = SequentialCPM(; acceptance = Metropolis(; offset = 3.0))).ownership != AN_STRIPES
    end
end

@testitem "anneal: copy attempts only" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: copy attempts only" begin
        prob = an_stripes(AnStripes(; name = :an_t); seed = 2)
        driven = remake(prob; p = [:μ => 3.0])
        a = Potts.anneal(driven, 5; seed = 1)
        @test a.ownership != AN_STRIPES                                  # copies ran ...
        @test all(iszero, a.cell.ticks)                          # ... the after-MCS update did not
        @test a.cell.volume == [count(==(c), a.ownership) for c in 1:2]  # the copy's own bookkeeping did
        @test all(==(8.0), solve(driven, SequentialCPM()).u[end].cell.ticks)   # negative control
        # a state with ticks set keeps them
        u = solve(prob, SequentialCPM()).u[end]
        @test Potts.anneal(prob, u, 3; seed = 1).cell.ticks == u.cell.ticks
    end
end

@testitem "anneal: no lifecycle events" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: no lifecycle events" begin
        σ = zeros(Int32, 20, 20)
        σ[8:13, 9:12] .= 1                                       # volume 24 = 2A₀
        prob = PottsProblem(AnDividing(; name = :an_d), [ownership => σ, kind => [:cell]], (0, 4); capacity = 8, seed = 1)
        sol = solve(prob, SequentialCPM())
        @test sol.stats.lifecycle.divisions >= 1                 # negative control
        a = Potts.anneal(prob, 4; seed = 1)
        @test maximum(a.ownership) == 1 && count(>(0), a.cell.volume) == 1
    end
end

@testitem "anneal: a copy, deterministic, seeded" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: a copy, deterministic, seeded" begin
        σ, k = Int32[x <= 4 ? 1 : 2 for x in 1:8, y in 1:8], [:A, :B]
        prob = an_stripes(AnStripes(; name = :an_c); seed = 7)
        driven = remake(prob; p = [:μ => 3.0])
        f, u0, p0 = driven.f, deepcopy(driven.u0), deepcopy(driven.p)
        for alg in (SequentialCPM(), CheckerboardCPM())
            a = Potts.anneal(driven, 3; seed = 5, alg)
            @test a.ownership == Potts.anneal(driven, 3; seed = 5, alg).ownership
            @test a.ownership != Potts.anneal(driven, 3; seed = 6, alg).ownership   # the seed is used
            @test driven.f === f && driven.u0.ownership == u0.ownership && driven.u0.cell.volume == u0.cell.volume && driven.p == p0
        end
        # the problem's own seed does not enter (only `seed`)
        @test Potts.anneal(driven, 3; seed = 5).ownership == Potts.anneal(remake(driven; seed = 99), 3; seed = 5).ownership
        z = Potts.anneal(driven, 0)
        @test z !== driven.u0 && z.ownership == σ && z.ownership !== driven.u0.ownership
        an_throws(
            ArgumentError, ["`mcs` must be non-negative", "pass `mcs >= 0`"],
            () -> Potts.anneal(driven, -1)
        )
        # an annealed state can be annealed again and measured
        @test valtype(Potts.boundary_lengths(driven, Potts.anneal(driven, z, 1))) === Int
    end
end

@testitem "anneal: derived refreshes run before every MCS" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: derived refreshes run before every MCS" begin
        σ = zeros(Int32, 24, 24); n = 0
        for i in 3:6:21, j in 3:6:21
            n += 1; σ[i:(i + 2), j:(j + 2)] .= n
        end
        prob = PottsProblem(AnPopFold(; name = :an_pf), [ownership => σ, kind => fill(:A, n)], (0, 6); seed = 1)
        # negative control: the same copy dynamics with the snapshot frozen at u's value (no
        # phases at all) is not the run's
        f = prob.f
        frozen = CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint,
            temperature = Potts._ZeroTemperature(f.temperature), f.bias, f.acceptance, f.footprint, f.fingerprint, f.sys)
        for alg in (SequentialCPM(), CheckerboardCPM())
            differs = 0
            for s in 1:3
                run0 = solve(remake(prob; p = [:T => 0.0], seed = s, tspan = (0, 6)), alg).u[end]
                @test Potts.anneal(prob, 6; seed = s, alg).ownership == run0.ownership
                stale = solve(remake(prob; f = frozen, seed = s, tspan = (0, 6)), alg; save_start = false).u[end]
                differs += stale.ownership != run0.ownership
            end
            @test differs >= 1
        end
    end
end

@testitem "anneal: a non-finite ΔH is an error" setup = [AnalysisSetup] tags = [:potts, :analysis] begin
    @testset "anneal: a non-finite ΔH is an error" begin
        σ = zeros(Int32, 16, 16)
        σ[5:7, 5:7] .= 1                     # volume 9, at the pole: every copy of the cell has ΔH = −Inf
        prob = PottsProblem(AnBlowup(; name = :an_b), [ownership => σ, kind => [:A]], (0, 5); seed = 1)
        @test Symbol(solve(prob, SequentialCPM()).retcode) === :Unstable         # as in the run
        for alg in (SequentialCPM(), CheckerboardCPM())
            an_throws(
                Potts.PottsCompileError, ["Unstable"],
                () -> Potts.anneal(prob, 5; seed = 1, alg)
            )
        end
        # negative control: away from volume 8 the same model anneals
        σ2 = zeros(Int32, 16, 16)
        σ2[3:6, 3:6] .= 1                                        # volume 16: T = 0 grows it, ΔH finite
        ok = PottsProblem(AnBlowup(; name = :an_b2), [ownership => σ2, kind => [:A]], (0, 5); seed = 1)
        @test Potts.anneal(ok, 2; seed = 1).cell.volume[1] > 16
        an_throws(
            ArgumentError, ["`seed` must be non-negative", "pass `seed >= 0`"],
            () -> Potts.anneal(ok, 1; seed = -1)
        )
    end
end
