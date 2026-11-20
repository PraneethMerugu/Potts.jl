# one name, one category. A model's names
# live in one namespace: a kind, parameter (scalar or vector), variable (any scope), observed
# quantity, relation or component is declared under one category only. `@potts_model`
# already rejects a second declaration within one model (`_declare!`); `@extend` and
# `extend` merged by name only within each category, so a base parameter `x` and an
# extension variable `x(cell)` coexisted (`observe(sol, :x)` the variable, `lookup(sys, :x)`
# the parameter). Such a model is now rejected when the `PottsSystem` is built, with an
# `ArgumentError` naming the name and both categories. A component's namespaced quantities
# (`clk₊yy`) are names too: a declaration of one is rejected by the time the model compiles.
# Redeclaring a name in its own category stays an override (the extension wins).

@testsetup module NameCategoriesSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
const MTKB = Potts.ModelingToolkitBase
"""`:ok` if `f()` throws an `ArgumentError` (possibly inside `LoadError`s); otherwise a
description of what happened."""
function rejection(f, words...)
    try
        f()
    catch e
        while e isa LoadError
            e = e.error
        end
        e isa Union{ArgumentError, Potts.PottsCompileError} || return "not an ArgumentError or PottsCompileError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        return :ok
    end
    return "accepted silently"
end
# the component of the component cases: `yy` decays at rate `kk` (passed through a global
# slot, as `@components` resolves its system in module scope)
const SYSTEM = Ref{Any}(nothing)
function category_component()
    t = Potts.t
    yy = only(MTKB.@variables yy(t) = 1.0)
    kk = only(MTKB.@parameters kk = 0.3)
    return MTKB.System([Potts.D(yy) ~ -kk * yy], t; name = :comp)
end
SYSTEM[] = category_component()
@potts_model CategoryBase begin
    @kinds medium host
    @parameters begin
        gain = 1.0
        λ = 1.0
        bias[1:2] = [1.0, 2.0]
    end
    @variables level(cell) = 0.0
    @observed total ~ sum(volume for n in cells)
    @relations reach = Moore(2)
    @lattice Lattice((12, 12))
    @energy cells => λ * (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end
# the same kinds, with `gain` a cell variable (a second base, and `extend` by hand)
@potts_model VarGain begin
    @kinds medium host
    @variables gain(cell) = 5.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end
@potts_model CompBase begin
    @kinds medium host
    @components cells(host) clk = SYSTEM[]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end
"""The model `Ext` with the statements `stmts` (its `@extend` lines among them), built."""
function category_model(stmts::Expr)
    Base.invokelatest(
        eval, quote
            @potts_model Ext begin
                $(stmts.args...)
            end
        end
    )
    return Base.invokelatest(() -> getfield(@__MODULE__, :Ext)(; name = :ext))
end
"""A one-model build (no `@extend`): `stmts` plus a lattice, energy and sweep."""
single(stmts::Expr) = category_model(
    quote
        $(stmts.args...)
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 10.0)
    end
)
const ONE = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
"""Positive control: compiles, builds a problem and runs one MCS."""
function category_runs(m)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, [ownership => ONE, kind => [:host]], (0, 1))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end
category_count(xs, n) = count(x -> Potts.info(x).name === n, xs)
find(xs, n) = only(filter(x -> Potts.info(x).name === n, xs))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "name categories one name, one category" setup = [NameCategoriesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "name categories one name, one category" begin
        @testset "within one model: @potts_model rejects a second category (already today)" begin
            @test rejection(
                () -> single(
                    quote
                        @kinds medium host; @parameters gain = 1.0; @variables gain(cell) = 0.0
                    end
                ), "gain", "parameter", "variable"
            ) === :ok
            @test rejection(
                () -> single(
                    quote
                        @kinds medium host; @parameters host = 1.0
                    end
                ), "host", "kind", "parameter"
            ) === :ok
            @test rejection(
                () -> single(
                    quote
                        @kinds medium host; @parameters total = 1.0; @observed total ~ sum(volume for n in cells)
                    end
                ),
                "total", "parameter", "observed"
            ) === :ok
            @test rejection(
                () -> single(
                    quote
                        @kinds medium host; @components cells(host) clk = SYSTEM[]; @parameters clk = 1.0
                    end
                ),
                "clk", "component", "parameter"
            ) === :ok
            @test rejection(
                () -> single(
                    quote
                        @kinds medium host; @parameters volume = 1.0
                    end
                ), "volume"
            ) === :ok
        end

        @testset "a component's namespaced quantities are names too" begin
            # `clk₊yy` is the component's state; a parameter of that name is rejected by compile time
            @test rejection(
                () -> mtkcompile(
                    single(
                        quote
                            @kinds medium host; @components cells(host) clk = SYSTEM[]; @parameters clk₊yy = 2.0
                        end
                    )
                ),
                "clk₊yy", "component", "parameter"
            ) === :ok
            @test rejection(
                () -> mtkcompile(
                    category_model(
                        quote
                            @extend CompBase(); @parameters clk₊yy = 2.0
                        end
                    )
                ), "clk₊yy", "component", "parameter"
            ) === :ok
        end

        @testset "through @extend: base category vs extension category" begin
            ext(stmts, words...) = rejection(() -> category_model(stmts), words...)
            # the `api_defects_tests.jl` review repro: base parameter, extension cell variable
            @test ext(
                quote
                    @extend CategoryBase(); @variables gain(cell) = 5.0
                end, "gain", "parameter", "variable"
            ) === :ok
            @test ext(
                quote
                    @extend CategoryBase(); @variables gain(site) = 5.0
                end, "gain", "parameter", "variable"
            ) === :ok
            # and the reverse
            @test ext(
                quote
                    @extend CategoryBase(); @parameters level = 5.0
                end, "level", "variable", "parameter"
            ) === :ok
            # observed quantities
            @test ext(
                quote
                    @extend CategoryBase(); @observed gain ~ sum(volume for n in cells)
                end, "gain", "parameter", "observed"
            ) === :ok
            @test ext(
                quote
                    @extend CategoryBase(); @parameters total = 5.0
                end, "total", "observed", "parameter"
            ) === :ok
            @test ext(
                quote
                    @extend CategoryBase(); @variables total(cell) = 0.0
                end, "total", "observed", "variable"
            ) === :ok
            # kinds (inherited, or added by the extension)
            @test ext(
                quote
                    @extend CategoryBase(); @parameters host = 5.0
                end, "host", "kind", "parameter"
            ) === :ok
            @test ext(
                quote
                    @extend CategoryBase(); @kinds medium host gain
                end, "gain", "kind", "parameter"
            ) === :ok
            # relations, vector quantities, components
            @test ext(
                quote
                    @extend CategoryBase(); @parameters reach = 5.0
                end, "reach", "relation", "parameter"
            ) === :ok
            @test ext(
                quote
                    @extend CategoryBase(); @variables bias(cell) = 0.0
                end, "bias", "parameter", "variable"
            ) === :ok
            @test ext(
                quote
                    @extend CompBase(); @parameters clk = 5.0
                end, "clk", "component", "parameter"
            ) === :ok
            # a name bound by `@extend names = base = …` keeps its category
            @test ext(
                quote
                    @extend λ = base = CategoryBase(); @variables λ(cell) = 2.0
                end, "λ", "parameter", "variable"
            ) === :ok
            # two bases that disagree
            @test ext(
                quote
                    @extend b1 = CategoryBase(); @extend b2 = VarGain()
                end, "gain", "parameter", "variable"
            ) === :ok
            @test ext(
                quote
                    @extend b2 = VarGain(); @extend b1 = CategoryBase()
                end, "gain", "parameter", "variable"
            ) === :ok
        end

        @testset "programmatic builds: extend and PottsSystem" begin
            base = CategoryBase(; name = :b)
            var = VarGain(; name = :v)
            @test rejection(() -> extend(var, base), "gain", "parameter", "variable") === :ok
            @test rejection(() -> extend(base, var), "gain", "parameter", "variable") === :ok
            @test rejection(
                () -> Potts.PottsSystem(;
                    name = :p, kinds = getfield(getfield(base, :part), :kinds), lattice = Potts.lattice(base),
                    sweep = getfield(getfield(base, :part), :sweep), parameters = Any[Potts.declared_parameters(base)...], variables = Any[Potts.declared_variables(var)...]
                ),
                "gain", "parameter", "variable"
            ) === :ok
            # control: the same parts without the clash
            @test Potts.PottsSystem(;
                name = :p, kinds = getfield(getfield(base, :part), :kinds), lattice = Potts.lattice(base), sweep = getfield(getfield(base, :part), :sweep),
                parameters = Any[filter(p -> Potts.info(p).name !== :gain, Potts.declared_parameters(base))...],
                variables = Any[Potts.declared_variables(var)...]
            ) isa Potts.PottsSystem
            @test extend(CategoryBase(; name = :b2), base) isa Potts.PottsSystem
        end

        @testset "controls: a redeclaration in its own category is an override" begin
            m = category_model(
                quote
                    @extend CategoryBase(); @parameters λ = 3.0
                end
            )
            @test category_count(Potts.declared_parameters(m), :λ) == 1 && Potts.info(find(Potts.declared_parameters(m), :λ)).default == 3.0
            @test category_runs(m)
            m = category_model(
                quote
                    @extend CategoryBase(); @variables level(cell) = 2.0
                end
            )
            @test category_count(Potts.declared_variables(m), :level) == 1 && Potts.info(find(Potts.declared_variables(m), :level)).default == 2.0
            @test category_runs(m)
            m = category_model(
                quote
                    @extend CategoryBase(); @observed total ~ 2.0 * sum(volume for n in cells)
                end
            )
            @test count(o -> Potts.info(o.lhs).name === :total, getfield(getfield(m, :part), :observed)) == 1
            m = category_model(
                quote
                    @extend CategoryBase(); @kinds medium host extra
                end
            )
            @test getfield(getfield(m, :part), :kinds) == [:medium, :host, :extra]
            m = category_model(
                quote
                    @extend CategoryBase(); @relations reach = Moore(1)
                end
            )
            @test getfield(getfield(m, :part), :relations)[:reach] == Moore(1)
            m = category_model(
                quote
                    @extend b1 = CategoryBase(); @extend b2 = CategoryBase()
                end
            )
            @test category_count(Potts.declared_parameters(m), :gain) == 1
            m = category_model(
                quote
                    @extend CompBase(); @parameters rate = 1.0
                end
            )
            @test category_runs(m)
            # the repro, renamed: the variable and the parameter both reachable by their own names
            m = category_model(
                quote
                    @extend CategoryBase(); @variables gain_level(cell) = 5.0
                end
            )
            @test Potts.info(Potts.lookup(m, :gain)).role !== :cell && Potts.info(Potts.lookup(m, :gain_level)).role === :cell
            prob = PottsProblem(m, [ownership => ONE, kind => [:host]], (0, 2))
            sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 1)
            @test all(v -> v == [5.0], observe(sol, :gain_level))
        end

        @testset "controls: every PottsModels system still builds and compiles" begin
            for sys in (
                    GranerGlazier(; name = :gg), WortelAct(; name = :act), MerksVasculogenesis(; name = :merks),
                    OpenVTGrowingMonolayer(; name = :openvt), SingleDivisionFixture(; name = :fixture),
                    AkeebInvasion(; name = :akeeb),
                )
                @test mtkcompile(sys) isa CompiledPottsSystem
            end
        end
    end
end
