# The field pipeline's gates that hold no recorded value: the hard set on the device against the
# same run on the CPU, and the warm MCS of the Merks models at 500² allocating nothing. Both moved
# here from the F2 guard (test/fields_identity.jl) when D-274 deleted the guard's records, its
# fingerprint and fill-order pins and its bitwise-parent pins.
#
# (the models, `ownership`, `kind`, `fd_source_op`, `PottsDevices` and the Merks models are
# `FieldsSetup`'s, the converted fields.jl part of the suite)

# ROCm (F2 batch 2): with `POTTS_GPU=rocm`, every case on the device (CheckerboardCPM) against
# the same run on the CPU: σ equal, every site array within a relative 1e-5 (Float32) or 1e-12
# (Float64) of its largest value
@testitem "F2 guard (ROCm): the hard set on the device matches the CPU" setup = [FieldsSetup] tags = [:potts, :fields, :device] begin
    if PottsDevices.on_device() && PottsDevices.device_name() == "rocm"
        @testset "F2 guard (ROCm): the hard set on the device matches the CPU" begin
            backend = PottsDevices.device_backend()
            # a one-site frozen border (cell 1) and two endothelial cells
            function fp_op2006()
                σ = zeros(Int32, 16, 16)
                σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
                σ[4:7, 4:7] .= 2; σ[10:13, 9:12] .= 3
                return [ownership => σ, kind => [:border, :endothelial, :endothelial]]
            end
            # a frozen wall column (cell 1) and one cell
            fp_opmask() = (σ = zeros(Int32, 10, 8); σ[1, :] .= 1; σ[5:6, 4:5] .= 2; [ownership => σ, kind => [:wall, :A]])
            # (label, system, operating point, keywords): the models the device gate runs
            dev = [
                ("MerksVasculogenesis", () -> MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
                    [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]],
                    (; field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)),
                ),
                ("Merks2006", () -> Merks2006(; name = :m, lattice = (16, 16)), fp_op2006(),
                    (; field_solver = ExplicitEuler(substeps = 15))),
                # two solver groups; `u` reads `c` from its array (fields_tests.jl, FdTwo)
                ("FdTwo", () -> FdTwo(; name = :t), fd_source_op((12, 10)),
                    (; field_solver = ExplicitEuler(substeps = 2), solvers = [:u => ExplicitEuler(substeps = 3)])),
                ("FdMask", () -> FdMask(; name = :m), fp_opmask(), (; field_solver = ExplicitEuler())),
            ]
            # Float32 only: the Potts device suite ends with a scan that no kernel it compiled holds
            # a `double` (D-157, Metal stands in), and a Float64 problem's kernels do
            for (label, build, op, kw) in dev, T in (Float32,)
                prob = PottsProblem(build(), op, (0, 5); T, seed = 7, kw...)
                cpu = solve(prob, CheckerboardCPM()).u[end]
                dev_sol = solve(prob, CheckerboardCPM(); backend).u[end]
                ok = Array(dev_sol.σ) == Array(cpu.σ)
                tol = T === Float32 ? 1e-5 : 1e-12
                for k in keys(cpu.site)
                    a, b = Float64.(Array(getproperty(cpu.site, k))), Float64.(Array(getproperty(dev_sol.site, k)))
                    ok &= maximum(abs, a .- b; init = 0.0) <= tol * max(1.0, maximum(abs, a; init = 0.0))
                end
                ok || println(stderr, "  DEVICE differs: $label|$T")
                @test ok
            end
        end
    end
end

# F2-08a: a warm MCS of Merks at 500² (15 substeps, the field read by the CPM) allocates
# nothing on the CPU (measured inside a function)
@testitem "F2-08a: the Merks 500² warm MCS allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08a: the Merks 500² warm MCS allocates nothing (CPU)" begin
        warm(integ) = (step!(integ); step!(integ); @allocated step!(integ))
        σ = zeros(Int32, 500, 500); σ[200:215, 200:215] .= 1; σ[300:312, 280:300] .= 2
        prob = PottsProblem(MerksVasculogenesis(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:endothelial, :endothelial]],
            (0, 100); field_solver = ExplicitEuler(substeps = 15, lower_bound = 0.0)
        )
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
        @test warm(integ) == 0
    end
end

# F2-08b: Merks2006 has a masked field (its `kind == border` frame): the clamp at the step start
# runs every MCS, and a warm MCS at 500² still allocates nothing on the CPU (a `foreach` closure
# over the clamps allocated 176 B per MCS on front end A's runtime)
@testitem "F2-08b: the Merks2006 500² warm MCS (masked, clamped) allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08b: the Merks2006 500² warm MCS (masked, clamped) allocates nothing (CPU)" begin
        warm(integ) = (step!(integ); step!(integ); @allocated step!(integ))
        σ = zeros(Int32, 500, 500); σ[1, :] .= 1; σ[end, :] .= 1; σ[:, 1] .= 1; σ[:, end] .= 1
        σ[200:215, 200:215] .= 2; σ[300:312, 280:300] .= 3
        prob = PottsProblem(Merks2006(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:border, :endothelial, :endothelial]],
            (0, 100); field_solver = ExplicitEuler(substeps = 15))
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
        @test warm(integ) == 0
    end
end

# F2-08c: Merks2008 reads `mcs` (its `mcs ≥ t_relax` gate) through the clock's slot, whose
# launches derive their parameters at each launch with the MCS number: a warm MCS at 500²
# still allocates nothing on the CPU
@testitem "F2-08c: the Merks2008 500² warm MCS (mcs read) allocates nothing (CPU)" setup = [FieldsSetup] tags = [:potts, :fields] begin
    @testset "F2-08c: the Merks2008 500² warm MCS (mcs read) allocates nothing (CPU)" begin
        warm(integ) = (step!(integ); step!(integ); @allocated step!(integ))
        σ = zeros(Int32, 500, 500); σ[1:2, :] .= 1; σ[(end - 1):end, :] .= 1; σ[:, 1:2] .= 1; σ[:, (end - 1):end] .= 1
        σ[200:215, 200:215] .= 2; σ[300:312, 280:300] .= 3
        prob = PottsProblem(Merks2008(; name = :m, lattice = (500, 500)), [ownership => σ, kind => [:border, :endothelial, :endothelial],
            :t_relax => 1.0], (0, 100); field_solver = ExplicitEuler(substeps = 15))
        integ = init(prob, SequentialCPM(); save_start = false, save_end = false, save_everystep = false)
        @test warm(integ) == 0
    end
end
