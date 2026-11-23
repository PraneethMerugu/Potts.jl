# Kind tables written by kind name: the entry lines `J[k₁, k₂] = v` and one value for
# every entry lower to the array of the matrix form (one path after parsing);
# `remake`, setters and operating points change entries by name; results read as kind
# names (`kind_names`); and the build errors name the table, the entry and the fix.

@testsetup module KindTableSetup
using Potts, Test
using Potts.Layouts

"""The exception `f()` throws (a macro expansion's `LoadError` unwrapped), or `nothing`."""
function kt_error(f)
    try
        f()
    catch e
        return e isa LoadError ? e.error : e
    end
    return nothing
end

"""`f()` throws a `T` whose message contains `token`."""
function kt_throws(T, token, f)
    e = kt_error(f)
    e isa T && occursin(token, sprint(showerror, e)) && return true
    @info "kt_throws: expected a $T with `$(token)`" e
    return false
end

# a model `M` with the kinds `medium dark light` (and the class `both`), the `@parameters`
# lines `params`, a contact energy that reads `J` and a volume energy that reads `V₀`
function kt_model(M::Symbol, params::Expr)
    return :(
        @potts_model $M begin
            @kinds medium dark light both = (dark, light)
            @parameters begin
                $(params.args...)
            end
            @lattice Lattice((12, 12); neighborhood = Moore(1))
            @energy begin
                cells => (volume - V₀[kind])^2
                contacts => J[kind, neighbor_kind]
            end
            @sweep Metropolis(; temperature = 4.0)
        end
    )
end

"""Define model `M` from its `@parameters` lines and build it: the error, or `nothing`."""
function kt_build(M::Symbol, params::Expr)
    return kt_error(
        () -> (
            Core.eval(@__MODULE__, kt_model(M, params));
            Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))
        )
    )
end

# the same tables in two spellings: the matrix form and entry lines
@potts_model KTMatrix begin
    @kinds medium dark light
    @parameters begin
        Jx = 11.0
        V₀[kind] = [0.0, 30.0, 20.0]
        J[kind, kind] = [0 16 16; 16 2 Jx; 16 Jx 14]
        μ[kind, kind] = [0.0 1.0 2.0; 3.0 4.0 5.0; 6.0 7.0 8.0], [symmetric = false]
    end
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2 + μ[kind, kind] * volume
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model KTNamed begin
    @kinds medium dark light
    @parameters begin
        Jx = 11.0
        V₀[kind] = 0.0
        V₀[dark] = 30.0
        V₀[light] = 20.0
        J[kind, kind] = 16
        J[medium, medium] = 0
        J[dark, dark] = 2
        J[dark, light] = Jx
        J[light, light] = 14
        μ[kind, kind] = 0.0, [symmetric = false]
        μ[medium, dark] = 1.0
        μ[medium, light] = 2.0
        μ[dark, medium] = 3.0
        μ[dark, dark] = 4.0
        μ[dark, light] = 5.0
        μ[light, medium] = 6.0
        μ[light, dark] = 7.0
        μ[light, light] = 8.0
    end
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2 + μ[kind, kind] * volume
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end

# numbers only (no computed entry), so `remake` and setters may set the tables
@potts_model KTPlain begin
    @kinds medium dark light
    @parameters begin
        V₀[kind] = [0.0, 30.0, 20.0]
        J[kind, kind] = 16.0
        J[medium, medium] = 0.0
        J[dark, light] = 11.0
        μ[kind, kind] = 1.0, [symmetric = false]
    end
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2 + μ[kind, kind] * volume
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end

# an extension without its own `@kinds` names the base's kinds it binds
@potts_model KTExtended begin
    @extend dark, light = base = KTPlain()
    @parameters begin
        J[kind, kind] = 3.0
        J[dark, light] = 7.0
    end
end

kt_op(sys) = layout(Tiling((3, 3); region = (2:11, 2:11), kinds = [:dark, :light]), sys)
kt_prob(sys) = PottsProblem(sys, kt_op(sys), (0, 4); seed = 1)
J_of(p) = getp(p, :J)(p)
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "kind tables: entry lines and the matrix form give one problem" setup = [
    KindTableSetup,
] tags = [:potts, :kind_tables] begin
    @testset "kind tables: entry lines and the matrix form give one problem" begin
        pm = kt_prob(KTMatrix(; name = :m))
        pn = kt_prob(KTNamed(; name = :m))
        @test J_of(pm) == [0 16 16; 16 2 11; 16 11 14]
        @test getp(pm, :μ)(pm) == [0 1 2; 3 4 5; 6 7 8]
        # the same values, parameter type and generated code
        @test pn.p == pm.p
        @test typeof(pn.p) == typeof(pm.p)
        @test pn.f.fingerprint == pm.f.fingerprint
        @test total_energy(pn) == total_energy(pm)
        # an entry computed from a parameter follows it, on both sides of the diagonal
        r = remake(pn; p = [:Jx => 5.0])
        @test J_of(r)[2, 3] == 5.0 && J_of(r)[3, 2] == 5.0
        @test r.p == remake(pm; p = [:Jx => 5.0]).p
        # negative control: another entry value gives another table
        pk = kt_prob(KTNamed(; name = :m, Jx = 12.0))
        @test pk.p != pn.p && J_of(pk)[3, 2] == 12.0
        # the extension's entries, by the base's kind names
        pe = kt_prob(KTExtended(; name = :m))
        @test J_of(pe) == [3 3 3; 3 3 7; 3 7 3]
    end
end

@testitem "kind tables: remake, setters and operating points set entries by name" setup = [
    KindTableSetup,
] tags = [:potts, :kind_tables] begin
    using Random: Xoshiro
    @testset "kind tables: remake, setters and operating points set entries by name" begin
        sys = KTPlain(; name = :m)
        prob = kt_prob(sys)
        names = kind_names(sys)
        @test J_of(prob) == [0 16 16; 16 16 11; 16 11 16]
        # property: entries by name give the matrix they spell, from any start
        rng = Xoshiro(7)
        for _ in 1:20
            A = rand(rng, 0:20, 3, 3)
            S = A + A'
            upper = [(names[i], names[j]) => S[i, j] for j in 1:3 for i in 1:j]
            @test J_of(remake(prob; p = [:J => upper])) == S
            all_ = [(names[i], names[j]) => A[i, j] for i in 1:3 for j in 1:3]
            @test getp(prob, :μ)(remake(prob; p = [:μ => all_])) == A
        end
        # unlisted entries keep their values; a symmetric entry sets both sides
        r = remake(prob; p = [:J => [(:dark, :light) => 3.0]])
        @test J_of(r) == [0 16 16; 16 16 3; 16 3 16]
        # an asymmetric table sets one side
        r = remake(prob; p = (μ = Dict((:dark, :light) => 5.0),))
        @test getp(r, :μ)(r) == [1 1 1; 1 1 5; 1 1 1]
        # a one-kind table, by name
        r = remake(prob; p = [:V₀ => [:light => 25.0]])
        @test getp(r, :V₀)(r) == [0, 30, 25]
        # the operating point and the integrator setter take entries too
        po = PottsProblem(sys, [kt_op(sys); :J => [(:medium, :dark) => 9.0]], (0, 4))
        @test J_of(po)[1, 2] == 9.0 && J_of(po)[2, 1] == 9.0
        integ = init(prob, SequentialCPM())
        integ.ps[:J] = [(:light, :light) => 4.0]
        @test integ.ps[:J][3, 3] == 4.0 && integ.ps[:J][2, 3] == 11.0
        @test typeof(integ.p) === typeof(prob.p)
        # refusals name the entry: an unknown kind and a conflict
        @test kt_throws(
            ArgumentError, "drak", () -> remake(prob; p = [:J => [(:drak, :light) => 1.0]])
        )
        @test kt_throws(
            ArgumentError, "conflicts with", () -> remake(
                prob; p = [:J => [(:dark, :light) => 1.0, (:light, :dark) => 2.0]]
            )
        )
        # one number sets every entry, in `remake` and in a setter
        @test J_of(remake(prob; p = [:J => 5.0])) == fill(5.0, 3, 3)
        @test getp(prob, :V₀)(remake(prob; p = (V₀ = 2.0,))) == [2, 2, 2]
        integ.ps[:μ] = 3.0
        @test integ.ps[:μ] == fill(3.0, 3, 3)
        # a mirrored NaN is symmetric
        r = remake(prob; p = [:J => [(:dark, :light) => NaN]])
        @test isnan(J_of(r)[2, 3]) && isnan(J_of(r)[3, 2])
        # so is a mirrored signed zero
        M = Matrix(J_of(prob))
        M[2, 3], M[3, 2] = 0.0, -0.0
        @test J_of(remake(prob; p = [:J => M])) == M
        # an entry gives kind names: a number would read as a kind number, not an index
        @test kt_throws(
            ArgumentError, "give kind names",
            () -> remake(prob; p = [:J => [(1, 2) => 5.0]])
        )
        @test kt_throws(
            ArgumentError, "give kind names", () -> remake(prob; p = [:V₀ => [1 => 5.0]])
        )
        @test kt_throws(
            ArgumentError, "give kind names", () -> (integ.ps[:J] = [(0, :dark) => 5.0])
        )
        # the source problem is unchanged
        @test J_of(prob) == [0 16 16; 16 16 11; 16 11 16]
    end
end

@testitem "kind tables: constructor keywords take every table form" setup = [
    KindTableSetup,
] tags = [:potts, :kind_tables] begin
    @testset "kind tables: constructor keywords take every table form" begin
        declared = [0 16 16; 16 16 11; 16 11 16]
        # entries set over the declared table (both sides of a symmetric table)
        p = kt_prob(KTPlain(; name = :m, J = [(:dark, :light) => 1.0]))
        @test J_of(p) == [0 16 16; 16 16 1; 16 1 16]
        p = kt_prob(KTPlain(; name = :m, V₀ = [:dark => 31.0]))
        @test getp(p, :V₀)(p) == [0, 31, 20] && J_of(p) == declared
        p = kt_prob(KTPlain(; name = :m, μ = Dict((:dark, :light) => 5.0)))
        @test getp(p, :μ)(p) == [1 1 1; 1 1 5; 1 1 1]
        # one number or an array replaces the declared value and its entry lines
        @test J_of(kt_prob(KTPlain(; name = :m, J = 5.0))) == fill(5.0, 3, 3)
        @test J_of(kt_prob(KTPlain(; name = :m, J = 2 * ones(3, 3)))) == fill(2.0, 3, 3)
        # negative control: no keyword keeps the declared table
        @test J_of(kt_prob(KTPlain(; name = :m))) == declared
        # refusals: a kind number as an entry key, an unknown kind
        @test kt_throws(
            ArgumentError, "give kind names",
            () -> KTPlain(; name = :m, J = [(1, 2) => 1.0])
        )
        @test kt_throws(
            ArgumentError, "drak", () -> KTPlain(; name = :m, J = [(:drak, :light) => 1.0])
        )
    end
end

@testitem "kind tables: build errors name the table and the fix" setup = [
    KindTableSetup,
] tags = [:potts, :kind_tables] begin
    @testset "kind tables: build errors name the table and the fix" begin
        V = :(V₀[kind] = [0.0, 9.0, 9.0])
        cases = [
            # a matrix of the wrong size, and one without the medium's row and column
            (:KTSize, :($V; J[kind, kind] = ones(4, 4)), "needs 3×3"),
            (:KTMedium, :($V; J[kind, kind] = [2 11; 11 14]), "the medium's"),
            (:KTMediumV, :(V₀[kind] = [9.0, 9.0]; J[kind, kind] = 1.0), "the medium's"),
            # entries without the medium and without a value for the rest
            (
                :KTForgot, :(
                    $V; J[dark, dark] = 2; J[dark, light] = 11; J[light, light] = 14
                ), "the medium",
            ),
            # an unknown kind name, a kind class and a parameter as an index
            (:KTTypo, :($V; J[kind, kind] = 0; J[dark, lihgt] = 1), "lihgt"),
            (
                :KTTypoKinds, :($V; J[kind, kind] = 0; J[dark, lihgt] = 1),
                "the kinds are medium, dark, light",
            ),
            (:KTClass, :($V; J[kind, kind] = 0; J[both, light] = 1), "kind class"),
            (:KTParam, :($V; q = 1.0; J[kind, kind] = 0; J[q, light] = 1), "`q`"),
            # an entry given twice, and (k₁, k₂) against (k₂, k₁) in a symmetric table
            (
                :KTTwice, :($V; J[kind, kind] = 0; J[dark, light] = 1; J[dark, light] = 1),
                "given twice",
            ),
            (
                :KTConflict,
                :($V; J[kind, kind] = 0; J[dark, light] = 11; J[light, dark] = 12),
                "conflicts with",
            ),
            (
                :KTRepeat,
                :($V; J[kind, kind] = 0; J[dark, light] = 11; J[light, dark] = 11),
                "repeats",
            ),
            # an asymmetric matrix in a table not declared asymmetric
            (:KTAsym, :($V; J[kind, kind] = [0 1 2; 1 0 0; 3 0 0]), "is symmetric"),
            # both an array and entries; `symmetric` on a one-kind table
            (:KTBoth, :($V; J[kind, kind] = ones(3, 3); J[dark, light] = 1), "both as"),
            (
                :KTSymV, Expr(
                    :block, Meta.parse("V₀[kind] = [0.0, 9.0, 9.0], [symmetric = false]"),
                    :(J[kind, kind] = 1)
                ),
                "two-kind",
            ),
            # no value at all
            (:KTNone, :($V; J[kind, kind]), "has no value"),
            # a number as an index: the whole table takes `kind` on every axis
            (:KTNumber, :($V; J[2, 2] = ones(3, 3)), "J[kind, kind]"),
        ]
        @testset "$M" for (M, params, token) in cases
            e = kt_build(M, params)
            @test e isa ArgumentError
            msg = e === nothing ? "" : sprint(showerror, e)
            # the message names the table and contains the case's token
            @test occursin(r"`J|J\[|`V₀|V₀\[", msg)
            @test occursin(token, msg)
        end
        # negative controls: the same conflict in a table declared asymmetric, a matrix of
        # the right size, and every entry listed without a value for the rest
        @test kt_build(
            :KTAsymOK, Expr(
                :block, V, :(J[kind, kind] = 1.0),
                Meta.parse("μ[kind, kind] = 0.0, [symmetric = false]"),
                :(μ[dark, light] = 11), :(μ[light, dark] = 12)
            )
        ) === nothing
        @test kt_build(:KTSizeOK, :($V; J[kind, kind] = ones(3, 3))) === nothing
        @test kt_build(
            :KTAllOK, :(
                $V; J[medium, medium] = 0; J[medium, dark] = 16; J[medium, light] = 16;
                J[dark, dark] = 2; J[dark, light] = 11; J[light, light] = 14
            )
        ) === nothing
        # a kind name before `@kinds`, and a base kind not bound by the `@extend` line
        e = kt_error(
            () -> Core.eval(
                @__MODULE__, :(
                    @potts_model KTEarly begin
                        @parameters begin
                            J[kind, kind] = 1.0
                            J[dark, light] = 2.0
                        end
                        @kinds medium dark light
                    end
                )
            )
        )
        @test e isa ArgumentError &&
            occursin("declare @kinds before @parameters", sprint(showerror, e))
        e = kt_error(
            () -> Core.eval(
                @__MODULE__, :(
                    @potts_model KTUnbound begin
                        @extend dark = base = KTPlain()
                        @parameters begin
                            J[kind, kind] = 1.0
                            J[dark, light] = 2.0
                        end
                    end
                )
            )
        )
        @test e isa ArgumentError &&
            occursin("bind it in the @extend line", sprint(showerror, e))
        # a table of the wrong size given to `remake` names the size it needs
        prob = kt_prob(KTPlain(; name = :m))
        @test kt_throws(
            ArgumentError, "needs 3×3", () -> remake(prob; p = [:J => ones(2, 2)])
        )
        @test kt_throws(
            ArgumentError, "is symmetric",
            () -> remake(prob; p = [:J => [0 1 2; 1 0 0; 3 0 0]])
        )
    end
end

@testitem "kind_names: results by kind name" setup = [KindTableSetup] tags = [
    :potts, :kind_tables,
] begin
    @testset "kind_names: results by kind name" begin
        sys = KTPlain(; name = :m)
        prob = kt_prob(sys)
        sol = solve(prob, SequentialCPM(); saveat = 2)
        integ = init(prob, SequentialCPM())
        names = [:medium, :dark, :light]
        for x in (sys, mtkcompile(sys), prob, integ, sol)
            @test kind_names(x) == names
        end
        # property: each number maps to the name in its place, for every saved state
        ks = sol[:kind]
        named = kind_names(sol, ks)
        @test length(named) == length(ks)
        for (k, n) in zip(ks, named)
            @test n == [names[i + 1] for i in k]
            @test count(==(:dark), n) == count(==(1), k)
        end
        @test kind_names(prob, 2) === :light
        @test eltype(kind_names(sol, ks[end])) === Symbol
        # the returned names are a copy: changing them changes no model
        v = kind_names(sys)
        v[1] = :x
        @test kind_names(sys) == names
        # a number that is not a kind
        @test kt_throws(ArgumentError, "not a kind number", () -> kind_names(sol, 3))
        @test kt_throws(ArgumentError, "not a kind number", () -> kind_names(sol, [1, -1]))
        # a problem not built from a model has kinds without names
        σ = zeros(Int32, 8, 8)
        σ[2:4, 2:4] .= 1
        f = CPMFunction((st, p, prop, ctx) -> 0.0; temperature = (st, p, prop, ctx) -> 1.0)
        bare = PottsProblem(f, initial_state(σ, [1]), Lattice((8, 8)), (0, 2), (;))
        @test kt_throws(ArgumentError, "not built from a model", () -> kind_names(bare))
    end
end
