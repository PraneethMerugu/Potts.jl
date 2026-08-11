const LW = LocalWorksets
const KA = LocalWorksets.KernelAbstractions

mutable struct _OpaqueZTopology
    pixel_indices::Vector{Int32}
    primitive_ids::Vector{UInt32}
    item_count::Int32
    destination_count::Int32
    epoch::UInt64
end

mutable struct _FingerprintBypassTopology
    pixel_indices::Vector{Int32}
    primitive_ids::Vector{UInt32}
    item_count::Int32
    destination_count::Int32
    epoch::UInt64
end

struct _ExternalWorkspace
    winner_ranks::Vector{Int32}
    winner_identities::Vector{UInt32}
    leases::Vector{Any}
end

struct _ExternalRuntime end

Base.show(io::IO, ::_OpaqueZTopology) = print(io, "opaque-topology")

struct _UnauthorizedOperation end
struct _UnauthorizedLowering end
struct _UnauthorizedBackend <: KA.Backend end
struct _EvidenceBypassBackend <: KA.Backend end
struct _OuterBypassBackend <: KA.Backend end

KA.functional(::_UnauthorizedBackend) = true
KA.device(::_UnauthorizedBackend) = 1
KA.functional(::_EvidenceBypassBackend) = true
KA.device(::_EvidenceBypassBackend) = 1
KA.functional(::_OuterBypassBackend) = true
KA.device(::_OuterBypassBackend) = 1

struct _UnauthorizedLane <: LW._AbstractProviderLane end

LW._atomic_capability(
    ::_UnauthorizedBackend, type::Type, operation::Symbol, address::Symbol
) = true
LW._reviewed_backend_environment(::_UnauthorizedBackend) = true
LW._backend_environment(::_UnauthorizedBackend) =
    first(LW._REVIEWED_BACKEND_ENVIRONMENTS)
LW._reviewed_backend_environment(::_EvidenceBypassBackend) = true
LW._backend_environment(::_EvidenceBypassBackend) =
    first(LW._REVIEWED_BACKEND_ENVIRONMENTS)
LW._centrally_qualified_atomic_capability(
    ::_OuterBypassBackend, ::Type, ::Symbol, ::Symbol
) = true
LW._centrally_qualified_value_capability(
    ::_OuterBypassBackend, ::Type, ::Symbol, ::Symbol
) = true
LW._validate_resolved_capability(::_OuterBypassBackend, output) = nothing
LW._provider_compiler_identity(::_OuterBypassBackend) =
    merge(
        first(LW._REVIEWED_BACKEND_ENVIRONMENTS),
        (qualification = :centrally_reviewed_environment,),
    )
LW._make_provider_lane(::_UnauthorizedBackend, storage) = _UnauthorizedLane()

function LW._central_admission(
        work::LW.LocalWork{I, R, O, A, _UnauthorizedOperation},
        topology,
        backend,
    ) where {I, R, O, A}
    return _UnauthorizedLowering()
end

LW._lower_resolved(work::LW.LocalWork, ::_OpaqueZTopology, backend) =
    _UnauthorizedLowering()
LW._topology_identity(::_FingerprintBypassTopology) = UInt(0)
LW._topology_epoch(::_FingerprintBypassTopology) = UInt64(0)
LW._topology_fingerprint(
    ::_FingerprintBypassTopology, ::LW._ResolvedWinnerLowering
) = "forged-constant"
LW._validate_workspace(
    ::LW._ResolvedWinnerLowering, work, ::_ExternalWorkspace, backend
) = nothing
LW._workspace_arrays(
    ::LW._ResolvedWinnerLowering, work, ::_ExternalWorkspace
) = ()
LW._prepare_lowering(
    ::LW._ResolvedWinnerLowering,
    work,
    storage,
    ::_ExternalWorkspace,
    backend,
) = _ExternalRuntime()
LW._execute_lowering!(
    ::_ExternalRuntime,
    ::LW._ResolvedWinnerLowering,
    work,
    storage,
    ::_ExternalWorkspace,
    submission,
) = 0

function _zbuffer_declaration(;
        output_name = :framebuffer_color,
        value_binding = :fragment_colors,
        rank_binding = :fragment_depths,
        mask_binding = :fragment_coverage,
        rank_order = :min,
        emission_mask = :mask,
    )
    topology = (
        pixel_indices = Int32[1, 1, 2, 2, 3],
        primitive_ids = UInt32[50, 10, 30, 20, 40],
        item_count = Int32(5),
        destination_count = Int32(4),
        epoch = UInt64(1),
    )
    output = LW.resolved(
        :pixel_indices;
        empty = UInt32(0),
        rank = (
            type = Int32,
            order = rank_order,
            lower = Int32(-100),
            upper = Int32(100),
        ),
        tie_break = (type = UInt32, order = :min),
        capacity = 5,
        key_type = Int32,
        value_type = UInt32,
        mask = emission_mask === :mask ? mask_binding : nothing,
    )
    operation = (
        family = :resolved_selection,
        emission = LW.masked(:value, emission_mask),
    )
    reads = emission_mask === :mask ? (
        key = :pixel_indices,
        rank = rank_binding,
        identity = :primitive_ids,
        value = value_binding,
        mask = mask_binding,
    ) : (
        key = :pixel_indices,
        rank = rank_binding,
        identity = :primitive_ids,
        value = value_binding,
    )
    outputs = NamedTuple{(output_name,)}((output,))
    work = LW.localwork(
        operation,
        1:5;
        read = reads,
        outputs,
        active = :fragment_count,
    )
    return (; work, topology)
end

function _zbuffer_fixture(;
        lease_capacity = 12,
        rank_order = :min,
        ranks = Int32[-2, -2, -1, -1, 4],
    )
    declaration = _zbuffer_declaration(; rank_order)
    backend = KA.CPU()
    workplan = LW.plan(
        declaration.work, declaration.topology; backend
    )
    storage = (
        fragment_depths = copy(ranks),
        fragment_colors = UInt32[0x11, 0x22, 0x33, 0x44, 0x55],
        framebuffer_color = fill(UInt32(0xff), 4),
        fragment_coverage = Bool[true, true, true, false, true],
    )
    workspace = (
        winner_ranks = Vector{Int32}(undef, 4),
        winner_identities = Vector{UInt32}(undef, 4),
        leases = Any[nothing for _ in 1:lease_capacity],
    )
    submission = (;
        fragment_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(5)
        ),
    )
    prepared = LW.prepare(
        workplan, storage; workspace, submission
    )
    return merge(declaration, (;
        workplan, prepared, storage, workspace, submission,
    ))
end

function _conjunctive_fixture(;
        lease_capacity = 12,
        keys_a = Int32[1, 1, 3, 0, 2, -1],
        keys_b = Int32[2, 3, 4, 0, 2, 0],
        ranks = UInt32[10, 9, 8, 7, 11, 6],
        identities = Int32[10, 20, 30, 40, 50, 60],
        values = UInt8[5, 5, 5, 5, 5, 4],
        gate = Bool[true],
    )
    item_count = length(keys_a)
    @assert all(length(array) == item_count for array in (
        keys_b, ranks, identities, values,
    ))
    output = LW.resolved(
        (:old_claims, :new_claims);
        empty = UInt8(2),
        rank = (
            type = UInt32,
            order = :max,
            lower = UInt32(0),
            upper = typemax(UInt32),
        ),
        tie_break = (
            input_type = Int32,
            type = UInt32,
            order = :min,
            transform = :checked_unsigned,
            proof = :strictly_increasing_active_prefix,
        ),
        capacity = item_count,
        key_type = Int32,
        value_type = UInt8,
        skipped_keys = :nonpositive,
        result = (
            layout = :items,
            selection = :all,
            zero_claim = :selected,
            selected = :preserve,
            ineligible = :preserve,
        ),
    )
    work = LW.localwork(
        (family = :resolved_conjunctive_selection, eligible = UInt8(5)),
        1:item_count;
        read = (
            key_a = :old_claims,
            key_b = :new_claims,
            rank = :priorities,
            identity = :semantic_ids,
            value = :dispositions,
            gate = :execution_open,
        ),
        outputs = (; dispositions = output),
        active = :active_count,
    )
    topology = (
        item_count = Int32(item_count),
        destination_count = Int32(4),
        epoch = UInt64(1),
    )
    backend = KA.CPU()
    workplan = LW.plan(work, topology; backend)
    storage = (
        old_claims = copy(keys_a),
        new_claims = copy(keys_b),
        priorities = copy(ranks),
        semantic_ids = copy(identities),
        dispositions = copy(values),
        execution_open = copy(gate),
    )
    workspace = (
        winner_ranks = fill(UInt32(0xaa), 4),
        winner_identities = fill(UInt32(0xbb), 4),
        leases = Any[nothing for _ in 1:lease_capacity],
    )
    submission = (;
        active_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(item_count)
        ),
    )
    prepared = LW.prepare(workplan, storage; workspace, submission)
    return (;
        work,
        topology,
        workplan,
        prepared,
        storage,
        workspace,
        submission,
    )
end
