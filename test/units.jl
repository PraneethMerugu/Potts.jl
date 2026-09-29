# Units (M3.1): dimensional analysis when parameters/variables carry `[unit = …]`
# (PottsDynamicQuantitiesExt).
using DynamicQuantities: @u_str

@potts_model UnitSorting begin
    @kinds medium A
    @parameters begin
        λ = 1.0, [unit = u"J"]
        V₀ = 25.0
        J[kind, kind] = [0 2; 2 1], [unit = u"J"]
        T = 4.0, [unit = u"J"]
        k = 0.1, [unit = u"mol/s"]
    end
    @variables begin
        c(field) = 0.0, [unit = u"mol"]
        m(cell) = 0.0, [unit = u"mol"]
    end
    @lattice Lattice((16, 16))
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @after_mcs m ~ Pre(m) + integral(c)
    @observed total ~ sum(m for n in cells)
    @sweep Metropolis(; temperature = T)
end

function unit_model(body)
    m = eval(:(@potts_model _UnitBad begin
        @kinds medium A
        @parameters begin
            λ = 1.0, [unit = u"J"]
            μ = 1.0, [unit = u"m"]
            T = 4.0, [unit = u"J"]
        end
        @variables begin
            c(field) = 0.0, [unit = u"mol"]
            m(cell) = 0.0, [unit = u"mol"]
        end
        @lattice Lattice((8, 8))
        @energy cells => λ * (volume - 16)^2
        $(body)
        @sweep Metropolis(; temperature = T)
    end))
    return Base.invokelatest(m; name = :u)
end

@testset "units: dimensional analysis" begin
    c = mtkcompile(UnitSorting(; name = :s))                              # consistent: compiles
    σ = zeros(Int32, 16, 16); σ[5:9, 5:9] .= 1
    @test Symbol(solve(PottsProblem(c, [ownership => σ, kind => [1]], (0, 2)), SequentialCPM()).retcode) == :Success
    @test_throws ArgumentError mtkcompile(unit_model(:(@drive copy => μ * (new == 1))))          # H in J, drive in m
    @test_throws ArgumentError mtkcompile(unit_model(:(@after_mcs m ~ Pre(m) + μ)))             # mol ≠ mol + m
    @test_throws ArgumentError mtkcompile(unit_model(:(@after_mcs m ~ integral(c) * μ)))        # mol·m ≠ mol
    @test_throws ArgumentError mtkcompile(unit_model(:(@divide cells(A) when = m > 1)))         # mol vs unitless
    @test_throws ArgumentError mtkcompile(unit_model(:(@observed q ~ sum(m + μ for n in cells))))
    @test mtkcompile(unit_model(:(@divide cells(A) when = m > integral(c)))) isa CompiledPottsSystem  # mol vs mol
    # literal zeros take any unit (published-model patterns); real clashes in max/min still fail
    @test mtkcompile(unit_model(:(@drive copy => ifelse(old == 0, λ * (c[target] - c[source]) / c[source], 0.0)))) isa CompiledPottsSystem
    @test mtkcompile(unit_model(:(@after_mcs m ~ max(Pre(m) - integral(c), 0)))) isa CompiledPottsSystem
    @test_throws ArgumentError mtkcompile(unit_model(:(@after_mcs m ~ max(Pre(m), μ))))
    @test_throws ArgumentError mtkcompile(unit_model(:(@drive copy => ifelse(μ, λ, 0.0))))       # condition in m
end
