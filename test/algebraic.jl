# Algebraic equations in `@equations` and the ODE templates (`Potts.ode_system`), beside
# the frozen acceptance file p6_0bn_ode_mtkcompile.jl: reads across scopes, components
# beside algebraic variables, `@observed` over them, and the rejections the frozen file
# leaves to the implementer (indexed and lagged reads, `rand()`, division rules, couplings).

const ALG_M = Potts.ModelingToolkitBase
alg_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
alg_op(extra...) = Any[ownership => alg_sigma(), kind => [1, 1], extra...]
alg_names(xs) = Set{Symbol}(Potts.SymbolicIndexingInterface.getname(x) for x in xs)
alg_error(f, words...) = try
    f()
    false
catch err
    err isa ArgumentError && all(w -> occursin(w, sprint(showerror, err)), words)
end

# a cell definition reading a model algebraic variable, which reads a model ODE variable;
# an `@observed` quantity and an update reading the algebraic variables
@potts_model AlgCross begin
    @kinds medium A
    @parameters r = 0.5
    @variables begin
        m(model) = 1.0
        half(model) = 0.0
        x(cell) = 0.0
        drive(cell) = 0.0
        seen(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(m) ~ -r * m
        half ~ m / 2
        D(x) ~ drive - x
        drive ~ half * volume / 16
    end
    @after_mcs seen ~ drive
    @observed twice ~ 2 * drive
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model AlgCrossHand begin
    @kinds medium A
    @parameters r = 0.5
    @variables begin
        m(model) = 1.0
        x(cell) = 0.0
        seen(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(m) ~ -r * m
        D(x) ~ m / 2 * volume / 16 - x
    end
    @after_mcs seen ~ m / 2 * volume / 16
    @sweep Metropolis(; temperature = 1.0)
end

@testset "algebraic equations: reads across scopes, updates and @observed" begin
    c = mtkcompile(AlgCross(; name = :a))
    cell = Potts.ode_system(c, :cell)
    model = Potts.ode_system(c, :model)
    @test alg_names(ALG_M.unknowns(cell)) == Set([:x]) && :drive in alg_names(o.lhs for o in ALG_M.observed(cell))
    @test alg_names(ALG_M.unknowns(model)) == Set([:m]) && :half in alg_names(o.lhs for o in ALG_M.observed(model))
    @test alg_names(ALG_M.parameters(model)) == Set([:r])
    @test :half in alg_names(ALG_M.parameters(cell))                 # the model's variable is an input of the cell's
    @test :volume in alg_names(ALG_M.parameters(cell))
    for solver in (ExplicitEuler(), Potts.RK4(substeps = 2))
        s = solve(PottsProblem(AlgCross(; name = :a), alg_op(), (0, 6); seed = 3, ode_solver = solver), SequentialCPM(); saveat = 1)
        h = solve(PottsProblem(AlgCrossHand(; name = :h), alg_op(), (0, 6); seed = 3, ode_solver = solver), SequentialCPM(); saveat = 1)
        @test [u.σ for u in s.u] == [u.σ for u in h.u]
        @test all(isapprox.(s[:x], h[:x]; rtol = 1e-12)) && all(isapprox.(s[:seen], h[:seen]; rtol = 1e-12))
        @test all(isapprox.(s[:half], s[:m] ./ 2; rtol = 1e-12))
        @test all(isapprox.(s[:twice], 2 .* s[:drive]; rtol = 1e-12))
        @test all(v -> length(v) == 2, s[:drive])                       # one value per cell
    end
end

# components beside algebraic variables; a coupling reading one
using Potts.ModelingToolkitBase: System as AlgSystem
let t = Potts.t
    ALG_M.@variables drug(t) = 0.0
    ALG_M.@parameters dose = 0.0 clearance = 0.2
    global ALG_PK = AlgSystem([Potts.D(drug) ~ dose - clearance * drug], t; name = :pk)
end
@potts_model AlgComponent begin
    @kinds medium A
    @variables begin
        cells_now(model) = 0.0
        w(cell) = 1.0
    end
    @components model pk = ALG_PK
    @equations begin
        cells_now ~ count(true for c in cells)
        pk.dose ~ 0.1 * cells_now
        D(w) ~ -0.1 * w + pk.drug
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model AlgComponentHand begin
    @kinds medium A
    @variables w(cell) = 1.0
    @components model pk = ALG_PK
    @equations begin
        pk.dose ~ 0.1 * count(true for c in cells)
        D(w) ~ -0.1 * w + pk.drug
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "algebraic equations beside components" begin
    c = mtkcompile(AlgComponent(; name = :a))
    @test alg_names(ALG_M.unknowns(Potts.ode_system(c, :cell))) == Set([:w])        # the component is its own system
    @test Potts.ode_system(c, :model) !== nothing
    @test isempty(ALG_M.unknowns(Potts.ode_system(c, :model)))
    s = solve(PottsProblem(AlgComponent(; name = :a), alg_op(), (0, 5); seed = 2), SequentialCPM(); saveat = 1)
    h = solve(PottsProblem(AlgComponentHand(; name = :h), alg_op(), (0, 5); seed = 2), SequentialCPM(); saveat = 1)
    @test s[:pk₊drug] == h[:pk₊drug] && s[:w] == h[:w]
    @test all(==(2.0), s[:cells_now])
end

function alg_model(body)
    m = eval(:(@potts_model _AlgBad begin
        @kinds medium A
        @variables begin
            x(cell) = 1.0
            y(cell) = 0.0
            m(model) = 0.0
            c(field) = 0.0
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 16.0)^2
        $(body.args...)
        @sweep Metropolis(; temperature = 1.0)
    end))
    return Base.invokelatest(m; name = :bad)
end

@testset "algebraic equations: rejections" begin
    ok = alg_model(quote
        @equations begin
            D(x) ~ -y
            y ~ x
        end
    end)
    @test mtkcompile(ok) isa CompiledPottsSystem                                   # control
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations begin
            D(x) ~ -y[3 - id]
            y ~ x
        end
    end)), "algebraic", "`y`", "bare")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ x
        @after_mcs x ~ Pre(y)
    end)), "algebraic", "`y`")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ x * rand()
    end)), "algebraic", "rand()")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ Pre(x)
    end)), "algebraic", "previous")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ x
        @divide cells(A) when = volume > 30, along = RandomPlane(), y => 0.0
    end)), "algebraic", "`y`", "division rule")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ x
        @on_copy y[new] ~ 1.0
    end)), "algebraic", "`y`")
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations m ~ x                                           # a model definition reading a cell variable bare
    end)), "algebraic", "`x`", "bare")
    # a cell definition reads a field over the cell or at a site, not bare
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations y ~ c + x
    end)), "algebraic", "`y`", "`c`", "integral(c)")
    @test mtkcompile(alg_model(quote
        @equations y ~ integral(c) / volume + c[1] + x
    end)) isa CompiledPottsSystem                                                  # control
    # an error about a definition's quantities names the algebraic variable read
    @test alg_error(() -> mtkcompile(alg_model(quote
        @equations begin
            D(m) ~ y
            y ~ 2x
        end
    end)), "algebraic variable", "`y ~")
    # a declared initial value is not used: an error until initial values are supported
    default_model = eval(:(@potts_model _AlgDefault begin
        @kinds medium A
        @variables begin
            x(cell) = 1.0
            y(cell) = 2.0
        end
        @lattice Lattice((12, 8))
        @energy cells => (volume - 16.0)^2
        @equations y ~ x
        @sweep Metropolis(; temperature = 1.0)
    end))
    @test alg_error(() -> mtkcompile(Base.invokelatest(default_model; name = :d)), "`y`", "initial value")
    # input names: a built-in keeps its name; a compound input never takes a declared name
    let s = Potts.ode_system(mtkcompile(alg_model(quote
            @variables input(cell) = 0.0
            @equations D(x) ~ volume + sum(volume[owner[n]] for n in Moore(1)(42)) - input
        end)), :cell)
        ps = alg_names(ALG_M.parameters(s))
        @test :volume in ps && :input in ps && length(ps) == 3
    end
    # an operating-point value for an algebraic variable, by name and by symbol
    @test alg_error(() -> PottsProblem(ok, alg_op(:y => 1.0), (0, 1)), "`y`", "algebraic")
    @test alg_error(() -> PottsProblem(ok, alg_op(complete(ok).y => 1.0), (0, 1)), "`y`")
    @test PottsProblem(ok, alg_op(:x => 2.0), (0, 1)) isa PottsProblem               # control
    # every published-model-free model still compiles without templates
    c = mtkcompile(alg_model(quote end))
    @test Potts.ode_system(c, :cell) === nothing && Potts.ode_system(c, :model) === nothing
end
