# The discrete-time component fixtures (D-065): MTK clocked (`Shift`) systems
# lowered into one per-cell tick phase per clock. Both `SymbolicSetup` and `QaSetup` include
# this file: the QA items build `QADiscreteScratch`/`QADiscreteKinds` out of these systems
# and out of `DiscreteHybrid`, `discrete_counter_model` and `_discrete_blocks`, and an
# item's setup cannot see another setup's names (test/symbolic_tests.jl had them in Main
# with the rest).
using Potts
using Potts.ModelingToolkitBase: ShiftIndex, Clock, System, @parameters, @named

isdefined(@__MODULE__, :_tc) || const _tc = Potts.t      # Potts.t: the model time variable

# Discrete-time components (D-065): MTK clocked (`Shift`) systems lowered into one
# per-cell tick phase per clock, after the ODEs. Oracles are hand-computed sequences.
using Potts.ModelingToolkitBase: ShiftIndex, Clock

const _kd = ShiftIndex(_tc, 0)

Potts.ModelingToolkitBase.@variables fz(_tc) = 1.0 dn(_tc) = 0.0 dA(_tc)::Bool = false dB(
    _tc
)::Bool = false

@parameters dinc = 1.0 dwnt::Bool = false dsig::Bool = false du = 0.5

# a lag-2 recurrence: the older lag gets its own slot (`fib₊fzₜ₋₁`)
@named fib = System([fz(_kd) ~ fz(_kd - 1) + fz(_kd - 2)], _tc)

# a counter on a clock; `dinc` is coupled to a population fold in the model
counter(clock) = System([dn(clock) ~ dn(clock - 1) + dinc], _tc; name = :counter)

# a toggle driving a continuous component, and a Bool node sampling one
@named toggle = System([dA(_kd) ~ !dA(_kd - 1)], _tc)

@named sampler = System([dB(_kd) ~ dsig], _tc)

Potts.ModelingToolkitBase.@variables yx(_tc) = 1.0 xt(_tc) = 0.0

@parameters yr = 0.0

@named relax = System([Potts.D(yx) ~ -yr * yx, Potts.D(xt) ~ 1.0], _tc)

# asynchronous-style updating in MTK form (gap G9): a per-cell draw decides whether A
# updates
@named coin = System([dA(_kd) ~ ifelse(du < 0.5, !dA(_kd - 1), dA(_kd - 1))], _tc)

const _DISCRETE_SYS = Ref{Any}(nothing)

@potts_model DiscreteFib begin
    @kinds medium A
    @components cells(A) fib = fib
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

function discrete_counter_model(clock; mcs_duration = 1.0, scope = :cells)
    _DISCRETE_SYS[] = counter(clock)
    if scope === :cells
        @potts_model DiscreteCounter begin
            @kinds medium A
            @components cells(A) ctr = _DISCRETE_SYS[]
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
        end
        return DiscreteCounter(; name = :ctr)
    else
        @potts_model DiscreteCensus begin
            @kinds medium A
            @components model ctr = _DISCRETE_SYS[]
            @equations ctr.dinc ~ count(true for c in cells)       # a model-scope coupling
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
        end
        return DiscreteCensus(; name = :census)
    end
end

@potts_model DiscreteHybrid begin
    @kinds medium A
    @variables seen(cell) = 0.0
    @components cells(A) begin
        tg = toggle
        smp = sampler
        rel = relax
    end
    @equations begin
        # a Real parameter holds the latest tick (zero-order hold)
        rel.yr ~ 0.1 * tg.dA
        # a Bool parameter samples the ODE state at the tick
        smp.dsig ~ rel.xt > 2.5
    end
    @after_mcs seen ~ seen + tg.dA           # model statements read a node as 0/1
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model DiscreteCoin begin
    @kinds medium A
    @components cells(A) cn = coin
    @equations cn.du ~ rand()
    @lattice Lattice((40, 40))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

function _discrete_blocks(n = 4, L = 12)
    σ = zeros(Int32, L, L)
    for (c, (i, j)) in enumerate(
            Iterators.take(
                (
                    (i, j)
                        for i in 1:4:(L - 3), j in 1:4:(L - 3)
                ), n
            )
        )
        σ[(i + 1):(i + 3), (j + 1):(j + 3)] .= c
    end
    return σ
end

const _DISCRETE_ALGS = (
    SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)),
)

# Several tick phases (cell and model scope, clocks that coincide) read only pre-tick
# values: the result does not depend on declaration order.
Potts.ModelingToolkitBase.@variables dX(_tc)::Bool = false dM(_tc) = 0.0 dZ(
    _tc
)::Bool = false dY(_tc)::Bool = false

@parameters ds::Bool = false dq = 0.0 dw::Bool = false

@named xcell = System([dX(_kd) ~ ds], _tc)

@named mmodel = System([dM(_kd) ~ dq], _tc)

@named zslow = System([dZ(ShiftIndex(Clock(2.0))) ~ !dZ(ShiftIndex(Clock(2.0)) - 1)], _tc)

@named yfast = System([dY(_kd) ~ dw], _tc)
