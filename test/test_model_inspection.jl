@testset "model authoring capability inspection" begin
    medium = PottsToolkit.Medium(:inspection_medium)
    cell = PottsToolkit.CellType(:inspection_cell)
    volume = PottsToolkit.Volume(cell => (target = 4, strength = 2.0f0))
    model = PottsToolkit.PottsModel(medium, cell, volume)

    report = PottsToolkit.capabilities(model)
    @test Base.isvalid(report)
    @test report.overall.dimensions == (2, 3)
    @test report.overall.portable
    @test only(report.declarations).identity == PottsToolkit.semantic_identity(volume)
    @test PottsToolkit.provenance(model) ==
          PottsToolkit.provenance(PottsToolkit.normalize(model))
    rendered = sprint(show, MIME("text/plain"), report)
    @test occursin("PottsToolkit model capabilities", rendered)
    @test !occursin("Compiler", rendered)

    field = PottsToolkit.PrescribedField(
        :inspection_field, zeros(Float32, 3, 3))
    field_report = PottsToolkit.capabilities(
        PottsToolkit.PottsModel(medium, cell, field))
    @test field_report.overall.dimensions == (2,)

    role = PottsToolkit.CellRole(:required_cells)
    fragment = PottsToolkit.ModelFragment(
        :unbound_inspection; requires = (role,))
    invalid_report = PottsToolkit.capabilities(
        PottsToolkit.PottsModel(medium, cell, fragment))
    @test !Base.isvalid(invalid_report)
    @test isempty(invalid_report.overall.dimensions)
    @test any(item -> item.code === :unresolved_fragment_role,
        invalid_report.diagnostics)

    valid_display = sprint(show, MIME("text/plain"), model)
    @test occursin("PottsToolkit normalized model", valid_display)
    @test !occursin("_LoweredComponents", valid_display)
    invalid_display = sprint(show, MIME("text/plain"),
        PottsToolkit.PottsModel(medium, cell, fragment))
    @test occursin("unresolved_fragment_role", invalid_display)

    age = PottsToolkit.CellProperty(:inspection_age, cell;
        initial = 0.0f0, division = PottsToolkit.CloneOnDivision(),
        transition = PottsToolkit.PreserveOnTransition())
    phase = PottsToolkit.Phase(:inspection_phase)
    rule = PottsToolkit.@rule phase = phase age(owner) = age(owner) + 1.0f0
    rule_display = sprint(show, MIME("text/plain"), rule)
    @test occursin("target:     inspection_age(owner)", rule_display)
    @test occursin("reads:      inspection_age", rule_display)
    @test !occursin("ScalarCall{", rule_display)

    trigger = PottsToolkit.@trigger inspection_ready(owner) = age(owner) >= 2.0f0
    trigger_display = sprint(show, MIME("text/plain"), trigger)
    @test occursin("PottsToolkit trigger inspection_ready", trigger_display)
    @test occursin("reads:      inspection_age", trigger_display)
end
