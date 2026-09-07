import LocalMath
import Statistics
import Symbolics

function _gather_reduction_outcome(kind, ::Type{T}, values) where {T}
    operation = Potts._materialize_gather_reduction(Val(kind), T)
    outcome = LocalMath.evaluate_bounded(
        operation,
        length(values),
        index -> (present = true, value = values[Int(index)]),
    )
    return (; operation, outcome)
end

@testset "gather reductions preserve Julia values and result types" begin
    for T in (
            Bool,
            Int8, Int16, Int32, Int64,
            UInt8, UInt16, UInt32, UInt64,
            Float16, Float32, Float64,
        )
        values = T === Bool ? Bool[true, false, true] : T[1, 1, 2]
        for (kind, oracle) in (
                (:sum, sum),
                (:minimum, minimum),
                (:maximum, maximum),
                (:mean, Statistics.mean),
            )
            result = _gather_reduction_outcome(kind, T, values)
            expected = oracle(values)
            @test result.outcome.valid
            @test result.outcome.value == expected
            @test typeof(result.outcome.value) === typeof(expected)
            @test isbits(result.operation)
        end
    end

    empty_sum = _gather_reduction_outcome(:sum, Float32, Float32[]).outcome
    @test empty_sum.valid
    @test empty_sum.value === 0.0f0
    empty_mean = _gather_reduction_outcome(:mean, Float32, Float32[]).outcome
    @test empty_mean.valid
    @test isnan(empty_mean.value)
    @test empty_mean.value isa Float32
    @test !_gather_reduction_outcome(
        :minimum, Float32, Float32[]).outcome.valid
    @test !_gather_reduction_outcome(
        :maximum, Float32, Float32[]).outcome.valid

    geometric = _gather_reduction_outcome(
        :geometric_mean, Float32, Float32[1, 4, 16]).outcome
    @test geometric.valid
    @test geometric.value ≈ 4.0f0
    @test geometric.value isa Float32
    @test !_gather_reduction_outcome(
        :geometric_mean, Float32, Float32[0, 1]).outcome.valid
    @test !_gather_reduction_outcome(
        :geometric_mean, Float32, Float32[]).outcome.valid
end

@testset "symbolic gather reductions lower through one bounded-fold operation" begin
    @variables reduction_signal
    signal = FieldState(
        reduction_signal; name = :reduction_signal, initial = 1.0)
    site = SiteBinding(:reduction_site)
    values = gather(signal, :contact; at = site)

    for T in (Float32, Float64)
        operations = (
            Potts._materialize_gather_reduction(Val(:sum), T),
            Potts._materialize_gather_reduction(Val(:minimum), T),
            Potts._materialize_gather_reduction(Val(:maximum), T),
            Potts._materialize_gather_reduction(Val(:mean), T),
            Potts._materialize_gather_reduction(Val(:geometric_mean), T),
        )
        @test all(isbits, operations)
        @test all(operations) do operation
            result_type = Core.Compiler.return_type(
                operation.finish, Tuple{typeof(operation.seed),Int32})
            result_type === T
        end
    end

    @test sum(values) isa Symbolics.Num
    @test minimum(values) isa Symbolics.Num
    @test maximum(values) isa Symbolics.Num
    @test Statistics.mean(values) isa Symbolics.Num
    @test LocalMath.geometric_mean(values) isa Symbolics.Num
    proposal = ProposalContext(:whole_proposal)
    @test sum(gather(
        signal, :contact; at = proposal.target_site)) isa Symbolics.Num
    @test sum(gather(
        signal, :contact; at = Potts.anchor_value(site))) isa Symbolics.Num
    @test_throws ArgumentError gather(signal, :contact; at = proposal)
    for invalid_anchor in (1, :site, [1, 2])
        error = try
            gather(signal, :contact; at = invalid_anchor)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin("gather anchor must be", sprint(showerror, error))
    end
end

@testset "mixed gather reductions have a canonical compilation fingerprint" begin
    @variables mixed_reduction_signal
    signal = FieldState(
        mixed_reduction_signal;
        name = :mixed_reduction_signal,
        initial = 1.0f0,
    )
    cell = CellKind(:mixed_reduction_cell; extinction = RetireAtZero())
    medium = MediumKind(:mixed_reduction_medium)
    proposal = ProposalContext(:mixed_reduction_proposal)
    values = gather(signal, :contact; at = proposal.target_site)
    expression = sum(values) + minimum(values) + maximum(values) +
        Statistics.mean(values) + LocalMath.geometric_mean(values)

    source = PottsSystem(
        name = :mixed_gather_reduction_system,
        statements = StatementSet((
            Lattice((3, 3); relations = (
                contact = VonNeumann(), proposal = VonNeumann(),
            )),
            cell,
            medium,
            signal,
            ProposalDrive(:mixed_gather_reductions, expression),
            ProposalConstraint(:mixed_gather_reductions_frozen, false),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [mixed_reduction_signal],
    )
    first_schedule = mtkcompile(source)
    second_schedule = mtkcompile(source)
    @test scheduled_system_fingerprint(first_schedule) ==
          scheduled_system_fingerprint(second_schedule)
    @test mtkcompile(first_schedule) === first_schedule

    labels = zeros(Int32, 3, 3)
    labels[2, 2] = 1
    problem = PottsProblem(
        first_schedule,
        PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            values = (mixed_reduction_signal => fill(4.0f0, 3, 3),),
        ),
        (0, 1);
        seed = 0x6a71,
    )
    solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
end
