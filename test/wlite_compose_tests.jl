# W-lite wrap checks, Potts.compose, PDESystem conditions, hand-built inner guard, C9 components and Potts.component.

@testitem "W-lite: wrap checks" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: wrap checks" begin
        @test_throws ArgumentError Potts.wrap(:other, complete(inner_all), nothing, WLiteModels.part())
        @test_throws ["System is named", "must agree"] Potts.wrap(:other, complete(inner_all), nothing, WLiteModels.part())
        @test_throws ArgumentError Potts.wrap(:allparts, complete(inner_all), WLiteModels.pde(:x), WLiteModels.part())
        @test_throws ["PDESystem is named", "must agree"] Potts.wrap(:allparts, complete(inner_all), WLiteModels.pde(:x), WLiteModels.part())
        # P3-wlite trap 2: a completed system composed again is complete but not flat
        trap = compose(complete(WLiteModels.inner_top), [decay])
        @test iscomplete(trap) && !isempty(WL_MTKB.get_systems(trap))
        @test_throws ArgumentError Potts.wrap(:allparts, trap, nothing, WLiteModels.part())
        @test_throws ["not flattened", "compose the uncompleted"] Potts.wrap(:allparts, trap, nothing, WLiteModels.part())
        # an uncompleted system is completed (flattened) by wrap
        w = Potts.wrap(:allparts, inner_all, nothing, WLiteModels.part())
        @test iscomplete(Potts.inner(w)) && isempty(WL_MTKB.get_systems(Potts.inner(w))) &&
            issetequal(unknowns(w), unknowns(complete(inner_all)))
        @test Potts.fields(W_all) isa PDESystem && Potts.fields(W_empty) === nothing
        # the sweep payload is the inner System's metadata
        @test WL_MTKB.getmetadata(Potts.inner(w), Potts.PottsSweepSpec, nothing) isa Potts.PottsSweepSpec
        @test WL_MTKB.getmetadata(inner_all, Potts.PottsSweepSpec, nothing) === nothing
    end
end

@testitem "W-lite: Potts.compose equals the raw reference" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: Potts.compose equals the raw reference" begin
        C, M_, T_ = WLiteCompose.cell(), WLiteCompose.model(), WLiteCompose.top()
        part = WLiteModels.part
        bind(n) = [Potts.FieldBinding(Symbol[], :vol, :volume)]
        wcell = Potts.wrap(
            :cell, C, nothing, part(;
                bindings = [
                    Potts.FieldBinding(Symbol[], :cbar, :c_mean);
                    bind(:cell)
                ]
            )
        )
        wmodel = Potts.wrap(:model, M_, nothing, part(; bindings = bind(:model)))
        wtop = Potts.wrap(:top, T_, nothing, part())
        function same(W, ref)
            I = Potts.inner(W)
            isequal(Set(equations(I)), Set(equations(ref))) && issetequal(unknowns(I), unknowns(ref)) &&
                issetequal(parameters(I), parameters(ref)) &&
                length(parameters(I; initial_parameters = true)) == length(parameters(ref; initial_parameters = true))
        end
        ref = complete(compose(WLiteCompose.model(), [WLiteCompose.cell()]))
        Wb = Potts.compose(wmodel, wcell)
        @test same(Wb, ref)                                                    # b7
        @test any(isequal(unwrap(Wb.cell.xc)), unknowns(Wb))
        # nested: top ∘ (model ∘ cell)
        nref = complete(compose(WLiteCompose.top(), [compose(WLiteCompose.model(), [WLiteCompose.cell()])]))
        Wn = Potts.compose(wtop, Potts.compose(wmodel, wcell))
        @test same(Wn, nref)                                                   # b8
        @test any(isequal(unwrap(Wn.model.cell.xc)), unknowns(Wn))
        # negative control: unwrapping the flattened inner (not `get_parent`) loses the hierarchy (trap 1)
        flat = Potts.wrap(:model, complete(compose(Potts.inner(wmodel), [Potts.inner(wcell)]; name = :model)), nothing, part())
        @test_throws ArgumentError flat.cell
        # S-2: (path, name) bindings, prefixed at compose, resolve to bound inputs of unknowns(W)
        bs = Potts.getfield(Potts.getfield(Wn, :part), :bindings)
        @test sort([(b.path, b.name) for b in bs]) ==
            sort([(Symbol[:model], :vol), (Symbol[:model, :cell], :cbar), (Symbol[:model, :cell], :vol)])
        for b in bs
            r = unwrap(Potts.resolve(Wn, b))
            @test any(isequal(r), unknowns(Wn)) && Potts.ModelingToolkitBase.isinput(r)
        end
        inputs = filter(Potts.ModelingToolkitBase.isinput, unknowns(Wn))
        @test issetequal(inputs, [unwrap(Potts.resolve(Wn, b)) for b in bs])     # every input is bound
        @test occursin("binding model.cell.cbar ← c_mean", sprint(show, MIME"text/plain"(), Wn))
        # the resolved terms are template-compile inputs
        @test Potts.ModelingToolkitBase.mtkcompile(Potts.inner(Wn); inputs) isa System
        # C4 review B1 / C9: subsystems are lowered into the payload as model-scope components;
        # top-level content of a hand-built System (wmodel's `D(w)`) and component inputs (wcell's
        # `cbar`, `vol`) are refused by name, never dropped
        loud(f, what) = try
            f()
            false
        catch e
            e isa ArgumentError && occursin(what, sprint(showerror, e))
        end
        refused = r"payload cannot build|has the input"     # wmodel's top level; wcell's inputs
        for W in (Wb, Wn, wcell)
            @test loud(() -> mtkcompile(W), refused)
            @test loud(() -> Potts.ModelingToolkitBase.structural_simplify(W), refused)
            @test loud(() -> PottsProblem(W, [], (0, 1)), refused)
            @test loud(() -> Potts.extend(W, wtop), refused) &&
                loud(() -> Potts.extend(PottsModels.GranerGlazier(; name = :gg), W), refused)
        end
        # control: a model built from its payload compiles and extends
        gg = PottsModels.GranerGlazier(; name = :gg)
        @test mtkcompile(gg) isa CompiledPottsSystem && Potts.extend(gg, gg) isa PottsSystem
        # a component carrying CPM statements is refused
        cpm = PottsModels.GranerGlazier(; name = :gg)
        @test_throws ArgumentError Potts.compose(wtop, cpm)
    end
end

@testitem "W-lite: a PDESystem's condition is stored, printed and lowered (F1, V4; F2-11)" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: a PDESystem's condition is stored, printed and lowered (F1, V4; F2-11)" begin
        sys = WLiteBcs(; name = :b, with_bcs = true)
        bcs = Potts.getfield(Potts.getfield(sys, :part), :bcs)
        @test length(bcs) == 1 && occursin("masked", string(bcs[1]))
        @test occursin("bc      ", sprint(show, MIME"text/plain"(), sys))
        # F2-11: lowered. The sites of the border cell after the last sweep hold 5.0
        σ = zeros(Int32, 8, 8); σ[1, :] .= 1
        op = [ownership => σ, kind => [:border]]
        u = solve(PottsProblem(sys, op, (0, 2); field_solver = ExplicitEuler(substeps = 1)), SequentialCPM()).u[end]
        a, own = u.site.c, Array(u.σ) .== 1
        @test any(own) && all(a[own] .== 5.0) && maximum(a) == 5.0
        @test any(!=(0.0), a[.!own]) && all(a[.!own] .!= 5.0)
        @test any(b -> occursin("masked", string(b)), getfield(Potts.fields(sys), :bcs))
        @test isempty(Potts.getfield(Potts.getfield(WLiteBcs(; name = :n, with_bcs = false), :part), :bcs))
    end
end

@testitem "W-lite: a hand-built inner System with other values or extra statements is refused" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite: a hand-built inner System with other values or extra statements is refused" begin
        g = WLiteGuard(; name = :g)
        part = Potts.getfield(g, :part)
        m = WL_MTKB.getmetadata(Potts.inner(g), Potts._BuiltFrom, nothing)
        @test m[1] === part && m[2][] === Potts.inner(g)                       # the identity path
        ref = Potts._inner_system(Potts._staged(:g, part))
        x = only(filter(v -> occursin("x", string(v)), unknowns(ref)))
        λ = only(filter(v -> string(v) == "λ", parameters(ref)))
        @variables z(Potts.t)
        rebuilt(; kw...) = System(
            equations(ref), Potts.t, unknowns(ref), parameters(ref); name = :g,
            observed = observed(ref), initialization_eqs = WL_MTKB.initialization_equations(ref), kw...
        )
        c9(f) = try
            f()
            false
        catch e
            e isa ArgumentError && occursin("payload cannot build", sprint(showerror, e))
        end
        @test mtkcompile(Potts.wrap(:g, rebuilt(), nothing, part)) isa CompiledPottsSystem
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; initialization_eqs = [x ~ 9.0]), nothing, part)))
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; initial_conditions = Dict(x => 7.0, λ => 5.0)), nothing, part)))
        @test c9(() -> mtkcompile(Potts.wrap(:g, rebuilt(; observed = [unwrap(z) ~ 2 * x]), nothing, part)))
        @test c9(() -> Potts.extend(g, Potts.wrap(:g, rebuilt(; initialization_eqs = [x ~ 9.0]), nothing, part)))
        @variables yd(Potts.t)
        dsys = System([WL_MTKB.Differential(Potts.t)(yd) ~ -yd], Potts.t; name = :dsys)
        par = WL_MTKB.get_parent(Potts.inner(g))
        for derived in (complete(WL_MTKB.extend(dsys, par; name = :g)), complete(WL_MTKB.extend(par, dsys)))
            @test WL_MTKB.getmetadata(derived, Potts._BuiltFrom, nothing) !== nothing
            msg = try
                mtkcompile(Potts.wrap(:g, derived, nothing, part))
                "built"
            catch e
                sprint(showerror, e)
            end
            @test occursin("payload cannot build", msg) && occursin("yd", msg)
        end
        composed = complete(WL_MTKB.compose(WL_MTKB.toggle_namespacing(par, true), [dsys]))
        @test WL_MTKB.getmetadata(composed, Potts._BuiltFrom, nothing) !== nothing
        c = mtkcompile(Potts.wrap(:g, composed, nothing, part))
        @test c isa CompiledPottsSystem && any(v -> occursin("dsys₊yd", string(v)), unknowns(c.sys))
    end
end

@testitem "W-lite C9: Potts.compose results compile, solve and extend" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite C9: Potts.compose results compile, solve and extend" begin
        part = WLiteModels.part
        wdec = Potts.wrap(:decay, WLiteC9.decay(), nothing, part())
        W = Potts.compose(WLiteGuard(; name = :g), wdec)
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W))
        c = mtkcompile(W)
        @test c isa CompiledPottsSystem
        σ = zeros(Int32, 8, 8); σ[2:4, 2:4] .= 1
        p = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        @test :decay₊yd in propertynames(p.u0.model) && :decay₊kd in propertynames(p.p)
        rk4(h) = 1 - h + h^2 / 2 - h^3 / 6 + h^4 / 24
        u = solve(p, SequentialCPM()).u[end]
        @test u.model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1.0e-12
        @test u.model.decay₊yd[1] ≈ 2.0 * exp(-0.3 * 10) rtol = 1.0e-5
        @test u.model.x[1] ≈ rk4(2.0 / 4)^40 rtol = 1.0e-12
        p0 = PottsProblem(WLiteGuard(; name = :g), [Potts.ownership => σ, Potts.kind => [1]], (0, 1))
        @test !(:decay₊yd in propertynames(p0.u0.model))
        w2 = Potts.wrap(:inner2, WLiteC9.inner2(), nothing, part())
        Wn = Potts.compose(W, w2)
        pn = PottsProblem(Wn, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        un = solve(pn, SequentialCPM()).u[end]
        @test un.model.decay₊yd[1] ≈ u.model.decay₊yd[1] rtol = 1.0e-12
        @test un.model.inner2₊zz[1] ≈ rk4(0.1 / 4)^40 rtol = 1.0e-12
        Wd = Potts.compose(WLiteGuard(; name = :g), Potts.compose(wdec, w2))
        @test any(isequal(unwrap(Wd.decay.inner2.zz)), unknowns(Wd))
        pd = PottsProblem(Wd, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
        @test solve(pd, SequentialCPM()).u[end].model.decay₊inner2₊zz[1] ≈ rk4(0.1 / 4)^40 rtol = 1.0e-12
        pk = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1], W.decay.yd => 5.0], (0, 1))
        @test pk.u0.model.decay₊yd[1] == 5.0
        @test occursin(
            "per cell", sprint(
                showerror, try
                    mtkcompile(Potts.compose(WLiteGuard(; name = :g), WLiteC9Cell(; name = :cc)))
                catch e
                    e
                end
            )
        )
        for E in (Potts.extend(WLiteGuard(; name = :g), W), Potts.extend(W, WLiteGuard(; name = :g)))
            pe = PottsProblem(E, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4))
            @test :decay₊kd in propertynames(pe.p) && pe.p.decay₊kd == 0.3
            @test solve(pe, SequentialCPM()).u[end].model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1.0e-12
        end
    end
end

@testitem "W-lite C9: composed content that cannot be compiled is refused by name" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "W-lite C9: composed content that cannot be compiled is refused by name" begin
        part = WLiteModels.part
        M = WL_MTKB
        msg(f) = try
            f()
            "built"
        catch e
            e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
        end
        g = WLiteGuard(; name = :g)
        wdec = Potts.wrap(:decay, WLiteC9.decay(), nothing, part())
        @test occursin("@components", msg(() -> Potts.compose(g, WLiteC9PerCellComp(; name = :pc))))
        @test msg(() -> mtkcompile(Potts.compose(g, wdec))) == "built"
        @test occursin("kind table", msg(() -> mtkcompile(Potts.compose(g, WLiteC9Table(; name = :tab)))))
        W = Potts.compose(g, wdec)
        @test occursin("already has a component named `decay`", msg(() -> Potts.compose(W, wdec)))
        @test occursin("already has a component named `decay`", msg(() -> Potts.compose(WLiteC9ModelComp(; name = :mc), wdec)))
        two = msg(
            () -> mtkcompile(
                Potts.wrap(
                    :g, complete(
                        M.compose(
                            M.toggle_namespacing(M.get_parent(Potts.inner(g)), true),
                            [WLiteC9.decay(), WLiteC9.decay()]
                        )
                    ), nothing, Potts.getfield(g, :part)
                )
            )
        )
        @test occursin("two components named `decay`", two)
        dec = WLiteC9.decay()
        yd = dec.yd
        with(; kw...) = Potts.wrap(:h, System(Potts.Equation[], Potts.t; name = :h, systems = [WLiteC9.decay()], kw...), nothing, part())
        @test msg(() -> mtkcompile(with())) == "built"
        @test occursin("continuous events", msg(() -> mtkcompile(with(; continuous_events = [[yd ~ 1.0] => [yd ~ M.Pre(yd) + 1.0]]))))
        @test occursin("discrete events", msg(() -> mtkcompile(with(; discrete_events = [1.0 => [yd ~ M.Pre(yd) + 1.0]]))))
        @test occursin("tstops", msg(() -> mtkcompile(with(; tstops = [0.5]))))
        par = M.get_parent(Potts.inner(g))
        xg = only(filter(v -> occursin("x", string(v)), unknowns(Potts.inner(g))))
        ev = System(Potts.Equation[], Potts.t; name = :ev, discrete_events = [1.0 => [xg ~ M.Pre(xg) + 1.0]])
        @test occursin(
            "discrete events", msg(
                () -> mtkcompile(
                    Potts.wrap(
                        :g, complete(M.extend(ev, par; name = :g)), nothing,
                        Potts.getfield(g, :part)
                    )
                )
            )
        )
        @test occursin("costs", msg(() -> mtkcompile(with(; costs = [2.0]))))
        for (f, what) in (
                (WLiteC9Neg.noisy, "noise equations"), (WLiteC9Neg.constrained, "constraints"),
                (WLiteC9Neg.costly, "costs"), (WLiteC9Neg.poisson, "poissonians"),
            )
            top = msg(() -> mtkcompile(Potts.wrap(:h, f(:h; systems = [WLiteC9.decay()]), nothing, part())))
            comp = msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:hz, f(:hz), nothing, part()))))
            @test occursin(what, top)
            @test occursin(what, comp)
            occursin(what, top) && occursin(what, comp) || @info "C9 guard" what top comp
        end
        @test_throws MethodError Potts.wrap(:x, 1.0, nothing, part())
        @test occursin(
            "the PDESystem `decay` spans `x ∈ [0, 1]`, but axis 1 of the lattice of `g` spans [0, 8]",
            msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), WLiteModels.pde(:decay), part())))
        )
        @test occursin(
            "the PDESystem `h` spans `x ∈ [0, 1]`", msg(
                () -> mtkcompile(
                    Potts.wrap(
                        :h, System(
                            Potts.Equation[], Potts.t;
                            name = :h, systems = [WLiteC9.decay()]
                        ), WLiteModels.pde(:h), part()
                    )
                )
            )
        )
        fsys = mtkcompile(WLiteC9Field(; name = :wf)).sys
        @test Potts.fields(fsys) !== nothing
        @test msg(() -> mtkcompile(Potts.compose(fsys, Potts.wrap(:decay, WLiteC9.decay(), nothing, part())))) == "built"
        @test occursin(
            "has the kinds", msg(
                () -> Potts.compose(
                    g, Potts.wrap(
                        :decay, WLiteC9.decay(), nothing,
                        part(; kinds = [:medium, :ka, :kb])
                    )
                )
            )
        )
        @test occursin("has the kinds", msg(() -> Potts.compose(g, WLiteC9FoldOther(; name = :pf))))
        @test occursin(
            "another lattice", msg(
                () -> Potts.compose(
                    g, Potts.wrap(
                        :decay, WLiteC9.decay(), nothing,
                        part(; lattice = Potts.lattice_spec((6, 6)))
                    )
                )
            )
        )
        @test occursin("population fold", msg(() -> mtkcompile(Potts.compose(g, WLiteC9FoldSame(; name = :pf)))))
        pc = WLiteC9PerCellComp(; name = :pc)
        hand = Potts.wrap(
            :g, complete(
                M.compose(
                    M.toggle_namespacing(M.get_parent(Potts.inner(g)), true),
                    [M.toggle_namespacing(M.get_parent(Potts.inner(pc)), true)]
                )
            ), nothing, Potts.getfield(g, :part)
        )
        @test occursin("@components", msg(() -> mtkcompile(hand)))
        @test occursin("has a quantity named `x`", msg(() -> Potts.compose(g, Potts.wrap(:x, WLiteC9Neg.xsys(), nothing, part()))))
        @test occursin("has the input", msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:vv, WLiteC9Neg.vsys(), nothing, part())))))
        @test occursin("has the input", msg(() -> mtkcompile(Potts.compose(g, Potts.wrap(:cell, WLiteCompose.cell(), nothing, part())))))
    end
end

@testitem "F4-10: Potts.component composes an MTK System into a model with an energy" setup = [WliteSetup] tags = [:potts, :wlite] begin
    @testset "F4-10: Potts.component composes an MTK System into a model with an energy" begin
        msg(f) = try
            f()
            "built"
        catch e
            e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
        end
        m = WLiteF410(; name = :m)
        @test !isempty(Potts.hamiltonian(m))
        comp = Potts.component(:decay, WLiteC9.decay(), m)
        @test isempty(Potts.hamiltonian(comp)) && Potts.lattice(comp) == Potts.lattice(m)
        W = Potts.compose(m, comp)
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W)) && !isempty(Potts.hamiltonian(W))
        σ = zeros(Int32, 8, 8); σ[2:4, 2:4] .= 1
        p = PottsProblem(W, [Potts.ownership => σ, Potts.kind => [1]], (0, 10); ode_solver = RK4(substeps = 4), seed = 2)
        sol = solve(p, SequentialCPM())
        rk4(h) = 1 - h + h^2 / 2 - h^3 / 6 + h^4 / 24
        @test sol.u[end].model.decay₊yd[1] ≈ 2.0 * rk4(0.3 / 4)^40 rtol = 1.0e-12
        @test sol.u[end].model.x[1] ≈ rk4(2.0 / 4)^40 rtol = 1.0e-12
        @test sol.u[end].σ != σ
        old = msg(() -> Potts.compose(m, Potts.wrap(:decay, WLiteC9.decay(), nothing, Potts.part(m))))
        @test occursin("has energies", old) && occursin("Potts.component(:decay, system, model)", old)
        part = WLiteModels.part
        g = WLiteGuard(; name = :g)
        kinds = msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing, part(; kinds = [:medium, :ka]))))
        lat = msg(() -> Potts.compose(g, Potts.wrap(:decay, WLiteC9.decay(), nothing, part(; lattice = Potts.lattice_spec((6, 6))))))
        @test occursin("has the kinds", kinds) && occursin("Potts.component(name, system, model)", kinds)
        @test occursin("another lattice", lat) && occursin("Potts.component(name, system, model)", lat)
        @test occursin("must agree", msg(() -> Potts.component(:other, WLiteC9.decay(), m)))
    end
end
