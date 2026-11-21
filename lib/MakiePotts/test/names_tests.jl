# The public names of MakiePotts: exported and public names are ASCII, the old names of the
# conformance renames stay removed, and no export clashes with Makie or a package a user
# loads beside ours. The checks are the shared ones of the Potts tests
# (test/shared/names_checks.jl).

@testsetup module MP_names
using MakiePotts
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "names_checks.jl"))
end

@testitem "MakiePotts: public names" setup = [MP_names] tags = [:makiepotts, :core] begin
    using .MP_names: MakiePotts, CLASH_PACKAGES, manifest_package, export_clashes,
        non_ascii_names
    @testset "MakiePotts: public names" begin
        @test non_ascii_names(MakiePotts) == Symbol[]
        for n in (:channel, :encode)
            @test !isdefined(MakiePotts, n) ||
                (println("MakiePotts.", n, " is still defined"); false)
        end
        @test Base.isexported(MakiePotts, :frame_channel) &&
            Base.isexported(MakiePotts, :encode_frame)
        @test Base.ispublic(MakiePotts, :LegendEntry) &&
            !Base.isexported(MakiePotts, :LegendEntry)
        others = [manifest_package(p) for p in [CLASH_PACKAGES; "Makie"; "CairoMakie"]]
        @test export_clashes(MakiePotts, others) == Pair{Symbol, Symbol}[]
    end
end
