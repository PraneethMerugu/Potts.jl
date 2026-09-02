# Immutable settled-boundary observation evaluators owned by Potts.

abstract type AbstractCompiledObservationEvaluator end

struct StateExportObservationEvaluator{H <: CorePotts.CompilerSPI.StateHandle} <:
        AbstractCompiledObservationEvaluator
    handle::H
end

struct OccupiedSitesObservationEvaluator <:
        AbstractCompiledObservationEvaluator
    kind::Int16
end

struct RelationshipDegreeObservationEvaluator <:
        AbstractCompiledObservationEvaluator
    relationship_slot::Int32
    endpoint::Int32
end

function _evaluate_observation(
        evaluator::StateExportObservationEvaluator,
        runtime,
    )
    return copy(CorePotts.CompilerSPI.state_block(
        runtime.descriptor_state, evaluator.handle
    ).values)
end

function _evaluate_observation(
        evaluator::OccupiedSitesObservationEvaluator,
        runtime,
    )
    total = 0
    for owner in CorePotts.CompilerSPI.ownership_state(runtime)
        CorePotts.CompilerSPI.owner_kind(runtime, owner) == evaluator.kind &&
            (total += 1)
    end
    return total
end

function _evaluate_observation(
        evaluator::RelationshipDegreeObservationEvaluator,
        runtime,
    )
    return CorePotts.CompilerSPI.relationship_degree(
        runtime, evaluator.relationship_slot, evaluator.endpoint
    )
end
