@doc "Closed Phase 13 taxonomy of algorithm scientific-guarantee labels." ALGORITHM_GUARANTEE_TAXONOMY
@doc "Semantic RNG contract version embedded in replay and evidence identities." RNG_CONTRACT_VERSION
@doc "PottsToolkit Level 1 authoring-language contract version." AUTHORING_DSL_CONTRACT_VERSION
@doc "Normalized authoring-IR contract version." NORMALIZED_IR_CONTRACT_VERSION
@doc "Canonical exact-checkpoint schema version." CHECKPOINT_SCHEMA_VERSION
@doc "Semantic model-fingerprint contract version." SEMANTIC_FINGERPRINT_VERSION
@doc "Compiled execution-fingerprint contract version." EXECUTION_FINGERPRINT_VERSION
@doc "Phase 13 result/evidence schema contract version." PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION
@doc "SequentialCPM algorithm semantic-contract version." SEQUENTIAL_ALGORITHM_CONTRACT_VERSION
@doc "CheckerboardSweepCPM scheduler semantic-contract version." CHECKERBOARD_SCHEDULER_CONTRACT_VERSION
@doc "LotteryCPM algorithm semantic-contract version." LOTTERY_ALGORITHM_CONTRACT_VERSION
@doc "Experimental tiled-checkerboard contract version; this identity is not stable API." TILED_CHECKERBOARD_EXPERIMENTAL_CONTRACT_VERSION
@doc "The immutable aggregate of all current scientific contract identities." SCIENTIFIC_CONTRACT_VERSIONS

@doc "Open family of acceptance laws; implementations define `acceptance_probability`." AbstractAcceptanceLaw
@doc "Open family of backend capability values used by compatibility preflight." AbstractBackendCapability
@doc "Open storage adapter family for canonical checkpoints." AbstractCheckpointStore
@doc "Open family of scientific initial-layout declarations." AbstractInitialLayout
@doc "Open family of normalized-MCS schedules." AbstractMCSSchedule
@doc "Open family of lifecycle targets selected before trigger evaluation." AbstractLifecycleTarget
@doc "Open family of pure lifecycle trigger predicates." AbstractLifecycleTrigger
@doc "Open family of typed lifecycle effects." AbstractLifecycleEffect
@doc "Open family of owner filters for spatial scientific queries." AbstractOwnerFilter
@doc "Open family of snapshot policies controlling explicit observation boundaries." AbstractSnapshotPolicy
@doc "Open family of scientific topology descriptions independent of compiled storage." AbstractTopology

@doc "Canonical checkpoint containing logical state, semantic identities, RNG state, and integrity data." CanonicalCheckpoint
@doc "In-memory adapter for canonical checkpoint values." MemoryCheckpointStore
@doc "HDF5-backed canonical checkpoint adapter loaded through the package extension." HDF5CheckpointStore
@doc "Zarr-backed canonical checkpoint adapter loaded through the package extension." ZarrCheckpointStore
@doc "Compatibility report separating execution preflight from algorithm scientific guarantees." PottsCompatibilityReport
@doc "Structured report of compilation choices, requirements, and fingerprints." PottsCompilationReport
@doc "SciML-compatible mutable integrator for a compiled Potts problem." PottsIntegrator
@doc "SciML-compatible Potts solution with explicit saved-state and observable policies." PottsSolution
@doc "Execution counters and accepted-attempt accounting attached to a solution." PottsStats
@doc "Stable symbolic handle for a model parameter." PottsParameterHandle
@doc "Stable symbolic handle for a requested scientific observable." PottsObservableHandle
@doc "Host-owned snapshot policy that materializes complete logical states." HostSnapshotPolicy
@doc "Snapshot policy that materializes only a declared set of scientific observables." ObservableSnapshotPolicy
@doc "Return the exact completed-MCS coordinate carried by a saved solution entry." snapshot_mcs
@doc "Return the declared storage residency of a saved solution entry." snapshot_residency
@doc "Return a complete logical host state retained explicitly by `HostSnapshotPolicy`." snapshot_state
@doc "Return the public spatial geometry carried by a Potts problem." problem_geometry
@doc "Return the problem that produced a Potts solution." solution_problem
@doc "Conventional Metropolis acceptance law." ConventionalMetropolis
@doc "Metropolis–Hastings acceptance law with explicit forward/reverse proposal probabilities." MetropolisHastings
@doc "Exact-continuation compatibility profile for checkpoint restoration." ExactContinuationProfile

@doc "Return the typed inputs consumed by an acceptance law for one proposal." acceptance_inputs
@doc "Return the acceptance probability for a law and validated acceptance inputs." acceptance_probability
@doc "Return active finite-cell identifiers in deterministic slot order." active_cell_ids
@doc "Return the finite-cell capacity declared by a logical state." capacity
@doc "Capture a synchronized canonical checkpoint at the current completed-MCS boundary." capture_checkpoint
@doc "Return the biological type of a generation-aware active cell." cell_type
@doc "Return the canonical logical state embedded in a checkpoint." checkpoint_logical_state
@doc "Return the compatibility report for a problem, algorithm, and backend." compatibility_report
@doc "Return the compilation report for a compiled problem or integrator." compilation_report
@doc "Return the stable identity and semantic version of a scientific component." component_identity
@doc "Return the semantic RNG streams owned by a scientific component." component_rng_streams
@doc "Return the logical Cartesian domain boundaries in axis order." domain_boundaries
@doc "Return the logical Cartesian domain dimensions in axis order." domain_dimensions
@doc "Return the logical Cartesian lattice spacing in axis order." domain_spacing
@doc "Return the finite volume of an active cell from authoritative logical state." finite_volume
@doc "Return the current generation of a cell slot." generation
@doc "Import a compatible checkpoint as a new run under the declared import profile." import_checkpoint
@doc "Return whether a generation-aware cell identifier is currently active." is_active
@doc "Return logical lattice dimensions without exposing compiled storage." lattice_size
@doc "Return the number of active finite cells." n_cells
@doc "Return the allocated finite-cell slot count." nslots
@doc "Return the registered scientific observable names for a model." observable_symbols
@doc "Return the semantic owner at a logical lattice site." owner_at
@doc "Return the portable numerical policy for the selected scalar type." portable_numerical_policy
@doc "Return the ordered semantic property keys in a schema or logical state." property_keys
@doc "Return one generation-aware cell property value." property_value
@doc "Return the storage-independent logical values of a declared property." property_values
@doc "Read and validate a canonical checkpoint from a checkpoint store." read_checkpoint
@doc "Return the production floating-point type selected by a numerical policy." real_type
@doc "Restore exact continuation after validating all frozen checkpoint identities." restore_checkpoint
@doc "Return the semantic version of an RNG contract value." rng_contract_version
@doc "Return the versioned semantic fingerprint of the complete scientific model." scientific_model_fingerprint
@doc "Mutate one declared cell property through the validated logical-state interface." set_cell_property!
@doc "Update one declared problem parameter through its stable symbolic handle." set_parameter!
@doc "Write a canonical checkpoint through a selected checkpoint store." write_checkpoint!

@doc "Return the typed observable requirements declared by a scientific component." required_observables
@doc "Return the typed property requirements declared by a scientific component." required_properties
@doc "Return the typed spatial-relation requirements declared by a scientific component." required_relations
@doc "Return the public validation report for an algorithm component." validate_algorithm_component
@doc "Return the public validation report for a hard-constraint component." validate_constraint_component
@doc "Return the public validation report for a drive component." validate_drive_component
@doc "Return the public validation report for an energy component." validate_energy_component
@doc "Return the public validation report for an event component." validate_event_component
@doc "Return the public validation report for a kinetic-modifier component." validate_kinetic_modifier_component
@doc "Return the public validation report for a mechanical component." validate_mechanical_component
@doc "Return the public validation report for a proposal-law component." validate_proposal_component
@doc "Return the public validation report for a topology component." validate_topology_component
@doc "Return the public validation report for a tracker component." validate_tracker_component
@doc "Run the reusable downstream-style algorithm conformance helper." test_algorithm
@doc "Run the reusable downstream-style event conformance helper." test_event
@doc "Run the reusable downstream-style topology conformance helper." test_topology
@doc "Run the reusable downstream-style tracker conformance helper." test_tracker

@doc "Typed property-addition lifecycle effect." AddCellProperty
@doc "Owner filter accepting every active finite cell." AnyFiniteCell
@doc "Semantic-RNG Bernoulli lifecycle trigger." BernoulliCellTrigger
@doc "Owner filter selecting active cells with one biological type." CellTypeFilter
@doc "Constitutive-mean property initialization policy." ConstitutiveMeanInitialization
@doc "Fixed-value boundary condition for a scientific field." DirichletFieldBoundary
@doc "Typed cell-division lifecycle effect." DivideCell
@doc "Chemotaxis mode applying work only to extensions." ExtensionChemotaxis
@doc "Typed effect that begins the registered shrink-death process." InitiateShrinkDeath
@doc "Linear scientific field-response law." LinearResponse
@doc "Major-axis cell-division geometry." MajorAxisDivision
@doc "Saturating Michaelis–Menten scientific field-response law." MichaelisMentenResponse
@doc "Minor-axis cell-division geometry." MinorAxisDivision
@doc "Multilinear interpolation policy for cell-centered fields." MultilinearFieldInterpolation
@doc "Mutable scientific property policy." MutableProperty
@doc "Nearest-neighbor interpolation policy for cell-centered fields." NearestFieldInterpolation
@doc "Periodic boundary condition for a scientific field." PeriodicFieldBoundary
@doc "Preserve a mechanical property during exact initialization or import." PreserveMechanicalInitialization
@doc "Lifecycle trigger requiring a property to reach a threshold." PropertyAtLeast
@doc "Random-orientation cell-division geometry." RandomOrientationDivision
@doc "Read-only scientific property policy." ReadOnlyProperty
@doc "Chemotaxis mode coupling extensions and retractions reciprocally." ReciprocalChemotaxis
@doc "Typed effect that immediately retires a cell into medium." RemoveCellImmediately
@doc "Chemotaxis mode applying work only to retractions." RetractionChemotaxis
@doc "Piecewise-linear saturating scientific field-response law." SaturationLinearResponse
@doc "Stationary-distribution mechanical initialization policy." StationaryMechanicalInitialization
@doc "Typed biological cell-transition lifecycle effect." TransitionCell
@doc "Explicit-vector cell-division geometry." VectorDivision
@doc "Zero-normal-derivative boundary condition for a scientific field." ZeroNeumannFieldBoundary
@doc "Count boundary sites selected by a scientific owner query." boundary_site_count
@doc "Return the typed capabilities declared by a scientific value." capabilities
@doc "Count contact edges selected by a scientific spatial query." contact_edge_count
@doc "Measure weighted contact selected by a scientific spatial query." contact_measure
@doc "Return the collision-checked RNG address owned by a downstream extension." extension_rng_address
@doc "Count distinct neighboring cells selected by an owner query." neighbor_cell_count
@doc "Average a property over distinct neighboring cells selected by a query." neighbor_property_mean
@doc "Sum a property over distinct neighboring cells selected by a query." neighbor_property_sum
@doc "Return whether a hard constraint admits one proposal." proposal_constraint_allowed
@doc "Return nonconservative log-rate work contributed by one drive." proposal_drive_log_bias
@doc "Return non-Hamiltonian mechanical work contributed to one proposal." proposal_mechanical_work
@doc "Return the transition-rate modifier contribution for one proposal." proposal_modifier_contribution
@doc "Return the structured validation and capability report for a component collection." scientific_components_report
