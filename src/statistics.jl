# Summaries and discrepancy measures for independent samples.
#
# These functions assume independent, identically distributed observations. That
# precondition is in the name of `summarize_independent` because violating it is
# the single most common way to report an interval that is wrong by a large
# factor: a Monte Carlo or molecular-dynamics time series is correlated, and its
# uncertainty must be obtained from correlated_statistics.jl instead.
#
# The estimators themselves are taken from Statistics, StatsBase, and
# Distributions rather than rewritten here. What this file adds is the scientific
# contract: which precondition applies, what is validated, and what is returned.
#
# Every field of every returned summary is a `Float64`, except the sample size,
# so that a summary has one concrete type whatever the element type of the input.
#
# `Float64` is therefore the effective numerical domain of this file, and it is
# the domain in which the contracts are enforced. An argument is converted first
# and validated afterwards, so that a value which is mathematically finite but
# whose conversion is not — a `BigInt` of order `10^400`, say — is rejected rather
# than silently admitted as an infinity. Each result is checked in turn, so that
# no accepted input yields a `NaN` or an `Inf`: an overflow in a subtraction, a
# square, an accumulation, or a division is an error, and never a returned value.

"""
    summarize_independent(x::AbstractVector{<:Real}; level::Real = 0.95) -> NamedTuple

Summarise an **independent, identically distributed** sample.

Returns `(n, mean, sd, sem, lower, upper, level)`, where `sd` is the unbiased
sample standard deviation, `sem` the Monte Carlo standard error `sd / √n`, and
`(lower, upper)` a two-sided Student-*t* confidence interval at coverage `level`
with `n - 1` degrees of freedom.

The i.i.d. precondition is not checked and cannot be: it is a property of how the
sample was produced. Applying this function to a correlated series understates
the uncertainty, usually severely, because the effective sample size is then far
smaller than `n`. Use `summarize_correlated` for such data.

The summary is computed in the **`Float64` numerical domain**. Every observation
must be finite once converted, and every returned floating field must be finite
in turn, so that a sample whose mean or variance overflows is rejected rather
than summarised as `Inf`. A sample whose meaningful distinctions lie below
`Float64` resolution should be rescaled — by subtracting a reference value, or by
changing units — before it is summarised here.

A genuinely constant sample is admissible: its standard deviation and standard
error are zero and its interval has zero width, which is the correct report for a
sample that carries no information about dispersion.

Requires `n ≥ 2`, observations finite in `Float64`, and `0 < level < 1`; anything
else throws an `ArgumentError`.
"""
function summarize_independent(x::AbstractVector{<:Real}; level::Real = 0.95)
    n = length(x)
    n >= 2 || throw(
        ArgumentError("an interval requires at least 2 observations, got n = $n"),
    )
    for (i, xi) in enumerate(x)
        isfinite(Float64(xi)) || throw(
            ArgumentError(
                "every observation must be finite in the Float64 numerical " *
                "domain; element $i is $xi",
            ),
        )
    end
    coverage = Float64(level)
    (isfinite(coverage) && 0 < coverage < 1) ||
        throw(ArgumentError("the coverage level must satisfy 0 < level < 1, got $level"))
    centre = Float64(mean(x))
    sd = Float64(std(x))
    se = Float64(sem(x))
    halfwidth = quantile(TDist(n - 1), (1 + coverage) / 2) * se
    lower = centre - halfwidth
    upper = centre + halfwidth
    (
        isfinite(centre) &&
        isfinite(sd) &&
        isfinite(se) &&
        isfinite(lower) &&
        isfinite(upper)
    ) || throw(
        ArgumentError(
            "the summary must be finite in the Float64 numerical domain, got " *
            "mean = $centre, sd = $sd, sem = $se and interval ($lower, $upper); " *
            "rescale the sample if its meaningful distinctions lie outside the " *
            "representable range",
        ),
    )
    return (
        n = n,
        mean = centre,
        sd = sd,
        sem = se,
        lower = lower,
        upper = upper,
        level = coverage,
    )
end

"""
    nsigma(estimate::Real, reference::Real, se::Real) -> Float64

Return the discrepancy `|estimate - reference| / se`, the distance between an
estimate and a reference expressed in standard errors.

This is the quantity every validation section reports and every statistical
assertion in the test suite thresholds. The repository-wide threshold is four
standard errors; see docs/methods/error-analysis.md.

The operands are converted to `Float64` and validated there, and the resulting
discrepancy is required to be finite: an estimate and a reference whose
difference overflows, or a standard error so small that the ratio does, is an
error rather than an `Inf`.

Requires operands finite in `Float64` and a strictly positive `se`; anything else
throws an `ArgumentError`.
"""
function nsigma(estimate::Real, reference::Real, se::Real)
    value = Float64(estimate)
    target = Float64(reference)
    error_scale = Float64(se)
    (isfinite(value) && isfinite(target) && isfinite(error_scale)) || throw(
        ArgumentError(
            "the estimate, the reference and the standard error must all be " *
            "finite in the Float64 numerical domain, got estimate = $estimate, " *
            "reference = $reference and se = $se",
        ),
    )
    error_scale > 0 ||
        throw(ArgumentError("the standard error must be > 0, got se = $se"))
    discrepancy = abs(value - target) / error_scale
    isfinite(discrepancy) || throw(
        ArgumentError(
            "the discrepancy must be finite in the Float64 numerical domain; " *
            "estimate = $estimate, reference = $reference and se = $se overflow it",
        ),
    )
    return discrepancy
end

"""
    rmse(errors::AbstractVector{<:Real}) -> Float64

Return the root mean squared value of `errors`, `√(mean(errors.^2))`.

The argument is a vector of errors that have already been formed. Each is
converted to `Float64` and validated there, and the running sum of squares is
checked at every step, so that an error whose square or whose accumulation
overflows is rejected rather than returned as `Inf`.

Requires a nonempty vector of values finite in `Float64`, with a finite sum of
squares; anything else throws an `ArgumentError`.
"""
function rmse(errors::AbstractVector{<:Real})
    n = length(errors)
    n >= 1 || throw(ArgumentError("the error vector must be nonempty"))
    total = 0.0
    for (i, e) in enumerate(errors)
        value = Float64(e)
        isfinite(value) || throw(
            ArgumentError(
                "every error must be finite in the Float64 numerical domain; " *
                "element $i is $e",
            ),
        )
        total += abs2(value)
        isfinite(total) || throw(
            ArgumentError(
                "the sum of squared errors must be finite in the Float64 " *
                "numerical domain; squaring or accumulating element $i overflows it",
            ),
        )
    end
    result = sqrt(total / n)
    isfinite(result) || throw(
        ArgumentError(
            "the root mean squared error must be finite in the Float64 numerical " *
            "domain, got $result",
        ),
    )
    return result
end

"""
    rmse(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}) -> Float64

Return the root mean squared difference between paired observations,
`√(mean((x .- y).^2))`.

The differences are accumulated in one pass, so no full-length temporary vector
is formed. Each pair is converted to `Float64` and validated there, and both the
difference and the running sum of squares are checked, so that an overflow in the
subtraction, the squaring, or the accumulation is rejected rather than returned
as `Inf`.

Requires nonempty vectors of equal length holding values finite in `Float64`,
with finite differences and a finite sum of squares; anything else throws an
`ArgumentError`.
"""
function rmse(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    n = length(x)
    length(y) == n || throw(
        ArgumentError(
            "paired vectors must have equal length, got $(length(x)) and $(length(y))",
        ),
    )
    n >= 1 || throw(ArgumentError("the paired vectors must be nonempty"))
    total = 0.0
    for (i, (xi, yi)) in enumerate(zip(x, y))
        left = Float64(xi)
        right = Float64(yi)
        (isfinite(left) && isfinite(right)) || throw(
            ArgumentError(
                "every paired value must be finite in the Float64 numerical " *
                "domain; element $i is ($xi, $yi)",
            ),
        )
        difference = left - right
        isfinite(difference) || throw(
            ArgumentError(
                "every paired difference must be finite in the Float64 numerical " *
                "domain; element $i is ($xi, $yi)",
            ),
        )
        total += abs2(difference)
        isfinite(total) || throw(
            ArgumentError(
                "the sum of squared differences must be finite in the Float64 " *
                "numerical domain; squaring or accumulating element $i overflows it",
            ),
        )
    end
    result = sqrt(total / n)
    isfinite(result) || throw(
        ArgumentError(
            "the root mean squared difference must be finite in the Float64 " *
            "numerical domain, got $result",
        ),
    )
    return result
end

"""
    relative_error(estimate::Real, reference::Real) -> Float64

Return `|estimate - reference| / |reference|`.

A zero reference throws an `ArgumentError` rather than returning `Inf` or `NaN`.
The relative error is undefined there, and the choice between an absolute
tolerance and a mixed absolute-relative one is a scientific decision belonging to
the caller, which a silent convention here would take on its behalf.

The operands are converted to `Float64` and validated there, so the zero-reference
rejection applies to a reference that underflows to zero on conversion as well as
to an exact zero; both leave the ratio undefined at this precision. The result is
required to be finite, so an overflow in the subtraction or the division is an
error rather than an `Inf`.

Requires operands finite in `Float64` and a nonzero reference; anything else
throws an `ArgumentError`.
"""
function relative_error(estimate::Real, reference::Real)
    value = Float64(estimate)
    target = Float64(reference)
    (isfinite(value) && isfinite(target)) || throw(
        ArgumentError(
            "the estimate and the reference must both be finite in the Float64 " *
            "numerical domain, got estimate = $estimate and reference = $reference",
        ),
    )
    iszero(target) && throw(
        ArgumentError(
            "the relative error is undefined for a zero reference; select an " *
            "absolute or mixed tolerance explicitly",
        ),
    )
    result = abs(value - target) / abs(target)
    isfinite(result) || throw(
        ArgumentError(
            "the relative error must be finite in the Float64 numerical domain; " *
            "estimate = $estimate and reference = $reference overflow it",
        ),
    )
    return result
end
