# The lowering driver (passes 3–6) and the compiled-kernel description handed to Exec.

"""
A lowered kernel: the body expression plus everything Exec needs to launch it.
`args[l]` lists `(field or table id, role)` for lane `lanes[l]`, in the order of `S[l]`;
`levels` gives the order of `G.dims`. `T` is the value type the body is emitted for
(Float32, Float64, BigFloat); Dual arrays and parameters of that value type run the same
body. `derive(Praw, c, t, k)` maps the raw parameters (any `Real` eltype, kept as given) to
`P` in the type of `c` (the compute element type): the raw values, then the hoisted ones,
derived in at least Float64 and rounded once; with the options' clock slot, the step index
`k` is written into that slot first (`k = nothing` keeps it). `timed`: some hoisted value
reads the time `t`, or the kernel reads the clock slot (itself or through a hoisted value), so
`P` is derived again at each launch.
"""
struct CompiledKernel{N}
    key::String
    body::Expr
    strategy::Symbol
    space::Space{N}
    levels::Vector{Int8}
    lanes::Vector{Scalar}
    args::Vector{Vector{Tuple{Int32, Symbol}}}
    nparams::Int
    derived::Vector{Any}
    derive::Expr
    timed::Bool
    T::Type
    I::Type
    hash::String
    kernel::Kernel{N}
end

"""
The lowering stages; tests replace one to inject a fault.
"""
const LOWERING = (; powi = expand_powi, hoist = hoist_params, index = lower_index,
    target = linear_index, order = loads_first, passthrough = passthrough)

"""
Lower semantic kernel `k` of program `p` (passes 3–6).
"""
function compile_kernel(p::Program{N}, k::Kernel{N}, o::CompileOptions = CompileOptions();
        stages = LOWERING) where {N}
    o.T === nothing && (o = CompileOptions(Float32, o.I, o.float64_ok, o.debug, o.index, o.lanes, o.clock, o.S, o.declared))
    check_types(p, k, o)
    !isempty(k.reductions) && o.index == :cartesian &&
        irerror("kernel `", k.key, "`: reductions need the linear index strategy")
    big = maximum(nsites(p, l) * ncomp(f) for f in p.fields for l in f.levels)
    big > typemax(Int32) && o.I == Int32 &&
        (o = CompileOptions(o.T, Int64, o.float64_ok, o.debug, o.index, o.lanes, o.clock, o.S, o.declared))
    if !o.debug
        k = stages.powi(p, k)
        k, derived = stages.hoist(p, k)
    else
        derived = Any[]
    end
    verify(with_kernels(p, [k]))
    body, L = emit(p, k, o; stages)
    T = o.T
    vals = Any[[:(lanecast(typeof(c), P[$i])) for i in 1:(p.nparams)];
               [:(lanecast(typeof(c), $d)) for d in derived]]
    # the clock's step index `k` (an integer, exact in Float64 up to 2^53) into its slot of the
    # raw parameters, before anything is derived from them; `k = nothing` keeps the slot
    clock = 0 < o.clock <= p.nparams ? o.clock : 0
    tick = if clock == 0
        nothing
    else
        :(P = k === nothing ? P : $(Expr(:tuple, [i == clock ? :(oftype(P[$i], k)) : :(P[$i]) for i in 1:(p.nparams)]...)))
    end
    derive = :((P, c, t, k) -> begin
        $tick
        Q = map(_wide, P)
        t = _wide(t)
        $(Expr(:tuple, vals...))
    end)
    # derived again at each launch: a hoisted value that reads the time, and every kernel that
    # reads the clock slot (directly, or through a hoisted value)
    timed = any(d -> _reads(d, :t), derived) ||
            (clock != 0 && (_reads_slot(k, clock) || any(d -> _reads_q(d, clock), derived)))
    h = bytes2hex(sha1(string(body)))
    # a declared Float64 on a device: the body's signature part into the D-157 registry
    o.declared && _touches_float64(p, k, o) && Exec.register_float64!(string(typeof(rgf(body))))
    return CompiledKernel{N}(k.key, body, L.strategy, k.space, L.levels, L.lanes, L.args,
        p.nparams, derived, derive, timed, T, o.I, h, k)
end

# whether kernel `k` computes in Float64 or loads or stores a lane that holds Float64
function _touches_float64(p::Program, k::Kernel, o::CompileOptions)
    return value_type(o.T) <: Float64 ||
        any(a -> isfloat(p.fields[a.field].storage) && value_type(_lane_holds(p.fields[a.field], o)) <: Float64, k.accesses) ||
        any(s -> isfloat(p.fields[s.access.field].storage) && value_type(_lane_holds(p.fields[s.access.field], o)) <: Float64, k.stores)
end
_reads(ex, s::Symbol) = ex === s || (ex isa Expr && any(a -> _reads(a, s), ex.args))
# whether kernel `k` reads parameter slot `i` itself, and whether a hoisted value's host
# expression reads it (`Q[i]`, `hostexpr`)
_reads_slot(k::Kernel, i::Integer) = any(n -> n.op == PARAM && n.imm == i, k.nodes)
_reads_q(ex, i::Integer) = ex isa Expr && ((ex.head === :ref && ex.args[1] === :Q && ex.args[2] == i) || any(a -> _reads_q(a, i), ex.args))

"""
Compile `ex` to a RuntimeGeneratedFunction without its expression (CLAUDE.md rule).
"""
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))
body_function(ck::CompiledKernel) = rgf(ck.body)
derive_function(ck::CompiledKernel) = rgf(ck.derive)
