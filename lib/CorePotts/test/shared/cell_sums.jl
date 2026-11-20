# Definitions of cell_sums_tests.jl that other test files use.
using CorePotts: CellReduce, reduce_scratch, REDUCE_STATUS, STATUS_SUM_RANGE

# a stand-in for a backend without 64-bit atomics (Metal; `CorePotts._atomic64` is false
# there)
struct CS_NoAtomic64 <: CorePotts.KernelAbstractions.GPU end
CorePotts._atomic64(::CS_NoAtomic64) = false

# a state of `n` cells over `σ` with a site array `v` and a float column `x` of type `T`
function cs_state(σ, v, n; T = Float64)
    sc = reduce_scratch(n)
    return initial_state(
        σ, ones(Int32, n); site = (; v),
        cell = (; x = zeros(T, n), sc.cell...), model = sc.model
    )
end
const CS_SUM = CellReduce((:cell, :x), (st, p, ctx, key, mcs, i) -> st.site.v[i])
function cs_run!(st, ph = CS_SUM; backend = CPU())
    (ph(st, nothing, (;), RNGKey(0), 0, backend); copy(st.cell.x))
end

# values with order-dependent float sums: magnitudes over 12 decades, both signs
function cs_values(dims; seed = 3)
    rng = Random.Xoshiro(seed)
    return [(rand(rng) - 0.3) * 10.0^rand(rng, -6:6) for _ in CartesianIndices(dims)]
end
# cells as vertical stripes of width 4, a medium column every 9th
function cs_owners(dims)
    σ = zeros(Int32, dims)
    for I in CartesianIndices(dims)
        I[1] % 9 == 0 || (σ[I] = Int32(1 + (I[1] - 1) ÷ 4 + 64 * ((I[2] - 1) ÷ 16)))
    end
    return σ
end

# the old float CAS loop of `max`/`min` (before integer cell sums): writes `v`, stops on
# `op(old, v) == old`; its compare-and-swap compares bits (`===`)
function cs_old_max!(a, c, v)
    old = a[c]
    while max(old, v) != old
        a[c] === old && (a[c] = v; break)
        old = a[c]
    end
    return
end
