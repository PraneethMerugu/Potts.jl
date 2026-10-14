# `@convert` passes on the device (R8, D-233): every stage of `CorePotts.ConvertPass`
# (reset, entity, decide, allocate with the reference reset of a dead referent, transfer,
# writes, paint, σ, finalize) launched on the device, which the GPU group must compile
# (device IR coverage, D-157). Compared with the CPU Float32 run. The frozen acceptance
# files (lib/PottsModels/test/acceptance/p6_5b_*.jl) hold the behavioural contract.

# Cytoplasm 1 (cluster 1) names the doomed cell 2 through `keep`; the sweep empties cell 2
# early (its energy is 50·volume²). At MCS 3 the pass converts cell 1's 4 `sub` sites into a
# lamellipodium allocated in the lowest free slot, 2 (serial 3): the allocation first resets
# `keep` of cell 1, which names the dead slot 2, to 0.
@potts_model CVDevice begin
    @kinds medium cytoplasm lamellipodium doomed
    @parameters begin
        J[kind, kind] = [0 16 16 16; 16 2 0 16; 16 0 2 16; 16 16 16 2]
    end
    @variables begin
        sub(site) = 0.0
        V_target(cell) = ifelse(kind == cytoplasm, 36.0, 0.0)
        keep(cell)::CellRef
        births(model) = 0.0
        nconv(model) = 0.0
    end
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

function cv_device_problem()
    σ = zeros(Int32, 24, 24)
    σ[5:10, 5:10] .= 1
    σ[20, 20] = 2
    sub = zeros(24, 24)
    sub[8, 6:9] .= 1.0                     # interior sites: the sweep leaves them
    return PottsProblem(CVDevice(; name = :cv), [ownership => σ, kind => [:cytoplasm, :doomed], cluster => [1, 2],
            :keep => [2, 0], :sub => sub], (0, 4); T = Float32, capacity = 4)
end
# after the run: the lamellipodium in slot 2 (serial 3, cluster 1), `keep` of cell 1 reset,
# one allocation, 4 conversions, the 4 units of `V_target` moved to the new cell
function cv_device_summary(u)
    v = Array(u.cell.volume)
    return (; alive = findall(>(0), v), kind2 = Array(u.cell.kind)[2], birth2 = Array(u.cell.birth)[2],
        cluster2 = Array(u.cell.cluster)[2], keep1 = Array(u.cell.keep)[1], births = Array(u.model.births)[1],
        nconv = Array(u.model.nconv)[1], vt = Array(u.cell.V_target)[1:2])
end

@testset "@convert passes on the device (PottsDevices)" begin
    if isdefined(Main, :PottsDevices) && PottsDevices.on_device()
        backend = PottsDevices.device_backend()
        prob = cv_device_problem()
        cpu = cv_device_summary(solve(prob, CheckerboardCPM()).u[end])
        @test cpu == (; alive = [1, 2], kind2 = 2, birth2 = 3, cluster2 = 1, keep1 = 0, births = 1.0f0,
            nconv = 4.0f0, vt = Float32[32, 4])
        sol = solve(prob, CheckerboardCPM(); backend)
        @test Symbol(sol.retcode) === :Success
        @test cv_device_summary(sol.u[end]) == cpu
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end
