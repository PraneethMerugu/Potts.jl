# Definitions of coarse_tests.jl that other test files use (moved here by TS1b).
using LatticeFields.IR: print_program
using LinearAlgebra: I
using Random: Xoshiro, randperm

const CK = 4
const CDIMS = (16, 16)
cdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
cmsg(f) = try
    f(); ""
catch err
    err isa ArgumentError ? err.msg : sprint(showerror, err)
end
# a fine kind map whose every 4×4 block has a kind on 10 of its 16 sites (a strict majority),
# the others drawn from the remaining kinds: the Majority fold of `q == k` is the block's kind
function ckinds(seed; dims = CDIMS, k = CK)
    rng = Xoshiro(seed)
    Q = zeros(Int32, dims)
    Qc = Int32[rand(rng, 0:3) for _ in 1:(dims[1] ÷ k), _ in 1:(dims[2] ÷ k)]
    for J in CartesianIndices(Qc)
        sites = [CartesianIndex((J[1] - 1) * k + i, (J[2] - 1) * k + j) for i in 1:k for j in 1:k]
        own = randperm(rng, k^2)
        for (n, s) in enumerate(sites)
            Q[s] = own[n] <= 10 ? Qc[J] : rand(rng, setdiff(0:3, Qc[J]))
        end
    end
    return Q, Qc
end
# the block mean of a fine array (the children in the IR's order: axis 1 fastest)
function cmean(A, k = CK)
    nc = size(A) .÷ k
    return [sum(A[(I[1] - 1) * k + i, (I[2] - 1) * k + j] for j in 1:k for i in 1:k) / k^2 for I in CartesianIndices(nc)]
end
# the owned problem of `sys` on `dims` with inputs `ins`
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
cown(sys, dims; T = Float64, ins = (), kw...) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T, kw...);
    inputs = collect(Pair, ins)))

# One system with the features a coarse field must carry: a face coefficient of the coordinates,
# a decay at a kind, a source at a kind, a moving masked Dirichlet, a Robin face, a Dirichlet face
# whose value reads the coordinates, a face value that reads an input (a field face), a table at
# the kind and a source from a real input. With `hand` (the twin), the kind expressions are real
# inputs that hold their block means: `f2` for `ismember(q, (2,))`, `f1` for `q == 1`, `sv` for
# `at(cSv, q + 1)` (F4-15: a kind expression folds by its mean, as a real input does)
@parameters cD = 0.02 ckd = 3.0 cs = 0.5 cSv[1:4] = [1.0, 2.0, 5.0, 3.0]
@variables f1(..) [input = true, bounds = (0, 1)] f2(..) [input = true, bounds = (0, 1)] sv(..) [input = true, bounds = (1, 5)]
function csys(c, q, g; steady = false, hand = false)
    ce, qe, ge = c(t, x, y), q(t, x, y), g(t, x, y)
    k2, k1, tv = hand ? (f2(t, x, y), f1(t, x, y), sv(t, x, y)) : (ismember(qe, (2,)), qe == 1, at(cSv, qe + 1))
    rhs = cD * DivKGrad(:harmonic)(1 + x, ce) - ckd * ce * k2 + cs * k1 + 0.1 * tv + 0.05 * ge
    eqs = steady ? [0 ~ rhs] : [D(ce) ~ rhs]
    bcs = [ce ~ masked(qe == 3, 1.0), 0.5 * c(t, 0, y) - 0.1 * Differential(x)(c(t, 0, y)) ~ 0.3,
        c(t, x, 1) ~ x, c(t, 1, y) ~ g(t, 1, y)]
    steady || push!(bcs, c(0, x, y) ~ x * y)
    dvs = hand ? [ce, qe, ge, f1(t, x, y), f2(t, x, y), sv(t, x, y)] : [ce, qe, ge]
    return PDESystem(eqs, bcs, cdom(), [t, x, y], dvs, [cD, ckd, cs, cSv]; name = :cs)
end
# the hand twin's inputs for the fine kind map `Q`: the block means of the kind expressions, and
# the block's majority kind for the mask (`ckinds` gives every block a strict majority)
chand(Q, Qc) = [f1(t, x, y) => cmean(Float64.(Q .== 1)), f2(t, x, y) => cmean(Float64.(Q .== 2)),
    sv(t, x, y) => cmean(Float64[1.0, 2.0, 5.0, 3.0][Q .+ 1])]
# equal to rounding: the fold multiplies the block mean last in a product, the twin in its term order
capprox(a, b; rtol = 1e-13) = isapprox(a, b; rtol) || (println("coarse twin: max |Δ| ", maximum(abs, a .- b)); false)
const CQ1, CQ1c = ckinds(11)
const CQ2, CQ2c = ckinds(12)
# a real input whose block sums are exact (integers): the mean is exact in both problems
const CG = Float64[(3i + 5j) % 7 for i in 1:16, j in 1:16]

# a kind map with ties (review r1 S1): blocks of 8 P + 8 Q (owner P: the smaller kind), 9 P + 7 Q,
# 6 P + 6 Q + 4 medium, 16 P, 8 medium + 8 Q (owner Q: the medium loses a tie), 16 medium,
# 7 Q + 9 N, 8 Q + 8 N, two three-way mixes, and random blocks
function ctiekinds(; seed = 31)
    rng = Xoshiro(seed)
    mixes = [[1 => 8, 2 => 8], [1 => 9, 2 => 7], [1 => 6, 2 => 6, 0 => 4], [1 => 16], [0 => 8, 2 => 8], [0 => 16],
        [2 => 7, 3 => 9], [2 => 8, 3 => 8], [3 => 5, 1 => 5, 0 => 6], [0 => 5, 3 => 5, 2 => 6]]
    Q = zeros(Int32, 16, 16)
    for (b, J) in enumerate(CartesianIndices((4, 4)))
        vals = b <= length(mixes) ? reduce(vcat, [fill(Int32(v), n) for (v, n) in mixes[b]]) : Int32[rand(rng, 0:3) for _ in 1:16]
        vals = vals[randperm(rng, 16)]
        for (n, (i, j)) in enumerate((i, j) for j in 1:4 for i in 1:4)
            Q[(J[1] - 1) * 4 + i, (J[2] - 1) * 4 + j] = vals[n]
        end
    end
    return Q
end
const CQT = ctiekinds()

# the coarse problem and its hand-coarsened twin (a 4×4 grid with the folded inputs)
function ctwins(; steady = false, T = Float64, storage = nothing, backend = nothing)
    nm = Symbol(:ctw, steady ? :s : :r, T, storage === nothing ? "" : storage)
    c = Symbolics.variable(nm; T = SymbolicUtils.FnType{Tuple, Real, Nothing})
    c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(c), LatticePDE.LatticeLevel, Coarse(CK)))
    storage === nothing || (c = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(c), LatticePDE.LatticeStorage, storage)))
    ch = Symbolics.variable(Symbol(nm, :h); T = SymbolicUtils.FnType{Tuple, Real, Nothing})
    storage === nothing || (ch = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(ch), LatticePDE.LatticeStorage, storage)))
    q, g = @variables q(..)::Int32 [input = true] g(..) [input = true]
    kw = backend === nothing ? (;) : (; backend)
    pc = cown(csys(c, q, g; steady), CDIMS; T, ins = [q(t, x, y) => CQ1, g(t, x, y) => CG], kw...)
    ph = cown(csys(ch, q, g; steady, hand = true), CDIMS .÷ CK; T,
        ins = vcat([q(t, x, y) => CQ1c, g(t, x, y) => cmean(CG)], chand(CQ1, CQ1c)), kw...)
    return pc, ph, (c, ch, q, g)
end
