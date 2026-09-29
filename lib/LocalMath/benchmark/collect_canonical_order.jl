using Statistics
import KernelAbstractions
include("../test/fixtures/collect_canonical_order_contracts.jl")

# Run in a normal package environment, or test/metal's environment with --metal.
# Preparation and warmup are excluded; these timings are not pass/fail thresholds.
backend = if "--metal" in ARGS
    @eval import Metal
    Metal.functional() || error("the selected Metal backend is not functional")
    Metal.allowscalar(false)
    Metal.MetalBackend()
else
    KernelAbstractions.CPU()
end
function benchmark_collect_order(backend, count)
    (; prepared, storage) = _prepare_canonical_order_fixture(backend, count)
    submit() = wait(
        LocalMath.execute!(
            prepared;
            parameters = (; enabled = true, odd_only = false, duplicate = false, tied_keys = false)
        )
    )
    for _ in 1:3
        submit()
    end
    samples = map(1:9) do _
        elapsed = @elapsed for _ in 1:10
            submit()
        end
        elapsed / 10
    end
    records = collect(LocalMath.Adapt.adapt(Array, storage.records))
    @assert Array(storage.count) == Int32[count]
    @assert map(record -> record.slot, records) == Int32.(count:-1:1)
    return println(
        (;
            count, minimum_seconds = minimum(samples),
            median_seconds = median(samples), maximum_seconds = maximum(samples),
        )
    )
end

println("LocalMath=", pathof(LocalMath), " backend=", typeof(backend))
foreach(count -> benchmark_collect_order(backend, count), (256, 4096))
