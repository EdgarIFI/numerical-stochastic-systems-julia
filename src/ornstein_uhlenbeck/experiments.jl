# The four experiments of the case, and the assembly of their reported values.
#
# Each experiment is a function of an explicit generator and a resolved parameter
# set, and returns a `NamedTuple` of plain arrays and scalars. There is no result
# type, no abstract experiment interface, and no registry: five experiments in one
# case do not justify a framework, and G3-D.10 fixes named tuples and arrays as
# the representation until repeated evidence says otherwise.
#
# The four scientific regimes are deliberately distinct, and each isolates one
# thing.
#
#   1. A transient ensemble from a deterministic start, which tests the
#      time-dependent moments against their closed forms.
#   2. An independent ensemble drawn from the invariant law, which tests the
#      stationary moments with no correlation to correct for.
#   3. One long stationary path, which is the only correlated regime and the only
#      place an autocorrelation, an integrated autocorrelation time, or an
#      effective sample size appears.
#   4. A discrete-stationary one-step Euler experiment, which measures the bias of
#      the scheme's own invariant variance at several step sizes.
#
# Regimes 1 to 3 are sampled exactly, so their only error is sampling error.
# Regime 4 is the one place the Euler scheme is used at all.

"""
    CASE_SLUG

The directory name of this case study, `"06-ornstein-uhlenbeck"`, as fixed by the
frozen taxonomy in `case-studies/README.md`. It is the value recorded as the case
in a reference summary, and it is stated once here rather than repeated as a
literal in the driver, the record, and the tests.
"""
const CASE_SLUG = "06-ornstein-uhlenbeck"

"""
    MASTER_SEED

The single master seed of this case study.

Every stochastic quantity the case reports is a pure function of this one
integer: the nine substream seeds are derived from it by `derive_seeds`, and each
experiment consumes exactly one of them. Recording it, together with the preset
and the committed manifest, is what makes a run reproducible.

It lies in `0 ≤ seed ≤ typemax(Int64)`, as `derive_seeds` requires, so that it is
an ordinary nonnegative integer whatever integer type a caller uses and can be
recorded as the TOML integer provenance seed.
"""
const MASTER_SEED = 6_060_606

"""
    SEED_SLOTS

The number of substreams the case derives, `9`, and therefore the length of the
vector `derive_seeds(MASTER_SEED, SEED_SLOTS)` returns.

The slots are **semantic and fixed**: slot `i` always means the same thing,
whatever preset is run.

| Slot | Consumer |
| --- | --- |
| 1 | exact transient ensemble |
| 2 | exact stationary independent ensemble |
| 3 | exact stationary long path |
| 4 | representative exact trajectories |
| 5 | Euler study, `h = 0.4` |
| 6 | Euler study, `h = 0.2` |
| 7 | Euler study, `h = 0.1` |
| 8 | Euler study, `h = 0.05` |
| 9 | Euler study, `h = 0.025` |

All nine are derived under every preset, including the smoke preset whose Euler
grid uses only the first three of the five Euler slots. Deriving the same nine
regardless is what makes the smoke run a genuine prefix of the production run:
`derive_seeds` is prefix-preserving, so slot `k` holds the same value in every
run of the case, and enlarging the Euler grid extends the set of substreams
rather than renumbering it.

The Euler grids are themselves prefixes — `[0.4, 0.2, 0.1]` under the smoke
preset, extended by `0.05` and `0.025` under the others — so the step at position
`j` of a preset's grid is always the step of slot `4 + j`.
"""
const SEED_SLOTS = 9

"""
    _EULER_SLOT_OFFSET

The number of seed slots preceding the Euler block, so that the study of the
`j`th step of a preset's Euler grid uses slot `_EULER_SLOT_OFFSET + j`.
"""
const _EULER_SLOT_OFFSET = 4

"""
    OU_PRESETS

The parameter values this case declares for each of the three shared execution
presets.

The shared layer fixes only the vocabulary `(:smoke, :figure, :production)` under
G3-D.4; what a preset means numerically is a scientific property of the case, and
it is stated here. The scientific parameters — `kappa`, `mu`, `sigma`, `x0` — are
identical across all three presets, because a preset changes how much evidence is
gathered and never which process is being studied. Only the sample sizes, the
path length, the Euler grid, and the number of illustrative trajectories differ.

All three entries share **one concrete `NamedTuple` type**, so that
`preset_parameters(OU_PRESETS, preset)` infers a concrete return type and a
driver's downstream code is type-stable in the preset it was given. That is why
the two grids are `Vector{Float64}` rather than tuples: `euler_steps` has three
elements under the smoke preset and five under the others, and a tuple would give
the three parameter sets three different types.

The vectors are **not copied on lookup**. `ou_parameters` returns the parameter
set exactly as `preset_parameters` yields it, so the grids are shared with this
constant and must be treated as read-only; the experiments copy them into their
results rather than storing the references.

`reference_eligible` is a control flag rather than a scientific parameter: it
records that only the production preset gathers enough evidence for a committed
reference summary, and it is deliberately absent from
[`reference_parameters`](@ref).

| Field | Meaning |
| --- | --- |
| `kappa` | mean-reversion rate `κ > 0` |
| `mu` | long-run mean `μ` |
| `sigma` | noise amplitude `σ > 0` |
| `x0` | deterministic initial value of the transient ensemble |
| `transient_times` | times at which the transient moments are tested |
| `transient_paths` | independent draws per transient time |
| `stationary_samples` | independent draws from the invariant law |
| `long_path_length` | number of points on the correlated stationary path |
| `correlation_step` | observation step `h` of that path |
| `maxlag` | explicit lag window for the autocorrelation and `τ_int` |
| `euler_steps` | Euler step sizes studied |
| `euler_paths` | independent one-step endpoints per Euler step |
| `representative_paths` | illustrative trajectories drawn for the figure |
| `representative_horizon` | horizon of those trajectories |
| `representative_step` | grid step of those trajectories |
| `reference_eligible` | whether the preset may write a committed reference |
"""
const OU_PRESETS = (
    smoke = (
        kappa = 1.0,
        mu = 1.0,
        sigma = 1.0,
        x0 = -1.0,
        transient_times = [0.25, 0.5, 1.0, 2.0, 4.0],
        transient_paths = 4_000,
        stationary_samples = 4_000,
        long_path_length = 20_000,
        correlation_step = 0.1,
        maxlag = 40,
        euler_steps = [0.4, 0.2, 0.1],
        euler_paths = 4_000,
        representative_paths = 4,
        representative_horizon = 5.0,
        representative_step = 0.02,
        reference_eligible = false,
    ),
    figure = (
        kappa = 1.0,
        mu = 1.0,
        sigma = 1.0,
        x0 = -1.0,
        transient_times = [0.25, 0.5, 1.0, 2.0, 4.0],
        transient_paths = 30_000,
        stationary_samples = 30_000,
        long_path_length = 100_000,
        correlation_step = 0.1,
        maxlag = 80,
        euler_steps = [0.4, 0.2, 0.1, 0.05, 0.025],
        euler_paths = 30_000,
        representative_paths = 12,
        representative_horizon = 5.0,
        representative_step = 0.02,
        reference_eligible = false,
    ),
    production = (
        kappa = 1.0,
        mu = 1.0,
        sigma = 1.0,
        x0 = -1.0,
        transient_times = [0.25, 0.5, 1.0, 2.0, 4.0],
        transient_paths = 200_000,
        stationary_samples = 200_000,
        long_path_length = 250_000,
        correlation_step = 0.1,
        maxlag = 80,
        euler_steps = [0.4, 0.2, 0.1, 0.05, 0.025],
        euler_paths = 200_000,
        representative_paths = 12,
        representative_horizon = 5.0,
        representative_step = 0.02,
        reference_eligible = true,
    ),
)

"""
    ou_parameters(preset::Symbol) -> NamedTuple

Resolve the parameter set this case declares for `preset`.

A thin call to the shared `preset_parameters` over [`OU_PRESETS`](@ref): the
shared function validates the preset name and the shape of the table, and this
one supplies the table. An unrecognised preset throws an `ArgumentError` naming
the valid ones, and there is no fallback and no environment-variable override.

The returned parameter set is the declared one, unmodified and uncopied.
"""
ou_parameters(preset::Symbol) = preset_parameters(OU_PRESETS, preset)

"""
    _variance_standard_error(analytic_variance::Real, n::Integer) -> Float64

The standard error of the sample variance of `n` independent Gaussian
observations whose true variance is `analytic_variance`:

    SE(s²) = σ² √(2 / (n − 1))

For a Gaussian sample, `(n − 1)s²/σ²` is chi-squared on `n − 1` degrees of
freedom, so `Var(s²) = 2σ⁴/(n − 1)` **exactly**. Every ensemble this case
summarises is exactly Gaussian by construction — the exact transition law, the
exact invariant law, and the Euler invariant law are all Gaussian — so the
expression is the exact standard error here rather than a large-sample
approximation.

The **analytical** variance is used as `σ²` rather than the measured one, so the
uncertainty against which a discrepancy is judged is a fixed reference quantity
and not itself an estimate that moves with the sample.

Using the standard error of the *mean* to judge a variance would be a category
error, and a large one: the two differ by a factor of order `σ√(n/2)`. It is
named here so that the distinction is visible at the point of use.

Requires `n ≥ 2` and a finite, strictly positive variance.
"""
function _variance_standard_error(analytic_variance::Real, n::Integer)
    variance = Float64(analytic_variance)
    (isfinite(variance) && variance > 0) || throw(
        ArgumentError(
            "the analytical variance must be finite and > 0, got $analytic_variance",
        ),
    )
    n >= 2 || throw(
        ArgumentError(
            "the standard error of a sample variance requires at least 2 " *
            "observations, got n = $n",
        ),
    )
    return variance * sqrt(2 / (n - 1))
end

"""
    run_transient_experiment(rng::AbstractRNG, params::NamedTuple) -> NamedTuple

Test the transient mean and variance against their closed forms at each time of
`params.transient_times`.

At each time an independent ensemble of `params.transient_paths` values of `X_t`
is drawn **directly** from the exact marginal law of the process started at
`params.x0`, by [`sample_exact_terminal`](@ref). The mean is summarised with the
shared `summarize_independent` and the variance with the exact Gaussian standard
error of [`_variance_standard_error`](@ref); both discrepancies are expressed in
standard errors by the shared `nsigma`.

The ensembles at the several times are drawn one after another from the single
supplied generator, so they are not independent of one another as sequences of
draws — they are consecutive segments of one stream. That is immaterial to what
is tested: each time is compared with its own closed form separately, and no
statement is made about the joint behaviour across times.

Returns `(times, analytic_mean, empirical_mean, mean_sem, mean_nsigma,
analytic_variance, empirical_variance, variance_se, variance_nsigma, n)`, where
every array is indexed by time and `times` is a copy that does not alias the
preset.
"""
function run_transient_experiment(rng::AbstractRNG, params::NamedTuple)
    times = collect(Float64, params.transient_times)
    isempty(times) && throw(ArgumentError("the transient time grid must be nonempty"))
    n = params.transient_paths
    count = length(times)
    analytic_mean = Vector{Float64}(undef, count)
    empirical_mean = Vector{Float64}(undef, count)
    mean_sem = Vector{Float64}(undef, count)
    mean_nsigma = Vector{Float64}(undef, count)
    analytic_variance = Vector{Float64}(undef, count)
    empirical_variance = Vector{Float64}(undef, count)
    variance_se = Vector{Float64}(undef, count)
    variance_nsigma = Vector{Float64}(undef, count)
    for (i, t) in enumerate(times)
        sample = sample_exact_terminal(
            rng,
            n,
            t,
            params.kappa,
            params.mu,
            params.sigma,
            params.x0,
        )
        summary = summarize_independent(sample)
        analytic_mean[i] = transient_mean(t, params.kappa, params.mu, params.x0)
        empirical_mean[i] = summary.mean
        mean_sem[i] = summary.sem
        mean_nsigma[i] = nsigma(summary.mean, analytic_mean[i], summary.sem)
        analytic_variance[i] = transient_variance(t, params.kappa, params.sigma)
        empirical_variance[i] = var(sample)
        variance_se[i] = _variance_standard_error(analytic_variance[i], n)
        variance_nsigma[i] =
            nsigma(empirical_variance[i], analytic_variance[i], variance_se[i])
    end
    return (
        times = times,
        analytic_mean = analytic_mean,
        empirical_mean = empirical_mean,
        mean_sem = mean_sem,
        mean_nsigma = mean_nsigma,
        analytic_variance = analytic_variance,
        empirical_variance = empirical_variance,
        variance_se = variance_se,
        variance_nsigma = variance_nsigma,
        n = n,
    )
end

"""
    run_stationary_experiment(rng::AbstractRNG, params::NamedTuple) -> NamedTuple

Test the mean and variance of the invariant distribution against their closed
forms, from an independent ensemble drawn exactly from that distribution.

`params.stationary_samples` values are drawn by [`sample_stationary`](@ref).
Because the invariant law is sampled directly, the ensemble is in equilibrium by
construction: **nothing is discarded as burn-in**, and no claim about the length
of a burn-in is needed or made. The observations are independent, so the shared
`summarize_independent` applies without an autocorrelation correction — which is
precisely what separates this experiment from the correlated one that follows it.

Returns `(analytic_mean, empirical_mean, mean_sem, mean_nsigma,
analytic_variance, empirical_variance, variance_se, variance_nsigma, n)`.
"""
function run_stationary_experiment(rng::AbstractRNG, params::NamedTuple)
    n = params.stationary_samples
    sample = sample_stationary(rng, n, params.kappa, params.mu, params.sigma)
    summary = summarize_independent(sample)
    analytic_mean = Float64(params.mu)
    analytic_variance = stationary_variance(params.kappa, params.sigma)
    empirical_variance = var(sample)
    variance_se = _variance_standard_error(analytic_variance, n)
    return (
        analytic_mean = analytic_mean,
        empirical_mean = summary.mean,
        mean_sem = summary.sem,
        mean_nsigma = nsigma(summary.mean, analytic_mean, summary.sem),
        analytic_variance = analytic_variance,
        empirical_variance = empirical_variance,
        variance_se = variance_se,
        variance_nsigma = nsigma(empirical_variance, analytic_variance, variance_se),
        n = n,
    )
end

"""
    run_correlated_experiment(rng::AbstractRNG, params::NamedTuple) -> NamedTuple

Measure the temporal correlation structure of the stationary process from one
long path, and correct the uncertainty of its mean accordingly.

The path is started at a value drawn from the exact invariant law and integrated
exactly on a grid of step `params.correlation_step`, so it is **stationary from
its first point**. No burn-in is discarded, because none is needed: a burn-in
exists to remove the memory of an arbitrary initial condition, and there is no
arbitrary initial condition here.

The empirical autocorrelations at lags `0:params.maxlag` are estimated with
`StatsBase.autocor`, and the mean is summarised by the shared
`summarize_correlated` over the same explicit window. The window is the caller's
scientific responsibility under G3-CORR.1 and is fixed by the preset; it is not
selected adaptively and is not tuned against the result.

Three comparisons are formed.

  - `tau_exact_window` is the analytical integrated autocorrelation time summed
    over **the same finite window**, obtained by passing the exact
    autocorrelations to the shared `integrated_autocorrelation_time`. The
    comparator is computed with the same shared estimator and the same window as
    the measurement, so the two differ only in whether the autocorrelations were
    measured or computed. Comparing against the infinite-window limit instead
    would charge the deliberate truncation of the sum to the estimate.
  - `acf_rmse` is the root mean squared difference between the measured and exact
    autocorrelation series over the window.
  - `mean_nsigma` compares the sample mean with `μ` using the
    autocorrelation-corrected standard error, not the independent one.

Returns `(path, lags, acf_empirical, acf_analytic, summary, tau_exact_window,
tau_relative_error, acf_rmse, mean_nsigma)`, where `summary` is the shared
correlated summary and therefore carries `tau_int`, `ess`, `sem`, and the
approximate interval.

The autocorrelations are estimated twice — once here for the series that is
reported and compared, and once inside `summarize_correlated`, which forms its
own. The duplication is deliberate: the shared summary owns its estimator, and
reproducing its internals here to save one pass would couple this case to them.
"""
function run_correlated_experiment(rng::AbstractRNG, params::NamedTuple)
    length_ = params.long_path_length
    length_ >= 2 || throw(
        ArgumentError(
            "the correlated path must have at least 2 points, got " *
            "long_path_length = $length_",
        ),
    )
    maxlag = params.maxlag
    start = sample_stationary(rng, 1, params.kappa, params.mu, params.sigma)[1]
    path = simulate_exact_path(
        rng,
        length_ - 1,
        params.correlation_step,
        params.kappa,
        params.mu,
        params.sigma,
        start,
    )
    lags = collect(0:maxlag)
    acf_empirical = collect(Float64, autocor(path, lags))
    acf_analytic = [
        exact_autocorrelation(k * params.correlation_step, params.kappa) for k in lags
    ]
    summary = summarize_correlated(path; maxlag = maxlag)
    tau_exact_window = integrated_autocorrelation_time(acf_analytic; maxlag = maxlag)
    return (
        path = path,
        lags = lags,
        acf_empirical = acf_empirical,
        acf_analytic = acf_analytic,
        summary = summary,
        tau_exact_window = tau_exact_window,
        tau_relative_error = relative_error(summary.tau_int, tau_exact_window),
        acf_rmse = rmse(acf_empirical, acf_analytic),
        mean_nsigma = nsigma(summary.mean, params.mu, summary.sem),
    )
end

"""
    _fit_positive_empirical_bias(
        steps::AbstractVector{<:Real},
        empirical_bias::AbstractVector{<:Real},
    ) -> Union{NamedTuple,Nothing}

Fit the measured Euler biases against the step sizes on logarithmic axes, or
report that no such fit is defined.

The shared `fit_loglog` requires strictly positive ordinates, and a measured bias
is a **signed** random quantity: at a step whose bias is comparable with its own
sampling error, a perfectly valid realisation may come out zero or negative. The
log-log fit is then undefined — but the simulation that produced it is not
wrong, and refusing the whole result because of it would make a scientifically
valid run fail for a reason unrelated to the validity of the model. This helper
therefore separates the two cases:

  - every bias finite and strictly positive — return `fit_loglog(steps, empirical_bias)`;
  - any bias finite and `≤ 0` — return `nothing`, the fit being undefined;
  - any bias non-finite — throw, that being a broken simulation and not an
    unlucky one.

**The biases pass through untouched.** No absolute value is taken, no floor,
clamp, or epsilon is applied, no point is dropped, and nothing is redrawn: the
signed bias is the reported scientific observable, and suppressing its sign to
keep a fit alive would substitute a fiction for a measurement.

The errors `fit_loglog` raises for its own reasons — fewer than three points, a
constant `log(x)`, a constant `log(y)` — are deliberately not caught, because
each signals a malformed grid rather than a noisy one, and the shared contract is
not weakened here.
"""
function _fit_positive_empirical_bias(
    steps::AbstractVector{<:Real},
    empirical_bias::AbstractVector{<:Real},
)
    for (i, bias) in enumerate(empirical_bias)
        isfinite(bias) || throw(
            ArgumentError(
                "every measured Euler bias must be finite; element $i is $bias",
            ),
        )
    end
    all(>(0), empirical_bias) || return nothing
    return fit_loglog(steps, empirical_bias)
end

"""
    run_euler_experiment(seeds::AbstractVector{UInt64}, params::NamedTuple) -> NamedTuple

Measure the finite-step bias of the Euler–Maruyama invariant variance across
`params.euler_steps`.

Each step size receives **its own substream**, seeded from the corresponding
semantic slot of [`SEED_SLOTS`](@ref), so that the points of the study are
mutually independent and each is reproducible on its own. `seeds` holds exactly
those seeds, one per step, in the order of the grid; a mismatched length is an
error rather than a silent truncation. The steps are run one after another in a
single thread.

For each step, [`sample_euler_stationary_step`](@ref) draws
`params.euler_paths` independent endpoints of the discrete-stationary one-step
experiment. Two quantities follow:

  - the endpoint variance is compared with `v_EM(h)`, the exact invariant
    variance of the Euler recursion, which checks that the experiment measures
    what it claims to;
  - the bias relative to the exact stationary variance `σ²/(2κ)` of the process
    is reported both as measured and as predicted by
    [`euler_stationary_bias`](@ref).

Both bias sequences are then fitted against the step sizes by the shared
`fit_loglog`. `analytic_fit` is a fit to an exact formula and is a description of
its behaviour **on this grid**; `empirical_fit` is the same fit to measured
biases. Neither is an asymptotic statement: no order of convergence outside the
tested grid is claimed, and the fitted slope of a three-point grid has one
residual degree of freedom and correspondingly little to say.

The two fits differ in one respect. `analytic_fit` always exists, the analytical
bias being strictly positive throughout the admissible interval. `empirical_fit`
is **optional** — a `NamedTuple` when every measured bias is strictly positive
and `nothing` otherwise — because the measured bias is signed and may, at a step
whose bias is comparable with its own sampling error, come out zero or negative.
Such a run is an unremarkable statistical realisation rather than a failure, so
the Euler result is returned complete and only the fit is reported as
unavailable; see [`_fit_positive_empirical_bias`](@ref), which takes no absolute
value, drops no point, and redraws nothing.

`empirical_bias` is signed throughout and is the reported observable:

    empirical_bias[i] = empirical_variance[i] − exact_ou_variance

Returns `(steps, analytic_euler_variance, empirical_variance, variance_se,
variance_nsigma, exact_ou_variance, analytic_bias, empirical_bias, analytic_fit,
empirical_fit, n)`, with `empirical_fit` a `NamedTuple` or `nothing`.
"""
function run_euler_experiment(seeds::AbstractVector{UInt64}, params::NamedTuple)
    steps = collect(Float64, params.euler_steps)
    count = length(steps)
    count >= 3 || throw(
        ArgumentError(
            "the Euler study is fitted by log-log least squares and requires at " *
            "least 3 step sizes, got $count",
        ),
    )
    length(seeds) == count || throw(
        ArgumentError(
            "the Euler study needs exactly one seed per step size, got " *
            "$(length(seeds)) seeds for $count steps",
        ),
    )
    n = params.euler_paths
    exact_ou_variance = stationary_variance(params.kappa, params.sigma)
    analytic_euler_variance = Vector{Float64}(undef, count)
    empirical_variance = Vector{Float64}(undef, count)
    variance_se = Vector{Float64}(undef, count)
    variance_nsigma = Vector{Float64}(undef, count)
    analytic_bias = Vector{Float64}(undef, count)
    empirical_bias = Vector{Float64}(undef, count)
    for (i, h) in enumerate(steps)
        rng = Xoshiro(seeds[i])
        sample = sample_euler_stationary_step(
            rng,
            n,
            h,
            params.kappa,
            params.mu,
            params.sigma,
        )
        analytic_euler_variance[i] =
            euler_stationary_variance(params.kappa, params.sigma, h)
        empirical_variance[i] = var(sample)
        variance_se[i] = _variance_standard_error(analytic_euler_variance[i], n)
        variance_nsigma[i] = nsigma(
            empirical_variance[i],
            analytic_euler_variance[i],
            variance_se[i],
        )
        analytic_bias[i] = euler_stationary_bias(params.kappa, params.sigma, h)
        empirical_bias[i] = empirical_variance[i] - exact_ou_variance
    end
    return (
        steps = steps,
        analytic_euler_variance = analytic_euler_variance,
        empirical_variance = empirical_variance,
        variance_se = variance_se,
        variance_nsigma = variance_nsigma,
        exact_ou_variance = exact_ou_variance,
        analytic_bias = analytic_bias,
        empirical_bias = empirical_bias,
        analytic_fit = fit_loglog(steps, analytic_bias),
        empirical_fit = _fit_positive_empirical_bias(steps, empirical_bias),
        n = n,
    )
end

"""
    run_representative_paths(rng::AbstractRNG, params::NamedTuple) -> NamedTuple

Draw a handful of exact trajectories from `params.x0`, for illustration.

The trajectories show what a realisation of the process looks like: the decay of
the initial displacement towards `μ` and the fluctuations about it. They are
**illustrative and not inferential**. Nothing is estimated from them, no reported
value depends on them, and a dozen paths would support no statistical claim if
one were attempted.

The grid is uniform with `params.representative_paths` trajectories over
`params.representative_horizon` at step `params.representative_step`, and the
horizon is required to be a whole number of steps. The time grid is formed by
integer multiplication rather than by accumulating the step, so no grid point is
reached through accumulated rounding error.

Returns `(times, paths)`, with `times` of length `nsteps + 1` and `paths` of size
`(nsteps + 1) × representative_paths`, one trajectory per column, each including
its initial point.
"""
function run_representative_paths(rng::AbstractRNG, params::NamedTuple)
    paths = simulate_exact_paths(
        rng,
        params.representative_paths,
        params.representative_horizon,
        params.representative_step,
        params.kappa,
        params.mu,
        params.sigma,
        params.x0,
    )
    nsteps = size(paths, 1) - 1
    step = Float64(params.representative_step)
    times = [k * step for k in 0:nsteps]
    return (times = times, paths = paths)
end

"""
    run_case_study(preset::Symbol; master_seed::Integer = MASTER_SEED) -> NamedTuple

Run the whole case study at `preset` and return every result in one named tuple.

The parameters are resolved from [`OU_PRESETS`](@ref) and the nine substream
seeds are derived from `master_seed` by the shared `derive_seeds`. Each
experiment then receives a fresh canonical `Xoshiro` seeded from its own semantic
slot, so the experiments are mutually independent, each is reproducible on its
own, and the whole run is a pure function of the single master seed. Execution is
serial and nothing is threaded.

**This function computes and returns; it writes nothing.** No file is created, no
directory is created, and no figure is rendered, whatever the preset. Writing a
figure or a reference summary is the driver's business and is guarded there, so
that running the case study from a test or a REPL cannot leave anything behind.

Returns `(preset, parameters, seeds, transient, stationary, correlated, euler,
representative)`. The `seeds` field carries the derived `UInt64` values in memory
for inspection; they are **not** a durable payload and are never recorded in a
reference summary, where only the master seed appears.

The result is complete for **any** valid master seed. In particular a run whose
`euler.empirical_fit` is `nothing` is a valid scientific result and not a
failure: the empirical log-log fit is optional at this level, and only the
assembly of a committed reference summary demands it. Nothing here narrows the
master seed to the canonical [`MASTER_SEED`](@ref) or quietly substitutes it for
one that was supplied.

Requires a valid preset, an Euler grid no longer than the five Euler slots, and a
master seed in `0 ≤ seed ≤ typemax(Int64)`; anything else throws an
`ArgumentError`.
"""
function run_case_study(preset::Symbol; master_seed::Integer = MASTER_SEED)
    params = ou_parameters(preset)
    euler_count = length(params.euler_steps)
    euler_count <= SEED_SLOTS - _EULER_SLOT_OFFSET || throw(
        ArgumentError(
            "the case derives $(SEED_SLOTS - _EULER_SLOT_OFFSET) Euler seed slots, " *
            "but the `:$preset` preset declares $euler_count step sizes",
        ),
    )
    seeds = derive_seeds(master_seed, SEED_SLOTS)
    transient = run_transient_experiment(Xoshiro(seeds[1]), params)
    stationary = run_stationary_experiment(Xoshiro(seeds[2]), params)
    correlated = run_correlated_experiment(Xoshiro(seeds[3]), params)
    representative = run_representative_paths(Xoshiro(seeds[4]), params)
    euler = run_euler_experiment(
        seeds[(_EULER_SLOT_OFFSET+1):(_EULER_SLOT_OFFSET+euler_count)],
        params,
    )
    return (
        preset = preset,
        parameters = params,
        seeds = seeds,
        transient = transient,
        stationary = stationary,
        correlated = correlated,
        euler = euler,
        representative = representative,
    )
end

"""
    _KEY_SCALE_TOLERANCE

The absolute agreement with its nearest integer that a scaled grid value must
show before it is used to form a reference-summary key.

A key such as `euler_variance_h0025` encodes its step size as an integer, and the
encoding must be exact: two steps that scaled to the same integer would collapse
onto one key and one result would be lost. The scaled value is therefore required
to agree with its nearest integer to within this **internal numerical acceptance
tolerance**, which admits the representation error of a decimal grid value in
binary and nothing wider. It is not a scientific tolerance.
"""
const _KEY_SCALE_TOLERANCE = 1.0e-6

"""
    _grid_tag(value::Real, scale::Integer, width::Integer, name::AbstractString) -> String

Encode a grid value as the fixed-width zero-padded integer `round(value * scale)`
used inside a reference-summary key.

Transient times are encoded at `scale = 100` in three digits, so `0.25` becomes
`"025"` and `4.0` becomes `"400"`. Euler steps are encoded at `scale = 1000` in
four digits, so `0.4` becomes `"0400"` and `0.025` becomes `"0025"`. A value that
does not scale to an integer within `_KEY_SCALE_TOLERANCE`, that is negative, or
whose encoding does not fit `width` digits throws an `ArgumentError` naming it:
the key set of a committed record must be determined by the grid and never by a
rounding accident.
"""
function _grid_tag(value::Real, scale::Integer, width::Integer, name::AbstractString)
    scaled = Float64(value) * scale
    isfinite(scaled) ||
        throw(ArgumentError("$name must be finite to form a key, got $value"))
    nearest = round(scaled)
    abs(scaled - nearest) <= _KEY_SCALE_TOLERANCE || throw(
        ArgumentError(
            "$name = $value does not scale to an integer at a factor of $scale, " *
            "giving $scaled; a reference-summary key must encode its grid value " *
            "exactly",
        ),
    )
    0 <= nearest <= typemax(Int) ||
        throw(ArgumentError("$name = $value scales outside the encodable range"))
    digits = string(Int(nearest))
    length(digits) <= width || throw(
        ArgumentError(
            "$name = $value encodes as \"$digits\", which does not fit the $width " *
            "digits the key reserves for it",
        ),
    )
    return lpad(digits, width, '0')
end

"""
    _named_tuple(names::Vector{Symbol}, entries::Vector) -> NamedTuple

Assemble a named tuple from parallel vectors of field names and values, rejecting
a repeated name.

The key set of [`reference_values`](@ref) depends on the preset's grids, so it is
built rather than written out. A duplicate name would silently drop a result,
which is exactly the failure the explicit encoding of [`_grid_tag`](@ref) exists
to prevent, so it is caught here as well.
"""
function _named_tuple(names::Vector{Symbol}, entries::Vector)
    length(names) == length(entries) ||
        throw(ArgumentError("the field names and values must correspond one to one"))
    allunique(names) || throw(
        ArgumentError(
            "the assembled record carries a repeated result name; the grid encoding " *
            "is not injective",
        ),
    )
    return NamedTuple{Tuple(names)}(Tuple(entries))
end

"""
    reference_parameters(result::NamedTuple) -> NamedTuple

Assemble the `[parameters]` table of a schema version 1 reference summary from a
completed [`run_case_study`](@ref) result.

The table records the **resolved** values that produced the results — the numbers
actually used after the preset was applied — together with the two derived scales
a reader needs in order to interpret them, the relaxation time `1/κ` and the
stationary variance `σ²/(2κ)`. The preset name is not a parameter; it is recorded
in the provenance table instead.

`reference_eligible` is deliberately absent: it controls whether the driver may
write a record at all and says nothing about the process. No Euler horizon
appears either, because the Euler experiment has none — it takes exactly one step
from the scheme's own invariant law.

The grids are copied, so the returned table does not alias [`OU_PRESETS`](@ref).
Every field is a durable TOML payload: a finite `Float64`, an `Int` inside the
signed 64-bit range, or a homogeneous vector of one of those.
"""
function reference_parameters(result::NamedTuple)
    params = result.parameters
    return (
        kappa = Float64(params.kappa),
        mu = Float64(params.mu),
        sigma = Float64(params.sigma),
        x0 = Float64(params.x0),
        relaxation_time = relaxation_time(params.kappa),
        stationary_variance = stationary_variance(params.kappa, params.sigma),
        transient_times = collect(Float64, params.transient_times),
        transient_paths = params.transient_paths,
        stationary_samples = params.stationary_samples,
        long_path_length = params.long_path_length,
        correlation_step = Float64(params.correlation_step),
        maxlag = params.maxlag,
        euler_steps = collect(Float64, params.euler_steps),
        euler_paths = params.euler_paths,
        representative_paths = params.representative_paths,
        representative_horizon = Float64(params.representative_horizon),
        representative_step = Float64(params.representative_step),
    )
end

"""
    reference_values(result::NamedTuple) -> NamedTuple

Assemble the `[values]` table of a schema version 1 reference summary from a
completed [`run_case_study`](@ref) result.

Each field is one reported result, carrying at least a finite `value` and a
`kind`, and — every result here being an estimate — a standard error `se`. Each
also carries the analytical reference it was compared against and the discrepancy
in standard errors, so that the comparison a reader would otherwise have to
redo is recorded alongside the number.

The key set follows the preset's grids. Under the production preset it is

  - `transient_mean_tNNN` and `transient_variance_tNNN` for each transient time,
    encoded by [`_grid_tag`](@ref) at a factor of 100;
  - `stationary_mean` and `stationary_variance`;
  - `correlated_mean`, which carries the whole correlation analysis: the measured
    and finite-window analytical integrated autocorrelation times, the effective
    sample size, the lag grid, both autocorrelation series, and their root mean
    squared difference;
  - `euler_variance_hNNNN` for each Euler step, encoded at a factor of 1000;
  - `euler_fit_slope`, the fitted log-log slope of the measured biases, with the
    slope fitted to the analytical biases on the same grid beside it.

A smaller preset produces the same structure over its own shorter Euler grid.
**No record is written here**: this function assembles an in-memory candidate,
and only the driver's production branch writes one, from the production preset
alone.

Every payload is durable in TOML — a finite `Float64`, an `Int` inside the signed
64-bit range, a string, or a homogeneous vector of those. No derived `UInt64`
seed appears anywhere: they are not TOML integers, and only the master seed is
recorded, in the provenance table. No path, no trajectory, and no timing appears
either.

**A defined empirical Euler fit is a precondition.** `euler_fit_slope` is a
required field of the record, so a result whose `euler.empirical_fit` is
`nothing` is refused here with an `ArgumentError`, before anything is assembled
and therefore long before the driver could write a file. A committed reference is
canonical evidence and may demand more than an in-memory run: the analytical fit
is not substituted for the missing empirical one, no `NaN` or zero is inserted,
the field is not silently omitted, and the absolute bias is not used. The remedy
is a production run whose measured biases are strictly positive throughout the
grid, not a weaker record.
"""
function reference_values(result::NamedTuple)
    result.euler.empirical_fit === nothing && throw(
        ArgumentError(
            "the reference summary records `euler_fit_slope`, the fitted log-log " *
            "slope of the measured Euler biases, and this result has no empirical " *
            "fit because at least one measured bias is not strictly positive. A " *
            "production reference requires a strictly positive empirical " *
            "Euler-bias grid, on which alone the ratified log-log empirical fit " *
            "is defined; the analytical fit is not a substitute for it",
        ),
    )
    names = Symbol[]
    entries = Any[]

    transient = result.transient
    for (i, t) in enumerate(transient.times)
        tag = _grid_tag(t, 100, 3, "the transient time")
        push!(names, Symbol("transient_mean_t", tag))
        push!(
            entries,
            (
                value = transient.empirical_mean[i],
                kind = "estimate",
                se = transient.mean_sem[i],
                analytic = transient.analytic_mean[i],
                nsigma = transient.mean_nsigma[i],
                t = Float64(t),
                n = transient.n,
            ),
        )
        push!(names, Symbol("transient_variance_t", tag))
        push!(
            entries,
            (
                value = transient.empirical_variance[i],
                kind = "estimate",
                se = transient.variance_se[i],
                analytic = transient.analytic_variance[i],
                nsigma = transient.variance_nsigma[i],
                t = Float64(t),
                n = transient.n,
            ),
        )
    end

    stationary = result.stationary
    push!(names, :stationary_mean)
    push!(
        entries,
        (
            value = stationary.empirical_mean,
            kind = "estimate",
            se = stationary.mean_sem,
            analytic = stationary.analytic_mean,
            nsigma = stationary.mean_nsigma,
            n = stationary.n,
        ),
    )
    push!(names, :stationary_variance)
    push!(
        entries,
        (
            value = stationary.empirical_variance,
            kind = "estimate",
            se = stationary.variance_se,
            analytic = stationary.analytic_variance,
            nsigma = stationary.variance_nsigma,
            n = stationary.n,
        ),
    )

    correlated = result.correlated
    push!(names, :correlated_mean)
    push!(
        entries,
        (
            value = correlated.summary.mean,
            kind = "estimate",
            se = correlated.summary.sem,
            analytic = Float64(result.parameters.mu),
            nsigma = correlated.mean_nsigma,
            tau_int = correlated.summary.tau_int,
            tau_exact_window = correlated.tau_exact_window,
            tau_relative_error = correlated.tau_relative_error,
            ess = correlated.summary.ess,
            acf_rmse = correlated.acf_rmse,
            maxlag = correlated.summary.maxlag,
            lags = correlated.lags,
            acf_empirical = correlated.acf_empirical,
            acf_analytic = correlated.acf_analytic,
            n = correlated.summary.n,
        ),
    )

    euler = result.euler
    for (i, h) in enumerate(euler.steps)
        tag = _grid_tag(h, 1000, 4, "the Euler step")
        push!(names, Symbol("euler_variance_h", tag))
        push!(
            entries,
            (
                value = euler.empirical_variance[i],
                kind = "estimate",
                se = euler.variance_se[i],
                analytic_euler_variance = euler.analytic_euler_variance[i],
                exact_ou_variance = euler.exact_ou_variance,
                empirical_bias = euler.empirical_bias[i],
                analytic_bias = euler.analytic_bias[i],
                nsigma = euler.variance_nsigma[i],
                h = Float64(h),
                n = euler.n,
            ),
        )
    end
    push!(names, :euler_fit_slope)
    push!(
        entries,
        (
            value = euler.empirical_fit.slope,
            kind = "estimate",
            se = euler.empirical_fit.slope_se,
            analytic_finite_grid_slope = euler.analytic_fit.slope,
            r2 = euler.empirical_fit.r2,
            steps = euler.steps,
            empirical_biases = euler.empirical_bias,
            analytic_biases = euler.analytic_bias,
        ),
    )

    return _named_tuple(names, entries)
end
