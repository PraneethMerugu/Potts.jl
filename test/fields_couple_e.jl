# F4-E1 (research/field-compiler/f4/F4-ergonomics.md item 10). Uses the
# definitions of fields_couple.jl (CpPDE, CpRev, CpHost, cp_msg, cp_run, cp_same, cp_build_err).
#
# E1: a constant binding is refused whether Julia gives it as `false` or as `Num(false)`. In a
# vector that also holds a symbolic binding, `Potts.kind == :A` (Julia's `false`) is promoted to
# `Num(false)`; at the base 4ca38af7 the `e isa Bool` guard missed it and the input was false at
# every site (probe ~/lpwork/f4ergo/probe5.jl: 0 true sites). Negative control at 4ca38af7: the
# E1 testset fails, the mixed and the single `Num` bindings build ("built", ~/lpwork/f4E/nc-e1e2.log).

@testset "F4-E1: a constant symbolic binding is a constant (mixed vectors, one binding)" begin
    host = CpHost(; name = :m)
    vol = Potts.at(Potts.B.volume, Potts.B.owner)
    # the mixed vector: Julia promotes the `false` (the real reason of the bug)
    b = [CpPDE.endo => Potts.kind == :A, CpPDE.vol => vol]
    @test last(eltype(b).parameters) === Potts.Num
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = b))
    @test occursin("the input `endo` is bound to the constant `false`", e) &&
          occursin("Potts.kind == Potts.lookup(model, :A)", e) || (println(e); false)
    # either order, and a `Bool` and a numeric input mixed with a test
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.vol => vol, CpPDE.endo => Potts.kind == :A]))
    @test occursin("bound to the constant `false`", e) || (println(e); false)
    # one constant binding, given symbolic: the same refusal as the plain one
    for (sym, plain) in ((Potts.Num(false), false), (Potts.Num(true), true))
        es, ep = (cp_msg(() -> Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => v])) for v in (sym, plain))
        @test es == ep && occursin("a binding to a constant is the same at every site", es) || (println(es); false)
    end
    # a numeric input bound to a symbolic constant equals the plain constant (bitwise)
    ms = Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => Potts.Num(16.0)])
    mp = Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => 16.0])
    rs, rp = cp_run(ms, ExplicitEuler()), cp_run(mp, ExplicitEuler())
    @test cp_same(rs, rp) && maximum(rs.u[end].site.c) > 0.1
    # the route: a test that is not constant still binds (a mixed vector of symbolic tests)
    mr = Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == Potts.lookup(host, :A), CpPDE.vol => vol])
    @test count(Potts.field_inputs(PottsProblem(mr, cp_op(), (0, 1)))[:endo]) == 32
end
