@testset "Potts uses only the frozen Core boundary and explicit SPIs" begin
    @test !isdefined(Potts, :stage_external_inputs!)
    @test !isdefined(Potts, :_stage_external_inputs!)

    frozen_top_level = Set((
        :CompilerSPI,
        :BackendSPI,
        :ProgramInitialState,
        :ProgramSnapshot,
        :ProgramRuntime,
        :ProgramFailureReport,
        :program_failed,
        :program_failure_report,
        :ProgramSettlementReceipt,
        :initialize_program,
        :program_snapshot,
        :advance_mcs!,
        :update_program_parameters!,
        :program_execution_report,
        :program_capability_report,
        :ProgramCheckpoint,
        :program_checkpoint,
        :restore_program_checkpoint,
        :CellIdentity,
        :QualifiedLifecycleRequestIdentity,
        :AbstractLifecycleEvent,
        :LifecycleEvent,
        :LifecycleReceipt,
        :MaybeLifecycleReceipt,
        :CreateLifecycleEvent,
        :RemoveCellLifecycleEvent,
        :RetireLifecycleEvent,
        :TransitionLifecycleEvent,
        :DivideLifecycleEvent,
        :ParentBeforeIdentity,
        :ParentAfterIdentity,
        :DaughterAfterIdentity,
        :lifecycle_request_identity,
        :lifecycle_events,
        :validate_lifecycle_receipt,
        :program_lifecycle_receipt,
    ))
    roots = (
        joinpath(@__DIR__, "..", "src"),
        joinpath(@__DIR__, "..", "ext"),
        @__DIR__,
    )
    direct_references = Tuple{String, Symbol}[]
    spi_references = Tuple{String, Symbol, Symbol}[]

    for root in roots
        isdir(root) || continue
        for (directory, _, names) in walkdir(root)
            for name in names
                endswith(name, ".jl") || continue
                file = joinpath(directory, name)
                source = read(file, String)
                for found in eachmatch(
                        r"CorePotts\.([A-Za-z_][A-Za-z0-9_!]*)(?:\.([A-Za-z_][A-Za-z0-9_!]*))?",
                        source,
                    )
                    owner = Symbol(found.captures[1])
                    member = found.captures[2]
                    if owner === :CompilerSPI || owner === :BackendSPI
                        member === nothing || push!(
                            spi_references,
                            (file, owner, Symbol(member)),
                        )
                    else
                        push!(direct_references, (file, owner))
                    end
                end
            end
        end
    end

    for (file, name) in direct_references
        @test name in frozen_top_level || begin
            @info "private CorePotts package-level reach" file name
            false
        end
    end
    for (file, owner, member) in spi_references
        spi = getproperty(CorePotts, owner)
        @test Base.ispublic(spi, member) || begin
            @info "non-public CorePotts SPI reach" file owner member
            false
        end
    end
    @test !isempty(spi_references)
end
