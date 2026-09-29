using Test
import LocalMath
import KernelAbstractions

struct ReductionControlProducer{SkipClosed} end
@inline function (::ReductionControlProducer{SkipClosed})(item::Int32, reads, parameters) where {SkipClosed}
    enabled = something(reads[1][1].value)
    return (value = LocalMath.RoutedContribution(Int32(1), enabled, !SkipClosed || enabled),)
end
struct ReductionControlSum end
@inline (::ReductionControlSum)(item::Int32, reads, parameters) =
    (value = LocalMath.RoutedContribution(Int32(1), something(reads[1][1].value)),)

function reduction_control_filtered_producers(array_type)
    return @testset "filtered reductions still produce total control" begin
        for selection in (:prefix, :mask, :subset)
            sites, singleton = LocalMath.Space(3), LocalMath.Space(1)
            enabled = LocalMath.Field(sites, Bool)
            selected = LocalMath.Field(sites, Bool)
            input = LocalMath.Field(sites, Float32)
            gate, output = LocalMath.Field(singleton, Bool), LocalMath.Field(singleton, Float32)
            count = LocalMath.Parameter(:source_count, Int32)
            route = LocalMath.RuntimeRelation(sites => singleton; degree_bound = 1, key_type = Int32)
            control = selection === :prefix ? LocalMath.Control(; prefix = count) :
                selection === :mask ? LocalMath.Control(; mask = selected) :
                LocalMath.Control(; subset = LocalMath.MaskedRelation(LocalMath.IdentityRelation(sites), selected))
            producer = LocalMath.Stage(
                sites,
                (enabled = LocalMath.Access(enabled, LocalMath.IdentityRelation(sites); required = true),),
                (
                    LocalMath.Publication(
                        (LocalMath.FieldPublication(gate, route, LocalMath.PublicationValue(:value)),),
                        LocalMath.Reduce(Bool, |; maximum = 1, seed = LocalMath.IdentitySeed(false), order = LocalMath.CanonicalLeftFold())
                    ),
                ),
                LocalMath.Evaluator(ReductionControlProducer{false}(), selection === :prefix ? (count,) : ()), control,
                LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :filtered_control_producer)
            )
            consumer = LocalMath.Stage(
                sites,
                (input = LocalMath.Access(input, LocalMath.IdentityRelation(sites); required = true),),
                (
                    LocalMath.Publication(
                        (LocalMath.FieldPublication(output, route, LocalMath.PublicationValue(:value)),),
                        LocalMath.Reduce(Float32, +; maximum = 1, seed = LocalMath.IdentitySeed(0.0f0), order = LocalMath.CanonicalLeftFold())
                    ),
                ),
                LocalMath.Evaluator(ReductionControlSum()), LocalMath.Control(; gate),
                LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :filtered_control_consumer)
            )
            selected_values = array_type(Bool[true, false, true])
            gate_values, destination = array_type(Bool[true]), array_type(Float32[-99])
            bindings = (
                enabled => array_type(trues(3)), input => array_type(Float32[1, 2, 3]),
                gate => gate_values, output => destination,
                (selection === :prefix ? () : (selected => selected_values,))...,
            )
            prepared = LocalMath.prepare(
                LocalMath.sequence(LocalMath.LocalLaw(producer), LocalMath.LocalLaw(consumer)),
                bindings...; backend = KernelAbstractions.get_backend(destination)
            )
            for active in (true, false, true)
                copyto!(selected_values, array_type(fill(active, 3)))
                parameters = selection === :prefix ? (; source_count = active ? Int32(2) : Int32(0)) : NamedTuple()
                wait(LocalMath.execute!(prepared; parameters))
                @test Array(gate_values) == Bool[active]
                @test Array(destination) == Float32[6]
            end
        end
    end
end

struct ReductionControlCount end
@inline (::ReductionControlCount)(item::Int32, reads, parameters) =
    (value = LocalMath.RoutedContribution(Int32(1), Int32(1), something(reads[1][1].value)),)

function reduction_control_atomic_prefix(array_type)
    return @testset "atomic identity-seeded reduction produces a prefix" begin
        sites, singleton = LocalMath.Space(3), LocalMath.Space(1)
        enabled = LocalMath.Field(sites, Bool)
        input = LocalMath.Field(sites, Float32)
        prefix, output = LocalMath.Field(singleton, Int32), LocalMath.Field(singleton, Float32)
        route = LocalMath.RuntimeRelation(sites => singleton; degree_bound = 1, key_type = Int32)
        producer = LocalMath.Stage(
            sites,
            (enabled = LocalMath.Access(enabled, LocalMath.IdentityRelation(sites); required = true),),
            (
                LocalMath.Publication(
                    (LocalMath.FieldPublication(prefix, route, LocalMath.PublicationValue(:value)),),
                    LocalMath.Reduce(Int32, +; maximum = 1, seed = LocalMath.IdentitySeed(Int32(0)), order = LocalMath.RelaxedAtomic())
                ),
            ),
            LocalMath.Evaluator(ReductionControlCount()), LocalMath.Control(),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :atomic_prefix_producer)
        )
        consumer = LocalMath.Stage(
            sites,
            (input = LocalMath.Access(input, LocalMath.IdentityRelation(sites); required = true),),
            (
                LocalMath.Publication(
                    (LocalMath.FieldPublication(output, route, LocalMath.PublicationValue(:value)),),
                    LocalMath.Reduce(Float32, +; maximum = 1, seed = LocalMath.IdentitySeed(0.0f0), order = LocalMath.CanonicalLeftFold())
                ),
            ),
            LocalMath.Evaluator(ReductionControlSum()), LocalMath.Control(; prefix),
            LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :atomic_prefix_consumer)
        )
        enabled_values = array_type(trues(3))
        prefix_values, destination = array_type(Int32[3]), array_type(Float32[-99])
        prepared = LocalMath.prepare(
            LocalMath.sequence(LocalMath.LocalLaw(producer), LocalMath.LocalLaw(consumer)),
            enabled => enabled_values, input => array_type(Float32[1, 2, 3]), prefix => prefix_values, output => destination;
            backend = KernelAbstractions.get_backend(destination)
        )
        for (flags, expected_count, expected_sum) in ((trues(3), 3, 6), (falses(3), 0, 0), (Bool[true, false, true], 2, 3))
            copyto!(enabled_values, array_type(flags))
            wait(LocalMath.execute!(prepared))
            @test Array(prefix_values) == Int32[expected_count]
            @test Array(destination) == Float32[expected_sum]
        end
    end
end

struct ReductionControlUnique end
@inline (::ReductionControlUnique)(item::Int32, reads, parameters) =
    (value = LocalMath.UniqueValue(something(reads[1][1].value)),)

function reduction_control_producer_totality(array_type)
    return @testset "whole-stage participation and control totality" begin
        for reduction in (false, true), gated in (false, true)
            singleton = LocalMath.Space(1)
            external = LocalMath.Field(singleton, Bool)
            gate = LocalMath.Field(singleton, Bool)
            input = LocalMath.Field(singleton, Float32)
            output = LocalMath.Field(singleton, Float32)
            producer_enabled = LocalMath.Parameter(:producer_enabled, Bool)
            route = LocalMath.RuntimeRelation(singleton => singleton; degree_bound = 1, key_type = Int32)
            law = reduction ? LocalMath.Reduce(
                    Bool, |; maximum = 1,
                    seed = LocalMath.IdentitySeed(false), order = LocalMath.CanonicalLeftFold()
                ) : LocalMath.Unique(Bool)
            relation = reduction ? route : LocalMath.IdentityRelation(singleton)
            evaluator = reduction ? ReductionControlProducer{false}() : ReductionControlUnique()
            producer = LocalMath.Stage(
                singleton,
                (enabled = LocalMath.Access(external, LocalMath.IdentityRelation(singleton); required = true),),
                (LocalMath.Publication((LocalMath.FieldPublication(gate, relation, LocalMath.PublicationValue(:value)),), law),),
                LocalMath.Evaluator(evaluator, gated ? (producer_enabled,) : ()),
                gated ? LocalMath.Control(; gate = producer_enabled) : LocalMath.Control(),
                LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :conditional_control_producer)
            )
            consumer = LocalMath.Stage(
                singleton,
                (input = LocalMath.Access(input, LocalMath.IdentityRelation(singleton); required = true),),
                (
                    LocalMath.Publication(
                        (LocalMath.FieldPublication(output, route, LocalMath.PublicationValue(:value)),),
                        LocalMath.Reduce(Float32, +; maximum = 1, seed = LocalMath.IdentitySeed(0.0f0), order = LocalMath.CanonicalLeftFold())
                    ),
                ),
                LocalMath.Evaluator(ReductionControlSum()), LocalMath.Control(; gate),
                LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :conditional_control_consumer)
            )
            gate_values, destination = array_type(Bool[true]), array_type(Float32[-99])
            enabled_values = array_type(Bool[false])
            bindings = (external => enabled_values, input => array_type(Float32[7]), gate => gate_values, output => destination)
            work = LocalMath.sequence(LocalMath.LocalLaw(producer), LocalMath.LocalLaw(consumer))
            backend = KernelAbstractions.get_backend(destination)
            if !gated
                prepared = LocalMath.prepare(work, bindings...; backend)
                wait(LocalMath.execute!(prepared))
                @test Array(gate_values) == Bool[false]
                @test Array(destination) == Float32[-99]
                copyto!(enabled_values, array_type(Bool[true]))
                wait(LocalMath.execute!(prepared))
                @test Array(gate_values) == Bool[true]
                @test Array(destination) == Float32[7]
                continue
            end
            failure = try
                LocalMath.prepare(work, bindings...; backend)
                nothing
            catch error
                error
            end
            @test failure isa LocalMath.LocalMathValidationError
            @test failure.contract === :control_field_totality
            @test Array(gate_values) == Bool[true]
            @test Array(destination) == Float32[-99]
        end
    end
end

function reduction_control_contracts(array_type)
    return @testset "identity-seeded reduction controls" begin
        for skip_closed in (false, true), seed in (LocalMath.IdentitySeed(false), LocalMath.ExistingSeed())
            @testset "skip closed=$skip_closed seed=$(nameof(typeof(seed)))" begin
                sites, singleton = LocalMath.Space(3), LocalMath.Space(1)
                enabled = LocalMath.Field(sites, Bool)
                input = LocalMath.Field(sites, Float32)
                gate = LocalMath.Field(singleton, Bool)
                output = LocalMath.Field(singleton, Float32)
                route = LocalMath.RuntimeRelation(sites => singleton; degree_bound = 1, key_type = Int32)
                producer = LocalMath.Stage(
                    sites,
                    (enabled = LocalMath.Access(enabled, LocalMath.IdentityRelation(sites); required = true),),
                    (
                        LocalMath.Publication(
                            (LocalMath.FieldPublication(gate, route, LocalMath.PublicationValue(:value)),),
                            LocalMath.Reduce(Bool, |; maximum = 1, seed, order = LocalMath.CanonicalLeftFold())
                        ),
                    ),
                    LocalMath.Evaluator(ReductionControlProducer{skip_closed}()), LocalMath.Control(),
                    LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :reduced_control_producer)
                )
                consumer = LocalMath.Stage(
                    sites,
                    (input = LocalMath.Access(input, LocalMath.IdentityRelation(sites); required = true),),
                    (
                        LocalMath.Publication(
                            (LocalMath.FieldPublication(output, route, LocalMath.PublicationValue(:value)),),
                            LocalMath.Reduce(Float32, +; maximum = 1, seed = LocalMath.IdentitySeed(0.0f0), order = LocalMath.CanonicalLeftFold())
                        ),
                    ),
                    LocalMath.Evaluator(ReductionControlSum()), LocalMath.Control(; gate),
                    LocalMath.SourceOrigin(@__FILE__, @__LINE__; label = :reduced_control_consumer)
                )
                enabled_values = array_type(Bool[true, false, true])
                input_values = array_type(Float32[1, 2, 3])
                gate_values = array_type(Bool[true])
                destination = array_type(Float32[-99])
                work = LocalMath.sequence(LocalMath.LocalLaw(producer), LocalMath.LocalLaw(consumer))
                bindings = (enabled => enabled_values, input => input_values, gate => gate_values, output => destination)
                backend = KernelAbstractions.get_backend(destination)
                if seed isa LocalMath.ExistingSeed
                    failure = try
                        LocalMath.prepare(work, bindings...; backend)
                        nothing
                    catch error
                        error
                    end
                    @test failure isa LocalMath.LocalMathValidationError
                    @test failure.contract === :control_field_totality
                    @test Array(gate_values) == Bool[true]
                    @test Array(destination) == Float32[-99]
                    continue
                end
                prepared = LocalMath.prepare(work, bindings...; backend)
                wait(LocalMath.execute!(prepared))
                @test Array(gate_values) == Bool[true]
                @test Array(destination) == Float32[6]
                copyto!(enabled_values, array_type(falses(3)))
                copyto!(input_values, array_type(Float32[4, 5, 6]))
                wait(LocalMath.execute!(prepared))
                @test Array(gate_values) == Bool[false]
                @test Array(destination) == Float32[6]
                copyto!(enabled_values, array_type(Bool[false, true, false]))
                wait(LocalMath.execute!(prepared))
                @test Array(gate_values) == Bool[true]
                @test Array(destination) == Float32[15]
                @test Array(input_values) == Float32[4, 5, 6]
            end
        end
    end
end
