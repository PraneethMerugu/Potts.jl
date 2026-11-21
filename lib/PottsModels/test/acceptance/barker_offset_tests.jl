# `Barker(; offset)` carries its offset.
#
# The defect. `@sweep Barker(; temperature = T, offset = δ)` is accepted by `sweep_spec`,
# but `_acceptance` (src/problem.jl) returns `CorePotts.Barker()` for `:barker`, so δ is
# silently dropped; `CorePotts.Barker` has no offset at all.
#
# Resolution pinned here: CARRY the offset (not reject it). Reasons:
#   - `offset = ε` in docs/src/manual/sweep.md is a row of the `@sweep` table shared by both
#     laws, not a Metropolis-only option, and `sweep_spec` already takes it for `:barker`.
#   - Metropolis defines the offset as a shift of ΔH: it is the plain law applied to
#     x = ΔH − offset (`x = dH - T(law.offset)` in lib/CorePotts/src/algorithms.jl), and its
#     T ≤ 0 tie rule is stated on x (`ΔH == offset`). The same shift on Barker is
#     well-defined and keeps the documented identity "at T ≤ 0 the two laws coincide"
#     (manual: both accept ΔH < 0 and half the ties) true for every offset.
#   - Morpheus's yield Y (offset = −Y) is a ΔH shift independent of the acceptance function.
#
# Surface fixed by this file:
#
#   CorePotts.Barker(; offset = 0)          # `Barker()` keeps working; field `offset`
#   CorePotts.Barker(offset)                # positional, like `Metropolis(offset)`
#   CorePotts.accept(law::Barker, dH::T, temperature::T, u::T)
#       x = dH - T(law.offset)
#       temperature ≤ 0:  x < 0 || (x == 0 && u < 0.5)          (Metropolis's T ≤ 0 rule)
#       otherwise:        u < inv(one(T) + exp(x / temperature))
#     i.e. p = 1/(1 + e^{(ΔH − offset)/T}), computed exactly in that form, so the pinned
#     threshold points below are bitwise.
#   A model built with `@sweep Barker(; temperature, offset = δ)` has `prob.f.acceptance`
#   a `CorePotts.Barker` with `offset == δ` (stored as the problem's scalar type, as for
#   Metropolis); `SequentialCPM(; acceptance = Barker(; offset = δ))` and
#   `CheckerboardCPM(; acceptance = …)` run under it.
#   `offset = 0` reproduces today's Barker bit for bit.
#
# Oracles. The trajectories are compared, bit for bit, with runs under test-defined
# acceptance laws (`BarkerRef`), subtypes of `CorePotts.AbstractAcceptanceLaw` implementing
# the formula above (and, with δ = 0, today's Barker formula verbatim), passed through the
# algorithm's `acceptance` keyword. They are independent of `CorePotts.Barker`, so a law
# that ignores δ, or applies it with the wrong sign, fails the comparison.
#
#  1. CorePotts level: `accept` at exact thresholds (u = p accepted iff u < p) for several
#     (ΔH, T, offset), including negative offsets and T ≤ 0 ties on x = ΔH − offset.
#  2. `@sweep Barker(; offset = δ)` is carried: `prob.f.acceptance.offset == δ`; the run
#     equals the reference-law run on SequentialCPM and CheckerboardCPM, and δ > 0 changes
#     more sites, δ < 0 fewer, than δ = 0 at the same seed.
#  3. `SequentialCPM(; acceptance = Barker(; offset = δ))` (and CheckerboardCPM) overrides
#     the model's law and equals the reference-law run.
#  4. `offset = 0` (model and algorithm forms) reproduces today's Barker bit for bit:
#     identical to a run with no offset given, and to the legacy-formula reference law.

@testsetup module BarkerOffsetSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ------------------------------------------------------------------------------------------
# Reference acceptance law (independent of CorePotts.Barker)
# ------------------------------------------------------------------------------------------
struct BarkerRef{F} <: CorePotts.AbstractAcceptanceLaw
    offset::F
end
@inline function CorePotts.accept(law::BarkerRef, dH::T, temperature::T, u::T) where {T}
    x = dH - T(law.offset)
    temperature <= zero(T) && return x < zero(T) || (x == zero(T) && u < T(0.5))
    return u < inv(one(T) + exp(x / temperature))
end
# Today's Barker, verbatim (lib/CorePotts/src/algorithms.jl at 416e9285).
struct Legacy <: CorePotts.AbstractAcceptanceLaw end
@inline function CorePotts.accept(::Legacy, dH::T, temperature::T, u::T) where {T}
    temperature <= zero(T) && return dH < zero(T) || (dH == zero(T) && u < T(0.5))
    return u < inv(one(T) + exp(dH / temperature))
end
barker_p(dH, T, δ) = inv(one(dH) + exp((dH - δ) / T))
# ------------------------------------------------------------------------------------------
# Fixture: a small two-kind sorting model under Barker, one model per sweep form
# ------------------------------------------------------------------------------------------
const BARKER_T = 4.0
for (name, sweep) in (
        (:None, :(Barker(; temperature = 4.0))),
        (:Zero, :(Barker(; temperature = 4.0, offset = 0))),
        (:Plus, :(Barker(; temperature = 4.0, offset = 3.0))),
        (:Minus, :(Barker(; temperature = 4.0, offset = -2.5))),
    )
    @eval @potts_model $name begin
        @kinds medium dark light
        @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        @lattice Lattice((20, 20); neighborhood = Moore(1))
        @energy begin
            Volume(dark, light; target = 16.0, strength = 1.0)
            Adhesion(J)
        end
        @sweep $sweep
    end
end
function problem(model; seed = 7, tspan = (0, 20))
    σ = zeros(Int32, 20, 20)
    id = 0
    for i in 0:2, j in 0:2
        id += 1
        σ[(3 + 5i):(6 + 5i), (3 + 5j):(6 + 5j)] .= id
    end
    kinds = [isodd(k) ? :dark : :light for k in 1:id]
    return PottsProblem(
        model(; name = :barker), [ownership => σ, kind => kinds], tspan;
        seed
    )
end
function barker_run(prob, alg)
    sol = solve(prob, alg; saveat = 1)
    return (;
        σs = [copy(u.ownership) for u in sol.u],
        accepted = sol.stats.accepted, attempts = sol.stats.attempts,
    )
end
same(a, b) = a.σs == b.σs && a.accepted == b.accepted && a.attempts == b.attempts
# Activity: sites changed between consecutive saved states (CheckerboardCPM does not count
# acceptances in `sol.stats`, so the direction check uses this for both algorithms).
activity(r) = sum(count(r.σs[k + 1] .!= r.σs[k]) for k in 1:(length(r.σs) - 1))
const ALGS = (
    ("SequentialCPM", acc -> SequentialCPM(; acceptance = acc)),
    ("CheckerboardCPM", acc -> CheckerboardCPM(; acceptance = acc)),
)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "barker offset: CorePotts.Barker carries an offset" setup = [
    BarkerOffsetSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 1. CorePotts level
    # --------------------------------------------------------------------------------------
    @testset "barker offset: CorePotts.Barker carries an offset" begin
        @test CorePotts.Barker().offset == 0
        @test CorePotts.Barker(; offset = 1.5).offset == 1.5
        @test CorePotts.Barker(1.5).offset == 1.5
        @test CorePotts.Barker(; offset = 1.5) isa CorePotts.AbstractAcceptanceLaw

        # T > 0: accepted iff u < p = 1/(1 + e^{(ΔH − δ)/T}), at the exact threshold
        for (dH, T, δ) in (
                (0.0, 1.0, 0.0), (0.0, 1.0, 1.0), (2.0, 1.0, 2.0), (3.0, 2.0, 1.0),
                (-1.0, 0.5, -3.0), (5.0, 10.0, -2.5), (1.0, 4.0, 7.0),
            )
            law = CorePotts.Barker(; offset = δ)
            p = barker_p(dH, T, δ)
            @test CorePotts.accept(law, dH, T, prevfloat(p))
            @test !CorePotts.accept(law, dH, T, p)
            # Float32 path (Metal-sized scalars)
            p32 = barker_p(Float32(dH), Float32(T), Float32(δ))
            @test CorePotts.accept(
                CorePotts.Barker(; offset = Float32(δ)),
                Float32(dH), Float32(T), prevfloat(p32)
            )
            @test !CorePotts.accept(
                CorePotts.Barker(; offset = Float32(δ)), Float32(dH),
                Float32(T), p32
            )
        end
        # the shift is ΔH − offset: a tie at ΔH == offset is accepted with probability ½
        @test CorePotts.accept(CorePotts.Barker(; offset = 2.0), 2.0, 1.0, prevfloat(0.5))
        @test !CorePotts.accept(CorePotts.Barker(; offset = 2.0), 2.0, 1.0, 0.5)
        # a positive offset raises, a negative one lowers, the acceptance of the same ΔH
        @test CorePotts.accept(CorePotts.Barker(; offset = 1.0), 1.0, 1.0, 0.45)
        @test !CorePotts.accept(CorePotts.Barker(), 1.0, 1.0, 0.45)
        @test !CorePotts.accept(CorePotts.Barker(; offset = -1.0), 0.0, 1.0, 0.45)
        @test CorePotts.accept(CorePotts.Barker(), 0.0, 1.0, 0.45)

        # T ≤ 0: Metropolis's rule on x = ΔH − offset (accept x < 0, half of x == 0)
        for T in (0.0, -1.0)
            for (dH, δ) in ((0.5, 1.0), (-3.0, -2.0), (0.0, 0.25))     # x < 0: always
                @test CorePotts.accept(CorePotts.Barker(; offset = δ), dH, T, 0.999)
            end
            for (dH, δ) in ((0.0, -1.0), (2.0, 1.0), (-1.0, -2.0))     # x > 0: never
                @test !CorePotts.accept(CorePotts.Barker(; offset = δ), dH, T, 0.0)
            end
            for (dH, δ) in ((1.0, 1.0), (-2.5, -2.5), (0.0, 0.0))      # x == 0: u < ½
                @test CorePotts.accept(
                    CorePotts.Barker(; offset = δ), dH, T,
                    prevfloat(0.5)
                )
                @test !CorePotts.accept(CorePotts.Barker(; offset = δ), dH, T, 0.5)
            end
            # and coincides with Metropolis(offset) there, for every u
            for (dH, δ) in ((0.5, 1.0), (0.0, -1.0), (1.0, 1.0)),
                    u in (0.0, prevfloat(0.5), 0.5, 0.9)

                @test CorePotts.accept(CorePotts.Barker(; offset = δ), dH, T, u) ==
                    CorePotts.accept(CorePotts.Metropolis(; offset = δ), dH, T, u)
            end
        end
    end
end

@testitem "barker offset: @sweep Barker(; offset) reaches the acceptance law" setup = [
    BarkerOffsetSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 2. `@sweep Barker(; offset = δ)` is carried into the run
    # --------------------------------------------------------------------------------------
    @testset "barker offset: @sweep Barker(; offset) reaches the acceptance law" begin
        for (model, δ) in ((Plus, 3.0), (Minus, -2.5))
            prob = problem(model)
            law = prob.f.acceptance
            @test law isa CorePotts.Barker
            @test law.offset == δ
        end
        @test problem(None).f.acceptance.offset == 0
        @test problem(Zero).f.acceptance.offset == 0
    end
end

@testitem "barker offset: @sweep Barker(; offset) runs under 1/(1 + e^{(ΔH − δ)/T})" setup =
    [BarkerOffsetSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "barker offset: @sweep Barker(; offset) runs under 1/(1 + e^{(ΔH − δ)/T}) \
        ($name)" for (name, mk) in ALGS
        base = barker_run(problem(None), mk(nothing))
        for (model, δ) in ((Plus, 3.0), (Minus, -2.5))
            prob = problem(model)
            got = barker_run(prob, mk(nothing))                       # the model's own law
            ref = barker_run(problem(None), mk(BarkerRef(δ)))
            @test same(got, ref)
            @test !same(got, base)                             # δ is not dropped
            # direction: δ > 0 accepts more, δ < 0 fewer, at the same seed
            @test δ > 0 ? activity(got) > activity(base) : activity(got) < activity(base)
        end
    end
end

@testitem "barker offset (; acceptance = Barker(; offset)) carries the offset" setup = [
    BarkerOffsetSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 3. The algorithm keyword carries it too
    # --------------------------------------------------------------------------------------
    @testset "barker offset $name(; acceptance = Barker(; offset)) carries the offset" for (
            name, mk,
        ) in ALGS
        prob = problem(None)
        base = barker_run(prob, mk(nothing))
        for δ in (3.0, -2.5)
            alg = mk(CorePotts.Barker(; offset = δ))
            @test CorePotts._law(alg, prob.f).offset == δ
            got = barker_run(prob, alg)
            @test same(got, barker_run(prob, mk(BarkerRef(δ))))
            @test !same(got, base)
        end
        # the algorithm's law overrides the model's offset
        @test same(
            barker_run(problem(Plus), mk(CorePotts.Barker(; offset = -2.5))),
            barker_run(prob, mk(BarkerRef(-2.5)))
        )
    end
end

@testitem "barker offset: offset = 0 reproduces today's Barker" setup = [
    BarkerOffsetSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 4. offset = 0 is today's Barker, bit for bit
    # --------------------------------------------------------------------------------------
    @testset "barker offset: offset = 0 reproduces today's Barker ($name)" for (
            name,
            mk,
        ) in ALGS
        prob = problem(None)
        legacy = barker_run(prob, mk(Legacy()))
        # no offset given
        @test same(barker_run(prob, mk(nothing)), legacy)
        # `offset = 0` in @sweep
        @test same(barker_run(problem(Zero), mk(nothing)), legacy)
        @test same(barker_run(prob, mk(CorePotts.Barker())), legacy)
        # oracle self-check
        @test same(barker_run(prob, mk(BarkerRef(0.0))), legacy)
        # negative control: the legacy oracle is sensitive to the law
        @test !same(barker_run(prob, mk(BarkerRef(3.0))), legacy)
    end
end
