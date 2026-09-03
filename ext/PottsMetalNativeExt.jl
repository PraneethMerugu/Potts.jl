module PottsMetalNativeExt

using Potts
using DiffEqGPU
using KernelAbstractions
using Metal
using ModelingToolkit
using StaticArrays

import ModelingToolkitBase
import SciMLBase
import SymbolicIndexingInterface
import Symbolics

function _package_identity(module_value)
    package = Potts._native_package_identity(module_value)
    return (
        package = package.name,
        uuid = package.uuid,
        version = package.version,
    )
end

const _TESTED_METAL_NATIVE_STACK = (
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
        version = v"7.37.0",
    ),
    StaticArrays = (
        package = "StaticArrays",
        uuid = "90137ffa-7385-5640-81b9-e52037218182",
        version = v"1.9.18",
    ),
    Julia = (
        version = v"1.12.6",
        kernel = :Darwin,
        architecture = :aarch64,
        word_size = 64,
        machine = "arm64-apple-darwin24.0.0",
    ),
)

const _TESTED_METAL_NATIVE_STACKS = (_TESTED_METAL_NATIVE_STACK,)

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
    return Potts.NativeCapabilityError(
        Potts.native_component_path(component), capability, message
    )
end

function _metal_kernelabstractions_backend(component)
    backend = Metal.MetalBackend()
    backend isa KernelAbstractions.Backend || throw(_metal_error(
        component,
        :kernelabstractions_backend,
        "Metal native execution requires a KernelAbstractions backend",
    ))
    return backend
end

function _standard_preflight(component, point, profile, initial_time)
    return invoke(
        Potts.preflight_native_component,
        Tuple{
            Potts.ScheduledNativeComponent,
            Potts.NativeOperatingPoint,
            Potts.NativeSolveProfile,
            Any,
        },
        component, point, profile, initial_time,
    )
end

function Potts.preflight_native_component(
        component::Potts.ScheduledNativeComponent,
        point::Potts.NativeOperatingPoint,
        profile::Potts.NativeSolveProfile{
            P, A, O, Potts.MetalNativeExecution,
        },
        initial_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    Metal.functional() || throw(_metal_error(
        component, :device_available,
        "MetalNativeExecution was requested but Metal is not functional",
    ))
    !profile.exact_replay ||
        _metal_native_stack_identity() in _TESTED_METAL_NATIVE_STACKS ||
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

function Potts._native_profile_evidence(
        component::Potts.ScheduledNativeComponent,
        profile::Potts.NativeSolveProfile{
            P, A, O, Potts.MetalNativeExecution,
        },
    ) where {P <: Tuple, A, O <: NamedTuple}
    declaration = getfield(component, :declaration)
    _metal_native_stack_identity() in _TESTED_METAL_NATIVE_STACKS ||
        return nothing
    getfield(declaration, :capabilities) isa
        Potts._MethodOfLinesNativeCapability && return nothing
    Potts.native_family(declaration) isa Potts.ODEComponent ||
        return nothing
    Potts._native_event_contract(component).admitted || return nothing
    profile.algorithm isa DiffEqGPU.GPUTsit5 || return nothing
    get(profile.options, :adaptive, nothing) === false || return nothing
    get(profile.options, :dt, nothing) isa Float32 || return nothing
    profile.exact_replay && profile.deterministic || return nothing
    scope = getfield(declaration, :scope)
    scope isa Union{Potts.Global, Potts.PerCell} || return nothing
    field_output = any(
        endpoint -> endpoint.port isa Potts.NativeFieldOutput,
        Potts.native_coupling_endpoints(component),
    )
    field_output && !(scope isa Potts.Global) && return nothing
    suite = field_output ?
        :native_field_metal_exact_replay : scope isa Potts.Global ?
        :global_metal_native_ode_exact_replay :
        :per_cell_metal_native_ode_exact_replay
    evidence = Potts._capability_evidence_identity(
        :Potts,
        suite,
        v"1.0.0",
        Potts._sha256_hex(
            "metal-native-evidence-v1",
            Potts._native_profile_fingerprint(profile),
            Potts.native_scheduled_fingerprint(component).hex,
            _metal_native_stack_identity(),
            :ensemble_gpu_kernel_kernelabstractions,
            :metal_backend_adapter,
            :explicit_coupled_interval_transfer,
            field_output,
        ),
    )
    return (
        status = Potts.CorePotts.BackendSPI.Supported,
        exact_replay = true,
        evidence,
    )
end

function Potts._initialize_preflighted_native_component(
        component::Potts.ScheduledNativeComponent,
        point::Potts.NativeOperatingPoint,
        profile::Potts.NativeSolveProfile{
            P, A, O, Potts.MetalNativeExecution,
        },
        inputs::Tuple,
        initial_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    problem = Potts._native_initial_problem(
        component, point, inputs, initial_time
    )
    eltype(problem.u0) === Float32 || throw(_metal_error(
        component, :scalar_type,
        "Metal native initial state must be Float32",
    ))
    return Potts._native_logical_from_problem_solution(
        component,
        problem,
        problem.u0,
        initial_time,
        SciMLBase.ReturnCode.Default,
    )
end

function _metal_problems(component, lanes, target_time)
    problems = map(lanes) do lane
        problem = Potts._native_continuation_problem(
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
    isempty(lanes) && return Potts.NativeLogicalState[]
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
    # DiffEqGPU.EnsembleGPUKernel accepts and launches a
    # KernelAbstractions.Backend. Metal supplies only the backend adapter and
    # storage implementation; Potts owns no vendor kernel or launch.
    ka_backend = _metal_kernelabstractions_backend(component)
    solution = SciMLBase.solve(
        ensemble,
        profile.algorithm,
        DiffEqGPU.EnsembleGPUKernel(ka_backend);
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
    return [Potts._native_logical_from_problem_solution(
        component,
        problems[index],
        solution.u[index].u[end],
        reached,
        SciMLBase.ReturnCode.Success,
    ) for index in eachindex(problems)]
end

function Potts._advance_native_cell_batch(
        component::Potts.ScheduledNativeComponent,
        lanes::AbstractVector,
        profile::Potts.NativeSolveProfile{
            P, A, O, Potts.MetalNativeExecution,
        },
        target_time,
    ) where {P <: Tuple, A, O <: NamedTuple}
    return _solve_metal_lanes(component, lanes, profile, target_time)
end

function Potts.advance_native_component(
        component::Potts.ScheduledNativeComponent,
        state::Potts.NativeLogicalState,
        profile::Potts.NativeSolveProfile{
            P, A, O, Potts.MetalNativeExecution,
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
