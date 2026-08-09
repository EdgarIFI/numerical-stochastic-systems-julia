# Stochastic Systems in Julia

**Ten Reproducible Numerical Case Studies in Probability, Stochastic Processes,
and Computational Statistical Physics**

Ten self-contained numerical studies. Each poses a concrete question about a
stochastic system, develops what can be established analytically, implements the
numerical method from first principles in Julia, and then checks the computed
answer against that analysis with a quantified uncertainty. The emphasis falls on
methods that are built rather than called, and on results that are validated
rather than merely plotted.

## Development status

The repository is under active construction on an audited development branch, and
is merged to `main` only when a milestone is complete.

What exists today is the shared package scaffold, the pinned Julia environment,
the continuous-integration configuration, the governing documentation, and **one
completed case study, the CS-06 pilot**, with its figure, its numerical reference
summary, and its validated values. The remaining nine are planned: a case-study
directory is created only when its implementation begins, so the absence of a
directory below is deliberate rather than an oversight.

The first public milestone, `v0.1.0`, follows the completion of the scaffold, the
shared infrastructure, and the CS-06 pilot. Version `v1.0.0` requires all ten
completed case studies.

## The ten case studies

Depth tiers describe planned analytical and numerical depth rather than
difficulty; they are defined in [case-studies/README.md](case-studies/README.md),
which also records the conceptual prerequisites between cases.

| ID | Case study | Part | Tier | Status |
| --- | --- | --- | --- | --- |
| CS-01 | Central Limit Theorem: Characteristic Functions and Rates of Convergence | I | A | Planned |
| CS-02 | Markov Chain Convergence and Information Loss in a Binary Symmetric Channel | I | A | Planned |
| CS-03 | Poisson Counting Processes: Exact Simulation and the Bernoulli Limit | II | A | Planned |
| CS-04 | Stochastic SIR Epidemics: Exact Gillespie Simulation and the Master Equation | II | B | Planned |
| CS-05 | The Wiener Process and Diffusive Scaling | III | A | Planned |
| CS-06 | [Ornstein–Uhlenbeck Dynamics: Mean Reversion and Numerical Convergence Orders](case-studies/06-ornstein-uhlenbeck/) | III | B | Complete (pilot) |
| CS-07 | Phase Transitions in the Two-Dimensional Ising Model | IV | C | Planned |
| CS-08 | Bidisperse Disk Packing by Simulated Annealing | IV | B | Planned |
| CS-09 | Free Langevin Dynamics and the Einstein Relation | V | B | Planned |
| CS-10 | Langevin Molecular Dynamics of a Two-Dimensional Lennard-Jones Fluid | V | C | Planned |

## The five-part map

- **Part I — Foundations of Randomness and Convergence.** How sums of independent
  random variables converge, at what rate, and under which hypotheses; and how a
  finite-state Markov chain relaxes towards its stationary law.
- **Part II — Counting and Jump Processes.** Exact simulation of processes that
  advance by discrete events, from the Poisson process to the stochastic
  epidemic and its master equation.
- **Part III — Diffusion and Stochastic Differential Equations.** Brownian motion
  and diffusive scaling, followed by mean-reverting dynamics used to measure the
  strong and weak convergence orders of numerical schemes.
- **Part IV — Monte Carlo Sampling and Stochastic Optimisation.** Metropolis
  sampling at fixed temperature near a critical point, and the same family of
  moves redirected towards optimisation by annealing.
- **Part V — Stochastic Dynamics of Physical Systems.** Langevin dynamics of a
  free particle, validated against its exact transition law, and then of an
  interacting fluid.

## What the repository is designed to demonstrate

- Numerical methods implemented from first principles, so that the algorithm
  rather than a library call is the object of study.
- Results validated against analytical predictions or independently computed
  references, always with a stated uncertainty.
- Correlated-sample statistics treated honestly, with blocking or integrated
  autocorrelation-time corrections where they are required.
- Randomness handled explicitly, with declared seeds and deterministic
  substreams instead of hidden global state.
- A pinned, reproducible environment, and a clear distinction between exact and
  statistical reproduction.
- Readable scientific Julia: thin drivers, performance-critical kernels inside
  functions, and an interactive workflow that keeps intermediate quantities
  inspectable.

## Repository layout

```text
.
├── .github/workflows/   Continuous-integration configuration
├── case-studies/        Case-study taxonomy; one directory per case as it is implemented
├── docs/                Conventions, methods, and the decision record
│   └── methods/         Reproducibility, randomness, and error analysis
├── scripts/             Environment and reproducibility utilities
├── src/                 The shared StochasticCaseStudies package
└── test/                Package tests
```

## Getting started

Julia 1.10 or later is required. The canonical development and reproduction
version is Julia 1.12.6.

The commands below are written for a POSIX shell such as Git Bash and work
unchanged in PowerShell.

```bash
git clone https://github.com/EdgarIFI/numerical-stochastic-systems-julia.git
cd numerical-stochastic-systems-julia

# Instantiate the canonical environment from the committed Manifest.toml.
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Confirm that the package loads and that the scaffold tests pass.
julia --project=. -e 'using Pkg; Pkg.test()'

# Print the environment report that must accompany any reported result.
julia --project=. scripts/env_report.jl

# Validate the reproducibility scaffold.
julia --project=. scripts/verify_reproducibility.jl
```

## Interactive workflow

The repository is written for an interactive session rather than for a batch
runner. Each case study will be driven by a thin script divided into `# %%`
cells, which the Julia extension for VS Code executes one cell at a time in a
persistent REPL, leaving the intermediate quantities available for inspection.
The numerical work itself lives in package functions, so that performance-critical
loops are compiled rather than interpreted at top level.

Every driver will expose three execution presets:

| Preset | Purpose |
| --- | --- |
| `:smoke` | Seconds. Confirms that the code runs and the plumbing is sound. |
| `:figure` | Minutes. Produces the committed figures. |
| `:production` | Long. Produces the highest-precision results. |

Committed drivers default to `:smoke`, so that cloning the repository and running
a driver never starts an unexpectedly long computation.

Conventions are recorded in [docs/style-guide.md](docs/style-guide.md), and the
policy for symbols shared between cases in
[docs/notation.md](docs/notation.md).

## Reproducibility

Exact and statistical reproduction are distinguished deliberately.

- **Exact reproduction** uses Julia 1.12.x together with the committed
  `Manifest.toml`, which pins every package version.
- **Supported-version reproduction**, on any Julia from 1.10 onwards, is
  statistical rather than bitwise: Julia does not guarantee identical default
  random number streams across minor releases, so agreement is expected within
  the stated statistical uncertainty rather than to the last bit.

Figures are verified through the numerical series behind them, never by comparing
pixels. Heavy output is regenerated rather than tracked and belongs in the
ignored `results/` directory; only small reference summaries are committed.

Continuous integration is configured to run the tests on Linux against both the
canonical manifest and a fresh resolution on the Julia LTS release, to check
formatting, and to run the reproducibility scaffold.

The details are set out in
[docs/methods/reproducibility.md](docs/methods/reproducibility.md),
[docs/methods/rng-and-seeding.md](docs/methods/rng-and-seeding.md), and
[docs/methods/error-analysis.md](docs/methods/error-analysis.md). The
architectural decisions behind them are recorded in
[docs/decisions.md](docs/decisions.md).

## Licensing

All code, text, figures, and data in this repository are original work by the
author unless an explicit third-party attribution states otherwise.

| Content | Licence | Scope |
| --- | --- | --- |
| Julia source code | [MIT](LICENSE) | `src/`, `test/`, `scripts/`, and the case-study `.jl` drivers added in later gates |
| Prose, figures, and data | [CC BY 4.0](LICENSE-CC-BY) | Original prose, figures, and lightweight generated numerical data |
| Third-party content | its own terms | Any third-party material remains under its own licence and is explicitly attributed where it appears |

## Citation

Citation metadata is provided in [CITATION.cff](CITATION.cff). The repository has
not been released, so it carries no version tag and no DOI; please cite the
repository together with the commit you used.

## Contributing

Issues are welcome for questions about the methods and for reproducibility
reports — in particular, a result that does not reproduce within its stated
uncertainty on a supported Julia version. Pull requests are not currently being
solicited, because the case studies are authored as a single coherent body of
work.
