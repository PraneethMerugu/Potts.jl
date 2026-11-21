# Round trip through the keyword constructor: every model `@potts_model` builds is rebuilt
# by `PottsSystem(; name, <the PottsPart fields>...)` from its own payload (`Potts.part`),
# and the test requires the same problem and the same run, step by step. Each model below
# uses a group of the macro's sections. This shows that the macro adds nothing outside the
# payload and that the keyword constructor takes every payload field. It does not show that
# a user can write each section by hand with public constructors (a separate test, not
# here). The system metadata of `@description` and `@metadata` lives in the inner system,
# not in the payload, so the round trip does not carry it and the test does not check it.

@testsetup module MacroParitySetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))
using Potts.ModelingToolkitBase: System as MPSystem

module MPPDE
    using ..FieldPDE
    @variables c(..)
    const C = c(t, x, y)
    relax() = pdesys([Dt(C) ~ 1.0 - C], [c(0, x, y) ~ 0.0], (12, 8), [C])
end

let t = Potts.t
    Potts.ModelingToolkitBase.@variables drug(t) = 0.0
    Potts.ModelingToolkitBase.@parameters dose = 0.0 clearance = 0.2
    global MP_PK = MPSystem([Potts.D(drug) ~ dose - clearance * drug], t; name = :pk)
end

# parameters (a scalar and a kind table), model and cell variables, ODE and algebraic
# equations, an update after the sweep, an observed quantity, the proposal relation, a
# connectivity constraint and copy updates
@potts_model MPCells begin
    @kinds medium A B
    @parameters begin
        r = 0.5
        J[kind, kind] = [0 8 8; 8 2 6; 8 6 2]
    end
    @variables begin
        m(model) = 1.0
        half(model) = 0.0
        g(cell) = 0.0
        seen(cell) = 0.0
        act(site) = 0.0
    end
    @lattice Lattice((12, 8); neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells => (volume - 16.0)^2
        contacts => J[kind, neighbor_kind]
        sites => 0.5 * act
    end
    @equations begin
        D(m) ~ -r * m
        half ~ m / 2
        D(g) ~ half - g
    end
    @after_mcs seen ~ g
    @on_copy act[target] ~ 1.0
    @observed twice ~ 2 * g
    @constraint connectivity(A, B; rule = Global(; window = 1))
    @sweep Metropolis(; temperature = 2.0)
end

# a structural parameter, a site variable, a drive, an update before the sweep, a division
# rule and a placed schedule
@potts_model MPSites begin
    @structural_parameters side = 20
    @kinds medium A
    @variables h(site) = 1.0
    @lattice Lattice((side, 20))
    @energy cells => (volume - 16.0)^2
    @drive copy => 1.0e9
    @before_mcs h ~ 2.0
    @divide cells(A) when = integral(h) > 20.0, along = (1.0, 0.0)
    @schedule lifecycle, sweep
    @sweep Metropolis(; temperature = 1.0)
end

# a relationship between cells with an edge variable and link and unlink rules
@potts_model MPLinks begin
    @kinds medium leader follower
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @variables age(edge) = 0.0
    @relationship bond(cell, cell) capacity = 8
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy contacts => J[kind, neighbor_kind]
    @link bond when = new_contact(a, b) && (kind[a] == leader), every = 2
    @unlink bond when = distance > 100.0
    @sweep Metropolis(; temperature = 10.0)
end

# an MTK component per model, read and driven by the model's equations
@potts_model MPComponent begin
    @kinds medium A
    @variables w(cell) = 1.0
    @components model pk = MP_PK
    @equations begin
        pk.dose ~ 0.1 * count(true for c in cells)
        D(w) ~ -0.1 * w + pk.drug
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# `@extend` and initialization equations, in the base and in the extension
@potts_model MPBase begin
    @kinds medium A
    @variables Vt(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations Vt ~ 2volume
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model MPExtended begin
    @extend Vt = base = MPBase()
    @variables v2(cell)
    @initialization_equations v2 ~ Vt + 1
end

# a field coupled with `@fields`
@potts_model MPFields begin
    @kinds medium A
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @fields MPPDE.relax()
    @sweep Metropolis(; temperature = 1.0)
end

# a conversion pass (cells of a cluster become a sibling kind)
@potts_model MPConvert begin
    @kinds medium cytoplasm lamellipodium
    @parameters J[kind, kind] = [0 16 16; 16 2 0; 16 0 2]
    @variables begin
        sub(site) = 0.0
        V_target(cell) = ifelse(kind == cytoplasm, 100.0, 0.0)
        tot(model) = 0.0
    end
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cytoplasm, lamellipodium) => (volume - V_target)^2
        contacts => J[kind, neighbor_kind]
    end
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.0
        p = ifelse(mcs == 1, 1.0, 0.0)
        V_target[to] += 0.37 * sub
        tot += sub
    end
    @sweep Metropolis(; temperature = 2.0)
end

# the model rebuilt by the keyword constructor from its payload
function mp_rebuild(sys)
    p = Potts.part(sys)
    return PottsSystem(;
        name = nameof(sys), (
            f => getfield(p, f)
                for f in fieldnames(Potts.PottsPart)
        )...
    )
end

function mp_two_cells()
    σ = zeros(Int32, 12, 8)
    σ[3:6, 3:6] .= 1
    σ[7:10, 3:6] .= 2
    return σ
end

# (model, operating point, time span, problem keywords)
function mp_cases()
    σ20 = zeros(Int32, 20, 20)
    σ20[6:9, 6:9] .= 1
    σ30 = zeros(Int32, 30, 30)
    σ30[5:10, 12:17] .= 1
    σ30[12:17, 12:17] .= 2
    σ24 = zeros(Int32, 24, 24)
    σ24[7:18, 7:18] .= 1
    sub = zeros(24, 24)
    sub[10:14, 10:14] .= 1.0
    one = [ownership => mp_two_cells(), kind => [:A, :A]]
    return [
        (
            MPCells(; name = :cells),
            [ownership => mp_two_cells(), kind => [:A, :B]], (0, 4), (;),
        ),
        (
            MPSites(; name = :sites), [ownership => σ20, kind => [:A]],
            (0, 3), (; capacity = 8),
        ),
        (
            MPLinks(; name = :links),
            [ownership => σ30, kind => [:leader, :follower]], (0, 4), (;),
        ),
        (MPComponent(; name = :component), one, (0, 4), (;)),
        (MPExtended(; name = :extended), one, (0, 2), (;)),
        (MPFields(; name = :fields), one, (0, 3), (; field_solver = ExplicitEuler())),
        (
            MPConvert(; name = :convert),
            [ownership => σ24, kind => [:cytoplasm], cluster => [1], :sub => sub],
            (0, 3), (; capacity = 8),
        ),
    ]
end

# every array a state holds (ownership, kinds, cell, site, model and edge stores), flattened
# in the state's own order, for an exact comparison of two runs
mp_leaves(x::AbstractArray{<:Number}) = Any[copy(x)]
mp_leaves(x::Number) = Any[x]
function mp_leaves(x::Union{NamedTuple, Tuple})
    return reduce(
        vcat, (mp_leaves(v) for v in values(x));
        init = Any[]
    )
end
function mp_leaves(x)
    return if isstructtype(typeof(x))
        reduce(
            vcat, (mp_leaves(getfield(x, i)) for i in 1:fieldcount(typeof(x)));
            init = Any[]
        )
    else
        Any[x]
    end
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "@potts_model models round-trip through PottsSystem(...)" setup = [
    MacroParitySetup,
] tags = [
    :potts, :symbolic,
] begin
    @testset "@potts_model models round-trip through PottsSystem(...)" begin
        for (sys, op, tspan, kw) in mp_cases()
            again = mp_rebuild(sys)
            @test again isa PottsSystem && nameof(again) === nameof(sys)
            a = PottsProblem(sys, op, tspan; seed = 5, kw...)
            b = PottsProblem(again, op, tspan; seed = 5, kw...)
            @test a.f.fingerprint == b.f.fingerprint
            sa = solve(a, SequentialCPM(); saveat = 1)
            sb = solve(b, SequentialCPM(); saveat = 1)
            @test sa.t == sb.t
            @test length(mp_leaves(sa.u[end])) > 2
            @test all(k -> isequal(mp_leaves(sa.u[k]), mp_leaves(sb.u[k])), eachindex(sa.u))
        end
        # the comparison sees a dropped section and a different run
        sys, op, tspan, _ = first(mp_cases())
        p = Potts.part(sys)
        fewer = PottsSystem(;
            name = nameof(sys),
            (f => getfield(p, f) for f in fieldnames(Potts.PottsPart) if f !== :updates)...
        )
        a = PottsProblem(sys, op, tspan; seed = 5)
        @test PottsProblem(fewer, op, tspan; seed = 5).f.fingerprint != a.f.fingerprint
        @test !isequal(
            mp_leaves(solve(a, SequentialCPM()).u[end]),
            mp_leaves(solve(remake(a; seed = 6), SequentialCPM()).u[end])
        )
    end
end
