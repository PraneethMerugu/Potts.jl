# The numbers that page 15 quotes about Potts.jl (checkerboard), re-read from this record
# (spec 15 §1.3; D-225, D-226, D-227). The page includes this file and calls `cb_check`, so a
# regenerated record cannot leave the page's text stale: the docs build fails and lists the
# expected lines. Three kinds of quote are checked:
#   - phrases inside the "Potts.jl (checkerboard)" section;
#   - phrases elsewhere on the page (the Figure 2, 3 and 9 slots, Table S5, the records table);
#   - the section's deviations table, which must hold exactly the record's rows, in order.
# This record measures the lockless block CheckerboardCPM (no colors, claims or ablation), so
# the quotes of the 2026-10-10 record about those are gone.
# Run as a script, it prints all of them (the table rows in the page's Literate form):
#     julia lib/PottsModels/reproductions/data/15/checkerboard-2026-11-05/page_quotes.jl
using TOML

const CB_DATA15 = normpath(joinpath(@__DIR__, ".."))
function cb_tsv(dir, file)
    lines = filter(!isempty, readlines(joinpath(CB_DATA15, dir, file)))
    head = split(lines[1], '\t')
    return [Dict(String(h) => String(v) for (h, v) in zip(head, split(l, '\t'))) for l in lines[2:end]]
end

function cb_quotes(dir)
    tm = TOML.parsefile(joinpath(CB_DATA15, dir, "meta.toml"))
    prov = TOML.parsefile(joinpath(CB_DATA15, dir, "provenance.toml"))
    t = tm["time"]
    f2(x) = (s = string(round(x; digits = 2)); occursin('.', s) ? rpad(s, findfirst('.', s) + 2, '0') : s * ".00")
    pct(x) = string(round(Int, 100 * x), " %")
    c8(c) = first(strip(c), 8)
    cmp = cb_tsv(dir, "comparison.tsv")
    devs = cb_tsv(dir, joinpath("entry", "deviations.tsv"))
    key(d) = (d["case"], String(first(split(d["target"]))))
    T, Ts = t["T_lambda2"], t["T_seq_p1b"]
    cyc = t["beyond"] ? "5T = $(t["cycle_mcs"]) MCS" : "the sequential cycle of $(t["cycle_mcs"]) MCS"
    section = ["$(t["phases_chain"]) phases per MCS on the chain and $(t["phases_monolayer"]) on the monolayer",
        "commit `$(c8(prov["commit"]))`",
        "T(λ = 2) = $T MCS", "sequential $Ts MCS on the same chain (z = $(f2(t["z_p1b"])))",
        "$(t["T_seq"]) MCS on the sequential record's P1 strip (z = $(f2(t["z"])))",
        t["beyond"] ? "beyond the spread (D-218)" : "within the spread (D-218)", cyc,
        "α = $(t["alpha_text"]) px per MCS",
        "$(pct(t["chain_copy_ratio"])) of the sequential copies",
        "$(count(r -> r["beyond"] == "true", cmp)) of $(length(cmp)) metrics"]
    clauses = [String(strip(first(split(d["suspected_cause"], ':')))) for d in devs]
    for c in unique(clauses)
        k = count(==(c), clauses)
        push!(section, (k == length(clauses) ? "all $k rows" : "$k of $(length(clauses)) rows") * ": $c")
    end
    page = ["T(λ = 2) = $T MCS against $Ts", "cases (f) and (b) in its own $(t["cycle_mcs"])-MCS cycles",
        "case (a) in its own $(t["cycle_mcs"])-MCS cycles", "Potts.jl (checkerboard) has its own λ = 2 row on the P1b chain: T = $T MCS",
        "| `$dir` | Potts.jl (checkerboard), a characterization of `CheckerboardCPM` |",
        "and its GPU | `$(c8(prov["commit"]))` |"]
    cell(s) = replace(s, "|" => "∣")
    am(s) = replace(s, "characteris" => "characteriz")
    rows = map(devs) do d
        z = match(r"\|z\| = (\d+\.\d+)", d["target"])
        "| `$(key(d)[2])` ($(d["case"]))" * (z === nothing ? "" : ", ∣z∣ = $(z[1])") * " | " *
        join(cell.((d["ours"], d["paper"], am(d["suspected_cause"]), am(d["author_question"]))), " | ") * " |"
    end
    return section, page, rows
end
function cb_check(dir, page)
    src = read(page, String)
    i, j = findfirst("# ### Potts.jl (checkerboard)", src), findfirst("# ## 4. Details", src)
    flat(s) = strip(replace(replace(s, r"(?m)^# ?" => ""), r"\s+" => " "))
    secsrc = src[first(i):(first(j) - 1)]
    sec, all = flat(secsrc), flat(src)
    section, pagewide, rows = cb_quotes(dir)
    bad = [filter(q -> !occursin(flat(q), sec), section); filter(q -> !occursin(flat(q), all), pagewide)]
    have = [flat(l) for l in split(secsrc, '\n') if startswith(l, "# | `")]
    have == flat.(rows) || push!(bad, "the deviations table ($(length(have)) rows) must be exactly the record's " *
                                      "$(length(rows)) rows:", rows...)
    isempty(bad) || error("page 15: the checkerboard text is stale against $dir; expected:\n" * join(bad, "\n"))
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    section, page, rows = cb_quotes(basename(@__DIR__))
    foreach(println, section)
    println()
    foreach(println, page)
    println()
    foreach(r -> println("# ", r), rows)
end
