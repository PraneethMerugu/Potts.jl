# Units (M3.1): dimensional analysis when parameters/variables carry `[unit = …]`
# (PottsDynamicQuantitiesExt).

@testsetup module UnitsSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
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
        contacts => J[kind, neighbor_kind]
    end
    @after_mcs m ~ Pre(m) + integral(c)
    @observed total ~ sum(m for n in cells)
    @sweep Metropolis(; temperature = T)
end


@potts_model UnitCase begin
    @structural_parameters kind_case = :divide_good_integral
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
    if kind_case === :drive_bad_unit
        @drive copy => μ * (new == 1)
    elseif kind_case === :after_bad_add
        @after_mcs m ~ Pre(m) + μ
    elseif kind_case === :after_bad_mul
        @after_mcs m ~ integral(c) * μ
    elseif kind_case === :divide_bad_unit
        @divide cells(A) when = m > 1
    elseif kind_case === :obs_bad_unit
        @observed q ~ sum(m + μ for n in cells)
    elseif kind_case === :divide_good_integral
        @divide cells(A) when = m > integral(c)
    elseif kind_case === :drive_good_zero
        @drive copy => ifelse(old == 0, λ * (c[target] - c[source]) / c[source], 0.0)
    elseif kind_case === :after_good_max
        @after_mcs m ~ max(Pre(m) - integral(c), 0)
    elseif kind_case === :after_bad_max
        @after_mcs m ~ max(Pre(m), μ)
    elseif kind_case === :drive_bad_cond
        @drive copy => ifelse(μ, λ, 0.0)
    elseif kind_case === :divide_good_zero
        @divide cells(A) when = m >= 0, m => 0.0
    elseif kind_case === :after_good_zero
        @after_mcs m ~ 0
    elseif kind_case === :eq_bad_unit
        @equations D(m) ~ μ
    elseif kind_case === :eq_good_rate
        @equations D(m) ~ -m
    elseif kind_case === :divide_good_logic
        @divide cells(A) when = (m > integral(c)) & !(volume < 4)
    end
    @sweep Metropolis(; temperature = T)
end

unit_compile(kind_case) = mtkcompile(UnitCase(; name = :u, kind_case))

# a difference with the value before the block, `m - Pre(m)`: the unit check keeps `Pre(m)`
# apart from `m` (the two must not cancel to a dimensionless zero)
@potts_model UnitPreDiff begin
    @kinds medium A
    @parameters begin
        λ = 1.0, [unit = u"J"]
        T = 4.0, [unit = u"J"]
        k = 1.0, [unit = u"mol"]
    end
    @variables begin
        m(cell) = 0.0, [unit = u"mol"]
        dm(cell) = 0.0, [unit = u"mol"]
    end
    @lattice Lattice((8, 8))
    @energy cells => λ * (volume - 16)^2
    @after_mcs begin
        m ~ Pre(m) + k
        dm ~ m - Pre(m)
    end
    @sweep Metropolis(; temperature = T)
end


@potts_model UnitRate begin
    @kinds medium A
    @parameters begin
        k = 0.1, [unit = u"1/s"]
        T = 4.0
    end
    @variables m(cell) = 1.0, [unit = u"mol"]
    @lattice Lattice((8, 8))
    @energy cells => (volume - 16)^2
    @equations D(m) ~ -k * m
    @sweep Metropolis(; temperature = T)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "units: dimensional analysis" setup = [UnitsSetup] tags = [:potts, :units] begin
    @testset "units: dimensional analysis" begin
        c = mtkcompile(UnitSorting(; name = :s))                              # consistent: compiles
        σ = zeros(Int32, 16, 16); σ[5:9, 5:9] .= 1
        @test Symbol(solve(PottsProblem(c, [ownership => σ, kind => [1]], (0, 2)), SequentialCPM()).retcode) == :Success
        @test_throws ArgumentError unit_compile(:drive_bad_unit)              # H in J, drive in m
        @test_throws ["units:", "disagree"] unit_compile(:drive_bad_unit)
        @test_throws ArgumentError unit_compile(:after_bad_add)               # mol ≠ mol + m
        @test_throws ["units:", "do not match"] unit_compile(:after_bad_add)
        @test_throws ArgumentError unit_compile(:after_bad_mul)               # mol·m ≠ mol
        @test_throws ["units:", "right side", "expected"] unit_compile(:after_bad_mul)
        @test_throws ArgumentError unit_compile(:divide_bad_unit)             # mol vs unitless
        @test_throws ["units:"] unit_compile(:divide_bad_unit)
        @test_throws ArgumentError unit_compile(:obs_bad_unit)
        @test_throws ["units:", "do not match"] unit_compile(:obs_bad_unit)
        @test unit_compile(:divide_good_integral) isa CompiledPottsSystem     # mol vs mol
        # literal zeros take any unit (published-model patterns); real clashes in max/min still fail
        @test unit_compile(:drive_good_zero) isa CompiledPottsSystem
        @test unit_compile(:after_good_max) isa CompiledPottsSystem
        @test_throws ArgumentError unit_compile(:after_bad_max)
        @test_throws ["units:"] unit_compile(:after_bad_max)
        @test_throws ArgumentError unit_compile(:drive_bad_cond)              # condition in m
        @test_throws ["Condition of", "Bool"] unit_compile(:drive_bad_cond)
        # A-56: zero in comparisons and rules; equations need x's units per unit of time
        @test unit_compile(:divide_good_zero) isa CompiledPottsSystem
        @test unit_compile(:after_good_zero) isa CompiledPottsSystem
        @test_throws ArgumentError unit_compile(:eq_bad_unit)                 # m per time ≠ m
        @test_throws ["units:", "rate", "per unit of time"] unit_compile(:eq_bad_unit)
        @test unit_compile(:eq_good_rate) isa CompiledPottsSystem             # per MCS
        @test unit_compile(:divide_good_logic) isa CompiledPottsSystem        # `&`, `!` of conditions
        @test mtkcompile(UnitPreDiff(; name = :pd)) isa CompiledPottsSystem   # `m - Pre(m)` in mol
    end
end

# Potts' unit rules for `Pre` and the logic operations live in Potts' own unit check
# (the model cases above); MTK's `get_unit` answers those operations with its own methods for
# every other expression, so loading Potts changes no MTK model's unit check
@testitem "units: MTK's get_unit is not extended for MTK's operations" setup = [UnitsSetup] tags = [:potts, :units] begin
    @testset "units: MTK's get_unit is not extended for MTK's operations" begin
        MTK = Potts.ModelingToolkitBase
        ext = Base.get_extension(Potts, :PottsDynamicQuantitiesExt)
        @test ext !== nothing
        for op in (MTK.Pre, typeof(&), typeof(|), typeof(!), typeof(xor))
            @test parentmodule(which(MTK.get_unit, Tuple{op, Vector{Any}})) !== ext
        end
    end
end

@testitem "units: rates per unit of time (A-56)" setup = [UnitsSetup] tags = [:potts, :units] begin
    @testset "units: rates per unit of time (A-56)" begin
        @test mtkcompile(UnitRate(; name = :r)) isa CompiledPottsSystem
    end
end
