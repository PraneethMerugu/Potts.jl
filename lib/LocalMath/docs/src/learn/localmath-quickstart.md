# [LocalMath in ten minutes](@id localmath-quickstart)

LocalMath keeps the numerical equation, storage association, and backend
choice explicit. This complete CPU example performs one periodic finite
difference update.

```@example localmath_quickstart
using LocalMath
using KernelAbstractions

backend = KernelAbstractions.CPU()
cells = Space(8)
u = Field(cells, Float32)
laplacian = Field(cells, Float32)

law = @localmath i ∈ periodic(cells) begin
    laplacian[i] = u[i - 1] - 2f0 * u[i] + u[i + 1]
end

host_u = Float32[1, 2, 4, 7, 11, 16, 22, 29]
prepared = @prepare (law; backend) begin
    u = host_u
    laplacian = allocate(0f0)
end

receipt = execute!(prepared)
wait(receipt)
result = LocalMath.storage(prepared, laplacian)
@assert result == Float32[29, 1, 1, 1, 1, 1, 1, -35]
nothing
```

`Space` and `Field` are mathematical descriptors, not arrays. The setup block
associates `u` with caller-owned storage and asks LocalMath to allocate the
output on the explicit backend. Initialization remains explicit. Although this
periodic map is mathematically total, its publication is relation-routed rather
than identity-routed, so the conservative definite-initialization proof asks
for an initial value.

An interior stencil also publishes only the interior. Its boundary
destinations remain untouched, so an uninitialized output is unsafe. Supply a
filled or copied output instead:

```julia
laplacian = allocate(0f0)       # exact fill value
# or
laplacian = allocate(host_seed) # exact-shape copy
```

Inspecting is cold and non-mutating:

```@example localmath_quickstart
facts = LocalMath.inspect(prepared)
@assert facts.lifecycle == :PreparedPlan
@assert length(facts.stages) == 1
@assert facts.planning.base_provider_launch_count >= 1
nothing
```

For the full relation vocabulary, continue to [LocalMath relations and
storage](@ref localmath-relations). For conflict laws and recurrence, see
[LocalMath scientific recipes](@ref localmath-recipes).
