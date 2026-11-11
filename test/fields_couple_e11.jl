# F4-E11 to F4-E15 (gaps found by the Potts test port F4-B4t, ~/lpwork/f4B4t/EVIDENCE.txt). Until
# F4-B6 each model here was checked bitwise against its A form; now the oracles are an
# independent spelling (an array field against the same fields as scalars) and LatticePDE's own
# run of the same PDESystem (σ frozen: no cells). Uses `cp_msg` and `CpHost` of fields_couple.jl.
# Negative controls (each item's src change reverted alone in the test copy):
# ~/lpwork/f4E/nc-e11e15.log.

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
# the same fields as scalars: `ua, ub` for `u`, `wa, wb` for `w`
@variables ua(..) = 0.5 ub(..) = 0.5 wa(..) = 0.0 wb(..) = 0.0
const UA, UB, WA, WB = ua(t, x, y), ub(t, x, y), wa(t, x, y), wb(t, x, y)
sfi() = pdesystem([Differential(t)(UA) ~ 0.5 * Δ(UA) - 40 * UA / (0.025 + UA) + 20, Differential(t)(UB) ~ 0.5 * Δ(UB) - UB + UA];
    name = :sfi)
sfc() = pdesystem([0 ~ 0.1 * Δ(WA) - 0.1 * WA + 5.0 * WB + 0.5 * k(t, x, y), 0 ~ 0.1 * Δ(WB) - WB - 5.0 * WA]; name = :sfc)
end
@potts_model CeHostArr begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
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
@potts_model CeFiDriveB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields u = CeArr.fi()
    @drive copy => -10.0 * (u[2][target] - u[2][source])
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFcCompB begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields w = CeArr.fc() (k => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
# the scalar spellings
@potts_model CeFiScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields CeArr.sfi()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFiDriveScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields ua, ub = CeArr.sfi()
    @drive copy => -10.0 * (ub[target] - ub[source])
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFcScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields CeArr.sfc() (k => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end
# the values of each MCS, by position (the names differ)
ce_values(r) = [last.(filter(p -> !endswith(string(first(p)), "__next"), step)) for step in r]

@testset "F4-E11: array fields of a PDESystem are the components u_1, …, u_n" begin
    op = ce_op((12, 10))
    for fs in (BackwardEuler(), CrankNicolson())
        a, b = ce_steps(CeFiCompB(; name = :f), op, 3; field_solver = fs), ce_steps(CeFiScal(; name = :f), op, 3; field_solver = fs)
        @test filter(n -> !endswith(string(n), "__next"), first.(a[end])) == [:u_1, :u_2] && ce_values(a) == ce_values(b)   # bitwise, by component
    end
    a, b = ce_steps(CeFcCompB(; name = :f), op, 3), ce_steps(CeFcScal(; name = :f), op, 3)
    @test ce_values(a) == ce_values(b) && maximum(abs, last(a[end][1])) > 0.01
    # `Potts.couple` too, and `@fields u = …` bound the vector of the components
    m = Potts.couple(CeHostArr(; name = :h), CeArr.fi())
    @test ce_steps(m, op, 3; field_solver = BackwardEuler()) == ce_steps(CeFiCompB(; name = :f), op, 3; field_solver = BackwardEuler())
    d = ce_steps(CeFiDriveB(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3)
    @test ce_values(d) == ce_values(ce_steps(CeFiDriveScal(; name = :f), op, 3; field_solver = BackwardEuler(), seed = 3))
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
# (`dims`: the lattice's domain, for LatticePDE's own run of the same system)
dom(dims) = dims === nothing ? Any[] : lattice_domain(t, (x, y), dims)
adv(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([ux, 0.0], C) + s * y]; name = :adv, domain = dom(dims))
advconst(dims = nothing) = pdesystem([Differential(t)(C) ~ -Advect(Upwind1())([0.3, 0.0], C) + s * y]; name = :advc,
    domain = dom(dims))
# (the model's lattice is periodic: LatticePDE's run takes it as periodic conditions)
burgers(dims = nothing) = pdesystem([Differential(t)(CB) ~ -Advect(Upwind1())([CB, 0.0], CB)],
    dims === nothing ? Any[] : [cb(t, 0, y) ~ cb(t, dims[1], y), cb(t, x, 0) ~ cb(t, x, dims[2])]; name = :burgers, domain = dom(dims))
ivadv(dims = nothing) = pdesystem([Differential(t)(CI) ~ 0.1 * Δ(CI) - Advect(Upwind1())([0.05 * (1 + x), 0.0], CI)]; name = :ivadv,
    domain = dom(dims))
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
    LP = Potts.LatticePDE
    e0(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]
    run(M, op, k, fs) = solve(PottsProblem(M(; name = :f), op, (0, k); field_solver = fs, seed = 1), SequentialCPM()).u[end].site
    # LatticePDE's own run of the same system (no cells: σ is the medium), `k` windows of length 1
    own(sys, u0, k, alg) = reshape(LP.solve(LP.remake(LP.discretize(sys, LP.LatticeDiscretization(LP.Grid(size(u0)); T = Float64));
        u0 = vec(u0), tspan = (0.0, Float64(k))), alg).u[end], size(u0))
    c0 = [0.01 * (i + 3j) for i in 1:8, j in 1:6]
    for (B, sys) in ((CeAdvB, CeAdv.adv((8, 6))), (CeAdvConstB, CeAdv.advconst((8, 6))))
        b = run(B, [e0((8, 6)); :c => c0], 2, ExplicitEuler(; substeps = 4))
        @test b.c == own(sys, c0, 2, LP.ExplicitEuler(; dt = 1.0, substeps = 4)) && maximum(b.c) > 0
    end
    cb0 = [0.5 + 0.4 * sin(2π * (i - 0.5) / 32) for i in 1:32, j in 1:32]
    # (the user's count past the linearized limit warns once per session, fields.jl tests it)
    b, o = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        run(CeBurgersB, [e0((32, 32)); :cb => cb0], 5, ExplicitEuler(; substeps = 8)),
        own(CeAdv.burgers((32, 32)), cb0, 5, LP.ExplicitEuler(; dt = 1.0, substeps = 8))
    end
    @test b.cb == o && b.cb != cb0
    ci0 = [0.01 * i * j for i in 1:16, j in 1:16]
    b = run(CeIvAdvB, [e0((16, 16)); :ci => ci0], 2, ExplicitEuler())
    @test b.ci == own(CeAdv.ivadv((16, 16)), ci0, 2, LP.ExplicitEuler(; dt = 1.0)) && b.ci != ci0
end

# --- E13: a centroid-reading mask in a condition ---------------------------------------------
# The moment trackers were allocated for `@boundary` masks only: a masked condition (a
# PDESystem's) that reads `centroid(owner, 1)` met no trackers. The RHMaskCentroid oracle
# (test/ref_helpers.jl): cell 1 (centroid 6) is clamped to 7, cell 2 (centroid 2) and the
# medium stay 0.
module CeMask
using Potts: Potts
using Potts.Fields
@variables c(..) = 0.0 m(..)::Bool [input = true]
const C = c(t, x, y)
sys() = pdesystem([Differential(t)(C) ~ -C], [C ~ masked(m(t, x, y), 7.0)]; name = :mask)
end
@potts_model CeMaskB begin
    @kinds medium ka
    @lattice Lattice((12, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 1.0e6 * (volume - 9.0)^2
    @fields CeMask.sys() (m => (kind == ka) & (centroid(owner, 1) > 4.0))
    @sweep Metropolis(; temperature = 0.01)
end
function ce_mask_sigma()
    σ = zeros(Int32, 12, 10)
    σ[5:7, 4:6] .= 1
    σ[1:3, 4:6] .= 2
    return σ
end

@testset "F4-E13: a centroid in a masked condition allocates the moment trackers" begin
    for M in (CeMaskB,)
        prob = PottsProblem(M(; name = :bm), [ownership => ce_mask_sigma(), kind => [:ka, :ka]], (0, 1); T = Float64,
            field_solver = ExplicitEuler(substeps = 1))
        @test hasproperty(prob.u0.cell, :anchor)
        u = solve(prob, SequentialCPM()).u[end]
        @test Array(u.σ) == ce_mask_sigma() && Array(u.site.c) == 7.0 .* (ce_mask_sigma() .== 1)
    end
end

# --- E14: a face condition on a field with no spatial operator ---------------------------------
# A face sets the ghost values of a spatial operator; on `D(c) ~ 0.1 - 0.01c` it would do
# nothing. `@boundary` refused it; a condition (a PDESystem's) built.
module CeFace
using Potts: Potts
using Potts.Fields
@variables c(..) = 0.0
const C = c(t, x, y)
nolap() = pdesystem([Differential(t)(C) ~ 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :nolap)
lap() = pdesystem([Differential(t)(C) ~ 0.1 * Δ(C) + 0.1 - 0.01 * C], [c(t, 0, y) ~ 1.0]; name = :lap)
end
@potts_model CeFaceB begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields CeFace.nolap()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CeFaceLapB begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields CeFace.lap()
    @sweep Metropolis(; temperature = 1.0)
end
@testset "F4-E14: a face condition on a field with no spatial operator is refused" begin
    op = [ownership => zeros(Int32, 8, 6), kind => Symbol[]]
    e = cp_msg(() -> PottsProblem(CeFaceB(; name = :f), op, (0, 1)))
    @test occursin("the PDESystem `nolap`", e) && occursin("has no `Δ(c)`", e) && occursin("would do nothing", e) ||
          (println(e); false)
    @test PottsProblem(CeFaceLapB(; name = :f), op, (0, 1)) isa PottsProblem          # control: with `Δ(c)`
end

# --- E15: a fingerprint that depends on the session -----------------------------------------
# A neighbourhood with an anonymous weight printed its compiler-generated type name
# (`Main.var"#24#25"`) into the fingerprint seed; the number depends on what was defined before
# it in the session (the B4t pad tests: CsWComp and CsWSurf in cell_sums_models.jl). Two
# closures with the same body have two such names: the fingerprints must agree.
const CE_W1 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
const CE_W2 = Potts.CorePotts.Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o)))
for (nm, w) in ((:CeW1, :CE_W1), (:CeW2, :CE_W2))
    @eval @potts_model $nm begin
        @kinds medium A
        @lattice Lattice((20, 20); boundary = Periodic(), neighborhood = $w)
        @energy cells => (volume - 16.0)^2
        @sweep Metropolis(; temperature = 10.0)
    end
end

@testset "F4-E15: a neighbourhood's anonymous weight does not enter the fingerprint by name" begin
    @test typeof(CE_W1.weight) != typeof(CE_W2.weight)
    op = (σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; [ownership => σ, kind => [:A]])
    f1, f2 = (PottsProblem(M(; name = :w), op, (0, 1)).f.fingerprint for M in (CeW1, CeW2))
    @test f1 == f2
    # the resolved weights do enter it: another weight gives another fingerprint
    W3 = Potts.CorePotts.Weighted(Moore(1), o -> 2 / sqrt(sum(abs2, o)))
    @eval @potts_model CeW3 begin
        @kinds medium A
        @lattice Lattice((20, 20); boundary = Periodic(), neighborhood = $W3)
        @energy cells => (volume - 16.0)^2
        @sweep Metropolis(; temperature = 10.0)
    end
    @test Base.invokelatest(() -> PottsProblem(CeW3(; name = :w), op, (0, 1)).f.fingerprint) != f1
    # a neighbourhood without a closure keeps its printed form (and so its fingerprint)
    @test !occursin("resolved(", Potts._fingerprint_seed(CpHost(; name = :m), Float64))
end
