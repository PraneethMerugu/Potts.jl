using PottsToolkit
using Statistics
using Symbolics

import CorePotts

_lower_lifecycle_benchmark(system) = PottsToolkit._lower_execution_plan(
    mtkcompile(complete(system)), SequentialCPM(), CPUBackend(), Float32
)

const SAMPLE_COUNT = parse(Int, get(ENV, "POTTS_LIFECYCLE_SAMPLES", "9"))

function runtime_for(executable, initial; mcs = 0, seed = 0x63a1)
    runtime = init(PottsProblem(executable, initial, (0, 1); seed)).runtime
    runtime.mcs = mcs
    return runtime
end

function measure_case(name, make_runtime, operation; samples = SAMPLE_COUNT)
    operation(make_runtime())
    runtimes = [make_runtime() for _ in 1:samples]
    GC.gc()
    elapsed = map(runtimes) do runtime
        started = time_ns()
        operation(runtime)
        time_ns() - started
    end
    allocation_runtime = make_runtime()
    allocated = @allocated operation(allocation_runtime)
    println(join((
        name,
        samples,
        median(elapsed),
        minimum(elapsed),
        maximum(elapsed),
        allocated,
    ), ','))
    return nothing
end

function cadence_fixture(side)
    cell = CellKind(:cadence_cell; extinction = ForbidExtinction())
    medium = MediumKind(:cadence_medium)
    anchor = CellBinding(:cadence_anchor)
    dormant = LifecycleProcess(
        :dormant_transition;
        domain = cells(cell),
        anchor,
        expression = false,
        effects = (Transition(
            anchor,
            cell;
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    system = PottsSystem(
        name = Symbol(:LifecycleCadence_, side),
        statements = StatementSet((
            Lattice((side, side); max_cells = 1),
            cell,
            medium,
            dormant,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = ones(Int, side, side)
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return executable, initial
end

function no_lifecycle_fixture(side)
    cell = CellKind(:control_cell; extinction = ForbidExtinction())
    medium = MediumKind(:control_medium)
    system = PottsSystem(
        name = Symbol(:LifecycleControl_, side),
        statements = StatementSet((
            Lattice((side, side); max_cells = 1),
            cell,
            medium,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    initial = PottsInitialState(ownership = LabelledCells(
        ones(Int, side, side); cells = [cell], medium
    ))
    return executable, initial
end

function division_fixture(area)
    width = max(2, round(Int, sqrt(area)))
    height = max(2, cld(area, width))
    side = max(width, height) + 2
    cell = CellKind(:division_cell; extinction = RetireAtZero())
    medium = MediumKind(:division_medium)
    relation = SpatialRelation(:division_relation; neighborhood = VonNeumann())
    anchor = CellBinding(:division_anchor)
    divide = LifecycleProcess(
        :measured_division;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = Symbol(:LifecycleDivision_, area),
        statements = StatementSet((
            Lattice((side, side); max_cells = 2),
            cell,
            medium,
            relation,
            divide,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = zeros(Int, side, side)
    remaining = area
    for site in CartesianIndices(labels)
        remaining > 0 || break
        labels[site] = 1
        remaining -= 1
    end
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return executable, initial
end

function request_fixture(count; conflicting)
    cell = CellKind(:request_cell; extinction = RetireAtZero())
    medium = MediumKind(:request_medium)
    births = ntuple(count) do index
        LifecycleProcess(
            Symbol(:request_, index);
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(conflicting ? 1 : index),
                priority = conflicting ? index : 0,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    side = max(2, ceil(Int, sqrt(count)))
    system = PottsSystem(
        name = Symbol(:LifecycleRequests_, conflicting, :_, count),
        statements = StatementSet((
            Lattice((side, side); max_cells = count),
            cell,
            medium,
            births...,
            Protocol(
                Sweep();
                name = :main,
                lifecycle_conflicts = StableLifecyclePriority(),
            ),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    initial = PottsInitialState(ownership = LabelledCells(
        zeros(Int, side, side); cells = [], medium
    ))
    return executable, initial
end

function active_scan_fixture(capacity)
    cell = CellKind(:scan_cell; extinction = ForbidExtinction())
    medium = MediumKind(:scan_medium)
    anchor = CellBinding(:scan_anchor)
    dormant = LifecycleProcess(
        :scan_trigger;
        domain = cells(cell),
        anchor,
        expression = false,
        effects = (Transition(
            anchor,
            cell;
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    side = max(2, ceil(Int, sqrt(capacity)))
    system = PottsSystem(
        name = Symbol(:LifecycleActiveScan_, capacity),
        statements = StatementSet((
            Lattice((side, side); max_cells = capacity),
            cell,
            medium,
            dormant,
            Protocol(Sweep(); name = :main),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = zeros(Int, side, side)
    labels[1] = 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return executable, initial
end

function prepared_emit_runtime(executable, initial)
    runtime = runtime_for(executable, initial)
    workspace = runtime.lifecycle_workspace
    CorePotts._reset_lifecycle_workspace!(workspace)
    CorePotts._index_lifecycle_representative_sites!(runtime, workspace)
    return runtime
end

emit_lifecycle_requests!(runtime) = CorePotts._emit_lifecycle_requests!(
    runtime, runtime.program.lifecycle_plan, runtime.lifecycle_workspace
)

function cell_request_fixture(cell_count; competitors = 1)
    source = CellKind(:request_source; extinction = ForbidExtinction())
    destination = CellKind(
        :request_destination; extinction = ForbidExtinction()
    )
    medium = MediumKind(:cell_request_medium)
    anchor = CellBinding(:request_anchor)
    transitions = ntuple(competitors) do index
        LifecycleProcess(
            Symbol(:cell_request_, index);
            domain = cells(source),
            anchor,
            expression = true,
            effects = (Transition(
                anchor,
                destination;
                priority = index,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    side = max(2, ceil(Int, sqrt(cell_count)))
    system = PottsSystem(
        name = Symbol(:LifecycleCellRequests_, competitors, :_, cell_count),
        statements = StatementSet((
            Lattice((side, side); max_cells = cell_count),
            source,
            destination,
            medium,
            transitions...,
            Protocol(
                Sweep();
                name = :main,
                lifecycle_conflicts = StableLifecyclePriority(),
            ),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = zeros(Int, side, side)
    for cell in 1:cell_count
        labels[cell] = cell
    end
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = fill(source, cell_count), medium
    ))
    return executable, initial
end

function competing_division_fixture(area, competitors)
    width = max(2, round(Int, sqrt(area)))
    side = width + 2
    cell = CellKind(:competing_division_cell; extinction = RetireAtZero())
    medium = MediumKind(:competing_division_medium)
    relation = SpatialRelation(
        :competing_division_relation; neighborhood = VonNeumann()
    )
    anchor = CellBinding(:competing_division_anchor)
    divisions = ntuple(competitors) do index
        LifecycleProcess(
            Symbol(:competing_division_, index);
            domain = cells(cell),
            anchor,
            expression = true,
            effects = (Divide(
                anchor;
                geometry = SpecifiedNormalPlane((1.0, 0.0)),
                relation,
                side = CanonicalSide(),
                priority = index,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    system = PottsSystem(
        name = Symbol(:LifecycleCompetingDivision_, competitors, :_, area),
        statements = StatementSet((
            Lattice((side, side); max_cells = 2),
            cell,
            medium,
            relation,
            divisions...,
            Protocol(
                Sweep();
                name = :main,
                lifecycle_conflicts = StableLifecyclePriority(),
            ),
        )),
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = zeros(Int, side, side)
    for linear in 1:area
        labels[linear] = 1
    end
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [cell], medium
    ))
    return executable, initial
end

function staging_fixture(side, capacity)
    @variables staging_time staging_value(staging_time)
    source = CellKind(:staging_source; extinction = RetireAtZero())
    destination = CellKind(:staging_destination; extinction = RetireAtZero())
    medium = MediumKind(:staging_medium)
    state = CellState(
        staging_value;
        initial = 1.0,
        retirement = RetireTo(0.0),
        transition = Preserve(),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:staging_anchor)
    transition = LifecycleProcess(
        :measured_transition;
        domain = cells(source),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            destination;
            state = (state => Preserve(),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    system = PottsSystem(
        name = Symbol(:LifecycleStaging_, side, :_, capacity),
        statements = StatementSet((
            Lattice((side, side); max_cells = capacity),
            source,
            destination,
            medium,
            state,
            transition,
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [staging_value],
        independent_variables = [staging_time],
    )
    executable = _lower_lifecycle_benchmark(system)
    labels = zeros(Int, side, side)
    labels[1] = 1
    initial = PottsInitialState(ownership = LabelledCells(
        labels; cells = [source], medium
    ))
    return executable, initial
end

println("case,samples,median_ns,min_ns,max_ns,allocated_bytes")

for side in (32, 128, 512)
    executable, initial = cadence_fixture(side)
    measure_case(
        "no_descriptor_due_side_$side",
        () -> runtime_for(executable, initial; mcs = 0),
        CorePotts.execute_lifecycle!,
    )
    measure_case(
        "due_false_trigger_side_$side",
        () -> runtime_for(executable, initial; mcs = 1),
        CorePotts.execute_lifecycle!,
    )
    control_executable, control_initial = no_lifecycle_fixture(side)
    measure_case(
        "whole_mcs_without_lifecycle_side_$side",
        () -> runtime_for(control_executable, control_initial; mcs = 0),
        CorePotts.advance_mcs!,
    )
    measure_case(
        "whole_mcs_no_descriptor_due_side_$side",
        () -> runtime_for(executable, initial; mcs = 0),
        CorePotts.advance_mcs!,
    )
    measure_case(
        "whole_mcs_due_false_trigger_side_$side",
        () -> runtime_for(executable, initial; mcs = 1),
        CorePotts.advance_mcs!,
    )
end

for area in (16, 64, 256, 1024)
    executable, initial = division_fixture(area)
    measure_case(
        "one_division_area_$area",
        () -> runtime_for(executable, initial),
        CorePotts.execute_lifecycle!,
    )
end

for count in (4, 16, 64)
    for conflicting in (false, true)
        executable, initial = request_fixture(count; conflicting)
        label = conflicting ? "conflicting" : "independent"
        measure_case(
            "$(label)_requests_$count",
            () -> runtime_for(executable, initial),
            CorePotts.execute_lifecycle!,
        )
    end
end

for capacity in (64, 1024, 16384)
    executable, initial = active_scan_fixture(capacity)
    measure_case(
        "active_cell_scan_capacity_$capacity",
        () -> prepared_emit_runtime(executable, initial),
        emit_lifecycle_requests!,
    )
end

for cell_count in (32, 128, 512)
    for competitors in (1, 2)
        executable, initial = cell_request_fixture(
            cell_count; competitors
        )
        measure_case(
            "cell_requests_$(cell_count)_competitors_$competitors",
            () -> runtime_for(executable, initial),
            CorePotts.execute_lifecycle!,
        )
    end
end

for competitors in (1, 2, 4)
    executable, initial = competing_division_fixture(256, competitors)
    measure_case(
        "division_area_256_competitors_$competitors",
        () -> runtime_for(executable, initial),
        CorePotts.execute_lifecycle!,
    )
end

for (side, capacity) in ((32, 64), (128, 256), (512, 1024))
    executable, initial = staging_fixture(side, capacity)
    measure_case(
        "full_staging_side_$(side)_capacity_$capacity",
        () -> runtime_for(executable, initial),
        CorePotts.execute_lifecycle!,
    )
end
