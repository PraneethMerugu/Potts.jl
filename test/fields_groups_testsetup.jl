@testsetup module FieldsGroupsSetup
using Potts, Test
using Potts: CorePotts

module FgPDE
    using Potts
    include(joinpath(@__DIR__, "shared", "field_pde.jl"))
    using .FieldPDE
    @variables c(..) u(..) o(..) v(..) w(..) s1(..) s2(..) dk(..) [input = true]
    const X = (t, x, y)
    const C, U, O, V, W, S1, S2, DK = c(X...), u(X...), o(X...), v(X...), w(X...), s1(X...), s2(X...), dk(X...)
    const MCS = step_index(t)
    ic(f, v = 0.0) = f(0, x, y) ~ v
    field1(rate, dims, ps = []; bcs = [], c0 = 0.0, dvs = [C]) = pdesys([Dt(C) ~ rate], [ic(c, c0); bcs], dims, dvs, ps)
    function ode(rates, fs, u0, ps = []; dims = (6, 6))
        return pdesys([Dt(f(X...)) ~ r for (f, r) in zip(fs, rates)], [ic(f, v) for (f, v) in zip(fs, u0)], dims, [f(X...) for f in fs], ps)
    end
    rot() = (@parameters k = 0.5; ode([-k * O, k * C], (c, o), [1.0, 0.0], [k]))
    one_way() = (@parameters k = 3.0; ode([-0.1 * C, k * C - U], (c, u), [1.0, 0.0], [k]))
    loop3() = (@parameters k = 3.0; ode([-k * O, -k * V, k * C], (c, o, v), [1.0, 0.0, 0.0], [k]))
    loop_chain() = (@parameters k = 30.0 r = 0.5; ode([-r * O, r * C, k * C - U], (c, o, u), [1.0, 0.0, 0.0], [k, r]))
    function unseen_chain()
        @parameters k = 3.0
        @variables z(..)
        Z = z(X...)
        return ode([-0.1 * C - 1.0e-9 * C * Z^2, k * C - U, -0.5 * Z], (c, u, z), [1.0, 0.0, 1.0], [k])
    end
    self_src() = (@parameters k = 3.0; ode([-0.1 * S1^2, k * S1 - U], (s1, u), [1.0, 0.0], [k]))
    chain_loop() = (@parameters k = 3.0 w = 0.05; ode([-0.1 * S1, k * S1 - w * C, w * S2], (s1, s2, c), [1.0, 0.0, 0.5], [k, w]))
    function rot_cells()
        @parameters k = 0.5 Dc = 0.1
        return pdesys([Dt(C) ~ Dc * laplacian(C) - k * O - DK * O, Dt(O) ~ k * C], [ic(c, 1.0), ic(o)], (6, 6), [C, O, DK], [k, Dc])
    end
    mcs_source() = (@parameters η = 0.5; field1(-C + η * MCS, (6, 6), [η]; c0 = 1.0))
    mcs_diff() = (@parameters ε = 0.5; field1((1 + ε * MCS) * laplacian(C), (6, 6), [ε]))
    clock_repeat() = ode([MCS, t], (c, u), [0.0, 0.0]; dims = (4, 4))
    time_read() = field1(-C + sin(t), (4, 4); c0 = 0.3)
    clock_half() = (@parameters η = 0.5; ode([MCS, t, -W + η * MCS], (c, u, w), [0.0, 0.0, 1.0], [η]; dims = (4, 4)))
end

@potts_model _FgFrozen6x6 begin
    @structural_parameters begin
        sys_fn = FgPDE.rot
        md = nothing
    end
    @kinds medium A[frozen]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields sys_fn()
    if md === nothing
        @sweep Metropolis(; temperature = 1.0)
    else
        @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
    end
end

FdRot(; name = :FdRot, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.rot, name, kw...)
FdOneWay(; name = :FdOneWay, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.one_way, name, kw...)
FdLoop3(; name = :FdLoop3, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.loop3, name, kw...)
FdLoopChain(; name = :FdLoopChain, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.loop_chain, name, kw...)
FdUnseenChain(; name = :FdUnseenChain, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.unseen_chain, name, kw...)
FdSelfSrc(; name = :FdSelfSrc, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.self_src, name, kw...)
FdChainLoop(; name = :FdChainLoop, kw...) = _FgFrozen6x6(; sys_fn = FgPDE.chain_loop, name, kw...)
fd_rot_md(md) = _FgFrozen6x6(; sys_fn = FgPDE.rot, md, name = :rmd)

@potts_model FdRotCells begin
    @kinds medium A
    @parameters κ[kind] = [0.0, 0.0]
    @lattice Lattice((6, 6); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields FgPDE.rot_cells() (FgPDE.dk => κ[kind])
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model _FgMcs6x6 begin
    @structural_parameters begin
        periodic = false
        sys_fn = FgPDE.mcs_source
    end
    @kinds medium A
    @lattice Lattice((6, 6); boundary = periodic ? Periodic() : Closed())
    @energy cells(A) => (volume - 4.0)^2
    @fields sys_fn()
    @sweep Metropolis(; temperature = 1.0)
end

FdMcsSource(; name = :FdMcsSource, kw...) = _FgMcs6x6(; periodic = false, sys_fn = FgPDE.mcs_source, name, kw...)
FdMcsDiff(; name = :FdMcsDiff, kw...) = _FgMcs6x6(; periodic = true, sys_fn = FgPDE.mcs_diff, name, kw...)

@potts_model _Fg4x4 begin
    @structural_parameters variant = :clock_repeat
    @kinds medium A
    @lattice Lattice((4, 4); boundary = Closed())
    @energy cells(A) => (volume - 4.0)^2
    if variant === :clock_repeat
        @fields FgPDE.clock_repeat()
        @sweep Metropolis(; temperature = 1.0)
        @schedule repeat(4, sweep(fraction = 1 // 4), fields)
    elseif variant === :time_read
        @fields FgPDE.time_read()
        @sweep Metropolis(; temperature = 1.0)
    elseif variant === :clock_half
        @fields FgPDE.clock_half()
        @sweep Metropolis(; temperature = 1.0, mcs_duration = 0.5)
        @schedule repeat(4, sweep(fraction = 1 // 4), fields)
    else
        throw(ArgumentError("unknown _Fg4x4 variant: $variant"))
    end
end

FdClockRepeat(; name = :FdClockRepeat, kw...) = _Fg4x4(; variant = :clock_repeat, name, kw...)
FdTimeRead(; name = :FdTimeRead, kw...) = _Fg4x4(; variant = :time_read, name, kw...)
FdClockHalf(; name = :FdClockHalf, kw...) = _Fg4x4(; variant = :clock_half, name, kw...)

struct AStub <: Potts.LatticeFields.Problems.AbstractFieldAlgorithm
    code::UInt32
    at::Int
    need::Int
    budget::Int
end
AStub(; code = 0, at = 0, need = 0, budget = 8) = AStub(UInt32(code), at, need, budget)

mutable struct AStubCache
    word::Vector{UInt32}
    steps::Int
    a::AStub
end

Potts.LatticeFields.Problems.nbuffers(::AStub) = 2
Potts.LatticeFields.Problems.update_key(::AStub) = :euler
Potts.LatticeFields.Problems.update_rule(::AStub) = Potts.LatticeFields.Problems.update_rule(ExplicitEuler())
Potts.LatticeFields.Problems.alg_cache(a::AStub, group, store) = AStubCache(zeros(UInt32, 8), 0, a)
Potts.LatticeFields.Problems.status_word(c::AStubCache) = c.word
Potts.LatticeFields.Problems.substeps(::Potts.LatticeFields.Problems.GroupSpec, ::AStub, dt, pp; kw...) = 1
function Potts.LatticeFields.Problems.step_retcode!(c::AStubCache, rt)
    LFP = Potts.LatticeFields.Problems
    c.steps += 1
    c.word[LFP.STATUS_SOLVES] += 1
    c.a.need > c.a.budget && (c.word[LFP.STATUS_BUDGET] += 1)
    if c.a.code > 0 && c.steps == c.a.at
        c.word[LFP.STATUS_CODE] = c.a.code
        c.a.code >= 2 && (c.word[LFP.STATUS_WINDOW] = rt.totals.windows; c.word[LFP.STATUS_CAUSE] = 0x02)
    end
    return Potts.SciMLBase.ReturnCode.Success
end

include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end
