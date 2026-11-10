# F4-E1, F4-E2 (research/field-compiler/f4/F4-ergonomics.md items 10 and 8). Uses the
# definitions of fields_couple.jl (CpPDE, CpRev, CpHost, cp_msg, cp_run, cp_same, cp_build_err).
#
# E1: a constant binding is refused whether Julia gives it as `false` or as `Num(false)`. In a
# vector that also holds a symbolic binding, `Potts.kind == :A` (Julia's `false`) is promoted to
# `Num(false)`; at the base 4ca38af7 the `e isa Bool` guard missed it and the input was false at
# every site (probe ~/lpwork/f4ergo/probe5.jl: 0 true sites). Negative control at 4ca38af7: the
# E1 testset fails, the mixed and the single `Num` bindings build ("built", ~/lpwork/f4E/nc-e1e2.log).
#
# E2: a bare-symbol key of an `@fields` binding names an input of the PDESystem first, and its
# value in the constructor only when no input has that name, so `endo => kind == endo` works in
# a model with a kind `endo`. Negative control at 4ca38af7: "`1` is not a dependent variable"
# (the kind number), and a key naming nothing is an `UndefVarError` (~/lpwork/f4E/nc-e1e2.log).

@testset "F4-E1: a constant symbolic binding is a constant (mixed vectors, one binding)" begin
    host = CpHost(; name = :m)
    vol = Potts.at(Potts.B.volume, Potts.B.owner)
    # the mixed vector: Julia promotes the `false` (the real reason of the bug)
    b = [CpPDE.endo => Potts.kind == :A, CpPDE.vol => vol]
    @test last(eltype(b).parameters) === Potts.Num
    e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = b))
    @test occursin("the input `endo` is bound to the constant `false`", e) &&
          occursin("Potts.is_kind(model, :A)", e) || (println(e); false)
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

# a model whose kind has the name of the PDESystem's input; and a global that holds an input
# under another name (the value fallback)
@potts_model CeKindNamed begin
    @kinds medium endo
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(endo) => (volume - 16.0)^2
    @fields CpPDE.sys2() (endo => kind == endo)
    @sweep Metropolis(; temperature = 4.0)
end
const CE_ALIAS = CpPDE.endo
@potts_model CeAlias begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields CpPDE.sys2() (CE_ALIAS => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

@testset "F4-E2: a bare key names an input first, its value second" begin
    ce_op(k) = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [k, k]])
    ref = cp_run(CpFields2(; name = :m), ExplicitEuler())
    kn = cp_run(CeKindNamed(; name = :m), ExplicitEuler(); op = ce_op(:endo))
    @test cp_same(kn, ref) && maximum(ref.u[end].site.c) > 0.1                  # bitwise, kind `endo` ≡ kind `A`
    @test count(Potts.field_inputs(PottsProblem(CeKindNamed(; name = :m), ce_op(:endo), (0, 1)))[:endo]) == 32
    @test cp_same(cp_run(CeAlias(; name = :m), ExplicitEuler()), ref)            # the value of a name that is no input
    # a key that names neither an input nor a value: the refusal names the inputs
    e = cp_build_err(quote
        @potts_model CeNeither begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells(A) => (volume - 16.0)^2
            @fields CpPDE.sys2() (ce_nothing_here => kind == A)
            @sweep Metropolis(; temperature = 4.0)
        end
        CeNeither(; name = :m)
    end)
    @test occursin("`ce_nothing_here` is not a dependent variable of the PDESystem `fields`", e) && occursin("`endo`", e) ||
          (println(e); false)
    # a key whose value is no input (a kind number) keeps the existing refusal
    e = cp_build_err(quote
        @potts_model CeKindKey begin
            @kinds medium A
            @lattice Lattice((24, 20); boundary = Closed())
            @energy cells(A) => (volume - 16.0)^2
            @fields CpPDE.sys2() (A => kind == A)
            @sweep Metropolis(; temperature = 4.0)
        end
        CeKindKey(; name = :m)
    end)
    @test occursin("`1` is not a dependent variable", e) || (println(e); false)
end
