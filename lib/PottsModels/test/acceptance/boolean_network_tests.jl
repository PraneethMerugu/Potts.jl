# Boolean networks are MTK discrete-time components
# (clocked, `Shift`), extending D-038 (D-065 Q9). A per-cell 3-node network must match a
# hand-written truth table exactly, under both algorithms (and on Metal), with zero warm
# allocations.

@testsetup module BooleanNetworkSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, Sample, Hold, @variables, @parameters
const NETWORK_K = 12
# ticks compared against the reference

# ---------------------------------------------------------------------------------------
# The networks: plain MTK systems (no Potts-side representation)
"""The 3-node network. `ordered`: C reads A's new value; `wrong`: `&` swapped for `|` in A's
rule (negative control); `clock`: the ShiftIndex clock (default one tick per MCS)."""
function boolean_network(; ordered = false, wrong = false, clock = nothing)
    t = Potts.t
    k = clock === nothing ? ShiftIndex(t, 0) : ShiftIndex(clock)
    @variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false
    @parameters wnt::Bool = false
    ruleA = wrong ? (wnt | (B(k - 1) | !C(k - 1))) : (wnt | (B(k - 1) & !C(k - 1)))
    ruleC = ordered ? !(A(k) | B(k - 1)) : !(A(k - 1) | B(k - 1))
    return System([A(k) ~ ruleA, B(k) ~ A(k - 1), C(k) ~ ruleC], t; name = :grn)
end
# Hand-written references: (wnt, A, B, C) at a tick → (A, B, C) after it.
# Synchronous: A′ = wnt ∨ (B ∧ ¬C), B′ = A, C′ = ¬(A ∨ B).
const TABLE = Dict{NTuple{4, Int}, NTuple{3, Int}}(
    (0, 0, 0, 0) => (0, 0, 1), (0, 0, 0, 1) => (0, 0, 1), (0, 0, 1, 0) => (1, 0, 0), (0, 0, 1, 1) => (0, 0, 0),
    (0, 1, 0, 0) => (0, 1, 0), (0, 1, 0, 1) => (0, 1, 0), (0, 1, 1, 0) => (1, 1, 0), (0, 1, 1, 1) => (0, 1, 0),
    (1, 0, 0, 0) => (1, 0, 1), (1, 0, 0, 1) => (1, 0, 1), (1, 0, 1, 0) => (1, 0, 0), (1, 0, 1, 1) => (1, 0, 0),
    (1, 1, 0, 0) => (1, 1, 0), (1, 1, 0, 1) => (1, 1, 0), (1, 1, 1, 0) => (1, 1, 0), (1, 1, 1, 1) => (1, 1, 0)
)
# Ordered: as above, but C′ = ¬(A′ ∨ B) (C reads the new A).
const TABLE_ORDERED = Dict{NTuple{4, Int}, NTuple{3, Int}}(
    (0, 0, 0, 0) => (0, 0, 1), (0, 0, 0, 1) => (0, 0, 1), (0, 0, 1, 0) => (1, 0, 0), (0, 0, 1, 1) => (0, 0, 0),
    (0, 1, 0, 0) => (0, 1, 1), (0, 1, 0, 1) => (0, 1, 1), (0, 1, 1, 0) => (1, 1, 0), (0, 1, 1, 1) => (0, 1, 0),
    (1, 0, 0, 0) => (1, 0, 0), (1, 0, 0, 1) => (1, 0, 0), (1, 0, 1, 0) => (1, 0, 0), (1, 0, 1, 1) => (1, 0, 0),
    (1, 1, 0, 0) => (1, 1, 0), (1, 1, 0, 1) => (1, 1, 0), (1, 1, 1, 0) => (1, 1, 0), (1, 1, 1, 1) => (1, 1, 0)
)
# every (wnt, A, B, C), in a fixed order: row r is host cell r
const ROWS = [(w, a, b, c) for w in 0:1 for a in 0:1 for b in 0:1 for c in 0:1]
"""Reference trajectory of one start row over `n` ticks: element m + 1 is the state after m ticks."""
function reference(table, row, n)
    w = row[1]
    traj = NTuple{3, Int}[(row[2], row[3], row[4])]
    for _ in 1:n
        push!(traj, table[(w, traj[end]...)])
    end
    return traj
end
# ---------------------------------------------------------------------------------------
# The model: 16 host cells (one per row), 3 cells of another kind, one zero-volume host slot

# `@potts_model` resolves a component's system in module scope when the constructor runs, so
# the system under test is passed through a global slot
const SYSTEM = Ref{Any}(nothing)
function model(grn; name = :bn)
    SYSTEM[] = grn
    @potts_model BooleanCells begin
        @kinds medium host other
        @parameters begin
            λ = 1.0
            T = 1.0e-6
        end
        @variables input(cell) = 0.0
        @components cells(host) grn = SYSTEM[]
        @equations grn.wnt ~ input > 0.5
        @lattice Lattice((30, 24))
        @energy cells => λ * (volume - 16.0)^2
        @sweep Metropolis(; temperature = T)
    end
    return BooleanCells(; name)
end
const HOSTS = 1:16
const OTHERS = 17:19
# kind `other`: the component is not instantiated there
const DEAD = 20
# a host slot with no sites (volume 0 from the start)
const LAST = 21
# a live host cell after the empty slot (labels stay contiguous in kind)
"""Labels: 4×4 cells on a 6-site grid; id 20 owns no site."""
function network_state()
    σ = zeros(Int32, 30, 24)
    ids = [collect(1:19); LAST]
    n = 0
    for i in 1:6:25, j in 1:6:19
        n += 1
        n <= length(ids) || break
        σ[(i + 1):(i + 4), (j + 1):(j + 4)] .= ids[n]
    end
    return σ
end
function problem(grn; tspan = (0, NETWORK_K), T = Float64)
    # hosts 1–16 start at ROWS; others/dead/last start at (0,0,1,0) or (0,0,0,0) rows,
    # which change under a tick, so a skipped tick is visible
    rows = [ROWS; fill((0, 0, 1, 0), 3); (0, 0, 1, 0); (0, 0, 0, 0)]
    col(i) = [r[i] == 1 for r in rows]
    kinds = [fill(:host, 16); fill(:other, 3); :host; :host]
    op = [
        ownership => network_state(), kind => kinds, :input => Float64.(col(1)),
        Symbol("grn₊A") => col(2), Symbol("grn₊B") => col(3), Symbol("grn₊C") => col(4),
    ]
    return PottsProblem(model(grn), op, tspan; T), rows
end
function network_bit(x)
    if x == 1
        return 1
    elseif x == 0
        return 0
    else
        return -1
    end
end
# exact 0/1, anything else is a mismatch
"""The (A, B, C) trajectory of cell `c` in a solution (host arrays, CPU or device)."""
function network_trajectory(sol, c)
    return [
        (
            network_bit(Array(getproperty(u.cell, Symbol("grn₊A")))[c]),
            network_bit(Array(getproperty(u.cell, Symbol("grn₊B")))[c]),
            network_bit(Array(getproperty(u.cell, Symbol("grn₊C")))[c]),
        ) for u in sol.u
    ]
end
"""Number of host cells (1–16 and the last) whose trajectory differs from `table`."""
function mismatches(sol, rows, table; every = 1)
    bad = 0
    for c in [collect(HOSTS); LAST]
        ref = reference(table, rows[c], NETWORK_K)
        got = network_trajectory(sol, c)
        want = [ref[m ÷ every + 1] for m in 0:NETWORK_K]
        got == want || (bad += 1)
    end
    return bad
end
function warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false, save_everystep = false)
    step!(integ)
    step!(integ)
    m = typemax(Int)
    for _ in 1:5
        m = min(m, @allocated step!(integ))
    end
    return m
end
const ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "boolean network: a per-cell Boolean network matches its truth table" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    @testset "boolean network: a per-cell Boolean network matches its truth table" begin
        for T in (Float64, Float32)
            prob, rows = problem(boolean_network(); T)
            for alg in ALGS
                sol = solve(prob, alg; saveat = 0:NETWORK_K)
                @test length(sol.u) == NETWORK_K + 1
                @test mismatches(sol, rows, TABLE) == 0
                u = sol.u[end]
                @test all(>(0), Array(u.cell.volume)[[collect(HOSTS); collect(OTHERS); LAST]])
            end
        end
    end
end

@testitem "boolean network: on the device" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: on the device" begin
        if PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            prob, rows = problem(boolean_network(); T = Float32)
            sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 0:NETWORK_K)
            @test mismatches(sol, rows, TABLE) == 0
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "boolean network: zero warm allocations" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: zero warm allocations" begin
        for T in (Float64, Float32), alg in ALGS
            prob, _ = problem(boolean_network(); tspan = (0, 100), T)
            @test warm_allocs(prob, alg) == 0
        end
    end
end

@testitem "boolean network: the clock sets the cadence" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: the clock sets the cadence" begin
        # Clock(2) at mcs_duration = 1 follows MTK clock time: ticks at t = 2, 4, … (the end of
        # MCS 1, 3, …); the clock's t = 0 tick is the initial state. The state saved at t has had
        # t ÷ 2 ticks. (This is one MCS later than `Every(2)` on updates and rules, which fire at
        # MCS 0, 2, …: the clock belongs to the MTK system, not to a Potts cadence.)
        prob, rows = problem(boolean_network(; clock = Clock(2.0)))
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:NETWORK_K)
            @test mismatches(sol, rows, TABLE; every = 2) == 0
            @test mismatches(sol, rows, TABLE) > 0                 # not every MCS
        end
        # a period that is not a whole number of MCS
        @test_throws Potts.PottsCompileError mtkcompile(model(boolean_network(; clock = Clock(1.5))))
    end
end

@testitem "boolean network: update order comes from the MTK equations" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: update order comes from the MTK equations" begin
        # the two references differ on some rows, so the check separates the semantics
        @test any(r -> TABLE[r] != TABLE_ORDERED[r], ROWS)
        prob, rows = problem(boolean_network(; ordered = true))
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:NETWORK_K)
            @test mismatches(sol, rows, TABLE_ORDERED) == 0
            @test mismatches(sol, rows, TABLE) > 0
        end
    end
end

@testitem "boolean network: kinds and empty slots do not tick" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: kinds and empty slots do not tick" begin
        prob, rows = problem(boolean_network())
        for alg in ALGS
            sol = solve(prob, alg; saveat = 0:NETWORK_K)
            @test Array(sol.u[1].cell.volume)[DEAD] == 0
            for c in [collect(OTHERS); DEAD]
                start = (rows[c][2], rows[c][3], rows[c][4])
                @test all(==(start), network_trajectory(sol, c))
            end
        end
    end
end

@testitem "boolean network: negative control (a wrong rule is caught)" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: negative control (a wrong rule is caught)" begin
        prob, rows = problem(boolean_network(; wrong = true))
        sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = 0:NETWORK_K)
        @test mismatches(sol, rows, TABLE) > 0
    end
end

@testitem "boolean network: unsupported discrete components are rejected at mtkcompile(PottsSystem)" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: unsupported discrete components are rejected at mtkcompile(PottsSystem)" begin
        t = Potts.t
        k = ShiftIndex(t, 0)
        @variables A(t)::Bool = false B(t)::Bool = false x(t) = 1.0 w(t) = 0.5
        @parameters wnt::Bool = false            # every system uses `wnt`, so the model's coupling is valid
        Dt = Potts.D
        # positive control: the valid network compiles (the rejections below fail for their own reason)
        @test mtkcompile(model(boolean_network())) isa Potts.CompiledPottsSystem
        reject(sys) = @test_throws Potts.PottsCompileError mtkcompile(model(sys; name = :rejected))
        # hybrid: a continuous equation in a discrete component
        reject(System([Dt(x) ~ -x, A(k) ~ wnt & !A(k - 1)], t; name = :grn))
        # Sample/Hold (MTKBase would compile these with the wrong semantics)
        kc = ShiftIndex(Clock(1.0))
        reject(System([Dt(x) ~ -x + Hold(w), w(kc) ~ ifelse(wnt, Sample(Clock(1.0))(x), 0.0)], t; name = :grn))
        # implicit: w(k) on both sides leaves an algebraic equation
        reject(System([w(k) ~ 0.5 * w(k)^2 + 0.1 * w(k - 1) + ifelse(wnt, 0.1, 0.0)], t; name = :grn))
        # two clocks in one component
        k1, k2 = ShiftIndex(Clock(1.0)), ShiftIndex(Clock(2.0))
        reject(System([A(k1) ~ wnt & !A(k1 - 1), B(k2) ~ !B(k2 - 1)], t; name = :grn))
        # a Bool node given a Real rule
        reject(System([A(k) ~ ifelse(wnt & B(k - 1), 1.0, 0.0), B(k) ~ !B(k - 1)], t; name = :grn))
    end
end

@testitem "boolean network: Jafari-style node (smoke)" setup = [BooleanNetworkSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "boolean network: Jafari-style node (smoke)" begin
        t = Potts.t
        k = ShiftIndex(t, 0)
        @variables β(t)::Bool = false Akt(t)::Bool = false PI3K(t)::Bool = true
        @parameters Wnt::Bool = false cad::Bool = false APC::Bool = false
        SYSTEM[] = System([β(k) ~ Wnt | (Akt(k - 1) & !cad & !APC), Akt(k) ~ PI3K(k - 1), PI3K(k) ~ PI3K(k - 1)], t; name = :jaf)
        @potts_model NetworkJafari begin
            @kinds medium tumour
            @parameters begin
                λ = 1.0
                T = 4.0
            end
            @components cells(tumour) jaf = SYSTEM[]
            @equations jaf.cad ~ volume > 16.0
            @lattice Lattice((20, 20))
            @energy cells => λ * (volume - 16.0)^2
            @sweep Metropolis(; temperature = T)
        end
        σ = zeros(Int32, 20, 20)
        σ[3:6, 3:6] .= 1
        σ[12:15, 12:15] .= 2
        prob = PottsProblem(NetworkJafari(; name = :jafari), [ownership => σ, kind => [:tumour, :tumour]], (0, 20))
        for alg in ALGS
            u = solve(prob, alg).u[end]
            for n in (:β, :Akt, :PI3K)
                @test all(x -> x == 0 || x == 1, Array(getproperty(u.cell, Symbol("jaf₊", n))))
            end
        end
    end
end
