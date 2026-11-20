# Shared 6-package QA helpers (Potts, CorePotts, LatticeFields, LatticePDE,
# MakiePotts, PottsModels). Included by each package's QA test file/setup.

if !isdefined(@__MODULE__, :_POTTS_QA_COMMON_DEFINED)
    const _POTTS_QA_COMMON_DEFINED = true

    const _QA_DEFAULT_BANNED = r"\b(Jiang|Merks|Bauer|Graner|Glazier|Fortuna|Hogeweg|Szabo|Marée|FBCA|OpenVT)\b"

    """
        qa_aqua(mod; ambiguities = true, persistent_tasks = true,
                deps_compat = (; check_extras = true), kwargs...)

    Run `Aqua.test_all` with `ambiguities = true` enabled by default across all six
    packages. Pass `persistent_tasks = false` or `deps_compat = (; check_extras = false)`
    only where justified and documented at the call site.
    """
    function qa_aqua(
            mod::Module;
            ambiguities = true,
            persistent_tasks = true,
            deps_compat = (; check_extras = true),
            kwargs...
        )
        Aqua = Base.require(Base.PkgId(Base.UUID("4c88cf16-eb10-579e-8560-4a9242c79595"), "Aqua"))
        Base.invokelatest(Aqua.test_all, mod; ambiguities, persistent_tasks, deps_compat, kwargs...)
        return nothing
    end

    const _QA_AQUA = Base.PkgId(Base.UUID("4c88cf16-eb10-579e-8560-4a9242c79595"), "Aqua")
    const _QA_TEST = Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test")

    # The functions and types of `owners` and of their submodules.
    function _qa_owned(owners)
        own = Any[]
        seen = Set{Module}()
        function walk(o::Module)
            o in seen && return
            push!(seen, o)
            for n in names(o; all = true, imported = false)
                isdefined(o, n) || continue
                v = getfield(o, n)
                if v isa Module
                    v !== o && parentmodule(v) === o && walk(v)
                elseif v isa Function || v isa Type
                    push!(own, v)
                end
            end
            return
        end
        foreach(walk, owners)
        return own
    end

    """
        qa_pirates(ext; owners) -> Vector{Method}

    The methods of module `ext` that Aqua's piracy hunt flags, with the functions and types of
    `owners` (and their submodules) treated as `ext`'s own. Empty when `ext` pirates nothing.
    """
    function qa_pirates(ext::Module; owners)
        Aqua = Base.require(_QA_AQUA)
        return Base.invokelatest(Aqua.Piracy.hunt, ext; treat_as_own = _qa_owned(owners))
    end

    """
        qa_extension_piracies(mod; owners = (mod,)) -> Vector{Module}

    Aqua's piracy check on each loaded package extension of `mod` (`Aqua.test_all`
    does not look inside extensions), with the functions and types of `owners` (and their
    submodules) treated as the extension's own: an extension may extend its parent's
    functions and add methods on its parent's types, but not add a foreign function's
    method on foreign types. Returns the extensions checked; load the trigger packages first.
    """
    function qa_extension_piracies(mod::Module; owners = (mod,))
        Test = Base.require(_QA_TEST)
        TOML = Base.require(Base.PkgId(Base.UUID("fa267f1f-6049-4f14-aa54-33bafae1ed76"), "TOML"))
        project = Base.invokelatest(TOML.parsefile, joinpath(pkgdir(mod), "Project.toml"))
        exts = Module[]
        for name in sort!(collect(keys(get(project, "extensions", Dict{String, Any}()))))
            ext = Base.get_extension(mod, Symbol(name))
            ext === nothing && continue
            push!(exts, ext)
            pirates = qa_pirates(ext; owners)
            isempty(pirates) || @error "type piracy in the extension $name" pirates
            Test.@test isempty(pirates)
        end
        return exts
    end

    """
        qa_piracy_control()

    The negative control of [`qa_extension_piracies`](@ref): a scratch parent module and a
    scratch extension of it. The extension's method of a parent function and its method of a
    foreign function on a parent type are not flagged; its method of a foreign function on
    foreign types (`Base.nameof` on a `Pair{Char, Int8}`) is the one pirate found. (Two scratch
    modules count as one package, so the control cannot show what the owners add; the
    extension checks of the packages do, by passing.)
    """
    function qa_piracy_control()
        Test = Base.require(_QA_TEST)
        parent = Module(:ScratchParent)
        Core.eval(parent, :(struct Owned end; owned_function(x) = x))
        ext = Module(:ScratchParentExt)
        Core.eval(ext, :(const P = $parent))
        Core.eval(ext, :(P.owned_function(::Int) = 1))
        Core.eval(ext, :(Base.show(io::IO, ::P.Owned) = print(io, "owned")))
        Core.eval(ext, :(Base.nameof(::Pair{Char, Int8}) = :pirate))
        pirates = qa_pirates(ext; owners = (parent,))
        Test.@test length(pirates) == 1 && only(pirates).name === :nameof
        return nothing
    end

    const _QA_JET = Base.PkgId(Base.UUID("c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"), "JET")

    """
        qa_jet_reports(mod) -> (; errors, locals)

    JET's error analysis of the whole package `mod` (`JET.report_package` in `:typo` mode, with
    `target_modules = (mod,)`): references to undefined names and fields. `locals` are the
    reports of a local variable that "may be" or "is not" defined; JET does not follow a
    variable that a closure captures and the enclosing function assigns again (a `Core.Box`),
    so these are reported where the code is correct, and `qa_jet_package` does not fail on
    them. `errors` are the other reports, each as its message text.
    """
    function qa_jet_reports(mod::Module)
        JET = Base.require(_QA_JET)
        result = Base.invokelatest(
            JET.report_package, mod; target_modules = (mod,), mode = :typo, toplevel_logger = nothing
        )
        reports = Base.invokelatest(JET.get_reports, result)
        is_local(r) = r isa JET.UndefVarErrorReport && r.var isa Symbol
        message(r) = sprint(JET.JETInterface.print_report_message, r)
        return (;
            errors = String[Base.invokelatest(message, r) for r in reports if !is_local(r)],
            locals = String[Base.invokelatest(message, r) for r in reports if is_local(r)],
        )
    end

    """
        qa_jet_package(mod; broken = Pair{Regex, String}[])

    Fail on every report of [`qa_jet_reports`](@ref) that is not a local variable. `broken`
    lists known reports as `pattern => reason`: the reports a pattern matches are a
    `@test_broken` (which turns into an error, an unexpected pass, once the report is gone).
    """
    function qa_jet_package(mod::Module; broken = Pair{Regex, String}[])
        Test = Base.require(_QA_TEST)
        (; errors) = qa_jet_reports(mod)
        unexpected = filter(m -> !any(((p, _),) -> occursin(p, m), broken), errors)
        isempty(unexpected) || @error "JET reports in $mod" unexpected
        Test.@test isempty(unexpected)
        for (p, _) in broken
            Test.@test_broken !any(m -> occursin(p, m), errors)
        end
        return nothing
    end

    """
        qa_jet_control()

    The negative control of [`qa_jet_package`](@ref): a scratch package, written to a
    temporary directory and loaded, whose functions read an undefined global and a field their
    argument's type does not have (through `getfield`: JET does not report `p.y` on Julia
    1.13, where `getproperty` throws the `FieldError`). Both are reported.
    """
    function qa_jet_control()
        Test = Base.require(_QA_TEST)
        mktempdir() do dir
            uuid = Base.UUID("6a1c4b2e-9d3f-4e8a-b7c5-0f2e1d3c4b5a")
            write(joinpath(dir, "Project.toml"), "name = \"ScratchJET\"\nuuid = \"$uuid\"\n")
            mkdir(joinpath(dir, "src"))
            write(
                joinpath(dir, "src", "ScratchJET.jl"), """
                module ScratchJET
                struct Point
                    x::Float64
                end
                reads_undefined(p::Point) = p.x + undefined_global_name
                reads_missing_field(p::Point) = getfield(p, :y)
                end
                """
            )
            pushfirst!(LOAD_PATH, dir)
            try
                scratch = Base.require(Base.PkgId(uuid, "ScratchJET"))
                (; errors) = qa_jet_reports(scratch)
                Test.@test any(m -> occursin("undefined_global_name", m), errors)
                Test.@test any(m -> occursin("no field `y`", m), errors)
            finally
                filter!(!=(dir), LOAD_PATH)
            end
        end
        return nothing
    end

    # `@inbounds` hides an out-of-bounds read unless Julia runs with `--check-bounds=yes`
    _qa_read_past_end(v::Vector{Int}) = @inbounds v[length(v) + 1]

    """
        qa_check_bounds_control()

    The negative control of the check-bounds lanes. Under `--check-bounds=yes`, a read one past
    the end of a vector inside `@inbounds` throws a `BoundsError`. With the environment variable
    `POTTS_CHECK_BOUNDS_LANE=true` (set by the CI lanes), the flag itself must be on, so a lane
    that lost it fails. Without the flag the read is not made (it is undefined behavior).
    """
    function qa_check_bounds_control()
        Test = Base.require(_QA_TEST)
        on = Base.JLOptions().check_bounds == 1
        get(ENV, "POTTS_CHECK_BOUNDS_LANE", "false") == "true" && Test.@test on
        on && Test.@test_throws BoundsError _qa_read_past_end([1, 2, 3])
        return on
    end

    """
        qa_explicit_imports(mod; nonpublic_explicit = (), nonpublic_qualified = (),
                            skip_owners = false)

    Run the five `ExplicitImports` hygiene checks on `mod` (including any loaded
    extensions).
    """
    function qa_explicit_imports(
            mod::Module;
            nonpublic_explicit = (),
            nonpublic_qualified = (),
            skip_owners = false
        )
        EI = Base.require(Base.PkgId(Base.UUID("7d51a73a-1435-4ff3-83d9-f097790105c7"), "ExplicitImports"))
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        Test.@test Base.invokelatest(EI.check_no_implicit_imports, mod) === nothing
        Test.@test Base.invokelatest(EI.check_all_explicit_imports_are_public, mod; ignore = nonpublic_explicit) === nothing
        Test.@test Base.invokelatest(EI.check_no_stale_explicit_imports, mod) === nothing
        if !skip_owners
            Test.@test Base.invokelatest(EI.check_all_qualified_accesses_via_owners, mod) === nothing
        end
        Test.@test Base.invokelatest(EI.check_all_qualified_accesses_are_public, mod; ignore = nonpublic_qualified) === nothing
        return nothing
    end

    function _qa_collect_docs_coverage(docs_dir::AbstractString)
        autodoc_modules = Set{String}()
        doc_entries = Set{String}()
        scan_dirs = [joinpath(docs_dir, "src"), joinpath(docs_dir, "models")]
        for d in scan_dirs
            isdir(d) || continue
            for (root, _, files) in walkdir(d), f in files
                (endswith(f, ".md") || endswith(f, ".jl")) || continue
                text = read(joinpath(root, f), String)
                for m in eachmatch(r"```@autodocs\s+(.*?)```"s, text)
                    mm = match(r"Modules\s*=\s*\[([^\]]+)\]", m[1])
                    mm === nothing && continue
                    for item in split(mm[1], ',')
                        s = strip(item)
                        isempty(s) || push!(autodoc_modules, s)
                    end
                end
                for m in eachmatch(r"```@docs\s*\n(.*?)```"s, text)
                    for line in split(m[1], '\n')
                        s = strip(line)
                        isempty(s) || push!(doc_entries, s)
                    end
                end
            end
        end
        return autodoc_modules, doc_entries
    end

    """
        qa_api_docs(mod; submodules = (), docs_dir = nothing, check_docs_blocks = true,
                    doc_module_names = String[], extra_documented = Symbol[])

    Verify that every public name in `mod` (and `submodules`) has a docstring via
    `Docs.undocumented_names`, and when `check_docs_blocks` is true, verify that `mod`
    is covered by `@autodocs` or `@docs` blocks under `docs_dir`.
    """
    function qa_api_docs(
            mod::Module;
            submodules = (),
            docs_dir = nothing,
            check_docs_blocks::Bool = true,
            doc_module_names::AbstractVector{<:AbstractString} = String[],
            extra_documented::AbstractVector{Symbol} = Symbol[]
        )
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        Test.@test isempty(Docs.undocumented_names(mod; private = false))
        for sub in submodules
            Test.@test isempty(Docs.undocumented_names(sub; private = false))
        end
        if check_docs_blocks && docs_dir !== nothing && isdir(docs_dir)
            autodoc_modules, doc_entries = _qa_collect_docs_coverage(docs_dir)
            candidates = isempty(doc_module_names) ? [string(nameof(mod))] : collect(String, doc_module_names)
            if !any(in(autodoc_modules), candidates)
                public_names = [
                    n for n in names(mod; all = false, imported = false)
                        if n !== nameof(mod) && !(n in extra_documented)
                ]
                prefix = string(nameof(mod), ".")
                missing_docs = [
                    n for n in public_names
                        if !(string(n) in doc_entries) && !((prefix * string(n)) in doc_entries)
                ]
                Test.@test isempty(missing_docs)
            end
        end
        return nothing
    end

    """
        qa_source_rules(pkg_root; banned_pattern = _QA_DEFAULT_BANNED,
                        check_no_generated = true, exclude_files = String[])

    Verify that `src/` and `test/` files in `pkg_root` do not contain model/author names
    matching `banned_pattern`, and (when `check_no_generated = true`) that `src/` contains
    no `@generated` definitions.
    """
    function qa_source_rules(
            pkg_root::AbstractString;
            banned_pattern::Regex = _QA_DEFAULT_BANNED,
            check_no_generated::Bool = true,
            exclude_files::AbstractVector{<:AbstractString} = String[]
        )
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        excluded = Set(normpath.(exclude_files))
        files = [
            joinpath(d, f) for dir in ("src", "test")
                for (d, _, fs) in walkdir(joinpath(pkg_root, dir))
                for f in fs if endswith(f, ".jl")
        ]
        hits = [f for f in files if !(normpath(f) in excluded) && occursin(banned_pattern, read(f, String))]
        Test.@test isempty(hits)
        if check_no_generated
            src_prefix = normpath(joinpath(pkg_root, "src")) * Base.Filesystem.path_separator
            src_files = filter(f -> startswith(normpath(f), src_prefix), files)
            Test.@test !any(f -> occursin("@generated", read(f, String)), src_files)
        end
        return nothing
    end

    const _QA_STALE_FRONTEND_RE = r"\bfront[- ]end\s+[AB]\b|\bboth\s+front\s+ends\b|@bcs\b"

    function _qa_walk_ast_rules!(
            ex, line::Base.RefValue{Int},
            error_calls::Vector{Int}, bare_catches::Vector{Int}, non_assertion_invariants::Vector{Int};
            in_assertion::Bool = false
        )
        if ex isa LineNumberNode
            ex.line > 0 && (line[] = ex.line)
            return nothing
        elseif ex isa String
            !in_assertion && occursin("please report", ex) && push!(non_assertion_invariants, line[])
            return nothing
        end
        ex isa Expr || return nothing
        # Skip docstring text on `@doc` macrocalls; scan only the documented expression.
        if ex.head === :macrocall && length(ex.args) >= 4 && ex.args[1] == GlobalRef(Core, Symbol("@doc"))
            _qa_walk_ast_rules!(ex.args[end], line, error_calls, bare_catches, non_assertion_invariants; in_assertion)
            return nothing
        end
        next_assertion = in_assertion
        if ex.head === :call && !isempty(ex.args)
            callee = ex.args[1]
            if callee === :error || callee == :(Base.error) || callee === :ErrorException || callee == :(Base.ErrorException)
                push!(error_calls, line[])
            elseif callee === :AssertionError || callee == :(Base.AssertionError)
                next_assertion = true
            end
        elseif ex.head === :try && length(ex.args) >= 3
            # `try ... catch; ... end` leaves the catch binding slot `ex.args[2] === false`
            # with a catch body (`ex.args[3] !== false`); `try ... finally` has `ex.args[3] === false`.
            ex.args[2] === false && ex.args[3] !== false && push!(bare_catches, line[])
        end
        for a in ex.args
            _qa_walk_ast_rules!(a, line, error_calls, bare_catches, non_assertion_invariants; in_assertion = next_assertion)
        end
        return nothing
    end

    function _qa_scan_error_rules(text::AbstractString; allow_bcs::Bool = false, allow_bcs_test::Bool = false)
        ast = Base.Meta.parseall(text)
        error_calls = Int[]
        bare_catches = Int[]
        non_assertion_invariants = Int[]
        _qa_walk_ast_rules!(ast, Ref(1), error_calls, bare_catches, non_assertion_invariants)
        stale_terms = Int[]
        for (i, ln) in enumerate(eachsplit(text, '\n'; keepempty = true))
            if occursin(_QA_STALE_FRONTEND_RE, ln)
                !occursin(r"\bfront[- ]end\s+[AB]\b|\bboth\s+front\s+ends\b", ln) &&
                    ((allow_bcs && occursin("Symbol(\"@bcs\")", ln)) || allow_bcs_test) && continue
                push!(stale_terms, i)
            end
        end
        return (; error_calls, bare_catches, non_assertion_invariants, stale_terms)
    end

    _qa_invariants_match(found, reviewed) = sort(collect(String, found)) == sort(collect(String, reviewed))

    function _qa_collect_tree(pkg_root::AbstractString, allowed_bcs_files::AbstractVector{<:AbstractString})
        allowed_bcs = Set(normpath.(allowed_bcs_files))
        qa_self = normpath(joinpath(pkg_root, "test", "shared", "qa_common.jl"))

        bad_errors = String[]
        bad_catches = String[]
        bad_invariant_forms = String[]
        bad_stale = String[]
        found_invariants = String[]

        for dir in ("src", "ext", "test")
            root = joinpath(pkg_root, dir)
            isdir(root) || continue
            files = String[]
            for (d, _, fs) in walkdir(root), f in fs
                endswith(f, ".jl") && push!(files, joinpath(d, f))
            end
            sort!(files)
            for f in files
                nf = normpath(f)
                dir == "test" && nf == qa_self && continue
                rel = relpath(f, pkg_root)
                text = read(f, String)
                in_bcs = nf in allowed_bcs
                res = _qa_scan_error_rules(
                    text;
                    allow_bcs = dir != "test" && in_bcs,
                    allow_bcs_test = dir == "test" && in_bcs
                )
                for l in res.stale_terms
                    push!(bad_stale, "$rel:$l")
                end
                dir == "test" && continue
                for l in res.error_calls
                    push!(bad_errors, "$rel:$l")
                end
                for l in res.bare_catches
                    push!(bad_catches, "$rel:$l")
                end
                for l in res.non_assertion_invariants
                    push!(bad_invariant_forms, "$rel:$l")
                end
                for ln in eachsplit(text, '\n'; keepempty = true)
                    occursin("please report", ln) && push!(found_invariants, rel)
                end
            end
        end
        return (; bad_errors, bad_catches, bad_invariant_forms, bad_stale, found_invariants)
    end

    # qa_error_rules(pkg_root; reviewed_invariants = String[], allowed_bcs_files = String[])
    #
    # Verify that `src/` and `ext/` in `pkg_root` contain:
    # - no `error(...)`, `Base.error(...)`, or `ErrorException(...)` calls,
    # - no bare `catch` clauses (`try ... catch; ... end` without an exception binding),
    # - internal `"please report"` invariants thrown exclusively via `AssertionError` and
    #   matching `reviewed_invariants`,
    # that `src/`, `ext/`, and `test/` contain no stale front-end wording (a front end named by a
    # letter, "both front ends", "@bcs" outside the explicit legacy-section refusal), and run
    # negative controls proving every guard flags synthetic violations.
    function qa_error_rules(
            pkg_root::AbstractString;
            reviewed_invariants::AbstractVector{<:AbstractString} = String[],
            allowed_bcs_files::AbstractVector{<:AbstractString} = String[]
        )
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        (; bad_errors, bad_catches, bad_invariant_forms, bad_stale, found_invariants) =
            _qa_collect_tree(pkg_root, allowed_bcs_files)

        isempty(bad_errors) || @error "untyped error() / ErrorException calls" bad_errors
        isempty(bad_catches) || @error "bare catch clauses" bad_catches
        isempty(bad_invariant_forms) || @error "non-AssertionError invariant throws" bad_invariant_forms
        isempty(bad_stale) || @error "stale front-end terms" bad_stale
        Test.@test isempty(bad_errors)
        Test.@test isempty(bad_catches)
        Test.@test isempty(bad_invariant_forms)
        Test.@test isempty(bad_stale)
        Test.@test _qa_invariants_match(found_invariants, reviewed_invariants)

        # Negative controls: each guard flags synthetic scratch inputs and spares valid ones.
        err_neg = _qa_scan_error_rules(
            "f() = error(\"boom\")\ng() = Base.error(\"boom\")\nh() = throw(ErrorException(\"boom\"))\nk() = throw(Base.ErrorException(\"boom\"))"
        )
        Test.@test err_neg.error_calls == [1, 2, 3, 4]
        catch_neg = _qa_scan_error_rules("f() = try x() catch; 1 end")
        Test.@test length(catch_neg.bare_catches) == 1
        catch_ok = _qa_scan_error_rules("f() = try x() catch e; isfatal(e) && rethrow(); 1 end\ng() = try x() finally 1 end")
        Test.@test isempty(catch_ok.bare_catches)
        inv_form_neg = _qa_scan_error_rules("f() = throw(ArgumentError(\"bad (please report it)\"))")
        Test.@test inv_form_neg.non_assertion_invariants == [1]
        inv_form_ok = _qa_scan_error_rules("f() = throw(AssertionError(\"bad (please report it)\"))")
        Test.@test isempty(inv_form_ok.non_assertion_invariants)
        mktempdir() do tmp
            mkdir(joinpath(tmp, "src"))
            write(joinpath(tmp, "src", "planted.jl"), "f() = throw(AssertionError(\"bad (please report)\"))\n")
            planted = _qa_collect_tree(tmp, String[])
            Test.@test isempty(planted.bad_invariant_forms)
            Test.@test !_qa_invariants_match(planted.found_invariants, String[])
            Test.@test _qa_invariants_match(planted.found_invariants, ["src/planted.jl"])
        end
        stale_neg = _qa_scan_error_rules("# front " * "end A\nmsg = \"write @bcs: x\"")
        Test.@test stale_neg.stale_terms == [1, 2]
        bcs_neg = _qa_scan_error_rules("op === Symbol(\"@bcs\")"; allow_bcs = false)
        Test.@test bcs_neg.stale_terms == [1]
        bcs_ok = _qa_scan_error_rules("op === Symbol(\"@bcs\")"; allow_bcs = true)
        Test.@test isempty(bcs_ok.stale_terms)
        bcs_test_neg = _qa_scan_error_rules("msg = \"@bcs\""; allow_bcs_test = false)
        Test.@test bcs_test_neg.stale_terms == [1]
        bcs_test_ok = _qa_scan_error_rules("msg = \"@bcs\""; allow_bcs_test = true)
        Test.@test isempty(bcs_test_ok.stale_terms)
        bcs_test_fe = _qa_scan_error_rules("# front " * "end A"; allow_bcs_test = true)
        Test.@test bcs_test_fe.stale_terms == [1]
        return nothing
    end

    # ── Phase names ──────────────────────────────────────────────────────────────────────────
    # Development-process IDs (roadmap items, review rounds, design drafts) do not belong in
    # names, titles, comments or messages: a reader with no project history cannot decode them.
    # The pattern matches ID shapes only, never prose words. Each alternative is written in
    # pieces so that this file does not match itself. "round" and a number is not matched on
    # purpose: domain text uses it too (the rounds of an Eden growth).
    const _QA_PHASE_RE = Regex(
        join(
            (
                raw"\bP[0-9]+\.(?:[0-9]+[a-z]{0,2}[0-9]?[a-z]?|ci)\b",        # roadmap items
                raw"\b[pP][0-9]+_[0-9]+[a-z0-9]*",                           # the same in file names
                raw"\b[pP][0-9]{2,4}[A-Za-z]{1,3}[0-9]?_",                   # identifier prefixes
                raw"\b[pP][0-9]{2,4}[a-z]{1,3}[0-9]?[A-Z]",                  # and CamelCase names
                raw"\bF[0-9]-(?:[A-EG-Z]?[0-9]+[a-z]?)\b",                   # field-compiler items
                raw"\bF[0-9] (?:design|round|review)\b", raw"\bv[0-9] §",    # design drafts
                raw"\bTS(?:-R)?[0-9]+[a-z]?\b",                              # test-suite passes
                raw"\bM[0-9]+\.[0-9]+[a-z]?\b",                              # milestones
                raw"\breview r[0-9]\b", raw"\br[0-9] [SMN][0-9]+\b", raw"\bR[0-9]-[MSN][0-9]+\b",
                raw"\bbatch(?:-end| [0-9]+) review\b",                       # review rounds and findings
                raw"\breview (?:[SMN][0-9]+|[0-9]+|B[0-9])", raw"\(B[0-9]\)",
                raw"\bP[0-9]-(?:mg|rev|mtk|wlite)",                           # design studies
                "\\bfront " * raw"end [AB]\b", "\\bW-" * raw"lite\b",        # superseded design labels
                "\\bcutover " * raw"C[0-9]+\b", raw"\bC[0-9]{1,2} (?:gate|review)\b",
                raw"\bPG-[0-9]\b", raw"\bP[0-9]-gates\b",
                raw"\bD-[A-Z][0-9]?[a-z]?-?[0-9]+[a-z]?\b",                  # phase-scoped decision IDs
            ), "|"
        )
    )

    """
        qa_phase_tokens(text) -> Vector{String}

    The development-process IDs in `text`, in order: roadmap items and their file-name and
    identifier forms, field-compiler and test-suite items, milestones, review rounds and
    findings, design-draft sections, superseded design labels, and phase-scoped decision IDs.
    Plain decision IDs (`D-` and three digits) are not matched here; see
    [`qa_decision_ids`](@ref). The controls in `test/qa_tests.jl` show the shapes.
    """
    qa_phase_tokens(text::AbstractString) = String[m.match for m in eachmatch(_QA_PHASE_RE, text)]

    # Plain decision IDs may stay in code comments, as links to the rationale in
    # docs/design/DECISIONS.md. Messages, docstrings and docs pages say the reason in words.
    const _QA_DECISION_RE = r"\bD-[0-9]{3}\b"
    const _QA_CODE_EXTS = (".jl", ".sh", ".toml", ".yml", ".yaml", ".py")

    # A file whose comments are not code comments: docs pages, READMEs, and the Literate pages
    # (reproductions and model pages), whose comments render as the page's prose.
    function _qa_prose_file(p::AbstractString)
        any(e -> endswith(p, e), _QA_CODE_EXTS) || return true
        occursin(r"^lib/[^/]+/reproductions/[^/]+\.jl$", p) && return true
        return occursin(r"^docs/models/[^/]+\.jl$", p) && basename(p) != "render.jl"
    end

    """
        qa_decision_ids(line; prose = false) -> Vector{String}

    The plain decision IDs (`D-` and three digits) in `line` that are not in a comment: every
    one when `prose`, otherwise those before the line's first `#`. A `#` inside a string ends
    the code part too, so an ID after it is missed; docstring lines have no `#` as a rule.
    """
    function qa_decision_ids(line::AbstractString; prose::Bool = false)
        h = prose ? nothing : findfirst('#', line)
        return String[m.match for m in eachmatch(_QA_DECISION_RE, line) if h === nothing || m.offset < h]
    end

    const _QA_PHASE_EXCLUDE = ("docs/design/", ".claude/", "lib/PottsModels/reproductions/data/")
    const _QA_PHASE_ALLOWLIST = "test/phase_names_allow.txt"

    function _qa_phase_in_scope(p::AbstractString)
        if any(e -> startswith(p, e), _QA_PHASE_EXCLUDE) || basename(p) == "CLAUDE.md" || p == _QA_PHASE_ALLOWLIST
            return false
        elseif startswith(basename(p), "README") || startswith(basename(p), "CONTRIBUTING") || p == "docs/make.jl"
            return true
        elseif any(d -> startswith(p, d), ("src/", "ext/", "test/", "benchmark/", "docs/src/", "docs/models/", "docs/status/", "tools/", ".github/"))
            return true
        end
        return occursin(r"^lib/[^/]+/(?:src|ext|test)/", p) || occursin(r"^lib/[^/]+/reproductions/[^/]+\.jl$", p)
    end

    function _qa_phase_files(root::AbstractString)
        git = Sys.which("git")
        if git !== nothing && ispath(joinpath(root, ".git"))
            out = IOBuffer()
            ok = success(pipeline(`$git -C $root ls-files -z`; stdout = out, stderr = devnull))
            ok && return sort!(filter!(!isempty, split(String(take!(out)), '\0')))
        end
        files = String[]
        for (d, _, fs) in walkdir(root), f in fs
            push!(files, replace(relpath(joinpath(d, f), root), '\\' => '/'))
        end
        return sort!(filter!(p -> !startswith(p, ".git/"), files))
    end

    """
        qa_phase_allowlist(path) -> Set{Tuple{String, String}}

    Read an allowlist of `path<TAB>token<TAB>reason` lines (`#` lines and blank lines are
    skipped). Every entry needs a reason.
    """
    function qa_phase_allowlist(path::AbstractString)
        allow = Set{Tuple{String, String}}()
        isfile(path) || return allow
        for (i, l) in enumerate(eachline(path))
            (isempty(strip(l)) || startswith(l, "#")) && continue
            f = split(l, '\t')
            (length(f) == 3 && !isempty(strip(f[3]))) ||
                throw(ArgumentError("$path:$i: expected `path<TAB>token<TAB>reason`"))
            push!(allow, (String(f[1]), String(f[2])))
        end
        return allow
    end

    """
        qa_no_phase_names(root; allow = qa_phase_allowlist(joinpath(root, "test", "phase_names_allow.txt")))
            -> Vector{String}

    Scan the tracked files of the checkout at `root` (`git ls-files`, or every file when git or
    the repository is absent) in the package sources, extensions, tests, benchmarks, docs pages
    and models, the status page, reproduction pages, tools, CI files, READMEs and CONTRIBUTING files for
    [`qa_phase_tokens`](@ref), in file contents and in the paths themselves, and for
    [`qa_decision_ids`](@ref) in file contents (comments of code files exempt). Skipped:
    `docs/design/`, `CLAUDE.md`, `.claude/`, the committed records under
    `lib/PottsModels/reproductions/data/` and the allowlist itself. Returns one
    `"file:line: token"` per hit not in `allow` (line 0 for a path); empty when clean.
    """
    function qa_no_phase_names(
            root::AbstractString;
            allow = qa_phase_allowlist(joinpath(root, _QA_PHASE_ALLOWLIST))
        )
        bad = String[]
        for p in _qa_phase_files(root)
            _qa_phase_in_scope(p) || continue
            for t in qa_phase_tokens(p)
                (p, t) in allow || push!(bad, "$p:0: $t")
            end
            file = joinpath(root, p)
            isfile(file) || continue
            bytes = read(file)
            (0x00 in bytes || !isvalid(String, bytes)) && continue
            prose = _qa_prose_file(p)
            for (i, ln) in enumerate(eachsplit(String(bytes), '\n'; keepempty = true))
                for t in Iterators.flatten((qa_phase_tokens(ln), qa_decision_ids(ln; prose)))
                    (p, t) in allow || push!(bad, "$p:$i: $t")
                end
            end
        end
        return bad
    end

end
