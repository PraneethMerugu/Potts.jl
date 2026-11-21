"""
    OpenVTChain(; name, lattice = (150, 5), λ = 2.0, T = 20.0, A = 50.0, A_c = 25.0,
        J = [0 10 10; 10 20 20; 10 20 20])

Build the mechanical calibration of the OpenVT monolayer benchmark (the manuscript's §2.2,
Fig 2 and Table S5): a chain of cells on a thin periodic strip, compressed during a burn-in
and then released, so that the chain relaxes toward its rest length.

The time a chain of 11 cells takes to reach 90% of its relaxed width defines the
benchmark's time unit T in MCS (T = 155 MCS at λ = 2, Table S5; see
`docs/design/research/model-specs/15_openvt_monolayer.md`). The shape of the relaxation is
compared with an overdamped spring–dashpot chain ([`spring_dashpot_width`](@ref)).

- Kinds `medium`, `compressed` and `relaxed`. A compressed cell has the area target `A_c`,
  a relaxed cell `A`: energies `λ (volume − A_c)²` and `λ (volume − A)²`.
- Adhesion `J[kind, neighbor_kind]`: cell–cell 20, cell–medium 10 (Table S1).
- `A = 50` is one cell diameter (CD = 10 sites) times the 5-row strip.
- The lattice is periodic on both axes with `Moore(1)` contacts, and proposals are
  `Moore(1)`. On a 5-row strip each cell spans the strip, so the chain is one-dimensional.
- No growth and no division.

Seed with [`openvt_chain`](@ref) and release with [`openvt_release`](@ref), which sets
`A_c := A` (a parameter change, no extra mechanism). Measure with
`PottsModels.Analysis.chain_width`.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (150, 5)`: the lattice size (structural); use `(250, 5)` for
  `openvt_chain(21)`.
- `λ = 2.0`: the area strength.
- `T = 20.0`: the Metropolis temperature.
- `A = 50.0`: the target area of a relaxed cell.
- `A_c = 25.0`: the target area of a compressed cell.
- `J = [0 10 10; 10 20 20; 10 20 20]`: the contact energies over
  (medium, compressed, relaxed).

# Returns
- `PottsSystem`: the model.

# Examples
```julia
using PottsModels, Potts
sys = OpenVTChain(; name = :chain, λ = 2.0)
prob = PottsProblem(sys, openvt_chain(11), (0, 100 + 775); seed = 1)
sol = solve(prob, SequentialCPM(; proposal = Moore(1)); callback = openvt_release(100),
    saveat = 100:875)
w = [PottsModels.Analysis.chain_width(u.ownership) for u in sol.u]  # w[1] = 5 CD at t = 0
```

See also [`openvt_chain`](@ref), [`openvt_release`](@ref), [`spring_dashpot_width`](@ref).
"""
@potts_model OpenVTChain begin
    @structural_parameters begin
        lattice = (150, 5)
    end
    @kinds medium compressed relaxed
    @parameters begin
        λ = 2.0
        T = 20.0
        A = 50.0
        A_c = 25.0
        J[kind, kind] = [0.0 10.0 10.0; 10.0 20.0 20.0; 10.0 20.0 20.0]
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(compressed) => λ * (volume - A_c)^2
        cells(relaxed) => λ * (volume - A)^2
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = T)
end

"""
    openvt_chain(n = 11) -> Vector{Pair}

Return an initial chain of [`OpenVTChain`](@ref), placed as in the benchmark's Morpheus
models (`Relaxation_11cells_Morpheus_V5.xml` and its 11+10 variant).

- `n = 11`: on a 150 × 5 lattice, 11 `compressed` 5 × 5 cells packed edge to edge at
  `x ∈ 49:103` (half a cell diameter each, so the chain's width is 5 CD).
- `n = 21`: on a 250 × 5 lattice, the same 11 compressed cells at `x ∈ 99:153` with 5
  `relaxed` 10 × 5 cells flush on each side (`x ∈ 49:98` and `154:203`).

Cell numbers run left to right (for `n = 21`: relaxed 1–5, compressed 6–16, relaxed
17–21). The first compressed column is `L ÷ 2 − 26` for a lattice of length `L`,
Morpheus's box origin `L/2 − 27` (0-based), which centers the 11-chain within one site.

# Arguments
- `n::Integer = 11`: the number of cells, 11 or 21. Throws an `ArgumentError` otherwise.

# Returns
- `Vector{Pair}`: the operating point `[ownership => σ, kind => kinds]`.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> u0 = openvt_chain(21);

julia> size(u0[1].second), length(u0[2].second)
((250, 5), 21)
```

See also [`OpenVTChain`](@ref), [`openvt_release`](@ref).
"""
function openvt_chain(n::Integer = 11)
    n in (11, 21) || throw(ArgumentError("openvt_chain: n must be 11 or 21, got $n"))
    L = n == 11 ? 150 : 250
    x0 = L ÷ 2 - 26                                         # first compressed column
    core = Tiling((5, 5); region = (x0:(x0 + 54), 1:5), kinds = [:compressed])
    n == 11 && return layout(core, (L, 5))
    left = Tiling((10, 5); region = ((x0 - 50):(x0 - 1), 1:5), kinds = [:relaxed])
    right = Tiling((10, 5); region = ((x0 + 55):(x0 + 104), 1:5), kinds = [:relaxed])
    return layout(overlay(left, core, right), (L, 5))
end

"""
    openvt_release(at = 100) -> DiscreteCallback

Return a callback that releases the compressed cells of [`OpenVTChain`](@ref): at the end
of MCS `at` it sets the parameter `A_c` to `A`.

The state saved at MCS `at` is the end of the burn-in and the relaxation's t = 0; the first
relaxing MCS is `at + 1`. The callback saves no state of its own.

# Arguments
- `at::Integer = 100`: the last MCS of the burn-in.

# Returns
- `DiscreteCallback`: pass it as `solve(prob, alg; callback = openvt_release(100))`.

# Examples
```jldoctest
julia> using PottsModels

julia> openvt_release(50) isa PottsModels.DiscreteCallback
true
```

See also [`OpenVTChain`](@ref), [`openvt_chain`](@ref).
"""
function openvt_release(at::Integer = 100)
    # a parameter write: the state is unchanged, so no save of its own (`saveat` saves MCS
    # `at`)
    return DiscreteCallback(
        (u, t, integ) -> t == at, integ -> (integ.ps[:A_c] = integ.ps[:A]; nothing);
        save_positions = (false, false)
    )
end

"""
    spring_dashpot_width(t; n = 11, rate = 18.2816647214633, pinned = false) -> Float64

Return the width of the overdamped spring–dashpot chain that the OpenVT calibration
compares with (`relaxation_exact.m` of the benchmark).

The chain has `n` beads at `x_i(0) = i/2` (in CD, `i = 0 … n−1`), unit rest length, and

    ẋ_i = rate · [(x_{i+1} − x_i − 1) − (x_i − x_{i−1} − 1)],

with both ends free (or `x_0` held fixed with `pinned = true`). The width is
`x_{n−1}(t) − x_0(t)` in CD, with `t` in units of the benchmark's T. It starts at
`(n − 1)/2` and approaches `n − 1` from below.

The solution is the exact eigenmode expansion of the chain: the free chain's Laplacian has
the modes `cos((i + ½) kπ/n)` with rates `2 − 2cos(kπ/n)`, and the chain pinned at `x_0`
has `sin(i θ_k)`, `θ_k = (2k − 1)π/(2n − 1)`, with rates `2 − 2cos θ_k`.

# Arguments
- `t::Real`: the time, in units of T.

# Keywords
- `n::Integer = 11`: the number of beads, at least 2. Throws an `ArgumentError` otherwise.
- `rate::Real = 18.2816647214633`: `k/η`. The default is solved from `w(1) = 9` for 11
  beads, so `spring_dashpot_width(1.0) ≈ 9`.
- `pinned::Bool = false`: hold `x_0` fixed.

# Returns
- `Float64`: the width, in CD.

# Examples
```jldoctest
julia> using PottsModels

julia> spring_dashpot_width(0.0) ≈ 5
true

julia> isapprox(spring_dashpot_width(1.0), 9; atol = 1e-6)
true
```

See also [`OpenVTChain`](@ref).
"""
function spring_dashpot_width(
        t::Real; n::Integer = 11, rate::Real = 18.2816647214633,
        pinned::Bool = false
    )
    n >= 2 || throw(ArgumentError("spring_dashpot_width: n must be at least 2, got $n"))
    u0(i) = -i / 2                                  # displacement from the rest position i
    du = 0.0                                        # u_{n−1}(t) − u_0(t)
    if pinned
        m = n - 1
        for k in 1:m
            θ = (2k - 1) * π / (2m + 1)
            c = sum(u0(i) * sin(i * θ) for i in 1:m) / ((2m + 1) / 4)
            du += exp(-rate * t * (2 - 2cos(θ))) * c * sin(m * θ)
        end
    else
        for k in 1:(n - 1)                          # the k = 0 mode is a translation
            v(i) = cos((i + 1 / 2) * k * π / n)
            c = sum(u0(i) * v(i) for i in 0:(n - 1)) / (n / 2)
            du += exp(-rate * t * (2 - 2cos(k * π / n))) * c * (v(n - 1) - v(0))
        end
    end
    return (n - 1) + du
end
