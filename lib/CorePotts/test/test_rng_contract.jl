@testset "semantic Philox known answers and address isolation" begin
    contract = CorePotts.Philox4x32x10V2()
    seed = UInt64(0x123456789abcdef0)
    addresses = (
        CorePotts.RNGAddress(
            stream = CorePotts.ProposalRecipientStream,
            mcs = 0,
            entity = 1,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.ProposalDirectionStream,
            mcs = 7,
            subround = 2,
            operation = 3,
            entity = 19,
            draw = 1,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 11,
            operation = 5,
            entity = 29,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.CheckerboardColorOrderStream,
            mcs = 23,
            subround = 1,
            operation = 5,
            entity_kind = CorePotts.GlobalEntity,
            entity = 4,
        ),
    )
    expected = (
        (0xd5435ca6, 0xe6f8d826, 0x0a5be497, 0x655d2e74),
        (0x868780c6, 0xd8f3722f, 0x32d0eed7, 0xa67c75ea),
        (0x1da796db, 0xbb662cea, 0x65d4ed06, 0x91036c89),
        (0x3719387b, 0x66108d4d, 0x3c826416, 0xb29ecb59),
    )

    # This is intentionally Core-owned. Raw words are part of the versioned
    # implementation contract, but are not widened into the package API.
    @test map(
        address -> CorePotts._rng_words(contract, seed, address),
        addresses,
    ) == expected
    @test reverse(map(
        address -> CorePotts._rng_words(contract, seed, address),
        reverse(addresses),
    )) == expected

    semantic_coordinates = [
        (stream, mcs, subround, entity, draw)
        for stream in (
            CorePotts.ProposalRecipientStream,
            CorePotts.ProposalDirectionStream,
            CorePotts.AcceptanceStream,
            CorePotts.CheckerboardColorOrderStream,
        )
        for mcs in 0:2
        for subround in 0:1
        for entity in 1:4
        for draw in 0:1
    ]
    @test allunique(semantic_coordinates)
    raw_words = map(semantic_coordinates) do coordinates
        stream, mcs, subround, entity, draw = coordinates
        CorePotts._rng_words(
            contract,
            seed,
            CorePotts.RNGAddress(
                stream = stream,
                mcs = mcs,
                subround = subround,
                entity = entity,
                draw = draw,
            ),
        )
    end
    @test allunique(raw_words)
    @test all(stream -> UInt8(stream) <= 0x0f, instances(CorePotts.RNGStream))

    kind_draw_addresses = (
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            entity_kind = CorePotts.GlobalEntity,
            draw = 1,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            entity_kind = CorePotts.DestinationEntity,
            draw = 0,
        ),
    )
    @test CorePotts._rng_words(contract, seed, kind_draw_addresses[1]) !=
        CorePotts._rng_words(contract, seed, kind_draw_addresses[2])

    minimum_words = ntuple(_ -> UInt32(0), 4)
    maximum_words = ntuple(_ -> typemax(UInt32), 4)
    @test 0.0f0 < CorePotts._uniform_open01_from_words(
        Float32, minimum_words
    ) < 1.0f0
    @test 0.0f0 < CorePotts._uniform_open01_from_words(
        Float32, maximum_words
    ) < 1.0f0
    @test 0.0 < CorePotts._uniform_open01_from_words(
        Float64, minimum_words
    ) < 1.0
    @test 0.0 < CorePotts._uniform_open01_from_words(
        Float64, maximum_words
    ) < 1.0

    old_collision_seed = UInt64(0xa2598acb81de843f)
    @test CorePotts._trajectory_seed(UInt64(0), UInt32(1), UInt32(1)) !=
        CorePotts._trajectory_seed(
            old_collision_seed, UInt32(2), UInt32(1)
        )

    base = CorePotts.RNGAddress(
        stream = CorePotts.AcceptanceStream,
        mcs = 9,
        subround = 1,
        operation = 4,
        entity_kind = CorePotts.CellEntity,
        entity = 7,
        generation = 3,
        invocation = 0,
        draw = 2,
    )
    base_words = CorePotts._rng_words(contract, seed, base)
    changed = (
        CorePotts.RNGAddress(
            stream = CorePotts.ProposalDirectionStream,
            mcs = 9,
            subround = 1,
            operation = 4,
            entity_kind = CorePotts.CellEntity,
            entity = 7,
            generation = 3,
            invocation = 0,
            draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 10,
            subround = 1,
            operation = 4,
            entity_kind = CorePotts.CellEntity,
            entity = 7,
            generation = 3,
            invocation = 0,
            draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9,
            subround = 1,
            operation = 4,
            entity_kind = CorePotts.CellEntity,
            entity = 7,
            generation = 4,
            invocation = 0,
            draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9,
            subround = 1,
            operation = 4,
            entity_kind = CorePotts.CellEntity,
            entity = 7,
            generation = 3,
            invocation = 1,
            draw = 2,
        ),
    )
    @test all(
        address -> CorePotts._rng_words(contract, seed, address) != base_words,
        changed,
    )

    isolation_base = CorePotts.RNGAddress(
        stream = CorePotts.AcceptanceStream,
        mcs = 9,
        subround = 1,
        operation = 4,
        entity_kind = CorePotts.SiteEntity,
        entity = 7,
        generation = 3,
        invocation = 1,
        draw = 2,
    )
    coordinate_extrema = (
        CorePotts.RNGAddress(
            stream = CorePotts.ProposalDirectionStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = CorePotts._RNG_MAX_MCS, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = typemax(UInt8), operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = CorePotts._RNG_MAX_OPERATION,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.CellEntity, entity = 7,
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = typemax(UInt32),
            generation = 3, invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = typemax(UInt64), invocation = 1, draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = typemax(UInt8), draw = 2,
        ),
        CorePotts.RNGAddress(
            stream = CorePotts.AcceptanceStream,
            mcs = 9, subround = 1, operation = 4,
            entity_kind = CorePotts.SiteEntity, entity = 7,
            generation = 3, invocation = 1, draw = CorePotts._RNG_MAX_DRAW,
        ),
    )
    isolation_words = CorePotts._rng_words(contract, seed, isolation_base)
    @test all(coordinate_extrema) do address
        CorePotts._rng_words(contract, seed, address) != isolation_words
    end
end
