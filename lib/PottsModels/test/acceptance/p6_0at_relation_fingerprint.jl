# P6.0at (ROADMAP Phase 6, step 0): named and inline gather relations are in the
# fingerprint. Decision: D-124 (amends D-016, after D-122). Frozen (AUTONOMY §7.3).
#
# The defect (P6.0ar test author, D-122 "Follow-up"). A named relation (`@relations far =
# Ball(2.0)`, read by `contacts(far)` or a fold `for n in far(site)`) and an inline gather
# relation (`for n in Moore(1)(42)`) reach the generated code only as a field of the run
# context (`ctx.far`, `ctx.gather1`: the compiler numbers inline gathers `gather1`, `gather2`,
# … in statement order, D-107); their resolved offsets and weights are runtime data, not
# constants in the kernels. So the code hash sees the NAME a statement reads and which
# statement reads which gather, but not the relation itself. Measured on e4b6ab51 with the
# fixtures below (12×12 periodic, Moore(1) lattice neighbourhood): `contacts(far)` with far
# = Ball(2.0) vs Ball(3.0) (energies 112 vs 360 on the same state), a cell-energy fold
# `far(40)` (0.5 vs 0.8), an inline gather `Moore(1)(40)` vs `Moore(2)(40)` in a cell energy
# (0.3 vs 0.8), in a cell ODE, in a `@drive`, a named relation in a cell ODE or a `@drive`,
# and `Weighted(Moore(1), 2)` vs `3` all fingerprint alike pairwise, so a checkpoint loads
# across them although the energy or the dynamics differ.
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
# canonically ordered offsets, weights by value) and keyed by its context name (the relation's
# name, or the `gatherN` the compiler gives the inline spec; the code ties that name to its
# use sites). There is no default to skip. Specs that resolve alike fingerprint alike
# (`Ball(1.5)`, `Moore(1)` and a permuted Moore(1) `Stencil` on a square lattice; `Hex(1)`
# and `Moore(1)` on a hexagonal one; `NeighborOrder(2)` and `Moore(1)` inline; a permuted
# inline `Stencil`). A checkpoint does not load across problems that differ in one
# (`ArgumentError`). The proposal and contact neighbourhoods keep their D-122 rule.
#
# Pins. A model that reads no named or inline gather relation keeps its fingerprint (the
# relation-free fixtures here, the D-122 `proposal = Moore(1)` fixture, GranerGlazier,
# MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture, AkeebInvasion). Models
# that read one MUST move: WortelAct (both variants; its drive folds an inline
# `Moore(1; include_self = true)` gather) and the P6.0ah fixture `P60ahAt` (an inline
# `Moore(1)(42)` in a cell rate). Their pins in the earlier frozen files (p6_0aq, p6_0p,
# p6_0t, p6_0x, p6_0ah) are re-pinned by the implementer under D-124 (pin lines only); here
# they are only required to differ from the old values and to be deterministic.
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures: one model per lattice, `@relations` content and use

const P60AT_LATTICES = Dict(
    :sq => :(Lattice((12, 12))),
    :hex => :(Lattice((12, 12); geometry = Hexagonal())),
    :cube => :(Lattice((8, 8, 8))),
)
# a fold of relation `r` (a name or an inline spec call) around a fixed site: 40 = (4, 4), a
# corner of cell 1 on the 12×12 lattices; 74 = (2, 2, 2), a corner of cell 1 on the cube
p60at_count(r, who = :id; site = 40) = :(count(owner[n] == $who for n in $r($site)))
# copy drive reading relations `rs` at the source and `rt` at the target
p60at_drive(rs, rt) = :(@drive copy => 0.1 * (count(owner[n] == 1 for n in $rs(source)) - count(owner[n] == 1 for n in $rt(target))))

# label => (lattice, @relations body or nothing, statements after the volume energy)
const P60AT_FIXTURES = [
    # relation-free and declared-but-unused
    "sq" => (:sq, nothing, []),
    "sq far unused" => (:sq, :(far = Ball(2.0)), []),
    "sq proposal=Moore(1)" => (:sq, :(proposal = Moore(1)), []),
    # contacts(far)
    "sq contacts far=Ball(2.0)" => (:sq, :(far = Ball(2.0)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Ball(3.0)" => (:sq, :(far = Ball(3.0)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Moore(2)" => (:sq, :(far = Moore(2)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=VonNeumann(1)" => (:sq, :(far = VonNeumann(1)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts near=Ball(2.0)" => (:sq, :(near = Ball(2.0)), [:(@energy contacts(near) => 1.0)]),
    # contacts(far), specs that resolve to Moore(1)
    "sq contacts far=Moore(1)" => (:sq, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Ball(1.5)" => (:sq, :(far = Ball(1.5)), [:(@energy contacts(far) => 1.0)]),
    "sq contacts far=Stencil(Moore1 permuted)" => (:sq,
        :(far = Stencil([[1, 1], [0, 1], [-1, 1], [1, 0], [-1, 0], [1, -1], [0, -1], [-1, -1]])),
        [:(@energy contacts(far) => 1.0)]),
    # weighted, with an energy that reads the weight
    "sq contacts far=Weighted(Moore(1), 2)" => (:sq, :(far = Weighted(Moore(1), o -> 2.0)), [:(@energy contacts(far) => 1.0 * weight)]),
    "sq contacts far=Weighted(Moore(1), 2) again" => (:sq, :(far = Weighted(Moore(1), o -> 2.0)), [:(@energy contacts(far) => 1.0 * weight)]),
    "sq contacts far=Weighted(Moore(1), 3)" => (:sq, :(far = Weighted(Moore(1), o -> 3.0)), [:(@energy contacts(far) => 1.0 * weight)]),
    # a named fold in a cell energy
    "sq energy far(40) far=Ball(2.0)" => (:sq, :(far = Ball(2.0)), [:(@energy cells => 0.1 * $(p60at_count(:far)))]),
    "sq energy far(40) far=Ball(3.0)" => (:sq, :(far = Ball(3.0)), [:(@energy cells => 0.1 * $(p60at_count(:far)))]),
    # an inline gather in a cell energy
    "sq energy Moore(1)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Moore(1)))))]),
    "sq energy Moore(2)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Moore(2)))))]),
    "sq energy NeighborOrder(2)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(NeighborOrder(2)))))]),
    "sq energy Stencil(+x,+y)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Stencil([[1, 0], [0, 1]])))))]),
    "sq energy Stencil(+y,+x)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Stencil([[0, 1], [1, 0]])))))]),
    "sq energy Stencil(+x,-y)(40)" => (:sq, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Stencil([[1, 0], [0, -1]])))))]),
    # a cell ODE: inline gather and named relation
    "sq ode Moore(1)(40)" => (:sq, nothing, [:(@equations D(y) ~ 0.1 * $(p60at_count(:(Moore(1)))) - 0.1y)]),
    "sq ode Moore(2)(40)" => (:sq, nothing, [:(@equations D(y) ~ 0.1 * $(p60at_count(:(Moore(2)))) - 0.1y)]),
    "sq ode far(40) far=Ball(2.0)" => (:sq, :(far = Ball(2.0)), [:(@equations D(y) ~ 0.1 * $(p60at_count(:far)) - 0.1y)]),
    "sq ode far(40) far=Ball(3.0)" => (:sq, :(far = Ball(3.0)), [:(@equations D(y) ~ 0.1 * $(p60at_count(:far)) - 0.1y)]),
    # a copy drive: named and inline, and the use-site assignment of two inline gathers
    "sq drive far far=Ball(2.0)" => (:sq, :(far = Ball(2.0)), [p60at_drive(:far, :far)]),
    "sq drive far far=Ball(3.0)" => (:sq, :(far = Ball(3.0)), [p60at_drive(:far, :far)]),
    "sq drive Moore(1)/Moore(1)" => (:sq, nothing, [p60at_drive(:(Moore(1)), :(Moore(1)))]),
    "sq drive Moore(2)/Moore(2)" => (:sq, nothing, [p60at_drive(:(Moore(2)), :(Moore(2)))]),
    "sq drive Moore(2)/Moore(1)" => (:sq, nothing, [p60at_drive(:(Moore(2)), :(Moore(1)))]),
    "sq drive Moore(1)/Moore(2)" => (:sq, nothing, [p60at_drive(:(Moore(1)), :(Moore(2)))]),
    # a site update after each MCS
    "sq update Moore(1)(40)" => (:sq, nothing, [:(@after_mcs q ~ 0.1 * $(p60at_count(:(Moore(1)), 1)))]),
    "sq update Moore(2)(40)" => (:sq, nothing, [:(@after_mcs q ~ 0.1 * $(p60at_count(:(Moore(2)), 1)))]),
    # read only by an observed quantity
    "sq observed far(40) far=Ball(2.0)" => (:sq, :(far = Ball(2.0)), [:(@observed o(cell) ~ $(p60at_count(:far)))]),
    "sq observed far(40) far=Ball(3.0)" => (:sq, :(far = Ball(3.0)), [:(@observed o(cell) ~ $(p60at_count(:far)))]),
    # hexagonal
    "hex" => (:hex, nothing, []),
    "hex contacts far=Hex(2)" => (:hex, :(far = Hex(2)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Hex(3)" => (:hex, :(far = Hex(3)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Hex(1)" => (:hex, :(far = Hex(1)), [:(@energy contacts(far) => 1.0)]),
    "hex contacts far=Moore(1)" => (:hex, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "hex energy Hex(1)(40)" => (:hex, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Hex(1)))))]),
    "hex energy Hex(2)(40)" => (:hex, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(Hex(2)))))]),
    # 3D
    "cube" => (:cube, nothing, []),
    "cube contacts far=Moore(1)" => (:cube, :(far = Moore(1)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=NeighborOrder(2)" => (:cube, :(far = NeighborOrder(2)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=VonNeumann(1)" => (:cube, :(far = VonNeumann(1)), [:(@energy contacts(far) => 1.0)]),
    "cube contacts far=NeighborOrder(3)" => (:cube, :(far = NeighborOrder(3)), [:(@energy contacts(far) => 1.0)]),
    "cube energy NeighborOrder(1)(74)" => (:cube, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(NeighborOrder(1)); site = 74)))]),
    "cube energy NeighborOrder(2)(74)" => (:cube, nothing, [:(@energy cells => 0.1 * $(p60at_count(:(NeighborOrder(2)); site = 74)))]),
]
const P60AT_MODELS = Dict{String, Any}()
const P60AT_LATTICE_OF = Dict{String, Symbol}()
for (i, (label, (lk, rel, body))) in enumerate(P60AT_FIXTURES)
    name = Symbol(:P60atRel, i)
    ln = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    relx = rel === nothing ? nothing : Expr(:macrocall, Symbol("@relations"), ln, rel)
    lat = P60AT_LATTICES[lk]
    @eval @potts_model $name begin
        @kinds medium A
        @variables y(cell) = 0.0 q(site) = 0.0
        @lattice $lat
        $relx
        @energy cells => (volume - 9.0)^2
        $(body...)
        @sweep Metropolis(; temperature = 2.0)
    end
    P60AT_MODELS[label] = @eval $name
    P60AT_LATTICE_OF[label] = lk
end

"""Two cells of kind A: 3×3 squares on a 12×12 lattice, 2×2×2 cubes on an 8×8×8 one."""
function p60at_op(lk::Symbol)
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

p60at_problem(label; T = Float64, tspan = (0, 12), seed = 1) =
    PottsProblem(P60AT_MODELS[label](; name = :rel), p60at_op(P60AT_LATTICE_OF[label]), tspan; T, seed)
p60at_fp(label; T = Float64) = p60at_problem(label; T).f.fingerprint
p60at_energy(label) = (p = p60at_problem(label); total_energy(p, p.u0))

"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function p60at_pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "P6.0at: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end
p60at_distinct(labels; T = Float64) = p60at_pairwise_distinct([label => p60at_fp(label; T) for label in labels])

"""Each label fingerprints like `base` (one @test per label)."""
function p60at_like(base, labels; T = Float64)
    f0 = p60at_fp(base; T)
    for label in labels
        fp = p60at_fp(label; T)
        @test fp == f0
        fp == f0 || @info "P6.0at: `$label` ($(repr(fp))) does not fingerprint like `$base` ($(repr(f0)))"
    end
end

"""A checkpoint of `pa` after `k` MCS under `alg`: refused by `pb` (ArgumentError) unless
`pb === nothing`, accepted by `pa2`, in memory and through a file."""
function p60at_checkpoint(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "p60at.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)
        @test i2.t == k
        @test i2.u.σ == ck.state.σ
    end
end

# ---------------------------------------------------------------------------------------
# 1. Controls (pass on the base)

@testset "P6.0at: controls — the fixtures read the relations they declare" begin
    p = p60at_problem("sq contacts far=Ball(2.0)")
    @test haskey(p.relations, :far) && length(CorePotts.relation(p.relations.far, p.lattice)) == 12
    @test length(CorePotts.relation(p60at_problem("sq contacts far=Ball(3.0)").relations.far, p.lattice)) == 28
    @test length(CorePotts.relation(p60at_problem("sq contacts far=Ball(1.5)").relations.far, p.lattice)) == 8
    g1 = p60at_problem("sq energy Moore(1)(40)")
    g2 = p60at_problem("sq energy Moore(2)(40)")
    @test keys(g1.relations) == keys(g2.relations) == (:gather1,)          # one inline gather, same name
    @test length(CorePotts.relation(g1.relations.gather1, g1.lattice)) == 8
    @test length(CorePotts.relation(g2.relations.gather1, g2.lattice)) == 24
    # the two inline gathers of the swapped drives are the same two relations, read at swapped sites
    d1 = p60at_problem("sq drive Moore(2)/Moore(1)")
    d2 = p60at_problem("sq drive Moore(1)/Moore(2)")
    @test keys(d1.relations) == keys(d2.relations) == (:gather1, :gather2)
    @test d1.relations == d2.relations
    # an inline Stencil resolves to canonically ordered offsets: the permuted pair alike
    s1 = p60at_problem("sq energy Stencil(+x,+y)(40)")
    s2 = p60at_problem("sq energy Stencil(+y,+x)(40)")
    @test CorePotts.relation(s1.relations.gather1, s1.lattice) == CorePotts.relation(s2.relations.gather1, s2.lattice)
end

@testset "P6.0at: controls — the relations change the model" begin
    E = p60at_energy
    @test E("sq contacts far=Ball(2.0)") != E("sq contacts far=Ball(3.0)")
    @test E("sq contacts far=Ball(2.0)") != E("sq contacts far=Moore(2)")
    @test E("sq contacts far=Weighted(Moore(1), 2)") != E("sq contacts far=Weighted(Moore(1), 3)")
    @test E("sq energy far(40) far=Ball(2.0)") != E("sq energy far(40) far=Ball(3.0)")
    @test E("sq energy Moore(1)(40)") != E("sq energy Moore(2)(40)")
    @test E("sq energy Stencil(+x,+y)(40)") != E("sq energy Stencil(+x,-y)(40)")
    @test E("hex contacts far=Hex(2)") != E("hex contacts far=Hex(3)")
    @test E("hex energy Hex(1)(40)") != E("hex energy Hex(2)(40)")
    @test E("cube contacts far=Moore(1)") != E("cube contacts far=NeighborOrder(2)")
    @test E("cube energy NeighborOrder(1)(74)") != E("cube energy NeighborOrder(2)(74)")
    # specs that resolve alike give the same energy
    @test E("sq contacts far=Ball(1.5)") == E("sq contacts far=Moore(1)") == E("sq contacts far=Stencil(Moore1 permuted)")
    @test E("sq energy NeighborOrder(2)(40)") == E("sq energy Moore(1)(40)")
    # the ODE rates read their relations: different cell values after a few MCS (same seed)
    y(label) = solve(p60at_problem(label; tspan = (0, 4)), SequentialCPM()).u[end].cell.y
    @test y("sq ode Moore(1)(40)") != y("sq ode Moore(2)(40)")
    @test y("sq ode far(40) far=Ball(2.0)") != y("sq ode far(40) far=Ball(3.0)")
    # the site update reads its relation
    q(label) = solve(p60at_problem(label; tspan = (0, 2)), SequentialCPM()).u[end].site.q
    @test q("sq update Moore(1)(40)") != q("sq update Moore(2)(40)")
end

@testset "P6.0at: controls — what the generated code already tells apart" begin
    # negative control: the fingerprint is not constant
    @test p60at_fp("sq contacts far=Ball(2.0)") != p60at_fp("sq")
    @test p60at_fp("hex") != p60at_fp("sq")
    # the name of a named relation, and the use site of an inline gather, are in the code
    p60at_distinct(["sq contacts far=Ball(2.0)", "sq contacts near=Ball(2.0)"])
    p60at_distinct(["sq drive Moore(2)/Moore(1)", "sq drive Moore(1)/Moore(2)"])
    p60at_distinct(["sq contacts far=Ball(2.0)", "sq contacts near=Ball(2.0)"]; T = Float32)
end

# ---------------------------------------------------------------------------------------
# 2. A different named or inline gather relation, a different fingerprint

@testset "P6.0at: named and inline gather relations are in the fingerprint" begin
    for T in (Float64, Float32)
        @testset "contacts(far), square 2D, $T" begin
            p60at_distinct(["sq contacts far=Ball(2.0)", "sq contacts far=Ball(3.0)", "sq contacts far=Moore(2)",
                "sq contacts far=VonNeumann(1)", "sq contacts far=Moore(1)"]; T)
        end
        @testset "contacts(far) weights, square 2D, $T" begin
            p60at_distinct(["sq contacts far=Weighted(Moore(1), 2)", "sq contacts far=Weighted(Moore(1), 3)"]; T)
        end
        @testset "a named fold in an energy, $T" begin
            p60at_distinct(["sq energy far(40) far=Ball(2.0)", "sq energy far(40) far=Ball(3.0)"]; T)
        end
        @testset "an inline gather in an energy, $T" begin
            p60at_distinct(["sq energy Moore(1)(40)", "sq energy Moore(2)(40)", "sq energy Stencil(+x,+y)(40)",
                "sq energy Stencil(+x,-y)(40)"]; T)
        end
        @testset "a cell ODE, $T" begin
            p60at_distinct(["sq ode Moore(1)(40)", "sq ode Moore(2)(40)"]; T)
            p60at_distinct(["sq ode far(40) far=Ball(2.0)", "sq ode far(40) far=Ball(3.0)"]; T)
        end
        @testset "a copy drive, $T" begin
            p60at_distinct(["sq drive far far=Ball(2.0)", "sq drive far far=Ball(3.0)"]; T)
            p60at_distinct(["sq drive Moore(1)/Moore(1)", "sq drive Moore(2)/Moore(2)", "sq drive Moore(2)/Moore(1)",
                "sq drive Moore(1)/Moore(2)"]; T)
        end
        @testset "a site update, $T" begin
            p60at_distinct(["sq update Moore(1)(40)", "sq update Moore(2)(40)"]; T)
        end
    end
    @testset "hexagonal 2D" begin
        p60at_distinct(["hex contacts far=Hex(1)", "hex contacts far=Hex(2)", "hex contacts far=Hex(3)"])
        p60at_distinct(["hex energy Hex(1)(40)", "hex energy Hex(2)(40)"])
    end
    @testset "3D" begin
        p60at_distinct(["cube contacts far=Moore(1)", "cube contacts far=NeighborOrder(2)", "cube contacts far=VonNeumann(1)"])
        p60at_distinct(["cube energy NeighborOrder(1)(74)", "cube energy NeighborOrder(2)(74)"])
    end
    @testset "deterministic: the same model built twice fingerprints alike" begin
        for (label, _) in P60AT_FIXTURES
            @test p60at_fp(label) == p60at_fp(label)
        end
    end
end

@testset "P6.0at: relations that resolve alike fingerprint alike" begin
    for T in (Float64, Float32)
        p60at_like("sq contacts far=Moore(1)", ["sq contacts far=Ball(1.5)", "sq contacts far=Stencil(Moore1 permuted)"]; T)
        p60at_like("sq energy Moore(1)(40)", ["sq energy NeighborOrder(2)(40)"]; T)
        p60at_like("sq energy Stencil(+x,+y)(40)", ["sq energy Stencil(+y,+x)(40)"]; T)
    end
    p60at_like("hex contacts far=Hex(1)", ["hex contacts far=Moore(1)"])
    p60at_like("cube contacts far=Moore(1)", ["cube contacts far=NeighborOrder(3)"])
    # weights hash by value, not by the weight function
    p60at_like("sq contacts far=Weighted(Moore(1), 2)", ["sq contacts far=Weighted(Moore(1), 2) again"])
end

@testset "P6.0at: relations no generated code reads are not in the fingerprint" begin
    for T in (Float64, Float32)
        p60at_like("sq", ["sq far unused"]; T)
        p60at_like("sq observed far(40) far=Ball(2.0)", ["sq observed far(40) far=Ball(3.0)"]; T)
    end
end

# ---------------------------------------------------------------------------------------
# 3. Checkpoints do not cross named or inline gather relations

@testset "P6.0at: a checkpoint does not load under another relation" begin
    pr = p60at_problem
    @testset "contacts(far) Ball(2.0) → Ball(3.0)" begin
        p60at_checkpoint(pr("sq contacts far=Ball(2.0)"), pr("sq contacts far=Ball(3.0)"), pr("sq contacts far=Ball(2.0)"))
    end
    @testset "contacts(far) weights 3 → 2, CheckerboardCPM" begin
        p60at_checkpoint(pr("sq contacts far=Weighted(Moore(1), 3)"), pr("sq contacts far=Weighted(Moore(1), 2)"),
            pr("sq contacts far=Weighted(Moore(1), 3)"); alg = CheckerboardCPM())
    end
    @testset "a named fold in an energy" begin
        p60at_checkpoint(pr("sq energy far(40) far=Ball(3.0)"), pr("sq energy far(40) far=Ball(2.0)"),
            pr("sq energy far(40) far=Ball(3.0)"))
    end
    @testset "an inline gather in an energy" begin
        p60at_checkpoint(pr("sq energy Moore(1)(40)"), pr("sq energy Moore(2)(40)"), pr("sq energy Moore(1)(40)"))
    end
    @testset "an inline gather in a cell ODE" begin
        p60at_checkpoint(pr("sq ode Moore(2)(40)"), pr("sq ode Moore(1)(40)"), pr("sq ode Moore(2)(40)"))
    end
    @testset "a named relation in a cell ODE" begin
        p60at_checkpoint(pr("sq ode far(40) far=Ball(2.0)"), pr("sq ode far(40) far=Ball(3.0)"), pr("sq ode far(40) far=Ball(2.0)"))
    end
    @testset "a copy drive" begin
        p60at_checkpoint(pr("sq drive far far=Ball(2.0)"), pr("sq drive far far=Ball(3.0)"), pr("sq drive far far=Ball(2.0)"))
        p60at_checkpoint(pr("sq drive Moore(1)/Moore(1)"), pr("sq drive Moore(2)/Moore(2)"), pr("sq drive Moore(1)/Moore(1)"))
    end
    @testset "a site update" begin
        p60at_checkpoint(pr("sq update Moore(1)(40)"), pr("sq update Moore(2)(40)"), pr("sq update Moore(1)(40)"))
    end
    @testset "Float32: an inline gather in an energy" begin
        p60at_checkpoint(pr("sq energy Moore(2)(40)"; T = Float32), pr("sq energy Moore(1)(40)"; T = Float32),
            pr("sq energy Moore(2)(40)"; T = Float32))
    end
    @testset "hexagonal: contacts(far) Hex(2) → Hex(3)" begin
        p60at_checkpoint(pr("hex contacts far=Hex(2)"), pr("hex contacts far=Hex(3)"), pr("hex contacts far=Hex(2)"))
    end
    @testset "3D: contacts(far) Moore(1) → NeighborOrder(2)" begin
        p60at_checkpoint(pr("cube contacts far=Moore(1)"), pr("cube contacts far=NeighborOrder(2)"), pr("cube contacts far=Moore(1)"))
    end
end

@testset "P6.0at: a checkpoint loads across relations that resolve alike or are not read" begin
    pr = p60at_problem
    p60at_checkpoint(pr("sq contacts far=Ball(1.5)"), nothing, pr("sq contacts far=Moore(1)"))
    p60at_checkpoint(pr("sq energy NeighborOrder(2)(40)"), nothing, pr("sq energy Moore(1)(40)"))
    p60at_checkpoint(pr("hex contacts far=Moore(1)"), nothing, pr("hex contacts far=Hex(1)"))
    p60at_checkpoint(pr("sq far unused"), nothing, pr("sq"))
    p60at_checkpoint(pr("sq observed far(40) far=Ball(2.0)"), nothing, pr("sq observed far(40) far=Ball(3.0)"))
end

# ---------------------------------------------------------------------------------------
# 4. Pins

function p60at_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
p60at_wortel(; kw...) = PottsProblem(WortelAct(; name = :act, lattice = (8, 8), kw...), p60at_two_wortel(), (0, 10))

# The P6.0ah fixture `P60ahAt` and its builder, copied verbatim (renamed): an inline
# `Moore(1)(42)` gather in a cell rate. Its fingerprint does not depend on the model's name.
@potts_model P60atAhAt begin
    @kinds medium A
    @variables y(cell) = 0.0 g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.03 * y[3 - id] + 0.04 * sin(y) + 0.05 * exp(-y) + 0.02 * sum(volume[owner[n]] for n in Moore(1)(42)) +
               0.01 * sum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - 0.1y
    end
    @after_mcs g ~ 0.01 * sum(volume[c] for c in cells) + 0.02 * sum(y[c] for c in cells) + 0.3 * g + 0.001 * sum(1.0 for s in sites)
    @sweep Metropolis(; temperature = 1.0)
end
function p60at_ah(solver)
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return PottsProblem(P60atAhAt(; name = :x), Any[ownership => s, kind => [:A, :A]], (0, 10); seed = 7, ode_solver = solver)
end

# no named or inline gather relation read: unchanged. The fixture values were recorded on
# e4b6ab51; the PottsModels systems carry their D-122 pins (p6_0aq, p6_0p, p6_0t).
p60at_unchanged() = (
    "sq" => () -> p60at_problem("sq"),
    "sq far unused" => () -> p60at_problem("sq far unused"),
    "sq proposal=Moore(1)" => () -> p60at_problem("sq proposal=Moore(1)"),
    "sq observed far(40) far=Ball(2.0)" => () -> p60at_problem("sq observed far(40) far=Ball(2.0)"),
    "sq Float32" => () -> p60at_problem("sq"; T = Float32),
    "hex" => () -> p60at_problem("hex"),
    "cube" => () -> p60at_problem("cube"),
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
)
const P60AT_FINGERPRINTS = Dict{String, UInt64}(
    "sq" => 0x4f162b777e9799ab,
    "sq far unused" => 0x4f162b777e9799ab,
    "sq proposal=Moore(1)" => 0x84a3dc5064968e50,
    "sq observed far(40) far=Ball(2.0)" => 0x4f162b777e9799ab,
    "sq Float32" => 0x50c5cd0b28cd4266,
    "hex" => 0x7f64ce1e5b4dfc59,
    "cube" => 0xff2e2fb12cf95e96,
    "GranerGlazier" => 0x04a4528dcdf3fcb8,
    "MerksVasculogenesis" => 0x984e2ad5906fc999,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "AkeebInvasion" => 0x8d33bd0bb1eddd1c,
)

# models that read an inline gather: the old pins (D-122 values, e4b6ab51) must move; the new
# values are recorded by the implementer in D-124 and re-pinned in the earlier frozen files.
p60at_moved() = (
    "WortelAct" => () -> p60at_wortel(),
    "WortelAct connected" => () -> p60at_wortel(; connected = true),
    "P60ahAt RK4" => () -> p60at_ah(Potts.RK4()),
    "P60ahAt ExplicitEuler" => () -> p60at_ah(Potts.ExplicitEuler()),
)
const P60AT_OLD_FINGERPRINTS = Dict{String, UInt64}(
    "WortelAct" => 0xd6d4f8e4e7850c5e,
    "WortelAct connected" => 0xa2b5702602b1e8f9,
    "P60ahAt RK4" => 0x5df9f7a97301532a,
    "P60ahAt ExplicitEuler" => 0x2130555794801e36,
)

@testset "P6.0at: fingerprints of models reading no named or gather relation unchanged" begin
    for (name, build) in p60at_unchanged()
        prob = build()
        fp = prob.f.fingerprint
        @test fp == P60AT_FINGERPRINTS[name]
        fp == P60AT_FINGERPRINTS[name] || @info "P6.0at: fingerprint $name = $(repr(fp))"
    end
end

@testset "P6.0at: models reading an inline gather move off their old pins" begin
    for (name, build) in p60at_moved()
        prob = build()
        @test any(k -> startswith(string(k), "gather"), keys(prob.relations))   # the fixture is what it claims
        fp = prob.f.fingerprint
        @test fp != P60AT_OLD_FINGERPRINTS[name]
        @test build().f.fingerprint == fp                                    # deterministic
        @info "P6.0at: fingerprint $name = $(repr(fp))"
    end
end
