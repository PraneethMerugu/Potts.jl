# P6.0am (ROADMAP Phase 6, step 0; found by the P6.0al test author): a name that `@extend`
# binds from the base and the extension then redeclares in its own category keeps the
# extension's own default. Frozen (AUTONOMY §7.2).
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
using Test, Potts, PottsModels

@potts_model P60amBase begin
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
        contacts => J[kind, kind′]
        cells(A, B) => x * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

# the Accept line: a bound parameter redeclared
@potts_model P60amParam begin
    @extend λ = base = P60amBase()
    @parameters λ = 3.0
end

# several names bound, only λ redeclared; V₀, J and x keep the base's values
@potts_model P60amPartial begin
    @extend λ, V₀, J, x = base = P60amBase()
    @parameters λ = 3.0
end

# ... with a value given to the base call
@potts_model P60amPartialKw begin
    @extend λ, V₀ = base = P60amBase(; V₀ = 8.0)
    @parameters λ = 3.0
end

# bound, not redeclared at all
@potts_model P60amBoundOnly begin
    @extend λ, V₀ = base = P60amBase()
end

# a bound variable redeclared
@potts_model P60amVar begin
    @extend x = base = P60amBase()
    @variables x(cell) = 2.0
end

# a bound parameter and a bound variable, both redeclared
@potts_model P60amBoth begin
    @extend λ, x = base = P60amBase()
    @parameters λ = 3.0
    @variables x(cell) = 2.0
end

# a bound kind table redeclared
@potts_model P60amTable begin
    @extend J = base = P60amBase()
    @parameters J[kind, kind] = [0 3 3; 3 1 5; 3 5 1]
end

# computed defaults reading a bound name: not redeclared (the base's λ) ...
@potts_model P60amMuBase begin
    @extend λ, A = base = P60amBase()
    @parameters μ = 2λ
    @energy cells(A) => μ * volume
end

# ... the base's λ as given to the base call ...
@potts_model P60amMuBaseKw begin
    @extend λ, A = base = P60amBase(; λ = 1.5)
    @parameters μ = 2λ
    @energy cells(A) => μ * volume
end

# ... redeclared before μ ...
@potts_model P60amMuRedecl begin
    @extend λ, A = base = P60amBase()
    @parameters begin
        λ = 3.0
        μ = 2λ
    end
    @energy cells(A) => μ * volume
end

# ... and redeclared after μ (one value per name, whatever the order)
@potts_model P60amMuAfter begin
    @extend λ, A = base = P60amBase()
    @parameters μ = 2λ
    @parameters λ = 3.0
    @energy cells(A) => μ * volume
end

# control: no binding (works today)
@potts_model P60amUnbound begin
    @extend P60amBase()
    @parameters λ = 3.0
end

function p60am_op()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:6] .= 2
    return [ownership => σ, kind => [:A, :B]]
end

"""`f()`, or the message of the error it throws (so a failure shows the reason)."""
function p60am_try(f)
    try
        return f()
    catch e
        while e isa LoadError
            e = e.error
        end
        return "error: " * first(sprint(showerror, e), 300)
    end
end

p60am_problem(m) = PottsProblem(m, p60am_op(), (0, 2); seed = 7)
"""The total energy of model `m` on the fixture, or the error message."""
p60am_energy(m) = p60am_try(() -> total_energy(p60am_problem(m)))
"""The value of parameter `k` in `m`'s problem (plain numbers or a matrix), or the error."""
p60am_value(m, k) = p60am_try(() -> (v = getp(p60am_problem(m), k)(p60am_problem(m)); v isa Number ? v : Matrix(v)))
"""The declared default of quantity `k` in `m` as plain numbers, or the error (a symbolic
default does not convert)."""
p60am_default(m, k) = p60am_try(() -> (d = Potts.info(Potts.lookup(m, k)).default;
    d isa AbstractArray ? Matrix{Float64}(d) : Float64(d)))
p60am_count(m, k) = count(p -> Potts.info(p).name === k, m.parameters)
p60am_build(F; kws...) = p60am_try(() -> F(; name = :ext, kws...))

const P60AM_J0 = [0 2 2; 2 1 4; 2 4 1]
const P60AM_J1 = [0 3 3; 3 1 5; 3 5 1]   # contacts 27 + 33 + 15 = 75
const P60AM_M = [0 1 1; 1 0 2; 1 2 0]    # contacts 9 + 11 + 6 = 26

@testset "P6.0am: an @extend-bound name redeclared keeps its own default" begin
    @testset "negative controls: the base and a binding without redeclaration" begin
        b = P60amBase(; name = :b)
        @test p60am_default(b, :λ) == 1.0
        @test p60am_energy(b) == 71.5
        m = p60am_build(P60amBoundOnly)
        @test m isa Potts.PottsSystem
        @test p60am_default(m, :λ) == 1.0 && p60am_default(m, :V₀) == 9.0
        @test p60am_energy(m) == 71.5
    end

    @testset "control: @extend without binding" begin
        m = p60am_build(P60amUnbound)
        @test p60am_count(m, :λ) == 1
        @test p60am_default(m, :λ) == 3.0
        @test p60am_value(m, :λ) == 3.0
        @test p60am_energy(m) == 89.5                          # 27 + 52 + 10.5
        k = p60am_build(P60amUnbound; λ = 5.0)
        @test p60am_default(k, :λ) == 5.0
        @test p60am_energy(k) == 107.5                         # 45 + 52 + 10.5
    end

    @testset "a bound parameter redeclared (the Accept line)" begin
        m = p60am_build(P60amParam)
        @test m isa Potts.PottsSystem
        @test p60am_count(m, :λ) == 1
        @test p60am_default(m, :λ) == 3.0                      # at build
        @test p60am_value(m, :λ) == 3.0                        # in PottsProblem
        @test p60am_energy(m) == 89.5                          # 27 + 52 + 10.5
        # a constructor keyword still overrides
        k = p60am_build(P60amParam; λ = 5.0)
        @test p60am_default(k, :λ) == 5.0
        @test p60am_value(k, :λ) == 5.0
        @test p60am_energy(k) == 107.5                         # 45 + 52 + 10.5
        # building the extension leaves the base as it was
        @test p60am_energy(P60amBase(; name = :b)) == 71.5
    end

    @testset "bound names not redeclared keep the base's values" begin
        m = p60am_build(P60amPartial)
        @test p60am_default(m, :λ) == 3.0
        @test p60am_default(m, :V₀) == 9.0
        @test p60am_default(m, :J) == P60AM_J0
        @test p60am_default(m, :x) == 0.5
        @test p60am_value(m, :V₀) == 9.0 && p60am_value(m, :J) == P60AM_J0
        @test p60am_energy(m) == 89.5
        k = p60am_build(P60amPartial; λ = 5.0)
        @test p60am_default(k, :V₀) == 9.0 && p60am_energy(k) == 107.5
        # a value given to the base call is the base's value
        w = p60am_build(P60amPartialKw)
        @test p60am_default(w, :V₀) == 8.0 && p60am_default(w, :λ) == 3.0
        @test p60am_value(w, :V₀) == 8.0
        @test p60am_energy(w) == 113.5                         # 3 (1 + 16) + 52 + 10.5
    end

    @testset "a bound variable redeclared" begin
        m = p60am_build(P60amVar)
        @test count(v -> Potts.info(v).name === :x, m.variables) == 1
        @test p60am_default(m, :x) == 2.0
        @test p60am_default(m, :λ) == 1.0
        @test p60am_energy(m) == 103.0                         # 9 + 52 + 42
        b = p60am_build(P60amBoth)
        @test p60am_default(b, :x) == 2.0 && p60am_default(b, :λ) == 3.0
        @test p60am_energy(b) == 121.0                         # 27 + 52 + 42
        k = p60am_build(P60amBoth; λ = 5.0)
        @test p60am_default(k, :x) == 2.0 && p60am_energy(k) == 139.0   # 45 + 52 + 42
    end

    @testset "a bound kind table redeclared" begin
        m = p60am_build(P60amTable)
        @test p60am_count(m, :J) == 1
        @test p60am_default(m, :J) == P60AM_J1
        @test p60am_value(m, :J) == P60AM_J1
        @test p60am_energy(m) == 94.5                          # 9 + 75 + 10.5
        k = p60am_build(P60amTable; J = P60AM_M)
        @test p60am_default(k, :J) == P60AM_M
        @test p60am_value(k, :J) == P60AM_M
        @test p60am_energy(k) == 45.5                          # 9 + 26 + 10.5
    end

    @testset "computed defaults reading a bound name" begin
        # not redeclared: the base's λ
        m = p60am_build(P60amMuBase)
        @test p60am_value(m, :μ) == 2.0
        @test p60am_energy(m) == 89.5                          # 71.5 + 9·2
        m = p60am_build(P60amMuBaseKw)
        @test p60am_value(m, :λ) == 1.5 && p60am_value(m, :μ) == 3.0
        @test p60am_energy(m) == 103.0                         # 13.5 + 52 + 10.5 + 27
        # redeclared: the extension's λ, before or after μ
        for F in (P60amMuRedecl, P60amMuAfter)
            m = p60am_build(F)
            @test p60am_count(m, :λ) == 1
            @test p60am_default(m, :λ) == 3.0
            @test p60am_value(m, :λ) == 3.0 && p60am_value(m, :μ) == 6.0
            @test p60am_energy(m) == 143.5                     # 27 + 52 + 10.5 + 54
            # the extension's keyword is the model's λ, and μ follows it
            k = p60am_build(F; λ = 5.0)
            @test p60am_value(k, :λ) == 5.0 && p60am_value(k, :μ) == 10.0
            @test p60am_energy(k) == 197.5                     # 45 + 52 + 10.5 + 90
            # and μ still follows λ after the build (D-112)
            q = p60am_try(() -> remake(p60am_problem(m); p = [:λ => 2.0]))
            @test p60am_try(() -> (getp(q, :μ)(q), total_energy(q))) == (4.0, 116.5)   # 18 + 52 + 10.5 + 36
        end
    end
end
