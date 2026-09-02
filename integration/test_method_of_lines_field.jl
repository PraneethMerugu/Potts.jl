using DomainSets
using MethodOfLines
using OrdinaryDiffEqTsit5

@testset "MethodOfLines checked field adapter" begin
    @parameters mol_t mol_x mol_y
    @variables mol_u(..) mol_field(mol_t)
    Dt = ModelingToolkit.Differential(mol_t)
    Dxx = ModelingToolkit.Differential(mol_x)^2
    Dyy = ModelingToolkit.Differential(mol_y)^2
    equations = [
        Dt(mol_u(mol_t, mol_x, mol_y)) ~ 0.1 * (
            Dxx(mol_u(mol_t, mol_x, mol_y)) +
            Dyy(mol_u(mol_t, mol_x, mol_y))
        ),
    ]
    boundaries = [
        mol_u(0, mol_x, mol_y) ~ 1 + mol_x + mol_y,
        mol_u(mol_t, 0, mol_y) ~ mol_u(mol_t, 1, mol_y),
        mol_u(mol_t, mol_x, 0) ~ mol_u(mol_t, mol_x, 1),
    ]
    domains = [
        mol_t ∈ Interval(0.0, 1.0),
        mol_x ∈ Interval(0.0, 1.0),
        mol_y ∈ Interval(0.0, 1.0),
    ]
    @named pde = ModelingToolkit.PDESystem(
        equations,
        boundaries,
        domains,
        [mol_t, mol_x, mol_y],
        [mol_u(mol_t, mol_x, mol_y)],
    )
    discretization = MOLFiniteDifference(
        [mol_x => 4, mol_y => 4], mol_t; grid_align = center_align
    )
    field = FieldState(
        mol_field; name = :mol_field, initial = 0.0, stencil = :field_stencil
    )
    component = MethodOfLinesComponent(
        pde,
        discretization,
        mol_u(mol_t, mol_x, mol_y),
        field;
        spatial = (mol_x, mol_y),
        name = :mol_component,
        time = FixedPhysicalTime(0.0, 0.125),
    )
    @test getfield(component, :capabilities) isa
        Potts._MethodOfLinesNativeCapability
    generic_field_component = NativeComponent(
        Potts.native_source(component);
        name = :generic_field_component,
        family = ODEComponent(),
        scope = Global(),
        time = FixedPhysicalTime(0.0, 0.125),
        outputs = Potts.native_outputs(component),
    )
    @test getfield(generic_field_component, :capabilities) isa
        StandardNativeCapability
    cell = CellKind(:mol_cell; extinction = RetireAtZero())
    medium = MediumKind(:mol_medium)
    source = PottsSystem(
        name = :mol_potts,
        statements = StatementSet((
            Lattice(
                (4, 4);
                boundary = Periodic(),
                relations = (field_stencil = VonNeumann(),),
            ),
            cell,
            medium,
            field,
            ProposalConstraint(:mol_frozen, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [mol_field],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:mol_potts, :mol_component)
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    generic_path = (:generic_field_potts, :generic_field_component)
    generic_system = mtkcompile(PottsSystem(
        name = :generic_field_potts,
        statements = StatementSet((
            Lattice(
                (4, 4);
                boundary = Periodic(),
                relations = (field_stencil = VonNeumann(),),
            ),
            cell,
            medium,
            field,
            ProposalConstraint(:generic_field_frozen, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [mol_field],
        native_components = (generic_field_component,),
    ))
    generic_problem = PottsProblem(
        generic_system,
        PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            native = (NativeOperatingPoint(generic_path),),
        ),
        (0, 1);
        seed = 0x54f,
    )
    generic_profile = NativeSolveProfile(
        generic_path,
        Tsit5();
        deterministic = true,
        adaptive = false,
        dt = 0.015625,
    )
    generic_integrator = init(
        generic_problem,
        SequentialCPM();
        native_profiles = (generic_profile,),
    )
    @test size(generic_integrator.u.mol_field) == (4, 4)
    @test generic_integrator.capability_report.status ===
        Potts.CorePotts.BackendSPI.Supported
    @test !generic_integrator.capability_report.exact_replay
    problem = PottsProblem(
        scheduled,
        PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            native = (NativeOperatingPoint(path),),
        ),
        (0, 2);
        seed = 0x54e,
    )
    profile = NativeSolveProfile(
        path,
        Tsit5();
        deterministic = true,
        adaptive = false,
        dt = 0.015625,
    )
    integrator = init(problem, SequentialCPM(); native_profiles = (profile,))
    @test size(integrator.u.mol_field) == (4, 4)
    @test integrator.u.mol_field != zeros(4, 4)
    step!(integrator)
    variables = Potts.native_variables(
        only(Potts.native_outputs(component))
    )
    expected = reshape([
        native_value(integrator, path, variable) for variable in variables
    ], 4, 4)
    @test integrator.u.mol_field ≈ expected
    @test_throws ArgumentError checkpoint(integrator)

    discrete = MethodOfLines.get_discrete(pde, discretization)
    @test_throws ArgumentError NativeFieldOutput(
        discrete[mol_u(mol_t, mol_x, mol_y)],
        field;
        coordinates = (0.0:1.0:3.0, 0.0:1.0:2.0),
        value_type = Float64,
    )
end
