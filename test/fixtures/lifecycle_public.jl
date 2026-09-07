isdefined(@__MODULE__, :LifecycleOperationFixtures) ||
    include("LifecycleOperationFixtures.jl")

function lifecycle_public_fixture()
    @variables lifecycle_activity
    cell = CellKind(:lifecycle_cell; extinction = RetireAtZero(priority = -20))
    daughter = CellKind(
        :lifecycle_daughter; extinction = RetireAtZero(priority = -20)
    )
    medium = MediumKind(:lifecycle_medium)
    relation = SpatialRelation(
        :lifecycle_division; neighborhood = VonNeumann()
    )
    activity = CellState(
        lifecycle_activity;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:lifecycle_event_cell)
    create_site = LinearIndices((6, 6))[CartesianIndex(5, 2)]
    reuse_site = LinearIndices((6, 6))[CartesianIndex(2, 2)]
    create = LifecycleProcess(
        :lifecycle_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                create_site, ((0, 0), (1, 0)); relation
            ),
            state = (activity => InitializeFrom(2.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :lifecycle_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (activity => Transform(lifecycle_activity + 1),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :lifecycle_divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (
                activity => SplitConservatively(0.5; rounding = :exact),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :lifecycle_remove;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(4),
    )
    reuse = LifecycleProcess(
        :lifecycle_reuse;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            daughter;
            placement = SeedAt(reuse_site),
            state = (activity => InitializeFrom(5.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(5),
    )
    source = PottsSystem(
        name = :lifecycle_public_model,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 6),
            cell,
            daughter,
            medium,
            relation,
            activity,
            ProposalConstraint(:freeze_lifecycle_trajectory, false),
            create,
            transition,
            divide,
            remove,
            reuse,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [lifecycle_activity],
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    return (; source, initial, activity = lifecycle_activity)
end

function lifecycle_birth_system(
        name,
        births;
        max_cells,
        conflicts = RejectLifecycleAmbiguity(),
        state = nothing,
        unknowns = [],
    )
    cell = CellKind(:birth_cell; extinction = RetireAtZero())
    medium = MediumKind(:birth_medium)
    declarations = state === nothing ? () : (state,)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((3, 3); max_cells),
            cell,
            medium,
            declarations...,
            births(cell)...,
            Protocol(
                Sweep(); name = :main, lifecycle_conflicts = conflicts
            ),
        )),
        unknowns = unknowns,
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium
        )
    )
    return (; source, initial)
end

function permutation_lifecycle_fixture(reverse_order; conflicting = false)
    births = cell -> begin
        sites = conflicting ? (1, 1) : (1, 2)
        declarations = ntuple(2) do index
            LifecycleProcess(
                Symbol(:permutation_birth_, index);
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = SeedAt(sites[index]),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
                cadence = AtMCS(1),
            )
        end
        return reverse_order ? reverse(declarations) : declarations
    end
    return lifecycle_birth_system(
        conflicting ? :public_conflict_permutation :
        :public_success_permutation,
        births;
        max_cells = 2,
    )
end
