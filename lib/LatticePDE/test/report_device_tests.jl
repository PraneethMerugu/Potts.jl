# The field report on a device (LATTICEPDE_GPU = rocm | metal), Float32: `field_report` of
# an owned integrator (explicit and Backward Euler), of an owned solution and of an
# OrdinaryDiffEq solve on device arrays prints the same group policy as the host, with the
# device's counters, and the run after a report equals the run without one, bit for bit.
# Negative control at 4d025fa8: `field_report` is not defined.

@testsetup module LP_report_device
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/maskswitch.jl")
using KernelAbstractions: KernelAbstractions
using OrdinaryDiffEqTsit5: Tsit5
if !@isdefined(PDEV)
    if lowercase(get(ENV, "LATTICEPDE_GPU", "")) == "metal"
        using Metal: Metal
        const PDEV = Metal.MetalBackend()
    else
        using AMDGPU: AMDGPU
        const PDEV = AMDGPU.ROCBackend()
    end
end
include("shared/export_all.jl")
end

@testitem "field_report on nameof(typeof(PDEV))" setup = [LP_report_device] tags = [
    :latticepde, :report_device, :gpu_only,
] begin
    @testset "field_report on $(nameof(typeof(PDEV)))" begin
        @parameters dD = 1.0e-3 dk = 0.1
        @variables dc(..)
        dce = dc(t, x, y)
        sys = PDESystem(
            D(dce) ~ dD * laplacian(dce) - dk * dce,
            [
                dc(0, x, y) ~ 0.0, dc(t, 0, y) ~ 1.0,
                Differential(x)(dc(t, 1, y)) ~ 0.0, dc(t, x, 0) ~ dc(t, x, 1),
            ],
            [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [
                t, x, y,
            ], [dce], [dD, dk]; name = :d
        )
        function mk(n, be)
            return discretize(
                sys,
                LatticeDiscretization(Grid((n, n)); T = Float32, backend = be)
            )
        end
        function body(r)
            return join(
                filter(
                    l -> !(
                        startswith(l, "  problem") || startswith(l, "  launches") ||
                            startswith(l, "  fusion") ||
                            startswith(l, "           ")
                    ), split(r, '\n')
                ), '\n'
            )
        end
        # the §7.4 count at 512² (12 substeps of the bound) on the device
        pd = mk(512, PDEV)
        ig = init(pd, ExplicitEuler(); dt = 0.01)
        r = sprint(field_report, ig)
        @test occursin("backend $(nameof(typeof(PDEV)))", r) &&
            occursin("12 substeps", r) && occursin("/ 1.8⌉ = 12 [bound]", r)
        @test occursin("state Float32, compute Float32", r)
        for alg in (ExplicitEuler(), BackwardEuler())
            pd, ph = mk(32, PDEV), mk(32, KernelAbstractions.CPU())
            a, b, h = init(pd, alg; dt = 0.01), init(pd, alg; dt = 0.01),
                init(ph, alg; dt = 0.01)
            step!(a)
            step!(b)
            step!(h)
            rd, rh = sprint(field_report, a), sprint(field_report, h)
            # the same group policy as the host (the device and host plans' launches may
            # differ)
            @test body(rd) == body(rh) || (println(rd, "\n----\n", rh); false)
            step!(a)
            step!(b)
            # the report changed nothing in the run
            @test Array(a.u) == Array(b.u)
            if alg isa BackwardEuler
                @test occursin("LatticePCG() (`linsolve = :auto`), multigrid levels", rd) &&
                    occursin("1 window; 1 solve; status Success", rd)
            end
        end
        s = solve(mk(32, PDEV), BackwardEuler(); dt = 0.01)
        rs = sprint(field_report, s)
        @test occursin("owned solve, BackwardEuler(), retcode Success", rs) &&
            occursin("substep counts dc 1; 10 solves", rs)
        st = solve(mk(32, PDEV), Tsit5())
        rt = sprint(field_report, st)
        @test occursin("SciML solve, Tsit5, retcode Success", rt) &&
            occursin("backend $(nameof(typeof(PDEV)))", rt)
        # (the device's matrix-free `JacobianOperator`, a SciMLOperators `FunctionOperator`)
        @test occursin(
            "jac update_coefficients!; jac_prototype FunctionOperator; jvp LatticeJVP", rt
        )
    end
end
