using Test
import CorePotts

# Deliberately independent of CorePotts selection helpers and LocalMath.
# This serial test interpreter is the scientific decision oracle for canonical
# request identity, conflict policy, finite cell allocation, and publication
# order. Production code must never call it.

_selection_oracle_key(request) = request.key

function _selection_oracle_pair(left, right, requests)
    left_key = _selection_oracle_key(requests[left])
    right_key = _selection_oracle_key(requests[right])
    return left_key <= right_key ? (left, right) : (right, left)
end

# Physical-input differential oracle. Unlike the compact decision unit above,
# this path derives conflicts from anchors and planned sites, reproduces the
# request-index ordering independently, and is compared field-for-field with
# the production request-index and selection sequence.
_physical_identity_parts(value::UInt64) =
    (UInt32(value >> 32), UInt32(value & UInt64(typemax(UInt32))))

function _physical_request(
        identity::Integer, priority::Integer;
        active::Bool = true,
        effect = :transition,
        anchor::Integer = identity,
        generation::Integer = 1,
        sites = (),
        source_handle::Integer = identity,
        relationship::Bool = false,
    )
    source_identity = UInt64(identity)
    action_identity = UInt64(10_000 + identity)
    source_high, source_low = _physical_identity_parts(source_identity)
    action_high, action_low = _physical_identity_parts(action_identity)
    key = (
        source_high, source_low, action_high, action_low,
        Int32(anchor), UInt32(generation),
    )
    return (
        key,
        priority = Int32(priority),
        active,
        effect,
        anchor = Int32(anchor),
        generation = UInt32(generation),
        sites = Tuple(Int32.(sites)),
        source_handle = Int32(source_handle),
        source_identity,
        action_identity,
        relationship,
    )
end

function _physical_requests_conflict(left, right, relationship_edges)
    left.anchor > 0 && left.anchor == right.anchor && return true
    any(site -> site in right.sites, left.sites) && return true
    left.relationship && right.relationship || return false
    return any(relationship_edges) do edge
        left.anchor in edge && right.anchor in edge
    end
end

function _physical_status(
        code;
        source = 0,
        action_identity = 0,
        secondary_source = 0,
        anchor = 0,
        required = 0,
        available = 0,
        maximum = 0,
    )
    return CorePotts.ProgramStatus(
        code,
        Int32(1),
        CorePotts.ProgramStageSelection,
        Int32(source),
        UInt64(action_identity),
        Int32(secondary_source),
        Int32(anchor),
        CorePotts.LifecycleDetailNone,
        Int32(required),
        Int32(available),
        Int32(maximum),
    )
end

function _physical_selection_oracle(
        requests, cell_kinds, cell_generations, policy::Symbol,
        relationship_edges = (),
    )
    planning = sort!(
        findall(request -> request.active, requests);
        by = slot -> (
            requests[slot].priority,
            requests[slot].key...,
            -slot,
        ),
    )
    canonical = Int[]
    seen = Set{typeof(first(requests).key)}()
    for slot in planning
        requests[slot].key in seen && continue
        push!(seen, requests[slot].key)
        push!(canonical, slot)
    end
    selected = Int[]
    conflict = nothing
    if policy === :reject
        conflict_pairs = Tuple{Int,Int}[]
        for left_position in eachindex(canonical)
            for right_position in (left_position + 1):length(canonical)
                left = canonical[left_position]
                right = canonical[right_position]
                _physical_requests_conflict(
                    requests[left], requests[right], relationship_edges
                ) || continue
                push!(conflict_pairs, requests[left].key <= requests[right].key ?
                    (left, right) : (right, left))
            end
        end
        if isempty(conflict_pairs)
            append!(selected, canonical)
        else
            sort!(conflict_pairs; by = pair -> (
                requests[pair[1]].key..., requests[pair[2]].key...
            ))
            conflict = first(conflict_pairs)
        end
    else
        candidates = sort!(copy(canonical); by = slot -> (
            -Int64(requests[slot].priority), requests[slot].key..., slot
        ))
        for candidate in candidates
            blockers = filter(selected) do incumbent
                _physical_requests_conflict(
                    requests[incumbent], requests[candidate], relationship_edges
                )
            end
            any(incumbent -> requests[incumbent].priority >
                    requests[candidate].priority, blockers) && continue
            tied = filter(incumbent -> requests[incumbent].priority ==
                    requests[candidate].priority, blockers)
            if !isempty(tied)
                left = argmin(slot -> requests[slot].key, tied)
                conflict = requests[left].key <= requests[candidate].key ?
                    (left, candidate) : (candidate, left)
                break
            end
            push!(selected, candidate)
        end
    end
    canonical_mask = [slot in canonical for slot in eachindex(requests)]
    if conflict !== nothing
        left, right = conflict
        source = requests[left].source_handle
        first_source = findfirst(
            request -> request.source_handle == source, requests
        )
        status = _physical_status(
            CorePotts.ProgramStatusConflict;
            source,
            action_identity = requests[first_source].action_identity,
            secondary_source = requests[right].source_handle,
            anchor = requests[right].anchor,
        )
        return (
            planning_order = planning,
            canonical_mask,
            selected_mask = policy === :stable_priority ?
                [slot in selected for slot in eachindex(requests)] :
                falses(length(requests)),
            selected = Int[],
            conflict,
            high_water = Int32(0),
            free_cells = Int[],
            demands = Int[],
            allocations = zeros(Int32, length(requests)),
            ready = false,
            status,
        )
    end
    sort!(selected; by = slot -> (requests[slot].key..., slot))
    high_water = something(
        findlast(!iszero, cell_generations), 0
    )
    recycled = [cell for cell in eachindex(cell_kinds)
        if iszero(cell_kinds[cell]) && !iszero(cell_generations[cell])]
    virgin = [cell for cell in eachindex(cell_kinds)
        if iszero(cell_kinds[cell]) && iszero(cell_generations[cell]) &&
            cell > high_water]
    free_cells = (recycled..., virgin...)
    demands = [slot for slot in selected
        if requests[slot].effect in (:create, :divide)]
    allocations = zeros(Int32, length(requests))
    if length(demands) > length(free_cells)
        first_selected = first(selected)
        status = _physical_status(
            CorePotts.ProgramStatusCellCapacity;
            source = requests[first_selected].source_handle,
            action_identity = requests[first_selected].action_identity,
            required = length(demands),
            available = length(free_cells),
            maximum = length(cell_kinds),
        )
        return (
            planning_order = planning,
            canonical_mask,
            selected_mask = policy === :stable_priority ?
                [slot in selected for slot in eachindex(requests)] :
                falses(length(requests)),
            selected = Int[],
            conflict = nothing,
            high_water = Int32(high_water),
            free_cells = collect(free_cells),
            demands,
            allocations,
            ready = false,
            status,
        )
    end
    for (position, request) in pairs(demands)
        cell = free_cells[position]
        if cell_generations[cell] == typemax(UInt32)
            matching = findfirst(
                slot -> requests[slot].anchor == cell, selected
            )
            status = matching === nothing ? _physical_status(
                CorePotts.ProgramStatusGenerationOverflow; anchor = cell
            ) : _physical_status(
                CorePotts.ProgramStatusGenerationOverflow;
                source = requests[selected[matching]].source_handle,
                action_identity = requests[selected[matching]].action_identity,
                anchor = cell,
            )
            return (
                planning_order = planning,
                canonical_mask,
                selected_mask = policy === :stable_priority ?
                    [slot in selected for slot in eachindex(requests)] :
                    falses(length(requests)),
                selected = Int[],
                conflict = nothing,
                high_water = Int32(high_water),
                free_cells = collect(free_cells),
                demands,
                allocations,
                ready = false,
                status,
            )
        end
        allocations[request] = Int32(cell)
    end
    return (
        planning_order = planning,
        canonical_mask,
        selected_mask = policy === :stable_priority ?
            [slot in selected for slot in eachindex(requests)] :
            falses(length(requests)),
        selected,
        conflict = nothing,
        high_water = Int32(high_water),
        free_cells = collect(free_cells),
        demands,
        allocations,
        ready = true,
        status = CorePotts.ProgramStatus(),
    )
end

function _physical_descriptor(index, request)
    effect = request.effect === :create ?
        CorePotts.CreateCellLifecycleEffect :
        request.effect === :divide ? CorePotts.DivideCellLifecycleEffect :
        CorePotts.TransitionCellLifecycleEffect
    return CorePotts.LifecycleDescriptor{2,Float64}(
        request.source_handle,
        request.source_identity,
        request.action_identity,
        CorePotts.ModelLifecycleDomain,
        Int16(0),
        Int32(1),
        CorePotts.EveryMCSLifecycleCadence,
        Int32(1),
        effect,
        request.priority,
        CorePotts.FilterLifecycleInadmissible,
        Int16(2),
        Int16(1),
        CorePotts.NoLifecyclePlacement,
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        CorePotts.NoLifecyclePartition,
        Int32(0),
        false,
        (0.0, 0.0),
        (0.0, 0.0),
        CorePotts.CanonicalLifecycleSide,
        UInt16(0),
        UInt16(0),
        Int16(1),
        Int16(2),
        Int32(1),
        Int32(0),
        Int32(1),
        request.relationship ? Int32(1) : Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        true,
    )
end

function _production_selection_snapshot(
        requests, cell_kinds, cell_generations, policy::Symbol,
        relationship_edges = (),
    )
    descriptors = CorePotts.LifecycleDescriptor{2,Float64}[
        _physical_descriptor(index, request)
        for (index, request) in pairs(requests)
    ]
    conflict_policy = policy === :reject ?
        CorePotts.RejectLifecycleConflicts :
        CorePotts.StablePriorityLifecycleConflicts
    relationship_rules = isempty(relationship_edges) ?
        CorePotts.LifecycleRelationshipRule[] :
        CorePotts.LifecycleRelationshipRule[
            CorePotts.LifecycleRelationshipRule(
                Int32(1),
                CorePotts.RejectWhileLinkedLifecycleRelationship,
                Int16(2),
                Int16(2),
            ),
        ]
    plan = CorePotts.LifecycleExecutionPlan(
        descriptors,
        CorePotts.LifecycleEvaluatorStorage(
            Any[
                CorePotts.StaticEvaluator(
                    CorePotts.LiteralExpression(true)
                ) for _ in requests
            ],
            fill(:lifecycle_trigger, length(requests)),
        ),
        CorePotts.LifecycleStateRuleStorage(Any[]),
        relationship_rules,
        (),
        NTuple{2,Int16}[],
        CorePotts.LifecycleRelationStorage(Any[], Val(2)),
        conflict_policy,
        length(cell_kinds),
        length(requests),
        max(1, maximum(length(request.sites) for request in requests)),
        0,
        falses(2),
    )
    relationship_schema = isempty(relationship_edges) ? () : (
        CorePotts.RelationshipStoreSchema(
            length(relationship_edges),
            maximum(count(edge -> cell in edge, relationship_edges)
                for cell in eachindex(cell_kinds)),
        ),
    )
    program = test_program(
        CorePotts.SequentialProgramEngine();
        lifecycle_plan = plan,
        relationships = relationship_schema,
    )
    ownership = zeros(Int32, 6, 6)
    for cell in eachindex(cell_kinds)
        iszero(cell_kinds[cell]) || (ownership[cell] = Int32(cell))
    end
    relationship_state = if isempty(relationship_edges)
        ()
    else
        state = CorePotts.ProgramRelationshipState(
            Float64,
            length(relationship_edges),
            length(cell_kinds),
            maximum(count(edge -> cell in edge, relationship_edges)
                for cell in eachindex(cell_kinds)),
            0,
        )
        requests_to_apply = [
            CorePotts.CreateRelationshipRequest(
                edge[1], edge[2];
                generation_a = cell_generations[edge[1]],
                generation_b = cell_generations[edge[2]],
                identity = index,
            ) for (index, edge) in pairs(relationship_edges)
        ]
        CorePotts.apply_relationship_requests!(
            state,
            Int16.(cell_kinds),
            UInt32.(cell_generations),
            only(relationship_schema),
            requests_to_apply,
        )
        (state,)
    end
    initial = CorePotts.ProgramInitialState(
        ownership,
        Int16.(cell_kinds);
        scalar_type = Float64,
        cell_generations = UInt32.(cell_generations),
        relationships = relationship_state,
    )
    runtime = CorePotts.initialize_program(
        program, initial, Float64[], UInt64(0x8c4), UInt32(1)
    )
    workspace = runtime.lifecycle_workspace
    CorePotts._reset_lifecycle_workspace!(workspace)
    CorePotts.set_lifecycle_request_count!(workspace, length(requests))
    for (slot, request) in pairs(requests)
        source_high, source_low = _physical_identity_parts(
            request.source_identity
        )
        action_high, action_low = _physical_identity_parts(
            request.action_identity
        )
        workspace.descriptor[slot] = Int32(slot)
        workspace.anchor[slot] = request.anchor
        workspace.generation[slot] = request.generation
        workspace.request_priority[slot] = request.priority
        workspace.request_source_high[slot] = source_high
        workspace.request_source_low[slot] = source_low
        workspace.request_action_high[slot] = action_high
        workspace.request_action_low[slot] = action_low
        workspace.active[slot] = request.active
        workspace.planned_site_count[slot] = Int32(length(request.sites))
        for (position, site) in pairs(request.sites)
            workspace.planned_sites[position, slot] = site
        end
    end
    CorePotts._run_host_lifecycle_request_index!(runtime, workspace)
    CorePotts._run_host_lifecycle_selection!(runtime, workspace)
    selection = workspace.selection
    planning_count = Int(workspace.request_index.count[1])
    selected_count = Int(selection.selected_requests.count[1])
    free_count = Int(selection.free_cells.count[1])
    demand_count = Int(selection.demands.count[1])
    conflict = policy === :reject ? let witness = selection.conflict_witness[1]
        iszero(witness.left) ? nothing : (Int(witness.left), Int(witness.right))
    end : begin
        left = selection.conflict_left[1]
        iszero(left) ? nothing : (Int(left), Int(selection.conflict_right[1]))
    end
    return (
        planning_order = [Int(
            workspace.request_index.records.slot[position]
        ) for position in 1:planning_count],
        canonical_mask = collect(selection.canonical),
        selected_mask = collect(selection.selected),
        selected = [Int(selection.selected_requests.records.request[position])
            for position in 1:selected_count],
        conflict,
        high_water = selection.high_water[1],
        free_cells = [Int(selection.free_cells.records.cell[position])
            for position in 1:free_count],
        demands = [Int(selection.demands.records.request[position])
            for position in 1:demand_count],
        allocations = collect(selection.allocation),
        ready = selection.ready[1],
        status = workspace.status[1],
    )
end

@testset "lifecycle selection physical differential" begin
    cases = (
        (
            requests = (
                _physical_request(1, 90),
                _physical_request(1, 10),
                _physical_request(2, 30),
            ),
            kinds = Int16[0, 0, 0, 0],
            generations = UInt32[5, 0, 0, 0],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(1, 90; anchor = 1, sites = (8,)),
                _physical_request(2, 10; anchor = 2, sites = (8,)),
            ),
            kinds = Int16[2, 2, 0, 0],
            generations = UInt32[1, 1, 0, 0],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(1, 50; anchor = 1),
                _physical_request(2, 50; anchor = 1),
            ),
            kinds = Int16[2, 0, 0, 0],
            generations = UInt32[1, 0, 0, 0],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(3, 10; anchor = 3, sites = (7,)),
                _physical_request(1, 20; anchor = 1, sites = (7,)),
                _physical_request(2, 30; anchor = 2, sites = (7,)),
            ),
            kinds = Int16[2, 2, 2, 0],
            generations = UInt32[1, 1, 1, 0],
            policy = :reject,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(2, 1; effect = :create, anchor = 0),
                _physical_request(1, 90; effect = :create, anchor = 0),
            ),
            kinds = Int16[2],
            generations = UInt32[1],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(1, 20; effect = :create, anchor = 2),
            ),
            kinds = Int16[2, 0],
            generations = UInt32[1, typemax(UInt32)],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(1, 20; effect = :create, anchor = 1),
            ),
            kinds = Int16[2, 0],
            generations = UInt32[1, typemax(UInt32)],
            policy = :stable_priority,
            relationships = (),
        ),
        (
            requests = (
                _physical_request(
                    3, 100; anchor = 3, source_handle = 7
                ),
                _physical_request(
                    1, 50; anchor = 1, source_handle = 7,
                    relationship = true,
                ),
                _physical_request(
                    2, 50; anchor = 2, relationship = true
                ),
            ),
            kinds = Int16[2, 2, 2],
            generations = UInt32[1, 1, 1],
            policy = :stable_priority,
            relationships = ((1, 2),),
        ),
    )
    for case in cases
        oracle = _physical_selection_oracle(
            case.requests, case.kinds, case.generations, case.policy,
            case.relationships,
        )
        production = _production_selection_snapshot(
            case.requests, case.kinds, case.generations, case.policy,
            case.relationships,
        )
        @test production == oracle
    end
end

function _selection_oracle(
        requests, conflicts, cell_kinds, cell_generations, policy::Symbol
    )
    active = sort!(
        findall(request -> request.active, requests);
        by = request -> (_selection_oracle_key(requests[request]), request),
    )
    canonical = Int[]
    previous = nothing
    for request in active
        key = _selection_oracle_key(requests[request])
        key == previous && continue
        push!(canonical, request)
        previous = key
    end

    selected = Int[]
    conflict = nothing
    if policy === :reject
        conflict_pairs = Tuple{Int, Int}[]
        for left_position in eachindex(canonical)
            for right_position in (left_position + 1):length(canonical)
                left = canonical[left_position]
                right = canonical[right_position]
                conflicts[left, right] || conflicts[right, left] || continue
                push!(
                    conflict_pairs,
                    _selection_oracle_pair(left, right, requests),
                )
            end
        end
        if isempty(conflict_pairs)
            append!(selected, canonical)
        else
            sort!(conflict_pairs; by = pair -> (
                _selection_oracle_key(requests[pair[1]])...,
                _selection_oracle_key(requests[pair[2]])...,
            ))
            conflict = first(conflict_pairs)
        end
    elseif policy === :stable_priority
        candidates = sort!(copy(canonical); by = request -> (
            -Int64(requests[request].priority),
            _selection_oracle_key(requests[request]),
            request,
        ))
        for request in candidates
            blockers = filter(selected) do incumbent
                conflicts[incumbent, request] || conflicts[request, incumbent]
            end
            any(incumbent -> requests[incumbent].priority >
                    requests[request].priority, blockers) && continue
            tie = findfirst(incumbent -> requests[incumbent].priority ==
                    requests[request].priority, blockers)
            if tie !== nothing
                conflict = _selection_oracle_pair(
                    blockers[tie], request, requests
                )
                empty!(selected)
                break
            end
            push!(selected, request)
        end
    else
        throw(ArgumentError("unknown lifecycle selection oracle policy"))
    end

    conflict === nothing || return (
        status = :conflict,
        canonical,
        selected = Int[],
        conflict,
        free_cells = Int[],
        demands = Int[],
        allocations = Dict{Int, Int}(),
    )

    sort!(selected; by = request -> (
        _selection_oracle_key(requests[request]), request
    ))
    demands = filter(
        request -> requests[request].effect in (:create, :divide), selected
    )
    high_water = findlast(value -> !iszero(value), cell_generations)
    high_water === nothing && (high_water = 0)
    recycled = Int[]
    virgin = Int[]
    for cell in eachindex(cell_kinds)
        iszero(cell_kinds[cell]) || continue
        if !iszero(cell_generations[cell])
            push!(recycled, cell)
        elseif cell > high_water
            push!(virgin, cell)
        end
    end
    free_cells = (recycled..., virgin...)
    length(demands) <= length(free_cells) || return (
        status = :capacity,
        canonical,
        selected = Int[],
        conflict = nothing,
        free_cells = collect(free_cells),
        demands,
        allocations = Dict{Int, Int}(),
    )
    allocations = Dict{Int, Int}()
    for (ordinal, request) in pairs(demands)
        cell = free_cells[ordinal]
        cell_generations[cell] == typemax(UInt32) && return (
            status = :generation_overflow,
            canonical,
            selected = Int[],
            conflict = nothing,
            overflow = (ordinal, request, cell),
            free_cells = collect(free_cells),
            demands,
            allocations = Dict{Int, Int}(),
        )
        allocations[request] = cell
    end
    return (
        status = :success,
        canonical,
        selected,
        conflict = nothing,
        free_cells = collect(free_cells),
        demands,
        allocations,
    )
end

function _oracle_request(
        key, priority; active = true, effect = :transition
    )
    return (; key, priority = Int32(priority), active, effect)
end

@testset "independent lifecycle selection decision oracle" begin
    key(value) = (
        UInt32(value), UInt32(0), UInt32(0), UInt32(0), Int32(value),
        UInt32(1),
    )
    requests = [
        _oracle_request(key(3), 90; effect = :create),
        _oracle_request(key(1), 10; effect = :divide),
        _oracle_request(key(2), 50),
        _oracle_request(key(1), 99; effect = :divide),
    ]
    no_conflicts = falses(4, 4)
    success = _selection_oracle(
        requests,
        no_conflicts,
        Int16[1, 0, 1, 0, 0],
        UInt32[1, 7, 2, 0, 0],
        :stable_priority,
    )
    @test success.status === :success
    @test success.canonical == [2, 3, 1]
    @test success.selected == [2, 3, 1]
    @test success.free_cells == [2, 4, 5]
    @test success.demands == [2, 1]
    @test success.allocations == Dict(2 => 2, 1 => 4)

    dominance = copy(no_conflicts)
    dominance[1, 3] = true
    dominant = _selection_oracle(
        requests, dominance, zeros(Int16, 5), zeros(UInt32, 5),
        :stable_priority,
    )
    @test dominant.status === :success
    @test dominant.selected == [2, 1]

    tied_requests = copy(requests)
    tied_requests[3] = _oracle_request(key(2), 90)
    tied = _selection_oracle(
        tied_requests, dominance, zeros(Int16, 5), zeros(UInt32, 5),
        :stable_priority,
    )
    @test tied.status === :conflict
    @test tied.conflict == (3, 1)

    reject_conflicts = copy(no_conflicts)
    reject_conflicts[1, 3] = true
    reject_conflicts[2, 3] = true
    rejected = _selection_oracle(
        requests, reject_conflicts, zeros(Int16, 5), zeros(UInt32, 5),
        :reject,
    )
    @test rejected.status === :conflict
    @test rejected.conflict == (2, 3)

    capacity = _selection_oracle(
        requests, no_conflicts, Int16[1, 0, 1], UInt32[1, 7, 2],
        :stable_priority,
    )
    @test capacity.status === :capacity

    overflow = _selection_oracle(
        requests,
        no_conflicts,
        Int16[1, 0, 1, 0],
        UInt32[1, typemax(UInt32), 2, 0],
        :stable_priority,
    )
    @test overflow.status === :generation_overflow
    @test overflow.overflow == (1, 2, 2)
end
