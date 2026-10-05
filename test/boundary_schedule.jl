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
