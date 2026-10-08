# Entity-local initialization (`@initialization_equations`, `Potts.initialization_system`),
# beside the frozen acceptance file p6_0bo_initialization.jl: the `kind` built-in, parameter
# expressions as fixed values, vector components with guesses, `D(m)` of a model ODE, `extend`,
# `Float32` problems, algebraic model variables from the operating point, many cells, and the
# rejections the frozen file leaves to the implementer.

const INI_M = Potts.ModelingToolkitBase
ini_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:5] .= 2; s)      # volumes 16, 12
ini_op(extra...; kinds = [1, 1]) = Any[ownership => ini_sigma(), kind => kinds, extra...]
ini_u0(prob, n) = Vector{Float64}(Array(getproperty(prob.u0.cell, n)))
ini_names(xs) = Set{Symbol}(Potts.SymbolicIndexingInterface.getname(x) for x in xs)
ini_error(f, words...) = try
    f()
    false
catch err
    e = err isa LoadError ? err.error : err
    ok = e isa ArgumentError && all(w -> occursin(w, sprint(showerror, e)), words)
    ok || @info "initialization: expected an ArgumentError naming $(words)" exception = e
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

@testset "initialization: kind, parameter expressions, vector guesses" begin
    prob = PottsProblem(IniKinds(; name = :k), ini_op(; kinds = [:A, :B]), (0, 1))
    @test ini_u0(prob, :y) ≈ [10 + 16 + 6.0, 20 + 12 + 6.0] rtol = 1e-12
    @test ini_u0(prob, :p_1) ≈ sqrt.(INI_VOL) rtol = 1e-9
    @test ini_u0(prob, :p_2) ≈ -sqrt.(INI_VOL) rtol = 1e-9
    @test !isapprox(ini_u0(prob, :p_2), sqrt.(INI_VOL); rtol = 1e-3)          # control: the other root
    # the parameter is read at its problem value
    prob2 = PottsProblem(IniKinds(; name = :k, c0 = 1.0), ini_op(; kinds = [:A, :B]), (0, 1))
    @test ini_u0(prob2, :y) ≈ [10 + 16 + 2.0, 20 + 12 + 2.0] rtol = 1e-12
    # the template: guesses from the vector's metadata, `w` fixed at its written value
    s = Potts.initialization_system(mtkcompile(IniKinds(; name = :k)), :cell)
    @test issubset(Set([:y, :w, :p_1, :p_2]), ini_names(INI_M.unknowns(s)))
    @test :c0 in ini_names(INI_M.parameters(s))
    @test length(INI_M.initialization_equations(s)) == 3
    # Float32 problems are initialized in Float64 and stored as Float32
    p32 = PottsProblem(IniKinds(; name = :k), ini_op(; kinds = [:A, :B]), (0, 1); T = Float32)
    @test eltype(p32.u0.cell.y) === Float32 && ini_u0(p32, :y) == Float64.(Float32.([32.0, 38.0]))
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

@testset "initialization: D(m) of a model ODE" begin
    c = mtkcompile(IniModelODE(; name = :m))
    sm = Potts.initialization_system(c, :model)
    @test :m in ini_names(INI_M.unknowns(sm)) && issubset(Set([:ka, :kb]), ini_names(INI_M.parameters(sm)))
    sc = Potts.initialization_system(c, :cell)
    @test ini_names(INI_M.unknowns(sc)) == Set([:z])
    prob = PottsProblem(c, ini_op(), (0, 3))
    @test only(Array(prob.u0.model.m)) ≈ 4.0 rtol = 1e-12                    # ka / kb
    @test ini_u0(prob, :z) ≈ INI_VOL .+ 4.0 rtol = 1e-12                    # D(m) = 0 at the start
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)))
    @test all(u -> isapprox(only(Array(u.model.m)), 4.0; rtol = 1e-12), sol.u)  # a steady start stays
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

@testset "initialization: extend keeps the base's equations" begin
    sys = IniExt(; name = :e)
    @test length(INI_M.initialization_equations(sys)) == 2
    @test occursin("initialization", sprint(show, MIME"text/plain"(), sys))
    prob = PottsProblem(sys, ini_op(), (0, 1))
    @test ini_u0(prob, :Vt) == 2 .* INI_VOL
    @test ini_u0(prob, :v2) == 2 .* INI_VOL .+ 1
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

@testset "initialization: algebraic values from the operating point" begin
    sys = IniHalf(; name = :h)
    prob = PottsProblem(sys, ini_op(:half => 3.0, :xd => [19.0, 15.0]), (0, 1))
    @test only(Array(prob.u0.model.m)) ≈ 6.0 rtol = 1e-12
    @test ini_u0(prob, :x) ≈ [1.0, 1.0] rtol = 1e-12                         # (xd − volume) / 3
    # keyed by the compiled model's symbol, the declared symbol or the name: the same values
    for key in (complete(sys).xd, getproperty(sys, :xd), :xd)
        p = PottsProblem(sys, ini_op(key => [19.0, 15.0]), (0, 1))
        @test ini_u0(p, :x) ≈ [1.0, 1.0] rtol = 1e-12
    end
    # a model value with a cell condition: the cell problem reads the initialized model
    @test ini_error(() -> PottsProblem(sys, ini_op(:m => 1.0, :half => 3.0), (0, 1)), "overdetermined", "half", "m")
    @test ini_error(() -> PottsProblem(sys, ini_op(:xd => [1.0, 2.0, 3.0]), (0, 1)), "xd")
    # no algebraic value, no initialization: the values declared
    @test ini_u0(PottsProblem(sys, ini_op(), (0, 1)), :x) == [0.0, 0.0]
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
    @test all(c -> isapprox(r[c]^3 + r[c], vol[c] + 2c; rtol = 1e-9), 1:n)
    @test ini_u0(prob, :s) ≈ r .* (1:n) rtol = 1e-12
    @test length(unique(r)) == n                                          # each cell solved, not copied
end

# rejections the frozen file leaves to the implementer
@potts_model IniNoODE begin
    @kinds medium A
    @variables v(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations D(v) ~ 0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniSurface begin
    @kinds medium A
    @variables v(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations v ~ surface
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniTwice begin
    @kinds medium A
    @variables v(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations begin
        v ~ volume
        v ~ 2volume
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniDraw begin
    @kinds medium A
    @variables v(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations v ~ rand()
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

@testset "initialization: rejections" begin
    @test ini_error(() -> PottsProblem(IniModelByCell(; name = :r), ini_op(), (0, 1)), "model variable", "`mm`", "model equation")
    @test ini_error(() -> mtkcompile(IniNoODE(; name = :r)), "D(v", "ODE")
    @test ini_error(() -> mtkcompile(IniSurface(; name = :r)), "initialization", "surface")
    @test ini_error(() -> PottsProblem(IniTwice(; name = :r), ini_op(), (0, 1)), "overdetermined", "v")
    @test ini_error(() -> mtkcompile(IniDraw(; name = :r)), "initialization")
    @test ini_error(() -> mtkcompile(IniGatherRate(; name = :r)), "initialization", "D(g")
    # errors name where the equation was written
    @test ini_error(() -> mtkcompile(IniSurface(; name = :r)), "@initialization_equations", "initialization.jl")
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

@testset "initialization: results are checked against the conditions" begin
    # oracle: k·kx = volume; with k = 0 there is none (MTK's linear solve would return 0)
    @test ini_u0(PottsProblem(IniCoef(; name = :c, k = 2.0), ini_op(), (0, 1)), :kx) ≈ INI_VOL ./ 2 rtol = 1e-12
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
    @test ini_u0(p, :ty) ≈ sqrt.(1.0e-20 .* INI_VOL) rtol = 1e-9
    @test ini_u0(p, :cc) ≈ sqrt.(1.0e-12 .* INI_VOL) rtol = 1e-9
    # no guess: 0.0 makes the Jacobian of `r^2 ~ volume` singular; an ArgumentError, not a LinearAlgebra one
    @test ini_error(() -> PottsProblem(IniNoGuess(; name = :c), ini_op(), (0, 1)), "initialization", "`r`", "guess")
    @test ini_error(() -> PottsProblem(IniNoRoot(; name = :c), ini_op(), (0, 1)), "found no solution", "`q`")
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

@testset "initialization: roots at zero and where the terms vanish" begin
    p = PottsProblem(IniRoots(; name = :z), ini_op(), (0, 1))
    for n in (:e1, :e2, :e3)
        @test all(v -> abs(v) <= 1e-9, ini_u0(p, n))
    end
    @test ini_u0(p, :e4) ≈ log.(1 .+ (INI_VOL .- 16) ./ 16) atol = 1e-12
    @test ini_u0(p, :s1) ≈ [π, π] rtol = 1e-9
    @test ini_u0(p, :c1) ≈ [π / 2, π / 2] rtol = 1e-9
    # a repeated root: solved to about √eps
    @test ini_u0(PottsProblem(IniRepeated(; name = :z), ini_op(), (0, 1)), :q2) ≈ [1.0, 1.0] atol = 1e-6
    # a flat root reached exactly (the start): the growing step still sees the equation
    @test ini_u0(PottsProblem(IniFlat(; name = :z), ini_op(), (0, 1)), :f3) == [0.0, 0.0]
end

# flat equations are refused (the finite-difference step never crosses a kink or a branch);
# a large guess does not loosen the check; a guess may be an expression of parameters
@potts_model IniKink begin
    @kinds medium A
    @variables v(cell), [guess = 1.0]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations max(v, 1000.0) ~ 1000.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniClamp begin
    @kinds medium A
    @variables v(cell), [guess = 5.0]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations clamp(v, -1.0, 1.0) ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniBigGuess begin
    @kinds medium A
    @variables v(cell), [guess = 1.0e6]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations v^2 ~ volume
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniParamGuess begin
    @kinds medium A
    @parameters pz = -1.0
    @variables v(cell), [guess = pz]
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations v^2 ~ volume
    @sweep Metropolis(; temperature = 1.0)
end

@testset "initialization: flat equations, large and symbolic guesses" begin
    @test ini_error(() -> PottsProblem(IniKink(; name = :f), ini_op(), (0, 1)), "uniquely", "`v`")
    @test ini_error(() -> PottsProblem(IniClamp(; name = :f), ini_op(), (0, 1)), "uniquely", "`v`")
    @test ini_u0(PottsProblem(IniBigGuess(; name = :f), ini_op(), (0, 1)), :v) ≈ sqrt.(INI_VOL) rtol = 1e-12
    # the guess is the parameter's value for the problem: it picks the root
    @test ini_u0(PottsProblem(IniParamGuess(; name = :f), ini_op(), (0, 1)), :v) ≈ -sqrt.(INI_VOL) rtol = 1e-12
    @test ini_u0(PottsProblem(IniParamGuess(; name = :f, pz = 1.0), ini_op(), (0, 1)), :v) ≈ sqrt.(INI_VOL) rtol = 1e-12
end

# kind tables are read at the cell's own kind
@potts_model IniTable begin
    @kinds medium A B
    @parameters g[kind] = [0.0, 1.0, 3.0]
    @variables kv(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations kv ~ g[kind] * volume
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model IniTableFixed begin
    @kinds medium A B
    @parameters g[kind] = [0.0, 1.0, 3.0]
    @variables kv(cell)
    @lattice Lattice((12, 8))
    @energy cells => (volume - 14.0)^2
    @initialization_equations kv ~ g[2] * volume
    @sweep Metropolis(; temperature = 1.0)
end

@testset "initialization: kind tables" begin
    @test ini_u0(PottsProblem(IniTable(; name = :t), ini_op(; kinds = [:A, :B]), (0, 1)), :kv) == [16.0, 36.0]
    @test ini_u0(PottsProblem(IniTable(; name = :t), ini_op(; kinds = [:B, :A]), (0, 1)), :kv) == [48.0, 12.0]
    s = Potts.initialization_system(mtkcompile(IniTable(; name = :t)), :cell)
    @test :g_kind in ini_names(INI_M.parameters(s))
    @test ini_error(() -> mtkcompile(IniTableFixed(; name = :t)), "kind table", "g[kind]")
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

@testset "initialization: no value written changes nothing else" begin
    a, b = IniBare(; name = :n), IniZero(; name = :n)
    @test !Potts._written(only(Potts.variables(a))) && Potts._written(only(Potts.variables(b)))
    @test string(generated_code(a)) == string(generated_code(b))
    pa, pb = PottsProblem(a, ini_op(), (0, 1)), PottsProblem(b, ini_op(), (0, 1))
    @test pa.f.fingerprint == pb.f.fingerprint
    @test ini_u0(pa, :x) == ini_u0(pb, :x) == [0.0, 0.0]
    @test isempty(mtkcompile(a).initialization) && Potts.initialization_system(mtkcompile(a), :cell) === nothing
    # control: the detector sees a written value
    @test Potts._written(Potts.variable(only(Potts.Symbolics.@variables q(Potts.t)), :cell; default = 1.0))
end
