# P6.0al (ROADMAP Phase 6, step 0; P6.0ab review): one name, one category. A model's names
# live in one namespace: a kind, parameter (scalar or vector), variable (any scope), observed
# quantity, relation or component is declared under one category only. `@potts_model`
# already rejects a second declaration within one model (`_declare!`); `@extend` and
# `extend` merged by name only within each category, so a base parameter `x` and an
# extension variable `x(cell)` coexisted (`observe(sol, :x)` the variable, `lookup(sys, :x)`
# the parameter). Such a model is now rejected when the `PottsSystem` is built, with an
# `ArgumentError` naming the name and both categories. A component's namespaced quantities
# (`clk₊yy`) are names too: a declaration of one is rejected by the time the model compiles.
# Redeclaring a name in its own category stays an override (the extension wins). Frozen
# (AUTONOMY §7.2).
const P60AL_MTKB = Potts.ModelingToolkitBase

"""`:ok` if `f()` throws an `ArgumentError` (possibly inside `LoadError`s) whose message
contains every one of `words`; otherwise a description of what happened."""
function p60al_rejection(f, words...)
    try
        f()
    catch e
        while e isa LoadError
            e = e.error
        end
        e isa ArgumentError || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        msg = sprint(showerror, e)
        all(w -> occursin(w, msg), words) || return "message does not name $(words): $(first(msg, 400))"
        return :ok
    end
    return "accepted silently"
end

# the component of the component cases: `yy` decays at rate `kk` (passed through a global
# slot, as `@components` resolves its system in module scope)
const P60AL_SYSTEM = Ref{Any}(nothing)
function p60al_component()
    t = Potts.t
    yy = only(P60AL_MTKB.@variables yy(t) = 1.0)
    kk = only(P60AL_MTKB.@parameters kk = 0.3)
    return P60AL_MTKB.System([Potts.D(yy) ~ -kk * yy], t; name = :comp)
end
P60AL_SYSTEM[] = p60al_component()

@potts_model P60alBase begin
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
@potts_model P60alVarGain begin
    @kinds medium host
    @variables gain(cell) = 5.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model P60alCompBase begin
    @kinds medium host
    @components cells(host) clk = P60AL_SYSTEM[]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end

"""The model `P60alExt` with the statements `stmts` (its `@extend` lines among them), built."""
function p60al_model(stmts::Expr)
    Base.invokelatest(eval, quote
        @potts_model P60alExt begin
            $(stmts.args...)
        end
    end)
    return Base.invokelatest(() -> getfield(Main, :P60alExt)(; name = :ext))
end
"""A one-model build (no `@extend`): `stmts` plus a lattice, energy and sweep."""
p60al_single(stmts::Expr) = p60al_model(quote
    $(stmts.args...)
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end)

const P60AL_ONE = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
"""Positive control: compiles, builds a problem and runs one MCS."""
function p60al_runs(m)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, [ownership => P60AL_ONE, kind => [:host]], (0, 1))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end
p60al_count(xs, n) = count(x -> Potts.info(x).name === n, xs)
p60al_find(xs, n) = only(filter(x -> Potts.info(x).name === n, xs))

@testset "P6.0al one name, one category" begin
    @testset "within one model: @potts_model rejects a second category (already today)" begin
        @test p60al_rejection(() -> p60al_single(quote
            @kinds medium host; @parameters gain = 1.0; @variables gain(cell) = 0.0 end), "gain", "parameter", "variable") === :ok
        @test p60al_rejection(() -> p60al_single(quote
            @kinds medium host; @parameters host = 1.0 end), "host", "kind", "parameter") === :ok
        @test p60al_rejection(() -> p60al_single(quote
            @kinds medium host; @parameters total = 1.0; @observed total ~ sum(volume for n in cells) end),
            "total", "parameter", "observed") === :ok
        @test p60al_rejection(() -> p60al_single(quote
            @kinds medium host; @components cells(host) clk = P60AL_SYSTEM[]; @parameters clk = 1.0 end),
            "clk", "component", "parameter") === :ok
        @test p60al_rejection(() -> p60al_single(quote @kinds medium host; @parameters volume = 1.0 end), "volume") === :ok
    end

    @testset "a component's namespaced quantities are names too" begin
        # `clk₊yy` is the component's state; a parameter of that name is rejected by compile time
        @test p60al_rejection(() -> mtkcompile(p60al_single(quote
            @kinds medium host; @components cells(host) clk = P60AL_SYSTEM[]; @parameters clk₊yy = 2.0 end)),
            "clk₊yy", "component", "parameter") === :ok
        @test p60al_rejection(() -> mtkcompile(p60al_model(quote
            @extend P60alCompBase(); @parameters clk₊yy = 2.0 end)), "clk₊yy", "component", "parameter") === :ok
    end

    @testset "through @extend: base category vs extension category" begin
        ext(stmts, words...) = p60al_rejection(() -> p60al_model(stmts), words...)
        # the P6.0ab review repro: base parameter, extension cell variable
        @test ext(quote @extend P60alBase(); @variables gain(cell) = 5.0 end, "gain", "parameter", "variable") === :ok
        @test ext(quote @extend P60alBase(); @variables gain(site) = 5.0 end, "gain", "parameter", "variable") === :ok
        # and the reverse
        @test ext(quote @extend P60alBase(); @parameters level = 5.0 end, "level", "variable", "parameter") === :ok
        # observed quantities
        @test ext(quote @extend P60alBase(); @observed gain ~ sum(volume for n in cells) end, "gain", "parameter", "observed") === :ok
        @test ext(quote @extend P60alBase(); @parameters total = 5.0 end, "total", "observed", "parameter") === :ok
        @test ext(quote @extend P60alBase(); @variables total(cell) = 0.0 end, "total", "observed", "variable") === :ok
        # kinds (inherited, or added by the extension)
        @test ext(quote @extend P60alBase(); @parameters host = 5.0 end, "host", "kind", "parameter") === :ok
        @test ext(quote @extend P60alBase(); @kinds medium host gain end, "gain", "kind", "parameter") === :ok
        # relations, vector quantities, components
        @test ext(quote @extend P60alBase(); @parameters reach = 5.0 end, "reach", "relation", "parameter") === :ok
        @test ext(quote @extend P60alBase(); @variables bias(cell) = 0.0 end, "bias", "parameter", "variable") === :ok
        @test ext(quote @extend P60alCompBase(); @parameters clk = 5.0 end, "clk", "component", "parameter") === :ok
        # a name bound by `@extend names = base = …` keeps its category
        @test ext(quote @extend λ = base = P60alBase(); @variables λ(cell) = 2.0 end, "λ", "parameter", "variable") === :ok
        # two bases that disagree
        @test ext(quote @extend b1 = P60alBase(); @extend b2 = P60alVarGain() end, "gain", "parameter", "variable") === :ok
        @test ext(quote @extend b2 = P60alVarGain(); @extend b1 = P60alBase() end, "gain", "parameter", "variable") === :ok
    end

    @testset "programmatic builds: extend and PottsSystem" begin
        base = P60alBase(; name = :b)
        var = P60alVarGain(; name = :v)
        @test p60al_rejection(() -> P60AL_MTKB.extend(var, base), "gain", "parameter", "variable") === :ok
        @test p60al_rejection(() -> P60AL_MTKB.extend(base, var), "gain", "parameter", "variable") === :ok
        @test p60al_rejection(() -> Potts.PottsSystem(; name = :p, kinds = base.kinds, lattice = base.lattice,
            sweep = base.sweep, parameters = Any[base.parameters...], variables = Any[var.variables...]),
            "gain", "parameter", "variable") === :ok
        # control: the same parts without the clash
        @test Potts.PottsSystem(; name = :p, kinds = base.kinds, lattice = base.lattice, sweep = base.sweep,
            parameters = Any[filter(p -> Potts.info(p).name !== :gain, base.parameters)...],
            variables = Any[var.variables...]) isa Potts.PottsSystem
        @test P60AL_MTKB.extend(P60alBase(; name = :b2), base) isa Potts.PottsSystem
    end

    @testset "controls: a redeclaration in its own category is an override" begin
        m = p60al_model(quote @extend P60alBase(); @parameters λ = 3.0 end)
        @test p60al_count(m.parameters, :λ) == 1 && Potts.info(p60al_find(m.parameters, :λ)).default == 3.0
        @test p60al_runs(m)
        m = p60al_model(quote @extend P60alBase(); @variables level(cell) = 2.0 end)
        @test p60al_count(m.variables, :level) == 1 && Potts.info(p60al_find(m.variables, :level)).default == 2.0
        @test p60al_runs(m)
        m = p60al_model(quote @extend P60alBase(); @observed total ~ 2.0 * sum(volume for n in cells) end)
        @test count(o -> Potts.info(o.var).name === :total, m.observed) == 1
        m = p60al_model(quote @extend P60alBase(); @kinds medium host extra end)
        @test m.kinds == [:medium, :host, :extra]
        m = p60al_model(quote @extend P60alBase(); @relations reach = Moore(1) end)
        @test m.relations[:reach] == Moore(1)
        m = p60al_model(quote @extend b1 = P60alBase(); @extend b2 = P60alBase() end)
        @test p60al_count(m.parameters, :gain) == 1
        m = p60al_model(quote @extend P60alCompBase(); @parameters rate = 1.0 end)
        @test p60al_runs(m)
        # the repro, renamed: the variable and the parameter both reachable by their own names
        m = p60al_model(quote @extend P60alBase(); @variables gain_level(cell) = 5.0 end)
        @test Potts.info(Potts.lookup(m, :gain)).role !== :cell && Potts.info(Potts.lookup(m, :gain_level)).role === :cell
        prob = PottsProblem(m, [ownership => P60AL_ONE, kind => [:host]], (0, 2))
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 1)
        @test all(v -> v == [5.0], observe(sol, :gain_level))
    end

    @testset "controls: every PottsModels system still builds and compiles" begin
        for sys in (GranerGlazier(; name = :gg), WortelAct(; name = :act), MerksVasculogenesis(; name = :merks),
                    OpenVTGrowingMonolayer(; name = :openvt), SingleDivisionFixture(; name = :fixture),
                    AkeebInvasion(; name = :akeeb))
            @test mtkcompile(sys) isa CompiledPottsSystem
        end
    end
end
