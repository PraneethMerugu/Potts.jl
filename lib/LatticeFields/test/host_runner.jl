# The tests run generated bodies through Exec's host executor (LatticeFields.Problems binds
# each launch description of a step plan to an Exec.Launch). The padded host loop below is
# kept only as an oracle: it pads launches as a device does (linear: up to a multiple of 256,
# guarded `s <= G.n`; Cartesian: the padded box, each axis guarded by the body), and every
# test step compares Exec's result with it bit for bit.

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
    ck.strategy == :cartesian ? oracle_cartesian!(body, padded, S, P, G) :
    oracle_loop!(body, G.n, S, P, G)
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
    foreach(i -> st.tables[i] = zeros(IR.juliatype(p.tables[i].storage), 4), eachindex(st.tables))
    return st
end
function _rt2(rt)
    length(rt) == 2 ? Float64.(Tuple(rt)) :
    length(rt) == 1 ? (Float64(rt[1]), 0.0) : (0.0, 0.0)
end
function _snapshot(st)
    FieldStore(st.backend, Vector{Any}[Any[copy(a) for a in b] for b in st.bufs], copy(st.cur), copy(st.tables))
end
_same(a, b) = length(a) == length(b) && all(i -> isequal(a[i], b[i]), eachindex(a))   # -0.0 ≠ 0.0, NaN = NaN

"""
A launch bound through Exec (host executor); `run!` is the warm call.
"""
function prepare(p::IR.Program, l::LaunchSpec, st, Praw; rt = ())
    Problems.bind(
        HOST, p, l, launch_arrays(st, l), launch_parameters(l.kernel, Praw), _rt2(rt))
end
run!(l) = (l(); nothing)

"""
Run one step plan through Exec, then the host slot swaps. The same step runs on a copy of
the store through the padded oracle loops; every array must agree bit for bit.
"""
function run_step!(p::IR.Program, sp::StepPlan, st, Praw; rt = ())
    ref = _snapshot(st)
    for l in sp.launches
        oracle_launch!(p, l, ref, Praw, _rt2(rt))
    end
    Problems.run_step!(HOST, p, sp, st, Praw; rt = _rt2(rt))
    Problems.swap!(ref, sp)
    @test all(i -> all(j -> _same(st.bufs[i][j], ref.bufs[i][j]), eachindex(st.bufs[i])),
        eachindex(st.bufs))
    return st
end

"""
Does an expression hold a Float64 literal or the symbol `Float64`?
"""
has_f64(x) = x isa Float64 || x === :Float64 || (x isa Expr && any(has_f64, x.args))

"""
Semantic program and step plan. Every Float32 launch is checked on the way: no Float64
in the body, and a warm host launch allocates nothing (on a scratch store).
"""
function build(pb; options = CompileOptions(), fuse = !options.debug, stages = LOWERING,
        passes = Compile.SEMANTIC_PASSES, kw...)
    s = semantic(program(pb); passes)
    sp = plan(s; options, fuse, stages, kw...)
    if something(options.T, Float32) == Float32
        st = HostStore(s)
        foreach(i -> st.tables[Int32(i)] = zeros(IR.juliatype(s.tables[i].storage), 4),
            eachindex(s.tables))
        for l in sp.launches
            @test !has_f64(l.kernel.body)
            prep = prepare(s, l, st, ntuple(_ -> 1.0, s.nparams))
            run!(prep)
            @test (@allocated run!(prep)) == 0
        end
    end
    return s, sp
end
