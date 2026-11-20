# Definitions of compile/multilevel_tests.jl that other test files use.
using LatticeFields.IR: reduce!, gate!, table!, table, constant, CLAMP, I32

ml_msg(f) =
    try
        f()
        ""
    catch e
        sprint(showerror, e)
    end
function ml_modes(pb, inputs; out = "v")
    map((CompileOptions(), CompileOptions(; index = :linear), debug_options())) do o
        s, sp = build(pb; options = o)
        st = HostStore(s)
        foreach(((k, v),) -> copyto!(current(st, s, k), v), inputs)
        run_step!(s, sp, st, ())
        copy(current(st, s, out))
    end
end

"""
Children of coarse index `X` on an axis of `nf` fine sites (n ÷ 2 convention, oracle).
"""
function kids(X, nf)
    if nf == 1
        X:X
    elseif X == nf ÷ 2 && isodd(nf)
        (2X - 1):(2X + 1)
    else
        (2X - 1):(2X)
    end
end

function restrict_case(dims; op = :sum, lane = F32)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), levels = 2)
    r = field!(pb, "r"; role = :input, storage = lane)
    v = field!(pb, "v"; role = :output, levels = [1], storage = lane)
    kb = kernel(pb, Space{N}(; level = 1))
    # child value plus its fine +x neighbor (fine-frame offset inside the child scope)
    x = load(kb, r; level = -1) +
        2 * load(kb, r; level = -1, offset = unitoff(N), policy = CLAMP)
    store(kb, v, IR.restrict(lane == U8 ? load(kb, r; level = -1) : x; op))
    add!(pb, kb, "rs")
    return pb
end
unitoff(N) = ntuple(d -> d == 1 ? 1 : 0, N)
