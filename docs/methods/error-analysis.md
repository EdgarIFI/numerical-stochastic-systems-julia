# Error analysis

The standards every reported quantity in this repository must meet, and the
shared estimators that implement them.

The standards are the same for every case study, so the estimators are shared
rather than rewritten per case. Those that exist are listed under *Implemented
estimators* below; the rest are written at the gate that first needs them. No
case study has yet been implemented, so nothing here has yet been applied to a
scientific result.

## A value without an uncertainty is not a result

**Every reported value carries a confidence interval**, or the standard error
from which one can be formed. This applies to figures as much as to text: an
estimated curve is drawn with its uncertainty band, and a point estimate in a
table is quoted with its interval.

Where a value is exact — an analytical result, a count, a parameter — it is
identified as exact, so that the absence of an interval is never ambiguous.

## Correlated samples

Monte Carlo and molecular-dynamics time series are **not** independent samples.
Treating them as independent understates the uncertainty, often by a large
factor, and produces confidence intervals that are simply wrong.

Any quantity estimated from a correlated series is therefore analysed by
**blocking**, or by an explicit **integrated autocorrelation time** correction,
so that the effective sample size is used rather than the raw sample count. The
method used, and the resulting effective sample size, are reported alongside the
value.

Of these two, the integrated autocorrelation time is implemented, under the
convention

```math
\tau_{\mathrm{int}} = 1 + 2 \sum_{k=1}^{M} \rho(k), \qquad
n_{\mathrm{eff}} = \frac{n}{\tau_{\mathrm{int}}}, \qquad
\mathrm{SE} = s \sqrt{\frac{\tau_{\mathrm{int}}}{n}}
```

where $`\rho(k)`$ is the autocorrelation at lag $`k`$, $`s`$ the unbiased sample
standard deviation, and $`M`$ the summation window. The effective sample size is
not capped at $`n`$: an anticorrelated series has $`\tau_{\mathrm{int}} < 1`$ and
genuinely carries more information about its mean than $`n`$ independent
observations would.

**The window $`M`$ is chosen by the caller, not by the estimator.** There is no
adaptive window and no warning: a window shorter than the correlation time
understates $`\tau_{\mathrm{int}}`$, and so overstates the precision of the mean,
while a much longer one adds noise from lags that are not resolved. A case study
that uses the correction states the window it chose and why. This shared,
minimal, explicit-window layer is ratified under G3-D.6 and the scientific
correction G3-CORR.1.

Two internal constants appear in the implementation. Neither is a
window-selection rule, and neither carries a decision identifier; both are
recorded here so that a reader of a result knows exactly what they do and, as
importantly, what they do not.

| Constant | What it does | What it does not do |
| --- | --- | --- |
| `_ACF_LAG_ZERO_TOLERANCE = 1e-8` | Verifies that an externally supplied sequence is a **normalised** autocorrelation function, by requiring its lag-zero value to equal 1 to within `1e-8`. An autocovariance, a truncated tail, or a differently normalised series is rejected. | It is an internal numerical **acceptance tolerance** on one value. It takes no part in choosing $`M`$, in truncating the sum, or in deciding which lags are resolved. |
| `_MIN_LAG_PAIRS = 3` | Requires the largest selected lag to leave at least three contributing observation pairs: with $`n`$ observations and a window of $`M`$, the autocorrelation at lag $`M`$ is formed from $`n - M`$ lagged products. | Three pairs **exclude a degenerate estimate only**. They are not evidence that $`M`$ is statistically sufficient — an autocorrelation formed from three products carries no useful precision — and the choice of $`M`$ remains the caller's scientific responsibility. |

The interval also requires an effective sample size greater than one. That guard
is retained defensively: under exact arithmetic, and under the demeaned
denominator-$`n`$ autocorrelation convention `StatsBase` currently uses, the
guards on the sample variance and on $`\tau_{\mathrm{int}}`$ already imply it, so
no admissible input is known that triggers it. It is kept because it is the
property the interval actually needs, and because floating-point corner cases, a
future change of estimator, and pathological external input lie outside that
proof.

The interval that accompanies a correlated mean is an **effective-sample-size
approximation**: a Student-*t* interval with $`n_{\mathrm{eff}} - 1`$ degrees of
freedom, which ignores the uncertainty in $`\tau_{\mathrm{int}}`$ itself. Its
coverage is nominal rather than exact, and is poorest when $`n_{\mathrm{eff}}`$
is small.

**Deferred under the narrowed G3-DEF.1**: adaptive summation windows, automatic
truncation criteria, blocking, blocking-plateau selection, and bootstrap
intervals. Each embeds a selection rule whose failure modes are only visible
against real correlated data, so each is implemented at the first case study that
produces such data rather than written against none.

The following case studies produce correlated data and require this treatment:

- **CS-07** — Markov-chain Monte Carlo sampling of the Ising model, where
  correlation times grow sharply near the critical temperature.
- **CS-09** — Langevin trajectories, whose successive states are correlated by
  construction.
- **CS-10** — Langevin molecular dynamics, for the same reason and with the
  longest correlation times of the three.

Correlation times near a critical point are not a nuisance to be assumed away:
they are part of what CS-07 measures.

## Nonlinear estimators

An estimator that is a nonlinear function of sample means — a ratio, a
susceptibility, a fitted exponent, a Binder cumulant — does not inherit a
confidence interval from the standard errors of its ingredients. Such quantities
use **bootstrap** intervals, resampling at the level of independent blocks when
the underlying data are correlated. The bootstrap is not implemented; it is
deferred with blocking under the narrowed G3-DEF.1, and arrives with the first
case study that needs it.

## Burn-in is measured, not assumed

The discarded initial segment of a chain or trajectory is **justified from the
measured correlation time**, not set to a round number chosen by habit. The case
study reports the correlation time it measured and the burn-in it discarded, so
that the choice can be checked.

## Thresholds for automated assertions

Two thresholds are fixed repository-wide, so that they are neither tuned per test
nor argued about case by case:

| Purpose | Threshold |
| --- | --- |
| Statistical assertion in a test | four standard errors |
| Hypothesis test | `alpha = 0.001` |

Both are deliberately loose. A test suite runs repeatedly in continuous
integration, so a threshold that fails once in twenty runs of a correct
implementation is worse than useless: it trains the reader to ignore failures.
Four standard errors, and a significance level of `0.001`, keep the false-failure
rate low enough that a red test is worth investigating, while remaining tight
enough to catch a genuine implementation error.

A test that fails intermittently is treated as a defect in the test — a threshold
too tight, a sample too small, or an unaccounted correlation — and never worked
around by fixing the random stream.

## Implemented estimators

The shared estimators live in the package and are reached by explicit import; the
package exports nothing.

```julia
using StochasticCaseStudies: summarize_independent, nsigma, rmse, relative_error
using StochasticCaseStudies: integrated_autocorrelation_time, summarize_correlated
using StochasticCaseStudies: fit_loglog
```

Every estimator below computes in the **`Float64` numerical domain**, and states
its contract there. A value that is mathematically finite but whose conversion to
`Float64` is not is rejected rather than admitted as an infinity, and a
calculation that overflows is rejected rather than returned: no estimator here
returns `NaN` or `Inf` from otherwise accepted input. Data whose meaningful
distinctions lie below `Float64` resolution should be rescaled — by subtracting a
reference value, or by changing units — before being summarised. See G3-CORR.3.

**Independent samples**, in
[../../src/statistics.jl](../../src/statistics.jl), ratified under G3-D.6. The
i.i.d. precondition is in the name of the summary because violating it is the
most common way to report an interval that is wrong by a large factor.

| Function | Returns |
| --- | --- |
| `summarize_independent(x; level = 0.95)` | `(n, mean, sd, sem, lower, upper, level)`, with a two-sided Student-*t* interval on `n - 1` degrees of freedom |
| `nsigma(estimate, reference, se)` | the discrepancy in standard errors, the quantity the four-standard-error rule above thresholds |
| `rmse(errors)`, `rmse(x, y)` | the root mean squared error, formed from errors or from paired values |
| `relative_error(estimate, reference)` | `abs(estimate - reference) / abs(reference)`; a zero reference is an error, so that the caller chooses an absolute or mixed tolerance explicitly |

**Correlated samples**, in
[../../src/correlated_statistics.jl](../../src/correlated_statistics.jl),
implementing the convention stated above under G3-D.6 and G3-CORR.1.

| Function | Returns |
| --- | --- |
| `integrated_autocorrelation_time(acf; maxlag)` | `τ_int` over the caller's window; the autocorrelation function may be offset-indexed, its lag-zero value being `acf[begin]` |
| `summarize_correlated(x; maxlag, level = 0.95)` | `(n, mean, sd, tau_int, ess, sem, lower, upper, level, maxlag)`; the series must be **one-based**, because it is passed to `StatsBase.autocor` |

**Convergence**, in
[../../src/error_analysis.jl](../../src/error_analysis.jl), ratified under
G3-D.7.

| Function | Returns |
| --- | --- |
| `fit_loglog(x, y)` | `(slope, intercept, slope_se, r2, residuals)` from unweighted ordinary least squares on `log(x)` and `log(y)` |

Fitting on logarithms treats *relative* error as homoscedastic, which suits
errors spanning decades but is an assumption rather than a fact about the data.
For a deterministic convergence study the residuals measure departure from a pure
power law rather than sampling noise, so `slope_se` there is a goodness-of-fit
statistic and not a confidence interval for the order. The acceptance bands that
would decide whether a measured slope confirms a claimed order are not
implemented.

Every one of these functions validates its preconditions and throws an
`ArgumentError` naming the failure. None substitutes a default, discards a point,
or emits a warning in place of an error. That is one of the ratified Gate 3
implementation principles rather than a numbered decision, and it is recorded as
such in the decision record.

## Reporting

A validation section states, for each compared quantity: the estimate, its
uncertainty and how that uncertainty was obtained, the reference value and its
provenance, the discrepancy expressed in standard errors, and the sample size —
effective, where the samples are correlated.

The committed reference summaries that carry this provenance are governed by
G3-D.9, which fixes a versioned schema, atomic writing, and path-aware
validation. **That decision is implemented** in the Gate 3B-I.2 working-tree
candidate, together with the bounded corrections of Gate 3C-C.1: the schema, the
provenance capture, the atomic writer, and the path-aware validator all exist,
and [reproducibility.md](reproducibility.md) describes what they enforce.

Implementation is not the same as having something to report with, and three
things follow.

- **One scientific reference summary exists**, that of the CS-06 pilot. The other
  nine cases have produced no reference values, and no number outside that one
  record is claimed to have been reproduced.
- **No generic scientific tolerance comparison exists.** Schema validation
  establishes that a record is well formed, complete, and in the right place; it
  makes no numerical comparison at all. Semantic checking of a persisted record —
  recomputing its analytical references and its recorded discrepancies, and
  applying the case's own acceptance criteria — is done by that case's reference
  test, and is a different thing again from a fresh numerical reproduction of the
  run. `tolerance_abs` and `tolerance_rel` are recorded by the schema so that a
  generic comparison has something to compare against when it is introduced.
- **The acceptance bands of this document remain unimplemented as automation**,
  as stated above: the schema records the result of an error analysis rather than
  performing one, and a case that enforces a band does so in its own tests.

## Related documents

- [reproducibility.md](reproducibility.md) — what reproduction promises.
- [rng-and-seeding.md](rng-and-seeding.md) — control of randomness.
- [../decisions.md](../decisions.md) — decisions G1-D.6, G1-D.20, G3-D.6, G3-D.7
  and G3-D.9, the scientific corrections G3-CORR.1 and G3-CORR.3, the
  infrastructure corrections G3-CORR.4, G3-CORR.5 and G3-CORR.6, the narrowed
  G3-DEF.1, and the unnumbered *Ratified Gate 3 implementation principles*.
