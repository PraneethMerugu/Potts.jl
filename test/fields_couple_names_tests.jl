# Gaps found when the Merks models and the older tests moved to `@fields`. Uses the
# definitions of couple_testsetup.jl (cp_run, cp_same, cp_op, cp_build_err, cp_msg).
#
# `@fields c, s = pdesys (…)` binds a PDESystem parameter by name for the statements after
# the line, as it binds fields. Oracle: a drive that reads the PDESystem's `s`, bitwise against
# the workaround (a model parameter `s` bound to an input of the PDESystem). Negative control at
# the commit before this feature: "`s` is not a field of the PDESystem".

@testitem "a later statement reads a @fields PDESystem parameter by name" setup = [CoupleSetup] tags = [:potts, :fields_couple_names] begin
    @testset "a later statement reads a @fields PDESystem parameter by name" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            n, w = cp_run(CeNamed(; name = :m), fs), cp_run(CeWork(; name = :m), fs)
            @test cp_same(n, w) && maximum(n.u[end].site.c) > 0.1
            # the keyword sets the one parameter the field and the drive read
            n8, w8 = cp_run(CeNamed(; name = :m, s = 0.8), fs), cp_run(CeWork(; name = :m, s = 0.8), fs)
            @test cp_same(n8, w8) && n8.u[end].site.c != n.u[end].site.c
        end
        @test count(==(:s), [Potts.info(p).name for p in Potts.declared_parameters(CeNamed(; name = :m))]) == 1
        # a name that is neither a field nor a parameter: the refusal lists both
        e = cp_build_err(
            quote
                @potts_model CeNoName begin
                    @kinds medium A
                    @lattice Lattice((24, 20); boundary = Closed())
                    @fields c, q = CeS.named() (a => kind == A)
                    @sweep Metropolis(; temperature = 4.0)
                end
                CeNoName(; name = :m)
            end
        )
        @test occursin("`q` is not a field of the PDESystem `fields`; its fields are `c`", e) &&
            occursin("its parameters (a name may be one too) ", e) && occursin("`s`", e) || (println(e); false)
    end
end

@testitem "a Bool input takes a truth-valued expression (any over a relation)" setup = [CoupleSetup] tags = [:potts, :fields_couple_names] begin
    @testset "a Bool input takes a truth-valued expression (any over a relation)" begin
        op = cp_op()
        σ = first(op).second
        nb = [
            any(
                1 <= i + di <= size(σ, 1) && 1 <= j + dj <= size(σ, 2) && σ[i + di, j + dj] != 0
                    for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
            ) for i in axes(σ, 1), j in axes(σ, 2)
        ]
        fi = Potts.field_inputs(PottsProblem(CeAny(; name = :m), op, (0, 1)))[:a]
        @test fi == nb && count(nb) > 32                                         # cells' edges and their medium rims
        function hand(σ, kind)
            return [
                :a => [
                    any(
                        1 <= i + di <= size(σ, 1) && 1 <= j + dj <= size(σ, 2) && σ[i + di, j + dj] != 0 &&
                            kind[σ[i + di, j + dj]] == 1 for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    )
                        for i in axes(σ, 1), j in axes(σ, 2)
                ],
            ]
        end
        err, n = cp_replay(CeAny(; name = :m), CeS.named_owned(), hand, ExplicitEuler())
        @test n == 12 && err <= 1.0e-14 || (println("CeAny: $err"); false)   # (measured 4.4e-16, 2026-11-10: one rounding)
        host = CpHost(; name = :m)
        k, vol = Potts.kind, Potts.value_at(Potts.B.volume, Potts.B.owner)
        # the other truth-valued forms couple; a numeric one is refused
        for b in ((k == 1) & (vol > 3.0), (k == 1) | (k == 0), !(k == 1), Potts.LatticePDE.ismember(k, (0, 1)))
            @test Potts.couple(host, CeS.named(); inputs = [CeS.a => b]) isa Potts.PottsSystem
        end
        for b in (vol, k, vol + 1.0)
            e = cp_msg(() -> Potts.couple(host, CeS.named(); inputs = [CeS.a => b]))
            @test occursin("the input `a` is a `Bool`", e) && occursin("is not a truth value", e) || (println(e); false)
        end
        e = cp_build_err(
            quote
                @potts_model CeSum begin
                    @kinds medium A
                    @lattice Lattice((24, 20); boundary = Closed())
                    @fields c = CeS.named() (a => sum(volume[n] for n in VonNeumann(1)(site)))
                    @sweep Metropolis(; temperature = 4.0)
                end
                CeSum(; name = :m)
            end
        )
        @test occursin("is not a truth value", e) || (println(e); false)
    end
end

@testitem "a PDESystem's condition is named in its refusal" setup = [CoupleSetup] tags = [:potts, :fields_couple_names] begin
    @testset "a PDESystem's condition is named in its refusal" begin
        op = [ownership => zeros(Int32, 12, 12), kind => Symbol[]]
        for m in (CePeriodic(; name = :m), Potts.couple(CePeriodicHost(; name = :m), CeB.face()))
            e = cp_compile_msg(() -> PottsProblem(m, op, (0, 1)))
            @test !startswith(e, "wrong exception") && occursin("faced", e) || (println(e); false)
        end
    end
end
