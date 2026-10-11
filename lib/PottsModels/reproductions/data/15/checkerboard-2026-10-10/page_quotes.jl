# The numbers that page 15 quotes about Potts.jl (checkerboard), re-read from this record
# (spec 15 §1.3; D-225, D-226, D-227). The page includes this file and calls `cb_check`, so a
# regenerated record cannot leave the page's text stale: the docs build fails and lists the
# expected lines. Three kinds of quote are checked:
#   - phrases inside the "Potts.jl (checkerboard)" section;
#   - phrases elsewhere on the page (the Figure 2, 3 and 9 slots, Table S5, the records table);
#   - the section's deviations table, which must hold exactly the record's rows, in order.
# Run as a script, it prints all of them (the table rows in the page's Literate form):
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
    prov = TOML.parsefile(joinpath(CB_DATA15, dir, "provenance.toml"))
    t, dh, ab = tm["time"], tm["dH_check"], prov["ablation"]
    f2(x) = (s = string(round(x; digits = 2)); occursin('.', s) ? rpad(s, findfirst('.', s) + 2, '0') : s * ".00")
    sg(x) = (x >= 0 ? "+" : "") * f2(x)
    pct(x) = string(round(Int, 100 * x), " %")
    grp(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")
    sig(x) = string(round(x; sigdigits = 3))
    c8(c) = first(strip(c), 8)
    cmp = cb_tsv(dir, "comparison.tsv")
    abl = Dict((r["case"], r["metric"]) => r for r in cb_tsv(dir, "ablation.tsv"))
    devs = cb_tsv(dir, joinpath("entry", "deviations.tsv"))
    nab = maximum(parse(Int, r["colours"]) for r in values(abl))
    arm = match(r"c64: (\d+) on the chain, (\d+) on the monolayer", ab["arms"])
    stride = match(r"stride (\d+)", prov["colours"])
    ab["chain_replays_equal_gpu"] === true || error("$dir: the chain replays do not equal the GPU runs")
    dh["mismatches"] == 0 || error("$dir: ΔH mismatches")
    key(d) = (d["case"], String(first(split(d["target"]))))
    crit_ref(case) = only(unique(f2(parse(Float64, r["crit_ref"])) for (k, r) in abl if k[1] == case))
    n_ref(case) = only(unique(r["n_ref"] for (k, r) in abl if k[1] == case))
    T, Ts = t["T_lambda2"], t["T_seq_p1b"]
    section = ["$(t["colours_chain"]) colours on the chain and $(t["colours_monolayer"]) on the monolayer",
        "commit `$(c8(prov["commit"]))`",
        "T(λ = 2) = $T MCS", "sequential $Ts MCS on the same chain (z = $(f2(t["z_p1b"])))",
        "$(t["T_seq"]) MCS on the sequential record's P1 strip (z = $(f2(t["z"])))", "5T = $(t["cycle_mcs"]) MCS",
        "α = $(t["alpha_text"]) px per MCS", "$(pct(t["chain_commit_fraction"])) of accepted copies commit on the chain",
        "$(count(r -> r["beyond"] == "true", cmp)) of $(length(cmp)) metrics",
        "$(grp(dh["copies"])) committed copies ($(dh["mismatches"]) mismatches",
        "$(pct(dh["commit_fraction"])) of accepted copies commit",
        "$(grp(round(Int, dh["committed_per_mcs"]))) of $(grp(round(Int, dh["accepted_per_mcs"]))) per MCS at $(grp(dh["live_at_start"])) cells",
        "($(t["colours_monolayer"]) colours, stride $(stride[1]))",
        "$nab colours (T = $(ab["T_c64"]) MCS, cycle $(ab["cycle_c64"]) MCS)",
        "$(arm[1]) colours on the chain, $(arm[2]) on the monolayer",
        "T_c64 = $(ab["T_c64"]) $(ab["T_c64"] < Ts ? "<" : ">=") $Ts",
        "T = $T is the net of thinning and update order on the chain",
        "runs per arm: $(ab["runs_per_arm"])",
        "ablation commits " * join(("`$(c8(c))`" for c in split(ab["commits"], ',')), ", ", " and "),
        "the $(n_ref("a")) sequential seeds of case (a) (crit $(crit_ref("a")))",
        "below about $(crit_ref("b"))·se"]
    @assert crit_ref("b") == crit_ref("f")
    kc = count(d -> abl[key(d)]["beyond_contrast"] == "true", devs)
    push!(section, "The contrast is beyond the spread for " * (kc == length(devs) ? "every row" : "$kc of $(length(devs)) rows"))
    kr = count(d -> abl[key(d)]["beyond_c64"] == "true", devs)
    push!(section, "the 64-colour remainder is beyond the spread in " * (kr == 0 ? "no row" : "$kr of $(length(devs)) rows"))
    clauses = [String(strip(first(split(d["suspected_cause"], ':')))) for d in devs]
    for c in unique(clauses)
        k = count(==(c), clauses)
        push!(section, (k == length(clauses) ? "all $k rows" : "$k of $(length(clauses)) rows") * ": $c")
    end
    page = ["T(λ = 2) = $T MCS against $Ts", "cases (f) and (b) in its own $(t["cycle_mcs"])-MCS cycles",
        "case (a) in its own $(t["cycle_mcs"])-MCS cycles", "Potts.jl (checkerboard) has its own λ = 2 row on the P1b chain: T = $T MCS",
        "| `$dir` | Potts.jl (checkerboard), a characterisation of `CheckerboardCPM` |",
        "and its GPU | `$(c8(prov["commit"]))` |"]
    cell(s) = replace(s, "|" => "∣")
    function cause(d)
        r = abl[key(d)]
        x(k) = parse(Float64, r[k])
        s = String(strip(first(split(d["suspected_cause"], ':')))) *
            "; 4 against $nab colours: z $(sg(x("z_contrast"))) (crit $(f2(x("crit_contrast"))), n = $(r["n_arm"]) per arm); " *
            "$nab-colour remainder z $(sg(x("z_c64"))) against sequential (crit $(f2(x("crit_ref"))))"
        same = sign(x("diff_c64")) == sign(x("diff_stock")) ? "same" : "opposite"
        return s * (r["beyond_c64"] == "true" ? ", beyond the spread, of the $same sign, $(pct(abs(x("remainder_fraction")))) of the stock difference" :
                    ": not resolved, not absent (limit $(sig(x("resolution_c64"))), $(pct(x("resolution_fraction"))) of the stock difference)")
    end
    rows = map(devs) do d
        z = match(r"\|z\| = (\d+\.\d+)", d["target"])
        "| `$(key(d)[2])` ($(d["case"]))" * (z === nothing ? "" : ", ∣z∣ = $(z[1])") * " | " *
        join(cell.((d["ours"], d["paper"], cause(d), d["author_question"])), " | ") * " |"
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
