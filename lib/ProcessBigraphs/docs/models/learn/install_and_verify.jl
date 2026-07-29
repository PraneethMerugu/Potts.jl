using ProcessBigraphs

scale = TimeScale(1, 10, :second)
deadline = LogicalTime(25, scale)
delay = Duration(5, scale)
target = deadline + delay

@assert physical_value(target) == 3
@assert decode_logical_value(encode_logical_value(target)) == target

result = (
    version=pkgversion(ProcessBigraphs),
    logical_time=target,
    seconds=physical_value(target),
    identity=canonical_fingerprint((:installation_probe, target)),
)
