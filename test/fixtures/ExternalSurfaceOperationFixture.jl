module ExternalSurfaceOperationFixture

using Potts
using Symbolics
import CorePotts
import Potts: operation_transfer
import Potts: registered_operation_tracker_requirements
import Potts: is_direct_scalar_tracker_projection

const CompilerSPI = CorePotts.CompilerSPI

const VERSION = v"1.0.0"

function external_cell_surface end
Symbolics.@register_symbolic external_cell_surface(cell)::Real
function external_cell_surface_alt end
Symbolics.@register_symbolic external_cell_surface_alt(cell)::Real
is_direct_scalar_tracker_projection(::typeof(external_cell_surface)) = true
is_direct_scalar_tracker_projection(::typeof(external_cell_surface_alt)) = true

struct ExternalCellSurfaceCallable <: CompilerSPI.AbstractContextualOperation end

CompilerSPI.operation_context_supported(
    ::ExternalCellSurfaceCallable,
    ::Type{CompilerSPI.AbstractHamiltonianEvaluationContext},
) = true

operation_transfer(::typeof(external_cell_surface), ::Int) =
    Potts.OperationTransfer(
        :fixture_external_cell_surface,
        VERSION,
        "external-cell-surface-v1",
        1:1,
        :real,
        :dimensionless,
        :pure,
        :total,
        Potts.OwnerFootprintRule(),
        true,
        true,
        (:fixture_external_cell_surface_tracker,),
        :any,
        (:hamiltonian,),
        (:Proposal,),
        :hamiltonian,
        :ExternalSurfaceOperationFixture,
        "ExternalSurfaceOperationFixture.ExternalCellSurfaceCallable",
        (Potts.NamedSpatialRelationRequirement(:surface),),
    )

operation_transfer(::typeof(external_cell_surface_alt), ::Int) =
    Potts.OperationTransfer(
        :fixture_external_cell_surface_alt,
        VERSION,
        "external-cell-surface-alt-v1",
        1:1,
        :real,
        :dimensionless,
        :pure,
        :total,
        Potts.OwnerFootprintRule(),
        true,
        true,
        (:fixture_external_cell_surface_alt_tracker,),
        :any,
        (:hamiltonian,),
        (:Proposal,),
        :hamiltonian,
        :ExternalSurfaceOperationFixture,
        "ExternalSurfaceOperationFixture.ExternalCellSurfaceCallable",
        (Potts.NamedSpatialRelationRequirement(:surface_alt),),
    )

CompilerSPI.operation_callable(
    ::Val{:fixture_external_cell_surface}, version::VersionNumber
) = version == VERSION ? ExternalCellSurfaceCallable() :
    throw(ArgumentError("unsupported external surface version $version"))
CompilerSPI.operation_callable(
    ::Val{:fixture_external_cell_surface_alt}, version::VersionNumber
) = version == VERSION ? ExternalCellSurfaceCallable() :
    throw(ArgumentError("unsupported alternate external surface version $version"))

@inline CompilerSPI.qualified_tracker_operation_call(
    ::ExternalCellSurfaceCallable,
    arguments,
    context,
    quantity::Val,
    source_handle::Int32,
) = CompilerSPI.tracker_operation_value(
    context,
    quantity,
    source_handle,
    Int32(only(arguments)),
)

function registered_operation_tracker_requirements(
        ::Union{
            Val{:fixture_external_cell_surface_tracker},
            Val{:fixture_external_cell_surface_alt_tracker},
        },
        context::Potts.OperationTrackerContext,
        ::Type,
        ::Tuple,
    )
    relations = filter(
        binding -> binding.kind === :SpatialRelation,
        context.bindings,
    )
    relation = only(relations)
    return (CompilerSPI.CellSurfaceTracker(
        relation.handle,
        relation.metadata.maximum_neighbors,
    ),)
end

end
