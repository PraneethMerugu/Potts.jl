module ExternalSurfaceOperationFixture

using PottsToolkit
using Symbolics
import CorePotts
import PottsToolkit: operation_transfer
import PottsToolkit: registered_operation_tracker_requirements

const VERSION = v"1.0.0"

function external_cell_surface end
Symbolics.@register_symbolic external_cell_surface(cell)::Real

struct ExternalCellSurfaceCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::ExternalCellSurfaceCallable,
    ::Type{CorePotts.AbstractHamiltonianEvaluationContext},
) = true

operation_transfer(::typeof(external_cell_surface), ::Int) =
    PottsToolkit.OperationTransfer(
        :fixture_external_cell_surface,
        VERSION,
        "external-cell-surface-v1",
        1:1,
        :real,
        :dimensionless,
        :pure,
        :total,
        PottsToolkit.OwnerFootprintRule(),
        true,
        true,
        (:fixture_external_cell_surface_tracker,),
        :any,
        (:hamiltonian,),
        (:Proposal,),
        :hamiltonian,
        :ExternalSurfaceOperationFixture,
        "ExternalSurfaceOperationFixture.ExternalCellSurfaceCallable",
        (PottsToolkit.NamedSpatialRelationRequirement(:surface),),
    )

CorePotts.operation_callable(
    ::Val{:fixture_external_cell_surface}, version::VersionNumber
) = version == VERSION ? ExternalCellSurfaceCallable() :
    throw(ArgumentError("unsupported external surface version $version"))

@inline CorePotts.qualified_tracker_operation_call(
    ::ExternalCellSurfaceCallable,
    arguments,
    context,
    quantity::Val,
    source_handle::Int32,
) = CorePotts.tracker_operation_value(
    context,
    quantity,
    source_handle,
    Int32(only(arguments)),
)

function registered_operation_tracker_requirements(
        ::Val{:fixture_external_cell_surface_tracker},
        context::PottsToolkit.OperationTrackerContext,
        ::Type,
        ::Tuple,
    )
    relations = filter(
        binding -> binding.kind === :SpatialRelation,
        context.bindings,
    )
    relation = only(relations)
    return (CorePotts.CellSurfaceTracker(
        relation.handle,
        relation.metadata.maximum_neighbors,
    ),)
end

end
