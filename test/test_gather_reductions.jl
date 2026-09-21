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

_test_act_finish(total, count) = exp(total / count)

@testset "lane-bound site gathers expose exact-owner selection" begin
    @variables gathered_activity
    cell = CellKind(:gathered_activity_cell; extinction = RetireAtZero())
    activity = SiteState(
        gathered_activity; name = :gathered_activity, owner = cell,
        initial = 0.0, lifecycle = ClearOnOwnershipChange())
    copy = ProposalContext(:gathered_activity_copy)
    lane = SiteBinding(:gathered_activity_lane)
    other_lane = SiteBinding(:other_activity_lane)
    values = gather(
        site_value(activity, lane);
        bind = lane,
        at = copy.source_site,
        over = :act_neighbors,
        where = site_owner(lane) == copy.source_cell,
    )
    expression = LocalMath.fold(values;
        map = log, combine = +, init = 0.0,
        finish = _test_act_finish,
        domain = >=(0.0), invalid = :reject, empty = 0.0,
        order = :canonical,
    )
    node = Symbolics.unwrap(expression)
    @test Symbolics.operation(node) === Potts._potts_bounded_fold
    arguments = Symbolics.arguments(node)
    @test length(arguments) == 6
    @test Symbolics.value(arguments[5]) === true
    @test Symbolics.operation(arguments[6]) === source_cell
    @test_throws ArgumentError gather(
        site_value(activity, lane);
        bind = other_lane, at = copy.source_site, over = :act_neighbors)
    @test_throws ArgumentError gather(
        site_value(activity, lane);
        bind = lane, at = copy.source_site, over = :act_neighbors,
        where = site_owner(other_lane) == copy.source_cell)
end

@testset "symbolic gather reductions lower through one bounded-fold operation" begin
    @variables reduction_signal
    signal = FieldState(
        reduction_signal; name = :reduction_signal, initial = 1.0)
    site = SiteBinding(:reduction_site)
    values = gather(signal; at = site, over = :contact)

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
    @test sum(gather(signal; at = proposal.target_site, over = :contact)) isa Symbolics.Num
    @test sum(gather(
        signal; at = Potts.anchor_value(site), over = :contact)) isa Symbolics.Num
    @test_throws ArgumentError gather(signal; at = proposal, over = :contact)
    for invalid_anchor in (1, :site, [1, 2])
        error = try
            gather(signal; at = invalid_anchor, over = :contact)
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
    values = gather(signal; at = proposal.target_site, over = :contact)
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
