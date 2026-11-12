# The top-level definitions of fields_implicit.jl, fields_steppers.jl (converted from the include-into-Main suite, TS1a).

@testsetup module ImplicitSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

# ---- from fields_implicit.jl ------------------------------------------------------------------------
using Potts: CorePotts

using StableRNGs: StableRNG

const FIP = Potts.LatticeFields.Problems

const FiRC = Potts.SciMLBase.ReturnCode

using Potts.LatticeFields.IR: fieldid


# the models' fields, coupled with `@fields` (F4-B4t; before, written in `@equations` and `@bcs`):
# a kind or a CPM term is a bound input, a kind table the model's
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module FiPDE
using ..FieldPDE
@variables c(..) e(..) o(..) u(..) w(..) kA(..)::Bool [input = true] kM(..)::Bool [input = true] vol(..) [input = true]
@variables big(..)::Bool [input = true] dk(..) [input = true]
const X = (t, x, y)
const C, E, KA = c(X...), e(X...), kA(X...)
const D = (12, 10)
ic(f, v = 0.0) = f(0, x, y) ~ v
mix() = (@parameters Dc = 0.4 kd = 0.3 s = 0.5 v = 1.5;
         pdesys([Dt(C) ~ Dc * Δ(C) - kd * C + s * KA, Dt(E) ~ 0.02 + 0.01 * x], [ic(c), ic(e), C ~ masked(E >= 0.5, v)], D,
             [C, E, KA], [Dc, kd, s, v]))
# `rate` with the conditions `bcs`, no parameters, on lattice `dims`
field1(rate, bcs = []; dims = D, c0 = 0.0, dvs = [C], ps = []) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps)
robin_p() = field1(0.4 * Δ(C) - 0.3 * C + 0.1 * x, [1.0 * c(t, x, 0) - Differential(y)(c(t, x, 0)) ~ 0.5])
robin_n() = field1(0.4 * Δ(C) - 0.3 * C + 0.1 * x, [1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5])
field_face() = field1(DivKGrad(:harmonic)(1 + 0.05 * x * y, C) - 0.3 * C, [c(t, 0, y) ~ 1.0 + 0.1 * y])
mask_field() = field1(0.4 * Δ(C) - 0.3 * C, [C ~ masked(KA, 1 + 0.1 * x)]; dvs = [C, KA])
moving() = (@parameters Dc = 0.5 kd = 0.4;
            field1(Dc * Δ(C) + 0.5 * KA - kd * C * kM(X...); dims = (16, 16), dvs = [C, KA, kM(X...)], ps = [Dc, kd]))
blowup() = (@parameters g = 1.0; field1(0.1 * Δ(C) + g * C^3; dims = (8, 6), c0 = 1000.0, ps = [g]))
still() = (@parameters Dc = 0.4 kd = 0.3; field1(DivKGrad(:harmonic)(Dc * (1 + 0.05 * x), C) - kd * C + 0.1 * x; ps = [Dc, kd]))
periodic() = (@parameters Dc = 1.0; pdesys([Dt(C) ~ Dc * Δ(C)], [ic(c)], (16, 8), [C], [Dc]; spacing = 2.0))
timed() = field1(0.1 * Δ(C) - (1 + 20 * t) * C; dims = (8, 8), c0 = 1.0)
robin_w() = (@parameters rb = -1.0;
             field1(0.4 * Δ(C) - 0.3 * C + 0.1 * x, [1.5 * c(t, x, 0) - rb * Differential(y)(c(t, x, 0)) ~ 0.5]; ps = [rb]))
hex() = field1(2.0 * Δ(C) - C + 0.1 * KA; dims = (16, 16), dvs = [C, KA])
hex_f() = field1(0.4 * Δ(C) - 0.3 * C + 0.1 * x, [C ~ masked(KA, 1.5)]; dvs = [C, KA])
hex_face() = field1(0.4 * Δ(C) - 0.3 * C + 0.1 * x,
    [c(t, 0, y) ~ 1.0, 1.5 * c(t, x, 0) - 0.5 * Differential(y)(c(t, x, 0)) ~ 0.2])
kind3() = field1(1.0 * KA; dvs = [C, KA])
scal() = (O = o(X...); pdesys([Dt(C) ~ 0.5 * Δ(C) - 40 * C / (0.025 + C) + 20, Dt(O) ~ 0.5 * Δ(O) - O + C],
                             [ic(c, 0.5), ic(o, 0.5)], D, [C, O]))
# two components of one array field `u`
function comp()
    @variables u(..)[1:2] = [0.5, 0.5]
    Ua = u(X...)
    return pdesystem([Dt(Ua[1]) ~ 0.5 * Δ(Ua[1]) - 40 * Ua[1] / (0.025 + Ua[1]) + 20,
        Dt(Ua[2]) ~ 0.5 * Δ(Ua[2]) - Ua[2] + Ua[1]]; name = :fields)
end
site_m() = field1(0.04 * (1 + x) * Δ(C) - 0.3 * C + 0.1 * y)
site_k() = field1(0.04 * (1 + x) * DivKGrad(:harmonic)(1 + 0.05 * y, C) - 0.3 * C + 0.1 * y)
# the derivative models (F3-21b)
const DD = (24, 20)
dual() = (@parameters Dc = 0.2 s = 0.5 kd = 0.1 Dh = 0.5 * Dc;
          field1(Dh * Δ(C) + Dh * Δ(C) + s * KA - kd * C; dims = DD, dvs = [C, KA], ps = [Dc, s, kd, Dh]))
dual_mask() = (@parameters Dc = 0.4 kd = 0.3 v = 1.5 c0 = 0.2;
               field1(Dc * Δ(C) - kd * C, [C ~ masked(KA, v)]; c0, dvs = [C, KA], ps = [Dc, kd, v, c0]))
dual_two() = (@parameters ra = 0.3 rb = 0.2; U = u(X...); W = w(X...);
              pdesys([Dt(U) ~ 0.2 * Δ(U) + ra * KA - 0.1 * U, Dt(W) ~ 0.3 * Δ(W) + rb * U - 0.2 * W], [ic(u), ic(w)], DD,
                  [U, W, KA], [ra, rb]))
dual_fill() = (@parameters V0 = 14.0 s0 = 0.5;
               field1(0.2 * Δ(C) + ifelse(big(X...), s0, 0.0) - 0.1 * C; dims = DD, dvs = [C, big(X...)], ps = [V0, s0]))
dual_vol() = (@parameters V0 = 14.0;
              field1(0.2 * Δ(C) + 0.01 * KA * (vol(X...) - V0) - 0.1 * C; dims = DD, dvs = [C, KA, vol(X...)], ps = [V0]))
dual_kind() = field1(0.2 * Δ(C) + dk(X...) - 0.1 * C; dims = DD, dvs = [C, dk(X...)])
end


@potts_model FiMix begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.mix() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiRobinP begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.robin_p()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiRobinN begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.robin_n()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiFieldFace begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.field_face()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiMaskField begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.mask_field() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# a moving σ: the decay reads the kind (a field row, rebuilt every window)
@potts_model FiMoving begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 12.0)^2
    @fields FiPDE.moving() (FiPDE.kA => kind == A, FiPDE.kM => kind == medium)
    @sweep Metropolis(; temperature = 8.0)
    @schedule sweep, fields
end

# a growth term the operator does not see, `+ g c³`: with large data the defect correction
# diverges and the run ends
@potts_model FiBlowup begin
    @kinds medium A[frozen]
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.blowup()
    @sweep Metropolis(; temperature = 1.0)
end


# a field row whose operator kernels read only the coordinates and parameters: nothing moves,
# so only a parameter write rebuilds its hierarchy and `jac:` arrays
@potts_model FiStill begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.still()
    @sweep Metropolis(; temperature = 1.0)
end


# a periodic field with no cells (the messages)
@potts_model FiPeriodic begin
    @kinds medium A
    @lattice Lattice((16, 8); boundary = Periodic(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.periodic()
    @sweep Metropolis(; temperature = 1.0)
end


fi_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

fi_kin(dims) = (K = zeros(Int32, dims...); K[4:6, 3:5] .= 1; K)

# the model's field `c` after each of `k` MCS
function fi_runA(M, op, k; field_solver = BackwardEuler(), kw...)
    integ = init(PottsProblem(M(; name = :f), op, (0, k); field_solver, kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:k], integ
end

# B's (`Potts.fields` → `discretize`) at the same MCS, from the same start
function fi_runB(M, dims, k; u0, inputs = [:kind => fi_kin(dims)], alg = BackwardEuler(; dt = 1.0))
    bp = Potts.LatticePDE.discretize(Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(dims); T = Float64);
        u0, tspan = (0, k), inputs)
    return (s -> [s[:c, i] for i in 2:length(s.t)])(Potts.LatticePDE.solve(bp, alg; saveat = 1.0))
end

fi_warm(integ) = (step!(integ); @allocated step!(integ))


# F3 batch 3 review r1 (research/field-compiler/f3/reviews/F3-batch3-r1.md), the A halves of M1,
# M2, M4 and M6. Base 2d213237 (~/lpwork/f3r1-nc-a-base.log): each testset fails there.
@potts_model FiTimed begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.timed()
    @sweep Metropolis(; temperature = 1.0, mcs_duration = 0.2)
end

@potts_model FiRobinW begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.robin_w()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiHex begin
    @kinds medium A
    @lattice Lattice((16, 16); geometry = Hexagonal(), boundary = Periodic())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.hex() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiHexF begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); geometry = Hexagonal(), boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.hex_f() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiHexFace begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); geometry = Hexagonal(), boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.hex_face()
    @sweep Metropolis(; temperature = 1.0)
end

# a three-kind class in a rate (F3-20 r1 M2)
@potts_model FiKind3 begin
    @kinds medium A[frozen] B[frozen] C[frozen] cells3 = (A, B, C)
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.kind3() (FiPDE.kA => ismember(kind, cells3))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiComp begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.comp()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiScal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.scal()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model FiSiteM begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.site_m()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiSiteK begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.site_k()
    @sweep Metropolis(; temperature = 1.0)
end


# F3-21b (F3 design §5 F3-21, note research/field-compiler/f3/F3-21b-note.md): a ForwardDiff
# Dual in an A parameter runs. The CPM runs on the primal parameters (its run is the primal run,
# bit for bit), and every field group also steps a shadow tangent store (Dual twins of the
# fields): the derivative is pathwise, at the run's CPM path. Checked against central finite
# differences at the same seed, with the path (σ at every saved MCS) identical between the ±
# runs, for an explicit and the implicit field solvers; the model's chemotaxis drive reads the
# field, so the CPM's reads stay primal. Base 9fccc948: every Dual is refused at `PottsProblem`.
# Negative controls (lp-f3t mutations, ~/lpwork/f321b/nc-*.log): the twins' derivative parts
# reset before each window (the operator's propagation of u̇ dropped), and the parameters'
# derivative parts dropped from the shadow step (the source term `∂f/∂p` dropped).
using ForwardDiff: ForwardDiff

@potts_model FiDual begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = FiPDE.dual() (FiPDE.kA => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FiDualMask begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.dual_mask() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# two groups: `w` (implicit) reads `u` (explicit), so `w`'s derivative runs through `u`'s twin
@potts_model FiDualTwo begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FiPDE.dual_two() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FiDualNoField begin
    @kinds medium A
    @parameters λ = 1.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => λ * (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

# a CPM read filled whole (an `ifelse` of CPM reads) holding a parameter: refused; a CPM read
# outside it (`volume[owner] - V0`) differentiates in the field program (F3-21b r1 N2)
@potts_model FiDualFill begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FiPDE.dual_fill() (FiPDE.big => volume[owner] > 15.0)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FiDualVol begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FiPDE.dual_vol() (FiPDE.kA => kind == A, FiPDE.vol => volume[owner])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FiDualKind begin
    @kinds medium A
    @parameters δk[kind] = [0.0, 0.1]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FiPDE.dual_kind() (FiPDE.dk => δk[kind])
    @sweep Metropolis(; temperature = 4.0)
end

fi_dop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

const FI_DW = [0.01 * (i + 2j) for i in 1:24, j in 1:20]

fi_dq(sol) = sum(FI_DW .* sol.u[end].site.c)

fi_drun(fs, ps; M = FiDual, op = fi_dop(), alg = SequentialCPM(), kw...) =
    solve(PottsProblem(M(; name = :m), [op; ps], (0, 12); field_solver = fs, seed = 3, kw...), alg; saveat = 0:3:12)

fi_derr(f) = try f(); "" catch err sprint(showerror, err) end

# ---- from fields_steppers.jl ------------------------------------------------------------------------
isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module FsPDE
using ..FieldPDE
@variables c(..) e(..) u(..) v(..) w(..) kA(..)::Bool [input = true]
@variables dk(..) [input = true] kout(..) [input = true] kinp(..) [input = true]
const X = (t, x, y)
const C, E, U, V, W, KA = c(X...), e(X...), u(X...), v(X...), w(X...), kA(X...)
const D = (12, 10)
ic(f, v = 0.0) = f(0, x, y) ~ v
move() = pdesys([Dt(C) ~ 4.0 * Δ(C) - 2.0 * C], [ic(c), C ~ masked(KA, 1.0)], (24, 24), [C, KA])
secrete() = pdesys([Dt(C) ~ 1.0 * Δ(C) - 0.2 * C + 1.0 * KA], [ic(c)], (24, 24), [C, KA])
steady(; zero = false) = (@parameters Dc = 0.4 kd = 0.3 s = 0.5;
    pdesys([(zero ? 0 : Dt(C)) ~ Dc * Δ(C) - kd * C + s * KA], [ic(c)], D, [C, KA], [Dc, kd, s]))
island() = (@parameters kd = 1.0; pdesys([Dt(C) ~ 0.5 * Δ(C) - kd * KA * C + 1.0], [ic(c)], (24, 12), [C, KA], [kd]))
no_island() = pdesys([Dt(C) ~ 0.5 * Δ(C) - 0.1 * C + 1.0], [ic(c)], (24, 12), [C])
grow() = (@parameters g = -0.5; pdesys([Dt(C) ~ 0.4 * Δ(C) - g * C + 0.1 * KA], [ic(c)], D, [C, KA], [g]))
# two fields in a loop (`u` reads `w`, `w` reads `u`) with the parameters `ps`; a kind table is
# the model's, bound to `dk`, `kout` or `kinp`
loop(ru, rw, ps = [], ins = []) = pdesys([Dt(U) ~ ru, Dt(W) ~ rw], [ic(u), ic(w, 1.0)], D, [U, W, ins...], ps)
loop() = loop(0.1 * Δ(U) - 0.1 * U + 0.5 * W, 0.1 * Δ(W) - W - 0.5 * U)
loop_k() = (@parameters kd = 1.0 kc = 0.5; loop(0.1 * Δ(U) - kd * U + kc * W, 0.1 * Δ(W) - W - kc * U, [kd, kc]))
loop_t() = (@parameters kc = 0.5; loop(0.1 * Δ(U) - dk(X...) * U + kc * W, 0.1 * Δ(W) - W - kc * U, [kc], [dk(X...)]))
loop_x() = loop(0.1 * Δ(U) - 1.0 * U + kout(X...) * W, 0.1 * Δ(W) - W - kinp(X...) * U, [], [kout(X...), kinp(X...)])
steady_mix() = pdesys([Dt(E) ~ 0.1 * Δ(E) - E + C, 0 ~ 0.4 * Δ(C) - 0.3 * C + 0.5 * KA], [ic(e), ic(c)], D, [E, C, KA])
steady_neg() = (@parameters Dc = 0.4 kd = 0.3 s = 0.5;
    pdesys([0 ~ kd * C - Dc * Δ(C) - s * KA], [ic(c)], D, [C, KA], [Dc, kd, s]))
local_() = pdesys([0 ~ -2.0 * C + 0.5 * E, Dt(E) ~ 0.1 * Δ(E) - E + 0.5 * KA], [ic(c), ic(e)], D, [C, E, KA])
robin_q() = pdesys([Dt(C) ~ 0.4 * Δ(C) - 1.0 * C + 0.1 * x], [ic(c), 1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5], D, [C])
pair() = pdesys([0 ~ 0.1 * Δ(U) - 0.1 * U + 5.0 * V + 0.5 * KA, 0 ~ 0.1 * Δ(V) - V - 5.0 * U], [ic(u), ic(v)], D, [U, V, KA])
feed() = (@parameters k = 0.5;
    pdesys([Dt(E) ~ 0.1 * Δ(E) - E + 0.5 * V + 0.5 * KA, 0 ~ 0.1 * Δ(U) - U + k * V + 0.2 * E, 0 ~ 0.1 * Δ(V) - V - k * U],
        [ic(e), ic(u), ic(v)], D, [E, U, V, KA], [k]))
# two components of one array field `w` in steady rows
function comp()
    @variables w(..)[1:2] = [0.0, 0.0]
    Wa = w(X...)
    return pdesystem([0 ~ 0.1 * Δ(Wa[1]) - 0.1 * Wa[1] + 5.0 * Wa[2] + 0.5 * KA, 0 ~ 0.1 * Δ(Wa[2]) - Wa[2] - 5.0 * Wa[1]];
        name = :fields)
end
function half()
    @variables v(..) [lattice_storage = Float16]
    Vh = v(X...)
    return pdesys([0 ~ 0.1 * Δ(U) - U + 0.5 * Vh + 0.5 * KA, 0 ~ 0.1 * Δ(Vh) - Vh - 0.5 * U], [ic(u), ic(v)], D, [U, Vh, KA])
end
end


# a Dirichlet mask on moving cells (P1 (c)): `c = 1` inside the cells, fast diffusion and decay
@potts_model FiMove begin
    @kinds medium A
    @lattice Lattice((24, 24); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FsPDE.move() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 12.0)
    @schedule sweep, fields
end

fi_rt(integ) = CorePotts._runtime(getfield(integ.ctx, :__fields1))

fi_c(integ) = copy(Array(current_state(integ).site.c))


# a Merks-like secretion field: the cells secrete `c`, which diffuses and decays; it reads the
# CPM (`kind`), so its data jump every MCS, and it does not steer the CPM (σ is the same in
# every run)
@potts_model FiSecrete begin
    @kinds medium A
    @lattice Lattice((24, 24); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FsPDE.secrete() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 10.0)
end


# F3-12a (F3 design §3.5): `QuasiSteady` in a model, through the runtime of B. With σ
# frozen the model equals B bitwise; the refusals name the route; an island the cells' kinds leave
# with no decay ends the run with `ConvergenceFailure`. Base (b32d9112,
# ~/lpwork/f3b5-nc-12a-a-base.log): `QuasiSteady` is not defined in Potts (every testset errors).
@potts_model FiSteady begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.steady() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# two discs (the field's domain), a decay only inside the cells: the disc with no cell is an
# island with no decay and no fixed value
@potts_model FiIsland begin
    @structural_parameters begin
        domain = x -> (x[1] - 6.5)^2 + (x[2] - 6.5)^2 <= 25 || (x[1] - 18.5)^2 + (x[2] - 6.5)^2 <= 25
    end
    @kinds medium A
    @lattice Lattice((24, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 16.0)^2
    @fields FsPDE.island() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiNoIsland begin
    @structural_parameters begin
        domain = x -> (x[1] - 6.5)^2 + (x[2] - 6.5)^2 <= 25 || (x[1] - 18.5)^2 + (x[2] - 6.5)^2 <= 25
    end
    @kinds medium A
    @lattice Lattice((24, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 16.0)^2
    @fields FsPDE.no_island()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiGrow begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.grow() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end


# Review r2 M1 in a model: a steady field in a loop of solver groups is refused until F3-12c bounds
# its gain; the routes (one `BackwardEuler` solver; `BackwardEuler` for the steady field) run.
# Base (773f0957, ~/lpwork/f3b5-nc-r2-m1-a.log): the loop is accepted (the refusal test fails).
@potts_model FiLoop begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.loop()
    @sweep Metropolis(; temperature = 1.0)
end


# F3-12b (F3 design §3.5): steady rows `0 ~ rhs` in a model. A steady row is solved by `QuasiSteady`
# for the field its operator acts on, by default too; another solver for it is refused; the
# QuasiSteady groups step first. Base (6b6bf089, ~/lpwork/f3b5-nc-12b-a-base.log): `0 ~ rhs` is
# refused ("equations are `D(x) ~ rhs` …"; every testset errors).
@potts_model FiSteady0 begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.steady(; zero = true) (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# a transient field `e` (declared and written first) that reads the steady `c`
@potts_model FiSteadyMix begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.steady_mix() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end


# Review r3 S3, S4: a steady row's sign does not matter (the elliptic form `0 ~ k c − D Δ(c) −
# s`), and its field follows the one rule of both front ends (`LatticePDE.steady_choice`): a
# field with no other equation, so a local row that reads a transient field (`0 ~ −2c + 0.5e`)
# is `c`'s, equal to B. Base (e7068add, ~/lpwork/f3b6-nc-r3-a.log): "the diffusion coefficient …
# is negative", and "this row's operators apply to `c` and `e`".
@potts_model FiSteadyNeg begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.steady_neg() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiLocal begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.local_() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end


# F3-12c in a model: the QuasiSteady gain in the coupling rule, and `init = :steady`. `FiLoopK` is
# FiLoop with the decay `kd` and the coupling `kc` as parameters: at kd = 1, kc = 0.5 the gain
# is 1 and κ = 1 · 0.5 · 1 · 0.5 = 0.25, accepted; uniform data stay uniform (no flux faces), so
# each MCS is u = (kc/kd) w, then w⁺ = (w − kc u)/2. A write to kd = 0.1 (κ = 2.5) is refused:
# the transient group's rule reads the steady row's decay (every group holds the system's
# parameters). Base (932c12ce, ~/lpwork/f3b7-nc-12c-a-base.log): the loop is refused ("does not
# bound that gain yet") and `init` is no keyword (both testsets error).
@potts_model FiLoopK begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.loop_k()
    @sweep Metropolis(; temperature = 1.0)
end

# the decay a kind table: the transient group's rule reads that table too (its phase holds the
# system's tables after its own). Control (a327e38f, ~/lpwork/f3b7-a2.log before the fix): the
# table was missing from the rule, its decay read 0, and the loop was refused ("`u` has no decay").
@potts_model FiLoopT begin
    @kinds medium A[frozen]
    @parameters δ[kind] = [2.0, 1.0]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.loop_t() (FsPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 1.0)
end

# the cross coefficients kind tables (review r4 N3; reviewer probe ~/lpwork/f3rev9/a4.jl): the
# steady row's `ko[kind]` (k_out) and the reader's `ki[kind]` (k_in), each read by the rule
# from the whole system's tables; at 0.5 κ = 0.25, at 3 in one kind κ = 1.5
@potts_model FiLoopX begin
    @kinds medium A[frozen]
    @parameters begin
        ko[kind] = [0.5, 0.5]
        ki[kind] = [0.5, 0.5]
    end
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.loop_x() (FsPDE.kout => ko[kind], FsPDE.kinp => ki[kind])
    @sweep Metropolis(; temperature = 1.0)
end


# a Robin face of opposite signs with a definite steady operator (decay 1 > the face's 0.8)
@potts_model FiRobinQ begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.robin_q()
    @sweep Metropolis(; temperature = 1.0)
end


# F3-12d: the coupled steady solve in a model. Steady rows that read one another are one QuasiSteady
# group solved together (Krylov.jl FGMRES on the group's whole Jacobian), as in B: with σ frozen
# the model equals B bitwise; components equal scalars; a loop through a transient field composes the
# steady gains; Float16 storage is refused. Base (c40a68f8, ~/lpwork/f312d/nc-base-potts.log):
# the strong pair ends `ConvergenceFailure`, the feedback loop is refused.
@potts_model FcPair begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.pair() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcComp begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.comp() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcFeed begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.feed() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FcHalf begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.half() (FsPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

fc_site(integ, names) = [copy(Array(getproperty(current_state(integ).site, n))) for n in names]

function fc_runA(M, k, names; kw...)
    integ = init(PottsProblem(M(; name = :f), fi_op((12, 10)), (0, k); kw...), SequentialCPM(); save_start = false)
    return [(step!(integ); fc_site(integ, names)) for _ in 1:k], integ
end

function fc_runB(M, k, names; alg, kw...)
    bp = Potts.LatticePDE.discretize(Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((12, 10)); T = Float64);
        u0 = [n => zeros(12, 10) for n in names], tspan = (0, k), inputs = [:kind => fi_kin((12, 10))], kw...)
    s = Potts.LatticePDE.solve(bp, alg; saveat = 1.0)
    return [[s[n, i] for n in names] for i in 2:(k + 1)], s
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
