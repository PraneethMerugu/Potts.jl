# Definitions of groups_tests.jl that other test files use.
using LatticeFields: Problems as LFP
using SciMLBase: SciMLBase, remake, reinit!, ReturnCode
using SymbolicIndexingInterface: setp
using LatticeFields.Compile: fingerprint_text, fuse_update

# a stub algorithm: Euler with three substeps, three buffers and a counting cache that fails at
# step `fail_at` (0: never)
struct GStub <: LFP.AbstractFieldAlgorithm
    fail_at::Int
end
mutable struct GStubCache
    steps::Int
    resets::Int
    fail_at::Int
end
LFP.nbuffers(::GStub) = 3
LFP.update_key(::GStub) = :euler
LFP.update_rule(::GStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::GStub, group, store) = GStubCache(0, 0, a.fail_at)
LFP.reset_cache!(c::GStubCache) = (c.resets += 1; nothing)
LFP.step_retcode!(c::GStubCache, rt) = (c.steps += 1; c.steps == c.fail_at ? ReturnCode.ConvergenceFailure : ReturnCode.Success)
LFP.substeps(::LFP.FieldProblem, ::GStub, p = nothing; tables = nothing, inputs = nothing, dt = nothing) = 3

@parameters ga = 0.3 gb = 0.2
@variables gc(..) go(..)
gce, goe = gc(t, x, y), go(t, x, y)
# c diffuses and reads o; o decays and reads c
gsys(; T = 0.1) = PDESystem(
    [D(gce) ~ laplacian(gce) + ga * goe, D(goe) ~ -gb * goe + 0.1 * gce],
    [gc(0, x, y) ~ x * y, go(0, x, y) ~ 1.0 + x, gc(t, 0, y) ~ gc(t, 1, y), gc(t, x, 0) ~ gc(t, x, 1),
     go(t, 0, y) ~ go(t, 1, y), go(t, x, 0) ~ go(t, x, 1)],
    [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [gce, goe], [ga, gb]; name = :g)
# (the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
gown(sys; n = 8) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64)))
gwarm(ig) = (step!(ig); step!(ig); @allocated step!(ig))      # (a function barrier)
gerr(f) = try
    f(); ""
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end

# Hand FTCS on a 2D box (test/fields.jl:10–33, ported): `n` substeps of `dt/n`; periodic or
# zero-flux faces; `rate(c, i, j)` the reaction; the update clipped below at `lower`
function g_ftcs(c0, D, h, dt, n; periodic, rate = (c, i, j) -> 0.0, lower = nothing)
    c = copy(c0)
    nx, ny = size(c)
    for _ in 1:n
        new = similar(c)
        for j in 1:ny, i in 1:nx
            lap = 0.0
            for (di, dj, hd) in ((1, 0, h[1]), (-1, 0, h[1]), (0, 1, h[2]), (0, -1, h[2]))
                a, b = i + di, j + dj
                if periodic
                    a, b = mod1(a, nx), mod1(b, ny)
                elseif !(1 <= a <= nx && 1 <= b <= ny)
                    continue                                       # zero flux: the ghost is the site
                end
                lap += (c[a, b] - c[i, j]) / hd^2
            end
            v = c[i, j] + dt / n * (D * lap + rate(c, i, j))
            new[i, j] = lower === nothing ? v : max(v, lower)
        end
        c = new
    end
    return c
end

# A group that reads another group's field through a spatial operator (`laplacian(o)` in
# `c`'s rate) keeps that field's face conditions in the cut, so the input `o` has the face rules
# of the whole system (here a Dirichlet face on x = 0). Base 9afaac05: IRError "field `go` has no
# boundary rule on axis 1".
using LatticeFields.IR: FaceRule as GFaceRule

# The group's slots are specs, not names. A parameter slot holds its
# default and role (a computed default: `:computed` with its expression), a table its values, an
# input its element type, declared bounds, default and whether a caller fills it at every
# step (`filled`: coupled CPM reads; none standalone). `string` of each is its key, so the
# names in order are unchanged.
@parameters gk = 2ga
@variables gin(..) [input = true, bounds = (0.0, 2.0)] gki(..)::Int32 [input = true]

# An aux field read at neighbor sites by a rate (`K ~ k c`, `D(c) ~ laplacian(K)`)
# has no value beyond a closed face: refused in the equation's words with the route (`k laplacian(c)`),
# which builds and gives the same run on a periodic box. A face condition on an aux field is
# refused naming it. Base (8f658abd): "IRError: field `K` has no boundary rule on axis 1 side -";
# a face on `K`: "face conditions apply to rate fields (a map's offset …)".
@variables gsc(..) gsK(..)

# An aux field that carries one state into another's rate (`K ~ c`,
# `D(a) ~ -k K`, `D(c) ~ k a`) is a one-buffer field read new inside the group's Jacobi step:
# its kernel runs first. One group equals the hand-stepped Jacobi step; two groups the split
# (a's group, holding c, then c's group reading the new a). Base (eb2efb60): `discretize`
# refused it ("the fields K, a, c define each other within one step (a read cycle …)").
@parameters gkl = 1.0
@variables gla(..) glc(..) glK(..)

# The status word and its readers. A stub with a solve (`WStub`)
# steps as Euler and writes into its cache's word what an implicit solver would: a solve per
# window, a linear budget hit per window when `need > budget`, and code `code` from window `at`
# (sticky, with the window and a cause bit). B reads the word on the host after every step,
# and at the saves and the end. Base (f8510fe8): no reader; the run ended `Success`.
struct WStub <: LFP.AbstractFieldAlgorithm
    code::UInt32
    at::Int
    need::Int
    budget::Int
end
WStub(; code = 0, at = 0, need = 0, budget = 8) = WStub(UInt32(code), at, need, budget)
mutable struct WStubCache{W}
    word::W
    steps::Int
    a::WStub
end
LFP.nbuffers(::WStub) = 2
LFP.update_key(::WStub) = :euler
LFP.update_rule(::WStub) = LFP.update_rule(ExplicitEuler())
LFP.alg_cache(a::WStub, group, store) = WStubCache(fill!(similar(store.flat[1], UInt32, 8), 0), 0, a)
LFP.status_word(c::WStubCache) = c.word
LFP.reset_cache!(::WStubCache) = nothing                  # (no history; a write keeps the word)
LFP.substeps(::LFP.FieldProblem, ::WStub, p = nothing; tables = nothing, inputs = nothing, dt = nothing) = 1
wbump!(w, i, x) = (v = view(w, i:i); v .+= UInt32(x); nothing)
wset!(w, i, x) = (v = view(w, i:i); v .= UInt32(x); nothing)
function LFP.step_retcode!(c::WStubCache, rt)
    c.steps += 1
    wbump!(c.word, LFP.STATUS_SOLVES, 1)
    c.a.need > c.a.budget && wbump!(c.word, LFP.STATUS_BUDGET, 1)
    if c.a.code > 0 && c.steps == c.a.at
        wset!(c.word, LFP.STATUS_CODE, c.a.code)
        # the window, as a solver writes it: the runtime's window count
        c.a.code >= 2 && (wset!(c.word, LFP.STATUS_WINDOW, rt.totals.windows); wset!(c.word, LFP.STATUS_CAUSE, 1))
    end
    return ReturnCode.Success
end
