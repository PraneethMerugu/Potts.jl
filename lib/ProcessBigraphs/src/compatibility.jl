"""
Compatibility aliases retained for the ProcessBigraphs 0.5 internal-beta line.

Living code, tests, and documentation use the domain-oriented names on the right-hand side.
The aliases preserve the observable spellings introduced by the historical implementation
milestones without creating a second implementation.
"""

const PHASE16_CHECKPOINT_VERSION = COUPLED_CHECKPOINT_FORMAT_VERSION
const PHASE16_CHECKPOINT_SCHEMA = COUPLED_CHECKPOINT_SCHEMA
const LogicalCheckpointV3 = CoupledLogicalCheckpoint
const RestoredPhase16Checkpoint = RestoredLogicalCheckpoint
const phase16_checkpoint = capture_logical_checkpoint
const decode_phase16_checkpoint = decode_logical_checkpoint
const restore_phase16_checkpoint = restore_logical_checkpoint
