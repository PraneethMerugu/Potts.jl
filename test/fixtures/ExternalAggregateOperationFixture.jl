module ExternalAggregateOperationFixture

using Potts
using Symbolics
import CorePotts
import Potts: operation_transfer

const VERSION = v"1.0.0"

function external_response end
Symbolics.@register_symbolic external_response(value)::Real

function captured_response end
Symbolics.@register_symbolic captured_response(value)::Real

double_value(value) = value + value

struct CapturedResponseCallable
    coefficients::Vector{Float64}
end

(operation::CapturedResponseCallable)(value) = only(operation.coefficients) * value

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:fixture_external_response}, version::VersionNumber,
    )
    version == VERSION || throw(ArgumentError(
        "unsupported external aggregate operation version $version"
    ))
    return double_value
end

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:fixture_captured_response}, version::VersionNumber,
    )
    version == VERSION || throw(ArgumentError(
        "unsupported captured aggregate operation version $version"
    ))
    return CapturedResponseCallable([2.0])
end

function _transfer(identity; callable_identity)
    return Potts.OperationTransfer(
        identity;
        schema_version = VERSION,
        serialization_identity =
            "external-aggregate-operation:" * String(identity) * ":v1",
        arity = 1,
        result_rule = :preserve_numeric,
        unit_rule = :unary,
        operand_rule = :numeric,
        footprint_rule = Potts.InheritFootprintRule(),
        purity = :pure,
        totality = :total,
        cpu = true,
        gpu = true,
        allowed_roles = (:process,),
        allowed_phases = (:AfterMCS,),
        required_context = :any,
        owner = :ExternalAggregateOperationFixture,
        callable_identity,
    )
end

operation_transfer(::typeof(external_response), ::Int) = _transfer(
    :fixture_external_response;
    callable_identity = "ExternalAggregateOperationFixture.double_value:v1",
)

operation_transfer(::typeof(captured_response), ::Int) = _transfer(
    :fixture_captured_response;
    callable_identity = "ExternalAggregateOperationFixture.CapturedResponseCallable:v1",
)

function model(; operation = external_response)
    @variables signal response
    lattice = LatticeDomain(
        :extension_space;
        shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(), max_cells = 3,
    )
    kind = CellKind(:extension_cell; extinction = ForbidExtinction())
    medium = MediumKind(:extension_medium)
    declarations = scoped(sites(lattice), :extension_sites) do site
        consumers = scoped(cells(kind), :extension_cells) do cell
            maintained = aggregate(operation(signal); over = site, by = cell)
            StatementSet((
                CellState(response; initial = 0.0),
                Synchronous(:publish_extension, Assign(response, maintained)),
            ))
        end
        StatementSet((FieldState(signal; initial = 0.0), consumers...))
    end
    system = PottsSystem(
        name = :external_aggregate_operation,
        statements = StatementSet((
            lattice, kind, medium, declarations...,
            ProposalConstraint(:fixed_extension_ownership, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = (signal, response),
    )
    labels = Int32[1 2; 1 0]
    values = Float32[1 2; 3 4]
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [kind, kind], medium),
        values = (signal => values,),
    )
    return (; problem = PottsProblem(system, initial, (0, 2); seed = 41), signal)
end

end
