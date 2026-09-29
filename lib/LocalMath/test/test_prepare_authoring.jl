using Test
import KernelAbstractions
import LocalMath
const LMPA = LocalMath

function _prepare_macro_error(source)
    try
        macroexpand(@__MODULE__, Meta.parse(source))
        return nothing
    catch error
        return error
    end
end

@testset "lexical preparation lowers to the canonical Pair API" begin
    cells = LMPA.Space(3)
    input = LMPA.Field(cells, Float32)
    output = LMPA.Field(cells, Float32)
    law = LMPA.@localmath i ∈ cells begin
        output[i] = 2f0 * input[i]
    end
    backend = KernelAbstractions.CPU()
    source = Float32[1, 2, 3]
    explicit = LMPA.prepare(law,
        input => source, output => LMPA.Allocate(undef); backend)
    authored = LMPA.@prepare (law; backend) begin
        input = source
        output = allocate(undef)
    end
    wait(LMPA.execute!(explicit))
    wait(LMPA.execute!(authored))

    @test LMPA.storage(authored, input) === source
    @test LMPA.storage(authored, output) == Float32[2, 4, 6]
    @test LMPA.storage(explicit, output) == LMPA.storage(authored, output)
    @test LMPA.inspect(explicit.plan).equivalence ==
        LMPA.inspect(authored.plan).equivalence
    @test !occursin("Allocate", string(typeof(authored)))
end

@testset "lexical preparation preserves hygiene and single evaluation" begin
    cells = LMPA.Space(2)
    input = LMPA.Field(cells, Int32)
    output = LMPA.Field(cells, Int32)
    law = LMPA.@localmath i ∈ cells begin
        output[i] = input[i]
    end
    counts = zeros(Int, 4)
    order = Int[]
    once(index, value) = (counts[index] += 1; push!(order, index); value)
    backend_value = KernelAbstractions.CPU()
    source = Int32[5, 6]
    prepare = nothing
    allocate = nothing
    prepared = LMPA.@prepare (
            once(1, law);
            backend = once(2, backend_value),
            lease_capacity = once(3, 2),
        ) begin
        input = once(4, source)
        output = allocate(undef)
    end
    @test counts == ones(Int, 4)
    @test order == [1, 4, 2, 3]
    @test LMPA.submission_capacity(prepared).capacity == 2
    wait(LMPA.execute!(prepared))
    @test LMPA.storage(prepared, output) == source
end

@testset "lexical allocation forms retain exact storage meaning" begin
    cells = LMPA.Space(2)
    source_field = LMPA.Field(cells, Int32)
    filled = LMPA.Field(cells, Int32)
    copied = LMPA.Field(cells, Int32)
    output = LMPA.Field(cells, Int32)
    law = LMPA.@localmath i ∈ cells begin
        output[i] = source_field[i] + filled[i] + copied[i]
    end
    backend = KernelAbstractions.CPU()
    borrowed = Int32[1, 2]
    copied_source = Int32[10, 20]
    prepared = LMPA.@prepare (law; backend) begin
        source_field = borrowed
        filled = allocate(Int32(3))
        copied = allocate(copied_source)
        output = LMPA.Allocate(undef)
    end
    copied_source .= -1
    wait(LMPA.execute!(prepared))
    @test LMPA.storage(prepared, source_field) === borrowed
    @test LMPA.storage(prepared, filled) == Int32[3, 3]
    @test LMPA.storage(prepared, copied) == Int32[10, 20]
    @test LMPA.storage(prepared, copied) !== copied_source
    @test LMPA.storage(prepared, output) == Int32[14, 25]
end

@testset "lexical preparation rejects ambiguous setup syntax" begin
    cases = (
        "LocalMath.@prepare law begin input = data end",
        "LocalMath.@prepare (law, other) begin input = data end",
        "LocalMath.@prepare (law, other; backend) begin input = data end",
        "LocalMath.@prepare (law; backend, unknown=1) begin input = data end",
        "LocalMath.@prepare (law; backend) begin end",
        "LocalMath.@prepare (law; backend) begin model.input = data end",
        "LocalMath.@prepare (law; backend) begin (input, output) = data end",
        "LocalMath.@prepare (law; backend) begin input = data; input = other end",
        "LocalMath.@prepare (law; backend) begin if ready; input = data; end end",
        "LocalMath.@prepare (law; backend) begin input => data end",
        "LocalMath.@prepare (law; backend) begin input = allocate(1, 2) end",
    )
    for source in cases
        error = _prepare_macro_error(source)
        @test error isa LMPA.LocalMathValidationError
        @test error.contract == :prepare_syntax
        @test error.origin !== nothing
    end
end
