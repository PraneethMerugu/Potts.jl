module PottsToolkitMetalNativeExt

using PottsToolkit
using DiffEqGPU
using Metal
using ModelingToolkit
using StaticArrays

import ModelingToolkitBase
import SciMLBase
import SymbolicIndexingInterface
import Symbolics

function _package_identity(module_value)
    package = PottsToolkit._native_package_identity(module_value)
    return (
        package = package.name,
        uuid = package.uuid,
        version = package.version,
    )
end

const _G5H4_TESTED_METAL_NATIVE_STACK_1_12_1 = (
    DiffEqGPU = (
        package = "DiffEqGPU",
        uuid = "071ae1c0-96b5-11e9-1965-c90190d839ea",
        version = v"3.16.0",
    ),
    Metal = (
        package = "Metal",
        uuid = "dde4c033-4e86-420c-a63e-0dd931031962",
        version = v"1.10.0",
    ),
    ModelingToolkit = (
        package = "ModelingToolkit",
        uuid = "961ee093-0014-501f-94e3-6117800e7a78",
        version = v"11.38.0",
    ),
    ModelingToolkitBase = (
        package = "ModelingToolkitBase",
        uuid = "7771a370-6774-4173-bd38-47e70ca0b839",
        version = v"1.59.0",
    ),
    SciMLBase = (
        package = "SciMLBase",
        uuid = "0bca4576-84f4-4d90-8ffe-ffa030f20462",
        version = v"3.41.0",
    ),
    SymbolicIndexingInterface = (
        package = "SymbolicIndexingInterface",
        uuid = "2efcf032-c050-4f8e-a9bb-153293bab1f5",
        version = v"0.3.51",
    ),
    Symbolics = (
        package = "Symbolics",
        uuid = "0c5d862f-8b57-4792-8d23-62f2024744c7",
        version = v"7.35.0",
    ),
    StaticArrays = (
        package = "StaticArrays",
        uuid = "90137ffa-7385-5640-81b9-e52037218182",
        version = v"1.9.18",
    ),
    Julia = (
        version = v"1.12.1",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),
)

const _G5H4_TESTED_METAL_NATIVE_STACK = merge(
    _G5H4_TESTED_METAL_NATIVE_STACK_1_12_1,
    (Julia = (
        version = v"1.12.6",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),),
)

const _G5H4_TESTED_METAL_NATIVE_STACKS = (
    _G5H4_TESTED_METAL_NATIVE_STACK_1_12_1,
    _G5H4_TESTED_METAL_NATIVE_STACK,
)

function _metal_native_stack_identity()
    return (
        DiffEqGPU = _package_identity(DiffEqGPU),
        Metal = _package_identity(Metal),
        ModelingToolkit = _package_identity(ModelingToolkit),
        ModelingToolkitBase = _package_identity(ModelingToolkitBase),
        SciMLBase = _package_identity(SciMLBase),
        SymbolicIndexingInterface =
            _package_identity(SymbolicIndexingInterface),
        Symbolics = _package_identity(Symbolics),
        StaticArrays = _package_identity(StaticArrays),
        Julia = (
            version = VERSION,
            kernel = Sys.KERNEL,
            architecture = Sys.ARCH,
            word_size = Sys.WORD_SIZE,
            machine = Sys.MACHINE,
        ),
    )
end

struct StaticNativeODEFunction{N, F}
    f::F
end

function (f::StaticNativeODEFunction{N})(u, p, t) where {N}
    du = MVector{N, eltype(u)}(undef)
    f.f(du, u, p, t)
    return SVector{N}(du)
end

function _metal_error(component, capability, message)
    return PottsToolkit.NativeCapabilityError(
        PottsToolkit.native_component_path(component), capability, message
    )
end

function _standard_preflight(component, point, profile, initial_time)
    return invoke(
        PottsToolkit.preflight_native_component,
        Tuple{
            PottsToolkit.ScheduledNativeComponent,
            PottsToolkit.NativeOperatingPoint,
            PottsToolkit.NativeSolveProfile,
            Any,
        },
        component, point, profile, initial_time,
    )
end

function PottsToolkit.preflight_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        profile::PottsToolkit.NativeSolveProfile{
            P, A, O, PottsToolkit.MetalNativeExecution,
        },
        initial_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    Metal.functional() || throw(_metal_error(
        component, :device_available,
        "MetalNativeExecution was requested but Metal is not functional",
    ))
    _metal_native_stack_identity() in _G5H4_TESTED_METAL_NATIVE_STACKS ||
        throw(_metal_error(
            component,
            :native_runtime_stack,
            "the requested Metal native stack has no closed real-device evidence row",
        ))
    profile.algorithm isa DiffEqGPU.GPUTsit5 || throw(_metal_error(
        component, :native_algorithm,
        "the qualified Metal kernel row requires DiffEqGPU.GPUTsit5()",
    ))
    get(profile.options, :adaptive, nothing) === false ||
        throw(_metal_error(
            component, :native_algorithm,
            "MetalNativeExecution requires adaptive=false",
        ))
    dt = get(profile.options, :dt, nothing)
    dt isa Float32 && isfinite(dt) && dt > 0 || throw(_metal_error(
        component, :scalar_type,
        "the qualified Metal kernel row requires a positive Float32 dt",
    ))
    _standard_preflight(component, point, profile, initial_time)
    return nothing
end

function PottsToolkit._native_profile_evidence(
        component::PottsToolkit.ScheduledNativeComponent,
        profile::PottsToolkit.NativeSolveProfile{
            P, A, O, PottsToolkit.MetalNativeExecution,
        },
    ) where {P <: Tuple, A, O <: NamedTuple}
    declaration = getfield(component, :declaration)
    _metal_native_stack_identity() in _G5H4_TESTED_METAL_NATIVE_STACKS ||
        return nothing
    getfield(declaration, :capabilities) isa
        PottsToolkit._MethodOfLinesNativeCapability && return nothing
    PottsToolkit.native_family(declaration) isa PottsToolkit.ODEComponent ||
        return nothing
    PottsToolkit._native_event_contract(component).admitted || return nothing
    profile.algorithm isa DiffEqGPU.GPUTsit5 || return nothing
    get(profile.options, :adaptive, nothing) === false || return nothing
    get(profile.options, :dt, nothing) isa Float32 || return nothing
    profile.exact_replay && profile.deterministic || return nothing
    scope = getfield(declaration, :scope)
    scope isa Union{PottsToolkit.Global, PottsToolkit.PerCell} || return nothing
    field_output = any(
        endpoint -> endpoint.port isa PottsToolkit.NativeFieldOutput,
        PottsToolkit.native_coupling_endpoints(component),
    )
    field_output && !(scope isa PottsToolkit.Global) && return nothing
    suite = field_output ?
        :g5h4_native_field_metal_exact_replay : scope isa PottsToolkit.Global ?
        :g5h4_global_metal_native_ode_exact_replay :
        :g5h4_per_cell_metal_native_ode_exact_replay
    evidence = PottsToolkit.CorePotts.BackendSPI.CapabilityEvidenceIdentity(
        :PottsToolkit,
        suite,
        v"1.0.0",
        PottsToolkit._sha256_hex(
            "g5h4-metal-native-evidence-v1",
            PottsToolkit._native_profile_fingerprint(profile),
            PottsToolkit.native_scheduled_fingerprint(component).hex,
            _metal_native_stack_identity(),
            :ensemble_gpu_kernel_metal,
            :explicit_coupled_interval_transfer,
            field_output,
        ),
    )
    return (
        status = PottsToolkit.CorePotts.BackendSPI.Supported,
        maturity = PottsToolkit.CorePotts.BackendSPI.ReplayQualified,
        evidence,
    )
end

function PottsToolkit._initialize_preflighted_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        point::PottsToolkit.NativeOperatingPoint,
        profile::PottsToolkit.NativeSolveProfile{
            P, A, O, PottsToolkit.MetalNativeExecution,
        },
        inputs::Tuple,
        initial_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    problem = PottsToolkit._native_initial_problem(
        component, point, inputs, initial_time
    )
    eltype(problem.u0) === Float32 || throw(_metal_error(
        component, :scalar_type,
        "Metal native initial state must be Float32",
    ))
    return PottsToolkit._native_logical_from_problem_solution(
        component,
        problem,
        problem.u0,
        initial_time,
        SciMLBase.ReturnCode.Default,
    )
end

function _metal_problems(component, lanes, target_time)
    problems = map(lanes) do lane
        problem = PottsToolkit._native_continuation_problem(
            component, lane.state, lane.inputs, target_time
        )
        SciMLBase.isinplace(problem) || throw(_metal_error(
            component, :native_execution_mode,
            "MetalNativeExecution requires an in-place MTK-generated ODE function",
        ))
        eltype(problem.u0) === Float32 || throw(_metal_error(
            component, :scalar_type,
            "Metal native state must be Float32 at the coupled boundary",
        ))
        problem
    end
    reference = first(problems)
    width = length(reference.u0)
    width > 0 || throw(_metal_error(
        component, :fixed_dimension_state,
        "Metal native state must be nonempty",
    ))
    all(problem ->
        typeof(problem.f) === typeof(reference.f) &&
        length(problem.u0) == width &&
        eltype(problem.u0) === Float32 &&
        typeof(problem.p) === typeof(reference.p), problems) ||
        throw(_metal_error(
            component, :fixed_dimension_state,
            "all Metal lanes must share one fixed state and parameter schema",
        ))
    return problems
end

function _static_parameter_field(component, value)
    if value isa AbstractVector && isbitstype(eltype(value))
        return SVector{length(value), eltype(value)}(Tuple(value))
    end
    isbitstype(typeof(value)) || throw(_metal_error(
        component, :device_parameter_schema,
        "an MTK parameter field of type $(typeof(value)) has no fixed isbits device representation",
    ))
    return value
end

function _static_parameters(component, parameters)
    fields = ntuple(
        index -> _static_parameter_field(
            component, getfield(parameters, index)
        ),
        fieldcount(typeof(parameters)),
    )
    static = ModelingToolkitBase.MTKParameters(fields...)
    isbitstype(typeof(static)) || throw(_metal_error(
        component, :device_parameter_schema,
        "the statically lowered MTK parameter buffer is not isbits",
    ))
    return static
end

function _solve_metal_lanes(component, lanes, profile, target_time)
    isempty(lanes) && return PottsToolkit.NativeLogicalState[]
    problems = _metal_problems(component, lanes, target_time)
    reference = first(problems)
    static_parameters = map(
        problem -> _static_parameters(component, problem.p), problems
    )
    N = length(reference.u0)
    generated_f = reference.f.f
    isbitstype(typeof(generated_f)) || throw(_metal_error(
        component, :device_function_schema,
        "the MTK generated ODE function is not an isbits GPU kernel value",
    ))
    static_f = StaticNativeODEFunction{N, typeof(generated_f)}(generated_f)
    base = SciMLBase.ODEProblem{false}(
        static_f,
        SVector{N, Float32}(Tuple(reference.u0)),
        (Float32(reference.tspan[1]), Float32(reference.tspan[2])),
        first(static_parameters),
    )
    ensemble = SciMLBase.EnsembleProblem(
        base;
        prob_func = (prob, context) -> begin
            lane_index = min(context.sim_id, length(problems))
            lane = problems[lane_index]
            SciMLBase.remake(
                prob;
                u0 = SVector{N, Float32}(Tuple(lane.u0)),
                p = static_parameters[lane_index],
            )
        end,
        safetycopy = false,
    )
    options = merge(
        profile.options,
        (;
            # DiffEqGPU deliberately routes a one-trajectory ensemble through
            # EnsembleSerial. Pad a global/single-live-cell solve with one
            # identical lane so MetalNativeExecution never silently falls
            # back to the host.
            trajectories = max(2, length(problems)),
            save_everystep = false,
            save_start = false,
            save_end = true,
        ),
    )
    solution = SciMLBase.solve(
        ensemble,
        profile.algorithm,
        DiffEqGPU.EnsembleGPUKernel(Metal.MetalBackend());
        options...,
    )
    solution.converged || throw(_metal_error(
        component, :native_solve,
        "DiffEqGPU Metal ensemble did not converge",
    ))
    all(index -> solution.u[index].t[end] == Float32(target_time),
        eachindex(problems)) || throw(_metal_error(
        component, :native_solve,
        "DiffEqGPU Metal ensemble did not reach the exact coupled boundary",
    ))
    reached = Float32(target_time)
    return [PottsToolkit._native_logical_from_problem_solution(
        component,
        problems[index],
        solution.u[index].u[end],
        reached,
        SciMLBase.ReturnCode.Success,
    ) for index in eachindex(problems)]
end

function PottsToolkit._advance_native_cell_batch(
        component::PottsToolkit.ScheduledNativeComponent,
        lanes::AbstractVector,
        profile::PottsToolkit.NativeSolveProfile{
            P, A, O, PottsToolkit.MetalNativeExecution,
        },
        target_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    return _solve_metal_lanes(component, lanes, profile, target_time)
end

function PottsToolkit.advance_native_component(
        component::PottsToolkit.ScheduledNativeComponent,
        state::PottsToolkit.NativeLogicalState,
        profile::PottsToolkit.NativeSolveProfile{
            P, A, O, PottsToolkit.MetalNativeExecution,
        },
        inputs::Tuple,
        target_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    lane = (slot = 1, state = state, inputs = inputs)
    return only(_solve_metal_lanes(
        component, [lane], profile, target_time
    ))
end

end
