# P6.0e2 (ROADMAP Phase 6, step 0; follow-up to D-061): `x′` (the value at the pair's other
# site) exists only for site and field variables. Writing `m′` for a cell or model variable
# `m` is a Potts error that names `m′` and says "primes exist only for site/field
# variables", wherever the expression is written; it is not a bare `UndefVarError`. A
# programmatically built `PottsSystem` that declares a quantity `c′` next to a site
# variable `c` is rejected at construction, as `@potts_model` and `@extend` already do.
# Frozen (AUTONOMY §7.3).
#
# A rejection may surface while the macro expands (Julia wraps it in a `LoadError`) or
# while the constructor or `mtkcompile` runs; `p60e2_rejection` unwraps a `LoadError` and
# then requires an `ArgumentError`.

const P60E2_PHRASE = "primes exist only for site/field variables"

"""A two-kind model with a cell variable `m`, a model variable `g`, a site variable `c`, a
field `u` and the extra statements `stmts`, built by `eval` of the macro and compiled."""
function p60e2_model(stmts...)
    ex = quote
        @potts_model P60e2Model begin
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
        P60e2Model(; name = :p60e2)
    end
    return Base.invokelatest(eval, ex)
end

"""`:ok` if `f()` throws an `ArgumentError` (possibly inside a macro-expansion `LoadError`)
whose message contains every one of `words`; otherwise a description of what happened."""
function p60e2_rejection(f, words...)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        e isa ArgumentError || return "not an ArgumentError: $(typeof(e)): $(first(sprint(showerror, e), 300))"
        msg = sprint(showerror, e)
        all(w -> occursin(w, msg), words) || return "message does not contain $(words): $(first(msg, 400))"
        return :ok
    end
    return "accepted silently"
end

const P60E2_ONE = (s = zeros(Int32, 10, 10); s[3:5, 3:5] .= 1; s)

"""Positive control: the model compiles, builds a problem and runs a few MCS."""
function p60e2_runs(m)
    mtkcompile(m) isa CompiledPottsSystem || return false
    prob = PottsProblem(m, [ownership => P60E2_ONE, kind => [:A]], (0, 3))
    return Symbol(solve(prob, SequentialCPM(; proposal = Moore(1))).retcode) === :Success
end

@testset "P6.0e2: primes of non-site variables" begin
    @testset "`m′` of a cell variable is rejected where it is written ($where)" for (where, stmt) in [
        "contact energy" => :(@energy contacts => J[kind, kind′] + m′),
        "cell energy" => :(@energy cells(A) => m′ * volume),
        "drive" => :(@drive copy => m′),
        "constraint" => :(@constraint cells(A) => m′ < 2),
        "update" => :(@after_mcs m ~ m′ + 1),
        "on-copy update" => :(@on_copy c ~ m′),
        "equation" => :(@equations D(u) ~ m′ - u),
        "observed" => :(@observed q ~ m′),
    ]
        @test p60e2_rejection(() -> mtkcompile(p60e2_model(stmt)), "m′", P60E2_PHRASE) === :ok
    end

    @testset "`g′` of a model variable is rejected" begin
        @test p60e2_rejection(() -> mtkcompile(p60e2_model(:(@energy contacts => J[kind, kind′] + g′))),
            "g′", P60E2_PHRASE) === :ok
        @test p60e2_rejection(() -> mtkcompile(p60e2_model(:(@after_mcs g ~ g′ + 1))), "g′", P60E2_PHRASE) === :ok
    end

    @testset "a programmatic PottsSystem may not declare `c′` next to a site variable `c`" begin
        base = p60e2_model()
        t = Potts.t
        # a cell variable named `c′`
        cprime = Potts.variable(only(Potts.Symbolics.@variables c′(t)), :cell)
        @test p60e2_rejection("c′") do
            sys = PottsSystem(; name = :p60e2prog, kinds = base.kinds, lattice = base.lattice,
                parameters = base.parameters, variables = [base.variables; cprime],
                energies = base.energies, sweep = base.sweep)
            mtkcompile(sys)
        end === :ok
        # a parameter named `c′`
        pprime = Potts.parameter(Symbol("c′"), 1.0)
        @test p60e2_rejection("c′") do
            sys = PottsSystem(; name = :p60e2prog, kinds = base.kinds, lattice = base.lattice,
                parameters = [base.parameters; pprime], variables = base.variables,
                energies = base.energies, sweep = base.sweep)
            mtkcompile(sys)
        end === :ok
        # control: the same programmatic rebuild without the clash builds and runs
        ok = PottsSystem(; name = :p60e2prog, kinds = base.kinds, lattice = base.lattice,
            parameters = base.parameters, variables = base.variables,
            energies = base.energies, sweep = base.sweep)
        @test p60e2_runs(ok)
    end

    @testset "`@potts_model` rejects a declared `c′` next to a site variable `c` (D-061)" begin
        @test p60e2_rejection(() -> p60e2_model(:(@variables c′(cell) = 0.0)), "c′") === :ok
    end

    @testset "negative controls" begin
        # D-061: `c′` of a site variable in a contact energy still builds and runs
        @test p60e2_runs(p60e2_model(:(@energy contacts => J[kind, kind′] + (c + c′) / 2)))
        # an unprimed cell variable still works in energies and updates
        @test p60e2_runs(p60e2_model(:(@energy cells(A) => 0.1 * m * volume)))
        @test p60e2_runs(p60e2_model(:(@after_mcs m ~ m + 1)))
        # a primed site variable outside a contact term keeps its own (existing) error
        @test p60e2_rejection(() -> mtkcompile(p60e2_model(:(@energy cells(A) => c′)))) === :ok
    end
end
