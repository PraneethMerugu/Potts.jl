# `integral(...)` in drives and constraints.
# Decision: D-125. Related: D-042/D-076 (integrals in update blocks),
# D-080 (`integral(Pre(x))` outside update blocks), D-110 (hoisted fold slots), D-120
# (integrals refresh only for their readers; `_integrals_folds` gather order).
#
# The gap (observed on e4b6ab51). `_check_geometry` rejects
# `integral` only in energies; `_integrals_folds` (src/lower.jl) gathers integrals from
# updates, equations, division conditions and rules, link rules, the temperature, discrete
# ticks and `@observed`, never from `sys.drives` or `sys.constraints`, so an integral there
# has no `integral_*` cell column. Today:
#   - bare, `@drive copy => integral(u)` / `@constraint integral(u) > 0`: rejected while
#     lowering, by accident, with the generic "`integral(x)` is per cell: use it in cell
#     updates, division conditions or observed quantities" (no copy-scope cell is bound);
#   - inside a population fold over cells, which binds a cell
#     (`@drive copy => sum(integral(u) for c in cells if c == new)`, the same in a
#     `@constraint` or in `Chemotaxis(…; strength = …)`): the model builds, `PottsProblem`
#     builds without the column, and the first `solve` dies with
#     `FieldError: type NamedTuple has no field integral_…`.
#
# Rule (D-125): drives and constraints are evaluated per copy attempt inside the sweep
# (`_delta_H_expr`, the constraint test in src/codegen.jl), where σ moves at every accepted
# copy while an integral is refreshed only between sweeps; like energies, they reject it.
# Any `integral(…)` in a `@drive` (including `Chemotaxis` arguments) or an expression
# `@constraint` is a `PottsCompileError` at build (`mtkcompile`, hence `PottsProblem`) that
# names `integral`, the section (the statement's location) and the workaround: keep the
# integral in a cell variable updated `@before_mcs` (`s ~ integral(x)`) and read `s[new]`,
# `s[old]`. `connectivity(…)` and `no_extinction` carry no user expression.
#
# Pinned here:
#  1. Rejections at build, each naming `integral`, the section and `@before_mcs`: drives
#     (bare; in a cell fold; in a block next to an accepted drive; in `Chemotaxis`
#     strength), expression constraints (bare; in a cell fold; in a block next to
#     `connectivity` and `no_extinction`); `integral(Pre(u))` in a drive is rejected too.
#  2. The workaround runs and reads the right values (Sequential and Checkerboard): the
#     cell variable equals the oracle fold over the saved σ of the previous MCS, a
#     constraint and a drive reading it veto the growth of exactly the cell above the
#     threshold, and a control without the veto lets that cell grow.
#  3. Integrals elsewhere are still accepted with their values (before block, after block,
#     `@observed`, temperature), and energies still reject them.
#  4. Negative control: drives and constraints with population folds over cells that read
#     no integral build and run.
#  5. Fingerprints unchanged (recorded on e4b6ab51) for the PottsModels systems and the
#     workaround models.

@testsetup module IntegralReadersSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# ---------------------------------------------------------------------------------------
# Fixtures rejected after the change
@potts_model DriveBare begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1.0e-3 * integral(u)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model DriveFold begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1.0e-3 * sum(integral(u) for c in cells if c == new)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model DriveBlock begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive begin
        copy => -0.5 * (displacement(new, 1) - displacement(old, 1))
        copy => 1.0e-3 * maximum(integral(u) for c in cells)
    end
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model ReadersChemotaxis begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive Chemotaxis(u; strength = 1.0e-4 * sum(integral(u) for c in cells))
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model DrivePre begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1.0e-3 * sum(integral(Pre(u)) for c in cells if c == new)
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model ConstraintBare begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @constraint integral(u) > 0
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model ConstraintFold begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @constraint sum(integral(u) for c in cells if c == old) > -1
    @sweep Metropolis(; temperature = 4.0)
end
@potts_model ConstraintBlock begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy cells => (volume - 16)^2
    @constraint begin
        connectivity(A)
        no_extinction
        count(integral(u) > 1000 for c in cells) < 3
    end
    @sweep Metropolis(; temperature = 4.0)
end
const REJECTED = (
    (:drive, "bare", DriveBare),
    (:drive, "cell fold", DriveFold),
    (:drive, "block", DriveBlock),
    (:drive, "Chemotaxis strength", ReadersChemotaxis),
    (:constraint, "bare", ConstraintBare),
    (:constraint, "cell fold", ConstraintFold),
    (:constraint, "block with rules", ConstraintBlock),
)
# ---------------------------------------------------------------------------------------
# The workaround: the integral in a cell variable updated @before_mcs

# u is 100 on the left half (x ≤ 8) and 0.01 on the right; cell 1 sits on the left, cell 2
# on the right, so s[1] ≥ 100 and s[2] ≤ 0.01·volume while cell 2 stays right of x = 8.
# Both 4×4 cells are below their target volume 20: each wants to grow, and losing a site
# costs ≥ 18, so the vetoed cell 1 stays alive
@potts_model WorkConstraint begin
    @kinds medium A
    @parameters θ = 50.0
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != neighbor_kind)
    end
    @before_mcs s ~ integral(u)
    @constraint s[new] < θ
    @sweep Metropolis(; temperature = 6.0)
end
@potts_model WorkDrive begin
    @kinds medium A
    @parameters θ = 50.0
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != neighbor_kind)
    end
    @before_mcs s ~ integral(u)
    @drive copy => ifelse(s[new] > θ, 1.0e9, 0.0)
    @sweep Metropolis(; temperature = 6.0)
end
# integrals in every place that accepts them
@potts_model Elsewhere begin
    @kinds medium A
    @variables begin
        u(site) = 0.0
        v(site) = 1.0
        sb(cell) = 0.0
        sa(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 0.5 * (volume - 16)^2
        contacts => 2.0 * (kind != neighbor_kind)
    end
    @before_mcs sb ~ integral(u)
    @after_mcs sa ~ integral(u)
    @observed ob(cell) ~ integral(2u)
    @sweep Metropolis(; temperature = 2.0 + integral(v) / 4)
end
# energies still reject an integral
@potts_model Energy begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2 + 1.0e-3 * integral(u)
    @sweep Metropolis(; temperature = 4.0)
end
# negative control: population folds over cells in a drive and a constraint, no integral
@potts_model FoldNoIntegral begin
    @kinds medium A
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 0.5 * (volume - 16)^2
    @before_mcs s ~ integral(u)
    @drive copy => 1.0e-3 * sum(s for c in cells if c == new)
    @constraint maximum(volume for c in cells) < 1000
    @sweep Metropolis(; temperature = 6.0)
end
const ALGS = (SequentialCPM(), CheckerboardCPM())
const SIGMA = (s = zeros(Int32, 16, 16); s[2:5, 6:9] .= 1; s[11:14, 6:9] .= 2; s)
const READERS_U0 = [i <= 8 ? 100.0 : 0.01 for i in 1:16, j in 1:16]
readers_op(extra...) = [ownership => SIGMA, kind => [:A, :A], :u => READERS_U0, extra...]
problem(M, K = 12; extra = ()) = PottsProblem(M(; name = :m), readers_op(extra...), (0, K))
"""Per cell 1:2, Σ over the sites of cell c in σ of `x`."""
readers_fold(σ, x) = [sum(x[i] for i in eachindex(σ) if σ[i] == c; init = 0.0) for c in 1:2]
readers_cell(sol, n) = [Array(getproperty(u.cell, n)) for u in sol.u]
"""Whether cell `c` owns, in some saved state, a site it did not own in the previous one."""
function gained(σs, c)
    return any(
        k -> any(i -> σs[k + 1][i] == c && σs[k][i] != c, eachindex(σs[k])),
        1:(length(σs) - 1)
    )
end
"""The message of the exception `f()` throws (`nothing` if it throws none)."""
function readers_error(f)
    try
        f()
    catch e
        return e, sprint(showerror, e)
    end
    return nothing, ""
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "integral readers: integral in a @ is rejected at build" setup = [
    IntegralReadersSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 1. Rejections at build
    @testset "integral readers: integral in a @$section ($label) is rejected at build" for (
            section, label, M,
        ) in REJECTED
        e, msg = readers_error(() -> mtkcompile(M(; name = :m)))
        # DEFECT CHECK (fold: builds today)
        @test e isa Potts.PottsCompileError
        @test occursin("integral", msg)
        # and so does building the problem, before any step
        e2, msg2 = readers_error(() -> PottsProblem(M(; name = :m), readers_op(), (0, 2)))
        @test e2 isa Potts.PottsCompileError                                # DEFECT CHECK
        @test occursin("integral", msg2)
    end
end

@testitem "integral readers: integral(Pre(u)) in a drive is rejected at build" setup = [
    IntegralReadersSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "integral readers: integral(Pre(u)) in a drive is rejected at build" begin
        e, msg = readers_error(
            () -> PottsProblem(
                DrivePre(; name = :m), readers_op(), (
                    0, 2,
                )
            )
        )
        # DEFECT CHECK (builds today)
        @test e isa Potts.PottsCompileError
        @test occursin("integral", msg)
    end
end

@testitem "integral readers: the workaround reads the integral through a cell \
    variable" setup = [IntegralReadersSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 2. The workaround
    @testset "integral readers: the workaround reads the integral through a cell variable \
        ($(nameof(typeof(alg))))" for alg in ALGS
        K = 12
        for M in (WorkConstraint, WorkDrive)
            sol = solve(problem(M, K), alg; saveat = 0:K)
            σs = [Array(u.ownership) for u in sol.u]
            @test all(u -> Array(u.site.u) == READERS_U0, sol.u)
            # s after MCS k: the fold over σ at the end of MCS k - 1 (the before block)
            @test readers_cell(sol, :s)[2:end] ≈
                [readers_fold(σs[k], READERS_U0) for k in 1:K]
            # fixture: the threshold separates the cells with margin in every state the rule
            # sees (SequentialCPM only, D-271: the checkerboard's cell 2 holds a hot site
            # for one MCS)
            alg isa SequentialCPM &&
                @test all(
                k -> readers_fold(σs[k], READERS_U0)[1] >= 100 &&
                    readers_fold(σs[k], READERS_U0)[2] <= 25,
                1:K
            )
            # both cells live
            @test all(k -> all(>(0), readers_fold(σs[k + 1], ones(16, 16))), 0:K)
            # the veto: cell 1 (s ≥ 100 > θ) never gains a site; cell 2 does
            @test !gained(σs, 1)
            @test gained(σs, 2)
            # control: without the veto (θ above every s) cell 1 grows too
            free = solve(problem(M, K; extra = (:θ => 1.0e9,)), alg; saveat = 0:K)
            @test gained([Array(u.ownership) for u in free.u], 1)
        end
    end
end

@testitem "integral readers: integrals outside drives and constraints still work" setup = [
    IntegralReadersSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 3. Integrals elsewhere
    @testset "integral readers: integrals outside drives and constraints still work \
        ($(nameof(typeof(alg))))" for alg in ALGS
        K = 8
        prob = problem(Elsewhere, K)
        sol = solve(prob, alg; saveat = 0:K)
        @test Symbol(sol.retcode) === :Success
        σs = [Array(u.ownership) for u in sol.u]
        # the cells move
        @test any(k -> σs[k] != σs[k + 1], 1:K)
        @test readers_cell(sol, :sb)[2:end] ≈ [readers_fold(σs[k], READERS_U0) for k in 1:K]
        @test readers_cell(sol, :sa)[2:end] ≈
            [readers_fold(σs[k + 1], READERS_U0) for k in 1:K]
        @test Array.(sol[:ob]) ≈ [readers_fold(σs[k + 1], 2 .* READERS_U0) for k in 0:K]
    end
end

@testitem "integral readers: energies still reject integral" setup = [
    IntegralReadersSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "integral readers: energies still reject integral" begin
        e, msg = readers_error(() -> mtkcompile(Energy(; name = :m)))
        @test e isa Potts.PottsCompileError
        @test occursin("integral", msg)
    end
end

@testitem "integral readers: cell folds without integral in drives and constraints" setup =
    [IntegralReadersSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # 4. Negative control
    @testset "integral readers: cell folds without integral in drives and constraints \
        ($(nameof(typeof(alg))))" for alg in ALGS
        K = 6
        sol = solve(problem(FoldNoIntegral, K), alg; saveat = 0:K)
        @test Symbol(sol.retcode) === :Success
        σs = [Array(u.ownership) for u in sol.u]
        @test readers_cell(sol, :s)[2:end] ≈ [readers_fold(σs[k], READERS_U0) for k in 1:K]
    end
end
