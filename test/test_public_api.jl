@testset "authoritative public API inventory" begin
    expected = Set(Symbol[
        :Potts,
        Symbol("@named"), Symbol("@mtkcompile"), Symbol("@statements"),

        :PottsSystem, :StatementSet, :StatementID, :SourceLocation,
        :UnknownSource, :AbstractPottsStatement, :AbstractPottsEffect,
        :AbstractPottsPhase, :CellKind, :MediumKind, :LatticeDomain,
        :SpatialRelation, :SiteState, :CellState, :MediumState, :ModelState,
        :FieldState, :HistoryState, :RelationshipState, :HamiltonianTerm,
        :ProposalDrive, :ProposalConstraint, :ProposalModifier,
        :SynchronousProcess, :AcceptedCopyProcess, :RelationshipProcess,
        :LifecycleProcess, :Observation, :Protocol,
        :RegisteredStatement, :StatementRegistry, :default_statement_registry,
        :register_statement, :statements, :statement_id, :statement_source,
        :compose, :extend, :flatten, :complete, :iscomplete, :is_scheduled,
        :mtkcompile,

        :AbstractPottsAlgorithm, :SequentialCPM, :CheckerboardSweepCPM,
        :AbstractPottsBackend, :CPUBackend, :MetalBackend, :PottsParameters,
        :LabelledCells, :OwnershipLayout, :CellPlacement, :MediumPlacement,
        :AbstractProceduralPlacement, :RandomSitePlacement, :PottsInitialState,
        :PottsProblem, :PottsIntegrator, :PottsSavedState, :PottsSolution,
        :PottsStats, :init, :solve, :solve!, :step!, :remake, :terminate!,
        :PottsCheckpoint, :checkpoint, :runtime_statistics,

            # The narrow relationship-transaction boundary contributes two names.
        :CellIdentity, :relationship_transaction!,

        :DeclaredReferenceUnits, :ReferenceUnits, :SiteBinding, :CellBinding,
        :ContactBinding, :RelationshipBinding, :anchor_value, :ProposalContext,
        :source_site, :target_site, :source_cell, :target_cell, :source_kind,
        :target_kind, :is_extension, :is_retraction, :new_contact,
        :lost_contact, :cell_volume, :cell_surface, :cell_elongation,
        :cell_center, :unwrapped_center, :distance, :contact_owner_a,
        :contact_owner_b, :contact_kind_a, :contact_kind_b, :contact_measure,
        :contact_edge_count, :boundary_site_count, :neighbor_cells,
        :neighbor_cell_count, :neighbor_property_sum, :neighbor_property_mean,
        :global_interface_measure, :field_value, :field_gradient, :laplacian,
        :occupancy, :linked, :degree, :endpoint_a, :endpoint_b, :edge_payload,
        :lag, :history_value, :gather,

        :AbstractPottsDistribution, :Bernoulli, :Uniform, :Normal,
        :UnitVector, :DrawKey, :draw, :PureRead, :SynchronousAssign,
        :AcceptedCopyEffect, :OrderedBatchEffect, :Proposal, :AcceptedCopy,
        :AfterMCS, :RelationshipCommit, :Lifecycle, :Before, :After,
        :EveryMCS, :AtMCS, :Every, :sites, :cells, :model, :contacts, :edges,
        :incident_edges, :Assign, :Create, :Remove, :Retune, :CreateCell,
        :RemoveCell, :Transition, :Divide, :Retire, :SeedAt, :SeedStencil,
        :CellCentroid, :RandomPlane, :PrincipalAxisPlane,
        :SpecifiedNormalPlane, :CanonicalSide, :StableRandomSide,
        :PreserveKind, :SetKind, :InitializeFrom, :Unsupported, :RetireTo,
        :Preserve, :ResetTo, :Transform, :CopyToDaughters,
        :PreserveParentResetDaughter, :ResetBoth, :SplitConservatively,
        :TransformDaughters, :RedrawDaughters, :RejectWhileLinked,
        :RemoveIncident, :PreserveCompatible, :RemoveIncompatible,
        :RejectIncompatible, :FilterInadmissible, :ErrorOnInadmissible,
        :RejectLifecycleAmbiguity, :StableLifecyclePriority, :RetireAtZero,
        :ForbidExtinction, :Periodic, :Closed, :FrozenBorder, :VonNeumann,
        :Moore, :ClearOnOwnershipChange, :PreserveOnOwnershipChange,
        :Undirected, :RemoveWithEndpoint, :RejectEndpointRetirement,
        :DiscreteFieldEuler, :ExtensionsOnly, :RetractionsOnly,
        :ExtensionsAndRetractions, :Nearest, :Multilinear, :CellCentered,
        :AttemptsPerSite, :Lattice, :Volume, :ContactEnergy, :Elongation,
        :Chemotaxis, :LocalConnectivity, :ActEnergy, :Synchronous, :Sweep,
        :SweepStage, :RelationshipEnergy, :RelationshipConstraint, Symbol("↔"),

        :inspect, :Statements, :Variables, :Effects, :RandomOperations,
        :Schedule, :Capabilities, :Fingerprints, :ParameterSchema,
        :StateSchema, :Observations, :ExternalIO, :ReplayContract,
        :LifecyclePlans, :semantic_fingerprint, :completed_system_fingerprint,
        :scheduled_system_fingerprint,

        :NativeComponent, :ODEComponent, :DAEComponent, :Global, :PerCell,
        :FixedPhysicalTime, :CPMThenComponents, :NativeInput, :NativeOutput,
        :NativeFieldOutput, :MethodOfLinesComponent,
        :NativeOperatingPoint, :NativeSolveProfile, :NativeLogicalState,
        :SerialNativeExecution, :BatchedNativeExecution, :MetalNativeExecution,
        :CouplingEndpointSchema, :native_components,
        :scheduled_native_components, :native_component_path, :native_time_at,
        :native_cadence_stride, :native_due, :native_time_interval,
        :native_state, :native_value, :PreserveNativeInitialization,
        :PreserveNativeEvents, :GlobalNativeLifecycle, :PerCellNativeLifecycle,
        :LateBoundNativeAlgorithm, :StandardNativeCapability,

        :map_symbolics, :statement_kind, :with_source,
        :registered_statement_lowering, :OperationTransfer,
        :LifecycleOperationABI, :operation_transfer,
        :AbstractOperationSourceRequirement, :LatticeRankRequirement,
        :SpatialRelationRequirement, :NamedSpatialRelationRequirement,
        :AbstractFootprintTransferRule, :InheritFootprintRule,
        :ProposalSourceFootprintRule, :ProposalTargetFootprintRule,
        :ProposalSourceTargetFootprintRule, :IterationSiteFootprintRule,
        :OwnerFootprintRule, :ContactFootprintRule,
        :IncidentRelationshipFootprintRule, :AbstractNeighborhoodAnchorRule,
        :OperandNeighborhoodAnchors, :ProposalTargetNeighborhoodAnchor,
        :ProposalSourceTargetNeighborhoodAnchor, :IterationNeighborhoodAnchor,
        :NeighborhoodFootprintRule, :DescriptorSource,
        :DescriptorConstructionContext, :registered_descriptor_payload,
        :registered_workspace_schemas, :registered_tracker_requirements,
        :ResolvedOperationSourceBinding, :OperationTrackerContext,
        :registered_operation_tracker_requirements,
        :is_direct_scalar_tracker_projection, :QualifiedStatementID,
        :QualifiedStatement, :EffectBound, :RandomOperation, :EngineAdmission,
        :SemanticFingerprint, :CompletedSystemFingerprint,
        :ScheduledSystemFingerprint, :PottsCapabilityKey,
        :PottsCapabilityReport, :NativeSourceFingerprint,
        :CompletedNativeComponent, :ScheduledNativeComponent, :native_source,
        :native_family, :native_inputs, :native_outputs, :native_variable,
        :potts_endpoint, :native_value_type, :native_original_system,
        :native_scheduled_system, :native_coupling_endpoints,
        :native_original_fingerprint, :native_scheduled_fingerprint,
        :native_index_provider, :native_problem_constructor,

        :AbstractNativeRuntimeError, :NativeProfileError,
        :NativeCapabilityError, :NativeExecutionError, :NativeSolveFailure,
        :PottsDiagnostic, :PottsValidationError, :PottsLookupError,
        :PottsUnknownIdentityError, :PottsKnownUnsavedError,
        :PottsUnsavedTimeError, :to_dynamic_quantity, :to_unitful_quantity,
    ])

    actual = Set(names(Potts))
    missing = setdiff(expected, actual)
    unexpected = setdiff(actual, expected)
    @test isempty(missing)
    @test isempty(unexpected)

    retired = Set((
        :boundary_measure, :neighbor_count, :neighbor_sum, :neighbor_mean,
        :neighbor_geomean, :EquationStep, :Observe, :Directed,
        :ExplicitEuler, :Heun, :RK4, :ObserveStage, :compile,
        :PottsExecutable, :SequentialEngine, :CheckerboardEngine,
        :TiledCheckerboard, :EquationProcess, :ExplicitDiffusion,
        :CUDABackend, :ROCmBackend,
    ))
    @test isempty(intersect(actual, retired))
    @test all(name -> !isdefined(Potts, name), retired)
end

@testset "export and extension inventories are distinct" begin
    visible_names = names(Potts; all = false, imported = false)
    exported = Set(filter(name -> Base.isexported(Potts, name), visible_names))
    public_names = Set(filter(name -> Base.ispublic(Potts, name), visible_names))
    extension_api = setdiff(public_names, exported)
    @test :PottsSystem in exported
    @test :operation_transfer in extension_api
    @test !(:operation_transfer in exported)
end

@testset "curated public help is attached and truthful" begin
    @test isempty(Docs.undocumented_names(Potts; private = false))
    for binding in (PottsSystem, NativeComponent, NativeSolveProfile)
        @test Docs.doc(binding) !== nothing
    end
    native_component_help = sprint(show, MIME"text/plain"(),
        Docs.doc(NativeComponent))
    solve_profile_help = sprint(show, MIME"text/plain"(),
        Docs.doc(NativeSolveProfile))
    potts_system_help = sprint(show, MIME"text/plain"(), Docs.doc(PottsSystem))
    @test occursin("NativeComponent(source; name, family, time", native_component_help)
    @test occursin("capabilities=StandardNativeCapability()", native_component_help)
    @test occursin("NativeSolveProfile(path, algorithm", solve_profile_help)
    @test occursin("execution=SerialNativeExecution()", solve_profile_help)
    @test occursin("PottsSystem(; name", potts_system_help)
end
