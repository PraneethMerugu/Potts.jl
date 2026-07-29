module TransitionCommandLine

export parse_options

function parse_options(args)
    options = Dict{String, String}()
    force = false
    index = 1
    while index <= length(args)
        if args[index] == "--force"
            force = true
            index += 1
        else
            startswith(args[index], "--") || throw(ArgumentError(
                "unexpected positional argument: $(args[index])"))
            index < length(args) ||
                throw(ArgumentError("missing value for $(args[index])"))
            options[args[index][3:end]] = args[index + 1]
            index += 2
        end
    end
    return (; options, force)
end

end
