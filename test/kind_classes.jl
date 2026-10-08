# Kind classes (`@kinds … g = (k, …)`): rejections around the frozen acceptance file
# (lib/PottsModels/test/acceptance/p6_0g_kind_classes.jl): comparisons with a class, members
# resolved at expansion, layouts against a model, programmatic classes.

module KindClassTests
using Potts, Test

"""The message of the exception `f()` throws (unwrapping a macro expansion's `LoadError`),
or `nothing` if it throws none."""
function kc_error(f)
    try
        f()
    catch e
        e isa LoadError && (e = e.error)
        return e isa ArgumentError ? sprint(showerror, e) : "not an ArgumentError: " * sprint(showerror, e)
    end
    return nothing
end
kc_build(ex::Expr, M::Symbol) = kc_error(() -> (Core.eval(@__MODULE__, ex);
                                                Base.invokelatest(() -> getfield(@__MODULE__, M)(; name = :m))))
has(msg, parts...) = msg !== nothing && all(p -> occursin(p, msg), parts)

const Q = 2           # a global integer: never a class member

@potts_model KCBase begin
    @kinds medium fluid tip stalk endothelial = (tip, stalk)
    @lattice Lattice((12, 12))
    @energy cells(endothelial) => (volume - 9)^2
    @sweep Metropolis(; temperature = 2.0)
end

@testset "kind classes: `kind == g` and `kind != g` are errors, not constants" begin
    for (label, stmt) in (("==", :(@energy sites => 1.0 * (kind == endothelial))),
                          ("!=", :(@energy sites => 1.0 * (kind != endothelial))),
                          ("class on the left", :(@energy sites => 1.0 * (endothelial == kind))),
                          ("constraint", :(@constraint !(kind[new] == endothelial))),
                          ("drive", :(@drive copy => ifelse(endothelial != kind[old], 1.0, 0.0))))
        M = Symbol(:KCEq, hash(label) % 10_000)
        ex = :(@potts_model $M begin
            @kinds medium tip stalk endothelial = (tip, stalk)
            @lattice Lattice((12, 12))
            $stmt
            @sweep Metropolis(; temperature = 2.0)
        end)
        @test has(kc_build(ex, M), "`endothelial` is a kind class", "kind ∈ endothelial")
    end
    # control: membership builds, and on the host `∈` on kind numbers works
    @test kc_build(:(@potts_model KCIn begin
        @kinds medium tip stalk endothelial = (tip, stalk)
        @lattice Lattice((12, 12))
        @energy sites => 1.0 * (kind ∈ endothelial) + 2.0 * (kind ∉ endothelial)
        @sweep Metropolis(; temperature = 2.0)
    end), :KCIn) === nothing
    g = Potts.KindClass(:g, [1, 3])
    @test 3 in g && !(2 in g) && collect(g) == [1, 3]
end

@testset "kind classes: members are resolved when the macro expands" begin
    expand(body) = kc_error(() -> macroexpand(@__MODULE__, :(@potts_model KCX begin
        $body
        @lattice Lattice((12, 12))
        @sweep Metropolis(; temperature = 2.0)
    end)))
    @test has(expand(:(@kinds medium fluid tip stalk endothelial = (tip, stlk))),
        "kind class `endothelial`", "`stlk` is not a kind or an earlier kind class")
    @test has(expand(:(@kinds begin
        medium; fluid; tip; stalk
        g1 = (g2, fluid)                     # a later class
        g2 = (tip,)
    end)), "kind class `g1`", "`g2`")
    @test has(expand(:(@kinds medium fluid tip g = (tip, Q))), "kind class `g`", "`Q`")   # a global
    @test has(expand(:(@kinds medium tip g = (g, tip))), "cannot contain itself")
    # controls: kinds before or after the class line, earlier classes
    @test expand(:(@kinds begin
        medium; g = (tip, stalk); tip; stalk
        h = (g, fluid); fluid
    end)) === nothing
    # names bound by an `@extend` before `@kinds` are members too; after it they are not
    # bound yet when the class is built
    @potts_model KCExt begin
        @extend endothelial = base = KCBase()
        @kinds begin
            medium; fluid; tip; stalk
            prolif
            sprout = (endothelial, prolif)
        end
        @energy cells(sprout) => 0.5 * (volume - 9)^2
    end
    @test has(kc_error(() -> macroexpand(@__MODULE__, :(@potts_model KCLate begin
        @kinds medium fluid tip stalk prolif sprout = (endothelial, prolif)
        @extend endothelial = base = KCBase()
    end))), "kind class `sprout`", "`endothelial`")
    s = KCExt(; name = :m)
    @test [(g.name, g.kinds) for g in getfield(s, :kind_classes)] == [(:endothelial, [2, 3]), (:sprout, [2, 3, 4])]
    @potts_model KCExtOnlyClass begin
        @extend tip, stalk = base = KCBase()
        @kinds pair = (tip, stalk)           # no kind lines: the kinds are the base's
    end
    s = KCExtOnlyClass(; name = :m)
    @test getfield(s, :kinds) == [:medium, :fluid, :tip, :stalk]
    @test [(g.name, g.kinds) for g in getfield(s, :kind_classes)] == [(:endothelial, [2, 3]), (:pair, [2, 3])]
end

@testset "kind classes: an @extend restatement keeps the member order" begin
    msg = kc_build(:(@potts_model KCReorder begin
        @extend base = KCBase()
        @kinds begin
            medium; fluid; tip; stalk
            endothelial = (stalk, tip)
        end
    end), :KCReorder)
    @test has(msg, "endothelial", "same members in the same order")
end

@testset "kind classes: layouts against a model take kinds" begin
    sys = KCBase(; name = :m)
    tiles = Tiling((3, 3); kinds = [:tip, :stalk])
    for (l, what) in ((Tiling((3, 3); kinds = [:endothelial]), "kind class"),
                      (overlay(tiles, InsertUntil(:tip; into = [:stalk, :endothelial], number = 2, seed = 1)), "kind class"),
                      (overlay(tiles, InsertUntil(:endothelial; into = [:stalk], number = 2, seed = 1)), "kind class"),
                      (Frame(:endothelial), "kind class"),
                      (Scattered(2, (2, 2); kinds = [:endothelial], seed = 1), "kind class"))
        @test has(kc_error(() -> layout(l, sys)), what)
    end
    @test has(kc_error(() -> layout(Tiling((3, 3); kinds = [:endothelial]), mtkcompile(sys))), "kind class")
    # controls: kinds of the model; a dims target knows no kinds; other names pass the
    # layout (a model may serve as a lattice) and are rejected by `PottsProblem`
    @test has(kc_error(() -> PottsProblem(sys, layout(Tiling((3, 3); kinds = [:tpi]), sys), (0, 1))), "unknown kind `tpi`")
    op = layout(overlay(tiles, InsertUntil(:tip; into = [:stalk], number = 2, seed = 1)), sys)
    @test PottsProblem(sys, op, (0, 1)) isa PottsProblem
    @test layout(Tiling((3, 3); kinds = [:endothelial]), (12, 12)) isa Vector
end

@testset "kind classes: programmatic classes are checked" begin
    s = KCBase(; name = :m)
    with(classes) = kc_error(() -> PottsSystem(; (f => getfield(s, f) for f in fieldnames(PottsSystem))...,
                                                kind_classes = classes))
    @test with([Potts.KindClass(:ok, [1, 3])]) === nothing
    @test has(with([Potts.KindClass(:volume, [1])]), "kind class `volume`", "built-in")
    @test has(with([Potts.KindClass(:a, [1])]), "reserved")
    @test has(with([Potts.KindClass(:tip, [1])]), "tip")                       # a kind's name
    @test has(with([Potts.KindClass(:g, [0])]), "kind class `g`", "not a cell kind")
    @test has(with([Potts.KindClass(:g, [4])]), "kind class `g`", "not a cell kind")
    @test has(with([Potts.KindClass(:g, Int[])]), "empty")
    @test has(with([Potts.KindClass(:g, [1, 1])]), "twice")
    @test has(with([Potts.KindClass(:g, [1]), Potts.KindClass(:g, [2])]), "declared twice")
end
end
