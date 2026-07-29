function _structural_checkpoint_checksum(
    contract_version,
    ordinal,
    structure,
    epoch_fingerprint,
    identities,
    lineage,
    capacity,
)
    canonical_fingerprint((
        :process_bigraph_structural_checkpoint_v1,
        contract_version,
        ordinal,
        structural_fingerprint(structure),
        epoch_fingerprint,
        identities,
        lineage,
        (capacity.composites, capacity.total_parts),
    ))
end

function structural_checkpoint(epoch::DynamicStructuralEpoch)
    checksum = _structural_checkpoint_checksum(
        epoch.contract_version,
        epoch.ordinal,
        epoch.structure,
        epoch.fingerprint,
        epoch.identities,
        epoch.lineage,
        epoch.capacity,
    )
    StructuralEpochCheckpoint(
        epoch.contract_version,
        epoch.ordinal,
        deepcopy(epoch.structure),
        epoch.fingerprint,
        deepcopy(epoch.identities),
        deepcopy(epoch.lineage),
        epoch.capacity,
        checksum,
    )
end

function restore_structural_checkpoint(
    checkpoint::StructuralEpochCheckpoint,
)
    checkpoint.contract_version == STRUCTURAL_TRANSACTION_VERSION ||
        _fail(:structural_checkpoint_version_mismatch,
            "structural checkpoint uses an incompatible contract version";
            expected=STRUCTURAL_TRANSACTION_VERSION,
            actual=checkpoint.contract_version)
    expected_checksum = _structural_checkpoint_checksum(
        checkpoint.contract_version,
        checkpoint.ordinal,
        checkpoint.structure,
        checkpoint.epoch_fingerprint,
        checkpoint.identities,
        checkpoint.lineage,
        checkpoint.capacity,
    )
    expected_checksum == checkpoint.checksum ||
        _fail(:structural_checkpoint_checksum_mismatch,
            "structural checkpoint checksum does not match its contents";
            expected=expected_checksum, actual=checkpoint.checksum)
    _validate_structure_shape(checkpoint.structure)
    _validate_capacity(checkpoint.structure, checkpoint.capacity)
    expected_fingerprint = _structural_epoch_fingerprint(
        checkpoint.ordinal,
        checkpoint.structure,
        checkpoint.identities,
        checkpoint.lineage,
        checkpoint.capacity,
    )
    expected_fingerprint == checkpoint.epoch_fingerprint ||
        _fail(:structural_checkpoint_fingerprint_mismatch,
            "structural checkpoint epoch fingerprint is invalid";
            expected=expected_fingerprint,
            actual=checkpoint.epoch_fingerprint)
    DynamicStructuralEpoch(
        checkpoint.contract_version,
        checkpoint.ordinal,
        deepcopy(checkpoint.structure),
        checkpoint.epoch_fingerprint,
        deepcopy(checkpoint.identities),
        deepcopy(checkpoint.lineage),
        checkpoint.capacity,
    )
end
