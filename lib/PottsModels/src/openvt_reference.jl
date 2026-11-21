"""
    OpenVTReferenceMonolayer(; name, lattice = (1400, 1400), A₀ = 50.0, λ = 2.0, T = 20.0,
        α = 50/775, μ_X = 2.0, σ_X = 0.4, β = 0.0, γ = 0.0, J = [0.0 10.0; 10.0 20.0])

Build the OpenVT growing monolayer with contact inhibition as the benchmark manuscript
specifies it (Table S1 and §2.1; `docs/design/research/model-specs/15_openvt_monolayer.md`
§2): one disc-shaped cell grows into a colony on a closed lattice.

The lattice must be large enough that the colony stays away from the edge; guard the run
with [`edge_guard`](@ref PottsModels.edge_guard).

- **Energies.** An area constraint `λ (volume − A_star)²`, adhesion
  `J[kind, neighbor_kind]` on `Moore(1)` with `J_cm = 10`, `J_cc = 20` (no net adhesion),
  and Metropolis at `T`.
- **Growth.** Once per MCS after the sweep, `A_star += α` if and only if
  `volume / A_star ≥ β` (type 1) and `f ≥ γ` (type 2). `f` is the free-surface fraction:
  the cell's medium contact pairs over its unlike contact pairs on `Moore(1)` (the
  manuscript's Fig 4, TST's "method 3"), read with the contact fold
  `count(neighbor_kind == medium for _ in contacts) / count(true for _ in contacts)`.
- **Division.** At `volume ≥ X · A₀`, along a random plane. Both daughters take half the
  mother's `A_star` and draw their own `X ~ N(μ_X, σ_X)`, redrawn while `X ≤ 0`
  (`randn(μ_X, σ_X; lower_bound = 0)`); the first cell draws its `X` the same way before
  the first division check. `σ_X = 0` is the deterministic mode `X ≡ μ_X`.

The defaults are Table S1: `α = 50/775` sites per MCS gives a cycle of `5T = A₀/α = 775`
MCS, and `β = γ = 0` is uninhibited. The kinds are `medium` and `cell`, and the cell
variables are `A_star`, `X` and `f`. Seed with [`openvt_reference_state`](@ref). Stop at a
cell count with [`stop_at_cells`](@ref PottsModels.stop_at_cells), and record the rows of
the benchmark's output with [`openvt_snapshot`](@ref PottsModels.openvt_snapshot) and
[`openvt_frame`](@ref PottsModels.openvt_frame). The 2024 Artistoo parameter set is the
variant [`OpenVTGrowingMonolayer`](@ref).

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (1400, 1400)`: the lattice size (structural).
- `A₀ = 50.0`: the initial target area `A*(0)`, in sites.
- `λ = 2.0`: the area strength.
- `T = 20.0`: the Metropolis temperature.
- `α = 50/775`: the growth of the target area per MCS, in sites.
- `μ_X = 2.0`, `σ_X = 0.4`: the mean and standard deviation of the division size `X`, in
  units of `A₀`.
- `β = 0.0`: the type-1 (area) inhibition threshold.
- `γ = 0.0`: the type-2 (free-surface) inhibition threshold.
- `J = [0.0 10.0; 10.0 20.0]`: the contact energies over (medium, cell).

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> OpenVTReferenceMonolayer(; name = :colony, lattice = (100, 100), β = 0.9) isa
           PottsSystem
true
```

See also [`openvt_reference_state`](@ref),
[`openvt_snapshot`](@ref PottsModels.openvt_snapshot),
[`stop_at_cells`](@ref PottsModels.stop_at_cells).
"""
@potts_model OpenVTReferenceMonolayer begin
    @structural_parameters begin
        lattice = (1400, 1400)
    end
    @kinds medium cell
    @parameters begin
        A₀ = 50.0
        λ = 2.0
        T = 20.0
        α = 50 / 775
        μ_X = 2.0
        σ_X = 0.4
        β = 0.0
        γ = 0.0
        J[kind, kind] = [0.0 10.0; 10.0 20.0]
    end
    @variables begin
        A_star(cell) = A₀
        X(cell) = 0.0                  # 0: not drawn yet (drawn at the first MCS)
        f(cell) = 1.0
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(cell) => λ * (volume - A_star)^2
        contacts => J[kind, neighbor_kind]
    end
    @before_mcs X ~ ifelse(Pre(X) > 0, Pre(X), randn(μ_X, σ_X; lower_bound = 0.0))
    @after_mcs begin
        f ~ ifelse(
            count(true for _ in contacts) > 0,
            count(neighbor_kind == medium for _ in contacts) /
                count(true for _ in contacts),
            1.0
        )
        A_star ~
            ifelse((volume / Pre(A_star) >= β) && (f >= γ), Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(cell) when = volume >= X * A₀, along = RandomPlane(), A_star => Split(),
        X => randn(μ_X, σ_X; lower_bound = 0.0)
    @sweep Metropolis(; temperature = T)
end

"""
    openvt_reference_state(; lattice = (1400, 1400), area0 = 50) -> Vector{Pair}

Return the initial state of [`OpenVTReferenceMonolayer`](@ref): one disc-shaped cell at the
lattice center.

The cell owns the sites whose centers lie within `R = √(area0/π)` of the center point
`(size .+ 1) ./ 2` (Morpheus' `Sphere radius = R`). For `area0 = 50` that is 52 sites on an
even lattice and 45 on an odd one.

# Keywords
- `lattice = (1400, 1400)`: the lattice size.
- `area0 = 50`: the target area, the model's `A₀`.

# Returns
- `Vector{Pair}`: the operating point `[ownership => σ, kind => [:cell]]`, with
  `σ::Matrix{Int32}` and the cell numbered 1.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> even = openvt_reference_state(; lattice = (20, 20))[1].second;

julia> odd = openvt_reference_state(; lattice = (21, 21))[1].second;

julia> count(==(1), even), count(==(1), odd)
(52, 45)
```

See also [`OpenVTReferenceMonolayer`](@ref).
"""
function openvt_reference_state(; lattice = (1400, 1400), area0 = 50)
    σ = zeros(Int32, lattice)
    R = sqrt(area0 / π)
    c = (Tuple(lattice) .+ 1) ./ 2
    for I in CartesianIndices(σ)
        sqrt(sum(abs2, Tuple(I) .- c)) <= R && (σ[I] = 1)
    end
    return [ownership => σ, kind => [:cell]]
end

"""
    PottsModels.openvt_snapshot(u; area0 = 50.0, center = (size(u.ownership) .+ 1) ./ 2)
        -> (; x, y, r, f, a)

Return the per-cell rows of the benchmark's snapshot output (the O2 table of
`docs/design/research/model-specs/15_openvt_monolayer.md` §3.1) for a saved state `u` of
[`OpenVTReferenceMonolayer`](@ref).

There is one row per live cell (volume > 0), in cell-number order. Lengths are in units of
`R = √(area0/π)`.

- `x`, `y`: the centroid (mean site index; the lattice is closed) minus `center`, over `R`.
- `r = √(A_star/π) / R`: the radius of the cell's reference area.
- `f`: the free-surface fraction, medium pairs over unlike pairs on `Moore(1)`, from `σ`.
- `a = volume / A_star`.

# Arguments
- `u`: a saved state with `u.ownership` (2D), `u.cell.volume` and `u.cell.A_star`, on the
  CPU or a GPU.

# Keywords
- `area0 = 50.0`: the model's `A₀`, which sets `R`.
- `center = (size(u.ownership) .+ 1) ./ 2`: the origin of `x` and `y`.

Throws an `ArgumentError` when the state is not 2D.

# Returns
- `NamedTuple`: `(; x, y, r, f, a)`, each a `Vector{Float64}`.

# Examples
```julia
using PottsModels, Potts
o = PottsModels.openvt_snapshot(sol.u[end])
o.f    # the free-surface fraction of each live cell
```

See also [`openvt_frame`](@ref PottsModels.openvt_frame), [`write_openvt`](@ref).
"""
function openvt_snapshot(u; area0 = 50.0, center = (size(u.ownership) .+ 1) ./ 2)
    σ = Array(u.ownership)
    ndims(σ) == 2 ||
        throw(ArgumentError("openvt_snapshot: a 2D state is required, got $(ndims(σ))D"))
    volume = Array(u.cell.volume)
    A = Array(u.cell.A_star)
    n = length(volume)
    sx = zeros(n)
    sy = zeros(n)
    med = zeros(Int, n)
    unlike = zeros(Int, n)
    nx, ny = size(σ)
    for j in 1:ny, i in 1:nx
        c = σ[i, j]
        c == 0 && continue
        sx[c] += i
        sy[c] += j
        for dj in -1:1, di in -1:1
            (di == 0 && dj == 0) && continue
            (1 <= i + di <= nx && 1 <= j + dj <= ny) || continue
            q = σ[i + di, j + dj]
            q == c && continue
            unlike[c] += 1
            q == 0 && (med[c] += 1)
        end
    end
    live = findall(>(0), volume)
    R = sqrt(area0 / π)
    x = [(sx[c] / volume[c] - center[1]) / R for c in live]
    y = [(sy[c] / volume[c] - center[2]) / R for c in live]
    r = [sqrt(Float64(A[c]) / π) / R for c in live]
    f = [med[c] / unlike[c] for c in live]
    a = [volume[c] / Float64(A[c]) for c in live]
    return (; x, y, r, f, a)
end

"""
    PottsModels.openvt_frame(u; beta, gamma, area0 = 50.0,
        center = (size(u.ownership) .+ 1) ./ 2) -> (; x, y, i, n)

Return the per-cell rows of the benchmark's time-series output (the O1 table of
`docs/design/research/model-specs/15_openvt_monolayer.md` §3.1) for a saved state `u` of
[`OpenVTReferenceMonolayer`](@ref), ready for `write_openvt(dest, :O1, frame)`.

There is one row per live cell (volume > 0), in cell-number order.

- `x`, `y`: the centroid in units of `R = √(area0/π)` from `center`, exactly as
  [`openvt_snapshot`](@ref PottsModels.openvt_snapshot) gives them.
- `i`: the inhibition code [`openvt_inhibition_code`](@ref) of the snapshot's `a` and `f`
  at the thresholds `beta` and `gamma`: 0 growing, 1, 2 or 3.
- `n`: the number of distinct other cells (medium and the cell itself excluded) among the
  `Moore(1)` neighbors of the cell's sites
  (`docs/design/research/model-specs/15_openvt_monolayer.md` §2.4), on the closed lattice
  (no wrap).

The code `i` is computed on the saved state, after that MCS's growth increment: `a` is
`volume / A_star` with the grown `A_star`, while the model decided growth on the pre-growth
`volume / Pre(A_star)`. The two can differ only for a cell whose target area is within one
increment `α` of the β threshold.

`σ` and the volumes are copied to the host twice, once by the snapshot and once for the
neighbor count.

# Arguments
- `u`: a saved state with `u.ownership` (2D), `u.cell.volume` and `u.cell.A_star`, on the
  CPU or a GPU.

# Keywords
- `beta::Real`: the type-1 (area) threshold, the model's `β`.
- `gamma::Real`: the type-2 (free-surface) threshold, the model's `γ`.
- `area0 = 50.0`: the model's `A₀`, which sets `R`.
- `center = (size(u.ownership) .+ 1) ./ 2`: the origin of `x` and `y`.

# Returns
- `NamedTuple`: `(; x, y, i, n)`, with `x` and `y` of type `Vector{Float64}` and `i` and
  `n` of type `Vector{Int}`.

# Examples
```julia
using PottsModels, Potts
frame = PottsModels.openvt_frame(sol.u[end]; beta = 0.9, gamma = 0.0)
write_openvt("frame.txt", :O1, frame)
```

See also [`openvt_snapshot`](@ref PottsModels.openvt_snapshot), [`write_openvt`](@ref).
"""
function openvt_frame(
        u; beta::Real, gamma::Real, area0 = 50.0, center = (size(u.ownership) .+ 1) ./ 2
    )
    o = openvt_snapshot(u; area0, center)
    σ = Array(u.ownership)
    live = findall(>(0), Array(u.cell.volume))
    i = [openvt_inhibition_code(o.a[j], o.f[j]; beta, gamma) for j in eachindex(o.a)]
    deg = _moore_degrees(σ, length(u.cell.volume))
    return (; o.x, o.y, i, n = deg[live])
end

# the number of distinct other nonzero ids Moore(1)-adjacent to each id 1:ncell of σ (closed
# lattice). Adjacency is symmetric, so the four forward offsets visit every unlike adjacent
# pair once per direction; each pair is stored once (packed lo << 32 | hi), deduplicated,
# and counted at both ends.
function _moore_degrees(σ::AbstractMatrix{<:Integer}, ncell::Integer)
    nx, ny = size(σ)
    pairs = UInt64[]
    for j in 1:ny, i in 1:nx
        c = σ[i, j]
        c == 0 && continue
        for (di, dj) in ((1, 0), (-1, 1), (0, 1), (1, 1))
            (1 <= i + di <= nx && j + dj <= ny) || continue
            q = σ[i + di, j + dj]
            (q == 0 || q == c) && continue
            lo, hi = minmax(UInt64(c), UInt64(q))
            push!(pairs, (lo << 32) | hi)
        end
    end
    unique!(sort!(pairs))
    deg = zeros(Int, ncell)
    for p in pairs
        deg[p >> 32] += 1
        deg[p & 0xffffffff] += 1
    end
    return deg
end

# ---------------------------------------------------------------------------------------
# Run guards (callbacks checked at every MCS boundary, after the lifecycle)

"""
    PottsModels.stop_at_cells(n; every = 1) -> DiscreteCallback

Return a callback that ends a run when the colony reaches `n` cells.

The run ends with `ReturnCode.Terminated` at the end of the first checked MCS whose number
of live cells (volume > 0, after the lifecycle) is at least `n`; the state of that MCS is
the last one saved. The check runs every `every` MCS. On a GPU, each check reads one count
over the cell volumes back to the host.

# Arguments
- `n::Integer`: the number of live cells that ends the run.

# Keywords
- `every::Integer = 1`: the check interval, in MCS. Throws an `ArgumentError` when below 1.

# Returns
- `DiscreteCallback`: pass it as `solve(prob, alg; callback)`.

# Examples
```jldoctest
julia> using PottsModels

julia> PottsModels.stop_at_cells(10_000; every = 10) isa PottsModels.DiscreteCallback
true
```

See also [`edge_guard`](@ref PottsModels.edge_guard).
"""
function stop_at_cells(n::Integer; every::Integer = 1)
    every >= 1 || throw(ArgumentError("stop_at_cells: `every` must be ≥ 1, got $every"))
    condition(u, t, integ) = t % every == 0 && count(>(0), u.cell.volume) >= n
    # one save of the last MCS
    return DiscreteCallback(condition, terminate!; save_positions = (false, false))
end

"""
    PottsModels.edge_guard(margin; terminate = false, every = 1) -> DiscreteCallback

Return a callback that guards a run on a finite lattice that stands for an unbounded
domain.

After every checked MCS, if a cell comes within `margin` sites of the lattice edge
([`Analysis.near_edge`](@ref PottsModels.Analysis.near_edge)), the callback throws a
`DomainError` (the default) or, with `terminate = true`, stops the run with
`ReturnCode.Failure` (the state of that MCS is the last one saved). The check runs every
`every` MCS. On a GPU, each check reads one masked reduction over `σ` back to the host.

# Arguments
- `margin::Integer`: the distance from the edge, in sites.

# Keywords
- `terminate::Bool = false`: stop the run instead of throwing.
- `every::Integer = 1`: the check interval, in MCS. Throws an `ArgumentError` when below 1.

# Returns
- `DiscreteCallback`: pass it as `solve(prob, alg; callback)`.

# Examples
```jldoctest
julia> using PottsModels

julia> PottsModels.edge_guard(20; terminate = true) isa PottsModels.DiscreteCallback
true
```

See also [`stop_at_cells`](@ref PottsModels.stop_at_cells).
"""
function edge_guard(margin::Integer; terminate::Bool = false, every::Integer = 1)
    every >= 1 || throw(ArgumentError("edge_guard: `every` must be ≥ 1, got $every"))
    g = _EdgeGuard(Int(margin), Ref{Any}(nothing))
    condition(u, t, integ) = t % every == 0 && g(u.ownership)
    function affect!(integ)
        if terminate
            return terminate!(integ, ReturnCode.Failure)
        else
            throw(
                DomainError(
                    margin, "edge_guard: a cell came within $margin sites of the lattice " *
                        "edge at MCS $(integ.t); use a larger lattice"
                )
            )
        end
    end
    # one save of the last MCS
    return DiscreteCallback(condition, affect!; save_positions = (false, false))
end

# `near_edge` as one masked reduction: the frame of `margin` sites, built once per array
# type and size on its backend (the cache key is the state array's type and size, so a check
# allocates nothing but the reduction's result)
struct _EdgeGuard
    margin::Int
    # (array type, size, frame mask) once built; read only on the host
    frame::Ref{Any}
end
function (g::_EdgeGuard)(σ::AbstractArray)
    σ isa Array && return Analysis.near_edge(σ, g.margin)
    c = g.frame[]
    if !(c isa Tuple && c[1] === typeof(σ) && c[2] == size(σ))
        host = falses(size(σ))
        for I in CartesianIndices(host)
            host[I] = any(
                d -> I[d] <= g.margin || I[d] >= size(σ, d) - g.margin + 1,
                1:ndims(σ)
            )
        end
        m = similar(σ, Bool)
        copyto!(m, Array(host))
        c = (typeof(σ), size(σ), m)
        g.frame[] = c
    end
    return mapreduce((s, f) -> f & (s != 0), |, σ, c[3]; init = false)
end
