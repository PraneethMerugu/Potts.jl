# Reproducible warm marginal footprint for the two mandatory dependency-footprint
# dependencies. Run in a fresh Julia process with the LocalMath project.

function _new_module_method_count(modules)
    owners = Set(modules)
    found = Set{Method}()
    for module_value in modules
        for name in names(module_value; all = true, imported = true)
            isdefined(module_value, name) || continue
            value = getglobal(module_value, name)
            value isa Union{Function, DataType, UnionAll} || continue
            method_list = try
                methods(value)
            catch
                continue
            end
            for method in method_list
                method.module in owners && push!(found, method)
            end
        end
    end
    return length(found)
end

function _new_module_cache_bytes(modules)
    paths = Set{String}()
    for module_value in modules
        package = Base.PkgId(module_value)
        path = try
            Base.compilecache_path(package)
        catch
            continue
        end
        isfile(path) && push!(paths, path)
    end
    return sum(path -> stat(path).size, paths; init = 0), sort!(collect(paths))
end

function _import_fact(importer::Function, package::Symbol)
    before = Set(values(Base.loaded_modules))
    sample = @timed importer()
    after = Set(values(Base.loaded_modules))
    added = sort!(collect(setdiff(after, before)); by = module_value ->
        String(nameof(module_value)))
    cache_bytes, cache_paths = _new_module_cache_bytes(added)
    return (
        package,
        seconds = sample.time,
        bytes = sample.bytes,
        allocations = Base.gc_alloc_count(sample.gcstats),
        loaded_module_delta = length(added),
        method_delta = _new_module_method_count(added),
        precompile_cache_bytes = cache_bytes,
        cache_files = basename.(cache_paths),
    )
end

staticarrays = _import_fact(:StaticArrays) do
    @eval import StaticArrays
end

structarrays = _import_fact(:StructArrays) do
    @eval import StructArrays
end

println((; staticarrays, structarrays))
