# Top-level definitions for layouts test suites (`layouts_tests.jl`, `layouts_insert_voronoi_tests.jl`, `layouts_eden_splits_tests.jl`).

@testsetup module LayoutsSetup
using Potts, Test
using Potts.Layouts
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using PottsModels: akeeb_state

using Test: Test


_op(op, key) = only(last(p) for p in op if isequal(first(p), key))

# operating points compared by value (their keys are symbolic)
_same(a, b) = _op(a, ownership) == _op(b, ownership) && _op(a, kind) == _op(b, kind)

_sites(σ, c) = findall(==(c), σ)

# the smallest Chebyshev distance between two site sets (brute force)
_cheb(a, b) = minimum(maximum(abs.(Tuple(x - y))) for x in a, y in b)

# every pair of distinct cells is more than `gap` sites apart (Chebyshev)
_separated(σ, gap) = (
    n = maximum(σ);
    all(_cheb(_sites(σ, a), _sites(σ, b)) > gap for a in 1:n for b in (a + 1):n)
)


@potts_model HexLayoutProbe begin
    @kinds medium wall[frozen] cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((18, 14); boundary = Closed(), geometry = Hexagonal(), neighborhood = Hex(1))
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end


@potts_model PeriodicLayoutProbe begin
    @kinds medium cell
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model ChannelLayoutProbe begin
    @kinds medium wall cell
    @lattice Lattice((11, 11); boundary = (Periodic(), Closed()))
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end


@potts_model DomainLayoutProbe begin
    @kinds medium cell
    @lattice Lattice((10, 10); boundary = Closed(), domain = OnIndices(x -> x[1] <= 5))
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end


# a disk domain (Cartesian predicate) with a frozen wall kind; the same model with a mobile
# wall is the negative control for "the frame stays put"
@potts_model DiskFrameProbe begin
    @kinds medium wall[frozen] cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((24, 24); boundary = Closed(), domain = x -> (x[1] - 12.5)^2 + (x[2] - 12.5)^2 <= 10.5^2)
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end


@potts_model DiskMobileWallProbe begin
    @kinds medium wall cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((24, 24); boundary = Closed(), domain = x -> (x[1] - 12.5)^2 + (x[2] - 12.5)^2 <= 10.5^2)
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end


# brute-force frame oracle: in-domain sites with a site outside the domain, or beyond a
# closed lattice edge, within Chebyshev distance `w` (through the wrap on periodic axes)
function _frame_oracle(mask, per, w)
    dims = size(mask)
    return [
        mask[i] &&
            any(CartesianIndices(ntuple(_ -> (-w):w, ndims(mask)))) do o
            j = Tuple(i) .+ Tuple(o)
            all(d -> per[d] || 1 <= j[d] <= dims[d], 1:ndims(mask)) || return true
            !mask[CartesianIndex(map((x, n, p) -> p ? mod1(x, n) : x, j, dims, per))]
        end for i in CartesianIndices(mask)
    ]
end


# two distinct cells touch (Moore(1)), through the wrap on axes marked periodic
function _touching(σ, per)
    n = size(σ)
    for i in CartesianIndices(σ), d in CartesianIndices(ntuple(_ -> -1:1, ndims(σ)))
        j = Tuple(i + d)
        all(k -> per[k] || 1 <= j[k] <= n[k], 1:ndims(σ)) || continue
        s = σ[CartesianIndex(map((x, m, p) -> p ? mod1(x, m) : x, j, n, per))]
        σ[i] != 0 && s != 0 && σ[i] != s && return true
    end
    return false
end


# The extension API: a layout defined outside Potts, through public names only.
module ScratchLayouts
    using Potts: Potts, AbstractLayout
    using CorePotts: CorePotts
    """Paint the given sites as one cell of kind `k`."""
    struct Sites{N} <: AbstractLayout
        idx::Vector{NTuple{N, Int}}
        k::Symbol
    end
    function Potts.paint!(op::Potts.LayoutState, l::Sites, lat)
        clat = Potts.core_lattice(lat)                      # CorePotts view, e.g. for `shift`
        id = Potts.new_cell!(op, l.k)
        for i in l.idx
            _, j = CorePotts.shift(clat, i, ntuple(_ -> Int32(0), length(i)))
            Potts.assign!(op, Tuple(j), id)
        end
        Potts.record!(op; requested = 1, painted = 1)
    end
    # every qualified access above, as ExplicitImports' `check_all_qualified_accesses_are_public` sees them
    const QUALIFIED = (
        (Potts, :paint!), (Potts, :LayoutState), (Potts, :core_lattice), (Potts, :new_cell!),
        (Potts, :assign!), (Potts, :record!), (CorePotts, :shift),
    )
end


_warnings(f) = [r.message for r in Test.collect_test_logs(f; min_level = Base.CoreLogging.Warn)[1]]


# ---------------------------------------------------------------------------------------------
# InsertUntil (P6.2a, review §3 R2)
# ---------------------------------------------------------------------------------------------

@potts_model InsertProbe begin
    @kinds medium host guest
    @parameters begin
        J[kind, kind] = [0 8 8; 8 4 6; 8 6 4]
    end
    @lattice Lattice((16, 16); boundary = Closed(), domain = OnIndices(x -> x[1] + x[2] <= 26))
    @energy begin
        cells(host) => (volume - 16)^2
        cells(guest) => (volume - 4)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = 4.0)
end


# the point and the InsertUntil rows of the layout report as (; painted, misses, counted)
function _tally(l, x)
    op, rep = layout(l, x; report = true)
    return op, [(; r.painted, r.misses, r.counted) for r in rep if r.type === :InsertUntil]
end

_kind_sites(op, k) = (σ = _op(op, ownership); ks = _op(op, kind); findall(i -> σ[i] > 0 && ks[σ[i]] == k, CartesianIndices(σ)))


# ---------------------------------------------------------------------------------------------
# Eden, Splits, RandomPoints(replace = true), shortfall (P6.3c, D-141); the frozen acceptance
# file holds the hand fixtures, the growth oracle and the spec 01 bands
# ---------------------------------------------------------------------------------------------

using LinearAlgebra: Symmetric, eigen


# An independent recursive oracle for Splits on a 1 × n strip: every cut is across x, at the
# centroid, the daughter taking the sites right of it; daughters follow their mothers.
function _strip_splits(n, k)
    cells = [collect(1:n)]
    for _ in 1:k
        for c in 1:length(cells)
            S = cells[c]
            length(S) >= 2 || continue
            m = sum(S) / length(S)
            push!(cells, filter(>(m), S))
            cells[c] = filter(<=(m), S)
        end
    end
    return cells
end


# The cut by an independent eigendecomposition: daughter = sites on the positive side of the
# sign-fixed top eigenvector of the Cartesian scatter matrix.
function _eig_cut(S, emb)
    P = [collect(emb(x)) for x in S]
    c = sum(P) / length(P)
    C = sum((p - c) * (p - c)' for p in P)
    v = eigen(Symmetric(C)).vectors[:, end]
    v[findfirst(x -> abs(x) > 1.0e-9, v)] < 0 && (v = -v)
    return Set(S[i] for i in eachindex(S) if sum((P[i] - c) .* v) > 0)
end


# A custom layer painting given site sets, one cell of kind :c each.
struct _SiteSets <: AbstractLayout
    cells::Vector{Vector{NTuple{N, Int}}} where {N}
end

function Potts.paint!(op::Potts.LayoutState, l::_SiteSets, lat)
    for c in l.cells
        id = Potts.new_cell!(op, :c)
        foreach(x -> Potts.assign!(op, x, id), c)
    end
    return nothing
end


# Exact cut oracle (2D, BigFloat at 512 bits): the daughter is the sites with (p − c)·v > 0,
# with exact zeros (|·| < 1e-60 at this precision) on the plane.
function _exact_daughter_2d(S)
    setprecision(BigFloat, 512) do
        P = [BigFloat.(s) for s in S]
        n = length(P)
        c = (sum(p[1] for p in P) / n, sum(p[2] for p in P) / n)
        a = sum((p[1] - c[1])^2 for p in P); d = sum((p[2] - c[2])^2 for p in P)
        b = sum((p[1] - c[1]) * (p[2] - c[2]) for p in P)
        λ = (a + d) / 2 + sqrt(((a - d) / 2)^2 + b^2)
        v = abs(b) > 1.0e-60 ? [λ - d, b] : (a >= d ? [big(1.0), big(0.0)] : [big(0.0), big(1.0)])
        v ./= sqrt(sum(abs2, v))
        v[findfirst(x -> abs(x) > 1.0e-9, v)] < 0 && (v .*= -1)
        Set(S[i] for i in eachindex(S) if (P[i][1] - c[1]) * v[1] + (P[i][2] - c[2]) * v[2] > 1.0e-60)
    end
end


function ly_throws(T, pats, f)
    err = try
        f(); nothing
    catch e
        e
    end
    @test err isa T
    return err
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
