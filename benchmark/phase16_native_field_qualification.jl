VERSION == v"1.12.6" ||
    error("Phase 16 native-field qualification requires Julia 1.12.6; found $VERSION")

using CorePotts
using KernelAbstractions
using SHA
using TOML

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    isnothing(argument) ? default :
        ARGS[argument][(length(prefix) + 1):end]
end

const backend_name = option("backend", "cpu")
const output_path = option(
    "output",
    joinpath(
        @__DIR__,
        "results",
        "phase16-native-field-$(backend_name).toml",
    ),
)
backend_name in ("cpu", "metal", "amdgpu") ||
    error("expected --backend=cpu, --backend=metal, or --backend=amdgpu")
backend_name == "metal" && (@eval using Metal)
backend_name == "amdgpu" && (@eval using AMDGPU)

function backend_and_adaptor(name)
    name == "cpu" && return (KernelAbstractions.CPU(), Array)
    if name == "metal"
        Metal.functional() || error("Metal is not functional")
        return (Metal.MetalBackend(), Metal.MtlArray)
    end
    AMDGPU.functional() || error("AMDGPU is not functional")
    (AMDGPU.ROCBackend(), AMDGPU.ROCArray)
end

function initial_field(dimensions)
    rank = length(dimensions)
    Array{Float32}(undef, dimensions...) .= reshape(
        Float32[
            1.0f0 +
            0.05f0 * cospi(2f0 * (index - 1) / dimensions[1]) +
            0.025f0 * sinpi(2f0 * (index - 1) / prod(dimensions))
            for index in 1:prod(dimensions)
        ],
        dimensions,
    )
end

function native_engine(values, plan, boundaries)
    geometry = CorePotts.NativeFieldGeometry(
        size(values);
        spacing=ntuple(axis -> Float32(0.5 + 0.25axis), ndims(values)),
        number_type=Float32,
    )
    engine = CorePotts.NativeFieldEngine(
        :phase16_qualification,
        values,
        plan;
        geometry,
        boundaries,
        diffusion=0.05f0,
        decay=0.01f0,
        tick_duration=0.01f0,
        substeps_per_tick=2,
        reject_negative=true,
    )
    engine.forcing .= reshape(
        Float32[
            1.0f-4 * Float32(mod(index, 7))
            for index in 1:length(values)
        ],
        size(values),
    )
    engine
end

publication_allocations(engine) =
    @allocated CorePotts.publish_native_field!(engine)

function run_case(name, dimensions, boundaries, backend, adaptor)
    values = initial_field(dimensions)
    cpu_plan = ExecutionPlan(KernelAbstractions.CPU(); block_size=128)
    cpu = native_engine(values, cpu_plan, boundaries)
    CorePotts.advance_native_field!(cpu, 2)
    expected = copy(cpu.published)

    source = native_engine(
        values,
        ExecutionPlan(KernelAbstractions.CPU(); block_size=128),
        boundaries,
    )
    plan = ExecutionPlan(backend; block_size=128)
    candidate = backend_name == "cpu" ? source :
        CorePotts.adapt_native_field_engine(plan, adaptor, source)
    if backend_name == "cpu"
        candidate.plan = plan
    end
    before = (
        h2d=plan.metrics.host_to_device_transfers,
        d2h=plan.metrics.device_to_host_transfers,
        allocations=plan.metrics.device_allocations,
        launches=plan.metrics.launches,
        synchronizations=plan.metrics.host_synchronizations,
    )
    all(array -> isequal(
            KernelAbstractions.get_backend(array), backend),
        (
            candidate.published,
            candidate.first,
            candidate.second,
            candidate.forcing,
            candidate.status,
            candidate.failing_index,
        )) || error("$name has mixed or incorrect residency")

    authoritative = candidate.published
    CorePotts.stage_native_field!(candidate, 2)
    candidate.published === authoritative ||
        error("$name published before completion")
    plan.metrics.host_to_device_transfers == before.h2d ||
        error("$name staged an undeclared host-to-device transfer")
    plan.metrics.device_to_host_transfers == before.d2h ||
        error("$name staged an undeclared device-to-host transfer")
    plan.metrics.device_allocations == before.allocations ||
        error("$name allocated device memory during warm staging")
    CorePotts.complete_native_field!(candidate)
    plan.metrics.device_to_host_transfers ==
        before.d2h + (backend_name == "cpu" ? 0 : 2) ||
        error("$name completion transfer count changed")
    allocation_bytes = publication_allocations(candidate)
    allocation_bytes == 0 ||
        error("$name publication allocated $allocation_bytes host bytes")
    candidate.published !== authoritative ||
        error("$name did not pointer-swap its completed candidate")
    observed = CorePotts.native_field_snapshot(candidate)
    maximum(abs, observed .- expected) <= 2.0f-6 ||
        error("$name differs from the Float32 CPU reference")
    candidate.time_tick == 2 ||
        error("$name did not publish its exact target tick")
    candidate.publication_epoch == 1 ||
        error("$name publication epoch changed")

    Dict(
        "name" => name,
        "rank" => length(dimensions),
        "dimensions" => collect(dimensions),
        "maximum_absolute_error" => maximum(abs, observed .- expected),
        "published_exact_tick" => candidate.time_tick,
        "publication_epoch" => Int(candidate.publication_epoch),
        "publication_host_allocated_bytes" => allocation_bytes,
        "initial_host_to_device_transfers" => before.h2d,
        "staging_host_to_device_transfers" =>
            plan.metrics.host_to_device_transfers - before.h2d,
        "completion_and_observation_device_to_host_transfers" =>
            plan.metrics.device_to_host_transfers - before.d2h,
        "warm_device_allocations" =>
            plan.metrics.device_allocations - before.allocations,
        "launches" => plan.metrics.launches - before.launches,
        "host_synchronizations" =>
            plan.metrics.host_synchronizations - before.synchronizations,
    )
end

backend, adaptor = backend_and_adaptor(backend_name)
periodic2 = ntuple(
    _ -> AxisFieldBoundary(PeriodicFieldBoundary()), 2)
mixed3 = (
    AxisFieldBoundary(PeriodicFieldBoundary()),
    AxisFieldBoundary(ZeroNeumannFieldBoundary()),
    AxisFieldBoundary(
        MixedFieldBoundary(1.0f0, 1.0f0, 1.0f0),
        DirichletFieldBoundary(1.0f0),
    ),
)
cases = [
    run_case("periodic-2d", (64, 48), periodic2, backend, adaptor),
    run_case("mixed-3d", (16, 12, 8), mixed3, backend, adaptor),
]

mkpath(dirname(output_path))
source_path = joinpath(
    @__DIR__, "..", "lib", "CorePotts", "src", "coupled", "native_fields.jl")
result = Dict(
    "schema_version" => "1.0.0",
    "evidence_id" => "process-bigraph-phase16-native-field-v1",
    "backend" => backend_name,
    "backend_type" => string(typeof(backend)),
    "julia_version" => string(VERSION),
    "architecture" => string(Sys.ARCH),
    "kernel" => "reaction-diffusion-explicit-euler-v1",
    "precision" => "Float32",
    "real_hardware_required" => backend_name != "cpu",
    "github_sha" => get(ENV, "GITHUB_SHA", "local"),
    "hardware_id" => get(
        ENV, "POTTS_BENCHMARK_HARDWARE_ID", "local-$(backend_name)"),
    "driver" => get(ENV, "POTTS_GPU_DRIVER", "runtime-reported"),
    "native_field_source_sha256" =>
        bytes2hex(SHA.sha256(read(source_path))),
    "cases" => cases,
)
open(output_path, "w") do io
    TOML.print(io, result; sorted=true)
end
println("PHASE16_NATIVE_FIELD_RESULT=", output_path)
println("PHASE16_NATIVE_FIELD_QUALIFICATION=", result)
