using Test
using CorePotts
using .TransitionKernelOracle
using .TransitionFixtures

@testset "transition-kernel registered production fixtures" begin
    manifest = load_transition_manifest()
    rows = empirical_fixture_rows(manifest)
    @test length(rows) == manifest["registered_empirical_source_states"] == 12
    @test length(unique(row.row_id for row in rows)) == length(rows)

    for row in rows
        fixture = build_transition_fixture(row; manifest)
        @test fixture.production_temperature isa Float32
        @test eltype(fixture.production_domain.spacing) === Float32
        @test eltype(fixture.proposal_relation.weights) === Float32
        @test eltype(property_values(fixture.logical_state, :target_volume)) === Float32
        @test eltype(property_values(fixture.logical_state, :volume_strength)) === Float32
        @test size(lattice_storage(fixture.logical_state)) ==
              Tuple(row.fixture["dimensions"])
        @test CorePotts.assert_valid_state(fixture.logical_state) === fixture.logical_state
        @test device_storage_valid(fixture.compiled_state.storage)
        if fixture.production_supported
            @test scientific_storage_valid(fixture.scientific_state)
            @test fixture.production_limitation === nothing
        else
            @test occursin("relation offsets", fixture.production_limitation) ||
                  occursin("self-edge", fixture.production_limitation)
            @test row.fixture["boundary_class"] == "periodic"
        end
        @test state_id(fixture.oracle_catalog, fixture.oracle_state) > 0
        @test length(fixture.oracle_catalog.states) <= 3^prod(row.fixture["dimensions"])

        production_energy = CorePotts.global_energy(
            fixture.volume_component, fixture.logical_state) +
            CorePotts.global_energy(fixture.contact_component, fixture.logical_state,
                fixture.production_domain)
        independent_energy = TransitionKernelOracle.global_energy(
            fixture.oracle_model, fixture.oracle_state, fixture.oracle_domain, BigFloat)
        @test Float64(independent_energy) ≈ production_energy atol = 1.0e-5
    end
end
