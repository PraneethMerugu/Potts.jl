# Shared 6-package QA helpers (TS3-1: Potts, CorePotts, LatticeFields, LatticePDE,
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

    """
        qa_extension_piracies(mod; owners = (mod,)) -> Vector{Module}

    Aqua's piracy check on each loaded package extension of `mod` (`Aqua.test_all`
    does not look inside extensions), with the functions and types of `owners` (and their
    submodules) treated as the extension's own: an extension may extend its parent's
    functions and add methods on its parent's types, but not add a foreign function's
    method on foreign types. Returns the extensions checked; load the trigger packages first.
    """
    function qa_extension_piracies(mod::Module; owners = (mod,))
        Aqua = Base.require(Base.PkgId(Base.UUID("4c88cf16-eb10-579e-8560-4a9242c79595"), "Aqua"))
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        own = Any[]
        _qa_owned!(own, o::Module) =
            for n in names(o; all = true, imported = false)
            isdefined(o, n) || continue
            v = getfield(o, n)
            if v isa Module
                v !== o && parentmodule(v) === o && _qa_owned!(own, v)
            elseif v isa Function || v isa Type
                push!(own, v)
            end
        end
        foreach(o -> _qa_owned!(own, o), owners)
        TOML = Base.require(Base.PkgId(Base.UUID("fa267f1f-6049-4f14-aa54-33bafae1ed76"), "TOML"))
        project = Base.invokelatest(TOML.parsefile, joinpath(pkgdir(mod), "Project.toml"))
        exts = Module[]
        for name in sort!(collect(keys(get(project, "extensions", Dict{String, Any}()))))
            ext = Base.get_extension(mod, Symbol(name))
            ext === nothing && continue
            push!(exts, ext)
            Base.invokelatest(Aqua.test_piracies, ext; treat_as_own = own)
        end
        return exts
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

    function _qa_walk_ast_rules!(ex, line::Base.RefValue{Int}, error_calls::Vector{Int}, bare_catches::Vector{Int})
        if ex isa LineNumberNode
            ex.line > 0 && (line[] = ex.line)
            return nothing
        end
        ex isa Expr || return nothing
        if ex.head === :call && !isempty(ex.args)
            callee = ex.args[1]
            if callee === :error || callee == :(Base.error)
                push!(error_calls, line[])
            end
        elseif ex.head === :try && length(ex.args) >= 3
            # `try ... catch; ... end` leaves the catch binding slot `ex.args[2] === false`
            # with a catch body (`ex.args[3] !== false`); `try ... finally` has `ex.args[3] === false`.
            ex.args[2] === false && ex.args[3] !== false && push!(bare_catches, line[])
        end
        for a in ex.args
            _qa_walk_ast_rules!(a, line, error_calls, bare_catches)
        end
        return nothing
    end

    function _qa_scan_error_rules(text::AbstractString; allow_bcs::Bool = false)
        ast = Base.Meta.parseall(text)
        error_calls = Int[]
        bare_catches = Int[]
        _qa_walk_ast_rules!(ast, Ref(1), error_calls, bare_catches)
        stale_terms = Int[]
        for (i, ln) in enumerate(eachsplit(text, '\n'; keepempty = true))
            if occursin(_QA_STALE_FRONTEND_RE, ln)
                allow_bcs && occursin("Symbol(\"@bcs\")", ln) && !occursin(r"\bfront[- ]end\s+[AB]\b|\bboth\s+front\s+ends\b", ln) && continue
                push!(stale_terms, i)
            end
        end
        return (; error_calls, bare_catches, stale_terms)
    end

    """
        qa_error_rules(pkg_root; allowed_error_calls = Set{String}(),
                       reviewed_invariants = String[], allowed_bcs_files = String[])

    Verify that `src/` and `ext/` in `pkg_root` contain:
    - no `error(...)` / `Base.error(...)` calls outside `allowed_error_calls` (`"relpath:line"`),
    - no bare `catch` clauses (`try ... catch; ... end` without an exception binding),
    - no stale front-end wording (`"front end A"`, `"front end B"`, `"both front ends"`, `"@bcs"` outside explicit legacy section refusal),
    - internal `"please report"` invariants matching `reviewed_invariants`,
    and run negative controls proving the scanner flags synthetic violations.
    """
    function qa_error_rules(
            pkg_root::AbstractString;
            allowed_error_calls::AbstractSet{<:AbstractString} = Set{String}(),
            reviewed_invariants::AbstractVector{<:AbstractString} = String[],
            allowed_bcs_files::AbstractVector{<:AbstractString} = String[]
        )
        Test = Base.require(Base.PkgId(Base.UUID("8dfed614-e22c-5e08-85e1-65c5234f0b40"), "Test"))
        allowed_bcs = Set(normpath.(allowed_bcs_files))
        src_files = String[]
        for dir in ("src", "ext")
            root = joinpath(pkg_root, dir)
            isdir(root) || continue
            for (d, _, fs) in walkdir(root), f in fs
                endswith(f, ".jl") && push!(src_files, joinpath(d, f))
            end
        end
        sort!(src_files)

        bad_errors = String[]
        bad_catches = String[]
        bad_stale = String[]
        found_invariants = String[]
        for f in src_files
            rel = relpath(f, pkg_root)
            text = read(f, String)
            res = _qa_scan_error_rules(text; allow_bcs = normpath(f) in allowed_bcs)
            for l in res.error_calls
                loc = "$rel:$l"
                loc in allowed_error_calls || push!(bad_errors, loc)
            end
            for l in res.bare_catches
                push!(bad_catches, "$rel:$l")
            end
            for l in res.stale_terms
                push!(bad_stale, "$rel:$l")
            end
            for ln in eachsplit(text, '\n'; keepempty = true)
                occursin("please report", ln) && push!(found_invariants, rel)
            end
        end

        isempty(bad_errors) || @error "untyped error() calls" bad_errors
        isempty(bad_catches) || @error "bare catch clauses" bad_catches
        isempty(bad_stale) || @error "stale front-end terms" bad_stale
        Test.@test isempty(bad_errors)
        Test.@test isempty(bad_catches)
        Test.@test isempty(bad_stale)
        Test.@test sort(found_invariants) == sort(collect(String, reviewed_invariants))

        # Negative controls: each guard flags synthetic scratch inputs and spares valid ones.
        err_neg = _qa_scan_error_rules("f() = error(\"boom\")\ng() = Base.error(\"boom\")")
        Test.@test length(err_neg.error_calls) == 2
        catch_neg = _qa_scan_error_rules("f() = try x() catch; 1 end")
        Test.@test length(catch_neg.bare_catches) == 1
        catch_ok = _qa_scan_error_rules("f() = try x() catch e; 1 end\ng() = try x() finally 1 end")
        Test.@test isempty(catch_ok.bare_catches)
        stale_neg = _qa_scan_error_rules("# front end A\nmsg = \"write @bcs: x\"")
        Test.@test stale_neg.stale_terms == [1, 2]
        return nothing
    end
end
