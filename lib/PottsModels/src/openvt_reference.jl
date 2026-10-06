"""
    OpenVTReferenceMonolayer(; name, lattice = (1400, 1400), …)

The OpenVT growing monolayer with contact inhibition as the benchmark manuscript specifies it
(Table S1 and §2.1; spec `15_openvt_monolayer.md` §2). One disc-shaped cell grows into a
colony on a closed lattice, large enough that the colony stays away from the edge (guard it
with [`edge_guard`](@ref PottsModels.edge_guard)):

- area constraint `λ (volume − A_star)²`, adhesion `J[kind, kind′]` on `Moore(1)` with
  `J_cm = 10`, `J_cc = 20` (no net adhesion), Metropolis at `T`;
- growth once per MCS after the sweep: `A_star += α` iff `volume / A_star ≥ β` (type 1)
  and `f ≥ γ` (type 2), where `f` is the free-surface fraction, the cell's medium contact
  pairs over its unlike contact pairs on `Moore(1)` (M's Fig 4, TST's "method 3"), read
  with the contact fold `count(kind′ == medium for _ in contacts) / count(true for _ in contacts)`;
- division at `volume ≥ X · A₀` along a random plane. Both daughters take half the
  mother's `A_star` and draw their own `X ~ N(μ_X, σ_X)`, redrawn while `X ≤ 0`
  (`randn(μ_X, σ_X; lower = 0)`); the first cell draws its `X` the same way before the first
  division check. `σ_X = 0` is the deterministic mode `X ≡ μ_X`.

Parameters (Table S1): `A₀ = 50` (A\\*(0), px), `λ = 2`, `T = 20`, `α = 50/775` px/MCS (a
cycle of `5T = A₀/α = 775` MCS), `μ_X = 2`, `σ_X = 0.4`, `β = γ = 0` (uninhibited) and
`J = [0 10; 10 20]`. Cell variables: `A_star`, `X` and `f`.

Seed with [`openvt_reference_state`](@ref). Stop at a cell count with
[`stop_at_cells`](@ref PottsModels.stop_at_cells); record the O2 rows with
[`openvt_snapshot`](@ref PottsModels.openvt_snapshot). The 2024 Artistoo parameter set is
the variant [`OpenVTGrowingMonolayer`](@ref).
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
        contacts => J[kind, kind′]
    end
    @before_mcs X ~ ifelse(Pre(X) > 0, Pre(X), randn(μ_X, σ_X; lower = 0.0))
    @after_mcs begin
        f ~ ifelse(count(true for _ in contacts) > 0,
            count(kind′ == medium for _ in contacts) / count(true for _ in contacts), 1.0)
        A_star ~ ifelse((volume / Pre(A_star) >= β) && (f >= γ), Pre(A_star) + α, Pre(A_star))
    end
    @divide cells(cell) when = volume >= X * A₀, along = RandomPlane(), A_star => Split(),
        X => randn(μ_X, σ_X; lower = 0.0)
    @sweep Metropolis(; temperature = T)
end

"""
    openvt_reference_state(; lattice = (1400, 1400), A₀ = 50)

One disc-shaped cell at the lattice centre: the sites whose centres lie within
`R = √(A₀/π)` of the centre point `(size .+ 1) ./ 2` (Morpheus' `Sphere radius = R`), id 1,
as `[ownership => σ, kind => [:cell]]`. For `A₀ = 50` that is 52 sites on an even lattice
and 45 on an odd one.
"""
function openvt_reference_state(; lattice = (1400, 1400), A₀ = 50)
    σ = zeros(Int32, lattice)
    R = sqrt(A₀ / π)
    c = (Tuple(lattice) .+ 1) ./ 2
    for I in CartesianIndices(σ)
        sqrt(sum(abs2, Tuple(I) .- c)) <= R && (σ[I] = 1)
    end
    return [ownership => σ, kind => [:cell]]
end

"""
    openvt_snapshot(u; A₀ = 50.0, center = (size(u.σ) .+ 1) ./ 2) -> (; x, y, r, f, a)

The O2 rows of a saved state `u` of [`OpenVTReferenceMonolayer`](@ref) (spec §3.1): one per
live cell (volume > 0), in id order, lengths in units of `R = √(A₀/π)`:

- `x`, `y`: the centroid (mean site index; the lattice is closed) minus `center`, over `R`;
- `r = √(A_star/π) / R`, the radius of the cell's reference area;
- `f`: the free-surface fraction, medium pairs over unlike pairs on `Moore(1)`, from σ;
- `a = volume / A_star`.
"""
function openvt_snapshot(u; A₀ = 50.0, center = (size(u.σ) .+ 1) ./ 2)
    σ = Array(u.σ)
    ndims(σ) == 2 || throw(ArgumentError("openvt_snapshot: a 2D state is required, got $(ndims(σ))D"))
    volume = Array(u.cell.volume)
    A = Array(u.cell.A_star)
    n = length(volume)
    sx = zeros(n); sy = zeros(n); med = zeros(Int, n); unlike = zeros(Int, n)
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
    R = sqrt(A₀ / π)
    x = [(sx[c] / volume[c] - center[1]) / R for c in live]
    y = [(sy[c] / volume[c] - center[2]) / R for c in live]
    r = [sqrt(Float64(A[c]) / π) / R for c in live]
    f = [med[c] / unlike[c] for c in live]
    a = [volume[c] / Float64(A[c]) for c in live]
    return (; x, y, r, f, a)
end

# ---------------------------------------------------------------------------------------
# Run guards (callbacks checked at every MCS boundary, after the lifecycle)

"""
    stop_at_cells(n; every = 1) -> DiscreteCallback

Terminate a run (`ReturnCode.Terminated`) at the end of the first checked MCS whose number of
live cells (volume > 0, after the lifecycle) is at least `n`; the state of that MCS is the
last one saved. Checked every `every` MCS: on a device each check is one host read (a count
over the cell volumes), a declared host pass (D-145).
"""
function stop_at_cells(n::Integer; every::Integer = 1)
    every >= 1 || throw(ArgumentError("stop_at_cells: `every` must be ≥ 1, got $every"))
    condition(u, t, integ) = t % every == 0 && count(>(0), u.cell.volume) >= n
    return DiscreteCallback(condition, terminate!)
end

"""
    edge_guard(margin; terminate = false, every = 1) -> DiscreteCallback

Guard a run on a finite lattice that stands for an unbounded domain: after every checked MCS,
if a cell comes within `margin` sites of the lattice edge
([`Analysis.near_edge`](@ref PottsModels.Analysis.near_edge)), throw a `DomainError` (the
default) or, with `terminate = true`, stop the run with `ReturnCode.Failure` (the state of
that MCS is the last one saved). Checked every `every` MCS: on a device each check is one
host read (a masked reduction over σ), a declared host pass (D-145).
"""
function edge_guard(margin::Integer; terminate::Bool = false, every::Integer = 1)
    every >= 1 || throw(ArgumentError("edge_guard: `every` must be ≥ 1, got $every"))
    g = _EdgeGuard(Int(margin), Ref{Any}(nothing))
    condition(u, t, integ) = t % every == 0 && g(u.σ)
    affect!(integ) = terminate ? terminate!(integ, ReturnCode.Failure) :
                     throw(DomainError(margin, "edge_guard: a cell came within $margin sites of the lattice edge " *
                                               "at MCS $(integ.t); use a larger lattice"))
    return DiscreteCallback(condition, affect!)
end

# `near_edge` as one masked reduction: the frame of `margin` sites, built once per array
# type and size on its backend
struct _EdgeGuard
    margin::Int
    frame::Ref{Any}          # a concrete `RefValue{Any}` at construction; read only on the host
end
function (g::_EdgeGuard)(σ::AbstractArray)
    σ isa Array && return Analysis.near_edge(σ, g.margin)
    m = g.frame[]
    if !(m isa AbstractArray && typeof(m) == typeof(similar(σ, Bool)) && size(m) == size(σ))
        host = falses(size(σ))
        for I in CartesianIndices(host)
            host[I] = any(d -> I[d] <= g.margin || I[d] >= size(σ, d) - g.margin + 1, 1:ndims(σ))
        end
        m = similar(σ, Bool)
        copyto!(m, Array(host))
        g.frame[] = m
    end
    return mapreduce((s, f) -> f & (s != 0), |, σ, m; init = false)
end
