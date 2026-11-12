# Definitions of euler_tests.jl that other test files use (moved here by TS1b).
function euler_brute(X::AbstractArray{Bool}, adj, hex::Bool = false)
    N = ndims(X)
    L = size(X)
    g(j) = all(d -> 1 <= j[d] <= L[d], 1:N) && X[j...]
    if hex
        χ = 0
        for I in CartesianIndices(X)
            i = Tuple(I)
            χ += g(i) - sum(g(i) & g(i .+ e) for e in ((1, 0), (0, 1), (-1, 1)))
        end
        for i in Iterators.product(0:L[1], 0:L[2])          # both triangles, anchored left/below too
            χ += (g(i) & g(i .+ (1, 0)) & g(i .+ (0, 1))) + (g(i .+ (1, 0)) & g(i .+ (0, 1)) & g(i .+ (1, 1)))
        end
        return χ
    end
    χ = 0
    spans = Iterators.product(ntuple(_ -> (0, 1), N)...)
    if adj === :face
        for I in CartesianIndices(X), S in spans
            i = Tuple(I)
            all(g(i .+ e) for e in Iterators.product(ntuple(d -> S[d] == 1 ? (0, 1) : (0,), N)...)) &&
                (χ += (-1)^sum(S))
        end
    else
        for v in Iterators.product(ntuple(d -> 1:(L[d] + 1), N)...), S in spans
            any(g(v .- e) for e in Iterators.product(ntuple(d -> S[d] == 1 ? (0,) : (0, 1), N)...)) &&
                (χ += (-1)^sum(S))
        end
    end
    return χ
end

# the device lifecycle's rebuild (zeroed, then summed from σ), on the CPU backend: cells
# divide (cutting holed and fragmented cells) and the columns equal the recount
function eu_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx, prop)
    commit_euler!(st.cell.euler, prop, euler_change(st.σ, ctx, prop, Val(:face)))
    commit_euler!(st.cell.euler_full, prop, euler_change(st.σ, ctx, prop, Val(:full)))
    return nothing
end
eu_trigger(st, p, ctx, key, mcs, c) = (iseven(mcs) && st.cell.volume[c] >= 24) ? EVENT_DIVIDE : EVENT_NONE
function eu_problem()
    lat = Lattice((24, 20); boundary = (Periodic(), Closed()))
    σ = zeros(Int32, 24, 20)
    σ[2:8, 2:8] .= 1; σ[4:6, 4:6] .= 0; σ[12:17, 3:9] .= 2; σ[5:9, 12:17] .= 3; σ[24, 12:16] .= 4; σ[1:3, 12:16] .= 4
    cell = (; init_moments(σ, lat, 4)..., euler = recompute_euler(σ, lat, Val(:face), 4), euler_full = recompute_euler(σ, lat, Val(:full), 4))
    st = with_capacity(initial_state(σ, Int32[1, 2, 1, 2]; cell), 32)
    f = CPMFunction(gg_delta_H; commit! = eu_commit!, temperature = gg_temperature,
        lifecycle = Lifecycle(eu_trigger; normal = random_plane))
    return PottsProblem(f, st, lat, (0, 16), merge(gg_params(), (; V0 = 30.0, T = 8.0)); contact = Moore(1),
        proposal = Moore(1), seed = 3)
end
eu_bad(cell, σ, lat) = (n = length(cell.kind);
    count(cell.euler .!= recompute_euler(σ, lat, Val(:face), n)) +
    count(cell.euler_full .!= recompute_euler(σ, lat, Val(:full), n)))
