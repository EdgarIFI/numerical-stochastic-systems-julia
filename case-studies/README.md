# Case studies

The ten case studies of *Stochastic Systems in Julia*, in their frozen order.

The numbering, order, slugs, and titles below are fixed and will not change:
directory names and cross-references depend on them.

A case-study directory is created only when the corresponding implementation gate
begins. Nothing below is a link, because no case-study directory exists yet.

## Status

Every case is currently **Planned**. No case study has been implemented, and no
numerical result, figure, or validated value exists in this repository.

| ID | Slug | Title | Part | Tier | Status |
| --- | --- | --- | --- | --- | --- |
| CS-01 | `01-central-limit-theorem` | Central Limit Theorem: Characteristic Functions and Rates of Convergence | I | A | Planned |
| CS-02 | `02-binary-symmetric-channel` | Markov Chain Convergence and Information Loss in a Binary Symmetric Channel | I | A | Planned |
| CS-03 | `03-poisson-processes` | Poisson Counting Processes: Exact Simulation and the Bernoulli Limit | II | A | Planned |
| CS-04 | `04-stochastic-sir` | Stochastic SIR Epidemics: Exact Gillespie Simulation and the Master Equation | II | B | Planned |
| CS-05 | `05-wiener-process` | The Wiener Process and Diffusive Scaling | III | A | Planned |
| CS-06 | `06-ornstein-uhlenbeck` | Ornstein–Uhlenbeck Dynamics: Mean Reversion and Numerical Convergence Orders | III | B | Planned |
| CS-07 | `07-ising-model` | Phase Transitions in the Two-Dimensional Ising Model | IV | C | Planned |
| CS-08 | `08-disk-packing` | Bidisperse Disk Packing by Simulated Annealing | IV | B | Planned |
| CS-09 | `09-langevin-diffusion` | Free Langevin Dynamics and the Einstein Relation | V | B | Planned |
| CS-10 | `10-lennard-jones-md` | Langevin Molecular Dynamics of a Two-Dimensional Lennard-Jones Fluid | V | C | Planned |

## Taxonomy

### Part I — Foundations of Randomness and Convergence

| ID | Title | Slug |
| --- | --- | --- |
| CS-01 | Central Limit Theorem: Characteristic Functions and Rates of Convergence | `01-central-limit-theorem` |
| CS-02 | Markov Chain Convergence and Information Loss in a Binary Symmetric Channel | `02-binary-symmetric-channel` |

### Part II — Counting and Jump Processes

| ID | Title | Slug |
| --- | --- | --- |
| CS-03 | Poisson Counting Processes: Exact Simulation and the Bernoulli Limit | `03-poisson-processes` |
| CS-04 | Stochastic SIR Epidemics: Exact Gillespie Simulation and the Master Equation | `04-stochastic-sir` |

### Part III — Diffusion and Stochastic Differential Equations

| ID | Title | Slug |
| --- | --- | --- |
| CS-05 | The Wiener Process and Diffusive Scaling | `05-wiener-process` |
| CS-06 | Ornstein–Uhlenbeck Dynamics: Mean Reversion and Numerical Convergence Orders | `06-ornstein-uhlenbeck` |

### Part IV — Monte Carlo Sampling and Stochastic Optimisation

| ID | Title | Slug |
| --- | --- | --- |
| CS-07 | Phase Transitions in the Two-Dimensional Ising Model | `07-ising-model` |
| CS-08 | Bidisperse Disk Packing by Simulated Annealing | `08-disk-packing` |

### Part V — Stochastic Dynamics of Physical Systems

| ID | Title | Slug |
| --- | --- | --- |
| CS-09 | Free Langevin Dynamics and the Einstein Relation | `09-langevin-diffusion` |
| CS-10 | Langevin Molecular Dynamics of a Two-Dimensional Lennard-Jones Fluid | `10-lennard-jones-md` |

## Depth tiers

The tiers declare the intended analytical and numerical depth of each case. They
describe planned scope rather than difficulty, and they exist so that depth is
allocated deliberately instead of drifting case by case.

- **Tier A** — CS-01, CS-02, CS-03, CS-05.
  Foundational cases with a closed-form reference against which the numerical
  result is checked directly.
- **Tier B** — CS-04, CS-06, CS-08, CS-09.
  Cases requiring a more substantial numerical method, a convergence study, or a
  careful statistical treatment.
- **Tier C** — CS-07, CS-10.
  The most demanding cases: critical behaviour and an interacting many-particle
  system, both of which need correlated-sample statistics and the longest runs.

## Conceptual prerequisites

Each arrow means that the second case builds directly on a method or result
established in the first. The prerequisites constrain the order of
implementation, not the order in which the finished studies may be read.

- CS-03 → CS-04. Exact simulation of a counting process precedes the exact
  simulation of a reaction system.
- CS-05 → CS-06. Brownian motion precedes the mean-reverting diffusion driven by
  it.
- CS-07 → CS-08. Metropolis sampling at fixed temperature precedes annealed
  optimisation.
- CS-09 → CS-10. The exact free-particle Langevin transition precedes the
  interacting Langevin fluid, whose thermostat substep reuses it.

## Implementation order

**CS-06 is the pilot.** The Ornstein–Uhlenbeck case is implemented first because
it exercises the whole intended architecture — an exact transition law to
validate against, a convergence study over several numerical schemes, and a
figure supported by committed numerical data — at a scale small enough to be run
repeatedly while the shared infrastructure settles.

CS-05 follows, as the first test of whether that architecture generalises rather
than having been fitted to a single case.

The remaining cases are implemented in an order to be decided once the shared
infrastructure has stabilised, subject to the prerequisites above.

## Structure of a completed case study

Each completed case study will occupy one directory named by its slug, containing
a README that follows the eleven-section template recorded in
[../docs/style-guide.md](../docs/style-guide.md), a thin driver divided into
`# %%` cells, the committed PNG figures, and the small numerical reference
summaries that make the reported values verifiable. The governing conventions are
set out in [../docs/notation.md](../docs/notation.md) and the method documents
under [../docs/methods](../docs/methods).
