# A CPU host-loop runner implementing the Exec contract (src/schedule/contract.jl), so the
# tests execute generated bodies without a GPU. Exec (C2) replaces it at the merge.

using LatticeFields
using LatticeFields: IR, Compile, Schedule
using LatticeFields.IR: Grid, Coef, FaceRule, ImmersedRule, NodeValueRule, Space,
                        ProgramBuilder,
                        field!, mask!, rule!, kernel, load, store, param, coord, select, eq,
                        add!, program,
                        F32, F16, F64, U8, I32, U32, MASKED, RESTRICTED
using LatticeFields.Compile: CompileOptions, debug_options, semantic, compile_kernel,
                             body_function, derive_function, fingerprint, LOWERING
using LatticeFields.Schedule: plan, StepPlan, LaunchSpec, CostModel

"""
The geometry object of the contract (item 4).
"""
struct HostGeom{N, L, R, I, T}
    n::I
    dims::NTuple{L, NTuple{N, Int32}}
    rt::NTuple{R, T}
end

# Padded launches, as on a device: the linear wrapper guards `s <= G.n`; Cartesian bodies
# guard each axis themselves (contract item 1).
function host_loop!(body::F, n::I, S, P, G) where {F, I}
    for s in one(I):(cld(n, I(256)) * I(256))
        s <= G.n && body(s, S, P, G)
    end
    return nothing
end
function host_cartesian!(body::F, padded::NTuple{N, Int}, S, P,
        G::HostGeom{N, L, R, I}) where {F, N, L, R, I}
    for ci in CartesianIndices(padded)
        body(map(c -> c % I, Tuple(ci)), S, P, G)
    end
    return nothing
end

"""
Arrays of a program: one or two buffers per field, plus the current-slot index.
"""
mutable struct HostStore
    bufs::Dict{Int32, Vector{Any}}
    cur::Dict{Int32, Int}
    tables::Dict{Int32, Any}
end
function HostStore(p::IR.Program{N}; init = (key, A) -> nothing) where {N}
    bufs, cur = Dict{Int32, Vector{Any}}(), Dict{Int32, Int}()
    for (i, f) in enumerate(p.fields)
        dims = Int.(IR.leveldims(p, f.levels[1]))
        A = [zeros(IR.juliatype(f.storage), prod(dims) * IR.ncomp(f))
             for _ in 1:(f.buffers)]
        foreach(a -> init(f.key, a), A)
        length(A) == 2 && copyto!(A[2], A[1])
        bufs[Int32(i)], cur[Int32(i)] = A, 1
    end
    return HostStore(bufs, cur, Dict{Int32, Any}())
end
function array(st::HostStore, id, role)
    role == :table && return st.tables[id]
    b = st.bufs[id]
    return length(b) == 1 ? b[1] : b[role == :cur ? st.cur[id] : 3 - st.cur[id]]
end
current(st::HostStore, p, key) = array(st, IR.fieldid(p, key), :cur)

"""
Everything a launch needs, built once; `run!` is the warm call.
"""
function prepare(p::IR.Program{N}, l::LaunchSpec{N}, st::HostStore, Praw; rt = ()) where {N}
    ck = l.kernel
    S = Tuple(Tuple(array(st, id, role) for (id, role) in lane) for lane in l.bind)
    P = derive_function(ck)(Tuple(Float64.(Praw)))
    I = ck.I
    dims = Tuple(map(Int32, IR.leveldims(p, lv)) for lv in ck.levels)
    n = I(prod(IR.leveldims(p, ck.space.level)))
    G = HostGeom{N, length(dims), length(rt), I, ck.T}(n, dims, Tuple(ck.T.(rt)))
    padded = map((n, w) -> cld(n, w) * w, l.ndrange, l.workgroup)
    return (body_function(ck), ck.strategy, S, P, G, padded)
end
function run!(prep)
    body, strategy, S, P, G, padded = prep
    strategy == :cartesian ? host_cartesian!(body, padded, S, P, G) :
    host_loop!(body, G.n, S, P, G)
    return nothing
end

"""
Run one step plan on the host: launches in order, then the host slot swaps.
"""
function run_step!(p::IR.Program, sp::StepPlan, st::HostStore, Praw; rt = ())
    foreach(l -> run!(prepare(p, l, st, Praw; rt)), sp.launches)
    foreach(f -> st.cur[f] = 3 - st.cur[f], sp.swaps)
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
