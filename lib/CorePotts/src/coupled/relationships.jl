struct StableRelationshipPriority end

abstract type AbstractRelationshipRequest end
struct CreateRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
CreateRelationship(left, right, payload; priority::Integer = 0) =
    CreateRelationship(left, right, payload, Int32(priority))
struct RemoveRelationship <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    priority::Int32
end
RemoveRelationship(left, right; priority::Integer = 0) =
    RemoveRelationship(left, right, Int32(priority))
struct RetuneRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
RetuneRelationship(left, right, payload; priority::Integer = 0) =
    RetuneRelationship(left, right, payload, Int32(priority))

const RELATIONSHIP_REMOVE_REQUEST = UInt8(1)
const RELATIONSHIP_RETUNE_REQUEST = UInt8(2)
const RELATIONSHIP_CREATE_REQUEST = UInt8(3)

struct RelationshipTransactionWorkspace{
        E <: AbstractVector{UInt32}, G <: AbstractVector{UInt64},
        P <: AbstractVector, A <: AbstractVector{UInt8},
        C <: AbstractVector{UInt32}, K <: AbstractVector{UInt8},
        R <: AbstractVector{Int32}}
    candidate_endpoint_a::E
    candidate_generation_a::G
    candidate_endpoint_b::E
    candidate_generation_b::G
    candidate_payload::P
    candidate_active::A
    candidate_count::C
    request_kind::K
    request_endpoint_a::E
    request_generation_a::G
    request_endpoint_b::E
    request_generation_b::G
    request_payload::P
    request_priority::R
    request_count::C
    status::C
    failing_request::C
end

function RelationshipTransactionWorkspace(
        state::RelationshipState; request_capacity::Integer =
            Int(state.declaration.capacity.value))
    request_capacity > 0 || throw(ArgumentError(
        "relationship request capacity must be positive"))
    candidate_endpoint_a = similar(state.endpoint_a)
    candidate_generation_a = similar(state.generation_a)
    candidate_endpoint_b = similar(state.endpoint_b)
    candidate_generation_b = similar(state.generation_b)
    candidate_payload = similar(state.payload)
    candidate_active = similar(state.active)
    request_endpoint_a = similar(state.endpoint_a, UInt32, request_capacity)
    request_generation_a = similar(
        state.generation_a, UInt64, request_capacity)
    request_endpoint_b = similar(state.endpoint_b, UInt32, request_capacity)
    request_generation_b = similar(
        state.generation_b, UInt64, request_capacity)
    request_payload = similar(state.payload, eltype(state.payload), request_capacity)
    request_kind = similar(state.active, UInt8, request_capacity)
    request_priority = similar(state.endpoint_a, Int32, request_capacity)
    candidate_count = similar(state.count)
    request_count = similar(state.count)
    status = similar(state.count)
    failing_request = similar(state.count)
    for array in (
            candidate_endpoint_a, candidate_generation_a,
            candidate_endpoint_b, candidate_generation_b,
            candidate_active, request_endpoint_a, request_generation_a,
            request_endpoint_b, request_generation_b, request_kind,
            request_priority, candidate_count, request_count,
            status, failing_request)
        fill!(array, zero(eltype(array)))
    end
    return RelationshipTransactionWorkspace(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_priority, request_count, status, failing_request)
end

function Adapt.adapt_structure(to,
        workspace::RelationshipTransactionWorkspace)
    return RelationshipTransactionWorkspace(
        Adapt.adapt(to, workspace.candidate_endpoint_a),
        Adapt.adapt(to, workspace.candidate_generation_a),
        Adapt.adapt(to, workspace.candidate_endpoint_b),
        Adapt.adapt(to, workspace.candidate_generation_b),
        Adapt.adapt(to, workspace.candidate_payload),
        Adapt.adapt(to, workspace.candidate_active),
        Adapt.adapt(to, workspace.candidate_count),
        Adapt.adapt(to, workspace.request_kind),
        Adapt.adapt(to, workspace.request_endpoint_a),
        Adapt.adapt(to, workspace.request_generation_a),
        Adapt.adapt(to, workspace.request_endpoint_b),
        Adapt.adapt(to, workspace.request_generation_b),
        Adapt.adapt(to, workspace.request_payload),
        Adapt.adapt(to, workspace.request_priority),
        Adapt.adapt(to, workspace.request_count),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_request))
end

@inline _relationship_request_kind(::RemoveRelationship) =
    RELATIONSHIP_REMOVE_REQUEST
@inline _relationship_request_kind(::RetuneRelationship) =
    RELATIONSHIP_RETUNE_REQUEST
@inline _relationship_request_kind(::CreateRelationship) =
    RELATIONSHIP_CREATE_REQUEST

function stage_relationship_requests!(
        workspace::RelationshipTransactionWorkspace,
        declaration::RelationshipSet, requests)
    ordered = collect(requests)
    all(request -> request isa AbstractRelationshipRequest, ordered) ||
        throw(ArgumentError(
            "relationship transaction contains an untyped request"))
    sort!(ordered; by = _request_key)
    length(ordered) <= length(workspace.request_kind) || throw(
        RelationshipCapacityError(
            declaration.name, length(ordered),
            UInt32(length(workspace.request_kind))))
    previous = nothing
    for (index, request) in enumerate(ordered)
        left, right = _canonical_endpoints(
            declaration, request.left, request.right)
        key = (left, right)
        key == previous && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        previous = key
        payload = request isa RemoveRelationship ?
            workspace.request_payload[index] :
            convert(eltype(workspace.request_payload), request.payload)
        @inbounds begin
            workspace.request_kind[index] =
                _relationship_request_kind(request)
            workspace.request_endpoint_a[index] = value(left.cell)
            workspace.request_generation_a[index] =
                value(left.generation)
            workspace.request_endpoint_b[index] = value(right.cell)
            workspace.request_generation_b[index] =
                value(right.generation)
            request isa RemoveRelationship ||
                (workspace.request_payload[index] = payload)
            workspace.request_priority[index] = request.priority
        end
    end
    workspace.request_count[1] = UInt32(length(ordered))
    return workspace
end

function clear_relationship_requests!(
        workspace::RelationshipTransactionWorkspace)
    workspace.request_count[1] = UInt32(0)
    return workspace
end

@inline function _relationship_endpoint_is_current(
        active, generations, endpoint::UInt32, generation::UInt64)
    return UInt32(1) <= endpoint <= UInt32(length(active)) &&
        @inbounds(active[Int(endpoint)] != zero(eltype(active)) &&
            generations[Int(endpoint)] == generation)
end

@inline function _relationship_raw_edge_index(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, left, left_generation, right, right_generation)
    for index in 1:count
        @inbounds if active[index] != UInt8(0) &&
                endpoint_a[index] == left &&
                generation_a[index] == left_generation &&
                endpoint_b[index] == right &&
                generation_b[index] == right_generation
            return index
        end
    end
    return 0
end

@inline function _relationship_raw_degree(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, endpoint, generation)
    degree = 0
    for index in 1:count
        @inbounds active[index] == UInt8(0) && continue
        @inbounds degree += (
            (endpoint_a[index] == endpoint &&
             generation_a[index] == generation) ||
            (endpoint_b[index] == endpoint &&
             generation_b[index] == generation))
    end
    return degree
end

@inline function _relationship_raw_copy!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, destination, source)
    @inbounds begin
        endpoint_a[destination] = endpoint_a[source]
        generation_a[destination] = generation_a[source]
        endpoint_b[destination] = endpoint_b[source]
        generation_b[destination] = generation_b[source]
        payload[destination] = payload[source]
        active[destination] = active[source]
    end
    return nothing
end

@inline function _relationship_raw_less(
        left_a, left_ga, left_b, left_gb,
        right_a, right_ga, right_b, right_gb)
    left_a != right_a && return left_a < right_a
    left_ga != right_ga && return left_ga < right_ga
    left_b != right_b && return left_b < right_b
    return left_gb < right_gb
end

@kernel function _relationship_initialize_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, status, failing_request)
    index = @index(Global, Linear)
    @inbounds begin
        candidate_endpoint_a[index] = endpoint_a[index]
        candidate_generation_a[index] = generation_a[index]
        candidate_endpoint_b[index] = endpoint_b[index]
        candidate_generation_b[index] = generation_b[index]
        candidate_payload[index] = payload[index]
        candidate_active[index] = active[index]
        if index == 1
            candidate_count[1] = count[1]
            status[1] = UInt32(0)
            failing_request[1] = UInt32(0)
        end
    end
end

@kernel function _relationship_apply_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_count, cell_active, cell_generations,
        directed, maximum_degree, status, failing_request)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        prior_a = UInt32(0)
        prior_ga = UInt64(0)
        prior_b = UInt32(0)
        prior_gb = UInt64(0)
        for request_index in 1:Int(@inbounds request_count[1])
            kind = @inbounds request_kind[request_index]
            left = @inbounds request_endpoint_a[request_index]
            left_generation =
                @inbounds request_generation_a[request_index]
            right = @inbounds request_endpoint_b[request_index]
            right_generation =
                @inbounds request_generation_b[request_index]
            if !directed && _relationship_raw_less(
                    right, right_generation, left, left_generation,
                    left, left_generation, right, right_generation)
                left, right = right, left
                left_generation, right_generation =
                    right_generation, left_generation
            end
            code = UInt32(0)
            if left == right && left_generation == right_generation
                code = UInt32(1)
            elseif !_relationship_endpoint_is_current(
                    cell_active, cell_generations, left, left_generation) ||
                    !_relationship_endpoint_is_current(
                        cell_active, cell_generations, right, right_generation)
                code = UInt32(2)
            elseif request_index > 1 &&
                    left == prior_a && left_generation == prior_ga &&
                    right == prior_b && right_generation == prior_gb
                code = UInt32(3)
            else
                edge_index = _relationship_raw_edge_index(
                    candidate_endpoint_a, candidate_generation_a,
                    candidate_endpoint_b, candidate_generation_b,
                    candidate_active, count,
                    left, left_generation, right, right_generation)
                if kind == RELATIONSHIP_REMOVE_REQUEST
                    if edge_index != 0
                        for source in (edge_index + 1):count
                            _relationship_raw_copy!(
                                candidate_endpoint_a,
                                candidate_generation_a,
                                candidate_endpoint_b,
                                candidate_generation_b,
                                candidate_payload, candidate_active,
                                source - 1, source)
                        end
                        @inbounds candidate_active[count] = UInt8(0)
                        count -= 1
                    end
                elseif kind == RELATIONSHIP_RETUNE_REQUEST
                    if edge_index == 0
                        code = UInt32(4)
                    else
                        @inbounds candidate_payload[edge_index] =
                            request_payload[request_index]
                    end
                elseif kind == RELATIONSHIP_CREATE_REQUEST
                    if edge_index != 0
                        code = UInt32(5)
                    elseif count >= length(candidate_active)
                        code = UInt32(6)
                    elseif _relationship_raw_degree(
                            candidate_endpoint_a, candidate_generation_a,
                            candidate_endpoint_b, candidate_generation_b,
                            candidate_active, count,
                            left, left_generation) >= maximum_degree ||
                            _relationship_raw_degree(
                                candidate_endpoint_a, candidate_generation_a,
                                candidate_endpoint_b, candidate_generation_b,
                                candidate_active, count,
                                right, right_generation) >= maximum_degree
                        code = UInt32(7)
                    else
                        insertion = count + 1
                        for index in 1:count
                            @inbounds if _relationship_raw_less(
                                    left, left_generation,
                                    right, right_generation,
                                    candidate_endpoint_a[index],
                                    candidate_generation_a[index],
                                    candidate_endpoint_b[index],
                                    candidate_generation_b[index])
                                insertion = index
                                break
                            end
                        end
                        for destination in (count + 1):-1:(insertion + 1)
                            _relationship_raw_copy!(
                                candidate_endpoint_a,
                                candidate_generation_a,
                                candidate_endpoint_b,
                                candidate_generation_b,
                                candidate_payload, candidate_active,
                                destination, destination - 1)
                        end
                        @inbounds begin
                            candidate_endpoint_a[insertion] = left
                            candidate_generation_a[insertion] =
                                left_generation
                            candidate_endpoint_b[insertion] = right
                            candidate_generation_b[insertion] =
                                right_generation
                            candidate_payload[insertion] =
                                request_payload[request_index]
                            candidate_active[insertion] = UInt8(1)
                        end
                        count += 1
                    end
                else
                    code = UInt32(8)
                end
            end
            if code != UInt32(0)
                @inbounds begin
                    status[1] = code
                    failing_request[1] = UInt32(request_index)
                end
                break
            end
            prior_a, prior_ga, prior_b, prior_gb =
                left, left_generation, right, right_generation
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

@kernel function _relationship_commit_transaction!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, publication_epoch,
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count, status)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        endpoint_a[index] = candidate_endpoint_a[index]
        generation_a[index] = candidate_generation_a[index]
        endpoint_b[index] = candidate_endpoint_b[index]
        generation_b[index] = candidate_generation_b[index]
        payload[index] = candidate_payload[index]
        active[index] = candidate_active[index]
        if index == 1
            count[1] = candidate_count[1]
            publication_epoch[1] += UInt64(1)
        end
    end
end

function apply_relationship_requests!(
        plan::ExecutionPlan, scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    execution = scientific_execution(scientific)
    core = execution.core
    arrays = (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, workspace.status,
        workspace.failing_request,
        core.active, core.generations)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable relationship storage has a backend mismatch"))
    capacity = length(state.active)
    all(==(capacity), map(length, (
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active))) ||
        throw(DimensionMismatch(
            "portable relationship capacities differ"))
    initialize = _execution_kernel(
        plan, _relationship_initialize_transaction!, capacity)
    launch!(plan, initialize,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        workspace.status, workspace.failing_request;
        ndrange = capacity)
    apply = _execution_kernel(
        plan, _relationship_apply_transaction!, 1)
    launch!(plan, apply,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        workspace.request_kind,
        workspace.request_endpoint_a,
        workspace.request_generation_a,
        workspace.request_endpoint_b,
        workspace.request_generation_b,
        workspace.request_payload,
        workspace.request_count, core.active, core.generations,
        state.declaration.directed,
        Int(state.declaration.maximum_degree),
        workspace.status, workspace.failing_request;
        ndrange = 1)
    commit = _execution_kernel(
        plan, _relationship_commit_transaction!, capacity)
    launch!(plan, commit,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count, workspace.status;
        ndrange = capacity)
    return state
end

function synchronize_relationship_status!(
        plan::ExecutionPlan,
        workspace::RelationshipTransactionWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_request))
    throw(ArgumentError(
        "relationship transaction failed with status $status at request $failing"))
end

struct ElasticLinkRetune{PROPERTY, S, T <: AbstractFloat}
    name::Symbol
    relationships::Symbol
    scope::S
    property::Symbol
    parameters::ElasticLinkParameters{T}
    version::VersionNumber
end
function ElasticLinkRetune(name::Symbol,
        relationships::Union{Symbol, RelationshipSet}, scope;
        property::Symbol, strength::T, target_length::T,
        maximum_length::T,
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    parameters = ElasticLinkParameters(
        strength, target_length, maximum_length)
    return ElasticLinkRetune{
        property, typeof(scope), T}(
        name,
        relationships isa Symbol ? relationships : relationships.name,
        scope, property, parameters, version)
end
component_identity(process::ElasticLinkRetune) =
    ComponentIdentity(
        process.name, process.version, :relationship_retune)
component_semantic_data(process::ElasticLinkRetune) = (
    relationships = process.relationships,
    scope = process.scope, property = process.property,
    parameters = process.parameters)
process_reads(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:ownership, :cells))
process_writes(process::ElasticLinkRetune) = (
    (:relationships, process.relationships),
    (:cell_property, process.property))

struct ElasticLinkRetuneWorkspace{
        P <: AbstractVector, T <: AbstractVector,
        C <: AbstractVector{UInt32}}
    candidate_property::P
    candidate_strength::T
    candidate_target_length::T
    candidate_maximum_length::T
    status::C
    failing_edge::C
end

function ElasticLinkRetuneWorkspace(
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        property_values::AbstractVector{T}) where {D, T}
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    status = similar(state.count)
    failing_edge = similar(state.count)
    fill!(status, UInt32(0))
    fill!(failing_edge, UInt32(0))
    return ElasticLinkRetuneWorkspace(
        similar(property_values),
        similar(payload.strength),
        similar(payload.target_length),
        similar(payload.maximum_length),
        status, failing_edge)
end

function Adapt.adapt_structure(to,
        workspace::ElasticLinkRetuneWorkspace)
    return ElasticLinkRetuneWorkspace(
        Adapt.adapt(to, workspace.candidate_property),
        Adapt.adapt(to, workspace.candidate_strength),
        Adapt.adapt(to, workspace.candidate_target_length),
        Adapt.adapt(to, workspace.candidate_maximum_length),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_edge))
end

function apply_elastic_link_retune!(
        logical::LogicalPottsState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    property = property_values(logical, process.property)
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "elastic retune cell-property capacities differ"))
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    copyto!(workspace.candidate_property, property)
    copyto!(workspace.candidate_strength, payload.strength)
    copyto!(
        workspace.candidate_target_length, payload.target_length)
    copyto!(
        workspace.candidate_maximum_length, payload.maximum_length)
    fill!(workspace.status, UInt32(0))
    fill!(workspace.failing_edge, UInt32(0))
    for index in 1:_relationship_count(state)
        edge = _relationship_edge(state, index)
        for endpoint in (edge.left, edge.right)
            if !is_active(logical, endpoint.cell) ||
                    generation(logical, endpoint.cell) !=
                        endpoint.generation
                workspace.status[1] = UInt32(1)
                workspace.failing_edge[1] = UInt32(index)
                throw(ArgumentError(
                    "elastic retune encountered a stale endpoint at edge $index"))
            end
        end
        @inbounds begin
            workspace.candidate_strength[index] =
                process.parameters.strength
            workspace.candidate_target_length[index] =
                process.parameters.target_length
            workspace.candidate_maximum_length[index] =
                process.parameters.maximum_length
        end
    end
    for slot in eachindex(property)
        cell = CellID(slot)
        is_active(logical, cell) || continue
        _cell_scope_matches_exchange(
            process.scope, logical, cell) || continue
        @inbounds workspace.candidate_property[slot] =
            process.parameters.strength
    end
    copyto!(property, workspace.candidate_property)
    copyto!(payload.strength, workspace.candidate_strength)
    copyto!(
        payload.target_length, workspace.candidate_target_length)
    copyto!(
        payload.maximum_length, workspace.candidate_maximum_length)
    state.publication_epoch[1] += UInt64(1)
    return state
end

@inline function _record_relationship_failure!(
        status, failing_edge, code, index)
    Atomix.@atomic max(status[1], UInt32(code))
    Atomix.@atomic min(failing_edge[1], UInt32(index))
    return nothing
end

@kernel function _elastic_retune_initialize!(
        candidate_property, property,
        candidate_strength, strength,
        candidate_target_length, target_length,
        candidate_maximum_length, maximum_length,
        status, failing_edge, edge_capacity)
    index = @index(Global, Linear)
    if index <= length(property)
        @inbounds candidate_property[index] = property[index]
    end
    if index <= edge_capacity
        @inbounds begin
            candidate_strength[index] = strength[index]
            candidate_target_length[index] = target_length[index]
            candidate_maximum_length[index] = maximum_length[index]
        end
    end
    if index == 1
        @inbounds begin
            status[1] = UInt32(0)
            failing_edge[1] = typemax(UInt32)
        end
    end
end

@kernel function _elastic_retune_apply!(
        candidate_property,
        candidate_strength, candidate_target_length,
        candidate_maximum_length,
        relationship_endpoint_a, relationship_generation_a,
        relationship_endpoint_b, relationship_generation_b,
        relationship_active, relationship_count,
        cell_active, cell_generations, cell_types, scope_type,
        strength, target_length, maximum_length,
        status, failing_edge)
    index = @index(Global, Linear)
    if index <= length(candidate_property)
        @inbounds if cell_active[index] != zero(eltype(cell_active)) &&
                _portable_cell_eligible(scope_type, cell_types[index])
            candidate_property[index] = strength
        end
    end
    if index <= Int(@inbounds relationship_count[1]) &&
            @inbounds(relationship_active[index] != UInt8(0))
        left = @inbounds relationship_endpoint_a[index]
        left_generation =
            @inbounds relationship_generation_a[index]
        right = @inbounds relationship_endpoint_b[index]
        right_generation =
            @inbounds relationship_generation_b[index]
        if _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            @inbounds begin
                candidate_strength[index] = strength
                candidate_target_length[index] = target_length
                candidate_maximum_length[index] = maximum_length
            end
        else
            _record_relationship_failure!(
                status, failing_edge, 1, index)
        end
    end
end

@kernel function _elastic_retune_commit!(
        property, candidate_property,
        strength, candidate_strength,
        target_length, candidate_target_length,
        maximum_length, candidate_maximum_length,
        publication_epoch, status, edge_capacity)
    index = @index(Global, Linear)
    @inbounds if status[1] == UInt32(0)
        index <= length(property) &&
            (property[index] = candidate_property[index])
        if index <= edge_capacity
            strength[index] = candidate_strength[index]
            target_length[index] = candidate_target_length[index]
            maximum_length[index] =
                candidate_maximum_length[index]
        end
        index == 1 &&
            (publication_epoch[1] += UInt64(1))
    end
end

function apply_elastic_link_retune!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState{
            D, ElasticLinkParameters{T}},
        process::ElasticLinkRetune,
        workspace::ElasticLinkRetuneWorkspace) where {D, T}
    process.relationships === state.declaration.name ||
        throw(ArgumentError(
            "elastic retune targets a different relationship set"))
    execution = scientific_execution(scientific)
    core = execution.core
    property = getproperty(core.properties, process.property)
    payload = state.payload
    payload isa ElasticLinkColumns || throw(ArgumentError(
        "elastic relationship state lacks SoA payload columns"))
    arrays = (
        property, payload.strength, payload.target_length,
        payload.maximum_length, state.endpoint_a,
        state.generation_a, state.endpoint_b,
        state.generation_b, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        workspace.status, workspace.failing_edge,
        core.active, core.generations, core.cell_types)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable elastic-retune storage has a backend mismatch"))
    length(property) == length(workspace.candidate_property) ||
        throw(DimensionMismatch(
            "portable elastic-retune cell capacities differ"))
    edge_capacity = length(state.active)
    all(==(edge_capacity), map(length, (
        payload.strength, payload.target_length,
        payload.maximum_length,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length))) ||
        throw(DimensionMismatch(
            "portable elastic-retune edge capacities differ"))
    ndrange = max(length(property), edge_capacity)
    initialize = _execution_kernel(
        plan, _elastic_retune_initialize!, ndrange)
    launch!(plan, initialize,
        workspace.candidate_property, property,
        workspace.candidate_strength, payload.strength,
        workspace.candidate_target_length, payload.target_length,
        workspace.candidate_maximum_length, payload.maximum_length,
        workspace.status, workspace.failing_edge, edge_capacity;
        ndrange)
    scope_type = _portable_scope_type(process.scope)
    apply = _execution_kernel(
        plan, _elastic_retune_apply!, ndrange)
    launch!(plan, apply,
        workspace.candidate_property,
        workspace.candidate_strength,
        workspace.candidate_target_length,
        workspace.candidate_maximum_length,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.active, state.count,
        core.active, core.generations, core.cell_types,
        scope_type, process.parameters.strength,
        process.parameters.target_length,
        process.parameters.maximum_length,
        workspace.status, workspace.failing_edge;
        ndrange)
    commit = _execution_kernel(
        plan, _elastic_retune_commit!, ndrange)
    launch!(plan, commit,
        property, workspace.candidate_property,
        payload.strength, workspace.candidate_strength,
        payload.target_length,
        workspace.candidate_target_length,
        payload.maximum_length,
        workspace.candidate_maximum_length,
        state.publication_epoch, workspace.status,
        edge_capacity; ndrange)
    return state
end

function synchronize_elastic_retune_status!(
        plan::ExecutionPlan,
        workspace::ElasticLinkRetuneWorkspace)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    status = only(Adapt.adapt(Array, workspace.status))
    iszero(status) && return workspace
    failing = only(Adapt.adapt(Array, workspace.failing_edge))
    failing == typemax(UInt32) && (failing = UInt32(0))
    throw(ArgumentError(
        "elastic relationship retune failed with status $status at edge $failing"))
end

@kernel function _relationship_cleanup_transaction!(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        cell_active, cell_generations)
    lane = @index(Global, Linear)
    if lane == 1
        count = Int(@inbounds candidate_count[1])
        index = 1
        while index <= count
            left = @inbounds candidate_endpoint_a[index]
            left_generation =
                @inbounds candidate_generation_a[index]
            right = @inbounds candidate_endpoint_b[index]
            right_generation =
                @inbounds candidate_generation_b[index]
            current = _relationship_endpoint_is_current(
                cell_active, cell_generations,
                left, left_generation) &&
                _relationship_endpoint_is_current(
                    cell_active, cell_generations,
                    right, right_generation)
            if current
                index += 1
            else
                for source in (index + 1):count
                    _relationship_raw_copy!(
                        candidate_endpoint_a,
                        candidate_generation_a,
                        candidate_endpoint_b,
                        candidate_generation_b,
                        candidate_payload, candidate_active,
                        source - 1, source)
                end
                @inbounds candidate_active[count] = UInt8(0)
                count -= 1
            end
        end
        @inbounds candidate_count[1] = UInt32(count)
    end
end

function cleanup_relationships!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        state::RelationshipState,
        workspace::RelationshipTransactionWorkspace)
    state.declaration.endpoint_lifecycle isa RemoveIncidentEdges ||
        throw(ArgumentError(
            "portable relationship cleanup requires RemoveIncidentEdges"))
    execution = scientific_execution(scientific)
    core = execution.core
    capacity = length(state.active)
    initialize = _execution_kernel(
        plan, _relationship_initialize_transaction!, capacity)
    launch!(plan, initialize,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        workspace.status, workspace.failing_request;
        ndrange = capacity)
    cleanup = _execution_kernel(
        plan, _relationship_cleanup_transaction!, 1)
    launch!(plan, cleanup,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count,
        core.active, core.generations;
        ndrange = 1)
    commit = _execution_kernel(
        plan, _relationship_commit_transaction!, capacity)
    launch!(plan, commit,
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch,
        workspace.candidate_endpoint_a,
        workspace.candidate_generation_a,
        workspace.candidate_endpoint_b,
        workspace.candidate_generation_b,
        workspace.candidate_payload,
        workspace.candidate_active,
        workspace.candidate_count, workspace.status;
        ndrange = capacity)
    return state
end

"""Atomic relationship transaction planner over one common graph/cell snapshot."""
struct RelationshipDynamics{L, C}
    name::Symbol
    relationships::Symbol
    law::L
    conflicts::C
    version::VersionNumber
end
function RelationshipDynamics(name::Symbol,
        relationships::Union{Symbol, RelationshipSet};
        law = nothing, create = nothing, remove = nothing, update = nothing,
        conflicts = StableRelationshipPriority(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION)
    supplied = count(value -> value !== nothing, (create, remove, update))
    if law !== nothing && supplied > 0
        throw(ArgumentError(
            "RelationshipDynamics accepts either law or create/remove/update policies"))
    end
    law isa Function && throw(ArgumentError(
        "stable relationship laws must use DirectLaw with explicit identity"))
    for policy in (create, remove, update)
        policy isa Function && throw(ArgumentError(
            "stable relationship policies must use DirectLaw with explicit identity"))
    end
    resolved_law = law === nothing ?
        RelationshipPolicyBundle(create, remove, update) : law
    return RelationshipDynamics(name,
        relationships isa Symbol ? relationships : relationships.name,
        resolved_law, conflicts, version)
end

struct RelationshipPolicyBundle{C, R, U}
    create::C
    remove::R
    update::U
end

component_identity(process::RelationshipDynamics) =
    ComponentIdentity(process.name, process.version, :relationship_dynamics)
component_semantic_data(process::RelationshipDynamics) = (
    relationships = process.relationships,
    law = process.law, conflicts = process.conflicts)
component_effects(::RelationshipDynamics) = (:relationship_phase_write,)
process_reads(process::RelationshipDynamics) =
    ((:relationships, process.relationships), (:ownership, :cells))
process_writes(process::RelationshipDynamics) =
    ((:relationships, process.relationships),)

function _relationship_requests(law, relationships, potts_snapshot,
        target_mcs, stage)
    applicable(law, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs, stage))
    applicable(law, relationships, potts_snapshot, target_mcs) &&
        return Tuple(law(relationships, potts_snapshot, target_mcs))
    applicable(law, relationships, potts_snapshot) &&
        return Tuple(law(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law must return typed requests from a supported snapshot signature"))
end

function _relationship_requests(law::DirectLaw, relationships,
        potts_snapshot, target_mcs, stage)
    function_value = law.function_value
    applicable(function_value, relationships, potts_snapshot, target_mcs, stage) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs, stage))
    applicable(function_value, relationships, potts_snapshot, target_mcs) &&
        return Tuple(function_value(
            relationships, potts_snapshot, target_mcs))
    applicable(function_value, relationships, potts_snapshot) &&
        return Tuple(function_value(relationships, potts_snapshot))
    throw(ArgumentError(
        "relationship law `$(law.name)` has no supported snapshot signature"))
end

function _relationship_requests(bundle::RelationshipPolicyBundle,
        relationships, potts_snapshot, target_mcs, stage)
    requests = ()
    for policy in (bundle.remove, bundle.update, bundle.create)
        policy === nothing && continue
        produced = _relationship_requests(
            policy, relationships, potts_snapshot, target_mcs, stage)
        requests = (requests..., produced...)
    end
    return requests
end

_request_key(request::AbstractRelationshipRequest) = (
    -Int(request.priority),
    value(request.left.cell), value(request.left.generation),
    value(request.right.cell), value(request.right.generation),
    request isa RemoveRelationship ? 1 :
    request isa RetuneRelationship ? 2 : 3)

function apply_relationship_dynamics!(state::RelationshipState,
        process::RelationshipDynamics, potts_snapshot,
        target_mcs::Integer; stage = nothing)
    process.relationships === state.declaration.name || throw(ArgumentError(
        "RelationshipDynamics targets a different RelationshipSet"))
    requests = collect(_relationship_requests(
        process.law, deepcopy(state), potts_snapshot, target_mcs, stage))
    all(request -> request isa AbstractRelationshipRequest, requests) ||
        throw(ArgumentError(
            "relationship dynamics produced an untyped transaction request"))
    sort!(requests; by = _request_key)
    candidate = deepcopy(state)
    touched = Set{Tuple{CellEndpoint, CellEndpoint}}()
    for request in requests
        endpoints = _canonical_endpoints(
            candidate.declaration, request.left, request.right)
        endpoints in touched && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        push!(touched, endpoints)
        if request isa RemoveRelationship
            remove_relationship!(candidate, endpoints...)
        elseif request isa RetuneRelationship
            retune_relationship!(
                candidate, endpoints..., request.payload)
        else
            create_relationship!(
                candidate, endpoints..., request.payload)
        end
    end
    _publish_state!(state, candidate)
    return state
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, process::RelationshipDynamics,
        target_mcs, stage, interval)
    source = _state_by_name(snapshot.relationships, process.relationships)
    target = _state_by_name(candidate.relationships, process.relationships)
    _publish_state!(target, source)
    apply_relationship_dynamics!(
        target, process, potts_snapshot, target_mcs; stage)
    return nothing
end

function _apply_site_lifecycle!(state::SitePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    policy = state.declaration.ownership
    policy isa PreserveAtSite && return state
    before_owners = lattice_storage(before)
    after_owners = lattice_storage(after)
    for site in eachindex(before_owners)
        before_owners[site] == after_owners[site] && continue
        if policy isa ResetChangedSites
            _site_write!(state, site, policy.value)
        else
            throw(ArgumentError(
                "AcceptedCopyManaged does not define lifecycle-driven ownership changes; declare a coupled lifecycle site policy"))
        end
    end
    return state
end

function _apply_history_lifecycle!(state::CellHistoryState,
        before::LogicalPottsState, after::LogicalPottsState)
    for slot in eachindex(state.generations)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        next_generation = generation(after, cell)
        if !active_after || state.generations[slot] != next_generation
            state.heads[slot] = UInt32(0)
            state.fills[slot] = UInt32(0)
            state.generations[slot] = next_generation
        end
    end
    return state
end

function _apply_relationship_lifecycle!(state::RelationshipState,
        before::LogicalPottsState, after::LogicalPottsState)
    stale = CellEndpoint[]
    for edge in state.edges, endpoint in (edge.left, edge.right)
        cell = endpoint.cell
        if !is_active(after, cell) || generation(after, cell) != endpoint.generation
            endpoint in stale || push!(stale, endpoint)
        end
    end
    for endpoint in stale
        retire_relationship_endpoint!(state, endpoint)
    end
    return state
end

function _apply_membrane_lifecycle!(state::MembranePropertyState,
        before::LogicalPottsState, after::LogicalPottsState)
    initial = state.declaration.initial.value
    for slot in axes(state.values, 1)
        cell = CellID(slot)
        active_after = is_active(after, cell)
        generation_after = generation(after, cell)
        if !active_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = false
            state.generations[slot] = generation_after
        elseif !state.active[slot] ||
                state.generations[slot] != generation_after
            fill!(@view(state.values[slot, :]), initial)
            state.active[slot] = true
            state.generations[slot] = generation_after
        end
    end
    return state
end

"""Apply coupled-state cleanup after one accepted CorePotts lifecycle transaction."""
function apply_coupled_lifecycle!(state::CoupledState,
        before::LogicalPottsState, after::LogicalPottsState)
    candidate = deepcopy(state)
    foreach(item -> _apply_site_lifecycle!(item, before, after),
        candidate.site_states)
    foreach(item -> _apply_history_lifecycle!(item, before, after),
        candidate.histories)
    foreach(item -> _apply_relationship_lifecycle!(item, before, after),
        candidate.relationships)
    foreach(item -> _apply_membrane_lifecycle!(item, before, after),
        candidate.membranes)
    publish_coupled_state!(state, candidate)
    return state
end
