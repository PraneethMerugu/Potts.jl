# The tests run generated bodies through Exec's host executor (LatticeFields.Problems binds
# each launch description of a step plan to an Exec.Launch). The padded host loop below is
# kept only as an oracle: it pads launches as a device does (linear: up to a multiple of
# 256, guarded `s <= G.n`; Cartesian: the padded box, each axis guarded by the body), and
# every test step compares Exec's result with it bit for bit.

using LatticeFields
using LatticeFields: IR, Compile, Schedule, Problems
using KernelAbstractions: KernelAbstractions
using LatticeFields.IR: Grid, Coef, FaceRule, ImmersedRule, NodeValueRule, Space,
    ProgramBuilder,
    field!, mask!, rule!, kernel, load, store, param, coord, select, eq,
    add!, program,
    F32, F16, F64, U8, I32, U32, MASKED, RESTRICTED
using LatticeFields.Compile: CompileOptions, debug_options, semantic, compile_kernel,
    body_function, derive_function, fingerprint, LOWERING
using LatticeFields.Schedule: plan, StepPlan, LaunchSpec, CostModel

const HOST = KernelAbstractions.CPU()
using LatticeFields.Problems: FieldStore, array, current, launch_geometry,
    launch_parameters, launch_arrays

# ---- the oracle: padded host loops over the same bodies ----------------------------------
function oracle_loop!(body::F, n, S, P, G) where {F}
    for s in 1:(cld(Int(n), 256) * 256)
        s <= G.n && body(s, S, P, G)
    end
    return nothing
end
function oracle_cartesian!(body::F, padded::NTuple{N, Int}, S, P, G) where {F, N}
    for ci in CartesianIndices(padded)
        body(Tuple(ci), S, P, G)
    end
    return nothing
end
function oracle_launch!(p, l::LaunchSpec, st, Praw, rt)
    ck = l.kernel
    S, P, G = launch_arrays(st, l), launch_parameters(ck, Praw), launch_geometry(p, ck, rt)
    body = Compile.body_function(ck)
    padded = map((n, w) -> cld(n, w) * w, l.ndrange, l.workgroup)
    if ck.strategy == :cartesian
        oracle_cartesian!(body, padded, S, P, G)
    else
        oracle_loop!(body, G.n, S, P, G)
    end
    return nothing
end

"""
Host store of a program: zeroed arrays, `init(key, A)` applied to each buffer (the second
buffer of a two-buffer field copies the first), 4-element zero tables.
"""
function HostStore(p::IR.Program; init = (key, A) -> nothing)
    st = FieldStore(HOST, p)
    for (i, f) in enumerate(p.fields)
        A = st.bufs[i]
        foreach(a -> init(f.key, a), A)
        length(A) == 2 && copyto!(A[2], A[1])
    end
    foreach(
        i -> st.tables[i] = zeros(IR.juliatype(p.tables[i].storage), 4),
        eachindex(st.tables)
    )
    return st
end
function _rt2(rt)
    return if length(rt) == 2
        Float64.(Tuple(rt))
    elseif length(rt) == 1
        (Float64(rt[1]), 0.0)
    else
        (0.0, 0.0)
    end
end
function _snapshot(st)
    return FieldStore(
        st.backend, Vector{Any}[Any[copy(a) for a in b] for b in st.bufs],
        copy(st.cur), copy(st.tables)
    )
end
# -0.0 ≠ 0.0, NaN = NaN
_same(a, b) = length(a) == length(b) && all(i -> isequal(a[i], b[i]), eachindex(a))

"""
A launch bound through Exec (host executor); `run!` is the warm call.
"""
function prepare(p::IR.Program, l::LaunchSpec, st, Praw; rt = ())
    ck = l.kernel
    isempty(ck.kernel.reductions) || return WorkgroupPrep(          # contract item 5
        body_function(ck), l.ndrange[1] ÷ Schedule.WG, zeros(ck.T, Schedule.reduce_lds(ck)),
        launch_arrays(st, l), launch_parameters(ck, Praw), launch_geometry(p, ck, _rt2(rt))
    )
    return Problems.bind_program(
        HOST, p, l, launch_arrays(st, l), launch_parameters(ck, Praw), _rt2(rt)
    )
end
run!(l) = (l(); nothing)

"""
A reducing launch in the workgroup form (contract item 5) on the host: Exec does not bind
these (the solvers launch them through their own executor protocol), so the tests run them
through `Schedule.host_workgroups!`.
"""
struct WorkgroupPrep{F, L, S, P, G}
    body::F
    ngroups::Int
    lds::L
    S::S
    P::P
    G::G
end
function run!(w::WorkgroupPrep; reverse = HOST_REVERSE[])
    Schedule.host_workgroups!(
        w.body, w.ngroups, Schedule.WG, Schedule.REDUCE_PHASES, w.lds,
        w.S, w.P, w.G; reverse
    )
    return nothing
end
"""
Run workgroup items backwards in every phase (a race check: results must not change).
"""
const HOST_REVERSE = Ref(false)

"""
The oracle of a reducing launch: phase 1 of the body per block (the site work, the stores,
and each item's reduction value in `lds`), then each block's reduction computed here on
the host, independently of the emitted tree, block indexing, identity padding and table
write: the contract's halving tree (`pair`; fixed order, so sums agree bit for bit) or the
maximum, written to `target[min(block, length(target))]`. The per-site values themselves
come from the body: they are the kernel's own expressions, which the site-form oracle and
the tests' own oracles check.
"""
function oracle_reduce!(w::WorkgroupPrep, ck)
    WG = Schedule.WG
    pair(xs) = length(xs) == 1 ? xs[1] : pair(xs[1:(end ÷ 2)] .+ xs[(end ÷ 2 + 1):end])
    for g in 1:(w.ngroups)
        for t in 1:WG
            w.body(Int32(1), Int32(g), Int32(t), w.lds, w.S, w.P, w.G)
        end
        for (q, r) in enumerate(ck.kernel.reductions)
            v = w.lds[((q - 1) * WG + 1):(q * WG)]
            l, j = only(
                (l, j) for (l, as) in enumerate(ck.args)
                    for (j, a) in enumerate(as) if a == (r.target, :table)
            )
            A = w.S[l][j]
            A[min(g, length(A))] = r.op == :sum ? pair(v) : reduce(max, v)
        end
    end
    return nothing
end

"""
Run one step plan through Exec, then the host slot swaps. The same step runs on a copy of
the store through the padded oracle loops; every array must agree bit for bit. Reducing
launches run in the host workgroup form (`WorkgroupPrep`) on the store and through
`oracle_reduce!` (an independent host reduction) on the copy.
"""
function run_step!(p::IR.Program, sp::StepPlan, st, Praw; rt = ())
    ref = _snapshot(st)
    if any(l -> !isempty(l.kernel.kernel.reductions), sp.launches)
        # a step with a reducing launch: launch by launch (Exec binds the others), the
        # reducing ones in the host workgroup form, against the host-reduction oracle
        for l in sp.launches
            if isempty(l.kernel.kernel.reductions)
                oracle_launch!(p, l, ref, Praw, _rt2(rt))
            else
                oracle_reduce!(prepare(p, l, ref, Praw; rt), l.kernel)
            end
            run!(prepare(p, l, st, Praw; rt))
        end
        Problems.swap!(st, sp)
    else
        for l in sp.launches
            oracle_launch!(p, l, ref, Praw, _rt2(rt))
        end
        Problems.run_step!(HOST, p, sp, st, Praw; rt = _rt2(rt))
    end
    Problems.swap!(ref, sp)
    @test all(
        i -> all(j -> _same(st.bufs[i][j], ref.bufs[i][j]), eachindex(st.bufs[i])),
        eachindex(st.bufs)
    )
    return st
end

"""
Does an expression hold a Float64 literal or the symbol `Float64`?
"""
has_f64(x) = x isa Float64 || x === :Float64 || (x isa Expr && any(has_f64, x.args))

"""
Does type `t` hold Float64: itself, or a field of a (named) tuple or struct, recursively?
"""
function f64_type(t, seen = Set{Any}())
    t = Core.Compiler.widenconst(t)
    t === Float64 && return true
    (t isa DataType && isconcretetype(t) && !(t in seen)) || return false
    push!(seen, t)
    return any(f -> f64_type(f, seen), fieldtypes(t))
end

"""
The Float64 values in the optimized typed code of the call signature `tt` and of every
callee it invokes, recursively (non-inlined callees included): `"callee: statement"`.
"""
function f64_sites(tt; seen = Set{Any}(), out = String[])
    tt in seen && return out
    push!(seen, tt)
    for (ci, _) in Base.code_typed_by_type(tt; optimize = true)
        for (k, st) in enumerate(ci.code)
            f64_type(ci.ssavaluetypes[k]) && push!(out, string(tt.parameters[1], ": ", st))
            if st isa Expr && st.head === :invoke
                mi = st.args[1]
                mi isa Core.CodeInstance && (mi = mi.def)
                f64_sites(mi.specTypes; seen, out)
            end
        end
    end
    return out
end

"""
The call signature of a solver launch body (contract items 4 and 5).
"""
function launch_sig(l)
    args = l.wg == 0 ? (typeof(_index(1, l.G)),) : (Int32, Int32, Int32, typeof(l.lds))
    return Tuple{typeof(l.body), args..., typeof(l.S), typeof(l.P), typeof(l.G)}
end

"""
Semantic program and step plan. Every Float32 launch is checked on the way: no Float64
in the body, and a warm host launch allocates nothing (on a scratch store).
"""
function build(
        pb; options = CompileOptions(), fuse = !options.debug, stages = LOWERING,
        passes = Compile.SEMANTIC_PASSES, kw...
    )
    s = semantic(program(pb); passes)
    sp = plan(s; options, fuse, stages, kw...)
    if something(options.T, Float32) == Float32
        st = HostStore(s)
        foreach(
            i -> st.tables[Int32(i)] = zeros(IR.juliatype(s.tables[i].storage), 4),
            eachindex(s.tables)
        )
        for l in sp.launches
            @test !has_f64(l.kernel.body)
            prep = prepare(s, l, st, ntuple(_ -> 1.0, s.nparams))
            run!(prep)
            @test (@allocated run!(prep)) == 0
        end
    end
    return s, sp
end

# The executor protocol of LatticeFields.Solvers on the host (Exec implements it at the
# merge).
using LatticeFields: Solvers
struct HostExec
    # false: a host stand-in for a backend without Float64
    f64::Bool
end
HostExec() = HostExec(true)
Solvers.alloc(::HostExec, ::Type{T}, n) where {T} = zeros(T, n)
Schedule.supports(e::HostExec, ::Type{Float64}) = e.f64
Solvers.to_host(::HostExec, A) = copy(A)
function Solvers.launch!(::HostExec, l::Solvers.Launch)
    if l.wg == 0
        _hostrun(l.body, l.n, l.S, l.P, l.G)
    else
        Schedule.host_workgroups!(
            l.body, l.n, l.wg, l.phases, l.lds, l.S, l.P, l.G;
            reverse = HOST_REVERSE[]
        )
    end
    return nothing
end
_index(i, G) = hasfield(typeof(G), :n) ? oftype(G.n, i) : i
function _hostrun(body::F, n, S, P, G) where {F}
    for i in 1:n
        body(_index(i, G), S, P, G)
    end
    return nothing
end
