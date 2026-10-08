# P6.3b (D-145): `@boundary` and `@schedule` beyond the frozen acceptance file: how they
# compose (`extend`), the errors of the less common forms, the canonical fingerprint and the
# phase tuples the compiler builds.
using Potts: CorePotts

@potts_model BSBase begin
    @kinds medium A wall[frozen]
    @parameters begin
        Dc = 0.2
        S = 1.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((12, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @boundary c begin
        x => (Dirichlet(S), NoFlux())
        sites(kind == wall) => Dirichlet(0.0)
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = 2.0)
end

# an extension keeps the base's boundary and schedule unless it gives its own
@potts_model BSKeep begin
    @extend Dc, S, c = base = BSBase()
    @kinds medium A wall[frozen]
end
@potts_model BSOwn begin
    @extend Dc, S, c = base = BSBase()
    @kinds medium A wall[frozen]
    @boundary c begin
        y => (NoFlux(), Dirichlet(0.5))
    end
    @schedule sweep, fields
end

bs_op() = (σ = zeros(Int32, 12, 10); σ[5:7, 4:6] .= 1; σ[10, :] .= 2; [ownership => σ, kind => [:A, :wall]])
bs_problem(sys; kw...) = PottsProblem(sys, bs_op(), (0, 2); field_solver = ExplicitEuler(substeps = 2), kw...)

@testset "@boundary/@schedule: extension, phases and display" begin
    keep, own = BSKeep(; name = :k), BSOwn(; name = :o)
    @test getfield(keep, :schedule) == [:fields, :sweep]
    @test [b.axis for b in getfield(keep, :boundaries)] == [1, 0]
    @test getfield(own, :schedule) == [:sweep, :fields]
    @test [b.axis for b in getfield(own, :boundaries)] == [2]                   # the field's block replaced
    # the schedule `fields, sweep`: the field step sits before the sweep, its clamp on it
    ph = bs_problem(BSBase(; name = :b)).f.phases
    k = findfirst(e -> e isa CorePotts.SweepPhase, ph.mcs)
    @test any(x -> x isa CorePotts.FieldStep && x.clamp !== nothing, ph.mcs[k - 1])
    @test any(x -> x isa CorePotts.FieldStep, ph.after_mcs)                     # by role, for inspection
    @test any(x -> x isa CorePotts.FieldClamp, ph.at_init)
    # the masked clamp holds on the initial state, wall sites at 0 after every MCS
    sol = solve(bs_problem(BSBase(; name = :b)), SequentialCPM(); saveat = 1)
    wall = bs_op()[1].second .== 2
    @test all(u -> all(==(0.0), Array(u.site.c)[wall]), sol.u)
    txt = sprint(show, MIME"text/plain"(), BSBase(; name = :b))
    @test occursin("boundary c x => (Dirichlet(S), NoFlux())", txt) && occursin("schedule fields, sweep", txt)
end

@potts_model BSOrderA begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 1.0 - c
    @schedule fields, before_mcs, sweep
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model BSOrderB begin                     # the same placed order, listed differently
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 1.0 - c
    @schedule fields, before_mcs, sweep, after_mcs, components
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model BSOrderC begin                     # the default relative order
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 1.0 - c
    @schedule sweep, fields, end_mcs
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model BSOrderNone begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 1.0 - c
    @sweep Metropolis(; temperature = 1.0)
end

@testset "@schedule: canonical fingerprints and placement" begin
    @test Potts._placed_schedule([:fields, :sweep]) ==
          [:before_mcs, :fields, :sweep, :after_mcs, :components, :operators, :lifecycle, :end_mcs]
    @test Potts._placed_schedule([:lifecycle, :fields]) ==
          [:before_mcs, :sweep, :after_mcs, :lifecycle, :fields, :components, :operators, :end_mcs]
    σ = zeros(Int32, 8, 8); σ[3:4, 3:4] .= 1
    fp(M) = PottsProblem(M(; name = :o), [ownership => σ, kind => [:A]], (0, 1); field_solver = ExplicitEuler()).f.fingerprint
    @test fp(BSOrderA) == fp(BSOrderB)                    # equal after canonicalization (D-145 ruling 9)
    @test fp(BSOrderC) == fp(BSOrderNone)                 # the default order keeps the fingerprint
    @test fp(BSOrderA) != fp(BSOrderNone)
    # no schedule: today's order, entry for entry
    p = PottsProblem(BSOrderNone(; name = :o), [ownership => σ, kind => [:A]], (0, 1); field_solver = ExplicitEuler()).f.phases
    @test p.mcs == (p.before_mcs, CorePotts.SweepPhase(), p.after_mcs, CorePotts.LifecyclePhase(), p.end_mcs)
end

bs_error(f) = try
    f(); nothing
catch e
    while e isa LoadError
        e = e.error
    end
    sprint(showerror, e)
end

# models whose errors surface at construction or compilation (each expands)
const BS_COMMON = quote
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
bs_model(name, sections...) = Core.eval(@__MODULE__, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(1, :bs), name,
    Expr(:block, BS_COMMON.args..., sections...)))
bs_model(:BSNoEq, :(@variables begin
    c(field) = 0.0
    u(field) = 0.0
end), :(@equations D(c) ~ 0.1 * Δ(c)), :(@boundary u begin
    x => (NoFlux(), NoFlux())
end))
bs_model(:BSVarValue, :(@variables c(field) = 0.0), :(@equations D(c) ~ 0.1 * Δ(c)), :(@boundary c begin
    x => (Dirichlet(c), NoFlux())
end))
bs_model(:BSTwice, :(@variables c(field) = 0.0), :(@equations D(c) ~ 0.1 * Δ(c)), :(@boundary c begin
    x => (NoFlux(), NoFlux())
    x => (Dirichlet(1.0), NoFlux())
end))
bs_model(:BSSched2, :(@schedule fields, sweep), :(@schedule sweep, fields))
@potts_model BSHex begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 8); boundary = Closed(), geometry = Hexagonal())
    @energy cells(A) => (volume - 4.0)^2
    @equations D(c) ~ 0.1 * Δ(c)
    @boundary c begin
        x => (Dirichlet(0.0), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "@boundary/@schedule: less common errors name the offender" begin
    @test occursin("Hexagonal", something(bs_error(() -> mtkcompile(BSHex(; name = :h))), ""))
    @test occursin("D(u)", something(bs_error(() -> mtkcompile(Base.invokelatest(BSNoEq; name = :n))), ""))
    @test occursin("reads `c`", something(bs_error(() -> Base.invokelatest(BSVarValue; name = :v)), ""))
    @test occursin("axis `x` is given twice", something(bs_error(() -> mtkcompile(Base.invokelatest(BSTwice; name = :t))), ""))
    @test occursin("given twice", something(bs_error(() -> Base.invokelatest(BSSched2; name = :s)), ""))
    @test occursin("`end_mcs` must be last", something(bs_error(() -> Potts._placed_schedule([:end_mcs, :fields])), ""))
end

# Integrals under a non-default order (D-145, review round 1): one rule on the placed order
# refreshes, after each σ-moving entry and each block write, what the later entries read.
@potts_model BSIntS1 begin                       # components after the sweep, the after block last
    @kinds medium A
    @variables begin
        y(cell) = 0.0
        h(site) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ integral(h)
    @after_mcs h ~ Pre(h)
    @schedule sweep, components, after_mcs
    @sweep Metropolis(; temperature = 20.0)
end
@potts_model BSIntS2 begin                       # the lifecycle before the sweep, after the before block
    @kinds medium A
    @variables h(site) = 1.0
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @drive copy => 1.0e9
    @before_mcs h ~ 2.0
    @divide cells(A) when = integral(h) > 20.0, along = (1.0, 0.0)
    @schedule lifecycle, sweep
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model BSIntS4 begin                       # the before block after a division
    @kinds medium A
    @variables begin
        h(site) = 1.0
        r(cell) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16.0)^2
    @drive copy => 1.0e9
    @before_mcs r ~ integral(h)
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @schedule lifecycle, before_mcs, sweep
    @sweep Metropolis(; temperature = 1.0)
end

@testset "@schedule: integrals are fresh for the entries that read them" begin
    σ = zeros(Int32, 20, 20); σ[6:9, 6:9] .= 1         # one 4×4 cell
    # S1: the components read integral(h) over the σ the sweep just left: Δy = Σ h over it
    hx = Float64[i for i in 1:20, j in 1:20]
    sol = solve(PottsProblem(BSIntS1(; name = :s), [ownership => σ, kind => [:A], :h => hx], (0, 6)), SequentialCPM(); saveat = 1)
    @test any(k -> sol.u[k].σ != sol.u[k + 1].σ, 1:6)
    @test all(k -> sol.u[k + 1].cell.y[1] - sol.u[k].cell.y[1] == sum(hx[sol.u[k + 1].σ .== 1]), 1:6)
    # S2: the before block sets h = 2, so the lifecycle reads integral(h) = 16·2 = 32 > 20 and
    # divides in MCS 0 (stale, 16·1 = 16 would wait a step); no copy is accepted after
    sol = solve(PottsProblem(BSIntS2(; name = :s), [ownership => σ, kind => [:A]], (0, 3); capacity = 8), SequentialCPM(); saveat = 1)
    @test [count(>(0), u.cell.volume) for u in sol.u[2:end]] == [2, 2, 2]
    # S4: the before block reads integral(h) = volume of each half (8 sites, h = 1), not the parent's 16
    sol = solve(PottsProblem(BSIntS4(; name = :s), [ownership => σ, kind => [:A]], (0, 2); capacity = 8), SequentialCPM(); saveat = 1)
    @test sol.u[2].cell.volume[1:2] == [8, 8]
    @test sol.u[2].cell.r[1:2] == [8.0, 8.0]
end

# Field clamps hold on a fresh initial state only: a checkpoint restore and `anneal` skip them.
@potts_model BSClampCK begin
    @kinds medium sink
    @parameters begin
        Dc = 0.2
        s = 0.05
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) + s
    @boundary c begin
        sites(kind == sink) => Dirichlet(0.0)
    end
    @schedule fields, sweep
    @sweep Metropolis(; temperature = 4.0)
end

@testset "@boundary: field clamps on fresh states only" begin
    σ = zeros(Int32, 16, 16); σ[7:10, 7:10] .= 1
    prob = PottsProblem(BSClampCK(; name = :k), [ownership => σ, kind => [:sink], :c => fill(0.1, 16, 16)], (0, 8);
        field_solver = ExplicitEuler(substeps = 2), seed = 5)
    @test all(==(0.0), prob.u0.site.c[σ .== 1])          # clamped at construction
    for alg in (SequentialCPM(), CheckerboardCPM())
        full = solve(prob, alg)
        integ = init(prob, alg; save_start = false, save_end = false)
        foreach(_ -> step!(integ), 1:4)
        sol = solve!(init(prob, alg; checkpoint = checkpoint(integ)))
        @test sol.u[end].σ == full.u[end].σ
        @test sol.u[end].site.c == full.u[end].site.c
    end
    # `anneal` runs the derived refreshes only: the field (not stepped) is left as given
    u = deepcopy(prob.u0); u.site.c .= 0.1
    @test Potts.anneal(prob, u; mcs = 2).site.c == u.site.c
end

# `Δ` of a field with faces sees them wherever it is lowered (here `@observed`)
@potts_model BSFaceObs begin
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((8, 4); boundary = (Closed(), Periodic()))
    @energy cells => 0.0 * volume
    @equations D(c) ~ 0.1 * Δ(c)
    @observed lap ~ Δ(c)
    @boundary c begin
        x => (Dirichlet(1.0), NoFlux())
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "@boundary: faces in Δ outside the field step" begin
    prob = PottsProblem(BSFaceObs(; name = :o), [ownership => zeros(Int32, 8, 4), kind => Symbol[], :c => zeros(8, 4)], (0, 0);
        field_solver = ExplicitEuler(substeps = 1))
    lap = solve(prob, SequentialCPM())[:lap][1]
    @test lap[1, :] == fill(2.0, 4)                      # the ghost 2·1 − 0 at the Dirichlet face
    @test all(iszero, lap[2:end, :])                     # interior and the zero-flux face
end

bs_model(:BSMaskSelf, :(@variables c(field) = 0.0), :(@equations D(c) ~ 0.1 * Δ(c)), :(@boundary c begin
    sites(c > 0.5) => Dirichlet(0.0)
end))
bs_model(:BSMaskLater, :(@variables begin
    c(field) = 0.0
    u(field) = 0.0
end), :(@equations begin
    D(c) ~ 0.1 * Δ(c)
    D(u) ~ 0.1 * Δ(u)
end), :(@boundary c begin
    sites(u > 0.5) => Dirichlet(0.0)
end))
bs_model(:BSMaskEarlier, :(@variables begin
    c(field) = 0.0
    u(field) = 0.0
end), :(@equations begin
    D(c) ~ 0.1 * Δ(c)
    D(u) ~ 0.1 * Δ(u)
end), :(@boundary u begin
    sites(c > 0.5) => Dirichlet(0.0)
end))
bs_model(:BSFaceNoLap, :(@variables c(field) = 0.0), :(@equations D(c) ~ 0.1 - 0.01 * c), :(@boundary c begin
    x => (Dirichlet(1.0), NoFlux())
end))

@testset "@boundary: masks and faces that cannot hold" begin
    @test occursin("reads `c`, the field it clamps", something(bs_error(() -> mtkcompile(Base.invokelatest(BSMaskSelf; name = :m))), ""))
    @test occursin("reads `u`, a field stepped with or after `c`", something(bs_error(() -> mtkcompile(Base.invokelatest(BSMaskLater; name = :m))), ""))
    @test bs_error(() -> mtkcompile(Base.invokelatest(BSMaskEarlier; name = :m))) === nothing
    @test occursin("has no `Δ(c)`", something(bs_error(() -> mtkcompile(Base.invokelatest(BSFaceNoLap; name = :f))), ""))
end
