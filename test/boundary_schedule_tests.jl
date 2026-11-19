# P6.3b (D-145): `@schedule` beyond the frozen acceptance file: how it composes (`extend`), the
# errors of the less common forms, the canonical fingerprint and the phase tuples the compiler
# builds. The field conditions (front end A's `@boundary` until F4-B6) are a PDESystem's.

@testsetup module BoundaryScheduleSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts: CorePotts


# the fields of the `@schedule` and mask models, coupled with `@fields` (F4-B4t, F4-B6)
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module BsPDE
    using ..FieldPDE
    @variables c(..) u(..) sink(..)::Bool [input = true] wall(..)::Bool [input = true]
    const X = (t, x, y)
    const C, U = c(X...), u(X...)
    # `D(c) ~ Dc Δc`: c = S on the face x = 0, no flux on x = 12, 0 on the wall's sites
    base() = (
        @parameters Dc = 0.2 S = 1.0;
        pdesys(
            [Dt(C) ~ Dc * laplacian(C)], [
                c(0, x, y) ~ 0.0, c(t, 0, y) ~ S, Differential(x)(c(t, 12, y)) ~ 0.0,
                C ~ masked(wall(X...), 0.0),
            ], (12, 10), [C, wall(X...)], [Dc, S]
        )
    )
    relax() = pdesys([Dt(C) ~ 1.0 - C], [c(0, x, y) ~ 0.0], (8, 8), [C])
    clamp_ck() = (
        @parameters Dc = 0.2 s = 0.05;
        pdesys([Dt(C) ~ Dc * laplacian(C) + s], [c(0, x, y) ~ 0.0, C ~ masked(sink(X...), 0.0)], (16, 16), [C, sink(X...)], [Dc, s])
    )
    face_obs() = pdesys([Dt(C) ~ 0.1 * laplacian(C)], [c(0, x, y) ~ 0.0, c(t, 0, y) ~ 1.0], (8, 4), [C])
    mask_self() = pdesys([Dt(C) ~ 0.1 * laplacian(C)], [c(0, x, y) ~ 0.0, C ~ masked(C > 0.5, 0.0)], (8, 8), [C])
    two(mask) = pdesys([Dt(C) ~ 0.1 * laplacian(C), Dt(U) ~ 0.1 * laplacian(U)], [c(0, x, y) ~ 0.0, u(0, x, y) ~ 0.0, mask], (8, 8), [C, U])
    mask_later() = two(C ~ masked(U > 0.5, 0.0))
    mask_earlier() = two(U ~ masked(C > 0.5, 0.0))
end


@potts_model BSBase begin
    @kinds medium A wall[frozen]
    @lattice Lattice((12, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells(A) => (volume - 9.0)^2
    @fields c = BsPDE.base() (BsPDE.wall => kind == wall)
    @schedule fields, sweep
    @sweep Metropolis(; temperature = 2.0)
end


# an extension keeps the base's fields and schedule unless it gives its own schedule
@potts_model BSKeep begin
    @extend c = base = BSBase()
    @kinds medium A wall[frozen]
end

@potts_model BSOwn begin
    @extend c = base = BSBase()
    @kinds medium A wall[frozen]
    @schedule sweep, fields
end


bs_op() = (σ = zeros(Int32, 12, 10); σ[5:7, 4:6] .= 1; σ[10, :] .= 2; [ownership => σ, kind => [:A, :wall]])

bs_problem(sys; kw...) = PottsProblem(sys, bs_op(), (0, 2); field_solver = ExplicitEuler(substeps = 2), kw...)


@potts_model BSOrder begin
    @structural_parameters order = :none
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields BsPDE.relax()
    if order === :a
        @schedule fields, before_mcs, sweep
    elseif order === :b
        @schedule fields, before_mcs, sweep, after_mcs, components
    elseif order === :c
        @schedule sweep, fields, end_mcs
    end
    @sweep Metropolis(; temperature = 1.0)
end


bs_error(f) = try
    f(); nothing
catch e
    while e isa LoadError
        e = e.error
    end
    sprint(showerror, e)
end


@potts_model BSSched2 begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @schedule fields, sweep
    @schedule sweep, fields
    @sweep Metropolis(; temperature = 1.0)
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


# Field clamps hold on a fresh initial state only: a checkpoint restore and `anneal` skip them.
@potts_model BSClampCK begin
    @kinds medium sink
    @lattice Lattice((16, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @fields BsPDE.clamp_ck() (BsPDE.sink => kind == sink)
    @schedule fields, sweep
    @sweep Metropolis(; temperature = 4.0)
end


# `laplacian` is lowered by the field compiler in field equations only (cutover C8); a model body
# reaches it qualified (the bare name points to `using Potts.Fields`, F4-B6)
@potts_model BSFaceObs begin
    @kinds medium A
    @lattice Lattice((8, 4); boundary = (Closed(), Periodic()))
    @energy cells => 0.0 * volume
    @fields c = BsPDE.face_obs()
    @observed lap ~ Potts.LatticePDE.laplacian(c)
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model BSMask begin
    @structural_parameters mask_case = :self
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if mask_case === :self
        @fields BsPDE.mask_self()
    elseif mask_case === :later
        @fields BsPDE.mask_later()
    else
        @fields BsPDE.mask_earlier()
    end
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "@schedule: extension, phases and display" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "@schedule: extension, phases and display" begin
        keep, own = BSKeep(; name = :k), BSOwn(; name = :o)
        @test Potts._p(keep, :schedule) == [:fields, :sweep]
        @test Potts._p(own, :schedule) == [:sweep, :fields]
        @test length(Potts._p(keep, :bcs)) == length(Potts._p(own, :bcs)) == length(Potts._p(BSBase(; name = :b), :bcs)) > 0
        # the schedule `fields, sweep`: the field step sits before the sweep, its clamp on it
        ph = bs_problem(BSBase(; name = :b)).f.phases
        k = findfirst(e -> e isa CorePotts.SweepPhase, ph.mcs)
        @test any(x -> x isa CorePotts.FieldPhase && !x.init && !isempty(x.masks.launches), ph.mcs[k - 1])
        @test any(x -> x isa CorePotts.FieldPhase, ph.after_mcs)                    # by role, for inspection
        @test any(x -> x isa CorePotts.FieldPhase && x.init, ph.at_init)            # the clamp of a fresh state
        # the masked clamp holds on the initial state, wall sites at 0 after every MCS
        sol = solve(bs_problem(BSBase(; name = :b)), SequentialCPM(); saveat = 1)
        wall = bs_op()[1].second .== 2
        @test all(u -> all(==(0.0), Array(u.site.c)[wall]), sol.u)
        # (and the face: c = S = 1 at x = 0, the column next to it below 1 and above 0)
        c = Array(sol.u[end].site.c)
        @test 0 < c[1, 1] < 1.0
        txt = sprint(show, MIME"text/plain"(), BSBase(; name = :b))
        @test occursin("schedule fields, sweep", txt)
    end
end

@testitem "@schedule: canonical fingerprints and placement" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "@schedule: canonical fingerprints and placement" begin
        @test Potts._placed_schedule([:fields, :sweep]) ==
            [:before_mcs, :fields, :sweep, :after_mcs, :components, :operators, :lifecycle, :end_mcs]
        @test Potts._placed_schedule([:lifecycle, :fields]) ==
            [:before_mcs, :sweep, :after_mcs, :lifecycle, :fields, :components, :operators, :end_mcs]
        σ = zeros(Int32, 8, 8); σ[3:4, 3:4] .= 1
        fp(order) = PottsProblem(BSOrder(; name = :o, order), [ownership => σ, kind => [:A]], (0, 1); field_solver = ExplicitEuler()).f.fingerprint
        @test fp(:a) == fp(:b)                                # equal after canonicalization (D-145 ruling 9)
        @test fp(:c) == fp(:none)                             # the default order keeps the fingerprint
        @test fp(:a) != fp(:none)
        # no schedule: today's order, entry for entry
        p = PottsProblem(BSOrder(; name = :o, order = :none), [ownership => σ, kind => [:A]], (0, 1); field_solver = ExplicitEuler()).f.phases
        @test p.mcs == (p.before_mcs, CorePotts.SweepPhase(), p.after_mcs, CorePotts.LifecyclePhase(), p.end_mcs)
    end
end

@testitem "@schedule: less common errors name the offender" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "@schedule: less common errors name the offender" begin
        @test_throws ArgumentError BSSched2(; name = :s)
        @test_throws ArgumentError Potts._placed_schedule([:end_mcs, :fields])
    end
end

@testitem "@schedule: integrals are fresh for the entries that read them" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "@schedule: integrals are fresh for the entries that read them" begin
        σ = zeros(Int32, 20, 20); σ[6:9, 6:9] .= 1         # one 4×4 cell
        # S1: the components read integral(h) over the σ the sweep just left: Δy = Σ h over it
        hx = Float64[i for i in 1:20, j in 1:20]
        sol = solve(PottsProblem(BSIntS1(; name = :s), [ownership => σ, kind => [:A], :h => hx], (0, 6)), SequentialCPM(); saveat = 1)
        @test any(k -> sol.u[k].ownership != sol.u[k + 1].ownership, 1:6)
        @test all(k -> sol.u[k + 1].cell.y[1] - sol.u[k].cell.y[1] == sum(hx[sol.u[k + 1].ownership .== 1]), 1:6)
        # S2: the before block sets h = 2, so the lifecycle reads integral(h) = 16·2 = 32 > 20 and
        # divides in MCS 0 (stale, 16·1 = 16 would wait a step); no copy is accepted after
        sol = solve(PottsProblem(BSIntS2(; name = :s), [ownership => σ, kind => [:A]], (0, 3); capacity = 8), SequentialCPM(); saveat = 1)
        @test [count(>(0), u.cell.volume) for u in sol.u[2:end]] == [2, 2, 2]
        # S4: the before block reads integral(h) = volume of each half (8 sites, h = 1), not the parent's 16
        sol = solve(PottsProblem(BSIntS4(; name = :s), [ownership => σ, kind => [:A]], (0, 2); capacity = 8), SequentialCPM(); saveat = 1)
        @test sol.u[2].cell.volume[1:2] == [8, 8]
        @test sol.u[2].cell.r[1:2] == [8.0, 8.0]
    end
end

@testitem "masked conditions: field clamps on fresh states only" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "masked conditions: field clamps on fresh states only" begin
        σ = zeros(Int32, 16, 16); σ[7:10, 7:10] .= 1
        prob = PottsProblem(
            BSClampCK(; name = :k), [ownership => σ, kind => [:sink], :c => fill(0.1, 16, 16)], (0, 8);
            field_solver = ExplicitEuler(substeps = 2), seed = 5
        )
        @test all(==(0.0), prob.u0.site.c[σ .== 1])          # clamped at construction
        for alg in (SequentialCPM(), CheckerboardCPM())
            full = solve(prob, alg)
            integ = init(prob, alg; save_start = false, save_end = false)
            foreach(_ -> step!(integ), 1:4)
            sol = solve!(init(prob, alg; checkpoint = checkpoint(integ)))
            @test sol.u[end].ownership == full.u[end].ownership
            @test sol.u[end].site.c == full.u[end].site.c
        end
        # `anneal` runs the derived refreshes only: the field (not stepped) is left as given
        u = deepcopy(prob.u0); u.site.c .= 0.1
        @test Potts.anneal(prob, u, 2).site.c == u.site.c
    end
end

@testitem "Δ outside a field equation is refused" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "Δ outside a field equation is refused" begin
        prob = PottsProblem(
            BSFaceObs(; name = :o), [ownership => zeros(Int32, 8, 4), kind => Symbol[], :c => zeros(8, 4)], (0, 0);
            field_solver = ExplicitEuler(substeps = 1)
        )
        err = bs_error(() -> solve(prob, SequentialCPM())[:lap])
        @test occursin("laplacian", something(err, ""))
    end
end

@testitem "masks and faces that cannot hold" setup = [BoundaryScheduleSetup] tags = [:potts, :boundary_schedule] begin
    @testset "masks and faces that cannot hold" begin
        # a mask that reads the field it clamps is accepted (F2-11 review (a); before: refused)
        @test bs_error(() -> mtkcompile(BSMask(; name = :m, mask_case = :self))) === nothing
        # a mask that reads a field stepped after its own reads it at the window start (round 2 of
        # F2 batch 4; before: refused "a field stepped with or after `c`")
        @test bs_error(() -> mtkcompile(BSMask(; name = :m, mask_case = :later))) === nothing
        @test bs_error(() -> mtkcompile(BSMask(; name = :m, mask_case = :earlier))) === nothing
    end
end
