# Interleaved A/B timing of one gate case (AUTONOMY §7.4): decides flagged Metal cases,
# whose absolute timing is bimodal on this machine. Runs `rounds` alternations of the base
# and the candidate checkouts, each a fresh process under the machine lock. Each run
# reports its median; the GPU flips between power states from run to run (base alone:
# 80 and 115 ns/site), so the verdict compares the FASTEST run median of each side, i.e.
# the same power state.
#     julia benchmark/ab.jl <base checkout> <candidate checkout> <case> [metal|sequential|checkerboard] [rounds]
# Exit 1 when the candidate's fastest run median is more than 5% above the base's.
using Printf


base, cand, case = ARGS[1], ARGS[2], ARGS[3]
alg = length(ARGS) >= 4 ? ARGS[4] : "metal"
rounds = length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 4
lock = joinpath(@__DIR__, "..", "tools", "exclusive.sh")
function once(dir)
    out = read(Cmd(`$lock julia --project=benchmark $(joinpath(dir, "benchmark", "ab_one.jl")) $case $alg`; dir), String)
    return parse(Float64, last(split(only(filter(startswith("AB "), split(out, '\n'))))))
end
a, b = Float64[], Float64[]
for r in 1:rounds
    push!(a, once(base)); push!(b, once(cand))
    @printf("round %d  base %.2f  candidate %.2f ns/site (median)\n", r, a[end], b[end])
end
ratio = minimum(b) / minimum(a)
@printf("%s.%s  candidate/base = %.3f\n", case, alg, ratio)
exit(ratio > 1.05 ? 1 : 0)
