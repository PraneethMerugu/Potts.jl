module Wortel2021

using ...Authoring
import CorePotts
import ProcessBigraphs
import SciMLBase

export Profile, Model, profile, canonical_profile, reduced_profile
export model, problem, composite, observation_plan, initial_labels
export semantic_manifest, run

const SEMANTIC_VERSION = v"1.0.0"
const SOURCE_DOI = "10.1371/journal.pone.0255151"

"""
Named, source-bounded execution profile for the Wortel 2021 Act-CPM case.

The profile records the scientific and execution claim separately. `:canonical`
retains the frozen qualification extent; `:reduced_cpu` is the bounded
documentation profile and is not a Figure 2 reproduction.
"""
struct Profile
    identity::Symbol
    dimensions::NTuple{2,Int}
    cell_side::Int
    maximum_activity::Float32
    activity_strength::Float32
    volume_strength::Float32
    temperature::Float32
    observation_every::Int
    mcs::Int
    seed::UInt64
    backend_claim::Symbol
    source_trace::NamedTuple
    deviations::Tuple
    expected_observations::Tuple
    scientific_nonclaims::Tuple
end

function Profile(identity::Symbol, dimensions::NTuple{2,<:Integer};
        cell_side::Integer,
        maximum_activity::Real=10.0f0,
        activity_strength::Real=20.0f0,
        volume_strength::Real=1.0f0,
        temperature::Real=20.0f0,
        observation_every::Integer=5,
        mcs::Integer=5,
        seed::Integer=0x7068617365313401,
        backend_claim::Symbol=:cpu,
        deviations::Tuple=(),
        scientific_nonclaims::Tuple=(
            :no_figure_2_reproduction,
            :no_parameter_ensemble_claim,
            :no_source_author_endorsement,
        ))
    dims = (Int(dimensions[1]), Int(dimensions[2]))
    all(>(0), dims) || throw(ArgumentError(
        "Wortel profile dimensions must be positive"))
    0 < cell_side < minimum(dims) || throw(ArgumentError(
        "Wortel cell side must fit the profile domain"))
    observation_every > 0 ||
        throw(ArgumentError("Wortel observation cadence must be positive"))
    mcs > 0 || throw(ArgumentError("Wortel runtime bound must be positive"))
    0 <= seed <= typemax(UInt64) ||
        throw(ArgumentError("Wortel seed must fit UInt64"))
    scalars = Float32.(
        (maximum_activity, activity_strength, volume_strength, temperature))
    all(isfinite, scalars) && all(>(0), scalars) ||
        throw(ArgumentError(
            "Wortel activity, volume, and temperature values must be finite and positive"))
    source_trace = (
        doi=SOURCE_DOI,
        qualified_mechanism=:act_cpm_geometric_activity,
        frozen_oracle="phase14-wortel-gpu-native-qualification-v1",
        semantic_model_version=string(SEMANTIC_VERSION),
    )
    return Profile(
        identity,
        dims,
        Int(cell_side),
        scalars...,
        Int(observation_every),
        Int(mcs),
        UInt64(seed),
        backend_claim,
        source_trace,
        deviations,
        (:activity_summary, :mcs_report, :logical_state),
        scientific_nonclaims,
    )
end

canonical_profile() = Profile(
    :canonical,
    (128, 128);
    cell_side=8,
    mcs=5,
    backend_claim=:qualified_cpu_metal_rocm,
)

reduced_profile() = Profile(
    :reduced_cpu,
    (24, 24);
    cell_side=4,
    observation_every=2,
    mcs=4,
    seed=0x7068617365313403,
    backend_claim=:cpu,
    deviations=(
        :reduced_domain,
        :shortened_runtime,
        :documentation_seed,
    ),
)

function profile(identity::Symbol=:reduced_cpu)
    identity === :canonical && return canonical_profile()
    identity === :reduced_cpu && return reduced_profile()
    throw(ArgumentError(
        "Wortel profile must be :canonical or :reduced_cpu"))
end

"""Reusable Wortel semantic model: ordinary CPM biology plus one explicit Act declaration."""
struct Model{P,M,A,C,D}
    profile::P
    potts::M
    activity::A
    cell::C
    medium::D
end

function model(spec::Profile=profile())
    medium = Medium(:extracellular)
    cell = CellType(:endothelial)
    volume = Volume(
        cell => (
            target=Float32(spec.cell_side^2),
            strength=spec.volume_strength,
        ),
    )
    contact = PairwiseLaw(
        :contact_energy,
        (medium, medium) => 0.0f0,
        (medium, cell) => 6.0f0,
        (cell, cell) => 2.0f0,
    )
    potts = PottsModel(medium, cell, volume, Adhesion(contact))
    activity = Act(
        maximum_activity=spec.maximum_activity,
        strength=spec.activity_strength,
        neighborhood=CorePotts.MooreTopology{2}(),
        spacing=(1.0f0, 1.0f0),
        algorithm=BudgetedSequentialCPM(
            AttemptsPerSite(1);
            temperature=spec.temperature,
        ),
        observation_every=spec.observation_every,
    )
    return Model(spec, potts, activity, cell, medium)
end

function initial_labels(spec::Profile=profile())
    labels = zeros(UInt64, spec.dimensions)
    pitch = spec.cell_side + 2
    identity = UInt64(0)
    for y in 2:pitch:(spec.dimensions[2] - spec.cell_side),
            x in 2:pitch:(spec.dimensions[1] - spec.cell_side)
        identity += UInt64(1)
        fill!(
            view(
                labels,
                x:(x + spec.cell_side - 1),
                y:(y + spec.cell_side - 1),
            ),
            identity,
        )
    end
    iszero(identity) && error(
        "Wortel profile contains no finite-cell placement")
    return labels
end

function problem(definition::Model=model();
        tspan=(0, definition.profile.mcs))
    labels = initial_labels(definition.profile)
    identities = Tuple(
        identity => definition.cell
        for identity in sort!(collect(Set(filter(!iszero, labels))))
    )
    base = PottsProblem(
        definition.potts,
        CartesianDomain(
            definition.profile.dimensions;
            spacing=(1.0f0, 1.0f0),
        ),
        Layout(LabelledCells(labels, identities));
        capacity=length(identities),
        tspan,
        seed=definition.profile.seed,
    )
    return CorePotts.ActivityPottsProblem(
        base,
        lower(definition.activity),
    )
end

problem(spec::Profile; kwargs...) = problem(model(spec); kwargs...)

function _labels(state)
    labels = zeros(UInt64, CorePotts.lattice_size(state))
    for site in eachindex(labels)
        owner = CorePotts.owner_at(state, site)
        labels[site] = CorePotts.is_cell_owner(owner) ?
            UInt64(CorePotts.value(CorePotts.cell_id(owner))) : UInt64(0)
    end
    return labels
end

function _activity(integrator, dimensions)
    values = Array{Float32}(undef, dimensions)
    for site in eachindex(values)
        values[site] = Float32(CorePotts.site_property_value(integrator, site))
    end
    return values
end

function run(definition::Model=model())
    integrator = SciMLBase.init(problem(definition))
    SciMLBase.step!(integrator, definition.profile.mcs)
    state = CorePotts.logical_state(integrator)
    return (
        labels=_labels(state),
        activity=_activity(integrator, definition.profile.dimensions),
        report=CorePotts.current_mcs_report(integrator),
        observations=ProcessBigraphs.observation_records(integrator),
        checkpoint=CorePotts.capture_checkpoint(integrator),
        integrator=integrator,
    )
end

function semantic_manifest(definition::Model=model())
    activity_model =
        CorePotts.canonical_coupled_model(lower(definition.activity))
    return (
        family=:Wortel2021,
        semantic_version=string(SEMANTIC_VERSION),
        profile=definition.profile.identity,
        source_trace=definition.profile.source_trace,
        deviations=definition.profile.deviations,
        scientific_nonclaims=definition.profile.scientific_nonclaims,
        potts_fingerprint=semantic_fingerprint(definition.potts).digest,
        activity_fingerprint=bytes2hex(
            CorePotts.semantic_model_fingerprint(activity_model)),
    )
end

struct _BatchProcess{M} <: ProcessBigraphs.AbstractProcess
    definition::M
end

function ProcessBigraphs.ports(step::_BatchProcess)
    dims = step.definition.profile.dimensions
    return (
        ProcessBigraphs.PortSpec(
            Array{UInt64,2},
            :labels,
            :output;
            update_law=:replace,
        ),
        ProcessBigraphs.PortSpec(
            Array{Float32,2},
            :activity,
            :output;
            update_law=:replace,
        ),
    )
end

ProcessBigraphs.semantic_version(::_BatchProcess) = string(SEMANTIC_VERSION)
ProcessBigraphs.semantic_parameters(step::_BatchProcess) = (
    family=:Wortel2021,
    manifest=semantic_manifest(step.definition),
)

function ProcessBigraphs.invoke(
        step::_BatchProcess,
        inputs::ProcessBigraphs.PortView,
        context::ProcessBigraphs.InvocationContext)
    result = run(step.definition)
    return ProcessBigraphs.InvocationResult((
        ProcessBigraphs.emit(
            context,
            :labels,
            ProcessBigraphs.ReplaceUpdate(),
            result.labels,
        ),
        ProcessBigraphs.emit(
            context,
            :activity,
            ProcessBigraphs.ReplaceUpdate(),
            result.activity,
        ),
    ); diagnostics=(
        accepted_copies=result.report.accepted_copies,
        activity_records=length(result.observations),
    ))
end

"""
Build an executable ProcessBigraph composite for one bounded Wortel profile.

The composite makes orchestration explicit while the reusable SciML problem
remains available independently through [`problem`](@ref).
"""
function composite(definition::Model=model())
    spec = definition.profile
    scale = ProcessBigraphs.TimeScale(1, 1, :mcs)
    assembled = ProcessBigraphs.compose(
        :Wortel2021;
        scale,
        profile=:reproducible,
    ) do system
        labels = ProcessBigraphs.store!(
            system,
            :labels,
            ProcessBigraphs.LeafSchema(
                UInt64;
                shape=spec.dimensions,
                default=zeros(UInt64, spec.dimensions),
                update_law=:replace,
                ontology="CPM cell identity",
            ),
        )
        activity = ProcessBigraphs.store!(
            system,
            :activity,
            ProcessBigraphs.LeafSchema(
                Float32;
                shape=spec.dimensions,
                default=zeros(Float32, spec.dimensions),
                update_law=:replace,
                ontology="Act memory",
            ),
        )
        simulation = ProcessBigraphs.mount!(
            system,
            :wortel_activity_run,
            _BatchProcess(definition),
        )
        ProcessBigraphs.attach!(
            system,
            simulation,
            (labels=labels, activity=activity),
        )
        ProcessBigraphs.schedule!(
            system,
            simulation,
            ProcessBigraphs.At((
                ProcessBigraphs.LogicalTime(spec.mcs, scale),
            )),
        )
    end
    return ProcessBigraphs.compile(assembled)
end

struct _Observer <: ProcessBigraphs.AbstractObserver end
ProcessBigraphs.observer_semantic_version(::_Observer) = string(SEMANTIC_VERSION)
ProcessBigraphs.observer_semantic_parameters(::_Observer) = (
    family=:Wortel2021,
    observation=:bounded_state_summary,
)

function ProcessBigraphs.observe(
        ::_Observer,
        projection,
        context)
    labels = projection[ProcessBigraphs.path("labels")]
    activity = projection[ProcessBigraphs.path("activity")]
    return ProcessBigraphs.ObservationResult((
        tick=Int(context.time.tick),
        cell_count=length(Set(filter(!iszero, labels))),
        occupied_sites=count(!iszero, labels),
        active_sites=count(>(0), activity),
        activity_mass=sum(activity),
    ))
end

function observation_plan(spec::Profile=profile())
    scale = ProcessBigraphs.TimeScale(1, 1, :mcs)
    observer = ProcessBigraphs.ObserverSpec(
        "wortel-state-summary",
        _Observer(),
        (
            ProcessBigraphs.path("labels"),
            ProcessBigraphs.path("activity"),
        ),
        ProcessBigraphs.AtTimesObservationSchedule((
            ProcessBigraphs.LogicalTime(spec.mcs, scale),
        ));
        record_schema=ProcessBigraphs.RecordSchema(
            NamedTuple;
            identity="wortel-state-summary-v1",
        ),
    )
    return ProcessBigraphs.ObservationPlan((observer,))
end

observation_plan(definition::Model) = observation_plan(definition.profile)

end
