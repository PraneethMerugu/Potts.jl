# Fields and cell sums on device backends (POTTS_GPU = metal | rocm).

# A coupled model's field kernels compile in the field phase's pending task
# (`rt.pending`): the step and the mask launches, whose bodies clamp the sites they mark
# (the clamp at the step start fused into the mask launch on a device: no separate clamp
# launch), and the slot-1 copy. Once the task is done, the first MCS adds no LatticeFields
# kernel to AMDGPU's kernel cache (counted), and the device run equals the host run.
@testitem "field kernels compile in the pending task, the clamp fused into the masks \
    (ROCm)" setup = [
    GpuSetup, FieldsSetup,
] tags = [:potts, :gpu, :device] begin
    if PottsDevices.device_name() == "rocm"
        @testset "field kernels compile in the pending task, the clamp fused into the \
            masks (ROCm)" begin
            AM = PottsDevices.device_package()
            function lfkernels()
                return Set(
                    s
                        for s in (
                            string(typeof(k))
                            for k in collect(values(AM.Compiler._kernel_instances))
                        )
                        if occursin("LatticeFields.Problems", s) ||
                        occursin("LatticeFields.Compile", s)
                )
            end
            backend = PottsDevices.device_backend()
            σ = zeros(Int32, 12, 12)
            σ[5:7, 5:7] .= 1
            prob = PottsProblem(
                FdMovingMask(; name = :m), [ownership => σ, kind => [:A]], (0, 4); backend,
                seed = 5,
                field_solver = ExplicitEuler(substeps = 3)
            )
            # from a host checkpoint: a fresh state's at-init clamp would await the task
            # inside `init`
            ck = checkpoint(init(prob, CheckerboardCPM()))
            integ = init(prob, CheckerboardCPM(); backend, checkpoint = ck)
            t = CorePotts._runtime(integ.ctx.__fields1).pending
            @test t isa Task
            wait(t)
            before = lfkernels()
            # the masks, clamp fused, compiled by the task
            @test any(s -> occursin("_MaskClamp", s), before)
            # no separate clamp launch
            @test isempty(CorePotts._runtime(integ.ctx.__fields1).stepclamps)
            step!(integ)
            PottsDevices.device_sync()
            # the first MCS compiled none
            @test isempty(setdiff(lfkernels(), before))
            host = init(prob, CheckerboardCPM(); checkpoint = ck)
            step!(host)
            # and equals the host run
            @test Array(current_state(integ).site.c) == current_state(host).site.c
        end
    end
end

# A Float32 problem with a Float64 field computed in
# Float64 on ROCm equals the host run to 1e-12; its kernels hold `double` and are registered
# in LatticeFields' Exec registry, which the full scan below skips (and, with the registry
# entries removed, flags: the scan's own negative control). Base f5641ce1: no registry, the
# model fails to build (`lattice_storage = Float64`).
@testitem "a declared Float64 field group on ROCm (registered for the Float64 scan)" setup =
    [
    GpuSetup, FieldsSetup,
] tags = [:potts, :gpu, :device] begin
    if PottsDevices.device_name() == "rocm"
        @testset "a declared Float64 field group on ROCm (registered for the Float64 \
            scan)" begin
            backend = PottsDevices.device_backend()
            σ = zeros(Int32, 12, 10)
            σ[3:5, 3:5] .= 1
            c0 = rand(StableRNG(14), 12, 10)
            before = length(Potts.LatticeFields.Exec.FLOAT64_KERNELS)
            for alg in (
                    ExplicitEuler(substeps = 8, compute_type = Float64),
                    BackwardEuler(compute_type = Float64, solver_type = Float64),
                )
                prob = PottsProblem(
                    FwWide(; name = :w), [ownership => σ, kind => [:A], :c => c0], (0, 2);
                    T = Float32, backend, seed = 3, field_solver = alg
                )
                dev = init(prob, CheckerboardCPM(); backend)
                host = init(
                    PottsProblem(
                        FwWide(; name = :w), [ownership => σ, kind => [:A], :c => c0], (
                            0, 2,
                        );
                        T = Float32, seed = 3, field_solver = alg
                    ), CheckerboardCPM()
                )
                step!(dev)
                step!(host)
                PottsDevices.device_sync()
                @test eltype(current_state(dev).site.c) == Float64
                @test maximum(
                    abs, Array(current_state(dev).site.c) .-
                        current_state(host).site.c
                ) < 1.0e-12
            end
            # registered
            @test length(Potts.LatticeFields.Exec.FLOAT64_KERNELS) > before
        end
    end
end

# An implicit runtime's launches (the operator program, the residuals, the shift,
# update, status and Newton-check bodies, the solver's rebuild, lift and solve plans)
# compile in the field phase's pending task: once it is done, the first MCS adds no
# LatticeFields kernel to AMDGPU's kernel cache, and the device run equals the host run to
# the Newton and solver tolerances. Base f5641ce1: the task compiled the explicit step only
# (the first MCS compiled the implicit kernels: the set grows).
@testitem "the implicit kernels compile in the pending task (ROCm)" setup = [
    GpuSetup, PortsSetup,
] tags = [:potts, :gpu, :device] begin
    if PottsDevices.device_name() == "rocm"
        @testset "the implicit kernels compile in the pending task (ROCm)" begin
            AM = PottsDevices.device_package()
            function lfkernels()
                return Set(
                    s
                        for s in (
                            string(typeof(k))
                            for k in collect(values(AM.Compiler._kernel_instances))
                        )
                        if occursin("LatticeFields.", s)
                )
            end
            backend = PottsDevices.device_backend()
            for fs in (
                    BackwardEuler(lower_bound = 0.0), CrankNicolson(lower_bound = 0.0),
                    BDF2(lower_bound = 0.0), QuasiSteady(),
                )
                prob = PottsProblem(
                    MERKS, [ownership => merks_state(), kind => [1, 1]],
                    (0, 4); T = Float32, seed = 5,
                    field_solver = fs
                )
                ck = checkpoint(init(prob, CheckerboardCPM(; proposal = Moore(1))))
                integ = init(
                    prob, CheckerboardCPM(; proposal = Moore(1)); backend,
                    checkpoint = ck
                )
                t = CorePotts._runtime(getfield(integ.ctx, :__fields1)).pending
                @test t isa Task
                wait(t)
                before = lfkernels()
                step!(integ)
                step!(integ)
                PottsDevices.device_sync()
                new = setdiff(lfkernels(), before)
                isempty(new) ||
                    @info "kernels the first MCS compiled \
                        ($(nameof(typeof(fs))))" new = first.(
                    collect(new), 300
                )
                @test isempty(new)
                host = init(prob, CheckerboardCPM(; proposal = Moore(1)); checkpoint = ck)
                step!(host)
                step!(host)
                cd, ch = Array(current_state(integ).site.c), current_state(host).site.c
                @test maximum(abs, cd .- ch) <= 1.0e-4 * maximum(abs, ch)
            end
        end
    end
end

# A `Coarse(4)` field of a model on ROCm (Float32): the field phase on the coarse arrays,
# the CPM's site reads through the node of each block (`integral(c) / volume`), against the
# host. Base 392dd404: `lattice_level` is not an option of `variable` (FcMix does not
# build).
@testitem "a Coarse(4) field of a model on ROCm equals the host (Float32)" setup = [
    GpuSetup, FieldsCoarseSetup,
] tags = [:potts, :gpu, :device] begin
    if PottsDevices.device_name() == "rocm"
        @testset "a Coarse(4) field of a model on ROCm equals the host (Float32)" begin
            backend = PottsDevices.device_backend()
            for fs in (ExplicitEuler(), BackwardEuler())
                function mk()
                    return PottsProblem(
                        FcMix(; name = :f), fc_op(), (0, 3);
                        T = Float32, seed = 2, field_solver = fs
                    )
                end
                dev = init(mk(), CheckerboardCPM(); backend)
                host = init(mk(), CheckerboardCPM())
                foreach(_ -> (step!(dev); step!(host)), 1:3)
                PottsDevices.device_sync()
                cd, ch = Array(current_state(dev).site.c), current_state(host).site.c
                @test size(cd) == (4, 3) &&
                    maximum(abs, cd .- ch) <= 1.0e-5 * maximum(abs, ch)
                ad, ah = Array(current_state(dev).cell.avg), current_state(host).cell.avg
                @test maximum(abs, ad .- ah) <= 1.0e-5 * maximum(abs, ah)
            end
        end
    end
end

# On a device `integ.stats` reads the field groups' status words first, so after
# `step!` (no save) `integ.stats.fields` counts the solves so far, as B's `field_stats`
# does. Before the fix (cb20be97): `solves = 0` until a save.
@testitem "integ.stats.fields counts the device solves after step! (ROCm)" setup = [
    GpuSetup, FieldsCoarseSetup,
] tags = [:potts, :gpu, :device] begin
    if PottsDevices.device_name() == "rocm"
        @testset "integ.stats.fields counts the device solves after step! (ROCm)" begin
            dev = init(
                PottsProblem(
                    FcMix(; name = :f), fc_op(), (0, 3); T = Float32,
                    seed = 2, field_solver = BackwardEuler()
                ),
                CheckerboardCPM(); backend = PottsDevices.device_backend(),
                save_start = false
            )
            foreach(_ -> step!(dev), 1:2)
            s1 = dev.stats.fields.solves
            step!(dev)
            @test s1 > 0 && dev.stats.fields.solves > s1 &&
                dev.stats.fields.code == Potts.SciMLBase.ReturnCode.Success
        end
    end
end

# Cell averages are exact fixed-point sums, so two device runs
# with the same seed are bitwise equal (σ and the averages), and a device average equals the
# host's bitwise when both read the same site values. Models: test/cell_sums_models.jl.
# Negative control: `CorePotts._FLOAT_ATOMICS` (the float atomics of the code before the
# fixed-point sums); the host and
# the device then differ, and two device runs may differ (logged: an order race is not
# certain to show in one pair of runs).
@testitem "cell averages on ROCm are bitwise reproducible and equal the host" setup = [
    GpuSetup,
] tags = [
    :potts, :gpu, :device,
] begin
    if PottsDevices.device_name() == "rocm"
        isdefined(@__MODULE__, :CsThreshold)||
            include(joinpath(@__DIR__, "cell_sums_models.jl"))
        @testset "cell averages on ROCm are bitwise reproducible and equal the host" begin
            backend = PottsDevices.device_backend()
            bits(x) = reinterpret(UInt32, vec(Array(x)))
            function merks()
                return solve(
                    PottsProblem(
                        CsThreshold(; name = :m), cs_threshold_op(),
                        (0, 30); T = Float32, seed = 7
                    ),
                    CheckerboardCPM(); backend, save_start = false
                ).u[end]
            end
            σj, kj = jiang_state(JG_DIMS)
            function jiang()
                return solve(
                    PottsProblem(
                        JiangLike(; name = :j), [ownership => σj, kind => kj], (0, 12);
                        T = Float32, seed = 7,
                        field_solver = BackwardEuler()
                    ), CheckerboardCPM(); backend, save_start = false
                ).u[end]
            end
            function site(b)
                return solve(
                    PottsProblem(
                        CsSiteAvg(; name = :s), cs_site_op(),
                        (0, 2); T = Float32, seed = 7
                    ),
                    CheckerboardCPM(); backend = b, save_start = false
                ).u[end]
            end
            # copies on the device checkerboard are not reproducible (live reads), so two
            # runs can end in different states; the fixed-point cell sums are, so equal
            # states give bitwise-equal averages
            a, b = merks(), merks()
            # the cells moved
            @test Array(a.ownership) != cs_threshold_op()[1][2]
            if Array(a.ownership) == Array(b.ownership)
                @test bits(a.cell.cavg) == bits(b.cell.cavg)
            end
            ja, jb = jiang(), jiang()
            @test bits(ja.cell.ocell) == bits(jb.cell.ocell) &&
                bits(ja.site.o) == bits(jb.site.o)
            host = site(CPU())
            @test bits(site(backend).cell.havg) == bits(host.cell.havg)
            CorePotts._FLOAT_ATOMICS[] = true
            try
                host0 = site(CPU())
                @test bits(site(backend).cell.havg) != bits(host0.cell.havg)
                a0, b0 = merks(), merks()
                ja0, jb0 = jiang(), jiang()
                @info "negative control (float atomics): two ROCm runs" merks_cavg_equal =
                    bits(a0.cell.cavg) ==
                    bits(b0.cell.cavg) merks_σ_equal = Array(a0.ownership) ==
                    Array(b0.ownership) jiang_ocell_equal = bits(ja0.cell.ocell) ==
                    bits(jb0.cell.ocell)
            finally
                CorePotts._FLOAT_ATOMICS[] = false
            end
        end
    end
end

# The other sums over sites on ROCm. `surface` over a weighted lattice
# neighborhood after divisions (the device lifecycle's recompute), `cluster_surface` of
# weighted compartments that divide, and the compound writes of a `@convert` pass are sums
# in integer units, so a device run and its recount from `σ` agree to a few Float32 ulps
# (rtol 1e-5), and the CPU's two lifecycle planners give the same bits.
#
# D-271 (the lockless checkerboard) changed what is reproducible across runs and backends:
# the per-copy `commit_surface!` adds `Float32` deltas atomically across concurrent GPU
# blocks, so `cell.surface` moves in its low bits from run to run, and a lockless ROCm
# trajectory diverges from the CPU's. So the cross-run and cross-backend equalities below
# are made where the lockless `σ` itself agrees (the integer-unit sums then agree bitwise),
# and the trackers are checked unconditionally against a recount from `σ` (as
# cell_sums_tests.jl does on the host). The full unconditional bitwise checks, at 1, 4 and 8
# threads, stay on the CPU in cell_sums_tests.jl. Negative control:
# `CorePotts._FLOAT_ATOMICS`, the float atomics of the earlier code; logged (an order race
# is not certain to show in a few runs), and its sums differ from the fixed-point ones.
@testitem "weighted surfaces and @convert writes on ROCm agree with a recount" setup = [
    GpuSetup,
] tags = [
    :potts, :gpu, :device,
] begin
    if PottsDevices.device_name() == "rocm"
        isdefined(@__MODULE__, :CsWSurf)||include(joinpath(@__DIR__, "cell_sums_models.jl"))
        @testset "weighted surfaces and @convert writes on ROCm agree with a recount" begin
            backend = PottsDevices.device_backend()
            a, (nw, nc) = cs_site_sum_digests(backend)
            b, _ = cs_site_sum_digests(backend)
            @test nw > 100 && nc > 10
            # the weighted surface against a recount from `σ`, on the run `a[2]` comes from
            # (CsWSurf, 80 MCS, the staged device lifecycle): copies add the float weights
            # and divisions their integer units, so the tracker and the recount differ in
            # the last bits
            pw_w = PottsProblem(
                CsWSurf(; name = :w), cs_wsurf_op(), (0, 80);
                T = Float32, seed = 7, capacity = 2000
            )
            sw_w = solve(
                pw_w, CheckerboardCPM(; fused_lifecycle_max_sites = 0); backend,
                save_start = false
            )
            w_end = sw_w.u[end]
            @test sw_w.stats.lifecycle.divisions > 100
            @test Array(w_end.cell.surface) ≈
                CorePotts.recompute_surface(
                Array(w_end.ownership), pw_w.lattice,
                CorePotts.relation(CS_W, pw_w.lattice),
                length(w_end.cell.volume)
            ) rtol = 1.0e-5
            # two device runs: the integer-unit sums agree bitwise where the lockless `σ`
            # agrees
            b[3] == a[3] ||
                @info "two ROCm runs' compartments left σ (lockless \
                    order)" a = a[3] b = b[3]
            # cluster_surface
            b[3] == a[3] && @test b[4] == a[4]
            b[5] == a[5] ||
                @info "two ROCm runs' @convert model left σ (lockless \
                    order)" a = a[5] b = b[5]
            # the compound writes
            b[5] == a[5] && @test b[6:7] == a[6:7]
            conv = [cs_conv_digests(backend) for _ in 1:5]
            same_conv_σ = all(c -> c[1] == conv[1][1], conv)
            same_conv_σ ||
                @info "the five ROCm @convert runs left σ (lockless order)" σ = first.(conv)
            same_conv_σ && @test allequal(conv)
            # the compartments in the staged device lifecycle too (its cluster-surface fold
            # launch), against a recount from `σ`; the bits are the fused form's where the
            # lockless `σ` agrees
            pc_w = PottsProblem(
                CsWComp(; name = :c), cs_wcomp_op(), (0, 40);
                T = Float32, seed = 7, capacity = 2000
            )
            staged = solve(
                pc_w, CheckerboardCPM(; fused_lifecycle_max_sites = 0); backend,
                save_start = false
            ).u[end]
            @test Array(staged.cell.cluster_surface) ≈
                CorePotts.recompute_cluster_surface(
                Array(staged.ownership), Array(staged.cell.cluster), pc_w.lattice, CS_W
            ) rtol = 1.0e-5
            cs_digest(staged.ownership) == a[3] ||
                @info "the staged compartments' σ differs from the fused \
                    run's" staged = cs_digest(staged.ownership) fused = a[3]
            cs_digest(staged.ownership) == a[3] &&
                @test cs_bits(staged.cell.cluster_surface) == a[4]
            # the CPU: σ of each model ([1, 3, 5]) and, where σ is equal, its sums
            h, _ = cs_site_sum_digests(CorePotts.CPU())
            same = (h[1] == a[1], h[3] == a[3], h[5] == a[5])
            @info "CPU and ROCm σ equal (weighted surface, compartments, convert)" same
            same[1] && @test h[2] == a[2]
            same[2] && @test h[4] == a[4]
            same[3] && @test h[6:7] == a[6:7]
            # The CPU's host lifecycle planner adds the same integer units as the
            # device lifecycle, so the two CPU paths agree in full (integer units, no float
            # deltas)
            hh, _ = cs_site_sum_digests(CorePotts.CPU(); host = true)
            @test hh == h
            # and across backends the same conditional reading: σ first, then the sums
            hh[1] == a[1] && @test hh[2] == a[2]
            hh[3] == a[3] && @test hh[4] == a[4]
            CorePotts._FLOAT_ATOMICS[] = true
            try
                a0, _ = cs_site_sum_digests(backend; ctl = true)
                b0, _ = cs_site_sum_digests(backend; ctl = true)
                conv0 = [cs_conv_digests(backend; ctl = true) for _ in 1:5]
                @test a0[[2, 4, 6, 7]] != a[[2, 4, 6, 7]]
                h0, _ = cs_site_sum_digests(CorePotts.CPU(); ctl = true, host = true)
                # the host's float recompute ≠ ROCm
                @test h0[2] != a0[2] && h0[2] != a[2]
                @info "negative control (float atomics): two ROCm runs" surface_equal = a0[
                    2,
                ] == b0[2] cluster_surface_equal = a0[4] ==
                    b0[4] conv_distinct_tot = length(
                    unique(
                        c -> c[2], conv0
                    )
                ) conv_distinct_Vt = length(unique(c -> c[3], conv0))
            finally
                CorePotts._FLOAT_ATOMICS[] = false
            end
        end
    end
end
