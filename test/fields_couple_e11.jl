# F4-E11 to F4-E15 (gaps found by the Potts test port F4-B4t, ~/lpwork/f4B4t/EVIDENCE.txt). Each
# model below is its A form (as at 4ca38af7 in test/) beside the B form, which must run bitwise
# equal. Uses `cp_msg` and `CpHost` of fields_couple.jl. Negative controls (each item's src
# change reverted alone in the test copy): ~/lpwork/f4E/nc-e11e15.log.

ce_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
# every site field after each of `k` MCS
function ce_steps(m, op, k; kw...)
    integ = init(PottsProblem(m, op, (0, k); kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); st = current_state(integ).site;
             [n => copy(Array(getproperty(st, n))) for n in sort!(collect(propertynames(st)))]) for _ in 1:k]
end

# --- E11: array (component) fields -----------------------------------------------------------
# `couple` failed with `getindex(::Num, ::Num)`: `u[i]` of an array dependent variable. Now the
# components are the fields `u_1, u_2` that `@variables u(field)[1:2]` declares.
module CeArr
using Potts: Potts
using Potts.Fields
@variables u(..)[1:2] = [0.5, 0.5] w(..)[1:2] = [0.0, 0.0] k(..)::Bool [input = true]
const U, W = u(t, x, y), w(t, x, y)
fi() = pdesystem([Differential(t)(U[1]) ~ 0.5 * Δ(U[1]) - 40 * U[1] / (0.025 + U[1]) + 20,
    Differential(t)(U[2]) ~ 0.5 * Δ(U[2]) - U[2] + U[1]]; name = :fi)
fc() = pdesystem([0 ~ 0.1 * Δ(W[1]) - 0.1 * W[1] + 5.0 * W[2] + 0.5 * k(t, x, y), 0 ~ 0.1 * Δ(W[2]) - W[2] - 5.0 * W[1]];
    name = :fc)
@variables q(..)[1:2, 1:2] = 0.0
const Q = q(t, x, y)
mat() = pdesystem([Differential(t)(Q[i, j]) ~ -Q[i, j] for i in 1:2 for j in 1:2]; name = :mat)
end
@potts_model CeHostArr begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFiCompA begin
    @kinds medium A[frozen]
    @variables u(field)[1:2] = 0.5
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u[1]) ~ 0.5 * Δ(u[1]) - 40 * u[1] / (0.025 + u[1]) + 20
        D(u[2]) ~ 0.5 * Δ(u[2]) - u[2] + u[1]
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFiCompB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields u = CeArr.fi()
    @sweep Metropolis(; temperature = 1.0)
end
# a later statement reads a component through the name `@fields u = …` binds
@potts_model CeFiDriveA begin
    @kinds medium A[frozen]
    @variables u(field)[1:2] = 0.5
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        D(u[1]) ~ 0.5 * Δ(u[1]) - 40 * u[1] / (0.025 + u[1]) + 20
        D(u[2]) ~ 0.5 * Δ(u[2]) - u[2] + u[1]
    end
    @drive copy => -10.0 * (u[2][target] - u[2][source])
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFiDriveB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields u = CeArr.fi()
    @drive copy => -10.0 * (u[2][target] - u[2][source])
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFcCompA begin
    @kinds medium A[frozen]
    @variables w(field)[1:2] = 0.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @equations begin
        0 ~ 0.1 * Δ(w[1]) - 0.1 * w[1] + 5.0 * w[2] + 0.5 * (kind == A)
        0 ~ 0.1 * Δ(w[2]) - w[2] - 5.0 * w[1]
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFcCompB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields w = CeArr.fc() (k => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "F4-E11: array fields of a PDESystem are the components of @variables u(field)[1:n]" begin
    op = ce_op((12, 10))
    for fs in (BackwardEuler(), CrankNicolson())
        a, b = ce_steps(CeFiCompA(; name = :f), op, 3; field_solver = fs), ce_steps(CeFiCompB(; name = :f), op, 3; field_solver = fs)
        @test filter(n -> !endswith(string(n), "__next"), first.(a[end])) == [:u_1, :u_2] && a == b   # bitwise, by component
    end
    a, b = ce_steps(CeFcCompA(; name = :f), op, 3), ce_steps(CeFcCompB(; name = :f), op, 3)
    @test a == b && maximum(abs, last(a[end][1])) > 0.01
    # `Potts.couple` too, and `@fields u = …` bound the vector of the components
    m = Potts.couple(CeHostArr(; name = :h), CeArr.fi())
    @test ce_steps(m, op, 3; field_solver = BackwardEuler()) == ce_steps(CeFiCompA(; name = :f), op, 3; field_solver = BackwardEuler())
    @test ce_steps(CeFiDriveA(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3) ==
          ce_steps(CeFiDriveB(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3)
    # only vectors: a matrix of fields is refused by its shape
    e = cp_msg(() -> Potts.couple(CeHostArr(; name = :h), CeArr.mat()))
    @test occursin("has the shape (2, 2)", e) && occursin("`q(..)[1:n]`", e) || (println(e); false)
end

# a face condition on a component, `u(t, 0, y)[1] ~ 1.0`: bitwise the same system in two
# scalar fields `a, b` with `a(t, 0, y) ~ 1.0`
module CeArrF
using Potts: Potts
using Potts.Fields
@variables u(..)[1:2] = [0.0, 0.0] a(..) = 0.0 b(..) = 0.0
const U, A, B = u(t, x, y), a(t, x, y), b(t, x, y)
arr() = pdesystem([Differential(t)(U[1]) ~ 0.5 * Δ(U[1]) - 0.1 * U[1], Differential(t)(U[2]) ~ 0.5 * Δ(U[2]) + 0.1 * U[1] - 0.2 * U[2]],
    [u(t, 0, y)[1] ~ 1.0]; name = :arrf)
sca() = pdesystem([Differential(t)(A) ~ 0.5 * Δ(A) - 0.1 * A, Differential(t)(B) ~ 0.5 * Δ(B) + 0.1 * A - 0.2 * B],
    [a(t, 0, y) ~ 1.0]; name = :scaf)
end

@testset "F4-E11: a face condition on a component of an array field" begin
    op = ce_op((12, 10))
    for fs in (ExplicitEuler(), BackwardEuler())
        ra = ce_steps(Potts.couple(CeHostArr(; name = :h), CeArrF.arr()), op, 3; field_solver = fs)
        rs = ce_steps(Potts.couple(CeHostArr(; name = :h), CeArrF.sca()), op, 3; field_solver = fs)
        @test [last.(r) for r in ra] == [last.(r) for r in rs] && maximum(last(ra[end][1])) > 0.5
    end
end

# --- E12: `Advect` with a velocity vector ------------------------------------------------------
# `_pde_term` sent the shape argument of `SymbolicUtils.array_literal` (`[ux, 0.0]`) through the
# generic path (a MethodError); now the shape is kept and the elements are mapped.
module CeAdv
using Potts: Potts
using Potts.Fields
@parameters ux = 0.3 s = 0.01
@variables c(..) = 0.0 cb(..) = 0.5 [bounds = (0, 1)] ci(..) = 0.5
const C, CB, CI = c(t, x, y), cb(t, x, y), ci(t, x, y)
adv() = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([ux, 0.0], C) + s * y]; name = :adv)
advconst() = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([0.3, 0.0], C) + s * y]; name = :advc)
burgers() = pdesystem([Differential(t)(CB) ~ -Advect(Upwind1())([CB, 0.0], CB)]; name = :burgers)
ivadv() = pdesystem([Differential(t)(CI) ~ 0.1 * Δ(CI) - Advect(Upwind1())([0.05 * (1 + x), 0.0], CI)]; name = :ivadv)
end
@potts_model CeAdvA begin
    @kinds medium A
    @parameters begin
        ux = 0.3
        s = 0.01
    end
    @variables c(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ -Advect(Upwind1())([ux, 0.0], c) + s * y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeAdvConstA begin
    @kinds medium A
    @parameters s = 0.01
    @variables c(field) = 0.0
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(c) ~ -Advect(Upwind1())([0.3, 0.0], c) + s * y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeBurgersA begin
    @kinds medium A
    @variables cb(field) = 0.5, [bounds = (0, 1)]
    @lattice Lattice((32, 32); boundary = Periodic())
    @energy cells(A) => (volume - 25.0)^2
    @equations D(cb) ~ -Advect(Upwind1())([cb, 0.0], cb)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeIvAdvA begin
    @kinds medium A
    @variables ci(field) = 0.5
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @equations D(ci) ~ 0.1 * Δ(ci) - Advect(Upwind1())([0.05 * (1 + x), 0.0], ci)
    @sweep Metropolis(; temperature = 1.0)
end
for (nm, dims, bnd, sys) in ((:CeAdvB, (8, 6), :(Closed()), :(CeAdv.adv())), (:CeAdvConstB, (8, 6), :(Closed()), :(CeAdv.advconst())),
                             (:CeBurgersB, (32, 32), :(Periodic()), :(CeAdv.burgers())), (:CeIvAdvB, (16, 16), :(Closed()), :(CeAdv.ivadv())))
    @eval @potts_model $nm begin
        @kinds medium A
        @lattice Lattice($dims; boundary = $bnd)
        @energy cells(A) => (volume - 9.0)^2
        @fields $sys
        @sweep Metropolis(; temperature = 1.0)
    end
end

@testset "F4-E12: Advect with a velocity vector in a coupled PDESystem" begin
    e0(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]
    c0 = [0.01 * (i + 3j) for i in 1:8, j in 1:6]
    run(M, op, k, fs) = solve(PottsProblem(M(; name = :f), op, (0, k); field_solver = fs, seed = 1), SequentialCPM()).u[end].site
    for (A, B) in ((CeAdvA, CeAdvB), (CeAdvConstA, CeAdvConstB))
        a, b = run(A, [e0((8, 6)); :c => c0], 2, ExplicitEuler(; substeps = 4)), run(B, [e0((8, 6)); :c => c0], 2, ExplicitEuler(; substeps = 4))
        @test a == b && maximum(a.c) > 0
    end
    cb0 = [0.5 + 0.4 * sin(2π * (i - 0.5) / 32) for i in 1:32, j in 1:32]
    # (the user's count past the linearized limit warns once per session, fields.jl tests it)
    a, b = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        run(CeBurgersA, [e0((32, 32)); :cb => cb0], 5, ExplicitEuler(; substeps = 8)),
        run(CeBurgersB, [e0((32, 32)); :cb => cb0], 5, ExplicitEuler(; substeps = 8))
    end
    @test a == b && a.cb != cb0
    ci0 = [0.01 * i * j for i in 1:16, j in 1:16]
    a, b = run(CeIvAdvA, [e0((16, 16)); :ci => ci0], 2, ExplicitEuler()), run(CeIvAdvB, [e0((16, 16)); :ci => ci0], 2, ExplicitEuler())
    @test a == b && a.ci != ci0
end
