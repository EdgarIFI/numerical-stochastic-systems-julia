# Error analysis

The standards every reported quantity in this repository must meet. This document
records the standards; it does not implement them. The shared estimators are
written at the gate that first needs them, and no case study has yet been
implemented.

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
the underlying data are correlated.

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

## Reporting

A validation section states, for each compared quantity: the estimate, its
uncertainty and how that uncertainty was obtained, the reference value and its
provenance, the discrepancy expressed in standard errors, and the sample size —
effective, where the samples are correlated.

## Related documents

- [reproducibility.md](reproducibility.md) — what reproduction promises.
- [rng-and-seeding.md](rng-and-seeding.md) — control of randomness.
- [../decisions.md](../decisions.md) — decisions G1-D.6 and G1-D.20.
