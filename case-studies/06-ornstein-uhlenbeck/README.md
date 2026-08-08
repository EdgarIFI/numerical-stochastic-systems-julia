# CS-06 — Ornstein–Uhlenbeck Dynamics: Mean Reversion and Numerical Convergence Orders

Part III — Diffusion and Stochastic Differential Equations. Depth tier B.

**Status: implementation baseline.** The source, the driver, and the tests exist
and run. No figure and no numerical reference summary have been produced or
committed, and no scientific value is reported here yet; both remain for the
evidence gate, Gate 4C-E.1. See *Results* and *Validation* below for exactly what
is and is not established.

## 1. Overview and question

The Ornstein–Uhlenbeck process is the simplest stochastic differential equation
that is both genuinely stochastic and genuinely mean-reverting. A restoring drift
pulls the state towards a long-run mean at a rate proportional to its
displacement, while a constant-amplitude noise pushes it away; the balance
between the two produces a stationary distribution and an exponentially decaying
memory, and both are available in closed form.

That combination is why the process is the pilot case of this repository. Almost
every quantity a numerical study of it produces has an exact reference to be
judged against, so a disagreement larger than the stated uncertainty is evidence
of a fault in the implementation rather than an open scientific question. A case
whose answers are known is the right place to establish the machinery for cases
whose answers are not.

The study asks four bounded questions.

1. **Does an exactly sampled ensemble reproduce the transient moments?** Started
   from a deterministic value, does the mean decay towards the long-run mean at
   the predicted rate, and does the variance grow towards its stationary value at
   the predicted rate, to within the sampling uncertainty?
2. **Does an exactly sampled equilibrium ensemble reproduce the invariant law?**
   Are the mean and variance of a direct draw from the invariant distribution
   those the closed form gives?
3. **What is the temporal correlation structure of the stationary process, and
   what does it do to the uncertainty of a mean estimated from one path?** Does
   the measured autocorrelation match the exact exponential decay, does the
   measured integrated autocorrelation time match the analytical value **summed
   over the same finite window**, and is the effective sample size of a long path
   as small as that implies?
4. **How large is the finite-step bias of the Euler–Maruyama scheme?** The scheme
   has an invariant distribution of its own, whose variance is not that of the
   process. How far apart are the two at each step size, and does the measured
   gap match the exact prediction?

The fourth question is where the case earns the second half of its title. It is
posed as a question about **invariant measures**, not about pathwise accuracy:
the study measures the bias of a stationary quantity across a grid of step sizes,
and makes no statement about strong convergence.

## 2. Mathematical formulation

The process is the solution of the linear stochastic differential equation

```math
\mathrm{d}X_t = \kappa\,(\mu - X_t)\,\mathrm{d}t + \sigma\,\mathrm{d}W_t,
\qquad X_0 = x_0,
```

where $`W_t`$ is a standard Wiener process. The drift is linear in the state and
restoring; the diffusion coefficient is constant. The equation has a unique
strong solution for every finite initial condition, and the solution is a
Gaussian Markov process.

### Symbol table

| Symbol | Meaning | Domain and units |
| --- | --- | --- |
| $`X_t`$ | state of the process at time $`t`$ | real |
| $`W_t`$ | standard Wiener process | real, $`W_0 = 0`$ |
| $`\kappa`$ | mean-reversion rate | $`\kappa > 0`$, inverse time |
| $`\mu`$ | long-run mean | real, units of $`X`$ |
| $`\sigma`$ | noise amplitude of the equation | $`\sigma > 0`$, units of $`X\cdot\text{time}^{-1/2}`$ |
| $`x_0`$ | deterministic initial value | real |
| $`m(t)`$ | mean of $`X_t`$ given $`X_0 = x_0`$ | units of $`X`$ |
| $`v(t)`$ | variance of $`X_t`$ given $`X_0 = x_0`$ | units of $`X^2`$ |
| $`v_\infty`$ | variance of the invariant distribution | units of $`X^2`$ |
| $`\rho(\tau)`$ | stationary autocorrelation at lag $`\tau`$ | dimensionless |
| $`h`$ | step size, of discretisation or of observation | $`h > 0`$, time |
| $`L`$ | lag summation window, in steps | integer, $`L \ge 0`$ |
| $`\tau_L`$ | integrated autocorrelation time over the window $`L`$ | dimensionless |
| $`a_h`$ | Euler one-step multiplier of the deviation from $`\mu`$ | dimensionless |
| $`v_{\mathrm{EM}}(h)`$ | variance of the Euler invariant distribution | units of $`X^2`$ |
| $`b_{\mathrm{EM}}(h)`$ | finite-step bias $`v_{\mathrm{EM}}(h) - v_\infty`$ | units of $`X^2`$ |
| $`Z`$ | standard normal variate | dimensionless |
| $`n`$ | sample size | positive integer |
| $`n_{\mathrm{eff}}`$ | effective sample size of a correlated series | positive real |

**A declared reuse of $`\sigma`$.** [../../docs/notation.md](../../docs/notation.md)
reserves $`\sigma`$ for a standard deviation unless it carries a subscript. In
this case study $`\sigma`$ is the **noise amplitude of the equation**, which is
not a standard deviation of $`X`$ and does not even have its units. The standard
deviation of the invariant distribution is $`\sigma/\sqrt{2\kappa}`$, and it is
always written that way rather than as a bare $`\sigma`$. The reuse is the
conventional notation for this equation, and it is declared here, locally and
unambiguously, exactly as the notation policy requires.

### Parameter domains

$`\kappa > 0`$ is what makes the process mean-reverting: at $`\kappa \le 0`$ the
invariant distribution, the stationary variance, and the autocorrelation all
cease to exist, so the restriction is a domain condition rather than a numerical
convenience. $`\sigma > 0`$ is required rather than $`\sigma \ge 0`$, because at
$`\sigma = 0`$ the equation is the deterministic relaxation
$`\dot{x} = \kappa(\mu - x)`$, every variance the case reports is identically
zero, and the invariant law collapses to a point mass. $`\mu`$ and $`x_0`$ are
unrestricted reals. Every step size is strictly positive, and every physical time
and lag is nonnegative. The Euler stationary quantities carry the further
restriction $`0 < \kappa h < 2`$, discussed in section 4.

Every one of these conditions is checked at the point of use, and a violation
raises an `ArgumentError` naming the offending value rather than producing a
`NaN`, a negative variance, or a silently substituted default.

## 3. Analytical results

Each result below holds for $`\kappa > 0`$ and $`\sigma > 0`$. The transient
results additionally assume a **deterministic** initial value $`x_0`$; the
stationary results assume the process is in its invariant distribution, which the
implementation arranges by sampling that distribution directly rather than by
relaxing towards it.

### Transient moments

For a process started at the deterministic value $`x_0`$,

```math
m(t) = \mu + (x_0 - \mu)\,\mathrm{e}^{-\kappa t},
\qquad
v(t) = \frac{\sigma^2}{2\kappa}\left(1 - \mathrm{e}^{-2\kappa t}\right).
```

The initial displacement decays with the time constant $`1/\kappa`$, the
**relaxation time**, and the noise amplitude does not enter the mean at all: the
mean of a linear diffusion follows the deterministic relaxation of its drift. The
variance grows from zero on the timescale $`1/(2\kappa)`$ and is independent of
both $`\mu`$ and $`x_0`$. The marginal law is Gaussian,
$`X_t \sim \mathcal{N}\!\left(m(t), v(t)\right)`$, at every $`t`$.

### The invariant law

As $`t \to \infty`$ the marginal converges to the invariant distribution

```math
\mathcal{N}\!\left(\mu,\; v_\infty\right),
\qquad
v_\infty = \frac{\sigma^2}{2\kappa},
\qquad
\sqrt{v_\infty} = \frac{\sigma}{\sqrt{2\kappa}}.
```

The stationary variance is the balance between the noise injected at rate
$`\sigma^2`$ and the restoring drift, and it does not depend on the initial
condition.

### The exact transition

The process has a Gaussian transition law in closed form. For any step $`h > 0`$,

```math
X_{t+h} = \mu + \mathrm{e}^{-\kappa h}\,(X_t - \mu)
  + \sigma\sqrt{\frac{1 - \mathrm{e}^{-2\kappa h}}{2\kappa}}\; Z,
\qquad Z \sim \mathcal{N}(0, 1),
```

with $`Z`$ independent of $`X_t`$. This is **exact at every step size**, not an
approximation refined by taking $`h`$ small. Iterating it produces a path whose
finite-dimensional distributions on the grid are exactly those of the process, so
a quantity estimated from such a path carries sampling error and no
discretisation error whatever. Note that the innovation variance is $`v(h)`$: the
variance accumulated over an interval of length $`h`$ is one quantity, whether it
is read as a transient variance from a deterministic start or as the conditional
variance of a step.

**Evaluating the variance factor stably.** Written as printed,
$`1 - \mathrm{e}^{-2\kappa h}`$ is the difference of two numbers that agree to
more and more digits as $`\kappa h`$ decreases, and in floating point it loses
significant digits accordingly: at $`h = 10^{-12}`$ the subtraction carries a
relative error of order $`3\times10^{-5}`$, at $`h = 10^{-15}`$ of order
$`3\times10^{-2}`$, and below about $`h = 10^{-17}`$ it underflows to exactly
zero. The implementation therefore evaluates the factor as
`-expm1(-2 * kappa * h)`, which is accurate throughout. The two expressions are
equal in exact arithmetic; only their floating-point behaviour differs. The same
form is used wherever the factor appears, and the test suite checks the accuracy
at step sizes at which the subtraction would visibly fail.

### The stationary autocorrelation

In the stationary regime the autocorrelation depends on the lag alone:

```math
\rho(\tau) = \mathrm{e}^{-\kappa|\tau|}.
```

It decays with the relaxation time $`1/\kappa`$ and is independent of $`\sigma`$,
of $`\mu`$, and of the initial condition: the noise amplitude sets the scale of
the fluctuations, the drift rate sets how quickly they decorrelate. Observed on a
uniform grid of step $`h`$, the autocorrelation at integer lag $`k`$ is

```math
\rho_k = \mathrm{e}^{-\kappa k h}.
```

### The finite-window integrated autocorrelation time

The shared correlated layer estimates the integrated autocorrelation time under
the convention of [../../docs/methods/error-analysis.md](../../docs/methods/error-analysis.md),

```math
\tau_{\mathrm{int}} = 1 + 2\sum_{k=1}^{L} \rho_k,
\qquad
n_{\mathrm{eff}} = \frac{n}{\tau_{\mathrm{int}}},
\qquad
\mathrm{SE} = s\sqrt{\frac{\tau_{\mathrm{int}}}{n}},
```

with the summation window $`L`$ supplied explicitly by the caller. The analytical
comparator this case uses is therefore the **same truncated sum**,

```math
\tau_L = 1 + 2\sum_{k=1}^{L} \mathrm{e}^{-\kappa k h},
```

and **not** the infinite-window limit
$`(1 + \mathrm{e}^{-\kappa h})/(1 - \mathrm{e}^{-\kappa h})`$. The distinction is
not a detail. At the settings this case uses, the finite-window value is
measurably below the limit, and comparing a deliberately truncated estimate
against the untruncated limit would charge the truncation to the estimate and
report a bias that is an artefact of the comparison. The implementation obtains
$`\tau_L`$ by passing the exact autocorrelations to the same shared estimator the
measurement uses, so the comparator and the measurement share one convention and
one window by construction.

### The Euler–Maruyama invariant law

The Euler–Maruyama discretisation of the equation is

```math
X_{n+1} = X_n + \kappa\,(\mu - X_n)\,h + \sigma\sqrt{h}\,Z_n,
\qquad Z_n \sim \mathcal{N}(0, 1)\ \text{independent}.
```

Acting on the deviation $`Y_n = X_n - \mu`$ it is the first-order autoregression
$`Y_{n+1} = a_h Y_n + \sigma\sqrt{h}\,Z_n`$ with

```math
a_h = 1 - \kappa h,
```

which is the linearisation of the exact multiplier $`\mathrm{e}^{-\kappa h}`$.
The recursion contracts precisely when $`|a_h| < 1`$, that is when

```math
0 < \kappa h < 2,
```

and only then does it have an invariant distribution at all. At $`\kappa h = 2`$
the deviation is reflected without decay and the variance grows without bound;
beyond it the recursion diverges. Within the admissible interval the invariant
variance solves $`v = a_h^2 v + \sigma^2 h`$, giving

```math
v_{\mathrm{EM}}(h) = \frac{\sigma^2 h}{1 - a_h^2}
  = \frac{\sigma^2}{\kappa\,(2 - \kappa h)}.
```

The invariant law of the discrete chain is $`\mathcal{N}(\mu, v_{\mathrm{EM}}(h))`$
**exactly**, for every admissible step. Its variance exceeds that of the process:
the Euler chain is overdispersed. The finite-step bias is

```math
b_{\mathrm{EM}}(h) = v_{\mathrm{EM}}(h) - v_\infty
  = \frac{\sigma^2}{\kappa(2 - \kappa h)} - \frac{\sigma^2}{2\kappa}
  = \frac{\sigma^2 h}{2\,(2 - \kappa h)},
```

and the right-hand form is the one the implementation computes. The two are equal
in exact arithmetic, but the difference of the two variances is a subtraction of
quantities that agree to more and more digits as $`h`$ decreases, so forming it
directly would lose precision fastest exactly where the bias is smallest and most
interesting. The simplified form has no such cancellation.

Expanding, $`b_{\mathrm{EM}}(h) = \sigma^2 h/4 + O(h^2)`$, so the bias vanishes
linearly as the step is refined. That statement is an expansion of the exact
formula above. It is **not** offered as a measured order of convergence, and the
fitted slopes reported by the study describe the grid actually tested and nothing
outside it — on the grids this case uses the exact bias is not a pure power law,
and its log-log slope exceeds one.

## 4. Numerical method

Four regimes are simulated. Three of them are sampled **exactly**, so their only
error is sampling error; the fourth is the one place the Euler scheme is used.

**Regime 1 — transient independent ensemble.** At each transient time, $`n`$
values of $`X_t`$ are drawn directly from $`\mathcal{N}(m(t), v(t))`$. No path is
integrated: the marginal at a single time is available in closed form, so
producing it by stepping would cost a factor of $`t/h`$ in work and introduce a
grid where none is needed.

**Regime 2 — stationary independent ensemble.** $`n`$ values are drawn directly
from $`\mathcal{N}(\mu, v_\infty)`$. The ensemble is in equilibrium by
construction, so **nothing is discarded as burn-in** and no claim about the
length of a burn-in is needed. The draws are independent, so the shared
independent-sample summary applies without an autocorrelation correction.

**Regime 3 — stationary long path.** One path is started at a value drawn from
the invariant law and then integrated with the exact transition on a uniform grid
of step $`h`$. It is therefore **stationary from its first point**, and again no
burn-in is discarded: a burn-in exists to remove the memory of an arbitrary
initial condition, and there is no arbitrary initial condition here. This is the
only correlated regime of the case.

**Regime 4 — the discrete-stationary one-step Euler experiment.** For each step
size, $`n`$ initial values are drawn independently from the **Euler recursion's
own invariant law** $`\mathcal{N}(\mu, v_{\mathrm{EM}}(h))`$, exactly one Euler
step is applied to each, and the independent endpoint ensemble is analysed.

The design of regime 4 is the point of it. Because the recursion preserves its
invariant law exactly, the endpoints are distributed as
$`\mathcal{N}(\mu, v_{\mathrm{EM}}(h))`$ too, and their sample variance estimates
$`v_{\mathrm{EM}}(h)`$ with sampling error alone. Two validations then follow
from one ensemble: the endpoint variance against $`v_{\mathrm{EM}}(h)`$, which
checks that the experiment measures what it claims to, and the gap between the
endpoint variance and $`v_\infty`$, which is the bias itself. Relaxing towards
the Euler invariant law from an arbitrary start would instead confound the
finite-step bias with an unconverged transient and would require a burn-in whose
length would have to be justified. **There is no Euler horizon and no Euler
burn-in in this case**, and the absence of both is a property of the design
rather than an omission.

## 5. Implementation notes

The case lives in the submodule `StochasticCaseStudies.OrnsteinUhlenbeck`, in
three files under [../../src/ornstein_uhlenbeck](../../src/ornstein_uhlenbeck):
the analytical model, the samplers built on it, and the experiments built on
those. The submodule **exports nothing**, in keeping with the decision that holds
through this pilot; every name is reached by an explicit import or by
qualification.

- **No shared-core change was needed.** The case consumes the frozen Gate 3
  layer — the preset lookup, deterministic seeding, the independent and
  correlated summaries, the discrepancy measures, the log-log fit, provenance
  capture, and the reference-summary writer — and adds nothing to it. Nor was a
  new dependency required.
- **Randomness is explicit throughout.** Every function that consumes randomness
  takes an `rng::AbstractRNG` argument, and nothing in `src/` seeds a generator.
  Draws are made one scalar at a time rather than through the array form of
  `randn`, so that enlarging a sample extends its draws rather than replacing
  them — the same prefix property the shared seed derivation provides, and the
  reason a smoke run is a genuine prefix of a production one.
- **Results are named tuples of plain arrays.** There is no result type, no
  abstract experiment interface, and no registry.
- **Coefficients are hoisted, not rewritten.** A loop over many steps at one step
  size computes the transition coefficients once, in exactly the arithmetic form
  the corresponding one-step function uses, so a hoisted loop and repeated single
  steps agree bit for bit given the same stream. The tests check that agreement
  rather than assuming it.
- **The variance of a variance is not the variance of a mean.** A sample variance
  is compared against its analytical value using
  $`\mathrm{SE}(s^2) = \sigma^2\sqrt{2/(n-1)}`$, which is exact for a Gaussian
  sample — and every ensemble here is exactly Gaussian by construction. The
  **analytical** variance is used as $`\sigma^2`$, so the uncertainty against
  which a discrepancy is judged is a fixed reference rather than an estimate that
  moves with the sample. Using the standard error of the mean to judge a variance
  would be wrong by a factor of order $`\sigma\sqrt{n/2}`$.
- **Grids are validated, not rounded.** A horizon must be a whole number of
  steps; the ratio is compared with its nearest integer under a stated internal
  tolerance and a mismatch is refused by name rather than rounded into a grid
  nobody asked for. Time grids are formed by integer multiplication, so no grid
  point is reached by accumulating rounding error.
- **The autocorrelations are estimated twice** — once for the series the case
  reports and compares, and once inside the shared correlated summary, which
  forms its own. The duplication is deliberate: the shared summary owns its
  estimator, and reproducing its internals here to save one pass would couple the
  case to them.
- **Execution is serial.** Nothing is threaded, no `@fastmath` is used, and no
  performance claim is made that a measurement in this repository does not
  support.
- **CairoMakie appears nowhere under `src/`.** It is loaded inside the driver's
  figure branch alone, so that neither the package, nor the default run, nor the
  test suite pays for a plotting stack it does not use.

## 6. Parameters

### Scientific parameters

Identical under all three presets: a preset changes how much evidence is
gathered, never which process is studied.

| Parameter | Value | Derived quantity | Value |
| --- | --- | --- | --- |
| $`\kappa`$ | `1.0` | relaxation time $`1/\kappa`$ | `1.0` |
| $`\mu`$ | `1.0` | stationary variance $`\sigma^2/(2\kappa)`$ | `0.5` |
| $`\sigma`$ | `1.0` | stationary deviation $`\sigma/\sqrt{2\kappa}`$ | `0.7071…` |
| $`x_0`$ | `-1.0` | initial displacement $`x_0 - \mu`$ | `-2.0` |

The choice $`\kappa = \sigma = 1`$ sets both the relaxation time and the noise
scale to unity, so every time in the study is read directly in units of the
relaxation time. Starting at $`x_0 = -1`$ places the process **two units** below
its long-run mean, and since $`\sqrt{v_\infty} = 1/\sqrt{2}`$ that displacement
is $`2\sqrt{2} \approx 2.83`$ stationary standard deviations, so the transient is
large enough to measure against the fluctuations rather than being lost in them. The transient times $`0.25, 0.5, 1, 2, 4`$ span a quarter of
a relaxation time to four of them, covering the regime in which the mean has
barely moved and the regime in which it has all but arrived.

### Preset values

| Field | `smoke` | `figure` | `production` |
| --- | ---: | ---: | ---: |
| `transient_times` | `[0.25, 0.5, 1.0, 2.0, 4.0]` | same | same |
| `transient_paths` | 4 000 | 30 000 | 200 000 |
| `stationary_samples` | 4 000 | 30 000 | 200 000 |
| `long_path_length` | 20 000 | 100 000 | 250 000 |
| `correlation_step` | 0.1 | 0.1 | 0.1 |
| `maxlag` | 40 | 80 | 80 |
| `euler_steps` | `[0.4, 0.2, 0.1]` | `[0.4, 0.2, 0.1, 0.05, 0.025]` | same as `figure` |
| `euler_paths` | 4 000 | 30 000 | 200 000 |
| `representative_paths` | 4 | 12 | 12 |
| `representative_horizon` | 5.0 | 5.0 | 5.0 |
| `representative_step` | 0.02 | 0.02 | 0.02 |
| `reference_eligible` | `false` | `false` | `true` |

All three parameter sets share one concrete `NamedTuple` type, so the preset
lookup is type-stable. That is why the two grids are stored as
`Vector{Float64}` rather than as tuples: `euler_steps` has three entries under
the smoke preset and five under the others, and tuples would give the three sets
three different types.

The observation step `0.1` is a tenth of the relaxation time, so the correlation
is well resolved in time; the windows of 40 and 80 lags reach four and eight
relaxation times respectively. Only the production preset is eligible to write a
committed reference summary — the smoke preset is a development convenience and
its values are not reportable, and the figure preset exists to render a figure at
a cost between the two.

### Seed map

One master seed, `6_060_606`, from which nine substream seeds are derived. The
slots are semantic and fixed: slot $`i`$ always means the same thing, under every
preset.

| Slot | Consumer |
| ---: | --- |
| 1 | exact transient ensemble |
| 2 | exact stationary independent ensemble |
| 3 | exact stationary long path |
| 4 | representative exact trajectories |
| 5 | Euler study, $`h = 0.4`$ |
| 6 | Euler study, $`h = 0.2`$ |
| 7 | Euler study, $`h = 0.1`$ |
| 8 | Euler study, $`h = 0.05`$ |
| 9 | Euler study, $`h = 0.025`$ |

All nine are derived under every preset, including the smoke preset, whose Euler
grid uses only the first three of the five Euler slots. Deriving the same nine
regardless is what makes a smoke run a genuine prefix of a production run: the
shared derivation is prefix-preserving, so slot $`k`$ holds the same value in
every run of the case, and enlarging the Euler grid extends the set of substreams
rather than renumbering it. The Euler grids are themselves prefixes of one
another, so the step at position $`j`$ of a preset's grid is always the step of
slot $`4 + j`$.

Only the master seed is ever recorded as provenance. The derived seeds are
`UInt64` values that exist in memory and are never written to a reference
summary. The canonical generator is `Xoshiro`; exact reproduction is claimed only
for the canonical Julia series together with the committed manifest, as
[../../docs/methods/reproducibility.md](../../docs/methods/reproducibility.md)
sets out.

## 7. Results

**No results are reported yet, and none has been published.** This section
records what the implemented baseline computes and what remains for Gate 4C-E.1.

Running the driver produces, in memory and on the console:

- the transient mean and variance at each of the five times, each with its
  analytical value, its standard error, and its discrepancy in standard errors;
- the stationary mean and variance, likewise;
- the correlated path's measured integrated autocorrelation time, the
  finite-window analytical value, their relative difference, the effective sample
  size, the autocorrelation-corrected standard error of the mean, and the root
  mean squared difference between the measured and exact autocorrelation series
  over the window;
- the Euler endpoint variance at each step size against $`v_{\mathrm{EM}}(h)`$,
  the measured and exact biases, the log-log fit of the exact bias sequence, and
  the log-log fit of the measured one where every measured bias on the grid is
  strictly positive and that fit is therefore defined;
- a handful of representative trajectories, which are illustrative and from which
  nothing is estimated.

What does **not** yet exist:

- **no committed figure.** The driver's figure branch is implemented and renders
  a two-by-three panel — mean reversion with representative trajectories, the
  growth of the variance, the stationary marginal, the autocorrelation, the
  integrated autocorrelation time against the summation window, and the Euler
  bias — to `figures/ornstein-uhlenbeck.png`. That branch has not been executed,
  the `figures/` directory has not been created, and no PNG exists.
- **no committed reference summary.** The assembly of the schema version 1
  parameters and values is implemented and is checked against the shared
  validator in the test suite as an in-memory candidate. The production branch
  that would capture provenance and write
  `reference/ornstein-uhlenbeck.toml` has not been executed, the `reference/`
  directory has not been created, and no TOML file exists.
- **no reported numerical value.** No number produced by this case is published,
  cited, or claimed to have been reproduced.

## 8. Validation

The comparisons the case performs, and the thresholds they are judged against,
are implemented. The **evidence** they will produce at the production preset
belongs to Gate 4C-E.1.

### Implemented comparisons

| Quantity | Reference | Uncertainty |
| --- | --- | --- |
| transient mean at each $`t`$ | $`m(t)`$, closed form | standard error of the mean, $`\sqrt{v(t)/n}`$ |
| transient variance at each $`t`$ | $`v(t)`$, closed form | $`v(t)\sqrt{2/(n-1)}`$, exact for a Gaussian sample |
| stationary mean | $`\mu`$ | standard error of the mean |
| stationary variance | $`v_\infty`$ | $`v_\infty\sqrt{2/(n-1)}`$ |
| correlated mean | $`\mu`$ | $`s\sqrt{\tau_{\mathrm{int}}/n}`$, corrected for autocorrelation |
| measured $`\tau_{\mathrm{int}}`$ | $`\tau_L`$, the **same** finite window | relative difference |
| measured autocorrelation series | $`\mathrm{e}^{-\kappa k h}`$ | root mean squared difference over the window |
| Euler endpoint variance at each $`h`$ | $`v_{\mathrm{EM}}(h)`$, closed form | $`v_{\mathrm{EM}}(h)\sqrt{2/(n-1)}`$ |
| Euler measured bias at each $`h`$ | $`b_{\mathrm{EM}}(h)`$, closed form | inherited from the variance |

### Acceptance thresholds

Discrepancies in standard errors are judged against the repository-wide threshold
of four standard errors fixed in
[../../docs/methods/error-analysis.md](../../docs/methods/error-analysis.md).
That applies to every independent mean and every independent Gaussian sample
variance in the table above.

For the correlated regime, the thresholds intended for the production preset are
a mean discrepancy within four standard errors, a relative difference between the
measured and finite-window integrated autocorrelation times of at most 0.10, and
an autocorrelation root mean squared error of at most 0.015; the figure preset
admits 0.025 for the last of these. **These are contracts for the evidence gate
and are computed but not enforced at the smoke preset**, whose 20 000-point path
is not the evidence they are written for. What the test suite checks of the smoke
correlated run is structural: that every output is finite, that
$`\tau_{\mathrm{int}} > 1`$, that $`1 < n_{\mathrm{eff}} \le n`$, that the
corrected standard error is positive and larger than the independent one, and
that the array lengths and the window agree.

The smoke preset's statistical checks — the four-standard-error tests on every
transient and stationary moment and on every Euler endpoint variance — are part
of the test suite and pass at the ratified master seed. That is a statement about
the test suite, not a scientific result: the smoke preset is a development
convenience and its values are not reportable.

### What validation does not establish

Validation here establishes agreement between a measured quantity and its closed
form to within a stated uncertainty. It does not establish that the figure is
correct pixel by pixel — figures are validated through the numerical series
behind them and never by pixel comparison — and it makes no goodness-of-fit
claim about the shape of any distribution: no omnibus normality test and no
distributional fit is performed.

## 9. Limitations

- **Nothing is published yet.** No figure, no reference summary, and no reported
  value. The case study is not complete.
- **No strong convergence result.** The case measures the bias of a stationary
  quantity, not pathwise accuracy. Strong pathwise convergence, pathwise Brownian
  coupling between the exact and Euler schemes, and multilevel Monte Carlo are
  all outside its scope, and no order of strong convergence is claimed or
  measured. In particular the study drives the two schemes on **independently
  drawn** randomness, which is correct for comparing invariant measures and would
  be wrong for measuring a strong order.
- **No asymptotic order claim.** The fitted log-log slopes describe the grid
  actually tested. The exact bias is not a pure power law on that grid — its
  log-log slope exceeds one — and the fits are reported as descriptions of the
  tested range rather than as measurements of an asymptotic exponent.
- **The smoke Euler fit is weak by construction.** With three step sizes the fit
  has one residual degree of freedom, so its slope standard error is a
  goodness-of-fit statistic rather than a confidence interval, and it is not
  canonical evidence of anything.
- **A measured bias can come out nonpositive, and the empirical fit is then
  unavailable.** Measured biases are retained **with their signs**, and the
  signed bias is the reported observable. The log-log fit, by contrast, requires
  strictly positive ordinates: the analytical bias is positive throughout the
  admissible interval, but at a step whose bias is comparable with its own
  sampling error the **measured** bias is a random quantity that may be zero or
  negative. When that happens the case study still returns a complete and valid
  result, and the empirical log-log fit alone is reported as unavailable. No
  absolute value is taken, no point is silently dropped, no floor or epsilon is
  applied, and no sample is redrawn. Writing the canonical production reference
  summary is stricter and does require the empirical fit to be defined, because
  the record carries a fitted slope; a result without one is refused before
  anything is written, and the analytical fit is not substituted for it. The
  smaller the sample, the closer this comes to being a live risk; at the smoke
  preset the finest step has a bias of about two standard errors, and at the
  production preset about four.
- **No universal superiority claim.** The exact transition is exact for *this*
  equation, whose transition law happens to be available in closed form. That is
  a property of a linear stochastic differential equation with additive noise and
  does not generalise, and nothing here says that any scheme is better than any
  other in general.
- **The lag window is chosen, not derived.** The summation window is fixed by the
  preset and stated. Adaptive windows, automatic truncation, blocking, plateau
  detection, and block bootstrap intervals remain deferred, and no claim is made
  that the chosen window is optimal.
- **Stationarity is arranged, not tested.** Both stationary regimes begin in the
  invariant law by construction, so no burn-in is needed and none is measured.
  This case therefore contributes no evidence about burn-in diagnostics.
- **Serial execution only.** No threading, and no performance claim.

## 10. Reproduction

From the repository root, with the committed manifest instantiated:

```
julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl
julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl smoke
julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl figure
julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl production
```

The preset is chosen by that one optional positional argument and by nothing
else: no environment variable is read, no tracked file has to be edited, and
there is no hidden fallback. An unrecognised name, or more than one argument, is
an error naming what was given. With no argument the driver runs the smoke
preset.

- **`smoke`** — the default. Writes nothing, creates no directory, renders no
  figure, and produces no reference summary. It completes in a few seconds on the
  canonical environment.
- **`figure`** — additionally renders the figure. It requires
  `case-studies/06-ornstein-uhlenbeck/figures/` to exist already; the driver
  refuses to create it, because creating a directory implicitly is how a mistyped
  case slug becomes a second, silently empty case directory. That directory does
  not exist at present and this preset has not been run.
- **`production`** — additionally captures provenance and writes the reference
  summary. It requires the preset to be eligible and
  `case-studies/06-ornstein-uhlenbeck/reference/` to exist already, and
  provenance capture requires a clean working tree, so the recorded commit alone
  identifies the code and the committed manifest. That directory does not exist
  at present and this preset has not been run.

The master seed is `6_060_606` and the canonical environment is Julia 1.12.6 with
the committed `Manifest.toml`. Exact reproduction is claimed for that
combination; on other supported versions reproduction is statistical, as
[../../docs/methods/reproducibility.md](../../docs/methods/reproducibility.md)
records.

The case's own tests run with the rest of the suite:

```
julia --project=. -e "using Pkg; Pkg.test()"
```

## 11. References

The analytical results of section 3 are standard properties of a linear
stochastic differential equation with additive noise, and each is derived in this
document from the equation itself: the transient moments, the exact transition,
the invariant law, the autocorrelation, and the invariant variance of the
Euler–Maruyama recursion are all obtained here rather than quoted.

The implementation is written in Julia [1].

**Final public citations for this case remain for Gate 4C-E.1.** No external
source specific to the Ornstein–Uhlenbeck process is cited yet, and
[../../docs/references.bib](../../docs/references.bib) is deliberately unchanged
by this gate: an entry is added only when its bibliographic metadata has been
verified against an authoritative record, and none has been verified for this
case.

1. Bezanson, J., Edelman, A., Karpinski, S., and Shah, V. B. *Julia: A Fresh
   Approach to Numerical Computing*. SIAM Review **59**(1), 65–98, 2017.
   [doi:10.1137/141000671](https://doi.org/10.1137/141000671).
   Recorded as `Bezanson2017Julia` in
   [../../docs/references.bib](../../docs/references.bib).

Repository conventions governing this case:
[../../docs/methods/error-analysis.md](../../docs/methods/error-analysis.md),
[../../docs/methods/rng-and-seeding.md](../../docs/methods/rng-and-seeding.md),
[../../docs/methods/reproducibility.md](../../docs/methods/reproducibility.md),
[../../docs/notation.md](../../docs/notation.md),
[../../docs/style-guide.md](../../docs/style-guide.md), and the decision record
[../../docs/decisions.md](../../docs/decisions.md).
