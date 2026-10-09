# P6.0aq (ROADMAP Phase 6, step 0): the acceptance law's parameters are in the fingerprint.
# Decision: D-121 (amends D-016, after D-118). Frozen (AUTONOMY §7.3).
#
# The defect (P6.0p review, D-118 "Review and merge"). The fingerprint hashes the generated
# code, the lattice, spacing, neighbourhood, `T`, the canonical solver spec and (D-118) the
# non-default cadences and `mcs_duration` (`_problem_function`, src/problem.jl). The sweep's
# acceptance law is solver data outside the generated code: `_acceptance(sys.sweep, T)`
# builds `CorePotts.Metropolis(offset)` / `CorePotts.Barker(offset)` into
# `CPMFunction.acceptance`, and neither the law nor its offset reaches the hash. Measured on
# 432a0a74 with the fixture below: `@sweep Metropolis(; temperature = 2.0)` with offset
# omitted, 0, 2.0 and −1.5, and `@sweep Barker(…)` with offset 0 and 2.0, all fingerprint
# 0x6eb337cf0a174b0e, so a checkpoint loads across any two of them.
#
# Inventory of `SweepSpec` (src/vocabulary.jl: law, temperature, combine, offset,
# mcs_duration) and of the other sweep inputs, on 432a0a74:
#   - `law` (:metropolis / :barker): solver data, NOT fingerprinted. Changes results. Target.
#   - `offset`: solver data, NOT fingerprinted. Changes results. Target.
#   - `temperature`: lowered into the generated `temperature` function (`_temperature_expr`),
#     so already fingerprinted. Control below (passes on the base). A temperature that reads
#     a parameter takes its value from `p`, which a continuation may change by design
#     (`PottsCheckpoint` docstring: "parameters may change at a restart").
#   - `combine`: interpolated into the cell-scope temperature function, so already
#     fingerprinted where it is used. Control below (passes on the base).
#   - `mcs_duration`: fingerprinted when non-default since D-118 (not re-tested here).
#   - the T ≤ 0 tie rule: fixed in `CorePotts.accept`, not a parameter (nothing to hash).
#   - the algorithm (`SequentialCPM` / `CheckerboardCPM`) and its `acceptance`/`proposal`
#     keywords: chosen per run at `init`, like the backend; the fingerprint belongs to the
#     problem (D-016) and cannot see them. The CorePotts checkpoint notes that continuation
#     is exact only "on the same backend and thread-independent algorithm", i.e. another
#     algorithm is a legitimate (statistical, D-063) continuation. Decided here (D-121): the
#     algorithm is NOT in the fingerprint; a SequentialCPM checkpoint loads into a
#     CheckerboardCPM `init` (pinned below as a control; passes on the base). The
#     algorithm-level `acceptance` override is a run choice too and is not pinned either way.
#   OUT OF SCOPE (reported to the coordinator, not frozen here): the `@relations proposal`
#   and `@relations contact` neighbourhoods are not fingerprinted either (Moore(1) vs the
#   default fingerprint alike on 432a0a74); WortelAct, OpenVT and Merks set
#   `proposal = Moore(1)`, so hashing a non-default proposal would move their pins, which
#   this item keeps.
#
# Semantics pinned here:
#  1. Controls (pass on the base): the offset and the law change the run (accepted-copy
#     counts under SequentialCPM at one seed: a positive offset accepts more, a negative one
#     fewer, Barker differs from Metropolis); temperature and `combine` are already in the
#     fingerprint; omitting the offset and `offset = 0` give the same fingerprint.
#  2. Problems that differ only in the acceptance law or its offset have pairwise different
#     fingerprints (Metropolis offsets omitted/2.0/−1.5/2.5, Barker offsets 0/2.0), in
#     Float64 and Float32; equal laws and offsets built twice fingerprint alike.
#  3. A checkpoint of one fails to load into another with an `ArgumentError` (in memory and
#     through save_checkpoint/load_checkpoint); a fresh build with the same law and offset
#     loads it (control: the error is the fingerprint, not tspan or the state).
#  4. Only non-default values are hashed: the default law (Metropolis, offset 0) keeps its
#     fingerprint: the fixture's value on 432a0a74 and every PottsModels system (the P6.0p
#     pins, recorded on 4e81e1eb; all use `Metropolis` with offset 0) are unchanged.
using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures: one model per sweep form (offset is not a structural parameter of `@sweep`)

const P60AQ_SWEEPS = [
    "Metropolis()" => :(Metropolis(; temperature = 2.0)),
    "Metropolis(offset = 0)" => :(Metropolis(; temperature = 2.0, offset = 0)),
    "Metropolis(offset = 2.0)" => :(Metropolis(; temperature = 2.0, offset = 2.0)),
    "Metropolis(offset = -1.5)" => :(Metropolis(; temperature = 2.0, offset = -1.5)),
    "Metropolis(offset = 2.5)" => :(Metropolis(; temperature = 2.0, offset = 2.5)),
    "Barker()" => :(Barker(; temperature = 2.0)),
    "Barker(offset = 2.0)" => :(Barker(; temperature = 2.0, offset = 2.0)),
    "Metropolis(temperature = 3.0)" => :(Metropolis(; temperature = 3.0)),
]
const P60AQ_MODELS = Dict{String, Any}()
for (i, (label, sweep)) in enumerate(P60AQ_SWEEPS)
    name = Symbol(:P60aqSweep, i)
    @eval @potts_model $name begin
        @kinds medium A
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @energy contacts => 1.0
        @sweep $sweep
    end
    P60AQ_MODELS[label] = @eval $name
end

# cell-scope temperature: `combine` decides the copy's temperature
for (name, c) in ((:P60aqCombineMin, :min), (:P60aqCombineMax, :max))
    @eval @potts_model $name begin
        @kinds medium A
        @variables Tc(cell) = 2.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @energy contacts => 1.0
        @sweep Metropolis(; temperature = Tc, combine = $c)
    end
end

"""Two 3×3 cells of kind A on a 12×12 lattice."""
function p60aq_sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
const P60AQ_OP = [ownership => p60aq_sigma(), kind => [:A, :A]]

p60aq_problem(label; T = Float64, tspan = (0, 12), seed = 1) =
    PottsProblem(P60AQ_MODELS[label](; name = :sweep), P60AQ_OP, tspan; T, seed)
p60aq_fp(label; T = Float64) = p60aq_problem(label; T).f.fingerprint

"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function p60aq_pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "P6.0aq: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end

"""A checkpoint of `pa` after `k` MCS under `alg`: refused by `pb` (ArgumentError),
accepted by `pa2` (a fresh build of `pa`'s model) under `alg2`, in memory and through a file."""
function p60aq_checkpoint_refused(pa, pb, pa2; k = 3, alg = SequentialCPM(), alg2 = alg)
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "p60aq.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        pb === nothing || @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg2; checkpoint = c)          # control: the same law and offset load
        @test i2.t == k
        @test i2.u.σ == ck.state.σ
    end
end

p60aq_accepted(label; n = 12, seed = 1) = solve(p60aq_problem(label; tspan = (0, n), seed), SequentialCPM()).stats.accepted

# ---------------------------------------------------------------------------------------
# 1. Controls (pass on the base)

@testset "P6.0aq: controls — the law and the offset change the run" begin
    @test p60aq_problem("Metropolis(offset = 2.0)").f.acceptance == CorePotts.Metropolis(2.0)
    @test p60aq_problem("Barker(offset = 2.0)").f.acceptance == CorePotts.Barker(2.0)
    m0 = p60aq_accepted("Metropolis()")
    @test m0 > 0                                              # the fixture moves at all
    @test p60aq_accepted("Metropolis(offset = 2.0)") > m0     # a positive offset accepts more
    @test p60aq_accepted("Metropolis(offset = -1.5)") < m0    # a negative one fewer
    @test p60aq_accepted("Metropolis(offset = 2.5)") != p60aq_accepted("Metropolis(offset = 2.0)")
    b0 = p60aq_accepted("Barker()")
    @test b0 != m0                                            # Barker is another law
    @test p60aq_accepted("Barker(offset = 2.0)") > b0
    # the same run twice: the counts are a function of the law, not of chance
    @test p60aq_accepted("Metropolis(offset = 2.0)") == p60aq_accepted("Metropolis(offset = 2.0)")
end

@testset "P6.0aq: controls — temperature and combine are already in the fingerprint" begin
    @test p60aq_fp("Metropolis(temperature = 3.0)") != p60aq_fp("Metropolis()")
    cmb(M) = PottsProblem(M(; name = :sweep), P60AQ_OP, (0, 12)).f.fingerprint
    @test cmb(P60aqCombineMin) != cmb(P60aqCombineMax)
    # an omitted offset is offset 0: the same model, the same fingerprint
    @test p60aq_fp("Metropolis(offset = 0)") == p60aq_fp("Metropolis()")
end

@testset "P6.0aq: controls — another algorithm continues a checkpoint (D-121)" begin
    # the algorithm is a run choice, not part of the problem's fingerprint
    p60aq_checkpoint_refused(p60aq_problem("Metropolis(offset = 2.0)"), nothing, p60aq_problem("Metropolis(offset = 2.0)");
        alg = SequentialCPM(), alg2 = CheckerboardCPM())
    p60aq_checkpoint_refused(p60aq_problem("Metropolis()"), nothing, p60aq_problem("Metropolis()");
        alg = CheckerboardCPM(), alg2 = SequentialCPM())
end

# ---------------------------------------------------------------------------------------
# 2. A different acceptance law or offset, a different fingerprint

const P60AQ_DISTINCT = ["Metropolis()", "Metropolis(offset = 2.0)", "Metropolis(offset = -1.5)", "Metropolis(offset = 2.5)",
    "Barker()", "Barker(offset = 2.0)"]

@testset "P6.0aq: the acceptance law and its offset are in the fingerprint" begin
    @testset "Float64" begin
        p60aq_pairwise_distinct([label => p60aq_fp(label) for label in P60AQ_DISTINCT])
    end
    @testset "Float32" begin
        p60aq_pairwise_distinct([label => p60aq_fp(label; T = Float32) for label in P60AQ_DISTINCT])
    end
    @testset "deterministic: the same law and offset built twice fingerprint alike" begin
        for label in P60AQ_DISTINCT
            @test p60aq_fp(label) == p60aq_fp(label)
        end
    end
end

# ---------------------------------------------------------------------------------------
# 3. Checkpoints do not cross acceptance laws or offsets

@testset "P6.0aq: a checkpoint does not load under another acceptance law or offset" begin
    pr = p60aq_problem
    @testset "Metropolis offset 2.0 → offset 0" begin
        p60aq_checkpoint_refused(pr("Metropolis(offset = 2.0)"), pr("Metropolis()"), pr("Metropolis(offset = 2.0)"))
    end
    @testset "Metropolis offset 0 → offset 2.0" begin
        p60aq_checkpoint_refused(pr("Metropolis()"), pr("Metropolis(offset = 2.0)"), pr("Metropolis()"))
    end
    @testset "Metropolis offset 2.0 → offset 2.5" begin
        p60aq_checkpoint_refused(pr("Metropolis(offset = 2.0)"), pr("Metropolis(offset = 2.5)"), pr("Metropolis(offset = 2.0)"))
    end
    @testset "Barker → Metropolis (both offset 0)" begin
        p60aq_checkpoint_refused(pr("Barker()"), pr("Metropolis()"), pr("Barker()"))
    end
    @testset "Barker offset 2.0 → Metropolis offset 2.0" begin
        p60aq_checkpoint_refused(pr("Barker(offset = 2.0)"), pr("Metropolis(offset = 2.0)"), pr("Barker(offset = 2.0)"))
    end
    @testset "Barker offset 2.0 → Barker offset 0, CheckerboardCPM" begin
        p60aq_checkpoint_refused(pr("Barker(offset = 2.0)"), pr("Barker()"), pr("Barker(offset = 2.0)"); alg = CheckerboardCPM())
    end
    @testset "Float32: Metropolis offset −1.5 → offset 0" begin
        p60aq_checkpoint_refused(pr("Metropolis(offset = -1.5)"; T = Float32), pr("Metropolis()"; T = Float32),
            pr("Metropolis(offset = -1.5)"; T = Float32))
    end
end

# ---------------------------------------------------------------------------------------
# 4. The default law keeps its fingerprint

function p60aq_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
p60aq_unchanged() = (
    "fixture Metropolis()" => () -> p60aq_problem("Metropolis()"),
    "fixture Metropolis(offset = 0)" => () -> p60aq_problem("Metropolis(offset = 0)"),
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)), p60aq_two_wortel(), (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true), p60aq_two_wortel(), (0, 10)),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
)

# the fixture recorded on 432a0a74; the PottsModels systems are the P6.0p pins (4e81e1eb)
const P60AQ_FINGERPRINTS = Dict{String, UInt64}(
    "fixture Metropolis()" => 0x6eb337cf0a174b0e,
    "fixture Metropolis(offset = 0)" => 0x6eb337cf0a174b0e,
    "GranerGlazier" => 0x04a4528dcdf3fcb8,   # re-pinned under D-122
    "WortelAct" => 0xce4f1cec820b20fe,   # re-pinned under D-124
    "WortelAct connected" => 0x7f27099ea6f348a3,   # re-pinned under D-124; re-pinned under P6.3g (D-193): fingerprint only
    "MerksVasculogenesis" => 0xe51b575884b86e8d,   # re-pinned under D-122; re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,   # re-pinned under D-122
    "AkeebInvasion" => 0xc0529959e030d017,   # re-pinned under P6.3g (D-193): fingerprint only
)

@testset "P6.0aq: fingerprints under the default acceptance law unchanged" begin
    for (name, build) in p60aq_unchanged()
        prob = build()
        @test prob.f.acceptance in (nothing, CorePotts.Metropolis(), CorePotts.Metropolis(0.0))   # the default law
        fp = prob.f.fingerprint
        @test fp == P60AQ_FINGERPRINTS[name]
        fp == P60AQ_FINGERPRINTS[name] || @info "P6.0aq: fingerprint $name = $(repr(fp))"
    end
end
