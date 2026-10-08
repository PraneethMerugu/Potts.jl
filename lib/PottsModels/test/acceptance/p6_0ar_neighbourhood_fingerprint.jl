# P6.0ar (ROADMAP Phase 6, step 0): the proposal and contact neighbourhoods are in the
# fingerprint. Decision: D-122 (amends D-016, after D-118 and D-121). Frozen (AUTONOMY §7.3).
#
# The defect (P6.0aq test author, D-121 "Follow-up"). The fingerprint hashes the generated
# code, the lattice (its `neighborhood = …` by content), spacing, `T`, the canonical solver
# spec, the non-default cadences (D-118) and the non-default acceptance law (D-121)
# (`_problem_function`, src/problem.jl). `@relations proposal = …` and `@relations contact =
# …` are relation specs that reach the run as data (`PottsProblem.proposal`, the resolved
# `ctx.contact`), not as code, so they reach no hash. Measured on f137f929 with the fixture
# below (12×12 periodic, `neighborhood` omitted = Moore(1)): proposal omitted, Moore(1) and
# VonNeumann(1), and contact VonNeumann(1), Moore(1) and Moore(2), all fingerprint
# 0x6eb337cf0a174b0e (the D-121 fixture's value), so a checkpoint loads across copy
# neighbourhoods and across contact neighbourhoods although the contact one changes the
# energy. Hexagonal and 3D lattices likewise (e.g. hex proposal Hex(2) vs omitted, both
# 0x30481847bccda4d8).
#
# The defaults (src/compile.jl, `compile`): contact = the lattice's `neighborhood` (already
# hashed through the lattice); proposal = `VonNeumann(1)` on every lattice (the first shell:
# 4 in 2D, 6 in 3D, the 6-neighbour hex ball on a hexagonal lattice). Moore(1) is NOT the
# proposal default, so the published models that declare `proposal = Moore(1)`
# (GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer) fingerprint like
# the default today and MUST move: no rule can tell Moore(1) from the default while keeping
# both the Moore(1) pins and the pins of the many models that omit the proposal. Hashing only
# a non-default proposal moves the fewest pins (those four systems and the p6_0af fixture
# that declares Moore(1)); AkeebInvasion declares `VonNeumann(1)` (the default) and holds.
#
# Rule pinned here (D-122): a neighbourhood is its resolved relation on the problem's lattice
# (`CorePotts.relation(spec, lattice)`: canonically ordered offsets and weights). The
# proposal is hashed when its resolved relation differs from that of `VonNeumann(1)`; the
# contact when it differs from that of the lattice's `neighborhood`; each with its role, so
# `proposal = Moore(2)` and `contact = Moore(2)` differ. An explicit spec that resolves to
# the default (VonNeumann(1), NeighborOrder(1), a permuted Stencil, Moore(1) or Hex(1) on a
# hexagonal lattice) fingerprints like omission; weights hash by value, so two textually
# equal weight closures (two anonymous functions) fingerprint alike.
#
# OUT OF SCOPE (reported to the coordinator, not frozen here): named relations (`@relations
# far = Ball(2.0)` used by `contacts(far)` or a fold `for n in far(site)`) and inline gather
# relations (`for n in Moore(1)(42)` vs `Moore(2)(42)`) reach the run as `ctx` data too and
# collide the same way on f137f929; they have no default, so hashing them moves the pins of
# every fixture that uses one.
#
# Semantics pinned here:
#  1. Controls (pass on the base): the contact neighbourhood changes the energy of the same
#     state; the proposal changes the run (accepted copies at one seed); the lattice
#     neighbourhood is already hashed (negative control: the fingerprint is not constant);
#     explicit defaults fingerprint like omission and their checkpoints load into each
#     other; the algorithm's own `proposal` keyword is a run choice (D-121): a checkpoint
#     continues under `SequentialCPM(; proposal = Moore(1))`.
#  2. Problems that differ only in the proposal or the contact neighbourhood have pairwise
#     different fingerprints, on a square 2D (Float64 and Float32), hexagonal and 3D lattice.
#  3. A checkpoint of one fails to load into another with an `ArgumentError` (in memory and
#     through save_checkpoint/load_checkpoint); a fresh build of the same model loads it.
#  4. Pins: the fixture's default fingerprints (recorded on f137f929) and the PottsModels
#     systems that do not declare a non-default neighbourhood (SingleDivisionFixture,
#     AkeebInvasion; P6.0p pins of 4e81e1eb) are unchanged; the four systems declaring
#     `proposal = Moore(1)` no longer carry their old pins (the implementer re-pins them in
#     the earlier frozen files under D-122, with the p6_0af fixture `P60AF_FP_COUNTER`,
#     which declares `proposal = Moore(1)` too) and still fingerprint deterministically.
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures: one model per lattice and `@relations` content

const P60AR_LATTICES = Dict(
    :sq => :(Lattice((12, 12))),
    :hex => :(Lattice((12, 12); geometry = Hexagonal())),
    :cube => :(Lattice((8, 8, 8))),
    :sqvn => :(Lattice((12, 12); neighborhood = VonNeumann(1))),
)
# label => (lattice, @relations body or nothing[, :weight: the contact energy reads `weight`])
const P60AR_FIXTURES = [
    # square 2D: the default and non-default proposals
    "sq" => (:sq, nothing),
    "sq proposal=Moore(1)" => (:sq, :(proposal = Moore(1))),
    "sq proposal=Moore(2)" => (:sq, :(proposal = Moore(2))),
    "sq proposal=NeighborOrder(3)" => (:sq, :(proposal = NeighborOrder(3))),
    "sq proposal=Stencil(±x)" => (:sq, :(proposal = Stencil([[1, 0], [-1, 0]]))),
    # square 2D: the default proposal given explicitly
    "sq proposal=VonNeumann(1)" => (:sq, :(proposal = VonNeumann(1))),
    "sq proposal=NeighborOrder(1)" => (:sq, :(proposal = NeighborOrder(1))),
    "sq proposal=Stencil(VN1 permuted)" => (:sq, :(proposal = Stencil([[0, 1], [1, 0], [0, -1], [-1, 0]]))),
    # square 2D: non-default contacts
    "sq contact=VonNeumann(1)" => (:sq, :(contact = VonNeumann(1))),
    "sq contact=Moore(2)" => (:sq, :(contact = Moore(2))),
    "sq contact=Ball(3.0)" => (:sq, :(contact = Ball(3.0))),
    # weighted contacts, with a contact energy that reads the weight (`contacts => weight`)
    "sq contact=Weighted(Moore(1), 2)" => (:sq, :(contact = Weighted(Moore(1), o -> 2.0)), :weight),
    "sq contact=Weighted(Moore(1), 2) again" => (:sq, :(contact = Weighted(Moore(1), o -> 2.0)), :weight),
    "sq contact=Weighted(Moore(1), 3)" => (:sq, :(contact = Weighted(Moore(1), o -> 3.0)), :weight),
    # square 2D: the default contact (the lattice's Moore(1)) given explicitly
    "sq contact=Moore(1)" => (:sq, :(contact = Moore(1))),
    "sq contact=NeighborOrder(2)" => (:sq, :(contact = NeighborOrder(2))),
    "sq contact=Stencil(Moore1 permuted)" => (:sq, :(contact = Stencil([[1, 1], [0, 1], [-1, 1], [1, 0], [-1, 0], [1, -1], [0, -1], [-1, -1]]))),
    # both roles at once
    "sq proposal=Moore(1) contact=VonNeumann(1)" => (:sq, quote
        proposal = Moore(1)
        contact = VonNeumann(1)
    end),
    # a lattice whose own neighbourhood is VonNeumann(1): Moore(1) contact is non-default there
    "sqvn" => (:sqvn, nothing),
    "sqvn contact=Moore(1)" => (:sqvn, :(contact = Moore(1))),
    "sqvn contact=VonNeumann(1)" => (:sqvn, :(contact = VonNeumann(1))),
    # hexagonal 2D: Moore(1), VonNeumann(1) and Hex(1) are the same 6-neighbour ball
    "hex" => (:hex, nothing),
    "hex proposal=Hex(2)" => (:hex, :(proposal = Hex(2))),
    "hex contact=Hex(2)" => (:hex, :(contact = Hex(2))),
    "hex proposal=Moore(1)" => (:hex, :(proposal = Moore(1))),
    "hex proposal=Hex(1)" => (:hex, :(proposal = Hex(1))),
    "hex contact=Hex(1)" => (:hex, :(contact = Hex(1))),
    "hex contact=VonNeumann(1)" => (:hex, :(contact = VonNeumann(1))),
    # 3D
    "cube" => (:cube, nothing),
    "cube proposal=Moore(1)" => (:cube, :(proposal = Moore(1))),
    "cube proposal=NeighborOrder(2)" => (:cube, :(proposal = NeighborOrder(2))),
    "cube contact=VonNeumann(1)" => (:cube, :(contact = VonNeumann(1))),
    "cube contact=NeighborOrder(2)" => (:cube, :(contact = NeighborOrder(2))),
    "cube proposal=VonNeumann(1)" => (:cube, :(proposal = VonNeumann(1))),
    "cube contact=Moore(1)" => (:cube, :(contact = Moore(1))),
    "cube contact=NeighborOrder(3)" => (:cube, :(contact = NeighborOrder(3))),
]
const P60AR_MODELS = Dict{String, Any}()
const P60AR_LATTICE_OF = Dict{String, Symbol}()
for (i, (label, spec)) in enumerate(P60AR_FIXTURES)
    lk, rel = spec[1], spec[2]
    J = length(spec) == 3 ? :(1.0 * weight) : 1.0
    name = Symbol(:P60arNbhd, i)
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), rel)
    lat = P60AR_LATTICES[lk]
    @eval @potts_model $name begin
        @kinds medium A
        @lattice $lat
        $relx
        @energy cells => (volume - 9.0)^2
        @energy contacts => $J
        @sweep Metropolis(; temperature = 2.0)
    end
    P60AR_MODELS[label] = @eval $name
    P60AR_LATTICE_OF[label] = lk
end

"""Two cells of kind A: 3×3 squares on a 12×12 lattice, 2×2×2 cubes on an 8×8×8 one."""
function p60ar_op(lk::Symbol)
    if lk === :cube
        σ = zeros(Int32, 8, 8, 8)
        σ[2:3, 2:3, 2:3] .= 1
        σ[5:6, 5:6, 5:6] .= 2
    else
        σ = zeros(Int32, 12, 12)
        σ[2:4, 2:4] .= 1
        σ[7:9, 7:9] .= 2
    end
    return [ownership => σ, kind => [:A, :A]]
end

p60ar_problem(label; T = Float64, tspan = (0, 12), seed = 1) =
    PottsProblem(P60AR_MODELS[label](; name = :nbhd), p60ar_op(P60AR_LATTICE_OF[label]), tspan; T, seed)
p60ar_fp(label; T = Float64) = p60ar_problem(label; T).f.fingerprint

"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function p60ar_pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "P6.0ar: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end

"""Each label fingerprints like `base` (one @test per label)."""
function p60ar_like(base, labels; T = Float64)
    f0 = p60ar_fp(base; T)
    for label in labels
        fp = p60ar_fp(label; T)
        @test fp == f0
        fp == f0 || @info "P6.0ar: `$label` ($(repr(fp))) does not fingerprint like `$base` ($(repr(f0)))"
    end
end

"""A checkpoint of `pa` after `k` MCS under `alg`: refused by `pb` (ArgumentError) unless
`pb === nothing`, accepted by `pa2` under `alg2`, in memory and through a file."""
function p60ar_checkpoint(pa, pb, pa2; k = 3, alg = SequentialCPM(), alg2 = alg)
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "p60ar.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg2; checkpoint = c)
        @test i2.t == k
        @test i2.u.σ == ck.state.σ
    end
end

p60ar_accepted(label; n = 12, seed = 1) = solve(p60ar_problem(label; tspan = (0, n), seed), SequentialCPM()).stats.accepted

# ---------------------------------------------------------------------------------------
# 1. Controls (pass on the base)

@testset "P6.0ar: controls — the neighbourhoods change the model" begin
    # the fixtures carry the neighbourhoods they declare
    @test p60ar_problem("sq").proposal == VonNeumann(1)
    @test p60ar_problem("sq proposal=Moore(1)").proposal == Moore(1)
    @test length(p60ar_problem("sq").contact) == 8
    @test length(p60ar_problem("sq contact=VonNeumann(1)").contact) == 4
    @test length(p60ar_problem("sq contact=Moore(2)").contact) == 24
    @test length(p60ar_problem("hex").contact) == 6
    @test length(p60ar_problem("cube").contact) == 26
    # the contact neighbourhood changes the energy of the same state
    E(label) = (p = p60ar_problem(label); total_energy(p, p.u0))
    @test E("sq contact=VonNeumann(1)") != E("sq")
    @test E("sq contact=Moore(2)") != E("sq")
    @test E("sq contact=Weighted(Moore(1), 3)") != E("sq contact=Weighted(Moore(1), 2)")
    @test E("cube contact=VonNeumann(1)") != E("cube")
    # the proposal neighbourhood changes the run (the same seed)
    a0 = p60ar_accepted("sq")
    @test a0 > 0
    @test p60ar_accepted("sq proposal=Moore(2)") != a0
    @test p60ar_accepted("sq") == a0                      # a function of the model, not of chance
end

@testset "P6.0ar: controls — negative control and the run-choice override" begin
    # the fingerprint is not constant: the lattice's own neighbourhood is already hashed
    @test p60ar_fp("sqvn") != p60ar_fp("sq")
    @test p60ar_fp("hex") != p60ar_fp("sq")
    # the algorithm's `proposal` keyword is a run choice (D-121), not the problem's
    p60ar_checkpoint(p60ar_problem("sq"), nothing, p60ar_problem("sq");
        alg = SequentialCPM(), alg2 = SequentialCPM(; proposal = Moore(1)))
end

# ---------------------------------------------------------------------------------------
# 2. A different proposal or contact neighbourhood, a different fingerprint

const P60AR_SQ_DISTINCT = ["sq", "sq proposal=Moore(1)", "sq proposal=Moore(2)", "sq proposal=NeighborOrder(3)",
    "sq proposal=Stencil(±x)", "sq contact=VonNeumann(1)", "sq contact=Moore(2)", "sq contact=Ball(3.0)",
    "sq contact=Weighted(Moore(1), 2)", "sq contact=Weighted(Moore(1), 3)", "sq proposal=Moore(1) contact=VonNeumann(1)"]
const P60AR_SQVN_DISTINCT = ["sqvn", "sqvn contact=Moore(1)"]
const P60AR_HEX_DISTINCT = ["hex", "hex proposal=Hex(2)", "hex contact=Hex(2)"]
const P60AR_CUBE_DISTINCT = ["cube", "cube proposal=Moore(1)", "cube proposal=NeighborOrder(2)",
    "cube contact=VonNeumann(1)", "cube contact=NeighborOrder(2)"]

@testset "P6.0ar: the proposal and contact neighbourhoods are in the fingerprint" begin
    @testset "square 2D, Float64" begin
        p60ar_pairwise_distinct([label => p60ar_fp(label) for label in P60AR_SQ_DISTINCT])
    end
    @testset "square 2D, Float32" begin
        p60ar_pairwise_distinct([label => p60ar_fp(label; T = Float32) for label in P60AR_SQ_DISTINCT])
    end
    @testset "square 2D, lattice neighbourhood VonNeumann(1)" begin
        p60ar_pairwise_distinct([label => p60ar_fp(label) for label in P60AR_SQVN_DISTINCT])
    end
    @testset "hexagonal 2D" begin
        p60ar_pairwise_distinct([label => p60ar_fp(label) for label in P60AR_HEX_DISTINCT])
    end
    @testset "3D" begin
        p60ar_pairwise_distinct([label => p60ar_fp(label) for label in P60AR_CUBE_DISTINCT])
    end
    @testset "deterministic: the same model built twice fingerprints alike" begin
        for label in [P60AR_SQ_DISTINCT; P60AR_HEX_DISTINCT; P60AR_CUBE_DISTINCT]
            @test p60ar_fp(label) == p60ar_fp(label)
        end
    end
end

@testset "P6.0ar: a neighbourhood that resolves to the default fingerprints like omission" begin
    @testset "proposal, square 2D (Float64 and Float32)" begin
        for T in (Float64, Float32)
            p60ar_like("sq", ["sq proposal=VonNeumann(1)", "sq proposal=NeighborOrder(1)", "sq proposal=Stencil(VN1 permuted)"]; T)
        end
    end
    @testset "contact, square 2D (Float64 and Float32)" begin
        for T in (Float64, Float32)
            p60ar_like("sq", ["sq contact=Moore(1)", "sq contact=NeighborOrder(2)", "sq contact=Stencil(Moore1 permuted)"]; T)
        end
        p60ar_like("sqvn", ["sqvn contact=VonNeumann(1)"])
    end
    @testset "hexagonal 2D" begin
        p60ar_like("hex", ["hex proposal=Moore(1)", "hex proposal=Hex(1)", "hex contact=Hex(1)", "hex contact=VonNeumann(1)"])
    end
    @testset "3D" begin
        p60ar_like("cube", ["cube proposal=VonNeumann(1)", "cube contact=Moore(1)", "cube contact=NeighborOrder(3)"])
    end
    @testset "weights hash by value, not by the weight function" begin
        p60ar_like("sq contact=Weighted(Moore(1), 2)", ["sq contact=Weighted(Moore(1), 2) again"])
    end
end

# ---------------------------------------------------------------------------------------
# 3. Checkpoints do not cross proposal or contact neighbourhoods

@testset "P6.0ar: a checkpoint does not load under another neighbourhood" begin
    pr = p60ar_problem
    @testset "proposal Moore(1) → default" begin
        p60ar_checkpoint(pr("sq proposal=Moore(1)"), pr("sq"), pr("sq proposal=Moore(1)"))
    end
    @testset "proposal default → Moore(1)" begin
        p60ar_checkpoint(pr("sq"), pr("sq proposal=Moore(1)"), pr("sq"))
    end
    @testset "contact Moore(2) → default, CheckerboardCPM" begin
        p60ar_checkpoint(pr("sq contact=Moore(2)"), pr("sq"), pr("sq contact=Moore(2)"); alg = CheckerboardCPM())
    end
    @testset "contact default → VonNeumann(1)" begin
        p60ar_checkpoint(pr("sq"), pr("sq contact=VonNeumann(1)"), pr("sq"))
    end
    @testset "contact weights 2 → 3" begin
        p60ar_checkpoint(pr("sq contact=Weighted(Moore(1), 2)"), pr("sq contact=Weighted(Moore(1), 3)"),
            pr("sq contact=Weighted(Moore(1), 2)"))
    end
    @testset "proposal Moore(2) → contact Moore(2): the role is hashed" begin
        p60ar_checkpoint(pr("sq proposal=Moore(2)"), pr("sq contact=Moore(2)"), pr("sq proposal=Moore(2)"))
    end
    @testset "Float32: contact VonNeumann(1) → default" begin
        p60ar_checkpoint(pr("sq contact=VonNeumann(1)"; T = Float32), pr("sq"; T = Float32),
            pr("sq contact=VonNeumann(1)"; T = Float32))
    end
    @testset "hexagonal: proposal Hex(2) → default" begin
        p60ar_checkpoint(pr("hex proposal=Hex(2)"), pr("hex"), pr("hex proposal=Hex(2)"))
    end
    @testset "3D: proposal Moore(1) → default" begin
        p60ar_checkpoint(pr("cube proposal=Moore(1)"), pr("cube"), pr("cube proposal=Moore(1)"))
    end
    @testset "3D: contact NeighborOrder(2) → default" begin
        p60ar_checkpoint(pr("cube contact=NeighborOrder(2)"), pr("cube"), pr("cube contact=NeighborOrder(2)"))
    end
end

@testset "P6.0ar: a checkpoint loads across an explicit default and omission" begin
    pr = p60ar_problem
    p60ar_checkpoint(pr("sq proposal=VonNeumann(1)"), nothing, pr("sq"))
    p60ar_checkpoint(pr("sq"), nothing, pr("sq contact=Moore(1)"))
    p60ar_checkpoint(pr("hex proposal=Hex(1)"), nothing, pr("hex"))
    p60ar_checkpoint(pr("cube contact=NeighborOrder(3)"), nothing, pr("cube"))
end

# ---------------------------------------------------------------------------------------
# 4. Pins

function p60ar_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
p60ar_gg() = (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10)))
p60ar_wortel(; kw...) = PottsProblem(WortelAct(; name = :act, lattice = (8, 8), kw...), p60ar_two_wortel(), (0, 10))
p60ar_merks() = PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
    [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
    field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0))
p60ar_openvt() = PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
    openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64)

# default neighbourhoods: unchanged. The fixture values were recorded on f137f929 ("sq" is
# also the D-121 fixture's pin); the PottsModels systems are the P6.0p pins (4e81e1eb).
p60ar_unchanged() = (
    "sq" => () -> p60ar_problem("sq"),
    "sq proposal=VonNeumann(1)" => () -> p60ar_problem("sq proposal=VonNeumann(1)"),
    "sq contact=Moore(1)" => () -> p60ar_problem("sq contact=Moore(1)"),
    "hex" => () -> p60ar_problem("hex"),
    "cube" => () -> p60ar_problem("cube"),
    "sq Float32" => () -> p60ar_problem("sq"; T = Float32),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
)
const P60AR_FINGERPRINTS = Dict{String, UInt64}(
    "sq" => 0x6eb337cf0a174b0e,
    "sq proposal=VonNeumann(1)" => 0x6eb337cf0a174b0e,
    "sq contact=Moore(1)" => 0x6eb337cf0a174b0e,
    "hex" => 0x30481847bccda4d8,
    "cube" => 0x42f8b19ae169b688,
    "sq Float32" => 0x70e73072398309e0,
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "AkeebInvasion" => 0x8d33bd0bb1eddd1c,
)

# `proposal = Moore(1)`: the old pins (P6.0p, 4e81e1eb) must move; the new values are
# recorded by the implementer in D-122 and re-pinned in the earlier frozen files.
p60ar_moved() = (
    "GranerGlazier" => p60ar_gg,
    "WortelAct" => () -> p60ar_wortel(),
    "WortelAct connected" => () -> p60ar_wortel(; connected = true),
    "MerksVasculogenesis" => p60ar_merks,
    "OpenVTGrowingMonolayer" => p60ar_openvt,
)
const P60AR_OLD_FINGERPRINTS = Dict{String, UInt64}(
    "GranerGlazier" => 0x8942dc9ed483ec21,
    "WortelAct" => 0xeec6e447bfffba66,
    "WortelAct connected" => 0x9627f9c719353a2c,
    "MerksVasculogenesis" => 0xe8c37fa651d985f6,
    "OpenVTGrowingMonolayer" => 0xfe0d128235b9b8a6,
)

@testset "P6.0ar: fingerprints under the default neighbourhoods unchanged" begin
    for (name, build) in p60ar_unchanged()
        prob = build()
        @test CorePotts.relation(prob.proposal, prob.lattice) == CorePotts.relation(VonNeumann(1), prob.lattice)
        fp = prob.f.fingerprint
        @test fp == P60AR_FINGERPRINTS[name]
        fp == P60AR_FINGERPRINTS[name] || @info "P6.0ar: fingerprint $name = $(repr(fp))"
    end
end

@testset "P6.0ar: systems declaring proposal = Moore(1) move off their old pins" begin
    for (name, build) in p60ar_moved()
        prob = build()
        @test prob.proposal == Moore(1)                                     # the fixture is what it claims
        fp = prob.f.fingerprint
        @test fp != P60AR_OLD_FINGERPRINTS[name]
        @test build().f.fingerprint == fp                                   # deterministic
        @info "P6.0ar: fingerprint $name = $(repr(fp))"
    end
end
