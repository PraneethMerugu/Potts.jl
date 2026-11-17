# The top-level definitions of fields_implicit.jl, fields_steppers.jl (converted from the include-into-Main suite, TS1a).

@testsetup module ImplicitSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

using StableRNGs: StableRNG
using ForwardDiff: ForwardDiff

const FIP = Potts.LatticeFields.Problems
const FiRC = Potts.SciMLBase.ReturnCode
using Potts.LatticeFields.IR: fieldid

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
        pdesys(
            [Dt(C) ~ Dc * laplacian(C) - kd * C + s * KA, Dt(E) ~ 0.02 + 0.01 * x], [ic(c), ic(e), C ~ masked(E >= 0.5, v)], D,
             [C, E, KA], [Dc, kd, s, v]))
# `rate` with the conditions `bcs`, no parameters, on lattice `dims`
field1(rate, bcs = []; dims = D, c0 = 0.0, dvs = [C], ps = []) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps)
    robin_p() = field1(0.4 * laplacian(C) - 0.3 * C + 0.1 * x, [1.0 * c(t, x, 0) - Differential(y)(c(t, x, 0)) ~ 0.5])
    robin_n() = field1(0.4 * laplacian(C) - 0.3 * C + 0.1 * x, [1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5])
field_face() = field1(DivKGrad(:harmonic)(1 + 0.05 * x * y, C) - 0.3 * C, [c(t, 0, y) ~ 1.0 + 0.1 * y])
    mask_field() = field1(0.4 * laplacian(C) - 0.3 * C, [C ~ masked(KA, 1 + 0.1 * x)]; dvs = [C, KA])
moving() = (@parameters Dc = 0.5 kd = 0.4;
        field1(Dc * laplacian(C) + 0.5 * KA - kd * C * kM(X...); dims = (16, 16), dvs = [C, KA, kM(X...)], ps = [Dc, kd])
    )
    blowup() = (@parameters g = 1.0; field1(0.1 * laplacian(C) + g * C^3; dims = (8, 6), c0 = 1000.0, ps = [g]))
still() = (@parameters Dc = 0.4 kd = 0.3; field1(DivKGrad(:harmonic)(Dc * (1 + 0.05 * x), C) - kd * C + 0.1 * x; ps = [Dc, kd]))
    periodic() = (@parameters Dc = 1.0; pdesys([Dt(C) ~ Dc * laplacian(C)], [ic(c)], (16, 8), [C], [Dc]; spacing = 2.0))
    timed() = field1(0.1 * laplacian(C) - (1 + 20 * t) * C; dims = (8, 8), c0 = 1.0)
robin_w() = (@parameters rb = -1.0;
        field1(0.4 * laplacian(C) - 0.3 * C + 0.1 * x, [1.5 * c(t, x, 0) - rb * Differential(y)(c(t, x, 0)) ~ 0.5]; ps = [rb])
    )
    hex() = field1(2.0 * laplacian(C) - C + 0.1 * KA; dims = (16, 16), dvs = [C, KA])
    hex_f() = field1(0.4 * laplacian(C) - 0.3 * C + 0.1 * x, [C ~ masked(KA, 1.5)]; dvs = [C, KA])
    hex_face() = field1(
        0.4 * laplacian(C) - 0.3 * C + 0.1 * x,
    [c(t, 0, y) ~ 1.0, 1.5 * c(t, x, 0) - 0.5 * Differential(y)(c(t, x, 0)) ~ 0.2])
kind3() = field1(1.0 * KA; dvs = [C, KA])
    scal() = (
        O = o(X...); pdesys(
            [Dt(C) ~ 0.5 * laplacian(C) - 40 * C / (0.025 + C) + 20, Dt(O) ~ 0.5 * laplacian(O) - O + C],
            [ic(c, 0.5), ic(o, 0.5)], D, [C, O]
        )
    )
function comp()
    @variables u(..)[1:2] = [0.5, 0.5]
    Ua = u(X...)
        return pdesystem(
            [
                Dt(Ua[1]) ~ 0.5 * laplacian(Ua[1]) - 40 * Ua[1] / (0.025 + Ua[1]) + 20,
                Dt(Ua[2]) ~ 0.5 * laplacian(Ua[2]) - Ua[2] + Ua[1],
            ]; name = :fields
        )
end
    site_m() = field1(0.04 * (1 + x) * laplacian(C) - 0.3 * C + 0.1 * y)
    site_k() = field1(0.04 * (1 + x) * DivKGrad(:harmonic)(1 + 0.05 * y, C) - 0.3 * C + 0.1 * y)
const DD = (24, 20)
dual() = (@parameters Dc = 0.2 s = 0.5 kd = 0.1 Dh = 0.5 * Dc;
        field1(Dh * laplacian(C) + Dh * laplacian(C) + s * KA - kd * C; dims = DD, dvs = [C, KA], ps = [Dc, s, kd, Dh])
    )
dual_mask() = (@parameters Dc = 0.4 kd = 0.3 v = 1.5 c0 = 0.2;
        field1(Dc * laplacian(C) - kd * C, [C ~ masked(KA, v)]; c0, dvs = [C, KA], ps = [Dc, kd, v, c0])
    )
dual_two() = (@parameters ra = 0.3 rb = 0.2; U = u(X...); W = w(X...);
        pdesys(
            [Dt(U) ~ 0.2 * laplacian(U) + ra * KA - 0.1 * U, Dt(W) ~ 0.3 * laplacian(W) + rb * U - 0.2 * W], [ic(u), ic(w)], DD,
                  [U, W, KA], [ra, rb]))
dual_fill() = (@parameters V0 = 14.0 s0 = 0.5;
        field1(0.2 * laplacian(C) + ifelse(big(X...), s0, 0.0) - 0.1 * C; dims = DD, dvs = [C, big(X...)], ps = [V0, s0])
    )
dual_vol() = (@parameters V0 = 14.0;
        field1(0.2 * laplacian(C) + 0.01 * KA * (vol(X...) - V0) - 0.1 * C; dims = DD, dvs = [C, KA, vol(X...)], ps = [V0])
    )
    dual_kind() = field1(0.2 * laplacian(C) + dk(X...) - 0.1 * C; dims = DD, dvs = [C, dk(X...)])
end

module FsPDE
    using ..FieldPDE
    import ..FiPDE: kA
    @variables c(..) e(..) u(..) v(..) w(..)
    @variables dk(..) [input = true] kout(..) [input = true] kinp(..) [input = true]
    const X = (t, x, y)
    const C, E, U, V, W, KA = c(X...), e(X...), u(X...), v(X...), w(X...), kA(X...)
    const D = (12, 10)
    ic(f, v = 0.0) = f(0, x, y) ~ v
    move() = pdesys([Dt(C) ~ 4.0 * laplacian(C) - 2.0 * C], [ic(c), C ~ masked(KA, 1.0)], (24, 24), [C, KA])
    secrete() = pdesys([Dt(C) ~ 1.0 * laplacian(C) - 0.2 * C + 1.0 * KA], [ic(c)], (24, 24), [C, KA])
    steady(; zero = false) = (
        @parameters Dc = 0.4 kd = 0.3 s = 0.5;
        pdesys([(zero ? 0 : Dt(C)) ~ Dc * laplacian(C) - kd * C + s * KA], [ic(c)], D, [C, KA], [Dc, kd, s])
    )
    island() = (@parameters kd = 1.0; pdesys([Dt(C) ~ 0.5 * laplacian(C) - kd * KA * C + 1.0], [ic(c)], (24, 12), [C, KA], [kd]))
    no_island() = pdesys([Dt(C) ~ 0.5 * laplacian(C) - 0.1 * C + 1.0], [ic(c)], (24, 12), [C])
    grow() = (@parameters g = -0.5; pdesys([Dt(C) ~ 0.4 * laplacian(C) - g * C + 0.1 * KA], [ic(c)], D, [C, KA], [g]))
    loop(ru, rw, ps = [], ins = []) = pdesys([Dt(U) ~ ru, Dt(W) ~ rw], [ic(u), ic(w, 1.0)], D, [U, W, ins...], ps)
    loop() = loop(0.1 * laplacian(U) - 0.1 * U + 0.5 * W, 0.1 * laplacian(W) - W - 0.5 * U)
    loop_k() = (@parameters kd = 1.0 kc = 0.5; loop(0.1 * laplacian(U) - kd * U + kc * W, 0.1 * laplacian(W) - W - kc * U, [kd, kc]))
    loop_t() = (@parameters kc = 0.5; loop(0.1 * laplacian(U) - dk(X...) * U + kc * W, 0.1 * laplacian(W) - W - kc * U, [kc], [dk(X...)]))
    loop_x() = loop(0.1 * laplacian(U) - 1.0 * U + kout(X...) * W, 0.1 * laplacian(W) - W - kinp(X...) * U, [], [kout(X...), kinp(X...)])
    steady_mix() = pdesys([Dt(E) ~ 0.1 * laplacian(E) - E + C, 0 ~ 0.4 * laplacian(C) - 0.3 * C + 0.5 * KA], [ic(e), ic(c)], D, [E, C, KA])
    steady_neg() = (
        @parameters Dc = 0.4 kd = 0.3 s = 0.5;
        pdesys([0 ~ kd * C - Dc * laplacian(C) - s * KA], [ic(c)], D, [C, KA], [Dc, kd, s])
    )
    local_() = pdesys([0 ~ -2.0 * C + 0.5 * E, Dt(E) ~ 0.1 * laplacian(E) - E + 0.5 * KA], [ic(c), ic(e)], D, [C, E, KA])
    robin_q() = pdesys([Dt(C) ~ 0.4 * laplacian(C) - 1.0 * C + 0.1 * x], [ic(c), 1.0 * c(t, x, 0) + Differential(y)(c(t, x, 0)) ~ 0.5], D, [C])
    pair() = pdesys([0 ~ 0.1 * laplacian(U) - 0.1 * U + 5.0 * V + 0.5 * KA, 0 ~ 0.1 * laplacian(V) - V - 5.0 * U], [ic(u), ic(v)], D, [U, V, KA])
    feed() = (
        @parameters k = 0.5;
        pdesys(
            [Dt(E) ~ 0.1 * laplacian(E) - E + 0.5 * V + 0.5 * KA, 0 ~ 0.1 * laplacian(U) - U + k * V + 0.2 * E, 0 ~ 0.1 * laplacian(V) - V - k * U],
            [ic(e), ic(u), ic(v)], D, [E, U, V, KA], [k]
        )
    )
    function comp()
        @variables w(..)[1:2] = [0.0, 0.0]
        Wa = w(X...)
        return pdesystem(
            [0 ~ 0.1 * laplacian(Wa[1]) - 0.1 * Wa[1] + 5.0 * Wa[2] + 0.5 * KA, 0 ~ 0.1 * laplacian(Wa[2]) - Wa[2] - 5.0 * Wa[1]];
            name = :fields
        )
    end
    function half()
        @variables v(..) [lattice_storage = Float16]
        Vh = v(X...)
        return pdesys([0 ~ 0.1 * laplacian(U) - U + 0.5 * Vh + 0.5 * KA, 0 ~ 0.1 * laplacian(Vh) - Vh - 0.5 * U], [ic(u), ic(v)], D, [U, Vh, KA])
    end
end

# ---- Consolidated frozen (12, 10) / (8, 6) family (26 models -> 1) -------------------------------------
@potts_model _Fi12x10 begin
    @structural_parameters begin
        sys_fn = FiPDE.still
        has_kA = false
        dims = (12, 10)
    end
    @kinds medium A[frozen]
    @lattice Lattice(dims; boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if has_kA
        @fields sys_fn() (FiPDE.kA => kind == A)
    else
        @fields sys_fn()
    end
    @sweep Metropolis(; temperature = 1.0)
end

FiMix(; name = :FiMix, kw...) = _Fi12x10(; sys_fn = FiPDE.mix, has_kA = true, name, kw...)
FiRobinP(; name = :FiRobinP, kw...) = _Fi12x10(; sys_fn = FiPDE.robin_p, name, kw...)
FiRobinN(; name = :FiRobinN, kw...) = _Fi12x10(; sys_fn = FiPDE.robin_n, name, kw...)
FiFieldFace(; name = :FiFieldFace, kw...) = _Fi12x10(; sys_fn = FiPDE.field_face, name, kw...)
FiMaskField(; name = :FiMaskField, kw...) = _Fi12x10(; sys_fn = FiPDE.mask_field, has_kA = true, name, kw...)
FiBlowup(; name = :FiBlowup, kw...) = _Fi12x10(; sys_fn = FiPDE.blowup, dims = (8, 6), name, kw...)
FiStill(; name = :FiStill, kw...) = _Fi12x10(; sys_fn = FiPDE.still, name, kw...)
FiRobinW(; name = :FiRobinW, kw...) = _Fi12x10(; sys_fn = FiPDE.robin_w, name, kw...)
FiComp(; name = :FiComp, kw...) = _Fi12x10(; sys_fn = FiPDE.comp, name, kw...)
FiScal(; name = :FiScal, kw...) = _Fi12x10(; sys_fn = FiPDE.scal, name, kw...)
FiSiteM(; name = :FiSiteM, kw...) = _Fi12x10(; sys_fn = FiPDE.site_m, name, kw...)
FiSiteK(; name = :FiSiteK, kw...) = _Fi12x10(; sys_fn = FiPDE.site_k, name, kw...)
FiDualMask(; name = :FiDualMask, kw...) = _Fi12x10(; sys_fn = FiPDE.dual_mask, has_kA = true, name, kw...)
FiSteady(; name = :FiSteady, kw...) = _Fi12x10(; sys_fn = FsPDE.steady, has_kA = true, name, kw...)
FiGrow(; name = :FiGrow, kw...) = _Fi12x10(; sys_fn = FsPDE.grow, has_kA = true, name, kw...)
FiLoop(; name = :FiLoop, kw...) = _Fi12x10(; sys_fn = FsPDE.loop, name, kw...)
FiSteady0(; name = :FiSteady0, kw...) = _Fi12x10(; sys_fn = () -> FsPDE.steady(; zero = true), has_kA = true, name, kw...)
FiSteadyMix(; name = :FiSteadyMix, kw...) = _Fi12x10(; sys_fn = FsPDE.steady_mix, has_kA = true, name, kw...)
FiSteadyNeg(; name = :FiSteadyNeg, kw...) = _Fi12x10(; sys_fn = FsPDE.steady_neg, has_kA = true, name, kw...)
FiLocal(; name = :FiLocal, kw...) = _Fi12x10(; sys_fn = FsPDE.local_, has_kA = true, name, kw...)
FiLoopK(; name = :FiLoopK, kw...) = _Fi12x10(; sys_fn = FsPDE.loop_k, name, kw...)
FiRobinQ(; name = :FiRobinQ, kw...) = _Fi12x10(; sys_fn = FsPDE.robin_q, name, kw...)
FcPair(; name = :FcPair, kw...) = _Fi12x10(; sys_fn = FsPDE.pair, has_kA = true, name, kw...)
FcComp(; name = :FcComp, kw...) = _Fi12x10(; sys_fn = FsPDE.comp, has_kA = true, name, kw...)
FcFeed(; name = :FcFeed, kw...) = _Fi12x10(; sys_fn = FsPDE.feed, has_kA = true, name, kw...)
FcHalf(; name = :FcHalf, kw...) = _Fi12x10(; sys_fn = FsPDE.half, has_kA = true, name, kw...)

# ---- Consolidated movable single-kind family (5 models -> 1) ---------------------------------------------
@potts_model _FiMovable begin
    @structural_parameters begin
        sys_fn = FsPDE.secrete
        inp = :kA
        dims = (24, 24)
        boundary = Closed()
        spacing = (1.0, 1.0)
        v0 = 16.0
        temp = 1.0
        mcs_dur = 1.0
        sched_sf = false
    end
    @kinds medium A
    @lattice Lattice(dims; boundary, spacing)
    @energy cells(A) => (volume - v0)^2
    if inp === :kAkM
        @fields sys_fn() (FiPDE.kA => kind == A, FiPDE.kM => kind == medium)
    elseif inp === :kA
        @fields sys_fn() (FiPDE.kA => kind == A)
    else
        @fields sys_fn()
    end
    @sweep Metropolis(; temperature = temp, mcs_duration = mcs_dur)
    if sched_sf
        @schedule sweep, fields
    end
end

FiMoving(; name = :FiMoving, kw...) =
    _FiMovable(; sys_fn = FiPDE.moving, inp = :kAkM, dims = (16, 16), v0 = 12.0, temp = 8.0, sched_sf = true, name, kw...)
FiMove(; name = :FiMove, kw...) = _FiMovable(; sys_fn = FsPDE.move, temp = 12.0, sched_sf = true, name, kw...)
FiSecrete(; name = :FiSecrete, kw...) = _FiMovable(; sys_fn = FsPDE.secrete, temp = 10.0, name, kw...)
FiTimed(; name = :FiTimed, kw...) = _FiMovable(; sys_fn = FiPDE.timed, inp = :none, dims = (8, 8), v0 = 4.0, mcs_dur = 0.2, name, kw...)
FiPeriodic(; name = :FiPeriodic, kw...) =
    _FiMovable(; sys_fn = FiPDE.periodic, inp = :none, dims = (16, 8), boundary = Periodic(), spacing = (2.0, 2.0), v0 = 4.0, name, kw...)

# ---- Hexagonal & multi-kind models ---------------------------------------------------------------------
@potts_model FiHex begin
    @kinds medium A
    @lattice Lattice((16, 16); geometry = Hexagonal(), boundary = Periodic())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.hex() (FiPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _FiHexF begin
    @structural_parameters begin
        sys_fn = FiPDE.hex_f
        has_kA = true
    end
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); geometry = Hexagonal(), boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if has_kA
        @fields sys_fn() (FiPDE.kA => kind == A)
    else
        @fields sys_fn()
    end
    @sweep Metropolis(; temperature = 1.0)
end

FiHexF(; name = :FiHexF, kw...) = _FiHexF(; sys_fn = FiPDE.hex_f, has_kA = true, name, kw...)
FiHexFace(; name = :FiHexFace, kw...) = _FiHexF(; sys_fn = FiPDE.hex_face, has_kA = false, name, kw...)

@potts_model FiKind3 begin
    @kinds medium A[frozen] B[frozen] C[frozen] cells3 = (A, B, C)
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FiPDE.kind3() (FiPDE.kA => ismember(kind, cells3))
    @sweep Metropolis(; temperature = 1.0)
end

# ---- Island domain pair (2 models -> 1) ----------------------------------------------------------------
@potts_model _FiIsland begin
    @structural_parameters begin
        domain = x -> (x[1] - 6.5)^2 + (x[2] - 6.5)^2 <= 25 || (x[1] - 18.5)^2 + (x[2] - 6.5)^2 <= 25
        sys_fn = FsPDE.island
        has_kA = true
    end
    @kinds medium A
    @lattice Lattice((24, 12); boundary = Closed(), domain)
    @energy cells(A) => (volume - 16.0)^2
    if has_kA
        @fields sys_fn() (FiPDE.kA => kind == A)
    else
        @fields sys_fn()
    end
    @sweep Metropolis(; temperature = 1.0)
end

FiIsland(; name = :FiIsland, kw...) = _FiIsland(; sys_fn = FsPDE.island, has_kA = true, name, kw...)
FiNoIsland(; name = :FiNoIsland, kw...) = _FiIsland(; sys_fn = FsPDE.no_island, has_kA = false, name, kw...)

# ---- Loop models with parameter tables -----------------------------------------------------------------
@potts_model FiLoopT begin
    @kinds medium A[frozen]
    @parameters δ[kind] = [2.0, 1.0]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FsPDE.loop_t() (FsPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 1.0)
end

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

# ---- Dual sensitivity models ---------------------------------------------------------------------------
@potts_model FiDual begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = FiPDE.dual() (FiPDE.kA => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model _FiDual24x20 begin
    @structural_parameters begin
        sys_fn = FiPDE.dual_two
        bind_mode = :kA
    end
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    if bind_mode === :kA
        @fields sys_fn() (FiPDE.kA => kind == A)
    elseif bind_mode === :big
        @fields sys_fn() (FiPDE.big => volume[owner] > 15.0)
    else
        @fields sys_fn() (FiPDE.kA => kind == A, FiPDE.vol => volume[owner])
    end
    @sweep Metropolis(; temperature = 4.0)
end

FiDualTwo(; name = :FiDualTwo, kw...) = _FiDual24x20(; sys_fn = FiPDE.dual_two, bind_mode = :kA, name, kw...)
FiDualFill(; name = :FiDualFill, kw...) = _FiDual24x20(; sys_fn = FiPDE.dual_fill, bind_mode = :big, name, kw...)
FiDualVol(; name = :FiDualVol, kw...) = _FiDual24x20(; sys_fn = FiPDE.dual_vol, bind_mode = :kA_vol, name, kw...)

@potts_model FiDualNoField begin
    @kinds medium A
    @parameters λ = 1.0
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => λ * (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FiDualKind begin
    @kinds medium A
    @parameters δk[kind] = [0.0, 0.1]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields FiPDE.dual_kind() (FiPDE.dk => δk[kind])
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FiCoupleHost begin
    @kinds medium A
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 2.0)
end

# ---- Shared helpers ------------------------------------------------------------------------------------
fi_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

fi_kin(dims) = (K = zeros(Int32, dims...); K[4:6, 3:5] .= 1; K)

function fi_runA(M, op, k; field_solver = BackwardEuler(), kw...)
    integ = init(PottsProblem(M(; name = :f), op, (0, k); field_solver, kw...), SequentialCPM(); save_start = false, save_everystep = false)
    return [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:k], integ
end

function fi_runB(M, dims, k; u0, inputs = [:kind => fi_kin(dims)], alg = BackwardEuler())
    bp = Potts.LatticePDE.discretize(
        Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid(dims); T = Float64);
        u0, tspan = (0, k), inputs
    )
    return (s -> [s[:c, i] for i in 2:length(s.t)])(Potts.LatticePDE.solve(bp, alg; dt = 1.0, saveat = 1.0))
end

fi_warm(integ) = (step!(integ); @allocated step!(integ))
fi_rt(integ) = CorePotts._runtime(getfield(integ.ctx, :__fields1))
fi_c(integ) = copy(Array(current_state(integ).site.c))

function fi_check_table_rows(rows)
    dims = (12, 10)
    for (M, fs, k, u0_names, has_kind, check_warm) in rows
        a, integ = fi_runA(M, fi_op(dims), k; field_solver = fs)
        u0 = [nm => zeros(dims) for nm in u0_names]
        inputs = has_kind ? [:kind => fi_kin(dims)] : []
        alg = fs isa QuasiSteady ? QuasiSteady() : fs
        b = fi_runB(M, dims, k; u0, inputs, alg)
        @test a == b
        @test integ.retcode == FiRC.Default || integ.retcode == FiRC.Success
        @test (M === FiRobinN || fs isa CrankNicolson || fs isa BDF2) ? integ.stats.fields.solves >= k : integ.stats.fields.solves == k
        if M === FiMix && fs isa BackwardEuler
            rt = fi_rt(integ)
            @test rt.cache isa FIP.ImplicitCache && rt.cache.moving && rt.cache.newton == 1
            @test integ.stats.fields.budget == 0
            xs = [i - 0.5 for i in 1:12, j in 1:10]
            eprev = Array(current_state(integ).site.e) .- (0.02 .+ 0.01 .* xs)
            m = eprev .>= 0.5 + 1.0e-9
            @test any(m) && !all(m) && all(a[end][m] .== 1.5) && !any(a[2] .== 1.5)
            ae, _ = fi_runA(FiMix, fi_op(dims), k; field_solver = ExplicitEuler())
            @test maximum(abs, ae[end] .- a[end]) > 1.0e-3
        elseif M === FiRobinN && fs isa BackwardEuler
            c = fi_rt(integ).cache
            @test c.newton == 8 && c.seen && substep_counts(integ) == [2] && integ.stats.fields.newton_budget == 0
        elseif M === FiMaskField && fs isa BackwardEuler
            m = fi_kin(dims) .== 1
            @test a[1][m] == [1 + 0.1 * (i - 0.5) for i in 1:12, j in 1:10][m]
        elseif fs isa CrankNicolson
            @test fi_rt(integ).cache.jumps == (M === FiMix)
        elseif fs isa QuasiSteady && M === FiSteady
            @test substep_counts(integ) == [1]
        end
        check_warm && @test fi_warm(integ) == 0
    end
end

fi_dop() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:A, :A]])

const FI_DW = [0.01 * (i + 2j) for i in 1:24, j in 1:20]

fi_dq(sol) = sum(FI_DW .* sol.u[end].site.c)

fi_drun(fs, ps; M = FiDual, op = fi_dop(), alg = SequentialCPM(), kw...) =
    solve(PottsProblem(M(; name = :m), [op; ps], (0, 12); field_solver = fs, seed = 3, kw...), alg; saveat = 0:3:12)

fi_derr(f) = try
    f(); ""
catch err
    sprint(showerror, err)
end

function fi_throws(T, pats, f)
    err = try
        f(); nothing
    catch e
        e
    end
    @test err isa T
    msg = sprint(showerror, err)
    for pat in pats
        @test occursin(pat, msg) || (println("Expected $(repr(pat)) in: ", msg); false)
    end
    return err
end

function fi_check_dual_fd(fs, params)
    base = fi_drun(fs, Pair[])
    for (name, v) in params
        d = fi_drun(fs, [name => ForwardDiff.Dual(v, 1.0)])
        @test all(d.u[i].σ == base.u[i].σ for i in eachindex(base.u))
        @test all(ForwardDiff.value.(d.u[i].site.c) == base.u[i].site.c for i in eachindex(base.u))
        @test eltype(d.u[end].site.c) <: ForwardDiff.Dual && eltype(d.u[end].site.c__next) === Float64
        h = 1.0e-4 * v
        rp, rm = fi_drun(fs, [name => v + h]), fi_drun(fs, [name => v - h])
        @test all(rp.u[i].σ == base.u[i].σ == rm.u[i].σ for i in eachindex(base.u))
        fd = (fi_dq(rp) - fi_dq(rm)) / 2h
        @test abs(fd) > 1.0e-6
        @test ForwardDiff.partials(fi_dq(d), 1) ≈ fd rtol = 1.0e-6
    end
end

fc_site(integ, names) = [copy(Array(getproperty(current_state(integ).site, n))) for n in names]

function fc_runA(M, k, names; kw...)
    integ = init(PottsProblem(M(; name = :f), fi_op((12, 10)), (0, k); kw...), SequentialCPM(); save_start = false, save_everystep = false)
    return [(step!(integ); fc_site(integ, names)) for _ in 1:k], integ
end

function fc_runB(M, k, names; alg, kw...)
    bp = Potts.LatticePDE.discretize(Potts.fields(M(; name = :f)),
        Potts.LatticePDE.LatticeDiscretization(Potts.LatticePDE.Grid((12, 10)); T = Float64);
        u0 = [n => zeros(12, 10) for n in names], tspan = (0, k), inputs = [:kind => fi_kin((12, 10))], kw...)
    s = Potts.LatticePDE.solve(bp, alg; dt = 1.0, saveat = 1.0)
    return [[s[n, i] for n in names] for i in 2:(k + 1)], s
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
