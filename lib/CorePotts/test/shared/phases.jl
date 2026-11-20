# Definitions of phases_tests.jl that other test files use.
function jacobi!(st, p, ctx, key, mcs, i)
    lat = ctx.lattice
    x = coordinates(lat, i)
    acc = zero(eltype(st.site.u))
    for off in ctx.contact.offsets
        _, y = shift(lat, x, off)
        acc += @inbounds st.site.u[linear_index(lat, y)]
    end
    @inbounds st.site.u_next[i] = st.site.u[i] + p.D * (acc - length(ctx.contact) * st.site.u[i])
    return nothing
end
function host_jacobi(u, lat, rel, D)
    v = similar(u)
    for i in 1:nsites(lat)
        x = coordinates(lat, i)
        acc = 0.0
        for off in rel.offsets
            acc += u[linear_index(lat, shift(lat, x, off)[2])]
        end
        v[i] = u[i] + D * (acc - length(rel) * u[i])
    end
    return v
end
