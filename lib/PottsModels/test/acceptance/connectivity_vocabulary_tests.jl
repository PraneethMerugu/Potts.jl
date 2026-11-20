# the connectivity vocabulary, surface, with its negative controls
# (gain-side and hole negative controls). Decisions: D-189 (rulings 1–12,
# research/connectivity-vocabulary.md §8, §12, §13.1), D-191 (CC3D source check), D-099,
# D-140.
#
# Semantics pinned here. A proposal copies `new = σ(source)` into the target x, whose owner
# was `old`. The SHELL of x is the 8 sites of the 3×3 box (square 2D), the 6 hex neighbours,
# or the 26 sites of the 3×3×3 box (cubic 3D); periodic axes wrap. A shell POSITION off a
# `Closed()` face is out of domain and reads as "nothing": never `old`, never `new`, never
# medium, skipped by every fold. FACE adjacency is 4 (square), 6 (hex), 6 (cubic); FULL
# adjacency is 8 (square) and 26 (cubic). Hex has one adjacency: `:full` equals `:face` there.
#
# 1. Rule values (`Potts.DSL`): `Local(; gain = true, adjacency = :face)`, `ArcOrPair()`,
#    `Simple(; adjacency = :face)`, `Global(; window = nothing, adjacency = :face)`. A bad
#    `adjacency` (not `:face`/`:full`) is an `ArgumentError`. Defaults: gain ON (ruling 3),
#    face (ruling 4).
# 2. The losing-side tests, for a losing cell `old ≠ 0` (the medium as `old` is never
#    checked, D-191):
#    - `Local(; gain, adjacency)` refuses unless ALL of
#        (a) `old`'s shell sites form exactly one piece under `adjacency` (zero pieces, the
#            last site or an isolated fragment, is refused: D-074);
#        (b) the shell is not FULL: a full shell is every one of the 8/6/26 positions in the
#            domain and owned by `old` (ruling 10; D-191 CC3D rule 2). A shell with an
#            out-of-domain position is never full;
#        (c) if `gain`: `new` (the medium included, D-191 CC3D rule 1) owns a shell site that
#            is adjacent to x under `adjacency` (face: the 4/6/6 face neighbours; full: any
#            shell site).
#      With the defaults this is exactly CC3D rules 1 and 2 (D-191). In 3D, (a) is the face
#      count of the 26-shell (D-140).
#    - `ArcOrPair()` accepts iff `pieces(old, shell; face) ≤ 1`, or exactly two distinct
#      cells and no medium on the shell, where the out-of-domain positions, if any, count as
#      ONE extra distinct cell (ruling 5: TST's frame). Zero arcs pass.
#    - `Simple(; adjacency)` accepts iff x is a simple point of X = old's shell sites ∪ {x}
#      (out-of-domain positions are background, ruling 7): T(x, X) = 1 and T̄(x, X̄) = 1, with
#      the object adjacency `adjacency` and the background the dual one. 2D :face = (4, 8):
#      T = 4-components of N8* ∩ X that touch a 4-neighbour of x, T̄ = 8-components of
#      N8* ∩ X̄. :full = (8, 4). 3D :face = (6, 26): T = 6-components of N18* ∩ X touching a
#      6-neighbour, T̄ = 26-components of N26* ∩ X̄; :full = (26, 6). Hex: arcs of X and of X̄
#      on the 6-ring, both 1.
# 3. The gaining side. `Simple()` also tests `new ≠ 0`: x must be a simple point of
#    new's shell sites ∪ {x}. `Local()` and `ArcOrPair()` have no gaining-side test of their
#    own (Local's gain clause (c) is part of the losing-side test, as in CC3D).
# 4. `connectivity(kinds…; rule = Local(), penalty = nothing)`:
#    - in `@constraint` (veto): refuse when `old ≠ 0`, kind[old] ∈ kinds and the losing-side
#      test fails; for `Simple()` also when `new ≠ 0`, kind[new] ∈ kinds and the gaining
#      test fails (each cell against its own kind filter);
#    - in `@drive` (penalty): ΔH += penalty · [the veto form refuses];
#    - `penalty` in `@constraint` is an `ArgumentError` naming `@drive`; `@drive
#      connectivity(…)` without `penalty` is an `ArgumentError` naming `@constraint`
#      (ruling 2); `rule = Global()` is an `ArgumentError` naming `Global` until global connectivity.
# 5. `connected(c; rule = Local())`, `c ∈ {old, new}`, the copy-scope Boolean: `true` for the
#    medium; for `old` the losing-side test, for `new` under `Simple()` the gaining test. (Not
#    pinned: `connected(new)` under `Local()`/`ArcOrPair()`.)
# 6. Folds: `shell(target)` is a relation; `pieces(n for n in shell(target) if pred(n);
#    adjacency = :face)` counts the components of the shell sites where `pred` holds;
#    `pieces(c, shell(target); adjacency)` ≡ `pieces(n for n in shell(target) if owner[n] ==
#    c; adjacency)` (for `c = 0` the medium's pieces). `pieces` over a relation other than
#    `shell` is an `ArgumentError` naming `shell`. `distinct(body for n in rel(site) if cond)`
#    is the number of distinct values over the in-domain sites (the medium's 0 is a value).
#    `components` is gone with no alias (ruling 6): not in `Potts.DSL`, and a model using it
#    does not build.
# 7. Equivalent spellings, byte-identical generated code and fingerprint: `rule = Local()` ≡
#    no rule; `ring_cells` ≡ `distinct(owner[n] for n in shell(target) if
#    owner[n] != 0)`; `ring_medium` ≡ `count(owner[n] == 0 for n in shell(target))`.
#    `ring_arcs` and `local_components` keep their values: `pieces(old, shell(target))` for a
#    cell, 0 for the medium; `ring_cells` keeps "out of domain is nothing" (no frame).
#
# Oracles. Every rule is computed here, independently, from its definition by brute-force
# flood fill over the shell offsets (`connectivity_test*`), and the implementation is read through
# compiled models: one model charges rule i's refusals as a `@drive` penalty 2^(i−1), so
# `delta_H` returns all seven decisions at once; two more read back the folds, `connected`
# and the old names. Enumerations: square 3×3 (exhaustive at a periodic interior target, and
# at a closed edge and corner), hex (exhaustive, interior and edge), cubic 26-shell (every
# shell with ≤ 4 or ≥ 22 sites of `old` for (A, medium), ≤ 3 or ≥ 23 for (A, A), plus a fixed
# random sample; exhaustive at a closed corner). "Exhaustive" is over 4 owner labels for an
# (A loses, A gains) copy and 3 labels for the other (old, new) cases: A/B, A/medium,
# B/A, medium/A. 2D `Simple()` is also checked against a GLOBAL oracle (component and hole
# counts of a whole 7×7 image, outside = background). The source of every enumerated copy
# lies at distance 2, off the shell (as a `NeighborOrder(3)` copy), so full shells and
# detached gains are reachable.
#
# Negative controls. In 2D NeighborOrder(2) is the 8 Moore sites, so it equals
# Moore(1); NeighborOrder(3) reaches distance 2 along an axis.
#   - Gain side: a 16-cell confluent tissue (no medium, 24² Closed, T = 4), 3 seeds × 100 MCS:
#     `Local()` keeps every cell face-connected (0 split snapshots of 30, by construction);
#     `Local(; gain = false)` does not (measured with an equivalent expression on 36e4390a:
#     Moore(1)/NeighborOrder(2) 26 of 30, NeighborOrder(3) 30 of 30; asserted ≥ 10).
#   - Holes: one adhesive cell in medium (J_cM = −1, 24² Closed, T = 6): `Local()` develops
#     holes (measured 30 and 29 of 30 snapshots; asserted ≥ 10); `Simple()` and
#     `Simple(; adjacency = :full)` never split and never make a hole (0, by theorem), and
#     the cell still moves.
# Akeeb: VonNeumann(1) proposals make the gain test vacuous and the full shell unreachable,
# so its constraint is unchanged (checked here on a run state). Its dynamics stay pinned by
# the existing record tests (`akeeb_analysis_tests.jl`, `akeeb_inventory_tests.jl`,
# `reproductions/10_akeeb_tests.jl`), not duplicated here.
#
# On the base (36e4390a) this file fails for these reasons: `MethodError: no method matching
# connectivity(…; penalty)` and `UndefVarError` for `pieces`, `shell`, `Local`, `ArcOrPair`,
# `Simple` (every readback and veto model, every build-error control); `Potts.DSL` has no
# `Local`/`ArcOrPair`/`Simple` and `Global` takes no `adjacency`; `:components` is still in
# the DSL; the full-shell copy under the local rule is accepted and the closed-edge copy under
# the ring rule is accepted. Passing on the base (controls): the Akeeb check, the oracle
# self-checks, the old-name values (validated through the same enumeration harness).

@testsetup module ConnectivityVocabularySetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Independent oracle
const HEX = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
const SQUARE = Tuple((i, j) for j in -1:1 for i in -1:1 if (i, j) != (0, 0))
const CUBE = Tuple((i, j, k) for k in -1:1 for j in -1:1 for i in -1:1 if (i, j, k) != (0, 0, 0))
function connectivity_shell(geom)
    if geom === :hex
        return HEX
    elseif geom === :square
        return SQUARE
    else
        return CUBE
    end
end
isface(geom, o) = geom === :hex || sum(abs, o) == 1
function connectivity_adj(geom, adjacency, a, b)
    if geom === :hex
        return (a .- b) in HEX
    elseif adjacency === :face
        return sum(abs, a .- b) == 1
    else
        return maximum(abs, a .- b) == 1
    end
end
"""Number of components of `sites` under `adj` that contain a site with `touch(site)`."""
function ncomp(sites, adj; touch = _ -> true)
    seen = falses(length(sites))
    n = 0
    for s in eachindex(sites)
        seen[s] && continue
        seen[s] = true
        stack = [s]
        t = touch(sites[s])
        while !isempty(stack)
            a = pop!(stack)
            for b in eachindex(sites)
                (!seen[b] && adj(sites[a], sites[b])) || continue
                seen[b] = true
                t |= touch(sites[b])
                push!(stack, b)
            end
        end
        n += t
    end
    return n
end
"""Owner of `x .+ o` (−1 off a closed axis); `periodic` is one Bool per axis."""
function connectivity_owner(σ, x, o, periodic)
    y = x .+ o
    for d in eachindex(y)
        if periodic[d]
            y = Base.setindex(y, mod1(y[d], size(σ, d)), d)
        elseif !(1 <= y[d] <= size(σ, d))
            return -1
        end
    end
    return Int(σ[y...])
end
owners(σ, x, geom, periodic) = [connectivity_owner(σ, x, o, periodic) for o in connectivity_shell(geom)]
connectivity_sites(geom, own, pred) = [connectivity_shell(geom)[k] for k in eachindex(own) if pred(own[k])]
connectivity_pieces(geom, own, c; adjacency = :face) =
    ncomp(connectivity_sites(geom, own, ==(c)), (a, b) -> connectivity_adj(geom, adjacency, a, b))
"""`Local(; gain, adjacency)`, the losing-side test (true for the medium)."""
function connectivity_local(geom, own, old, new; gain = true, adjacency = :face)
    old == 0 && return true
    all(==(old), own) && return false                                  # full shell (ruling 10)
    connectivity_pieces(geom, own, old; adjacency) == 1 || return false
    gain || return true
    sh = connectivity_shell(geom)
    return any(k -> own[k] == new && (adjacency === :full || isface(geom, sh[k])), eachindex(sh))
end
"""`ArcOrPair()`: ≤ 1 arc, or two cells and no medium; out of domain = one extra cell."""
function arcorpair(geom, own, old)
    old == 0 && return true
    connectivity_pieces(geom, own, old) <= 1 && return true
    cells = length(unique(filter(>(0), own))) + any(==(-1), own)
    return cells == 2 && count(==(0), own) == 0
end
"""`Simple(; adjacency)`: x is a simple point of c's shell sites ∪ {x} (true for the medium)."""
function connectivity_simple(geom, own, c; adjacency = :face)
    c == 0 && return true
    X = connectivity_sites(geom, own, ==(c))
    B = connectivity_sites(geom, own, !=(c))                      # other cells, medium, out of domain
    if geom === :hex
        h = (a, b) -> connectivity_adj(:hex, :face, a, b)
        return ncomp(X, h) == 1 && ncomp(B, h) == 1
    end
    face = (a, b) -> connectivity_adj(geom, :face, a, b)
    full = (a, b) -> connectivity_adj(geom, :full, a, b)
    near = o -> geom === :square || sum(abs, o) <= 2          # N8 in 2D, N18 in 3D
    isf = o -> sum(abs, o) == 1
    if adjacency === :face
        T = ncomp(filter(near, X), face; touch = isf)
        Tb = ncomp(B, full)
    else
        T = ncomp(X, full)
        Tb = ncomp(filter(near, B), face; touch = isf)
    end
    return T == 1 && Tb == 1
end
# cells 1, 2, 3 have kinds A, B, A; every rule is applied to kind A
const KIND = (:A, :B, :A)
con(c) = c > 0 && KIND[c] === :A
"""The seven veto decisions (true = accept), in the order of the readback penalties."""
function connectivity_rules(geom, own, old, new)
    lo(f) = !con(old) || f
    simple(adj) = (!con(old) || connectivity_simple(geom, own, old; adjacency = adj)) &&
        (!con(new) || connectivity_simple(geom, own, new; adjacency = adj))
    return (
        lo(connectivity_local(geom, own, old, new)),
        lo(connectivity_local(geom, own, old, new; adjacency = :full)),
        lo(connectivity_local(geom, own, old, new; gain = false)),
        lo(connectivity_local(geom, own, old, new; gain = false, adjacency = :full)),
        lo(arcorpair(geom, own, old)),
        simple(:face),
        simple(:full),
    )
end
"""The fold readback: pieces(old), pieces(old; full), medium pieces, distinct(shell),
distinct(face neighbours), then six `connected` bits."""
function connectivity_folds(geom, own, old, new)
    sh = connectivity_shell(geom)
    v = connectivity_pieces(geom, own, old) + 16 * connectivity_pieces(geom, own, old; adjacency = :full) +
        256 * connectivity_pieces(geom, own, 0) + 4096 * length(unique(filter(>=(0), own))) +
        65536 * length(unique([own[k] for k in eachindex(sh) if own[k] >= 0 && isface(geom, sh[k])]))
    bits = (
        old == 0 || connectivity_local(geom, own, old, new),
        arcorpair(geom, own, old),
        connectivity_simple(geom, own, old),
        connectivity_simple(geom, own, new),
        old == 0 || connectivity_local(geom, own, old, new; gain = false),
        connectivity_simple(geom, own, new; adjacency = :full),
    )
    return v + 1048576 * sum(bits[i] << (i - 1) for i in 1:6)
end
"""The old names: ring_arcs, local_components, ring_cells (no frame), ring_medium."""
function oldnames(geom, own, old)
    arcs = old == 0 ? 0 : connectivity_pieces(geom, own, old)
    return arcs + 16 * arcs + 256 * length(unique(filter(>(0), own))) + 4096 * count(==(0), own)
end
# ---------------------------------------------------------------------------------------
# Readback models: one set per (geometry, boundary)
const LATTICES = [
    (:square, true) => :(Lattice((7, 7); boundary = Periodic(), neighborhood = Moore(1))),
    (:square, false) => :(Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))),
    (:hex, true) => :(Lattice((9, 8); geometry = Hexagonal(), boundary = Periodic(), neighborhood = Hex(1))),
    (:hex, false) => :(Lattice((9, 8); geometry = Hexagonal(), boundary = Closed(), neighborhood = Hex(1))),
    (:cubic, true) => :(Lattice((5, 5, 5); boundary = Periodic(), neighborhood = Moore(1))),
    (:cubic, false) => :(Lattice((5, 5, 5); boundary = Closed(), neighborhood = Moore(1))),
]
connectivity_name(prefix, geom, periodic) = Symbol(prefix, uppercasefirst(string(geom)), periodic ? "Periodic" : "Closed")
for ((geom, periodic), lat) in LATTICES
    face = geom === :hex ? :(Hex(1)) : :(VonNeumann(1))
    @eval @potts_model $(connectivity_name("Rules", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @drive connectivity(A; penalty = 1.0)
        @drive connectivity(A; rule = Local(; adjacency = :full), penalty = 2.0)
        @drive connectivity(A; rule = Local(; gain = false), penalty = 4.0)
        @drive connectivity(A; rule = Local(; gain = false, adjacency = :full), penalty = 8.0)
        @drive connectivity(A; rule = ArcOrPair(), penalty = 16.0)
        @drive connectivity(A; rule = Simple(), penalty = 32.0)
        @drive connectivity(A; rule = Simple(; adjacency = :full), penalty = 64.0)
        @sweep Metropolis(; temperature = 1.0)
    end
    @eval @potts_model $(connectivity_name("Folds", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @drive copy => pieces(old, shell(target)) + 16 * pieces(old, shell(target); adjacency = :full) +
            256 * pieces(n for n in shell(target) if owner[n] == 0) +
            4096 * distinct(owner[n] for n in shell(target)) +
            65536 * distinct(owner[n] for n in $face(target))
        @drive copy => 1048576 * (
            1.0 * connected(old) + 2.0 * connected(old; rule = ArcOrPair()) +
                4.0 * connected(old; rule = Simple()) + 8.0 * connected(new; rule = Simple()) +
                16.0 * connected(old; rule = Local(; gain = false)) +
                32.0 * connected(new; rule = Simple(; adjacency = :full))
        )
        @sweep Metropolis(; temperature = 1.0)
    end
    @eval @potts_model $(connectivity_name("Old", geom, periodic)) begin
        @kinds medium A B
        @lattice $lat
        @drive copy => ring_arcs + 16 * local_components + 256 * ring_cells + 4096 * ring_medium
        @sweep Metropolis(; temperature = 1.0)
    end
end
connectivity_model(prefix, geom, periodic) = getfield(@__MODULE__, connectivity_name(prefix, geom, periodic))
"""A problem for model `M` on `dims` with cells 1, 2, 3 (kinds A, B, A) at `cellsites`."""
function connectivity_problem(M, dims, cellsites)
    σ = zeros(Int32, dims)
    foreach(((c, s),) -> σ[s...] = c, enumerate(cellsites))
    return PottsProblem(M(; name = :connectivity), [ownership => σ, kind => collect(KIND)], (0, 1))
end
"""The drive readback of `prob` for target `x`, source `y` in state `u` (an integer)."""
function connectivity_read(prob, u, ctx, x, y)
    lat = prob.lattice
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y), x, 1, u.ownership[x...], u.ownership[y...])
    d = prob.f.delta_H(u, prob.p, prop, ctx) - energy_change(prob, u, prop)
    return round(Int, d)
end
"""Lattice sites of the in-domain shell positions of `x` (`nothing` off a closed axis)."""
function connectivity_shellsites(dims, x, geom, periodic)
    out = Any[]
    for o in connectivity_shell(geom)
        y = x .+ o
        inside = true
        for d in eachindex(y)
            if periodic[d]
                y = Base.setindex(y, mod1(y[d], dims[d]), d)
            elseif !(1 <= y[d] <= dims[d])
                inside = false
            end
        end
        push!(out, inside ? y : nothing)
    end
    return out
end
# Enumeration scenes: (geometry, periodic, target, source). The source is at distance 2 along
# axis 1, off the shell.
const SCENES = [
    (:square, true, (4, 4)), (:square, false, (1, 4)), (:square, false, (1, 1)),
    (:hex, true, (5, 4)), (:hex, false, (1, 4)),
    (:cubic, true, (3, 3, 3)), (:cubic, false, (1, 1, 1)),
]
# (old, new) cases: old A / new A (other cell 2 = B), old A / new B, old A / new medium,
# old B (unconstrained) / new A, old medium / new A
const CASES = [(1, 3), (1, 2), (1, 0), (2, 1), (0, 1)]
"""Owner assignments of the in-domain shell positions to enumerate in a scene."""
function configs(geom, periodic, nin, old, new)
    others = setdiff([0, 1, 2, 3], [old, new])
    labels = (old, new) == (1, 3) ? [old, new, 0, 2] : unique([old, new, first(others)])
    if geom === :cubic && periodic
        # (old A, new medium): every shell with ≤ 4 or ≥ 22 sites of `old`; (old A, new A):
        # ≤ 3 or ≥ 23; the rest of the shell alternates between `new` and a third label.
        # Plus a fixed random sample over the labels (2000, or 1500 for the other cases).
        out = Vector{Vector{Int}}()
        lo, hi, nrand = if (old, new) == (1, 0)
            (4, 22, 0)
        elseif (old, new) == (1, 3)
            (3, 23, 2000)
        else
            (-1, 27, 1500)
        end
        alt = new == 0 ? first(others) : 0
        for m in 0:(2^26 - 1)
            k = count_ones(m)
            (k <= lo || k >= hi) || continue
            push!(out, [(m >> (i - 1)) & 1 == 1 ? old : (isodd(i + k) ? new : alt) for i in 1:26])
        end
        st = UInt64(0x6367 + 97 * old + new)
        for _ in 1:nrand
            push!(
                out, [
                    begin
                        st = st * 6364136223846793005 + 1442695040888963407
                        labels[1 + Int((st >> 33) % length(labels))]
                    end for _ in 1:26
                ]
            )
        end
        return out
    end
    return [[labels[1 + (j ÷ length(labels)^(i - 1)) % length(labels)] for i in 1:nin] for j in 0:(length(labels)^nin - 1)]
end
"""Runs every config of a scene through `models` (prefix => oracle); returns counts."""
function connectivity_enumerate(geom, periodic, x, prefixes)
    dims = if geom === :cubic
        (5, 5, 5)
    elseif geom === :hex
        (9, 8)
    else
        (7, 7)
    end
    per = ntuple(_ -> periodic, length(dims))
    y = Base.setindex(x, x[1] + 2, 1)
    shellsites = connectivity_shellsites(dims, x, geom, per)
    taken = Set(Any[x, y, filter(!isnothing, shellsites)...])
    far = [Tuple(I) for I in CartesianIndices(dims) if !(Tuple(I) in taken)][1:3]
    probs = [connectivity_problem(connectivity_model(pre, geom, periodic), dims, far) for (pre, _) in prefixes]
    us = [deepcopy(p.u0) for p in probs]
    ctxs = [Potts._host_ctx(p) for p in probs]
    inpos = findall(!isnothing, shellsites)
    n = 0
    agree = zeros(Int, length(prefixes))
    firstbad = Any[nothing for _ in prefixes]
    for (old, new) in CASES, cfg in configs(geom, periodic, length(inpos), old, new)
        own = fill(-1, length(shellsites))
        own[inpos] .= cfg
        for (m, (_, oracle)) in enumerate(prefixes)
            σ = us[m].ownership
            σ[x...] = old
            σ[y...] = new
            for (k, i) in enumerate(inpos)
                σ[shellsites[i]...] = cfg[k]
            end
            want = oracle(geom, own, old, new)
            got = connectivity_read(probs[m], us[m], ctxs[m], x, y)
            ok = got == want
            agree[m] += ok
            (!ok && firstbad[m] === nothing) && (firstbad[m] = (; old, new, own, got, want))
        end
        n += 1
    end
    return n, agree, firstbad
end
rulebits(geom, own, old, new) = (r = connectivity_rules(geom, own, old, new); sum((!r[i]) << (i - 1) for i in 1:7))
# ---------------------------------------------------------------------------------------
# Hand-checked fixtures
@potts_model AliasLocal begin
    @kinds medium A B
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @constraint connectivity(A; rule = Local())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model VetoDefault begin
    @kinds medium A B
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @constraint connectivity(A)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model VetoSimple begin
    @kinds medium A B
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @constraint connectivity(A; rule = Simple())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model AliasPair begin
    @kinds medium A B
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @constraint connectivity(A; rule = ArcOrPair())
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model VetoPair begin
    @kinds medium A B
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @constraint connectivity(A; rule = ArcOrPair())
    @sweep Metropolis(; temperature = 1.0)
end
function allows(M, σ, x, y)
    prob = PottsProblem(M(; name = :v), [ownership => σ, kind => collect(KIND)], (0, 1))
    lat = prob.lattice
    prop = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y), x, 1, σ[x...], σ[y...])
    return prob.f.constraint(prob.u0, prob.p, prop, Potts._host_ctx(prob))
end
rulesread(geom, periodic, σ, x, y) =
    (
    M = connectivity_model("Rules", geom, periodic);
    prob = PottsProblem(M(; name = :v), [ownership => σ, kind => collect(KIND)], (0, 1));
    b = connectivity_read(prob, prob.u0, Potts._host_ctx(prob), x, y); ntuple(i -> (b >> (i - 1)) & 1 == 0, 7)
)
"""A 7×7 state with cells 1, 2, 3 present (2 and 3 in the far corner column)."""
connectivity_σ(fill1) = (σ = zeros(Int32, 7, 7); fill1(σ); σ[7, 6] = 2; σ[7, 7] = 3; σ)
# ---------------------------------------------------------------------------------------
# Global oracle for Simple() (2D): the copy keeps the numbers of object and background
# components of a whole 7×7 image (outside = background) iff Simple() accepts it
"""(object components, background components) of `X` (a BitMatrix) padded by background."""
function connectivity_topology(X, objadj)
    P = falses(size(X) .+ 2)
    P[2:(end - 1), 2:(end - 1)] .= X
    comps(M, eight) = begin
        seen = falses(size(M)); n = 0
        for I in CartesianIndices(M)
            (M[I] && !seen[I]) || continue
            n += 1; seen[I] = true; st = [I]
            while !isempty(st)
                J = pop!(st)
                for d in CartesianIndices((-1:1, -1:1))
                    (d == CartesianIndex(0, 0) || (!eight && sum(abs, Tuple(d)) != 1)) && continue
                    K = J + d
                    (checkbounds(Bool, M, K) && M[K] && !seen[K]) || continue
                    seen[K] = true; push!(st, K)
                end
            end
        end
        n
    end
    return (comps(P, objadj === :full), comps(.!P, objadj !== :full))
end
# ---------------------------------------------------------------------------------------
# The helper in two statements, and every misuse (ruling 2, §8.4)
"""The exception thrown while defining and building `body` (a quoted model), or `nothing`."""
function build_error(body::Expr)
    try
        Core.eval(@__MODULE__, body)
    catch e
        return e isa LoadError ? e.error : e
    end
    return nothing
end
msg(e) = e === nothing ? "" : sprint(showerror, e)
function connectivity_try(name, stmts...; lattice = :(Lattice((8, 8); neighborhood = Moore(1))))
    return build_error(
        quote
            @potts_model $name begin
                @kinds medium A B
                @parameters E₀ = 50.0
                @lattice $lattice
                @energy cells => (volume - 9)^2
                $(stmts...)
                @sweep Metropolis(; temperature = 1.0)
            end
            let σ = zeros(Int32, 8, 8)
                σ[3:5, 3:5] .= 1; σ[6:7, 6:7] .= 2
                solve(PottsProblem($name(; name = :e), [ownership => σ, kind => [:A, :B]], (0, 1)), SequentialCPM())
            end
        end
    )
end
@potts_model PenaltyParam begin
    @kinds medium A B
    @parameters E₀ = 50.0
    @lattice Lattice((7, 7); boundary = Closed(), neighborhood = Moore(1))
    @drive connectivity(A; rule = ArcOrPair(), penalty = E₀)
    @sweep Metropolis(; temperature = 1.0)
end
# ---------------------------------------------------------------------------------------
# Aliases lower byte-identically (generated code and fingerprint)
function strip_lines!(ex)
    ex isa Expr || return ex
    Base.remove_linenums!(ex)
    foreach(strip_lines!, ex.args)
    return ex
end
function code(M)
    g = Potts.generated_code(M(; name = :x))
    return [string(k) => string(strip_lines!(deepcopy(getproperty(g, k)))) for k in propertynames(g)]
end
connectivity_fp(M) = (
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1; σ[6:7, 6:7] .= 2;
    PottsProblem(M(; name = :x), [ownership => σ, kind => [:A, :B]], (0, 1)).f.fingerprint
)
const ALIASES = [
    "Local() ≡ default" => [:(@constraint connectivity(A; rule = Local())), :(@constraint connectivity(A))],
    "ring_cells ≡ distinct(…shell…)" => [
        :(@drive copy => 1.0 * ring_cells),
        :(@drive copy => 1.0 * distinct(owner[n] for n in shell(target) if owner[n] != 0))
    ],
    "ring_medium ≡ count(…shell…)" => [
        :(@drive copy => 1.0 * ring_medium),
        :(@drive copy => 1.0 * count(owner[n] == 0 for n in shell(target)))
    ],
]
# ---------------------------------------------------------------------------------------
# Negative controls
"""Components of `mask` (4- or 8-adjacency); and how many touch the lattice edge."""
function connectivity_comps(mask, eight)
    seen = falses(size(mask)); n = 0; edge = 0
    for I in CartesianIndices(mask)
        (mask[I] && !seen[I]) || continue
        n += 1; seen[I] = true; st = [I]; e = false
        while !isempty(st)
            J = pop!(st)
            e |= J[1] in (1, size(mask, 1)) || J[2] in (1, size(mask, 2))
            for d in CartesianIndices((-1:1, -1:1))
                (d == CartesianIndex(0, 0) || (!eight && sum(abs, Tuple(d)) != 1)) && continue
                K = J + d
                (checkbounds(Bool, mask, K) && mask[K] && !seen[K]) || continue
                seen[K] = true; push!(st, K)
            end
        end
        edge += e
    end
    return n, edge
end
connectivity_split(σ, c; eight = false) = connectivity_comps(σ .== c, eight)[1] > 1
"""Holes of cell `c`: background components (dual adjacency) that do not touch the edge."""
holes(σ, c; eight = false) = (r = connectivity_comps(σ .!= c, !eight); r[1] - r[2])
for (name, rule) in (
        (:NcLocal, :(Local())), (:NcNoGain, :(Local(; gain = false))),
        (:NcSimple, :(Simple())), (:NcSimpleFull, :(Simple(; adjacency = :full))),
    )
    @eval @potts_model $name begin
        @kinds medium A
        @parameters begin
            T = 4.0
            V = 36.0
            J[kind, kind] = [0.0 4.0; 4.0 2.0]
        end
        @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
        @energy begin
            cells => (volume - V)^2
            contacts => J[kind, neighbor_kind]
        end
        @constraint connectivity(A; rule = $rule)
        @sweep Metropolis(; temperature = T)
    end
end
connectivity_tissue() = (
    σ = zeros(Int32, 24, 24); k = 0;
    for i in 0:3, j in 0:3
        k += 1; σ[(6i + 1):(6i + 6), (6j + 1):(6j + 6)] .= k
    end; σ
)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "connectivity vocabulary: rule values and their options" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    @testset "connectivity vocabulary: rule values and their options" begin
        D = Potts.DSL
        @test all(in(keys(D)), (:Local, :ArcOrPair, :Simple, :Global))
        @test D.Local().gain === true                            # ruling 3: gain on by default
        @test D.Local().adjacency === :face                      # ruling 4: face by default
        @test D.Local(; gain = false).gain === false
        @test D.Local(; adjacency = :full).adjacency === :full
        @test D.Simple().adjacency === :face && D.Simple(; adjacency = :full).adjacency === :full
        @test D.Global().adjacency === :face && D.Global().window === nothing
        @test D.Global(; window = 8, adjacency = :full).adjacency === :full
        @test D.ArcOrPair() isa D.ArcOrPair
        @test_throws ArgumentError D.Local(; adjacency = :diagonal)
        @test_throws ArgumentError D.Simple(; adjacency = 8)
        @test_throws ArgumentError D.Global(; adjacency = :vertex)
        @test_throws ArgumentError D.Global(; window = 0)          # D-140 unchanged
    end
end

@testitem "connectivity vocabulary: `components` is gone, with no alias (ruling 6)" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: `components` is gone, with no alias (ruling 6)" begin
        @test !(:components in keys(Potts.DSL))
        # a model that uses it does not build; `pieces` does (both in the build-error testset)
    end
end

@testitem "connectivity vocabulary: enumeration oracle, rules x" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: enumeration oracle, rules $geom $(periodic ? "Periodic" : "Closed") x = $x" for (geom, periodic, x) in SCENES
        n, agree, bad = connectivity_enumerate(geom, periodic, x, ["Rules" => rulebits])
        bad[1] === nothing || @info "connectivity vocabulary rules: first disagreement" geom periodic x bad[1]
        @test agree[1] == n
        @test n >= 100
    end
end

@testitem "connectivity vocabulary: enumeration oracle, folds and `connected` x" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: enumeration oracle, folds and `connected` $geom $(periodic ? "Periodic" : "Closed") x = $x" for (geom, periodic, x) in SCENES
        n, agree, bad = connectivity_enumerate(geom, periodic, x, ["Folds" => connectivity_folds, "Old" => (g, o, a, _) -> oldnames(g, o, a)])
        bad[1] === nothing || @info "connectivity vocabulary folds: first disagreement" geom periodic x bad[1]
        bad[2] === nothing || @info "connectivity vocabulary old names: first disagreement" geom periodic x bad[2]
        @test agree[1] == n
        @test agree[2] == n                                      # the old names keep their values
    end
end

@testitem "connectivity vocabulary: the oracle enumeration is not vacuous" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: the oracle enumeration is not vacuous" begin
        # every rule both accepts and refuses, and the options change decisions: gain on/off,
        # face/full, Local/Simple, Local/ArcOrPair (counted on the oracle over the 2D square scene)
        seen = zeros(Int, 7, 2)
        differ = Dict(:gain => 0, :adjacency => 0, :local_simple => 0, :local_aop => 0, :simple_adj => 0)
        for (old, new) in CASES, cfg in configs(:square, true, 8, old, new)
            r = connectivity_rules(:square, cfg, old, new)
            for i in 1:7
                seen[i, 1 + r[i]] += 1
            end
            differ[:gain] += r[1] != r[3]
            differ[:adjacency] += r[1] != r[2]
            differ[:local_simple] += r[1] != r[6]
            differ[:local_aop] += r[1] != r[5]
            differ[:simple_adj] += r[6] != r[7]
        end
        @test all(>(0), seen)
        @test all(>(0), values(differ))
        # the 3D sample reaches the cases too
        seen3 = zeros(Int, 7, 2)
        for cfg in configs(:cubic, true, 26, 1, 3)
            r = connectivity_rules(:cubic, cfg, 1, 3)
            for i in 1:7
                seen3[i, 1 + r[i]] += 1
            end
        end
        @test all(>(0), seen3)
    end
end

@testitem "connectivity vocabulary: ruling 10, `Local` refuses a full shell" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: ruling 10, `Local()` refuses a full shell" begin
        # 2D: cell 1 owns the 3×3 box around x = (3, 4); the source (5, 4) is medium, distance 2
        # (a NeighborOrder(3) copy). Shell: 8 × cell 1 → one piece, but full.
        σ = connectivity_σ(s -> s[2:4, 3:5] .= 1)
        x, y = (3, 4), (5, 4)
        @test owners(σ, x, :square, (false, false)) == fill(1, 8)
        @test !allows(AliasLocal, σ, x, y)        # the alias is `Local()`; the base accepts
        @test allows(AliasPair, σ, x, y)          # one arc: ArcOrPair accepts (TST)
        r = rulesread(:square, false, σ, x, y)
        @test r == (false, false, false, false, true, false, false)   # every Local refuses
        @test r == connectivity_rules(:square, fill(1, 8), 1, 0)
        @test !allows(VetoDefault, σ, x, y)
        @test allows(VetoPair, σ, x, y)
        @test !allows(VetoSimple, σ, x, y)        # it would make a hole
        # one shell site not cell 1 (the corner (2, 3) medium): no longer full, one piece; the
        # gain test still fails (medium owns no face neighbour of x), so only gain = false accepts
        σ2 = copy(σ); σ2[2, 3] = 0
        r2 = rulesread(:square, false, σ2, x, y)
        @test r2[1] == false && r2[3] == true && r2[4] == true
        # at a closed wall the shell is never full: x = (1, 4), cell 1 owns every in-domain shell
        # site (5 of 8), source (3, 4) medium. One piece → Local(; gain = false) accepts; the gain
        # test refuses (no medium face neighbour); Simple accepts (a wall pocket is no hole).
        σw = connectivity_σ(s -> s[1:2, 3:5] .= 1)
        xw, yw = (1, 4), (3, 4)
        @test count(==(-1), owners(σw, xw, :square, (false, false))) == 3
        rw = rulesread(:square, false, σw, xw, yw)
        @test rw == (false, false, true, true, true, true, true)
    end
end

@testitem "connectivity vocabulary: ruling 10 on hex and 3D" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: ruling 10 on hex and 3D" begin
        # hex 9×8 periodic: cell 1 owns the 6-ring of x = (5, 4); source (7, 4) medium
        σ = zeros(Int32, 9, 8); σ[5, 4] = 1
        foreach(o -> σ[(5, 4) .+ o...] = 1, HEX)
        σ[1, 1] = 2; σ[1, 2] = 3
        r = rulesread(:hex, true, σ, (5, 4), (7, 4))
        @test r == (false, false, false, false, true, false, false)
        # 3D 5³ periodic: cell 1 owns the 26-shell of (3, 3, 3); source (5, 3, 3) medium
        σ3 = zeros(Int32, 5, 5, 5); σ3[2:4, 2:4, 2:4] .= 1; σ3[1, 1, 1] = 2; σ3[1, 1, 5] = 3
        r3 = rulesread(:cubic, true, σ3, (3, 3, 3), (5, 3, 3))
        @test r3 == (false, false, false, false, true, false, false)
    end
end

@testitem "connectivity vocabulary: gain test (ruling 3)" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: gain test (ruling 3)" begin
        # Target x = (4, 4), source (6, 4) at distance 2. Owners of the shell are listed by hand.
        # (a) the losing cell is B (unconstrained): cell 2 at x and (4, 5); cell 1 (A) gains with
        #     only the corner (3, 3). Local and ArcOrPair do not test a B loser; Simple(face) tests
        #     the gaining A cell and refuses (a corner-only gain is a second 4-piece); Simple(full)
        #     accepts (8-connected).
        σ = connectivity_σ(s -> (s[3, 3] = 1; s[4, 4] = 2; s[4, 5] = 2; s[6, 4] = 1))
        @test rulesread(:square, false, σ, (4, 4), (6, 4)) == (true, true, true, true, true, false, true)
        # (b) the same with an A loser (cell 3): Local() refuses (cell 1 owns no face neighbour of
        #     x), Local(; adjacency = :full) accepts (cell 1 owns a shell site), gain = false accepts
        σa = connectivity_σ(s -> (s[3, 3] = 1; s[4, 4] = 3; s[4, 5] = 3; s[6, 4] = 1))
        ra = rulesread(:square, false, σa, (4, 4), (6, 4))
        @test ra[1:4] == (false, true, true, true)
        @test !allows(VetoDefault, σa, (4, 4), (6, 4))
        # (c) the medium as the gaining owner is tested too (D-191): cell 3 (A) at x and (3, 4);
        #     the other face neighbours (4, 3), (5, 4), (4, 5) are cell 2; medium only at corners
        σm = connectivity_σ(s -> (s[4, 4] = 3; s[3, 4] = 3; s[4, 3] = 2; s[5, 4] = 2; s[4, 5] = 2))
        rm = rulesread(:square, false, σm, (4, 4), (6, 4))
        @test rm[1] == false && rm[2] == true && rm[3] == true
        # (d) the medium as the LOSING owner is never checked by Local or ArcOrPair (D-191):
        #     cell 3 gains x from the medium with only a corner contact
        σo = connectivity_σ(s -> (s[3, 3] = 3; s[6, 4] = 3))
        @test rulesread(:square, false, σo, (4, 4), (6, 4))[1:5] == (true, true, true, true, true)
    end
end

@testitem "connectivity vocabulary: ArcOrPair at a closed edge counts the frame as a cell (ruling 5)" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: ArcOrPair at a closed edge counts the frame as a cell (ruling 5)" begin
        # The `arc_or_pair_medium_tests.jl` edge fixture on 7×7 Closed: cell 1 along row 1 (cols 2:6), cell 3 (A) in
        # rows 2:3 (cols 2:6), target (1, 4), source (2, 4). Shell (ternary order (i, j), j outer):
        #   (−1,−1) OUT, (0,−1) 1, (1,−1) 3, (−1,0) OUT, (1,0) 3, (−1,1) OUT, (0,1) 1, (1,1) 3
        #   → arcs 2, cells {1, 3, frame} = 3, medium 0 → REFUSE (D-099 accepted: frame = nothing)
        σ = zeros(Int32, 7, 7); σ[1, 2:6] .= 1; σ[2:3, 2:6] .= 3; σ[7, 7] = 2
        @test owners(σ, (1, 4), :square, (false, false)) == [-1, 1, 3, -1, 3, -1, 1, 3]
        @test !allows(VetoPair, σ, (1, 4), (2, 4))
        @test !allows(AliasPair, σ, (1, 4), (2, 4))       # the alias, the same rule
        # a second cell (2) only at (2, 4): OUT 1 1 OUT 2 OUT 1 1 → arcs 2, cells {1, 2, frame}
        # → refused; with (2, 4) cell 1 instead, one arc → accepted
        σf = zeros(Int32, 7, 7); σf[1, 3:5] .= 1; σf[2, 3] = 1; σf[2, 5] = 1; σf[2, 4] = 2; σf[7, 7] = 3
        own = owners(σf, (1, 4), :square, (false, false))
        @test own == [-1, 1, 1, -1, 2, -1, 1, 1]
        @test !allows(VetoPair, σf, (1, 4), (3, 4))
        σg = copy(σf); σg[2, 4] = 1
        @test allows(VetoPair, σg, (1, 4), (3, 4))
        # the raw counts keep "out of domain is nothing": ring_cells is 2 here (cells 1 and 2),
        # ring_arcs 2, ring_medium 0 (the old-name readback is checked in the enumeration)
        @test oldnames(:square, own, 1) == 2 + 16 * 2 + 256 * 2
    end
end

@testitem "connectivity vocabulary: Simple against the global topology (2D, 7×7, both adjacencies)" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: Simple() against the global topology (2D, 7×7, both adjacencies)" begin
        prob = PottsProblem(RulesSquareClosed(; name = :g), [ownership => connectivity_σ(s -> s[1, 1] = 1), kind => collect(KIND)], (0, 1))
        u = deepcopy(prob.u0); ctx = Potts._host_ctx(prob)
        x, y = (4, 4), (6, 4)
        n = 0; agree = 0; kept = 0
        st = UInt64(0x6367)
        for trial in 1:1500, adding in (false, true)
            dens = 0.3 + 0.4 * ((trial % 5) / 4)
            X = falses(7, 7)
            for I in eachindex(X)
                st = st * 6364136223846793005 + 1442695040888963407
                X[I] = ((st >> 33) % 1000) / 1000 < dens
            end
            X[y...] = adding                      # the source holds `new`: cell 1 when adding
            X[x...] = !adding
            σ = u.ownership
            σ .= ifelse.(X, Int32(1), Int32(0))
            b = connectivity_read(prob, u, ctx, x, y)
            for (bit, adj) in ((6, :face), (7, :full))
                got = (b >> (bit - 1)) & 1 == 0
                A = copy(X); A[x...] = adding
                want = connectivity_topology(X, adj) == connectivity_topology(A, adj)
                n += 1; agree += got == want; kept += want
            end
        end
        @test agree == n
        @test 0.1 * n < kept < 0.9 * n                  # both outcomes occur often
    end
end

@testitem "connectivity vocabulary: build errors and their controls" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: build errors and their controls" begin
        # controls: the valid forms build and run
        @test connectivity_try(:OkVeto, :(@constraint connectivity(A; rule = Local(; gain = false)))) === nothing
        @test connectivity_try(:OkDrive, :(@drive connectivity(A; rule = ArcOrPair(), penalty = E₀))) === nothing
        @test connectivity_try(:OkConnected, :(@constraint connected(old; rule = Simple()) | (old == 0))) === nothing
        @test connectivity_try(:OkPieces, :(@drive copy => 1.0 * pieces(old, shell(target); adjacency = :full))) === nothing
        @test connectivity_try(:OkDistinct, :(@drive copy => 1.0 * distinct(owner[n] for n in Moore(1)(target) if owner[n] != 0))) === nothing
        # a penalty in @constraint: the error names @drive
        e = connectivity_try(:ErrPenalty, :(@constraint connectivity(A; penalty = 5.0)))
        @test e isa ArgumentError && occursin("@drive", msg(e))
        # no penalty in @drive: the error names @constraint
        e = connectivity_try(:ErrNoPenalty, :(@drive connectivity(A)))
        @test e isa ArgumentError && occursin("@constraint", msg(e))
        # Global() builds since global connectivity (amended), in the helper and in connected
        @test connectivity_try(:ErrGlobal, :(@constraint connectivity(A; rule = Global()))) === nothing
        @test connectivity_try(:ErrGlobalC, :(@constraint connected(old; rule = Global()) | (old == 0))) === nothing
        # an unknown rule symbol (unchanged)
        @test connectivity_try(:ErrRule, :(@constraint connectivity(A; rule = :nearby))) isa ArgumentError
        # pieces over a relation other than shell (no custom shells in v1, ruling 8)
        e = connectivity_try(:ErrRel, :(@drive copy => 1.0 * pieces(old, Moore(2)(target))))
        @test e isa ArgumentError && occursin("shell", msg(e))
        e = connectivity_try(:ErrRelGen, :(@drive copy => 1.0 * pieces(n for n in VonNeumann(1)(target) if owner[n] == old)))
        @test e isa ArgumentError && occursin("shell", msg(e))
        # a bad adjacency on the fold
        @test connectivity_try(:ErrAdj, :(@drive copy => 1.0 * pieces(old, shell(target); adjacency = :edge))) isa ArgumentError
        # `components` no longer builds (ruling 6); the replacement does (control above)
        @test connectivity_try(:ErrComponents, :(@drive copy => 100.0 * (components(old; scope = Global()) > 1))) !== nothing
    end
end

@testitem "connectivity vocabulary: the penalty form is penalty × [the veto form refuses], and follows the parameter" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: the penalty form is penalty × [the veto form refuses], and follows the parameter" begin
        σ = zeros(Int32, 7, 7); σ[2:6, 4] .= 1; σ[4, 3] = 2; σ[7, 7] = 3      # a bar of 1, cell 2 beside it
        prob = PottsProblem(PenaltyParam(; name = :q), [ownership => σ, kind => collect(KIND)], (0, 1))
        ctx = Potts._host_ctx(prob)
        @test connectivity_read(prob, prob.u0, ctx, (4, 4), (4, 3)) == 50          # splits the bar: charged E₀
        @test connectivity_read(prob, prob.u0, ctx, (2, 4), (2, 3)) == 0           # an end of the bar: free
        prob0 = remake(prob; p = [:E₀ => 0.0])
        @test connectivity_read(prob0, prob0.u0, ctx, (4, 4), (4, 3)) == 0
        @test !allows(VetoPair, σ, (4, 4), (4, 3)) && allows(VetoPair, σ, (2, 4), (2, 3))
    end
end

@testitem "connectivity vocabulary: alias" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "connectivity vocabulary: alias $label" for (label, stmts) in ALIASES
        Ms = map(enumerate(stmts)) do (i, s)
            name = Symbol("Alias", hash(label) % 100000, "_", i)
            Core.eval(
                @__MODULE__, quote
                    @potts_model $name begin
                        @kinds medium A B
                        @lattice Lattice((8, 8); neighborhood = Moore(1))
                        @energy cells => (volume - 9)^2
                        $s
                        @sweep Metropolis(; temperature = 1.0)
                    end
                end
            )
            getfield(@__MODULE__, name)
        end
        codes = map(M -> Base.invokelatest(code, M), Ms)
        fps = map(M -> Base.invokelatest(connectivity_fp, M), Ms)
        @test all(==(codes[1]), codes)
        @test all(==(fps[1]), fps)
    end
end

@testitem "connectivity vocabulary: Akeeb's constraint is unchanged under its VonNeumann(1) proposals" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # Akeeb: VonNeumann(1) proposals, so the gain test is vacuous and a full shell unreachable
    @testset "connectivity vocabulary: Akeeb's constraint is unchanged under its VonNeumann(1) proposals" begin
        op = akeeb_state(; lattice = (99, 60))
        prob = PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), op, (0, 10); capacity = 1000)
        u = solve(prob, SequentialCPM(; proposal = VonNeumann(1))).u[end]
        ctx = Potts._host_ctx(prob)
        lat = prob.lattice
        per = (true, false)                                  # (Periodic(), Closed())
        n = agree = vacuous = 0
        nrefuse = 0
        for I in CartesianIndices(u.ownership), d in ((1, 0), (-1, 0), (0, 1), (0, -1))
            x = Tuple(I)
            y = (mod1(x[1] + d[1], 99), x[2] + d[2])
            1 <= y[2] <= 60 || continue
            old, new = Int(u.ownership[x...]), Int(u.ownership[y...])
            old == new && continue
            own = owners(u.ownership, x, :square, per)
            # Local() with the defaults, every cell constrained, plus no_extinction
            want = old == 0 || (connectivity_local(:square, own, old, new) && u.cell.volume[old] > 1)
            prop = CorePotts.Proposal(CorePotts.linear_index(lat, x), CorePotts.linear_index(lat, y), x, 1, u.ownership[x...], u.ownership[y...])
            n += 1
            agree += prob.f.constraint(u, prob.p, prop, ctx) == want
            # the old rule (gain off, full shell accepted) decides the same
            vacuous += (old == 0 || connectivity_local(:square, own, old, new; gain = false)) ==
                (old == 0 || connectivity_local(:square, own, old, new))
            nrefuse += !want
        end
        @test agree == n
        @test vacuous == n
        @test n > 1000 && nrefuse > 0
    end
end

@testitem "gain-side control, confluent tissue" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "gain-side control, confluent tissue $(prop)" for prop in (Moore(1), NeighborOrder(2), NeighborOrder(3))
        splits = Dict{Symbol, Int}()
        for (label, M) in ((:gain, NcLocal), (:nogain, NcNoGain))
            s = 0
            for seed in 1:3
                p = PottsProblem(M(; name = :t), [ownership => connectivity_tissue(), kind => fill(:A, 16)], (0, 100); seed)
                sol = solve(p, SequentialCPM(; proposal = prop); saveat = 10:10:100)
                s += count(u -> any(c -> connectivity_split(u.ownership, c), 1:16), sol.u)
            end
            splits[label] = s
        end
        @test splits[:gain] == 0           # Local(): no corner-only or detached gain, no split
        @test splits[:nogain] >= 10        # control: measured 26 (Moore(1), NeighborOrder(2)) and 30 of 30
    end
end

@testitem "hole control, one adhesive cell in medium" setup = [ConnectivityVocabularySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hole control, one adhesive cell in medium $(prop)" for prop in (Moore(1), NeighborOrder(3))
        σ0 = zeros(Int32, 24, 24); σ0[9:16, 9:16] .= 1
        runs(M) = [
            solve(
                remake(
                    PottsProblem(M(; name = :h), [ownership => σ0, kind => [:A]], (0, 100); seed),
                    p = [:T => 6.0, :V => 64.0, :J => [0.0 -1.0; -1.0 4.0]]
                ),
                SequentialCPM(; proposal = prop); saveat = 10:10:100
            ) for seed in 1:3
        ]
        holes_local = sum(count(u -> holes(u.ownership, 1) > 0, sol.u) for sol in runs(NcLocal))
        @test holes_local >= 10            # control: Local() lets holes form (measured 30 and 29 of 30)
        for (M, eight) in ((NcSimple, false), (NcSimpleFull, true))
            sols = runs(M)
            @test sum(count(u -> holes(u.ownership, 1; eight) > 0, sol.u) for sol in sols) == 0
            @test sum(count(u -> connectivity_split(u.ownership, 1; eight), sol.u) for sol in sols) == 0
            @test all(sol -> sol.u[end].ownership != σ0, sols)        # non-vacuous: the cell moved
        end
    end
end
