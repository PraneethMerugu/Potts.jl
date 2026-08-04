# Fixed-size lifecycle status values and host-side failure translations.

@enum LifecycleStatusCode::UInt8 begin
    LifecycleStatusSuccess = 0x00
    LifecycleStatusInadmissible = 0x01
    LifecycleStatusConflict = 0x02
    LifecycleStatusCellCapacity = 0x03
    LifecycleStatusRelationshipCapacity = 0x04
    LifecycleStatusStaleGeneration = 0x05
    LifecycleStatusGenerationOverflow = 0x06
    LifecycleStatusEvaluator = 0x07
    LifecycleStatusFootprint = 0x08
    LifecycleStatusInvariant = 0x09
    LifecycleStatusBackend = 0x0a
end

@enum LifecycleStatusDetailCode::UInt16 begin
    LifecycleDetailNone = 0x0000
    LifecycleDetailOwnershipExceedsCellCapacity = 0x0001
    LifecycleDetailCellSiteIndexExceedsLattice = 0x0002
    LifecycleDetailCellSiteIndexMissingOwnedSite = 0x0003
    LifecycleDetailNonfiniteResult = 0x0004
    LifecycleDetailEvaluationError = 0x0005
    LifecycleDetailRequestBoundExceeded = 0x0006
    LifecycleDetailTriggerNotBoolean = 0x0007
    LifecycleDetailPlacementSelectionInvalid = 0x0008
    LifecycleDetailPlacementNotIntegral = 0x0009
    LifecycleDetailPlacementOutOfBounds = 0x000a
    LifecycleDetailPlacementSelectionEmpty = 0x000b
    LifecycleDetailPlacementEmissionBoundExceeded = 0x000c
    LifecycleDetailPlacementBoundExceeded = 0x000d
    LifecycleDetailDuplicatePlacementSite = 0x000e
    LifecycleDetailPlacementSiteUnavailable = 0x000f
    LifecycleDetailEmptySourceCell = 0x0010
    LifecycleDetailPartitionLabelInvalid = 0x0011
    LifecycleDetailPartitionGeometryInvalid = 0x0012
    LifecycleDetailPartitionEmptyDescendant = 0x0013
    LifecycleDetailPartitionParentDisconnected = 0x0014
    LifecycleDetailPartitionDaughterDisconnected = 0x0015
    LifecycleDetailRetireNonempty = 0x0016
    LifecycleDetailUnknownEffect = 0x0017
    LifecycleDetailRelationshipPolicyRejected = 0x0018
    LifecycleDetailUnknownDistribution = 0x0019
    LifecycleDetailSplitFractionOutOfBounds = 0x001a
    LifecycleDetailUnsupportedStatePolicy = 0x001b
    LifecycleDetailTrackerPlanStateMisalignment = 0x001c
    LifecycleDetailActiveOccupancyMismatch = 0x001d
    LifecycleDetailForbiddenExtinction = 0x001e
    LifecycleDetailDivisionPlanMissing = 0x001f
    LifecycleDetailStateValueInvalid = 0x0020
    LifecycleDetailTrackerStorageInvalid = 0x0021
    LifecycleDetailRelationshipIntegrityInvalid = 0x0022
    LifecycleDetailTrackerCommitInvalid = 0x0023
    LifecycleDetailRelationshipCommitInvalid = 0x0024
end

@enum LifecycleExecutionStage::UInt8 begin
    LifecycleStageNone = 0x00
    LifecycleStageIndex = 0x01
    LifecycleStageEmission = 0x02
    LifecycleStagePlanning = 0x03
    LifecycleStageSelection = 0x04
    LifecycleStageStructure = 0x05
    LifecycleStageRelationships = 0x06
    LifecycleStageState = 0x07
    LifecycleStageValidation = 0x08
    LifecycleStagePublication = 0x09
end

"""One fixed-size engine status; host exceptions are derived only at settlement."""
struct LifecycleStatusPayload
    code::LifecycleStatusCode
    mcs::Int32
    stage::LifecycleExecutionStage
    source::Int32
    action_identity::UInt64
    secondary_source::Int32
    anchor::Int32
    detail::LifecycleStatusDetailCode
    required::Int32
    available::Int32
    maximum::Int32
end

LifecycleStatusPayload() = LifecycleStatusPayload(
    LifecycleStatusSuccess,
    Int32(0),
    LifecycleStageNone,
    Int32(0),
    UInt64(0),
    Int32(0),
    Int32(0),
    LifecycleDetailNone,
    Int32(0),
    Int32(0),
    Int32(0),
)

LifecycleStatusPayload(
    code::LifecycleStatusCode,
    source::Int32,
    secondary_source::Int32,
    anchor::Int32,
    detail::LifecycleStatusDetailCode,
    required::Int32,
    available::Int32,
    maximum::Int32,
) = LifecycleStatusPayload(
    code,
    Int32(0),
    LifecycleStageNone,
    source,
    UInt64(0),
    secondary_source,
    anchor,
    detail,
    required,
    available,
    maximum,
)

abstract type AbstractLifecycleFailure <: Exception end

struct LifecycleInadmissibilityFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleConflictFailure <: AbstractLifecycleFailure
    first_source::Int32
    second_source::Int32
    anchor::Int32
end
struct CellCapacityFailure <: AbstractLifecycleFailure
    max_cells::Int32
    requested::Int32
    available::Int32
end
struct RelationshipCapacityFailure <: AbstractLifecycleFailure
    relationship_slot::Int32
end
struct StaleGenerationFailure <: AbstractLifecycleFailure
    cell::Int32
end
struct GenerationOverflowFailure <: AbstractLifecycleFailure
    cell::Int32
end
struct LifecycleEvaluatorFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleFootprintFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleInvariantFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleBackendFailure{E} <: AbstractLifecycleFailure
    cause::E
    first_possible_mcs::Int
    last_possible_mcs::Int
end

LifecycleBackendFailure(cause) = LifecycleBackendFailure(cause, 0, 0)

function Base.showerror(io::IO, failure::CellCapacityFailure)
    print(
        io,
        "cell capacity exhausted: transaction requested ",
        failure.requested,
        " new identities with ",
        failure.available,
        " available (max_cells=",
        failure.max_cells,
        ")",
    )
end

function Base.showerror(io::IO, failure::AbstractLifecycleFailure)
    print(io, nameof(typeof(failure)), "(")
    for (index, field) in enumerate(fieldnames(typeof(failure)))
        index > 1 && print(io, ", ")
        print(io, field, "=", repr(getfield(failure, field)))
    end
    print(io, ")")
end
