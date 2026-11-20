# Definitions of problems/bit_exact_kernels_tests.jl that other test files use.
using Random: Xoshiro
using LatticeFields.Compile: loads_first

"""
Coupling terms `(i, j)` per species, drawn once.
"""
function couplings(K, T; seed = 7)
    (rng = Xoshiro(seed); [[(rand(rng, 1:K), rand(rng, 1:K)) for _ in 1:T] for _ in 1:K])
end

offsets(N) = N == 2 ? OFFS2 : OFFS3

"""
The rate of species `k` from loads `c(j; offset)`; parameter 1 is `h`, then per species
`a_k, b_k, p_k1 … p_kT`.
"""
function species_update(kb, c, k, K, T, cpl, N)
    base = 1 + (k - 1) * (2 + T)
    ck = c(k, ntuple(_ -> 0, N))
    lap = sum(c(k, o) for o in offsets(N)) - 2N * ck
    r = param(kb, base + 1) * lap - param(kb, base + 2) * ck
    for (t, (i, j)) in enumerate(cpl[k])
        r = r + param(kb, base + 2 + t) * c(i, ntuple(_ -> 0, N)) * c(j, ntuple(_ -> 0, N))
    end
    return ck + param(kb, 1) * r
end

"""
K species on `dims`. `layout = :sep` (K fields) or `:slab` (one K-component field);
`kernels = :one` (one kernel stores every species: every read is the old value) or `:each`
(one kernel per species, ordered and fused by the planner).
"""
function species(dims::NTuple{N}, K, T; layout = :sep, kernels = :one) where {N}
    pb = ProgramBuilder(
        Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1 +
            K * (2 + T)
    )
    cpl = couplings(K, T)
    if layout == :sep
        fs = [field!(pb, "u$k"; buffers = 2) for k in 1:K]
        ld = kb -> (j, o) -> load(kb, fs[j]; offset = o)
        st = (kb, k, v) -> store(kb, fs[k], v)
    else
        f = field!(pb, "u"; shape = [K], buffers = 2)
        ld = kb -> (j, o) -> load(kb, f; comp = j, offset = o)
        st = (kb, k, v) -> store(kb, f, v; comp = k)
    end
    if kernels == :one
        kb = kernel(pb)
        foreach(k -> st(kb, k, species_update(kb, ld(kb), k, K, T, cpl, N)), 1:K)
        add!(pb, kb, "species")
    else
        for k in 1:K
            kb = kernel(pb)
            st(kb, k, species_update(kb, ld(kb), k, K, T, cpl, N))
            add!(pb, kb, "s$(lpad(k, 2, '0'))")
        end
    end
    return pb
end

function speciesP(K, T)
    return (0.01, (x for k in 1:K for x in (1.0 + 0.1k, 0.3, (0.05 * j for j in 1:T)...))...)
end
function inputs(dims, K; seed = 11)
    (rng = Xoshiro(seed); [rand(rng, Float32, prod(dims)) .* 0.1f0 for _ in 1:K])
end

"""
Run one step; return the K outputs (flat) of species 1:K.
"""
function run_species(s, sp, X, P, layout)
    st = HostStore(s)
    K = length(X)
    if layout == :sep
        foreach(k -> copyto!(current(st, s, "u$k"), X[k]), 1:K)
    else
        copyto!(current(st, s, "u"), reduce(vcat, X))
    end
    run_step!(s, sp, st, P)
    out = if layout == :sep
        [copy(current(st, s, "u$k")) for k in 1:K]
    else
        collect(Iterators.partition(copy(current(st, s, "u")), length(X[1])))
    end
    return reduce(vcat, map(o -> reinterpret(UInt32, collect(o)), out))
end

stores_last = merge(
    LOWERING, (;
        order = c -> Int32[loads_first(c); [s.value for s in c.k.stores]],
    )
)
