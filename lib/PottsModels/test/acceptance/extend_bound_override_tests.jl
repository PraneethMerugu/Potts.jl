# a name that `@extend`
# binds from the base and the extension then redeclares in its own category keeps the
# extension's own default.
#
# Today (a1c3ed57) `@extend λ = base = Base()` rebinds the constructor's local `λ` (the
# keyword `λ = nothing` of `Ext(; λ)`) to the base's symbolic `λ`, so the redeclaration
# `@parameters λ = 3.0` reads `λ === nothing ? 3.0 : λ` and takes the base's symbol as its
# default: `PottsProblem` throws "parameter `λ` = `λ` does not reduce to numbers". The same
# holds for a kind table (`J[kind, kind] = …` over a bound `J`), and a constructor keyword
# `Ext(; λ = 5.0)` is lost too (the binding overwrites it).
#
# Rule (D-114; D-113: redeclaring a name in its own category is an override, the extension
# wins). Binding a base name (`@extend λ, … = base = Base()`) never changes what a
# redeclaration means:
#   * a redeclared parameter or kind table takes the extension's own default (`λ = 3.0`),
#     at build (`info(lookup(sys, :λ)).default`) and in `PottsProblem`;
#   * a constructor keyword of the extension still overrides it (`Ext(; λ = 5.0)`);
#   * a redeclared variable takes the extension's default (`@variables x(cell) = 2.0`);
#   * a bound name that is not redeclared keeps the base's value, including a value given
#     to the base call (`Base(; V₀ = 8.0)`);
#   * a computed default of the extension that reads a bound name (`μ = 2λ`) reads the
#     model's one value of that name: the base's when the extension does not redeclare it,
#     the extension's own (or its keyword's) when it does, whatever the order of the
#     declarations (a model has one value per name, D-113);
#   * `@extend Base()` without binding behaves the same (control; it works today).
#
# Energies are checked by hand. Fixture: on a 12×12 lattice with von Neumann contacts, cell 1
# (kind A) at x = 3:5, y = 3:5 (volume 9) and cell 2 (kind B) at x = 6:8, y = 3:6 (volume
# 12). They share 3 contact pairs (x = 5|6, y = 3:5); cell 1 has 12 − 3 = 9 pairs with the
# medium, cell 2 has 14 − 3 = 11 (pairs counted once, docs/src/manual/energy.md). The base:
#   E = λ ((9 − V₀)² + (12 − V₀)²) + 9 J[M,A] + 11 J[M,B] + 3 J[A,B] + x (9 + 12)
# with λ = 1, V₀ = 9, J = [0 2 2; 2 1 4; 2 4 1] (contacts 18 + 22 + 12 = 52), x = 0.5:
#   E = 9 + 52 + 10.5 = 71.5.
# An extension term `cells(A) => μ * volume` adds 9μ.

@testsetup module ExtendBoundOverrideSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
@potts_model OverrideBase begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        V₀ = 9.0
        J[kind, kind] = [0 2 2; 2 1 4; 2 4 1]
    end
    @variables x(cell) = 0.5
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(A, B) => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
        cells(A, B) => x * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end
# the Accept line: a bound parameter redeclared
@potts_model Param begin
    @extend λ = base = OverrideBase()
    @parameters λ = 3.0
end
# several names bound, only λ redeclared; V₀, J and x keep the base's values
@potts_model Partial begin
    @extend λ, V₀, J, x = base = OverrideBase()
    @parameters λ = 3.0
end
# ... with a value given to the base call
@potts_model PartialKw begin
    @extend λ, V₀ = base = OverrideBase(; V₀ = 8.0)
    @parameters λ = 3.0
end
# bound, not redeclared at all
@potts_model BoundOnly begin
    @extend λ, V₀ = base = OverrideBase()
end
# a bound variable redeclared
@potts_model Var begin
    @extend x = base = OverrideBase()
    @variables x(cell) = 2.0
end
# a bound parameter and a bound variable, both redeclared
@potts_model Both begin
    @extend λ, x = base = OverrideBase()
    @parameters λ = 3.0
    @variables x(cell) = 2.0
end
# a bound kind table redeclared
@potts_model Table begin
    @extend J = base = OverrideBase()
    @parameters J[kind, kind] = [0 3 3; 3 1 5; 3 5 1]
end
# computed defaults reading a bound name: not redeclared (the base's λ) ...
@potts_model MuBase begin
    @extend λ, A = base = OverrideBase()
    @parameters μ = 2λ
    @energy cells(A) => μ * volume
end
# ... the base's λ as given to the base call ...
@potts_model MuBaseKw begin
    @extend λ, A = base = OverrideBase(; λ = 1.5)
    @parameters μ = 2λ
    @energy cells(A) => μ * volume
end
# ... redeclared before μ ...
@potts_model MuRedecl begin
    @extend λ, A = base = OverrideBase()
    @parameters begin
        λ = 3.0
        μ = 2λ
    end
    @energy cells(A) => μ * volume
end
# ... and redeclared after μ (one value per name, whatever the order)
@potts_model MuAfter begin
    @extend λ, A = base = OverrideBase()
    @parameters μ = 2λ
    @parameters λ = 3.0
    @energy cells(A) => μ * volume
end
# control: no binding (works today)
@potts_model Unbound begin
    @extend OverrideBase()
    @parameters λ = 3.0
end
function override_op()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:6] .= 2
    return [ownership => σ, kind => [:A, :B]]
end
"""`f()`, or the message of the error it throws (so a failure shows the reason)."""
function override_try(f)
    try
        return f()
    catch e
        while e isa LoadError
            e = e.error
        end
        return "error: " * first(sprint(showerror, e), 300)
    end
end
override_problem(m) = PottsProblem(m, override_op(), (0, 2); seed = 7)
"""The total energy of model `m` on the fixture, or the error message."""
override_energy(m) = override_try(() -> total_energy(override_problem(m)))
"""The value of parameter `k` in `m`'s problem (plain numbers or a matrix), or the error."""
override_value(m, k) = override_try(() -> (v = getp(override_problem(m), k)(override_problem(m)); v isa Number ? v : Matrix(v)))
"""The declared default of quantity `k` in `m` as plain numbers, or the error (a symbolic
default does not convert)."""
function override_default(m, k)
    return override_try(
        () -> (
            d = Potts.info(Potts.lookup(m, k)).default;
            d isa AbstractArray ? Matrix{Float64}(d) : Float64(d)
        )
    )
end
override_count(m, k) = count(p -> Potts.info(p).name === k, Potts.declared_parameters(m))
build(F; kws...) = override_try(() -> F(; name = :ext, kws...))
const OVERRIDE_J0 = [0 2 2; 2 1 4; 2 4 1]
const OVERRIDE_J1 = [0 3 3; 3 1 5; 3 5 1]
# contacts 27 + 33 + 15 = 75
const OVERRIDE_M = [0 1 1; 1 0 2; 1 2 0]
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "extend bound override: an @extend-bound name redeclared keeps its own default" setup = [ExtendBoundOverrideSetup] tags = [:pottsmodels, :acceptance] begin
    # contacts 9 + 11 + 6 = 26
    @testset "extend bound override: an @extend-bound name redeclared keeps its own default" begin
        @testset "negative controls: the base and a binding without redeclaration" begin
            b = OverrideBase(; name = :b)
            @test override_default(b, :λ) == 1.0
            @test override_energy(b) == 71.5
            m = build(BoundOnly)
            @test m isa Potts.PottsSystem
            @test override_default(m, :λ) == 1.0 && override_default(m, :V₀) == 9.0
            @test override_energy(m) == 71.5
        end

        @testset "control: @extend without binding" begin
            m = build(Unbound)
            @test override_count(m, :λ) == 1
            @test override_default(m, :λ) == 3.0
            @test override_value(m, :λ) == 3.0
            @test override_energy(m) == 89.5                          # 27 + 52 + 10.5
            k = build(Unbound; λ = 5.0)
            @test override_default(k, :λ) == 5.0
            @test override_energy(k) == 107.5                         # 45 + 52 + 10.5
        end

        @testset "a bound parameter redeclared (the Accept line)" begin
            m = build(Param)
            @test m isa Potts.PottsSystem
            @test override_count(m, :λ) == 1
            @test override_default(m, :λ) == 3.0                      # at build
            @test override_value(m, :λ) == 3.0                        # in PottsProblem
            @test override_energy(m) == 89.5                          # 27 + 52 + 10.5
            # a constructor keyword still overrides
            k = build(Param; λ = 5.0)
            @test override_default(k, :λ) == 5.0
            @test override_value(k, :λ) == 5.0
            @test override_energy(k) == 107.5                         # 45 + 52 + 10.5
            # building the extension leaves the base as it was
            @test override_energy(OverrideBase(; name = :b)) == 71.5
        end

        @testset "bound names not redeclared keep the base's values" begin
            m = build(Partial)
            @test override_default(m, :λ) == 3.0
            @test override_default(m, :V₀) == 9.0
            @test override_default(m, :J) == OVERRIDE_J0
            @test override_default(m, :x) == 0.5
            @test override_value(m, :V₀) == 9.0 && override_value(m, :J) == OVERRIDE_J0
            @test override_energy(m) == 89.5
            k = build(Partial; λ = 5.0)
            @test override_default(k, :V₀) == 9.0 && override_energy(k) == 107.5
            # a value given to the base call is the base's value
            w = build(PartialKw)
            @test override_default(w, :V₀) == 8.0 && override_default(w, :λ) == 3.0
            @test override_value(w, :V₀) == 8.0
            @test override_energy(w) == 113.5                         # 3 (1 + 16) + 52 + 10.5
        end

        @testset "a bound variable redeclared" begin
            m = build(Var)
            @test count(v -> Potts.info(v).name === :x, Potts.declared_variables(m)) == 1
            @test override_default(m, :x) == 2.0
            @test override_default(m, :λ) == 1.0
            @test override_energy(m) == 103.0                         # 9 + 52 + 42
            b = build(Both)
            @test override_default(b, :x) == 2.0 && override_default(b, :λ) == 3.0
            @test override_energy(b) == 121.0                         # 27 + 52 + 42
            k = build(Both; λ = 5.0)
            @test override_default(k, :x) == 2.0 && override_energy(k) == 139.0   # 45 + 52 + 42
        end

        @testset "a bound kind table redeclared" begin
            m = build(Table)
            @test override_count(m, :J) == 1
            @test override_default(m, :J) == OVERRIDE_J1
            @test override_value(m, :J) == OVERRIDE_J1
            @test override_energy(m) == 94.5                          # 9 + 75 + 10.5
            k = build(Table; J = OVERRIDE_M)
            @test override_default(k, :J) == OVERRIDE_M
            @test override_value(k, :J) == OVERRIDE_M
            @test override_energy(k) == 45.5                          # 9 + 26 + 10.5
        end

        @testset "computed defaults reading a bound name" begin
            # not redeclared: the base's λ
            m = build(MuBase)
            @test override_value(m, :μ) == 2.0
            @test override_energy(m) == 89.5                          # 71.5 + 9·2
            m = build(MuBaseKw)
            @test override_value(m, :λ) == 1.5 && override_value(m, :μ) == 3.0
            @test override_energy(m) == 103.0                         # 13.5 + 52 + 10.5 + 27
            # redeclared: the extension's λ, before or after μ
            for F in (MuRedecl, MuAfter)
                m = build(F)
                @test override_count(m, :λ) == 1
                @test override_default(m, :λ) == 3.0
                @test override_value(m, :λ) == 3.0 && override_value(m, :μ) == 6.0
                @test override_energy(m) == 143.5                     # 27 + 52 + 10.5 + 54
                # the extension's keyword is the model's λ, and μ follows it
                k = build(F; λ = 5.0)
                @test override_value(k, :λ) == 5.0 && override_value(k, :μ) == 10.0
                @test override_energy(k) == 197.5                     # 45 + 52 + 10.5 + 90
                # and μ still follows λ after the build (D-112)
                q = override_try(() -> remake(override_problem(m); p = [:λ => 2.0]))
                @test override_try(() -> (getp(q, :μ)(q), total_energy(q))) == (4.0, 116.5)   # 18 + 52 + 10.5 + 36
            end
        end
    end
end
