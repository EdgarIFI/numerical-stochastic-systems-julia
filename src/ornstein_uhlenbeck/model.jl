# Closed-form quantities of the Ornstein–Uhlenbeck process.
#
# The process
#
#     dX_t = κ (μ − X_t) dt + σ dW_t,     κ > 0,  σ > 0,
#
# is the linear stochastic differential equation whose transition law, transient
# moments, invariant law, and autocorrelation are all available in closed form.
# That is why it is the pilot case: every numerical quantity the case reports has
# an exact reference to be judged against, so a disagreement beyond the stated
# uncertainty is evidence of an implementation fault rather than an open
# scientific question.
#
# Everything in this file is deterministic. No function here consumes randomness
# and none allocates. These are the analytical references that simulation.jl
# samples from and experiments.jl compares against.
#
# The numerical domain is `Float64` throughout, matching the shared layer: an
# argument is converted first and validated afterwards, so that a value which is
# mathematically finite but whose conversion is not — a `BigInt` of order 10^400,
# say — is rejected rather than admitted as an infinity. Every returned value is
# a `Float64`, so each function has one concrete return type whatever real types
# it is given.

"""
    _check_rate(kappa::Real) -> Float64

Validate the mean-reversion rate and return it in the `Float64` domain.

`κ > 0` is what makes the process mean-reverting: it is the reciprocal of the
relaxation time, and at `κ ≤ 0` the invariant law, the stationary variance, and
the autocorrelation all cease to exist. The condition is therefore a domain
restriction rather than a numerical convenience, and violating it throws.
"""
function _check_rate(kappa::Real)
    rate = Float64(kappa)
    (isfinite(rate) && rate > 0) || throw(
        ArgumentError(
            "the mean-reversion rate must be finite and > 0 in the Float64 " *
            "numerical domain, got kappa = $kappa",
        ),
    )
    return rate
end

"""
    _check_scale(sigma::Real) -> Float64

Validate the noise amplitude and return it in the `Float64` domain.

`σ > 0` is required rather than `σ ≥ 0`: at `σ = 0` the process is the
deterministic relaxation `ẋ = κ(μ − x)`, its invariant law degenerates to a point
mass at `μ`, and every variance this case reports is identically zero. That is a
different model, and it is refused here rather than reported as a diffusion with
no diffusion.
"""
function _check_scale(sigma::Real)
    scale = Float64(sigma)
    (isfinite(scale) && scale > 0) || throw(
        ArgumentError(
            "the noise amplitude must be finite and > 0 in the Float64 numerical " *
            "domain, got sigma = $sigma",
        ),
    )
    return scale
end

"""
    _check_finite(value::Real, name::AbstractString) -> Float64

Validate an unrestricted real parameter — the long-run mean, or an initial
value — and return it in the `Float64` domain. Both may take either sign, so
finiteness is the whole contract.
"""
function _check_finite(value::Real, name::AbstractString)
    converted = Float64(value)
    isfinite(converted) || throw(
        ArgumentError(
            "$name must be finite in the Float64 numerical domain, got $value",
        ),
    )
    return converted
end

"""
    _check_time(t::Real, name::AbstractString) -> Float64

Validate a physical time or lag and return it in the `Float64` domain.

Times and lags are nonnegative. `t = 0` is admissible and is the degenerate case
in which the transient variance vanishes and the autocorrelation equals one.
"""
function _check_time(t::Real, name::AbstractString)
    time = Float64(t)
    (isfinite(time) && time >= 0) || throw(
        ArgumentError(
            "$name must be finite and ≥ 0 in the Float64 numerical domain, got $t",
        ),
    )
    return time
end

"""
    _check_step(h::Real) -> Float64

Validate a discretisation or observation step and return it in the `Float64`
domain. A step is strictly positive: a zero step advances nothing and a negative
one runs the recursions backwards.
"""
function _check_step(h::Real)
    step = Float64(h)
    (isfinite(step) && step > 0) || throw(
        ArgumentError(
            "the step must be finite and > 0 in the Float64 numerical domain, got h = $h",
        ),
    )
    return step
end

"""
    _check_window(maxlag::Integer) -> Int

Validate a lag-summation window and return it as an `Int`.

The domain is checked before the conversion, so that a window too large to
represent is rejected by name rather than raising an `InexactError` after the
value has already been used.
"""
function _check_window(maxlag::Integer)
    maxlag >= 0 ||
        throw(ArgumentError("the summation window must be ≥ 0, got maxlag = $maxlag"))
    maxlag <= typemax(Int) || throw(
        ArgumentError(
            "the summation window must be ≤ $(typemax(Int)), got maxlag = $maxlag",
        ),
    )
    return Int(maxlag)
end

"""
    _check_euler_stability(rate::Float64, step::Float64) -> Nothing

Require `0 < κh < 2`, the condition under which the Euler–Maruyama recursion has
an invariant distribution at all.

One Euler step multiplies the deviation from `μ` by `a_h = 1 − κh`, so the
recursion contracts precisely when `|a_h| < 1`, that is when `0 < κh < 2`. At
`κh = 2` the deviation is reflected without decay and the variance grows without
bound; beyond it the recursion diverges. The stationary Euler quantities of this
file are therefore undefined outside that interval, and are refused there rather
than returned as a negative or infinite variance.

Both arguments have already passed `_check_rate` and `_check_step`.
"""
function _check_euler_stability(rate::Float64, step::Float64)
    product = rate * step
    (isfinite(product) && 0 < product < 2) || throw(
        ArgumentError(
            "the Euler–Maruyama recursion has an invariant distribution only for " *
            "0 < kappa * h < 2, got kappa * h = $product from kappa = $rate and " *
            "h = $step",
        ),
    )
    return nothing
end

"""
    relaxation_time(kappa::Real) -> Float64

The relaxation time `1 / κ`: the time constant of the exponential decay of both
the mean and the autocorrelation towards their stationary values.

It is the natural time unit of the process. A simulation horizon is meaningful
only relative to it, and an observation step much larger than it resolves no
correlation at all.

Requires `κ` finite and strictly positive; anything else throws an
`ArgumentError`.
"""
relaxation_time(kappa::Real) = 1 / _check_rate(kappa)

"""
    stationary_variance(kappa::Real, sigma::Real) -> Float64

The variance `σ² / (2κ)` of the invariant distribution.

The invariant law of the process is `Normal(μ, σ² / (2κ))`, exactly. It is the
balance between the noise injected at rate `σ²` and the restoring drift, and it
is independent of both the long-run mean and the initial condition.

Requires `κ` and `σ` finite and strictly positive; anything else throws an
`ArgumentError`.
"""
function stationary_variance(kappa::Real, sigma::Real)
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    variance = scale^2 / (2 * rate)
    isfinite(variance) || throw(
        ArgumentError(
            "the stationary variance must be finite in the Float64 numerical " *
            "domain, got $variance from kappa = $kappa and sigma = $sigma",
        ),
    )
    return variance
end

"""
    stationary_standard_deviation(kappa::Real, sigma::Real) -> Float64

The standard deviation `σ / √(2κ)` of the invariant distribution.

Formed directly rather than as the square root of `stationary_variance`, so that
the intermediate square is never taken and an amplitude near the top of the
representable range is not squared into an overflow before its root is returned.

Requires `κ` and `σ` finite and strictly positive; anything else throws an
`ArgumentError`.
"""
function stationary_standard_deviation(kappa::Real, sigma::Real)
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    deviation = scale / sqrt(2 * rate)
    isfinite(deviation) || throw(
        ArgumentError(
            "the stationary standard deviation must be finite in the Float64 " *
            "numerical domain, got $deviation from kappa = $kappa and sigma = $sigma",
        ),
    )
    return deviation
end

"""
    transient_mean(t::Real, kappa::Real, mu::Real, x0::Real) -> Float64

The mean `m(t) = μ + (x₀ − μ) e^{−κt}` of the process started at the
deterministic value `x₀`.

The initial displacement decays exponentially with the relaxation time `1 / κ`,
and the noise amplitude does not enter: the mean of a linear diffusion follows
the deterministic relaxation of its drift. At `t = 0` the value is `x₀`, and as
`t → ∞` it approaches `μ`.

Requires `t ≥ 0`, `κ` finite and strictly positive, and `μ` and `x₀` finite;
anything else throws an `ArgumentError`.
"""
function transient_mean(t::Real, kappa::Real, mu::Real, x0::Real)
    time = _check_time(t, "the transient time")
    rate = _check_rate(kappa)
    centre = _check_finite(mu, "the long-run mean")
    start = _check_finite(x0, "the initial value")
    value = centre + (start - centre) * exp(-rate * time)
    isfinite(value) || throw(
        ArgumentError(
            "the transient mean must be finite in the Float64 numerical domain, " *
            "got $value at t = $t",
        ),
    )
    return value
end

"""
    transient_variance(t::Real, kappa::Real, sigma::Real) -> Float64

The variance `v(t) = σ² (1 − e^{−2κt}) / (2κ)` of the process started at a
deterministic value.

The variance grows from zero and approaches the stationary value `σ² / (2κ)` on
the timescale `1 / (2κ)`, independently of where the process started. This is
also the conditional variance of the exact transition over an interval of length
`t`, which is why one function serves both purposes.

The factor `1 − e^{−2κt}` is evaluated as `-expm1(-2κt)`. Formed as a subtraction
of two nearly equal numbers it would lose most of its significant digits for
`κt` small — the regime the finest steps of the Euler study occupy — whereas
`expm1` is accurate there by construction. The two expressions are equal in exact
arithmetic; only their floating-point behaviour differs.

Requires `t ≥ 0` and `κ`, `σ` finite and strictly positive; anything else throws
an `ArgumentError`.
"""
function transient_variance(t::Real, kappa::Real, sigma::Real)
    time = _check_time(t, "the transient time")
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    variance = scale^2 * (-expm1(-2 * rate * time)) / (2 * rate)
    isfinite(variance) || throw(
        ArgumentError(
            "the transient variance must be finite in the Float64 numerical " *
            "domain, got $variance at t = $t",
        ),
    )
    return variance
end

"""
    exact_autocorrelation(lag::Real, kappa::Real) -> Float64

The stationary autocorrelation `ρ(τ) = e^{−κτ}`.

In the stationary regime the autocorrelation is `e^{−κ|τ|}`, an even function of
the lag, so evaluating it on `τ ≥ 0` determines it everywhere. The argument is
required to be nonnegative because every lag this case forms is a nonnegative
physical time; nothing is lost by the restriction.

`ρ` does not depend on `σ`, on `μ`, or on the initial condition: the noise
amplitude sets the scale of the fluctuations and the drift rate sets how quickly
they decorrelate.

Requires `τ ≥ 0` and `κ` finite and strictly positive; anything else throws an
`ArgumentError`.
"""
function exact_autocorrelation(lag::Real, kappa::Real)
    time = _check_time(lag, "the lag")
    rate = _check_rate(kappa)
    return exp(-rate * time)
end

"""
    finite_window_iat(kappa::Real, h::Real, maxlag::Integer) -> Float64

The integrated autocorrelation time of the stationary process observed on a
uniform grid of step `h`, summed over the finite window `1:maxlag`:

    τ_L = 1 + 2 Σ_{k=1}^{L} e^{−κkh}

This is the **finite-window** comparator, and it is the quantity a measured
`τ_int` must be compared against. The estimator of the shared correlated layer
truncates its sum at the window the caller supplies, so comparing its output with
the infinite-window limit `(1 + e^{−κh}) / (1 − e^{−κh})` would attribute the
deliberate truncation of the sum to an error in the estimate. Summing the exact
autocorrelations over the very same window removes that mismatch by construction:
the analytical reference and the empirical estimate then differ only in whether
the autocorrelations were computed or measured.

The sum is formed term by term rather than through the closed-form geometric
expression, so that the reference is manifestly the same sum the estimator forms.
`maxlag = 0` returns `1.0`, the independent-sample value.

Requires `κ` finite and strictly positive, `h` finite and strictly positive, and
`0 ≤ maxlag ≤ typemax(Int)`; anything else throws an `ArgumentError`. A window so
long that the sum overflows is rejected rather than returned as an infinity.
"""
function finite_window_iat(kappa::Real, h::Real, maxlag::Integer)
    rate = _check_rate(kappa)
    step = _check_step(h)
    window = _check_window(maxlag)
    total = 0.0
    for k in 1:window
        total += exp(-rate * k * step)
    end
    tau = 1 + 2 * total
    isfinite(tau) || throw(
        ArgumentError(
            "the finite-window integrated autocorrelation time must be finite in " *
            "the Float64 numerical domain, got $tau over $window lags",
        ),
    )
    return tau
end

"""
    exact_transition_coefficients(kappa::Real, sigma::Real, h::Real) -> NamedTuple

The two coefficients of the exact transition over a step of length `h`, returned
as `(decay, innovation_std)`.

The process has a Gaussian transition law available in closed form,

    X_{t+h} = μ + e^{−κh} (X_t − μ) + σ √((1 − e^{−2κh}) / (2κ)) Z,
    Z ~ Normal(0, 1),

which is **exact for every `h`**, not an approximation refined by taking `h`
small. `decay` is `e^{−κh}` and `innovation_std` the standard deviation of the
independent Gaussian innovation. Both depend on the step alone, so a path on a
uniform grid computes them once and reuses them at every step.

The innovation variance is evaluated as `σ² · (-expm1(-2κh)) / (2κ)` for the
reason given in [`transient_variance`](@ref): written as `1 - exp(-2κh)` it is a
subtraction of two nearly equal numbers whenever `κh` is small, and loses
significant digits exactly where the case's finest grids operate.

Requires `κ`, `σ`, and `h` finite and strictly positive; anything else throws an
`ArgumentError`. Both returned coefficients are finite `Float64` values.
"""
function exact_transition_coefficients(kappa::Real, sigma::Real, h::Real)
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    step = _check_step(h)
    decay = exp(-rate * step)
    innovation_variance = scale^2 * (-expm1(-2 * rate * step)) / (2 * rate)
    innovation_std = sqrt(innovation_variance)
    (isfinite(decay) && isfinite(innovation_std)) || throw(
        ArgumentError(
            "the exact transition coefficients must be finite in the Float64 " *
            "numerical domain, got decay = $decay and innovation_std = " *
            "$innovation_std at h = $h",
        ),
    )
    return (decay = decay, innovation_std = innovation_std)
end

"""
    euler_decay(kappa::Real, h::Real) -> Float64

The Euler–Maruyama one-step multiplier `a_h = 1 − κh` of the deviation from `μ`.

The scheme `X_{n+1} = X_n + κ(μ − X_n)h + σ√h Z_n` acts on the deviation
`Y_n = X_n − μ` as `Y_{n+1} = a_h Y_n + σ√h Z_n`. The multiplier is the linear
approximation of the exact `e^{−κh}`, and the difference between the two is the
whole source of the discretisation bias this case measures.

The multiplier itself is defined for every positive step, so only `κ > 0` and
`h > 0` are required here. The stability restriction `|a_h| < 1`, equivalently
`0 < κh < 2`, belongs to the stationary quantities that need it and is enforced
by [`euler_stationary_variance`](@ref) and [`euler_stationary_bias`](@ref).

Requires `κ` and `h` finite and strictly positive; anything else throws an
`ArgumentError`.
"""
function euler_decay(kappa::Real, h::Real)
    rate = _check_rate(kappa)
    step = _check_step(h)
    decay = 1 - rate * step
    isfinite(decay) || throw(
        ArgumentError(
            "the Euler decay factor must be finite in the Float64 numerical " *
            "domain, got $decay at kappa = $kappa and h = $h",
        ),
    )
    return decay
end

"""
    euler_stationary_variance(kappa::Real, sigma::Real, h::Real) -> Float64

The variance `σ² / (κ(2 − κh))` of the invariant distribution of the
Euler–Maruyama recursion at step `h`.

The recursion `Y_{n+1} = a_h Y_n + σ√h Z_n` with `a_h = 1 − κh` is a stable
first-order autoregression whenever `|a_h| < 1`, and its invariant variance
solves `v = a_h² v + σ² h`, giving

    v_EM(h) = σ² h / (1 − a_h²) = σ² / (κ(2 − κh)).

The invariant law of the discrete recursion is `Normal(μ, v_EM(h))`, exactly. It
is a property of the **discrete chain**, not an approximation to the invariant
law of the process: the discrete chain has this variance for every admissible
step, and `v_EM(h) → σ²/(2κ)` as `h → 0`.

Requires `κ` and `σ` finite and strictly positive, `h` finite and strictly
positive, and `0 < κh < 2`; anything else throws an `ArgumentError`.
"""
function euler_stationary_variance(kappa::Real, sigma::Real, h::Real)
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    step = _check_step(h)
    _check_euler_stability(rate, step)
    variance = scale^2 / (rate * (2 - rate * step))
    (isfinite(variance) && variance > 0) || throw(
        ArgumentError(
            "the Euler invariant variance must be finite and > 0 in the Float64 " *
            "numerical domain, got $variance at h = $h",
        ),
    )
    return variance
end

"""
    euler_stationary_bias(kappa::Real, sigma::Real, h::Real) -> Float64

The finite-step bias `b_EM(h) = v_EM(h) − σ²/(2κ)` of the Euler invariant
variance relative to the exact stationary variance of the process.

The two variances differ by

    b_EM(h) = σ²/(κ(2 − κh)) − σ²/(2κ) = σ² h / (2(2 − κh)),

and the right-hand form is what is computed. The two are equal in exact
arithmetic; the difference of the two variances is a subtraction of quantities
that agree to more and more digits as `h` decreases, so forming it directly would
lose precision fastest exactly where the bias is smallest and most interesting.
The simplified form has no such cancellation.

The bias is strictly positive on the admissible interval: the Euler chain is
**overdispersed** relative to the process it approximates. On the tested grid the
leading behaviour is linear in `h`, since `b_EM(h) = σ² h / 4 + O(h²)`; that
statement is an expansion of this exact formula and is not offered as a measured
convergence order.

Requires `κ` and `σ` finite and strictly positive, `h` finite and strictly
positive, and `0 < κh < 2`; anything else throws an `ArgumentError`.
"""
function euler_stationary_bias(kappa::Real, sigma::Real, h::Real)
    rate = _check_rate(kappa)
    scale = _check_scale(sigma)
    step = _check_step(h)
    _check_euler_stability(rate, step)
    bias = scale^2 * step / (2 * (2 - rate * step))
    (isfinite(bias) && bias > 0) || throw(
        ArgumentError(
            "the Euler stationary-variance bias must be finite and > 0 in the " *
            "Float64 numerical domain, got $bias at h = $h",
        ),
    )
    return bias
end
