@parameters scheduling_target = 4.0
@variables scheduling_marker

function _scheduling_fixture(name::Symbol)
    cell = CellKind(:scheduled_cell; extinction = RetireAtZero())
    medium = MediumKind(:scheduled_medium)
    links = RelationshipState(
        :scheduled_links;
        capacity = 8,
        maximum_degree = 4,
        endpoints = Undirected(cell, cell),
    )
    return PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            links,
            SiteState(
                scheduling_marker;
                name = :scheduling_marker,
                owner = cell,
                initial = 0.0,
            ),
            Volume(cell; target = scheduling_target, strength = 1.0),
            Observation(:marker_observation, scheduling_marker),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [scheduling_marker],
        parameters = [scheduling_target],
        initial_conditions = Dict(scheduling_marker => 2.0),
    )
end

function _type_erased_scheduling_fixture(name::Symbol, observation_count::Int)
    cell = CellKind(:type_stability_cell; extinction = RetireAtZero())
    medium = MediumKind(:type_stability_medium)
    declarations = Any[Lattice((4, 4)), cell, medium]
    append!(declarations, [
        Observation(Symbol(:type_stability_observation_, index), Float64(index))
        for index in 1:observation_count
    ])
    push!(declarations, Protocol(Sweep(); name = :main))
    return PottsSystem(
        name = name,
        statements = StatementSet(declarations),
    )
end

@testset "completion and scheduling topology stays out of carrier types" begin
    # Composite numeric values are encoded structurally. `isbitstype` alone
    # is insufficient because `bitstring` accepts primitive numbers only.
    @test Potts._canonical_value(1.0u"m") ==
          Potts._canonical_value(1.0u"m")
    @test Potts._canonical_value(1.0u"m") !=
          Potts._canonical_value(2.0u"m")
    @test Potts._canonical_value(1.0u"m") !=
          Potts._canonical_value(1.0u"s")

    small = complete(_type_erased_scheduling_fixture(:type_stability_small, 1))
    large = complete(_type_erased_scheduling_fixture(:type_stability_large, 24))
    small_completion = getfield(small, :completion)
    large_completion = getfield(large, :completion)

    @test typeof(small_completion) === typeof(large_completion) ===
          Potts.CompletedPottsData
    @test typeof(small_completion.records) ===
          typeof(large_completion.records) === Vector{Potts.QualifiedStatement}
    @test typeof(small_completion.schedule) ===
          typeof(large_completion.schedule) === Vector{Potts.QualifiedStatement}
    @test typeof(small_completion.variables) ===
          typeof(large_completion.variables) === Vector{Any}
    @test inspect(small, Statements()) isa Tuple
    @test inspect(small, Variables()) isa Tuple
    @test inspect(small, Schedule()) isa Tuple

    small_scheduled = mtkcompile(small)
    large_scheduled = mtkcompile(large)
    small_data = getfield(small_scheduled, :completion).scheduled
    large_data = getfield(large_scheduled, :completion).scheduled
    @test typeof(small_data) === typeof(large_data) ===
          Potts.ScheduledPottsData
    @test typeof(small_data.schedule) === typeof(large_data.schedule) ===
          Vector{Potts.QualifiedStatement}
    @test typeof(small_data.provenance.records) ===
          typeof(large_data.provenance.records) === Vector{NamedTuple}
    @test typeof(small_data.capability_requirements.engine_admission) ===
          typeof(large_data.capability_requirements.engine_admission) ===
          Vector{NamedTuple}

    # The type-erased encoder must retain the reference logical tuple bytes.
    reference_fingerprint = Potts._scheduled_fingerprint(
        small_completion.fingerprints.completed,
        Tuple(small_data.schedule),
        Potts._fingerprint_scheduled_provenance(small_data.provenance),
        Potts._fingerprint_scheduled_parameters(small_data.parameters),
        Tuple(small_data.states),
        Tuple(small_data.relationships),
        Tuple(small_data.observations),
        Potts._fingerprint_scheduled_capabilities(
            small_data.capability_requirements
        ),
        Tuple(Potts._scheduled_native_provenance(
            small_data.native_components
        )),
    )
    @test small_data.fingerprint == reference_fingerprint
    @test inspect(small_scheduled, Schedule()) isa Tuple
    @test inspect(small_scheduled, StateSchema()).states isa Tuple
    @test inspect(small_scheduled, Observations()) isa Tuple
end

@testset "state defaults stay outside science identity but inside scheduling" begin
    @variables scheduled_default_state
    cell = CellKind(:scheduled_default_cell; extinction = RetireAtZero())
    medium = MediumKind(:scheduled_default_medium)
    function default_system(initial)
        return PottsSystem(
            name = :scheduled_default_model,
            statements = StatementSet((
                Lattice((3, 3)),
                cell,
                medium,
                SiteState(
                    scheduled_default_state;
                    name = :scheduled_default_state,
                    initial,
                ),
                Protocol(Sweep(); name = :main),
            )),
            unknowns = [scheduled_default_state],
        )
    end
    first_completed = complete(default_system(1.0))
    second_completed = complete(default_system(9.0))
    @test semantic_fingerprint(first_completed) ==
          semantic_fingerprint(second_completed)
    @test completed_system_fingerprint(first_completed) ==
          completed_system_fingerprint(second_completed)

    first = mtkcompile(first_completed)
    second = mtkcompile(second_completed)
    @test scheduled_system_fingerprint(first) !=
          scheduled_system_fingerprint(second)
    @test only(inspect(first, StateSchema()).states).initial == 1.0
    @test only(inspect(second, StateSchema()).states).initial == 9.0
end

@testset "PT03 spatial queries reject unsupported executable lowering" begin
    @variables query_owner query_filter
    cell = CellKind(:query_cell; extinction = RetireAtZero())
    medium = MediumKind(:query_medium)
    source = PottsSystem(
        name = :interface_only_query,
        statements = StatementSet((
            Lattice((2, 2)),
            cell,
            medium,
            ModelState(query_owner; name = :query_owner, initial = 1.0),
            ModelState(query_filter; name = :query_filter, initial = 1.0),
            Observation(
                :contact_edges,
                contact_edge_count(query_owner, query_filter),
            ),
            Protocol(Sweep(); name = :query_protocol),
        )),
        unknowns = [query_owner, query_filter],
    )
    error = try
        mtkcompile(source)
        nothing
    catch caught
        caught
    end
    @test error isa Potts.PottsValidationError
    @test error.stage === :scheduling
    @test occursin("interface-only settled-snapshot spatial query", sprint(
        showerror, error
    ))
    @test occursin("not implemented", sprint(showerror, error))
end

function _contains_corepotts_value(value)
    module_name = string(parentmodule(typeof(value)))
    startswith(module_name, "CorePotts") && return true
    if value isa NamedTuple || value isa Tuple
        return any(_contains_corepotts_value, values(value))
    elseif value isa Pair
        return _contains_corepotts_value(first(value)) ||
               _contains_corepotts_value(last(value))
    elseif value isa AbstractArray
        return any(_contains_corepotts_value, value)
    elseif value isa AbstractDict
        return any(pair ->
            _contains_corepotts_value(first(pair)) ||
            _contains_corepotts_value(last(pair)), value)
    elseif parentmodule(typeof(value)) === Potts &&
            isstructtype(typeof(value))
        return any(
            field -> _contains_corepotts_value(getfield(value, field)),
            fieldnames(typeof(value)),
        )
    end
    return false
end

@testset "pure-Potts structural mtkcompile" begin
    source = _scheduling_fixture(:scheduled_model)
    completed = complete(source)
    @test iscomplete(completed)
    @test !is_scheduled(completed)
    @test complete(completed) === completed

    scheduled = mtkcompile(completed)
    @test scheduled isa PottsSystem
    @test iscomplete(scheduled)
    @test is_scheduled(scheduled)
    @test complete(scheduled) === scheduled
    @test mtkcompile(scheduled) === scheduled

    fingerprints = inspect(scheduled, Fingerprints())
    @test fingerprints.semantic == semantic_fingerprint(scheduled)
    @test fingerprints.completed == completed_system_fingerprint(scheduled)
    @test fingerprints.scheduled == scheduled_system_fingerprint(scheduled)
    @test length(string(fingerprints.scheduled)) == 64

    independently_scheduled = mtkcompile(_scheduling_fixture(:scheduled_model))
    @test inspect(independently_scheduled, Fingerprints()) == fingerprints
    @test inspect(scheduled, Schedule()) == inspect(completed, Schedule())
    observation_record = only(filter(
        record -> record.kind === :Observation,
        inspect(scheduled, Schedule()),
    ))
    @test observation_record.phase === nothing
    @test isempty(observation_record.ordering_dependencies)

    parameters = inspect(scheduled, ParameterSchema())
    @test only(parameters.runtime).name === :scheduling_target
    @test only(parameters.runtime).default == 4.0
    @test !only(parameters.runtime).required
    state_schema = inspect(scheduled, StateSchema())
    @test only(state_schema.states).key === :scheduling_marker
    @test only(state_schema.states).initial == 2.0
    @test only(state_schema.states).initial_source === :system
    @test only(state_schema.relationships).name === :scheduled_links
    @test only(state_schema.relationships).capacity == 8
    @test only(inspect(scheduled, Observations())).name === :marker_observation
    @test length(inspect(scheduled, Capabilities()).requirements.domains) == 1

    completion = getfield(scheduled, :completion)
    structural = completion.scheduled
    @test structural isa Potts.ScheduledPottsData
    @test fieldnames(typeof(structural)) == (
        :schema_version,
        :schedule,
        :provenance,
        :parameters,
        :states,
        :relationships,
        :observations,
        :native_components,
        :capability_requirements,
        :fingerprint,
    )
    @test !_contains_corepotts_value(structural)
    for forbidden in (
            :algorithm, :engine, :backend, :device, :scalar_type,
            :core_program, :runtime, :workspace,
        )
        @test !hasfield(typeof(structural), forbidden)
    end

    runtime_error = try
        mtkcompile(completed; backend = CPUBackend())
        nothing
    catch caught
        caught
    end
    @test runtime_error isa ArgumentError
    @test occursin("pass runtime choices to init or solve", sprint(showerror, runtime_error))

    passes_error = try
        mtkcompile(completed; additional_passes = ())
        nothing
    catch caught
        caught
    end
    @test passes_error isa ArgumentError
    @test occursin("additional_passes", sprint(showerror, passes_error))

    io_error = try
        mtkcompile(completed; inputs = ())
        nothing
    catch caught
        caught
    end
    @test io_error isa ArgumentError
    @test occursin("declare inputs and outputs", sprint(showerror, io_error))

    @test Potts.mtkcompile === ModelingToolkitBase.mtkcompile
    @test :mtkcompile in names(Potts)
    @test Symbol("@mtkcompile") in names(Potts)

    macro_source = _scheduling_fixture(:macro_scheduled)
    @mtkcompile macro_scheduled = PottsSystem(
        statements = getfield(macro_source, :statements),
        unknowns = getfield(macro_source, :unknowns),
        parameters = getfield(macro_source, :ps),
        initial_conditions = getfield(macro_source, :initial_conditions),
    )
    @test is_scheduled(macro_scheduled)
    @test macro_scheduled isa PottsSystem

    project = dirname(@__DIR__)
    script = """
        using Potts
        @assert !any(id -> id.name == \"ModelingToolkit\", keys(Base.loaded_modules))
        cell = CellKind(:cell; extinction = RetireAtZero())
        medium = MediumKind(:medium)
        @mtkcompile smoke = PottsSystem(statements = StatementSet((
            Lattice((3, 3)),
            cell,
            medium,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )))
        @assert iscomplete(smoke)
        @assert getfield(smoke, :isscheduled)
        @assert mtkcompile(smoke) === smoke
        @assert !any(id -> id.name == \"ModelingToolkit\", keys(Base.loaded_modules))
        print(\"fresh-base-ok\")
    """
    command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
    @test read(command, String) == "fresh-base-ok"
end
