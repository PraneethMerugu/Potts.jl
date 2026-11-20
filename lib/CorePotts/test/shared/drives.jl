# Definitions of drives_tests.jl that other test files use.
"""Independent check: the owner's sites in the Moore neighbourhood of x (minus x) form one
face-connected component (flood fill over explicit coordinates); none at all is not one."""
function brute_local(σ, lat::Lattice{N}, x, a) where {N}
    nb = [o for o in Iterators.product(ntuple(_ -> -1:1, N)...) if any(!=(0), o)]
    own = Set{NTuple{N, Int}}()
    for o in nb
        inside, y = shift(lat, x, Int32.(o))
        inside && σ[linear_index(lat, y)] == a && push!(own, o)
    end
    isempty(own) && return false
    seen = Set([first(own)]); stack = [first(own)]
    while !isempty(stack)
        o = pop!(stack)
        for d in 1:N, s in (-1, 1)
            q = ntuple(k -> k == d ? o[k] + s : o[k], N)
            (q in own && !(q in seen)) && (push!(seen, q); push!(stack, q))
        end
    end
    return length(seen) == length(own)
end

"""Number of face-connected components of cell c (global)."""
function components(σ, lat::Lattice{N}, c) where {N}
    sites = Set(i for i in 1:nsites(lat) if σ[i] == c)
    n = 0
    vn = relation(VonNeumann(1), lat)
    while !isempty(sites)
        n += 1
        stack = [pop!(sites)]
        while !isempty(stack)
            i = pop!(stack)
            for off in vn.offsets
                inside, y = shift(lat, coordinates(lat, i), off)
                j = linear_index(lat, y)
                (inside && j in sites) && (delete!(sites, j); push!(stack, j))
            end
        end
    end
    return n
end

# A custom `track` (CPMFunction's hook): the effective ΔH, bias included.
struct EffectiveTrack end
(::EffectiveTrack)(st, p, prop, ctx, dH) = dH - p.T * p.b * (prop.new == 0 ? -1.0 : 1.0)
CorePotts.track_eltype(::EffectiveTrack) = Float64
# a custom track without `track_eltype`: fine sequentially, a clear error on the checkerboard
struct UntypedTrack end
(::UntypedTrack)(st, p, prop, ctx, dH) = dH
