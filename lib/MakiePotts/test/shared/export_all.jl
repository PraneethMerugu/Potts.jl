# Included last by every @testsetup module of this suite (TS1b): export the setup's whole
# namespace, its own definitions and the names its `using`s bring in, so a test item sees
# what the old single-Main run saw.
for n in names(@__MODULE__; all = true, imported = true, usings = true)
    s = string(n)
    (startswith(s, '#') || n in (:eval, :include, nameof(@__MODULE__))) && continue
    @eval export $n
end
