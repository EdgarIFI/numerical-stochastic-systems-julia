# Sampling and integration of the Ornstein–Uhlenbeck process.
#
# Two distinct algorithms live here, and the difference between them is the
# subject of the case rather than an implementation detail.
#
# The **exact** sampler uses the closed-form Gaussian transition law of
# model.jl. It is exact at every step size, so a quantity estimated from it
# carries sampling error alone and no discretisation error whatever. Every
# reference ensemble of this case is drawn that way, which is what allows a
# disagreement to be read as a fault rather than as a step-size artefact.
#
# The **Euler–Maruyama** scheme is the object under study. It is used only in the
# experiment that measures its finite-step bias, never to produce a reference.
#
# Randomness is taken from the supplied generator alone; no ambient or global
# generator is consulted and nothing here calls `Random.seed!`. Draws are made one
# scalar at a time rather than through the array form of `randn`, for the reason
# recorded in docs/methods/rng-and-seeding.md and implemented by `derive_seeds`:
# Julia does not specify that the array form agrees with successive scalar draws,
# and drawing scalars is what makes enlarging a sample extend its draws rather
# than replace them. That property matters here because
# `sample_euler_stationary_step` must interleave two draws per observation in any
# case, and one convention across the case's samplers is worth more than a
# marginal saving in one of them.
#
# Coefficients that depend only on the parameters and the step are computed once
# per call and reused, in exactly the arithmetic form the corresponding one-step
# function uses, so a hoisted loop and repeated single steps agree bit for bit
# given the same stream. The tests check that agreement rather than assuming it.

"""
    _GRID_RELATIVE_TOLERANCE

The relative agreement with its nearest integer that the ratio `horizon / h` must
show before a uniform grid is accepted.

A grid is specified by a horizon and a step, and `horizon / h` is almost never an
exact integer in binary floating point even when it is one in decimal — `5.0` and
`0.02` are the case's own representative values. Rejecting every such pair would
make the natural specification unusable; rounding silently would accept a horizon
that is not a whole number of steps and shorten or lengthen the interval without
saying so.

The ratio is therefore required to agree with its nearest integer to within this
**internal numerical acceptance tolerance**, and anything else is refused by
name. `1e-9` is far looser than the rounding error of a single division and far
tighter than any genuine mismatch: the smallest fractional grid this case could
plausibly be given, a horizon exceeding a whole number of steps by one part in a
thousand, is rejected by a margin of six orders of magnitude. It is not a
scientific tolerance and takes no part in any reported result.
"""
const _GRID_RELATIVE_TOLERANCE = 1.0e-9

"""
    _check_count(n::Integer, name::AbstractString) -> Int

Validate a strictly positive count and return it as an `Int`.

The domain is checked before the conversion, so that a count too large to
represent is rejected by name rather than raising an `InexactError` or reaching
the allocation.
"""
function _check_count(n::Integer, name::AbstractString)
    n >= 1 || throw(ArgumentError("$name must be ≥ 1, got $n"))
    n <= typemax(Int) || throw(ArgumentError("$name must be ≤ $(typemax(Int)), got $n"))
    return Int(n)
end

"""
    _grid_steps(horizon::Float64, step::Float64) -> Int

Return the number of steps of length `step` that make up `horizon`, requiring
that the horizon be a whole number of them.

The division is performed once and its result compared with its nearest integer
under `_GRID_RELATIVE_TOLERANCE`. A ratio that fails the comparison throws an
`ArgumentError` naming the horizon, the step, and the ratio, rather than being
rounded into a grid the caller did not ask for. Both arguments have already
passed their own validation.
"""
function _grid_steps(horizon::Float64, step::Float64)
    ratio = horizon / step
    (isfinite(ratio) && ratio >= 1) || throw(
        ArgumentError(
            "the horizon must cover at least one step, got horizon = $horizon and " *
            "h = $step",
        ),
    )
    ratio <= typemax(Int) || throw(
        ArgumentError(
            "the horizon spans $ratio steps, which exceeds $(typemax(Int)); shorten " *
            "the horizon or coarsen the step",
        ),
    )
    nearest = round(ratio)
    abs(ratio - nearest) <= _GRID_RELATIVE_TOLERANCE * nearest || throw(
        ArgumentError(
            "the horizon must be a whole number of steps: horizon = $horizon and " *
            "h = $step give horizon / h = $ratio, which is not an integer to within " *
            "a relative $(_GRID_RELATIVE_TOLERANCE)",
        ),
    )
    return Int(nearest)
end

"""
    exact_step(rng::AbstractRNG, x::Real, h::Real, kappa::Real, mu::Real,
               sigma::Real) -> Float64

Advance the process by one step of length `h` under its **exact** transition law.

Returns a draw from the exact conditional distribution of `X_{t+h}` given
`X_t = x`, namely

    Normal(μ + e^{−κh}(x − μ), σ²(1 − e^{−2κh})/(2κ)).

This is not an approximation refined by taking `h` small: the returned value is
distributed exactly as the process is, at every step size. Iterating it therefore
produces a path whose finite-dimensional distributions on the grid are exactly
those of the process, and the only error in a quantity estimated from it is
sampling error.

Randomness is taken from `rng` alone. The coefficients come from
[`exact_transition_coefficients`](@ref) and are recomputed on each call; a loop
over many steps at a fixed step size should hoist them, as
[`simulate_exact_path`](@ref) does.

Requires `κ`, `σ`, and `h` finite and strictly positive, and `x` and `μ` finite;
anything else throws an `ArgumentError`.
"""
function exact_step(rng::AbstractRNG, x::Real, h::Real, kappa::Real, mu::Real, sigma::Real)
    state = _check_finite(x, "the current state")
    centre = _check_finite(mu, "the long-run mean")
    coefficients = exact_transition_coefficients(kappa, sigma, h)
    return centre +
           coefficients.decay * (state - centre) +
           coefficients.innovation_std * randn(rng)
end

"""
    euler_step(rng::AbstractRNG, x::Real, h::Real, kappa::Real, mu::Real,
               sigma::Real) -> Float64

Advance the process by one **Euler–Maruyama** step of length `h`:

    X_{n+1} = X_n + κ(μ − X_n)h + σ√h Z_n,   Z_n ~ Normal(0, 1).

The drift is held fixed over the interval and the diffusion contributes an
increment of variance `σ²h`. Unlike [`exact_step`](@ref) this is an
approximation, and the discrepancy between the two is what the Euler experiment
of this case measures.

No stability restriction is imposed here: one step is well defined for every
positive `h`, and `0 < κh < 2` is required only of the stationary Euler
quantities, which enforce it themselves.

Requires `κ`, `σ`, and `h` finite and strictly positive, and `x` and `μ` finite;
anything else throws an `ArgumentError`.
"""
function euler_step(rng::AbstractRNG, x::Real, h::Real, kappa::Real, mu::Real, sigma::Real)
    state = _check_finite(x, "the current state")
    rate = _check_rate(kappa)
    centre = _check_finite(mu, "the long-run mean")
    scale = _check_scale(sigma)
    step = _check_step(h)
    return state + rate * (centre - state) * step + scale * sqrt(step) * randn(rng)
end

"""
    sample_exact_terminal(rng::AbstractRNG, n::Integer, t::Real, kappa::Real,
                          mu::Real, sigma::Real, x0::Real) -> Vector{Float64}

Draw `n` independent values of `X_t` for a process started at the deterministic
value `x₀`.

The values are drawn **directly** from the exact marginal law
`Normal(m(t), v(t))` given by [`transient_mean`](@ref) and
[`transient_variance`](@ref). No path is integrated: the marginal at a single
time is available in closed form, so producing it by stepping would cost a
factor of `t/h` in work and introduce a grid where none is needed.

The returned observations are mutually independent, which is what entitles a
caller to summarise them with `summarize_independent`. The returned vector is the
only allocation.

Requires `n ≥ 1`, `t ≥ 0`, `κ` and `σ` finite and strictly positive, and `μ` and
`x₀` finite; anything else throws an `ArgumentError`. Every returned value is
checked to be finite.
"""
function sample_exact_terminal(
    rng::AbstractRNG,
    n::Integer,
    t::Real,
    kappa::Real,
    mu::Real,
    sigma::Real,
    x0::Real,
)
    count = _check_count(n, "the number of samples")
    centre = transient_mean(t, kappa, mu, x0)
    deviation = sqrt(transient_variance(t, kappa, sigma))
    sample = Vector{Float64}(undef, count)
    for i in eachindex(sample)
        value = centre + deviation * randn(rng)
        isfinite(value) || throw(
            ArgumentError(
                "the sampled values must be finite; element $i overflows the Float64 " *
                "numerical domain at t = $t",
            ),
        )
        sample[i] = value
    end
    return sample
end

"""
    sample_stationary(rng::AbstractRNG, n::Integer, kappa::Real, mu::Real,
                      sigma::Real) -> Vector{Float64}

Draw `n` independent values from the exact invariant distribution
`Normal(μ, σ²/(2κ))`.

The invariant law is available in closed form, so an equilibrium ensemble is
drawn from it rather than produced by relaxing an arbitrary initial condition.
Nothing is discarded as burn-in because nothing needs to be: the sample is in
equilibrium by construction, exactly, and the question of how long a burn-in
would have had to be does not arise.

The returned observations are mutually independent. The returned vector is the
only allocation.

Requires `n ≥ 1`, `κ` and `σ` finite and strictly positive, and `μ` finite;
anything else throws an `ArgumentError`. Every returned value is checked to be
finite.
"""
function sample_stationary(
    rng::AbstractRNG,
    n::Integer,
    kappa::Real,
    mu::Real,
    sigma::Real,
)
    count = _check_count(n, "the number of samples")
    centre = _check_finite(mu, "the long-run mean")
    deviation = stationary_standard_deviation(kappa, sigma)
    sample = Vector{Float64}(undef, count)
    for i in eachindex(sample)
        value = centre + deviation * randn(rng)
        isfinite(value) || throw(
            ArgumentError(
                "the sampled values must be finite; element $i overflows the Float64 " *
                "numerical domain",
            ),
        )
        sample[i] = value
    end
    return sample
end

"""
    simulate_exact_path(rng::AbstractRNG, nsteps::Integer, h::Real, kappa::Real,
                        mu::Real, sigma::Real, x0::Real) -> Vector{Float64}

Integrate one path exactly on a uniform grid of `nsteps` steps of length `h`,
starting from `x₀`.

The returned vector has `nsteps + 1` elements and **includes the initial point**:
`path[1]` is `x₀` and `path[k+1]` is the state after `k` steps. Its
finite-dimensional distributions on the grid are exactly those of the process,
because each step is drawn from the exact transition law.

The transition coefficients are computed once and reused, in the same arithmetic
form [`exact_step`](@ref) uses, so this loop and repeated calls to that function
produce identical values from identical streams.

Passing `x₀` from [`sample_stationary`](@ref) yields a path that is stationary
from its first point, so no burn-in is required and none is performed. A path
started anywhere else is not stationary, and a correlated summary of it would
violate the stationarity its estimator assumes.

Requires `nsteps ≥ 1`, `h`, `κ` and `σ` finite and strictly positive, and `μ` and
`x₀` finite; anything else throws an `ArgumentError`. Every value is checked to be
finite. The returned vector is the only allocation.
"""
function simulate_exact_path(
    rng::AbstractRNG,
    nsteps::Integer,
    h::Real,
    kappa::Real,
    mu::Real,
    sigma::Real,
    x0::Real,
)
    count = _check_count(nsteps, "the number of steps")
    centre = _check_finite(mu, "the long-run mean")
    start = _check_finite(x0, "the initial value")
    coefficients = exact_transition_coefficients(kappa, sigma, h)
    decay = coefficients.decay
    innovation_std = coefficients.innovation_std
    path = Vector{Float64}(undef, count + 1)
    path[1] = start
    for k in 1:count
        value = centre + decay * (path[k] - centre) + innovation_std * randn(rng)
        isfinite(value) || throw(
            ArgumentError(
                "the path must remain finite; step $k overflows the Float64 " *
                "numerical domain",
            ),
        )
        path[k+1] = value
    end
    return path
end

"""
    simulate_exact_paths(rng::AbstractRNG, npaths::Integer, horizon::Real, h::Real,
                         kappa::Real, mu::Real, sigma::Real, x0::Real) -> Matrix{Float64}

Integrate `npaths` independent exact paths over `horizon`, on a uniform grid of
step `h`, each starting from `x₀`.

The horizon must be a whole number of steps. The ratio `horizon / h` is compared
with its nearest integer under `_GRID_RELATIVE_TOLERANCE` and a ratio that fails
the comparison is **rejected rather than rounded**, so a grid the caller did not
ask for is never silently substituted.

The result has `nsteps + 1` rows and `npaths` columns: column `j` is one complete
path including its initial point, laid out contiguously, so that a caller
plotting or reducing a single trajectory walks memory in order. The paths are
generated one after another from the single supplied generator and are mutually
independent.

The paths of this case are **illustrative**. They show what a realisation looks
like; no reported quantity is estimated from them, and a dozen trajectories
support no inference.

Requires `npaths ≥ 1`, a horizon that is a whole number of steps, `h`, `κ` and
`σ` finite and strictly positive, and `μ` and `x₀` finite; anything else throws
an `ArgumentError`. The returned matrix is the only allocation.
"""
function simulate_exact_paths(
    rng::AbstractRNG,
    npaths::Integer,
    horizon::Real,
    h::Real,
    kappa::Real,
    mu::Real,
    sigma::Real,
    x0::Real,
)
    count = _check_count(npaths, "the number of paths")
    span = _check_time(horizon, "the horizon")
    step = _check_step(h)
    nsteps = _grid_steps(span, step)
    centre = _check_finite(mu, "the long-run mean")
    start = _check_finite(x0, "the initial value")
    coefficients = exact_transition_coefficients(kappa, sigma, step)
    decay = coefficients.decay
    innovation_std = coefficients.innovation_std
    paths = Matrix{Float64}(undef, nsteps + 1, count)
    for j in 1:count
        paths[1, j] = start
        for k in 1:nsteps
            value = centre + decay * (paths[k, j] - centre) + innovation_std * randn(rng)
            isfinite(value) || throw(
                ArgumentError(
                    "the paths must remain finite; step $k of path $j overflows the " *
                    "Float64 numerical domain",
                ),
            )
            paths[k+1, j] = value
        end
    end
    return paths
end

"""
    sample_euler_stationary_step(rng::AbstractRNG, n::Integer, h::Real, kappa::Real,
                                 mu::Real, sigma::Real) -> Vector{Float64}

Draw `n` independent endpoints of the experiment that isolates the finite-step
bias of the Euler–Maruyama scheme: start in the scheme's **own** invariant
distribution, and take exactly one step.

Each observation is formed by drawing an initial value from
`Normal(μ, v_EM(h))`, the exact invariant law of the Euler recursion given by
[`euler_stationary_variance`](@ref), and applying one Euler step to it. The
recursion preserves that law exactly, so the endpoints are distributed as
`Normal(μ, v_EM(h))` too, and their sample variance estimates `v_EM(h)` with
sampling error alone.

This is what makes the experiment a clean measurement. Relaxing towards the Euler
invariant law from an arbitrary start would confound the finite-step bias with an
unconverged transient, and would require a burn-in whose length would then have
to be justified. **There is no horizon and no burn-in here**: the design removes
the need for both by beginning in the invariant law, exactly, at every step size.

Two draws are made per observation, in the order initial value then innovation.
The observations are mutually independent of one another. The step is applied in
exactly the arithmetic form [`euler_step`](@ref) uses, so this loop and repeated
calls to that function agree bit for bit given the same stream.

Requires `n ≥ 1`, `h`, `κ` and `σ` finite and strictly positive, `μ` finite, and
`0 < κh < 2`; anything else throws an `ArgumentError`. Every returned value is
checked to be finite. The returned vector is the only allocation.
"""
function sample_euler_stationary_step(
    rng::AbstractRNG,
    n::Integer,
    h::Real,
    kappa::Real,
    mu::Real,
    sigma::Real,
)
    count = _check_count(n, "the number of samples")
    rate = _check_rate(kappa)
    centre = _check_finite(mu, "the long-run mean")
    scale = _check_scale(sigma)
    step = _check_step(h)
    initial_std = sqrt(euler_stationary_variance(rate, scale, step))
    noise_std = scale * sqrt(step)
    sample = Vector{Float64}(undef, count)
    for i in eachindex(sample)
        state = centre + initial_std * randn(rng)
        value = state + rate * (centre - state) * step + noise_std * randn(rng)
        isfinite(value) || throw(
            ArgumentError(
                "the sampled values must be finite; element $i overflows the Float64 " *
                "numerical domain at h = $h",
            ),
        )
        sample[i] = value
    end
    return sample
end
