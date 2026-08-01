# Reproducibility

What this repository promises about reproducing its results, and what it
deliberately does not.

## Two kinds of reproduction

**Exact reproduction** uses Julia 1.12.x together with the committed
`Manifest.toml`, which pins every direct and transitive package version. This is
the canonical environment, and the one in which published results are produced.

**Supported-version reproduction** covers every Julia release from 1.10 onwards.
It is **statistical rather than bitwise**. Julia does not guarantee that its
default random number generator produces identical streams across minor releases,
and the algorithms behind `rand` and its relatives may change. Two runs on
different Julia minor versions will therefore generally produce different
sequences of random numbers, and so different values.

The correct expectation on a non-canonical version is that a result agrees with
the reported value **within its stated statistical uncertainty**, not that it
matches digit for digit. A study whose conclusion depended on the exact bits of a
random stream would not be a sound study.

The distinction is not a limitation to be apologised for; it is the honest
description of what a stochastic computation can promise.

## The canonical manifest and the LTS release

`Manifest.toml` is committed because this repository is an application rather
than a library. It records the exact package versions used, and instantiating it
reconstructs that environment.

Continuous integration deliberately serves two different purposes:

- The **canonical job** instantiates the committed manifest and runs the tests in
  the pinned environment.
- The **LTS job** removes the manifest inside its own ephemeral checkout and
  resolves afresh from `Project.toml`. This tests that the declared compatibility
  bounds are honest and that the package works on the supported floor. It makes
  no claim about bitwise reproduction, and it never modifies the committed
  manifest.

The two jobs answer different questions, and neither substitutes for the other.

## What every public result must record

A result is not publishable in this repository unless it is accompanied by:

- every **parameter** value, with units or scaling;
- the **seed** or seeds used;
- the **Julia version**;
- the **package state** — that is, the manifest against which it was produced;
- the **Git commit** of the repository.

The script [../../scripts/env_report.jl](../../scripts/env_report.jl) prints all
of this for the active environment, including whether the working tree was clean
at the time.

## Figures

Figures are committed as PNG. They are **verified through the numerical series
behind them, never by comparing pixels**. Rendered output depends on the plotting
backend, on font availability, and on rasterisation details, none of which bear
on whether a scientific result is correct. A figure is therefore accompanied by
the numerical data it draws, and it is that data which is checked.

## Heavy output is not tracked

Long production runs write to `results/`, which is ignored by Git. Such output is
regenerated from the committed drivers rather than stored. What is committed
instead is a small **reference summary** per case: the handful of numbers a
reader would need in order to confirm that a rerun agrees.

## Numerical reference summaries

The canonical location for a reference summary is:

```text
case-studies/<slug>/reference/<name>.toml
```

Each summary is a TOML file carrying a `[provenance]` table with, at minimum, the
case identifier, the seed, the Julia version, the Git commit, and the driver that
generated it, alongside the reported values themselves.

**No reference summary exists yet.** No case study has reached its implementation
gate, so there are no reference values in this repository, and no claim is made
that any result has been verified.

The script
[../../scripts/verify_reproducibility.jl](../../scripts/verify_reproducibility.jl)
already searches that location, validates the TOML syntax of anything it finds,
and checks the provenance metadata. In the present empty state it reports that no
summaries are registered and exits successfully, which is the correct outcome for
a scaffold. Comparison of committed values against freshly computed ones, within
tolerances, is added with the first case study.

## Related documents

- [rng-and-seeding.md](rng-and-seeding.md) — how randomness is controlled.
- [error-analysis.md](error-analysis.md) — how uncertainty is quantified.
- [../decisions.md](../decisions.md) — the decisions behind these policies.
