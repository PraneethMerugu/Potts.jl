# Entity-local initialization (`@initialization_equations`, `Potts.initialization_system`),
# beside the frozen acceptance file p6_0bo_initialization.jl: the `kind` built-in, parameter
# expressions as fixed values, vector components with guesses, `D(m)` of a model ODE, `extend`,
# `Float32` problems, algebraic model variables from the operating point, many cells, and the
# rejections the frozen file leaves to the implementer.

@testsetup module InitializationSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
const INI_M = Potts.ModelingToolkitBase

ini_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:5] .= 2; s)
# volumes 16, 12
ini_op(extra...; kinds = [1, 1]) = Any[ownership => ini_sigma(), kind => kinds, extra...]

ini_u0(prob, n) = Vector{Float64}(Array(getproperty(prob.u0.cell, n)))

ini_names(xs) = Set{Symbol}(Potts.SymbolicIndexingInterface.getname(x) for x in xs)

ini_error(f, words...) = try
    f()
    false
catch err
    e = err isa LoadError ? err.error : err
    ok = e isa ArgumentError
    ok || @info "initialization: expected an ArgumentError" exception = e
    ok
end

ini_compile_error(f, words...) = try
    f()
    false
catch err
    e = err isa LoadError ? err.error : err
    ok = e isa Potts.PottsCompileError && (isempty(words) || occursin(first(words), sprint(showerror, e)))
    ok || @info "initialization: expected a PottsCompileError" exception = e
    ok
end

const INI_VOL = [16.0, 12.0]


# the `kind` built-in, a parameter expression as a written (fixed) value, vector components
@potts_model IniKinds begin
    @kinds medium A B
    @parameters c0 = 3.0
    @variables begin
        y(cell)
        w(cell) = 2c0
        p(cell)[1:2], [guess = [1.0, -1.0]]
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations begin
        y ~ 10kind + volume + w
        p[1]^2 ~ volume
        p[2]^2 ~ volume
    end
    @sweep Metropolis(; temperature = 1.0)
end


# `D(m)` of a model ODE: a steady model start, read again by a cell equation
@potts_model IniModelODE begin
    @kinds medium A
    @parameters begin
        ka = 2.0
        kb = 0.5
    end
    @variables begin
        m(model)
        z(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @equations D(m) ~ ka - kb * m
    @initialization_equations begin
        D(m) ~ 0
        z ~ volume + m + D(m)
    end
    @sweep Metropolis(; temperature = 1.0)
end


# `extend`: the base's initialization equations come along; the extension adds its own
@potts_model IniBase begin
    @kinds medium A
    @variables Vt(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations Vt ~ 2volume
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniExt begin
    @extend Vt = base = IniBase()
    @variables v2(cell)
    @initialization_equations v2 ~ Vt + 1
end


# an algebraic model variable from the operating point; symbolic keys for algebraic variables
@potts_model IniHalf begin
    @kinds medium A
    @parameters r = 0.5
    @variables begin
        m(model)
        half(model)
        x(cell)
        xd(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @equations begin
        D(m) ~ -r * m
        half ~ m / 2
        D(x) ~ -xd
        xd ~ 3x + volume
    end
    @sweep Metropolis(; temperature = 1.0)
end


# many cells: every cell its own solve, values by hand
@potts_model IniMany begin
    @kinds medium A
    @variables begin
        r(cell), [guess = 1.0]
        s(cell)
    end
    @lattice Lattice((40, 40))
    @energy cells => (volume - 4.0)^2
    @initialization_equations begin
        r^3 + r ~ volume + 2id
        s ~ r * id
    end
    @sweep Metropolis(; temperature = 1.0)
end


# rejections the frozen file leaves to the implementer
@potts_model IniReject begin
    @structural_parameters begin
        kind_case = :surface
    end
    @kinds medium A
    @variables v(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    if kind_case === :no_ode
        @initialization_equations D(v) ~ 0
    elseif kind_case === :surface
        @initialization_equations v ~ surface
    elseif kind_case === :twice
        @initialization_equations begin
            v ~ volume
            v ~ 2volume
        end
    else
        @initialization_equations v ~ rand()
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniGatherRate begin
    @kinds medium A
    @variables g(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @equations D(g) ~ sum(volume[owner[n]] for n in Moore(1)(42)) - g
    @initialization_equations D(g) ~ 0
    @sweep Metropolis(; temperature = 1.0)
end


# a model variable that only a cell equation names
@potts_model IniModelByCell begin
    @kinds medium A
    @variables mm(model)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations mm ~ 2volume
    @sweep Metropolis(; temperature = 1.0)
end


# every result is checked against the conditions: no solution, no unique solution, small scales
@potts_model IniCoef begin
    @kinds medium A
    @parameters k = 0.0
    @variables kx(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations k * kx ~ volume
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniCellCoef begin
    @kinds medium A
    @variables zz(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations (id - 1) * zz ~ volume
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniPair begin
    @kinds medium A
    @parameters shift = 1.0
    @variables begin
        ta(cell)
        tb(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations begin
        ta + tb ~ volume
        ta + tb ~ volume + shift
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniDependent begin
    @kinds medium A
    @variables begin
        sa(cell)
        sb(cell)
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations begin
        sa + sb ~ volume
        2sa + 2sb ~ 2volume
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniSmall begin
    @kinds medium A
    @parameters begin
        kp = 1.0e-12
        kd = 1.0
    end
    @variables begin
        ty(cell), [guess = 1.0]
        cc(cell), [guess = 1.0e-3]
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @equations D(cc) ~ kp * volume - kd * cc^2
    @initialization_equations begin
        ty^2 ~ 1.0e-20volume
        D(cc) ~ 0
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniNoGuess begin
    @kinds medium A
    @variables r(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations r^2 ~ volume
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniNoRoot begin
    @kinds medium A
    @variables q(cell), [guess = 1.0]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations q^2 + 1 ~ 0
    @sweep Metropolis(; temperature = 1.0)
end


# roots at 0 and roots where the terms vanish (the Jacobian step follows the value's scale and
# is not judged below the residual's resolution; a vanishing-term root passes on its Newton
# correction): each solved, against its oracle
@potts_model IniRoots begin
    @kinds medium A
    @variables begin
        e1(cell), [guess = 0.5]
        e2(cell), [guess = -2.0]
        e3(cell), [guess = 0.5]
        e4(cell), [guess = 0.5]
        s1(cell), [guess = 3.0]
        c1(cell), [guess = 1.0]
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations begin
        exp(e1) ~ 1
        1 - exp(e2) ~ 0
        log(1 + e3) ~ 0
        exp(e4) - 1 ~ (volume - 16) / 16          # root 0 in cell 1
        sin(s1) ~ 0
        cos(c1) ~ 0
    end
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniRepeated begin
    @kinds medium A
    @variables q2(cell), [guess = 2.0]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations (q2 - 1)^2 ~ 0
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniFlat begin
    @kinds medium A
    @variables f3(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations f3^3 ~ 0
    @sweep Metropolis(; temperature = 1.0)
end


# flat equations are refused (the finite-difference step never crosses a kink or a branch);
# a large guess does not loosen the check; a guess may be an expression of parameters
@potts_model IniGuessed begin
    @structural_parameters begin
        kind_case = :kink
        guess_val = 1.0
        use_pz = false
    end
    @kinds medium A
    @parameters pz = -1.0
    @variables v(cell), [guess = use_pz ? pz : guess_val]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    if kind_case === :kink
        @initialization_equations max(v, 1000.0) ~ 1000.0
    elseif kind_case === :clamp
        @initialization_equations clamp(v, -1.0, 1.0) ~ 1.0
    else
        @initialization_equations v^2 ~ volume
    end
    @sweep Metropolis(; temperature = 1.0)
end


# kind tables are read at the cell's own kind
@potts_model IniTable begin
    @structural_parameters begin
        fixed = false
    end
    @kinds medium A B
    @parameters g[kind] = [0.0, 1.0, 3.0]
    @variables kv(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    if fixed
        @initialization_equations kv ~ g[2] * volume
    else
        @initialization_equations kv ~ g[kind] * volume
    end
    @sweep Metropolis(; temperature = 1.0)
end


# no value written: recorded, and nothing else changes (code, fingerprint, the start at 0.0)
@potts_model IniBare begin
    @kinds medium A
    @variables x(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - x)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model IniZero begin
    @kinds medium A
    @variables x(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - x)^2
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "initialization: kind, parameter expressions, vector guesses" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: kind, parameter expressions, vector guesses" begin
        prob = PottsProblem(IniKinds(; name = :k), ini_op(; kinds = [:A, :B]), (0, 1))
        @test ini_u0(prob, :y) ≈ [10 + 16 + 6.0, 20 + 12 + 6.0] rtol = 1.0e-12
        @test ini_u0(prob, :p_1) ≈ sqrt.(INI_VOL) rtol = 1.0e-9
        @test ini_u0(prob, :p_2) ≈ -sqrt.(INI_VOL) rtol = 1.0e-9
        @test !isapprox(ini_u0(prob, :p_2), sqrt.(INI_VOL); rtol = 1.0e-3)          # control: the other root
        # the parameter is read at its problem value
        prob2 = PottsProblem(IniKinds(; name = :k, c0 = 1.0), ini_op(; kinds = [:A, :B]), (0, 1))
        @test ini_u0(prob2, :y) ≈ [10 + 16 + 2.0, 20 + 12 + 2.0] rtol = 1.0e-12
        # the template: guesses from the vector's metadata, `w` fixed at its written value
        s = Potts.initialization_system(mtkcompile(IniKinds(; name = :k)), :cell)
        @test issubset(Set([:y, :w, :p_1, :p_2]), ini_names(INI_M.unknowns(s)))
        @test :c0 in ini_names(INI_M.parameters(s))
        @test length(INI_M.initialization_equations(s)) == 3
        # Float32 problems are initialized in Float64 and stored as Float32
        p32 = PottsProblem(IniKinds(; name = :k), ini_op(; kinds = [:A, :B]), (0, 1); T = Float32)
        @test eltype(p32.u0.cell.y) === Float32 && ini_u0(p32, :y) == Float64.(Float32.([32.0, 38.0]))
    end
end

@testitem "initialization: D(m) of a model ODE" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: D(m) of a model ODE" begin
        c = mtkcompile(IniModelODE(; name = :m))
        sm = Potts.initialization_system(c, :model)
        @test :m in ini_names(INI_M.unknowns(sm)) && issubset(Set([:ka, :kb]), ini_names(INI_M.parameters(sm)))
        sc = Potts.initialization_system(c, :cell)
        @test ini_names(INI_M.unknowns(sc)) == Set([:z])
        prob = PottsProblem(c, ini_op(), (0, 3))
        @test only(Array(prob.u0.model.m)) ≈ 4.0 rtol = 1.0e-12                    # ka / kb
        @test ini_u0(prob, :z) ≈ INI_VOL .+ 4.0 rtol = 1.0e-12                    # D(m) = 0 at the start
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
        @test all(u -> isapprox(only(Array(u.model.m)), 4.0; rtol = 1.0e-12), sol.u)  # a steady start stays
    end
end

@testitem "initialization: extend keeps the base's equations" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: extend keeps the base's equations" begin
        sys = IniExt(; name = :e)
        @test length(INI_M.initialization_equations(Potts.inner(sys))) == 2
        @test occursin("initialization", sprint(show, MIME"text/plain"(), sys))
        prob = PottsProblem(sys, ini_op(), (0, 1))
        @test ini_u0(prob, :Vt) == 2 .* INI_VOL
        @test ini_u0(prob, :v2) == 2 .* INI_VOL .+ 1
    end
end

@testitem "initialization: algebraic values from the operating point" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: algebraic values from the operating point" begin
        sys = IniHalf(; name = :h)
        prob = PottsProblem(sys, ini_op(:half => 3.0, :xd => [19.0, 15.0]), (0, 1))
        @test only(Array(prob.u0.model.m)) ≈ 6.0 rtol = 1.0e-12
        @test ini_u0(prob, :x) ≈ [1.0, 1.0] rtol = 1.0e-12                         # (xd − volume) / 3
        # keyed by the compiled model's symbol, the declared symbol or the name: the same values
        for key in (sys.xd, getproperty(sys, :xd), :xd)
            p = PottsProblem(sys, ini_op(key => [19.0, 15.0]), (0, 1))
            @test ini_u0(p, :x) ≈ [1.0, 1.0] rtol = 1.0e-12
        end
        # a model value with a cell condition: the cell problem reads the initialized model
        @test ini_error(() -> PottsProblem(sys, ini_op(:m => 1.0, :half => 3.0), (0, 1)), "overdetermined", "half", "m")
        @test ini_error(() -> PottsProblem(sys, ini_op(:xd => [1.0, 2.0, 3.0]), (0, 1)), "xd")
        # no algebraic value, no initialization: the values declared
        @test ini_u0(PottsProblem(sys, ini_op(), (0, 1)), :x) == [0.0, 0.0]
    end
end

@testitem "initialization: one solve per cell" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: one solve per cell" begin
        σ = zeros(Int32, 40, 40)
        n = 0
        for i in 1:2:40, j in 1:4:40
            n += 1
            σ[i, j:min(j + 1 + (n % 2), 40)] .= n          # volumes 2 and 3
        end
        vol = [Float64(count(==(c), σ)) for c in 1:n]
        prob = PottsProblem(IniMany(; name = :many), [ownership => σ, kind => fill(1, n)], (0, 1))
        r = ini_u0(prob, :r)
        @test all(c -> isapprox(r[c]^3 + r[c], vol[c] + 2c; rtol = 1.0e-9), 1:n)
        @test ini_u0(prob, :s) ≈ r .* (1:n) rtol = 1.0e-12
        @test length(unique(r)) == n                                          # each cell solved, not copied
    end
end

@testitem "initialization: rejections" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: rejections" begin
        @test ini_error(() -> PottsProblem(IniModelByCell(; name = :r), ini_op(), (0, 1)), "model variable", "`mm`", "model equation")
        @test ini_compile_error(() -> mtkcompile(IniReject(; name = :r, kind_case = :no_ode)), "D(v")
        @test ini_compile_error(() -> mtkcompile(IniReject(; name = :r, kind_case = :surface)), "surface")
        @test ini_error(() -> PottsProblem(IniReject(; name = :r, kind_case = :twice), ini_op(), (0, 1)), "overdetermined", "v")
        @test ini_compile_error(() -> mtkcompile(IniReject(; name = :r, kind_case = :draw)), "initialization")
        @test ini_compile_error(() -> mtkcompile(IniGatherRate(; name = :r)), "D(g")
        # errors name where the equation was written
        @test ini_compile_error(() -> mtkcompile(IniReject(; name = :r, kind_case = :surface)), "@initialization_equations")
    end
end

@testitem "initialization: results are checked against the conditions" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: results are checked against the conditions" begin
        # oracle: k·kx = volume; with k = 0 there is none (MTK's linear solve would return 0)
        @test ini_u0(PottsProblem(IniCoef(; name = :c, k = 2.0), ini_op(), (0, 1)), :kx) ≈ INI_VOL ./ 2 rtol = 1.0e-12
        @test ini_error(() -> PottsProblem(IniCoef(; name = :c), ini_op(), (0, 1)), "cell 1", "found no solution", "kx")
        # a coefficient zero for one cell only names that cell
        @test ini_error(() -> PottsProblem(IniCellCoef(; name = :c), ini_op(), (0, 1)), "cell 1", "zz")
        # inconsistent pair: no least-squares compromise; control: consistent (shift = 0) but
        # dependent, and an independent pair solves
        @test ini_error(() -> PottsProblem(IniPair(; name = :c), ini_op(), (0, 1)), "found no solution", "ta", "tb")
        @test ini_error(() -> PottsProblem(IniPair(; name = :c, shift = 0.0), ini_op(), (0, 1)), "uniquely", "ta", "tb")
        @test ini_error(() -> PottsProblem(IniDependent(; name = :c), ini_op(), (0, 1)), "uniquely", "sa", "sb")
        # small scales: the stop follows the size of the terms (oracle: sqrt(1e-20 V), sqrt(kp V / kd))
        p = PottsProblem(IniSmall(; name = :c), ini_op(), (0, 1))
        @test ini_u0(p, :ty) ≈ sqrt.(1.0e-20 .* INI_VOL) rtol = 1.0e-9
        @test ini_u0(p, :cc) ≈ sqrt.(1.0e-12 .* INI_VOL) rtol = 1.0e-9
        # no guess: 0.0 makes the Jacobian of `r^2 ~ volume` singular; an ArgumentError, not a LinearAlgebra one
        @test ini_error(() -> PottsProblem(IniNoGuess(; name = :c), ini_op(), (0, 1)), "initialization", "`r`", "guess")
        @test ini_error(() -> PottsProblem(IniNoRoot(; name = :c), ini_op(), (0, 1)), "found no solution", "`q`")
    end
end

@testitem "initialization: roots at zero and where the terms vanish" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: roots at zero and where the terms vanish" begin
        p = PottsProblem(IniRoots(; name = :z), ini_op(), (0, 1))
        for n in (:e1, :e2, :e3)
            @test all(v -> abs(v) <= 1.0e-9, ini_u0(p, n))
        end
        @test ini_u0(p, :e4) ≈ log.(1 .+ (INI_VOL .- 16) ./ 16) atol = 1.0e-12
        @test ini_u0(p, :s1) ≈ [π, π] rtol = 1.0e-9
        @test ini_u0(p, :c1) ≈ [π / 2, π / 2] rtol = 1.0e-9
        # a repeated root: solved to about √eps
        @test ini_u0(PottsProblem(IniRepeated(; name = :z), ini_op(), (0, 1)), :q2) ≈ [1.0, 1.0] atol = 1.0e-6
        # a flat root reached exactly (the start): the growing step still sees the equation
        @test ini_u0(PottsProblem(IniFlat(; name = :z), ini_op(), (0, 1)), :f3) == [0.0, 0.0]
    end
end

@testitem "initialization: flat equations, large and symbolic guesses" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: flat equations, large and symbolic guesses" begin
        @test ini_error(() -> PottsProblem(IniGuessed(; name = :f, kind_case = :kink, guess_val = 1.0), ini_op(), (0, 1)), "uniquely", "`v`")
        @test ini_error(() -> PottsProblem(IniGuessed(; name = :f, kind_case = :clamp, guess_val = 5.0), ini_op(), (0, 1)), "uniquely", "`v`")
        @test ini_u0(PottsProblem(IniGuessed(; name = :f, kind_case = :root, guess_val = 1.0e6), ini_op(), (0, 1)), :v) ≈ sqrt.(INI_VOL) rtol = 1.0e-12
        # the guess is the parameter's value for the problem: it picks the root
        @test ini_u0(PottsProblem(IniGuessed(; name = :f, kind_case = :root, use_pz = true), ini_op(), (0, 1)), :v) ≈ -sqrt.(INI_VOL) rtol = 1.0e-12
        @test ini_u0(PottsProblem(IniGuessed(; name = :f, kind_case = :root, use_pz = true, pz = 1.0), ini_op(), (0, 1)), :v) ≈ sqrt.(INI_VOL) rtol = 1.0e-12
    end
end

@testitem "initialization: kind tables" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: kind tables" begin
        @test ini_u0(PottsProblem(IniTable(; name = :t), ini_op(; kinds = [:A, :B]), (0, 1)), :kv) == [16.0, 36.0]
        @test ini_u0(PottsProblem(IniTable(; name = :t), ini_op(; kinds = [:B, :A]), (0, 1)), :kv) == [48.0, 12.0]
        s = Potts.initialization_system(mtkcompile(IniTable(; name = :t)), :cell)
        @test :g_kind in ini_names(INI_M.parameters(s))
        @test ini_compile_error(() -> mtkcompile(IniTable(; name = :t, fixed = true)), "kind table")
    end
end

@testitem "initialization: no value written changes nothing else" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    @testset "initialization: no value written changes nothing else" begin
        a, b = IniBare(; name = :n), IniZero(; name = :n)
        @test !Potts._written(only(Potts.declared_variables(a))) && Potts._written(only(Potts.declared_variables(b)))
        strip_expr(x) = x isa Expr ? Base.remove_linenums!(deepcopy(x)) :
            x isa Tuple ? map(strip_expr, x) : x
        ga, gb = generated_code(a), generated_code(b)
        @test keys(ga) == keys(gb)
        @test all(k -> strip_expr(getfield(ga, k)) == strip_expr(getfield(gb, k)), keys(ga))
        pa, pb = PottsProblem(a, ini_op(), (0, 1)), PottsProblem(b, ini_op(), (0, 1))
        @test pa.f.fingerprint == pb.f.fingerprint
        @test ini_u0(pa, :x) == ini_u0(pb, :x) == [0.0, 0.0]
        @test isempty(getfield(mtkcompile(a), :initialization)) && Potts.initialization_system(mtkcompile(a), :cell) === nothing
        # control: the detector sees a written value
        @test Potts._written(Potts.variable(only(Potts.Symbolics.@variables q(Potts.t)), :cell; default = 1.0))
    end
end

@testitem "initialization: SciML's initializealg" setup = [InitializationSetup] tags = [:potts, :initialization] begin
    SB = Potts.SciMLBase
    sys = IniKinds(; name = :k)
    op = ini_op(; kinds = [:A, :B])
    solved = [10 + 16 + 6.0, 20 + 12 + 6.0]
    # the default is `OverrideInit()`, and a user's nonlinear solver gives the same roots
    base = PottsProblem(sys, op, (0, 1))
    @test ini_u0(PottsProblem(sys, op, (0, 1); initializealg = SB.OverrideInit()), :p_1) == ini_u0(base, :p_1)
    broyden = PottsProblem(sys, op, (0, 1); initializealg = SB.OverrideInit(; nlsolve = Potts.SimpleNonlinearSolve.SimpleBroyden()))
    @test ini_u0(broyden, :p_1) ≈ sqrt.(INI_VOL) rtol = 1.0e-9
    @test ini_u0(broyden, :y) ≈ solved rtol = 1.0e-12
    # `abstol` stops the solve: a loose one accepts the guess
    loose = PottsProblem(sys, op, (0, 1); initializealg = SB.OverrideInit(; abstol = 1.0e6))
    @test !isapprox(ini_u0(loose, :p_1), sqrt.(INI_VOL); rtol = 1.0e-3)
    # `NoInit()` keeps the declared values, also on `remake`; `CheckInit()` checks them
    none = PottsProblem(sys, op, (0, 1); initializealg = SB.NoInit())
    @test ini_u0(none, :y) == [0.0, 0.0]
    @test ini_u0(Potts.SciMLBase.remake(none; u0 = op), :y) == [0.0, 0.0]
    @test solve(none, SequentialCPM()).retcode == SB.ReturnCode.Success
    @test_throws SB.CheckInitFailureError PottsProblem(sys, op, (0, 1); initializealg = SB.CheckInit())
    @test ini_u0(PottsProblem(IniBare(; name = :n), ini_op(), (0, 1); initializealg = SB.CheckInit()), :x) == [0.0, 0.0]
    # refusals: another algorithm, a negative tolerance, the keyword at `init`
    @test_throws ArgumentError PottsProblem(sys, op, (0, 1); initializealg = :newton)
    @test_throws ArgumentError PottsProblem(sys, op, (0, 1); initializealg = SB.OverrideInit(; reltol = -1.0))
    @test_throws ArgumentError init(base, SequentialCPM(); initializealg = SB.NoInit())
end
