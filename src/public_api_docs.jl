@doc """
    @rule name phase expression

Construct one closed, typed Level 1 rule declaration. The macro accepts only the documented rule
expression grammar and lowers through the same normalized IR as the typed authoring API.
""" var"@rule"

@doc """
    @rules begin ... end

Construct a `RuleGroup` from a block of `@rule` declarations without introducing a runtime closure
or an alternate compiler path.
""" var"@rules"

@doc """
    @trigger name schedule condition => effect

Construct one typed lifecycle trigger rule using the closed Level 1 trigger grammar.
""" var"@trigger"

@doc "Semantic version of the frozen Level 1 authoring-language contract." AUTHORING_DSL_CONTRACT_VERSION
@doc "Semantic version of the normalized PottsToolkit IR contract." NORMALIZED_IR_CONTRACT_VERSION
@doc "Semantic version of the model semantic-fingerprint contract." SEMANTIC_FINGERPRINT_VERSION
@doc "Semantic version of the execution-fingerprint contract." EXECUTION_FINGERPRINT_VERSION
@doc "Semantic version of the result/evidence schema contract." RESULT_EVIDENCE_SCHEMA_VERSION

@doc "Normalize a valid `PottsModel` into deterministic typed IR or throw `ModelValidationError`." normalize
@doc "Return the structured, deterministic inspection report for a model or normalized model." explain
@doc "Return source and lowering provenance for every normalized declaration." provenance
@doc "Return the resolved and unresolved dependency report for a model." dependencies
@doc "Return the declared scientific and execution capabilities of a model value." capabilities
@doc "Return the stable semantic identity of an authoring declaration." semantic_identity
@doc "Return the versioned, order-independent scientific fingerprint of a model." semantic_fingerprint
@doc "Validate a model without throwing and return all safely discoverable diagnostics." validate
@doc "Compose a model with one or more named fragments through the normalized-IR path." compose
@doc "Lower and validate a model, domain, and layout into a `CorePotts.PottsProblem`." problem

@doc "The paper-core conventional ordered CPM algorithm; inspect `algorithm_guarantees` before use." SequentialCPM
@doc "The paper-core graph-colored parallel CPM scheduler with an independent guarantee profile." CheckerboardSweepCPM
@doc "Run a schedule on every positive MCS boundary." EveryMCS
@doc "Run a schedule once at the specified positive MCS." AtMCS
@doc "Place a registered number of single-site cells using semantic RNG addressing." UniformSiteSeeds
@doc "Place cells by bounded sequential rejection using an explicit lattice shape." SequentialRejectionPlacement
@doc "A lattice-radius placement shape under the domain metric." LatticeBall
@doc "An axis-aligned lattice half-extent placement shape." LatticeBox

@doc "Typed scientific observable requesting per-cell finite volume." CellVolume
@doc "Typed scientific observable requesting per-cell biological type." CellTypeObservable
@doc "Typed scientific observable requesting host logical ownership and generation-aware metadata." LatticeOwnership
@doc "Typed scientific observable requesting per-cell boundary measure." CellBoundaryMeasure
@doc "Typed scientific observable requesting values of one declared cell property." CellPropertyValues
@doc "A deduplicated set of scientific observables used to construct a snapshot policy." ObservationSet
@doc "One generation-aware cell value in an observation frame." CellValue
@doc "The cell-value collection stored for one observable and MCS." CellValues
@doc "One MCS-indexed frame of generation-aware cell values." CellFrame
@doc "A time-ordered series of frames for one scientific observable." CellSeries
@doc "Generation-aware finite-cell metadata accompanying an ownership observation." ObservedCell
@doc "Host logical ownership plus finite-cell and medium metadata." OwnershipValues
@doc "One MCS-indexed spatial observation frame." SpatialFrame
@doc "A time-ordered series of spatial observation frames." SpatialSeries
@doc "Read one requested observable from a saved solution without accessing engine storage fields." observe
@doc "Construct the CorePotts snapshot policy required by an `ObservationSet`." observation_policy
@doc "Join saved scientific observables into generation-aware tabular rows." observation_table
@doc "Return the finite-cell ID of one observed ownership cell." observed_cell_id
@doc "Return the generation of one observed ownership cell." observed_cell_generation
@doc "Return the biological type of one observed ownership cell." observed_cell_type
@doc "Return the spatial dimensions of retained ownership values." ownership_size
@doc "Return the semantic CorePotts owner at one retained ownership site." ownership_owner_at
@doc "Return an immutable tuple of generation-aware retained cells." ownership_cells
@doc "Return the completed MCS associated with a spatial observation frame." spatial_mcs
@doc "Return the visualization-neutral values carried by a spatial observation frame." spatial_values
@doc "Attach an explicit spatial and temporal calibration to a dimensionless solution view." with_units
@doc "Return normalized Monte Carlo step coordinates from a solution or calibrated solution view." mcs

@doc "Evaluate a closed rule expression against its documented scalar/query context." evaluate
@doc "Construct a semantically addressed random draw inside the closed rule grammar." draw
@doc "A Bernoulli draw distribution with an explicit probability expression." Bernoulli
@doc "A bounded continuous uniform draw distribution." Uniform
@doc "A normal draw distribution with explicit mean and scale." Normal
@doc "An isotropic unit-vector draw distribution for the declared dimension." UnitVector
@doc "Count boundary sites for the selected owner query." boundary_site_count
@doc "Measure owner contact edges for the selected spatial query." contact_edge_count
@doc "Measure weighted owner contact for the selected spatial query." contact_measure
@doc "Count distinct neighboring cells matching the selected query filter." neighbor_cell_count
@doc "Sum a declared property over distinct neighboring cells." neighbor_property_sum
@doc "Average a declared property over distinct neighboring cells." neighbor_property_mean

@doc "A lifecycle trigger requiring a declared property to meet or exceed a threshold." PropertyAtLeast
@doc "Declare a cell property as readable but not mutable by model rules." ReadOnlyProperty
@doc "Declare a cell property as mutable through validated lifecycle effects." MutableProperty
@doc "Copy a property value to both products of division." SplitOnDivision
@doc "Apply distinct documented reset values to the two products of division." AsymmetricResetOnDivision
@doc "Initialize a mechanical property at its constitutive mean." ConstitutiveMeanInitialization
@doc "Initialize a mechanical property from its registered stationary distribution." StationaryMechanicalInitialization
@doc "Preserve a mechanical property during exact initialization/import." PreserveMechanicalInitialization
@doc "A positive-yield response used by accepted field and drive declarations." PositiveYield

@doc "Public namespace containing the typed Level 1/2 authoring implementation." Authoring
@doc "Public namespace containing the registered paper reference-model constructors." ReferenceModels
@doc "Per-axis Cartesian boundary declaration used by `CartesianDomain`." AxisBoundary
@doc "A schedule active only on the inclusive registered MCS interval." BetweenMCS
@doc "Mark a property as part of the versioned exact-checkpoint contract." CheckpointedProperty
@doc "Mark a property as recomputable and intentionally absent from exact checkpoints." EphemeralProperty
@doc "Declare a property as required by every compatible compiled model." RequiredProperty
@doc "Declare a property as optional when no component requests it." OptionalProperty
@doc "Declare a property as part of the documented observation/extension surface." PublicProperty
@doc "Declare a property as private to its owning compiled component." PrivateProperty
@doc "Structured report of resolved and unresolved model dependencies." DependencyReport
@doc "Structured exception carrying all model-validation diagnostics." ModelValidationError
@doc "Structured exception carrying all problem-construction diagnostics." ProblemValidationError
@doc "A typed property update whose draw is addressed by the semantic RNG contract." StochasticPropertyUpdate
@doc "Explicitly reject division for a declared property." UnsupportedDivision
@doc "Explicitly reject cell-type transition for a declared property." UnsupportedTransition
@doc "Linear field-response law used by chemotaxis declarations." LinearResponse
@doc "Saturating Michaelis–Menten field-response law." MichaelisMentenResponse
@doc "Piecewise-linear saturating field-response law." SaturationLinearResponse
@doc "Apply a field drive only to extensions of the selected cells." ExtensionChemotaxis
@doc "Apply a field drive only to retractions of the selected cells." RetractionChemotaxis
@doc "Apply equal and opposite extension/retraction field coupling." ReciprocalChemotaxis
