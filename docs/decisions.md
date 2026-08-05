# Decision record

This record is append-only. Entries state what was decided and, where it is not
self-evident, why. An entry is never rewritten or deleted; if a decision is later
changed, the original entry remains and a new entry supersedes it by identifier.

Identifiers have the form `G<gate>-D.<n>` for decisions, `G<gate>-CORR.<n>` for
scientific corrections, and `G<gate>-DEF.<n>` for decisions deliberately deferred.

---

## Gate 1 — Architecture

**Ratified 2026-07-31.**

### Identity and scope

**G1-D.1 — Public identity and case-study framing.**
The repository is published as *Stochastic Systems in Julia*, subtitled *Ten
Reproducible Numerical Case Studies in Probability, Stochastic Processes, and
Computational Statistical Physics*. The public framing is **case studies**. The
repository is not described as a homework archive, an assignment collection, a
course reconstruction, or a portfolio.

**G1-D.2 — Case order and numeric slugs frozen.**
The numbering, order, and directory slugs of the ten cases, from
`01-central-limit-theorem` to `10-lennard-jones-md`, are frozen. Renumbering
would invalidate directory names, cross-references, and any external link.

**G1-D.3 — Five-part taxonomy.**
The cases are grouped into five parts: I, Foundations of Randomness and
Convergence; II, Counting and Jump Processes; III, Diffusion and Stochastic
Differential Equations; IV, Monte Carlo Sampling and Stochastic Optimisation; V,
Stochastic Dynamics of Physical Systems. The grouping is by mathematical
structure rather than by application area, so that each part introduces one class
of process.

### Scientific structure

**G1-D.4 — CS-02 retitled to foreground Markov-chain convergence.**
CS-02 is titled *Markov Chain Convergence and Information Loss in a Binary
Symmetric Channel*. The subject of the case is the convergence of the channel's
Markov chain towards its stationary distribution; the information-theoretic
quantity is the consequence studied alongside it, not the sole topic.

**G1-D.5 — CS-07 and CS-08 paired conceptually.**
CS-07 and CS-08 form a conceptual pair: Metropolis sampling of an equilibrium
distribution at fixed temperature, against the same family of stochastic moves
redirected towards optimisation by an annealing schedule. The pairing is
conceptual only. It does not require that an Ising-specific kernel be reused in
CS-08, and CS-08 is free to implement whatever move set its own geometry demands.

**G1-D.6 — Shared correlated-data error analysis.**
One shared treatment of correlated samples serves every case that produces them,
rather than an ad hoc treatment per case. The standards are recorded in
[methods/error-analysis.md](methods/error-analysis.md).

**G1-D.7 — Amended dependency between CS-09 and CS-10.**
CS-09 validates the exact joint free-particle Langevin transition. CS-10 reuses
the exact Ornstein–Uhlenbeck thermostat substep inside the BAOAB integrator. This
supersedes any earlier reading in which the two cases shared only a general
theme: the dependency is a concrete reuse of an exactly sampled substep.

**G1-D.8 — Depth tiers.**
Tier A: CS-01, CS-02, CS-03, CS-05. Tier B: CS-04, CS-06, CS-08, CS-09. Tier C:
CS-07, CS-10. The tiers allocate analytical and numerical depth deliberately, so
that it does not drift case by case.

### Software architecture

**G1-D.9 — Thin driver, performance kernel.**
Each case study is driven by a thin script that sets parameters, calls into the
package, and presents results. Performance-critical numerical work lives inside
package functions, never at top level, so that it is compiled rather than
interpreted in global scope.

**G1-D.10 — `# %%` cell delimiter.**
`# %%` is the canonical cell delimiter for drivers, matching the Julia extension
for VS Code. Drivers keep intermediate variables visible in the REPL rather than
hiding them inside a single entry point.

**G1-D.11 — Three execution presets.**
Every driver exposes `:smoke`, `:figure`, and `:production`. Committed drivers
default to `:smoke`, so that running a driver immediately after cloning never
starts an unexpectedly long computation.

**G1-D.12 — One package with semantic case submodules.**
A single shared package, `StochasticCaseStudies`, holds the common
infrastructure; each case study is added as a semantic submodule at its own
implementation gate. One package keeps the environment single and the shared
utilities genuinely shared; submodules keep each case's namespace its own.

**G1-D.17 — Minimal dependency set; integrators implemented internally.**
The direct scientific dependencies are Distributions.jl, StatsBase.jl,
HypothesisTests.jl, and CairoMakie.jl, with StableRNGs.jl for testing. Stochastic
integrators and sampling algorithms are implemented within this repository rather
than taken from a differential-equation library, because the numerical method is
itself the object of study. Dependencies are never added casually.

**G1-D.18 — CairoMakie.**
CairoMakie is the plotting backend: it renders publication-quality static figures
headlessly, which suits both a committed PNG workflow and continuous integration.

**G1-D.19 — Performance standards eventually enforced as tests.**
Performance expectations for the numerical kernels are eventually expressed as
tests rather than left as prose. Not yet implemented.

### Environment and reproducibility

**G1-D.13 — Julia 1.10 minimum; Julia 1.12.6 canonical.**
The minimum supported Julia version is 1.10. The canonical development and
reproduction environment is Julia 1.12.6.

**G1-D.14 — Committed canonical manifest.**
`Manifest.toml` is committed. This repository is an application rather than a
library, so pinning the exact package versions used to produce the published
results is correct. The interaction between the canonical manifest and the Julia
LTS release is subject to the Gate 2 experiment recorded in G1-DEF.1.

**G1-D.15 — Explicit RNG and deterministic substreams.**
Every function that consumes randomness takes an explicit `rng::AbstractRNG`
argument; package code never calls `Random.seed!()`. Each experiment declares one
master seed, from which substream seeds are derived deterministically. See
[methods/rng-and-seeding.md](methods/rng-and-seeding.md).

**G1-D.16 — Exact versus statistical reproducibility.**
Exact reproduction is claimed only for the canonical Julia minor series together
with the committed manifest. On other supported versions, reproduction is
statistical: agreement is expected within the stated uncertainty, not to the last
bit. Julia does not guarantee identical default random streams across minor
releases, and the repository does not pretend otherwise.

**G1-D.29 — Reproducibility eventually enforced in CI.**
Continuous integration eventually verifies committed numerical reference outputs
rather than merely running the test suite. The scaffold for this check exists in
[../scripts/verify_reproducibility.jl](../scripts/verify_reproducibility.jl); no
reference values have been registered yet.

### Standards

**G1-D.20 — Statistical assertion thresholds.**
Statistical assertions use four standard errors. Hypothesis tests use
`alpha = 0.001`. Both thresholds are chosen so that a correct implementation
fails only very rarely across a suite run repeatedly in continuous integration.

**G1-D.21 — Committed figures with numerical provenance.**
Figures are committed per case as PNG, each accompanied by the numerical data
needed to verify it. Verification is performed on the numerical series, never by
comparing pixels.

**G1-D.22 — Language and GitHub conventions.**
British scientific English with -ise forms in prose; Julia ecosystem naming in
code. GitHub mathematics uses `` $`...`$ `` inline and fenced `math` blocks for
display. Links are relative and point at files or functions, never at mutable
line numbers. See [style-guide.md](style-guide.md).

**G1-D.23 — Central notation policy.**
A central policy governs only symbols that would otherwise collide between cases;
each case declares its own local symbol table. Conventions that vary legitimately
between textbooks — for example the normalisation used for the Ising
susceptibility — are declared explicitly in the case that uses them rather than
assumed universal. See [notation.md](notation.md).

### Presentation, licensing, and governance

**G1-D.24 — Dual licensing.**
Julia source code is licensed under MIT; original prose, figures, and lightweight
generated numerical data under CC BY 4.0. Third-party content remains under its
own terms and is explicitly attributed.

**G1-D.25 — Linux continuous integration.**
Continuous integration runs on Linux and covers the test suite, formatting, and
the reproducibility scaffold. Windows and macOS runners are deferred: the
scientific claims are platform-independent, and the author already exercises
Windows locally.

**G1-D.26 — LF line endings via `.gitattributes`.**
All text is stored and checked out with LF endings, so that diffs, checksums, and
formatter output are identical for a Windows author and a Linux runner.

**G1-D.27 — Minimal governance.**
Governance consists of [../CLAUDE.md](../CLAUDE.md) and this decision record.
Nothing further is added while the repository has a single author.

**G1-D.28 — CS-06 pilot, CS-05 second.**
CS-06 is implemented first. It exercises the whole intended architecture — an
exact transition law to validate against, a convergence study over several
schemes, and a figure backed by committed numerical data — at a scale small
enough to be run repeatedly while the shared infrastructure settles. CS-05
follows, as the first test that the architecture generalises rather than having
been fitted to one case.

### Scientific corrections

**G1-CORR.1 — Berry–Esseen hypotheses.**
Berry–Esseen bounds, and universal rate assertions of order `n^(-1/2)`, hold only
under their required finite-moment hypotheses, which are stronger than the finite
variance the central limit theorem itself requires. Distributions that are
heavy-tailed but have finite variance must be treated as a separate case, and no
universal rate may be asserted for them.

**G1-CORR.2 — No unsupported optimality claim in CS-08.**
CS-08 makes no claim of global optimality and no upper bound on the achievable
packing fraction of the specified bidisperse mixture. Simulated annealing yields
a good configuration, not a proven optimum. The optimal packing fraction of
congruent disks in the plane, `π / (2√3) ≈ 0.9069`, is context for the problem
and is not an upper bound for a mixture of two disk sizes.

**G1-CORR.3 — Exact Langevin transition and its reuse.**
CS-09 validates the exact correlated joint position–velocity transition of the
free Langevin particle; position and velocity are jointly Gaussian and
correlated, and the validation must treat them jointly rather than marginally.
CS-10 reuses the exact Ornstein–Uhlenbeck thermostat component of that transition
as the O substep of BAOAB.

**G1-CORR.4 — Force-continuous cutoff in CS-10.**
CS-10 uses a force-continuous cutoff strategy, provisionally a force-shifted
Lennard-Jones interaction, so that the truncation does not introduce an impulsive
force at the cutoff radius. The final choice is confirmed when CS-10 is
implemented.

### Deferred decisions

**G1-DEF.1 — Canonical manifest versus Julia LTS in CI.**
The mechanism by which continuous integration tests both the canonical manifest
and the Julia LTS release is resolved experimentally during Gate 2 rather than
assumed in advance. See G2-D.5.

### Owner decisions

- Citation identity: **Edgar Axel Pérez Flores**.
- ORCID: deferred. None is recorded, and none is invented.
- Development continues on the branch `rework/portfolio-v1`.
- The first merge to `main` occurs after the scaffold, the shared infrastructure,
  and a complete CS-06 pilot.
- That first public milestone is **v0.1.0**.
- **v1.0.0** requires all ten completed case studies.

---

## Gate 2A-I — Canonical repository scaffold

**Implemented 2026-07-31, under the authority of Gate 2A-I; submitted for owner
audit.**

The entries below record implementation decisions taken while translating the
Gate 1 architecture into the repository scaffold. They document what was done and
on what evidence.

**G2-D.1 — Package name and identity.**
The package is `StochasticCaseStudies`, UUID
`42ee9c3e-c0b5-4ecf-8812-4f39dbfa284b`, version `0.1.0-DEV`. The name was checked
against the local General registry, which contained no exact, case-insensitive,
or near collision among its 13 729 registered packages.

**G2-D.2 — Compat bounds pinned to the resolved minor series.**
Each direct dependency carries a caret bound on the minor series actually
resolved, rather than the patch-level bound the package manager generates by
default. Nothing is left unbounded. The looser bound is deliberate: it gives the
LTS resolver of G2-D.5 room to select a version of the same series that suits
Julia 1.10, without admitting an unrelated series the repository has never been
developed against. Every resolved version was confirmed against the registry to
declare a `julia` compat bound admitting 1.10.

**G2-D.3 — StableRNGs declared as a test dependency.**
A candidate implementation decision awaiting owner ratification, amended under
Gate 2C-I-CORR.1 to record the verified mechanism rather than the assumed one.
StableRNGs is declared in `[extras]` and the `test` target rather than in
`[deps]`, matching its ratified role, under the compat bound `"1.0"`. The
consequence of that declaration is more subtle than first recorded here. The
canonical `Manifest.toml` does contain StableRNGs 1.0.4, so current canonical
test execution uses that manifest-pinned version. Its presence in the manifest is
incidental rather than guaranteed by the test-only declaration: it enters
transitively, as a dependency of PlotUtils, which is reached from CairoMakie
through Makie. Were a future environment resolution to drop that transitive path,
`Pkg.test()` could resolve StableRNGs independently within compat `"1.0"`, and
the version the tests use would no longer be pinned by the committed manifest.
Whether StableRNGs requires a more explicit pin — promotion to `[deps]`, or a
tighter bound — is left to a later decision, taken once stochastic scientific
tests exist and the exposure is concrete.

**G2-D.4 — Canonical location of numerical reference summaries.**
Reference summaries are committed as TOML at
`case-studies/<slug>/reference/<name>.toml`, each carrying a `[provenance]`
table. The verification script searches exactly that location. The required
provenance fields are provisional and are held in one constant so that the gate
registering the first reference values can extend them.

**G2-D.5 — Manifest and LTS mechanism, resolving G1-DEF.1 provisionally.**
Continuous integration separates the two purposes. The canonical job instantiates
the committed manifest and reproduces the pinned environment. The LTS job deletes
the manifest in its ephemeral checkout and resolves afresh from `Project.toml`,
which tests package-compatibility on the supported floor and makes no claim about
bitwise reproduction. The mechanism is provisional until it has been observed to
work on a real runner; local verification was impossible because Julia 1.10 is
not installed on the author's machine and the gate forbids installing it.

**G2-D.6 — Formatting toolchain.**
Formatting uses JuliaFormatter v1 through `julia-actions/julia-format@v4`, which
pins that major version by default and reads `.JuliaFormatter.toml`. The
formatter is therefore never a dependency of the scientific environment. The
configuration is conservative, and preserves authored line breaks so that a
numerical expression laid out to mirror its mathematics survives formatting.

---

## Gate 3 — Shared infrastructure

**Ratified 2026-08-02.** Following the independent architecture review of Gate
3A-R, the owner ratified the decisions **G3-D.1** through **G3-D.12**, the
scientific correction **G3-CORR.1**, and a **narrowed G3-DEF.1**.

**Amended 2026-08-03.** Following the independent audit of Gate 3C-R, the owner
ratified the scientific corrections **G3-CORR.2** and **G3-CORR.3**. G3-CORR.2
restores the authoritative identities of G3-D.1 through G3-D.12, which the first
uncommitted draft of this section had misassigned; that draft had not been
published, and it is corrected in place under the explicit authority of
G3-CORR.2 rather than superseded by identifier.

The entries below record each ratified decision as it was implemented. Gate 3 is
divided into the implementation sequence recorded in G3-D.11; the stages carried
out so far are recorded under *Implementation status* below.

### Dependency plane

**G3-D.1 — Standard libraries promoted to direct dependencies.**
`Random`, `Statistics`, `TOML`, and `Dates` are declared in `[deps]`, each under
the compat bound `"1"`. A standard library that package code loads is a direct
dependency whether or not it also arrives transitively, and declaring it makes
the dependence visible and bounded. `TOML` was previously declared only in
`[extras]` and the `test` target; it is removed from both, because it is now a
dependency of the package rather than of its tests. `Test` and `StableRNGs`
remain test-only. All four promotions were made in one change, so that the
dependency plane moves once, even though `TOML` and `Dates` are first consumed by
the reproducibility layer of Gate 3B-I.2.

### Source organisation

**G3-D.2 — A flat include-based numerical layer in one module.**
The shared numerical utilities are plain functions defined directly in
`StochasticCaseStudies`, gathered into one file per subject and included in
dependency order. There is no infrastructure submodule, no abstract process
hierarchy, no universal result type, and no generic simulation framework. Small
functions with explicit arguments are easier to test, to reason about, and to
read against the mathematics than a framework would be, and nothing yet known
about the ten cases requires shared machinery beyond them. Case-study submodules
remain as ratified in G1-D.12, and are added at their own gates.

**G3-D.3 — The package exports nothing through the CS-06 pilot.**
Every shared function is reached through an explicit import, as in
`using StochasticCaseStudies: derive_seeds, rmse, fit_loglog`. A driver therefore
names what it depends on, and no identifier enters a caller's namespace
unannounced. Julia's `public` keyword is not used, because it does not exist in
Julia 1.10 and G1-D.13 fixes 1.10 as the supported minimum.

The decision carries an explicit horizon. It holds **through the CS-06 pilot**,
which is the first consumer of the shared layer and therefore the first evidence
of what an import list actually costs a driver to write and a reader to follow.
The export question is revisited only after that pilot, against that evidence,
and not before.

### Shared numerical contracts

**G3-D.4 — The preset vocabulary is shared; preset values belong to the cases.**
The shared layer fixes only the tuple `(:smoke, :figure, :production)` of G1-D.11
and a validating lookup over a case's own preset table. What a preset means
numerically differs between cases by orders of magnitude, so it is a scientific
property of the case that declares it. There is no `Preset` type, no fallback
preset, and no environment-variable override: an unrecognised preset name, or a
malformed table, is an error rather than a silent substitution.

**G3-D.5 — Seed derivation is explicit, deterministic, and visibly `Xoshiro`.**
`derive_seeds` implements the scheme planned in G1-D.15: one master seed per
experiment, from which `UInt64` substream seeds are drawn. Both an `AbstractRNG`
and a plain nonnegative integer master are accepted, the latter constructing the
canonical `Xoshiro`, which is named rather than left ambient so that a reader can
see which stream a result came from. Master seeds are plain integers, restricted
to `0 ≤ seed ≤ typemax(Int64)` so that a recorded seed is an ordinary
nonnegative integer whatever type a driver uses.

The seeds are drawn one at a time rather than through the array form of `rand`.
Julia does not specify that the array form agrees with successive scalar draws,
and for `Xoshiro` it does not: on Julia 1.12.6,
`rand(Xoshiro(2026), UInt64, 8)` does not reproduce eight successive scalar
`rand(rng, UInt64)` draws, and so does not preserve the prefix contract. That is
version-specific engineering evidence and nothing more; no claim is made about a
threshold at which the array form changes behaviour, nor about the internal
mechanism of Julia's generator. Drawing scalars makes the prefix property hold
for every generator, so that enlarging an experiment extends its set of
substreams instead of replacing it.

No collision-freedom is promised, no seed wrapper type is introduced, no test
asserts a value of either stream, and `StableRNGs` remains test-only.

**G3-D.6 — Shared independent-sample statistics, and a minimal correlated layer.**
Gate 3 implements the shared summaries and discrepancy measures for independent
samples — `summarize_independent`, `nsigma`, `rmse`, `relative_error` — and the
minimal explicit-window correlated layer established by G3-CORR.1:
`integrated_autocorrelation_time` and `summarize_correlated`, under the
convention recorded there, with the summation window supplied by the caller. The
i.i.d. precondition is named in the function that requires it, because violating
it is the most common way to report an interval wrong by a large factor. Broader
correlated machinery — adaptive windows, automatic truncation, blocking, and
bootstrap intervals — remains deferred under the narrowed G3-DEF.1.

**G3-D.7 — Convergence orders are fitted by elementary log-log least squares.**
`fit_loglog` estimates an empirical order of convergence by unweighted ordinary
least squares on logarithms, using elementary sums, so no regression dependency
is added to the ratified set of G1-D.17. The validity guards are hard: unequal
lengths, fewer than three points, a nonpositive or nonfinite abscissa or
ordinate, a constant `log(x)` or `log(y)`, and a nonfinite diagnostic are errors
rather than degraded fits, and no point is ever discarded silently. Fitting on
logarithms treats relative error as homoscedastic, which suits errors spanning
decades; that is an assumption and is recorded in the function's own
documentation. Weighted fitting, and the acceptance bands that would decide
whether a measured slope confirms a claimed order, are not implemented at this
gate.

**G3-D.8 — Brownian paths as increment vectors with an explicit step size.**
A Brownian path is represented by a plain vector of increments together with the
step size `dt` that generated it. There is no `BrownianPath` type: an increment
vector and its step size carry everything a caller needs, and a wrapper would
only obscure that. `brownian_increments` draws the increments from an explicit
generator; `coarsen_increments` reduces them to a coarser grid by summing
non-overlapping blocks of an integer factor. Coarsening exists so that a
convergence study can drive several step sizes with one path: comparing schemes
on independently drawn paths confounds discretisation error with sampling error
and destroys the strong order one is trying to measure. Indexing is integral
throughout, so that no grid point is reached by accumulating rounding error and
no floating-point time grid is built.

The shared layer stops there. The Ornstein–Uhlenbeck weighted stochastic
integrals, and the exact transition laws that CS-09 validates and CS-10 reuses
under G1-D.7 and G1-CORR.3, are **case-local**: they belong to the cases that
define them, and are not generalised into the shared layer in advance of a second
consumer.

**G3-D.9 — A versioned reference-summary schema, written atomically and
validated by path.**
Committed numerical reference summaries carry an explicit schema version, so that
a later change to the required fields is a visible migration rather than a silent
divergence between old and new files; they are written atomically, so that an
interrupted run leaves either the previous summary or the new one and never a
truncated file; and they are validated against the canonical location fixed in
G2-D.4, so that a summary in the wrong place is a failure rather than an
omission.

**This decision is implemented in the current working-tree candidate**, under
Gate 3B-I.2 and separately from the numerical candidate of Gate 3B-I.1. The
implementation status below records what was built and what remains open.

**G3-D.10 — Immutable `NamedTuple` returns over plain arrays.**
A function that reports several quantities returns a `NamedTuple` with a fixed
field set, and numerical data are plain `Array`s. There is no universal
simulation-result abstraction. The fields are named, so a caller cannot silently
transpose two of them; the value is immutable, so a summary cannot be edited
after the fact; and no custom type has to be documented, printed, or serialised
before a result can be reported.

**G3-D.11 — Gate 3 proceeds as a split implementation sequence.**
Gate 3 is divided into stages, so that the numerical and reproducibility layers
are audited separately and neither is published unreviewed:

1. **Gate 3B-I.1** — the shared numerical layer;
2. **Gate 3B-I.2** — the reproducibility layer: the metadata schema, the
   reference-summary writer, the path-aware validator, and the refactor of
   [../scripts/verify_reproducibility.jl](../scripts/verify_reproducibility.jl);
3. **Gate 3C-R** — independent audit;
4. **Gate 3C-C** — bounded corrections, if the audit requires any;
5. **Gate 3D-C** — owner staging, commit, push, and continuous integration;
6. **Gate 4A-R** — the architecture of the CS-06 pilot.

**G3-D.12 — Type stability, without unsupported performance claims.**
The shared numerical functions infer concrete return types for their intended
inputs, and the test suite checks this with `@inferred`. Allocating a returned
vector is legitimate; a clearly unnecessary full-length intermediate is not. No
zero-allocation claim is made at this gate, and no allocation threshold is
asserted: such tests are reserved for the in-place hot kernels that a later gate
will designate. Threading is not introduced, `@fastmath` is not used, and no
performance claim is made that a measurement in this repository does not support.

### Ratified Gate 3 implementation principles

These three principles were ratified with the decisions above and govern how the
shared layer is written. They deliberately carry **no `G3-D` identifier**: they
are standing practice rather than architectural choices between alternatives, and
numbering them would imply a decision point that was never taken.

1. **Established package and standard-library primitives are used rather than
   reimplemented without scientific justification.** The shared statistics call
   `Statistics.mean`, `Statistics.std`, `StatsBase.sem`, `StatsBase.autocor`, and
   the Student-*t* quantiles of `Distributions`. What the shared layer adds is
   the scientific contract around them: the stated precondition, the validation,
   and the returned interval. Rewriting a variance or a quantile would add a
   second thing to verify without adding anything to trust. Where a numerical
   method is itself the object of study, G1-D.17 already requires the opposite,
   and that requirement governs.

2. **Violated scientific contracts produce explicit errors rather than silent
   fallbacks, `NaN` or `Inf` results.** Every shared function validates its
   preconditions and throws `ArgumentError` when one fails, naming the offending
   input. Nothing degrades silently: a zero reference in a relative error, a
   nonpositive integrated autocorrelation time, a constant abscissa in a fit, or
   an accumulation that overflows the `Float64` domain stops the computation
   rather than returning `Inf`, `NaN`, or a substituted default. No warning is
   emitted in place of an error, because a warning in a long run is a message
   nobody reads.

3. **The test suite uses a stable includer while preserving all pre-existing
   scaffold checks.** `test/runtests.jl` keeps the scaffold tests of Gate 2 and
   otherwise only includes one test file per shared source file, so that a later
   gate adds a line rather than restructuring the file. Statistical tests use
   explicitly constructed generators and the thresholds of G1-D.20; `StableRNGs`
   is never used to freeze a statistical outcome.

### Scientific corrections

**G3-CORR.1 — The correlated-sample layer is implemented in stages.**
This refines the implementation timing of G1-D.6, which requires one shared
treatment of correlated samples, and supersedes any reading of it under which the
whole treatment had to arrive at once. Gate 3 implements the explicit-window
integrated autocorrelation time, the effective sample size derived from it, and
the corresponding correlated-mean uncertainty, under the convention

```math
\tau_{\mathrm{int}} = 1 + 2 \sum_{k=1}^{M} \rho(k), \qquad
n_{\mathrm{eff}} = \frac{n}{\tau_{\mathrm{int}}}, \qquad
\mathrm{SE} = s \sqrt{\frac{\tau_{\mathrm{int}}}{n}}
```

with the summation window $`M`$ supplied by the caller. The standard of G1-D.6 is
unchanged: a quantity estimated from a correlated series is still analysed with
an effective sample size rather than a raw count. What changed is that the
selection rules — adaptive windows, blocking plateaux — are held back until a
case study produces correlated data against which their behaviour can be judged,
rather than being written against no data at all.

**G3-CORR.2 — Authoritative Gate 3 decision identities, and the retraction of an
unsupported RNG claim.** *Ratified 2026-08-03.*
The first uncommitted draft of this section misassigned the Gate 3 identifiers.
Three standing practices had been numbered as decisions and given the identifiers
`G3-D.7`, `G3-D.8` and `G3-D.11`, displacing the log-log fitting decision, the
Brownian representation decision, the shared-statistics decision, the
reference-summary decision, and the implementation-sequence decision from the
identities the owner ratified. The correction restores the authoritative mapping
of **G3-D.1** through **G3-D.12** as recorded above; restores the *through the
CS-06 pilot* horizon in G3-D.3, which the draft had dropped; and places the three
practices in the unnumbered subsection *Ratified Gate 3 implementation
principles*, where they carry no `G3-D` identifier. Because the draft had not
been staged, committed, or published, it is corrected in place under this
correction's own authority rather than superseded entry by entry.

The correction also retracts an unsupported claim about Julia's random number
generator. The draft asserted that the array form of `rand` for `Xoshiro` takes a
vectorised path once more than four values are requested, and that its output is
a permuted interleaving of the scalar stream. Neither is supported: the
repository has measured only that on Julia 1.12.6,
`rand(Xoshiro(2026), UInt64, 8)` does not reproduce eight successive scalar
`rand(rng, UInt64)` draws, and therefore does not preserve the prefix contract
`derive_seeds` requires. That measurement is retained as version-specific
engineering evidence in
[methods/rng-and-seeding.md](methods/rng-and-seeding.md) and in the source; the
claims about a four-draw threshold and about the generator's internal mechanism
are withdrawn, because Julia documents neither and the repository has established
neither. The implemented scalar-draw algorithm is unchanged, and no test asserts
a value of either stream.

**G3-CORR.3 — Argument-domain and finiteness contracts for the shared numerical
layer.** *Ratified 2026-08-03.*
The shared numerical layer states its contracts in the `Float64` numerical
domain, and enforces them there. Four consequences are recorded.

*Integer range.* An `Integer` argument that is converted to `Int` before it is
used to allocate or to index is validated first, against an inclusive lower bound
and against `typemax(Int)`. A value outside that domain throws an `ArgumentError`
naming the argument, never an `InexactError` naming a machine type, and it does
so before any allocation or indexing. The contract applies to the substream count
of `derive_seeds` (`0 ≤ n`), the increment count of `brownian_increments`
(`1 ≤ n`), the factor of `coarsen_increments` (`1 ≤ factor`), and the summation
window of `integrated_autocorrelation_time` and `summarize_correlated`
(`0 ≤ maxlag`). Scientific restrictions beyond the representable range still
apply after the conversion. The master-seed domain of G3-D.5,
`0 ≤ master_seed ≤ typemax(Int64)`, is unchanged.

*Float64 domain and finite output.* A value that is mathematically finite but
whose conversion to `Float64` is not — a `BigInt` of order `10^400`, say — is
rejected with an `ArgumentError` rather than admitted as an infinity. No shared
function returns `NaN` or `Inf` from otherwise accepted input: an overflow in a
subtraction, a square, an accumulation, a division, or a block sum is an error.
A genuinely constant finite sample remains admissible, and its zero-width
interval remains the correct report.

*One-based indexing.* `summarize_correlated` passes its series to
`StatsBase.autocor`, which requires one-based indexing, so
`Base.require_one_based_indexing` is enforced and an offset-indexed series is
rejected explicitly rather than silently misaligned.
`integrated_autocorrelation_time` indexes from `firstindex` and continues to
accept an offset-indexed autocorrelation function.

*Internal constants and the defensive ESS guard.* The two internal constants of
the correlated layer, `_ACF_LAG_ZERO_TOLERANCE = 1e-8` and `_MIN_LAG_PAIRS = 3`,
are accepted as implementation constants and receive no decision identifier. The
`ess > 1` guard in `summarize_correlated` is retained: the Gate 3C-R audit
established that under exact arithmetic, and under the demeaned denominator-`n`
autocorrelation convention `StatsBase` currently uses, the preceding guards
already imply it, but it remains defensively useful against floating-point corner
cases, a future change of estimator, and pathological external input.

### Infrastructure corrections

The three corrections below arise from the independent Gate 3C-R audit of the
reproducibility layer and are applied under **Gate 3C-C.1**. They continue the
`G3-CORR` sequence, but unlike G3-CORR.1 to G3-CORR.3 they settle questions of
infrastructure rather than of scientific method. They alter nothing in the frozen
numerical layer, and they alter no earlier decision: G3-D.1 to G3-D.12,
G3-CORR.1 to G3-CORR.3, and the narrowed G3-DEF.1 stand exactly as recorded
above, in identity and in substance.

**G3-CORR.4 — Replacement of a reference summary is atomic or it fails.**
*Ratified 2026-08-03.*
The writer's replacement step is **fail-closed**. It either performs the platform
primitive that replaces atomically — `rename(2)` on POSIX, `MoveFileEx` with
replacement on Windows — or it throws the original I/O error. Two mechanisms
implement it: **Julia ≥ 1.12 calls `Base.rename`**, and **Julia 1.10–1.11 call
`jl_fs_rename` directly**, raising the libuv error themselves.

The direct call on the supported floor is the substance of the correction. On
those releases `Base.Filesystem.rename` falls back to copying the source and
removing it when the primitive fails, and a copy followed by a remove is exactly
the non-atomic sequence the contract exists to exclude; reaching the primitive
without that wrapper is the only way to guarantee on the LTS release what is
promised on the canonical one. **No fallback of any kind remains**: no `cp` and
`rm`, no `mv`, and no removal of an existing target before the replacement. A
refused replacement preserves an existing target, removes only the temporary
residue, and propagates the original error. The guarantee rests on the atomicity
of the platform call; **no power-loss scenario has been experimentally tested**,
and none is claimed.

**G3-CORR.5 — The reference tree is detected case-insensitively and accepted
only in canonical lower case.** *Ratified 2026-08-03.*
Detection is deliberately broader than acceptance. A path component equal to
`case-studies` **under case folding** marks a destination as an attempt to write
into the committed reference tree; the component's original spelling is then
carried into the strict validator, which accepts only
`case-studies/<case>/reference/<result>.toml` exactly. `CASE-STUDIES`,
`Case-Studies`, `case-Studies`, and `CASE-studies` are therefore detected and
then refused, for repository-relative, absolute, Windows, and mixed-separator
paths alike.

The asymmetry is the correction. On a case-insensitive filesystem — the default
on Windows and macOS — a case-folded spelling that escaped detection would have
been treated as an unrestricted development path, and a `smoke` record would have
been written straight into the committed tree.

**Case folding alone did not close every Windows component alias, and this entry
must not be read as claiming that it did.** The Gate 3C-A.1 audit subsequently
demonstrated that a component carrying trailing dots or trailing spaces also
resolves physically to the canonical directory on Windows, and escaped the
case-folding detector. **G3-CORR.7 below governs**, and extends detection to
those forms.

The same correction makes a **lowercase `.toml` destination mandatory for every
writer call**, inside the committed tree and outside it, checked before the
filesystem is touched: `draft.json`, `draft.txt`, `draft.TOML`, and an
extensionless `draft` are refused. A **development record outside `case-studies/`
may still carry `preset = "smoke"`** — that permission is unchanged — but its
destination must still end in `.toml`.

**Windows 8.3 short-name aliases remain deferred.** No claim is made that a path
reaching the writer through an alias such as `CASE-S~1` is recognised. The
concern is recorded as platform-specific alias work belonging to a case study
that actually exercises such a path, rather than repaired speculatively.

**G3-CORR.6 — Path hardening, bounded metadata, explicit precision semantics,
and reconciled Gate 3 documentation.** *Ratified 2026-08-03.*
Six matters are settled together.

*Control-character path hardening.* The Unicode control ranges `U+0000`–`U+001F`
and `U+007F`–`U+009F` are refused in `generated_by`, in a supplied `source_path`,
in the writer's destination, and in recursively validated payload fields whose
names denote paths under the existing path-key policy. In the destination the
check runs before any filesystem access; in the pure validator it is reported as
a problem and never raised. Ordinary Unicode — spaces, punctuation, percent
signs, non-ASCII letters — is not restricted. Percent-encoded text is read
literally with no URL decoding, and Unicode characters resembling a solidus are
ordinary characters rather than separators.

*Reserved notes reject `NUL` alone.* `provenance.note` and `values.<name>.note`
admit multiline prose, tabs, and newlines; only `U+0000` is refused, because it
terminates a string in every interface the record passes through.

*A fictitious example slug.* Generic infrastructure examples use
**`99-example-process`**, which names no case study and could not be mistaken for
one. It replaces `06-brownian-motion` throughout the source docstrings, the test
fixtures, and the method document. `06-ornstein-uhlenbeck` is **not** used for
this purpose: it is reserved for the scientific case gate that will define it. No
example directory is created.

*A bounded thread count.* `provenance.threads` must be an `Integer` excluding
`Bool` with `1 ≤ threads ≤ typemax(Int64)`. An oversized `BigInt` or unsigned
value produces a validation problem rather than an exception, and the writer
refuses it before TOML output. The value `capture_provenance` records remains
valid by construction.

*Explicit `Float64` precision semantics.* Any statement that conversion to TOML
loses nothing is **withdrawn**. Schema version 1 stores scientific `Real` payload
values in the `Float64` numerical domain; `Rational`, `BigFloat`, and other
`Real` inputs **may be rounded** when converted, and this is intentional, because
one numerical domain is what makes records comparable and round trips exact. A
caller needing more precision must not pretend schema version 1 preserves it. The
existing decision to accept finite `Rational` and `BigFloat` values through
`Float64` conversion is unchanged, and values converting to `NaN` or `Inf` remain
refused.

*Mandatory Git provenance tests, and reconciled documentation.* The
provenance-capture testset has **no skip path and no warning-only branch**: Git
is required by `capture_provenance`, by this repository, by continuous
integration, and by the Gate 3 contract, so an absent executable fails the suite
explicitly. Temporary repositories continue to use `git config --local` only, no
global configuration is modified, and no network operation is performed.
Alongside this, [methods/error-analysis.md](methods/error-analysis.md) no longer
states that G3-D.9 is unimplemented, and
[methods/reproducibility.md](methods/reproducibility.md) now records the
timestamp policy plainly — **leap second `60` is rejected**, **year `0000` is
accepted** — and the payload policy that **empty arrays are permitted**.

### The Windows reference-alias correction

The correction below arises from the independent **Gate 3C-A.1** audit of the
Gate 3C-C.1 corrections and is applied under **Gate 3C-C.2**. It continues the
`G3-CORR` sequence and settles a question of infrastructure. It alters nothing in
the frozen numerical layer, and it alters no earlier decision: G3-D.1 to G3-D.12,
G3-CORR.1 to G3-CORR.6, and the narrowed G3-DEF.1 stand exactly as recorded
above, in identity and in substance. The forward pointer added to G3-CORR.5
records that its case-folding rule was necessary but not sufficient; it does not
change what G3-CORR.5 decided.

**G3-CORR.7 — Reference-tree detection removes trailing ASCII dots and spaces
for comparison, and for comparison only.** *Ratified 2026-08-04.*
**Gate 3C-A.1 demonstrated a bypass on Windows.** The intermediate path component
`case-studies.` resolves physically to the canonical `case-studies` directory,
because Windows strips trailing dots and spaces from a path component. The
case-folding detector of G3-CORR.5 compared the component as written, did not
recognise it, and therefore treated the destination as an unrestricted
development path. A smoke reference record was written through such an alias and
landed inside the canonical committed-reference tree.

The correction is confined to detection. Each component of the destination, after
the existing `/` and `\` separator normalisation, has trailing ASCII full stops
`U+002E` and ASCII spaces `U+0020` **repeatedly removed to form an auxiliary
comparison key**, and that key is then compared with `case-studies` under the
existing case-insensitive rule. The last matching component continues to be
selected.

**The auxiliary key is never substituted for the component.** The original
spelling is carried unchanged into the logical path, so the strict validator —
unchanged, and still requiring exactly
`case-studies/<case>/reference/<result>.toml` — refuses every noncanonical
spelling. `case-studies.`, `CASE-STUDIES...`, `case-studies   `, and
`Case-Studies. .` are therefore detected and then rejected, for **both the
`smoke` and the `production` preset**: a production record cannot be refused by
the smoke prohibition, so its refusal establishes that the path rule alone is
doing the work. No destination is created, no parent directory is created, no
existing canonical summary is altered, and no temporary residue remains.

The removal is deliberately narrow. Only those two ASCII characters, only at the
end of a component, and only for comparison. A leading dot, an internal dot or
space, a tab, a newline, a non-breaking space `U+00A0`, and the Unicode full
stops `U+3002`, `U+FF0E`, and `U+2024` all survive, so `.case-studies` and
`case-studiesx.` are not the reference tree. Percent-encoded text stays literal
and is never decoded. **No general Windows path canonicalisation is performed**:
the rule is lexical, consults no filesystem, expands no short name, resolves no
link, and applies no Unicode normalisation.

Regression coverage spans repository-relative, absolute, Windows-separator, and
mixed-separator paths, for `smoke` and `production` alike, together with lexical
tests of the alias key and of the detector that are meaningful on every platform.
On Windows a live probe additionally establishes the physical alias and asserts
that the writer refuses it and that the canonical reference directory stays
empty; where a host does not expose the alias the probe records that fact rather
than passing silently, and the lexical tests remain the portable contract. The
canonical contracts are unchanged and retested: canonical lowercase `production`
still succeeds, canonical lowercase `smoke` still fails, a development record
outside `case-studies/` still takes `smoke`, and every destination must still end
in a lowercase `.toml`.

**Windows 8.3 short-name aliases remain deferred**, exactly as G3-CORR.5 recorded
them, and are not broadened here. **No claim is made that every possible Windows
filesystem alias is eliminated**; what is established is that the case-folded,
trailing-dot, and trailing-space forms are detected and refused.

The correction introduces **no new architectural identity and no new schema
version**: schema version 1, the provenance fields, the parameter and values
semantics, the RFC 3339 timestamp semantics, clean-tree provenance, the
`Float64` payload domain, atomic replacement, strict canonical source-path
validation, the mandatory lowercase `.toml` destination, control-character
rejection, verifier discovery, the zero-export policy, the dependency set,
`Project.toml`, `Manifest.toml`, and continuous integration are all untouched.
**No scientific case study is implemented.** **Gate 3 remains open**, pending a
focused independent re-audit of this correction. **Nothing has been staged,
committed, or pushed.**

### Deferred decisions

**G3-DEF.1 (narrowed) — Correlated-sample methods deferred to their first
consumer.**
Deferred: adaptive summation windows, automatic truncation criteria, blocking,
blocking-plateau selection, and bootstrap confidence intervals for the nonlinear
estimators of
[methods/error-analysis.md](methods/error-analysis.md). Each embeds a selection
rule whose failure modes are only visible against real correlated data. They are
implemented at the first case study that produces such data — CS-07, CS-09, or
CS-10 — and not before. The deferral is narrowed in the sense that the
explicit-window estimator it previously also covered has now been implemented
under G3-CORR.1.

### Implementation status

- **Gate 3B-I.1 is implemented in the current working-tree candidate**, and has
  not been staged, committed, or published. It is **not closed**: it has been
  audited under Gate 3C-R and carries the bounded corrections of Gate 3B-C.1,
  which apply G3-CORR.2 and G3-CORR.3, and it awaits owner acceptance.
- **Gate 3B-I.2 is implemented in the current working-tree candidate**, and has
  not been staged, committed, or published. It implements G3-D.9 and nothing
  else, and it left the accepted numerical layer byte-identical.
- **Gate 3C-C.1 is implemented in the current unstaged candidate**, and has not
  been staged, committed, or published. It applies G3-CORR.4, G3-CORR.5, and
  G3-CORR.6 to five files — [../src/reproducibility.jl](../src/reproducibility.jl),
  [../test/test_reproducibility.jl](../test/test_reproducibility.jl), this
  document, [methods/reproducibility.md](methods/reproducibility.md), and
  [methods/error-analysis.md](methods/error-analysis.md) — and left every other
  file, including the frozen numerical layer, `Project.toml`, and
  `Manifest.toml`, byte-identical.
- **Gate 3C-C.2 is implemented in the current unstaged candidate**, and has not
  been staged, committed, or published. It applies **G3-CORR.7** alone, to four
  files — [../src/reproducibility.jl](../src/reproducibility.jl),
  [../test/test_reproducibility.jl](../test/test_reproducibility.jl), this
  document, and [methods/reproducibility.md](methods/reproducibility.md) — and
  left every other file, including the frozen numerical layer, `Project.toml`,
  and `Manifest.toml`, byte-identical.
- **A focused independent post-correction audit remains required.** Gate 3C-C.1
  and Gate 3C-C.2 are corrections applied under the owner's ratification, not
  acceptances of themselves, and Gate 3C-C.2 has not been independently
  re-audited.
- **Gate 3 remains open.**
- **No case study has been implemented.** No case directory, driver, figure,
  dataset, result, or reference summary exists, and nothing has been staged,
  committed, or pushed.

The entries above were true when they were recorded and are retained as
historical record. The two entries below supersede them wherever they differ,
under **G3-CORR.8**: specifically, they supersede the statement that Gate 3
remains open, the statement that a focused independent post-correction audit
remains required, and the statement that Gate 3B-I.1 awaits owner acceptance.
They likewise supersede the closing paragraph of G3-CORR.7 and the third bullet
of *What Gate 3B-I.2 does not establish* below, both of which record Gate 3 as
open. Technical state and publication state are stated separately, because
closing a gate is not publishing its candidate.

- **Technical state: Gate 3 is owner-accepted and closed.** The stages of the
  G3-D.11 sequence carried out so far are Gate 3B-I.1, Gate 3B-I.2, Gate 3C-R,
  Gate 3C-C.1, Gate 3C-A.1, Gate 3C-C.2, and Gate 3C-A.2. The focused
  independent re-audit of G3-CORR.7 was performed as **Gate 3C-A.2**, which
  returned a ready-for-acceptance verdict, and the owner gave final acceptance
  after it on **2026-08-04**. Gate 3 is therefore technically accepted and
  closed.
- **Publication state: nothing has been published.** The 23-path working-tree
  candidate is **unstaged**, **uncommitted**, and **unpushed**, and **no remote
  continuous-integration run has tested it**. Staging still requires a renewed
  exact pre-staging audit, or a focused confirmation covering the correction
  recorded in G3-CORR.8; commit, push, and remote continuous integration remain
  pending and separately authorised. No case study, reference summary, result,
  figure, or dataset exists.

#### What Gate 3B-I.2 built

- **Reference-summary schema version 1**, in
  [../src/reproducibility.jl](../src/reproducibility.jl): one version integer and
  the three tables `provenance`, `parameters`, and `values`, with unknown
  top-level keys refused. The schema is versioned so that a later change to the
  required fields is a visible migration rather than a silent divergence between
  old files and new ones. The result identifier is the filename and is not
  repeated inside the payload.
- **Clean-tree provenance capture.** `capture_provenance` refuses a dirty working
  tree — including untracked files that are not ignored — rather than recording a
  dirty-state flag, so the full forty-character Git commit is by itself the
  environment identity. No manifest hash, project hash, package path, or absolute
  local path is recorded, and the timestamp is canonical RFC 3339 UTC. The Julia
  version, thread count, and operating system are recorded as machine context and
  carry no scientific contract.
- **An atomic writer.** `write_reference_summary` validates the complete
  prospective record before writing anything, then writes to a temporary sibling
  and moves it onto the target in one filesystem operation, leaving no partial
  target and no residue after either outcome. Output is sorted, UTF-8, LF, with
  no byte-order mark and exactly one terminal newline, so identical input yields
  identical bytes. The replacement step as first built retained a non-atomic
  fallback; **G3-CORR.4 removed it**, and that correction governs.
- **Path-aware validation.** `validate_reference_summary` is pure: it returns
  problems rather than raising, writes nothing, inspects no repository, and reads
  no environment variable. Given a source path it additionally enforces the
  canonical location of G2-D.4 and prohibits committing a `smoke` record. The
  case-folding, destination-extension, control-character, thread-bound, and
  precision rules of **G3-CORR.5 and G3-CORR.6** were added afterwards and
  likewise govern, as does **G3-CORR.7**, which extends reference-tree detection
  to the Windows trailing-dot and trailing-space aliases that case folding alone
  did not close.
- **The verification script** is now a thin caller of that validator, reporting
  every problem of every discovered file rather than stopping at the first.

The three functions are unexported, consistent with G3-D.3, and no custom type,
submodule, mutable global state, or new dependency was introduced. `Dates` and
`TOML`, promoted under G3-D.1, are consumed here for the first time.

#### What Gate 3B-I.2 does not establish

- **No case study exists.** Implementing the reference-summary machinery is not
  the same as having a result to record with it: no case directory, driver,
  figure, dataset, or reference summary was created, and none is authorised.
- **No numerical comparison is performed.** Validation establishes that a record
  is well formed, complete, and in the right place, not that its numbers are
  correct or were ever reproduced. Tolerance-based comparison arrives with the
  first case study.
- **Gate 3 remains open.** Under G3-D.11 the independent audit **Gate 3C-R** has
  since been performed and covered the reproducibility layer; it found the three
  bounded faults corrected above under **Gate 3C-C.1**. The focused re-audit of
  those corrections, **Gate 3C-A.1**, has since been performed in turn and found
  one further blocking fault, the Windows trailing-dot reference alias, corrected
  above under **Gate 3C-C.2** as **G3-CORR.7**. The sequence continues with a
  focused independent re-audit of that correction, and then Gate 3D-C and
  Gate 4A-R.
- **Nothing has been staged, committed, or pushed.** The candidate exists only in
  the working tree, and every publication operation remains the owner's.

### Historical status confirmations

These entries record what has since been observed about a decision already taken.
They confirm status and settle nothing new.

**G2-D.5 — confirmed by remote continuous integration.** The mechanism G2-D.5
described was provisional when it was recorded, because it had not been observed
to work on a real runner: Julia 1.10 is not installed on the author's machine and
the gate forbade installing it, so local verification was impossible. It has
since been exercised remotely, and both jobs succeeded — the canonical job
instantiating the committed manifest, and the LTS job deleting that manifest
inside its own ephemeral checkout and resolving afresh from `Project.toml`. The
committed manifest was not modified. The provisional Gate 2 entry stands as
written; this note records only that its mechanism now has the runner evidence it
lacked. The deferral it provisionally resolved, G1-DEF.1, is unaffected in
substance.

### The Gate 3 stage-status correction

The correction below arises from the exact pre-staging audit **Gate 3D-S.1** and
is applied under **Gate 3D-S.1-CORR.1**. It continues the `G3-CORR` sequence,
but unlike every correction before it, it settles a question of documentation
currency rather than one of scientific method or of infrastructure. It alters
nothing in the frozen numerical layer and nothing in the reproducibility layer,
and it alters no earlier decision: G3-D.1 to G3-D.12, G3-CORR.1 to G3-CORR.7,
and the narrowed G3-DEF.1 stand exactly as recorded above, in identity and in
substance.

**G3-CORR.8 — Gate 3 stage-status reconciliation.** *Ratified 2026-08-04.*
**Gate 3D-S.1 found the introduction to the Gate 3 section materially out of
date.** It still stated that Gate 3 was divided into the implementation sequence
recorded in G3-D.11 and that only its first stage had been carried out, although
the same working-tree candidate the audit examined already recorded Gate 3B-I.1,
Gate 3B-I.2, Gate 3C-R, Gate 3C-C.1, Gate 3C-A.1, Gate 3C-C.2, and Gate 3C-A.2.
A reader taking that introduction at its word would have understood the
candidate to be several stages younger than it is.

The correction removes the false fixed-count clause and puts nothing of the same
kind in its place. No replacement stage count is written into the introduction,
because a count fixed in a sentence that is never revisited is exactly what fell
out of date. The introduction now points instead to the *Implementation status*
subsection, which is the durable authority on which stages have been carried out
and which is extended as the sequence proceeds.

**This is a documentation-currency correction only.** It creates and alters no
scientific, numerical, reproducibility, schema, API, dependency, or
architectural decision, and it changes no prior decision identity: every entry
from G3-D.1 through G3-CORR.7, and the narrowed G3-DEF.1, keeps the identity and
the substance it already had. Historical entries that were true when they were
recorded are retained unaltered; they are superseded by the current-status
entries in *Implementation status*, never rewritten.

**Gate 3 is technically accepted and closed.** The focused independent re-audit
of G3-CORR.7 was performed as Gate 3C-A.2, and the owner gave Gate 3 final
acceptance after it on **2026-08-04**.

**Nothing has been published.** The 23-path working-tree candidate remains
**unstaged** and **uncommitted**. Staging still requires a renewed exact
pre-staging audit, or a focused confirmation covering this correction; commit,
push, and remote continuous integration remain pending and separately
authorised, and **no remote continuous-integration run has tested this
candidate**. **No case study, reference summary, result, figure, or dataset
exists.**
