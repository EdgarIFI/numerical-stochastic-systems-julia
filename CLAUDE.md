# CLAUDE.md

Operating instructions for AI assistants working in this repository.

## Project identity

**Stochastic Systems in Julia** — ten reproducible numerical case studies in
probability, stochastic processes, and computational statistical physics. The
shared Julia package is `StochasticCaseStudies`.

The public framing is *case studies*. Never describe the repository as a homework
archive, an assignment collection, a course reconstruction, or a portfolio.

The frozen taxonomy is in [case-studies/README.md](case-studies/README.md). The
binding architectural record is [docs/decisions.md](docs/decisions.md); read it
before proposing any structural change.

## Authority and originality

- The repository itself, together with properly cited public academic or official
  software sources, is the sole implementation authority.
- All code, text, figures, and data are original work by the author unless an
  explicit third-party attribution states otherwise. Never introduce copied,
  unpublished, or externally supplied source material.
- Never add provenance disclaimers, denials, or references to private context to
  any file in the repository.

## Git authority belongs to the owner

The owner alone performs every publication operation. Assistants must never run
`git add`, `git commit`, `git push`, `git tag`, `git switch`, `git checkout`,
`git merge`, `git rebase`, `git reset`, `git clean`, or `git stash`, and must
never create branches or pull requests, modify remote or Git configuration, or
rewrite history.

Read-only inspection — `git status`, `git diff`, `git log`, `git check-ignore` —
is permitted and encouraged.

## Gates

Work proceeds in explicitly authorised gates. Implement what the current gate
authorises and nothing beyond it. Do not create empty case directories,
placeholder modules, or speculative interfaces in order to imitate the shape of
the finished repository.

Inspect before editing: read the file, and the relevant decision, before changing
anything.

Finish every gate with a complete report of files created, files modified,
commands run with their exit codes, test results, and known limitations.

## Prose

- British scientific English throughout, using -ise forms: *modelling*,
  *normalisation*, *visualisation*, *optimisation*, *analyse*.
- Julia identifiers follow ecosystem convention even where it differs from the
  prose: `normalize`, `analyze`.
- No unsupported superlatives and no vague claims. Every quantitative claim
  carries evidence and a stated uncertainty.
- Full conventions: [docs/style-guide.md](docs/style-guide.md). Symbol collisions:
  [docs/notation.md](docs/notation.md).

## Julia code

- Every function that consumes randomness takes an explicit `rng::AbstractRNG`
  argument.
- Code in `src/` never calls `Random.seed!()`.
- No test asserts exact values produced by Julia's default random number
  generator. See [docs/methods/rng-and-seeding.md](docs/methods/rng-and-seeding.md).
- Performance-critical loops live inside functions, never at top level.
- No giant `main()`. Drivers stay thin; the numerical work belongs in package
  functions.
- Drivers are divided into `# %%` cells and keep intermediate variables visible
  in the Julia VS Code REPL.
- Three execution presets — `:smoke`, `:figure`, `:production`. Committed drivers
  default to `:smoke`.

## Scientific standards

- Never state a scientific claim the repository does not support. Where an
  established result requires hypotheses, state the hypotheses.
- Every reported value carries a confidence interval. Correlated samples require
  blocking or an integrated autocorrelation-time correction.
- Statistical assertions use four standard errors; hypothesis tests use
  `alpha = 0.001`. See [docs/methods/error-analysis.md](docs/methods/error-analysis.md).

## Outputs

- Heavy generated output belongs in `results/`, which is ignored by Git.
- Figures are eventually committed as PNG and validated through the numerical
  series behind them, never by pixel comparison.
- Every public result records its parameters, seed, Julia version, package state,
  and Git commit.

## Environment

- `Manifest.toml` is committed on purpose: this repository is an application, not
  a library.
- Julia 1.10 is the supported minimum; Julia 1.12.6 is the canonical environment.
- Never add a dependency casually. The dependency set is ratified; propose an
  addition in the decision record before making it.

## Model hierarchy

- **Fable** — architecture and global audit.
- **Opus** — difficult implementation and adversarial audit.
- **Sonnet** — bounded, mechanical work.

## Reporting

Close every gate with a complete file, change, and test report. State plainly
what was not done, what remains deferred, and what could not be verified locally.
