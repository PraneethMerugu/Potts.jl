@testsetup module FieldsOpBcsSetup
using Potts, Test

module FpPDE
    using Potts
    include(joinpath(@__DIR__, "shared", "field_pde.jl"))
    using .FieldPDE
    @variables c(..) m(..) K(..) w(..) e(..) cfield(..) kA(..)::Bool [input = true]
    const X = (t, x, y)
    const C, M, KK, W, E, KA = c(X...), m(X...), K(X...), w(X...), e(X...), kA(X...)
    const Dx, Dy = Differential(x), Differential(y)
    const MCS = step_index(t)
    ic(f, v = 0.0) = f(0, x, y) ~ v
    field1(rate, dims, ps = []; bcs = [], c0 = 0.0, dvs = [C], kw...) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps; kw...)
    p_divk() = (@parameters K0 = 0.4 s = 0.01; field1(DivKGrad(:harmonic)(K0, C) + s * x, (8, 6), [K0, s]))
    p_raw() = (@parameters K0 = 0.4 s = 0.01; field1(Dx(K0 * Dx(C)) + Dy(K0 * Dy(C)) + s * x, (8, 6), [K0, s]))
    p_aux() = (
        @parameters K0 = 0.4 s = 0.01;
        pdesys([KK ~ K0 * (1 + 0.05 * x), Dt(C) ~ DivKGrad(:arithmetic)(KK, C) + s * x], [ic(c), ic(K)], (8, 6), [C, KK], [K0, s])
    )
    p_map() = (@parameters g = 0.5; pdesys([Shift(t, 1)(M) ~ g * M + x], [ic(m)], (6, 4), [M], [g]))
    p_advect() = (@parameters ux = 0.3 s = 0.01; field1(-Advect(Upwind1())([ux, 0.0], C) + s * y, (8, 6), [ux, s]))
    p_advect_const() = (@parameters s = 0.01; field1(-Advect(Upwind1())([0.3, 0.0], C) + s * y, (8, 6), [s]))
    p_mixed() = pdesys([Dt(C) ~ -C, Shift(t, 1)(M) ~ M + 1], [ic(c), ic(m)], (6, 4), [C, M])
    p_z() = (C3 = c(t, x, y, z); pdesys([Dt(C3) ~ 0.1 * z], [c(0, x, y, z) ~ 0.0], (4, 4, 3), [C3]))
    p_map_repeat() = pdesys([Shift(t, 1)(M) ~ 0.5 * M + 1], [ic(m)], (6, 4), [M])
    advect_short() = field1(-Advect(Upwind1())([0.3], C) + 0.1 * laplacian(C), (8, 6))
    z2d() = field1(Differential(z)(Differential(z)(C)), (6, 4))
    b_dc(bcs = []; dims = (8, 6)) = (@parameters Dc = 0.5; field1(Dc * laplacian(C), dims, [Dc]; bcs))
    b_none() = b_dc()
    b_bcs_face() = b_dc([c(t, 0, y) ~ 1.0])
    function b_flux_robin_bcs()
        @parameters Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr = 0.5
        return field1(Dc * laplacian(C), (8, 6), [Dc, q, αr, βr, gr]; bcs = [Dx(c(t, 0, y)) ~ -q, αr * c(t, 8, y) + βr * Dx(c(t, 8, y)) ~ gr])
    end
    function b_bcs_nr()
        @parameters Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr = 0.5
        return field1(Dc * laplacian(C), (8, 6), [Dc, q, αr, βr, gr]; bcs = [Dx(c(t, 8, y)) ~ q, αr * c(t, x, 0) - βr * Dy(c(t, x, 0)) ~ gr])
    end
    b_self_mask(rate) = (@parameters Dc = 0.5; field1(rate(Dc), (8, 6), [Dc]; bcs = [C ~ masked(C >= 0.8, 0.8)]))
    b_self_mask_bcs() = b_self_mask(Dc -> 0.1)
    b_self_mask_diff_bcs() = b_self_mask(Dc -> Dc * laplacian(C) + 0.1)
    b_mask_later_bcs() = pdesys([Dt(C) ~ 0.5 * laplacian(C), Dt(E) ~ 0.1], [ic(c), ic(e), C ~ masked(E >= 0.5, 0.8)], (8, 6), [C, E])
    interior() = b_dc([c(t, 3, y) ~ 1.0, c(t, 8, y) ~ 0.0])
    periodic_bcs() = b_dc([c(t, x, 0) ~ c(t, x, 6)])
    b_mask_earlier() = pdesys([Dt(C) ~ 0.5 * laplacian(C) - 0.2 * C, Dt(E) ~ 0.1], [ic(c), ic(e), E ~ masked(C >= 0.5, 0.0)], (8, 6), [C, E])
    function b_flux_robin2()
        @parameters Dc = 0.5 q = 0.2 αr = 3.0 βr = 1.0 gr = 0.5
        return field1(
            Dc * laplacian(C), (8, 6), [Dc, q, αr, βr, gr]; spacing = 2.0,
            bcs = [
                Dx(c(t, 0, y)) ~ -q, αr * c(t, 16, y) + βr * Dx(c(t, 16, y)) ~ gr,
                Dy(c(t, x, 0)) ~ -q, αr * c(t, x, 12) + βr * Dy(c(t, x, 12)) ~ gr,
            ]
        )
    end
    a_state() = pdesys([Dt(C) ~ 0.1 * laplacian(C) - 0.2 * C, KK ~ 2C + 1], [ic(c, 1.0), ic(K, -5.0)], (8, 8), [C, KK])
    a_lower() = pdesys([Dt(C) ~ 0.1 * laplacian(C) + 0.2 * KA, KK ~ 2C + 1], [ic(c, -1.0), ic(K, 7.0)], (8, 8), [C, KK, KA])
    a_one() = (CF = cfield(X...); pdesys([CF ~ 1.0], [ic(cfield)], (12, 8), [CF]))
    a_clock() = pdesys([KK ~ MCS + 0.5 * t], [ic(K, -1.0)], (6, 4), [KK])
    a_kind() = pdesys([KK ~ KA], [ic(K)], (12, 12), [KK, KA])
    a_block() = (@parameters m0 = 0.0; pdesys([KK ~ ifelse(MCS >= m0, 1.0, 0.0)], [ic(K)], (12, 12), [KK], [m0]))
    w_nonlinear() = (@parameters Dc = 0.1 kw = 0.5; field1(Dc * laplacian(C) - kw * C^2, (8, 8), [Dc, kw]))
    x_loop() = (
        @parameters kx = 1.0;
        pdesys([KK ~ C, Dt(W) ~ -kx * KK, Dt(C) ~ kx * W], [ic(w, 1.0), ic(c), ic(K)], (6, 4), [W, C, KK], [kx])
    )
end

@potts_model _Fp8x6 begin
    @structural_parameters begin
        sys_fn = FpPDE.p_divk
        spacing = 1.0
    end
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed(), spacing = (spacing, spacing))
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FpDivK(; name = :FpDivK, kw...) = _Fp8x6(; sys_fn = FpPDE.p_divk, name, kw...)
FpRaw(; name = :FpRaw, kw...) = _Fp8x6(; sys_fn = FpPDE.p_raw, name, kw...)
FpAdvect(; name = :FpAdvect, kw...) = _Fp8x6(; sys_fn = FpPDE.p_advect, name, kw...)
FpAux(; name = :FpAux, kw...) = _Fp8x6(; sys_fn = FpPDE.p_aux, name, kw...)
FpAdvectConst(; name = :FpAdvectConst, kw...) = _Fp8x6(; sys_fn = FpPDE.p_advect_const, name, kw...)
FpAdvectShort(; name = :FpAdvectShort, kw...) = _Fp8x6(; sys_fn = FpPDE.advect_short, name, kw...)
FbNone(; name = :FbNone, kw...) = _Fp8x6(; sys_fn = FpPDE.b_none, name, kw...)
FbBcsFace(; name = :FbBcsFace, kw...) = _Fp8x6(; sys_fn = FpPDE.b_bcs_face, name, kw...)
FbFluxRobin(; name = :FbFluxRobin, kw...) = _Fp8x6(; sys_fn = FpPDE.b_flux_robin_bcs, name, kw...)
FbFluxRobinBcs(; name = :FbFluxRobinBcs, kw...) = _Fp8x6(; sys_fn = FpPDE.b_flux_robin_bcs, name, kw...)
FbBcsNR(; name = :FbBcsNR, kw...) = _Fp8x6(; sys_fn = FpPDE.b_bcs_nr, name, kw...)
FbInterior(; name = :FbInterior, kw...) = _Fp8x6(; sys_fn = FpPDE.interior, name, kw...)
FbSelfMaskBcs(; name = :FbSelfMaskBcs, kw...) = _Fp8x6(; sys_fn = FpPDE.b_self_mask_bcs, name, kw...)
FbSelfMaskDiffBcs(; name = :FbSelfMaskDiffBcs, kw...) = _Fp8x6(; sys_fn = FpPDE.b_self_mask_diff_bcs, name, kw...)
FbMaskLaterBcs(; name = :FbMaskLaterBcs, kw...) = _Fp8x6(; sys_fn = FpPDE.b_mask_later_bcs, name, kw...)
FbMaskEarlier(; name = :FbMaskEarlier, kw...) = _Fp8x6(; sys_fn = FpPDE.b_mask_earlier, name, kw...)
FbFluxRobin2(; name = :FbFluxRobin2, kw...) = _Fp8x6(; sys_fn = FpPDE.b_flux_robin2, spacing = 2.0, name, kw...)
FbPeriodicBcs(; name = :FbPeriodicBcs, kw...) = _Fp8x6(; sys_fn = FpPDE.periodic_bcs, name, kw...)

@potts_model _Fp6x4 begin
    @structural_parameters begin
        sys_fn = FpPDE.p_map
        repeat_sched = false
    end
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
    if repeat_sched
        @schedule repeat(4, sweep(fraction = 1 // 4), fields)
    end
end

FpMap(; name = :FpMap, kw...) = _Fp6x4(; sys_fn = FpPDE.p_map, name, kw...)
FpMixed(; name = :FpMixed, kw...) = _Fp6x4(; sys_fn = FpPDE.p_mixed, name, kw...)
FpZ2D(; name = :FpZ2D, kw...) = _Fp6x4(; sys_fn = FpPDE.z2d, name, kw...)
FpMapRepeat(; name = :FpMapRepeat, kw...) = _Fp6x4(; sys_fn = FpPDE.p_map_repeat, repeat_sched = true, name, kw...)

@potts_model FpZ begin
    @kinds medium A
    @lattice Lattice((4, 4, 3); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FpPDE.p_z()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _FaOneAux begin
    @structural_parameters begin
        dims = (8, 8)
        vol = 9.0
        temp = 5.0
        variant = :state
    end
    @kinds medium A
    @lattice Lattice(dims)
    @energy cells => (volume - vol)^2
    if variant === :state
        @fields FpPDE.a_state()
    elseif variant === :lower
        @fields FpPDE.a_lower() (FpPDE.kA => kind == A)
    elseif variant === :one
        @fields FpPDE.a_one()
    elseif variant === :clock
        @fields FpPDE.a_clock()
        @schedule repeat(4, sweep(fraction = 1 // 4), fields)
    else
        throw(ArgumentError("unknown _FaOneAux variant: $variant"))
    end
    @sweep Metropolis(; temperature = temp)
end

FaState(; name = :FaState, kw...) = _FaOneAux(; dims = (8, 8), vol = 9.0, temp = 5.0, variant = :state, name, kw...)
FaLower(; name = :FaLower, kw...) = _FaOneAux(; dims = (8, 8), vol = 9.0, temp = 5.0, variant = :lower, name, kw...)
FaOne(; name = :FaOne, kw...) = _FaOneAux(; dims = (12, 8), vol = 16.0, temp = 1.0, variant = :one, name, kw...)
FaClock(; name = :FaClock, kw...) = _FaOneAux(; dims = (6, 4), vol = 4.0, temp = 1.0, variant = :clock, name, kw...)

@potts_model FaKind begin
    @kinds medium A B
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16.0)^2
    @fields FpPDE.a_kind() (FpPDE.kA => ismember(kind, (2,)))
    @sweep Metropolis(; temperature = 20.0)
end

@potts_model FaBlock begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16.0)^2
    @fields K = FpPDE.a_block()
    @drive copy => ifelse(K[target] > 0.5, 1.0e9, 0.0)
    @sweep Metropolis(; temperature = 50.0)
end

@potts_model FwNonlinear begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells(A) => (volume - 9)^2
    @fields FpPDE.w_nonlinear()
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model FxLoop begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 4))
    @energy cells(A) => (volume - 4.0)^2
    @fields FpPDE.x_loop()
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
