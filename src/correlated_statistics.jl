# Uncertainty of a mean estimated from a correlated series.
#
# Monte Carlo and molecular-dynamics series are correlated by construction.
# Treating them as independent understates the uncertainty by a factor of about
# √τ_int, which for a chain near a critical point can be an order of magnitude.
#
# Only the explicit-window estimator is implemented at this gate: the caller
# states the summation window, and the function computes with it. Adaptive
# windows, automatic truncation, blocking with plateau selection, and bootstrap
# intervals are deliberately deferred, because each embeds a selection rule whose
# behaviour must be judged against a case that produces real correlated data —
# and no such case has been implemented. See G3-D.6, G3-CORR.1 and the narrowed
# G3-DEF.1 in docs/decisions.md.

"""
    _ACF_LAG_ZERO_TOLERANCE

Absolute tolerance within which an externally supplied sequence must equal 1 at
lag zero to be accepted as a normalised autocorrelation function. An
autocorrelation function is normalised by its own lag-zero value, so a departure
larger than this indicates an autocovariance, a truncated tail, or a series with
a different normalisation, rather than a rounding error.

`1e-8` is an **internal numerical acceptance tolerance**. It decides whether an
input is of the right kind; it is not a window-selection rule, and it takes no
part in choosing `maxlag` or in truncating the sum.
"""
const _ACF_LAG_ZERO_TOLERANCE = 1.0e-8

"""
    _MIN_LAG_PAIRS

The smallest number of contributing observation pairs the largest selected lag
may leave: with `n` observations and a window of `maxlag`, the autocorrelation at
that lag is formed from `n - maxlag` lagged products, and at least
`_MIN_LAG_PAIRS` of them are required.

Three pairs exclude a degenerate estimate **only**. They are not evidence that
`maxlag` is statistically sufficient, and no such claim is made: an
autocorrelation estimated from three products carries no useful precision.
Choosing a window long enough to capture the correlations and short enough to be
estimated remains the caller's scientific responsibility.
"""
const _MIN_LAG_PAIRS = 3

"""
    integrated_autocorrelation_time(acf::AbstractVector{<:Real}; maxlag::Integer) -> Float64

Return the integrated autocorrelation time of a series whose normalised
autocorrelation function is `acf`, summed over an explicitly supplied window:

    τ_int = 1 + 2 * sum(acf[2:maxlag+1])

`acf[begin]` is the lag-zero value and must equal 1 to within
`_ACF_LAG_ZERO_TOLERANCE`; element `k + 1` is the autocorrelation at lag `k`. In
this convention the variance of the sample mean of `n` correlated observations is
`τ_int` times the variance it would have for `n` independent ones, so the
effective sample size is `n / τ_int`.

There is no automatic window. `maxlag` is supplied by the caller and must satisfy
`0 ≤ maxlag < length(acf)`; `maxlag = 0` returns `1.0`, the independent-sample
value. Truncating the sum is a choice with consequences in both directions — too
short a window underestimates `τ_int`, too long a one adds noise from lags whose
autocorrelation is not resolved — and this function makes that choice visible
rather than taking it.

The sum is formed in the **`Float64` numerical domain**: each autocorrelation
over the summed window is converted and validated there, so a value that is
mathematically finite but whose conversion is not is rejected rather than
admitted as an infinity. Values beyond `maxlag` take no part in the sum and are
not validated, so a caller may pass a longer autocorrelation function than it
uses. Offset-indexed input is supported: the lag-zero element is `acf[begin]`
rather than `acf[1]`.

Requires `0 ≤ maxlag ≤ typemax(Int)`, values finite in `Float64` over the summed
window, and a resulting `τ_int` that is finite and strictly positive; anything
else throws an `ArgumentError`. A nonpositive result means the summed
autocorrelations cancel the lag-zero term, which happens when the window extends
into an anticorrelated tail, and no meaningful effective sample size can be
formed from it.
"""
function integrated_autocorrelation_time(acf::AbstractVector{<:Real}; maxlag::Integer)
    m = length(acf)
    m >= 1 || throw(ArgumentError("the autocorrelation function must be nonempty"))
    lag = _checked_int(maxlag, "the summation window", 0)
    lag < m || throw(
        ArgumentError(
            "the summation window must satisfy 0 ≤ maxlag < length(acf), got " *
            "maxlag = $maxlag and length(acf) = $m",
        ),
    )
    offset = firstindex(acf) - 1
    for k in 0:lag
        isfinite(Float64(acf[offset+1+k])) || throw(
            ArgumentError(
                "every autocorrelation over the summed window must be finite in " *
                "the Float64 numerical domain; the value at lag $k is " *
                "$(acf[offset+1+k])",
            ),
        )
    end
    zero_lag = Float64(acf[offset+1])
    abs(zero_lag - 1) <= _ACF_LAG_ZERO_TOLERANCE || throw(
        ArgumentError(
            "the autocorrelation at lag zero must equal 1 to within " *
            "$(_ACF_LAG_ZERO_TOLERANCE), got $zero_lag; supply a normalised " *
            "autocorrelation function rather than an autocovariance",
        ),
    )
    total = 0.0
    for k in 1:lag
        total += Float64(acf[offset+1+k])
    end
    tau_int = 1 + 2 * total
    (isfinite(tau_int) && tau_int > 0) || throw(
        ArgumentError(
            "the integrated autocorrelation time must be finite and > 0, got " *
            "τ_int = $tau_int over a window of $lag lags; the window reaches into " *
            "an anticorrelated tail",
        ),
    )
    return tau_int
end

"""
    summarize_correlated(x::AbstractVector{<:Real}; maxlag::Integer, level::Real = 0.95) -> NamedTuple

Summarise the mean of a **stationary scalar correlated series**, correcting the
uncertainty for autocorrelation over an explicitly supplied window.

Returns `(n, mean, sd, tau_int, ess, sem, lower, upper, level, maxlag)`. The
autocorrelations at lags `0:maxlag` are estimated with `StatsBase.autocor`,
`tau_int` is obtained from `integrated_autocorrelation_time`, and

    ess = n / tau_int
    sem = sd * √(tau_int / n)

where `sd` is the unbiased sample standard deviation. The effective sample size
is not capped at `n`: an anticorrelated series has `tau_int < 1` and genuinely
carries more information about its mean than `n` independent observations would.

`(lower, upper)` is an **approximate** two-sided interval at coverage `level`,
formed from a Student-*t* quantile with `ess - 1` effective degrees of freedom.
The approximation is the usual effective-sample-size one: it replaces the raw
count by `ess` and ignores the uncertainty in `tau_int` itself, so its coverage
is nominal rather than exact, and is poorest when `ess` is small.

Three limitations are stated rather than hidden.

  - **`maxlag` is the caller's scientific responsibility.** There is no automatic
    window and no warning. A window shorter than the correlation time
    underestimates `tau_int`, and so overstates the precision of the mean; a much
    longer one adds noise from unresolved lags. The floor of `_MIN_LAG_PAIRS`
    contributing observation pairs excludes a degenerate estimate only, and is
    not evidence that the window is statistically sufficient.
  - **Stationarity is assumed, not tested.** A series that has not reached its
    stationary distribution must have its burn-in discarded first, on evidence.
  - **This is not a substitute for case-specific correlation diagnostics.** A case
    that produces correlated data reports the correlation time it measured and
    the window it used, and justifies both.

The series must be **one-based**: `StatsBase.autocor` is called on it directly,
so `Base.require_one_based_indexing` is enforced first and an offset-indexed
series is rejected explicitly rather than silently misaligned. The summary is
computed in the **`Float64` numerical domain**, the observations are validated
there, and every returned floating diagnostic and interval endpoint is required
to be finite.

Adaptive windows, automatic truncation, blocking with plateau selection, and
bootstrap intervals for nonlinear estimators remain deferred; see the narrowed
G3-DEF.1 in docs/decisions.md.

Requires a one-based `x` with `n ≥ 3`, `0 ≤ maxlag < n` leaving at least
`_MIN_LAG_PAIRS` contributing observation pairs at the largest retained lag,
observations finite in `Float64`, a nonzero unbiased sample variance,
`0 < level < 1`, and a resulting `ess > 1`; anything else throws an
`ArgumentError`.
"""
function summarize_correlated(
    x::AbstractVector{<:Real};
    maxlag::Integer,
    level::Real = 0.95,
)
    Base.require_one_based_indexing(x)
    n = length(x)
    n >= 3 || throw(
        ArgumentError(
            "a correlated summary requires at least 3 observations, got n = $n",
        ),
    )
    lag = _checked_int(maxlag, "the summation window", 0)
    lag < n || throw(
        ArgumentError(
            "the summation window must satisfy 0 ≤ maxlag < n, got maxlag = $maxlag " *
            "and n = $n",
        ),
    )
    n - lag >= _MIN_LAG_PAIRS || throw(
        ArgumentError(
            "the autocorrelation at lag $lag would be estimated from $(n - lag) " *
            "lagged pairs; at least $(_MIN_LAG_PAIRS) are required, so reduce " *
            "maxlag or lengthen the series",
        ),
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
    variance = Float64(var(x))
    (isfinite(variance) && variance > 0) || throw(
        ArgumentError(
            "the unbiased sample variance must be finite and > 0, got $variance; a " *
            "constant series has no autocorrelation function",
        ),
    )
    sd = sqrt(variance)
    tau_int = integrated_autocorrelation_time(autocor(x, 0:lag); maxlag = lag)
    ess = n / tau_int
    # Defensive. Under exact arithmetic, and under the demeaned denominator-`n`
    # autocorrelation convention `StatsBase.autocor` currently uses, the guards
    # above already imply `ess > 1`; the Gate 3C-R audit established as much. It
    # is retained because it is the property the interval below actually needs,
    # and because floating-point corner cases, a future change of estimator, and
    # pathological external input are not covered by that proof.
    ess > 1 || throw(
        ArgumentError(
            "the effective sample size must exceed 1 for an interval to be " *
            "meaningful, got ess = $ess from n = $n and τ_int = $tau_int",
        ),
    )
    centre = Float64(mean(x))
    se = sd * sqrt(tau_int / n)
    halfwidth = quantile(TDist(ess - 1), (1 + coverage) / 2) * se
    lower = centre - halfwidth
    upper = centre + halfwidth
    (
        isfinite(centre) &&
        isfinite(sd) &&
        isfinite(tau_int) &&
        isfinite(ess) &&
        isfinite(se) &&
        isfinite(lower) &&
        isfinite(upper)
    ) || throw(
        ArgumentError(
            "the summary must be finite in the Float64 numerical domain, got " *
            "mean = $centre, sd = $sd, τ_int = $tau_int, ess = $ess, sem = $se " *
            "and interval ($lower, $upper)",
        ),
    )
    return (
        n = n,
        mean = centre,
        sd = sd,
        tau_int = tau_int,
        ess = ess,
        sem = se,
        lower = lower,
        upper = upper,
        level = coverage,
        maxlag = lag,
    )
end
