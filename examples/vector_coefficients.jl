module VectorCoefficientsExample

    using Potts, Symbolics, ModelingToolkitBase, StaticArrays, SymbolicIndexingInterface

    """One parent-owned coefficient vector, read through a component import."""
    function problem()
        @parameters coefficients[1:2] = [2.0, 3.0]
        @variables incoming[1:2] direction[1:2] amount
        response = PottsSystem(
            name = :response,
            statements = StatementSet(
                (
                    ModelState(direction; initial = SVector(0.0, 0.0)),
                    ModelState(amount; initial = 0.0),
                    Synchronous(:refresh_direction, Assign(direction, incoming)),
                    Synchronous(:accumulate_amount, Assign(amount, amount + incoming[1] + 2incoming[2])),
                )
            ),
            unknowns = (direction, amount), inputs = (incoming,),
            imports = (incoming => ComponentReference((), coefficients),),
        )
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :vector_coefficients,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            parameters = (coefficients,), systems = (response,),
        )
        initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
        return (; problem = PottsProblem(source, initial, (0, 3); seed = 71), coefficients)
    end

    function run_example(; algorithm = SequentialCPM())
        model = problem()
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        step!(integrator)
        setp(integrator, model.coefficients[2])(integrator, 5.0)
        step!(integrator)
        return integrator
    end

end

if abspath(PROGRAM_FILE) == @__FILE__
    result = VectorCoefficientsExample.run_example()
    println((direction = result.u[:response₊direction], amount = result.u[:response₊amount]))
end
