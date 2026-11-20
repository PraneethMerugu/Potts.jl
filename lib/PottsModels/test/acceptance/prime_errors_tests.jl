# `x′` (the value at the pair's other
# site) exists only for site and field variables. Writing `m′` for a cell or model variable
# `m` is a Potts error that names `m′` and says "primes exist only for site/field
# variables", wherever the expression is written; it is not a bare `UndefVarError`. A
# programmatically built `PottsSystem` that declares a quantity `c′` next to a site
# variable `c` is rejected at construction, as `@potts_model` and `@extend` already do.
#
# A rejection may surface while the macro expands (Julia wraps it in a `LoadError`) or
# while the constructor or `mtkcompile` runs; `rejection` unwraps a `LoadError` and
# then requires an `ArgumentError`.

@testsetup module PrimeErrorsSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
const PHRASE = "primes exist only for site/field variables"
"""A two-kind model with a cell variable `m`, a model variable `g`, a site variable `c`, a
field `u` and the extra statements `stmts`, built by `eval` of the macro and compiled."""
function prime_model(stmts...)
    ex = quote
        @potts_model Model begin
            @kinds medium A
            @parameters J[kind, kind] = [0 4; 4 2]
            @variables begin
                m(cell) = 1.0
                g(model) = 0.0
                c(site) = 0.0
                u(field) = 0.0
            end
            @lattice Lattice((10, 10))
            @energy cells => (volume - 9.0)^2
            $(stmts...)
            @sweep Metropolis(; temperature = 1.0)
        end
        Model(; name = :prime_errors)
    end
    return Base.invokelatest(eval, ex)
end
"""`:ok` if `f()` throws an `ArgumentError` (possibly inside a macro-expansion `LoadError`)
whose message contains every one of `words`; otherwise a description of what happened."""
function rejection(f, words...)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa Union{ArgumentError, Potts.PottsCompileError} || return "not an ArgumentError or PottsCompileError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        isempty(words) || occursin(first(words), sprint(showerror, e)) || return "message does not contain $(first(words))"
        return :ok
    end
    return "accepted silently"
end
# a field `w` with `D(w) ~ src − w`, a plain MTK PDESystem on the 10 × 10 lattice; its input
# `src` is bound at `@fields` (where `m′` is written)
function field_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables w(..) src(..) [input = true]
    W = w(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(W) ~ src(t, x, y) - W], [w(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), (10, 10)), [t, x, y], [W, src(t, x, y)], Any[]; name = :prime_field
    )
end
const ONE = (s = zeros(Int32, 10, 10); s[3:5, 3:5] .= 1; s)
"""Positive control: the model compiles, builds a problem and runs a few MCS."""
function prime_runs(m)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, [ownership => ONE, kind => [:A]], (0, 3))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "prime errors: primes of non-site variables" setup = [PrimeErrorsSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "prime errors: primes of non-site variables" begin
        @testset "`m′` of a cell variable is rejected where it is written ($where)" for (where, stmt) in [
                "contact energy" => :(@energy contacts => J[kind, neighbor_kind] + m′),
                "cell energy" => :(@energy cells(A) => m′ * volume),
                "drive" => :(@drive copy => m′),
                "constraint" => :(@constraint cells(A) => m′ < 2),
                "update" => :(@after_mcs m ~ m′ + 1),
                "on-copy update" => :(@on_copy c ~ m′),
                "field input binding" => :(@fields field_pde() (:src => m′)),
                "observed" => :(@observed q ~ m′),
            ]
            @test rejection(() -> mtkcompile(prime_model(stmt)), "m′", PHRASE) === :ok
        end

        @testset "`g′` of a model variable is rejected" begin
            @test rejection(
                () -> mtkcompile(prime_model(:(@energy contacts => J[kind, neighbor_kind] + g′))),
                "g′", PHRASE
            ) === :ok
            @test rejection(() -> mtkcompile(prime_model(:(@after_mcs g ~ g′ + 1))), "g′", PHRASE) === :ok
        end

        @testset "a programmatic PottsSystem may not declare `c′` next to a site variable `c`" begin
            base = prime_model()
            t = Potts.t
            # a cell variable named `c′`
            cprime = Potts.variable(only(Potts.Symbolics.@variables c′(t)), :cell)
            @test rejection("c′") do
                sys = PottsSystem(;
                    name = :prog, kinds = getfield(getfield(base, :part), :kinds), lattice = Potts.lattice(base),
                    parameters = Potts.declared_parameters(base), variables = [Potts.declared_variables(base); cprime],
                    energies = getfield(getfield(base, :part), :energies), sweep = getfield(getfield(base, :part), :sweep)
                )
                mtkcompile(sys)
            end === :ok
            # a parameter named `c′`
            pprime = Potts.parameter(Symbol("c′"), 1.0)
            @test rejection("c′") do
                sys = PottsSystem(;
                    name = :prog, kinds = getfield(getfield(base, :part), :kinds), lattice = Potts.lattice(base),
                    parameters = [Potts.declared_parameters(base); pprime], variables = Potts.declared_variables(base),
                    energies = getfield(getfield(base, :part), :energies), sweep = getfield(getfield(base, :part), :sweep)
                )
                mtkcompile(sys)
            end === :ok
            # control: the same programmatic rebuild without the clash builds and runs
            ok = PottsSystem(;
                name = :prog, kinds = getfield(getfield(base, :part), :kinds), lattice = Potts.lattice(base),
                parameters = Potts.declared_parameters(base), variables = Potts.declared_variables(base),
                energies = getfield(getfield(base, :part), :energies), sweep = getfield(getfield(base, :part), :sweep)
            )
            @test prime_runs(ok)
        end

        @testset "`@potts_model` rejects a declared `c′` next to a site variable `c`" begin
            @test rejection(() -> prime_model(:(@variables c′(cell) = 0.0)), "c′") === :ok
        end

        @testset "negative controls" begin
            # D-061: `c′` of a site variable in a contact energy still builds and runs
            @test prime_runs(prime_model(:(@energy contacts => J[kind, neighbor_kind] + (c + c′) / 2)))
            # an unprimed cell variable still works in energies and updates
            @test prime_runs(prime_model(:(@energy cells(A) => 0.1 * m * volume)))
            @test prime_runs(prime_model(:(@after_mcs m ~ m + 1)))
            # a primed site variable outside a contact term keeps its own (existing) error
            @test rejection(() -> mtkcompile(prime_model(:(@energy cells(A) => c′)))) === :ok
        end
    end
end
