# Definitions of the Fortuna test files (fortuna_model_tests.jl, fortuna_field_tests.jl):
# the copy-blocked twin of `FortunaMigration`, cached systems, hand states and Base-Julia
# oracles that read σ alone.
using Potts, PottsModels
using Potts: CorePotts

const KINDS = (:medium, :substrate, :lid, :cytoplasm, :lamellipodium, :nucleus)
const SUBSTRATE, LID, CYTOPLASM, LAMELLIPODIUM, NUCLEUS = 1, 2, 3, 4, 5   # kind codes
const ONE_STEP = ExplicitEuler(substeps = 1)
ball_volume(R) = 4 / 3 * π * R^3

# The copy-blocked twin: the constraint rejects every copy, so only the field step and the
# protrusion pass change the state.
@potts_model FortunaBlocked begin
    @structural_parameters begin
        lattice = (80, 80, 21)
    end
    @extend base = PottsModels.FortunaMigration(; lattice)
    @parameters mobile = 0.0
    @constraint mobile > 0.5
end

# one system per (model, lattice): one compilation each
const SYSTEMS = Dict{Any, Any}()
model_sys(lattice) = get!(
    () -> FortunaMigration(; name = :fortuna, lattice), SYSTEMS, (:model, lattice)
)
twin_sys(lattice) = get!(
    () -> FortunaBlocked(; name = :twin, lattice), SYSTEMS, (:twin, lattice)
)
function fortuna_problem(sys, op, R, φ_l; tspan = (0, 1), seed = 1, p = (), kw...)
    full = [op; :R => Float64(R); :φ_l => Float64(φ_l); collect(p)]
    return PottsProblem(sys, full, tspan; seed, field_solver = ONE_STEP, kw...)
end
entry(op, key) = op[findfirst(q -> isequal(q.first, key), op)].second

# the alive cells of kind code `k`
function alive(u, k)
    v, kd = volumes(u), cell_kinds(u)
    return [c for c in eachindex(v) if v[c] > 0 && kd[c] == k]
end

# A hand state from the shipped R = 10, φ_l = 0.05 start: a lamellipodium (cell 5) made of
# the cytoplasm sites at z = 2 with x ≥ 44 and at z = 3 with x ≥ 46, so it has sites that
# touch the substrate (z = 2) and sites that do not (z = 3). `shift` moves the nucleus in x.
function hand_op(op; shift = 0)
    σ = copy(entry(op, ownership))
    if shift != 0
        box = findall(==(2), σ)
        σ[box] .= 1
        σ[[CartesianIndex(I[1] + shift, I[2], I[3]) for I in box]] .= 2
    end
    for I in CartesianIndices(σ)
        σ[I] == 1 && ((I[3] == 2 && I[1] >= 44) || (I[3] == 3 && I[1] >= 46)) &&
            (σ[I] = 5)
    end
    return [
        ownership => σ,
        kind => [:cytoplasm, :nucleus, :substrate, :lid, :lamellipodium],
        cluster => [1, 1, 3, 4, 1],
    ]
end

# The face neighbors of site `x` on a lattice of size `L`: x and y wrap where `periodic`
# says so, a missing neighbor past a closed face is left out (zero flux).
function face_neighbors(x::NTuple{3, Int}, L, periodic)
    out = NTuple{3, Int}[]
    for d in 1:3, s in (-1, 1)
        y = ntuple(j -> j == d ? x[j] + s : x[j], 3)
        if !(1 <= y[d] <= L[d])
            periodic[d] || continue
            y = ntuple(j -> j == d ? mod1(y[j], L[j]) : y[j], 3)
        end
        push!(out, y)
    end
    return out
end

# Eq 6's source: 1 on lamellipodium sites with a substrate face neighbor; with
# `substrate = false`, 1 on every lamellipodium site (a negative control)
function source_mask(σ, kinds; substrate = true, periodic = (true, true, false))
    S = zeros(size(σ))
    kd(c) = c == 0 ? 0 : kinds[c]
    for I in CartesianIndices(σ)
        kd(σ[I]) == LAMELLIPODIUM || continue
        on = !substrate ||
            any(y -> kd(σ[y...]) == SUBSTRATE, face_neighbors(Tuple(I), size(σ), periodic))
        S[I] = on
    end
    return S
end

# One explicit Euler step of Eq 6 on the whole lattice: the 7-point Laplacian with x, y
# wrapping where `periodic` says so and zero flux elsewhere. `order`: `:unsplit` adds the
# source in the same update, `:split` diffuses and decays first and then adds the source
# (CompuCell3D's order), `:secrete_first` adds the source first and then diffuses and
# decays the result (a negative control).
function euler_step(
        F, S; D, k, ks, dt = 1.0, periodic = (true, true, false),
        order = :unsplit
    )
    order === :secrete_first && (F = F .+ dt * ks .* S)
    G = similar(F)
    for I in CartesianIndices(F)
        x = Tuple(I)
        lap = sum(y -> F[y...] - F[I], face_neighbors(x, size(F), periodic); init = 0.0)
        G[I] = F[I] + dt * (D * lap - k * F[I])
        order === :unsplit && (G[I] += dt * ks * S[I])
    end
    order === :split && (G .+= dt * ks .* S)
    return G
end

# circular-mean centroid on periodic x, y, wrapped into [1, L + 1); plain mean on z
function oracle_centroid(σ, ids)
    L = size(σ)
    idx = [Tuple(I) for I in CartesianIndices(σ) if σ[I] in ids]
    return ntuple(3) do d
        xs = Float64[i[d] for i in idx]
        d == 3 && return sum(xs) / length(xs)
        θ = atan(sum(sinpi.(2 .* (xs .- 1) ./ L[d])), sum(cospi.(2 .* (xs .- 1) ./ L[d])))
        m = 1 + mod(θ * L[d] / 2π, L[d])
        ys = [x + L[d] * round((m - x) / L[d]) for x in xs]
        return 1 + mod(sum(ys) / length(ys) - 1, L[d])
    end
end
minimum_image_distance(d, L) = d - L * round(d / L)
# Π_CN−N: V_C (r_C − r_N)/(V_C + V_N), x and y, minimum image
function oracle_polarization(σ, cyto, nuc)
    rc, rn = oracle_centroid(σ, (cyto,)), oracle_centroid(σ, (nuc,))
    vc, vn = count(==(cyto), σ), count(==(nuc), σ)
    w = vc / (vc + vn)
    return ntuple(d -> w * minimum_image_distance(rc[d] - rn[d], size(σ, d)), 2)
end
# lamellipodium sites with a face neighbor in the cytoplasm
function oracle_lam_cyto(σ, lam, cyto)
    return count(
        I -> σ[I] == lam &&
            any(
            y -> σ[y...] == cyto,
            face_neighbors(Tuple(I), size(σ), (true, true, false))
        ),
        CartesianIndices(σ)
    )
end

# The protrusion pass of the step t → t + 1 by hand: the cytoplasm sites at z = 2 (the
# only ones with a substrate face neighbor) whose draw of the stream
# "Potts.convert.protrusion" at (t, site) is below c (1 − V₃/(φ_l V)), V₃ at the start.
protrusion_draw(seed, t, s) = CorePotts.uniform(
    Float64,
    CorePotts.draw(
        CorePotts.RNGKey(seed), t, s,
        CorePotts.stream_id("Potts.convert.protrusion")
    )[1]
)
function oracle_pass(u, t, seed; c, φ_l, R)
    σ = Array(ownership(u))
    lam = alive(u, LAMELLIPODIUM)
    V3 = isempty(lam) ? 0 : volumes(u)[only(lam)]
    p = c * (1 - V3 / (φ_l * ball_volume(R)))
    cyto = only(alive(u, CYTOPLASM))
    cand = [s for s in eachindex(σ) if σ[s] == cyto && CartesianIndices(σ)[s][3] == 2]
    return [s for s in cand if protrusion_draw(seed, t, s) < p], cand, p
end

# Every face-neighbor copy between different cells, neither of them a plane
function boundary_proposals(prob, u)
    lat = prob.lattice
    vn = CorePotts.relation(VonNeumann(1), lat)
    σ = Array(ownership(u))
    kd = cell_kinds(u)
    plane(c) = c != 0 && kd[c] in (SUBSTRATE, LID)
    out = CorePotts.Proposal{3}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for o in vn.offsets
            ins, y = CorePotts.shift(lat, x, o)
            ins || continue
            s = CorePotts.linear_index(lat, y)
            (σ[t] == σ[s] || plane(σ[t]) || plane(σ[s])) && continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end
# the drive part of ΔH: ΔH with drives minus the authored energy change
function drive(prob, u, prop)
    ctx = (; lattice = prob.lattice, contact = prob.contact, prob.relations...)
    return prob.f.delta_H(u, prob.p, prop, ctx) - energy_change(prob, u, prop)
end
