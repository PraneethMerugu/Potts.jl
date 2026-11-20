# Core field setup for fields_tests.jl, fields_pipeline_tests.jl, gpu_tests.jl, and shared helpers/FdPDE.

@testsetup module FieldsSetup
using Potts, Test
using Potts: CorePotts
using PottsModels: MerksVasculogenesis, Merks2006, Merks2008
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

using StableRNGs: StableRNG
using ForwardDiff: ForwardDiff
using Potts.LatticePDE: DivKGrad

isdefined(@__MODULE__, :FieldPDE) || include(joinpath(@__DIR__, "shared", "field_pde.jl"))

module FdPDE
    using ..FieldPDE
    @variables c(..) u(..) o(..) v(..) m(..) K(..) w(..) e(..) s1(..) s2(..) cfield(..)
    @variables kA(..)::Bool [input = true] k1(..)::Bool [input = true] dk(..) [input = true] volume(..) [input = true]
    @variables domain(..) rnd(..) [input = true]
    const X = (t, x, y)
    const C, U, O, V, M, KK, W, E, S1, S2 = c(X...), u(X...), o(X...), v(X...), m(X...), K(X...), w(X...), e(X...), s1(X...), s2(X...)
    const KA, K1, DK, VOL, RND = kA(X...), k1(X...), dk(X...), volume(X...), rnd(X...)
    const Dx, Dy = Differential(x), Differential(y)
    const MCS = step_index(t)
    ic(f, v = 0.0) = f(0, x, y) ~ v
    field1(rate, dims, ps = []; bcs = [], c0 = 0.0, dvs = [C], kw...) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps; kw...)
    diffusion(dims, Dc0 = 1.0; h = 1) = (@parameters Dc = Dc0; field1(Dc * laplacian(C), dims, [Dc]; spacing = h))
    periodic() = diffusion((16, 8); h = 2.0)
    closed() = (@parameters Dc = 1.0 k = 0.0; field1(Dc * laplacian(C) - k * C, (12, 10), [Dc, k]))
    defaults() = (@parameters Dc = 1.0 k = 0.5; field1(Dc * laplacian(C) - k * C, (6, 4), [Dc, k]; c0 = 2.0))
    computed_rate() = (@parameters Dc = 1.0 k = 0.5 k2 = 2k; field1(Dc * laplacian(C) - k2 * C, (6, 4), [Dc, k, k2]; c0 = 1.0))
    volume_read() = field1(0.01 * VOL, (6, 4); dvs = [C, VOL])
    source(dims = (12, 10)) = (@parameters Dc = 0.2 s = 0.05; field1(Dc * laplacian(C) + s * KA, dims, [Dc, s]; dvs = [C, KA]))
    two() = pdesys([Dt(C) ~ 0.2 * laplacian(C) + 0.05 * KA, Dt(U) ~ 0.1 * laplacian(U) + 0.5 * C], [ic(c), ic(u)], (12, 10), [C, U, KA])
    decay() = field1(-2.0, (6, 6); c0 = 1.0)
    mask() = (@parameters v = 3.0; field1(0.2 * laplacian(C), (10, 8), [v]; bcs = [C ~ masked(KA, v)], dvs = [C, KA]))
    hex(dims) = diffusion(dims, 0.1)
    function half(dims = (12, 10), rate = (C, ps) -> ps[1] * laplacian(C); ps = (@parameters Dc = 1.0))
        @variables c(..) [lattice_storage = Float16]
        Ch = c(X...)
        return pdesys([Dt(Ch) ~ rate(Ch, ps)], [ic(c)], dims, [Ch], collect(ps))
    end
    stripe() = field1(0.1 * laplacian(C), (9, 9); bcs = [c(t, 0, y) ~ 0.0, c(t, 9, y) ~ 100.0])
    rand_rate() = field1(0.1 * laplacian(C) + 0.01 * RND, (8, 6); dvs = [C, RND])
    domain_word() = (DW = domain(X...); pdesys([Dt(DW) ~ 0.1 * laplacian(DW)], [ic(domain)], (9, 9), [DW]))
    tab() = (@parameters Dc = 0.2; field1(Dc * laplacian(C) - DK * C, (10, 8), [Dc]; c0 = 1.0, dvs = [C, DK]))
    gate() = (@parameters Dc = 1.0 t0 = 1.0; field1(ifelse(MCS >= t0, Dc * laplacian(C), 0.0), (12, 10), [Dc, t0]))
    function computed_face()
        @parameters Dc = 0.2 g1 = 1.0 g2 = 2.0 g = g1 + g2
        return field1(Dc * laplacian(C), (8, 8), [Dc, g1, g2, g]; bcs = [c(t, 0, y) ~ g])
    end
    expr_face() = (@parameters Dc = 0.2 g1 = 1.0 g2 = 2.0; field1(Dc * laplacian(C), (8, 8), [Dc, g1, g2]; bcs = [c(t, 0, y) ~ g1 + g2]))
    kind_nonlinear() = (@parameters Dc = 0.2; field1(Dc * laplacian(C) - C^2 * ifelse(K1, 1.0, 0.0), (8, 8), [Dc]; dvs = [C, K1]))
    divk() = (@parameters Dc = 0.2; field1(DivKGrad(:harmonic)(Dc, C), (8, 8), [Dc]))
    moving_mask() = (@parameters v = 1.0; field1(0.2 * laplacian(C), (12, 12), [v]; bcs = [C ~ masked(KA, v)], dvs = [C, KA]))
    chain_k() = (@parameters α = 0.1 β = 2α γ = β + 0.05 Dc = 0.2; field1(Dc * laplacian(C) - γ * C, (8, 6), [α, β, γ, Dc]; c0 = 1.0))
    function w_wide()
        @parameters Dc = 0.25
        @variables c(..) [lattice_storage = Float64]
        Cr = c(X...)
        return pdesys([Dt(Cr) ~ Dc * laplacian(Cr) - 0.125 * Cr, Dt(U) ~ Dc * laplacian(U) + 0.5 * Cr], [ic(c), ic(u)], (12, 10), [Cr, U], [Dc])
    end
end

function fd_ftcs(c0, D, h, dt, n; periodic, rate = (c, i, j) -> 0.0, lower = nothing)
    c = copy(c0)
    nx, ny = size(c)
    for _ in 1:n
        new = similar(c)
        for j in 1:ny, i in 1:nx
            lap = 0.0
            for (di, dj, hd) in ((1, 0, h[1]), (-1, 0, h[1]), (0, 1, h[2]), (0, -1, h[2]))
                a, b = i + di, j + dj
                if periodic
                    a, b = mod1(a, nx), mod1(b, ny)
                elseif !(1 <= a <= nx && 1 <= b <= ny)
                    continue
                end
                lap += (c[a, b] - c[i, j]) / hd^2
            end
            v = c[i, j] + dt / n * (D * lap + rate(c, i, j))
            new[i, j] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

function fb_ftcs(c0, D, h, dt, n, ghost)
    c = copy(c0)
    nx, ny = size(c)
    for _ in 1:n
        new = similar(c)
        for j in 1:ny, i in 1:nx
            lap = 0.0
            for (d, s) in ((1, 1), (1, -1), (2, 1), (2, -1))
                a, b = d == 1 ? (i + s, j) : (i, j + s)
                nb = (1 <= a <= nx && 1 <= b <= ny) ? c[a, b] : ghost(d, s, c[i, j])
                lap += (nb - c[i, j]) / h^2
            end
            new[i, j] = c[i, j] + dt / n * D * lap
        end
        c = new
    end
    return c
end

fd_empty(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]
fd_rand(dims) = rand(StableRNG(7), dims...)
function fd_mcs(prob, n; alg = SequentialCPM())
    integ = init(prob, alg; save_start = false)
    return [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:n]
end
fd_source_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])
function fd_err(f)
    return try
        f(); nothing
    catch e
        sprint(showerror, e)
    end
end
fd_n(integ, j = 1) = CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n
fdvar(sys, n) = only(filter(x -> string(x) in (n, n * "(t)"), Potts.declared_variables(sys)))
function fdargerr(f)
    return try
        f(); ""
    catch err
        err isa ArgumentError || rethrow()
        replace(sprint(showerror, err), r"\s+" => " ")
    end
end

const FD_HEX6 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))

function fd_oldpath(c0, lat, D, n; h = 1.0, bc = nothing, lower = nothing)
    c = copy(c0)
    N = ndims(lat)
    hex = lat.geometry isa CorePotts.Hexagonal
    for _ in 1:n
        new = similar(c)
        for i in eachindex(c)
            x = CorePotts.coordinates(lat, i)
            ci = c[i]
            CorePotts.in_domain(lat, i) || (new[i] = ci; continue)
            lap = 0.0
            if hex
                for o in FD_HEX6
                    inside, y = CorePotts.shift(lat, x, Int32.(o))
                    lap += (inside ? c[CorePotts.linear_index(lat, y)] : ci) - ci
                end
                lap *= 2 / (3 * h^2)
            else
                for d in 1:N, (s, side) in ((1, 2), (-1, 1))
                    o = ntuple(k -> Int32(k == d ? s : 0), N)
                    inside, y = CorePotts.shift(lat, x, o)
                    v = bc === nothing ? nothing : bc[d][side]
                    nb = if inside
                        c[CorePotts.linear_index(lat, y)]
                    elseif CorePotts._within_faces(lat, x, o) || v === nothing
                        ci
                    else
                        2v - ci
                    end
                    lap += (nb - ci) / h^2
                end
            end
            v = ci + D * lap / n
            new[i] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

struct FdNotANumber <: Real end
struct FdFakeDevice <: Potts.KernelAbstractions.GPU end

@potts_model FdPeriodic begin
    @kinds medium A
    @lattice Lattice((16, 8); boundary = Periodic(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.periodic()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _Fd12x10 begin
    @structural_parameters sys_fn = FdPDE.closed
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FdClosed(; name = :FdClosed, kw...) = _Fd12x10(; sys_fn = FdPDE.closed, name, kw...)
FdHalf(; name = :FdHalf, kw...) = _Fd12x10(; sys_fn = FdPDE.half, name, kw...)
FdGate(; name = :FdGate, kw...) = _Fd12x10(; sys_fn = FdPDE.gate, name, kw...)

@potts_model _Fd6x4 begin
    @structural_parameters variant = :defaults
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if variant === :defaults
        @fields FdPDE.defaults()
    elseif variant === :computed
        @fields FdPDE.computed_rate()
    elseif variant === :vol
        @fields FdPDE.volume_read() (FdPDE.volume => volume[owner])
    else
        throw(ArgumentError("unknown _Fd6x4 variant: $variant"))
    end
    @sweep Metropolis(; temperature = 1.0)
end

FdDefaults(; name = :FdDefaults, kw...) = _Fd6x4(; variant = :defaults, name, kw...)
FdComputedRate(; name = :FdComputedRate, kw...) = _Fd6x4(; variant = :computed, name, kw...)
FdVolumeRead(; name = :FdVolumeRead, kw...) = _Fd6x4(; variant = :vol, name, kw...)

@potts_model _FdFrozen12x10 begin
    @structural_parameters sys_fn = FdPDE.source
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields sys_fn() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

FdSource(; name = :FdSource, kw...) = _FdFrozen12x10(; sys_fn = FdPDE.source, name, kw...)
FdTwo(; name = :FdTwo, kw...) = _FdFrozen12x10(; sys_fn = FdPDE.two, name, kw...)

@potts_model FdDecay begin
    @kinds medium A
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.decay()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdMask begin
    @kinds medium A wall[frozen]
    @lattice Lattice((10, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.mask() (FdPDE.kA => kind == wall)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdHex begin
    @structural_parameters begin
        boundary = Periodic()
        dims = (8, 6)
    end
    @kinds medium A
    @lattice Lattice(dims; geometry = Hexagonal(), boundary)
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.hex(dims)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdDomain begin
    @structural_parameters begin
        dims = (40, 40)
        domain = x -> (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
    end
    @kinds medium A
    @lattice Lattice(dims; boundary = Closed(), domain)
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.diffusion(dims, 0.2)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _Fd9x9Stripe begin
    @structural_parameters sys_fn = FdPDE.stripe
    @kinds medium A
    @lattice Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    @energy cells(A) => (volume - 4.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FdStripe(; name = :FdStripe, kw...) = _Fd9x9Stripe(; sys_fn = FdPDE.stripe, name, kw...)
FdDomainWord(; name = :FdDomainWord, kw...) = _Fd9x9Stripe(; sys_fn = FdPDE.domain_word, name, kw...)

@potts_model FdRand begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.rand_rate() (FdPDE.rnd => rand())
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdTab begin
    @kinds medium A
    @parameters δ[kind] = [0.5, 0.0]
    @lattice Lattice((10, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.tab() (FdPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdMovingMask begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.moving_mask() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 20.0)
end

@potts_model FdChainK begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.chain_k()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _Fd8x8A begin
    @structural_parameters variant = :expr
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    if variant === :expr
        @fields FdPDE.expr_face()
    elseif variant === :computed
        @fields FdPDE.computed_face()
    elseif variant === :kind_nonlin
        @fields FdPDE.kind_nonlinear() (FdPDE.k1 => kind == 1)
    elseif variant === :divk
        @fields FdPDE.divk()
    else
        throw(ArgumentError("unknown _Fd8x8A variant: $variant"))
    end
    @sweep Metropolis(; temperature = 1.0)
end

FdExprFace(; name = :FdExprFace, kw...) = _Fd8x8A(; variant = :expr, name, kw...)
FdComputedFace(; name = :FdComputedFace, kw...) = _Fd8x8A(; variant = :computed, name, kw...)
FdKindNonlinear(; name = :FdKindNonlinear, kw...) = _Fd8x8A(; variant = :kind_nonlin, name, kw...)
FdDivK(; name = :FdDivK, kw...) = _Fd8x8A(; variant = :divk, name, kw...)

@potts_model FwWide begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.w_wide()
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
