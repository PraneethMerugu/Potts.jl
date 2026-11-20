# The container around MTK's System that a `PottsSystem` is: read access, show, property forwarding, SII,
# refusal matrix, negative control, 18-method boundary, piracy, and getfield behavioral check.

@testitem "system container: read access" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: read access" begin
        W, I, R = W_all, Potts.inner(W_all), complete(inner_all)
        @test W isa WL_MTKB.AbstractSystem && iscomplete(I) && iscomplete(W)     # complete, as its inner
        @test isequal(equations(W), equations(I))                                # A1
        @test isequal(unknowns(W), unknowns(I))                                  # A2
        @test isequal(parameters(W), parameters(I))                              # A3
        @test isequal(observed(W), observed(I))                                  # A4
        @test isequal(Dict(initial_conditions(W)), Dict(initial_conditions(I)))  # A5
        @test isequal(Dict(bindings(W)), Dict(bindings(I)))                      # A6
        @test issetequal(unknowns(W), unknowns(R))                               # A7
        @test issetequal(parameters(W), parameters(R))                           # A8
        @test string(initial_conditions(W)[unwrap(W.xv)]) == "2.0"               # A9
        @test nameof(W) === :allparts                                            # A10
    end
end

@testitem "system container: show" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: show" begin
        s = sprint(show, MIME"text/plain"(), W_all)
        @test occursin("PottsSystem allparts", s) && occursin("fields: PDESystem", s) && occursin("decay₊yd", s)
        @test !occursin("fields:", sprint(show, MIME"text/plain"(), W_empty))
        @test !isempty(sprint(show, W_all)) && !isempty(string(W_all))
        @test !isempty(sprint(print, W_all))
    end
end

@testitem "system container: sys.x" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: sys.x" begin
        W, I = W_all, Potts.inner(W_all)
        @test isequal(W.xv, xv) && isequal(W.a, a)                                       # C1, C2
        @test any(isequal(unwrap(W.decay.yd)), unknowns(W))                              # C3
        @test container_agree(s -> getproperty(s, Symbol("decay₊yd")), W, I)                    # C4
        @test any(isequal(unwrap(W.decay.kd)), parameters(W))                            # C5
        @test_throws ArgumentError W.nope                                                # C6
        @test isequal(W.t, Potts.t)                                                      # C7
    end
end

@testitem "system container: SymbolicIndexingInterface" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: SymbolicIndexingInterface" begin
        W, I = W_all, Potts.inner(W_all)
        uks, pps = unknowns(I), parameters(I)
        prob = WL_MTKB.ODEProblem(mtkcompile(I; inputs = [volume]), [volume => 1.0], (0.0, 1.0))
        @test WL_SII.is_time_dependent(W) === true                                                       # D1
        @test isequal(WL_SII.independent_variable_symbols(W), [unwrap(Potts.t)])                         # D2
        @test all(u -> container_agree(s -> WL_SII.is_variable(s, u), W, I), uks) && all(u -> WL_SII.is_variable(W, u), uks)   # D3
        @test all(u -> container_agree(s -> WL_SII.variable_index(s, u), W, I), uks)                            # D4
        @test all(p -> container_agree(s -> WL_SII.is_parameter(s, p), W, I), pps) && all(p -> WL_SII.is_parameter(W, p), pps) # D5
        @test all(p -> container_agree(s -> WL_SII.parameter_index(s, p), W, I), pps)                           # D6
        @test container_agree(WL_SII.variable_symbols, W, I)                                                    # D7
        @test container_agree(WL_SII.parameter_symbols, W, I)                                                   # D8
        @test container_agree(s -> WL_SII.is_observed(s, unwrap(excess)), W, I)                                 # D9
        @test container_agree(s -> Dict(WL_SII.default_values(s)), W, I)                                        # D10
        @test container_agree(WL_SII.all_variable_symbols, W, I)                                                # D11
        @test WL_SII.is_variable(W, W.decay.yd)                                                          # D12
        @test WL_SII.is_independent_variable(W, Potts.t)                                                 # D13
        @test prob[W.xv] == 2.0 && prob.ps[W.a] == 0.1                                                   # D14
        @test prob[W.decay.yd] == 1.0                                                                    # D15
        @test container_agree(s -> WL_SII.getu(s, W.xv)(prob), W, I)                                            # D16
        @test container_agree(s -> WL_SII.getp(s, W.a)(prob), W, I)                                             # D17
        @test all(p -> container_agree(s -> WL_SII.is_timeseries_parameter(s, p), W, I), pps)                   # D18
        @test container_agree(s -> WL_SII.variable_index(s, :xv), W, I)                                         # D19
        @test container_agree(s -> WL_SII.parameter_index(s, :a), W, I)                                         # D20
        @test container_agree(s -> WL_SII.is_parameter(s, WL_SII.parameter_index(I, a)), W, I)                  # D21
        @test container_agree(WL_SII.all_symbols, W, I)                                                         # D22
        @test all(p -> container_agree(s -> WL_SII.timeseries_parameter_index(s, p), W, I), pps)                # D23
        @test container_agree(s -> WL_SII.getu(s, W.xv + 2 * W.a)(prob), W, I)                                  # D24
        @test container_agree(s -> WL_SII.getp(s, 2 * W.a)(prob), W, I)                                         # D25
        # a getter built from the model reads through the problem's own index (the inner System
        # is not the compiled one the problem was built from)
        @test WL_SII.getu(W, [W.xv, W.decay.yd])(prob) == WL_SII.getu(prob, [W.xv, W.decay.yd])(prob)  # D26
        # the five SII methods answer from the inner, not from MTKBase's `::AbstractSystem` methods
        @test WL_SII.parameter_index(W, a) isa WL_MTKB.ParameterIndex                                    # not a plain Int
        @test WL_SII.getp(W, W.a)(prob) == 0.1
    end
end

@testitem "system container: template compile on the inner" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: template compile on the inner" begin
        I = Potts.inner(W_all)
        function du_of(sys)
            p = WL_MTKB.ODEProblem(sys, [volume => 1.0], (0.0, 1.0))
            d = similar(p.u0)
            p.f(d, p.u0, p.p, 0.0)
            return Dict(zip(unknowns(sys), d))
        end
        @test mtkcompile(I; inputs = [volume]) isa System                                                 # E1
        @test isequal(du_of(mtkcompile(I; inputs = [volume])), du_of(mtkcompile(inner_all; inputs = [volume])))   # E2
        @test length(parameters(mtkcompile(I; inputs = [volume]); initial_parameters = true)) ==
            length(parameters(mtkcompile(inner_all; inputs = [volume]); initial_parameters = true))     # E3
    end
end

@testitem "system container: refusal matrix (probe models)" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: refusal matrix (probe models)" begin
        for W in (W_all, W_empty)
            m = RefusalMatrix.matrix(W, decay)
            @test length(m) == 99
            @test isempty(filter(p -> occursin("Problem", first(p)) && last(p) === :BUILT, m))          # F1: no problem builds
            @test all(
                p -> last(p) === :REFUSED, filter(
                    p -> occursin("Problem", first(p)) &&
                        !startswith(first(p), "Initialization"), m
                )
            )
            built = WL_BY_DESIGN_RAW[nameof(W)]
            @test sort(RefusalMatrix.built(m)) == sort(built)                                            # F2
            @test all(l -> Dict(m)[l] === :LOUD, setdiff(WL_LOUD_REQUIRED, built))                     # F3: no hang, loud
            @test RefusalMatrix.tally(m) == Dict(:REFUSED => 80, :LOUD => 19 - length(built), :BUILT => length(built))
            @test_throws Potts.PottsCompileError mtkcompile(W)
        end
    end
end

@testitem "system container: names, strings and symbols after the system are refused" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: names, strings and symbols after the system are refused" begin
        for W in (W_all, W_empty, PottsModels.GranerGlazier(; name = :gg))
            sh = RefusalMatrix.shapes(W)
            @test length(sh) == 16 * 5 * 3 + 2
            bad = filter(p -> last(p) !== :REFUSED, sh)
            isempty(bad) || @info "shapes not refused" bad
            @test isempty(bad)
        end
    end
end

@testitem "system container: refusal matrix on every published model" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: refusal matrix on every published model" begin
        for n in WL_PUBLISHED
            W = getfield(PottsModels, n)(; name = :m)
            m = RefusalMatrix.matrix(W, decay)
            @test RefusalMatrix.tally(m) == Dict(:REFUSED => 80, :LOUD => 19 - length(WL_BY_DESIGN), :BUILT => length(WL_BY_DESIGN))
            @test sort(RefusalMatrix.built(m)) == sort(WL_BY_DESIGN)
            @test mtkcompile(W) isa CompiledPottsSystem
        end
    end
end

@testitem "system container: negative control (refusal loop deleted)" setup = [SystemContainerSetup] tags = [:potts, :system_container, :subprocess] begin
    @testset "system container: negative control (refusal loop deleted)" begin
        out = read(pipeline(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $(joinpath(@__DIR__,
        "system_refusal_negctl.jl"))`, "JULIA_PKG_GC_AUTO" => "false"); stderr = devnull), String)
        lines = filter(startswith("NEGCTL "), split(out, '\n'))
        @test length(lines) == length(WL_PUBLISHED)
        expected = sort(
            vcat(
                [
                    "$n{true}" for n in (
                            :ODEProblem, :NonlinearProblem, :SteadyStateProblem, :DiscreteProblem,
                            :ImplicitDiscreteProblem, :NonlinearLeastSquaresProblem, :LinearProblem, :IntervalNonlinearProblem,
                            :HomotopyProblem,
                        )
                ], ["ODEProblem{true,FullSpecialize}"]
            )
        )
        for l in lines
            _, model, nbuilt, routes... = split(l)
            @test sort(filter(r -> occursin("Problem", r), routes)) == sort(expected)
            @test parse(Int, nbuilt) == 10 + length(WL_BY_DESIGN)
        end
    end
end

@testitem "system container: the owned methods, piracy" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: the owned methods, piracy" begin
        @test isempty(Aqua.Piracy.hunt(Potts))                                                          # G1
        T = PottsSystem
        owned = Method[]
        for m in methodswith(T; supertypes = false)
            f = m.sig isa UnionAll ? Base.unwrap_unionall(m.sig).parameters[1] : m.sig.parameters[1]
            home = f <: Type ? nothing : parentmodule(f.instance)
            (m.module === Potts && home !== Potts && home !== nothing) && push!(owned, m)
        end
        names = sort(
            [
                string(
                    parentmodule(Base.unwrap_unionall(m.sig).parameters[1].instance), '.', m.name, '(',
                    join(string.(Base.unwrap_unionall(m.sig).parameters[3:end]), ", "), ')'
                ) for m in owned
            ]
        )
        plain(s) = replace(s, "Potts." => "")
        @test plain.(names) == sort(
            [
                "Base.convert(PottsSystem)", "Base.getproperty(Symbol)", "Base.propertynames()", "Base.show(MIME{Symbol(\"text/plain\")}, PottsSystem)",
                "Base.show(PottsSystem)", "LatticeFields.Problems.steady_fields()",
                "ModelingToolkitBase.equations()", "ModelingToolkitBase.unknowns()", "ModelingToolkitBase.parameters()",
                "ModelingToolkitBase.observed()", "ModelingToolkitBase.initial_conditions()", "ModelingToolkitBase.bindings()",
                "ModelingToolkitBase.independent_variable()", "ModelingToolkitBase.get_iv()", "ModelingToolkitBase.get_systems()",
                "ModelingToolkitBase.full_equations()", "ModelingToolkitBase.guesses()", "ModelingToolkitBase.inputs()",
                "ModelingToolkitBase.outputs()", "ModelingToolkitBase.iscomplete()", "ModelingToolkitBase.complete()",
                "ModelingToolkitBase.compose(AbstractArray)",
                "SymbolicUtils.getmetadata(DataType, Any)", "SymbolicUtils.hasmetadata(DataType)",
                "SymbolicUtils.setmetadata(DataType, Any)",
                "SymbolicIndexingInterface.symbolic_container()", "SymbolicIndexingInterface.all_symbols()",
                "SymbolicIndexingInterface.parameter_index(Any)", "SymbolicIndexingInterface.parameter_index(Symbol)",
                "SymbolicIndexingInterface.is_parameter(ModelingToolkitBase.ParameterIndex)",
                "SymbolicIndexingInterface.observed(Any)", "SymbolicIndexingInterface.parameter_observed(Any)",
                "SymbolicIndexingInterface.getsym(Any)", "SymbolicIndexingInterface.getp(Any)",
                "SymbolicIndexingInterface.setsym(Any)", "SymbolicIndexingInterface.setp(Any)",
                "ModelingToolkitBase.mtkcompile()", "ModelingToolkitBase.extend(ModelingToolkitBase.AbstractSystem)",
                "ModelingToolkitBase.extend(PottsSystem)", "ModelingToolkitBase.extend(PottsSystem)",
            ]
        )
        @test count(
            n -> !startswith(n, "ModelingToolkitBase.mtkcompile") && !startswith(n, "ModelingToolkitBase.extend") &&
                !startswith(n, "LatticeFields."), names
        ) == 35
        M, S = WL_MTKB, WL_SII
        fs = Any[
            nameof, getproperty, propertynames, show, ndims, M.equations, M.unknowns, M.parameters, M.observed,
            M.initial_conditions, M.bindings, M.get_systems, M.get_eqs, M.get_unknowns, M.get_ps, M.get_observed, M.get_iv,
            M.has_eqs, M.has_ps, M.has_observed, M.independent_variable, M.independent_variables, M.complete, M.extend,
            M.compose, M.toggle_namespacing, M.getvar, M.flatten, M.mtkcompile, M.getmetadata, M.setmetadata, M.hasmetadata,
            S.is_time_dependent, S.symbolic_container, S.parameter_index, S.is_parameter, S.observed, S.parameter_observed,
            S.is_variable, S.variable_index, S.default_values,
        ]
        scanned = [
            m for f in fs for m in methods(f) if m.module === Potts &&
                any(==(PottsSystem), Base.unwrap_unionall(m.sig).parameters)
        ]
        @test length(scanned) == 28 && all(m -> m in owned || m.name === :extend, scanned)
        @test length(RefusalMatrix.refusal_methods()) == 58
        @test isempty(filter(((a, b),) -> a.module === Potts || b.module === Potts, Test.detect_ambiguities(Potts; recursive = true)))
    end
end

@testitem "system container: internal access uses getfield (shadowed inner/part/fields properties)" setup = [SystemContainerSetup] tags = [:potts, :system_container] begin
    @testset "system container: internal access uses getfield (shadowed inner/part/fields properties)" begin
        base = ContainerShadow(; name = :sh)
        comp = Potts.component(:fields, ComposeSys.decay(; name = :fields), base)
        W = compose(base, comp)
        # User properties resolve to the model's quantity / parameter / subsystem, not PottsSystem fields
        @test isequal(unwrap(W.inner), unwrap(base.inner))
        @test isequal(unwrap(W.part), unwrap(base.part))
        @test W.fields isa WL_MTKB.AbstractSystem && any(isequal(unwrap(W.fields.yd)), unknowns(W))
        @test Potts.inner(W) isa WL_MTKB.System && !(W.inner isa WL_MTKB.System)
        @test Potts.part(W) isa Potts.PottsPart && !(W.part isa Potts.PottsPart)
        @test Potts.fields(W) isa WL_MTKB.PDESystem && !(W.fields isa WL_MTKB.PDESystem)
        # compose, wrap, show, compile and solve keep working when those names exist as properties
        cw = mtkcompile(W)
        @test cw isa CompiledPottsSystem
        σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
        prob = PottsProblem(
            cw, [ownership => σ, kind => [1]], (0, 2); ode_solver = Potts.RK4(substeps = 4),
            field_solver = ExplicitEuler()
        )
        @test :inner in propertynames(prob.u0.model) && :fields₊yd in propertynames(prob.u0.model) && :part in propertynames(prob.p)
        sol = solve(prob, SequentialCPM())
        @test sol.u[end].model.inner[1] < 2.0 && sol.u[end].model.fields₊yd[1] < 2.0
        @test !isempty(sprint(show, MIME"text/plain"(), W))
    end
end
