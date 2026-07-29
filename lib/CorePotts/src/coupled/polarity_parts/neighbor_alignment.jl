const NEIGHBOR_ALIGNMENT_SUCCEEDED = UInt32(0)
const NEIGHBOR_ALIGNMENT_NONFINITE_INPUT = UInt32(1)
const NEIGHBOR_ALIGNMENT_NEGATIVE_STRENGTH = UInt32(2)
const NEIGHBOR_ALIGNMENT_NONFINITE_OUTPUT = UInt32(3)

const _COUPLED_PROCESS_FAILURE_CODE_BITS = 4
const _COUPLED_PROCESS_FAILURE_CODE_MASK =
    (UInt32(1) << _COUPLED_PROCESS_FAILURE_CODE_BITS) - UInt32(1)
const _COUPLED_PROCESS_FAILURE_SENTINEL = typemax(UInt32)
const _COUPLED_PROCESS_MAX_CELL =
    (_COUPLED_PROCESS_FAILURE_SENTINEL >>
     _COUPLED_PROCESS_FAILURE_CODE_BITS) - UInt32(1)
const _ALIGNMENT_ADJACENCY_WORD_BITS = 8 * sizeof(UInt32)

@inline function _coupled_process_failure_key(
        code::UInt32, cell::Integer)
    return (UInt32(cell) << _COUPLED_PROCESS_FAILURE_CODE_BITS) | code
end

@inline _coupled_process_failure_code(key::UInt32) =
    key & _COUPLED_PROCESS_FAILURE_CODE_MASK
@inline _coupled_process_failing_cell(key::UInt32) =
    key >> _COUPLED_PROCESS_FAILURE_CODE_BITS

@inline _alignment_adjacency_words(capacity::Integer) =
    cld(capacity, _ALIGNMENT_ADJACENCY_WORD_BITS)
@inline _alignment_adjacency_word(neighbor::Integer) =
    ((neighbor - 1) ÷ _ALIGNMENT_ADJACENCY_WORD_BITS) + 1
@inline _alignment_adjacency_mask(neighbor::Integer) =
    UInt32(1) << ((neighbor - 1) % _ALIGNMENT_ADJACENCY_WORD_BITS)
@inline function _alignment_adjacency_contains(
        adjacency, cell::Integer, neighbor::Integer)
    word = _alignment_adjacency_word(neighbor)
    mask = _alignment_adjacency_mask(neighbor)
    return @inbounds(adjacency[word, cell] & mask) != UInt32(0)
end
@inline function _alignment_set_adjacency!(
        adjacency, cell::Integer, neighbor::Integer)
    word = _alignment_adjacency_word(neighbor)
    mask = _alignment_adjacency_mask(neighbor)
    @inbounds adjacency[word, cell] |= mask
    return nothing
end

struct NeighborPolarityWorkspace{
        T <: AbstractFloat,
        V <: AbstractVector{T},
        M <: AbstractMatrix{UInt32},
        C <: AbstractVector{UInt32}}
    source_x::V
    source_y::V
    neighbor_sum_x::V
    neighbor_sum_y::V
    neighbor_count::C
    candidate_x::V
    candidate_y::V
    candidate_fraction::V
    adjacency::M
    failure_key::C
end

function NeighborPolarityWorkspace(values::AbstractVector{T}) where {
        T <: AbstractFloat}
    capacity = length(values)
    capacity <= Int(_COUPLED_PROCESS_MAX_CELL) ||
        throw(ArgumentError(
            "neighbor-polarity capacity exceeds packed failure-key capacity"))
    arrays = ntuple(_ -> similar(values, T, capacity), Val(7))
    neighbor_count = similar(values, UInt32, capacity)
    adjacency = similar(
        values, UInt32,
        _alignment_adjacency_words(capacity), capacity)
    failure_key = similar(values, UInt32, 1)
    for array in (
            arrays..., neighbor_count, adjacency,
            failure_key)
        fill!(array, zero(eltype(array)))
    end
    fill!(failure_key, _COUPLED_PROCESS_FAILURE_SENTINEL)
    return NeighborPolarityWorkspace(
        arrays[1], arrays[2], arrays[3], arrays[4],
        neighbor_count, arrays[5], arrays[6], arrays[7],
        adjacency, failure_key)
end

function Adapt.adapt_structure(to, workspace::NeighborPolarityWorkspace)
    return NeighborPolarityWorkspace(
        Adapt.adapt(to, workspace.source_x),
        Adapt.adapt(to, workspace.source_y),
        Adapt.adapt(to, workspace.neighbor_sum_x),
        Adapt.adapt(to, workspace.neighbor_sum_y),
        Adapt.adapt(to, workspace.neighbor_count),
        Adapt.adapt(to, workspace.candidate_x),
        Adapt.adapt(to, workspace.candidate_y),
        Adapt.adapt(to, workspace.candidate_fraction),
        Adapt.adapt(to, workspace.adjacency),
        Adapt.adapt(to, workspace.failure_key))
end

neighbor_polarity_workspace_bytes(workspace::NeighborPolarityWorkspace) =
    sum(_array_bytes, (
        workspace.source_x, workspace.source_y,
        workspace.neighbor_sum_x, workspace.neighbor_sum_y,
        workspace.neighbor_count, workspace.candidate_x,
        workspace.candidate_y, workspace.candidate_fraction,
        workspace.adjacency, workspace.failure_key); init = 0)

"""
Backend-independent declaration of one contact-neighbor polarity alignment
law. Realization allocates the bounded adjacency workspace on the scientific
state backend.
"""
struct NeighborPolarityAlignment{
        X, Y, Strength, Fraction,
        R <: StaticCartesianRelation,
        T <: AbstractFloat}
    name::Symbol
    relation::R
    strength_scale::T
    maximum_fraction::T
    version::VersionNumber
end

function NeighborPolarityAlignment(
        name::Symbol,
        relation::StaticCartesianRelation;
        x::Symbol, y::Symbol, strength::Symbol,
        fraction::Symbol, strength_scale::T,
        maximum_fraction::T,
        version::VersionNumber =
            COUPLED_EXECUTION_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isempty(String(name)) && throw(ArgumentError(
        "neighbor-polarity alignment identity must not be empty"))
    isfinite(strength_scale) && strength_scale > zero(T) ||
        throw(ArgumentError(
            "neighbor-polarity strength scale must be finite and positive"))
    isfinite(maximum_fraction) &&
        zero(T) <= maximum_fraction <= one(T) ||
        throw(ArgumentError(
            "neighbor-polarity maximum fraction must lie in [0,1]"))
    length(unique((x, y, strength, fraction))) == 4 ||
        throw(ArgumentError(
            "neighbor-polarity properties must be unique"))
    return NeighborPolarityAlignment{
        x, y, strength, fraction,
        typeof(relation), T}(
        name, relation, strength_scale,
        maximum_fraction, version)
end

component_identity(process::NeighborPolarityAlignment) =
    ComponentIdentity(
        process.name, process.version,
        :neighbor_polarity_alignment)
component_semantic_data(process::NeighborPolarityAlignment{
        X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction} = (
    x = X,
    y = Y,
    strength = Strength,
    fraction = Fraction,
    relation = process.relation,
    strength_scale = process.strength_scale,
    maximum_fraction = process.maximum_fraction,
)
process_reads(process::NeighborPolarityAlignment{
        X, Y, Strength}) where {X, Y, Strength} = (
    (:ownership, :lattice),
    (:cell, X), (:cell, Y), (:cell, Strength),
)
process_writes(process::NeighborPolarityAlignment{
        X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction} = (
    (:cell, X), (:cell, Y), (:cell, Fraction),
)

struct NeighborPolarityAlignmentExecution{
        X, Y, Strength, Fraction,
        R <: StaticCartesianRelation,
        T <: AbstractFloat,
        W <: NeighborPolarityWorkspace}
    name::Symbol
    relation::R
    strength_scale::T
    maximum_fraction::T
    workspace::W
    version::VersionNumber
end

function _coupled_property_column(
        state::LogicalPottsState, property::Symbol)
    return property_values(state, property)
end
function _coupled_property_column(
        state::CompiledScientificState, property::Symbol)
    return getproperty(
        scientific_execution(state).core.properties, property)
end

function NeighborPolarityAlignmentExecution(
        name::Symbol, state,
        relation::StaticCartesianRelation;
        x::Symbol, y::Symbol, strength::Symbol,
        fraction::Symbol, strength_scale::T,
        maximum_fraction::T,
        version::VersionNumber =
            COUPLED_EXECUTION_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isempty(String(name)) && throw(ArgumentError(
        "neighbor-polarity alignment identity must not be empty"))
    isfinite(strength_scale) && strength_scale > zero(T) ||
        throw(ArgumentError(
            "neighbor-polarity strength scale must be finite and positive"))
    isfinite(maximum_fraction) &&
        zero(T) <= maximum_fraction <= one(T) ||
        throw(ArgumentError(
            "neighbor-polarity maximum fraction must lie in [0,1]"))
    columns = map(
        property -> _coupled_property_column(state, property),
        (x, y, strength, fraction))
    all(column -> column isa AbstractVector{T}, columns) ||
        throw(ArgumentError(
            "neighbor-polarity properties must share the parameter floating type"))
    all(==(length(first(columns))), map(length, columns)) ||
        throw(DimensionMismatch(
            "neighbor-polarity property capacities differ"))
    workspace = NeighborPolarityWorkspace(first(columns))
    return NeighborPolarityAlignmentExecution{
        x, y, strength, fraction,
        typeof(relation), T, typeof(workspace)}(
        name, relation, strength_scale,
        maximum_fraction, workspace, version)
end

NeighborPolarityAlignment(
    name::Symbol, state,
    relation::StaticCartesianRelation; kwargs...) =
    NeighborPolarityAlignmentExecution(
        name, state, relation; kwargs...)

function realize_coupled_process(
        process::NeighborPolarityAlignment{
            X, Y, Strength, Fraction},
        state::CoupledState,
        scientific::CompiledScientificState) where {
            X, Y, Strength, Fraction}
    return NeighborPolarityAlignmentExecution(
        process.name, scientific,
        process.relation;
        x = X, y = Y, strength = Strength,
        fraction = Fraction,
        strength_scale = process.strength_scale,
        maximum_fraction = process.maximum_fraction,
        version = process.version)
end

function Adapt.adapt_structure(
        to, process::NeighborPolarityAlignmentExecution{
            X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction}
    relation = Adapt.adapt(to, process.relation)
    workspace = Adapt.adapt(to, process.workspace)
    return NeighborPolarityAlignmentExecution{
        X, Y, Strength, Fraction,
        typeof(relation), typeof(process.strength_scale),
        typeof(workspace)}(
        process.name, relation, process.strength_scale,
        process.maximum_fraction, workspace, process.version)
end

component_identity(process::NeighborPolarityAlignmentExecution) =
    ComponentIdentity(
        process.name, process.version,
        :neighbor_polarity_alignment)
component_semantic_data(process::NeighborPolarityAlignmentExecution{
        X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction} = (
    x = X,
    y = Y,
    strength = Strength,
    fraction = Fraction,
    relation = process.relation,
    strength_scale = process.strength_scale,
    maximum_fraction = process.maximum_fraction,
)
process_reads(process::NeighborPolarityAlignmentExecution{
        X, Y, Strength}) where {X, Y, Strength} = (
    (:ownership, :lattice),
    (:cell, X), (:cell, Y), (:cell, Strength),
)
process_writes(process::NeighborPolarityAlignmentExecution{
        X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction} = (
    (:cell, X), (:cell, Y), (:cell, Fraction),
)
canonical_process_law(
        process::NeighborPolarityAlignmentExecution{
            X, Y, Strength, Fraction}) where {
            X, Y, Strength, Fraction} =
    NeighborPolarityAlignment(
        process.name, process.relation;
        x = X, y = Y, strength = Strength,
        fraction = Fraction,
        strength_scale = process.strength_scale,
        maximum_fraction = process.maximum_fraction,
        version = process.version)

@inline _coupled_column(properties, key::Symbol) =
    getproperty(properties, key)
@inline _coupled_column(
    properties::PropertyStore, key::Symbol) =
    property_values(properties, key)

@inline function _alignment_columns(
        properties,
        ::NeighborPolarityAlignmentExecution{
            X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction}
    return (
        _coupled_column(properties, X),
        _coupled_column(properties, Y),
        _coupled_column(properties, Strength),
        _coupled_column(properties, Fraction),
    )
end

@inline function _alignment_candidate(
        self_x, self_y, neighbor_sum_x,
        neighbor_sum_y, neighbor_count,
        strength, strength_scale, maximum_fraction)
    fraction =
        min(strength / strength_scale, one(strength)) *
        maximum_fraction
    if iszero(neighbor_count)
        neighbor_x = zero(self_x)
        neighbor_y = zero(self_y)
    else
        divisor = convert(typeof(self_x), neighbor_count)
        neighbor_x = neighbor_sum_x / divisor
        neighbor_y = neighbor_sum_y / divisor
    end
    one_minus = one(fraction) - fraction
    mixed_x = fraction * neighbor_x + one_minus * self_x
    mixed_y = fraction * neighbor_y + one_minus * self_y
    magnitude = sqrt(mixed_x * mixed_x + mixed_y * mixed_y)
    if iszero(magnitude)
        return zero(mixed_x), zero(mixed_y), fraction
    end
    return mixed_x / magnitude, mixed_y / magnitude, fraction
end

function apply_neighbor_polarity_alignment!(
        candidate::LogicalPottsState,
        snapshot::LogicalPottsState,
        domain::Union{CartesianDomain, CompiledCartesianDomain},
        process::NeighborPolarityAlignmentExecution)
    source_x, source_y, strengths, fractions =
        _alignment_columns(snapshot.properties, process)
    target_x, target_y, _, target_fractions =
        _alignment_columns(candidate.properties, process)
    workspace = process.workspace
    capacity = length(source_x)
    size(workspace.adjacency) ==
        (_alignment_adjacency_words(capacity), capacity) ||
        throw(DimensionMismatch(
            "neighbor-polarity adjacency capacity differs"))
    copyto!(workspace.source_x, source_x)
    copyto!(workspace.source_y, source_y)
    fill!(workspace.adjacency, UInt32(0))
    fill!(workspace.neighbor_sum_x, zero(eltype(source_x)))
    fill!(workspace.neighbor_sum_y, zero(eltype(source_y)))
    fill!(workspace.neighbor_count, UInt32(0))
    workspace.failure_key[1] =
        _COUPLED_PROCESS_FAILURE_SENTINEL
    for site in 1:prod(domain isa CartesianDomain ?
            domain.dims : domain.descriptor.dims)
        left = owner_at(snapshot, site)
        is_cell_owner(left) || continue
        for direction in 1:direction_count(process.relation)
            neighbor = realize_neighbor(
                domain, process.relation, site, direction)
            neighbor.kind === MutableNeighbor || continue
            right = owner_at(snapshot, Int(neighbor.site))
            is_cell_owner(right) || continue
            left == right && continue
            _alignment_set_adjacency!(
                workspace.adjacency,
                Int(left.value), Int(right.value))
            _alignment_set_adjacency!(
                workspace.adjacency,
                Int(right.value), Int(left.value))
        end
    end
    for slot in 1:capacity
        cell = CellID(slot)
        is_active(snapshot, cell) || continue
        self_x = @inbounds workspace.source_x[slot]
        self_y = @inbounds workspace.source_y[slot]
        strength = @inbounds strengths[slot]
        if !(isfinite(self_x) && isfinite(self_y) &&
                isfinite(strength))
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    NEIGHBOR_ALIGNMENT_NONFINITE_INPUT, slot)
            throw(ArgumentError(
                "neighbor-polarity input is nonfinite at slot $slot"))
        elseif strength < zero(strength)
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    NEIGHBOR_ALIGNMENT_NEGATIVE_STRENGTH, slot)
            throw(ArgumentError(
                "neighbor-polarity strength is negative at slot $slot"))
        end
        sum_x = zero(self_x)
        sum_y = zero(self_y)
        count = UInt32(0)
        for word in axes(workspace.adjacency, 1)
            bits = @inbounds workspace.adjacency[word, slot]
            while bits != UInt32(0)
                offset = trailing_zeros(bits)
                neighbor =
                    (word - 1) * _ALIGNMENT_ADJACENCY_WORD_BITS +
                    offset + 1
                if neighbor <= capacity
                    sum_x +=
                        @inbounds workspace.source_x[neighbor]
                    sum_y +=
                        @inbounds workspace.source_y[neighbor]
                    count += UInt32(1)
                end
                bits &= bits - UInt32(1)
            end
        end
        @inbounds begin
            workspace.neighbor_sum_x[slot] = sum_x
            workspace.neighbor_sum_y[slot] = sum_y
            workspace.neighbor_count[slot] = count
        end
        aligned_x, aligned_y, fraction =
            _alignment_candidate(
                self_x, self_y, sum_x, sum_y, count,
                strength, process.strength_scale,
                process.maximum_fraction)
        if !(isfinite(aligned_x) && isfinite(aligned_y) &&
                isfinite(fraction))
            workspace.failure_key[1] =
                _coupled_process_failure_key(
                    NEIGHBOR_ALIGNMENT_NONFINITE_OUTPUT, slot)
            throw(ArgumentError(
                "neighbor-polarity output is nonfinite at slot $slot"))
        end
        @inbounds begin
            workspace.candidate_x[slot] = aligned_x
            workspace.candidate_y[slot] = aligned_y
            workspace.candidate_fraction[slot] = fraction
        end
    end
    for slot in 1:capacity
        is_active(snapshot, CellID(slot)) || continue
        @inbounds begin
            target_x[slot] = workspace.candidate_x[slot]
            target_y[slot] = workspace.candidate_y[slot]
            target_fractions[slot] =
                workspace.candidate_fraction[slot]
        end
    end
    return candidate
end

@inline function _record_alignment_failure!(
        failure_key, code, cell)
    key = _coupled_process_failure_key(UInt32(code), cell)
    Atomix.@atomic min(failure_key[1], key)
    return nothing
end

@kernel function _alignment_initialize_cells!(
        source_x, source_y,
        neighbor_sum_x, neighbor_sum_y, neighbor_count,
        candidate_x, candidate_y, candidate_fraction,
        x, y, fraction, failure_key)
    cell = @index(Global, Linear)
    @inbounds begin
        source_x[cell] = x[cell]
        source_y[cell] = y[cell]
        neighbor_sum_x[cell] = zero(eltype(neighbor_sum_x))
        neighbor_sum_y[cell] = zero(eltype(neighbor_sum_y))
        neighbor_count[cell] = UInt32(0)
        candidate_x[cell] = x[cell]
        candidate_y[cell] = y[cell]
        candidate_fraction[cell] = fraction[cell]
        if cell == 1
            failure_key[1] =
                _COUPLED_PROCESS_FAILURE_SENTINEL
        end
    end
end

@kernel function _alignment_clear_adjacency!(adjacency)
    index = @index(Global, Linear)
    @inbounds adjacency[index] = UInt32(0)
end

@kernel function _alignment_build_adjacency!(
        adjacency, scientific, relation)
    site = @index(Global, Linear)
    left = _proposal_owner_at(scientific, site)
    if is_cell_owner(left)
        for direction in 1:direction_count(relation)
            neighbor = _realize_neighbor_unchecked(
                scientific.domain, relation, site, direction)
            neighbor.kind === MutableNeighbor || continue
            right = _proposal_owner_at(
                scientific, Int(neighbor.site))
            is_cell_owner(right) || continue
            left == right && continue
            left_word =
                _alignment_adjacency_word(Int(right.value))
            left_mask =
                _alignment_adjacency_mask(Int(right.value))
            right_word =
                _alignment_adjacency_word(Int(left.value))
            right_mask =
                _alignment_adjacency_mask(Int(left.value))
            Atomix.@atomic adjacency[
                left_word, Int(left.value)] |= left_mask
            Atomix.@atomic adjacency[
                right_word, Int(right.value)] |= right_mask
        end
    end
end

@kernel function _alignment_compute_cells!(
        source_x, source_y,
        neighbor_sum_x, neighbor_sum_y, neighbor_count,
        candidate_x, candidate_y, candidate_fraction,
        adjacency, strengths, active,
        strength_scale, maximum_fraction,
        failure_key)
    cell = @index(Global, Linear)
    @inbounds if active[cell] != UInt8(0)
        self_x = source_x[cell]
        self_y = source_y[cell]
        strength = strengths[cell]
        if !(isfinite(self_x) && isfinite(self_y) &&
                isfinite(strength))
            _record_alignment_failure!(
                failure_key,
                NEIGHBOR_ALIGNMENT_NONFINITE_INPUT, cell)
        elseif strength < zero(strength)
            _record_alignment_failure!(
                failure_key,
                NEIGHBOR_ALIGNMENT_NEGATIVE_STRENGTH, cell)
        else
            sum_x = zero(self_x)
            sum_y = zero(self_y)
            count = UInt32(0)
            for word in axes(adjacency, 1)
                bits = adjacency[word, cell]
                while bits != UInt32(0)
                    offset = trailing_zeros(bits)
                    neighbor =
                        (word - 1) *
                        _ALIGNMENT_ADJACENCY_WORD_BITS +
                        offset + 1
                    if neighbor <= length(source_x)
                        sum_x += source_x[neighbor]
                        sum_y += source_y[neighbor]
                        count += UInt32(1)
                    end
                    bits &= bits - UInt32(1)
                end
            end
            neighbor_sum_x[cell] = sum_x
            neighbor_sum_y[cell] = sum_y
            neighbor_count[cell] = count
            aligned_x, aligned_y, fraction =
                _alignment_candidate(
                    self_x, self_y, sum_x, sum_y, count,
                    strength, strength_scale, maximum_fraction)
            if isfinite(aligned_x) && isfinite(aligned_y) &&
                    isfinite(fraction)
                candidate_x[cell] = aligned_x
                candidate_y[cell] = aligned_y
                candidate_fraction[cell] = fraction
            else
                _record_alignment_failure!(
                    failure_key,
                    NEIGHBOR_ALIGNMENT_NONFINITE_OUTPUT, cell)
            end
        end
    end
end

@kernel function _alignment_commit_cells!(
        x, y, fraction,
        candidate_x, candidate_y, candidate_fraction,
        active, failure_key)
    cell = @index(Global, Linear)
    @inbounds if failure_key[1] ==
            _COUPLED_PROCESS_FAILURE_SENTINEL &&
            active[cell] != UInt8(0)
        x[cell] = candidate_x[cell]
        y[cell] = candidate_y[cell]
        fraction[cell] = candidate_fraction[cell]
    end
end

function apply_neighbor_polarity_alignment!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        process::NeighborPolarityAlignmentExecution)
    execution = scientific_execution(scientific)
    core = execution.core
    x, y, strengths, fractions =
        _alignment_columns(core.properties, process)
    workspace = process.workspace
    capacity = length(core.active)
    arrays = (
        x, y, strengths, fractions, core.active,
        workspace.source_x, workspace.source_y,
        workspace.neighbor_sum_x, workspace.neighbor_sum_y,
        workspace.neighbor_count, workspace.candidate_x,
        workspace.candidate_y, workspace.candidate_fraction,
        workspace.adjacency, workspace.failure_key)
    all(array -> isbitstype(eltype(array)) &&
            isequal(KernelAbstractions.get_backend(array), plan.backend),
        arrays) || throw(ArgumentError(
        "portable neighbor-polarity storage has a backend mismatch"))
    all(==(capacity), map(length, (
        x, y, strengths, fractions,
        workspace.source_x, workspace.source_y,
        workspace.neighbor_sum_x, workspace.neighbor_sum_y,
        workspace.neighbor_count, workspace.candidate_x,
        workspace.candidate_y, workspace.candidate_fraction))) ||
        throw(DimensionMismatch(
            "portable neighbor-polarity capacities differ"))
    size(workspace.adjacency) ==
        (_alignment_adjacency_words(capacity), capacity) ||
        throw(DimensionMismatch(
            "portable neighbor-polarity adjacency capacity differs"))
    initialize = _execution_kernel(
        plan, _alignment_initialize_cells!, capacity)
    launch!(plan, initialize,
        workspace.source_x, workspace.source_y,
        workspace.neighbor_sum_x, workspace.neighbor_sum_y,
        workspace.neighbor_count, workspace.candidate_x,
        workspace.candidate_y, workspace.candidate_fraction,
        x, y, fractions, workspace.failure_key;
        ndrange = capacity)
    clear = _execution_kernel(
        plan, _alignment_clear_adjacency!,
        length(workspace.adjacency))
    launch!(plan, clear, workspace.adjacency;
        ndrange = length(workspace.adjacency))
    build = _execution_kernel(
        plan, _alignment_build_adjacency!,
        length(core.ownership.tags))
    launch!(plan, build, workspace.adjacency,
        execution, process.relation;
        ndrange = length(core.ownership.tags))
    compute = _execution_kernel(
        plan, _alignment_compute_cells!, capacity)
    launch!(plan, compute,
        workspace.source_x, workspace.source_y,
        workspace.neighbor_sum_x, workspace.neighbor_sum_y,
        workspace.neighbor_count, workspace.candidate_x,
        workspace.candidate_y, workspace.candidate_fraction,
        workspace.adjacency, strengths, core.active,
        process.strength_scale, process.maximum_fraction,
        workspace.failure_key;
        ndrange = capacity)
    commit = _execution_kernel(
        plan, _alignment_commit_cells!, capacity)
    launch!(plan, commit,
        x, y, fractions,
        workspace.candidate_x, workspace.candidate_y,
        workspace.candidate_fraction,
        core.active, workspace.failure_key;
        ndrange = capacity)
    return scientific
end

function synchronize_neighbor_polarity_status!(
        plan::ExecutionPlan,
        process::NeighborPolarityAlignmentExecution)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    key = only(Adapt.adapt(
        Array, process.workspace.failure_key))
    key == _COUPLED_PROCESS_FAILURE_SENTINEL &&
        return process
    status = _coupled_process_failure_code(key)
    cell = _coupled_process_failing_cell(key)
    throw(ArgumentError(
        "neighbor-polarity alignment failed with status $status at cell $cell"))
end

function _execute_host_process!(
        candidate::CoupledState, snapshot::CoupledState,
        potts_candidate::LogicalPottsState,
        potts_snapshot::LogicalPottsState,
        scientific::CompiledScientificState,
        process::NeighborPolarityAlignmentExecution,
        target_mcs, stage, interval)
    apply_neighbor_polarity_alignment!(
        potts_candidate, potts_snapshot,
        scientific.domain, process)
    return (
        _alignment_x_property(process),
        _alignment_y_property(process),
        _alignment_fraction_property(process),
    )
end

@inline _alignment_x_property(
    ::NeighborPolarityAlignmentExecution{X}) where {X} = X
@inline _alignment_y_property(
    ::NeighborPolarityAlignmentExecution{X, Y}) where {X, Y} = Y
@inline _alignment_fraction_property(
    ::NeighborPolarityAlignmentExecution{
        X, Y, Strength, Fraction}) where {
        X, Y, Strength, Fraction} = Fraction

function _execute_portable_process!(
        integrator::CoupledIntegrator,
        process::NeighborPolarityAlignmentExecution,
        target_mcs, stage, interval)
    apply_neighbor_polarity_alignment!(
        integrator.potts.plan, integrator.potts.state,
        process)
    synchronize_neighbor_polarity_status!(
        integrator.potts.plan, process)
    return ()
end

const HILL_FORCE_SUCCEEDED = UInt32(0)
const HILL_FORCE_NONFINITE_INPUT = UInt32(1)
const HILL_FORCE_INVALID_SIGNAL = UInt32(2)
const HILL_FORCE_NONFINITE_OUTPUT = UInt32(3)
