# Classify a re-freeze (D-250): which changes to frozen acceptance files may proceed without
# the maintainer's OK. Usage, from the repository root:
#
#   julia tools/frozen_diff.jl <old-ref> [<new-ref>]     # <new-ref> omitted: the working tree
#
# For every file listed in `lib/PottsModels/test/frozen.toml` at <old-ref> whose content
# differs at <new-ref>, the old and new sources are parsed and their syntax trees compared.
# The rules are an allowlist: anything not listed here needs the maintainer.
#
#   wording   A String literal changes where it is a *direct* argument of a prose sink:
#             a docstring, a `@testset` name, `println`/`print`, or `Markdown.parse`.
#             Interpolated expressions must stay identical. Strings anywhere else,
#             including string macros (`md"…"`, `r"…"`) and strings passed to any other call,
#             are code. Comments are invisible to the tree; but every executable Documenter
#             block (```jldoctest, ```@example, ```@repl, ```@eval, ```@setup, ```@meta), in
#             comments or in strings, must stay byte-identical.
#   additive  Three insertions only:
#               - a top-level `@testset`;
#               - a top-level function definition whose name is new to the whole repository
#                 (no file at <old-ref> mentions it) and is not bound in Base, Core or Test;
#               - an `@test` or `@test_throws` line directly in an existing `@testset` body
#                 (never in a function, `let`, `if`, `do` or other nested block).
#             Inserted code is checked against an allowlist (`check_new`): no `global`,
#             `const`, `return` (except in a new function), `break`, `continue`, `try`,
#             `quote`, `macro`, `module`, `struct`, `import`/`using`; macros only `@test`,
#             `@test_throws`, `@test_deprecated`, `@test_logs`, `@test_warn`, `@test_nowarn`,
#             `@testset`, `@r_str`, `@v_str`; no access through Main, Core, Base, Test,
#             Libc, Sys, Meta, Random, Pkg or Filesystem; no denied names (eval, include,
#             exit, run, getfield, setfield!, invokelatest, …) as callee or value; a name
#             ending in `!` only as the callee of a call whose first argument is a value the
#             inserted code itself created. A line added to an existing testset may not
#             assign at all. `@testset` bodies are hard local scopes, so a new testset's own
#             assignments stay local.
#   pin       Inside `const NAME = …` where NAME is listed in the file's `pins` in
#             frozen.toml *at <old-ref>*, string and number literals may change; `=>` keys
#             and all other structure may not. Any change to a file's `pins` list needs the
#             maintainer.
#
# Everything else needs the maintainer: changed code (numbers, symbols, operators, calls,
# strings outside prose sinks), removed, reordered, skipped or broken tests, list or mapping
# elements, data files (TSV), removed or renamed frozen files, parse errors. New entries in
# frozen.toml are first freezes and are not judged.
#
# Exit codes: 0 every changed file is AUTO (or nothing changed), 1 some file needs the
# maintainer, 2 usage or git error.
using TOML: TOML
using Test: Test

const TOMLPATH = "lib/PottsModels/test/frozen.toml"
const TESTDIR = "lib/PottsModels/test"

const INNER_INSERT_MACROS = Set(Symbol.(["@test", "@test_throws"]))
const NEW_CODE_MACROS = Set(Symbol.(["@test", "@test_throws", "@test_deprecated", "@test_logs", "@test_warn",
    "@test_nowarn", "@testset", "@r_str", "@v_str"]))
const DENY_NAMES = Set([:eval, :include, :include_string, :evalfile, :exit, :quit, :atexit, :run, :pipeline,
    :getfield, :setfield!, :getproperty, :setproperty!, :getglobal, :setglobal!, :invokelatest, :invoke,
    :ccall, :cglobal, :cfunction, :cd, :rm, :mv, :cp, :touch, :mkdir, :mkpath, :open, :write, :chmod,
    :symlink, :download, :ENV, :Main, :Core, :Base, :Test, :Libc, :Sys, :Meta, :Random, :Pkg,
    :Filesystem, :Distributed, :InteractiveUtils, :Threads, :Docs, :Expr, :Symbol, :parse])
const DENY_MODULES = Set([:Main, :Core, :Base, :Test, :Libc, :Sys, :Meta, :Random, :Pkg, :Filesystem,
    :Distributed, :InteractiveUtils, :Threads, :Docs])
const NEW_CODE_HEADS = Set([:call, :kw, :parameters, :tuple, :vect, :vcat, :hcat, :row, :nrow, :ncat,
    :typed_vcat, :typed_hcat, :ref, :., :comparison, :&&, :||, :if, :elseif, :block, :let, :for,
    :while, :(=), :->, :do, :generator, :filter, :flatten, :comprehension, :typed_comprehension,
    :curly, :(::), :where, :macrocall, :string, :function, :return, :..., :<:, :>:])
const EXEC_FENCE = r"```[ \t]*(jldoctest|@example|@repl|@eval|@setup|@meta|@raw|@doctest)[^\n]*\n.*?```"s

# ---- git -------------------------------------------------------------------------------

function gitshow(ref, path)
    ref === nothing && return isfile(path) ? read(path, String) : nothing
    buf = IOBuffer()
    ok = success(pipeline(`git show $ref:$path`; stdout = buf, stderr = devnull))
    return ok ? String(take!(buf)) : nothing
end

"Every identifier-like token in every Julia file of the repository at `ref`."
function repo_identifiers(ref)
    names = Set{Symbol}()
    buf = IOBuffer()
    cmd = ref === nothing ? `git ls-files -- '*.jl'` : `git ls-tree -r --name-only $ref`
    success(pipeline(cmd; stdout = buf, stderr = devnull)) || return names
    for p in split(String(take!(buf)), '\n')
        endswith(p, ".jl") || continue
        src = gitshow(ref, p)
        src === nothing && continue
        for m in eachmatch(r"[\p{L}_][\p{L}\p{N}_!′]*", src)
            push!(names, Symbol(m.match))
        end
    end
    return names
end

# ---- trees -----------------------------------------------------------------------------

strip_lnn(x) = x
function strip_lnn(e::Expr)
    e.head === :macrocall &&
        return Expr(:macrocall, strip_lnn(e.args[1]), nothing, Any[strip_lnn(a) for a in e.args[3:end]]...)
    return Expr(e.head, Any[strip_lnn(a) for a in e.args if !(a isa LineNumberNode)]...)
end

macroargs(e::Expr) = e.args[3:end]
macroname(e) = e isa Expr && e.head === :macrocall ? e.args[1] : nothing
istestset(e) = macroname(e) === Symbol("@testset")
isdoc(e) = (m = macroname(e); m isa GlobalRef ? m.name === Symbol("@doc") : m === Symbol("@doc"))
isstringish(x) = x isa String || (x isa Expr && x.head === :string)
interpolations(e) = e isa Expr && e.head === :string ? Any[a for a in e.args if !(a isa String)] : Any[]
exec_blocks(src) = [replace(m.match, r"(?m)^[ \t]*#[ \t]?" => "") for m in eachmatch(EXEC_FENCE, replace(src, "\r\n" => "\n"))]

"The name a top-level function definition defines, or `nothing`."
function defined_function(st)
    st isa Expr || return nothing
    isdoc(st) && return defined_function(macroargs(st)[end])
    if st.head === :function || (st.head === :(=) && st.args[1] isa Expr && st.args[1].head in (:call, :where))
        sig = st.args[1]
        while sig isa Expr && sig.head in (:where, :(::))
            sig = sig.args[1]
        end
        sig isa Expr && sig.head === :call && sig.args[1] isa Symbol && return sig.args[1]
    end
    return nothing
end

# ---- the allowlist for inserted code ----------------------------------------------------

"Names the code assigns or binds (assignment targets, local functions, loop variables, arguments)."
function bound_names!(s::Set{Symbol}, e)
    e isa Expr || return s
    if e.head === :(=) || e.head === :function
        lhs_bind!(s, e.args[1])
    elseif e.head === :for
        it = e.args[1]
        for spec in (it isa Expr && it.head === :block ? it.args : (it,))
            spec isa Expr && spec.head === :(=) && lhs_bind!(s, spec.args[1])
        end
    elseif e.head === :->
        lhs_bind!(s, e.args[1])
    elseif e.head === :generator
        for spec in e.args[2:end]
            spec isa Expr && spec.head === :(=) && lhs_bind!(s, spec.args[1])
        end
    end
    foreach(a -> bound_names!(s, a), e.args)
    return s
end
function lhs_bind!(s, l)
    if l isa Symbol
        push!(s, l)
    elseif l isa Expr && l.head in (:tuple, :parameters, :call, :where, :(::), :kw, :...)
        args = l.head === :call ? l.args : l.args
        for a in args
            lhs_bind!(s, a)
        end
    end
end

"Is `x` a value the inserted code itself created: a local, or a call of a local function?"
function fresh_value(x, locals)
    x isa Symbol && return x in locals
    x isa Expr && x.head === :call && x.args[1] isa Symbol && return x.args[1] in locals
    return false
end

"""
Why the inserted code `e` is not allowed, or `nothing`. `locals` are the names the inserted
code binds; `allow_return` is true inside a new top-level function; `assign` is false for a
line added to an existing testset.
"""
function check_new(e, locals::Set{Symbol}; allow_return = false, assign = true)
    if e isa Symbol
        e in DENY_NAMES && return "uses `$(e)`"
        endswith(string(e), "!") && !(e in locals) && return "uses the mutating function `$(e)` as a value"
        return nothing
    end
    e isa QuoteNode && return e.value isa Symbol ? nothing : "a quoted expression"
    e isa Expr || return (e isa Union{Number, String, Char, Bool, Nothing} ? nothing : "a literal of type $(typeof(e))")
    h = e.head
    h in NEW_CODE_HEADS || return "`$(h)` is not allowed in inserted code"
    h === :return && !allow_return && return "`return` outside a new function"
    if h === :macrocall
        m = e.args[1]
        m in NEW_CODE_MACROS || return "macro `$(m)` is not allowed in inserted code"
        if m in (Symbol("@r_str"), Symbol("@v_str"))
            all(a -> a isa String || a === nothing, e.args[3:end]) || return "a string macro with code"
            return nothing
        end
        for a in macroargs(e)
            # `@test a ≈ b atol = 1`: a keyword of the macro, not an assignment
            if m !== Symbol("@testset") && a isa Expr && a.head === :(=) && a.args[1] isa Symbol
                a = a.args[2]
            end
            r = check_new(a, locals; allow_return, assign)
            r === nothing || return r
        end
        return nothing
    end
    if h === :.
        # field or module access `a.b`, or broadcast `f.(args)`
        if length(e.args) == 2 && e.args[2] isa QuoteNode
            b = e.args[1]
            b isa Symbol && b in DENY_MODULES && return "access through `$(b)`"
            q = e.args[2].value
            q isa Symbol && (q in DENY_NAMES || endswith(string(q), "!")) &&
                return "uses `$(b).$(q)` as a value"
            return check_new(b, locals; allow_return, assign)
        end
        return check_call(e.args[1], e.args[2] isa Expr ? e.args[2].args : Any[], locals; allow_return, assign)
    end
    if h === :call
        return check_call(e.args[1], e.args[2:end], locals; allow_return, assign)
    end
    if h in (:(=), :function)
        assign || return "an added line inside an existing testset assigns"
        l = e.args[1]
        l isa Symbol || (l isa Expr && l.head in (:tuple, :call, :where, :(::))) ||
            return "assignment into `$(l)`"
        if l isa Expr && l.head in (:call, :where)          # a local function: check its body only
            return check_new(e.args[2], locals; allow_return = true, assign)
        end
        return check_new(e.args[2], locals; allow_return, assign)
    end
    for a in e.args
        r = check_new(a, locals; allow_return, assign)
        r === nothing || return r
    end
    return nothing
end

function check_call(f, args, locals; allow_return, assign)
    # the callee
    if f isa Symbol
        f in DENY_NAMES && return "calls `$(f)`"
        if endswith(string(f), "!") && !(f in locals)
            pos = [a for a in args if !(a isa Expr && a.head in (:parameters, :kw))]
            (!isempty(pos) && fresh_value(pos[1], locals)) ||
                return "calls `$(f)` on something the inserted code did not create"
        end
    elseif f isa Expr && f.head === :. && length(f.args) == 2 && f.args[2] isa QuoteNode
        b, q = f.args[1], f.args[2].value
        (b isa Symbol && b in DENY_MODULES) && return "calls through `$(b)`"
        b isa Symbol || return "a callee `$(f)` that is not Module.name"
        q in DENY_NAMES && return "calls `$(f)`"
        if endswith(string(q), "!")
            pos = [a for a in args if !(a isa Expr && a.head in (:parameters, :kw))]
            (!isempty(pos) && fresh_value(pos[1], locals)) ||
                return "calls `$(f)` on something the inserted code did not create"
        end
    else
        return "a computed callee `$(f)`"
    end
    for a in args
        r = check_new(a, locals; allow_return, assign)
        r === nothing || return r
    end
    return nothing
end

# ---- comparison ------------------------------------------------------------------------

mutable struct Result
    kinds::Set{Symbol}
    reasons::Vector{String}
    fresh::Set{Symbol}          # names no file at the base mentions (top-level functions may use them)
    newfuns::Set{Symbol}        # names this file's insertions define
end
fail!(r, msg) = (push!(r.reasons, msg); false)
summ(x) = (s = string(x); s = replace(s, r"\s+" => " "); s[1:min(end, 70)])

"Compare a prose argument (a direct String argument of a prose sink)."
function prose!(r, o, n, where_)
    isequal(o, n) && return true
    (isstringish(o) && isstringish(n)) || return code!(r, o, n, where_)
    isequal(interpolations(o), interpolations(n)) || return fail!(r, "$where_: an interpolated expression in prose changed")
    push!(r.kinds, :wording)
    return true
end

"Compare the value of a pinned constant: literals may change, structure and keys may not."
function pin!(r, o, n, where_)
    isequal(o, n) && return true
    if (o isa String && n isa String) || (o isa Number && n isa Number && !(o isa Bool) && !(n isa Bool))
        push!(r.kinds, :pin)
        return true
    end
    (o isa Expr && n isa Expr && o.head === n.head && length(o.args) == length(n.args) && o.head !== :macrocall) ||
        return fail!(r, "$where_: the structure of a pinned constant changed")
    if o.head === :call && o.args[1] === :(=>)
        isequal(o.args[2], n.args[2]) || return fail!(r, "$where_: a pinned key changed")
        return pin!(r, o.args[3], n.args[3], where_)
    end
    isequal(o.args[1], n.args[1]) || o.head !== :call || return fail!(r, "$where_: a call in a pinned constant changed")
    for (x, y) in zip(o.args, n.args)
        pin!(r, x, y, where_) || return false
    end
    return true
end

"Compare code: equal, except for prose sinks, pinned constants, and allowed insertions."
function code!(r, o, n, where_; pins = Set{Symbol}())
    isequal(o, n) && return true
    (o isa Expr && n isa Expr && o.head === n.head) ||
        return fail!(r, "$where_: `$(summ(o))` became `$(summ(n))`")
    h = o.head
    if h === :macrocall
        isequal(o.args[1], n.args[1]) || return fail!(r, "$where_: macro $(o.args[1]) became $(n.args[1])")
        oa, na = macroargs(o), macroargs(n)
        length(oa) == length(na) || return fail!(r, "$where_: arguments of $(o.args[1]) changed")
        if istestset(o)
            for (i, (x, y)) in enumerate(zip(oa, na))
                if i == 1 && isstringish(x)
                    prose!(r, x, y, "$where_ @testset name") || return false
                elseif i == length(oa)
                    testset_body!(r, x, y, "$where_ @testset") || return false
                else
                    code!(r, x, y, where_) || return false
                end
            end
            return true
        end
        if isdoc(o) && length(oa) == 2
            prose!(r, oa[1], na[1], "$where_ docstring") || return false
            return code!(r, oa[2], na[2], where_; pins)
        end
        return args!(r, oa, na, where_)                     # every other macro, string macros included
    end
    # a prose sink: every argument is a string (so `println(io, …)` writing a file is code)
    if h === :call && (o.args[1] in (:println, :print) || isequal(o.args[1], :(Markdown.parse))) &&
       isequal(o.args[1], n.args[1]) && length(o.args) == length(n.args) >= 2 &&
       all(isstringish, o.args[2:end]) && all(isstringish, n.args[2:end])
        for (x, y) in zip(o.args[2:end], n.args[2:end])
            prose!(r, x, y, where_) || return false
        end
        return true
    end
    if h === :const && o.args[1] isa Expr && o.args[1].head === :(=) && n.args[1] isa Expr && n.args[1].head === :(=)
        name = o.args[1].args[1]
        isequal(name, n.args[1].args[1]) || return fail!(r, "$where_: const $(name) renamed")
        name isa Symbol && name in pins && return pin!(r, o.args[1].args[2], n.args[1].args[2], "$where_ const $(name)")
        return code!(r, o.args[1].args[2], n.args[1].args[2], "$where_ const $(name)")
    end
    return args!(r, o.args, n.args, where_)
end

function args!(r, oa, na, where_)
    length(oa) == length(na) || return fail!(r, "$where_: an argument, element or statement was added or removed")
    for (x, y) in zip(oa, na)
        code!(r, x, y, where_) || return false
    end
    return true
end

"A `@testset` body: a block, or a `for` whose body is a block. Lines may be added directly in it."
function testset_body!(r, o, n, where_)
    if o isa Expr && n isa Expr && o.head === :for && n.head === :for
        code!(r, o.args[1], n.args[1], where_) || return false
        return testset_body!(r, o.args[2], n.args[2], where_)
    end
    (o isa Expr && n isa Expr && o.head === :block && n.head === :block) || return code!(r, o, n, where_)
    return statements!(r, o.args, n.args, where_; inner = true)
end

"Statement lists: every old statement matches, in order; the rest are checked insertions."
function statements!(r, oa, na, where_; inner, pins = Set{Symbol}())
    j = 1
    for x in oa
        matched = false
        while j <= length(na)
            probe = Result(Set{Symbol}(), String[], r.fresh, r.newfuns)
            if code!(probe, x, na[j], where_; pins)
                union!(r.kinds, probe.kinds)
                matched = true
                j += 1
                break
            end
            ins = Result(Set{Symbol}(), String[], r.fresh, r.newfuns)
            if !insertion!(ins, na[j], where_; inner)
                same = x isa Expr && na[j] isa Expr && x.head === na[j].head && !isempty(probe.reasons)
                append!(r.reasons, same ? probe.reasons : ins.reasons)
                return false
            end
            union!(r.kinds, ins.kinds)
            j += 1
        end
        matched || return fail!(r, "$where_: a statement was removed or changed: `$(summ(x))`")
    end
    while j <= length(na)
        insertion!(r, na[j], where_; inner) || return false
        j += 1
    end
    return true
end

function insertion!(r, y, where_; inner)
    if inner
        macroname(y) in INNER_INSERT_MACROS ||
            return fail!(r, "$where_: only @test or @test_throws lines may be added to an existing testset: `$(summ(y))`")
        why = check_new(y, Set{Symbol}(); assign = false)
    elseif istestset(y)
        why = check_new(y, bound_names!(Set{Symbol}(), y))
    elseif (f = defined_function(y)) !== nothing
        (f in r.fresh) || return fail!(r, "$where_: the new function `$(f)` is not new to the repository, or is bound in Base, Core or Test")
        f in r.newfuns && return fail!(r, "$where_: `$(f)` is defined twice by the insertions")
        push!(r.newfuns, f)
        d = isdoc(y) ? macroargs(y)[end] : y
        isdoc(y) && !(isstringish(macroargs(y)[1])) && return fail!(r, "$where_: a computed docstring")
        sig, body = d.args[1], d.args[2]
        locals = Set{Symbol}()
        lhs_bind!(locals, sig)
        bound_names!(locals, body)
        why = check_sig(sig, locals)
        why === nothing && (why = check_new(body, locals; allow_return = true))
    else
        return fail!(r, "$where_: an inserted top-level statement must be a @testset or a new function: `$(summ(y))`")
    end
    why === nothing || return fail!(r, "$where_: inserted code $why")
    push!(r.kinds, :additive)
    return true
end

"Default values and type annotations in a new function's signature go through the allowlist too."
function check_sig(sig, locals)
    sig isa Expr || return nothing
    for a in (sig.head === :call ? sig.args[2:end] : sig.args)
        if a isa Expr && a.head === :kw
            r = check_new(a.args[2], locals)
            r === nothing || return r
        elseif a isa Expr
            r = check_sig(a, locals)
            r === nothing || return r
        end
    end
    return nothing
end

# ---- driver ----------------------------------------------------------------------------

const MAINT = (:maintainer, Set{Symbol}())

function classify(path, old_src, new_src, pins; fresh = Set{Symbol}(), newfuns = Set{Symbol}())
    endswith(path, ".jl") || return (MAINT..., ["not a Julia file (data records always need the maintainer)"])
    new_src === nothing && return (MAINT..., ["the frozen file was removed"])
    exec_blocks(old_src) == exec_blocks(new_src) ||
        return (MAINT..., ["an executable Documenter block (jldoctest, @example, @eval, …) changed"])
    o = n = nothing
    try
        o = strip_lnn(Meta.parseall(old_src))
        n = strip_lnn(Meta.parseall(new_src))
    catch err
        return (MAINT..., ["does not parse: $(sprint(showerror, err))"[1:min(end, 200)]])
    end
    bad(t) = any(x -> x isa Expr && x.head in (:error, :incomplete), t.args)
    (bad(o) || bad(n)) && return (MAINT..., ["parse error"])
    fr = Set(x for x in fresh if !isdefined(Base, x) && !isdefined(Core, x) && !isdefined(Test, x))
    r = Result(Set{Symbol}(), String[], fr, newfuns)
    ok = statements!(r, o.args, n.args, path; inner = false, pins)
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
    newentries = newtoml === nothing ? Dict{String, Any}() : Dict(f["path"] => f for f in TOML.parse(newtoml)["file"])
    known = repo_identifiers(oldref)
    fresh = Set{Symbol}()            # computed per candidate name: not in `known`
    newfuns = Set{Symbol}()
    worst = 0
    nchanged = 0
    for f in entries
        p = normpath(joinpath(TESTDIR, f["path"]))
        old_src = gitshow(oldref, p)
        new_src = gitshow(newref, p)
        ne = get(newentries, f["path"], nothing)
        oldpins = Set(Symbol.(get(f, "pins", String[])))
        pinschanged = ne !== nothing && Set(Symbol.(get(ne, "pins", String[]))) != oldpins
        old_src == new_src && ne !== nothing && !pinschanged && continue
        nchanged += 1
        if ne === nothing
            verdict, kinds, reasons = MAINT..., ["dropped from frozen.toml (removed or renamed)"]
        elseif pinschanged
            verdict, kinds, reasons = MAINT..., ["its `pins` list in frozen.toml changed"]
        else
            cand = new_src === nothing ? Set{Symbol}() :
                   Set(Symbol(m.match) for m in eachmatch(r"[\p{L}_][\p{L}\p{N}_!′]*", new_src))
            verdict, kinds, reasons = classify(p, old_src, new_src, oldpins; fresh = setdiff(cand, known), newfuns)
        end
        if verdict === :auto
            println("AUTO        ", f["path"], "  (", join(sort!(collect(kinds)), ", "), ")")
        else
            worst = 1
            println("MAINTAINER  ", f["path"])
            foreach(x -> println("    ", x), reasons)
        end
    end
    nchanged == 0 && println("no frozen file changed")
    return worst
end

if abspath(PROGRAM_FILE) == @__FILE__()
    exit(main(ARGS))
end
