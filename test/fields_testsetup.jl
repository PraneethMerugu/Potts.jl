# The top-level definitions of fields.jl (converted from the include-into-Main suite, TS1a).

@testsetup module FieldsSetup
using Potts, Test
using Potts: CorePotts
# (exported for the items: fields_pipeline_tests.jl's device gate and warm-MCS gates build them)
using PottsModels: MerksVasculogenesis, Merks2006, Merks2008
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

# ---- from fields.jl ---------------------------------------------------------------------------------
using Potts: CorePotts

using StableRNGs: StableRNG
using ForwardDiff: ForwardDiff          # (the items' Dual probes; visible through this setup's export)


# The models' fields, coupled with `@fields` (F4-B4t, F4-B6; before, written in `@equations`,
# `@bcs` and `@boundary`): each PDESystem below is the field system of the model of the same
# name. A kind or a CPM term is a bound input (`kA => kind == A`), a kind table the model's
# (`dk => δ[kind]`). The tests of A's own syntax and refusals went with it (F4-B6).
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
# one field `c` with the rate `rate`, the conditions `bcs` and the initial value `c0`
field1(rate, dims, ps = []; bcs = [], c0 = 0.0, dvs = [C], kw...) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps; kw...)
# the diffusion `Dc Δc` on `dims` (spacing `h`)
diffusion(dims, Dc0 = 1.0; h = 1) = (@parameters Dc = Dc0; field1(Dc * Δ(C), dims, [Dc]; spacing = h))
periodic() = diffusion((16, 8); h = 2.0)
closed() = (@parameters Dc = 1.0 k = 0.0; field1(Dc * Δ(C) - k * C, (12, 10), [Dc, k]))
defaults() = (@parameters Dc = 1.0 k = 0.5; field1(Dc * Δ(C) - k * C, (6, 4), [Dc, k]; c0 = 2.0))
computed_rate() = (@parameters Dc = 1.0 k = 0.5 k2 = 2k; field1(Dc * Δ(C) - k2 * C, (6, 4), [Dc, k, k2]; c0 = 1.0))
# an input named `volume`, bound to the owner's volume (A read the bare word, refused at build;
# B binds a cell quantity at the owner, F4-B6a)
volume_read() = field1(0.01 * VOL, (6, 4); dvs = [C, VOL])
source(dims = (12, 10)) = (@parameters Dc = 0.2 s = 0.05; field1(Dc * Δ(C) + s * KA, dims, [Dc, s]; dvs = [C, KA]))
two() = pdesys([Dt(C) ~ 0.2 * Δ(C) + 0.05 * KA, Dt(U) ~ 0.1 * Δ(U) + 0.5 * C], [ic(c), ic(u)], (12, 10), [C, U, KA])
decay() = field1(-2.0, (6, 6); c0 = 1.0)
mask() = (@parameters v = 3.0; field1(0.2 * Δ(C), (10, 8), [v]; bcs = [C ~ masked(KA, v)], dvs = [C, KA]))
hex(dims) = diffusion(dims, 0.1)
function half(dims = (12, 10), rate = (C, ps) -> ps[1] * Δ(C); ps = (@parameters Dc = 1.0))
    @variables c(..) [lattice_storage = Float16]
    Ch = c(X...)
    return pdesys([Dt(Ch) ~ rate(Ch, ps)], [ic(c)], dims, [Ch], collect(ps))
end
stripe() = field1(0.1 * Δ(C), (9, 9); bcs = [c(t, 0, y) ~ 0.0, c(t, 9, y) ~ 100.0])
# an input bound to a draw of the CPM (`rand()`)
rand_rate() = field1(0.1 * Δ(C) + 0.01 * RND, (8, 6); dvs = [C, RND])
# a field named `domain`, as the lattice's domain mask
domain_word() = (DW = domain(X...); pdesys([Dt(DW) ~ 0.1 * Δ(DW)], [ic(domain)], (9, 9), [DW]))
# the fields `fs` (no spatial operator), on a 6 × 6 box: `rates`, from `u0`
ode(rates, fs, u0, ps = []; dims = (6, 6)) =
    pdesys([Dt(f(X...)) ~ r for (f, r) in zip(fs, rates)], [ic(f, v) for (f, v) in zip(fs, u0)], dims, [f(X...) for f in fs], ps)
rot() = (@parameters k = 0.5; ode([-k * O, k * C], (c, o), [1.0, 0.0], [k]))
one_way() = (@parameters k = 3.0; ode([-0.1 * C, k * C - U], (c, u), [1.0, 0.0], [k]))
loop3() = (@parameters k = 3.0; ode([-k * O, -k * V, k * C], (c, o, v), [1.0, 0.0, 0.0], [k]))
loop_chain() = (@parameters k = 30.0 r = 0.5; ode([-r * O, r * C, k * C - U], (c, o, u), [1.0, 0.0, 0.0], [k, r]))
function unseen_chain()
    @parameters k = 3.0
    @variables z(..)
    Z = z(X...)
    return ode([-0.1 * C - 1.0e-9 * C * Z^2, k * C - U, -0.5 * Z], (c, u, z), [1.0, 0.0, 1.0], [k])
end
self_src() = (@parameters k = 3.0; ode([-0.1 * S1^2, k * S1 - U], (s1, u), [1.0, 0.0], [k]))
chain_loop() = (@parameters k = 3.0 w = 0.05; ode([-0.1 * S1, k * S1 - w * C, w * S2], (s1, s2, c), [1.0, 0.0, 0.5], [k, w]))
tab() = (@parameters Dc = 0.2; field1(Dc * Δ(C) - DK * C, (10, 8), [Dc]; c0 = 1.0, dvs = [C, DK]))
gate() = (@parameters Dc = 1.0 t0 = 1.0; field1(ifelse(MCS >= t0, Dc * Δ(C), 0.0), (12, 10), [Dc, t0]))
chemo() = (@parameters Dc = 0.2; field1(Dc * Δ(C) + 0.5 * KA - 0.1 * C, (24, 20), [Dc]; dvs = [C, KA]))
kind_nonlinear() = (@parameters Dc = 0.2; field1(Dc * Δ(C) - C^2 * ifelse(K1, 1.0, 0.0), (8, 8), [Dc]; dvs = [C, K1]))
divk() = (@parameters Dc = 0.2; field1(DivKGrad(:harmonic)(Dc, C), (8, 8), [Dc]))
rot_cells() = (@parameters k = 0.5 Dc = 0.1;
               pdesys([Dt(C) ~ Dc * Δ(C) - k * O - DK * O, Dt(O) ~ k * C], [ic(c, 1.0), ic(o)], (6, 6), [C, O, DK], [k, Dc]))
moving_mask() = (@parameters v = 1.0; field1(0.2 * Δ(C), (12, 12), [v]; bcs = [C ~ masked(KA, v)], dvs = [C, KA]))
mcs_source() = (@parameters η = 0.5; field1(-C + η * MCS, (6, 6), [η]; c0 = 1.0))
mcs_diff() = (@parameters ε = 0.5; field1((1 + ε * MCS) * Δ(C), (6, 6), [ε]))
clock_repeat() = ode([MCS, t], (c, u), [0.0, 0.0]; dims = (4, 4))
time_read() = field1(-C + sin(t), (4, 4); c0 = 0.3)
clock_half() = (@parameters η = 0.5; ode([MCS, t, -W + η * MCS], (c, u, w), [0.0, 0.0, 1.0], [η]; dims = (4, 4)))
# F2-10: the operators, aux fields and maps
p_divk() = (@parameters K0 = 0.4 s = 0.01; field1(DivKGrad(:harmonic)(K0, C) + s * x, (8, 6), [K0, s]))
p_raw() = (@parameters K0 = 0.4 s = 0.01; field1(Dx(K0 * Dx(C)) + Dy(K0 * Dy(C)) + s * x, (8, 6), [K0, s]))
p_aux() = (@parameters K0 = 0.4 s = 0.01;
           pdesys([KK ~ K0 * (1 + 0.05 * x), Dt(C) ~ DivKGrad(:arithmetic)(KK, C) + s * x], [ic(c), ic(K)], (8, 6), [C, KK], [K0, s]))
p_map() = (@parameters g = 0.5; pdesys([Shift(t, 1)(M) ~ g * M + x], [ic(m)], (6, 4), [M], [g]))
p_advect() = (@parameters ux = 0.3 s = 0.01; field1(-Advect(Upwind1())([ux, 0.0], C) + s * y, (8, 6), [ux, s]))
# the velocity as a constant vector
p_advect_const() = (@parameters s = 0.01; field1(-Advect(Upwind1())([0.3, 0.0], C) + s * y, (8, 6), [s]))
p_mixed() = pdesys([Dt(C) ~ -C, Shift(t, 1)(M) ~ M + 1], [ic(c), ic(m)], (6, 4), [C, M])
p_z() = (C3 = c(t, x, y, z); pdesys([Dt(C3) ~ 0.1 * z], [c(0, x, y, z) ~ 0.0], (4, 4, 3), [C3]))
p_map_repeat() = pdesys([Shift(t, 1)(M) ~ 0.5 * M + 1], [ic(m)], (6, 4), [M])
# F2-11: the conditions (faces, masks) of the PDESystems (front end A's `@bcs` until F4-B6)
b_dc(bcs = []; dims = (8, 6)) = (@parameters Dc = 0.5; field1(Dc * Δ(C), dims, [Dc]; bcs))
b_none() = b_dc()
b_bcs_face() = b_dc([c(t, 0, y) ~ 1.0])
# a face value that is a computed parameter, and the same value as an expression of parameters
computed_face() = (@parameters Dc = 0.2 g1 = 1.0 g2 = 2.0 g = g1 + g2;
                   field1(Dc * Δ(C), (8, 8), [Dc, g1, g2, g]; bcs = [c(t, 0, y) ~ g]))
expr_face() = (@parameters Dc = 0.2 g1 = 1.0 g2 = 2.0; field1(Dc * Δ(C), (8, 8), [Dc, g1, g2]; bcs = [c(t, 0, y) ~ g1 + g2]))
function b_flux_robin_bcs()
    @parameters Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr = 0.5
    return field1(Dc * Δ(C), (8, 6), [Dc, q, αr, βr, gr]; bcs = [Dx(c(t, 0, y)) ~ -q, αr * c(t, 8, y) + βr * Dx(c(t, 8, y)) ~ gr])
end
function b_bcs_nr()
    @parameters Dc = 0.5 q = 0.2 αr = 2.0 βr = 1.0 gr = 0.5
    return field1(Dc * Δ(C), (8, 6), [Dc, q, αr, βr, gr]; bcs = [Dx(c(t, 8, y)) ~ q, αr * c(t, x, 0) - βr * Dy(c(t, x, 0)) ~ gr])
end
b_self_mask(rate) = (@parameters Dc = 0.5; field1(rate(Dc), (8, 6), [Dc]; bcs = [C ~ masked(C >= 0.8, 0.8)]))
b_self_mask_bcs() = b_self_mask(Dc -> 0.1)
b_self_mask_diff_bcs() = b_self_mask(Dc -> Dc * Δ(C) + 0.1)
b_mask_later_bcs() = pdesys([Dt(C) ~ 0.5 * Δ(C), Dt(E) ~ 0.1], [ic(c), ic(e), C ~ masked(E >= 0.5, 0.8)], (8, 6), [C, E])
# F4-B6: a velocity of one term on a 2D lattice; `Differential(z)` on a 2D lattice; a condition
# off a face; a periodic pair on an axis the lattice closes
advect_short() = field1(-Advect(Upwind1())([0.3], C) + 0.1 * Δ(C), (8, 6))
z2d() = field1(Differential(z)(Differential(z)(C)), (6, 4))
interior() = b_dc([c(t, 3, y) ~ 1.0, c(t, 8, y) ~ 0.0])
periodic_bcs() = b_dc([c(t, x, 0) ~ c(t, x, 6)])
b_mask_earlier() = pdesys([Dt(C) ~ 0.5 * Δ(C) - 0.2 * C, Dt(E) ~ 0.1], [ic(c), ic(e), E ~ masked(C >= 0.5, 0.0)], (8, 6), [C, E])
function b_flux_robin2()
    @parameters Dc = 0.5 q = 0.2 αr = 3.0 βr = 1.0 gr = 0.5
    return field1(Dc * Δ(C), (8, 6), [Dc, q, αr, βr, gr]; spacing = 2.0,
        bcs = [Dx(c(t, 0, y)) ~ -q, αr * c(t, 16, y) + βr * Dx(c(t, 16, y)) ~ gr,
            Dy(c(t, x, 0)) ~ -q, αr * c(t, x, 12) + βr * Dy(c(t, x, 12)) ~ gr])
end
chain_k() = (@parameters α = 0.1 β = 2α γ = β + 0.05 Dc = 0.2; field1(Dc * Δ(C) - γ * C, (8, 6), [α, β, γ, Dc]; c0 = 1.0))
# F3-00: aux fields
a_state() = pdesys([Dt(C) ~ 0.1 * Δ(C) - 0.2 * C, KK ~ 2C + 1], [ic(c, 1.0), ic(K, -5.0)], (8, 8), [C, KK])
a_lower() = pdesys([Dt(C) ~ 0.1 * Δ(C) + 0.2 * KA, KK ~ 2C + 1], [ic(c, -1.0), ic(K, 7.0)], (8, 8), [C, KK, KA])
a_one() = (CF = cfield(X...); pdesys([CF ~ 1.0], [ic(cfield)], (12, 8), [CF]))
a_clock() = pdesys([KK ~ MCS + 0.5 * t], [ic(K, -1.0)], (6, 4), [KK])
a_kind() = pdesys([KK ~ KA], [ic(K)], (12, 12), [KK, KA])
a_block() = (@parameters m0 = 0.0; pdesys([KK ~ ifelse(MCS >= m0, 1.0, 0.0)], [ic(K)], (12, 12), [KK], [m0]))
w_nonlinear() = (@parameters Dc = 0.1 kw = 0.5; field1(Dc * Δ(C) - kw * C^2, (8, 8), [Dc, kw]))
x_loop() = (@parameters kx = 1.0;
            pdesys([KK ~ C, Dt(W) ~ -kx * KK, Dt(C) ~ kx * W], [ic(w, 1.0), ic(c), ic(K)], (6, 4), [W, C, KK], [kx]))
# F3-13: declared bounds (`b`: the bounds of `c`)
function bounded(rate, c0 = 0.5; b = (0, 1), dims = (16, 16), ps = [], bcs = [])
    @variables c(..) [bounds = b]
    Cb = c(X...)
    return pdesys([Dt(Cb) ~ rate(Cb)], [ic(c, c0); bcs], dims, [Cb], ps)
end
iv_divk() = bounded(c -> DivKGrad(:harmonic)(c, c))
iv_no_bounds() = field1(DivKGrad(:harmonic)(C, C), (16, 16); c0 = 0.5)
iv_out() = bounded(c -> DivKGrad(:harmonic)(c, c), 1.5)
iv_aux() = (@parameters k = 2.0; pdesys([KK ~ k * C, Dt(C) ~ 0.1 * Δ(C) - KK], [ic(c, 0.5), ic(K)], (16, 16), [C, KK], [k]))
dir3() = bounded(c -> DivKGrad(:harmonic)(c, c); bcs = [c(t, 16, y) ~ 3.0])
# Burgers: the velocity reads the field it moves
burgers() = bounded(c -> -Advect(Upwind1())([c, 0.0], c); dims = (32, 32))
iv_advect() = field1(0.1 * Δ(C) - Advect(Upwind1())([0.05 * (1 + x), 0.0], C), (16, 16); c0 = 0.5)
drift() = (@parameters Dc = 0.2 s = 1.0 k = 0.05;
           bounded(c -> DivKGrad(:harmonic)(Dc * (1 + c), c) + s - k * c, 0.0; b = (0, 3), ps = [Dc, s, k]))
# F3-14: number types per role
function w_roles()
    @parameters Dc = 0.25
    @variables c(..) [lattice_storage = Float64] h(..) [lattice_storage = Float16] s(..) [lattice_storage = Float32]
    Cr, H, Sr = c(X...), h(X...), s(X...)
    return pdesys([Dt(Cr) ~ Dc * Δ(Cr) - 0.125 * Cr, Dt(H) ~ Dc * Δ(H) - 0.125 * H, Dt(Sr) ~ Dc * Δ(Sr) - 0.125 * Sr,
            Dt(U) ~ Dc * Δ(U) + 0.5 * Cr], [ic(c), ic(h), ic(s), ic(u)], (12, 10), [Cr, H, Sr, U], [Dc])
end
function w_wide()
    @parameters Dc = 0.25
    @variables c(..) [lattice_storage = Float64]
    Cr = c(X...)
    return pdesys([Dt(Cr) ~ Dc * Δ(Cr) - 0.125 * Cr, Dt(U) ~ Dc * Δ(U) + 0.5 * Cr], [ic(c), ic(u)], (12, 10), [Cr, U], [Dc])
end
# S4 (batch-end review): a rate whose Float32 arithmetic cancels, `exp(c) - 1` at c = 1e-6
w_narrow() = field1(exp(C) - 1, (12, 10); c0 = 1e-6)
b_half() = half((16, 16), (C, ps) -> ps[1] * Δ(C) + ps[2] - ps[3] * C; ps = (@parameters Dc = 0.2 s = 0.1 k = 0.05))
b_full() = (@parameters Dc = 0.2 s = 0.1 k = 0.05; field1(Dc * Δ(C) + s - k * C, (16, 16), [Dc, s, k]))
end


# Hand FTCS on a 2D box: `n` substeps of `dt/n`; periodic or zero-flux faces; `rate(c, i, j)`
# the reaction; the update clipped below at `lower`
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
                    continue                                       # zero flux: the ghost is the site
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


@potts_model FdPeriodic begin
    @kinds medium A
    @lattice Lattice((16, 8); boundary = Periodic(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.periodic()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdClosed begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.closed()
    @sweep Metropolis(; temperature = 1.0)
end

# defaults that are not zero, for the PDESystem of `Potts.fields` (F1, V13)
@potts_model FdDefaults begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.defaults()
    @sweep Metropolis(; temperature = 1.0)
end

# a computed parameter, read through `Potts.fields` (F1)
@potts_model FdComputedRate begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.computed_rate()
    @sweep Metropolis(; temperature = 1.0)
end

# a CPM read other than `kind` in a field equation (an input named `volume`, F1)
@potts_model FdVolumeRead begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.volume_read() (FdPDE.volume => volume[owner])
    @sweep Metropolis(; temperature = 1.0)
end

# a frozen kind is a fixed source: σ never moves, so the field has an exact hand oracle
@potts_model FdSource begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.source() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

# two fields in two solver groups; `u` reads `c` from its own array
@potts_model FdTwo begin
    @kinds medium A[frozen]
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.two() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 1.0)
end

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

@potts_model FdHalf begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.half()
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

@potts_model FdStripe begin
    @kinds medium A
    @lattice Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.stripe()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdRand begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.rand_rate() (FdPDE.rnd => rand())
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model FdDomainWord begin
    @kinds medium A
    @lattice Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.domain_word()
    @sweep Metropolis(; temperature = 1.0)
end


fd_empty(dims) = [ownership => zeros(Int32, dims...), kind => Symbol[]]

fd_rand(dims) = rand(StableRNG(7), dims...)

# the field `c` after each of `n` MCS
fd_mcs(prob, n; alg = SequentialCPM()) = (integ = init(prob, alg; save_start = false);
                                          [(step!(integ); copy(Array(current_state(integ).site.c))) for _ in 1:n])

fd_source_op(dims) = (σ = zeros(Int32, dims...); σ[4:6, 3:5] .= 1; [ownership => σ, kind => [:A]])

fd_err(f) = try
    f(); nothing
catch e
    sprint(showerror, e)
end

fd_n(integ, j = 1) = CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n

# The old field path's Laplacian (CorePotts.laplacian before C8), as a hand oracle: square, the
# missing neighbor across a closed face is the face ghost (`2v − c` for Dirichlet `v`, else
# `c`) and across the domain edge `c`; hexagonal, `2/(3h²) Σ (cₙ − c)` over the six axial
# neighbors, a missing one reading `c`. `n` explicit substeps of `1/n` (clipped at `lower`).
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
            CorePotts.in_domain(lat, i) || (new[i] = ci; continue)        # outside: kept
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
                    nb = inside ? c[CorePotts.linear_index(lat, y)] :
                         CorePotts._within_faces(lat, x, o) || v === nothing ? ci : 2v - ci
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


# the rotation c' = −k o, o' = k c over the MCS window (dt = 1)
@potts_model FdRot begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.rot()
    @sweep Metropolis(; temperature = 1.0)
end


# Round 2 of the F2-06 review: only solver groups in a loop of the group read graph are limited
# (`u` reads `c`, `c` does not read `u`: a one-way chain, block triangular)
@potts_model FdOneWay begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.one_way()
    @sweep Metropolis(; temperature = 1.0)
end

# a 3-group loop (c reads o, o reads v, v reads c)
@potts_model FdLoop3 begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.loop3()
    @sweep Metropolis(; temperature = 1.0)
end

# a loop (the rotation of c and o at r) with a chain out of it (u reads c at k)
@potts_model FdLoopChain begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.loop_chain()
    @sweep Metropolis(; temperature = 1.0)
end

# a would-be chain z → c → u whose middle has a term the bound cannot see that reads z
@potts_model FdUnseenChain begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.unseen_chain()
    @sweep Metropolis(; temperature = 1.0)
end

# a chain whose source has a term on its own field only (`s1^2`: couples no group; round 3)
@potts_model FdSelfSrc begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.self_src()
    @sweep Metropolis(; temperature = 1.0)
end

# a one-way source s1 of the loop s2 ⇄ c (round 3)
@potts_model FdChainLoop begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.chain_loop()
    @sweep Metropolis(; temperature = 1.0)
end

# the rotation over a window `md`
function fd_rot_md(md)
    @potts_model FdRotMd begin
        @kinds medium A[frozen]
        @lattice Lattice((6, 6); boundary = Closed())
        @energy cells(A) => (volume - 4.0)^2
        @fields FdPDE.rot()
        @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
    end
    FdRotMd(; name = :rmd)
end

fdvar(sys, n) = only(filter(x -> string(x) in (n, n * "(t)"), Potts.variables(sys)))

fdargerr(f) = try
    f(); ""
catch err
    err isa ArgumentError || rethrow()
    replace(sprint(showerror, err), r"\s+" => " ")
end


@potts_model FdTab begin
    @kinds medium A
    @parameters δ[kind] = [0.5, 0.0]
    @lattice Lattice((10, 8); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.tab() (FdPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 1.0)
end


# a rate behind an `ifelse` gate that reads no field (Merks' `t ≥ t_relax`): bounded through
# its arms, so an explicit count stays a minimum over the diffusion (no warning)
@potts_model FdGate begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.gate()
    @sweep Metropolis(; temperature = 1.0)
end


# The threaded host Cartesian loop (above HOST_GRAIN sites, more than one thread): the same
# field as one thread, and a warm MCS allocates nothing (two fresh processes)
const FD_THREADS_RUN = raw"""
using Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: Δ, lattice_domain
@parameters x y Dc = 0.2
@variables c(..)
const FD_BIG = PDESystem([Differential(Potts.t)(c(Potts.t, x, y)) ~ Dc * Δ(c(Potts.t, x, y))], [c(0, x, y) ~ 0.0],
    lattice_domain(Potts.t, (x, y), (120, 100)), [Potts.t, x, y], [c(Potts.t, x, y)], [Dc]; name = :fields)
@potts_model FdBig begin
    @kinds medium A
    @lattice Lattice((120, 100); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FD_BIG
    @sweep Metropolis(; temperature = 1.0)
end
function fd_threads_run()
    c0 = [sin(i / 7) * cos(j / 5) for i in 1:120, j in 1:100]
    prob = PottsProblem(FdBig(; name = :b), [ownership => zeros(Int32, 120, 100), kind => Symbol[], :c => c0], (0, 20);
        field_solver = ExplicitEuler())
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
    step!(integ); step!(integ)
    a = minimum(_ -> (@allocated step!(integ)), 1:3)
    return a, hash(Array(current_state(integ).site.c))
end
a, h = fd_threads_run()
print(Threads.nthreads(), " ", a, " ", h)
"""


# P5 C3/4-1: a parameter that does not convert to the problem's scalar type is a named error.
# F1 (PO41): the field parameter `Dc` is not told the CPM reason (on f9a77dd3 the message said
# "CPM parameters are plain numbers … derivative is zero almost everywhere" for `Dc`)
struct FdNotANumber <: Real end


# ---------------------------------------------------------------------------------------
# The sub-MCS interleave: `@schedule repeat(n, sweep(fraction = 1//n), …)`
@potts_model FdChemo begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = FdPDE.chemo() (FdPDE.kA => kind == A)
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FdChemoPlain begin
    @extend base = FdChemo()
    @schedule sweep, fields
end

@potts_model FdChemoSplit begin                    # the sweep split, nothing between the passes
    @extend base = FdChemo()
    @schedule repeat(4, sweep(fraction = 1//4), after_mcs), fields
end

@potts_model FdChemoInter begin                    # the field stepped between the passes
    @extend base = FdChemo()
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end

@potts_model FdSourceInter begin
    @extend base = FdSource()
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end


fd_chemo_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2;
    [ownership => σ, kind => [:A, :A], :c => [0.05 * i for i in 1:24, j in 1:20]])


# ---------------------------------------------------------------------------------------
# F1: no silent wrongs, and messages in the model's words (refusal inventory)
using Potts.LatticePDE: DivKGrad

@potts_model FdExprFace begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.expr_face()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdComputedFace begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.computed_face()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdKindNonlinear begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.kind_nonlinear() (FdPDE.k1 => kind == 1)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdDivK begin
    @kinds medium A
    @lattice Lattice((8, 8); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.divk()
    @sweep Metropolis(; temperature = 1.0)
end


struct FdFakeDevice <: Potts.KernelAbstractions.GPU end


# F2-08a (review S1 of F2-06): a parameter write that the field phases refuse (a coupling past
# the limit, a negative diffusion coefficient) is refused before anything changes: by `setp`,
# `integ.ps[x] = v` and `remake` themselves, not by the next `step!` after its CPM sweep (base:
# `setp` returned, and the next `step!` threw after σ had moved, leaving a half step)
@potts_model FdRotCells begin
    @kinds medium A
    @parameters κ[kind] = [0.0, 0.0]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.rot_cells() (FdPDE.dk => κ[kind])
    @sweep Metropolis(; temperature = 1.0)
end


# F2-08b: the clamp at the step start in a model (D7; as front end B since F1). The masks
# run after the sweep, then the masked sites take their value, then the substeps: a site the
# cell has just reached holds `v` when the first substep's neighbors read it (base: the old
# value until the substep's store wrote `v`)
@potts_model FdMovingMask begin
    @kinds medium A
    @lattice Lattice((12, 12); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.moving_mask() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 20.0)
end


# F2-08c: the clock in a model (F2 design §2.6). `mcs` reads the step index (the reserved
# slot `clock__tick`: the MCS number at every substep, also in hoisted REAL forms), and
# `time` reads the PDESystem's time `t`: the window's start `(mcs + (r − 1)/R) · mcs_duration`
# plus `j h` at substep `j`
@potts_model FdMcsSource begin
    @kinds medium A
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.mcs_source()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FdMcsDiff begin
    @kinds medium A
    @lattice Lattice((6, 6); boundary = Periodic())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.mcs_diff()
    @sweep Metropolis(; temperature = 1.0)
end


# under `repeat(4, …, fields)` the four field passes of an MCS read one step index, and their
# windows start `mcs_duration / 4` apart
@potts_model FdClockRepeat begin
    @kinds medium A
    @lattice Lattice((4, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.clock_repeat()
    @sweep Metropolis(; temperature = 1.0)
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end


# `time` in a field equation reads `t0 + j h` per substep (base: a filled input, the CPM's time
# once per MCS, constant over the substeps)
@potts_model FdTimeRead begin
    @kinds medium A
    @lattice Lattice((4, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.time_read()
    @sweep Metropolis(; temperature = 1.0)
end


# Review round 1 of F2 batch 3 (S3 (b)): `mcs` and `time` under `repeat(4, …)` with
# `mcs_duration = 0.5` and a span that starts at MCS 2 (hand: window 0.125, t0 = (m + r/4) · 0.5)
@potts_model FdClockHalf begin
    @kinds medium A
    @lattice Lattice((4, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.clock_half()
    @sweep Metropolis(; temperature = 1.0, mcs_duration = 0.5)
    @schedule repeat(4, sweep(fraction = 1//4), fields)
end


# F2-10 (F2 design §2.11): `@equations` takes LatticePDE's operators (`DivKGrad`, `Advect`, a raw
# flux `Differential(x)(K * Differential(x)(c))`), aux fields `K ~ rhs`, maps `Shift(t, 1)(m) ~
# rhs` and the lattice coordinates `x`, `y`, `z`, all bound in the model body (no import). Each
# written in A and in B gives bitwise-equal arrays (σ frozen: no cell). Base (c2583722): every
# operator refused ("does not lower", PO02), the aux and the map refused (PO42, "equations are
# `D(x) ~ rhs`"), and `x` was a CPM read.
@potts_model FpDivK begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_divk()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpRaw begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_raw()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpAdvect begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_advect()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpAux begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_aux()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpMap begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_map()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpMixed begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_mixed()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpZ begin
    @kinds medium A
    @lattice Lattice((4, 4, 3); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_z()
    @sweep Metropolis(; temperature = 1.0)
end


# review M1–M3, S4 of F2 batch 4: a map under `repeat(4, …)` steps once per MCS; a constant
# velocity vector; a global `x`/`y`/`z` hidden by the coordinate binding warns; `Differential(z)`
# in 2D is not a clash
@potts_model FpMapRepeat begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_map_repeat()
    @sweep Metropolis(; temperature = 1.0)
    @schedule repeat(4, sweep(fraction = 1 // 4), fields)
end

@potts_model FpAdvectConst begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.p_advect_const()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpAdvectShort begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.advect_short()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FpZ2D begin
    @kinds medium A
    @lattice Lattice((6, 4); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.z2d()
    @sweep Metropolis(; temperature = 1.0)
end


# F2-11 (F2 design §2.12): a PDESystem's conditions (front end A's `@bcs` and `@boundary` until
# F4-B6) are parsed by LatticePDE's `parse_bcs`: faces (the face equation `α c + β ∂c/∂n = g`)
# and masks. Oracles: hand FTCS with the ghost-node rule, LatticePDE's own run. Base
# (c2583722): `@bcs` refused at `mtkcompile`; `Flux`/`Robin` refused (PO23).
@potts_model FbNone begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_none()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbBcsFace begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_bcs_face()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbFluxRobin begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_flux_robin_bcs()
    @sweep Metropolis(; temperature = 1.0)
end

# the same system under another name (both build, and both keep their derivative)
@potts_model FbFluxRobinBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_flux_robin_bcs()
    @sweep Metropolis(; temperature = 1.0)
end

# a Neumann face and a Robin face, against LatticePDE's own run of the same conditions
@potts_model FbBcsNR begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_bcs_nr()
    @sweep Metropolis(; temperature = 1.0)
end

# hand FTCS on a closed box with a ghost value per face: `ghost(d, s, ce)` is the missing
# neighbor of an edge site `ce` on side `s` (−1 low, +1 high) of axis `d`
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


# review S1, (a), (c), N1 of F2 batch 4 (S2, S3: front end A's `@boundary` routes, gone in F4-B6)
@potts_model FbInterior begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.interior()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbSelfMaskBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_self_mask_bcs()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbSelfMaskDiffBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_self_mask_diff_bcs()
    @sweep Metropolis(; temperature = 1.0)
end

# a mask on `c` that reads `e`, stepped after `c` (review round 2 of F2 batch 4, open question:
# accepted; before: refused "a field stepped with or after `c`"), and a mask on `e` that reads
# `c`, stepped before `e`
@potts_model FbMaskLaterBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_mask_later_bcs()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbMaskEarlier begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_mask_earlier()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbFluxRobin2 begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed(), spacing = (2.0, 2.0))
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_flux_robin2()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model FbPeriodicBcs begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.periodic_bcs()
    @sweep Metropolis(; temperature = 1.0)
end


# F2-15 (F2 design §2.7, D-F2-1): computed parameters are read-only and derived again from the
# base parameters after every write, in both front ends, through one derivation
# (`LatticePDE.derivation`). B keeps them as parameter slots, so a face value may read one.
# Base (244d58e7): A's computed parameters were settable (D-112) and `Potts.fields(FdComputedFace)`
# was refused by `discretize` ("a boundary value is a number, a parameter, or a number times a
# parameter").
@potts_model FdChainK begin
    @kinds medium A
    @lattice Lattice((8, 6); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.chain_k()
    @sweep Metropolis(; temperature = 1.0)
end


# F3-00 review r1 S1: a model with states and aux fields evaluates its aux fields at init too
# (the at-init phase runs for every group with aux kernels), so the first sweep and `u[1]` hold
# `rhs` of the initial state, not the declared value. Base (8f658abd): `K = -5` at init.
@potts_model FaState begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @fields FdPDE.a_state()
    @sweep Metropolis(; temperature = 5.0)
end

# review r2 N1: the at-init evaluation runs the `aux:` kernels alone, so it never writes the
# state: a `lower` bound does not clip `c = -1` at init. Base (e0347d1a, a zero-length step of the
# whole update): `c = 0.0` at init with the aux field, `-1.0` without it
@potts_model FaLower begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @fields FdPDE.a_lower() (FdPDE.kA => kind == A)
    @sweep Metropolis(; temperature = 5.0)
end


# F3-00 (F3 design §3.12; user ruling 2026-10-23): a model whose only fields are aux fields
# `K ~ rhs` builds. One field phase with no state evaluates them once per MCS, in the field
# phase's place (in pass 1 of a `repeat`), and once at init, so the first sweep reads `rhs`, not
# the declared value; clock reads take the window's start. Base (743ab0a0): `mtkcompile` refused
# every model here ("`cfield ~ 1.0` is an algebraic equation of the field `cfield` … the model
# steps no field").
@potts_model FaOne begin
    @kinds medium A
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @fields FdPDE.a_one()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FaClock begin
    @kinds medium A
    @lattice Lattice((6, 4))
    @energy cells => (volume - 4.0)^2
    @fields FdPDE.a_clock()
    @sweep Metropolis(; temperature = 1.0)
    @schedule repeat(4, sweep(fraction = 1 // 4), fields)
end

@potts_model FaKind begin
    @kinds medium A B
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16.0)^2
    @fields FdPDE.a_kind() (FdPDE.kA => ismember(kind, (2,)))
    @sweep Metropolis(; temperature = 20.0)
end

# a drive that forbids every copy into a site where `K > 0.5`: σ freezes from the first sweep
# that reads `K = 1`
@potts_model FaBlock begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16.0)^2
    @fields K = FdPDE.a_block()
    @drive copy => ifelse(K[target] > 0.5, 1.0e9, 0.0)
    @sweep Metropolis(; temperature = 50.0)
end


# F3-01 (F3 design §1.2 item 1, §3.7): one substep policy for both front ends. Front end A's
# rule is LatticeFields' `GroupSubsteps` (its `substeps` and `check_coupling`), in A's words;
# its warnings go to the one warning set, once per group, term and cause. An A sweep and a B
# sweep over the same term warn once each. Base (3d0ba21b): A kept its own policy
# (`_Substeps`) and its own set (`_SUBSTEP_WARNED`), so the shared set did not grow.
@potts_model FwNonlinear begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells(A) => (volume - 9)^2
    @fields FdPDE.w_nonlinear()
    @sweep Metropolis(; temperature = 5.0)
end


# F3-02 (F3 design §3.11): the aux-carried loop in a model (`K ~ c`, `D(w) ~ -k K`, `D(c) ~ k w`): one
# group is the Jacobi step, two groups (`solvers`) the split; K is read new (its kernel first).
# Base (eb2efb60): refused at build ("the fields K, c, w define each other within one step").
@potts_model FxLoop begin
    @kinds medium A[frozen]
    @lattice Lattice((6, 4))
    @energy cells(A) => (volume - 4.0)^2
    @fields FdPDE.x_loop()
    @sweep Metropolis(; temperature = 1.0)
end


# F3-04 (F3 design §3.3, §3.4; HANDOFF record "wire the read before an implicit solver lands in
# A"): A reads its field groups' status words (on the host after each window, on a device at
# `saveat` and the end). A stub with a solve (`AStub`) steps as Euler and writes into its word
# what an implicit solver would. Base (f8510fe8): A ignored the word, the run ended `Success`.
struct AStub <: Potts.LatticeFields.Problems.FieldAlgorithm
    code::UInt32
    at::Int
    need::Int
    budget::Int
end

AStub(; code = 0, at = 0, need = 0, budget = 8) = AStub(UInt32(code), at, need, budget)

mutable struct AStubCache
    word::Vector{UInt32}
    steps::Int
    a::AStub
end

Potts.LatticeFields.Problems.nbuffers(::AStub) = 2

Potts.LatticeFields.Problems.update_key(::AStub) = :euler

Potts.LatticeFields.Problems.update_rule(::AStub) = Potts.LatticeFields.Problems.update_rule(ExplicitEuler())

Potts.LatticeFields.Problems.alg_cache(a::AStub, group, store) = AStubCache(zeros(UInt32, 8), 0, a)

Potts.LatticeFields.Problems.status_word(c::AStubCache) = c.word

Potts.LatticeFields.Problems.substeps(::Potts.LatticeFields.Problems.GroupSpec, ::AStub, dt, pp; kw...) = 1

function Potts.LatticeFields.Problems.step_retcode!(c::AStubCache, rt)
    LFP = Potts.LatticeFields.Problems
    c.steps += 1
    c.word[LFP.STATUS_SOLVES] += 1
    c.a.need > c.a.budget && (c.word[LFP.STATUS_BUDGET] += 1)
    if c.a.code > 0 && c.steps == c.a.at
        c.word[LFP.STATUS_CODE] = c.a.code
        # the window, as a solver writes it: the runtime's window count (review r1 S3)
        c.a.code >= 2 && (c.word[LFP.STATUS_WINDOW] = rt.totals.windows; c.word[LFP.STATUS_CAUSE] = 0x2)
    end
    return Potts.SciMLBase.ReturnCode.Success
end


# F3-13 (F3 design §3.10, FE-11) in a model: a field's declared `bounds`, the coordinates, aux fields and
# advection reach the stability bound as in B (one bound: LatticePDE's), so these models take an
# automatic count, equal to B's for the same system. Base (b41b73c1, ~/lpwork/f3b8-nc-a-base.log):
# `bounds` is an unknown variable option, and every automatic count below is refused.
@potts_model FbIvDivK begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.iv_divk()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbIvNoBounds begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.iv_no_bounds()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbIvOut begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.iv_out()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbIvAux begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.iv_aux()
    @sweep Metropolis(; temperature = 1.0)
end


# Batch 5 review M1 in a model: a velocity that reads the advected field (Burgers) is not bounded by
# its frozen velocity; the automatic count is refused in words with its routes. Base 97045a1b
# (~/lpwork/b5r1-nc-m1.log): the count is [2], the run returns `Success` with c up to 1.129,
# above the declared bound 1 and the initial maximum 0.9.
@potts_model FbBurgers begin
    @kinds medium A
    @lattice Lattice((32, 32); boundary = Periodic())
    @energy cells(A) => (volume - 25.0)^2
    @fields FdPDE.burgers()
    @sweep Metropolis(; temperature = 1.0)
end


# Batch 5 review M2 in a model: a constant face value outside a field's declared bounds is refused at
# the build, and a field that leaves the interval its bound used ends the run with
# `ReturnCode.Unstable` and one warning (read after each MCS on the host). Base 97045a1b
# (~/lpwork/b5r1-nc-m2.log): the face model builds, and the source run returns `Success` with
# c up to 5.18 past its bound 3.
@potts_model FbDir3 begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.dir3()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbDrift begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.drift()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model FbIvAdvect begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.iv_advect()
    @sweep Metropolis(; temperature = 1.0)
end


# ---------------------------------------------------------------------------------------
# F3-14 (FE-17, F3 design §3.8): number types per role in a model. A field's `lattice_storage`
# (Float16, Float32 or Float64) is its array's type whatever the state type `T`; a group's
# `compute_T` compiles its kernels in a wider type (each store rounds once to the storage);
# `solver_T` is the implicit solver's. Base f5641ce1: `lattice_storage` is Float16 only and
# `compute_T` no keyword (the models below fail to build).
@potts_model FwRoles begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.w_roles()
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model FwWide begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.w_wide()
    @sweep Metropolis(; temperature = 1.0)
end


# Batch-end review S4: `compute_T = Float64` on a Float32 problem whose field is stored in Float32
# (no `lattice_storage`) computes in Float64 and rounds once at the store: `exp(c) - 1` at c = 1e-6
# loses 5% in Float32 arithmetic, nothing in Float64. The test above covers a Float64 storage
# only, where the group is wide whatever `compute_T` says. At ab34e226 this passes too (the
# reviewer's equal maxima were a coincidence of the printed digits: 504 of 576 sites differ,
# ~/lpwork/f4BE/s4.log); it pins the arithmetic type
@potts_model FwNarrow begin
    @kinds medium A
    @lattice Lattice((12, 10); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.w_narrow()
    @sweep Metropolis(; temperature = 1.0)
end


# Batch 5 review S1 and S4 in a model: a Float16 field under the implicit algorithms (solved in the
# state's type, each update rounded to Float16), accurate to its storage; a Dual parameter is
# refused in words (its value type, not its several-KB type); since F3-21b a Dual given to the
# problem runs, and an integrator write of one is refused. Base 97045a1b
# (~/lpwork/b5r1-nc-s1.log): every implicit algorithm refused; the Dual message prints the type.
@potts_model FbHalf begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_half()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model FbFull begin
    @kinds medium A
    @lattice Lattice((16, 16); boundary = Closed())
    @energy cells(A) => (volume - 9.0)^2
    @fields FdPDE.b_full()
    @sweep Metropolis(; temperature = 1.0)
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
