# The x1 bit-exactness experiment (pass 3, P3-gates §1) ported onto generated FV kernels:
# K coupled species, `u_k ← u_k + h (a_k Δu_k − b_k u_k + Σ_T p u_i u_j)` on a periodic
# grid. On identical inputs, outputs are compared as bit patterns (`-0.0 ≠ 0.0`) across
#   layout       K separate fields  vs  one K-component field (planes);
#   store order  interleaved stores vs  every value first, stores last;
#   fusion       the cost-model plan (fused) vs one launch per species (split);
#   wrapper      Exec's host executor vs the padded oracle loop (every `run_step!`), and
#                the device vs the host executor (problems_device.jl).
# Negative control: one input element one ulp up changes the output.
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
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1 +
                                                                               K * (2 + T))
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
    (0.01, (x for k in 1:K for x in (1.0 + 0.1k, 0.3, (0.05 * j for j in 1:T)...))...)
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
    out = layout == :sep ? [copy(current(st, s, "u$k")) for k in 1:K] :
          collect(Iterators.partition(copy(current(st, s, "u")), length(X[1])))
    return reduce(vcat, map(o -> reinterpret(UInt32, collect(o)), out))
end

stores_last = merge(LOWERING, (;
    order = c -> Int32[loads_first(c); [s.value for s in c.k.stores]]))

@testset "x1 port: generated FV kernels are bit-exact ($(length(dims))D K=$K T=$T)" for (dims, K, T) in (
    ((24, 20), 4, 0), ((24, 20), 4, 3), ((24, 20), 8, 3), ((10, 9, 8), 4, 3), (
    (10, 9, 8), 8, 0))
    X, P = inputs(dims, K), speciesP(K, T)
    one(layout; stages = LOWERING) = (
        b = build(species(dims, K, T; layout); stages); run_species(b..., X, P, layout))
    ref = one(:sep)
    @test one(:slab) == ref                                           # layout
    @test one(:sep; stages = stores_last) == ref                      # store order
    @test one(:slab; stages = stores_last) == ref
    # fusion: the planner's fused launches vs one launch per species (same order semantics)
    s, fused = build(species(dims, K, T; kernels = :each))
    _, split = build(species(dims, K, T; kernels = :each); fuse = false)
    @test length(split.launches) == K && length(fused.launches) < K
    @test run_species(s, fused, X, P, :sep) == run_species(s, split, X, P, :sep)
    # negative control: one input element one ulp up
    Xp = deepcopy(X)
    j = length(X[1]) ÷ 2 + 7
    Xp[1][j] = nextfloat(Xp[1][j])
    b = build(species(dims, K, T))
    d = count(run_species(b..., Xp, P, :sep) .!= ref)
    @test d > 0
end
