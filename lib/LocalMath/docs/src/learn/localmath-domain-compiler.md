# [Writing a LocalMath domain compiler](@id localmath-domain-compiler)

A domain compiler decides what scientific information an operation requires.
LocalMath expresses that decision as typed bounded reads and publication laws.
The compiler should emit ordinary public values directly—never a parallel
requirements IR or runtime builder.

This complete Core-shaped example materializes dynamic keys, gathers through
`IndexRelation`, and publishes the result. The first stage is written with the
same mathematical front end a compiler could construct explicitly; the second
uses the qualified SPI to make its positional contract visible.

```@example domain_compiler
using LocalMath, KernelAbstractions

struct GatherSelected end
@inline (::GatherSelected)(item::Int32, reads, parameters) =
    (selected_value = LocalMath.UniqueValue(
        something(getfield(reads, 1)[1].value)),)

backend = KernelAbstractions.CPU()
items, cells = Space(4), Space(5)
source_key = Field(items, Int32)
derived_key = Field(items, Int32)
cell_value = Field(cells, Float32)
result = Field(items, Float32)

key_law = @localmath item ∈ items begin
    derived_key[item] = source_key[item]
end

selection = IndexRelation(derived_key => cells)
identity = IdentityRelation(items)
gather_stage = LocalMath.Stage(
    items,
    (selected=LocalMath.Access(cell_value, selection),),
    (LocalMath.Publication(
        result, identity, LocalMath.Unique(Float32);
        value=:selected_value,
        origin=LocalMath.SourceOrigin(@__FILE__, @__LINE__)),),
    LocalMath.Evaluator(GatherSelected()),
    LocalMath.Control(),
    LocalMath.SourceOrigin(@__FILE__, @__LINE__; label=:gather_selected),
)
law = LocalMath.sequence(key_law, LocalLaw(gather_stage))

prepared = prepare(
    law,
    source_key => Int32[5,2,4,1],
    derived_key => LocalMath.Allocate(undef),
    cell_value => Float32[10,20,30,40,50],
    result => LocalMath.Allocate(undef);
    backend,
)
wait(execute!(prepared))
@assert LocalMath.storage(prepared, result) == Float32[50,20,40,10]

semantic = LocalMath.inspect(prepared; level=:numerics)
compiler = LocalMath.compilation_report(prepared)
@assert length(semantic.stages) == 2
@assert !isempty(compiler.callable_admissions)
nothing
```

The durable ownership split is:

1. the domain compiler interprets requirements and preserves scientific order;
2. Fields and Relations state bounded spatial meaning;
3. the evaluator receives only gathered values and scalar parameters;
4. publications state assignment, conflict, empty, and ordering semantics; and
5. `bind`, `plan`, and `prepare` validate and realize the one
   KernelAbstractions executor.

When lowering fails, retain the source origin from the domain operation. An
unsupported footprint should be rejected cold with that provenance rather
than captured in an opaque evaluator or guessed at runtime.
