"""
    LocalMath

Backend-portable execution of bounded local operations under centrally
validated topology, storage, conflict, visibility, and determinism contracts.
Domain packages retain physics, clocks, RNG, solver, and commit semantics.
"""
module LocalMath

# Ordinary scientific authoring surface.
export Space, Field, Relation, Collection, LocalLaw
export IdentityRelation, AffineRelation, FixedRelation, ProductRelation
export compose
export BoundaryRelation, RuntimeRelation, MaskedRelation, SelectedRelation
export IndexRelation, InverseRelation, PackedRelation
export StrictBoundary, PeriodicBoundary, ExteriorBoundary, MaskedBoundary
export GhostBoundary
export @localmath, @prepare
export prepare, execute!, waitall, workspace_requirements

# Advanced compiler, storage, inspection, and receipt vocabulary remains
# available by qualification without entering ordinary authoring namespaces.
public Plan, PreparedPlan, ExecutionReceipt, LocalMathValidationError
public bind, plan, Allocate, Temporary, MutableRelationStorage, storage, inspect
public compilation_report
public execution_contract, lowering_identity
public Stage, Publication, Access, Control, SourceOrigin, Parameter, ParameterSchema
public Evaluator, FieldPublication, CollectionPublication, FoldPublication
public PublicationValue
public CollectionAccess, CollectionCount, BoundedGroup, SourcePositionAccess
public sequence, allocate_workspace, submission_capacity, ispending, success_gate
public one_group, group_by, source_order, canonical_by
public persistent_source_position
public CompactedStorage, BoundedGroupView
public Unique, Reduce, Resolve, Collect, OrderedFold
public TotalCoverage, PartialCoverage, UnreachableEmpty, PreserveEmpty, FillEmpty
public IdentitySeed, ExistingSeed, CanonicalLeftFold, RelaxedAtomic
public ArgMin, ArgMax, CanonicalSourceLaneTie, TieMin, TieMax
public RejectOverflow, EmptyCollection
public FoldComponent, InitializedState, BoundedWrites, FoldStep
public initialized_state
public BoundedFold, bounded_fold, Where
public RejectInvalid, SkipInvalid, FillInvalid, RejectEmpty
public RelaxedAssociative
public BoundedFoldOutcome, evaluate_bounded
public UniqueValue, ConditionalUniqueValue, RoutedUniqueValue
public ConditionalRoutedUniqueValue, Contribution, RoutedContribution
public ResolutionValue, RoutedResolutionValue, CollectedValue
public GroupedCollectedValue, FoldValue
import Adapt
import Atomix
import KernelAbstractions
import StaticArrays
import StructArrays
import UUIDs
using KernelAbstractions: @index, @kernel, @localmem, @synchronize

include("model.jl")
include("spatial_model.jl")
include("ordering.jl")
include("compacted.jl")
include("ordered_fold.jl")
include("stage_model.jl")
include("binding_protocol.jl")
include("authoring.jl")
include("bounded_fold.jl")
include("preparation.jl")
include("execution.jl")
include("inspection.jl")

include("execution/mechanism_support.jl")
include("execution/validation_support.jl")
include("execution/relation_views.jl")
include("structural_binding.jl")
include("bound_law.jl")
include("stage_planning.jl")
include("execution/relation_preparation.jl")
include("execution/stage_preparation.jl")
include("execution/bounded_fold_support.jl")
include("execution/workspace_support.jl")
include("execution/candidate_grouping.jl")
include("execution/candidate_stage.jl")
include("execution/relation_receipts.jl")
include("execution/reduce_stage.jl")
include("execution/resolve_stage.jl")
include("execution/ordered_fold_stage.jl")
include("execution/fixed_lane_support.jl")
include("execution/collect_physical_support.jl")
include("execution/collect_stage.jl")
include("execution/stage_program_kernelabstractions.jl")
include("execution/stage_program.jl")

end
