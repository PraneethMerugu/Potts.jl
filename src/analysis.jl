# Model-agnostic measurements of a state beside `total_energy` (D-139): the boundary length
# split by kind pair, and the annealed copy of a state (its copy dynamics at T = 0).

"""
    Potts.boundary_lengths(prob, u = prob.u0; relation = nothing)

The boundary length of state `u` split by kind pair, as a
`Dict{Tuple{Symbol, Symbol}, <:Real}`.

A bond is an unordered pair of sites `{i, i + o}`, with `o` an offset of `relation` (a
relation such as `Moore(1)`, resolved on the problem's lattice; `nothing` means the
problem's contact relation). The neighbour must lie inside the lattice and its domain:
periodic axes wrap, closed axes and the domain edge do not. A bond counts when its two
owners differ. Each bond counts once, with the relation's weight (1 for an unweighted
relation, so the counts are integers).

The bond is credited to the kinds of its two owners. The medium has the model's first kind.
The keys are `(a, b)`, with kind `a` declared no later than `b` in `@kinds`. Every pair is
a key, zeros included, and `(medium, medium)` is always 0. Two cells of one kind count
under `(k, k)`. Kind classes are not keys.

For a model whose only energy is `contacts => J[kind, kind′]` (times `weight` for a
weighted relation), `Σ J[a, b] · L[(a, b)] == total_energy(prob, u)`.

Square, hexagonal and 3D lattices; `u` must be a host state.
"""
function boundary_lengths(prob::CorePotts.PottsProblem, u = prob.u0; relation = nothing)
    info = prob.f.sys
    info isa PottsModelInfo || throw(ArgumentError("boundary_lengths: not a problem of a Potts model"))
    names = getfield(info.csys.sys, :kinds)
    r = relation === nothing ? prob.contact : CorePotts.relation(relation, prob.lattice)
    CorePotts.is_symmetric(r) || throw(ArgumentError("boundary_lengths: the relation is not symmetric " *
                                                     "(each offset needs its negation with the same weight), so its bonds are not unordered pairs"))
    # each unordered pair once: the offsets whose first non-zero component is positive
    forward = [k for k in 1:length(r) if _is_forward(r.offsets[k])]
    acc = _bond_lengths(u.σ, u.cell.kind, prob.lattice, r, forward, length(names))
    return Dict((names[a], names[b]) => acc[a, b] for a in eachindex(names) for b in a:length(names))
end

_is_forward(o) = (j = findfirst(!iszero, o); j !== nothing && o[j] > 0)

# the bond lengths by kind index (1 = medium), accumulated in the upper triangle
function _bond_lengths(σ, kinds, lat, r, forward, nkinds)
    W = r.weights === nothing ? Int : Float64
    acc = zeros(W, nkinds, nkinds)
    for i in eachindex(σ)
        a = σ[i]
        x = CorePotts.coordinates(lat, i)
        for k in forward
            inside, y = CorePotts.shift(lat, x, r.offsets[k])
            inside || continue
            b = σ[CorePotts.linear_index(lat, y)]
            a == b && continue
            ka, kb = _kind_slot(kinds, a), _kind_slot(kinds, b)
            ka > kb && ((ka, kb) = (kb, ka))
            acc[ka, kb] += W(CorePotts.weight(r, k))
        end
    end
    return acc
end
_kind_slot(kinds, c) = c == 0 ? 1 : Int(kinds[c]) + 1

# The copy temperature of `anneal`: 0 in the type of the model's own temperature.
struct _ZeroTemperature{F}
    temperature::F
end
@inline (z::_ZeroTemperature)(st, p, prop, ctx) = zero(z.temperature(st, p, prop, ctx))

"""
    Potts.anneal(prob, u = prob.u0; mcs, seed = 0, alg = SequentialCPM())

The annealed copy of state `u`: a new state, `u` after `mcs` MCS of `prob`'s copy dynamics
with the copy temperature 0 for every proposal, whatever the model's temperature expression.

Everything else is the run's own: the parameters `prob.p`, the lattice and relations, the
proposal, the acceptance law (at T ≤ 0 it accepts ΔH below the offset, and ties with
probability ½) and the full ΔH, drives included. A bias term vanishes at T = 0. Only copy
attempts run: no MCS phases, rules, lifecycle events, ODE or field steps, so every other
variable keeps its value in `u`.

`u` and `prob` are not modified. The result is deterministic in `(prob, u, mcs, seed, alg)`.
`mcs = 0` returns an equal copy of `u`; `mcs < 0` is an `ArgumentError`. Measure the result
like any state, e.g. `boundary_lengths(prob, anneal(prob, u; mcs = 32))`.
"""
function anneal(prob::CorePotts.PottsProblem, u = prob.u0; mcs::Integer, seed::Integer = 0,
        alg = CorePotts.SequentialCPM())
    mcs >= 0 || throw(ArgumentError("anneal: `mcs` must be non-negative, got $mcs"))
    f = prob.f
    cold = CorePotts.CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads,
        temperature = _ZeroTemperature(f.temperature), f.bias, f.acceptance, f.footprint,
        f.fingerprint, f.sys)                       # no phases, no lifecycle
    q = SciMLBase.remake(prob; f = cold, u0 = u, tspan = (0, Int(mcs)), seed)
    return solve(q, alg; save_start = false).u[end]
end
