# F4-B2 (F4 design §11, research/front-end-b-only.md §1a, §2): a plain MTK `PDESystem` couples
# into a model, `Potts.couple(model, pdesys; inputs)` or `@fields pdesys (bindings…)` in
# `@potts_model`. Its fields join the model under their own names (`c`, not `name₊c`); each
# input of the PDESystem (a plain 0/1 or numeric input field) is bound to a CPM expression
# (`kind == A`, `volume[owner]`), filled per site by the field compiler. Oracles: LatticePDE's
# own run of the same PDESystem over each MCS window (`cp_replay`), from the coupled run's
# field before the window, with the inputs computed by hand from σ after the sweep (until
# the oracle was the same field in the model's `@equations`, bitwise); the routes
# (`Potts.couple`, `@fields`, `@extend` with a drive) against each other, bitwise; ForwardDiff
# against central differences at a fixed CPM path (F3-21b's shadow store); the ODE path, the
# PDESystem solved by Tsit5 with `Potts.field_inputs(integ)` against the owned explicit run at
# 400 substeps (max difference 4.05e-5, tolerance 6e-5), and the inputs against hand-computed
# site arrays (F4-09).
# Negative controls: at the base 4d025fa8 `Potts.couple`, `Potts.field_inputs` and `@fields` do
# not exist (a LoadError, ~/lpwork/f4B2/nc-base.log). A mutation that gives each of two bound
# inputs the other's expression fails the bitwise testsets (~/lpwork/f4B2/nc-swap.log), and a
# wrong binding (`kind == medium`) is checked to differ in this file.

@testitem "F4-B2: Potts.couple runs the PDESystem (owned oracle), under its own names" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: Potts.couple runs the PDESystem (owned oracle), under its own names" begin
        T, X, Y = CpPDE.t, CpPDE.x, CpPDE.y
        vol = Potts.value_at(Potts.B.volume, Potts.B.owner)
        # keys as the callable, the applied variable and the name
        for ins in ([CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol],
                    [CpPDE.endo(T, X, Y) => Potts.kind == 1, :vol => vol])
            m = Potts.couple(CpHost(; name = :m), CpPDE.sys(); inputs = ins)
            @test any(x -> Potts.info(x).name === :c, Potts.declared_variables(m))                 # `c`, not `fields₊c`
            @test Set(Potts.info(q).name for q in Potts.declared_parameters(m)) == Set([:Dc, :s, :kd, :av])
            for fs in (ExplicitEuler(), BackwardEuler())
                err, n = cp_replay(m, CpPDE.sys(), cp_hand, fs; fs)
                @test n == 12 && err <= cp_tol(fs) || (println("couple $fs: $err"); false)
                @test maximum(cp_run(m, fs).u[end].site.c) > 0.5
            end
        end
        # its parameters by name in the operating point, its field in a `FieldGroups` pair
        m = Potts.couple(CpHost(; name = :m), CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol])
        a = cp_run(m, FieldGroups(:c => BackwardEuler()); op = [cp_op(); :s => 0.9])
        b = cp_run(m, BackwardEuler(); op = [cp_op(); :s => 0.9])
        @test a.u[end].site.c == b.u[end].site.c && a.u[end].site.c != cp_run(m, BackwardEuler()).u[end].site.c
        @test a[:c][end] == a.u[end].site.c
        err, n = cp_replay(
            m, CpPDE.sys(), cp_hand, BackwardEuler(); fs = FieldGroups(:c => BackwardEuler()),
            op = [cp_op(); :s => 0.9], p = [CpPDE.s => 0.9])
        @test n == 12 && err <= cp_tol(BackwardEuler()) || (println("FieldGroups s = 0.9: $err"); false)
    end
end

@testitem "F4-B2: @fields in @potts_model; a drive reads the field by name" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: @fields in @potts_model; a drive reads the field by name" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            err, n = cp_replay(CpFields(; name = :m), CpPDE.sys(), cp_hand, fs; fs)
            @test n == 12 && err <= cp_tol(fs) || (println("CpFields $fs: $err"); false)
            # the drive reads `c` (the CPM path depends on the field); the field runs the PDESystem
            err, n = cp_replay(CpDrive(; name = :m), CpPDE.sys2(), cp_hand2, fs; fs)
            @test n == 12 && err <= cp_tol(fs) || (println("CpDrive $fs: $err"); false)
            # (control: the drive moves the path)
            @test cp_run(CpDrive(; name = :m), fs).u[end].ownership != cp_run(CpFields2(; name = :m), fs).u[end].ownership
        end
        # the operating point reaches the coupled parameters as any others
        k = cp_run(CpFields(; name = :m), ExplicitEuler(); op = [cp_op(); :kd => 0.3]).u[end].site.c
        err, n = cp_replay(
            CpFields(; name = :m), CpPDE.sys(), cp_hand, ExplicitEuler(); op = [cp_op(); :kd => 0.3],
            p = [CpPDE.kd => 0.3])
        @test n == 12 && err == 0 || (println("kd = 0.3: $err"); false)
        # and so do the constructor keywords (S1 of the F4-B2 review); an unknown keyword is refused
        @test k == cp_run(CpFields(; name = :m, kd = 0.3), ExplicitEuler()).u[end].site.c
        @test k != cp_run(CpFields(; name = :m), ExplicitEuler()).u[end].site.c
        @test occursin("zz", cp_msg(() -> CpFields(; name = :m, zz = 1.0)))
    end
end

@testitem "F4-B2: @fields c = pdesys binds the field for the statements after it" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: @fields c = pdesys binds the field for the statements after it" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            # the drive in the same body: bitwise the `@extend` route (whose field the owned oracle checks)
            a, d = cp_run(CpSame(; name = :m), fs), cp_run(CpDrive(; name = :m), fs)
            @test cp_same(d, a)
            @test a.u[end].ownership != cp_run(CpFields2(; name = :m), fs).u[end].ownership             # (control: the drive moves the path)
            # a list of names; one name with the other field reached by name: both fields run the PDESystem
            for M in (CpList, CpOne)
                err, n = cp_replay(M(; name = :m), CpPDE.sys3(), cp_hand2, fs; fs, fields = (:c, :u))
                @test n == 12 && err <= cp_tol(fs) || (println("$M $fs: $err"); false)
            end
            o = cp_run(CpOne(; name = :m), fs)
            @test maximum(o[:u][end]) > 0 && o.u[end].ownership != cp_run(CpList(; name = :m), fs).u[end].ownership   # (the drives read other fields)
        end
        # control: a wrong binding is caught by the oracles
        @test cp_run(CpWrong(; name = :m), ExplicitEuler()).u[end].site.c != cp_run(CpFields(; name = :m), ExplicitEuler()).u[end].site.c
        @test cp_replay(CpWrong(; name = :m), CpPDE.sys(), cp_hand, ExplicitEuler())[1] > 1.0e-3
        body(line; pre = :(), post = :()) = quote
            @potts_model CpBadNames begin
                @kinds medium A
                $pre
                @lattice Lattice((24, 20); boundary = Closed())
                $line
                $post
                @sweep Metropolis(; temperature = 4.0)
            end
            CpBadNames(; name = :m)
        end
        # a name that is not a field of the PDESystem (an input is not a field)
        for n in (:w, :endo)
            e = cp_build_err(body(:(@fields $n = CpPDE.sys2() (CpPDE.endo => kind == A))))
            @test occursin("`$n`", e) || (println(e); false)
        end
        # a field listed twice
        e = cp_build_err(body(:(@fields c, c = CpPDE.sys3() (CpPDE.endo => kind == A))))
        @test occursin("twice", e) || (println(e); false)
        # a name that clashes with the model: declared before, after, or one the PDESystem brings in
        e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); pre = :(@parameters c = 1.0)))
        @test occursin("`c`", e) || (println(e); false)
        e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); post = :(@variables c(field) = 0.0)))
        @test occursin("`c`", e) || (println(e); false)
        e = cp_build_err(body(:(@fields c = CpPDE.sys2() (CpPDE.endo => kind == A)); pre = :(@parameters kd = 1.0)))
        @test occursin("`kd`", e) || (println(e); false)
        # before the lattice
        e = cp_build_err(quote
            @potts_model CpBadNames begin
                @kinds medium A
                @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
                @lattice Lattice((24, 20); boundary = Closed())
                @sweep Metropolis(; temperature = 4.0)
            end
            CpBadNames(; name = :m)
        end)
        @test occursin("@lattice", e) || (println(e); false)
    end
end

@testitem "F4-B2: refusals name the input and the PDESystem" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: refusals name the input and the PDESystem" begin
        host = CpHost(; name = :m)
        vol = Potts.value_at(Potts.B.volume, Potts.B.owner)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.med => Potts.kind == 0]))
        @test occursin("`med`", e)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.c => Potts.kind == 0]))
        @test occursin("input", e)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, :endo => Potts.kind == 0]))
        @test occursin("`endo`", e)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => vol]))
        @test occursin("`endo`", e)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.vol => CpPDE.kd]))
        @test occursin("`kd`", e)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol, 3]))
        @test occursin("pair", e)
        # an unbound input with no CPM word is refused as before (`vol` is not a word the CPM fills)
        e = cp_msg(() -> Potts.couple(host, CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1]))
        @test occursin("`vol`", e)
        # a name the model has already: refused (a namespaced component is the route)
        e = cp_msg(() -> Potts.couple(CpFields(; name = :m), CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol]))
        @test !startswith(e, "wrong exception") && occursin("already has", e)
        # `@fields` syntax
        e = cp_build_err(
            :(
                @potts_model CpBadFields begin
                    @kinds medium A
                    @lattice Lattice((24, 20); boundary = Closed())
                    @fields CpPDE.sys() (CpPDE.endo, CpPDE.vol => volume[owner])
                    @sweep Metropolis(; temperature = 4.0)
                end
            )
        )
        @test occursin("binding", e)
        # the `:field` scope of `ode_system`: still refused with "field", now naming the route
        cs = mtkcompile(CpFields2(; name = :m))
        e = cp_msg(() -> Potts.ode_system(cs, :field))
        @test occursin("field", e)
        @test !occursin("field_inputs", cp_msg(() -> Potts.ode_system(cs, :site)))
    end
end

# F3-21b's shadow store through the coupling: a Dual parameter of the PDESystem runs, the CPM
# path stays primal, and the derivative matches central differences at the same seed
@testitem "F4-B2: field derivatives of a coupled model against central differences" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: field derivatives of a coupled model against central differences" begin
        tight = LatticePCG(; reltol = 1.0e-11, maxiters = 60)
        for fs in (ExplicitEuler(), BackwardEuler(; linsolve = tight)), M in (CpFields2, CpDrive)
            base = cp_run(M(; name = :m), fs)
            for (name, v) in ((:s, 0.5), (:kd, 0.1), (:Dc, 0.2))
                d = cp_run(M(; name = :m), fs; op = [cp_op(); name => ForwardDiff.Dual(v, 1.0)])
                @test all(d.u[i].ownership == base.u[i].ownership for i in eachindex(base.u))
                @test all(ForwardDiff.value.(d.u[i].site.c) == base.u[i].site.c for i in eachindex(base.u))
                @test eltype(d.u[end].site.c) <: ForwardDiff.Dual
                h = 1e-4 * v
                rp = cp_run(M(; name = :m), fs; op = [cp_op(); name => v + h])
                rm = cp_run(M(; name = :m), fs; op = [cp_op(); name => v - h])
                @test all(rp.u[i].ownership == base.u[i].ownership == rm.u[i].ownership for i in eachindex(base.u))   # the path is fixed
                fd = (cp_q(rp) - cp_q(rm)) / 2h
                @test ForwardDiff.partials(cp_q(d), 1) ≈ fd rtol = 1e-6
                @test abs(fd) > 1e-6                                                          # (not a zero derivative)
            end
        end
        # `ForwardDiff.derivative` through `solve` of a `Potts.couple` model
        m = Potts.couple(CpHost(; name = :m), CpPDE.sys2(); inputs = [CpPDE.endo => Potts.kind == 1])
        f(k) = cp_q(cp_run(m, ExplicitEuler(); op = [cp_op(); :kd => k]))
        @test ForwardDiff.derivative(f, 0.1) ≈ (f(0.1 + 1e-5) - f(0.1 - 1e-5)) / 2e-5 rtol = 1e-6
    end
end

# F4-09 through the coupling: the PDESystem stays a plain MTK system, and
# `Potts.field_inputs(integ)` gives its inputs at the CPM state of an integrator
@testitem "F4-B2: Potts.field_inputs and the ODE path (Tsit5) of the coupled PDESystem" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2: Potts.field_inputs and the ODE path (Tsit5) of the coupled PDESystem" begin
        # the inputs at MCS 5 of a moving run, against site arrays computed by hand
        integ = init(PottsProblem(CpFields(; name = :m), cp_op(), (0, 10); seed = 3), SequentialCPM())
        for _ in 1:5
            step!(integ)
        end
        inp = Potts.field_inputs(integ)
        σ = Array(current_state(integ).ownership)
        k = Array(current_state(integ).cell.kind)
        V = [count(==(j), σ) for j in 1:length(k)]
        # (the inputs of `Potts.fields`: the binding `endo => kind == A` is written in as `kind == 1`,
        # so its input is `kind`; `vol` binds a CPM read and keeps its name; F4-B6 review)
        @test Set(keys(inp)) == Set([:kind, :vol])
        @test eltype(inp[:kind]) === Int32 && inp[:kind] == [s == 0 ? 0 : k[s] for s in σ]
        @test eltype(inp[:vol]) === Float64 && inp[:vol] == [s == 0 ? 0.0 : Float64(V[s]) for s in σ]
        @test σ != cp_op()[1][2]                                                            # (the cells moved)
        # the initial state of a problem; a model without coupled inputs
        p = PottsProblem(CpFields(; name = :m), cp_op(), (0, 1))
        @test Potts.field_inputs(p)[:kind] == (cp_op()[1][2] .!= 0)
        @test isempty(Potts.field_inputs(PottsProblem(CpHost(; name = :m), cp_op(), (0, 1))))
        # the ODE path: σ frozen, the PDESystem discretized with those inputs and solved by Tsit5 over
        # one MCS from the field at MCS 5, against the owned explicit run at many substeps
        integ = init(PottsProblem(CpFrozen(; name = :m), cp_op(), (0, 6); seed = 3, field_solver = ExplicitEuler(; substeps = 400)),
            SequentialCPM())
        for _ in 1:5
            step!(integ)
        end
        c5 = copy(Array(current_state(integ).site.c))
        prob = Potts.LatticePDE.discretize(Potts.fields(CpFrozen(; name = :m)),
            Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((24, 20)); T = Float64); inputs = collect(Potts.field_inputs(integ)))
        s = solve(remake(prob; u0 = vec(c5), tspan = (0.0, 1.0)), Tsit5(); abstol = 1e-11, reltol = 1e-11)
        step!(integ)
        c6 = Array(current_state(integ).site.c)
        err = maximum(abs, reshape(s.u[end], 24, 20) .- c6)
        @info "F4-B2 ODE path: Tsit5 vs the owned run at 400 substeps, max difference $err"
        @test err < CP_ODE_TOL
        @test maximum(abs, c6 .- c5) > 1e-2                                                 # (the field moved)
    end
end

@testitem "F4-B2 review: lifecycle, faces, mask, steady rows (CrLife, owned oracle)" setup = [CoupleSetup, CoupleReviewSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review: lifecycle, faces, mask, steady rows (CrLife, owned oracle)" begin
        for fs in (ExplicitEuler(), FieldGroups(:c => BackwardEuler(), :q => QuasiSteady()))
            b = cr_run(CrLife(; name = :m), fs, 20; op = cr_rich_op())
            # (the run divides cells and kills cell 2)
            live = [length(setdiff(unique(u.ownership), 0)) for u in b.u]
            @test live[end] > live[1] && any(u -> count(==(2), u.ownership) == 0, b.u)
            fs isa FieldGroups && continue
            err, n = cp_replay(
                CrLife(; name = :m), CpRev.rich(), cr_hand, fs; fs, k = 20, op = cr_rich_op(), seed = 5,
                fields = (:c, :q), skip = cr_divided)
            @test n >= 10 && err <= cp_tol(fs) || (println("CrLife $fs: $err over $n windows"); false)
        end
    end
end

@testitem "F4-B2 review: two PDESystems (CrTwoU, CrTwoB, owned oracle)" setup = [CoupleSetup, CoupleReviewSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review: two PDESystems (CrTwoU, CrTwoB, owned oracle)" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            r = cr_run(CrTwoU(; name = :m), fs)
            @test cp_same(r, cr_run(CrTwoB(; name = :m), fs))
            @test maximum(r.u[end].site.w) > 0.1
            f1 = fs isa ExplicitEuler ? ExplicitEuler(; substeps = 4) : fs
            err, n = cp_replay(CrTwoB(; name = :m), CpRev.first_sys(), cp_hand2, f1; fs = f1, k = 10, seed = 5)
            @test n == 10 && err <= cp_tol(fs) || (println("CrTwoB $fs: $err"); false)
        end
    end
end

@testitem "F4-B2 review: Coarse(2) field against LatticePDE (CrCrs, owned oracle)" setup = [CoupleSetup, CoupleReviewSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review: Coarse(2) field against LatticePDE (CrCrs, owned oracle)" begin
        for fs in (ExplicitEuler(), BackwardEuler())
            # the coarse field against LatticePDE's run of the raw PDESystem, with `endo` filled by hand
            c = cr_run(CrCrs(; name = :m), fs)
            @test size(c.u[end].site.cc) == (12, 10)
            @test all(u -> cr_partial(u.ownership, 2) > 0, c.u)
            err, n = cp_replay(CrCrs(; name = :m), CpRev.coarse_sys(), (σ, kind) -> [:endo => [s != 0 && kind[s] == 1 for s in σ]],
                fs; fs, k = 10, seed = 5, fields = (:cc,)
            )
            @test n == 10 && err <= max(cp_tol(fs), 1e-14) || (println("CrCrs $fs: $err"); false)
        end
    end
end

@testitem "F4-B2 review M1: an unbound Bool input filled by a non-Bool word is refused" setup = [CoupleSetup, CoupleReviewSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review M1: an unbound Bool input filled by a non-Bool word is refused" begin
        e = cp_build_err(quote
            @potts_model CrKindBool begin
                @kinds medium A B
                @lattice Lattice((24, 20); boundary = Closed())
                @energy cells => (volume - 16.0)^2
                @fields CpRev.kind_bool()
                @sweep Metropolis(; temperature = 4.0)
            end
            CrKindBool(; name = :m)
        end)
        @test occursin("`Bool` input `kind`", e) && occursin("bind it: `kb => kind == A`", e) || (println(e); false)
        e = cp_msg(() -> Potts.couple(CrHost2(; name = :m), CpRev.kind_bool()))
        @test occursin("bind it: `kb => Potts.kind == :A`", e) || (println(e); false)
        # a numeric input filled by `kind` reads the kind number; `field_inputs` gives the same values
        err, n = cp_replay(CrKindReal(; name = :m), CpRev.kind_real(), (σ, kind) -> [:kind => [s == 0 ? 0.0 : Float64(kind[s]) for s in σ]],
            ExplicitEuler(); k = 10, seed = 5, op = cr_kop()
        )
        @test n == 10 && err <= 1e-14 || (println("CrKindReal: $err"); false)   # (measured 4.4e-16, 2026-11-10)
        fi = Potts.field_inputs(PottsProblem(CrKindReal(; name = :m), cr_kop(), (0, 1)))
        @test fi[:kind][6, 6] === Int32(1) && fi[:kind][15, 11] === Int32(2) && fi[:kind][1, 1] === Int32(0)
    end
end

@testitem "F4-B2 review M2: a name @fields brought in, declared again after it, is refused" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review M2: a name @fields brought in, declared again after it, is refused" begin
        e = cp_build_err(quote
            @potts_model CrAfter begin
                @kinds medium A
                @lattice Lattice((24, 20); boundary = Closed())
                @energy cells => (volume - 16.0)^2
                @fields CpRev.first_sys() (CpRev.endo => kind == A)
                @parameters kd = 5.0
                @sweep Metropolis(; temperature = 4.0)
            end
            CrAfter(; name = :m)
        end)
        @test occursin("`kd` is already declared by `@fields` (the PDESystem `one`)", e) || (println(e); false)
        e = cp_build_err(quote
            @potts_model CrAfterField begin
                @kinds medium A
                @lattice Lattice((24, 20); boundary = Closed())
                @energy cells => (volume - 16.0)^2
                @fields CpRev.first_sys() (CpRev.endo => kind == A)
                @variables c(site) = 0.0
                @sweep Metropolis(; temperature = 4.0)
            end
            CrAfterField(; name = :m)
        end)
        @test occursin("`c` is already declared by `@fields`", e) || (println(e); false)
    end
end

# (`Potts.kind == :A` is Julia's constant `false`: the name cannot be resolved, so a binding to a
# constant truth value is refused with the route, and the route gives the `kind == 1` model)
@testitem "F4-B2 review M3: kind names in Potts.couple" setup = [CoupleSetup, CoupleReviewSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review M3: kind names in Potts.couple" begin
        host = CrHost2(; name = :m)
        e = cp_msg(() -> Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == :A]))
        @test occursin("bound to the constant `false`", e) && occursin("a binding to a constant is the same at every site", e) &&
              occursin("Potts.is_kind(model, :A)", e) ||
              (println(e); false)
        e = cp_msg(() -> Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => true]))
        @test occursin("a binding to a constant is the same at every site", e) && !occursin("kind name", e) || (println(e); false)
        ma = Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == Potts.lookup(host, :A)])
        m1 = Potts.couple(host, CpRev.first_sys(); inputs = [CpRev.endo => Potts.kind == 1])
        a, b = cr_run(ma, ExplicitEuler(); op = cr_kop()), cr_run(m1, ExplicitEuler(); op = cr_kop())
        @test cp_same(b, a) && maximum(a.u[end].site.c) > 0.5
        @test Potts.field_inputs(PottsProblem(ma, cr_kop(), (0, 1)))[:kind][6, 6] === Int32(1)
    end
end

@testitem "F4-B2 review S2: messages name the @fields binding and line order" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B2 review S2: messages name the @fields binding and line order" begin
        hdr(line; first = :(@kinds medium A)) = quote
            @potts_model CrMsg begin
                $first
                @lattice Lattice((24, 20); boundary = Closed())
                @energy cells => (volume - 16.0)^2
                $line
                @sweep Metropolis(; temperature = 4.0)
            end
            CrMsg(; name = :m)
        end
        e = cp_build_err(hdr(:(@fields CpPDE.sys() (CpPDE.endo => kind == A, CpPDE.vol => volume))))
        @test occursin("@fields: the input `vol` is bound to `volume`", e) && occursin("`volume[owner]`", e) &&
              !occursin("@equations", e) || (println(e); false)
        # a name read before the line that binds it
        e = cp_build_err(quote
            @potts_model CrEarly begin
                @kinds medium A
                @parameters χ = 400.0
                @lattice Lattice((24, 20); boundary = Closed())
                @energy cells(A) => (volume - 16.0)^2
                @drive Chemotaxis(c; strength = χ, kinds = (A,))
                @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
                @sweep Metropolis(; temperature = 4.0)
            end
        end)
        @test occursin("`c` is read on a line before `@fields c = …`", e) && occursin("move the `@fields` line above", e) ||
              (println(e); false)
        # before `@kinds`
        e = cp_build_err(quote
            @potts_model CrNoKinds begin
                @lattice Lattice((24, 20); boundary = Closed())
                @fields CpPDE.sys2() (CpPDE.endo => kind == A)
                @kinds medium A
                @sweep Metropolis(; temperature = 4.0)
            end
        end)
        @test occursin("write `@fields` after `@kinds`", e) || (println(e); false)
    end
end

@testitem "F4-B6: a field line in @equations is refused, pointing to @fields" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B6: a field line in @equations is refused, pointing to @fields" begin
        for (line, what) in ((:(@equations D(c) ~ -0.1 * c), "D(c)"), (:(@equations 0 ~ 1.0 - c), "0 ~"), (:(@equations c ~ 1.0), "c ~"))
            e = cp_fresh_err(cp_a_model(line))
            @test occursin("@equations: `", e) && occursin(what, e) && occursin("is an equation of the field `c`", e) &&
                  occursin("`@equations` holds cell and model equations", e) && occursin("using Potts.Fields", e) &&
                  occursin("`@fields c = pdesys", e) || (println(e); false)
        end
        # control: a cell equation, and the static field read by a drive, build
        @test cp_fresh_err(cp_a_model(:(@equations D(x) ~ -0.1 * x), :(@drive Chemotaxis(c; strength = 1.0, kinds = (A,))))) == "built"
    end
end

@testitem "F4-B6: a name of a field's PDESystem in a model body points to using Potts.Fields" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B6: a name of a field's PDESystem in a model body points to using Potts.Fields" begin
        for s in (:laplacian, :Δ, :DivKGrad, :Advect, :Upwind1, :masked, :Differential, :Shift)
            e = cp_fresh_err(cp_a_model(:(@observed q ~ $s(1.0))))
            @test occursin("`$s` is not defined in the model body", e) && occursin("using Potts.Fields", e) &&
                  occursin("@fields", e) || (println(s, ": ", e); false)
        end
        # the A field line is refused at expansion with the same route
        e = cp_fresh_err(cp_a_model(:(@equations D(c) ~ 0.1 * laplacian(c))))
        @test occursin("`laplacian` is not defined in the model body", e) && occursin("@fields", e) || (println(e); false)
        # control: a module that defines the name reads its own (`using Potts.Fields`: `laplacian` is LatticePDE's
        # operator, which a model statement refuses where it is lowered, naming the route)
        m = Module(:CpFreshFields)
        Core.eval(m, :(using Potts; using Potts.Fields: laplacian))
        Core.eval(m, cp_a_model(:(@observed lap ~ laplacian(c))))
        @test Base.invokelatest(() -> Core.eval(m, :(CpA(; name = :m)))) isa PottsSystem
    end
end

@testitem "F4-B6: a field equation in PottsSystem(; equations) is refused, pointing to Potts.couple" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @testset "F4-B6: a field equation in PottsSystem(; equations) is refused, pointing to Potts.couple" begin
        c = Potts.variable(only(Potts.Symbolics.@variables c(Potts.t)), :field; default = 0.0)
        base = (; name = :p, kinds = [:medium, :A], lattice = Potts.lattice_spec((24, 20); boundary = Closed()),
            sweep = Potts.sweep_spec(:metropolis; temperature = 4.0))
        e = cp_msg(() -> Potts.PottsSystem(; base..., variables = Any[c], equations = [Potts.D(c) ~ -0.1 * c]))
        @test occursin("PottsSystem: the equation `", e) && occursin("is an equation of the field `c`", e) &&
              occursin("no coupled PDESystem brought", e) && occursin("Potts.couple(model, pdesys; inputs", e) || (println(e); false)
        # control: the route runs, and a coupled model rebuilt through the keyword constructor (an
        # extension) keeps its fields
        host = Potts.PottsSystem(; base...)
        m = Potts.couple(host, CpPDE.sys2(); inputs = [CpPDE.endo => Potts.kind == 1])
        @test maximum(cp_run(m, ExplicitEuler()).u[end].site.c) > 0.5
        @test extend(Potts.PottsSystem(; base...), m) isa PottsSystem
    end
end

# The inner System of a coupled model holds no field (a field equation there was a scalar
# ODE with a free `x`); the fields are in `Potts.fields`. A field that a remaining equation
# reads (`integral(c)` in a cell equation) is an input of the System, so the free symbols of
# its equations are its unknowns, inputs, parameters and time, and it compiles only with the
# input bound. MTK's hierarchy walkers answer (`get_systems` is empty: a Potts model has no
# subsystem hierarchy). Oracles: the cell ODE alone, compiled from `Potts.inner`, solves to
# `exp(-r t)`; the reader's System builds an `ODEProblem` once its input is bound. Controls on
# the code before this change: the field equation's free symbols, an unbalanced ODE, and
# errors from the walkers.
@testitem "a coupled model's System holds no field; MTK's walkers answer" setup = [CoupleSetup] tags = [:potts, :fields_couple] begin
    @potts_model DecayHost begin
        @kinds medium A
        @parameters r = 0.5
        @variables q(cell) = 1.0
        @lattice Lattice((24, 20); boundary = Closed())
        @energy cells(A) => (volume - 16.0)^2
        @equations D(q) ~ -r * q
        @sweep Metropolis(; temperature = 4.0)
    end
    @potts_model FieldReadingHost begin
        @kinds medium A
        @variables q(cell) = 1.0
        @lattice Lattice((24, 20); boundary = Closed())
        @energy cells(A) => (volume - 16.0)^2
        @fields c = CpPDE.sys2() (CpPDE.endo => kind == A)
        @equations D(q) ~ integral(c) - q
        @sweep Metropolis(; temperature = 4.0)
    end

    @testset "a coupled model's System holds no field; MTK's walkers answer" begin
        M, S = Potts.ModelingToolkitBase, Potts.Symbolics
        vol = Potts.value_at(Potts.B.volume, Potts.B.owner)
        decay = Potts.couple(DecayHost(; name = :host), CpPDE.sys(); inputs = [CpPDE.endo => Potts.kind == 1, CpPDE.vol => vol])
        reader = FieldReadingHost(; name = :reader)
        # property: the free symbols of the equations are declared
        for host in (decay, reader)
            known = Set(S.unwrap.([M.unknowns(host); M.parameters(host); Potts.t]))
            free = mapreduce(e -> Set(S.get_variables(e.rhs)), union, M.equations(host); init = Set{Any}())
            @test issubset(free, known)
            @test length(M.equations(Potts.fields(host))) == 1                 # the field: in the PDESystem
            @test Potts.info(host.c).name === :c && :c in propertynames(host)   # … and by name
        end
        eqs = M.equations(decay)
        @test length(eqs) == length(M.unknowns(decay)) == 1                    # the cell ODE only
        @test !any(x -> Potts.info(x).name === :c, M.unknowns(decay))
        # the reader: `c` is an input, not a state
        @test [M.isinput(x) for x in M.unknowns(reader)] == [Potts.info(x).name === :c for x in M.unknowns(reader)]
        @test any(M.isinput, M.unknowns(reader))
        # no subsystems; the walkers answer
        @test isempty(M.get_systems(decay))
        @test isequal(M.full_equations(decay), eqs)
        @test isempty(M.discrete_events(decay)) && isempty(M.continuous_events(decay))
        @test hasproperty(decay, :r) && !hasproperty(decay, :nothing_here)
        @test (redirect_stdout(() -> M.hierarchy(decay), devnull); true)
        # the cell ODE alone compiles and solves (every value given: oracle q(t) = exp(-r t))
        ode = mtkcompile(Potts.inner(decay))
        op = [only(M.unknowns(ode)) => 1.0; [p => 0.5 for p in M.parameters(ode)]]
        sol = Potts.SciMLBase.solve(Potts.SciMLBase.ODEProblem(ode, op, (0.0, 2.0)), Tsit5(); abstol = 1.0e-10, reltol = 1.0e-10)
        @test sol[only(M.unknowns(ode))][end] ≈ exp(-1.0) rtol = 1.0e-6
        # the reader compiles with its input bound; without it the System is unbalanced
        @test_throws M.ExtraVariablesSystemException mtkcompile(Potts.inner(reader))
        ro = mtkcompile(Potts.inner(reader); inputs = [reader.c])
        @test isequal(M.inputs(ro), [S.unwrap(reader.c)]) && length(M.unknowns(ro)) == 1
        # (a bound input is a parameter of the compiled System)
        pars = [p => (isequal(p, S.unwrap(reader.c)) ? 2.0 : 0.5) for p in M.parameters(ro)]
        rp = Potts.SciMLBase.ODEProblem(ro, [only(M.unknowns(ro)) => 1.0; pars], (0.0, 1.0))
        @test rp isa Potts.SciMLBase.ODEProblem
    end
end
