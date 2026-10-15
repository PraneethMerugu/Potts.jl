# `@convert` passes (R8, D-233), beyond the frozen acceptance files
# (lib/PottsModels/test/acceptance/p6_5b_*.jl, the behavioural contract): every stage of
# `CorePotts.ConvertPass` on the CPU and on the device (reset, entity, decide, allocate with
# the reference reset of a dead referent and the unlinking of the reused slot, transfer,
# writes, paint with the ownership hook, σ, finalize), which the GPU group must compile
# (device IR coverage, D-157); allocation order and deferral; the held dead root; the Int32
# moment-scratch bound; the compile-time refusals of the writes.

# Cytoplasm 1 (cluster 1) names the doomed cell 2 through `keep` and is bonded to it; the
# sweep empties cell 2 early (its energy is 50·volume²). At MCS 3 the pass converts cell 1's 4
# `sub` sites into a lamellipodium allocated in the lowest free slot, 2 (serial 3): the
# allocation first resets `keep` of cell 1, which names the dead slot 2, to 0, and drops the
# dead cell's bond; `act` (cleared on an ownership change) is reset at the converted sites.
@potts_model CVDevice begin
    @kinds medium cytoplasm lamellipodium doomed
    @parameters begin
        J[kind, kind] = [0 16 16 16; 16 2 0 16; 16 0 2 16; 16 16 16 2]
    end
    @variables begin
        sub(site) = 0.0
        act(site) = 0.0, [clear_on_ownership_change = true]
        V_target(cell) = ifelse(kind == cytoplasm, 36.0, 0.0)
        keep(cell)::CellRef
        births(model) = 0.0
        nconv(model) = 0.0
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cytoplasm, lamellipodium) => (volume - V_target)^2
        cells(doomed) => 50.0 * volume^2
        contacts => J[kind, kind′]
    end
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.5
        p = ifelse(mcs == 3, 1.0, 0.0)
        transfer(V_target, from => to, per_site = 1.0)
        births += created
        nconv += 1
    end
    @sweep Metropolis(; temperature = 0.5)
end

const CV_SUB = [CartesianIndex(8, j) for j in 6:9]          # interior sites: the sweep leaves them

function cv_device_problem()
    σ = zeros(Int32, 24, 24)
    σ[5:10, 5:10] .= 1
    σ[20, 20] = 2
    sub = zeros(24, 24)
    sub[CV_SUB] .= 1.0
    act = zeros(24, 24)
    act[5:10, 5:10] .= 1.0
    return PottsProblem(CVDevice(; name = :cv), [ownership => σ, kind => [:cytoplasm, :doomed], cluster => [1, 2],
            :keep => [2, 0], :sub => sub, :act => act, :bond => [(1, 2)]], (0, 4); T = Float32, capacity = 4)
end
# after the run: the lamellipodium in slot 2 (serial 3, cluster 1), `keep` of cell 1 reset,
# one allocation, 4 conversions, the 4 units of `V_target` moved to the new cell; the reused
# slot unlinked (no row names 2, its own row empty); `act` cleared at the converted sites only
function cv_device_summary(u)
    v = Array(u.cell.volume)
    L = Array(getfield(u.cell, CorePotts.adjacency_name(:bond)))
    act = Array(u.site.act)
    return (; alive = findall(>(0), v), kind2 = Array(u.cell.kind)[2], birth2 = Array(u.cell.birth)[2],
        cluster2 = Array(u.cell.cluster)[2], keep1 = Array(u.cell.keep)[1], births = Array(u.model.births)[1],
        nconv = Array(u.model.nconv)[1], vt = Array(u.cell.V_target)[1:2], unlinked = !any(==(2), L) && all(iszero, L[:, 2]),
        cleared = all(iszero, act[CV_SUB]), kept = act[7, 7] == 1)
end
const CV_EXPECTED = (; alive = [1, 2], kind2 = 2, birth2 = 3, cluster2 = 1, keep1 = 0, births = 1.0f0, nconv = 4.0f0,
    vt = Float32[32, 4], unlinked = true, cleared = true, kept = true)

@testset "@convert: every stage on the CPU (reference reset, unlinking, ownership hook)" begin
    prob = cv_device_problem()
    @test getfield(prob.u0.cell, CorePotts.adjacency_name(:bond))[:, 2] != zeros(Int32, 2)   # control: linked
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(prob, alg; saveat = 1)
        @test cv_device_summary(sol.u[end]) == CV_EXPECTED
        @test Array(sol.u[3].cell.keep)[1] == 2                        # before the allocation: still the dead slot
    end
end

# D-253: the lowest converted site (`#cv_first`, which decides `created`) and the flags are
# `site_index_type`, Int64 above 2³¹ − 1 sites. Forced at construction on 24²: the same run
# exactly, one `created` among the 4 conversions; unforced, Int32.
@testset "@convert: `created` at the Int64 site width (D-253)" begin
    wide(f) = (CorePotts._FORCE_WIDE_SITES[] = true; try f() finally CorePotts._FORCE_WIDE_SITES[] = false end)
    prob = wide(cv_device_problem)
    @test eltype(getfield(prob.u0.cell, CorePotts._CV_FIRST)) === Int64
    @test eltype(getfield(prob.u0.model, CorePotts.CONVERT_FLAGS)) === Int64
    @test eltype(getfield(cv_device_problem().u0.cell, CorePotts._CV_FIRST)) === Int32
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(prob, alg; saveat = 1)
        ref = solve(cv_device_problem(), alg; saveat = 1)                    # the Int32 run
        @test cv_device_summary(sol.u[end]) == CV_EXPECTED                  # births == 1
        @test all(i -> sol.u[i].σ == ref.u[i].σ, eachindex(sol.u))
    end
end

@testset "@convert passes on the device (PottsDevices)" begin
    if isdefined(Main, :PottsDevices) && PottsDevices.on_device()
        backend = PottsDevices.device_backend()
        prob = cv_device_problem()
        cpu = cv_device_summary(solve(prob, CheckerboardCPM()).u[end])
        @test cpu == CV_EXPECTED
        sol = solve(prob, CheckerboardCPM(); backend)
        @test Symbol(sol.retcode) === :Success
        @test cv_device_summary(sol.u[end]) == cpu
        # D-253: the Int64 width on the device, or its refusal without 64-bit atomics (Metal)
        wprob = (CorePotts._FORCE_WIDE_SITES[] = true; try cv_device_problem() finally CorePotts._FORCE_WIDE_SITES[] = false end)
        if CorePotts._atomic64(backend)
            @test cv_device_summary(solve(wprob, CheckerboardCPM(); backend).u[end]) == cpu
        else
            @test_throws r"@convert pass.*Int64 atomics.*D-253" init(wprob, CheckerboardCPM(); backend)
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

# Several entities allocating in one pass: three cytoplasm clusters (cells 1, 2, 3), the sweep
# frozen, every `sub` site converting at MCS 1. Entities allocate in slot order, each the
# lowest free slot: with capacity 5 (free slots 4, 5) cells 1 and 2 get 4 and 5, cell 3's
# allocation is deferred and counted (it converts nothing that MCS; later passes convert
# nothing, p = 0).
@potts_model CVMany begin
    @kinds medium cytoplasm lamellipodium
    @parameters mobile = 0.0
    @variables begin
        sub(site) = 0.0
        births(model) = 0.0
    end
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @constraint mobile > 0.5
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.5
        p = ifelse(mcs == 1, 1.0, 0.0)
        births += created
    end
    @sweep Metropolis(; temperature = 1.0)
end
function cv_many_problem(model = CVMany; capacity = 5, σ3 = 3)
    σ = zeros(Int32, 24, 24)
    σ[2:5, 2:5] .= 1
    σ[2:5, 10:13] .= 2
    σ[2:5, 18:21] .= σ3
    sub = zeros(24, 24)
    sub[3, [3, 11, 19]] .= 1.0
    return PottsProblem(model(; name = :many), [ownership => σ, kind => fill(:cytoplasm, maximum(σ)), cluster => [1, 2, 3],
            :sub => sub], (0, 2); capacity)
end

@testset "@convert: several entities allocate lowest-first; the rest are deferred and reported" begin
    prob = cv_many_problem()
    sol = @test_logs (:warn, r"1 allocation\(s\) deferred") match_mode = :any solve(prob, SequentialCPM())
    u = sol.u[end]
    @test u.cell.kind[4:5] == [2, 2] && u.cell.cluster[4:5] == [1, 2]       # entity 1 → slot 4, entity 2 → slot 5
    @test u.σ[3, 3] == 4 && u.σ[3, 11] == 5 && u.σ[3, 19] == 3            # entity 3: deferred, nothing converted
    @test u.model.births[1] == 2
    # control: with room for all three, nothing is deferred (and nothing is reported)
    @test_logs solve(cv_many_problem(; capacity = 6), SequentialCPM())
    @test solve(cv_many_problem(; capacity = 6), SequentialCPM()).u[end].σ[3, 19] == 6
end

@testset "@convert: a dead root that still names its cluster is not a free slot" begin
    # cell 2 is a dead slot that names the cluster of the live cell 3 (its root died): the
    # allocation for entity 1 skips slot 2 (held) and takes slot 4
    prob = cv_many_problem(; capacity = 4, σ3 = 3)
    u = deepcopy(prob.u0)
    u.σ[u.σ .== 2] .= 0
    u.cell.volume[2] = 0
    u.cell.cluster[2:3] .= 2
    p = remake(prob; u0 = u)
    sol = solve(p, SequentialCPM())
    v = sol.u[end]
    @test v.cell.volume[2] == 0 && v.σ[3, 3] == 4 && v.cell.kind[4] == 2 && v.cell.cluster[4] == 1
    # control: when no live cell names cluster 2, slot 2 is free and is taken first
    u2 = deepcopy(u)
    u2.cell.cluster[3] = 3
    @test solve(remake(prob; u0 = u2), SequentialCPM()).u[end].σ[3, 3] == 2
end

# The Int32 moment scratch (S1 of the P6.5b review): an entity whose cells' second moments
# exceed the bound converts nothing and is counted (the bound lowered here, as the device
# lifecycle's tests lower it)
@potts_model CVLarge begin
    @kinds medium cytoplasm lamellipodium
    @parameters mobile = 0.0
    @variables sub(site) = 0.0
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => (volume - 16.0)^2
    @constraint mobile > 0.5
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.5
        p = ifelse(mcs == 1, 1.0, 0.0)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "@convert: cells too large for the Int32 moment scratch are skipped and reported" begin
    old = CorePotts._SCRATCH_LIMIT[]
    try
        CorePotts._SCRATCH_LIMIT[] = 8                  # cell 1 (4×4): m2 = 20 per axis > 8 ÷ 4
        prob = cv_many_problem(CVLarge)
        sol = @test_logs (:warn, r"entity pass\(es\) skipped") match_mode = :any solve(prob, SequentialCPM())
        @test sol.u[end].σ == prob.u0.σ
    finally
        CorePotts._SCRATCH_LIMIT[] = old
    end
    prob = cv_many_problem(CVLarge; capacity = 6)      # control: the default bound
    @test solve(prob, SequentialCPM()).u[end].σ[3, 3] == 4
end

# The writes of a pass: at a cell named by a reference, and reading nothing the pass writes
cv_write_src(write) = quote
    @kinds medium cytoplasm lamellipodium
    @variables begin
        sub(site) = 0.0
        V_target(cell) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - V_target)^2
    @convert protrusion clusters(cytoplasm) begin
        to = sibling(lamellipodium)
        at = sub > 0.5
        $write
    end
    @sweep Metropolis(; temperature = 1.0)
end
function cv_write_error(write)
    try
        mod = Module()
        Core.eval(mod, :(using Potts))
        Core.eval(mod, Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :cv), :CVW, cv_write_src(write)))
        Base.invokelatest(() -> mtkcompile(Base.invokelatest(getfield(mod, :CVW); name = :w)))
        return nothing
    catch e
        return e isa LoadError ? e.error : e
    end
end

@testset "@convert: writes at a reference, reading nothing the pass writes" begin
    @test cv_write_error(:(V_target[to] += 1.0)) === nothing                 # controls
    @test cv_write_error(:(n += V_target[to])) === nothing
    e = cv_write_error(:(V_target[owner] += 1.0))
    @test e isa ArgumentError && occursin("named by a reference", sprint(showerror, e))
    for w in (:(V_target[to] += 0.1 * V_target[to]), :(n += n + 1.0), :(transfer(V_target, from => to, per_site = V_target[to])))
        e = cv_write_error(w)
        @test e isa ArgumentError && occursin("which the pass itself", sprint(showerror, e))
    end
end
