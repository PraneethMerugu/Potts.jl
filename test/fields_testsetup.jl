# The top-level definitions of fields.jl, fields_identity.jl (converted from the include-into-Main suite, TS1a).

@testsetup module FieldsSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

# ---- from fields.jl ---------------------------------------------------------------------------------
using Potts: CorePotts

using StableRNGs: StableRNG


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

# the same system under another name (a record of the guard)
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

using ForwardDiff: ForwardDiff

# ---- from fields_identity.jl ------------------------------------------------------------------------
using Potts, Test

using Potts: CorePotts

using PottsModels: MerksVasculogenesis, Merks2006, Merks2008


# (fields.jl's definitions, which this file read, are the part of this setup above)


# ---------------------------------------------------------------------------------------
# Copies of the pinned fixtures (p6_0o `P60oField`, p6_0g `P60gX`), verbatim

function p60o_field_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables c(..) dark(..)::Bool [input = true]
    C = c(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem([Potts.D(C) ~ 0.1 * L.Δ(C) + 0.02 * dark(t, x, y) - 0.01 * C],
        [c(0, x, y) ~ 0.0], L.lattice_domain(t, (x, y), (16, 16)), [t, x, y], [C, dark(t, x, y)], Any[]; name = :p60o_field)
end

@potts_model P60oField begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
        χ = 3.0
    end
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @fields c = p60o_field_pde() (:dark => kind == dark)
    @energy begin
        Volume(dark, light; target = 9.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end

const GD_OP_FIELD = [ownership => (s = zeros(Int32, 16, 16); s[:, 1] .= 1; s[4:6, 4:6] .= 2; s[10:12, 10:12] .= 3; s),
    kind => [:wall, :dark, :light]]


function p60g_q_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables q(..) tip_or_stalk(..)::Bool [input = true]
    Q = q(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem([Potts.D(Q) ~ 0.25 * tip_or_stalk(t, x, y)], [q(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), (32, 24)), [t, x, y], [Q, tip_or_stalk(t, x, y)], Any[]; name = :p60g_q)
end

@potts_model P60gX begin
    @kinds medium fluid matrix tip stalk
    @parameters begin
        J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
        χ = 4.0
    end
    @variables begin
        V(site) = 0.0
        gain(site) = 0.0
        near(site) = 0.0
        tgt(cell) = 0.0
        age(cell) = 0.0
        g(cell) = 0.0
    end
    @lattice Lattice((32, 24); neighborhood = Moore(1))
    @fields p60g_q_pde() (:tip_or_stalk => ((kind == tip) || (kind == stalk)))
    @variables n_ec(model) = 0.0
    @energy begin
        cells(tip, stalk) => 2.0 * (volume - 16)^2
        cells(fluid, matrix) => 0.02 * (volume - tgt)^2
        contacts => J[kind, kind′] + 3.0 * ((kind == tip) || (kind == stalk)) * ((kind′ == fluid) || (kind′ == matrix))
        sites => -0.5 * V * ((kind == tip) || (kind == stalk))
    end
    @drive begin
        copy => ifelse((kind[new] == tip) || (kind[new] == stalk), -χ * (V[target] - V[source]), 0.0)
        Chemotaxis(V; strength = 1.5, kinds = (tip, stalk))
    end
    @constraint begin
        connectivity(tip, stalk)
        !(((kind[old] == fluid) || (kind[old] == matrix)) && ((kind[new] == fluid) || (kind[new] == matrix)))
    end
    @on_copy gain[target] += ((kind[new] == tip) || (kind[new] == stalk))
    @before_mcs n_ec ~ count(true for c in cells(tip, stalk))
    @after_mcs begin
        age ~ Pre(age) + ((kind == tip) || (kind == stalk))
        near ~ count(true for n in Moore(1)(site) if (kind[n] == fluid) || (kind[n] == matrix))
    end
    @equations D(g) ~ 0.5 * ((kind == tip) || (kind == stalk))
    @observed begin
        nec ~ count(true for c in cells(tip, stalk))
        vecm ~ sum(volume for c in cells(fluid, matrix))
        nmix ~ count(true for c in cells if ((kind[c] == fluid) || (kind[c] == matrix)) || (kind[c] == tip))
        nmix2 ~ count(true for c in cells(fluid, matrix, tip))
        nnot ~ count(true for c in cells if !((kind[c] == tip) || (kind[c] == stalk)))
    end
    @sweep Metropolis(; temperature = 3.0)
end

function gd_p60g_op()
    σ = fill(Int32(1), 32, 24)
    σ[:, 9:10] .= 2; σ[:, 17:18] .= 3
    σ[4:7, 3:6] .= 4
    σ[4:7, 12:15] .= 5
    σ[12:15, 12:15] .= 6
    kinds = [:fluid, :matrix, :matrix, :tip, :stalk, :stalk]
    return [ownership => σ, kind => kinds, :V => [x / 32 for x in 1:32, y in 1:24],
        :tgt => Float64[count(==(c), σ) for c in 1:length(kinds)]]
end


# the frozen pins these copies reproduced (p6_0o, p6_0g): pin removed at integration (D-INT-1);
# replaced by a correctness test in the TS series
const GD_PINS = Dict{String, UInt64}()

# fingerprint records that moved at the integration with the lockless checkerboard's codegen
# (both sides changed them): pin removed at integration (D-INT-1); replaced by a correctness test
# in the TS series. Every behavior record (`|n`, `|digest|`) of these models is still compared.
# F4-15 (D-F4-15): the Jiang-like model's records that moved when a coarse field's kind bindings
# began to fold by the block mean: its field values (digests) and its program (fingerprints, the
# owner kernel gone). Not re-pinned: replaced by the property test of test/fields_jiang.jl (the
# coupled model equals its PDESystem with `Potts.field_inputs`, blocks covered in part included).
# Its mask, σ and kind digests and its `n` are still compared.
const GD_F415 = Set(["GjJiangLike BackwardEuler|Float64|digest|cell.ocell",
    ["GjJiangLike BackwardEuler|Float64|digest|site.$f$s" for f in ("g", "gf", "inh", "l", "o") for s in ("", "__next")]...,
    "GjJiangLike BackwardEuler|Float64|fingerprint", "GjJiangLike BackwardEuler|Float64|g1|arrays",
    "GjJiangLike BackwardEuler|Float64|g1|fingerprint_text"])

const GD_UNPINNED = GD_F415 ∪ Set(["fixture field|Float32|fingerprint",
    "fixture field|Float64|fingerprint",
    "GiMerks BackwardEuler|Float64|fingerprint",
    "GiMerks BDF2|Float64|fingerprint",
    "GiMerks CrankNicolson|Float64|fingerprint",
    "GiMerks QuasiSteady|Float64|fingerprint",
    "Merks2006|Float32|fingerprint",
    "Merks2006|Float64|fingerprint",
    "Merks2008|Float32|fingerprint",
    "Merks2008|Float64|fingerprint",
    "Merks2008 t_relax = 2.5|Float32|fingerprint",
    "Merks2008 t_relax = 2.5|Float64|fingerprint",
    "Merks2008 t_relax = 3|Float32|fingerprint",
    "Merks2008 t_relax = 3|Float64|fingerprint",
    "MerksVasculogenesis contact-inhibited|Float32|fingerprint",
    "MerksVasculogenesis contact-inhibited|Float64|fingerprint",
    "MerksVasculogenesis|Float32|fingerprint",
    "MerksVasculogenesis|Float64|fingerprint",
    "P60gX|Float32|fingerprint",
    "P60gX|Float64|fingerprint"])


# ---------------------------------------------------------------------------------------
# Copies of the `test/audit.jl` field models and of the p6_5c Fortuna-like model (soft set),
# their fields as PDESystems (a kind table or a parameter expression that a PDESystem does not
# hold is a bound input, `dk => δ[kind]`)

module GdPDE
using ..FieldPDE
@variables c(..) u(..) dk(..) [input = true]
const C, U, DK = c(t, x, y), u(t, x, y), dk(t, x, y)
const D16 = (16, 16)
ic(f) = f(0, x, y) ~ 0.0
diffusion() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * Δ(C)], [ic(c)], D16, [C], [Dc]))
nonlinear() = (@parameters Dc = 0.1 k = 0.5; pdesys([Dt(C) ~ Dc * Δ(C) - k * C^2], [ic(c)], D16, [C], [Dc, k]))
bounded() = (@parameters Dc = 1.0; pdesys([Dt(C) ~ Dc * Δ(C) - DK * C], [ic(c)], D16, [C, DK], [Dc]))
kind_diffusion() = pdesys([Dt(C) ~ DK * Δ(C)], [ic(c)], D16, [C, DK])
inv_table() = (@parameters Dc = 0.1; pdesys([Dt(C) ~ Dc * Δ(C) - (1 / DK) * C], [ic(c)], D16, [C, DK], [Dc]))
int_div() = (@parameters Dc = 0.25; Cx = c(t, x);
             pdesys([Dt(Cx) ~ Dc * Δ(Cx) - dk(t, x) * Cx], [c(0, x) ~ 0.0], (16,), [Cx, dk(t, x)], [Dc]))
two(e1, e2) = (@parameters Dc = 0.5 Dx = 0.5; pdesys([Dt(C) ~ e1(Dc, Dx), Dt(U) ~ e2(Dc, Dx)], [ic(c), ic(u)], (8, 8), [C, U], [Dc, Dx]))
cross_field() = two((Dc, Dx) -> Dc * Δ(C) - Dx * Δ(U), (Dc, Dx) -> Dc * Δ(U))
cross_linear() = two((Dc, Dx) -> Dc * Δ(C) - Dx * U, (Dc, Dx) -> Dc * Δ(U))
const MCS = step_index(t)
gate_rotation() = (@parameters t0 = 1000.0 k = 4.0;
                   pdesys([Dt(C) ~ ifelse(MCS >= t0, -10 * C, -k * U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, k * C)],
                       [ic(c), ic(u)], (8, 8), [C, U], [t0, k]))
gate_dominant() = (@parameters t0 = 1000.0;
                   pdesys([Dt(C) ~ ifelse(MCS >= t0, -10 * C - U, -10 * C + U), Dt(U) ~ ifelse(MCS >= t0, -10 * U, -5 * U)],
                       [ic(c), ic(u)], (8, 8), [C, U], [t0]))
end


@potts_model GdAuditDiffusion begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields GdPDE.diffusion()
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model GdAuditNonlinearField begin
    @kinds medium A
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields GdPDE.nonlinear()
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model GdAuditBoundedField begin
    @kinds medium A
    @parameters δ[kind] = [5.0, 0.0]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields GdPDE.bounded() (GdPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model GdAuditKindDiffusion begin             # test/audit.jl:272–280, `δ[kind] Δ(c)`
    @kinds medium A
    @parameters δ[kind] = [0.1, 0.2]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields GdPDE.kind_diffusion() (GdPDE.dk => δ[kind])
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model GdAuditInvTable begin
    @kinds medium A
    @parameters τ[kind] = [2.0, 0.5]
    @lattice Lattice((16, 16))
    @energy cells(A) => (volume - 9)^2
    @fields GdPDE.inv_table() (GdPDE.dk => τ[kind])
    @sweep Metropolis(; temperature = 5.0)
end

@potts_model GdAuditIntDivField begin
    @kinds medium A
    @parameters k₀ = 7.0
    @lattice Lattice((16,))
    @energy cells => (volume - 4.0)^2
    @fields GdPDE.int_div() (GdPDE.dk => k₀ ÷ 2)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model GdAuditCrossField begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields GdPDE.cross_field()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model GdAuditCrossLinear begin
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields GdPDE.cross_linear()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model GdAuditGateRotation begin             # test/audit.jl:424–440, reads `mcs`
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields GdPDE.gate_rotation()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model GdAuditGateDominant begin             # test/audit.jl:442–456, reads `mcs`
    @kinds medium A
    @lattice Lattice((8, 8))
    @energy cells => (volume - 4.0)^2
    @fields GdPDE.gate_dominant()
    @sweep Metropolis(; temperature = 1.0)
end

# p6_5c `P65cbAny` (Fixture P's shape, the any-neighbor predicate source)
function p65cb_pde(; diffusion = true, source = true)
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y z D_F = 0.0 k_d = 0.5 k_s = 0.5
    Potts.ModelingToolkitBase.@variables F(..) lam(..)::Bool [input = true] src(..) [input = true]
    X, LAM, SRC = F(t, x, y, z), lam(t, x, y, z), src(t, x, y, z)
    rate = -k_d * X + (source ? k_s * LAM * SRC : k_s * LAM)
    diffusion && (rate = D_F * L.Δ(X) + rate)
    return Potts.ModelingToolkitBase.PDESystem([Potts.D(X) ~ rate], [F(0, x, y, z) ~ 0.0],
        L.lattice_domain(t, (x, y, z), (6, 6, 4)), [t, x, y, z], source ? [X, LAM, SRC] : [X, LAM],
        diffusion ? [D_F, k_d, k_s] : [k_d, k_s]; name = :p65cb_field)
end

@potts_model GdP65cbAny begin
    @kinds medium substrate[frozen] lam
    @lattice Lattice((6, 6, 4); boundary = (Periodic(), Periodic(), Closed()), neighborhood = VonNeumann(1))
    touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0
    @fields p65cb_pde() (:lam => kind == lam, :src => any(kind[n] == substrate for n in VonNeumann(1)(site)))
    @parameters mobile = 0.0
    @energy cells(lam) => (volume - 8.0)^2
    @constraint mobile > 0.5
    @sweep Metropolis(; temperature = 1.0)
end

gd_p65cb_op() = (σ = zeros(Int32, 6, 6, 4); σ[:, :, 1] .= 1; σ[2:3, 2:3, 2:3] .= 2;
                 [ownership => σ, kind => [:substrate, :lam]])


# ---------------------------------------------------------------------------------------
# Records

# FNV-1a over bytes: a digest independent of Julia's `hash` (which samples large arrays)
function gd_fnv(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ b) * 0x00000100000001b3
    end
    return string(h; base = 16, pad = 16)
end

gd_digest(a) = gd_fnv(reinterpret(UInt8, vec(htol.(Array(a)))))

gd_text(s::AbstractString) = gd_fnv(codeunits(s))


gd_programs(sys, T, kw) = [e for e in generated_code(sys; T, kw...).phases if e isa Expr && e.head === :field_program]

# `n` of every field group of an integrator (the run-context entries `__fields1`, `__fields2`, …)
function gd_ns(integ)
    ns, j = Int[], 1
    while Symbol(:__fields, j) in propertynames(integ.ctx)
        push!(ns, CorePotts._runtime(getfield(integ.ctx, Symbol(:__fields, j))).n)
        j += 1
    end
    return ns
end

# solver keywords only (`generated_code` takes no `seed`)
gd_solverkw(kw) = (; (k => v for (k, v) in pairs(kw) if k in (:field_solver, :ode_solver, :solvers))...)


# the fingerprint records of one problem build: `pre` is "label|T"
function gd_fingerprints!(out, pre, sys, prob, T, kw)
    out["$pre|canonical"] = prob.f.sys.solvers.canonical
    out["$pre|fingerprint"] = repr(prob.f.fingerprint)
    progs = gd_programs(sys, T, gd_solverkw(kw))
    out["$pre|groups"] = string(length(progs))
    for (j, e) in enumerate(progs)
        fp, arrays, params, tables, least, flag = e.args
        out["$pre|g$j|fingerprint_text"] = gd_text(fp)
        out["$pre|g$j|arrays"] = arrays
        out["$pre|g$j|params"] = params
        out["$pre|g$j|tables"] = tables
        out["$pre|g$j|least"] = string(least)
        out["$pre|g$j|bounded"] = flag
    end
    return out
end


const GD_MERKS_OP = [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]]

# FdMask: a frozen wall column (Dirichlet v = 3) and one cell
gd_opmask() = (σ = zeros(Int32, 10, 8); σ[1, :] .= 1; σ[5:6, 4:5] .= 2; [ownership => σ, kind => [:wall, :A]])

# a one-site frozen border (cell 1) and two endothelial cells
function gd_op2006()
    σ = zeros(Int32, 16, 16)
    σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
    σ[4:7, 4:7] .= 2; σ[10:13, 9:12] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end

# a two-site frozen border and two endothelial cells
function gd_op2008()
    σ = zeros(Int32, 20, 20)
    σ[1:2, :] .= 1; σ[(end - 1):end, :] .= 1; σ[:, 1:2] .= 1; σ[:, (end - 1):end] .= 1
    σ[5:9, 5:9] .= 2; σ[12:16, 11:16] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end


# (label, system, operating point, keywords, pinned)
const GD_HARD = [
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), GD_MERKS_OP,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true), GD_MERKS_OP,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("Merks2006", () -> Merks2006(; name = :m, lattice = (16, 16)), gd_op2006(),
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    ("Merks2008", () -> Merks2008(; name = :m, lattice = (20, 20)), gd_op2008(),
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    # the `mcs >= t_relax` gate is crossed within the 5 MCS
    ("Merks2008 t_relax = 3", () -> Merks2008(; name = :m, lattice = (20, 20)), [gd_op2008(); :t_relax => 3.0],
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    ("fixture field", () -> P60oField(; name = :fld), GD_OP_FIELD,
        (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0)), true),
    ("P60gX", () -> P60gX(; name = :bauer), gd_p60g_op(), (; field_solver = ExplicitEuler()), true),
    # two solver groups; `u` reads `c` from its array (test/fields.jl FdTwo)
    ("FdTwo", () -> FdTwo(; name = :t), fd_source_op((12, 10)),
        (; field_solver = ExplicitEuler(substeps = 2), solvers = [:u => ExplicitEuler(substeps = 3)]), false),
    # F2 batch 2 (recorded at the batch-1 fixups): a sub-MCS `repeat(4, …)` field with n = 2,
    # the Merks2008 gate crossed between MCS boundaries, and the mask and domain lowerings (DivK
    # did not lower in `@equations` then (FdDivK was refused until F2-10): its digest is front
    # end B's, `GdB`)
    ("FdChemoInter repeat(4)", () -> FdChemoInter(; name = :m), fd_chemo_op(),
        (; field_solver = ExplicitEuler(substeps = 2)), false),
    ("Merks2008 t_relax = 2.5", () -> Merks2008(; name = :m, lattice = (20, 20)), [gd_op2008(); :t_relax => 2.5],
        (; field_solver = ExplicitEuler(substeps = 15)), false),
    ("FdMask digest", () -> FdMask(; name = :m), gd_opmask(), (; field_solver = ExplicitEuler()), false),
    ("FdDomain digest", () -> FdDomain(; name = :m), [fd_empty((40, 40)); :c => [0.01 * (i + 2j) for i in 1:40, j in 1:40]],
        (; field_solver = ExplicitEuler()), false),
]


function gd_hard!(out)
    for (label, build, op, kw, _) in GD_HARD, T in (Float64, Float32)
        pre = "$label|$T"
        sys = build()
        prob = PottsProblem(sys, op, (0, 5); T, seed = 7, kw...)
        gd_fingerprints!(out, pre, sys, prob, T, kw)
        integ = init(prob, SequentialCPM())
        out["$pre|n"] = string(gd_ns(integ))
        foreach(_ -> step!(integ), 1:5)
        st = current_state(integ)
        out["$pre|digest|σ"] = gd_digest(st.σ)
        for k in keys(st.site)
            out["$pre|digest|site.$k"] = gd_digest(getproperty(st.site, k))
        end
    end
    return out
end


const GD_SOFT = [:FdPeriodic, :FdClosed, :FdDefaults, :FdComputedRate, :FdVolumeRead, :FdSource, :FdDecay, :FdMask,
    :FdHex, :FdHalf, :FdDomain, :FdStripe, :FdRand, :FdDomainWord, :FdTab, :FdGate, :FdChemo, :FdChemoInter,
    :FdSourceInter, :FdComputedFace, :FdKindNonlinear, :FdDivK, :GdAuditDiffusion, :GdAuditNonlinearField,
    :GdAuditBoundedField, :GdAuditKindDiffusion, :GdAuditInvTable, :GdAuditIntDivField, :GdAuditCrossField,
    :GdAuditCrossLinear, :GdAuditGateRotation, :GdAuditGateDominant, :GdP65cbAny,
    # F2 batch 4 (review (d)): the operators, aux fields and maps of `@equations` (F2-10) and the
    # `@bcs` and `Flux`/`Robin` faces (F2-11), recorded at F2-11
    :FpDivK, :FpRaw, :FpAdvect, :FpAux, :FpMap, :FbBcsFace, :FbFluxRobin, :FbFluxRobinBcs, :FbBcsNR,
    # F3-00: an aux-only model (no stepped field, no `field_solver`), recorded at F3-00
    :FaOne]


gd_try(f) = try
    (f(), nothing)
catch e
    e isa ArgumentError || rethrow()
    (nothing, e)
end


# the automatic count first; refused, the same model with `substeps = 3` (the route records it)
function gd_soft!(out)
    for name in GD_SOFT
        M = getfield(@__MODULE__, name)
        sys = M(; name = :g)
        op = name === :GdP65cbAny ? gd_p65cb_op() :
             [ownership => zeros(Int32, Potts._p(sys, :lattice).dims...), kind => Symbol[]]
        pre = "$name|Float64"
        kw = name === :FpMap ? (; field_solver = ExplicitMap()) : name === :FaOne ? (;) : (; field_solver = ExplicitEuler())
        prob, e = gd_try(() -> PottsProblem(sys, op, (0, 2); kw...))
        route = "auto"
        if prob === nothing
            kw = (; field_solver = ExplicitEuler(substeps = 3))
            prob, e2 = gd_try(() -> PottsProblem(sys, op, (0, 2); kw...))
            route = prob === nothing ? "refused" : "explicit"
        end
        out["$pre|route"] = route
        prob === nothing && continue
        gd_fingerprints!(out, pre, sys, prob, Float64, kw)
        out["$pre|n"] = string(gd_ns(init(prob, SequentialCPM())))
    end
    return out
end


# ---------------------------------------------------------------------------------------
# Front end B (F2 batch 2): owned `FieldProblem`s (a rate with a Robin face, a site-diffusion
# rate with a host input, a DivK rate, a map) and the ODE right side, Float64: the substep count and a
# digest of the final state. F2-06 ports B onto the shared group layer; these must not move.
module GdB
using Potts: LatticePDE
using Potts.ModelingToolkitBase: @parameters, @variables, PDESystem, Differential, Shift, t_nounits as t,
                                 D_nounits as D
using .LatticePDE: Interval, discretize, LatticeDiscretization, Grid, Δ, at, DivKGrad, ExplicitEuler, ExplicitMap, solve,
                    substep_counts
function cases()
    @parameters x y βr = -0.5 Dk[1:2] = [0.2, 1.0] dx [lattice_spacing = 1]
    @variables c(..) kq(..)::Int32 [input = true] N(..)
    ce, qe, Ne = c(t, x, y), kq(t, x, y), N(t, x, y)
    dom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    own(sys, n; inputs = ()) = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64); inputs)
    out = Tuple{String, Any, Int}[]                     # label, final state, substep count (0: none)
    sr = PDESystem([D(ce) ~ Δ(ce)], [c(0, x, y) ~ x * y, c(t, 0, y) + βr * Differential(x)(c(t, 0, y)) ~ 1.0,
                                     c(t, x, 0) ~ c(t, x, 1)], dom(0.1), [t, x, y], [ce], [βr]; name = :r)
    s = solve(own(sr, 8), ExplicitEuler(; dt = 1e-2))
    push!(out, ("B Robin owned", s.u[end], substep_counts(s)[1]))
    o = discretize(sr, LatticeDiscretization(Grid((8, 8)); T = Float64))
    du = similar(o.u0)
    o.f(du, o.u0, o.p, 0.0)
    push!(out, ("B Robin ODE rhs", du, 0))
    ss = PDESystem([D(ce) ~ at(Dk, qe) * Δ(ce) - 0.1 * ce], [c(0, x, y) ~ 1.0 + sin(7x) * cos(5y)], dom(0.1),
        [t, x, y], [ce, qe], [Dk]; name = :s)
    K = [Int32(isodd(i + j) ? 1 : 2) for i in 1:8, j in 1:8]
    s = solve(own(ss, 8; inputs = [qe => K]), ExplicitEuler(; dt = 1e-2))
    push!(out, ("B site diffusion owned", s.u[end], substep_counts(s)[1]))
    sk = PDESystem([D(ce) ~ DivKGrad(:harmonic)(at(Dk, qe), ce)], [c(0, x, y) ~ 1.0 + x * y], dom(0.1),
        [t, x, y], [ce, qe], [Dk]; name = :k)
    s = solve(own(sk, 8; inputs = [qe => K]), ExplicitEuler(; dt = 1e-2, substeps = 4))
    push!(out, ("B DivK owned", s.u[end], substep_counts(s)[1]))
    sm = PDESystem([Shift(t, 1)(Ne) ~ (N(t, x + dx, y) + N(t, x - dx, y)) / 2], [N(0, x, y) ~ x], dom(3.0), [t, x, y],
        [Ne], [dx]; name = :m)
    s = solve(discretize(sm, LatticeDiscretization(Grid((8, 2)); T = Float64)), ExplicitMap())
    push!(out, ("B map owned", s.u[end], 0))
    return out
end
# F3 batch 4 (user OK 2026-10-25): one owned system under each implicit algorithm (soft set)
function implicit_cases()
    @parameters x y Dc = 0.3 k = 2.0
    @variables c(..)
    ce = c(t, x, y)
    sys = PDESystem([D(ce) ~ Dc * Δ(ce) - k * ce + x], [c(0, x, y) ~ x * y, c(t, 0, y) ~ 1.0],
        [t ∈ Interval(0.0, 0.4), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce], [Dc, k]; name = :i)
    prob = discretize(sys, LatticeDiscretization(Grid((8, 8)); T = Float64))
    out = Tuple{String, Any, Int}[]
    for alg in (LatticePDE.BackwardEuler(; dt = 0.1), LatticePDE.CrankNicolson(; dt = 0.1), LatticePDE.BDF2(; dt = 0.1),
                LatticePDE.QuasiSteady(; dt = 0.1))
        s = solve(prob, alg)
        push!(out, ("GiB " * string(nameof(typeof(alg))), s.u[end], substep_counts(s)[1]))
    end
    return out
end
end

const GD_B = ["B Robin owned", "B Robin ODE rhs", "B site diffusion owned", "B DivK owned", "B map owned"]


# F3 batch 4 (user OK 2026-10-25): the implicit algorithms in the soft set. Merks (A, 8², the
# hard set's operating point) under BackwardEuler, CrankNicolson and BDF2 (`lower = 0`): the
# fingerprints, `n` and the digests after 5 MCS; and one owned B system under each (`GdB`):
# the final state's digest and the substep count. Recorded at the guard commit (new records;
# no record moved). F3-12c (review r2 N3, the same OK): `QuasiSteady` in both (new records).
const GD_IMPLICIT = [("GiMerks BackwardEuler", BackwardEuler(lower = 0.0)), ("GiMerks CrankNicolson", CrankNicolson(lower = 0.0)),
    ("GiMerks BDF2", BDF2(lower = 0.0)), ("GiMerks QuasiSteady", QuasiSteady())]

function gd_implicit!(out)
    for (label, fs) in GD_IMPLICIT
        pre = "$label|Float64"
        sys = MerksVasculogenesis(; name = :merks, lattice = (8, 8))
        kw = (; field_solver = fs)
        prob = PottsProblem(sys, GD_MERKS_OP, (0, 5); seed = 7, kw...)
        gd_fingerprints!(out, pre, sys, prob, Float64, kw)
        integ = init(prob, SequentialCPM())
        out["$pre|n"] = string(gd_ns(integ))
        foreach(_ -> step!(integ), 1:5)
        st = current_state(integ)
        out["$pre|digest|σ"] = gd_digest(st.σ)
        for k in keys(st.site)
            out["$pre|digest|site.$k"] = gd_digest(getproperty(st.site, k))
        end
    end
    for (label, u, n) in GdB.implicit_cases()
        out["$label|Float64|digest|state"] = gd_digest(u)
        out["$label|Float64|n"] = string([n])
    end
    return out
end

# F3 batch 6 review r1 (add-only, design §6): the Jiang-like model of F3-18 (32³ lattice, five
# Coarse(4) fields, σ frozen) under the default BackwardEuler, CPU, Float64: the fingerprints,
# `n` and the digests of σ and the site arrays after 2 MCS, which are the same at `-t 1` and
# `-t 4` (the host's early Newton stop included; ~/lpwork/f3b6r-guard-t1.rec, -t4.rec). F3-23: the
# cell average `ocell` (`integral(o) / volume`) is recorded as well, since its sum is exact
# fixed point and so the same at every thread count (batch 6 left it out: float atomics).
isdefined(@__MODULE__, :JiangLike) || include(joinpath(@__DIR__, "fields_jiang_model.jl"))

function gd_jiang!(out)
    pre = "GjJiangLike BackwardEuler|Float64"
    σ, kinds = jiang_state(JG_DIMS)
    sys = JiangLike(; name = :j)
    kw = (; field_solver = BackwardEuler())
    prob = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 2); seed = 7, kw...)
    gd_fingerprints!(out, pre, sys, prob, Float64, kw)
    integ = init(prob, SequentialCPM())
    out["$pre|n"] = string(gd_ns(integ))
    foreach(_ -> step!(integ), 1:2)
    st = current_state(integ)
    out["$pre|digest|σ"] = gd_digest(st.σ)
    for k in keys(st.site)
        out["$pre|digest|site.$k"] = gd_digest(getproperty(st.site, k))
    end
    out["$pre|digest|cell.ocell"] = gd_digest(st.cell.ocell)
    return out
end

function gd_b!(out)
    for (label, u, n) in GdB.cases()
        out["$label|Float64|digest|state"] = gd_digest(u)
        n > 0 && (out["$label|Float64|n"] = string([n]))
    end
    return out
end


# ---------------------------------------------------------------------------------------
# The recorded values (lp/f1 bda31989, Julia 1.12.6, the PC). A listed move updates its entry
# here with the commit and the cause.

include(joinpath(@__DIR__, "fields_identity_records.jl"))


function gd_compare(got, want, keys)
    bad = String[]
    for k in keys
        g = get(got, k, "<missing>")
        g == get(want, k, "<missing>") ||
            push!(bad, "$k: recorded $(repr(get(want, k, "<missing>"))), now $(repr(g))")
    end
    return bad
end

gd_label(k) = first(split(k, '|'))

gd_pinned(k) = any(g -> g[1] == gd_label(k) && g[5], GD_HARD)


# F3-01 (R-F2b record 3; F3 design §3.11): the canonical fill order of every guard model's
# filled inputs (`kind__in` first, then the CPM reads sorted by their expression text, then
# `domain__in`). The sort key is `string(expr)`: a SymbolicUtils printing change that reorders
# the fills fails here before it moves a fingerprint silently. Recorded at F3-01; `nothing`: the
# model's `@equations` are refused.
include(joinpath(@__DIR__, "fields_identity_fill.jl"))


# ROCm (F2 batch 2): with `POTTS_GPU=rocm`, the hard set on the device (CheckerboardCPM) against
# the same run on the CPU: σ equal, every site array within a relative 1e-5 (Float32) or 1e-12
# (Float64) of its largest value
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))


# F2-08a: front end A steps through the shared group runtime (`lower_group`, `FieldGroup`,
# `GroupRuntime`). Merks, Merks2006 and Merks2008 (its `mcs ≥ t_relax` gate crossed at MCS 7)
# over 20 MCS on 32² lattices are bitwise equal to the parent a73ded80: σ and every site array,
# at Float64 and Float32, on the CPU (SequentialCPM) and on ROCm (CheckerboardCPM). The clamp
# at the step start (F2-08b; static masks) and the clock (F2-08c; `mcs` reads the same
# integer) keep these values.
function gd_op2006_32()
    σ = zeros(Int32, 32, 32); σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
    σ[6:11, 6:11] .= 2; σ[18:23, 16:21] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end

function gd_op2008_32()
    σ = zeros(Int32, 32, 32); σ[1:2, :] .= 1; σ[(end - 1):end, :] .= 1; σ[:, 1:2] .= 1; σ[:, (end - 1):end] .= 1
    σ[6:11, 6:11] .= 2; σ[18:23, 16:21] .= 3
    return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
end

const GD_M20 = [
    ("Merks", () -> MerksVasculogenesis(; name = :m, lattice = (32, 32)),
        () -> [ownership => (s = zeros(Int32, 32, 32); s[10:16, 10:16] .= 1; s[20:25, 18:24] .= 2; s),
               kind => [:endothelial, :endothelial]], (; field_solver = ExplicitEuler(substeps = 15, lower = 0.0))),
    ("Merks2006", () -> Merks2006(; name = :m, lattice = (32, 32)), gd_op2006_32, (; field_solver = ExplicitEuler(substeps = 15))),
    ("Merks2008", () -> Merks2008(; name = :m, lattice = (32, 32)), () -> [gd_op2008_32(); :t_relax => 7.0],
        (; field_solver = ExplicitEuler(substeps = 15)))]

const GD_M20_CPU = [
    "Merks|Float64|σ f58f6b1732c69db4 c de8341b36f6d6366 c__next de8341b36f6d6366 kind__in 514f7f4c15f8cb24",
    "Merks|Float32|σ f58f6b1732c69db4 c 7e3ae9191a6939b6 c__next 7e3ae9191a6939b6 kind__in 514f7f4c15f8cb24",
    "Merks2006|Float64|σ 7cda8d980d95b467 c 3a43587e58aa375a c__next 3a43587e58aa375a kind__in 3bf7cef411929a54 c__mask 006d1e48a8ec6841",
    "Merks2006|Float32|σ 7cda8d980d95b467 c a28e9c950fa7d25e c__next a28e9c950fa7d25e kind__in 3bf7cef411929a54 c__mask 006d1e48a8ec6841",
    "Merks2008|Float64|σ 039c9a8fab0e6fe6 c e5811b68a7ed436f c__next e5811b68a7ed436f kind__in 8916a0a7186b1c34 c__mask ca3b9f0899d80415",
    "Merks2008|Float32|σ 039c9a8fab0e6fe6 c ec274dd29b2c30bc c__next ec274dd29b2c30bc kind__in 8916a0a7186b1c34 c__mask ca3b9f0899d80415",
]

# (ROCm at Float32 only: the device suite's no-`double` scan; the Float64 device digests at
# a73ded80 were cbc7f7cf…/1ee0a004…, 73a96910…/1df109d0…, 9908b3e8…/626bfabe…, also unchanged)
const GD_M20_ROCM = [
    "Merks|Float32|σ cbc7f7cfb7cabb55 c 1b789dc265fc9cb4 c__next 1b789dc265fc9cb4 kind__in 8dff107e067c7db5",
    "Merks2006|Float32|σ 73a96910f6820396 c ee7bf6f111df0646 c__next ee7bf6f111df0646 kind__in 1de0fc3fda4fb414 c__mask 006d1e48a8ec6841",
    "Merks2008|Float32|σ 9908b3e850d4d4e4 c f519632ad6f8ad6f c__next f519632ad6f8ad6f kind__in 096d8a98c6289d35 c__mask ca3b9f0899d80415",
]

gd_m20_text(label, T, u) = string(label, "|", T, "|σ ", gd_digest(u.σ), " ",
    join(("$k " * gd_digest(getproperty(u.site, k)) for k in keys(u.site)), " "))

function gd_m20(; backend = nothing, types = (Float64, Float32))
    out = String[]
    for (label, build, op, kw) in GD_M20, T in types
        prob = PottsProblem(build(), op(), (0, 20); T, seed = 11, kw...)
        u = backend === nothing ? solve(prob, SequentialCPM(); save_start = false).u[end] :
            solve(prob, CheckerboardCPM(); backend, save_start = false).u[end]
        push!(out, gd_m20_text(label, T, u))
    end
    return out
end


# F2-08a: a warm MCS of Merks at 500² (15 substeps, the field read by the CPM) allocates
# nothing on the CPU (measured inside a function)
gd_warm(integ) = (step!(integ); step!(integ); @allocated step!(integ))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
