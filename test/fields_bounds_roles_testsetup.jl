@testsetup module FieldsBoundsRolesSetup
using Potts, Test

module FbrPDE
    using Potts
    include(joinpath(@__DIR__, "shared", "field_pde.jl"))
    using .FieldPDE
    @variables c(..) u(..) K(..)
    const X = (t, x, y)
    const C, U, KK = c(X...), u(X...), K(X...)
    ic(f, v = 0.0) = f(0, x, y) ~ v
    function field1(rate, dims, ps = []; bcs = [], c0 = 0.0, dvs = [C])
        return pdesys(
            [Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps
        )
    end
    function bounded(rate, c0 = 0.5; b = (0, 1), dims = (16, 16), ps = [], bcs = [])
        @variables c(..) [bounds = b]
        Cb = c(X...)
        return pdesys([Dt(Cb) ~ rate(Cb)], [ic(c, c0); bcs], dims, [Cb], ps)
    end
    iv_divk() = bounded(c -> DivKGrad(:harmonic)(c, c))
    iv_no_bounds() = field1(DivKGrad(:harmonic)(C, C), (16, 16); c0 = 0.5)
    iv_out() = bounded(c -> DivKGrad(:harmonic)(c, c), 1.5)
    function iv_aux()
        @parameters k = 2.0
        return pdesys(
            [KK ~ k * C, Dt(C) ~ 0.1 * laplacian(C) - KK],
            [ic(c, 0.5), ic(K)], (16, 16), [C, KK], [k]
        )
    end
    dir3() = bounded(c -> DivKGrad(:harmonic)(c, c); bcs = [c(t, 16, y) ~ 3.0])
    burgers() = bounded(c -> -Advect(Upwind1())([c, 0.0], c); dims = (32, 32))
    function iv_advect()
        return field1(
            0.1 * laplacian(C) - Advect(Upwind1())([0.05 * (1 + x), 0.0], C), (
                16, 16,
            ); c0 = 0.5
        )
    end
    function drift()
        @parameters Dc = 0.2 s = 1.0 k = 0.05
        return bounded(
            c -> DivKGrad(:harmonic)(Dc * (1 + c), c) + s - k * c, 0.0; b = (0, 3), ps = [
                Dc, s, k,
            ]
        )
    end
    function w_roles()
        @parameters Dc = 0.25
        @variables c(..) [lattice_storage = Float64] h(..) [lattice_storage = Float16] s(
            ..
        ) [lattice_storage = Float32]
        Cr, H, Sr = c(X...), h(X...), s(X...)
        return pdesys(
            [
                Dt(Cr) ~ Dc * laplacian(Cr) - 0.125 * Cr,
                Dt(H) ~ Dc * laplacian(H) - 0.125 * H,
                Dt(Sr) ~ Dc * laplacian(Sr) - 0.125 * Sr,
                Dt(U) ~ Dc * laplacian(U) + 0.5 * Cr,
            ], [ic(c), ic(h), ic(s), ic(u)], (12, 10), [Cr, H, Sr, U], [Dc]
        )
    end
    w_narrow() = field1(exp(C) - 1, (12, 10); c0 = 1.0e-6)
    function b_half()
        @parameters Dc = 0.2 s = 0.1 k = 0.05
        @variables c(..) [lattice_storage = Float16]
        Ch = c(X...)
        return pdesys(
            [Dt(Ch) ~ Dc * laplacian(Ch) + s - k * Ch], [ic(c)], (16, 16), [Ch], [Dc, s, k]
        )
    end
    function b_full()
        @parameters Dc = 0.2 s = 0.1 k = 0.05
        return field1(Dc * laplacian(C) + s - k * C, (16, 16), [Dc, s, k])
    end
end

@potts_model _Fb16x16 begin
    @structural_parameters sys_fn = FbrPDE.iv_divk
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FbIvDivK(; name = :FbIvDivK, kw...) = _Fb16x16(; sys_fn = FbrPDE.iv_divk, name, kw...)
function FbIvNoBounds(; name = :FbIvNoBounds, kw...)
    return _Fb16x16(;
        sys_fn = FbrPDE.iv_no_bounds, name,
        kw...
    )
end
FbIvOut(; name = :FbIvOut, kw...) = _Fb16x16(; sys_fn = FbrPDE.iv_out, name, kw...)
FbIvAux(; name = :FbIvAux, kw...) = _Fb16x16(; sys_fn = FbrPDE.iv_aux, name, kw...)
FbDir3(; name = :FbDir3, kw...) = _Fb16x16(; sys_fn = FbrPDE.dir3, name, kw...)
FbDrift(; name = :FbDrift, kw...) = _Fb16x16(; sys_fn = FbrPDE.drift, name, kw...)
FbIvAdvect(; name = :FbIvAdvect, kw...) = _Fb16x16(; sys_fn = FbrPDE.iv_advect, name, kw...)
FbHalf(; name = :FbHalf, kw...) = _Fb16x16(; sys_fn = FbrPDE.b_half, name, kw...)
FbFull(; name = :FbFull, kw...) = _Fb16x16(; sys_fn = FbrPDE.b_full, name, kw...)

@potts_model FbBurgers begin
    @kinds medium A
    @lattice Lattice((32, 32); boundary = Periodic())
    @energy cells(A) => (volume - 25.0)^2
    @fields FbrPDE.burgers()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _Fw12x10 begin
    @structural_parameters sys_fn = FbrPDE.w_roles
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FwRoles(; name = :FwRoles, kw...) = _Fw12x10(; sys_fn = FbrPDE.w_roles, name, kw...)
FwNarrow(; name = :FwNarrow, kw...) = _Fw12x10(; sys_fn = FbrPDE.w_narrow, name, kw...)

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
