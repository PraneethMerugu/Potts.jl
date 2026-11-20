# A site update that reads the lattice coordinate `x` should set each site to the coordinate a
# field reads there: the site center, lo + (i - 1/2) h. Today the site lowering does not bind
# the coordinates and the build refuses the read ("unknown symbol `x`"); the test records that
# as broken and fails loudly (an unexpected pass) once the lowering lands.

@testsetup module SiteCoordinatesSetup
using Potts, Test
using Potts: CorePotts

@potts_model SiteCoordinate begin
    @kinds medium A
    @variables begin
        h(site) = 0.0
    end
    @lattice Lattice((6, 4))
    @energy cells => (volume - 4.0)^2
    @after_mcs h ~ x
    @sweep Metropolis(; temperature = 1.0)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "a site update reads the field coordinate x" setup = [SiteCoordinatesSetup] tags = [:potts, :fields] begin
    @testset "a site update reads the field coordinate x" begin
        σ = zeros(Int32, 6, 4)
        σ[2:3, 2:3] .= 1
        h = try
            prob = PottsProblem(SiteCoordinate(; name = :s), [ownership => σ, kind => [:A]], (0, 1))
            solve(prob, SequentialCPM(); saveat = 1).u[end].site.h
        catch e
            e isa Potts.PottsCompileError && occursin("`x`", sprint(showerror, e)) || rethrow()
            nothing
        end
        @test_broken h !== nothing && h ≈ [i - 0.5 for i in 1:6, j in 1:4]
    end
end
