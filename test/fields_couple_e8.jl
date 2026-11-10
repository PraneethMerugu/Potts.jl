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
