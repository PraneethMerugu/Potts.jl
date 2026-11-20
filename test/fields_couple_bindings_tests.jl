# Constant bindings and bare-symbol keys of a coupled PDESystem. Uses the definitions of
# couple_testsetup.jl (CpPDE, CpCases, CpHost, cp_msg, cp_run, cp_same, cp_build_err).
#
# A constant binding is refused whether Julia gives it as `false` or as `Num(false)`. In a
# vector that also holds a symbolic binding, `Potts.kind == :A` (Julia's `false`) is
# promoted to `Num(false)`; at the base 4ca38af7 the `e isa Bool` guard missed it and the
# input was false at every site (0 true sites). Negative control at 4ca38af7: the first
# testset fails, the mixed and the single `Num` bindings build ("built").
#
# A bare-symbol key of an `@fields` binding names an input of the PDESystem first, and its
# value in the constructor only when no input has that name, so `endo => kind == endo` works
# in a model with a kind `endo`. Negative control at 4ca38af7: "`1` is not a dependent
# variable" (the kind number), and a key naming nothing is an `UndefVarError`.

@testitem "a constant symbolic binding is a constant (mixed vectors, one binding)" setup = [
    CoupleSetup,
] tags = [
    :potts, :fields_couple_bindings,
] begin
    @testset "a constant symbolic binding is a constant (mixed vectors, one binding)" begin
        host = CpHost(; name = :m)
        vol = Potts.value_at(Potts.B.volume, Potts.B.owner)
        # the mixed vector: Julia promotes the `false` (the real reason of the bug)
        b = [CpPDE.endo => Potts.kind == :A, CpPDE.vol => vol]
        @test last(eltype(b).parameters) === Potts.Num
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = b))
        @test occursin("the input `endo` is bound to the constant `false`", e) &&
            occursin("Potts.is_kind(model, :A)", e) || (println(e); false)
        # either order, and a `Bool` and a numeric input mixed with a test
        e = cp_msg(
            () -> Potts.couple(
                host, CpPDE.sys();
                inputs = [CpPDE.vol => vol, CpPDE.endo => Potts.kind == :A]
            )
        )
        @test occursin("bound to the constant `false`", e) || (println(e); false)
        # one constant binding, given symbolic: the same refusal as the plain one
        for (sym, plain) in ((Potts.Num(false), false), (Potts.Num(true), true))
            es, ep = (
                cp_msg(
                    () -> Potts.couple(
                        host, CpCases.first_sys(); inputs = [
                            CpCases.endo =>
                                v,
                        ]
                    )
                ) for v in (sym, plain)
            )
            @test es == ep &&
                occursin("a binding to a constant is the same at every site", es) ||
                (println(es); false)
        end
        # a numeric input bound to a symbolic constant equals the plain constant (bitwise)
        ms = Potts.couple(
            host, CpPDE.sys();
            inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => Potts.Num(16.0)]
        )
        mp = Potts.couple(
            host, CpPDE.sys(); inputs = [
                CpPDE.endo => Potts.kind == 1, CpPDE.vol => 16.0,
            ]
        )
        rs, rp = cp_run(ms, ExplicitEuler()), cp_run(mp, ExplicitEuler())
        @test cp_same(rs, rp) && maximum(rs.u[end].site.c) > 0.1
        # the route: a test that is not constant still binds (a mixed vector of symbolic
        # tests)
        mr = Potts.couple(
            host,
            CpPDE.sys();
            inputs = [CpPDE.endo => Potts.kind == Potts.lookup(host, :A), CpPDE.vol => vol]
        )
        @test count(==(1), Potts.field_inputs(PottsProblem(mr, cp_op(), (0, 1)))[:kind]) ==
            32
    end
end

@testitem "a bare key names an input first, its value second" setup = [CoupleSetup] tags = [
    :potts, :fields_couple_bindings,
] begin
    @testset "a bare key names an input first, its value second" begin
        function ce_op(k)
            σ = zeros(Int32, 24, 20)
            σ[5:8, 5:8] .= 1
            σ[14:17, 10:13] .= 2
            return [ownership => σ, kind => [k, k]]
        end
        ref = cp_run(CpFields2(; name = :m), ExplicitEuler())
        kn = cp_run(CeKindNamed(; name = :m), ExplicitEuler(); op = ce_op(:endo))
        # bitwise, kind `endo` ≡ kind `A`
        @test cp_same(kn, ref) && maximum(ref.u[end].site.c) > 0.1
        @test count(
            ==(1),
            Potts.field_inputs(
                PottsProblem(
                    CeKindNamed(; name = :m), ce_op(:endo), (
                        0, 1,
                    )
                )
            )[:kind]
        ) == 32
        # the value of a name that is no input
        @test cp_same(cp_run(CeAlias(; name = :m), ExplicitEuler()), ref)
        # a key that names neither an input nor a value: the refusal names the inputs
        e = cp_build_err(
            quote
                @potts_model CeNeither begin
                    @kinds medium A
                    @lattice Lattice((24, 20); boundary = Closed())
                    @energy cells(A) => (volume - 16.0)^2
                    @fields CpPDE.sys2() (ce_nothing_here => kind == A)
                    @sweep Metropolis(; temperature = 4.0)
                end
                CeNeither(; name = :m)
            end
        )
        @test occursin(
            "`ce_nothing_here` is not a dependent variable of the PDESystem `fields`", e
        ) &&
            occursin("`endo`", e) ||
            (println(e); false)
        # a key whose value is no input (a kind number) keeps the existing refusal
        e = cp_build_err(
            quote
                @potts_model CeKindKey begin
                    @kinds medium A
                    @lattice Lattice((24, 20); boundary = Closed())
                    @energy cells(A) => (volume - 16.0)^2
                    @fields CpPDE.sys2() (A => kind == A)
                    @sweep Metropolis(; temperature = 4.0)
                end
                CeKindKey(; name = :m)
            end
        )
        @test occursin("`1` is not a dependent variable", e) || (println(e); false)
    end
end
