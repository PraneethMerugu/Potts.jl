# kind classes. Decision: D-135.
# Related: D-075 / api-synthesis §2.2 (classes inside `@kinds`, lowered to an unrolled `|` of
# kind equalities), D-113 (one name, one category), D-016/D-121–D-124 (fingerprint), D-134
# (one of the last two step-0 rows). Consumer: Bauer 2009 (spec 05; sketch 05, friction 1:
# the stroma is two collective cells, fluid and matrix, so kind 0 owns no site and every
# `old == 0` / `new != 0` gate is wrong; classes are required, not sugar).
#
# The gap (462b012a). `@kinds` accepts only kind names (`name` or `name[frozen]`); a line
# `endothelial = (tip, stalk)` is an `ArgumentError` at macro expansion ("@kinds lists kind
# names …"). `cells`, `clusters`, `connectivity`, `Volume` and `Surface` take `Integer`s
# only, and `kind[x] ∈ (tip, stalk)` on a symbolic kind does not lower. A gate over several
# kinds must be spelled `kind[x] == tip || kind[x] == stalk` at every site.
#
# Surface (D-135):
#   @kinds begin
#       medium; fluid; matrix
#       ecm = (fluid, matrix)                 # a class: a named set of kinds; may sit anywhere
#       tip; stalk                            # in the block and never shifts kind numbers
#       endothelial = (tip, stalk)
#       mix = (ecm, tip)                      # members may be earlier classes (flattened, in order)
#   end
#   (one-line form: `@kinds medium fluid matrix tip stalk endothelial = (tip, stalk)`)
# - A class may appear wherever a kind list may: `cells(g)` (energy domain, `@divide`,
#   `@components`, population folds `for c in cells(g)`), `clusters(g)`, `connectivity(g)`,
#   `Volume(g; …)`, `Surface(g; …)`, `Chemotaxis(…; kinds = g)`, mixed with kinds
#   (`cells(ecm, tip)`).
# - `kind[x] ∈ g` (and `kind ∈ g`, `neighbor_kind ∈ g`, `kind[c] ∈ g`, `kind[n] ∈ g`, `x ∉ g`) is
#   exactly `(kind[x] == k₁) | (kind[x] == k₂) | …` in member order: constant kind numbers
#   in the generated code, no allocation, no `Set`/`Vector` on the device. So a model
#   written with classes generates the same code, and has the same fingerprint, as the same
#   model written with explicit `||` chains in member order. A declared class that no
#   statement reads changes nothing.
# - A class is not an index: `J[g, neighbor_kind]` / `γ[g]` is an `ArgumentError` naming the class.
# - Rejected at build (`ArgumentError`): an empty class; a member listed twice (also after
#   flattening); the medium as a member; a member that is not a kind or an earlier class; a
#   class named like another declaration (D-113); a reserved name. Misspelt names (a class
#   in a gate, a member in a declaration) fail at construction naming the misspelling.
# - `@extend`: a base's classes are bound like its kinds (`@extend endothelial = base =
#   Base()`), an extension may restate a base class with the same members and add classes
#   over its own kinds; restating it with other members is an `ArgumentError` naming it.
#
# Pinned here:
#  1. Every class fixture builds.
#  2. Class models generate the same code (every function, Float64 and Float32) and have the
#     same fingerprint as their explicit twins: main model, lifecycle, clusters, two
#     extensions. The explicit main model's fingerprint is pinned (462b012a).
#  3. Identical trajectories under a fixed seed, every saved state, every column:
#     SequentialCPM and CheckerboardCPM, Float64 and Float32.
#  4. Each gate site against a hand value or an independent oracle on the class model:
#     energy domain `cells(g)`, contact and site expressions (total energy at t = 0 =
#     4703.875 and a plain-Julia oracle on every saved state), drive and `Chemotaxis(kinds =
#     g)` (ΔH − ΔE = ∓5.5/32 for an EC gain, 0 otherwise), expression constraint and
#     `connectivity(g)` (on a bridge state), `@on_copy`, `@before_mcs` model fold,
#     `@after_mcs` cell update and site gather, cell ODE, field equation, `@observed` folds
#     (domain, filter, nested class, mixed list, `∉`), `@divide cells(g)` (one division,
#     the large fluid cell never divides), `@link` (only EC pairs), `clusters(g)` energy,
#     `Surface(g; …)` (through the `@extend` base).
#  5. ΔH equals H(after) − H(before) on random copies (brute-force self-check).
#  6. Negative controls: a class without `stalk` changes the fingerprint and gives 0 for a
#     stalk gain; misspelt names; medium, empty, duplicate, non-kind members; name clashes;
#     class as a table index; a class name as an operating-point kind; conflicting `@extend`.
#  7. Fingerprints of every published model unchanged (462b012a).
#  8. Metal (POTTS_GPU=metal with Metal loaded, from test/gpu.jl): the class model in
#     Float32 compiles and runs on the device and equals the CPU Float32 run.
#
# Measured. On 462b012a: 23 pass, 32 fail, 36 error of 92 (+1 Metal skip), every failure on
# the gap (the class fixtures do not build; the rejection checks get today's generic `@kinds`
# message); the explicit twins, the ClassX pin and the published pins pass. A prototype
# (`KindClass` bound by `@kinds`, `in` as an unrolled `|`, `cells`/`clusters`/`connectivity`/
# `Volume`/`Surface` flattening classes, classes stored on the system and merged by
# `extend`) passes 336/336 (+1 Metal skip), and 340/340 with POTTS_GPU=metal (bitwise CPU =
# Metal in Float32).

@testsetup module KindClassesSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "shared", "selfcheck.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# 0. Helpers. Class fixtures are defined through `define` so that a build failure
# (today: the `@kinds` line is rejected at macro expansion) fails the testsets that use the
# fixture instead of aborting the file.
const DEFINE_ERRORS = Dict{Symbol, Any}()
function define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
function class_model(name::Symbol)
    if isdefined(@__MODULE__, name)
        return getfield(@__MODULE__, name)
    else
        error("kind classes fixture $name did not build: $(get(DEFINE_ERRORS, name, "unknown"))")
    end
end
"""The exception `f()` throws and its message (`nothing, ""` if it throws none); a macro
expansion error arrives wrapped in a `LoadError` and is unwrapped."""
function class_error(f)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        return e, sprint(showerror, e)
    end
    return nothing, ""
end
"""Evaluate a model definition and construct it (`M(; name = :m)`), returning the error."""
function build_error(ex::Expr, M::Symbol)
    return class_error(
        () -> (
            Core.eval(@__MODULE__, ex);
            Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))
        )
    )
end
"""Every leaf of a saved state, as host arrays."""
function leaves(u)
    out = Pair{String, Any}["σ" => Array(u.ownership)]
    for f in (:cell, :site, :model, :history)
        nt = getfield(u, f)
        for k in keys(nt)
            v = getproperty(nt, k)
            push!(out, "$f.$k" => (v isa AbstractArray ? Array(v) : v))
        end
    end
    return out
end
class_same(a, b) = length(a.u) == length(b.u) && all(leaves(x) == leaves(y) for (x, y) in zip(a.u, b.u))
function class_code(sys; kw...)
    g = generated_code(sys; kw...)
    return string(
        Base.remove_linenums!(
            deepcopy(
                Any[
                    g.delta_H, g.commit!,
                    g.constraint, g.temperature, g.total_energy, g.delta_E, g.phases, g.lifecycle,
                ]
            )
        )
    )
end
"""ΔH (no drives) against H(after) − H(before) on copies of saved states (the suite's selfcheck)."""
function class_selfcheck(prob; n = 200)
    sol = solve(remake(prob; tspan = (0, 3)), SequentialCPM(; proposal = Moore(1)))
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CorePotts.relation(Moore(1), lat)
    worst = 0.0
    for u in sol.u, i in 1:n
        t = mod1(i * 7919, length(u.ownership)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[mod1(i, length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])
        a = deepcopy(u); a.ownership[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx)
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end
class_ctx(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...)
function class_prop(prob, u, t::NTuple{2, Int}, s::NTuple{2, Int})
    lat = prob.lattice
    ti = CorePotts.linear_index(lat, t)
    si = CorePotts.linear_index(lat, s)
    return CorePotts.Proposal(ti, si, t, 1, u.ownership[ti], u.ownership[si])
end
"""The drive part of ΔH for one proposal: ΔH − ΔE."""
class_drive(prob, u, prop) = prob.f.delta_H(u, prob.p, prop, class_ctx(prob)) - energy_change(prob, u, prop)
allowed(prob, u, prop) = Bool(prob.f.constraint(u, prob.p, prop, class_ctx(prob)))
const ALGS = (SequentialCPM(), CheckerboardCPM())
# ---------------------------------------------------------------------------------------
# 1. The Bauer-style main model: the stroma is two collective cells (fluid, matrix), the
# medium owns no site, ECs are tip and stalk. Kinds: medium 0, fluid 1, matrix 2, tip 3,
# stalk 4. Every gate site appears once; the explicit twin spells each class out.

# the field `q`, `D(q) ~ 0.25 [tip or stalk]`, as a plain MTK PDESystem on the 32 × 24 lattice; its
# input `tip_or_stalk` (0/1) is bound at `@fields` (a kind class or the explicit kinds)
function q_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables q(..) tip_or_stalk(..)::Bool [input = true]
    Q = q(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(Q) ~ 0.25 * tip_or_stalk(t, x, y)], [q(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), (32, 24)), [t, x, y], [Q, tip_or_stalk(t, x, y)], Any[]; name = :class_q
    )
end
define(
    :ClassC, :(
        @potts_model ClassC begin
            @kinds begin
                medium
                fluid
                matrix
                ecm = (fluid, matrix)               # between kind lines: kind numbers are unchanged
                tip
                stalk
                endothelial = (tip, stalk)
                mix = (ecm, tip)                    # nested: (fluid, matrix, tip)
            end
            @parameters begin
                J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
                χ = 4.0
            end
            @variables begin
                V(site) = 0.0
                gain(site) = 0.0
                near(site) = 0.0
                tgt(cell) = 0.0
                age(cell) = 0.0
                g(cell) = 0.0
            end
            @lattice Lattice((32, 24); neighborhood = Moore(1))
            @fields q_pde() (:tip_or_stalk => ismember(kind, endothelial))
            @variables n_ec(model) = 0.0
            @energy begin
                cells(endothelial) => 2.0 * (volume - 16)^2
                cells(ecm) => 0.02 * (volume - tgt)^2
                contacts => J[kind, neighbor_kind] + 3.0 * (kind ∈ endothelial) * (neighbor_kind ∈ ecm)
                sites => -0.5 * V * (kind ∈ endothelial)
            end
            @drive begin
                copy => ifelse(kind[new] ∈ endothelial, -χ * (V[target] - V[source]), 0.0)
                Chemotaxis(V; strength = 1.5, kinds = endothelial)
            end
            @constraint begin
                connectivity(endothelial)
                !((kind[old] ∈ ecm) && (kind[new] ∈ ecm))
            end
            @on_copy gain[target] += (kind[new] ∈ endothelial)
            @before_mcs n_ec ~ count(true for c in cells(endothelial))
            @after_mcs begin
                age ~ Pre(age) + (kind ∈ endothelial)
                near ~ count(true for n in Moore(1)(site) if kind[n] ∈ ecm)
            end
            @equations D(g) ~ 0.5 * ismember(kind, endothelial)
            @observed begin
                nec ~ count(true for c in cells(endothelial))
                vecm ~ sum(volume for c in cells(ecm))
                nmix ~ count(true for c in cells if kind[c] ∈ mix)
                nmix2 ~ count(true for c in cells(ecm, tip))
                nnot ~ count(true for c in cells if kind[c] ∉ endothelial)
            end
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
@potts_model ClassX begin
    @kinds medium fluid matrix tip stalk
    @parameters begin
        J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
        χ = 4.0
    end
    @variables begin
        V(site) = 0.0
        gain(site) = 0.0
        near(site) = 0.0
        tgt(cell) = 0.0
        age(cell) = 0.0
        g(cell) = 0.0
    end
    @lattice Lattice((32, 24); neighborhood = Moore(1))
    @fields q_pde() (:tip_or_stalk => ((kind == tip) || (kind == stalk)))
    @variables n_ec(model) = 0.0
    @energy begin
        cells(tip, stalk) => 2.0 * (volume - 16)^2
        cells(fluid, matrix) => 0.02 * (volume - tgt)^2
        contacts => J[kind, neighbor_kind] + 3.0 * ((kind == tip) || (kind == stalk)) * ((neighbor_kind == fluid) || (neighbor_kind == matrix))
        sites => -0.5 * V * ((kind == tip) || (kind == stalk))
    end
    @drive begin
        copy => ifelse((kind[new] == tip) || (kind[new] == stalk), -χ * (V[target] - V[source]), 0.0)
        Chemotaxis(V; strength = 1.5, kinds = (tip, stalk))
    end
    @constraint begin
        connectivity(tip, stalk)
        !(((kind[old] == fluid) || (kind[old] == matrix)) && ((kind[new] == fluid) || (kind[new] == matrix)))
    end
    @on_copy gain[target] += ((kind[new] == tip) || (kind[new] == stalk))
    @before_mcs n_ec ~ count(true for c in cells(tip, stalk))
    @after_mcs begin
        age ~ Pre(age) + ((kind == tip) || (kind == stalk))
        near ~ count(true for n in Moore(1)(site) if (kind[n] == fluid) || (kind[n] == matrix))
    end
    @equations D(g) ~ 0.5 * ((kind == tip) || (kind == stalk))
    @observed begin
        nec ~ count(true for c in cells(tip, stalk))
        vecm ~ sum(volume for c in cells(fluid, matrix))
        nmix ~ count(true for c in cells if ((kind[c] == fluid) || (kind[c] == matrix)) || (kind[c] == tip))
        nmix2 ~ count(true for c in cells(fluid, matrix, tip))
        nnot ~ count(true for c in cells if !((kind[c] == tip) || (kind[c] == stalk)))
    end
    @sweep Metropolis(; temperature = 3.0)
end
# negative control: the same model with `endothelial = (tip,)`: stalk leaves every gate
define(
    :CTip, :(
        @potts_model CTip begin
            @kinds begin
                medium
                fluid
                matrix
                ecm = (fluid, matrix)
                tip
                stalk
                endothelial = (tip,)
                mix = (ecm, tip)
            end
            @parameters begin
                J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
                χ = 4.0
            end
            @variables begin
                V(site) = 0.0
                gain(site) = 0.0
                near(site) = 0.0
                tgt(cell) = 0.0
                age(cell) = 0.0
                g(cell) = 0.0
            end
            @lattice Lattice((32, 24); neighborhood = Moore(1))
            @fields q_pde() (:tip_or_stalk => ismember(kind, endothelial))
            @variables n_ec(model) = 0.0
            @energy begin
                cells(endothelial) => 2.0 * (volume - 16)^2
                cells(ecm) => 0.02 * (volume - tgt)^2
                contacts => J[kind, neighbor_kind] + 3.0 * (kind ∈ endothelial) * (neighbor_kind ∈ ecm)
                sites => -0.5 * V * (kind ∈ endothelial)
            end
            @drive begin
                copy => ifelse(kind[new] ∈ endothelial, -χ * (V[target] - V[source]), 0.0)
                Chemotaxis(V; strength = 1.5, kinds = endothelial)
            end
            @constraint begin
                connectivity(endothelial)
                !((kind[old] ∈ ecm) && (kind[new] ∈ ecm))
            end
            @on_copy gain[target] += (kind[new] ∈ endothelial)
            @before_mcs n_ec ~ count(true for c in cells(endothelial))
            @after_mcs begin
                age ~ Pre(age) + (kind ∈ endothelial)
                near ~ count(true for n in Moore(1)(site) if kind[n] ∈ ecm)
            end
            @equations D(g) ~ 0.5 * ismember(kind, endothelial)
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
# a declared class no statement reads: the explicit model plus `spare`
define(
    :XSpare, :(
        @potts_model XSpare begin
            @kinds medium fluid matrix tip stalk spare = (matrix, tip)
            @parameters begin
                J[kind, kind] = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
                χ = 4.0
            end
            @variables begin
                V(site) = 0.0
                gain(site) = 0.0
                near(site) = 0.0
                tgt(cell) = 0.0
                age(cell) = 0.0
                g(cell) = 0.0
            end
            @lattice Lattice((32, 24); neighborhood = Moore(1))
            @fields q_pde() (:tip_or_stalk => ((kind == tip) || (kind == stalk)))
            @variables n_ec(model) = 0.0
            @energy begin
                cells(tip, stalk) => 2.0 * (volume - 16)^2
                cells(fluid, matrix) => 0.02 * (volume - tgt)^2
                contacts => J[kind, neighbor_kind] + 3.0 * ((kind == tip) || (kind == stalk)) * ((neighbor_kind == fluid) || (neighbor_kind == matrix))
                sites => -0.5 * V * ((kind == tip) || (kind == stalk))
            end
            @drive begin
                copy => ifelse((kind[new] == tip) || (kind[new] == stalk), -χ * (V[target] - V[source]), 0.0)
                Chemotaxis(V; strength = 1.5, kinds = (tip, stalk))
            end
            @constraint begin
                connectivity(tip, stalk)
                !(((kind[old] == fluid) || (kind[old] == matrix)) && ((kind[new] == fluid) || (kind[new] == matrix)))
            end
            @on_copy gain[target] += ((kind[new] == tip) || (kind[new] == stalk))
            @before_mcs n_ec ~ count(true for c in cells(tip, stalk))
            @after_mcs begin
                age ~ Pre(age) + ((kind == tip) || (kind == stalk))
                near ~ count(true for n in Moore(1)(site) if (kind[n] == fluid) || (kind[n] == matrix))
            end
            @equations D(g) ~ 0.5 * ((kind == tip) || (kind == stalk))
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
# cells 1 fluid (everything else), 2 and 3 matrix fibres (rows y = 9:10 and 17:18, across
# the periodic x axis), 4 tip (x 4:7, y 3:6), 5 stalk (x 4:7, y 12:15), 6 stalk (x 12:15, y 12:15)
function class_state()
    σ = fill(Int32(1), 32, 24)
    σ[:, 9:10] .= 2; σ[:, 17:18] .= 3
    σ[4:7, 3:6] .= 4
    σ[4:7, 12:15] .= 5
    σ[12:15, 12:15] .= 6
    return σ
end
const KINDS = [:fluid, :matrix, :matrix, :tip, :stalk, :stalk]
const CLASS_V = [x / 32 for x in 1:32, y in 1:24]
# VEGF, rising along x
function class_op(σ = class_state(), kinds = KINDS)
    return [ownership => σ, kind => kinds, :V => CLASS_V, :tgt => Float64[count(==(c), σ) for c in 1:length(kinds)]]
end
function problem(M, K = 8; T = Float64, op = class_op())
    return PottsProblem(M(; name = :bauer), op, (0, K); T, field_solver = ExplicitEuler(), seed = 7)
end
# --- independent oracles (plain Julia over σ) ---
const CLASS_J = [0 0 0 0 0; 0 6 9 8 8; 0 9 9 7 7; 0 8 7 3 3; 0 8 7 3 3]
isec(k) = k == 3 || k == 4
isecm(k) = k == 1 || k == 2
wrap(x, y, d) = (mod1(x, d[1]), mod1(y, d[2]))
"""H of the main model: Σ cells + unordered Moore pairs (periodic) + sites."""
function class_energy(σ, kd, tgt; ec = isec)
    d = size(σ)
    kof(c) = c == 0 ? 0 : Int(kd[c])
    E = 0.0
    for c in 1:length(kd)
        v = count(==(c), σ)
        v == 0 && continue
        ec(kof(c)) && (E += 2.0 * (v - 16)^2)
        isecm(kof(c)) && (E += 0.02 * (v - tgt[c])^2)
    end
    for x in 1:d[1], y in 1:d[2], (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[wrap(x + dx, y + dy, d)...]
        a == b && continue
        k, k′ = kof(a), kof(b)
        E += CLASS_J[k + 1, k′ + 1] + 1.5 * (ec(k) * isecm(k′) + ec(k′) * isecm(k))
    end
    for x in 1:d[1], y in 1:d[2]
        ec(kof(σ[x, y])) && (E += -0.5 * CLASS_V[x, y])
    end
    return E
end
"""Per site, the Moore neighbours (periodic) owned by an ECM cell."""
function class_near(σ, kd)
    return [
        count(
            ((dx, dy),) -> (dx, dy) != (0, 0) &&
                (c = σ[wrap(x + dx, y + dy, size(σ))...]; c != 0 && isecm(kd[c])), Iterators.product(-1:1, -1:1)
        )
            for x in 1:size(σ, 1), y in 1:size(σ, 2)
    ]
end
ecmask(σ, kd) = [c != 0 && isec(kd[c]) for c in σ]
# connectivity bridge state: 1 fluid; 2 matrix = two 3×3 blocks joined at (7, 15);
# 3 tip = two 3×3 blocks joined at (7, 5); 4 stalk below the matrix bridge (7, 13:14)
function bridge_state()
    σ = fill(Int32(1), 32, 24)
    σ[4:6, 4:6] .= 3; σ[8:10, 4:6] .= 3; σ[7, 5] = 3
    σ[4:6, 14:16] .= 2; σ[8:10, 14:16] .= 2; σ[7, 15] = 2
    σ[7, 13:14] .= 4
    return σ
end
# ---------------------------------------------------------------------------------------
# 2. Lifecycle: `@divide cells(g)` and `@link … kind[a] ∈ g`. Kinds: medium 0, fluid 1,
# tip 2, stalk 3. At MCS 1 the tip (target 36; 33–35 measured) is above the threshold 26,
# the stalk (target 16) below it, and the fluid cell (≈ 716 sites) far above it but outside
# the class.
define(
    :LifeC, :(
        @potts_model LifeC begin
            @kinds medium fluid tip stalk endothelial = (tip, stalk)
            @parameters begin
                J[kind, kind] = [0 0 0 0; 0 4 8 8; 0 8 2 2; 0 8 2 2]
                V₀[kind] = [0.0, 0.0, 36.0, 16.0]
            end
            @relationship bond(cell, cell) capacity = 4
            @lattice Lattice((32, 24); neighborhood = Moore(1))
            @energy begin
                cells(endothelial) => 1.0 * (volume - V₀[kind])^2
                contacts => J[kind, neighbor_kind]
                edges(bond) => 0.05 * (distance - 5.0)^2
            end
            @divide cells(endothelial) when = (mcs == 1) && (volume >= 26)
            @link bond when = new_contact(a, b) && (kind[a] ∈ endothelial) && (kind[b] ∈ endothelial)
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
@potts_model LifeX begin
    @kinds medium fluid tip stalk
    @parameters begin
        J[kind, kind] = [0 0 0 0; 0 4 8 8; 0 8 2 2; 0 8 2 2]
        V₀[kind] = [0.0, 0.0, 36.0, 16.0]
    end
    @relationship bond(cell, cell) capacity = 4
    @lattice Lattice((32, 24); neighborhood = Moore(1))
    @energy begin
        cells(tip, stalk) => 1.0 * (volume - V₀[kind])^2
        contacts => J[kind, neighbor_kind]
        edges(bond) => 0.05 * (distance - 5.0)^2
    end
    @divide cells(tip, stalk) when = (mcs == 1) && (volume >= 26)
    @link bond when = new_contact(a, b) && ((kind[a] == tip) || (kind[a] == stalk)) && ((kind[b] == tip) || (kind[b] == stalk))
    @sweep Metropolis(; temperature = 3.0)
end
# 1 fluid; 2 tip 6×6 (x 4:9, y 4:9); 3 stalk 4×4 touching it (x 10:13, y 5:8)
function life_state()
    σ = fill(Int32(1), 32, 24)
    σ[4:9, 4:9] .= 2
    σ[10:13, 5:8] .= 3
    return σ
end
function life_problem(M; T = Float64, K = 6)
    return PottsProblem(M(; name = :life), [ownership => life_state(), kind => [:fluid, :tip, :stalk]], (0, K); T, capacity = 8, seed = 3)
end
# ---------------------------------------------------------------------------------------
# 3. Clusters: `clusters(g)` selects clusters whose root is of a kind in g. Kinds: medium 0,
# fluid 1, tip 2, stalk 3. Cluster A = {2 tip, 3 stalk} (root tip), B = {4 stalk, 5 tip}
# (root stalk), fluid 1 alone (root fluid, outside the class).
define(
    :ClusterC, :(
        @potts_model ClusterC begin
            @kinds medium fluid tip stalk endothelial = (tip, stalk)
            @parameters J[kind, kind] = [0 0 0 0; 0 4 8 8; 0 8 3 3; 0 8 3 3]
            @lattice Lattice((20, 16); neighborhood = Moore(1))
            @energy begin
                contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 1.0, J[kind, neighbor_kind])
                clusters(endothelial) => 0.5 * (cluster_volume - 30)^2
            end
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
@potts_model ClusterX begin
    @kinds medium fluid tip stalk
    @parameters J[kind, kind] = [0 0 0 0; 0 4 8 8; 0 8 3 3; 0 8 3 3]
    @lattice Lattice((20, 16); neighborhood = Moore(1))
    @energy begin
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 1.0, J[kind, neighbor_kind])
        clusters(tip, stalk) => 0.5 * (cluster_volume - 30)^2
    end
    @sweep Metropolis(; temperature = 3.0)
end
function cluster_state()
    σ = fill(Int32(1), 20, 16)
    σ[3:6, 3:6] .= 2; σ[7:9, 3:6] .= 3          # A: 16 + 12 = 28
    σ[12:15, 9:12] .= 4; σ[16:18, 9:12] .= 5    # B: 16 + 12 = 28
    return σ
end
function cluster_problem(M; T = Float64)
    return PottsProblem(
        M(; name = :cl),
        [ownership => cluster_state(), kind => [:fluid, :tip, :stalk, :stalk, :tip], cluster => [1, 2, 2, 4, 4]], (0, 6); T, seed = 5
    )
end
"""H of the cluster model: contact pairs (Moore, periodic) + Σ over endothelial-rooted clusters."""
cluster_contacts(σ, kd, cl) = cluster_energy(σ, kd, cl; clusters = false)
const CLUSTER_E0 = 1016.0
# contacts 1012 + clusters 2 · 0.5 · (28 − 30)²
function cluster_energy(σ, kd, cl; clusters = true)
    J = [0 0 0 0; 0 4 8 8; 0 8 3 3; 0 8 3 3]
    d = size(σ)
    E = 0.0
    for x in 1:d[1], y in 1:d[2], (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]; b = σ[wrap(x + dx, y + dy, d)...]
        a == b && continue
        E += cl[a] == cl[b] ? 1.0 : J[kd[a] + 1, kd[b] + 1]
    end
    clusters || return E
    for r in unique(cl)
        members = [c for c in eachindex(cl) if cl[c] == r]
        root = minimum(c for c in members if count(==(c), σ) > 0)
        kd[root] in (2, 3) || continue
        E += 0.5 * (sum(count(==(c), σ) for c in members) - 30)^2
    end
    return E
end
# ---------------------------------------------------------------------------------------
# 4. `@extend`: a base class bound by name; an extension restating it and adding a kind and
# a nested class. Kinds: medium 0, fluid 1, tip 2, stalk 3 (+ prolif 4). The base also uses
# the library one-liner `Surface(g; …)`.
define(
    :BaseC, :(
        @potts_model BaseC begin
            @kinds begin
                medium
                fluid
                tip
                stalk
                endothelial = (tip, stalk)
            end
            @lattice Lattice((20, 16); neighborhood = Moore(1))
            @energy begin
                cells(endothelial) => 1.5 * (volume - 12)^2
                Surface(endothelial; target = 14.0, strength = 0.1)
                contacts => 4.0 * (kind != neighbor_kind) + 1.0
            end
            @sweep Metropolis(; temperature = 3.0)
        end
    )
)
define(
    :ExtC, :(
        @potts_model ExtC begin
            @extend endothelial = base = BaseC()
            @variables V(site) = 0.0
            @drive copy => ifelse(kind[new] ∈ endothelial, -3.0 * (V[target] - V[source]), 0.0)
        end
    )
)
define(
    :Ext2C, :(
        @potts_model Ext2C begin
            @extend base = BaseC()
            @kinds begin
                medium
                fluid
                tip
                stalk
                prolif
                endothelial = (tip, stalk)          # restated with the base's members
                sprout = (endothelial, prolif)
            end
            @energy cells(prolif) => 1.5 * (volume - 12)^2
            @drive copy => 0.25 * (kind[old] ∈ sprout)
            @observed nsprout ~ count(true for c in cells(sprout))
        end
    )
)
@potts_model BaseX begin
    @kinds medium fluid tip stalk
    @lattice Lattice((20, 16); neighborhood = Moore(1))
    @energy begin
        cells(tip, stalk) => 1.5 * (volume - 12)^2
        Surface(tip, stalk; target = 14.0, strength = 0.1)
        contacts => 4.0 * (kind != neighbor_kind) + 1.0
    end
    @sweep Metropolis(; temperature = 3.0)
end
@potts_model ExtX begin
    @extend tip, stalk = base = BaseX()
    @variables V(site) = 0.0
    @drive copy => ifelse((kind[new] == tip) || (kind[new] == stalk), -3.0 * (V[target] - V[source]), 0.0)
end
@potts_model Ext2X begin
    @extend base = BaseX()
    @kinds medium fluid tip stalk prolif
    @energy cells(prolif) => 1.5 * (volume - 12)^2
    @drive copy => 0.25 * (((kind[old] == tip) || (kind[old] == stalk)) || (kind[old] == prolif))
    @observed nsprout ~ count(true for c in cells(tip, stalk, prolif))
end
# 1 fluid; 2 tip, 3 stalk, 4 tip (3×4 each; 12 sites)
function ext_state()
    σ = fill(Int32(1), 20, 16)
    σ[3:5, 3:6] .= 2; σ[10:12, 3:6] .= 3; σ[10:12, 10:13] .= 4
    return σ
end
function ext_problem(M; T = Float64)
    return PottsProblem(
        M(; name = :ext),
        [ownership => ext_state(), kind => [:fluid, :tip, :stalk, :tip], :V => [x / 20 for x in 1:20, y in 1:16]], (0, 6); T, seed = 11
    )
end
function ext2_problem(M; T = Float64)
    return PottsProblem(
        M(; name = :ext2),
        [ownership => ext_state(), kind => [:fluid, :tip, :prolif, :stalk]], (0, 6); T, seed = 13
    )
end
# ---------------------------------------------------------------------------------------
# Tests
const CLASS_FIXTURES = (:ClassC, :CTip, :XSpare, :LifeC, :ClusterC, :BaseC, :ExtC, :Ext2C)
const BAD = (
    (
        "misspelt class in a gate", "endothelal", :BadGate, :(
            @potts_model BadGate begin
                @kinds medium fluid tip stalk endothelial = (tip, stalk)
                @lattice Lattice((12, 12))
                @drive copy => 1.0 * (kind[new] ∈ endothelal)
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "misspelt class as a domain", "endothelal", :BadDomain, :(
            @potts_model BadDomain begin
                @kinds medium fluid tip stalk endothelial = (tip, stalk)
                @lattice Lattice((12, 12))
                @energy cells(endothelal) => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "misspelt member", "stlk", :BadMember, :(
            @potts_model BadMember begin
                @kinds medium fluid tip stalk endothelial = (tip, stlk)
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
)
const REJECTED = (
    (
        "medium as a member", ["medium"], :Medium, :(
            @potts_model Medium begin
                @kinds medium fluid tip stalk nonliving = (medium, fluid)
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "empty class", ["none"], :Empty, :(
            @potts_model Empty begin
                @kinds medium fluid tip stalk none = ()
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a member twice", ["twice"], :Twice, :(
            @potts_model Twice begin
                @kinds medium fluid tip stalk twice = (tip, stalk, tip)
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a member twice after flattening", ["over"], :Overlap, :(
            @potts_model Overlap begin
                @kinds begin
                    medium; fluid; tip; stalk
                    endothelial = (tip, stalk)
                    over = (endothelial, tip)
                end
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a parameter as a member", ["odd"], :ParamMember, :(
            @potts_model ParamMember begin
                @kinds medium fluid tip stalk odd = (tip, λ)
                @parameters λ = 1.0
                @lattice Lattice((12, 12))
                @energy cells => λ * (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a class named like a kind", ["tip"], :Clash, :(
            @potts_model Clash begin
                @kinds medium fluid tip stalk tip = (stalk,)
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a class named like a parameter", ["λ"], :ClashP, :(
            @potts_model ClashP begin
                @kinds medium fluid tip stalk λ = (tip, stalk)
                @parameters λ = 1.0
                @lattice Lattice((12, 12))
                @energy cells => (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a reserved name", ["volume"], :Reserved, :(
            @potts_model Reserved begin
                @kinds medium fluid tip stalk volume = (tip, stalk)
                @lattice Lattice((12, 12))
                @energy cells => (9 - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a class indexing a 2-D kind table", ["endothelial", "kind class"], :Index2, :(
            @potts_model Index2 begin
                @kinds medium fluid tip stalk endothelial = (tip, stalk)
                @parameters J[kind, kind] = [0 1 1 1; 1 1 1 1; 1 1 1 1; 1 1 1 1]
                @lattice Lattice((12, 12))
                @energy contacts => J[endothelial, neighbor_kind]
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "a class indexing a 1-D kind table", ["endothelial", "kind class"], :Index1, :(
            @potts_model Index1 begin
                @kinds medium fluid tip stalk endothelial = (tip, stalk)
                @parameters γ[kind] = [0.0, 1.0, 2.0, 2.0]
                @lattice Lattice((12, 12))
                @energy cells => γ[endothelial] * (volume - 9)^2
                @sweep Metropolis(; temperature = 2.0)
            end
        )
    ),
    (
        "@extend restating a base class with other members", ["endothelial"], :ExtBad, :(
            @potts_model ExtBad begin
                @extend base = BaseC()
                @kinds begin
                    medium; fluid; tip; stalk
                    endothelial = (tip,)
                end
            end
        )
    ),
)
# ---------------------------------------------------------------------------------------
# Fingerprints of the published models (recorded on 462b012a)
two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
# ---------------------------------------------------------------------------------------
# Metal: the class gates compile for the device (constants, no allocation) and match the CPU
const ON_DEVICE = PottsDevices.on_device()
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "kind classes: class fixtures build" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: class fixtures build" begin
        for M in CLASS_FIXTURES
            ok = isdefined(@__MODULE__, M) && Base.invokelatest(getfield(@__MODULE__, M); name = :m) isa PottsSystem
            @test ok                                                        # GAP (the `@kinds` class line)
            ok || @info "kind classes: $M" error = get(DEFINE_ERRORS, M, nothing)
        end
        # a class is bound like a kind: `lookup` (what `@extend` uses) iterates its kind numbers
        sys = Base.invokelatest(class_model(:ClassC); name = :m)
        @test collect(Potts.lookup(sys, :endothelial)) == [3, 4]
        @test collect(Potts.lookup(sys, :ecm)) == [1, 2]
        @test collect(Potts.lookup(sys, :mix)) == [1, 2, 3]
        @test Potts.lookup(sys, :tip) == 3                                  # kind numbers unchanged by class lines
        @test getfield(getfield(sys, :part), :kinds) == [:medium, :fluid, :matrix, :tip, :stalk]   # the container (D-259): kinds live on the part
    end
end

@testitem "kind classes: classes lower to the explicit gates (same code, same fingerprint)" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    # pin removed at integration (D-INT-1); replaced by a correctness test in the TS series
    @testset "kind classes: classes lower to the explicit gates (same code, same fingerprint)" begin
        pairs = (
            (
                "main", () -> problem(class_model(:ClassC)), () -> problem(ClassX),
                (M, T) -> class_code(M(; name = :m); T, field_solver = ExplicitEuler()), :ClassC, ClassX,
            ),
            (
                "lifecycle", () -> life_problem(class_model(:LifeC)), () -> life_problem(LifeX),
                (M, T) -> class_code(M(; name = :m); T), :LifeC, LifeX,
            ),
            (
                "clusters", () -> cluster_problem(class_model(:ClusterC)), () -> cluster_problem(ClusterX),
                (M, T) -> class_code(M(; name = :m); T), :ClusterC, ClusterX,
            ),
            (
                "@extend bound class", () -> ext_problem(class_model(:ExtC)), () -> ext_problem(ExtX),
                (M, T) -> class_code(M(; name = :m); T), :ExtC, ExtX,
            ),
            (
                "@extend restated + nested class", () -> ext2_problem(class_model(:Ext2C)), () -> ext2_problem(Ext2X),
                (M, T) -> class_code(M(; name = :m); T), :Ext2C, Ext2X,
            ),
        )
        for (label, c, x, code, C, X) in pairs
            @testset "$label" begin
                @test c().f.fingerprint == x().f.fingerprint
                for T in (Float64, Float32)
                    @test code(class_model(C), T) == code(X, T)
                end
            end
        end
        # a class no statement reads changes nothing
        @test problem(class_model(:XSpare)).f.fingerprint == problem(ClassX).f.fingerprint
        # pin removed at integration (D-INT-1); replaced by a correctness test in the TS series
    end
end

@testitem "kind classes: identical trajectories, class vs explicit" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: identical trajectories, class vs explicit ($(nameof(typeof(alg))), $T)" for alg in ALGS, T in (Float64, Float32)
        K = 8
        a = solve(problem(class_model(:ClassC), K; T), alg; saveat = 0:K)
        b = solve(problem(ClassX, K; T), alg; saveat = 0:K)
        @test Symbol(a.retcode) === :Success
        @test class_same(a, b)
        @test a.u[end].ownership != a.u[1].ownership                                          # the run moves
        for o in (:nec, :vecm, :nmix, :nmix2, :nnot)
            @test observe(a, o) == observe(b, o)
        end
        @test class_same(
            solve(life_problem(class_model(:LifeC); T), alg; saveat = 0:6),
            solve(life_problem(LifeX; T), alg; saveat = 0:6)
        )
        @test class_same(
            solve(cluster_problem(class_model(:ClusterC); T), alg; saveat = 0:6),
            solve(cluster_problem(ClusterX; T), alg; saveat = 0:6)
        )
        @test class_same(
            solve(ext_problem(class_model(:ExtC); T), alg; saveat = 0:6),
            solve(ext_problem(ExtX; T), alg; saveat = 0:6)
        )
        a2 = solve(ext2_problem(class_model(:Ext2C); T), alg; saveat = 0:6)
        @test class_same(a2, solve(ext2_problem(Ext2X; T), alg; saveat = 0:6))
        @test all(==(3), observe(a2, :nsprout))                              # tip, prolif, stalk; fluid is out
    end
end

@testitem "kind classes: energy gates (cells(g), contacts, sites) against an oracle" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: energy gates (cells(g), contacts, sites) against an oracle" begin
        prob = problem(class_model(:ClassC))
        @test total_energy(prob) == 4703.875                                  # hand value of the t = 0 state
        @test class_energy(class_state(), Array(prob.u0.cell.kind), Array(prob.u0.cell.tgt)) == 4703.875
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:8)
            for u in sol.u
                @test total_energy(prob, u) ≈ class_energy(Array(u.ownership), Array(u.cell.kind), Array(u.cell.tgt)) atol = 1.0e-9
            end
        end
        # negative control: without stalk in the class, stalks leave the volume, contact and
        # site terms (stalk 6 shrunk to 15 sites so its volume term is not zero)
        tipo = problem(class_model(:CTip))
        σ = class_state(); σ[12, 12] = 1
        u, v = remake(tipo; u0 = class_op(σ)).u0, remake(prob; u0 = class_op(σ)).u0
        @test total_energy(tipo, u) ≈ class_energy(σ, Array(u.cell.kind), Array(u.cell.tgt); ec = ==(3)) atol = 1.0e-9
        @test total_energy(prob, v) ≈ class_energy(σ, Array(v.cell.kind), Array(v.cell.tgt)) atol = 1.0e-9
        @test abs(total_energy(prob, v) - total_energy(tipo, u)) > 1
    end
end

@testitem "kind classes: drive and Chemotaxis(kinds = g) gates" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: drive and Chemotaxis(kinds = g) gates" begin
        prob = problem(class_model(:ClassC)); u = prob.u0
        # tip gains a fluid site, +1 in x: −(χ + 1.5)·(1/32)
        @test class_drive(prob, u, class_prop(prob, u, (8, 4), (7, 4))) ≈ -5.5 / 32 atol = 1.0e-12
        # stalk gains a fluid site, −1 in x: +(χ + 1.5)·(1/32)
        @test class_drive(prob, u, class_prop(prob, u, (3, 13), (4, 13))) ≈ 5.5 / 32 atol = 1.0e-12
        # fluid gains a tip site; fluid gains a matrix site: no EC gains, no drive
        @test class_drive(prob, u, class_prop(prob, u, (7, 4), (8, 4))) == 0
        @test class_drive(prob, u, class_prop(prob, u, (8, 9), (8, 8))) == 0
        # negative control: a stalk outside the class gets nothing
        tipo = problem(class_model(:CTip)); w = tipo.u0
        @test class_drive(tipo, w, class_prop(tipo, w, (3, 13), (4, 13))) == 0
        @test class_drive(tipo, w, class_prop(tipo, w, (8, 4), (7, 4))) ≈ -5.5 / 32 atol = 1.0e-12
    end
end

@testitem "kind classes: constraint gates (expression and connectivity(g))" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: constraint gates (expression and connectivity(g))" begin
        prob = problem(class_model(:ClassC)); u = prob.u0
        @test !allowed(prob, u, class_prop(prob, u, (8, 9), (8, 8)))      # fluid takes matrix: ECM ↔ ECM
        @test !allowed(prob, u, class_prop(prob, u, (8, 8), (8, 9)))      # matrix takes fluid
        @test allowed(prob, u, class_prop(prob, u, (8, 4), (7, 4)))       # tip takes fluid
        @test allowed(prob, u, class_prop(prob, u, (7, 4), (8, 4)))       # fluid takes a tip edge site (tip stays connected)
        b = remake(prob; u0 = class_op(bridge_state(), [:fluid, :matrix, :tip, :stalk])); v = b.u0
        @test !allowed(b, v, class_prop(b, v, (7, 5), (7, 4)))            # fluid cuts the tip bridge
        @test allowed(b, v, class_prop(b, v, (7, 15), (7, 14)))           # stalk cuts the matrix bridge: matrix is not in the class
        @test !allowed(b, v, class_prop(b, v, (7, 15), (7, 16)))          # control: fluid there is ECM ↔ ECM
        # negative control: connectivity over (tip,) still holds the tip
        t = problem(class_model(:CTip)); tb = remake(t; u0 = class_op(bridge_state(), [:fluid, :matrix, :tip, :stalk]))
        @test !allowed(tb, tb.u0, class_prop(tb, tb.u0, (7, 5), (7, 4)))
        # in a run, no site ever passes from an ECM cell to another ECM cell between saves
        sol = solve(prob, SequentialCPM(); saveat = 0:8)
        for k in 1:8
            a, c = Array(sol.u[k].ownership), Array(sol.u[k + 1].ownership)
            @test !any(i -> a[i] != c[i] && a[i] in (1, 2, 3) && c[i] in (1, 2, 3), eachindex(a))
        end
    end
end

@testitem "kind classes: @on_copy gate" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: @on_copy gate" begin
        prob = problem(class_model(:ClassC)); u = prob.u0; ctx = class_ctx(prob)
        for (t, s, expect) in (((8, 4), (7, 4), 1.0), ((3, 13), (4, 13), 1.0), ((7, 4), (8, 4), 0.0))
            prop = class_prop(prob, u, t, s)
            a = deepcopy(u); a.ownership[prop.target] = prop.new
            prob.f.commit!(a, prob.p, prop, ctx)
            @test a.site.gain[prop.target] == expect
        end
        # in a run: every save-to-save EC gain of a site was counted
        sol = solve(prob, SequentialCPM(); saveat = 0:8)
        kd = Array(sol.u[1].cell.kind)
        for k in 1:8
            a, c = Array(sol.u[k].ownership), Array(sol.u[k + 1].ownership)
            ga, gc = Array(sol.u[k].site.gain), Array(sol.u[k + 1].site.gain)
            @test all(i -> !(a[i] != c[i] && isec(kd[c[i]])) || gc[i] >= ga[i] + 1, eachindex(a))
        end
        @test sum(Array(sol.u[end].site.gain)) >= 1
    end
end

@testitem "kind classes: update, equation and observed gates" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: update, equation and observed gates ($(nameof(typeof(alg))))" for alg in ALGS
        K = 8
        sol = solve(problem(class_model(:ClassC), K), alg; saveat = 0:K)
        kd = Array(sol.u[1].cell.kind)
        ec = [isec(k) for k in kd]
        for k in 0:K
            u = sol.u[k + 1]
            σ = Array(u.ownership)
            @test Array(u.cell.age) == [e ? Float64(k) : 0.0 for e in ec]         # @after_mcs cell update
            @test Array(u.cell.g) ≈ [e ? 0.5k : 0.0 for e in ec]                  # cell ODE (Euler, exact)
            k > 0 && @test only(Array(u.model.n_ec)) == 3                         # @before_mcs model fold
            k > 0 && @test Array(u.site.near) == class_near(σ, kd)                 # @after_mcs site gather
        end
        # the field gains 0.25 per MCS on the sites ECs own after the sweep, nothing elsewhere
        for k in 1:K
            dq = Array(sol.u[k + 1].site.q) .- Array(sol.u[k].site.q)
            m1 = ecmask(Array(sol.u[k + 1].ownership), kd)
            @test dq == 0.25 .* m1
            @test count(m1) >= 30                                              # ≈ 3 × 14 EC sites
        end
        @test all(==(3), observe(sol, :nec))
        @test observe(sol, :vecm) == [Float64(count(c -> c != 0 && isecm(kd[c]), Array(u.ownership))) for u in sol.u]
        @test all(==(4), observe(sol, :nmix))                                  # fluid, 2 matrix, tip
        @test all(==(4), observe(sol, :nmix2))
        @test all(==(3), observe(sol, :nnot))                                  # fluid, 2 matrix
    end
end

@testitem "kind classes: lifecycle gates (@divide cells(g), @link)" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: lifecycle gates (@divide cells(g), @link) ($(nameof(typeof(alg))))" for alg in ALGS
        sol = solve(life_problem(class_model(:LifeC)), alg; saveat = 0:6)
        @test Symbol(sol.retcode) === :Success
        @test sol.stats.lifecycle.divisions == 1                               # the tip only; fluid (≈716 sites) never
        u = sol.u[end]
        vol = Array(u.cell.volume); kd = Array(u.cell.kind)
        live = findall(>(0), vol)
        @test live == [1, 2, 3, 4]
        @test kd[live] == [1, 2, 3, 2]                                         # the daughter is a tip
        @test vol[1] >= 600
        store = CorePotts.link_store(u.cell, :bond)
        linked = [(i, j) for i in live, j in live if i < j && CorePotts.link_slot(store, i, j) != 0]
        @test (2, 3) in linked
        @test all(((i, j),) -> i != 1 && j != 1, linked)                       # fluid touches all, never linked
        @test length(linked) >= 2
    end
end

@testitem "kind classes: clusters(g) against an oracle" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: clusters(g) against an oracle" begin
        prob = cluster_problem(class_model(:ClusterC))
        σ = cluster_state()
        @test total_energy(prob) == cluster_energy(σ, [1, 2, 3, 3, 2], [1, 2, 2, 4, 4]) == CLUSTER_E0
        # the cluster part by hand: 0.5·(28 − 30)² for each EC-rooted cluster; the fluid root is outside
        @test CLUSTER_E0 - cluster_contacts(σ, [1, 2, 3, 3, 2], [1, 2, 2, 4, 4]) == 4.0
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:6)
            for u in sol.u
                @test total_energy(prob, u) ≈ cluster_energy(Array(u.ownership), Array(u.cell.kind), Array(u.cell.cluster)) atol = 1.0e-9
            end
        end
    end
end

@testitem "kind classes: ΔH self-check" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: ΔH self-check" begin
        @test class_selfcheck(problem(class_model(:ClassC))) < 1.0e-9
        @test class_selfcheck(life_problem(class_model(:LifeC))) < 1.0e-9
        @test class_selfcheck(cluster_problem(class_model(:ClusterC))) < 1.0e-9
        @test class_selfcheck(ext_problem(class_model(:ExtC))) < 1.0e-9
        @test class_selfcheck(ext2_problem(class_model(:Ext2C))) < 1.0e-9
    end
end

@testitem "kind classes: membership matters (a class without stalk)" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # Negative controls
    @testset "kind classes: membership matters (a class without stalk)" begin
        c, t = problem(class_model(:ClassC)), problem(class_model(:CTip))
        @test c.f.fingerprint != t.f.fingerprint
        @test !class_same(solve(c, SequentialCPM(); saveat = 0:8), solve(t, SequentialCPM(); saveat = 0:8))
    end
end

@testitem "kind classes: misspelt names fail at build, naming them" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: misspelt names fail at build, naming them ($label)" for (label, name, M, ex) in BAD
        e, msg = build_error(ex, M)
        @test e !== nothing
        @test occursin(name, msg)                                              # GAP: today the `@kinds` line fails first
    end
end

@testitem "kind classes: rejected classes" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: rejected classes ($label)" for (label, names, M, ex) in REJECTED
        e, msg = build_error(ex, M)
        @test e isa ArgumentError
        @test all(n -> occursin(n, msg), names)
        @test !occursin("@kinds lists kind names", msg)                        # GAP: not today's generic rejection
    end
end

@testitem "kind classes: a class name is not an operating-point kind" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: a class name is not an operating-point kind" begin
        e, msg = class_error(
            () -> PottsProblem(
                class_model(:ClassC)(; name = :m),
                class_op(class_state(), [:fluid, :matrix, :matrix, :endothelial, :stalk, :stalk]), (0, 2); field_solver = ExplicitEuler()
            )
        )
        @test e isa ArgumentError
        @test occursin("endothelial", msg)
    end
end

@testitem "kind classes: on the device (Float32), class gates equal the CPU run" setup = [KindClassesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "kind classes: on the device (Float32), class gates equal the CPU run" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            for (label, prob) in (
                    ("main", problem(class_model(:ClassC), 8; T = Float32)),
                    ("clusters", cluster_problem(class_model(:ClusterC); T = Float32)),
                )
                cpu = solve(prob, alg; saveat = 0:4)
                gpu = solve(prob, alg; backend, saveat = 0:4)
                @test Symbol(gpu.retcode) === :Success
                @test class_same(cpu, gpu)
                class_same(cpu, gpu) || @info "kind classes device $label" cpu = Array(cpu.u[end].ownership) == Array(gpu.u[end].ownership)
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
