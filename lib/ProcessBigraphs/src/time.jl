struct TimeScale
    numerator::Int64
    denominator::Int64
    unit::Symbol
    function TimeScale(numerator::Integer, denominator::Integer=1, unit::Symbol=:second)
        numerator > 0 || _fail(:invalid_time_scale, "time-scale numerator must be positive";
            numerator)
        denominator > 0 || _fail(:invalid_time_scale,
            "time-scale denominator must be positive"; denominator)
        divisor = gcd(numerator, denominator)
        normalized_numerator = div(numerator, divisor)
        normalized_denominator = div(denominator, divisor)
        normalized_numerator <= typemax(Int64) &&
            normalized_denominator <= typemax(Int64) ||
            _fail(:time_scale_overflow, "normalized time scale exceeds the Int64 fast path";
                numerator=string(normalized_numerator),
                denominator=string(normalized_denominator))
        new(Int64(normalized_numerator), Int64(normalized_denominator), unit)
    end
end

TimeScale(value::Rational, unit::Symbol=:second) =
    TimeScale(numerator(value), denominator(value), unit)

struct LogicalTime
    tick::Int64
    scale::TimeScale
end

function LogicalTime(tick::Integer, scale::TimeScale)
    typemin(Int64) <= tick <= typemax(Int64) ||
        _fail(:time_overflow, "logical time exceeds the Int64 tick fast path";
            tick=string(tick))
    LogicalTime(Int64(tick), scale)
end

struct Duration
    tick::Int64
    scale::TimeScale
    function Duration(tick::Integer, scale::TimeScale)
        tick >= 0 || _fail(:negative_duration, "durations cannot be negative"; tick)
        tick <= typemax(Int64) ||
            _fail(:time_overflow, "duration exceeds the Int64 tick fast path";
                tick=string(tick))
        new(Int64(tick), scale)
    end
end

function common_timescale(values::AbstractVector{<:Rational}; unit::Symbol=:second)
    isempty(values) && _fail(:empty_time_declarations,
        "at least one rational duration is required")
    any(value -> value <= 0, values) &&
        _fail(:invalid_time_declaration, "declared durations must be positive")
    common_denominator = foldl(lcm, BigInt.(denominator.(values)); init=big(1))
    integral = [BigInt(numerator(value * common_denominator)) for value in values]
    common_numerator = foldl(gcd, integral)
    TimeScale(common_numerator, common_denominator, unit)
end

common_timescale(values::Rational...; unit::Symbol=:second) =
    common_timescale(collect(values); unit)

function ticks(value::Rational, scale::TimeScale)
    quotient = value / (scale.numerator // scale.denominator)
    denominator(quotient) == 1 ||
        _fail(:inexact_time_conversion, "duration is not exact in the declared time scale";
            value=string(value), scale)
    raw = numerator(quotient)
    typemin(Int64) <= raw <= typemax(Int64) ||
        _fail(:time_overflow, "time value exceeds the Int64 tick fast path"; raw=string(raw))
    Int64(raw)
end

logical_time(value::Rational, scale::TimeScale) = LogicalTime(ticks(value, scale), scale)
duration(value::Rational, scale::TimeScale) = Duration(ticks(value, scale), scale)
physical_value(value::Union{LogicalTime,Duration}) =
    value.tick * (value.scale.numerator // value.scale.denominator)

function convert_scale(value::LogicalTime, scale::TimeScale)
    value.scale.unit == scale.unit ||
        _fail(:time_unit_mismatch, "cannot convert between different time units";
            source=value.scale.unit, destination=scale.unit)
    LogicalTime(ticks(physical_value(value), scale), scale)
end

function convert_scale(value::Duration, scale::TimeScale)
    value.scale.unit == scale.unit ||
        _fail(:time_unit_mismatch, "cannot convert between different time units";
            source=value.scale.unit, destination=scale.unit)
    Duration(ticks(physical_value(value), scale), scale)
end

function _same_scale(left, right)
    left.scale == right.scale ||
        _fail(:time_scale_mismatch, "logical values must use the compiled common time scale";
            left=left.scale, right=right.scale)
end

function Base.:+(time::LogicalTime, elapsed::Duration)
    _same_scale(time, elapsed)
    LogicalTime(Base.Checked.checked_add(time.tick, elapsed.tick), time.scale)
end

function Base.:-(left::LogicalTime, right::LogicalTime)
    _same_scale(left, right)
    Duration(Base.Checked.checked_sub(left.tick, right.tick), left.scale)
end

Base.isless(left::LogicalTime, right::LogicalTime) =
    (_same_scale(left, right); left.tick < right.tick)
Base.:(==)(left::LogicalTime, right::LogicalTime) =
    left.tick == right.tick && left.scale == right.scale
Base.isless(left::Duration, right::Duration) =
    (_same_scale(left, right); left.tick < right.tick)
Base.:(==)(left::Duration, right::Duration) =
    left.tick == right.tick && left.scale == right.scale

Base.zero(scale::TimeScale) = LogicalTime(0, scale)

function Base.show(io::IO, value::LogicalTime)
    print(io, "LogicalTime(", value.tick, " × ", value.scale.numerator, "//",
        value.scale.denominator, " ", value.scale.unit, ")")
end

function Base.show(io::IO, value::Duration)
    print(io, "Duration(", value.tick, " × ", value.scale.numerator, "//",
        value.scale.denominator, " ", value.scale.unit, ")")
end
