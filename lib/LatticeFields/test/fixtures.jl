# Programs shared by the tests: FV-style explicit diffusion steps built through the builder,
# and their hand-written loops. The hand loops follow the canonical operand order the IR
# documents (loads by offset, then products, then boundary selects by offset), with Float32
# literals rounded once from Float64 and hoisted coefficients computed in Float64 on the host.

using Random

const OFFS2 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const OFFS3 = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))

"""
2D 5-point step `u ← u + (dt·D/h²)(Σ nb − 4u)`, periodic on both axes. P = (dt, D, h).
"""
function diffusion2(dims = (7, 5))
    pb = ProgramBuilder(Grid(dims); periodic = (true, true), nparams = 3)
    u = field!(pb, "u"; buffers = 2)
    kb = kernel(pb)
    c = load(kb, u)
    nb = sum(load(kb, u; offset = o) for o in OFFS2)
    store(kb, u, c + param(kb, 1) * param(kb, 2) / param(kb, 3)^2 * (nb - 4c))
    add!(pb, kb, "diffuse")
    return pb
end

"""
3D 7-point step: x periodic, y no flux, z Dirichlet with g = P4 (low) and P5 (high).
"""
function diffusion3(dims = (6, 5, 4); alpha = 1.0)
    pb = ProgramBuilder(Grid(dims); periodic = (true, false, false), nparams = 5)
    u = field!(pb, "u"; buffers = 2)
    for s in (-1, 1)
        rule!(pb, FaceRule(u, 2, s, Coef(0), Coef(1), Coef(0)))
        rule!(pb, FaceRule(u, 3, s, Coef(alpha), Coef(0), Coef(1.0, s < 0 ? 4 : 5)))
    end
    kb = kernel(pb)
    c = load(kb, u)
    nb = sum(load(kb, u; offset = o) for o in OFFS3)
    store(kb, u, c + param(kb, 1) * param(kb, 2) / param(kb, 3)^2 * (nb - 6c))
    add!(pb, kb, "diffuse")
    return pb
end

coefk(P) = Float32((P[1] * P[2]) / (P[3] * P[3]))

function hand2!(out, u, P)
    nx, ny = size(u)
    k, m4 = coefk(P), Float32(-4.0)
    for j in 1:ny, i in 1:nx

        c = u[i, j]
        w, e = u[mod1(i - 1, nx), j], u[mod1(i + 1, nx), j]
        s, n = u[i, mod1(j - 1, ny)], u[i, mod1(j + 1, ny)]
        out[i, j] = c + ((((w + s) + n) + e) + m4 * c) * k
    end
    return out
end

function hand3!(out, u, P)
    nx, ny, nz = size(u)
    k, m6 = coefk(P), Float32(-6.0)
    glo, ghi = Float32(2.0 * P[4]), Float32(2.0 * P[5])
    for l in 1:nz, j in 1:ny, i in 1:nx
        c = u[i, j, l]
        w, e = u[mod1(i - 1, nx), j, l], u[mod1(i + 1, nx), j, l]
        ym = j > 1 ? u[i, j - 1, l] : c
        yp = j < ny ? u[i, j + 1, l] : c
        zm = l > 1 ? u[i, j, l - 1] : (-c) + glo
        zp = l < nz ? u[i, j, l + 1] : (-c) + ghi
        out[i, j, l] = c + ((((((w + e) + m6 * c) + ym) + zm) + zp) + yp) * k
    end
    return out
end

"""
A naive loop in a different summation order (for tolerance checks).
"""
function naive3!(out, u, P)
    nx, ny, nz = size(u)
    k = P[1] * P[2] / P[3]^2
    for l in 1:nz, j in 1:ny, i in 1:nx
        c = Float64(u[i, j, l])
        nb = u[mod1(i + 1, nx), j, l] + u[mod1(i - 1, nx), j, l] +
             (j < ny ? u[i, j + 1, l] : c) + (j > 1 ? u[i, j - 1, l] : c) +
             (l < nz ? u[i, j, l + 1] : 2P[5] - c) + (l > 1 ? u[i, j, l - 1] : 2P[4] - c)
        out[i, j, l] = c + k * (nb - 6c)
    end
    return out
end

"""
Run `steps` steps of a single-field program on the host; returns the final `u`.
"""
function run_field(s, sp, u0, P; key = "u", steps = 1)
    st = HostStore(s)
    copyto!(current(st, s, key), u0)
    for _ in 1:steps
        run_step!(s, sp, st, P)
    end
    return reshape(copy(current(st, s, key)), size(u0))
end
