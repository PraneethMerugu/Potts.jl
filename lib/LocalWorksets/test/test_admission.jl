const _WAIT_DRAIN_FIXTURE = _zbuffer_fixture()
const _WAIT_DRAIN_EVENT = LW.run!(
    _WAIT_DRAIN_FIXTURE.prepared, (; fragment_count = Int32(5))
)

@testset "source-level generic substrate contains no resolved mechanism" begin
    source_root = dirname(pathof(LW))
    source_paths = sort(filter(
        path -> endswith(path, ".jl"),
        collect(
            joinpath(root, file) for (root, _, files) in walkdir(source_root)
            for file in files
        ),
    ))
    all_source = join(read.(source_paths, String), '\n')
    substrate_paths = joinpath.(Ref(source_root), (
        "LocalWorksets.jl",
        "model.jl",
        "planning.jl",
        "preparation.jl",
        "execution.jl",
        "inspection.jl",
    ))
    substrate_source = join(read.(substrate_paths, String), '\n')
    resolved_source = read(joinpath(
        dirname(pathof(LW)), "execution", "localworksets_resolved.jl"
    ), String)
    provider_source = read(joinpath(
        dirname(pathof(LW)),
        "execution",
        "localworksets_kernelabstractions.jl",
    ), String)
    evidence_source = read(joinpath(
        dirname(pathof(LW)),
        "execution",
        "localworksets_evidence.jl",
    ), String)
    portable_source = join(read.(filter(
        path -> !endswith(path, "localworksets_evidence.jl"),
        source_paths,
    ), String), '\n')
    @test !occursin("winner_ranks", substrate_source)
    @test !occursin("winner_identities", substrate_source)
    @test !occursin("resolved_selection", substrate_source)
    @test !occursin("operation === identity", substrate_source)
    @test !occursin("fragment", lowercase(substrate_source))
    @test !occursin("checkerboard", lowercase(substrate_source))
    @test !occursin("_CPULane", substrate_source)
    for vendor in ("metal", "cuda", "amdgpu", "rocm", "allowscalar")
        @test !occursin(vendor, lowercase(portable_source))
    end
    @test !occursin("synchronize(", substrate_source)
    @test !occursin("synchronize(", resolved_source)
    @test length(collect(eachmatch(
        r"(?m)^\s*KernelAbstractions\.synchronize\(", provider_source
    ))) == 1
    @test occursin("Metal.MetalKernels", evidence_source)
    @test !occursin("@kernel", evidence_source)
    @test !occursin("synchronize(", evidence_source)
    @test !occursin("function ", evidence_source)
    @test !occursin("CorePotts", all_source)
    @test !occursin("PottsToolkit", all_source)
    @test !occursin("ModelingToolkit", all_source)
    @test !occursin("047998c1-3edd-4edf-b561-cee99549c5a6", all_source)
    @test !isdir(joinpath(dirname(source_root), "ext"))
    @test all(source_paths) do path
        count(line -> begin
            stripped = strip(line)
            !isempty(stripped) && !startswith(stripped, '#')
        end, eachline(path)) <= 1_000
    end
    @test occursin("@kernel", resolved_source)
    @test occursin("Atomix.@atomic", resolved_source)
    @test occursin("_centrally_qualified_atomic_capability", resolved_source)
    @test occursin("_centrally_qualified_value_capability", resolved_source)
end

@testset "lifecycle wrappers cannot replace package validation or execution" begin
    fixture = _zbuffer_fixture()
    LW._central_make_provider_lane(
        ::typeof(fixture.workplan.backend), ::typeof(fixture.storage)
    ) = :forged_lane
    LW._resolved_clear_kernel!(::KA.CPU) = :forged_kernel
    prepared = LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = fixture.workspace,
        submission = fixture.submission,
    )
    @test LW.inspect(prepared).provider === :KernelAbstractions
    @test prepared.runtime.clear_kernel !== :forged_kernel

    LW._cache_execution_lowering!(
        ::typeof(prepared), arguments::Tuple
    ) = begin
        fill!(fixture.storage.framebuffer_color, UInt32(0xdeadbeef))
        typeof(arguments)
    end
    event = LW.run!(prepared, (; fragment_count = Int32(5)))
    wait(event)
    @test fixture.storage.framebuffer_color == UInt32[0x22, 0x33, 0x55, 0]

    binding_fixture = _zbuffer_fixture()
    binding_storage = (
        fragment_depths = binding_fixture.storage.fragment_depths,
        fragment_colors = binding_fixture.storage.fragment_colors,
        framebuffer_color = binding_fixture.storage.framebuffer_color,
    )
    binding_submission = (
        fragment_count = binding_fixture.submission.fragment_count,
        fragment_coverage = LW.storage_slot(
            binding_fixture.storage.fragment_coverage; access = :read
        ),
        binding_nonce = LW.value_slot(
            UInt16; bounds = UInt16(0):UInt16(1)
        ),
    )
    binding_prepared = LW.prepare(
        binding_fixture.workplan,
        binding_storage;
        workspace = binding_fixture.workspace,
        submission = binding_submission,
    )
    binding_values = (
        fragment_count = Int32(5),
        fragment_coverage = binding_fixture.storage.fragment_coverage,
        binding_nonce = UInt16(1),
    )
    wait(LW.run!(binding_prepared, binding_values))
    LW._all_bindings(
        ::typeof(binding_prepared), ::typeof(binding_values)
    ) = (; forged = fill(UInt32(0xdeadbeef), 1))
    @test_throws LW.LocalWorkValidationError LW.run!(
        binding_prepared, binding_values
    )
    @test binding_prepared.submitted == UInt64(1)

    LW._canonical_submission(
        ::typeof(prepared.submission_schema), submission::NamedTuple
    ) = (; fragment_count = Int32(5))
    @test_throws LW.LocalWorkValidationError LW.run!(
        prepared, (; fragment_count = Int32(6))
    )

    LW._validate_fresh_topology(
        ::typeof(fixture.workplan); structural::Bool = true
    ) = nothing
    fixture.topology.pixel_indices[1] = Int32(2)
    @test_throws LW.LocalWorkValidationError LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = fixture.workspace,
        submission = fixture.submission,
    )
end

const _EXACT_EXECUTION_FIXTURE = _zbuffer_fixture()

@testset "type-specialized capability evidence cannot be substituted" begin
    LW._atomic_capability(
        ::KA.Backend, ::Type{Int32}, ::Symbol, ::Symbol
    ) = true
    LW._value_capability(
        ::KA.Backend, ::Type{UInt32}, ::Symbol, ::Symbol
    ) = true
    @test !invoke(
        LW._centrally_qualified_atomic_capability,
        Tuple{Any, Type, Symbol, Symbol},
        KA.CPU(),
        Int32,
        :min,
        :global,
    )
    @test !invoke(
        LW._centrally_qualified_value_capability,
        Tuple{Any, Type, Symbol, Symbol},
        KA.CPU(),
        UInt32,
        :store,
        :global,
    )
end

@testset "reviewed compiler evidence cannot be pirated" begin
    declaration = _zbuffer_declaration()
    LW._provider_compiler_identity(::KA.CPU) = (forged = true,)
    @test_throws Exception LW.plan(
        declaration.work, declaration.topology; backend = KA.CPU()
    )
end

@testset "lowering evidence cannot be pirated" begin
    declaration = _zbuffer_declaration()
    LW._lowering_evidence(
        lowering::LW._ResolvedWinnerLowering,
        work::LW.LocalWork,
        topology,
        ::KA.CPU,
    ) = (forged = true,)
    @test_throws Exception LW.plan(
        declaration.work, declaration.topology; backend = KA.CPU()
    )
end

@testset "admission has no replaceable wrapper dispatch" begin
    @test !isdefined(LW, :_admit)
    declaration = _zbuffer_declaration()
    valid = declaration.work
    unauthorized = LW.localwork(
        merge(valid.operation, (family = :unauthorized_family,)),
        valid.items;
        read = valid.reads,
        outputs = valid.outputs,
        active = valid.active,
    )
    @test typeof(unauthorized) === typeof(valid)
    LW._central_admission(
        ::typeof(unauthorized), topology, backend
    ) = :forged_lowering
    @test which(
        LW._central_admission,
        Tuple{typeof(unauthorized), typeof(declaration.topology), KA.CPU},
    ).module === Main
    @test_throws LW.LocalWorkValidationError LW.plan(
        unauthorized, declaration.topology; backend = KA.CPU()
    )
end

@testset "post-submission method changes cannot strand the provider tail" begin
    fixture = _WAIT_DRAIN_FIXTURE
    lane_type = typeof(fixture.prepared.lane)
    @eval function LW._validate_lane_current!(lane::$lane_type)
        error("hostile post-submission lane validation")
    end
    wait(_WAIT_DRAIN_EVENT)
    @test fixture.prepared.submitted == UInt64(1)
    @test fixture.prepared.drained == UInt64(1)
    @test all(isnothing, fixture.prepared.leases)
    @test fixture.storage.framebuffer_color == UInt32[0x22, 0x33, 0x55, 0]
end

@testset "exact cached-execution replacement cannot launch" begin
    fixture = _EXACT_EXECUTION_FIXTURE
    function LW._cache_execution_lowering!(
            prepared::LW.PreparedWork, arguments::Tuple
        )
        fill!(fixture.storage.framebuffer_color, UInt32(0xdeadbeef))
        return typeof(arguments)
    end
    @test which(
        LW._cache_execution_lowering!, Tuple{LW.PreparedWork, Tuple}
    ).module === Main
    @test_throws LW.LocalWorkValidationError LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    @test fixture.prepared.submitted == UInt64(0)
    @test !LW.inspect(fixture.prepared).poisoned
    @test fixture.storage.framebuffer_color == fill(UInt32(0xff), 4)
end

@testset "exact central admission replacement cannot launch" begin
    declaration = _zbuffer_declaration()
    function LW._central_admission(
            work::LW.LocalWork, topology::Any, backend::Any
        )
        return LW._ResolvedWinnerLowering(
            :rank,
            :identity,
            :destination,
            :value,
            :gate,
            :output,
            Int32,
            UInt32,
            UInt32,
            UInt32,
            :min,
            :min,
            :checked_unsigned,
            :all,
            :items,
            UInt32(0),
            4,
        )
    end
    @test which(
        LW._central_admission, Tuple{LW.LocalWork, Any, Any}
    ).module === Main
    @test_throws LW.LocalWorkValidationError LW.plan(
        declaration.work, declaration.topology; backend = KA.CPU()
    )
end
