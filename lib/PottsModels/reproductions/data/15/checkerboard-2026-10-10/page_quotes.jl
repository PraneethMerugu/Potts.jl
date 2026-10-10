# The numbers that page 15's "Potts.jl (checkerboard)" section quotes, re-read from this record
# (spec 15 §1.3; D-225, D-226). The page includes this file and calls `cb_check`, so a
# regenerated record cannot leave the page's text stale: the docs build fails and lists the
# expected lines. Run as a script, it prints those lines (the quoted phrases, then the
# deviations-table rows in the page's Literate form):
#     julia lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/page_quotes.jl
using TOML

const CB_DATA15 = normpath(joinpath(@__DIR__, ".."))
function cb_tsv(dir, file)
    lines = filter(!isempty, readlines(joinpath(CB_DATA15, dir, file)))
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'))) for l in lines[2:end]]
end

function cb_quotes(dir)
    tm = TOML.parsefile(joinpath(CB_DATA15, dir, "meta.toml"))
    t, dh, ab = tm["time"], tm["dH_check"], TOML.parsefile(joinpath(CB_DATA15, dir, "provenance.toml"))["ablation"]
    f2(x) = (s = string(round(x; digits = 2)); occursin('.', s) ? rpad(s, findfirst('.', s) + 2, '0') : s * ".00")
    pct(x) = string(round(Int, 100 * x), " %")
    grp(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")
    cmp = cb_tsv(dir, "comparison.tsv")
    nab = maximum(parse(Int, r["colours"]) for r in cb_tsv(dir, "ablation.tsv"))
    quotes = ["$(t["colours_chain"]) colours on the chain and $(t["colours_monolayer"]) on the monolayer",
        "T(λ = 2) = $(t["T_lambda2"]) MCS", "sequential $(t["T_seq_p1b"]) MCS on the same chain (z = $(f2(t["z_p1b"])))",
        "$(t["T_seq"]) MCS on the sequential record's P1 strip (z = $(f2(t["z"])))", "5T = $(t["cycle_mcs"]) MCS",
        "α = $(t["alpha_text"]) px per MCS", "$(pct(t["chain_commit_fraction"])) of accepted copies commit on the chain",
        "$(count(r -> r["beyond"] == "true", cmp)) of $(length(cmp)) metrics",
        "$(grp(dh["copies"])) committed copies ($(dh["mismatches"]) mismatches",
        "$(pct(dh["commit_fraction"])) of accepted copies commit",
        "$(grp(round(Int, dh["committed_per_mcs"]))) of $(grp(round(Int, dh["accepted_per_mcs"]))) per MCS at $(grp(dh["live_at_start"])) cells",
        "$nab colours (T = $(ab["T_c64"]) MCS, cycle $(ab["cycle_c64"]) MCS)",
        "runs per arm: $(ab["runs_per_arm"])",
        "ablation commits " * join(("`$(first(strip(c), 8))`" for c in split(ab["commits"], ',')), " and ")]
    devs = cb_tsv(dir, joinpath("entry", "deviations.tsv"))
    clauses = [String(strip(first(split(d["suspected_cause"], ':')))) for d in devs]
    abl = Dict((r["case"], r["metric"]) => r for r in cb_tsv(dir, "ablation.tsv"))
    kc = count(d -> abl[(d["case"], String(first(split(d["target"]))))]["beyond_contrast"] == "true", devs)
    push!(quotes, "The contrast is beyond the spread for " * (kc == length(devs) ? "every row" : "$kc of $(length(devs)) rows"))
    for c in unique(clauses)
        k = count(==(c), clauses)
        push!(quotes, (k == length(clauses) ? "all $k rows" : "$k of $(length(clauses)) rows") * ": $c")
    end
    cell(s) = replace(s, "|" => "∣")
    function cause(c)
        parts = [String(strip(first(split(c, ':'))))]
        m = match(r"contrast z ([+−-]?\d+\.\d+) \(crit (\d+\.\d+)\)", c)
        m === nothing || push!(parts, "4 against $nab colours: z $(m[1]) (crit $(m[2]))")
        r = match(r"remainder is of the (opposite|same) sign, (\d+)% of the stock difference", c)
        r === nothing || push!(parts, "$nab-colour remainder of the $(r[1]) sign, $(r[2]) %")
        return join(parts, "; ")
    end
    rows = map(devs) do d
        id = String(first(split(d["target"])))
        z = match(r"\|z\| = (\d+\.\d+)", d["target"])
        "| `$id` ($(d["case"]))" * (z === nothing ? "" : ", ∣z∣ = $(z[1])") * " | " *
        join(cell.((d["ours"], d["paper"], cause(d["suspected_cause"]), d["author_question"])), " | ") * " |"
    end
    return quotes, rows
end
function cb_check(dir, page)
    src = read(page, String)
    i, j = findfirst("# ### Potts.jl (checkerboard)", src), findfirst("# ## 4. Details", src)
    flat(s) = replace(replace(s, r"(?m)^# ?" => ""), r"\s+" => " ")
    sec = flat(src[first(i):(first(j) - 1)])
    quotes, rows = cb_quotes(dir)
    missing_ = filter(q -> !occursin(flat(q), sec), [quotes; rows])
    isempty(missing_) || error("page 15: the checkerboard section is stale against $dir; expected:\n" *
                               join(missing_, "\n"))
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    quotes, rows = cb_quotes(basename(@__DIR__))
    foreach(println, quotes)
    println()
    foreach(r -> println("# ", r), rows)
end
