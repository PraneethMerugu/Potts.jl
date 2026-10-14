# Classify a re-freeze (D-250): which changes to frozen acceptance files may proceed without
# the maintainer's OK. Usage, from the repository root:
#
#   julia tools/frozen_diff.jl <old-ref> [<new-ref>]     # <new-ref> omitted: the working tree
#
# For every file listed in `lib/PottsModels/test/frozen.toml` at <old-ref> whose content
# differs at <new-ref>, the old and new sources are parsed and their syntax trees compared.
# Comments never reach the tree, so comment-only edits compare equal. A file is AUTO when
# every difference falls in one of these kinds:
#
#   wording   a string literal changes where it is prose: a docstring, a `@testset` name,
#             `Markdown.parse`/`md"…"`, `print`/`println`, `@info`/`@warn`/`@debug`/`@error`,
#             `error(…)`. Interpolated expressions in such strings must not change.
#   additive  whole statements are inserted: a new top-level `@testset` or a definition of
#             a fresh name, or a new `@test…` line inside an existing block. Inserted code
#             may not assign, extend or mutate any name the old file defines (no `global`,
#             `eval`, `include`, `import`/`using`, method extensions, qualified or indexed
#             assignment, `f!(old_name, …)`).
#   pin       inside `const NAME = …` where NAME is listed in the file's `pins` in frozen.toml
#             *at <old-ref>* (so a re-freeze cannot declare its own pins), string and number
#             literals may change; keys of `=>` pairs and all other structure may not.
#
# Everything else needs the maintainer: a changed number, symbol, operator, call or string
# inside an assertion, a removed or reordered statement, an element added to a list or
# mapping (it can widen an allowlist), a removed frozen file, a non-Julia file (the TSV
# records), or a file that does not parse. New entries in frozen.toml are first freezes and
# are not judged.
#
# Exit codes: 0 every changed file is AUTO (or nothing changed), 1 some file needs the
# maintainer, 2 usage or git error.
using TOML: TOML

const TOMLPATH = "lib/PottsModels/test/frozen.toml"
const TESTDIR = "lib/PottsModels/test"

const ASSERT_MACROS = Set(Symbol.(["@test", "@test_throws", "@test_broken", "@test_skip", "@test_logs",
    "@test_warn", "@test_nowarn", "@test_deprecated", "@inferred", "@assert"]))
const PROSE_MACROS = Set(Symbol.(["@md_str", "@info", "@warn", "@debug", "@error"]))
const PROSE_FUNCS = Set([:print, :println, :error, :(Markdown.parse)])
const FORBIDDEN_CALLS = Set([:eval, :include, :ccall, :(Core.eval), :(Base.eval), :invokelatest, :(Base.invokelatest)])

# ---- git -------------------------------------------------------------------------------

function gitshow(ref, path)
    ref === nothing && return isfile(path) ? read(path, String) : nothing
    buf = IOBuffer()
    ok = success(pipeline(`git show $ref:$path`; stdout = buf, stderr = devnull))
    return ok ? String(take!(buf)) : nothing
end

# ---- trees -----------------------------------------------------------------------------

strip_lnn(x) = x
function strip_lnn(e::Expr)
    # a macro call keeps its source slot (args[2]) as `nothing`, so argument positions stay put
    e.head === :macrocall &&
        return Expr(:macrocall, strip_lnn(e.args[1]), nothing, Any[strip_lnn(a) for a in e.args[3:end]]...)
    return Expr(e.head, Any[strip_lnn(a) for a in e.args if !(a isa LineNumberNode)]...)
end

# The macro-call argument list without its LineNumberNode (`args[2]`).
macroargs(e::Expr) = e.args[3:end]

macroname(e) = e isa Expr && e.head === :macrocall ? e.args[1] : nothing
isassert(e) = macroname(e) in ASSERT_MACROS
istestset(e) = macroname(e) === Symbol("@testset")
isdocmacro(e) = (m = macroname(e); m isa GlobalRef && m.name === Symbol("@doc")) || macroname(e) === Symbol("@doc")

# Names a file defines at top level: assignments, `const`, functions, macros, structs.
function defined_names(tree)
    names = Set{Symbol}()
    for st in (tree isa Expr && tree.head === :toplevel ? tree.args : Any[tree])
        st isa LineNumberNode && continue
        isdocmacro(st) && (st = macroargs(st)[end])
        for n in assigned_names(st)
            push!(names, n)
        end
    end
    return names
end

function assigned_names(st)
    st isa Expr || return Symbol[]
    h = st.head
    h === :const && return assigned_names(st.args[1])
    h in (:global, :local) && return reduce(vcat, (assigned_names(a) for a in st.args); init = Symbol[])
    h in (:function, :macro) && return lhs_names(st.args[1])
    h === :(=) && return lhs_names(st.args[1])
    h in (:struct, :abstract, :primitive) && return lhs_names(st.args[h === :struct ? 2 : 1])
    return Symbol[]
end

function lhs_names(l)
    l isa Symbol && return [l]
    l isa Expr || return Symbol[]
    l.head in (:tuple, :parameters) && return reduce(vcat, (lhs_names(a) for a in l.args); init = Symbol[])
    l.head in (:call, :where, :(::), :curly, :(<:)) && return lhs_names(l.args[1])
    return Symbol[]
end

base_symbol(x) = x isa Symbol ? x : x isa Expr && x.head in (:ref, :., :(::), :curly) ? base_symbol(x.args[1]) : nothing

# ---- insertion safety ------------------------------------------------------------------

const ASSIGN_HEADS = Set([:(=), :+=, :-=, :*=, :/=, :^=, :÷=, :%=, :|=, :&=, :⊻=, :<<=, :>>=, :.=, Symbol(".+="), Symbol(".-="), Symbol(".*="), Symbol("./=")])

"""
Why the inserted code `e` is unsafe, or `nothing`. `old` holds the names the old file
defines (or, for statements inserted into an existing block, every symbol in that block).
"""
function unsafe_insert(e, old::Set{Symbol})
    e isa Expr || return nothing
    h = e.head
    h in (:global, :import, :using, :export, :ccall, :foreigncall) && return "inserted `$(h)`"
    if h === :macrocall
        m = macroname(e)
        m in (Symbol("@eval"), :(Base.@eval)) && return "inserted `@eval`"
    end
    if h === :call
        f = e.args[1]
        f in FORBIDDEN_CALLS && return "inserted call to `$(f)`"
        fs = f isa Symbol ? string(f) : f isa Expr && f.head === :. && f.args[end] isa QuoteNode ? string(f.args[end].value) : ""
        if endswith(fs, "!") && length(e.args) >= 2
            a = e.args[2] isa Expr && e.args[2].head === :parameters ? (length(e.args) >= 3 ? e.args[3] : nothing) : e.args[2]
            b = base_symbol(a)
            b in old && return "inserted `$(fs)` mutates `$(b)`, which the old code uses"
        end
    end
    if h in ASSIGN_HEADS || h === :function
        l = e.args[1]
        if l isa Expr && l.head in (:., :ref)
            return "inserted assignment into `$(l)`"
        end
        if l isa Expr && (l.head === :call || l.head === :where)
            f = l.head === :where ? (l.args[1] isa Expr ? l.args[1].args[1] : l.args[1]) : l.args[1]
            f isa Expr && f.head === :. && return "inserted method of a qualified function `$(f)`"
        end
        for n in lhs_names(l)
            n in old && return "inserted code assigns or extends `$(n)`, which the old code uses"
        end
    end
    for a in e.args
        r = unsafe_insert(a, old)
        r === nothing || return r
    end
    return nothing
end

allsymbols(x, s = Set{Symbol}()) = (x isa Symbol ? push!(s, x) : x isa Expr ? foreach(a -> allsymbols(a, s), x.args) : nothing; s)

# ---- comparison ------------------------------------------------------------------------

struct Ctx
    assert::Bool
    prose::Bool
    pin::Bool
    pins::Set{Symbol}
    old::Set{Symbol}         # names the old file defines
end
with(c::Ctx; assert = c.assert, prose = c.prose, pin = c.pin) = Ctx(assert, prose, pin, c.pins, c.old)

mutable struct Result
    kinds::Set{Symbol}
    reasons::Vector{String}
end

fail!(r, msg) = (push!(r.reasons, msg); false)

interpolations(e) = e isa Expr && e.head === :string ? Any[a for a in e.args if !(a isa String)] : Any[]
isstringish(x) = x isa String || (x isa Expr && x.head === :string)

function compare!(r::Result, o, n, c::Ctx, where_::String)
    isequal(o, n) && return true
    # literals
    if isstringish(o) && isstringish(n)
        c.assert && return fail!(r, "$where_: a string inside an assertion changed")
        if c.prose || c.pin
            isequal(interpolations(o), interpolations(n)) ||
                return fail!(r, "$where_: an interpolated expression in a string changed")
            push!(r.kinds, c.pin ? :pin : :wording)
            return true
        end
        return fail!(r, "$where_: a string outside prose changed: $(repr(o)[1:min(end, 60)])")
    end
    if o isa Number && n isa Number && !(o isa Bool) && !(n isa Bool)
        c.pin && !c.assert && (push!(r.kinds, :pin); return true)
        return fail!(r, "$where_: a number changed ($o → $n)")
    end
    (o isa Expr && n isa Expr && o.head === n.head) ||
        return fail!(r, "$where_: `$(summ(o))` became `$(summ(n))`")
    h = o.head
    if h === :macrocall
        isequal(o.args[1], n.args[1]) || return fail!(r, "$where_: macro $(o.args[1]) became $(n.args[1])")
        m = o.args[1]
        oa, na = macroargs(o), macroargs(n)
        if istestset(o)
            length(oa) == length(na) || return fail!(r, "$where_: @testset arguments changed")
            for (i, (x, y)) in enumerate(zip(oa, na))
                cc = i == 1 && isstringish(x) ? with(c; prose = !c.assert) : c
                compare!(r, x, y, cc, "$where_ @testset") || return false
            end
            return true
        end
        if isdocmacro(o) && length(oa) == 2 && length(na) == 2
            compare!(r, oa[1], na[1], with(c; prose = true), "$where_ docstring") || return false
            return compare!(r, oa[2], na[2], c, where_)
        end
        cc = m in ASSERT_MACROS ? with(c; assert = true, prose = false, pin = false) :
             m in PROSE_MACROS && !c.assert ? with(c; prose = true) : c
        return compare_args!(r, oa, na, cc, where_, false)
    end
    if h === :call && !c.assert && o.args[1] in PROSE_FUNCS && isequal(o.args[1], n.args[1])
        return compare_args!(r, o.args[2:end], n.args[2:end], with(c; prose = true), where_, false)
    end
    if h === :call && c.pin && o.args[1] === :(=>) && length(o.args) == 3 && length(n.args) == 3
        isequal(o.args[2], n.args[2]) || return fail!(r, "$where_: a pinned key changed")
        return compare!(r, o.args[3], n.args[3], c, where_)
    end
    if h === :const && o.args[1] isa Expr && o.args[1].head === :(=) && n.args[1] isa Expr && n.args[1].head === :(=)
        name = o.args[1].args[1]
        isequal(name, n.args[1].args[1]) || return fail!(r, "$where_: const $(name) renamed")
        cc = name isa Symbol && name in c.pins ? with(c; pin = true) : c
        return compare!(r, o.args[1].args[2], n.args[1].args[2], cc, "$where_ const $(name)")
    end
    if h in (:block, :toplevel) && !c.assert
        return compare_args!(r, o.args, n.args, c, where_, true; toplevel = h === :toplevel)
    end
    # prose context does not reach into ordinary calls' structure, only their string leaves
    return compare_args!(r, o.args, n.args, c, where_, false)
end

summ(x) = (s = x isa Expr ? string(x.head) * "(" * string(x)[1:min(end, 50)] * ")" : repr(x); s[1:min(end, 70)])

function compare_args!(r, oa, na, c, where_, insertable; toplevel = false)
    if !insertable
        length(oa) == length(na) || return fail!(r, "$where_: an argument or element was added or removed (lists and mappings need the maintainer)")
        for (x, y) in zip(oa, na)
            compare!(r, x, y, c, where_) || return false
        end
        return true
    end
    # statement lists: every old statement must match, in order; the rest are insertions
    j = 1
    blocksyms = toplevel ? c.old : union(c.old, allsymbols(Expr(:block, oa...)))
    for (i, x) in enumerate(oa)
        matched = false
        while j <= length(na)
            y = na[j]
            probe = Result(Set{Symbol}(), String[])
            if compare!(probe, x, y, c, where_)
                union!(r.kinds, probe.kinds)
                matched = true
                j += 1
                break
            end
            # `y` is an insertion, unless it is the edited form of `x`
            ins = Result(Set{Symbol}(), String[])
            if !insert_ok!(ins, y, c, blocksyms, toplevel, where_)
                # when the heads agree the edit is the likelier story: report why it is not allowed
                same = y isa Expr && x isa Expr && y.head === x.head && !isempty(probe.reasons)
                append!(r.reasons, same ? probe.reasons : ins.reasons)
                return false
            end
            union!(r.kinds, ins.kinds)
            j += 1
        end
        matched || return fail!(r, "$where_: a statement was removed or changed: `$(summ(x))`")
    end
    while j <= length(na)
        insert_ok!(r, na[j], c, blocksyms, toplevel, where_) || return false
        j += 1
    end
    return true
end

function insert_ok!(r, y, c, blocksyms, toplevel, where_)
    if toplevel
        ok = istestset(y) || !isempty(assigned_names(y)) || isdocmacro(y)
        ok || return fail!(r, "$where_: inserted top-level statement is not a @testset or a definition: `$(summ(y))`")
        why = unsafe_insert(y, c.old)
    else
        ok = isassert(y) || istestset(y)
        ok || return fail!(r, "$where_: inserted statement inside an existing block is not a @test or @testset: `$(summ(y))`")
        why = unsafe_insert(y, blocksyms)
    end
    why === nothing || return fail!(r, "$where_: $why")
    push!(r.kinds, :additive)
    return true
end

# ---- driver ----------------------------------------------------------------------------

function classify(path, old_src, new_src, pins)
    endswith(path, ".jl") || return (:maintainer, Set{Symbol}(), ["not a Julia file (data records always need the maintainer)"])
    new_src === nothing && return (:maintainer, Set{Symbol}(), ["the frozen file was removed"])
    o = try
        strip_lnn(Meta.parseall(old_src))
    catch err
        return (:maintainer, Set{Symbol}(), ["old version does not parse: $err"])
    end
    n = try
        strip_lnn(Meta.parseall(new_src))
    catch err
        return (:maintainer, Set{Symbol}(), ["new version does not parse: $err"])
    end
    any(x -> x isa Expr && x.head in (:error, :incomplete), n.args) && return (:maintainer, Set{Symbol}(), ["new version has a parse error"])
    r = Result(Set{Symbol}(), String[])
    c = Ctx(false, false, false, pins, defined_names(o))
    ok = compare!(r, o, n, c, path)
    ok || return (:maintainer, r.kinds, r.reasons)
    return (:auto, isempty(r.kinds) ? Set([:comments]) : r.kinds, String[])
end

function main(args)
    (1 <= length(args) <= 2) || (println(stderr, "usage: julia tools/frozen_diff.jl <old-ref> [<new-ref>]"); return 2)
    oldref = args[1]
    newref = length(args) == 2 ? args[2] : nothing
    oldtoml = gitshow(oldref, TOMLPATH)
    oldtoml === nothing && (println(stderr, "cannot read $TOMLPATH at $oldref"); return 2)
    entries = TOML.parse(oldtoml)["file"]
    newtoml = gitshow(newref, TOMLPATH)
    newpaths = newtoml === nothing ? Set{String}() : Set(f["path"] for f in TOML.parse(newtoml)["file"])
    worst = 0
    nchanged = 0
    for f in entries
        p = joinpath(TESTDIR, f["path"]) |> normpath
        old_src = gitshow(oldref, p)
        new_src = gitshow(newref, p)
        old_src == new_src && f["path"] in newpaths && continue
        nchanged += 1
        pins = Set(Symbol.(get(f, "pins", String[])))
        verdict, kinds, reasons = f["path"] in newpaths ? classify(p, old_src, new_src, pins) :
                                  (:maintainer, Set{Symbol}(), ["dropped from frozen.toml"])
        if verdict === :auto
            println("AUTO        ", f["path"], "  (", join(sort!(collect(kinds)), ", "), ")")
        else
            worst = 1
            println("MAINTAINER  ", f["path"])
            for x in reasons
                println("    ", x)
            end
        end
    end
    nchanged == 0 && println("no frozen file changed")
    return worst
end

if abspath(PROGRAM_FILE) == @__FILE__()
    exit(main(ARGS))
end
