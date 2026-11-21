# Definitions that a test also evaluates in a worker `julia` process, from one source
# string:
#
#     define_in_main(@__MODULE__, :Marker, preamble, DEFS, "label")
#
# evaluates `preamble` (an expression) and the string `DEFS` in `Main`, once per process
# (when `Main` has no `Marker` yet), as the worker evaluates them at its top level, and
# binds every name that `DEFS` defines at top level as a constant of the calling module. A
# fingerprint prints a function or type with its module, so the fingerprints of the two
# processes agree only when both define these in `Main` (a setup module's own name is
# generated, `var"##…"`).

"""The name that a top-level expression defines, or `nothing`."""
function main_defined_name(ex)
    ex isa Expr || return nothing
    ex.head === :macrocall && ex.args[1] === Symbol("@potts_model") && return ex.args[3]
    ex.head in (:const, :global) && return main_defined_name(ex.args[1])
    ex.head === :module && return ex.args[2]
    ex.head === :struct &&
        return (h = ex.args[2]; h isa Expr && h.head === :curly ? h.args[1] : h)
    if ex.head in (:function, :(=))
        h = ex.args[1]
        h isa Symbol && return h
        h isa Expr && h.head === :call && h.args[1] isa Symbol && return h.args[1]
    end
    return nothing
end

"""The names that the top level of `defs` defines (see `main_defined_name`)."""
function main_defined_names(defs::String)
    return Symbol[
        n
            for n in (main_defined_name(ex) for ex in Meta.parseall(defs).args)
            if n !== nothing
    ]
end

function define_in_main(
        into::Module, marker::Symbol, preamble::Expr, defs::String, label::String
    )
    defined = main_defined_names(defs)
    if !isdefined(Main, marker)
        # Two files that define one name in `Main` would share it silently in one process.
        owned = names(Main; all = true)
        clash = filter(in(owned), defined)
        isempty(clash) || error("$label: `Main` already defines $(join(clash, ", "))")
        Core.eval(Main, preamble)
        include_string(Main, defs, label)
    end
    for n in defined
        Core.eval(into, :(const $n = Main.$n))
    end
    return nothing
end
