# named and inline gather relations are in the
# fingerprint. Decision: D-124 (amends D-016, after D-122).
#
# The defect (D-122 "Follow-up"). A named relation (`@relations far =
# EuclideanBall(2.0)`, read by `contacts(far)` or a fold `for n in far(site)`) and an inline
# gather relation (`for n in Moore(1)(42)`) reach the generated code only as a field of the
# run context (`ctx.far`, `ctx.gather1`: the compiler numbers inline gathers `gather1`,
# `gather2`, … in statement order, D-107); their resolved offsets and weights are runtime
# data, not constants in the kernels. So the code hash sees the NAME a statement reads and
# which statement reads which gather, but not the relation itself. Measured on e4b6ab51 with
# the fixtures below (12×12 periodic, Moore(1) lattice neighbourhood): `contacts(far)` with
# far
# = EuclideanBall(2.0) vs EuclideanBall(3.0) (energies 112 vs 360 on the same state), a
# cell-energy fold `far(40)` (0.5 vs 0.8), an inline gather `Moore(1)(40)` vs `Moore(2)(40)`
# in a cell energy (0.3 vs 0.8), in a cell ODE, in a `@drive`, a named relation in a cell
# ODE or a `@drive`, and `Weighted(Moore(1), 2)` vs `3` all fingerprint alike pairwise, so a
# checkpoint loads across them although the energy or the dynamics differ.
#
# Amended under D-209. The cell-energy fixtures ("… energy …") originally folded
# `count(owner[n] == id for n in R(40))`, a σ-dependent gather that D-209 refuses at
# `mtkcompile` (its ΔH was wrong). They now fold the same count over a static site value,
# `0.1 * volume * count(q[n] == id for n in R(40))`, with `q` the initial owner map set from
# the operating point (every fixture's operating point carries it; `q` stays a site variable
# the "update" fixtures overwrite after each MCS). The fold reads the same relation at the
# same site and is read by the generated ΔH (through `volume`), so it enters the fingerprint
# as before; energies still differ between the twins. Nothing else changed.
#
# Already reflected in the code (pass on the base; pinned so the rule does not lose them):
#  - the name of a named relation (`contacts(far)` vs `contacts(near)`, same spec) differs,
#    as renaming anything the generated code reads does;
#  - which use site reads which inline gather (`Moore(2)` at `source` and `Moore(1)` at
#    `target` vs the swap) differs: the code reads `ctx.gather1` at one site and
#    `ctx.gather2` at the other.
# Not in the fingerprint, by design (pass on the base):
#  - a relation declared but read by nothing (it changes nothing);
#  - a relation read only by `@observed` quantities: observed functions are built at query
#    time and are not part of the fingerprint (an observed quantity changes no dynamics and
#    no saved state), so neither is what they read;
#  - `surface`: it cannot be declared (`@relations surface = …` is refused as a built-in
#    name) and is always the lattice's neighbourhood, already hashed through the lattice.
#
# Rule pinned here (D-124): every named or inline gather relation that the generated code
# reads is hashed, resolved on the problem's lattice (`CorePotts.relation(spec, lattice)`:
# canonically ordered offsets, weights by value) and keyed by its context name (the
# relation's name, or the `gatherN` the compiler gives the inline spec; the code ties that
# name to its use sites). There is no default to skip. Specs that resolve alike fingerprint
# alike (`EuclideanBall(1.5)`, `Moore(1)` and a permuted Moore(1) `Stencil` on a square
# lattice; `Hex(1)` and `Moore(1)` on a hexagonal one; `NeighborOrder(2)` and `Moore(1)`
# inline; a permuted inline `Stencil`). A checkpoint does not load across problems that
# differ in one (`ArgumentError`). The proposal and contact neighbourhoods keep their D-122
# rule.
#
# Pins. A model that reads no named or inline gather relation keeps its fingerprint (the
# relation-free fixtures here, the D-122 `proposal = Moore(1)` fixture, GranerGlazier,
# MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture, AkeebInvasion). Models
# that read one MUST move: WortelAct (both variants; its drive folds an inline
# `Moore(1; include_self = true)` gather) and the `canonical_term_order_tests.jl` fixture
# `CanonicalAt` (an inline `Moore(1)(42)` in a cell rate). Their pins in the earlier files
# (`acceptance_law_fingerprint_tests.jl`, `cadence_fingerprint_tests.jl`,
# `integral_refresh_tests.jl`, `gather_ode_allocations_tests.jl`,
# `canonical_term_order_tests.jl`) are re-pinned by the implementer under D-124 (pin lines
# only); here they are only required to differ from the old values and to be deterministic.

@testsetup module RelationFingerprintSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Fixtures: one model per lattice, `@relations` content and use
const LATTICES = Dict(
    :sq => :(Lattice((12, 12))),
    :hex => :(Lattice((12, 12); geometry = Hexagonal())),
    :cube => :(Lattice((8, 8, 8)))
)
# a fold of relation `r` (a name or an inline spec call) around a fixed site: 40 = (4, 4), a
# corner of cell 1 on the 12×12 lattices; 74 = (2, 2, 2), a corner of cell 1 on the cube
relation_count(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
# the same fold over the static site value `q` (the initial owner map, set from the
# operating point): the energy form allowed under D-209, read by the generated ΔH through
# `volume`
static(r, who = :id; site = 40) = :(count(q[n] == $who for n in $r($site)))
# copy drive reading relations `rs` at the source and `rt` at the target
function relation_drive(rs, rt)
    return :(
        @drive copy =>
            0.1 *
            (
            count(owner[n] == 1 for n in $rs(source)) -
                count(owner[n] == 1 for n in $rt(target))
        )
    )
end
# label => (lattice, @relations body or nothing, statements after the volume energy)
const FIXTURES = [
    # relation-free and declared-but-unused
    "sq" => (:sq, nothing, []),
    "sq far unused" => (:sq, :(far = EuclideanBall(2.0)), []),
    "sq proposal=Moore(1)" => (:sq, :(proposal = Moore(1)), []),
    # contacts(far)
    "sq contacts far=EuclideanBall(2.0)" =>
        (:sq, :(far = EuclideanBall(2.0)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=EuclideanBall(3.0)" =>
        (:sq, :(far = EuclideanBall(3.0)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Moore(2)" =>
        (:sq, :(far = Moore(2)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=VonNeumann(1)" =>
        (:sq, :(far = VonNeumann(1)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts near=EuclideanBall(2.0)" =>
        (:sq, :(near = EuclideanBall(2.0)), [:(@energy contacts(near) => 1.0)]),
    # contacts(far), specs that resolve to Moore(1)
    "sq contacts far=Moore(1)" =>
        (:sq, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=EuclideanBall(1.5)" =>
        (:sq, :(far = EuclideanBall(1.5)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Stencil(Moore1 permuted)" => (
        :sq,
        :(
            far = Stencil(
                [
                    [1, 1], [0, 1], [-1, 1], [1, 0], [-1, 0], [1, -1], [0, -1], [-1, -1],
                ]
            )
        ),
        [:(@energy contacts(far) => 1.0)]
    ),
    # weighted, with an energy that reads the weight
    "sq contacts far=Weighted(Moore(1), 2)" =>
        (
        :sq, :(far = Weighted(Moore(1), o -> 2.0)),
        [:(@energy contacts(far) => 1.0 * weight)]
    ),
    "sq contacts far=Weighted(Moore(1), 2) again" =>
        (
        :sq, :(far = Weighted(Moore(1), o -> 2.0)),
        [:(@energy contacts(far) => 1.0 * weight)]
    ),
    "sq contacts far=Weighted(Moore(1), 3)" =>
        (
        :sq, :(far = Weighted(Moore(1), o -> 3.0)),
        [:(@energy contacts(far) => 1.0 * weight)]
    ),
    # a named fold in a cell energy
    "sq energy far(40) far=EuclideanBall(2.0)" => (
        :sq, :(far = EuclideanBall(2.0)),
        [:(@energy cells => 0.1 * volume * $(static(:far)))]
    ),
    "sq energy far(40) far=EuclideanBall(3.0)" => (
        :sq, :(far = EuclideanBall(3.0)),
        [:(@energy cells => 0.1 * volume * $(static(:far)))]
    ),
    # an inline gather in a cell energy
    "sq energy Moore(1)(40)" =>
        (:sq, nothing, [:(@energy cells => 0.1 * volume * $(static(:(Moore(1)))))]),
    "sq energy Moore(2)(40)" =>
        (:sq, nothing, [:(@energy cells => 0.1 * volume * $(static(:(Moore(2)))))]),
    "sq energy NeighborOrder(2)(40)" =>
        (:sq, nothing, [:(@energy cells => 0.1 * volume * $(static(:(NeighborOrder(2)))))]),
    "sq energy Stencil(+x,+y)(40)" => (
        :sq, nothing,
        [:(@energy cells => 0.1 * volume * $(static(:(Stencil([[1, 0], [0, 1]])))))]
    ),
    "sq energy Stencil(+y,+x)(40)" => (
        :sq, nothing,
        [:(@energy cells => 0.1 * volume * $(static(:(Stencil([[0, 1], [1, 0]])))))]
    ),
    "sq energy Stencil(+x,-y)(40)" => (
        :sq, nothing,
        [:(@energy cells => 0.1 * volume * $(static(:(Stencil([[1, 0], [0, -1]])))))]
    ),
    # a cell ODE: inline gather and named relation
    "sq ode Moore(1)(40)" =>
        (:sq, nothing, [:(@equations D(y) ~ 0.1 * $(relation_count(:(Moore(1)))) - 0.1y)]),
    "sq ode Moore(2)(40)" =>
        (:sq, nothing, [:(@equations D(y) ~ 0.1 * $(relation_count(:(Moore(2)))) - 0.1y)]),
    "sq ode far(40) far=EuclideanBall(2.0)" => (
        :sq, :(far = EuclideanBall(2.0)),
        [:(@equations D(y) ~ 0.1 * $(relation_count(:far)) - 0.1y)]
    ),
    "sq ode far(40) far=EuclideanBall(3.0)" => (
        :sq, :(far = EuclideanBall(3.0)),
        [:(@equations D(y) ~ 0.1 * $(relation_count(:far)) - 0.1y)]
    ),
    # a copy drive: named and inline, and the use-site assignment of two inline gathers
    "sq drive far far=EuclideanBall(2.0)" =>
        (:sq, :(far = EuclideanBall(2.0)), [relation_drive(:far, :far)]),
    "sq drive far far=EuclideanBall(3.0)" =>
        (:sq, :(far = EuclideanBall(3.0)), [relation_drive(:far, :far)]),
    "sq drive Moore(1)/Moore(1)" =>
        (:sq, nothing, [relation_drive(:(Moore(1)), :(Moore(1)))]),
    "sq drive Moore(2)/Moore(2)" =>
        (:sq, nothing, [relation_drive(:(Moore(2)), :(Moore(2)))]),
    "sq drive Moore(2)/Moore(1)" =>
        (:sq, nothing, [relation_drive(:(Moore(2)), :(Moore(1)))]),
    "sq drive Moore(1)/Moore(2)" =>
        (:sq, nothing, [relation_drive(:(Moore(1)), :(Moore(2)))]),
    # a site update after each MCS
    "sq update Moore(1)(40)" =>
        (:sq, nothing, [:(@after_mcs q ~ 0.1 * $(relation_count(:(Moore(1)), 1)))]),
    "sq update Moore(2)(40)" =>
        (:sq, nothing, [:(@after_mcs q ~ 0.1 * $(relation_count(:(Moore(2)), 1)))]),
    # read only by an observed quantity
    "sq observed far(40) far=EuclideanBall(2.0)" => (
        :sq, :(far = EuclideanBall(2.0)),
        [:(@observed o(cell) ~ $(relation_count(:far)))]
    ),
    "sq observed far(40) far=EuclideanBall(3.0)" => (
        :sq, :(far = EuclideanBall(3.0)),
        [:(@observed o(cell) ~ $(relation_count(:far)))]
    ),
    # hexagonal
    "hex" => (:hex, nothing, []),
    "hex contacts far=Hex(2)" => (:hex, :(far = Hex(2)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Hex(3)" => (:hex, :(far = Hex(3)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Hex(1)" => (:hex, :(far = Hex(1)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Moore(1)" =>
        (:hex, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "hex energy Hex(1)(40)" =>
        (:hex, nothing, [:(@energy cells => 0.1 * volume * $(static(:(Hex(1)))))]),
    "hex energy Hex(2)(40)" =>
        (:hex, nothing, [:(@energy cells => 0.1 * volume * $(static(:(Hex(2)))))]),
    # 3D
    "cube" => (:cube, nothing, []),
    "cube contacts far=Moore(1)" =>
        (:cube, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=NeighborOrder(2)" =>
        (:cube, :(far = NeighborOrder(2)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=VonNeumann(1)" =>
        (:cube, :(far = VonNeumann(1)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=NeighborOrder(3)" =>
        (:cube, :(far = NeighborOrder(3)), [:(@energy contacts(far) => 1.0)]),
    "cube energy NeighborOrder(1)(74)" => (
        :cube,
        nothing,
        [:(@energy cells => 0.1 * volume * $(static(:(NeighborOrder(1)); site = 74)))]
    ),
    "cube energy NeighborOrder(2)(74)" => (
        :cube,
        nothing,
        [:(@energy cells => 0.1 * volume * $(static(:(NeighborOrder(2)); site = 74)))]
    )
]
const MODELS = Dict{String, Any}()
const LATTICE_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(FIXTURES)
    name = Symbol(:Rel, i)
    ln = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), ln, rel)
    lat = LATTICES[lk]
    @eval @potts_model $name begin
        @kinds medium A
        @variables y(cell) = 0.0 q(site) = 0.0
        @lattice $lat
        $relx
        @energy cells => (volume - 9.0)^2
        $(body...)
        @sweep Metropolis(; temperature = 2.0)
    end
    MODELS[label] = @eval $name
    LATTICE_OF[label] = lk
end
"""Two cells of kind A: 3×3 squares on a 12×12 lattice, 2×2×2 cubes on an 8×8×8 one."""
function relation_op(lk::Symbol)
    if lk === :cube
        σ = zeros(Int32, 8, 8, 8)
        σ[2:3, 2:3, 2:3] .= 1
        σ[5:6, 5:6, 5:6] .= 2
    else
        σ = zeros(Int32, 12, 12)
        σ[2:4, 2:4] .= 1
        σ[7:9, 7:9] .= 2
    end
    # q: static owner labels (`gather_energy_tests.jl`)
    return [ownership => σ, kind => [:A, :A], :q => Float64.(σ)]
end
function problem(label; T = Float64, tspan = (0, 12), seed = 1)
    return PottsProblem(
        MODELS[label](; name = :rel), relation_op(LATTICE_OF[label]), tspan; T, seed
    )
end
relation_fp(label; T = Float64) = problem(label; T).f.fingerprint
relation_energy(label) = (p = problem(label); total_energy(p, p.u0))
"""
The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the
pair).
"""
function pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "relation fingerprint: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end
function distinct(labels; T = Float64)
    return pairwise_distinct(
        [
            label => relation_fp(label; T)
                for label in labels
        ]
    )
end
"""Each label fingerprints like `base` (one @test per label)."""
function relation_like(base, labels; T = Float64)
    f0 = relation_fp(base; T)
    for label in labels
        fp = relation_fp(label; T)
        @test fp == f0
        fp == f0 ||
            @info "relation fingerprint: `$label` ($(repr(fp))) does not fingerprint like \
                `$base` ($(repr(f0)))"
    end
end
"""A checkpoint of `pa` after `k` MCS under `alg`: refused by `pb` (ArgumentError) unless
`pb === nothing`, accepted by `pa2`, in memory and through a file."""
function relation_checkpoint(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "relation_fingerprint.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)
        @test i2.t == k
        @test i2.u.ownership == ck.state.ownership
    end
end
# ---------------------------------------------------------------------------------------
# 4. Pins
function two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
function wortel(; kw...)
    return PottsProblem(
        WortelAct(; name = :act, lattice = (8, 8), kw...), two_wortel(), (
            0, 10,
        )
    )
end
# The `canonical_term_order_tests.jl` fixture `CanonicalAt` and its builder, copied verbatim
# (renamed): an inline `Moore(1)(42)` gather in a cell rate. Its fingerprint does not depend
# on the model's name.
@potts_model AhAt begin
    @kinds medium A
    @variables y(cell) = 0.0 g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~
            0.03 * y[3 - id] + 0.04 * sin(y) + 0.05 * exp(-y) +
            0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) +
            0.01 * sum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - 0.1y
    end
    @after_mcs g ~
        0.01 * sum(volume[c] for c in cells) + 0.02 * sum(y[c] for c in cells) +
        0.3 * g + 0.001 * sum(1.0 for s in sites)
    @sweep Metropolis(; temperature = 1.0)
end
function relation_ah(solver)
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return PottsProblem(
        AhAt(; name = :x), Any[ownership => s, kind => [:A, :A]],
        (0, 10); seed = 7, ode_solver = solver
    )
end
# a relation that is declared but unread, or read only by an observer, does not move the
# fingerprint; a proposal or a compute type does.
# models that read an inline gather: the fixture is what it claims, and its fingerprint is
# deterministic.
function moved()
    return (
        "WortelAct" => () -> wortel(),
        "WortelAct connected" => () -> wortel(; connected = true),
        "CanonicalAt RK4" => () -> relation_ah(Potts.RK4()),
        "CanonicalAt ExplicitEuler" => () -> relation_ah(Potts.ExplicitEuler()),
    )
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "relation fingerprint: controls — the fixtures read the relations they \
    declare" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 1. Controls (pass on the base)
    @testset "relation fingerprint: controls — the fixtures read the relations they \
        declare" begin
        p = problem("sq contacts far=EuclideanBall(2.0)")
        @test haskey(p.relations, :far) &&
            length(CorePotts.relation(p.relations.far, p.lattice)) == 12
        @test length(
            CorePotts.relation(
                problem("sq contacts far=EuclideanBall(3.0)").relations.far, p.lattice
            )
        ) == 28
        @test length(
            CorePotts.relation(
                problem("sq contacts far=EuclideanBall(1.5)").relations.far, p.lattice
            )
        ) == 8
        g1 = problem("sq energy Moore(1)(40)")
        g2 = problem("sq energy Moore(2)(40)")
        # one inline gather, same name
        @test keys(g1.relations) == keys(g2.relations) == (:gather1,)
        @test length(CorePotts.relation(g1.relations.gather1, g1.lattice)) == 8
        @test length(CorePotts.relation(g2.relations.gather1, g2.lattice)) == 24
        # the two inline gathers of the swapped drives are the same two relations, read at
        # swapped sites
        d1 = problem("sq drive Moore(2)/Moore(1)")
        d2 = problem("sq drive Moore(1)/Moore(2)")
        @test keys(d1.relations) == keys(d2.relations) == (:gather1, :gather2)
        @test d1.relations == d2.relations
        # an inline Stencil resolves to canonically ordered offsets: the permuted pair alike
        s1 = problem("sq energy Stencil(+x,+y)(40)")
        s2 = problem("sq energy Stencil(+y,+x)(40)")
        @test CorePotts.relation(s1.relations.gather1, s1.lattice) ==
            CorePotts.relation(s2.relations.gather1, s2.lattice)
    end
end

@testitem "relation fingerprint: controls — the relations change the model" setup = [
    RelationFingerprintSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: controls — the relations change the model" begin
        E = relation_energy
        @test E("sq contacts far=EuclideanBall(2.0)") !=
            E("sq contacts far=EuclideanBall(3.0)")
        @test E("sq contacts far=EuclideanBall(2.0)") != E("sq contacts far=Moore(2)")
        @test E("sq contacts far=Weighted(Moore(1), 2)") !=
            E("sq contacts far=Weighted(Moore(1), 3)")
        @test E("sq energy far(40) far=EuclideanBall(2.0)") !=
            E("sq energy far(40) far=EuclideanBall(3.0)")
        @test E("sq energy Moore(1)(40)") != E("sq energy Moore(2)(40)")
        @test E("sq energy Stencil(+x,+y)(40)") != E("sq energy Stencil(+x,-y)(40)")
        @test E("hex contacts far=Hex(2)") != E("hex contacts far=Hex(3)")
        @test E("hex energy Hex(1)(40)") != E("hex energy Hex(2)(40)")
        @test E("cube contacts far=Moore(1)") != E("cube contacts far=NeighborOrder(2)")
        @test E("cube energy NeighborOrder(1)(74)") != E("cube energy NeighborOrder(2)(74)")
        # specs that resolve alike give the same energy
        @test E("sq contacts far=EuclideanBall(1.5)") == E("sq contacts far=Moore(1)") ==
            E("sq contacts far=Stencil(Moore1 permuted)")
        @test E("sq energy NeighborOrder(2)(40)") == E("sq energy Moore(1)(40)")
        # the ODE rates read their relations: different cell values after a few MCS (same
        # seed)
        y(label) = solve(problem(label; tspan = (0, 4)), SequentialCPM()).u[end].cell.y
        @test y("sq ode Moore(1)(40)") != y("sq ode Moore(2)(40)")
        @test y("sq ode far(40) far=EuclideanBall(2.0)") !=
            y("sq ode far(40) far=EuclideanBall(3.0)")
        # the site update reads its relation
        q(label) = solve(problem(label; tspan = (0, 2)), SequentialCPM()).u[end].site.q
        @test q("sq update Moore(1)(40)") != q("sq update Moore(2)(40)")
    end
end

@testitem "relation fingerprint: controls — what the generated code already tells \
    apart" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: controls — what the generated code already tells \
        apart" begin
        # negative control: the fingerprint is not constant
        @test relation_fp("sq contacts far=EuclideanBall(2.0)") != relation_fp("sq")
        @test relation_fp("hex") != relation_fp("sq")
        # the name of a named relation, and the use site of an inline gather, are in the
        # code
        distinct(
            [
                "sq contacts far=EuclideanBall(2.0)", "sq contacts near=EuclideanBall(2.0)",
            ]
        )
        distinct(["sq drive Moore(2)/Moore(1)", "sq drive Moore(1)/Moore(2)"])
        distinct(
            [
                "sq contacts far=EuclideanBall(2.0)", "sq contacts near=EuclideanBall(2.0)",
            ]; T = Float32
        )
    end
end

@testitem "relation fingerprint: named and inline gather relations are in the \
    fingerprint" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 2. A different named or inline gather relation, a different fingerprint
    @testset "relation fingerprint: named and inline gather relations are in the \
        fingerprint" begin
        for T in (Float64, Float32)
            @testset "contacts(far), square 2D $T" begin
                distinct(
                    [
                        "sq contacts far=EuclideanBall(2.0)",
                        "sq contacts far=EuclideanBall(3.0)",
                        "sq contacts far=Moore(2)",
                        "sq contacts far=VonNeumann(1)", "sq contacts far=Moore(1)",
                    ]; T
                )
            end
            @testset "contacts(far) weights, square 2D $T" begin
                distinct(
                    [
                        "sq contacts far=Weighted(Moore(1), 2)",
                        "sq contacts far=Weighted(Moore(1), 3)",
                    ]; T
                )
            end
            @testset "a named fold in an energy $T" begin
                distinct(
                    [
                        "sq energy far(40) far=EuclideanBall(2.0)",
                        "sq energy far(40) far=EuclideanBall(3.0)",
                    ];
                    T
                )
            end
            @testset "an inline gather in an energy $T" begin
                distinct(
                    [
                        "sq energy Moore(1)(40)", "sq energy Moore(2)(40)",
                        "sq energy Stencil(+x,+y)(40)",
                        "sq energy Stencil(+x,-y)(40)",
                    ]; T
                )
            end
            @testset "a cell ODE $T" begin
                distinct(["sq ode Moore(1)(40)", "sq ode Moore(2)(40)"]; T)
                distinct(
                    [
                        "sq ode far(40) far=EuclideanBall(2.0)",
                        "sq ode far(40) far=EuclideanBall(3.0)",
                    ]; T
                )
            end
            @testset "a copy drive $T" begin
                distinct(
                    [
                        "sq drive far far=EuclideanBall(2.0)",
                        "sq drive far far=EuclideanBall(3.0)",
                    ]; T
                )
                distinct(
                    [
                        "sq drive Moore(1)/Moore(1)", "sq drive Moore(2)/Moore(2)",
                        "sq drive Moore(2)/Moore(1)",
                        "sq drive Moore(1)/Moore(2)",
                    ]; T
                )
            end
            @testset "a site update $T" begin
                distinct(["sq update Moore(1)(40)", "sq update Moore(2)(40)"]; T)
            end
        end
        @testset "hexagonal 2D" begin
            distinct(
                [
                    "hex contacts far=Hex(1)", "hex contacts far=Hex(2)",
                    "hex contacts far=Hex(3)",
                ]
            )
            distinct(["hex energy Hex(1)(40)", "hex energy Hex(2)(40)"])
        end
        @testset "3D" begin
            distinct(
                [
                    "cube contacts far=Moore(1)", "cube contacts far=NeighborOrder(2)",
                    "cube contacts far=VonNeumann(1)",
                ]
            )
            distinct(
                [
                    "cube energy NeighborOrder(1)(74)", "cube energy NeighborOrder(2)(74)",
                ]
            )
        end
        @testset "deterministic: the same model built twice fingerprints alike" begin
            for (label, _) in FIXTURES
                @test relation_fp(label) == relation_fp(label)
            end
        end
    end
end

@testitem "relation fingerprint: relations that resolve alike fingerprint alike" setup = [
    RelationFingerprintSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: relations that resolve alike fingerprint alike" begin
        for T in (Float64, Float32)
            relation_like(
                "sq contacts far=Moore(1)",
                [
                    "sq contacts far=EuclideanBall(1.5)",
                    "sq contacts far=Stencil(Moore1 permuted)",
                ];
                T
            )
            relation_like("sq energy Moore(1)(40)", ["sq energy NeighborOrder(2)(40)"]; T)
            relation_like(
                "sq energy Stencil(+x,+y)(40)", ["sq energy Stencil(+y,+x)(40)"];
                T
            )
        end
        relation_like("hex contacts far=Hex(1)", ["hex contacts far=Moore(1)"])
        relation_like("cube contacts far=Moore(1)", ["cube contacts far=NeighborOrder(3)"])
        # weights hash by value, not by the weight function
        relation_like(
            "sq contacts far=Weighted(Moore(1), 2)",
            ["sq contacts far=Weighted(Moore(1), 2) again"]
        )
    end
end

@testitem "relation fingerprint: relations no generated code reads are not in the \
    fingerprint" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: relations no generated code reads are not in the \
        fingerprint" begin
        for T in (Float64, Float32)
            relation_like("sq", ["sq far unused"]; T)
            relation_like(
                "sq observed far(40) far=EuclideanBall(2.0)",
                ["sq observed far(40) far=EuclideanBall(3.0)"]; T
            )
        end
    end
end

@testitem "relation fingerprint: a checkpoint does not load under another relation" setup =
    [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 3. Checkpoints do not cross named or inline gather relations
    @testset "relation fingerprint: a checkpoint does not load under another relation" begin
        pr = problem
        @testset "contacts(far) EuclideanBall(2.0) → EuclideanBall(3.0)" begin
            relation_checkpoint(
                pr("sq contacts far=EuclideanBall(2.0)"),
                pr("sq contacts far=EuclideanBall(3.0)"),
                pr("sq contacts far=EuclideanBall(2.0)")
            )
        end
        @testset "contacts(far) weights 3 → 2, CheckerboardCPM" begin
            relation_checkpoint(
                pr("sq contacts far=Weighted(Moore(1), 3)"),
                pr("sq contacts far=Weighted(Moore(1), 2)"),
                pr("sq contacts far=Weighted(Moore(1), 3)"); alg = CheckerboardCPM()
            )
        end
        @testset "a named fold in an energy" begin
            relation_checkpoint(
                pr("sq energy far(40) far=EuclideanBall(3.0)"),
                pr("sq energy far(40) far=EuclideanBall(2.0)"),
                pr("sq energy far(40) far=EuclideanBall(3.0)")
            )
        end
        @testset "an inline gather in an energy" begin
            relation_checkpoint(
                pr("sq energy Moore(1)(40)"), pr("sq energy Moore(2)(40)"),
                pr("sq energy Moore(1)(40)")
            )
        end
        @testset "an inline gather in a cell ODE" begin
            relation_checkpoint(
                pr("sq ode Moore(2)(40)"), pr("sq ode Moore(1)(40)"),
                pr("sq ode Moore(2)(40)")
            )
        end
        @testset "a named relation in a cell ODE" begin
            relation_checkpoint(
                pr("sq ode far(40) far=EuclideanBall(2.0)"),
                pr("sq ode far(40) far=EuclideanBall(3.0)"),
                pr("sq ode far(40) far=EuclideanBall(2.0)")
            )
        end
        @testset "a copy drive" begin
            relation_checkpoint(
                pr("sq drive far far=EuclideanBall(2.0)"),
                pr("sq drive far far=EuclideanBall(3.0)"),
                pr("sq drive far far=EuclideanBall(2.0)")
            )
            relation_checkpoint(
                pr("sq drive Moore(1)/Moore(1)"), pr("sq drive Moore(2)/Moore(2)"),
                pr("sq drive Moore(1)/Moore(1)")
            )
        end
        @testset "a site update" begin
            relation_checkpoint(
                pr("sq update Moore(1)(40)"), pr("sq update Moore(2)(40)"),
                pr("sq update Moore(1)(40)")
            )
        end
        @testset "Float32: an inline gather in an energy" begin
            relation_checkpoint(
                pr("sq energy Moore(2)(40)"; T = Float32),
                pr("sq energy Moore(1)(40)"; T = Float32),
                pr("sq energy Moore(2)(40)"; T = Float32)
            )
        end
        @testset "hexagonal: contacts(far) Hex(2) → Hex(3)" begin
            relation_checkpoint(
                pr("hex contacts far=Hex(2)"), pr("hex contacts far=Hex(3)"),
                pr("hex contacts far=Hex(2)")
            )
        end
        @testset "3D: contacts(far) Moore(1) → NeighborOrder(2)" begin
            relation_checkpoint(
                pr("cube contacts far=Moore(1)"), pr("cube contacts far=NeighborOrder(2)"),
                pr("cube contacts far=Moore(1)")
            )
        end
    end
end

@testitem "relation fingerprint: a checkpoint loads across relations that resolve alike \
    or are not read" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: a checkpoint loads across relations that resolve \
        alike or are not read" begin
        pr = problem
        relation_checkpoint(
            pr("sq contacts far=EuclideanBall(1.5)"), nothing,
            pr("sq contacts far=Moore(1)")
        )
        relation_checkpoint(
            pr("sq energy NeighborOrder(2)(40)"), nothing,
            pr("sq energy Moore(1)(40)")
        )
        relation_checkpoint(
            pr("hex contacts far=Moore(1)"), nothing,
            pr("hex contacts far=Hex(1)")
        )
        relation_checkpoint(pr("sq far unused"), nothing, pr("sq"))
        relation_checkpoint(
            pr("sq observed far(40) far=EuclideanBall(2.0)"), nothing,
            pr("sq observed far(40) far=EuclideanBall(3.0)")
        )
    end
end

@testitem "relation fingerprint: an unused or observed-only relation does not move the \
    fingerprint" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: an unused or observed-only relation does not move the \
        fingerprint" begin
        base = problem("sq").f.fingerprint
        @test problem("sq far unused").f.fingerprint == base
        @test problem("sq observed far(40) far=EuclideanBall(2.0)").f.fingerprint == base
        # D-124: a proposal is hashed
        @test problem("sq proposal=Moore(1)").f.fingerprint != base
        # the compute type is hashed
        @test problem("sq"; T = Float32).f.fingerprint != base
    end
end

@testitem "relation fingerprint: models reading an inline gather are what they claim and \
    deterministic" setup = [RelationFingerprintSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "relation fingerprint: models reading an inline gather are what they claim \
        and deterministic" begin
        for (name, build) in moved()
            prob = build()
            # the fixture is what it claims
            @test any(k -> startswith(string(k), "gather"), keys(prob.relations))
            fp = prob.f.fingerprint
            # deterministic
            @test build().f.fingerprint == fp
        end
    end
end
