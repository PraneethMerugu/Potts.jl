# Sources: D-159; research/mtk-native-plan.md §3.1, §4 route A4+, §5, §6.
# the sweep's definition as an MTK-visible object. A public `Potts.hamiltonian(sys)`
# gives the model's Hamiltonian as Symbolics expressions, and a typed metadata payload
# `Potts.PottsSweepSpec`, read through MTK's own `getmetadata`/`hasmetadata`, tells generic
# code that a system has a lattice sweep and what that sweep is (the Hamiltonian, drives,
# constraints, temperature and proposal neighbourhood). This is the plan §5 sentence "an
# `AbstractSystem` whose ... Hamiltonian [is a Symbolics expression] that ModelingToolkit's
# generic tools can inspect". It is a description only: MTK never executes the sweep.
#
# The contract pinned here (public API only; storage, caching, the domain objects' types
# and the payload's constructor are the implementer's):
#  A. `Potts.hamiltonian`, `Potts.drives` and `Potts.PottsSweepSpec` are public names of
#     Potts with docstrings. `PottsSweepSpec` is a concrete type.
#  H. `hamiltonian(sys)` is an `AbstractVector` of `domain => expr` pairs, one per `@energy`
#     term, in declaration order (`@extend` merged), on a `PottsSystem` and on a
#     `CompiledPottsSystem`. `expr` is the term's energy density as written: a
#     Symbolics expression in the declared parameter, variable and built-in symbols (`volume`,
#     `neighbor_kind`, …). Drives, constraints and the temperature are not Hamiltonian terms. The
#     domain (`first`) is the DSL domain value; its type is not pinned.
#     - Oracle 1 (symbolic, as written): each fixture term has exactly the symbols written
#       and equals the hand-written density at fixed points (substitution of numbers by
#       MTK's generic `Symbolics.substitute`).
#     - Oracle 2 (round trip, D-048): summing the substituted densities over the domain of
#       each term (cells of the term's kind; unordered bonds with different owners) equals
#       a hand count (31.0, 56.5) and `total_energy(prob, u)` (CorePotts H) on a three-state
#       fixture (medium + two cells), also after `remake` changes a parameter.
#     - Published models: every symbol in every term is a parameter or unknown of the
#       system (MTK's `parameters`/`unknowns`) or a DSL built-in; the term counts are the
#       models' as written.
#  D. `drives(sys)`: the `@drive copy => expr` expressions in declaration order (Symbolics
#     expressions); empty for a model without drives.
#  M. Metadata. `getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, nothing)` (MTK's generic
#     accessor, ModelingToolkitBase re-exports SymbolicUtils' function, on the complete System
#     a `PottsSystem` wraps; D-256) returns a `PottsSweepSpec` on every published
#     model and fixture, with no user action; `hasmetadata` is true. Its
#     properties `hamiltonian`, `drives`, `constraints`, `temperature` and `proposal` are
#     the system's: `hamiltonian` and `drives` equal the accessors, `constraints` has one
#     entry per `@constraint`, `temperature` is the `@sweep` temperature as written (the
#     declared symbol `T`), `proposal` the `@relations proposal` relation. It is present on
#     `mtkcompile(sys)` (the `CompiledPottsSystem` itself) and on its `.sys`'s inner System,
#     and describes the merged model after `extend` (never the base's stale payload).
#     `show` of the payload names `PottsSweepSpec`. Other metadata keys behave as before on
#     the inner System.
#  N. Negative controls: a plain MTK `System` (and its `mtkcompile`) has no payload
#     (`getmetadata(…, PottsSweepSpec, nothing) === nothing`, `hasmetadata` false), and
#     builds an `ODEProblem`.
#  X. Downstream detection: generic code that asks `hasmetadata(s, PottsSweepSpec)` of an MTK
#     `System` (`Potts.inner(sys)` for a `PottsSystem`) tells every Potts model from a plain
#     `System`; on every published model `ODEProblem` and
#     `JumpProblem` are still `ArgumentError`s naming `PottsProblem` (D-137 rule 5; a
#     regression guard that passes before this item).
#
# Not pinned here: generated code and fingerprints. They must stay byte-identical (the
# payload never enters code, D-137 rule 2); the pins of `abstract_system_tests.jl` and the other
# fingerprint suites check that. `Potts.constraints` is not pinned: MTK exports
# `constraints`, and `ModelingToolkitBase.constraints(sys)` already returns the Potts
# constraint vector through the `constraints` field (D-entry note).
#
# On e47f0e28 every A/H/D/M/X target errors (`Potts.hamiltonian`, `Potts.drives`,
# `Potts.PottsSweepSpec` are undefined); the N controls and the X regression guard pass.

@testsetup module HamiltonianMetadataSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
const HAMILTONIAN_M = Potts.ModelingToolkitBase
const HAMILTONIAN_S = Potts.Symbolics
const SII = Potts.SymbolicIndexingInterface
hamiltonian_name(x) = SII.getname(x)
hamiltonian_names(e) = Set{Symbol}(hamiltonian_name(v) for v in HAMILTONIAN_S.get_variables(HAMILTONIAN_S.unwrap(e)))
symbolic(e) = HAMILTONIAN_S.unwrap(e) isa Potts.SymbolicUtils.BasicSymbolic
# substitute numbers for every symbol of `e`, by name, and read the number back
function evaluate_at(e, vals::AbstractDict{Symbol})
    x = HAMILTONIAN_S.unwrap(e)
    sub = Dict{Any, Any}(v => vals[hamiltonian_name(v)] for v in HAMILTONIAN_S.get_variables(x))
    return Float64(HAMILTONIAN_S.value(HAMILTONIAN_S.substitute(x, sub)))
end
# the DSL's built-in names (AUTHORING; `Potts.DSL`): the only non-declared symbols an
# energy may read
const BUILTINS = Set(
    [
        :volume, :surface, :kind, :neighbor_kind, :owner, :neighbor_owner, :id, :generation,
        :weight, :source, :target, :old, :new, :mcs, :position, :a, :b, :distance, :cluster,
        :cluster_volume, :cluster_surface, :time, :site, :neighbor_site, :major_length, :local_components,
        :ring_arcs, :ring_cells, :ring_medium,
    ]
)
# ---------------------------------------------------------------------------------------
# Fixtures

# three states (medium, dark, light); per-kind cell terms and a constant contact term, so
# every term can be summed by hand; a drive and a constraint that are not in H
@potts_model Ham begin
    @kinds medium dark light
    @parameters begin
        λd = 2.0
        λl = 0.5
        Vd = 6.0
        Vl = 5.0
        Jc = 1.5
        T = 3.0
        μ = 0.25
    end
    @lattice Lattice((6, 6); boundary = Periodic(), neighborhood = VonNeumann(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(dark) => λd * (volume - Vd)^2
        cells(light) => λl * (volume - Vl)^2
        contacts => Jc
    end
    @drive copy => ifelse(new != 0, μ, 0.0)
    @constraint connectivity(dark)
    @sweep Metropolis(; temperature = T)
end
# an extension adding one cell term (for `extend`)
@potts_model Extra begin
    @kinds medium dark light
    @parameters κ = 0.75
    @lattice Lattice((6, 6); boundary = Periodic(), neighborhood = VonNeumann(1))
    @energy cells(dark) => κ * volume
    @sweep Metropolis(; temperature = 1.0)
end
const VALS = Dict(:λd => 2.0, :λl => 0.5, :Vd => 6.0, :Vl => 5.0, :Jc => 1.5)
# the hand-written densities, in declaration order (oracle 1)
const HAND = [
    (Set([:λd, :Vd, :volume]), v -> v[:λd] * (v[:volume] - v[:Vd])^2),
    (Set([:λl, :Vl, :volume]), v -> v[:λl] * (v[:volume] - v[:Vl])^2),
    (Set([:Jc]), v -> v[:Jc]),
]
const POINTS = [
    Dict(:λd => 2.0, :λl => 0.5, :Vd => 6.0, :Vl => 5.0, :Jc => 1.5, :volume => 4.0),
    Dict(:λd => -1.25, :λl => 3.0, :Vd => 0.5, :Vl => -2.0, :Jc => 7.0, :volume => 11.0),
    Dict(:λd => 0.1, :λl => 0.0, :Vd => 40.0, :Vl => 1.0, :Jc => -0.5, :volume => 0.0),
]
# state A: dark 2×2 block, light 1×3 bar below it (two shared bonds): 8 + 2 + 1.5·14 = 31
const HamiltonianσA = (s = zeros(Int32, 6, 6); s[2:3, 2:3] .= 1; s[4, 2:4] .= 2; s)
# state B: dark domino across the periodic row seam, light 3×2 block:
# 2·(2 − 6)² + 0.5·(6 − 5)² + 1.5·(6 + 10) = 56.5
const HamiltonianσB = (s = zeros(Int32, 6, 6); s[6, 3] = 1; s[1, 3] = 1; s[3:5, 5:6] .= 2; s)
const KINDS = [:dark, :light]
# unordered nearest-neighbour bonds (periodic VonNeumann(1)) whose owners differ
function hamiltonian_bonds(σ)
    n1, n2 = size(σ)
    bonds = Tuple{Int32, Int32}[]
    for i in 1:n1, j in 1:n2
        σ[i, j] != σ[mod1(i + 1, n1), j] && push!(bonds, (σ[i, j], σ[mod1(i + 1, n1), j]))
        σ[i, j] != σ[i, mod1(j + 1, n2)] && push!(bonds, (σ[i, j], σ[i, mod1(j + 1, n2)]))
    end
    return bonds
end
# the hand oracle: H of a state of Ham, written out
function hand_H(σ, kinds, v)
    H = 0.0
    for c in eachindex(kinds)
        V = count(==(c), σ)
        H += kinds[c] === :dark ? v[:λd] * (V - v[:Vd])^2 : v[:λl] * (V - v[:Vl])^2
    end
    return H + v[:Jc] * length(hamiltonian_bonds(σ))
end
# H of the same state from `hamiltonian(sys)` by substitution: term 1 over dark cells, term 2
# over light cells, term 3 over the bonds (kind/neighbor_kind bound per bond if the term reads them)
function substituted_H(terms, σ, kinds, v)
    function kindnum(c)
        if c == 0
            return 0
        elseif kinds[c] === :dark
            return 1
        else
            return 2
        end
    end
    H = 0.0
    for (t, k) in ((terms[1], :dark), (terms[2], :light)), c in eachindex(kinds)
        kinds[c] === k || continue
        H += evaluate_at(last(t), merge(v, Dict(:volume => Float64(count(==(c), σ)))))
    end
    for (p, q) in hamiltonian_bonds(σ)
        H += evaluate_at(last(terms[3]), merge(v, Dict(:kind => kindnum(p), :neighbor_kind => kindnum(q))))
    end
    return H
end
# continuous MTK system for the negative controls
function hamiltonian_decay()
    t = Potts.t
    HAMILTONIAN_M.@variables y(t) = 1.0
    HAMILTONIAN_M.@parameters k = 0.1
    return HAMILTONIAN_M.System([Potts.D(y) ~ -k * y], t; name = :decay)
end
struct OtherKey end
# every published model (small lattices; construction only), with its number of `@energy`
# terms as written in lib/PottsModels/src
const MODELS = [
    ("GranerGlazier", () -> GranerGlazier(; name = :gg), 2),
    ("WortelAct", () -> WortelAct(; name = :act, lattice = (8, 8)), 2),
    ("WortelAct connected", () -> WortelAct(; name = :act, lattice = (8, 8), connected = true), 2),
    ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)), 2),
    (
        "MerksVasculogenesis contact-inhibited",
        () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8), contact_inhibited = true), 2,
    ),
    ("Merks2006", () -> Merks2006(; name = :m6, lattice = (16, 16)), 2),
    ("Merks2006 hard", () -> Merks2006(; name = :m6, lattice = (16, 16), rule = :hard), 2),
    ("Merks2008", () -> Merks2008(; name = :m8, lattice = (16, 16)), 2),
    ("Merks2008 extension only", () -> Merks2008(; name = :m8, lattice = (16, 16), mode = :extension_only), 2),
    ("SingleDivisionFixture", () -> SingleDivisionFixture(; name = :fixture), 2),
    ("OpenVTGrowingMonolayer", () -> OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)), 2),
    ("AkeebInvasion", () -> AkeebInvasion(; name = :akeeb, lattice = (60, 40)), 2),
    ("OpenVTChain", () -> OpenVTChain(; name = :chain), 3),
    ("OpenVTReferenceMonolayer", () -> OpenVTReferenceMonolayer(; name = :ref, lattice = (24, 24)), 2),
]
clear(f, words...) = try
    f()
    false
catch err
    err isa ArgumentError && (isempty(words) || occursin(first(words), sprint(showerror, err)))
end
# ---------------------------------------------------------------------------------------
# M. The typed metadata payload

# a PottsSystem keeps its metadata on the complete System it wraps (D-256)
meta(s) = s isa PottsSystem ? Potts.inner(s) : s
hamiltonian_spec(s) = HAMILTONIAN_M.getmetadata(meta(s), Potts.PottsSweepSpec, nothing)
same_terms(a, b) = length(a) == length(b) &&
    all(i -> isequal(HAMILTONIAN_S.unwrap(last(a[i])), HAMILTONIAN_S.unwrap(last(b[i]))), eachindex(a, b))
# ---------------------------------------------------------------------------------------
# X. Downstream detection, and the misuse refusal

# what a downstream package writes: no Potts internals, only MTK's metadata API on an MTK
# `System` (for a `PottsSystem`, the public `Potts.inner(sys)`)
has_sweep(s) = HAMILTONIAN_M.hasmetadata(meta(s), Potts.PottsSweepSpec)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "hamiltonian metadata A: public names with docstrings" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # A. Public names
    @testset "hamiltonian metadata A: public names with docstrings" begin
        for n in (:hamiltonian, :drives, :PottsSweepSpec)
            @test isdefined(Potts, n) && Base.ispublic(Potts, n)
            @test isdefined(Potts, n) && Base.Docs.hasdoc(Potts, n)
        end
        @test isconcretetype(Potts.PottsSweepSpec)
    end
end

@testitem "hamiltonian metadata H: the fixture's terms as written (oracle 1)" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # H. hamiltonian(sys)
    @testset "hamiltonian metadata H: the fixture's terms as written (oracle 1)" begin
        sys = Ham(; name = :hx)
        H = Potts.hamiltonian(sys)
        @test H isa AbstractVector && length(H) == 3                    # the drive is not a term
        @test all(t -> t isa Pair && symbolic(last(t)), H)
        for (t, (names, f)) in zip(H, HAND)
            @test hamiltonian_names(last(t)) == names                         # exactly the symbols written
            @test all(v -> isapprox(evaluate_at(last(t), v), f(v); rtol = 1.0e-12, atol = 1.0e-12), POINTS)
        end
        # the symbols are the model's own: the declared parameter symbols (the complete inner System's)
        c = sys
        @test any(v -> isequal(v, HAMILTONIAN_S.unwrap(c.λd)), HAMILTONIAN_S.get_variables(HAMILTONIAN_S.unwrap(last(H[1]))))
        @test any(v -> isequal(v, HAMILTONIAN_S.unwrap(c.Jc)), HAMILTONIAN_S.get_variables(HAMILTONIAN_S.unwrap(last(H[3]))))
        # neither the temperature nor the drive's parameter is in H
        @test !any(t -> (:T in hamiltonian_names(last(t))) || (:μ in hamiltonian_names(last(t))), H)
        # the same on a compiled system
        for s in (c, mtkcompile(sys))
            Hs = Potts.hamiltonian(s)
            @test length(Hs) == 3 && all(i -> isequal(HAMILTONIAN_S.unwrap(last(Hs[i])), HAMILTONIAN_S.unwrap(last(H[i]))), 1:3)
        end
    end
end

@testitem "hamiltonian metadata H: round trip against the hand H and CorePotts H (oracle 2)" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata H: round trip against the hand H and CorePotts H (oracle 2)" begin
        sys = Ham(; name = :hx)
        H = Potts.hamiltonian(sys)
        @test hand_H(HamiltonianσA, KINDS, VALS) == 31.0     # hand counts (header)
        @test hand_H(HamiltonianσB, KINDS, VALS) == 56.5
        prob = PottsProblem(sys, [ownership => HamiltonianσA, kind => KINDS], (0, 1))
        @test total_energy(prob) == 31.0
        @test substituted_H(H, HamiltonianσA, KINDS, VALS) ≈ 31.0
        pB = remake(prob; u0 = [ownership => HamiltonianσB, kind => KINDS])
        @test total_energy(pB) == 56.5
        @test substituted_H(H, HamiltonianσB, KINDS, VALS) ≈ 56.5
        # the H symbols are live parameters: change Jc and λd through `remake` and H follows
        c = sys
        v2 = merge(VALS, Dict(:Jc => 2.0, :λd => 0.5))
        p2 = remake(prob; p = [c.Jc => 2.0, c.λd => 0.5])
        want = hand_H(HamiltonianσA, KINDS, v2)
        @test want == 0.5 * 4 + 2 + 2.0 * 14 == 32.0
        @test total_energy(p2) ≈ want
        @test substituted_H(H, HamiltonianσA, KINDS, v2) ≈ want
        # negative control: swapping the per-kind terms (the wrong domain) gives the wrong H
        @test !(substituted_H(H[[2, 1, 3]], HamiltonianσA, KINDS, VALS) ≈ 31.0)
    end
end

@testitem "hamiltonian metadata H: extend merges the terms" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata H: extend merges the terms" begin
        base = Ham(; name = :hx)
        ext = extend(Extra(; name = :extra), base)
        H = Potts.hamiltonian(ext)
        @test length(H) == 4
        got = Set(string(HAMILTONIAN_S.unwrap(last(t))) for t in H)
        want = Set(string(HAMILTONIAN_S.unwrap(last(t))) for t in [Potts.hamiltonian(base); Potts.hamiltonian(Extra(; name = :extra))])
        @test got == want
        @test any(t -> hamiltonian_names(last(t)) == Set([:κ, :volume]), H)
    end
end

@testitem "hamiltonian metadata H: published models" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata H: published models" begin
        @testset "$label" for (label, build, nterms) in MODELS
            sys = build()
            H = Potts.hamiltonian(sys)
            @test H isa AbstractVector && length(H) == nterms
            @test all(t -> t isa Pair && symbolic(last(t)), H)
            declared = Set{Symbol}(hamiltonian_name(x) for x in [HAMILTONIAN_M.parameters(sys); HAMILTONIAN_M.unknowns(sys)])
            for t in H
                extra = setdiff(hamiltonian_names(last(t)), declared, BUILTINS)
                isempty(extra) || @info "hamiltonian metadata: $label H term reads undeclared $(collect(extra))"
                @test isempty(extra)
            end
            @test length(Potts.hamiltonian(mtkcompile(sys))) == nterms
        end
        # Graner–Glazier as written: λ(volume − V₀)² and J[kind, neighbor_kind]; T is not an energy
        H = Potts.hamiltonian(GranerGlazier(; name = :gg))
        @test hamiltonian_names(last(H[1])) == Set([:λ, :V₀, :volume])
        @test hamiltonian_names(last(H[2])) == Set([:J, :kind, :neighbor_kind])
        @test evaluate_at(last(H[1]), Dict(:λ => 1.0, :V₀ => 40.0, :volume => 37.0)) == 9.0
        # Wortel: the act drive is not in H
        Hw = Potts.hamiltonian(WortelAct(; name = :act, lattice = (8, 8)))
        @test hamiltonian_names(last(Hw[1])) == Set([:λ, :V₀, :λₛ, :S₀, :volume, :surface])
        @test !any(t -> !isdisjoint(hamiltonian_names(last(t)), (:λ_act, :max_act)), Hw)
    end
end

@testitem "hamiltonian metadata D: drives" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # D. drives(sys)
    @testset "hamiltonian metadata D: drives" begin
        d = Potts.drives(Ham(; name = :hx))
        @test d isa AbstractVector && length(d) == 1 && symbolic(only(d))
        @test hamiltonian_names(only(d)) == Set([:new, :μ])
        @test isempty(Potts.drives(GranerGlazier(; name = :gg)))
        @test isempty(Potts.drives(OpenVTChain(; name = :chain)))
        dw = Potts.drives(WortelAct(; name = :act, lattice = (8, 8)))
        @test length(dw) == 1 && issubset((:λ_act, :max_act), hamiltonian_names(only(dw)))
        @test length(Potts.drives(AkeebInvasion(; name = :akeeb, lattice = (60, 40)))) == 1
        @test length(Potts.drives(mtkcompile(Ham(; name = :hx)))) == 1
    end
end

@testitem "hamiltonian metadata M: the fixture's payload" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata M: the fixture's payload" begin
        sys = Ham(; name = :hx)
        @test HAMILTONIAN_M.hasmetadata(Potts.inner(sys), Potts.PottsSweepSpec)
        spec = hamiltonian_spec(sys)
        @test spec isa Potts.PottsSweepSpec
        @test same_terms(spec.hamiltonian, Potts.hamiltonian(sys))
        @test length(spec.drives) == 1 && isequal(HAMILTONIAN_S.unwrap(only(spec.drives)), HAMILTONIAN_S.unwrap(only(Potts.drives(sys))))
        @test length(spec.constraints) == 1
        @test isequal(HAMILTONIAN_S.unwrap(spec.temperature), HAMILTONIAN_S.unwrap(sys.T))
        @test spec.proposal == Moore(1)
        @test startswith(sprint(show, MIME"text/plain"(), spec), "PottsSweepSpec")
        @test occursin("PottsSweepSpec", sprint(show, spec))
        # present after mtkcompile (on the compiled system and on its `.sys`)
        cs = mtkcompile(sys)
        for s in (cs, getfield(cs, :sys))
            @test HAMILTONIAN_M.hasmetadata(meta(s), Potts.PottsSweepSpec)
            @test hamiltonian_spec(s) isa Potts.PottsSweepSpec && same_terms(hamiltonian_spec(s).hamiltonian, spec.hamiltonian)
        end
        # other keys are untouched: absent unless set, and set out of place as before
        i = Potts.inner(sys)
        @test HAMILTONIAN_M.getmetadata(i, OtherKey, :none) === :none && !HAMILTONIAN_M.hasmetadata(i, OtherKey)
        s2 = HAMILTONIAN_M.setmetadata(i, OtherKey, 42)
        @test HAMILTONIAN_M.getmetadata(s2, OtherKey, :none) == 42 && hamiltonian_spec(s2) isa Potts.PottsSweepSpec
    end
end

@testitem "hamiltonian metadata M: extend gives the merged model's payload" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata M: extend gives the merged model's payload" begin
        base = Ham(; name = :hx)
        ext = extend(Extra(; name = :extra), base)
        spec = hamiltonian_spec(ext)
        @test spec isa Potts.PottsSweepSpec
        @test length(spec.hamiltonian) == 4                             # not the base's 3, not the extra's 1
        @test same_terms(spec.hamiltonian, Potts.hamiltonian(ext))
        @test length(spec.drives) == 1 && length(spec.constraints) == 1
    end
end

@testitem "hamiltonian metadata M: published models" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata M: published models" begin
        @testset "$label" for (label, build, nterms) in MODELS
            sys = build()
            @test HAMILTONIAN_M.hasmetadata(Potts.inner(sys), Potts.PottsSweepSpec)
            spec = hamiltonian_spec(sys)
            @test spec isa Potts.PottsSweepSpec
            @test same_terms(spec.hamiltonian, Potts.hamiltonian(sys)) && length(spec.hamiltonian) == nterms
            @test length(spec.drives) == length(Potts.drives(sys))
            @test spec.proposal isa CorePotts.AbstractRelationSpec
        end
        gg = GranerGlazier(; name = :gg)
        @test isequal(HAMILTONIAN_S.unwrap(hamiltonian_spec(gg).temperature), HAMILTONIAN_S.unwrap(gg.T))
        @test hamiltonian_spec(gg).proposal == Moore(1)
        @test hamiltonian_spec(AkeebInvasion(; name = :akeeb, lattice = (60, 40))).proposal == VonNeumann(1)
        @test length(hamiltonian_spec(AkeebInvasion(; name = :akeeb, lattice = (60, 40))).constraints) == 2
        @test isempty(hamiltonian_spec(WortelAct(; name = :act, lattice = (8, 8))).constraints)
        @test length(hamiltonian_spec(WortelAct(; name = :act, lattice = (8, 8), connected = true)).constraints) == 1
    end
end

@testitem "hamiltonian metadata N: a plain System has no sweep payload" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # N. Negative controls: a plain MTK System
    @testset "hamiltonian metadata N: a plain System has no sweep payload" begin
        mtk = hamiltonian_decay()
        simple = HAMILTONIAN_M.mtkcompile(mtk)
        for s in (mtk, simple)
            @test HAMILTONIAN_M.getmetadata(s, isdefined(Potts, :PottsSweepSpec) ? Potts.PottsSweepSpec : OtherKey, nothing) === nothing
            @test !HAMILTONIAN_M.hasmetadata(s, isdefined(Potts, :PottsSweepSpec) ? Potts.PottsSweepSpec : OtherKey)
        end
        @test HAMILTONIAN_M.ODEProblem(simple, [], (0.0, 1.0)) isa Potts.SciMLBase.ODEProblem
    end
end

@testitem "hamiltonian metadata X: generic code detects the sweep" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata X: generic code detects the sweep" begin
        @test !has_sweep(hamiltonian_decay()) && !has_sweep(HAMILTONIAN_M.mtkcompile(hamiltonian_decay()))
        @test has_sweep(Ham(; name = :hx)) && has_sweep(mtkcompile(Ham(; name = :hx)))
        @test all(c -> has_sweep(c[2]()), MODELS)
    end
end

@testitem "hamiltonian metadata X: ODEProblem and JumpProblem refuse every published model (regression guard)" setup = [HamiltonianMetadataSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "hamiltonian metadata X: ODEProblem and JumpProblem refuse every published model (regression guard)" begin
        @testset "$label" for (label, build, _) in MODELS
            sys = build()
            @test clear(() -> HAMILTONIAN_M.ODEProblem(sys, [], (0.0, 1.0)), "ODEProblem", "PottsProblem")
            @test clear(() -> HAMILTONIAN_M.JumpProblem(sys, [], (0.0, 1.0)), "JumpProblem", "PottsProblem")
        end
    end
end
