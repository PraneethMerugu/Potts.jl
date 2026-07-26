import ProcessBigraphs: ports, capabilities, semantic_parameters

struct PB0PortLaw <: AbstractProcess
    amount::Int
end
ports(::PB0PortLaw) = (
    InputPort(Int, :input),
    OutputPort(Int, :output; update_law=:add),
)
semantic_parameters(law::PB0PortLaw) = (amount=law.amount,)

struct PB0DeviceLaw <: AbstractProcess end
ports(::PB0DeviceLaw) = (InputPort(Int, :input),)
capabilities(::PB0DeviceLaw) = CapabilitySet((:metal,))

struct PB0Step <: AbstractStep end
ports(::PB0Step) = ()

struct PB0ReplaceStep <: AbstractStep end
ports(::PB0ReplaceStep) =
    (OutputPort(String, :out; update_law=:replace),)

@testset "static composite and residency preflight" begin
    scale = TimeScale(1)
    schema = BranchSchema(x=LeafSchema(Int; default=0, update_law=:add))
    declaration = ProcessDeclaration(
        "increment",
        PB0PortLaw(1),
        FixedSchedule(Duration(1, scale)),
    )
    bindings = (
        PortBinding("increment", :input, path("x")),
        PortBinding("increment", :output, path("x")),
    )
    composite = StaticComposite(schema, Dict(), scale;
        processes=(declaration,), bindings)
    compiled = compile_composite(composite)
    @test length(model_fingerprint(compiled)) == 64
    @test isempty(step_layers(compiled))
    @test isempty(compiled.preflight_report.transfers)

    reversed = StaticComposite(schema, Dict(), scale;
        processes=(declaration,), bindings=reverse(bindings))
    @test model_fingerprint(compile_composite(reversed)) ==
        model_fingerprint(compiled)

    @test_throws ProcessBigraphError compile_composite(StaticComposite(
        schema, Dict(), scale; processes=(declaration,),
        bindings=(PortBinding("increment", :input, path("x")),)))

    gpu_schema = BranchSchema(x=LeafSchema(Int; default=0, residency=:cpu))
    gpu = ProcessDeclaration("gpu", PB0DeviceLaw(),
        FixedSchedule(Duration(1, scale)); domain=:metal)
    hidden = StaticComposite(gpu_schema, Dict(), scale; processes=(gpu,),
        bindings=(PortBinding("gpu", :input, path("x")),))
    @test_throws ProcessBigraphError compile_composite(hidden)
    explicit = StaticComposite(gpu_schema, Dict(), scale; processes=(gpu,),
        bindings=(PortBinding("gpu", :input, path("x");
            transfer=TransferDeclaration(:cpu, :metal; max_bytes=8)),))
    report = preflight(explicit)
    @test length(report.transfers) == 1
    undersized = StaticComposite(gpu_schema, Dict(), scale; processes=(gpu,),
        bindings=(PortBinding("gpu", :input, path("x");
            transfer=TransferDeclaration(:cpu, :metal; max_bytes=1)),))
    @test_throws ProcessBigraphError preflight(undersized)

    a = StepDeclaration("a", PB0Step(); dependencies=("b",))
    b = StepDeclaration("b", PB0Step(); dependencies=("a",))
    @test_throws ProcessBigraphError compile_composite(StaticComposite(
        BranchSchema(), Dict(), scale; steps=(a, b)))

    replace_schema = BranchSchema(
        owner=LeafSchema(String; default="none", update_law=:replace))
    first_replace = StepDeclaration("first", PB0ReplaceStep())
    second_replace = StepDeclaration("second", PB0ReplaceStep();
        dependencies=("first",))
    replace_bindings = (
        PortBinding("first", :out, path("owner")),
        PortBinding("second", :out, path("owner")),
    )
    @test compile_composite(StaticComposite(replace_schema, Dict(), scale;
        steps=(first_replace, second_replace), bindings=replace_bindings)) isa
        CompiledComposite
    concurrent_replace = StepDeclaration("concurrent", PB0ReplaceStep())
    @test_throws ProcessBigraphError compile_composite(StaticComposite(
        replace_schema, Dict(), scale;
        steps=(first_replace, concurrent_replace),
        bindings=(
            PortBinding("first", :out, path("owner")),
            PortBinding("concurrent", :out, path("owner")),
        )))
end
