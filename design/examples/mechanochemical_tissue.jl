# PROPOSED END-STATE API — DESIGN EXAMPLE, NOT EXECUTABLE AGAINST CURRENT PACKAGES.
#
# This file is a single-source authoring walkthrough for the PR-chain proposal.
# Existing names and proposed names appear together. New constructors/keywords
# below specify the intended experience; they have not been implemented or frozen.
# See ../authoring-api-overview.md for the API legend and semantic contracts.
# This is the explicit semantic walkthrough, not the final ergonomic syntax.
# The strengthened spec requires scoped declarations, one-time assembly, direct
# scientific geometry and simpler native binding over the SAME declarations.
# See ../../spec/ideal_api_vision.md and ../authoring-design-research.md.
#
# Scientific example: a closed, active epithelial tissue coupled to a permeating
# ligand field, intracellular storage, receptor/cycle dynamics, and focal links.
# All numerical values use nondimensional reference units. It is an illustrative
# model, not a claim to reproduce a paper. It is a nonequilibrium model.
#
# Calling factories only builds declarations. No simulation runs at file load.

module MechanochemicalTissueExample

using Potts
using PottsModels
using LocalMath
using ModelingToolkit
using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase
using StaticArrays
using LinearAlgebra
using Statistics
using Test

# -----------------------------------------------------------------------------
# 1. Ordinary Julia mathematics. No knowledge of storage or proposal internals.
# -----------------------------------------------------------------------------

saturating(x, half) = x / (half + x)

function bounded_mean(values)
    return LocalMath.fold(values;
        map = identity,
        combine = +,
        init = 0.0,
        finish = (total, count) -> total / count,
        domain = isfinite,
        invalid = :reject,
        empty = 0.0,
        order = :canonical,
    )
end

# A concrete fixed-vector function is registered through the same public
# mathematical function mechanism used by scalar custom operations. Structured
# arguments are one of the additions in the proposed chain.
LocalMath.@localmath function regularized_direction(v::SVector{2, T}, epsilon::T) where {T}
    return v / sqrt(dot(v, v) + epsilon^2)
end

# This helper RETURNS a process declaration. It can live in PottsModels, or be
# defined in a scientist's model file. Its contract is to read supplied motion,
# polarity and cue_gradient and atomically write polarity and reset motion.
# This small replacement hook introduces no extra owned state. Larger reusable
# components return ordinary composed PottsSystem declarations with their state.
function motion_alignment(;
        name,
        population,
        polarity,
        motion,
        cue_gradient,
        clock_interval,
        memory,
        cue_weight,
        epsilon,
    )
    c = CellBinding(:responding_cell)
    desired = regularized_direction(
        motion[c] / clock_interval + cue_weight * cue_gradient[c], epsilon)

    return SynchronousProcess(name;
        domain = population,
        anchor = c,
        effects = (
            Assign(polarity[c], memory * polarity[c] + (1 - memory) * desired),
            Assign(motion[c], zero(motion[c])),
        ),
        # Both right-hand sides read the SAME stage-entry snapshot.
        # Resetting motion cannot erase the value used above.
        cadence = EveryMCS(1),
    )
end

# -----------------------------------------------------------------------------
# 2. Complete model factory: science is independent of CPU/GPU and solver choice.
# -----------------------------------------------------------------------------

function mechanochemical_tissue(;
        name = :tissue,
        shape = (96, 96),
        max_cells = 512,
        max_links = 2048,
        scalar_type = Float64,
        polarity_mechanism = motion_alignment,
    )
    length(shape) == 2 || throw(ArgumentError(
        "this example's vector function and initialization are explicitly 2D"))
    T = scalar_type
    T in (Float32, Float64) || throw(ArgumentError("choose Float32 or Float64"))
    zero_vector = SVector{2, T}(0, 0)

    # Structural quantities: changing these reconstructs the model.
    spacing = 1.0
    voxel_volume = spacing^2
    interval = 0.05                     # native physical duration per MCS

    # Numerical parameters: changed through PottsProblem/remake, not by editing
    # execution objects. Symbolic parameters propagate into components normally.
    @parameters temperature = 2.0
    @parameters target_volume = 40.0 growth_gain = 0.5
    @parameters volume_strength = 2.0 surface_strength = 0.02
    @parameters contact_strength = 8.0
    @parameters migration_strength = 2.0 chemotaxis_strength = 1.0
    @parameters activity_strength = 0.5 activity_lifetime = 10.0
    @parameters diffusivity = 0.1 uptake_rate = 0.2 uptake_half = 0.1
    @parameters storage_capacity = 4.0
    @parameters receptor_on = 1.0 receptor_off = 0.2
    @parameters cycle_rate = 0.4 damage_rate = 0.05 repair_rate = 0.1
    @parameters polarity_memory = 0.8 cue_weight = 0.5 direction_epsilon = 1.0e-6
    @parameters spring_stiffness = 0.05 link_relaxation = 0.02
    @parameters formation_distance = 12.0 rupture_distance = 20.0
    @parameters division_volume = 65.0 lethal_damage = 0.35

    lattice = Lattice(shape;
        boundary = Closed(),
        spacing,
        max_cells,
        relations = (proposal = VonNeumann(), contact = VonNeumann()),
    )
    epithelial = CellKind(:epithelial; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    population = cells(epithelial)

    s = SiteBinding(:site)
    c = CellBinding(:cell)
    copy = ProposalContext(:copy)

    # Contacts between DISTINCT cells. The site stencil still has repeated
    # owner lanes; this relation explicitly requests a different measure.
    neighbors = CellContacts(:neighbors;
        from = :contact,
        domain = population,
        measure = :distinct_cells,
        include_medium = false,
        maximum_degree = 32,
    )

    # -------------------------------------------------------------------------
    # 3. Authoritative state. References ARE symbolic quantities; there is no
    #    second @variables declaration or manual tracker-array binding for them.
    # -------------------------------------------------------------------------

    # Free ligand is present at ALL voxels, including cell-occupied voxels.
    # It models a permeating environment, not material displaced by occupancy.
    free_ligand = FieldState(:free_ligand;
        domain = sites(lattice),
        value_type = T,
        initial = 0.05,
        bounds = (0.0, Inf),
        interpretation = :amount_per_site,
    )

    # This is a separate physical pool. Division conserves its extensive amount.
    # Retirement transfers it to the PRE-removal footprint before removing cells.
    # The residual-to-second-daughter rule avoids independently rounded shares.
    internal_ligand = CellState(:internal_ligand;
        domain = population,
        value_type = T,
        initial = 0.5,
        bounds = (0.0, Inf),
        division = SplitConservatively(weight = :daughter_volume, residual = :second),
        retirement = DepositTo(free_ligand;
            over = :pre_removal_sites, weights = :uniform, empty = :reject),
    )

    receptor = CellState(:receptor;
        domain = population, value_type = T, initial = 0.1, bounds = (0.0, 1.0),
        division = CopyToDaughters(), retirement = Discard())
    cycle = CellState(:cycle;
        domain = population, value_type = T, initial = 0.0, bounds = (0.0, Inf),
        division = ResetBoth(0.0), retirement = Discard())
    damage = CellState(:damage;
        domain = population, value_type = T, initial = 0.0, bounds = (0.0, Inf),
        division = CopyToDaughters(), retirement = Discard())

    polarity = CellState(:polarity;
        domain = population, value_type = SVector{2, T},
        initial = SVector{2, T}(1, 0),
        division = CopyToDaughters(), retirement = Discard())
    motion = CellState(:motion;
        domain = population, value_type = SVector{2, T},
        initial = zero_vector,
        division = ResetBoth(zero_vector), retirement = Discard())

    activity = SiteState(:activity;
        domain = sites(lattice), value_type = T, initial = 0.0, bounds = (0.0, Inf),
        ownership_change = ClearOnOwnershipChange())

    # -------------------------------------------------------------------------
    # 4. Derived quantities. The compiler follows every source mutation, including
    #    field updates with no copies, compound effects, division, and restore.
    # -------------------------------------------------------------------------

    # The short aggregate form means an additive aggregate with a known identity
    # and retraction law. Custom algebra is explicit; arbitrary code is not guessed.
    site_count = aggregate(1;
        name = :site_count, over = sites(lattice), by = owner, groups = population)
    volume = derived(:volume;
        domain = population, anchor = c,
        expression = voxel_volume * site_count[c])
    exposure_amount = aggregate(free_ligand;
        name = :exposure_amount,
        over = sites(lattice), by = owner, groups = population)
    first_moment = aggregate(site_position(lattice);
        name = :first_moment,
        over = sites(lattice), by = owner, groups = population)
    second_moment = aggregate(outer(site_position(lattice), site_position(lattice));
        name = :second_moment,
        over = sites(lattice), by = owner, groups = population)

    center = derived(:center;
        domain = population, anchor = c,
        expression = first_moment[c] / site_count[c])
    covariance = derived(:covariance;
        domain = population, anchor = c,
        expression = second_moment[c] / site_count[c] - outer(center[c], center[c]))
    environment_concentration = derived(:environment_concentration;
        domain = population, anchor = c,
        expression = exposure_amount[c] / volume[c])
    internal_concentration = derived(:internal_concentration;
        domain = population, anchor = c,
        expression = internal_ligand[c] / volume[c])

    neighbor_receptor = derived(:neighbor_receptor;
        domain = population, anchor = c,
        expression = bounded_mean(gather(receptor, neighbors; at = c)))
    cue_gradient = derived(:cue_gradient;
        domain = population, anchor = c,
        expression = field_gradient(free_ligand / voxel_volume;
            at = center[c], boundary = NoFlux()))
    growing_target = derived(:growing_target;
        domain = population, anchor = c,
        expression = target_volume * (1 + growth_gain * cycle[c]))

    # Intentionally sampled state: this value updates every five MCS at the point
    # where it appears in the protocol below. It is initialized at MCS zero.
    # The ODE reads the held result; it is not a live shape tracker during proposals.
    # Lifecycle recomputes daughters immediately but preserves global cadence.
    # Off-tick restore retains the saved sample, not a recomputation from current
    # geometry: restoring MCS 7 retains the MCS-5 sample and next refresh at 10.
    sampled_shape = derived(:sampled_shape;
        domain = population, anchor = c,
        expression = tr(covariance[c]),
        cadence = EveryMCS(5),
        initialize = :evaluate,
        lifecycle = :recompute,
    )

    # -------------------------------------------------------------------------
    # 5. Relationships. Link identity, generations and capacity are engine-owned.
    # -------------------------------------------------------------------------

    links = RelationshipState(:focal_links;
        endpoints = Undirected(epithelial, epithelial),
        payload = (stiffness = spring_stiffness, rest_length = 8.0),
        capacity = max_links,
        maximum_degree = 6,
        lifecycle = RemoveWithEndpoint(),
    )
    e = RelationshipBinding(:link, links)
    contact = ContactBinding(:neighbor_pair, neighbors)

    # -------------------------------------------------------------------------
    # 6. State energies versus proposal drives and hard constraints.
    # -------------------------------------------------------------------------

    volume_energy = HamiltonianTerm(:volume_energy;
        domain = population, anchor = c,
        expression = volume_strength * (volume[c] - growing_target[c])^2)
    surface_energy = HamiltonianTerm(:surface_energy;
        domain = population, anchor = c,
        expression = surface_strength * cell_surface(c, :contact)^2)
    contact_energy = ContactEnergy(
        [0.0 contact_strength; contact_strength contact_strength / 2];
        kinds = (medium, epithelial), relation = :contact)
    spring_energy = HamiltonianTerm(:spring_energy;
        domain = edges(links), anchor = e,
        expression = 0.5 * e.stiffness *
            (norm(center[endpoint_a(e)] - center[endpoint_b(e)]) - e.rest_length)^2)

    # A copy changes all incident springs of BOTH affected cells. That dependency
    # follows from this state expression; no handwritten delta_h is needed.
    # The field below and the independent continuous values are snapshots during
    # a CPM interval. Ownership-derived geometry still changes on accepted copies.
    # `when` guards are evaluated BEFORE the body: a medium-owned proposal must
    # never evaluate a finite-cell polarity/receptor lookup.
    migration = ProposalDrive(:migration,
        -migration_strength * dot(polarity[copy.new_owner], copy.direction);
        when = source_kind(copy) == epithelial)
    chemotaxis = ProposalDrive(:chemotaxis,
        -chemotaxis_strength * (1 + receptor[copy.new_owner]) *
        (free_ligand[copy.target_site] - free_ligand[copy.source_site]) / voxel_volume;
        when = source_kind(copy) == epithelial)
    activity_bias = PottsModels.ActivityDrive(epithelial;
        activity, strength = activity_strength, neighborhood = :contact,
        within = :same_owner, reduction = :geometric_mean,
        zero_activity = :zero_mean, empty = 0.0)
    connectivity = LocalConnectivity(epithelial; relation = :contact)

    # -------------------------------------------------------------------------
    # 7. Accepted-copy effects and simultaneous boundary processes.
    # -------------------------------------------------------------------------

    # Accumulate ACTUAL centroid displacement for losing and gaining cells.
    # A lattice copy direction is not generally a cell-centroid displacement.
    accepted_motion = AcceptedCopyProcess(:accepted_motion;
        domain = affected_cells(copy; within = population),
        anchor = c,
        effects = (Assign(motion[c], motion[c] +
            after(center[c], copy) - before(center[c], copy)),),
    )
    activate = AcceptedCopyProcess(:activate;
        when = source_kind(copy) == epithelial,
        effects = (Assign(activity[copy.target_site], activity_lifetime),),
    )
    # ClearOnOwnershipChange resets the changed site's previous activity first;
    # this accepted-copy activation then initializes activity for the new owner.
    # Zero activity contributes a zero geometric mean, not a log-domain failure.
    decay_activity = SynchronousProcess(:decay_activity;
        domain = sites(lattice), anchor = s,
        effects = (Assign(activity[s], max(0.0, activity[s] - 1.0)),),
        cadence = EveryMCS(1),
    )
    align_polarity = polarity_mechanism(;
        name = :align_polarity, population, polarity, motion, cue_gradient,
        clock_interval = interval, memory = polarity_memory,
        cue_weight, epsilon = direction_epsilon,
    )

    # Opinionated numerical/scientific components are ordinary PottsModels
    # factories. They consume the public Potts spatial/process primitives; a
    # reusable finite-volume stencil retains its appropriate numerical owner.
    # Diffusion represents dc/dt = diffusivity * Laplacian(c). The finite-volume
    # flux discretization is conservative, with zero normal boundary flux.
    diffusion = PottsModels.Diffusion(free_ligand;
        diffusivity,
        duration = interval,
        boundary = NoFlux(),
        discretization = :cartesian_finite_volume,
        substeps = 4,
        invalid = :reject,               # never clamp away negative mass
    )

    # This is ONE transfer, not separate subtract/add processes. Requested uptake
    # is a cell amount per unit native time; realized transfer is bounded by both
    # source availability and remaining destination capacity.
    uptake = Transfer(:uptake;
        domain = population, anchor = c,
        from = free_ligand,
        to = internal_ligand[c],
        over = owned_sites(c),
        rate = uptake_rate * volume[c] *
            saturating(environment_concentration[c], uptake_half),
        duration = interval,
        destination_capacity = storage_capacity * volume[c],
        weights = :available_amount,
        shortage = :limit,
        shared_source = :proportional,
    )
    # destination_capacity limits new uptake. A shrinking cell already above
    # that capacity takes up zero; its existing store is never clipped away.

    # -------------------------------------------------------------------------
    # 8. Native equations: these remain a genuine ModelingToolkit system.
    # -------------------------------------------------------------------------

    @independent_variables t
    Dt = Differential(t)
    @variables r(t) z(t) d(t) outside(t) inside(t) neighbors_r(t) shape_cue(t)

    # r, z and d are dimensionless signaling/cycle/damage variables. These
    # equations DO NOT consume ligand. Binding that consumes ligand would need
    # an additional bound pool in the conservative transfer model.
    equations = [
        Dt(r) ~ receptor_on * outside * (1 - r) - receptor_off * r,
        Dt(z) ~ cycle_rate * r * saturating(inside, uptake_half) /
            (1 + 0.01 * shape_cue + neighbors_r),
        Dt(d) ~ damage_rate / (1 + inside) - repair_rate * d,
    ]
    @named intracellular_ode = System(equations, t)

    intracellular = NativeComponent(intracellular_ode;
        name = :intracellular,
        family = ODEComponent(),
        scope = PerCell(epithelial),
        anchor = c,
        time = FixedPhysicalTime(0.0, interval),
        cadence = EveryMCS(1),
        inputs = (
            NativeInput(outside, environment_concentration[c]),
            NativeInput(inside, internal_concentration[c]),
            NativeInput(neighbors_r, neighbor_receptor[c]),
            NativeInput(shape_cue, sampled_shape[c]),
        ),
        outputs = (
            NativeOutput(r, receptor[c]),
            NativeOutput(z, cycle[c]),
            NativeOutput(d, damage[c]),
        ),
        initialization = FromPublishedState(),
        lifecycle = PerCellNativeLifecycle(
            creation = FromPublishedState(),
            division = FromPublishedState(),
            transition = FromPublishedState(),
            retirement = Discard(),
        ),
    )
    # FromPublishedState means initialize/reinitialize native unknowns from their
    # mapped CPM outputs AFTER declared lifecycle policies. It is not two sets of
    # independently writable state. Native inputs are held over each solve interval.
    # r/z/d are actual native unknowns here. Arbitrary observed outputs, such as
    # y=x^2, cannot generally be initialized backwards; those need a supported
    # native initialization problem rather than an inferred inverse.

    # -------------------------------------------------------------------------
    # 9. Link events and lifecycle use the SAME scientific quantity references.
    # -------------------------------------------------------------------------

    form_links = RelationshipProcess(:form_links;
        domain = contacts(neighbors; pairs = :unordered_unique), anchor = contact,
        when = !linked(links, contact.a, contact.b) &
            (norm(center[contact.a] - center[contact.b]) < formation_distance),
        effects = (Create(links, contact.a, contact.b;
            payload = (stiffness = spring_stiffness,
                rest_length = norm(center[contact.a] - center[contact.b]))),),
        cadence = EveryMCS(10),
        on_inadmissible = FilterInadmissible(),
        order = :canonical,
    )
    relax_links = RelationshipProcess(:relax_links;
        domain = edges(links), anchor = e,
        effects = (Retune(links, e;
            payload = (rest_length = e.rest_length + interval * link_relaxation *
                (norm(center[endpoint_a(e)] - center[endpoint_b(e)]) - e.rest_length),)),),
        cadence = EveryMCS(1),
    )
    rupture_links = RelationshipProcess(:rupture_links;
        domain = edges(links), anchor = e,
        when = norm(center[endpoint_a(e)] - center[endpoint_b(e)]) > rupture_distance,
        effects = (Remove(links, e),),
        cadence = EveryMCS(1),
    )

    divide = LifecycleProcess(:divide;
        domain = population, anchor = c,
        when = (cycle[c] >= 1.0) & (volume[c] >= division_volume),
        effects = (Divide(c;
            geometry = PrincipalAxisPlane(;
                normal = :major_axis, degenerate = :canonical_axis),
            relationships = (links => RemoveIncident(),)),),
        on_inadmissible = FilterInadmissible(),
        cadence = EveryMCS(1),
    )
    retire = LifecycleProcess(:retire;
        domain = population, anchor = c,
        when = damage[c] >= lethal_damage,
        effects = (Retire(c; to = medium),),
        cadence = EveryMCS(1),
    )
    # Retirement deposits internal_ligand while the old footprint exists, removes
    # incident links, and then retires the identity. All are one transaction.
    # Division partitions extensive quantities, copies/reset intensive state,
    # reconstructs derived values, and reinitializes the native daughter systems.
    # The division plane's NORMAL is the major axis, so daughters separate along
    # the long direction. Contact enumeration emits each unordered pair once.

    # -------------------------------------------------------------------------
    # 10. Observations and the scientific schedule.
    # -------------------------------------------------------------------------

    ligand_total = Observation(:ligand_total,
        sum(free_ligand; over = sites(lattice)) +
        sum(internal_ligand; over = population))
    # exposure_amount is NOT added: it is a view of free ligand, not a new pool.
    lineage_observation = Observation(:lineage, lineage(population))
    observations = (ligand_total, volume, center, covariance, receptor, cycle,
        polarity, free_ligand, links, lineage_observation)
    # Existing quantities are directly selectable: no second Observation with
    # the same name/meaning is needed. Only new expressions get named observations.

    protocol = Protocol(Sweep(; temperature);
        name = :main,
        after = (
            diffusion,
            uptake,
            sampled_shape,
            intracellular,
            align_polarity,
            decay_activity,
            relax_links,
            rupture_links,
            form_links,
            LifecycleBatch((retire, divide);
                arbitration = StableLifecyclePriority((retire, divide))),
        ),
    )
    # Cadence determines whether an item is due; this list fixes relative order.
    # All due native islands in one native batch would read one sampled snapshot.
    # Source changes refresh dependent live aggregates before their next consumer.
    # The complete MCS, including native work, commits atomically or fails.
    # Observation/checkpoint publication occurs only after successful settlement.
    # StatementSet enrolls each declaration once. Protocol entries refer to those
    # SAME identities to order execution. A sampled quantity's protocol entry
    # refreshes its existing held value rather than declaring another quantity.

    state = (free_ligand, internal_ligand, receptor, cycle, damage, polarity, motion, activity)
    quantities = (site_count, volume, exposure_amount, first_moment, second_moment,
        center, covariance, environment_concentration, internal_concentration,
        neighbor_receptor, cue_gradient, growing_target, sampled_shape)
    energies = (volume_energy, surface_energy, contact_energy, spring_energy)
    drives = (migration, chemotaxis, activity_bias)
    processes = (accepted_motion, activate, decay_activity, align_polarity,
        diffusion, uptake, form_links, relax_links, rupture_links, divide, retire)

    system = PottsSystem(;
        name,
        statements = StatementSet((
            lattice, epithelial, medium, neighbors,
            state..., quantities..., links,
            energies..., drives..., connectivity,
            processes..., ligand_total, lineage_observation, protocol,
        )),
        native_components = (intracellular,),
        # Reachable parameter/quantity declarations are inferred by identity.
        # Explicit parameter lists remain available for advanced construction.
    )

    return (;
        system, lattice, epithelial, medium, shape, interval, scalar_type, links,
        state = (; free_ligand, internal_ligand, receptor, cycle, damage, polarity, motion, activity),
        quantities = (; site_count, volume, exposure_amount, first_moment, second_moment,
            center, covariance, environment_concentration, internal_concentration,
            neighbor_receptor, cue_gradient, growing_target, sampled_shape, ligand_total),
        parameters = (; migration_strength, chemotaxis_strength, target_volume,
            uptake_rate, division_volume, lethal_damage),
        native = intracellular,
        events = (; divide, retire),
        observations,
    )
end

# -----------------------------------------------------------------------------
# 11. Initial conditions are ordinary data, separate from model declarations.
# -----------------------------------------------------------------------------

function initial_tissue(model; contact_rich = false, division_ready = false,
        damaged_cell = nothing, seed_links = false)
    nx, ny = model.shape
    T = model.scalar_type
    min(nx, ny) >= 40 || throw(ArgumentError("this four-cell initializer needs at least 40 × 40"))
    labels = zeros(Int32, nx, ny)
    radius = division_ready ? 5 : 3
    cx, cy = nx ÷ 2, ny ÷ 2
    locations = contact_rich ? (
        (cx - radius - 1, cy - radius - 1), (cx + radius, cy - radius - 1),
        (cx - radius - 1, cy + radius), (cx + radius, cy + radius),
    ) : ((nx ÷ 3, ny ÷ 3), (2nx ÷ 3, ny ÷ 3),
        (nx ÷ 3, 2ny ÷ 3), (2nx ÷ 3, 2ny ÷ 3))
    for (id, (cx, cy)) in enumerate(locations)
        for y in 1:ny, x in 1:nx
            if (x - cx)^2 + (y - cy)^2 <= radius^2
                labels[x, y] == 0 || error("initial cells overlap")
                labels[x, y] = id
            end
        end
    end
    n = length(locations)
    free = [T(0.02 + 0.08 * (x - 1) / (nx - 1)) for x in 1:nx, y in 1:ny]
    initial_cycle = zeros(T, n)
    initial_damage = zeros(T, n)
    division_ready && (initial_cycle[1] = T(1.2))
    damaged_cell === nothing || (initial_damage[damaged_cell] = T(10))
    initial_links = seed_links ? ((model.links => [(1, 2)]),) : ()

    return PottsInitialState(;
        ownership = LabelledCells(labels;
            cells = fill(model.epithelial, n), medium = model.medium),
        values = (
            model.state.free_ligand => free,
            model.state.internal_ligand => fill(T(0.5), n),
            model.state.receptor => fill(T(0.1), n),
            model.state.cycle => initial_cycle,
            model.state.damage => initial_damage,
            model.state.polarity => fill(SVector{2, T}(1, 0), n),
            model.state.motion => fill(SVector{2, T}(0, 0), n),
            initial_links...,
        ),
    )
    # Derived quantities are constructed from authoritative initial values.
    # Native unknowns initialize from their mapped published quantities.
    # No user-supplied volumes, moments, tracker buffers, or duplicate ODE values.
end

# -----------------------------------------------------------------------------
# 12. Inspection, problem construction, execution, and ordinary analysis.
# -----------------------------------------------------------------------------

function run_example(; mcs = 200, seed = 0x5142, initial_options = (;))
    model = mechanochemical_tissue()
    initial = initial_tissue(model; initial_options...)

    # Optional structural work for exploration. PottsProblem performs it itself.
    display(explain(model.system))
    display(explain(model.system, model.quantities.environment_concentration))
    display(inspect(complete(model.system), Schedule()))

    problem = PottsProblem(model.system, initial, (0, mcs); seed)
    native_profiles = (NativeSolveProfile(
        model.native,
        Tsit5();
        execution = BatchedNativeExecution(32),
        adaptive = false,
        dt = model.interval / 4,
        exact_replay = false,
    ),)

    # Sequential execution is the reference profile for this linked model.
    # Checkerboard admission must also prove read/write conflict closure through
    # linked endpoints and mutable aggregates, not merely local lattice coloring.
    solution = solve(problem, SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        native_profiles,
        saveat = unique(sort([collect(0:10:mcs); mcs])),
        observables = model.observations,
    )
    solution.retcode == SciMLBase.ReturnCode.Success || error(failure_report(solution))

    final_state = solution[end]
    final_receptor = final_state[model.state.receptor]
    final_polarity = final_state[model.state.polarity]
    total_amounts = [state[:ligand_total] for state in solution]

    # A numerical conservation check, not a bitwise trajectory/replay promise.
    @test all(isapprox(total, first(total_amounts); rtol = 1e-9, atol = 1e-10)
        for total in total_amounts)

    return (; model, problem, solution, native_profiles, final_receptor, final_polarity)
end

# An explicitly perturbed scenario exercises links and lifecycle much sooner
# than four widely separated unstressed cells. This is a declaration example,
# not a claim that we have executed or validated the future model.
function event_scenario()
    return run_example(; mcs = 2, initial_options = (
        contact_rich = true, division_ready = true, damaged_cell = 4, seed_links = true))
end

# -----------------------------------------------------------------------------
# 13. Parameter experiments use standard problems and ensembles.
# -----------------------------------------------------------------------------

function experiment_problems(model, initial; strengths = (0.0, 1.0, 2.0), mcs = 200)
    base = PottsProblem(model.system, initial, (0, mcs); seed = 0x5142)
    return [remake(base;
        p = (model.parameters.migration_strength => strength,)) for strength in strengths]
end

function run_replicates(problem; native_profiles, trajectories = 8)
    return solve(EnsembleProblem(problem), SequentialCPM(), EnsembleThreads();
        trajectories,
        backend = CPUBackend(), scalar_type = Float64,
        native_profiles,
        observables = (:ligand_total, :volume, :receptor),
    )
    # The ensemble assigns replica identity. Per-cell batching is a different
    # level of parallelism. This does not claim pathwise gradients through CPM.
end

# -----------------------------------------------------------------------------
# 14. Checkpoint and resume use the SAME problem and numerical profile.
# -----------------------------------------------------------------------------

function checkpoint_example(problem; native_profiles, steps_before_checkpoint = 10)
    options = (;
        backend = CPUBackend(), scalar_type = Float64, native_profiles,
        observables = (:ligand_total, :volume, :receptor),
    )
    integrator = init(problem, SequentialCPM(); options...)
    for _ in 1:steps_before_checkpoint
        step!(integrator)
    end
    saved = checkpoint(integrator)
    resumed = init(problem, SequentialCPM(); checkpoint = saved, options...)
    return solve!(resumed)
    # This requires admitted logical restart for the selected features/profile.
    # To request exact continuation, pass native_profiles that explicitly request
    # exact_replay with a real supported profile_id/environment. No fictional
    # profile ID is hardcoded here, and restart alone is not called exact replay.
end

# -----------------------------------------------------------------------------
# 15. Visualization is optional, and consumes retained public observations.
# -----------------------------------------------------------------------------

# In the same Julia session, after selecting a Makie backend:
#
# using CairoMakie, MakiePotts
# result = run_example()
# frame = renderframe(result.solution[end];
#     channels = (quantity_channel(result.model.state.receptor),
#                 quantity_channel(result.model.state.polarity)))
# figure, axis, plot = CairoMakie.plot(frame;
#     color = result.model.state.receptor,
#     vectors = result.model.state.polarity,
#     boundaries = true)
# CairoMakie.save("mechanochemical_tissue.png", figure)
#
# quantity_channel/color/vectors are PROPOSED adapters over retained quantities.
# No frame requests a hidden simulation step or reconstructs unsaved state.

# -----------------------------------------------------------------------------
# 16. Smaller single-file models use the same public declarations.
# -----------------------------------------------------------------------------

function minimal_sorting_model(; name = :sorting)
    a = CellKind(:a; extinction = ForbidExtinction())
    b = CellKind(:b; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    lattice = Lattice((64, 64); boundary = Periodic(), max_cells = 256)
    system = PottsSystem(;
        name,
        statements = (@statements begin
            lattice
            a
            b
            medium
            Volume(a; target = 40.0, strength = 2.0)
            Volume(b; target = 40.0, strength = 2.0)
            ContactEnergy([0.0 16.0 16.0; 16.0 4.0 12.0; 16.0 12.0 4.0];
                kinds = (medium, a, b))
            Protocol(Sweep(; temperature = 2.0); name = :main)
        end),
    )
    return (; system, a, b, medium)
end

# Reusable library experience: the library factory owns its model, exposes
# meaningful parameters, and returns ordinary declarations/data references.
#
# model = PottsModels.PersistentMigration(; name=:migration, shape=(128,128),
#     persistence_time=20.0, activity_lifetime=10.0, strength=2.0)
# problem = PottsProblem(model.system, model.initial_state, (0,1000); seed=42)
# solution = solve(problem, CheckerboardSweepCPM(); backend=CPUBackend())
#
# To replace the polarity law in the large example:
# model = mechanochemical_tissue(
#     polarity_mechanism=PottsModels.CueAlignment)
#
# The replacement factory accepts the documented scientific input keywords and
# returns a process with the same outputs; duplicate writers fail at completion.

# -----------------------------------------------------------------------------
# 17. Breadth-branch alternatives. These are SEPARATE model/solver choices,
#     not declarations to append indiscriminately to the active tissue above.
# -----------------------------------------------------------------------------

# A. B1: a dimension-generic PottsModels factory, after 3D is implemented.
# The hand-written regularized_direction/initializer above stay explicitly 2D.
#
# model3d = PottsModels.MechanochemicalTissue(; shape=(64,64,64), max_cells=1024)
# problem3d = PottsProblem(model3d.system, model3d.initial_state, (0,200); seed=42)
# solve(problem3d, SequentialCPM(); backend=CPUBackend(),
#     native_profiles=PottsModels.native_profiles(model3d; solver=Tsit5()))

# B. B4: native root events REPLACE sampled-cycle triggering in that component.
#
# Inside a replacement intracellular factory, where z and c are explicitly bound:
# cycle_events = NativeEvent(z ~ 1.0;
#     latch=:once_per_cell_cycle,
#     deliver=AtNextMCSBoundary(),
#     effect=Divide(c; geometry=PrincipalAxisPlane()))
#
# The native solver localizes the root. CPM division happens at the next declared
# boundary, with its timestamp retained. Reset z/latch through daughter policies;
# do not also keep the sampled division rule and trigger the same event twice.

# C. B3: explicit compartment ownership, requiring the containment branch.
#
# compartments = PottsModels.NucleusCytoplasm(;
#     nucleus_fraction=0.2,
#     internal_contact=4.0,
#     external_contact=12.0,
#     division=:coordinated,
#     ligand_partition=:conservative)
#
# This is a model component with a Core-owned containment contract, not a second
# set of hand-maintained parent labels or a callback that divides two cells.

# D. B2: fluctuating mechanics is an explicitly active stochastic model.
#
# model = mechanochemical_tissue()
# mechanics = PottsModels.FluctuatingTension(;
#     cells=cells(model.epithelial), mean=0.02, correlation_time=10.0,
#     noise_amplitude=0.005, daughter_state=CopyToDaughters())
#
# Its stochastic law and time discretization must be stated by that component;
# an MCS random draw is not automatically an adaptive SDE solver's Brownian path.

# E. B2/B8: equilibrium auxiliary sampling is a DIFFERENT complete experiment.
#
# equilibrium = PottsModels.EquilibriumAuxiliaryVolume(;
#     shape=(64,64), cell_count=8, temperature=2.0,
#     target_volume=40.0, auxiliary_stiffness=0.1)
# equilibrium_problem = PottsProblem(
#     equilibrium.system, equilibrium.initial_state, (0,10000); seed=42)
# solve(equilibrium_problem, MetropolisHastingsCPM(); backend=CPUBackend())
#
# This needs an implemented reverse-probability/auxiliary transition contract.
# It cannot retain active motility, growth, division, or driven link creation
# and inherit an equilibrium claim from its energy terms.

# F. P12/B7: same science, a separately supported device/solver profile.
#
# using Metal, DiffEqGPU
# gpu_model = mechanochemical_tissue(; scalar_type=Float32)
# gpu_problem = PottsProblem(gpu_model.system, initial_tissue(gpu_model), (0,200); seed=42)
# gpu_profiles = (NativeSolveProfile(gpu_model.native, GPUTsit5();
#     execution=MetalNativeExecution(32), adaptive=false, dt=gpu_model.interval/4),)
# solve(gpu_problem, CheckerboardSweepCPM(); backend=MetalBackend(),
#     scalar_type=Float32, native_profiles=gpu_profiles)
# The declarations explicitly choose Float32 too; changing a solve keyword may
# not silently rewrite declared Float64 fields or vectors.
# The complete model also needs proven conflict handling for incident springs
# and shared mutable dependencies. Two distant proposals can change opposite
# endpoints of one spring despite having disjoint old/new-owner claims.
# Until that whole-model combination is admitted and tested, this GPU example
# must fail preflight rather than silently approximate the authored energy.
#
# CUDA/ROCm add their own actual extensions and conformance tests in B7.
# Merely replacing a selector does not establish support for every model,
# Float64, solver, dimension, or replay guarantee.

end # module
