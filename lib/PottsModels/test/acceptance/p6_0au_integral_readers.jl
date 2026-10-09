# P6.0au (ROADMAP Phase 6, step 0): `integral(...)` in drives and constraints.
# Decision: D-125. Frozen (AUTONOMY §7.3). Related: D-042/D-076 (integrals in update blocks),
# D-080 (`integral(Pre(x))` outside update blocks), D-110 (hoisted fold slots), D-120
# (integrals refresh only for their readers; `_integrals_folds` gather order).
#
# The gap (from the P6.0t review; observed on e4b6ab51). `_check_geometry` rejects
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
# `@constraint` is an `ArgumentError` at build (`mtkcompile`, hence `PottsProblem`) that
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
#     cell variable equals the oracle fold over the saved σ of the previous MCS, a constraint
#     and a drive reading it veto the growth of exactly the cell above the threshold, and
#     a control without the veto lets that cell grow.
#  3. Integrals elsewhere are still accepted with their values (before block, after block,
#     `@observed`, temperature), and energies still reject them.
#  4. Negative control: drives and constraints with population folds over cells that read
#     no integral build and run.
#  5. Fingerprints unchanged (recorded on e4b6ab51) for the PottsModels systems and the
#     workaround models.

using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures rejected after the change

@potts_model P60auDriveBare begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1e-3 * integral(u)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auDriveFold begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1e-3 * sum(integral(u) for c in cells if c == new)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auDriveBlock begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive begin
        copy => -0.5 * (displacement(new, 1) - displacement(old, 1))
        copy => 1e-3 * maximum(integral(u) for c in cells)
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auChemotaxis begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive Chemotaxis(u; strength = 1e-4 * sum(integral(u) for c in cells))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auDrivePre begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @drive copy => 1e-3 * sum(integral(Pre(u)) for c in cells if c == new)
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auConstraintBare begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @constraint integral(u) > 0
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auConstraintFold begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2
    @constraint sum(integral(u) for c in cells if c == old) > -1
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model P60auConstraintBlock begin
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

const P60AU_REJECTED = (
    (:drive, "bare", P60auDriveBare),
    (:drive, "cell fold", P60auDriveFold),
    (:drive, "block", P60auDriveBlock),
    (:drive, "Chemotaxis strength", P60auChemotaxis),
    (:constraint, "bare", P60auConstraintBare),
    (:constraint, "cell fold", P60auConstraintFold),
    (:constraint, "block with rules", P60auConstraintBlock),
)

# ---------------------------------------------------------------------------------------
# The workaround: the integral in a cell variable updated @before_mcs

# u is 100 on the left half (x ≤ 8) and 0.01 on the right; cell 1 sits on the left, cell 2
# on the right, so s[1] ≥ 100 and s[2] ≤ 0.01·volume while cell 2 stays right of x = 8.
# Both 4×4 cells are below their target volume 20: each wants to grow, and losing a site
# costs ≥ 18, so the vetoed cell 1 stays alive
@potts_model P60auWorkConstraint begin
    @kinds medium A
    @parameters θ = 50.0
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != kind′)
    end
    @before_mcs s ~ integral(u)
    @constraint s[new] < θ
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60auWorkDrive begin
    @kinds medium A
    @parameters θ = 50.0
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != kind′)
    end
    @before_mcs s ~ integral(u)
    @drive copy => ifelse(s[new] > θ, 1e9, 0.0)
    @sweep Metropolis(; temperature = 6.0)
end

# integrals in every place that accepts them
@potts_model P60auElsewhere begin
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
        contacts => 2.0 * (kind != kind′)
    end
    @before_mcs sb ~ integral(u)
    @after_mcs sa ~ integral(u)
    @observed ob(cell) ~ integral(2u)
    @sweep Metropolis(; temperature = 2.0 + integral(v) / 4)
end

# energies still reject an integral
@potts_model P60auEnergy begin
    @kinds medium A
    @variables u(site) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16)^2 + 1e-3 * integral(u)
    @sweep Metropolis(; temperature = 4.0)
end

# negative control: population folds over cells in a drive and a constraint, no integral
@potts_model P60auFoldNoIntegral begin
    @kinds medium A
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 0.5 * (volume - 16)^2
    @before_mcs s ~ integral(u)
    @drive copy => 1e-3 * sum(s for c in cells if c == new)
    @constraint maximum(volume for c in cells) < 1000
    @sweep Metropolis(; temperature = 6.0)
end

const P60AU_ALGS = (SequentialCPM(), CheckerboardCPM())
const P60AU_SIGMA = (s = zeros(Int32, 16, 16); s[2:5, 6:9] .= 1; s[11:14, 6:9] .= 2; s)
const P60AU_U0 = [i <= 8 ? 100.0 : 0.01 for i in 1:16, j in 1:16]
p60au_op(extra...) = [ownership => P60AU_SIGMA, kind => [:A, :A], :u => P60AU_U0, extra...]
p60au_problem(M, K = 12; extra = ()) = PottsProblem(M(; name = :m), p60au_op(extra...), (0, K))

"""Per cell 1:2, Σ over the sites of cell c in σ of `x`."""
p60au_fold(σ, x) = [sum(x[i] for i in eachindex(σ) if σ[i] == c; init = 0.0) for c in 1:2]
p60au_cell(sol, n) = [Array(getproperty(u.cell, n)) for u in sol.u]
"""Whether cell `c` owns, in some saved state, a site it did not own in the previous one."""
p60au_gained(σs, c) = any(k -> any(i -> σs[k + 1][i] == c && σs[k][i] != c, eachindex(σs[k])), 1:length(σs) - 1)

"""The message of the exception `f()` throws (`nothing` if it throws none)."""
function p60au_error(f)
    try
        f()
    catch e
        return e, sprint(showerror, e)
    end
    return nothing, ""
end

# ---------------------------------------------------------------------------------------
# 1. Rejections at build

@testset "P6.0au: integral in a @$section ($label) is rejected at build" for (section, label, M) in P60AU_REJECTED
    e, msg = p60au_error(() -> mtkcompile(M(; name = :m)))
    @test e isa ArgumentError                                           # DEFECT CHECK (fold: builds today)
    @test occursin("integral", msg)
    @test occursin("@$section", msg)                                    # the section (location)
    @test occursin("@before_mcs", msg)                                  # DEFECT CHECK (the workaround)
    # and so does building the problem, before any step
    e2, msg2 = p60au_error(() -> PottsProblem(M(; name = :m), p60au_op(), (0, 2)))
    @test e2 isa ArgumentError                                          # DEFECT CHECK
    @test occursin("integral", msg2) && occursin("@$section", msg2)
    @test occursin("@before_mcs", msg2)                                 # DEFECT CHECK
    # a constraint's message does not send the user to drives, and vice versa
    section === :constraint && @test !occursin("in @drive", msg)
    section === :drive && @test !occursin("in @constraint", msg)
end

@testset "P6.0au: integral(Pre(u)) in a drive is rejected at build" begin
    e, msg = p60au_error(() -> PottsProblem(P60auDrivePre(; name = :m), p60au_op(), (0, 2)))
    @test e isa ArgumentError                                           # DEFECT CHECK (builds today)
    @test occursin("integral", msg) && occursin("@drive", msg)
end

# ---------------------------------------------------------------------------------------
# 2. The workaround

@testset "P6.0au: the workaround reads the integral through a cell variable ($(nameof(typeof(alg))))" for alg in P60AU_ALGS
    K = 12
    for M in (P60auWorkConstraint, P60auWorkDrive)
        sol = solve(p60au_problem(M, K), alg; saveat = 0:K)
        σs = [Array(u.σ) for u in sol.u]
        @test all(u -> Array(u.site.u) == P60AU_U0, sol.u)
        # s after MCS k: the fold over σ at the end of MCS k - 1 (the before block)
        @test p60au_cell(sol, :s)[2:end] ≈ [p60au_fold(σs[k], P60AU_U0) for k in 1:K]
        # fixture: the threshold separates the cells with margin in every state the rule sees
        @test all(k -> p60au_fold(σs[k], P60AU_U0)[1] >= 100 && p60au_fold(σs[k], P60AU_U0)[2] <= 25, 1:K)
        @test all(k -> all(>(0), p60au_fold(σs[k + 1], ones(16, 16))), 0:K)    # both cells live
        # the veto: cell 1 (s ≥ 100 > θ) never gains a site; cell 2 does
        @test !p60au_gained(σs, 1)
        @test p60au_gained(σs, 2)
        # control: without the veto (θ above every s) cell 1 grows too
        free = solve(p60au_problem(M, K; extra = (:θ => 1e9,)), alg; saveat = 0:K)
        @test p60au_gained([Array(u.σ) for u in free.u], 1)
    end
end

# ---------------------------------------------------------------------------------------
# 3. Integrals elsewhere

@testset "P6.0au: integrals outside drives and constraints still work ($(nameof(typeof(alg))))" for alg in P60AU_ALGS
    K = 8
    prob = p60au_problem(P60auElsewhere, K)
    sol = solve(prob, alg; saveat = 0:K)
    @test Symbol(sol.retcode) === :Success
    σs = [Array(u.σ) for u in sol.u]
    @test any(k -> σs[k] != σs[k + 1], 1:K)                                    # the cells move
    @test p60au_cell(sol, :sb)[2:end] ≈ [p60au_fold(σs[k], P60AU_U0) for k in 1:K]
    @test p60au_cell(sol, :sa)[2:end] ≈ [p60au_fold(σs[k + 1], P60AU_U0) for k in 1:K]
    @test Array.(sol[:ob]) ≈ [p60au_fold(σs[k + 1], 2 .* P60AU_U0) for k in 0:K]
end

@testset "P6.0au: energies still reject integral" begin
    e, msg = p60au_error(() -> mtkcompile(P60auEnergy(; name = :m)))
    @test e isa ArgumentError
    @test occursin("integral", msg) && occursin("energies", msg)
end

# ---------------------------------------------------------------------------------------
# 4. Negative control

@testset "P6.0au: cell folds without integral in drives and constraints ($(nameof(typeof(alg))))" for alg in P60AU_ALGS
    K = 6
    sol = solve(p60au_problem(P60auFoldNoIntegral, K), alg; saveat = 0:K)
    @test Symbol(sol.retcode) === :Success
    σs = [Array(u.σ) for u in sol.u]
    @test p60au_cell(sol, :s)[2:end] ≈ [p60au_fold(σs[k], P60AU_U0) for k in 1:K]
end

# ---------------------------------------------------------------------------------------
# 5. Fingerprints that must not change (recorded on e4b6ab51)

p60au_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
p60au_pinned() = (
    (:GranerGlazier, () -> (g = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => g[1], kind => g[2]], (0, 10)))),
    (:WortelAct, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => p60au_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:WortelActConnected, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [ownership => p60au_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:MerksVasculogenesis, () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
    (:SingleDivisionFixture, () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10))),
    (:OpenVTGrowingMonolayer, () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10))),
    (:AkeebInvasion, () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (99, 60)), akeeb_state(; lattice = (99, 60)), (0, 10);
        capacity = 1000)),
    (:P60auWorkConstraint, () -> p60au_problem(P60auWorkConstraint)),
    (:P60auWorkDrive, () -> p60au_problem(P60auWorkDrive)),
    (:P60auElsewhere, () -> p60au_problem(P60auElsewhere)),
    (:P60auFoldNoIntegral, () -> p60au_problem(P60auFoldNoIntegral)),
)
const P60AU_FINGERPRINTS = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x04a4528dcdf3fcb8,
    :WortelAct => 0xce4f1cec820b20fe,  # re-pinned under D-124
    :WortelActConnected => 0x7f27099ea6f348a3,  # re-pinned under D-124; re-pinned under P6.3g (D-193): fingerprint only
    :MerksVasculogenesis => 0xe51b575884b86e8d,   # re-pinned under D-189 rulings 3 and 10: dynamics change (gain test, full-shell refusal under Moore(1) copies)
    :SingleDivisionFixture => 0x13a4ddc2bb677287,
    :OpenVTGrowingMonolayer => 0xfcecc4612f387b5e,
    :AkeebInvasion => 0x3bd4b680b6f7cdec,   # re-pinned under P6.3g (D-193): fingerprint only
    :P60auWorkConstraint => 0x02d8f1e4c5c0ceaf,
    :P60auWorkDrive => 0x8f44cafaafd34959,
    :P60auElsewhere => 0x90f12fb66b4fe6bf,
    :P60auFoldNoIntegral => 0xfe046bcadac4ea2c,
)

@testset "P6.0au: fingerprints unchanged" begin
    for (name, build) in p60au_pinned()
        fp = build().f.fingerprint
        @test fp == P60AU_FINGERPRINTS[name]
        fp == P60AU_FINGERPRINTS[name] || @info "P6.0au: fingerprint $name = $(repr(fp))"
    end
end
