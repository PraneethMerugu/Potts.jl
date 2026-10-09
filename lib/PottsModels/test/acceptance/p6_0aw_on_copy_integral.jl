# P6.0aw (ROADMAP Phase 6, step 0): `integral(...)` in `@on_copy` right-hand sides.
# Decision: D-129. Frozen (AUTONOMY §7.3). Follow-up of D-125 (integrals rejected in drives
# and expression constraints). Related: D-045 (energies reading on-copy writes), D-080
# (`integral(Pre(x))`), D-120 (integrals refresh only for their readers).
#
# The gap (observed on bff31b39). `_dry_lower` checks drives and expression constraints with
# `_check_copy_integral` (D-125) but lowers an `@on_copy` right-hand side in the proposal
# environment without it. Today:
#   - bare, `@on_copy w[target] ~ integral(u)` / `@on_copy y[new] ~ integral(u)`: rejected
#     while lowering, by accident, with the generic "`integral(x)` is per cell: use it in cell
#     updates, …" (no copy-scope cell is bound), which names no workaround;
#   - inside a population fold over cells (`sum(integral(u) for c in cells if c == new)`,
#     also with `Pre(u)`), the model builds and runs on Sequential and Checkerboard, and each
#     accepted copy writes the integral as refreshed at the start of the MCS (measured: the
#     fold over the σ saved at the end of the previous MCS), while σ, and the volume of the
#     very cell being read, change at every accepted copy of the sweep. When an energy reads
#     the written cell variable (D-045), that stale value enters ΔH, i.e. the acceptance
#     decision, exactly the case D-125 rejects for drives.
#
# Rule (D-129): an `@on_copy` right-hand side runs once per accepted copy inside the sweep,
# like a drive or a constraint runs once per copy attempt, while an integral is refreshed only
# between sweeps. Rather than define a second, implicit "start-of-MCS" meaning for `integral`
# in copy scope, any `integral(…)` in an `@on_copy` right-hand side, site-scope
# (`x[target] ~ …`) or cell-scope (`y[new] ~ …`, `y[old] ~ …`), bare, in a fold, or with
# `Pre`, is an `ArgumentError` at build (`mtkcompile`, hence `PottsProblem`) with D-125's
# message and workaround: it names `integral`, the statement (`@on_copy`) and the workaround,
# keep the integral in a cell variable updated `@before_mcs` (`s ~ integral(x)`) and read
# `s[new]`, `s[old]`. The workaround gives the same start-of-MCS value, explicitly.
#
# Pinned here:
#  1. Rejections at build, each naming `integral`, `@on_copy`, the refresh "between sweeps"
#     and `@before_mcs` with `s ~ integral(x)`: site scope (bare; cell fold; `maximum` fold in
#     a block next to an accepted write), cell scope (bare at `new`; fold at `new`;
#     `integral(Pre(u))` fold at `old`; a cell write that an energy reads, D-045).
#  2. The workaround runs and writes the hand-checked start-of-MCS value (Sequential and
#     Checkerboard): a site write `w[target] ~ s[new]` and a cell write `y[new] ~ s[new]`
#     equal the fold of u over the σ saved one MCS earlier, at every site that changed owner
#     and every cell that gained a site.
#  3. Negative controls: `@on_copy` without integral (site `+=`, cell `+=`, a cell fold of
#     `volume`) builds and runs; an `@after_mcs` integral of a site variable written
#     `@on_copy` reads the end-of-MCS sum.
#  4. Fingerprints unchanged (recorded on bff31b39): the published model with an `@on_copy`
#     (WortelAct, both variants), Graner–Glazier, and the fixtures that build here.

using Potts: CorePotts

# ---------------------------------------------------------------------------------------
# Fixtures rejected after the change

@potts_model P60awSiteBare begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        w(site) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy w[target] ~ integral(u)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60awSiteFold begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        w(site) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy w[target] ~ sum(integral(u) for c in cells if c == new)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60awSiteBlock begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        w(site) = 0.0
        hits(site) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy begin
        hits[target] += 1
        w[target] ~ 1e-3 * maximum(integral(u) for c in cells)
    end
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60awCellBare begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        y(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy y[new] ~ integral(u)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60awCellFold begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        y(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy y[new] ~ sum(integral(u) for c in cells if c == new)
    @sweep Metropolis(; temperature = 6.0)
end

@potts_model P60awCellPreOld begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        y(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2
    @on_copy y[old] ~ sum(integral(Pre(u)) for c in cells if c == old)
    @sweep Metropolis(; temperature = 6.0)
end

# the written cell variable is read by an energy (D-045): the right-hand side enters ΔH
@potts_model P60awCellEnergy begin
    @kinds medium A
    @variables begin
        u(site) = 1.0
        y(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => 2.0 * (volume - 20)^2 + 1e-3 * y
    @on_copy y[new] ~ sum(integral(u) for c in cells if c == new)
    @sweep Metropolis(; temperature = 6.0)
end

const P60AW_REJECTED = (
    (:site, "bare", P60awSiteBare),
    (:site, "cell fold", P60awSiteFold),
    (:site, "block with an accepted write", P60awSiteBlock),
    (:cell, "bare at new", P60awCellBare),
    (:cell, "cell fold at new", P60awCellFold),
    (:cell, "integral(Pre(u)) at old", P60awCellPreOld),
    (:cell, "read by an energy", P60awCellEnergy),
)

# ---------------------------------------------------------------------------------------
# The workaround: the integral in a cell variable updated @before_mcs, read in @on_copy

# u is 100 on the left half (x ≤ 8) and 0.01 on the right; cell 1 sits on the left, cell 2
# on the right. Both 4×4 cells are below their target volume 20 and grow.
@potts_model P60awWork begin
    @kinds medium A
    @variables begin
        u(site) = 0.0
        s(cell) = 0.0
        w(site) = -1.0
        y(cell) = -1.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != kind′)
    end
    @before_mcs s ~ integral(u)
    @on_copy begin
        w[target] ~ s[new]
        y[new] ~ s[new]
    end
    @sweep Metropolis(; temperature = 6.0)
end

# negative control: @on_copy without integral, site and cell scope, and an @after_mcs
# integral of the site variable the copies write
@potts_model P60awNoIntegral begin
    @kinds medium A
    @variables begin
        u(site) = 0.0
        hits(site) = 0.0
        n(cell) = 0.0
        vn(cell) = 0.0
        h(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => 2.0 * (volume - 20)^2
        contacts => 2.0 * (kind != kind′)
    end
    @on_copy begin
        hits[target] += 1
        n[new] += 1
        vn[new] ~ sum(volume for c in cells if c == new)
    end
    @after_mcs h ~ integral(hits)
    @sweep Metropolis(; temperature = 6.0)
end

const P60AW_ALGS = (SequentialCPM(), CheckerboardCPM())
const P60AW_SIGMA = (s = zeros(Int32, 16, 16); s[2:5, 6:9] .= 1; s[11:14, 6:9] .= 2; s)
const P60AW_U0 = [i <= 8 ? 100.0 : 0.01 for i in 1:16, j in 1:16]
p60aw_op() = [ownership => P60AW_SIGMA, kind => [:A, :A], :u => P60AW_U0]
p60aw_problem(M, K = 12) = PottsProblem(M(; name = :m), p60aw_op(), (0, K))

"""Per cell 1:2, Σ over the sites of cell c in σ of `x`."""
p60aw_fold(σ, x) = [sum(x[i] for i in eachindex(σ) if σ[i] == c; init = 0.0) for c in 1:2]
"""Cells that own, in `b`, a site they did not own in `a`."""
p60aw_gainers(a, b) = sort!(unique(b[i] for i in eachindex(a) if b[i] != 0 && b[i] != a[i]))

"""The exception `f()` throws and its message (`nothing, ""` if it throws none)."""
function p60aw_error(f)
    try
        f()
    catch e
        return e, sprint(showerror, e)
    end
    return nothing, ""
end

# ---------------------------------------------------------------------------------------
# 1. Rejections at build

@testset "P6.0aw: integral in a $scope-scope @on_copy ($label) is rejected at build" for (scope, label, M) in P60AW_REJECTED
    for build in (() -> mtkcompile(M(; name = :m)), () -> PottsProblem(M(; name = :m), p60aw_op(), (0, 2)))
        e, msg = p60aw_error(build)
        @test e isa ArgumentError                                       # DEFECT CHECK (folds: build today)
        @test occursin("integral", msg)
        @test occursin("@on_copy", msg)                                 # the statement (location)
        @test occursin("between sweeps", msg)                           # DEFECT CHECK (D-125's reason)
        @test occursin("@before_mcs", msg)                              # DEFECT CHECK (the workaround)
        @test occursin("s ~ integral(x)", msg)                          # DEFECT CHECK
        @test !occursin("in @drive", msg) && !occursin("in @constraint", msg)
    end
end

# ---------------------------------------------------------------------------------------
# 2. The workaround writes the start-of-MCS value

@testset "P6.0aw: @on_copy reads the integral through a @before_mcs cell variable ($(nameof(typeof(alg))))" for alg in P60AW_ALGS
    K = 12
    sol = solve(p60aw_problem(P60awWork, K), alg; saveat = 0:K)
    @test Symbol(sol.retcode) === :Success
    σs = [Array(u.σ) for u in sol.u]
    ws = [Array(u.site.w) for u in sol.u]
    ys = [Array(u.cell.y) for u in sol.u]
    @test all(u -> Array(u.site.u) == P60AW_U0, sol.u)
    # s during MCS k (saved at k + 1): the fold of u over σ saved at k
    @test [Array(u.cell.s) for u in sol.u][2:end] ≈ [p60aw_fold(σs[k], P60AW_U0) for k in 1:K]
    # fixture: the two cells' integrals stay apart by orders of magnitude, so a value read
    # from the wrong cell or the wrong MCS cannot pass by accident
    @test all(k -> p60aw_fold(σs[k], P60AW_U0)[1] >= 1500 && p60aw_fold(σs[k], P60AW_U0)[2] <= 400, 1:K + 1)
    nsite = 0; ncell = 0; nmoved = 0
    for k in 1:K
        S = p60aw_fold(σs[k], P60AW_U0)
        # site scope: a site that changed owner to a cell got, at its last accepted copy
        # (new = its owner now), that cell's start-of-MCS integral
        for i in eachindex(σs[k])
            c = σs[k + 1][i]
            (c != 0 && c != σs[k][i]) || continue
            nsite += 1
            @test ws[k + 1][i] ≈ S[c]
        end
        # cell scope: a cell that gained a site was written its start-of-MCS integral
        for c in p60aw_gainers(σs[k], σs[k + 1])
            ncell += 1
            @test ys[k + 1][c] ≈ S[c]
            # the start-of-MCS value differs from the end-of-MCS one (the check sees the MCS)
            nmoved += abs(p60aw_fold(σs[k + 1], P60AW_U0)[c] - S[c]) > 50
        end
        # a cell that has never gained a site keeps its default
        for c in 1:2
            any(j -> c in p60aw_gainers(σs[j], σs[j + 1]), 1:k) || @test ys[k + 1][c] == -1.0
        end
    end
    @test nsite >= 10 && ncell >= 4 && nmoved >= 2                      # the checks are not vacuous
    @test any(k -> 1 in p60aw_gainers(σs[k], σs[k + 1]), 1:K) && any(k -> 2 in p60aw_gainers(σs[k], σs[k + 1]), 1:K)
    # sites far from both cells (no copy reaches them in K MCS) keep their default
    @test all(==(-1.0), ws[end][:, 15:16]) && all(==(-1.0), ws[end][:, 1:1])
end

# ---------------------------------------------------------------------------------------
# 3. Negative controls

@testset "P6.0aw: @on_copy without integral still works ($(nameof(typeof(alg))))" for alg in P60AW_ALGS
    K = 8
    sol = solve(p60aw_problem(P60awNoIntegral, K), alg; saveat = 0:K)
    @test Symbol(sol.retcode) === :Success
    σs = [Array(u.σ) for u in sol.u]
    hs = [Array(u.site.hits) for u in sol.u]
    @test any(k -> σs[k] != σs[k + 1], 1:K)                                    # the cells move
    for k in 1:K
        # every site that changed owner was hit at least once more; hits never decrease
        @test all(i -> σs[k + 1][i] == σs[k][i] || hs[k + 1][i] >= hs[k][i] + 1, eachindex(σs[k]))
        @test all(hs[k + 1] .>= hs[k])
        # a cell that gained a site counted at least one copy into it
        for c in p60aw_gainers(σs[k], σs[k + 1])
            @test sol.u[k + 1].cell.n[c] >= sol.u[k].cell.n[c] + 1
            @test sol.u[k + 1].cell.vn[c] >= 1
        end
        # @after_mcs integral of the on-copy-written site variable: the end-of-MCS sum
        @test Array(sol.u[k + 1].cell.h) ≈ p60aw_fold(σs[k + 1], hs[k + 1])
    end
    # total hits = total copies counted into cells plus copies into the medium (≥ cell count)
    @test sum(hs[end]) >= sum(Array(sol.u[end].cell.n))
end

# ---------------------------------------------------------------------------------------
# 4. Fingerprints that must not change (recorded on bff31b39)

p60aw_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
p60aw_pinned() = (
    (:GranerGlazier, () -> (g = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => g[1], kind => g[2]], (0, 10)))),
    (:WortelAct, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => p60aw_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:WortelActConnected, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true),
        [ownership => p60aw_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:P60awWork, () -> p60aw_problem(P60awWork)),
    (:P60awNoIntegral, () -> p60aw_problem(P60awNoIntegral)),
)
const P60AW_FINGERPRINTS = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x04a4528dcdf3fcb8,
    :WortelAct => 0xce4f1cec820b20fe,  # re-pinned under D-124
    :WortelActConnected => 0x7f27099ea6f348a3,  # re-pinned under D-124; re-pinned under P6.3g (D-193): fingerprint only
    :P60awWork => 0x9e008b0ce3f6cd31,
    :P60awNoIntegral => 0x8d4940ecc79e4f5a,
)

@testset "P6.0aw: fingerprints unchanged" begin
    for (name, build) in p60aw_pinned()
        fp = build().f.fingerprint
        @test fp == P60AW_FINGERPRINTS[name]
        fp == P60AW_FINGERPRINTS[name] || @info "P6.0aw: fingerprint $name = $(repr(fp))"
    end
end
