# Convergence-order estimation by ordinary least squares on logarithms.
#
# A convergence study produces pairs (step size, error) that a scheme of order p
# should follow as error ≈ C * h^p. Taking logarithms turns that into a straight
# line whose slope estimates p, and estimating the line by unweighted ordinary
# least squares needs nothing beyond elementary sums — so no regression
# dependency is introduced.
#
# Fitting on logarithms is a modelling choice with a consequence: unweighted
# least squares in log space corresponds to weighting the original errors by
# their reciprocal, which is to say it treats *relative* error as homoscedastic.
# That suits a convergence study, whose errors span decades and whose scatter is
# proportional rather than additive, but it is an assumption and is recorded as
# one. Weighted fitting, and the acceptance bands that decide whether a measured
# slope confirms a claimed order, are not implemented at this gate.

"""
    fit_loglog(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}) -> NamedTuple

Fit `log(y) = intercept + slope * log(x)` by unweighted ordinary least squares.

Returns `(slope, intercept, slope_se, r2, residuals)`. For a convergence study
with `x` the step size and `y` the error, `slope` estimates the observed order of
convergence and `exp(intercept)` the leading error constant. The residuals are
returned in the order of the input, on the logarithmic scale on which the fit was
performed.

The standard error of the slope is the textbook two-parameter expression

    slope_se = √((SSE / (n - 2)) / Sxx)

with `SSE` the residual sum of squares, `Sxx` the total sum of squares of
`log(x)`, and `n - 2` residual degrees of freedom; `r2 = 1 - SSE / SST`. Both are
descriptive statistics of the fit under the homoscedastic-in-log assumption
above. `slope_se` is a sampling uncertainty only if the scatter about the line is
independent noise, which for a deterministic convergence study it generally is
not: there, the residuals measure the departure from a pure power law, and the
interval must be read as a goodness-of-fit statement rather than as a confidence
interval for the order.

An exact power law is admissible input, and returns residuals that are zero to
rounding, `slope_se` zero to rounding, and `r2 = 1`.

Requires equal lengths, at least 3 points, every `x` and `y` finite and strictly
positive, at least two distinct values of `log(x)`, and a non-constant `log(y)`;
anything else throws an `ArgumentError` naming the condition that failed. No
point is ever discarded silently and no warning is emitted: a study that must
drop a point does so explicitly, in the case study, with its reason recorded.
"""
function fit_loglog(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    n = length(x)
    length(y) == n || throw(
        ArgumentError(
            "x and y must have equal length, got $(length(x)) and $(length(y))",
        ),
    )
    n >= 3 || throw(
        ArgumentError(
            "a two-parameter fit with a residual variance requires at least 3 " *
            "points, got n = $n",
        ),
    )
    lx = Vector{Float64}(undef, n)
    ly = Vector{Float64}(undef, n)
    for (i, (xi, yi)) in enumerate(zip(x, y))
        (isfinite(xi) && xi > 0) || throw(
            ArgumentError(
                "every x must be finite and strictly positive; element $i is $xi",
            ),
        )
        (isfinite(yi) && yi > 0) || throw(
            ArgumentError(
                "every y must be finite and strictly positive; element $i is $yi",
            ),
        )
        lx[i] = log(Float64(xi))
        ly[i] = log(Float64(yi))
    end
    allequal(lx) && throw(
        ArgumentError(
            "the fit requires at least two distinct values of log(x); all $n are equal",
        ),
    )
    allequal(ly) && throw(
        ArgumentError(
            "the fit requires log(y) to be non-constant; all $n values are equal",
        ),
    )
    mean_lx = mean(lx)
    mean_ly = mean(ly)
    sxx = 0.0
    sxy = 0.0
    sst = 0.0
    for i in 1:n
        dx = lx[i] - mean_lx
        dy = ly[i] - mean_ly
        sxx += dx * dx
        sxy += dx * dy
        sst += dy * dy
    end
    (isfinite(sxx) && sxx > 0) || throw(
        ArgumentError(
            "the sum of squares of log(x) about its mean must be finite and > 0, " *
            "got Sxx = $sxx",
        ),
    )
    (isfinite(sst) && sst > 0) || throw(
        ArgumentError(
            "the sum of squares of log(y) about its mean must be finite and > 0, " *
            "got SST = $sst",
        ),
    )
    slope = sxy / sxx
    intercept = mean_ly - slope * mean_lx
    residuals = Vector{Float64}(undef, n)
    sse = 0.0
    for i in 1:n
        residual = ly[i] - (intercept + slope * lx[i])
        residuals[i] = residual
        sse += residual * residual
    end
    slope_se = sqrt((sse / (n - 2)) / sxx)
    r2 = 1 - sse / sst
    (isfinite(slope) && isfinite(intercept) && isfinite(slope_se) && isfinite(r2)) ||
        throw(
            ArgumentError(
                "the fit produced a non-finite diagnostic: slope = $slope, " *
                "intercept = $intercept, slope_se = $slope_se, r2 = $r2",
            ),
        )
    return (
        slope = slope,
        intercept = intercept,
        slope_se = slope_se,
        r2 = r2,
        residuals = residuals,
    )
end
