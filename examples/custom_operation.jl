module CustomOperation

using Potts
using ModelingToolkitBase: @parameters
using SciMLBase
using Symbolics
import CorePotts

# Generic Julia helpers execute during authoring on symbolic arguments. They
# need no registration when their constituent operations are already supported.
response(value) = value / (1 + abs(value))

# An opaque operation intentionally retains one named call in the symbolic graph.
# Its concrete execution still uses the same ordinary numerical implementation.
function opaque_response end
Symbolics.@register_symbolic opaque_response(value)::Real

Potts.operation_transfer(::typeof(opaque_response), ::Int) = Potts.OperationTransfer(
    :tutorial_response;
    schema_version = v"1.0.0",
    serialization_identity = "custom-operation-response:v1",
    arity = 1,
    result_rule = :real,
    unit_rule = :dimensionless,
    operand_rule = :numeric,
    footprint_rule = Potts.InheritFootprintRule(),
    allowed_roles = (:constraint,),
    allowed_phases = (:Proposal,),
    owner = :CustomOperation,
    callable_identity = "CustomOperation.response:v1",
    gpu = false,
)

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:tutorial_response}, version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError("unsupported response version $version"))
    return response
end

"""Execute a CPU proposal constraint using the opaque or ordinary helper."""
function run_custom_operation(; operation = opaque_response, seed = 0x7531)
    @parameters gain = 1.0
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :custom_operation,
        statements = (
            @statements begin
                Lattice((2, 2); boundary = Periodic(), relations = (proposal = VonNeumann(),))
                cell
                medium
                ProposalConstraint(:response_guard, operation(gain) < 0)
                Protocol(Sweep(; temperature = 1.0); name = :main)
            end
        ),
        parameters = [gain],
    )
    labels = Int32[1 0; 0 1]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
    )
    problem = PottsProblem(source, initial, (0, 1); seed)
    solution = solve(
        problem, SequentialCPM(); backend = CPUBackend(), scalar_type = Float64,
    )
    # Every proposed neighbor has a different owner. The positive runtime gain
    # makes every response fail the constraint, exercising its actual evaluator.
    @assert solution.retcode == SciMLBase.ReturnCode.Success
    @assert solution.stats.constraint_rejections == 4
    @assert last(solution).ownership == labels
    return (; problem, solution)
end

end
