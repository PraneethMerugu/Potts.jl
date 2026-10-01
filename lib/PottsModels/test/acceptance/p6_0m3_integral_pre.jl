# P6.0m3 (ROADMAP Phase 6, step 0): `integral(Pre(w))` in an update block. Frozen (AUTONOMY
# §7.3). Decisions: D-042 (update-block semantics: `Pre(x)` is the value before the block),
# D-076 (fresh integrals: a bare `integral(x)` sees the block's new values), D-078 (after-MCS
# order: updates first).
#
# Semantics pinned here:
#  1. `integral(Pre(w))` read in an update block is, per cell, the sum over the cell's sites
#     (σ as the block sees it, i.e. after the sweep) of w's value at the START of the block:
#     the Pre snapshot (D-042). This holds whether the block writes `w` before or after the
#     reader runs, and whatever the declaration order of writer and reader.
#  2. A plain `integral(w)` in the same block stays fresh (D-076): it sums w's NEW values.
#  3. `integral(Pre(w))` and `integral(w)` are distinct quantities in one block and in one
#     right-hand side.
# "Both orders": the writer `w ~ …` declared before the reader, and the reader declared
# before the writer. Execution order is set by dependencies (D-042), so each order is also
# exercised with a reader that must run AFTER the writer (it also reads `integral(w)` bare)
# and with readers that only read `Pre` (free to run first).
#
# Today `integral(Pre(w))` with `w` written in the block fails with `FieldError: no field
# integral_…` (the right side is rewritten to the `w__pre` snapshot, whose integral has no
# state slot). Two plausible wrong fixes are excluded by the oracles below: refreshing the
# integral after the writer (gives 16k, the new values) and refreshing it from `w__pre`
# before the block's snapshot copy (gives 16(k-2), the snapshot of the previous MCS).

# ---------------------------------------------------------------------------------------
# Fixed cell (T = 0, E = (volume - 16)^2: every copy has ΔH = +1, rejected). w = 0 at start,
# w ~ Pre(w) + 1 every MCS, so w = k everywhere after MCS k and the cell keeps its 16 sites.
# At save k ≥ 1: integral(Pre(w)) = 16(k-1), integral(w) = 16k. At save 0 the cell
# variables keep their defaults (0).

# writer declared before the reader; the reader reads only `Pre` (may run first)
@potts_model P60m3WriterFirst begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        w ~ Pre(w) + 1
        s ~ integral(Pre(w))
    end
    @sweep Metropolis(; temperature = 0.0)
end

# reader declared before the writer
@potts_model P60m3ReaderFirst begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        s ~ integral(Pre(w))
        w ~ Pre(w) + 1
    end
    @sweep Metropolis(; temperature = 0.0)
end

# writer first; `d` reads `integral(w)` bare, so it must run after the writer, and reads
# `integral(Pre(w))` in the same right-hand side. `f` is the plain fresh integral (D-076).
@potts_model P60m3MixedWriterFirst begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
        f(cell) = 0.0
        d(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        w ~ Pre(w) + 1
        s ~ integral(Pre(w))
        f ~ integral(w)
        d ~ integral(w) - integral(Pre(w))
    end
    @sweep Metropolis(; temperature = 0.0)
end

# the same, readers declared before the writer
@potts_model P60m3MixedReaderFirst begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
        f(cell) = 0.0
        d(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        d ~ integral(w) - integral(Pre(w))
        f ~ integral(w)
        s ~ integral(Pre(w))
        w ~ Pre(w) + 1
    end
    @sweep Metropolis(; temperature = 0.0)
end

# control (runs today): `w` written in @before_mcs, so in the after block it is not written
# and `Pre(w)` is its current value, k after MCS k: integral(Pre(w)) = 16k
@potts_model P60m3BeforeWriter begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @before_mcs w ~ Pre(w) + 1
    @after_mcs s ~ integral(Pre(w))
    @sweep Metropolis(; temperature = 0.0)
end

p60m3_cell(sol, n) = [Array(getproperty(u.cell, n))[1] for u in sol.u]
p60m3_solve(M, alg, σ, K; kw...) = solve(PottsProblem(M(; name = :m), [ownership => σ, kind => [:A]], (0, K); kw...), alg;
    saveat = 0:K)

@testset "P6.0m3: integral(Pre(w)) reads the block-start values ($(nameof(typeof(alg))))" for
    alg in (SequentialCPM(), CheckerboardCPM())
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    K = 4
    pre = [k == 0 ? 0.0 : 16.0 * (k - 1) for k in 0:K]      # 0, 0, 16, 32, 48
    new = [16.0 * k for k in 0:K]                             # 0, 16, 32, 48, 64
    diff = [k == 0 ? 0.0 : 16.0 for k in 0:K]                 # 0, 16, 16, 16, 16
    # negative controls: the oracle tells the semantics from the two plausible wrong fixes
    after_writer = new                                        # refreshed after the write
    stale_snapshot = [k == 0 ? 0.0 : 16.0 * max(k - 2, 0) for k in 0:K]   # w__pre before its copy
    @test pre != after_writer && pre != stale_snapshot

    @test p60m3_cell(p60m3_solve(P60m3BeforeWriter, alg, σ, K), :s) == new   # control

    @testset "Pre only, $order" for (M, order) in ((P60m3WriterFirst, "writer first"), (P60m3ReaderFirst, "reader first"))
        sol = p60m3_solve(M, alg, σ, K)                                     # DEFECT CHECK (FieldError)
        @test p60m3_cell(sol, :volume) == fill(16, K + 1)
        @test [sum(Array(u.site.w)[Array(u.σ) .== 1]) for u in sol.u] == new   # w itself is right
        @test p60m3_cell(sol, :s) == pre                                       # DEFECT CHECK
    end
    @testset "Pre and fresh, $order" for (M, order) in ((P60m3MixedWriterFirst, "writer first"),
                                                         (P60m3MixedReaderFirst, "reader first"))
        sol = p60m3_solve(M, alg, σ, K)                                     # DEFECT CHECK (FieldError)
        @test p60m3_cell(sol, :volume) == fill(16, K + 1)
        @test p60m3_cell(sol, :s) == pre                                       # DEFECT CHECK
        @test p60m3_cell(sol, :f) == new                                       # fresh (D-076)
        @test p60m3_cell(sol, :d) == diff                                      # DEFECT CHECK
    end
end

# ---------------------------------------------------------------------------------------
# Moving cell (T = 4): the sweep changes the cell's sites, so the integral must fold the
# post-sweep σ (the block's σ) with the block-start w. w0[i, j] = i, w ~ Pre(w) + 1, so at
# the start of MCS k's after block w[i, j] = i + k - 1, and after it i + k. Oracle per save
# k ≥ 1, from the saved σ (the after block does not move σ):
#   integral(Pre(w)) = Σ_{σ_k == 1} (i + k - 1),   integral(w) = Σ_{σ_k == 1} (i + k).
p60m3_fold(σ, k) = sum(Float64(I[1] + k) for I in CartesianIndices(σ) if σ[I] == 1; init = 0.0)

@potts_model P60m3Moving begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        s(cell) = 0.0
        f(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        s ~ integral(Pre(w))
        w ~ Pre(w) + 1
        f ~ integral(w)
    end
    @sweep Metropolis(; temperature = 4.0)
end

@testset "P6.0m3: integral(Pre(w)) folds the post-sweep sites ($(nameof(typeof(alg))))" for
    alg in (SequentialCPM(), CheckerboardCPM())
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    w0 = [Float64(i) for i in 1:12, j in 1:12]
    K = 6
    sol = solve(PottsProblem(P60m3Moving(; name = :m), [ownership => σ, kind => [:A], :w => w0], (0, K)), alg; saveat = 0:K)
    σs = [Array(u.σ) for u in sol.u]
    # negative control: the cell moved, so pre-sweep and post-sweep σ give different folds
    @test any(k -> p60m3_fold(σs[k + 1], k - 1) != p60m3_fold(σs[k], k - 1), 1:K)
    @test all(k -> Array(sol.u[k + 1].site.w) == w0 .+ k, 0:K)
    @test p60m3_cell(sol, :s)[2:end] ≈ [p60m3_fold(σs[k + 1], k - 1) for k in 1:K]   # DEFECT CHECK
    @test p60m3_cell(sol, :f)[2:end] ≈ [p60m3_fold(σs[k + 1], k) for k in 1:K]       # fresh (D-076)
end
