using Test
import KernelAbstractions
import LocalMath

const LMDP = LocalMath

@testset "semantic descriptors have compact mathematical displays" begin
    cells = LMDP.Space((4, 5))
    values = LMDP.Field(cells, Float32)
    fixed = LMDP.FixedRelation(cells => cells; degree = 4)
    keys = LMDP.Field(cells, NTuple{2,Int32})
    indexed = LMDP.IndexRelation(keys => cells; optional = true)
    affine = LMDP.AffineRelation(cells => cells;
        offsets = ((-1, 0), (1, 0)))
    periodic = LMDP.BoundaryRelation(
        affine, LMDP.PeriodicBoundary((true, false)))
    records = LMDP.Collection(Tuple{Int32,Float32}, 12)

    space_text = sprint(show, cells)
    field_text = sprint(show, values)
    fixed_text = sprint(show, fixed)
    indexed_text = sprint(show, indexed)
    periodic_text = sprint(show, periodic)
    collection_text = sprint(show, records)
    detailed_relation = sprint(show, MIME("text/plain"), fixed)

    @test occursin("extent=(4, 5)", space_text)
    @test occursin("Field(Float32", field_text)
    @test occursin("FixedRelation", fixed_text)
    @test occursin("degree=4", fixed_text)
    @test occursin("storage=required", fixed_text)
    @test occursin("IndexRelation", indexed_text)
    @test occursin("optional=true", indexed_text)
    @test occursin("BoundaryRelation", periodic_text)
    @test occursin("periodic", periodic_text)
    @test occursin("capacity=12", collection_text)
    @test occursin("domain:", detailed_relation)
    @test occursin("codomain:", detailed_relation)
    @test !occursin("_FixedRelation", fixed_text)
    @test !occursin("_IndexSpaceKind", space_text)
end

@testset "law and prepared displays derive from canonical authorities" begin
    backend = KernelAbstractions.CPU()
    cells = LMDP.Space(3)
    input = LMDP.Field(cells, Float32)
    output = LMDP.Field(cells, Float32)
    law = LMDP.@localmath i ∈ cells begin
        output[i] = input[i]
    end
    prepared = LMDP.@prepare (law; backend) begin
        input = Float32[1, 2, 3]
        output = zeros(Float32, 3)
    end
    before = LMDP.inspect(prepared).realized.state
    semantic_source = LMDP.inspect(law).stages[1].source
    law_text = sprint(show, MIME("text/plain"), law)
    plan_text = sprint(show, MIME("text/plain"), prepared.plan)
    prepared_text = sprint(show, MIME("text/plain"), prepared)
    after = LMDP.inspect(prepared).realized.state

    @test occursin("descriptors:", law_text)
    @test occursin("stages:", law_text)
    @test occursin("domain:", law_text)
    @test occursin("input_via_identity_required", law_text)
    @test occursin("output_unique", law_text)
    @test occursin("conflicts=reject_multiple", law_text)
    @test !occursin("read_1", law_text)
    @test !occursin("port_1", law_text)
    @test length(findall("field:", law_text)) == 2
    @test occursin("planning:", plan_text)
    @test occursin("workspace_bytes=", plan_text)
    @test occursin("storage ownership:", prepared_text)
    @test occursin("physical_segments=", prepared_text)
    @test before == after
    @test semantic_source.kind == :index
    @test semantic_source.structure === nothing
    @test !occursin("_IndexSpaceKind", sprint(show, semantic_source))
end

@testset "binding diagnostics report complete requirements" begin
    backend = KernelAbstractions.CPU()
    cells = LMDP.Space(3)
    input = LMDP.Field(cells, Float32)
    output = LMDP.Field(cells, Float32)
    law = LMDP.@localmath i ∈ cells begin
        output[i] = input[i]
    end
    error = try
        LMDP.bind(law; backend)
        nothing
    catch caught
        caught
    end
    @test error isa LMDP.LocalMathValidationError
    @test error.contract == :binding_coverage
    @test length(error.expected) == 2
    @test map(fact -> fact.role, error.expected) == (:field, :field)
    @test all(fact -> fact.requirement.shape == (3,), error.expected)
    @test all(fact -> fact.origin !== nothing, error.expected)
    @test all(fact -> !isempty(fact.uses), error.expected)
    @test error.actual.relations == ()
    rendered = sprint(showerror, error)
    @test occursin("missing for 2 descriptors", rendered)
    @test length(findall("Field(Float32", rendered)) >= 2

    edges = LMDP.Space(3)
    nodes = LMDP.Space(4)
    values = LMDP.Field(nodes, Float32)
    residual = LMDP.Field(nodes, Float32)
    incidence = LMDP.FixedRelation(edges => nodes; degree = 2)
    relation_law = LMDP.@localmath edge ∈ edges begin
        local_values = values[incidence(edge)]
        residual[incidence(edge)] += (local_values[1], local_values[2])
    end
    malformed = try
        LMDP.prepare(relation_law,
            values => zeros(Float32, 4),
            residual => zeros(Float32, 4),
            incidence => zeros(Int32, 1, 3);
            backend)
        nothing
    catch caught
        caught
    end
    @test malformed isa LMDP.LocalMathValidationError
    @test malformed.contract == :fixed_relation_lanes
    @test malformed.expected.minimum_lanes == 2
    @test malformed.actual.shape == (1, 3)
    @test occursin("lane-major", malformed.hint)
end
