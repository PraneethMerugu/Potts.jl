# F4-E8 to F4-E10 (gaps found by the Merks and frozen ports, HANDOFF 2026-11-10 "F4-B4m + F4-B5
# DONE"). Uses the definitions of fields_couple.jl (cp_run, cp_same, cp_op, cp_build_err, cp_msg).
#
# E8: `@fields c, s = pdesys (…)` binds a PDESystem parameter by name for the statements after
# the line, as it binds fields. Oracle: a drive that reads the PDESystem's `s`, bitwise against
# the workaround (a model parameter `s` bound to an input of the PDESystem). Negative control at
# the E7 commit: "`s` is not a field of the PDESystem" (~/lpwork/f4E/nc-e8e10.log).

module CeS
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2 s = 0.5 kd = 0.1
@variables c(..) = 0.0 a(..)::Bool [input = true] sv(..) [input = true]
const C = c(t, x, y)
named() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + s * a(t, x, y) - kd * C]; name = :fields)
# the workaround: `s` an input, bound to a model parameter
work() = pdesystem([Differential(t)(C) ~ Dc * Δ(C) + sv(t, x, y) * a(t, x, y) - kd * C]; name = :fields)
end

@potts_model CeNamed begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c, s = CeS.named() (a => kind == A)
    @drive copy => -400.0 * s * (c[target] - c[source])
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CeWork begin
    @kinds medium A
    @parameters s = 0.5
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CeS.work() (a => kind == A, sv => s)
    @drive copy => -400.0 * s * (c[target] - c[source])
    @sweep Metropolis(; temperature = 4.0)
end

@testset "F4-E8: a later statement reads a @fields PDESystem parameter by name" begin
    for fs in (ExplicitEuler(), BackwardEuler())
        n, w = cp_run(CeNamed(; name = :m), fs), cp_run(CeWork(; name = :m), fs)
        @test cp_same(n, w) && maximum(n.u[end].site.c) > 0.1
        # the keyword sets the one parameter the field and the drive read
        n8, w8 = cp_run(CeNamed(; name = :m, s = 0.8), fs), cp_run(CeWork(; name = :m, s = 0.8), fs)
        @test cp_same(n8, w8) && n8.u[end].site.c != n.u[end].site.c
    end
    @test count(==(:s), [Potts.info(p).name for p in Potts.parameters(CeNamed(; name = :m))]) == 1
    # a name that is neither a field nor a parameter: the refusal lists both
    e = cp_build_err(quote
        @potts_model CeNoName begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @fields c, q = CeS.named() (a => kind == A)
            @sweep Metropolis(; temperature = 4.0)
        end
        CeNoName(; name = :m)
    end)
    @test occursin("`q` is not a field of the PDESystem `fields`; its fields are `c`", e) &&
          occursin("its parameters (a name may be one too) ", e) && occursin("`s`", e) || (println(e); false)
end

# E9: a `::Bool` input takes any truth-valued expression: a comparison, `ismember`, `!`, `&`,
# `|`, and an `any`/`all` fold over a relation, whose symbolic type is not `Bool`. A numeric
# expression is still refused. Oracles: the input against the hand-computed sites, and the
# field bitwise against the same term in `@equations`. Negative control at the E8 commit: "is
# not a truth value" for the `any` binding (~/lpwork/f4E/nc-e8e10.log).
@potts_model CeAny begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = CeS.named() (a => any(kind[n] == A for n in VonNeumann(1)(site)))
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model CeAnyRef begin
    @kinds medium A
    @parameters begin
        Dc = 0.2
        s = 0.5
        kd = 0.1
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c) + s * any(kind[n] == A for n in VonNeumann(1)(site)) - kd * c
    @sweep Metropolis(; temperature = 4.0)
end
@testset "F4-E9: a Bool input takes a truth-valued expression (any over a relation)" begin
    op = cp_op()
    σ = first(op).second
    nb = [any(1 <= i + di <= size(σ, 1) && 1 <= j + dj <= size(σ, 2) && σ[i + di, j + dj] != 0
              for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))) for i in axes(σ, 1), j in axes(σ, 2)]
    fi = Potts.field_inputs(PottsProblem(CeAny(; name = :m), op, (0, 1)))[:a]
    @test fi == nb && count(nb) > 32                                         # cells' edges and their medium rims
    @test cp_same(cp_run(CeAny(; name = :m), ExplicitEuler()), cp_run(CeAnyRef(; name = :m), ExplicitEuler()))
    host = CpHost(; name = :m)
    k, vol = Potts.kind, Potts.at(Potts.B.volume, Potts.B.owner)
    # the other truth-valued forms couple; a numeric one is refused
    for b in ((k == 1) & (vol > 3.0), (k == 1) | (k == 0), !(k == 1), Potts.LatticePDE.ismember(k, (0, 1)))
        @test Potts.couple(host, CeS.named(); inputs = [CeS.a => b]) isa Potts.PottsSystem
    end
    for b in (vol, k, vol + 1.0)
        e = cp_msg(() -> Potts.couple(host, CeS.named(); inputs = [CeS.a => b]))
        @test occursin("the input `a` is a `Bool`", e) && occursin("is not a truth value", e) || (println(e); false)
    end
    e = cp_build_err(quote
        @potts_model CeSum begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @fields c = CeS.named() (a => sum(volume[n] for n in VonNeumann(1)(site)))
            @sweep Metropolis(; temperature = 4.0)
        end
        CeSum(; name = :m)
    end)
    @test occursin("is not a truth value", e) || (println(e); false)
end

# E10: a refusal of a condition that a PDESystem brought names the PDESystem and the condition,
# not `@bcs` (a model's own `@bcs` keeps its wording). Negative control at the E9 commit: the
# messages start "@bcs:" and end "in @bcs …" (~/lpwork/f4E/nc-e8e10.log).
module CeB
using Potts: Potts
using Potts.Fields
@parameters Dc = 0.2
@variables c(..) = 0.0
const C = c(t, x, y)
face() = pdesystem([Differential(t)(C) ~ Dc * Δ(C)], [c(t, 0, y) ~ 1.0]; name = :faced)
end
@potts_model CePeriodic begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    @fields CeB.face()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CePeriodicHost begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CePeriodicBcs begin
    @kinds medium A
    @parameters Dc = 0.2
    @variables c(field) = 0.0
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy cells => (volume - 16.0)^2
    @equations D(c) ~ Dc * Δ(c)
    @bcs c(t, 0, y) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F4-E10: a PDESystem's condition is named in its refusal" begin
    op = [ownership => zeros(Int32, 12, 12), kind => Symbol[]]
    for m in (CePeriodic(; name = :m), Potts.couple(CePeriodicHost(; name = :m), CeB.face()))
        e = cp_msg(() -> PottsProblem(m, op, (0, 1)))
        @test startswith(e, "ArgumentError: the PDESystem `faced`: the condition `c(t, 0, y) ~ 1.0` sets a face of axis `x`, which the lattice " *
                            "makes periodic") && occursin("in the condition `c(t, 0, y) ~ 1.0` of the PDESystem `faced`", e) &&
              !occursin("@bcs", e) || (println(e); false)
    end
    # a model's own `@bcs` keeps its wording
    e = cp_msg(() -> PottsProblem(CePeriodicBcs(; name = :m), op, (0, 1)))
    @test startswith(e, "ArgumentError: @bcs: the condition `c(t, 0, y) ~ 1.0` sets a face") && occursin("in @bcs", e) || (println(e); false)
end
