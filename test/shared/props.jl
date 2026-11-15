# Shared property-test helpers (TS-R2 §2, §3, §4):
# - `fp_props`: fingerprint sensitivity, invariance, checkpoint compatibility, and subprocess determinism
# - `stat_accept` / `required_n`: normal/t/TOST statistical acceptance helpers with stated α and power
# - `observed_orders` / `observed_order`: empirical convergence-order helpers
# - `tiny_oracle_sample` / `tiny_oracle_check`: tiny-lattice transition-kernel enumerator helpers
#
# Designed to be `include`d inside a ReTestItems `@testsetup` module.

using Test: @test, @test_throws

if !isdefined(@__MODULE__, :stat_accept)
    include(joinpath(@__DIR__, "stats_helpers.jl"))
end

if !isdefined(@__MODULE__, :Oracle)
    include(joinpath(@__DIR__, "..", "..", "lib", "CorePotts", "test", "oracle_core.jl"))
end

# --- Fingerprint property helpers (§2.1, §5) ---------------------------------------------

function _assert_checkpoint_refused(base_prob, mut_prob)
    integ = init(base_prob, SequentialCPM(); save_start = false)
    ck = checkpoint(integ)
    @test_throws ArgumentError init(mut_prob, SequentialCPM(); checkpoint = ck)
end

function _assert_checkpoint_accepted(base_prob, eq_prob)
    integ = init(base_prob, SequentialCPM(); save_start = false)
    ck = checkpoint(integ)
    loaded = init(eq_prob, SequentialCPM(); checkpoint = ck)
    @test loaded.state.σ == integ.state.σ
end

"""
    fp_props(make_base; variants = (), invariants = (), check_checkpoint = true,
             check_algorithms = false, subprocess_expr = nothing, project = dirname(@__DIR__))

Verify fingerprint properties for a problem family without stored literal pins:
- same-session determinism (`make_base()` built twice gives equal fingerprints)
- sensitivity: every `(label, make_mut)` in `variants` changes `prob.f.fingerprint`
  (and refuses a checkpoint from `base` when `check_checkpoint` is true)
- invariance: every `(label, make_eq)` in `invariants` preserves `prob.f.fingerprint`
  (and accepts a checkpoint from `base` when `check_checkpoint` is true)
- optional algorithm independence (`SequentialCPM` vs `CheckerboardCPM`)
- optional fresh-subprocess determinism (`subprocess_expr` prints `repr(fp)` or `string(fp)`).
"""
function fp_props(make_base;
        variants = (),
        invariants = (),
        check_checkpoint::Bool = true,
        check_algorithms::Bool = false,
        subprocess_expr::Union{Nothing, AbstractString} = nothing,
        project::AbstractString = dirname(@__DIR__))
    base = make_base()
    fp0 = base.f.fingerprint
    @test make_base().f.fingerprint == fp0

    for (label, make_mut) in variants
        @testset "sensitivity: $label" begin
            mut = make_mut()
            @test mut.f.fingerprint != fp0
            check_checkpoint && _assert_checkpoint_refused(base, mut)
        end
    end

    for (label, make_eq) in invariants
        @testset "invariance: $label" begin
            eq = make_eq()
            @test eq.f.fingerprint == fp0
            check_checkpoint && _assert_checkpoint_accepted(base, eq)
        end
    end

    if check_algorithms
        ck = checkpoint(init(base, SequentialCPM(); save_start = false))
        cb = init(base, CheckerboardCPM(); checkpoint = ck)
        @test cb.state.σ == ck.state.σ
    end

    if subprocess_expr !== nothing
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $subprocess_expr`
        out = strip(read(cmd, String))
        @test parse(UInt64, out) == fp0
    end

    return (; base = fp0, sensitivity = length(variants), invariance = length(invariants))
end

# --- Tiny-lattice transition-kernel enumerator helpers -----------------------------------

function tiny_oracle_sample(prob, alg, R::Integer)
    counts = Dict{Vector{Int8}, Int}()
    for seed in 1:R
        σ = vec(Int8.(solve(remake(prob; seed), alg; save_start = false).u[end].σ))
        counts[σ] = get(counts, σ, 0) + 1
    end
    return counts
end

function tiny_oracle_check(tiny::Oracle.Tiny, σ0::Vector{Int8}, nmcs::Integer, step, prob, alg;
        R::Integer = 40_000)
    ex = Oracle.exact(tiny, σ0, nmcs, step)
    counts = tiny_oracle_sample(prob, alg, R)
    d, noise = Oracle.tv(ex, counts, R)
    z = Oracle.chi2_z(ex, counts, R)
    return (; z, tv = d, noise, exact = ex, counts)
end
