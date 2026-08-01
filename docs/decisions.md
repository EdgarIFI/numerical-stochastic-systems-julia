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
