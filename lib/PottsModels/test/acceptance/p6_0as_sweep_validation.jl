# P6.0as (ROADMAP Phase 6, step 0): `@sweep` validation and `combine` hashing.
# Decision: D-123 (amends D-016/D-121). Frozen (AUTONOMY §7.3).
#
# The defects (P6.0aq review, D-121 "Review"), measured on b14a81cd:
#  1. `sweep_spec` (src/vocabulary.jl) converts `offset` with `Float64(offset)` and accepts
#     NaN, Inf and -Inf. A NaN offset makes every acceptance comparison false (the run is
#     meaningless); ±Inf accepts or rejects every copy whatever ΔH is.
#  2. The cell-scope temperature interpolates the `combine` object into the generated
#     temperature function (`_temperature_expr`, src/codegen.jl), and the fingerprint hashes
#     `string(expr)`. What that string holds for each kind of `combine` (two separate
#     `julia` processes, the second defining 7 anonymous functions first):
#       - a named function: its module path and name (`min`, `(+)`, `Main.mymix`,
#         `Main.Inner.mix2`; Base names print bare). Printing does not depend on the active
#         module (no `:module` in the IOContext), so the string is the same in every
#         session. Stable; already right.
#       - an instance of a callable struct `Mix(0.3)`: the type path and field values,
#         printed by `show`. Stable, and two instances with other fields differ.
#       - an anonymous function: `var"#2#3"()` in one process, `var"#23#24"()` in the
#         other; an inline `(a, b) -> …` in the `@sweep`: `var"#50#51"()` vs `var"#71#72"()`.
#         The counter is session-global, so the same model fingerprints differently in two
#         sessions (a checkpoint is refused for no reason) and two different anonymous
#         functions can get the same name in two sessions (a checkpoint loads across them:
#         unsafe). The body is never hashed.
#       - a closure from a generator `mk(w) = (a, b) -> …`: `var"#mk##0#mk##1"{Float64}(0.3)`,
#         a compiler-generated name (stable only while the source of `mk` keeps its
#         closures in the same order) plus the captured values.
#     No PottsModels system sets `combine` (they all keep the default `min`, or use a
#     copy-scope temperature where `combine` is not called), so none of their pins depends
#     on this.
#
# Rule (D-123), pinned here:
#  A. `offset` must be finite: NaN, Inf and -Inf are an `ArgumentError` from `@sweep`
#     (`sweep_spec`, so building the system throws), for Metropolis and Barker alike, in
#     Float64 and Float32. Every finite offset (0, -0.0, integers, Float32, large values) is
#     accepted as before.
#  B. `combine` must have a stable identity: a named function (a constant global binding,
#     hashed by its module path and name, as printed today) or an instance of a named
#     callable type (hashed by its printed value). An anonymous function or a closure (a
#     compiler-generated type name, starting with `#`) is an `ArgumentError` from `@sweep`
#     whose message names `combine`, whatever the temperature's scope: define a named
#     function, or a callable struct to carry parameters. Named `combine` keeps its
#     fingerprint (the generated code is unchanged), so every existing pin stays.
#  C. A named or callable-struct `combine` fingerprints the same in another `julia`
#     process (perturbed by extra anonymous functions and types defined first), and a
#     checkpoint written there loads here; a callable struct with other fields is refused.
#     The generated temperature code holds no compiler-generated (`var"#…"`) name.
#  D. Unchanged pins: the default fixture, the named-combine fixtures recorded on
#     b14a81cd, and every PottsModels system (the D-121/D-122 pins).
using Potts: CorePotts
using TOML: TOML

# ---------------------------------------------------------------------------------------
# Fixtures. The named-combine models are one source string, evaluated here and in the
# subprocess (part C), so both sessions build exactly the same models.

const P60AS_DEFS = raw"""
p60as_mean(a, b) = (a + b) / 2
module P60asCombine
mix(a, b) = 0.25 * a + 0.75 * b
end
struct P60asMix
    w::Float64
end
(m::P60asMix)(a, b) = m.w * a + (1 - m.w) * b

const P60AS_NAMED = [
    "min" => :min, "max" => :max, "+" => :+, "p60as_mean" => :p60as_mean,
    "P60asCombine.mix" => :(P60asCombine.mix), "P60asMix(0.3)" => :(P60asMix(0.3)), "P60asMix(0.7)" => :(P60asMix(0.7)),
]
const P60AS_NAMED_MODELS = Dict{String, Any}()
for (i, (label, c)) in enumerate(P60AS_NAMED)
    name = Symbol(:P60asNamed, i)
    @eval @potts_model $name begin
        @kinds medium A
        @variables Tc(cell) = 2.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @energy contacts => 1.0
        @sweep Metropolis(; temperature = Tc, combine = $c)
    end
    P60AS_NAMED_MODELS[label] = @eval $name
end

function p60as_sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
p60as_op() = [ownership => p60as_sigma(), kind => [:A, :A]]
p60as_named_problem(label; T = Float64) = PottsProblem(P60AS_NAMED_MODELS[label](; name = :sweep), p60as_op(), (0, 12); T, seed = 1)
"""
include_string(@__MODULE__, P60AS_DEFS, "p6_0as_defs")

# a model per sweep form; built lazily, so a form `@sweep` rejects throws at `M(; name)`
const P60AS_SWEEPS = Dict{String, Any}()
function p60as_def(label, sweep; cell = false)
    name = Symbol(:P60asSweep, length(P60AS_SWEEPS) + 1)
    if cell
        @eval @potts_model $name begin
            @kinds medium A
            @variables Tc(cell) = 2.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @energy contacts => 1.0
            @sweep $sweep
        end
    else
        @eval @potts_model $name begin
            @kinds medium A
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @energy contacts => 1.0
            @sweep $sweep
        end
    end
    P60AS_SWEEPS[label] = @eval $name
end
p60as_sys(label) = P60AS_SWEEPS[label](; name = :sweep)
p60as_problem(label; T = Float64) = PottsProblem(p60as_sys(label), p60as_op(), (0, 12); T, seed = 1)

# A. offsets
const P60AS_BAD_OFFSETS = ["NaN" => :NaN, "Inf" => :Inf, "-Inf" => :(-Inf), "NaN32" => :NaN32, "-Inf32" => :(-Inf32)]
for law in (:Metropolis, :Barker), (l, o) in P60AS_BAD_OFFSETS
    p60as_def("$law(offset = $l)", :($law(; temperature = 2.0, offset = $o)))
end
const P60AS_GOOD_OFFSETS = ["0" => 0, "-0.0" => -0.0, "2" => 2, "-1.5" => -1.5, "2.0f0" => 2.0f0, "1e300" => 1.0e300]
for law in (:Metropolis, :Barker), (l, o) in P60AS_GOOD_OFFSETS
    p60as_def("$law(offset = $l)", :($law(; temperature = 2.0, offset = $o)))
end
p60as_def("Metropolis()", :(Metropolis(; temperature = 2.0)))
p60as_def("Barker()", :(Barker(; temperature = 2.0)))
p60as_def("unknown keyword", :(Metropolis(; temperature = 2.0, ofset = 1.0)))     # control

# B. combine forms without a stable identity
p60as_mk(w) = (a, b) -> w * a + (1 - w) * b
function p60as_local()
    inner(a, b) = max(a, b)          # a local named function: a closure type `#inner#…`
    return inner
end
p60as_anon = (a, b) -> 0.5a + 0.5b   # a non-constant global bound to an anonymous function
const P60AS_ANON_C3 = p60as_mk(0.3)
const P60AS_LOCAL = p60as_local()
const P60AS_UNSTABLE = [
    "inline anonymous" => :((a, b) -> 0.5a + 0.5b),
    "global anonymous" => :p60as_anon,
    "closure p60as_mk(0.3)" => :P60AS_ANON_C3,
    "local named function" => :P60AS_LOCAL,
]
for (l, c) in P60AS_UNSTABLE
    p60as_def("cell: $l", :(Metropolis(; temperature = Tc, combine = $c)); cell = true)
    p60as_def("copy: $l", :(Metropolis(; temperature = 2.0, combine = $c)))           # combine unused, still rejected
    p60as_def("barker cell: $l", :(Barker(; temperature = Tc, combine = $c)); cell = true)
end

"""`f()` throws an ArgumentError whose message contains every one of `words`."""
function p60as_argerror(f, words...)
    err = try
        f()
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    err isa ArgumentError && for w in words
        @test occursin(w, err.msg)
    end
    return err
end

# ---------------------------------------------------------------------------------------
# Controls (pass on the base)

@testset "P6.0as: controls" begin
    # an `@sweep` ArgumentError surfaces from building the system (the channel A and B use)
    p60as_argerror(() -> p60as_sys("unknown keyword"), "ofset")
    # the default law keeps its D-121 fingerprint, and offset 0 / -0.0 are the default
    @test p60as_problem("Metropolis()").f.fingerprint == 0x6eb337cf0a174b0e
    @test p60as_problem("Metropolis(offset = 0)").f.fingerprint == 0x6eb337cf0a174b0e
    @test p60as_problem("Metropolis(offset = -0.0)").f.fingerprint == 0x6eb337cf0a174b0e
    # negative control: an anonymous function's printed form is a compiler-generated name,
    # so the `var"#` probe of part C does detect one
    @test occursin("var\"#", string(:($(p60as_anon)(a, b))))
    @test occursin("var\"#", string(:($(P60AS_ANON_C3)(a, b))))
    @test !occursin("var\"#", string(:($(P60asCombine.mix)(a, b))))
    # combine is in the fingerprint where it is called (cell-scope temperature)
    fps = [label => p60as_named_problem(label).f.fingerprint for (label, _) in P60AS_NAMED]
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        @test fps[i].second != fps[j].second
    end
end

# ---------------------------------------------------------------------------------------
# A. A non-finite offset is rejected; finite offsets are accepted

@testset "P6.0as: a non-finite offset is an ArgumentError" begin
    for law in (:Metropolis, :Barker), (l, _) in P60AS_BAD_OFFSETS
        @testset "$law(offset = $l)" begin
            p60as_argerror(() -> p60as_sys("$law(offset = $l)"), "offset")
        end
    end
    # the sweep constructor itself (the macro's target)
    for law in (:metropolis, :barker), o in (NaN, Inf, -Inf, NaN32, Inf32, -Inf32)
        @test_throws ArgumentError Potts.sweep_spec(law; temperature = 2.0, offset = o)
    end
end

@testset "P6.0as: finite offsets are accepted" begin
    for law in (:Metropolis, :Barker), (l, o) in P60AS_GOOD_OFFSETS
        @testset "$law(offset = $l)" begin
            prob = p60as_problem("$law(offset = $l)")
            @test prob.f.acceptance isa (law === :Metropolis ? CorePotts.Metropolis : CorePotts.Barker)
            @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
        end
    end
    for law in (:metropolis, :barker), o in (0, -0.0, 3, -2.5, 1.0f-3, floatmax(Float64))
        s = Potts.sweep_spec(law; temperature = 2.0, offset = o)
        @test s.offset == Float64(o)
    end
end

# ---------------------------------------------------------------------------------------
# B. An anonymous function or closure as `combine` is rejected

@testset "P6.0as: combine without a stable identity is an ArgumentError" begin
    for (l, _) in P60AS_UNSTABLE, scope in ("cell", "copy", "barker cell")
        @testset "$scope: $l" begin
            p60as_argerror(() -> p60as_sys("$scope: $l"), "combine")
        end
    end
    for f in (p60as_anon, P60AS_ANON_C3, P60AS_LOCAL, (a, b) -> a)
        @test_throws ArgumentError Potts.sweep_spec(:metropolis; temperature = 2.0, combine = f)
    end
    # named functions and callable structs are accepted by the constructor
    for f in (min, max, +, p60as_mean, P60asCombine.mix, P60asMix(0.3))
        @test Potts.sweep_spec(:metropolis; temperature = 2.0, combine = f).combine === f
    end
end

# ---------------------------------------------------------------------------------------
# C. Named and callable-struct `combine` is session-stable

@testset "P6.0as: the temperature code names combine by a stable identity" begin
    for (label, _) in P60AS_NAMED
        s = string(Base.remove_linenums!(deepcopy(generated_code(P60AS_NAMED_MODELS[label](; name = :sweep)).temperature)))
        @test !occursin("var\"#", s)
    end
end

"""Run the named-combine fixtures in a fresh `julia` process (perturbed first) and return its
fingerprints and the paths of checkpoints it wrote after 3 MCS."""
function p60as_worker(dir)
    outfile = joinpath(dir, "out.toml")
    script = joinpath(dir, "worker.jl")
    write(script, """
    using Potts, PottsModels, TOML
    # perturb the session: compiler-generated names now start elsewhere
    for i in 1:9
        @eval p60as_noise = (x -> x + \$i)
    end
    struct P60asNoiseType end
    module P60asNoiseModule; f(a, b) = a; g = (a, b) -> b; end
    """ * P60AS_DEFS * """
    r = Dict{String, Any}()
    for (label, _) in P60AS_NAMED
        prob = p60as_named_problem(label)
        r["fp " * label] = repr(prob.f.fingerprint)
        integ = init(prob, SequentialCPM())
        for _ in 1:3
            step!(integ)
        end
        path = joinpath($(repr(dir)), "ck " * label * ".jls")
        save_checkpoint(path, checkpoint(integ))
        r["ck " * label] = path
    end
    open(io -> TOML.print(io, r), $(repr(outfile)), "w")
    """)
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`
    run(cmd)
    return TOML.parsefile(outfile)
end

@testset "P6.0as: named combine fingerprints alike in another process" begin
    mktempdir() do dir
        r = p60as_worker(dir)
        for (label, _) in P60AS_NAMED
            @testset "$label" begin
                here = p60as_named_problem(label)
                there = parse(UInt64, r["fp " * label])
                @test here.f.fingerprint == there
                # the other session's checkpoint loads here
                ck = load_checkpoint(r["ck " * label])
                integ = init(here, SequentialCPM(); checkpoint = ck)
                @test integ.t == 3
                @test integ.u.σ == ck.state.σ
            end
        end
        # negative controls: the harness compares real values (another combine differs, and
        # a checkpoint of another combine is refused)
        @test parse(UInt64, r["fp max"]) != p60as_named_problem("min").f.fingerprint
        @test parse(UInt64, r["fp P60asMix(0.3)"]) != p60as_named_problem("P60asMix(0.7)").f.fingerprint
        @test_throws ArgumentError init(p60as_named_problem("P60asMix(0.7)"), SequentialCPM();
            checkpoint = load_checkpoint(r["ck P60asMix(0.3)"]))
        @test_throws ArgumentError init(p60as_named_problem("min"), SequentialCPM(); checkpoint = load_checkpoint(r["ck max"]))
    end
end

# ---------------------------------------------------------------------------------------
# D. Unchanged pins

function p60as_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
p60as_unchanged() = (
    "fixture Metropolis()" => () -> p60as_problem("Metropolis()"),
    "fixture Metropolis(offset = 2)" => () -> p60as_problem("Metropolis(offset = 2)"),
    "fixture Barker(offset = -1.5)" => () -> p60as_problem("Barker(offset = -1.5)"),
    (("combine " * label) => (() -> p60as_named_problem(label)) for (label, _) in P60AS_NAMED)...,
    ("combine $label Float32" => (() -> p60as_named_problem(label; T = Float32)) for label in ("min", "P60asCombine.mix"))...,
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)), p60as_two_wortel(), (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true), p60as_two_wortel(), (0, 10)),
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

# the fixtures recorded on b14a81cd; the PottsModels systems are the D-121/D-122 pins
const P60AS_FINGERPRINTS = Dict{String, UInt64}(
    "fixture Metropolis()" => 0x6eb337cf0a174b0e,
    "fixture Metropolis(offset = 2)" => 0x78bb06853bde9a10,
    "fixture Barker(offset = -1.5)" => 0xf08a29ae32a9efa8,
    "combine min" => 0x5feb039d56b02a3b,
    "combine max" => 0xb4eaf9fd061f8301,
    "combine +" => 0x4df4cfd758dcab1f,
    "combine p60as_mean" => 0xb7f611fbac07502c,
    "combine P60asCombine.mix" => 0x5bc25a5e335498f9,
    "combine P60asMix(0.3)" => 0x4836306c6e61bb70,
    "combine P60asMix(0.7)" => 0x0d52d586a119fb08,
    "combine min Float32" => 0x38e017d24b57e251,
    "combine P60asCombine.mix Float32" => 0x60ffc4e9af6c0abe,
    "GranerGlazier" => 0x04a4528dcdf3fcb8,
    "WortelAct" => 0xce4f1cec820b20fe,  # re-pinned under D-124
    "WortelAct connected" => 0x993142c5fb9c8f2f,  # re-pinned under D-124
    "MerksVasculogenesis" => 0x984e2ad5906fc999,
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,
    "AkeebInvasion" => 0x8d33bd0bb1eddd1c,
)

@testset "P6.0as: fingerprints unchanged" begin
    for (name, build) in p60as_unchanged()
        fp = build().f.fingerprint
        @test fp == P60AS_FINGERPRINTS[name]
        fp == P60AS_FINGERPRINTS[name] || @info "P6.0as: fingerprint $name = $(repr(fp))"
    end
end
