# edge-scope MCS updates through
# `mtkcompile`.
#
# The defect, measured on 405915dc: `@before_mcs`/`@after_mcs` statements that write an edge
# variable (`rest(edge)`, `rest(bond)`) are accepted by `@potts_model` and listed by
# `Potts.updates(sys)` with scope `:edge` (D-164), but `mtkcompile` fails with an opaque
#     KeyError: key :edge not found
# from `_schedule_block` (src/schedule.jl: the stage order knows `:model`, `:cell` and
# `:site` only). `PottsProblem` compiles first, so no model with an edge update can run.
#
# Rule (supported, not refused): an edge-scope MCS update runs once per existing link of
# the written variable's relationship, with the meaning the existing edge machinery already
# gives an edge (the `edges(rel) => …` term and `@unlink` condition environment):
#  C. `mtkcompile` accepts it, and `Potts.updates(csys)` on the
#     compiled form equals the authored listing (phase, scope `:edge`, cadence and the
#     `isequal` equation; the `update_rules_tests.jl` F check extended to the compiled
#     form).
#  B. Behaviour, on a frozen configuration (every copy costs ≥ ~990 at T = 1, so σ and the
#     centroids never change; checked) with links (1,2) at d = 8 and (2,3) at d = 10 and
#     (1,3) unlinked:
#       - `@after_mcs rest ~ Pre(rest) + κ * (distance - Pre(rest))` (κ = 0.25, rest₀ = 12)
#         gives, at save t, rest = d + (12 - d)·0.75ᵗ on each link: each link's own
#         centroid distance, applied once per link per MCS (not once per stored end), the
#         same value at both ends of the link;
#       - `Pre(rest)` is the value before the block; `distance` and parameters read as in
#         `edges(rel)`;
#       - cadence and phase as D-164: `@before_mcs Every(3) age ~ Pre(age) + 1` runs before
#         MCS 0 and 3, so its saved value steps at t = 1, 4 (2 at t = 6);
#       - a cell update in the same block still runs (`g += 1`: 6 after 6 MCS);
#       - no link is created or removed, and empty link slots keep their 0 payload;
#       - SequentialCPM and CheckerboardCPM agree; Float32 at rtol 1e-5.
#  R. An edge update reads only its own relationship's edge variables (as `_check_edge_vars`
#     already requires of edge terms and link rules): writing `rest(bond)` from
#     `len(tether)` is a `PottsCompileError` at `mtkcompile` naming `len` and `tether`, not
#     a KeyError.
#  D. On the device (POTTS_GPU = metal | rocm; Float32, CheckerboardCPM): the same payloads
#     as the CPU at rtol 1e-5.
#
# Negative controls (pass before this item): the same model without the edge updates keeps
# rest = 12 and age = 0 on both links, σ unchanged, links unchanged (so the decay comes from
# the update, and the configuration is frozen); the expected values differ from the
# twice-per-link (0.75²ᵗ) and the never-applied (12) values; a model without edge updates
# compiles and lists its cell update as before.
#
# Not pinned: how the stage is generated (host phase or kernel), stage order relative to
# cell/site/model stages beyond the values above, edge updates reading endpoint cell
# variables (`a`, `b`) or other updates' new values, `@on_copy` writes of edge variables.
#
# On 405915dc (Mac): see the D-entry (every C/B/R/D target errors with the KeyError; the
# controls pass).

@testsetup module EdgeAfterMCSSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const EDGE_UPDATE_M = Potts.ModelingToolkitBase
const EDGE_UPDATE_S = Potts.Symbolics
const EDGE_UPDATE_SU = Potts.SymbolicUtils
const SII = Potts.SymbolicIndexingInterface
row(u) = (u.phase, u.scope, u.every)
function same(a, b)
    return length(a) == length(b) &&
        all(i -> row(a[i]) == row(b[i]) && isequal(a[i].eq, b[i].eq), eachindex(a, b))
end
lhsname(u) = SII.getname(EDGE_UPDATE_S.unwrap(u.eq.lhs))
function clear(f, words...)
    return try
        f()
        false
    catch err
        err isa Potts.PottsCompileError
    end
end
# ---------------------------------------------------------------------------------------
# Fixtures

# `update_rules_tests.jl`'s edge fixture, unchanged
@potts_model Edge begin
    @kinds medium blob
    @parameters T = 1.0
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36.0)^2
        contacts => 16.0
        edges(bond) => (distance - rest)^2
    end
    @after_mcs rest ~ Pre(rest) * 0.9
    @sweep Metropolis(; temperature = T)
end
# the behaviour fixture: rest relaxes toward the link's distance, age counts every 3 MCS,
# a cell counter in the same block
@potts_model Relax begin
    @kinds medium blob
    @parameters begin
        T = 1.0
        κ = 0.25
    end
    @variables begin
        rest(edge) = 12.0
        age(edge) = 0.0
        g(cell) = 0.0
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @after_mcs begin
        rest ~ Pre(rest) + κ * (distance - Pre(rest))
        g += 1
    end
    @before_mcs Every(3) age ~ Pre(age) + 1
    @sweep Metropolis(; temperature = T)
end
# the negative control: the same model without its edge updates
@potts_model Still begin
    @kinds medium blob
    @parameters begin
        T = 1.0
        κ = 0.25
    end
    @variables begin
        rest(edge) = 12.0
        age(edge) = 0.0
        g(cell) = 0.0
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => 1000.0 * (volume - 16.0)^2
        contacts => 1.0
        edges(bond) => 0.01 * (distance - rest)^2
    end
    @after_mcs g += 1
    @sweep Metropolis(; temperature = T)
end
# an edge update reading another relationship's edge variable
@potts_model Cross begin
    @kinds medium blob
    @parameters T = 1.0
    @variables begin
        rest(bond) = 12.0
        len(tether) = 18.0
    end
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((30, 12); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 16.0)^2
        edges(bond) => (distance - rest)^2
        edges(tether) => (distance - len)^2
    end
    @after_mcs rest ~ Pre(rest) + len
    @sweep Metropolis(; temperature = T)
end
# three 4×4 blobs at x 3:6, 11:14, 21:24 (rows 5:8): centroids 4.5, 12.5, 22.5, so
# d12 = 8, d23 = 10; links (1,2) and (2,3); (1,3) unlinked
function state()
    σ = zeros(Int32, 30, 12)
    σ[3:6, 5:8] .= 1
    σ[11:14, 5:8] .= 2
    σ[21:24, 5:8] .= 3
    return σ
end
function edge_update_op()
    return Any[
        ownership => state(), kind => [:blob, :blob, :blob], :bond => [
            (1, 2), (2, 3),
        ],
    ]
end
function problem(M; T = Float64, nmcs = 6)
    return PottsProblem(
        M(; name = :m), edge_update_op(), (
            0, nmcs,
        ); T
    )
end
const EDGE_UPDATE_D = Dict((1, 2) => 8.0, (2, 3) => 10.0)
edge_update_rest(d, t) = d + (12.0 - d) * 0.75^t
# payload `x` of the `bond` link between `a` and `b`, read at `a`'s end (`nothing`:
# unlinked)
function payload(cell, x, a, b)
    k = CorePotts.link_slot(CorePotts.link_store(cell, :bond), a, b)
    return k == 0 ? nothing : Float64(Array(getproperty(cell, Symbol(:link_, x)))[k, a])
end
# the payload entries of empty slots (`links[k, c] == 0`)
function empty_slots(cell, x)
    L = Array(CorePotts.link_store(cell, :bond).links)
    P = Array(getproperty(cell, Symbol(:link_, x)))
    return [P[k, c] for k in axes(L, 1), c in axes(L, 2) if L[k, c] == 0]
end
edge_update_links(cell) = Array(CorePotts.link_store(cell, :bond).links)
# ---------------------------------------------------------------------------------------
# D. On the device
const ON_DEVICE = PottsDevices.on_device()
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "edge after mcs C: mtkcompile of an edge-scope update; updates(csys) as \
    authored" setup = [EdgeAfterMCSSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # C. mtkcompile accepts edge updates; `updates` on the compiled form
    @testset "edge after mcs C: mtkcompile of an edge-scope update; updates(csys) as \
        authored" begin
        sys = Edge(; name = :pe)
        U = Potts.updates(sys)
        # as `update_rules_tests.jl` (control)
        @test length(U) == 1 && only(U).scope === :edge
        cs = mtkcompile(sys)
        @test cs isa Potts.CompiledPottsSystem
        @test same(Potts.updates(cs), U)
        u = only(Potts.updates(cs))
        @test u.phase === :after_mcs && u.scope === :edge && u.every == Potts.Every(1)
        @test lhsname(u) === :rest
        # both phases, a cadence and a cell statement in the same block
        r = Relax(; name = :pr)
        Ur = Potts.updates(r)
        @test [row(u) for u in Ur] == [
            (:after_mcs, :edge, Potts.Every(1)), (:after_mcs, :cell, Potts.Every(1)),
            (:before_mcs, :edge, Potts.Every(3)),
        ]
        @test same(Potts.updates(mtkcompile(r)), Ur)
        # the compiled system still has no MTK events (D-162)
        @test isempty(
            EDGE_UPDATE_M.discrete_events(Potts.inner(getfield(mtkcompile(sys), :sys)))
        )
    end
end

@testitem "edge after mcs B: edge updates run once per link per MCS" setup = [
    EdgeAfterMCSSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # B. Behaviour: once per link, each link's distance, both ends equal
    @testset "edge after mcs B: edge updates run once per link per MCS" begin
        prob = problem(Relax)
        @testset "$(nameof(typeof(alg)))" for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(prob, alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success && sol.t == 0:6
            # frozen: distances fixed
            @test all(u -> u.ownership == state(), sol.u)
            for (i, t) in enumerate(sol.t), ((a, b), d) in EDGE_UPDATE_D
                c = sol.u[i].cell
                @test payload(c, :rest, a, b) ≈ edge_update_rest(d, t) rtol = 1.0e-12
                @test payload(c, :rest, b, a) == payload(c, :rest, a, b)    # both ends
            end
            c = sol.u[end].cell
            # not applied twice per link (once per stored end), and applied at all
            for ((a, b), d) in EDGE_UPDATE_D
                @test !isapprox(
                    payload(c, :rest, a, b), d + (12.0 - d) * 0.75^12;
                    rtol = 1.0e-6
                )
                @test !isapprox(payload(c, :rest, a, b), 12.0; rtol = 1.0e-6)
            end
            # @before_mcs Every(3): before MCS 0 and 3, seen at t = 1 and 4
            ages = [payload(u.cell, :age, 1, 2) for u in sol.u]
            @test [sol.t[i + 1] for i in 1:(length(ages) - 1) if ages[i + 1] != ages[i]] ==
                [1, 4]
            @test ages[end] == 2.0 && payload(c, :age, 3, 2) == 2.0
            # the cell update in the same block
            @test c.g == fill(6.0, 3)
            # links unchanged; empty slots untouched; (1,3) still unlinked
            @test edge_update_links(c) == edge_update_links(prob.u0.cell)
            @test payload(c, :rest, 1, 3) === nothing
            @test all(iszero, empty_slots(c, :rest)) && all(iszero, empty_slots(c, :age))
        end
        # Float32 runs the same updates
        s32 = solve(problem(Relax; T = Float32), SequentialCPM())
        for ((a, b), d) in EDGE_UPDATE_D
            @test payload(s32.u[end].cell, :rest, a, b) ≈
                edge_update_rest(d, 6) rtol = 1.0e-5
        end
    end
end

@testitem "edge after mcs R: an edge update reading another relationship's edge \
    variable" setup = [EdgeAfterMCSSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # R. An edge update reads only its own relationship's edge variables
    @testset "edge after mcs R: an edge update reading another relationship's edge \
        variable" begin
        sys = Cross(; name = :px)
        # listed (control)
        @test only(Potts.updates(sys)).scope === :edge
        @test clear(() -> mtkcompile(sys), "len", "tether")
    end
end

@testitem "edge after mcs D: edge updates on the device (Float32) equal the CPU run" setup =
    [EdgeAfterMCSSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "edge after mcs D: edge updates on the device (Float32) equal the CPU \
        run" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            prob = problem(Relax; T = Float32)
            cpu = solve(prob, alg; saveat = 0:6)
            gpu = solve(prob, alg; backend, saveat = 0:6)
            @test Symbol(gpu.retcode) === :Success
            for i in eachindex(cpu.u), ((a, b), d) in EDGE_UPDATE_D
                @test payload(gpu.u[i].cell, :rest, a, b) ≈
                    payload(cpu.u[i].cell, :rest, a, b) rtol = 1.0e-5
                @test payload(gpu.u[i].cell, :age, a, b) ==
                    payload(cpu.u[i].cell, :age, a, b)
            end
            @test payload(gpu.u[end].cell, :rest, 2, 3) ≈
                edge_update_rest(10.0, 6) rtol = 1.0e-5
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "edge after mcs N: without edge updates the payloads stay; the configuration is \
    frozen" setup = [EdgeAfterMCSSetup] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # N. Negative controls (pass before this item)
    @testset "edge after mcs N: without edge updates the payloads stay; the configuration \
        is frozen" begin
        prob = problem(Still)
        @test [row(u) for u in Potts.updates(mtkcompile(Still(; name = :ps)))] ==
            [(:after_mcs, :cell, Potts.Every(1))]
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(prob, alg; saveat = 1)
            @test all(u -> u.ownership == state(), sol.u)
            c = sol.u[end].cell
            for (a, b) in keys(EDGE_UPDATE_D)
                @test payload(c, :rest, a, b) == 12.0 && payload(c, :rest, b, a) == 12.0
                @test payload(c, :age, a, b) == 0.0
                @test CorePotts.centroid_distance(Float64, c, prob.lattice, a, b) ==
                    EDGE_UPDATE_D[(a, b)]
            end
            @test payload(c, :rest, 1, 3) === nothing
            @test edge_update_links(c) == edge_update_links(prob.u0.cell)
            @test c.g == fill(6.0, 3)
        end
        # the oracle separates once-per-link from twice and from never
        @test !isapprox(edge_update_rest(8.0, 6), 8.0 + 4.0 * 0.75^12; rtol = 1.0e-6) &&
            edge_update_rest(8.0, 0) == 12.0
    end
end
