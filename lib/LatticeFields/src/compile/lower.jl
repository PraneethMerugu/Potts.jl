# The lowering driver (passes 3–6) and the compiled-kernel description handed to Exec.

"""
A lowered kernel: the body expression plus everything Exec needs to launch it.
`args[l]` lists `(field or table id, role)` for lane `lanes[l]`, in the order of `S[l]`;
`levels` gives the order of `G.dims`. `T` is the value type the body is emitted for
(Float32, Float64, BigFloat); Dual arrays and parameters of that value type run the same
body. `derive(Praw, c, t)` maps the raw parameters (any `Real` eltype, kept as given) to `P`
in the type of `c` (the compute element type): the raw values, then the hoisted ones,
derived in at least Float64 and rounded once. `timed`: some hoisted value reads the time
`t`, so `P` is derived again at each launch.
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
    o.T === nothing && (o = CompileOptions(Float32, o.I, o.float64_ok, o.debug, o.index, o.lanes))
    check_types(p, k, o)
    (any(s -> s.law != :owned, k.stores) || !isempty(k.reductions)) && irerror("kernel `",
        k.key, "`: `:accumulate` stores and reductions are not lowered yet (C7b)")
    big = maximum(nsites(p, l) * ncomp(f) for f in p.fields for l in f.levels)
    big > typemax(Int32) && o.I == Int32 &&
        (o = CompileOptions(o.T, Int64, o.float64_ok, o.debug, o.index, o.lanes))
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
    derive = :((P, c, t) -> begin
        Q = map(_wide, P)
        t = _wide(t)
        $(Expr(:tuple, vals...))
    end)
    timed = any(d -> _reads(d, :t), derived)
    h = bytes2hex(sha1(string(body)))
    return CompiledKernel{N}(k.key, body, L.strategy, k.space, L.levels, L.lanes, L.args,
        p.nparams, derived, derive, timed, T, o.I, h, k)
end

_reads(ex, s::Symbol) = ex === s || (ex isa Expr && any(a -> _reads(a, s), ex.args))

"""
Compile `ex` to a RuntimeGeneratedFunction without its expression (CLAUDE.md rule).
"""
rgf(ex::Expr) = drop_expr(RuntimeGeneratedFunction(@__MODULE__, @__MODULE__, ex))
body_function(ck::CompiledKernel) = rgf(ck.body)
derive_function(ck::CompiledKernel) = rgf(ck.derive)
