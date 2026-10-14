# Classify a re-freeze (D-250): does it only re-pin declared recorded values? Run the base's
# own copy of this file, from the repository root:
#
#   git show <base>:tools/frozen_diff.jl > /tmp/frozen_diff.jl
#   julia /tmp/frozen_diff.jl <base> [<candidate>]       # <candidate> omitted: the working tree
#
# A changed frozen file (listed in `lib/PottsModels/test/frozen.toml` at <base>) is AUTO only
# when every difference is a String literal inside a `const NAME = …` whose NAME the file's
# `pins` list declares *at <base>*. Within that constant, `=>` keys and all other structure
# must stay; comments on its lines may change (its lines end at its last code line). Every
# statement outside the declared constants must parse to the same tree, and every line outside
# them must be byte-identical, comments included (on a Literate page, comments are the page). The line
# count must not change.
#
# Only a plain String that is a `=>` value or a vector element may change; a string passed to a
# call is code. Everything else needs the maintainer, including any change to a file's `pins`
# list, a new frozen.toml entry that declares pins, a change to this tool, `frozen.jl`, the
# test runners, `.github/workflows/ci.yml` or `.github/ci/parallel.sh`, and a frozen file
# removed or renamed. Other new entries are first freezes and are not judged.
#
# Exit codes: 0 every changed frozen file is AUTO (or none changed), 1 something needs the
# maintainer, 2 an error, including running a copy that is not the base's own. Errors never
# produce AUTO.
using TOML: TOML

const TOMLPATH = "lib/PottsModels/test/frozen.toml"
const TESTDIR = "lib/PottsModels/test"
const TOOLPATH = "tools/frozen_diff.jl"
# Changing these changes how frozen files are checked or run: always the maintainer.
const GUARDED = [TOOLPATH, "lib/PottsModels/test/frozen.jl", "lib/PottsModels/test/runtests.jl", "test/runtests.jl",
    ".github/workflows/ci.yml", ".github/ci/parallel.sh"]

struct ToolError <: Exception
    msg::String
end
Base.showerror(io::IO, e::ToolError) = print(io, e.msg)

function gitshow(ref, path)
    ref === nothing && return isfile(path) ? read(path, String) : nothing
    buf = IOBuffer()
    ok = success(pipeline(`git show $ref:$path`; stdout = buf, stderr = devnull))
    return ok ? String(take!(buf)) : nothing
end

function gitcommit(ref)
    success(pipeline(`git rev-parse --verify --quiet $(ref * "^{commit}")`; stdout = devnull, stderr = devnull)) ||
        throw(ToolError("not a commit: $ref"))
    return ref
end

# ---- one file --------------------------------------------------------------------------

"""
Top-level statements with their first and last source lines. The last line is the statement's
last code line: blank and comment-only lines before the next statement are not part of it.
"""
function statement_spans(src)
    tree = Meta.parseall(src)
    any(x -> x isa Expr && x.head in (:error, :incomplete), tree.args) && throw(ToolError("parse error"))
    out = Tuple{Any, Int, Int}[]
    nlines = count(==('\n'), src) + 1
    line = 1
    for a in tree.args
        if a isa LineNumberNode
            line = a.line
            isempty(out) || (out[end] = (out[end][1], out[end][2], line - 1))
        else
            push!(out, (a, line, nlines))
        end
    end
    # end each statement at the first line where its own text parses complete, so trailing
    # blanks and comments (`#` lines or a `#= … =#` block) belong to no statement
    lines = split(src, '\n')
    for (k, (st, a, b)) in enumerate(out)
        for e in a:b
            x = Meta.parse(join(lines[a:e], '\n'); raise = false)
            if !(x isa Expr && x.head in (:error, :incomplete))
                b = e
                break
            end
        end
        out[k] = (st, a, b)
    end
    return out
end

strip_lnn(x) = x
function strip_lnn(e::Expr)
    e.head === :macrocall &&
        return Expr(:macrocall, strip_lnn(e.args[1]), nothing, Any[strip_lnn(a) for a in e.args[3:end]]...)
    return Expr(e.head, Any[strip_lnn(a) for a in e.args if !(a isa LineNumberNode)]...)
end

pinned_name(st, pins) =
    st isa Expr && st.head === :const && st.args[1] isa Expr && st.args[1].head === :(=) &&
    st.args[1].args[1] isa Symbol && st.args[1].args[1] in pins ? st.args[1].args[1] : nothing

"Structural equality that also compares types (`isequal(7, 7.0)` is true; this is not)."
function same(a, b)
    a isa Expr && b isa Expr &&
        return a.head === b.head && length(a.args) == length(b.args) && all(same(x, y) for (x, y) in zip(a.args, b.args))
    return typeof(a) === typeof(b) && isequal(a, b)
end

"""
Equal except for plain String literals that are a `=>` value or a vector element (`slot`);
`=>` keys must be equal. A string passed to any call (`parse(Float64, "0.05")`, `Regex(…)`)
is code and must not change.
"""
function strings_only(o, n, slot = false)
    same(o, n) && return true
    o isa String && n isa String && return slot
    (o isa Expr && n isa Expr && o.head === n.head && length(o.args) == length(n.args)) || return false
    o.head === :macrocall && return false
    if o.head === :call && o.args[1] === :(=>) && length(o.args) == 3
        return same(o.args[2], n.args[2]) && strings_only(o.args[3], n.args[3], true)
    end
    o.head === :vect && return all(strings_only(x, y, true) for (x, y) in zip(o.args, n.args))
    return all(strings_only(x, y) for (x, y) in zip(o.args, n.args))
end

"""
`(:auto | :maintainer, reasons)` for one frozen file. `pins` are the names declared at the
base. Throws `ToolError` when a version does not parse.
"""
function classify(path, old_src, new_src, pins::Set{Symbol})
    new_src === nothing && return (:maintainer, ["the frozen file was removed"])
    endswith(path, ".jl") || return (:maintainer, ["not a Julia file"])
    isempty(pins) && return (:maintainer, ["the file declares no pins"])
    old_src = replace(old_src, "\r\n" => "\n")
    new_src = replace(new_src, "\r\n" => "\n")
    ol, nl = split(old_src, '\n'), split(new_src, '\n')
    length(ol) == length(nl) || return (:maintainer, ["the line count changed"])
    os, ns = statement_spans(old_src), statement_spans(new_src)
    length(os) == length(ns) || return (:maintainer, ["a statement was added or removed"])
    inpin = falses(length(ol))
    for ((o, o1, o2), (n, n1, n2)) in zip(os, ns)
        (o1, o2) == (n1, n2) || return (:maintainer, ["statements moved (line $o1)"])
        name = pinned_name(o, pins)
        if name === nothing
            same(strip_lnn(o), strip_lnn(n)) || return (:maintainer, ["line $o1: a statement outside the pins changed"])
            continue
        end
        isequal(name, pinned_name(n, pins)) || return (:maintainer, ["line $o1: const $name renamed"])
        strings_only(strip_lnn(o.args[1].args[2]), strip_lnn(n.args[1].args[2])) ||
            return (:maintainer, ["line $o1: const $name changed beyond its string literals"])
        inpin[o1:o2] .= true
    end
    for (i, (a, b)) in enumerate(zip(ol, nl))
        a == b || inpin[i] || return (:maintainer, ["line $i is outside the declared pins and changed"])
    end
    # outside the pins every line is identical, so the trees can differ only inside them
    return (:auto, String[])
end

# ---- the push ----------------------------------------------------------------------------

function classify_push(oldref, newref; self = nothing)
    gitcommit(oldref)
    newref === nothing || gitcommit(newref)
    base_tool = gitshow(oldref, TOOLPATH)
    base_tool === nothing && throw(ToolError("$TOOLPATH does not exist at $oldref: no AUTO before the tool is at the base"))
    self === nothing || self == base_tool ||
        throw(ToolError("this is not $oldref's copy of $TOOLPATH; run `git show $oldref:$TOOLPATH > /tmp/frozen_diff.jl` and that"))
    oldtoml = gitshow(oldref, TOMLPATH)
    oldtoml === nothing && throw(ToolError("cannot read $TOMLPATH at $oldref"))
    newtoml = gitshow(newref, TOMLPATH)
    newtoml === nothing && throw(ToolError("cannot read $TOMLPATH at the candidate"))
    entries = TOML.parse(oldtoml)["file"]
    newentries = Dict(f["path"] => f for f in TOML.parse(newtoml)["file"])
    lines = String[]
    worst = 0
    for g in GUARDED
        if gitshow(oldref, g) != gitshow(newref, g)
            push!(lines, "MAINTAINER  $g changed (it governs how frozen files are checked or run)")
            worst = 1
        end
    end
    oldpaths = Set(f["path"] for f in entries)
    for (path, ne) in newentries
        # a first freeze needs no maintainer, so it may not declare pins unseen
        if !(path in oldpaths) && !isempty(get(ne, "pins", String[]))
            push!(lines, "MAINTAINER  $path")
            push!(lines, "    a new frozen.toml entry declares pins")
            worst = 1
        end
    end
    for f in entries
        p = normpath(joinpath(TESTDIR, f["path"]))
        old_src = gitshow(oldref, p)
        old_src === nothing && throw(ToolError("cannot read $p at $oldref"))
        new_src = gitshow(newref, p)
        ne = get(newentries, f["path"], nothing)
        pins = Set(Symbol.(get(f, "pins", String[])))
        newpins = ne === nothing ? pins : Set(Symbol.(get(ne, "pins", String[])))
        (old_src == new_src && ne !== nothing && newpins == pins) && continue
        verdict, reasons = ne === nothing ? (:maintainer, ["dropped from frozen.toml (removed or renamed)"]) :
                           newpins != pins ? (:maintainer, ["its `pins` list in frozen.toml changed"]) :
                           classify(p, old_src, new_src, pins)
        if verdict === :auto
            push!(lines, "AUTO        $(f["path"])  (pin: $(join(sort!(string.(collect(pins))), ", ")))")
        else
            worst = 1
            push!(lines, "MAINTAINER  $(f["path"])")
            append!(lines, "    " .* reasons)
        end
    end
    isempty(lines) && push!(lines, "no frozen file changed")
    return worst, lines
end

function main(args)
    (1 <= length(args) <= 2) || (println(stderr, "usage: julia frozen_diff.jl <base> [<candidate>]"); return 2)
    try
        worst, lines = classify_push(args[1], length(args) == 2 ? args[2] : nothing; self = read(@__FILE__, String))
        foreach(println, lines)
        return worst
    catch err
        # every error, ours or not, is exit 2: never AUTO, never mistaken for a verdict
        println(stderr, "frozen_diff: ", sprint(showerror, err))
        return 2
    end
end

if abspath(PROGRAM_FILE) == @__FILE__()
    exit(main(ARGS))
end
