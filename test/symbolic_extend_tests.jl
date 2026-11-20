# Split from test/symbolic_tests.jl

@testitem "composition: extend and @extend" setup = [SymbolicSetup, PortsSetup] tags = [:potts, :symbolic] begin
    @testset "composition: extend and @extend" begin
        @potts_model ChemoSorting begin
            @extend λ, V₀, dark = base = GranerGlazier()
            @parameters χ = 50.0
            @fields c = SyPDE.chemo((72, 72)) (SyPDE.src => kind == dark)
            @drive Chemotaxis(c; strength = χ, kinds = (dark,))
            @observed mean_excess ~ sum((volume - V₀) for n in cells) * λ
        end

        @potts_model WalledSorting begin
            @extend base = GranerGlazier(; lattice = (40, 40), T = 6.0)
            @kinds medium dark light wall[frozen]
            @parameters J[kind, kind] = [0 16 16 30; 16 2 11 30; 16 11 14 30; 30 30 30 0]
        end

        ext = ChemoSorting(; name = :chemo)
        @test Potts._p(ext, :kinds) == [:medium, :dark, :light]
        @test Set(Potts.info(x).name for x in Potts.declared_parameters(ext)) == Set([:λ, :V₀, :T, :J, :χ])
        @test length(Potts._p(ext, :energies)) == 2 && length(Potts._p(ext, :drives)) == 1 && Potts.lattice(ext) == Potts.lattice(getfield(SORTING, :sys))
        σ, kinds = graner_state()
        a = symbolic_graner_problem(; nmcs = 5)
        b = PottsProblem(ext, [ownership => σ, kind => kinds], (0, 5); field_solver = ExplicitEuler())
        # without the drive the extension's energy is the base's
        @test all(((u, prop),) -> energy_change(a, u, prop) == energy_change(b, u, prop), proposal_states(a; mcs = (0, 5), n = 100))
        @test b.p.χ == 50.0 && haskey(b.u0.site, :c)
        @test selfcheck(b) < 1.0e-9
        sol = solve(b, SequentialCPM(; proposal = Moore(1)))
        @test length(sol[:mean_excess]) == length(sol.t)
        @test sol[:volume][end] == [Float64(v) for v in sol.u[end].cell.volume] && sol[:c][end] == sol.u[end].site.c
        # an added frozen kind and a redeclared (wider) contact table; base overrides by keyword
        w = WalledSorting(; name = :walled)
        @test Potts._p(w, :kinds) == [:medium, :dark, :light, :wall] && Potts._p(w, :frozen_kinds) == [3]
        @test count(x -> Potts.info(x).name === :J, Potts.declared_parameters(w)) == 1 && size(Potts.info(only(filter(x -> Potts.info(x).name === :J, Potts.declared_parameters(w)))).default) == (4, 4)
        @test Potts.lattice(w).dims == (40, 40)
        σw = zeros(Int32, 40, 40); σw[:, 1] .= 1; σw[10:15, 10:15] .= 2; σw[20:25, 20:25] .= 3
        pw = PottsProblem(w, [ownership => σw, kind => [:wall, :dark, :light]], (0, 10))
        @test pw.p.T == 6.0 && count(pw.frozen) == 40
        @test_throws ArgumentError extend(
            PottsSystem(;
                name = :x, kinds = [:medium, :light], lattice = Potts.lattice(getfield(SORTING, :sys)),
                sweep = Potts._p(getfield(SORTING, :sys), :sweep)
            ), getfield(SORTING, :sys)
        )
        @test_throws ArgumentError Potts.lookup(getfield(SORTING, :sys), :nope)
    end
end


@testitem "@extend: a bound vector parameter redeclared keeps its own default" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "@extend: a bound vector parameter redeclared keeps its own default" begin
        @potts_model ExtVecBase begin
            @kinds medium A B
            @parameters begin
                λ = 1.0
                V₀ = 9.0
                J[kind, kind] = [0 2 2; 2 1 4; 2 4 1]
                d[1:2] = [1.0, 2.0]
            end
            @variables x(cell) = 0.5
            @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
            @energy begin
                cells(A, B) => λ * (volume - V₀)^2
                contacts => J[kind, neighbor_kind]
                cells(A, B) => x * volume
                cells(A) => d[1] * volume
                cells(B) => d[2] * volume
            end
            @sweep Metropolis(; temperature = 10.0)
        end

        @potts_model ExtVecRedecl begin
            @extend d = base = ExtVecBase()
            @parameters d[1:2] = [3.0, 4.0]
        end

        σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[6:8, 3:6] .= 2
        E(m) = total_energy(PottsProblem(m, [ownership => σ, kind => [:A, :B]], (0, 2); seed = 7))
        @test E(ExtVecBase(; name = :b)) == 104.5                           # 71.5 + 9 + 24
        @test E(ExtVecRedecl(; name = :e)) == 146.5                         # 71.5 + 27 + 48
        @test E(ExtVecRedecl(; name = :e, d = [0.0, 0.0])) == 71.5
        # `#…` names are the constructor's own; a declaration of one is rejected
        @test_throws ArgumentError Potts._potts_model(
            :HashName, quote
                @parameters var"##kw#λ" = 4.0
            end, @__MODULE__
        )
    end
end


@testitem "diagnostics name the statement and its source line" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "diagnostics name the statement and its source line" begin
        @potts_model BadSiteVar begin
            @kinds medium A
            @parameters T = 1.0
            @variables x(site) = 0.0
            @lattice Lattice((8, 8))
            @energy begin
                cells(A) => (volume - 10.0)^2
                cells(A) => x                      # a site variable without a site
            end
            @sweep Metropolis(; temperature = T)
        end

        BAD_ENERGY_LINE = @__LINE__() - 5

        @potts_model BadDrive begin
            @kinds medium A
            @parameters T = 1.0
            @lattice Lattice((8, 8))
            @drive copy => volume                  # `volume` changes with the copy
            @sweep Metropolis(; temperature = T)
        end

        BAD_DRIVE_LINE = @__LINE__() - 4

        function msg(f)
            return try
                f(); ""
            catch e
                sprint(showerror, e)
            end
        end
        m = msg(() -> mtkcompile(BadSiteVar(; name = :bad)))
        @test occursin("symbolic_extend_tests.jl:$BAD_ENERGY_LINE", m)
        m = msg(() -> mtkcompile(BadDrive(; name = :bad)))
        @test occursin("symbolic_extend_tests.jl:$BAD_DRIVE_LINE", m)
        # locations survive `extend`
        m = msg(
            () -> mtkcompile(
                extend(
                    PottsSystem(;
                        name = :e, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
                        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)
                    ), BadSiteVar(; name = :bad)
                )
            )
        )
        @test occursin("symbolic_extend_tests.jl:$BAD_ENERGY_LINE", m)
    end
end


@testitem "a model built inside an @extend base has its own build state" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "a model built inside an @extend base has its own build state" begin
        @potts_model _Helper3D begin
            @kinds medium A
            @variables q(cell) = 0.0
            @lattice Lattice((6, 6, 6))
            @after_mcs q ~ rand() + rand()
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model _BuildsHelper begin
            @kinds medium A
            @variables p(cell)[1:2] = 0.0 w(cell) = 0.0
            @lattice Lattice((12, 8))
            helper = _Helper3D(; name = :h)
            @after_mcs w ~ rand()
            @after_mcs p ~ centroid()
            @sweep Metropolis(; temperature = 1.0)
        end

        @potts_model _ExtendsBuilder begin
            @kinds medium A
            @variables v(cell) = 0.0
            @extend b = _BuildsHelper()
            @after_mcs v ~ rand()
            @sweep Metropolis(; temperature = 1.0)
        end

        draws(sys) = sort!([parse(Int, m[1]) for m in eachmatch(r"random_uniform\((\d+)\)", string(Potts._p(sys, :updates)))])
        s = _ExtendsBuilder(; name = :o)                 # threw a DimensionMismatch (3D helper's dim leaked)
        @test draws(s) == [1, 2]                         # base's draw, then the extension's: the helper's two draws are its own
        @test draws(_Helper3D(; name = :h)) == [1, 2]
        @test length(Potts.lattice(s).dims) == 2
        @test count(u -> occursin("cell_centroid", string(u.eq)), Potts._p(s, :updates)) == 2   # p is 2D, not 3D
        @test draws(_BuildsHelper(; name = :b)) == [1]   # serial build of the base alone is unchanged
    end
end


@testitem "one name, one category: vector components" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "one name, one category: vector components" begin
        @potts_model NameVecBase begin
            @kinds medium host
            @parameters vb[1:2] = [1.0, 2.0]
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 10.0)
        end

        @potts_model NameVecVarBase begin
            @kinds medium host
            @variables vb_1(cell) = 7.0
            @observed tot ~ sum(volume for n in cells)
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 10.0)
        end

        @potts_model NameVecUse begin
            @kinds medium host
            @parameters vb[1:3] = [1.0, 2.0, 3.0]
            @variables vw(cell)[1:3] = [0.1, 0.2, 0.3]
            @after_mcs vw[3] ~ Pre(vw[3]) + vb[3]
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2 + vb[3] * vw[3]
            @sweep Metropolis(; temperature = 10.0)
        end

        function rejection(f, words...)
            try
                f()
            catch e
                while e isa LoadError
                    e = e.error
                end
                e isa ArgumentError || return "not an ArgumentError: $(typeof(e))"
                return :ok
            end
            return "accepted silently"
        end
        @potts_model NVVarClash begin
            @extend NameVecBase(); @variables vb_1(cell) = 7.0
        end
        @potts_model NVVecOnVar begin
            @extend NameVecVarBase(); @parameters vb[1:2] = [1.0, 2.0]
        end
        @potts_model NVSingleClash begin
            @kinds medium host; @parameters vb[1:2] = [1.0, 2.0]; @variables vb_1(cell) = 7.0
            @lattice Lattice((12, 12)); @energy cells => (volume - 9.0)^2; @sweep Metropolis(; temperature = 10.0)
        end
        @potts_model NVScalarOnVec begin
            @extend NameVecBase(); @parameters vb_1 = 5.0
        end
        @potts_model NVSingleScalar1 begin
            @kinds medium host; @parameters begin
                vb[1:2] = [1.0, 2.0]; vb_2 = 3.0
            end
            @lattice Lattice((12, 12)); @energy cells => (volume - 9.0)^2; @sweep Metropolis(; temperature = 10.0)
        end
        @potts_model NVSingleScalar2 begin
            @kinds medium host; @parameters begin
                vb_2 = 3.0; vb[1:2] = [1.0, 2.0]
            end
            @lattice Lattice((12, 12)); @energy cells => (volume - 9.0)^2; @sweep Metropolis(; temperature = 10.0)
        end
        @potts_model NVShortParam begin
            @extend NameVecUse(); @parameters vb[1:2] = [5.0, 6.0]
        end
        @potts_model NVShortVar begin
            @extend NameVecUse(); @variables vw(cell)[1:2] = [0.0, 0.0]
        end
        @potts_model NVValidLong begin
            @extend NameVecUse(); @parameters vb[1:4] = [5.0, 6.0, 7.0, 8.0]; @variables vw(cell)[1:3] = [1.0, 1.0, 1.0]
        end
        @potts_model NVObsClash begin
            @extend NameVecVarBase(); @parameters tot = 1.0
        end
        @potts_model NVValidVec begin
            @extend NameVecBase(); @parameters vb[1:3] = [4.0, 5.0, 6.0]
        end
        @potts_model NVValidOther begin
            @extend NameVecBase(); @variables vb_3(cell) = 1.0; @parameters vb₁ = 1.0
        end

        vec = "a parameter (a component of the vector `vb`)"
        # across categories, both directions, attributing the base's side
        @test rejection(() -> NVVarClash(; name = :ext), "variable `vb_1`", vec, "in the base") === :ok
        @test rejection(() -> NVVecOnVar(; name = :ext), "`vb_1`", "variable in the base", "component of the vector `vb`") === :ok
        # within one model (`@potts_model` alone does not see the component names)
        @test rejection(() -> NVSingleClash(; name = :ext), "variable `vb_1`", vec) === :ok
        # a scalar of the same category named like a component would leave half a vector
        @test rejection(() -> NVScalarOnVec(; name = :ext), "parameter `vb_1`", vec, "in the base") === :ok
        @test rejection(() -> NVSingleScalar1(; name = :ext), "`vb_2`", "component of the vector `vb`") === :ok
        # programmatic: `extend` and a hand-built `PottsSystem`
        base, var = NameVecBase(; name = :b), NameVecVarBase(; name = :v)
        @test rejection(() -> extend(var, base), "`vb_1`", "in the base `b`", "component of the vector `vb`") === :ok
        @test rejection(
            () -> Potts.PottsSystem(;
                name = :p, kinds = Potts._p(base, :kinds), lattice = Potts.lattice(base), sweep = Potts._p(base, :sweep),
                parameters = Any[Potts.declared_parameters(base)...], variables = Any[Potts.declared_variables(var)...]
            ), "`vb_1`", vec
        ) === :ok
        # the label reads `parameter `vb_2` (a component of the vector `vb`)`
        @test rejection(() -> NVSingleScalar2(; name = :ext), "parameter `vb_2` (a component of the vector `vb`)") === :ok
        # an override vector may not be shorter than the base's (the base reads `vb[3]`, `vw[3]`)
        @test rejection(() -> NVShortParam(; name = :ext), "`vb` has 3 components in the base", "`vb[1:2]` would drop `vb_3`") === :ok
        @test rejection(() -> NVShortVar(; name = :ext), "`vw` has 3 components in the base", "`vw[1:2]` would drop `vw_3`") === :ok
        m = NVValidLong(; name = :ext)
        s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1
        sol = solve(PottsProblem(m, [ownership => s, kind => [:host]], (0, 2)), SequentialCPM(; proposal = Moore(1)); saveat = 1)
        @test observe(sol, :vw_3)[end] == [1.0 + 2 * 7.0]
        # the article follows the category
        @test rejection(() -> NVObsClash(; name = :ext), "already declared as an observed quantity") === :ok
        # controls: a vector override replaces the base's vector whole; other names are free
        m = NVValidVec(; name = :ext)
        @test sort([Potts.info(p).name for p in Potts.declared_parameters(m)]) == [:vb_1, :vb_2, :vb_3] &&
            all(p -> Potts.info(p).default == 3.0 + Potts.info(p).options.index, Potts.declared_parameters(m))
        m = NVValidOther(; name = :ext)
        @test Potts.info(Potts.lookup(m, :vb_3)).role === :cell && mtkcompile(m) isa Potts.CompiledPottsSystem
    end
end


@testitem "a key namespaced by the model itself is the declared quantity" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "a key namespaced by the model itself is the declared quantity" begin
        @potts_model NsComp begin
            @kinds medium host
            @variables x(cell) = 1.5
            @components cells(host) dc = NS_DECAY[]
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @equations D(x) ~ -0.1 * x
            @sweep Metropolis(; temperature = 1.0)
        end

        ns_op() = [ownership => (s = zeros(Int32, 12, 12); s[2:4, 2:4] .= 1; s[7:9, 7:9] .= 2; s), kind => [:host, :host]]

        SII = Potts.SymbolicIndexingInterface
        M = Potts.ModelingToolkitBase
        sys = NsCell(; name = :pr)
        ns = M.toggle_namespacing(Potts.inner(sys), true)                       # MTK's namespaced view
        @test SII.getname(ns.λ) === :pr₊λ && SII.getname(sys.λ) === :λ          # the keys differ …
        # … and mean the same everywhere: operating point (parameter and variable)
        p1 = PottsProblem(sys, [ns_op(); ns.λ => 7.0; ns.x => 3.0], (0, 2))
        p2 = PottsProblem(sys, [ns_op(); sys.λ => 7.0; sys.x => 3.0], (0, 2))
        @test p1.p == p2.p && p1.p.λ == 7.0 && p1.u0.cell.x == p2.u0.cell.x == [3.0, 3.0]
        @test PottsProblem(sys, [ns_op(); Symbol("pr₊λ") => 5.0], (0, 1)).p.λ == 5.0     # the name, too
        # remake p and u0
        @test remake(p1; p = [ns.λ => 9.0]).p.λ == 9.0
        @test remake(p1; u0 = [ns_op(); ns.x => 4.0]).u0.cell.x == [4.0, 4.0]
        # getu / setu / getp / observe / prob[…] / sol[…], with observed quantities and expressions
        @test SII.getu(p1, ns.x)(p1) == [3.0, 3.0] && SII.getp(p1, ns.λ)(p1) == 7.0
        @test observe(p1, ns.total) == observe(p1, sys.total) == 6.0
        @test p1[ns.total] == 6.0 && p1[ns.g] == p1[sys.g]
        @test observe(p1, 2 * ns.total + ns.λ) == 2 * 6.0 + 7.0
        q = deepcopy(p1)
        SII.setu(q, ns.x)(q, [1.0, 2.0])
        @test q.u0.cell.x == [1.0, 2.0]
        sol = solve(p1, SequentialCPM())
        @test sol[ns.total] == sol[sys.total] && sol[ns.g] == sol[sys.g]
        # solvers keys
        fp(k) = PottsProblem(sys, ns_op(), (0, 1); solvers = [k => Potts.RK4()]).f.fingerprint
        @test fp(ns.x) == fp(sys.x) == fp(:x) != PottsProblem(sys, ns_op(), (0, 1)).f.fingerprint
        # components: `sys.dc.y` is the flattened `dc₊y`
        comp = NsComp(; name = :pc)
        @test PottsProblem(comp, [ns_op(); comp.dc.y => 2.0], (0, 1)).u0.cell.dc₊y == [2.0, 2.0]
        cfp(k) = PottsProblem(comp, ns_op(), (0, 1); solvers = [k => Potts.RK4()]).f.fingerprint
        @test cfp(comp.dc.y) == cfp(M.toggle_namespacing(Potts.inner(comp), true).dc.y)
        # negative controls: a key namespaced by another model names nothing here
        other = M.toggle_namespacing(Potts.inner(NsCell(; name = :other)), true)
        for f in (
                () -> PottsProblem(sys, [ns_op(); other.λ => 1.0], (0, 1)), () -> remake(p1; p = [other.λ => 1.0]),
                () -> observe(p1, other.total),
            )
            e = try
                f(); nothing
            catch err
                err
            end
            @test e isa ArgumentError
        end
        # … and wherever else a key is resolved: `getp`, `prob.ps[…]`, `solvers`,
        # and inside an expression
        for f in (
                () -> Potts.SymbolicIndexingInterface.getp(p1, other.λ)(p1), () -> p1.ps[other.λ],
                () -> PottsProblem(sys, ns_op(), (0, 1); solvers = [other.x => Potts.RK4()]), () -> p1[sys.total + other.λ],
                () -> observe(p1, sys.total + other.λ),
            )
            e = try
                f(); nothing
            catch err
                err
            end
            @test e isa ArgumentError
        end
        @test p1[sys.total + sys.λ] == 6.0 + 7.0                     # control: the model's own keys
        @test p1.ps[sys.λ] == 7.0 && SII.getp(p1, sys.λ)(p1) == 7.0
        # a vector quantity, a kind or an unknown name is not a property (MTK's own error)
        @test_throws ArgumentError sys.w
        @test_throws ArgumentError sys.host
        @test_throws ArgumentError sys.nosuch
        @test isequal(M.independent_variables(sys), Any[Potts._unwrap(Potts.t)])
    end
end


@testitem "MTK's system operations on a PottsSystem; metadata is the inner System's" setup = [SymbolicSetup] tags = [:potts, :symbolic] begin
    @testset "MTK's system operations on a PottsSystem; metadata is the inner System's" begin
        M = Potts.ModelingToolkitBase
        sys = NsCell(; name = :pr)
        # Potts re-exports MTK's own `compose` and `extend`; `complete` is MTK's, not exported
        @test Potts.complete === M.complete && Potts.compose === M.compose && Potts.extend === M.extend
        @test !Base.isexported(Potts, :complete)
        @test M.complete(sys) === sys
        @test M.extend(sys, NsCell(; name = :b)) isa PottsSystem
        @test_throws ArgumentError M.toggle_namespacing(sys, false)
        @test nameof(NsSetfield.@set sys.name = :zz) === :zz
        @test M.getmetadata(sys, NsKey, nothing) === nothing
        # the sweep payload is on the inner System, and follows `extend`
        @test M.getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
        e = extend(NsCell(; name = :a), NsCell(; name = :b))
        @test M.getmetadata(Potts.inner(e), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
        @test M.getmetadata(Potts.inner(sys), NsKey, nothing) === nothing
    end
end
