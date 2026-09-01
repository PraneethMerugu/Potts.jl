# Structural validation shared by admitted lowerings. These helpers validate
# representation and bounded kernel-ABI facts only; output-family semantics
# remain with the lowering that owns them.

const _VALIDATION_STATUS_FIELDS = 6
const _VALIDATION_FAILURE_CLASS = 1
const _VALIDATION_CONTEXT_INDEX = 2
const _VALIDATION_PRIMARY_RECORD = 3
const _VALIDATION_SECONDARY_RECORD = 4
const _VALIDATION_WITNESS_BITS = 5
const _VALIDATION_STAGE_INDEX = 6

struct _ValidatedPublicationStatus{D, H, C}
    device::D
    host::H
    context::C
    port::Symbol
    stage::Int
end

"""One stage-qualified view of the sole program-level validation buffer."""
struct _ProgramValidationTarget{D}
    device::D
    stage::Int32
end
Adapt.@adapt_structure _ProgramValidationTarget

@inline _validation_encode(value::UInt32) = value
@inline _validation_encode(value::UInt8) = UInt32(value)
@inline _validation_encode(value::Int32) = reinterpret(UInt32, value)
@inline _validation_decode_int32(value::UInt32) = reinterpret(Int32, value)

@inline function _clear_validation_status!(status, lease_index::Integer)
    @inbounds for field in 1:_VALIDATION_STATUS_FIELDS
        status[field, lease_index] = UInt32(0)
    end
    return nothing
end

@inline function _store_program_validation_status!(
        target::_ProgramValidationTarget,
        lease_index::Integer,
        failure_class,
        context_index,
        primary_record,
        secondary_record,
        witness_bits,
    )
    status = target.device
    # Stages execute in semantic order on one provider tail.  Preserve the first
    # failure as the sole diagnostic authority; later closed stages cannot
    # replace its scientific provenance.
    if @inbounds status[_VALIDATION_FAILURE_CLASS, lease_index] == UInt32(0)
        _store_validation_status!(status, lease_index, failure_class,
            context_index, primary_record, secondary_record, witness_bits)
        @inbounds status[_VALIDATION_STAGE_INDEX, lease_index] =
            reinterpret(UInt32, target.stage)
    end
    return nothing
end

@inline function _store_validation_status!(
        status,
        lease_index::Integer,
        failure_class,
        context_index,
        primary_record,
        secondary_record,
        witness_bits,
    )
    @inbounds begin
        status[_VALIDATION_FAILURE_CLASS, lease_index] =
            _validation_encode(failure_class)
        status[_VALIDATION_CONTEXT_INDEX, lease_index] =
            _validation_encode(context_index)
        status[_VALIDATION_PRIMARY_RECORD, lease_index] =
            _validation_encode(primary_record)
        status[_VALIDATION_SECONDARY_RECORD, lease_index] =
            _validation_encode(secondary_record)
        status[_VALIDATION_WITNESS_BITS, lease_index] =
            _validation_encode(witness_bits)
    end
    return nothing
end

@inline _validation_status_word(status::_ValidatedPublicationStatus, row, lease_index) =
    @inbounds status.host[row, lease_index]

_is_publication_validation_error(error) = error isa LocalMathValidationError &&
    error.contract in (
        :runtime_stage_validation,
        :runtime_key_validation,
        :runtime_compacted_validation,
        :runtime_ordered_fold_validation,
    )

_prepared_validation_statuses(prepared) = ()
@inline function _prepared_validation_statuses(prepared::PreparedPlan)
    # Every contextual Stage status views the same program-level device/host
    # buffer. Settlement and success gating therefore need one representative,
    # not a flattened tuple whose type grows with total program length.
    return (first(prepared.runtime.launches).status,)
end

@inline _prepared_validation_status_groups(prepared::PreparedPlan) =
    (map(launch -> launch.status, prepared.runtime.launches),)

function _transfer_validation_statuses!(statuses::Tuple)
    isempty(statuses) && return nothing
    # Every Stage status is a contextual view of this same program-level
    # buffer. One host-visible copy is therefore the complete settlement.
    status = first(statuses)
    copyto!(status.host, status.device)
    return nothing
end

function _prepared_validation_error_at(prepared, lease_index::Int32)
    for statuses in _prepared_validation_status_groups(prepared)
        for status in statuses
            error = _validated_publication_error(status, Int(lease_index))
            error === nothing || return error
        end
    end
    return nothing
end

function _exact_host_int(value, purpose; stage::Symbol = :plan)
    try
        return Int(value)
    catch
        throw(LocalMathValidationError(
            "$purpose must be exactly representable as Int";
            stage,
            contract = :exact_host_integer,
            expected = Int,
            actual = value,
        ))
    end
end

function _bounded_count(
        value,
        purpose;
        positive::Bool = false,
        terminal::Bool = false,
        stage::Symbol = :plan,
    )
    count = _exact_host_int(value, purpose; stage)
    valid = positive ? count > 0 : count >= 0
    valid || throw(LocalMathValidationError(
        "$purpose must be $(positive ? "positive" : "nonnegative")";
        stage,
        contract = :bounded_count,
        expected = positive ? :positive : :nonnegative,
        actual = count,
    ))
    return _checked_int32_count(
        count,
        purpose;
        terminal,
        stage,
    )
end

# One authority for the bounded record domain shared by fixed-route and
# runtime-keyed candidate storage. `int32_index=true` admits ordinary Int32
# record indices; `terminal=true` additionally reserves the terminal sentinel.
function _candidate_record_capacity(
        item_count::Int,
        maximum_emissions::Int,
        purpose::Symbol;
        int32_index::Bool = false,
        terminal::Bool = false,
    )
    capacity = _checked_int_product(
        item_count,
        maximum_emissions,
        purpose,
    )
    (int32_index || terminal) && _checked_int32_count(
        capacity,
        purpose;
        terminal,
    )
    return capacity
end
