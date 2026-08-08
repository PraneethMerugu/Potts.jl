@testset "semantic Philox known answers and address isolation" begin
    contract = CorePotts.Philox4x32x10V1()
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
    )
    expected = (
        (0xd5435ca6, 0xe6f8d826, 0x0a5be497, 0x655d2e74),
        (0x4bbab362, 0xc294cc98, 0xbc40f1d2, 0x1ee62536),
        (0x1da796db, 0xbb662cea, 0x65d4ed06, 0x91036c89),
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
end
