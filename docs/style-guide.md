# Style guide

The conventions that govern prose, mathematics, and code presentation across the
repository. Architectural decisions live in [decisions.md](decisions.md); symbol
collisions in [notation.md](notation.md).

## Language

Prose is written in **British scientific English**, at a level corresponding to
CEFR C1 or IELTS Academic Band 7 and above: precise, impersonal, and readable by
someone who knows the mathematics but not this repository.

The -ise family of spellings is used throughout:

| Preferred | Not used |
| --- | --- |
| modelling | modeling |
| normalisation | normalization |
| visualisation | visualization |
| optimisation | optimization |
| analyse | analyze |
| behaviour | behavior |

**Code is exempt.** Julia identifiers follow the conventions of the Julia
ecosystem even where these differ from the surrounding prose, because an
identifier must match the name the ecosystem already uses:

```julia
normalize(v)   # the ecosystem spelling, in code
analyze(data)  # likewise
```

Prose describing that code still says *normalisation* and *analyse*. The
inconsistency is deliberate and is preferable to inventing identifiers that no
Julia programmer would guess.

## Claims

- No unsupported superlatives, and no vague claims. *Fast*, *efficient*,
  *excellent agreement*, and *very accurate* mean nothing without a number.
- **Every quantitative claim carries evidence and an uncertainty.** A reported
  value appears with a confidence interval, or with the standard error from which
  one can be formed, together with the parameters and seed that produced it.
- Where a standard theorem is invoked, its hypotheses are stated. A result that
  holds only under stronger assumptions than the reader may expect is flagged as
  such.
- A limitation is stated plainly in the case study that has it, not omitted.

## Mathematics on GitHub

GitHub renders LaTeX in Markdown. Inline mathematics is delimited by a dollar
sign and a backtick; display mathematics uses a fenced block tagged `math`. The
backtick form is preferred for inline mathematics because it survives characters
that would otherwise be interpreted as Markdown.

Source:

~~~markdown
The variance of the summands is $`\sigma^2 = \operatorname{Var}(X)`$.

```math
\lim_{n \to \infty} \Pr\left( \frac{S_n - n\mu}{\sigma \sqrt{n}} \le x \right) = \Phi(x)
```
~~~

Rendered — this pair is deliberately kept here as a smoke test of GitHub's
mathematics rendering:

The variance of the summands is $`\sigma^2 = \operatorname{Var}(X)`$.

```math
\lim_{n \to \infty} \Pr\left( \frac{S_n - n\mu}{\sigma \sqrt{n}} \le x \right) = \Phi(x)
```

## Names and dashes

- An **en dash** joins the names of two different people:
  Ornstein–Uhlenbeck, Berry–Esseen, Kolmogorov–Smirnov, Metropolis–Hastings.
- A **hyphen** is used inside one person's double-barrelled surname:
  **Lennard-Jones**. Sir John Lennard-Jones was one person, so *Lennard–Jones*
  with an en dash would be wrong.
- An em dash — used sparingly — sets off a parenthetical clause.

## Links

- All internal links are **relative**: `[notation.md](notation.md)`,
  `[../src/StochasticCaseStudies.jl](../src/StochasticCaseStudies.jl)`.
- Link to a **file or a named function**, never to a line number. Line numbers
  move; names do not. Write "the `verify_reproducibility.jl` script" rather than
  a permalink to a line.
- Do not link to a directory that does not yet exist. A planned case study is
  named in plain text until its directory is created.

## Julia code

- `# %%` is the canonical cell delimiter in drivers. It is what the Julia
  extension for VS Code recognises, and it lets a driver be executed one step at
  a time in a persistent REPL.
- Drivers stay thin and keep intermediate variables visible; there is no giant
  `main()`. Numerical work belongs in package functions, where it is compiled.
- Functions that consume randomness take an explicit `rng::AbstractRNG` argument;
  see [methods/rng-and-seeding.md](methods/rng-and-seeding.md).
- Formatting is enforced by JuliaFormatter through
  [../.JuliaFormatter.toml](../.JuliaFormatter.toml). The configuration preserves
  authored line breaks, so an expression may be laid out to mirror the
  mathematics it implements.

## The case-study README template

Every case study's README follows the same eleven sections, in this order. The
order takes the reader from the question to the evidence, and makes any two cases
directly comparable.

1. **Overview and question** — what is being asked, and why it is worth asking.
2. **Mathematical formulation** — the model, its assumptions, and its notation.
3. **Analytical results** — what can be established in closed form, with the
   hypotheses each result requires.
4. **Numerical method** — the algorithm, its rationale, and its expected order of
   accuracy.
5. **Implementation notes** — the choices a reader of the source would otherwise
   have to reconstruct.
6. **Parameters** — every parameter, its value, and its units or scaling.
7. **Results** — the figures and the reported values.
8. **Validation** — the comparison against the analytical or independent
   reference, with uncertainties.
9. **Limitations** — what the study does not establish.
10. **Reproduction** — the exact commands, the preset, the seed, and the expected
    runtime.
11. **References** — the sources actually used.
