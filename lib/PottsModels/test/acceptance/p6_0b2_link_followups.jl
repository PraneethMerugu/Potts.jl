# P6.0b2 (ROADMAP Phase 6, step 0): P6.0b review follow-ups on edge variables.
# Decision: D-127 (amends D-058). Frozen (AUTONOMY §7.3).
#
# The defects, measured on 18861b25:
#  1. `_bind_edge_scope` (src/vocabulary.jl) binds every unscoped `x(edge)` of a body to the
#     body's only relationship before `@extend` merges, and `extend` (src/compose.jl) keeps
#     the extension's variable of each name. An extension that re-declares a base edge
#     variable to change its default (`@variables rest(edge) = 9.0`, the D-114 override
#     idiom) while adding one relationship of its own (`tether`) therefore moves `rest` to
#     `tether`, and `mtkcompile` fails on the BASE's term:
#       "edges(bond) reads `rest`, an edge variable of relationship `tether`"
#     With no relationship of its own over a two-relationship base, or with two of its own,
#     the re-declaration stays unscoped and `mtkcompile` calls it "ambiguous". An explicit
#     re-scope (`rest(tether)` over a base `rest(bond)`) is accepted by the constructor and
#     moves the payload silently when nothing of the base reads it.
#  2. `_initial_state` (src/problem.jl) skips edge variables (`continue`) and seeds initial
#     links from `info(x).default`: `:rest => 9.0` (or `[1.0, 2.0]`) in the operating point
#     passes `_operating_point` and is ignored (`link_rest == [12.0 12.0 0.0]`, the same
#     total energy as without it).
#
# Rule (D-127), pinned here:
#  A. An unscoped `x(edge)` in an extension body that re-declares an edge variable the
#     extension inherits keeps the inherited relationship, whatever relationships the
#     extension body declares (none, one or several); only its default (and anything else
#     it re-declares) is the extension's (D-114). A NEW unscoped edge variable keeps D-058:
#     the body's only relationship, "ambiguous" with several. An explicitly scoped
#     re-declaration naming another relationship (`rest(tether)` over the base's
#     `rest(bond)`) is an `ArgumentError` when the extension is built, naming the variable
#     and both relationships (an edge variable's payload column belongs to one
#     relationship; moving it would silently strip the base's terms and rules of it).
#  B. An edge variable's operating-point value is the initial value of that variable on
#     every initial link of its relationship (the links given as `:rel => [(a, b), …]`), on
#     both ends, converted to the problem's `T`, at construction and in
#     `remake(prob; u0 = op)`. It must be a number; anything else is an `ArgumentError`
#     naming the variable. Links created later by `@link` start at the declared default
#     (compiled into the rule, part of the fingerprint); the operating point is state, so
#     it never changes the fingerprint.
#  Generated code is unchanged: every link model's fingerprint stays (pins below).
#
# Hand-checked values. `p60b2_three()`: three 6×6 blobs at x 5:10, 20:25, 40:45 (rows
# 12:17) on a 60×30 Moore(1) lattice, so centroid distances d12 = 15 and d23 = 20. Each blob
# has 4 corner sites with 5 medium neighbours and 16 edge sites with 3: 68 unlike pairs,
# 204 for three, × J = 16 → 3264; volumes are at target (0). A bond adds
# k (d12 - rest)² = 2·(15 - rest)² (rest 12 → 18, 9 → 72, 7.5 → 112.5), a tether
# 1.5 (d23 - len)² (len 18 → 6, 20 → 0). Edge terms count each link once (measured:
# Spring 3282 = 3264 + 18, Explicit 3342 = 3264 + 72 + 6, Two 3288 = 3264 + 18 + 6).
#
# Failures on 18861b25: every "re-declared edge variable" target (A) and every
# operating-point target (B); the controls and pins pass.
using Potts: CorePotts

@potts_model P60b2Spring begin                      # base: `rest(edge)` means `bond`
    @kinds medium blob
    @parameters begin
        T = 10.0
        k = 2.0
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36.0)^2
        contacts => 16.0
        edges(bond) => k * (distance - rest)^2
    end
    @sweep Metropolis(; temperature = T)
end

# the oracle for A: the same extension with the base's relationship written out (works today)
@potts_model P60b2Explicit begin
    @extend base = P60b2Spring()
    @variables begin
        rest(bond) = 9.0
        len(tether) = 18.0
    end
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end

# a two-relationship base (the P6.0b SpringTether pattern; works today)
@potts_model P60b2Two begin
    @extend base = P60b2Spring()
    @variables len(tether) = 18.0
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end

# A, one relationship of its own: the reviewer's case
@potts_model P60b2Redeclare begin
    @extend base = P60b2Spring()
    @variables begin
        rest(edge) = 9.0
        len(tether) = 18.0
    end
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end

# A, the same with the base name bound (`@extend rest = …`, D-114)
@potts_model P60b2RedeclareBound begin
    @extend rest = base = P60b2Spring()
    @variables begin
        rest(edge) = 9.0
        len(tether) = 18.0
    end
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end

# A, no relationship of its own over a two-relationship base: both inherited variables
@potts_model P60b2RedeclareOverTwo begin
    @extend base = P60b2Two()
    @variables begin
        rest(edge) = 9.0
        len(edge) = 20.0
    end
end
@potts_model P60b2ExplicitOverTwo begin              # its oracle
    @extend base = P60b2Two()
    @variables begin
        rest(bond) = 9.0
        len(tether) = 20.0
    end
end

# A, two relationships of its own
@potts_model P60b2RedeclareTwoOwn begin
    @extend base = P60b2Spring()
    @variables begin
        rest(edge) = 9.0
        len(tether) = 18.0
        w(glue) = 1.0
    end
    @relationship tether(cell, cell) capacity = 1
    @relationship glue(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end

# A: the extension's own term reads the re-declared (still `bond`'s) variable
@potts_model P60b2RedeclareOwnRead begin
    @extend base = P60b2Spring()
    @variables rest(edge) = 9.0
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - rest)^2
end

# A: explicit re-scope to another relationship, read by the base's term
@potts_model P60b2Rescope begin
    @extend base = P60b2Spring()
    @variables rest(tether) = 9.0
    @relationship tether(cell, cell) capacity = 1
end

# a base whose edge variable no term or rule reads (today an explicit re-scope moves it
# silently)
@potts_model P60b2Linker begin
    @kinds medium blob
    @parameters begin
        T = 2.0
    end
    @variables age(edge) = 1.5
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((40, 20); neighborhood = Moore(1))
    @energy begin
        cells(blob) => (volume - 36.0)^2
        contacts => 16.0
    end
    @link bond when = new_contact(a, b)
    @sweep Metropolis(; temperature = T)
end
@potts_model P60b2RescopeUnread begin
    @extend base = P60b2Linker()
    @variables age(tether) = 4.0
    @relationship tether(cell, cell) capacity = 1
end

# controls (D-058, unchanged): a NEW unscoped edge variable
@potts_model P60b2NewUnscoped begin                  # one own relationship: binds to it
    @extend base = P60b2Spring()
    @variables len(edge) = 18.0
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end
@potts_model P60b2NewAmbiguous begin                 # two own relationships: ambiguous
    @extend base = P60b2Spring()
    @variables w(edge) = 1.0
    @relationship tether(cell, cell) capacity = 1
    @relationship glue(cell, cell) capacity = 1
end
@potts_model P60b2RedeclareNoRel begin               # no own relationship over one: binds today
    @extend base = P60b2Spring()
    @variables rest(edge) = 9.0
end

function p60b2_three()
    σ = zeros(Int32, 60, 30)
    σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2; σ[40:45, 12:17] .= 3
    return σ
end
p60b2_op(extra...) = Any[ownership => p60b2_three(), kind => [:blob, :blob, :blob], :bond => [(1, 2)], extra...]
p60b2_op2(extra...) = p60b2_op(:tether => [(2, 3)], extra...)
p60b2_compile(M) = mtkcompile(M(; name = :m))
p60b2_names(c, r) = [Potts.info(x).name for x in c.edge_vars[r]]
p60b2_problem(M, op; kw...) = PottsProblem(M(; name = :m), op, (0, 10); kw...)
# payload `x` of the `rel` link between `a` and `b`, read at `a`'s end
function p60b2_payload(u, rel, x, a, b)
    k = CorePotts.link_slot(CorePotts.link_store(u.cell, rel), a, b)
    return k == 0 ? nothing : getproperty(u.cell, Symbol(:link_, x))[k, a]
end
function p60b2_linker_state()
    σ = zeros(Int32, 40, 20)
    σ[3:8, 8:13] .= 1; σ[20:25, 8:13] .= 2; σ[26:31, 8:13] .= 3   # 2 and 3 touch (6 sites); 1 is 11 away
    return σ
end

const p60b2_FP_SPRING = 0x16701c1f8ce3fa21           # measured on 18861b25 (Float64)
const p60b2_FP_TWO = 0x71f6f255dc6b2be8              # Two and Explicit alike (no link rule reads a default)
const p60b2_FP_LINKER = 0xfe75f056748fa0b1

# ---------------------------------------------------------------------------------------
# A. a re-declared inherited edge variable keeps its relationship

@testset "P6.0b2: a re-declared base edge variable keeps the base's relationship" begin
    oracle = p60b2_compile(P60b2Explicit)
    @test p60b2_names(oracle, :bond) == [:rest] && p60b2_names(oracle, :tether) == [:len]   # control
    for M in (P60b2Redeclare, P60b2RedeclareBound)
        c = p60b2_compile(M)
        @test p60b2_names(c, :bond) == [:rest]
        @test p60b2_names(c, :tether) == [:len]
        prob = p60b2_problem(M, p60b2_op2())
        u = prob.u0
        @test p60b2_payload(u, :bond, :rest, 1, 2) == p60b2_payload(u, :bond, :rest, 2, 1) == 9.0   # the extension's default
        @test p60b2_payload(u, :tether, :len, 2, 3) == 18.0
        @test total_energy(prob) == 3264 + 72 + 6 == total_energy(p60b2_problem(P60b2Explicit, p60b2_op2()))
        @test prob.f.fingerprint == p60b2_FP_TWO
        @test selfcheck(prob) < 1e-9
    end
end

@testset "P6.0b2: re-declarations without, or with several, relationships of their own" begin
    c = p60b2_compile(P60b2RedeclareOverTwo)
    @test p60b2_names(c, :bond) == [:rest] && p60b2_names(c, :tether) == [:len]
    prob = p60b2_problem(P60b2RedeclareOverTwo, p60b2_op2())
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 2) == 9.0
    @test p60b2_payload(prob.u0, :tether, :len, 3, 2) == 20.0
    @test total_energy(prob) == 3264 + 72 + 0 == total_energy(p60b2_problem(P60b2ExplicitOverTwo, p60b2_op2()))
    @test prob.f.fingerprint == p60b2_FP_TWO

    c = p60b2_compile(P60b2RedeclareTwoOwn)
    @test p60b2_names(c, :bond) == [:rest]
    @test p60b2_names(c, :tether) == [:len] && p60b2_names(c, :glue) == [:w]
    prob = p60b2_problem(P60b2RedeclareTwoOwn, p60b2_op2(:glue => [(1, 3)]))
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 2) == 9.0 && p60b2_payload(prob.u0, :glue, :w, 1, 3) == 1.0
    @test total_energy(prob) == 3264 + 72 + 6
end

@testset "P6.0b2: the re-declared variable is the base relationship's, not the extension's" begin
    # the extension's own edge term may not read it (it has no slot on `tether` links)
    @test_throws ArgumentError p60b2_compile(P60b2RedeclareOwnRead)
    @test_throws r"edges\(tether\) reads `rest`, an edge variable of relationship `bond`" p60b2_compile(P60b2RedeclareOwnRead)
end

@testset "P6.0b2: an explicit re-scope to another relationship is rejected when built" begin
    for (M, x) in ((P60b2Rescope, "rest"), (P60b2RescopeUnread, "age"))
        @test_throws ArgumentError M(; name = :m)
        err = try
            M(; name = :m); nothing
        catch e
            e
        end
        msg = err === nothing ? "" : sprint(showerror, err)
        @test occursin("`$x`", msg) && occursin("bond", msg) && occursin("tether", msg)
    end
    # control: the same re-declaration scoped to the base's relationship builds
    @test p60b2_names(p60b2_compile(P60b2Explicit), :bond) == [:rest]
end

@testset "P6.0b2: new unscoped edge variables keep D-058 (controls)" begin
    c = p60b2_compile(P60b2NewUnscoped)
    @test p60b2_names(c, :tether) == [:len] && p60b2_names(c, :bond) == [:rest]
    @test_throws "ambiguous" p60b2_compile(P60b2NewAmbiguous)
    c = p60b2_compile(P60b2RedeclareNoRel)
    @test p60b2_names(c, :bond) == [:rest]
    prob = p60b2_problem(P60b2RedeclareNoRel, p60b2_op())
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 2) == 9.0 && total_energy(prob) == 3264 + 72
    c = p60b2_compile(P60b2Two)
    @test p60b2_names(c, :bond) == [:rest] && p60b2_names(c, :tether) == [:len]
end

# ---------------------------------------------------------------------------------------
# B. edge-variable values in the operating point

@testset "P6.0b2: an operating-point edge value seeds every initial link" begin
    base = p60b2_problem(P60b2Spring, p60b2_op())
    @test p60b2_payload(base.u0, :bond, :rest, 1, 2) == 12.0 && total_energy(base) == 3264 + 18   # control
    prob = p60b2_problem(P60b2Spring, p60b2_op(:rest => 9.0))
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 2) == 9.0
    @test p60b2_payload(prob.u0, :bond, :rest, 2, 1) == 9.0
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 3) === nothing   # no other link
    @test total_energy(prob) == 3264 + 72
    @test total_energy(prob) - total_energy(base) == 54
    @test selfcheck(prob) < 1e-9                       # ΔH reads the seeded payload too
    @test p60b2_payload(p60b2_problem(P60b2Spring, p60b2_op(:rest => 9)).u0, :bond, :rest, 1, 2) === 9.0   # an Int
    p32 = p60b2_problem(P60b2Spring, p60b2_op(:rest => 9.0); T = Float32)
    @test p60b2_payload(p32.u0, :bond, :rest, 1, 2) === 9.0f0
    # equal to the default: no change (control)
    @test total_energy(p60b2_problem(P60b2Spring, p60b2_op(:rest => 12.0))) == total_energy(base)
    # the payload is state: a run keeps it (no rule rewrites it)
    u = solve(remake(prob; tspan = (0, 5)), SequentialCPM()).u[end]
    @test p60b2_payload(u, :bond, :rest, 1, 2) == 9.0
end

@testset "P6.0b2: operating-point edge values per relationship" begin
    prob = p60b2_problem(P60b2Two, p60b2_op2(:len => 20.0))
    @test p60b2_payload(prob.u0, :tether, :len, 2, 3) == p60b2_payload(prob.u0, :tether, :len, 3, 2) == 20.0
    @test p60b2_payload(prob.u0, :bond, :rest, 1, 2) == 12.0   # the other relationship keeps its default
    @test total_energy(prob) == 3264 + 18 + 0
    prob = p60b2_problem(P60b2Two, p60b2_op2(:rest => 9.0, :len => 20.0))
    @test total_energy(prob) == 3264 + 72 + 0
    # a value for a relationship with no initial links is accepted and changes nothing
    prob = p60b2_problem(P60b2Two, p60b2_op(:len => 20.0))
    @test all(iszero, prob.u0.cell.links__tether) && total_energy(prob) == 3264 + 18
end

@testset "P6.0b2: remake(prob; u0 = op) honours edge values" begin
    prob = p60b2_problem(P60b2Spring, p60b2_op())
    q = remake(prob; u0 = p60b2_op(:rest => 7.5))
    @test p60b2_payload(q.u0, :bond, :rest, 1, 2) == 7.5 && total_energy(q) == 3264 + 112.5
    r = remake(q; u0 = p60b2_op())                    # without the key: the default again
    @test p60b2_payload(r.u0, :bond, :rest, 1, 2) == 12.0
end

@testset "P6.0b2: links made by @link start at the declared default" begin
    prob = PottsProblem(P60b2Linker(; name = :m), [ownership => p60b2_linker_state(), kind => [:blob, :blob, :blob],
        :bond => [(1, 2)], :age => 5.0], (0, 2))
    @test p60b2_payload(prob.u0, :bond, :age, 1, 2) == p60b2_payload(prob.u0, :bond, :age, 2, 1) == 5.0
    @test p60b2_payload(prob.u0, :bond, :age, 2, 3) === nothing
    for seed in 1:2
        u = solve(remake(prob; seed), SequentialCPM()).u[end]
        @test p60b2_payload(u, :bond, :age, 1, 2) == 5.0       # the initial link keeps the op value
        @test p60b2_payload(u, :bond, :age, 2, 3) == 1.5       # the new one (2 and 3 touch) the default
        @test p60b2_payload(u, :bond, :age, 3, 2) == 1.5
    end
end

@testset "P6.0b2: a non-number edge value is rejected" begin
    for v in ([1.0, 2.0], fill(9.0, 1, 3), "9")
        @test_throws ArgumentError p60b2_problem(P60b2Spring, p60b2_op(:rest => v))
        @test_throws r"`rest`" p60b2_problem(P60b2Spring, p60b2_op(:rest => v))
    end
    # unchanged: an unknown key still names nothing (control)
    @test_throws "names nothing" p60b2_problem(P60b2Spring, p60b2_op(:rset => 9.0))
end

# ---------------------------------------------------------------------------------------
# unchanged: generated code, fingerprints and defaults of link models

@testset "P6.0b2: link models keep their fingerprints" begin
    @test p60b2_problem(P60b2Spring, p60b2_op()).f.fingerprint == p60b2_FP_SPRING
    @test p60b2_problem(P60b2Spring, p60b2_op(:rest => 9.0)).f.fingerprint == p60b2_FP_SPRING   # state, not code
    @test p60b2_problem(P60b2Two, p60b2_op2()).f.fingerprint == p60b2_FP_TWO
    @test p60b2_problem(P60b2Explicit, p60b2_op2()).f.fingerprint == p60b2_FP_TWO
    lk = [ownership => p60b2_linker_state(), kind => [:blob, :blob, :blob], :bond => [(1, 2)]]
    @test PottsProblem(P60b2Linker(; name = :m), lk, (0, 2)).f.fingerprint == p60b2_FP_LINKER
    @test PottsProblem(P60b2Linker(; name = :m), [lk; :age => 5.0], (0, 2)).f.fingerprint == p60b2_FP_LINKER
    # defaults without an operating-point value are as before
    two = p60b2_problem(P60b2Two, p60b2_op2())
    @test two.u0.cell.link_rest == [12.0 12.0 0.0] && two.u0.cell.link_len == [0.0 18.0 18.0]
    @test total_energy(two) == 3264 + 18 + 6
end
