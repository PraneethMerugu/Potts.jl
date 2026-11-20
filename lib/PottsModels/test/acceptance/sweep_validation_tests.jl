# `@sweep` validation and `combine` hashing.
# Decision: D-123 (amends D-016/D-121).
#
# The defects (`acceptance_law_fingerprint_tests.jl` review, D-121 "Review"), measured on b14a81cd:
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
#     copy-scope temperature where `combine` is not called).
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
#     function, or a callable struct to carry parameters.
#  C. A named or callable-struct `combine` fingerprints the same in another `julia`
#     process (perturbed by extra anonymous functions and types defined first), and a
#     checkpoint written there loads here; a callable struct with other fields is refused.

@testsetup module SweepValidationSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using TOML: TOML
# ---------------------------------------------------------------------------------------
# Fixtures. The named-combine models are one source string, evaluated here and in the
# subprocess (part C), so both sessions build exactly the same models.
const DEFS = raw"""
sweep_mean(a, b) = (a + b) / 2
module Combine
mix(a, b) = 0.25 * a + 0.75 * b
end
struct Mix
    w::Float64
end
(m::Mix)(a, b) = m.w * a + (1 - m.w) * b

const NAMED = [
    "min" => :min, "max" => :max, "+" => :+, "sweep_mean" => :sweep_mean,
    "Combine.mix" => :(Combine.mix), "Mix(0.3)" => :(Mix(0.3)), "Mix(0.7)" => :(Mix(0.7)),
]
const NAMED_MODELS = Dict{String, Any}()
for (i, (label, c)) in enumerate(NAMED)
    name = Symbol(:Named, i)
    @eval @potts_model $name begin
        @kinds medium A
        @variables Tc(cell) = 2.0
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @energy contacts => 1.0
        @sweep Metropolis(; temperature = Tc, combine = $c)
    end
    NAMED_MODELS[label] = @eval $name
end

function sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
sweep_op() = [ownership => sigma(), kind => [:A, :A]]
named_problem(label; T = Float64) = PottsProblem(NAMED_MODELS[label](; name = :sweep), sweep_op(), (0, 12); T, seed = 1)
"""
# The definitions are evaluated in `Main`, as the worker process below evaluates them, so the
# fingerprints of the two agree (shared/main_definitions.jl).
include(joinpath(@__DIR__, "..", "shared", "main_definitions.jl"))
define_in_main(@__MODULE__, :NAMED_MODELS, :(using Potts, PottsModels, TOML), DEFS, "sweep_validation_definitions")
# a model per sweep form; built lazily, so a form `@sweep` rejects throws at `M(; name)`
const SWEEPS = Dict{String, Any}()
function def(label, sweep; cell = false)
    name = Symbol(:Sweep, length(SWEEPS) + 1)
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
    SWEEPS[label] = @eval $name
end
sys(label) = SWEEPS[label](; name = :sweep)
problem(label; T = Float64) = PottsProblem(sys(label), sweep_op(), (0, 12); T, seed = 1)
# A. offsets
const BAD_OFFSETS = ["NaN" => :NaN, "Inf" => :Inf, "-Inf" => :(-Inf), "NaN32" => :NaN32, "-Inf32" => :(-Inf32)]
for law in (:Metropolis, :Barker), (l, o) in BAD_OFFSETS
    def("$law(offset = $l)", :($law(; temperature = 2.0, offset = $o)))
end
const GOOD_OFFSETS = ["0" => 0, "-0.0" => -0.0, "2" => 2, "-1.5" => -1.5, "2.0f0" => 2.0f0, "1e300" => 1.0e300]
for law in (:Metropolis, :Barker), (l, o) in GOOD_OFFSETS
    def("$law(offset = $l)", :($law(; temperature = 2.0, offset = $o)))
end
def("Metropolis()", :(Metropolis(; temperature = 2.0)))
def("Barker()", :(Barker(; temperature = 2.0)))
def("unknown keyword", :(Metropolis(; temperature = 2.0, ofset = 1.0)))
# control

# B. combine forms without a stable identity
sweep_mk(w) = (a, b) -> w * a + (1 - w) * b
function sweep_local()
    inner(a, b) = max(a, b)          # a local named function: a closure type `#inner#…`
    return inner
end
anon = (a, b) -> 0.5a + 0.5b
# a non-constant global bound to an anonymous function
const ANON_C3 = sweep_mk(0.3)
const LOCAL = sweep_local()
const UNSTABLE = [
    "inline anonymous" => :((a, b) -> 0.5a + 0.5b),
    "global anonymous" => :anon,
    "closure sweep_mk(0.3)" => :ANON_C3,
    "local named function" => :LOCAL,
]
for (l, c) in UNSTABLE
    def("cell: $l", :(Metropolis(; temperature = Tc, combine = $c)); cell = true)
    def("copy: $l", :(Metropolis(; temperature = 2.0, combine = $c)))           # combine unused, still rejected
    def("barker cell: $l", :(Barker(; temperature = Tc, combine = $c)); cell = true)
end
"""`f()` throws an ArgumentError whose message contains every one of `words`."""
function argerror(f, words...)
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
# C. Named and callable-struct `combine` is session-stable
"""Run the named-combine fixtures in a fresh `julia` process (perturbed first) and return its
fingerprints and the paths of checkpoints it wrote after 3 MCS."""
function sweep_worker(dir)
    outfile = joinpath(dir, "out.toml")
    script = joinpath(dir, "worker.jl")
    write(
        script, """
        using Potts, PottsModels, TOML
        # perturb the session: compiler-generated names now start elsewhere
        for i in 1:9
            @eval noise = (x -> x + \$i)
        end
        struct NoiseType end
        module NoiseModule; f(a, b) = a; g = (a, b) -> b; end
        """ * DEFS * """
            r = Dict{String, Any}()
            for (label, _) in NAMED
                prob = named_problem(label)
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
            """
    )
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script`
    run(cmd)
    return TOML.parsefile(outfile)
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "sweep validation: controls" setup = [SweepValidationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # Controls (pass on the base)
    @testset "sweep validation: controls" begin
        # an `@sweep` ArgumentError surfaces from building the system (the channel A and B use)
        argerror(() -> sys("unknown keyword"), "ofset")
        # offset 0 / -0.0 are the default law
        fp_default = problem("Metropolis()").f.fingerprint
        @test problem("Metropolis(offset = 0)").f.fingerprint == fp_default
        @test problem("Metropolis(offset = -0.0)").f.fingerprint == fp_default
        # combine is in the fingerprint where it is called (cell-scope temperature)
        fps = [label => named_problem(label).f.fingerprint for (label, _) in NAMED]
        for i in eachindex(fps), j in (i + 1):lastindex(fps)
            @test fps[i].second != fps[j].second
        end
    end
end

@testitem "sweep validation: a non-finite offset is an ArgumentError" setup = [SweepValidationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # A. A non-finite offset is rejected; finite offsets are accepted
    @testset "sweep validation: a non-finite offset is an ArgumentError" begin
        for law in (:Metropolis, :Barker), (l, _) in BAD_OFFSETS
            @testset "$law(offset = $l)" begin
                argerror(() -> sys("$law(offset = $l)"), "offset")
            end
        end
        # the sweep constructor itself (the macro's target)
        for law in (:metropolis, :barker), o in (NaN, Inf, -Inf, NaN32, Inf32, -Inf32)
            @test_throws ArgumentError Potts.sweep_spec(law; temperature = 2.0, offset = o)
        end
    end
end

@testitem "sweep validation: finite offsets are accepted" setup = [SweepValidationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "sweep validation: finite offsets are accepted" begin
        for law in (:Metropolis, :Barker), (l, o) in GOOD_OFFSETS
            @testset "$law(offset = $l)" begin
                prob = problem("$law(offset = $l)")
                @test prob.f.acceptance isa (law === :Metropolis ? CorePotts.Metropolis : CorePotts.Barker)
                @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
            end
        end
        for law in (:metropolis, :barker), o in (0, -0.0, 3, -2.5, 1.0f-3, floatmax(Float64))
            s = Potts.sweep_spec(law; temperature = 2.0, offset = o)
            @test s.offset == Float64(o)
        end
    end
end

@testitem "sweep validation: combine without a stable identity is an ArgumentError" setup = [SweepValidationSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # B. An anonymous function or closure as `combine` is rejected
    @testset "sweep validation: combine without a stable identity is an ArgumentError" begin
        for (l, _) in UNSTABLE, scope in ("cell", "copy", "barker cell")
            @testset "$scope: $l" begin
                argerror(() -> sys("$scope: $l"), "combine")
            end
        end
        for f in (anon, ANON_C3, LOCAL, (a, b) -> a)
            @test_throws ArgumentError Potts.sweep_spec(:metropolis; temperature = 2.0, combine = f)
        end
        # named functions and callable structs are accepted by the constructor
        for f in (min, max, +, sweep_mean, Combine.mix, Mix(0.3))
            @test Potts.sweep_spec(:metropolis; temperature = 2.0, combine = f).combine === f
        end
    end
end

@testitem "sweep validation: named combine fingerprints alike in another process" setup = [SweepValidationSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "sweep validation: named combine fingerprints alike in another process" begin
        mktempdir() do dir
            r = sweep_worker(dir)
            for (label, _) in NAMED
                @testset "$label" begin
                    here = named_problem(label)
                    there = parse(UInt64, r["fp " * label])
                    @test here.f.fingerprint == there
                    # the other session's checkpoint loads here
                    ck = load_checkpoint(r["ck " * label])
                    integ = init(here, SequentialCPM(); checkpoint = ck)
                    @test integ.t == 3
                    @test current_state(integ).ownership == ck.state.ownership
                end
            end
            # negative controls: the harness compares real values (another combine differs, and
            # a checkpoint of another combine is refused)
            @test parse(UInt64, r["fp max"]) != named_problem("min").f.fingerprint
            @test parse(UInt64, r["fp Mix(0.3)"]) != named_problem("Mix(0.7)").f.fingerprint
            @test_throws ArgumentError init(
                named_problem("Mix(0.7)"), SequentialCPM();
                checkpoint = load_checkpoint(r["ck Mix(0.3)"])
            )
            @test_throws ArgumentError init(named_problem("min"), SequentialCPM(); checkpoint = load_checkpoint(r["ck max"]))
        end
    end
end
