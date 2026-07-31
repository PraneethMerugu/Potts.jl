module CorePotts

using LinearAlgebra: Symmetric, eigen
using SHA

const RNG_CONTRACT_VERSION = v"1.0.0"

include("rng/semantic.jl")
include("program/v1.jl")

public AbstractProgramEngine, SequentialProgramEngine, CheckerboardProgramEngine
public CPUProgramBackend, CompiledScalar, compiled_scalar_value
public AbstractProgramExpression, ProgramLiteral, ProgramScalar, ProgramCall
public ProgramDraw, CompiledProposalTerm
public CompiledActivityPlan, CompiledFieldPlan, CompiledHistoryPlan
public CompiledElongationPlan
public CompiledRelationshipPlan, CompiledPottsProgram
public AbstractProgramObservation, OccupiedSitesObservation
public FieldStateObservation, RelationshipDegreeObservation
public ProgramRelationshipState, ProgramRelationshipRequest
public CreateRelationshipRequest, RemoveRelationshipRequest
public RetuneRelationshipRequest, apply_relationship_requests!
public initialize_program_relationships
public ProgramInitialState, ProgramSnapshot, ProgramRuntime
public initialize_program, program_snapshot, advance_mcs!
public initialization_bounded
public update_program_parameters!, program_observations
public program_execution_report, program_capability_report
public ProgramCheckpoint, program_checkpoint, restore_program_checkpoint

end
