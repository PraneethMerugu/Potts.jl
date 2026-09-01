# [LocalMath scientific recipes](@id localmath-recipes)

These modest examples execute during the documentation build. The larger
scientific witnesses use the same public builders and compare against
independent numerical oracles.

## 1. Periodic and interior stencils

```@example recipe_stencil
using LocalMath, KernelAbstractions
backend = KernelAbstractions.CPU()
cells = Space(6)
u = Field(cells, Float32)
periodic_result = Field(cells, Float32)
interior_result = Field(cells, Float32)

periodic_law = @localmath i ∈ periodic(cells) begin
    periodic_result[i] = u[i - 1] + u[i + 1]
end
interior_law = @localmath i ∈ interior(cells, 1) begin
    interior_result[i] = u[i - 1] + u[i + 1]
end
values = Float32[1, 2, 3, 4, 5, 6]
periodic_prepared = @prepare (periodic_law; backend) begin
    u = values
    periodic_result = allocate(0f0)
end
interior_prepared = @prepare (interior_law; backend) begin
    u = values
    interior_result = allocate(0f0)
end
wait(execute!(periodic_prepared)); wait(execute!(interior_prepared))
@assert LocalMath.storage(periodic_prepared, periodic_result) == Float32[8,4,6,8,10,6]
@assert LocalMath.storage(interior_prepared, interior_result) == Float32[0,4,6,8,10,0]
nothing
```

Periodic publication is total. Interior publication is partial, so its output
has an explicit initial value.

## 2. Matrix-free finite-element scatter

```@example recipe_fem
using LocalMath, KernelAbstractions
backend = KernelAbstractions.CPU()
elements, nodes = Space(2), Space(5)
nodal = Field(nodes, Float32)
residual = Field(nodes, Float32)
incidence = FixedRelation(elements => nodes; degree=3)
law = @localmath e ∈ elements begin
    x = nodal[incidence(e)]
    residual[incidence(e)] += (x[1], 2f0*x[2], 3f0*x[3])
end
endpoints = Int32[1 3; 2 4; 3 5]
prepared = @prepare (law; backend) begin
    nodal = Float32[1,2,3,4,5]
    residual = zeros(Float32, 5)
    incidence = endpoints
end
wait(execute!(prepared))
@assert LocalMath.storage(prepared, residual) == Float32[1,4,12,8,15]
nothing
```

The deterministic `+=` publication owns conflict ordering; there is no assembled
global matrix.

## 3. Deterministic z-buffer resolution

```@example recipe_resolve
using LocalMath, KernelAbstractions
backend = KernelAbstractions.CPU()
fragments, pixels = Space(4), Space(2)
depth = Field(fragments, Int32); color = Field(fragments, UInt32)
tie = Field(fragments, UInt32); covered = Field(fragments, Bool)
output = Field(pixels, UInt32)
pixel = FixedRelation(fragments => pixels; degree=1)
law = @localmath f ∈ fragments begin
    output[pixel(f)] = resolve_to(;
        score=depth[f], tie=tie[f], payload=color[f],
        lower=Int32(-10), upper=Int32(10), onempty=UInt32(0),
        when=covered[f])
end
prepared = @prepare (law; backend) begin
    depth = Int32[-2,-2,1,0]
    color = UInt32[0x11,0x22,0x33,0x44]
    tie = UInt32[9,3,1,2]
    covered = Bool[true,true,true,false]
    output = fill(UInt32(0xff), 2)
    pixel = reshape(Int32[1,1,2,2], 1, 4)
end
wait(execute!(prepared))
@assert LocalMath.storage(prepared, output) == UInt32[0x22,0x33]
nothing
```

Rank selects the smallest depth and the explicit tie selects the smallest
identity among equal depths.

## 4. Bounded grouped collection and consumption

```@example recipe_collect
using LocalMath, KernelAbstractions
@inline function sum_records(records)
    total = Int32(0)
    for record in records
        total += record[2]
    end
    total
end
backend = KernelAbstractions.CPU()
particles, cells = Space(4), Space(2)
cell_key = Field(particles, Int32); mass = Field(particles, Int32)
records = Collection(Tuple{Int32,Int32}, 4)
cell_mass = Field(cells, Int32)
law = @localmath begin
    @stage group(p ∈ particles) begin
        records[p] = bounded_collect((cell_key[p], mass[p]);
            maximum=1, group=cell_key[p], groups=2)
    end
    @stage consume(c ∈ cells) begin
        local_records = bounded(records[c]; maximum=3)
        cell_mass[c] = sum_records(local_records)
    end
end
prepared = @prepare (law; backend) begin
    cell_key = Int32[1,2,1,1]
    mass = Int32[2,5,7,3]
    records = allocate()
    cell_mass = allocate(undef)
end
wait(execute!(prepared))
@assert LocalMath.storage(prepared, cell_mass) == Int32[12,5]
nothing
```

The total capacity, per-source emission width, group count, and consumer bound
are distinct explicit contracts.

## 5. Ordered RSA recurrence

```@example recipe_ordered
using LocalMath, KernelAbstractions
backend = KernelAbstractions.CPU()
events, sites = Space(3), Space(4)
first_site = Field(events, Int32); second_site = Field(events, Int32)
label = Field(events, Int32); ordinal = Field(events, Int32)
identity = Field(events, UInt32); accepted_initial = Field(events, Int32)
accepted = Field(events, Int32); occupancy_initial = Field(sites, Int32)
occupancy = Field(sites, Int32)
law = @localmath event ∈ events begin
    first = first_site[event]; second = second_site[event]
    value = label[event]
    @ordered (
        by=(ordinal[event], identity[event]),
        state=(occupancy => occupancy_initial,
               accepted => accepted_initial),
    ) begin
        admitted = occupancy[first] == 0 && occupancy[second] == 0
        if admitted
            occupancy[(first, second)] = (value, value)
        end
        accepted[event] = Int32(admitted)
    end
end
prepared = @prepare (law; backend) begin
    first_site = Int32[2,1,3]; second_site = Int32[3,2,4]
    label = Int32[2,1,3]; ordinal = Int32[2,1,3]
    identity = UInt32[20,10,30]
    accepted_initial = zeros(Int32, 3); accepted = allocate(Int32(0))
    occupancy_initial = zeros(Int32, 4); occupancy = allocate(Int32(0))
end
wait(execute!(prepared))
@assert LocalMath.storage(prepared, occupancy) == Int32[1,1,3,3]
@assert LocalMath.storage(prepared, accepted) == Int32[0,1,1]
nothing
```

State reads observe the accumulated canonical prefix, not a snapshot. The
production witness also proves that distinction against a sequential oracle.

For larger D2Q9, LSM, deposition, graph, DEM, FEM, Potts, PGS, and
stoichiometry cases, run `test/localmath_witnesses/runtests.jl` with the
repository Julia environment.
