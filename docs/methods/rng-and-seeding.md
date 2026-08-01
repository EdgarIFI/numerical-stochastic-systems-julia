# Randomness and seeding

How random number generation is controlled. The policy exists so that every
stochastic result in this repository can be traced to a declared seed, and so
that no result depends on hidden global state.

Sections marked **planned** describe requirements that later gates must satisfy;
they are not yet implemented, because no case study has been implemented.

## Generators are passed, never assumed

Every function that consumes randomness takes an explicit generator as an
argument:

```julia
function sample_something(rng::AbstractRNG, n::Integer)
    # ...
end
```

The argument comes first, following Julia's own convention for `rand` and its
relatives. This makes the dependence on randomness visible in the signature,
allows a caller to supply an independent stream per replicate, and keeps
functions testable without touching global state.

## No global seeding in package code

**Code in `src/` never calls `Random.seed!()`.** Seeding the global generator is
an action a caller may take in its own driver; it is not something a library may
do on a caller's behalf, because it silently changes the behaviour of every other
consumer of randomness in the session.

Drivers construct the generators they need explicitly and pass them down.

## One master seed per experiment

Each experiment declares **one master seed**, recorded in the case study's
*Parameters* and *Reproduction* sections and in its reference summary. Everything
stochastic in that experiment derives from it.

**Planned.** Substreams are derived deterministically: a master `Xoshiro` stream
is constructed from the master seed and used to draw `UInt64` seeds, each of
which then seeds the generator for one replicate, one parameter point, or one
independent chain.

Deriving substream seeds this way, rather than by adding an index to the master
seed, keeps the substreams independent in practice and keeps the whole derivation
a pure function of the single declared seed. The scheme is implemented in the
shared package at the gate that requires it, so that every case uses the same
derivation.

## Threading must not change results

**Planned.** Where independent replicates are computed in parallel, each
replicate receives its own generator, derived as above from its index. The result
must therefore be identical whether the replicates run on one thread or on many.

Thread count is a performance parameter and never a scientific one. Any scheme in
which threads share a generator, or in which results depend on scheduling order,
is excluded by this requirement.

## Tests never assert default-RNG values

**No test asserts an exact value produced by Julia's default random number
generator.** Julia may change the algorithm or the stream of `rand` between minor
releases; a test that pinned such values would encode a promise the language does
not make, and would fail on a supported version for no scientific reason.

Tests of stochastic code instead assert:

- exact properties that hold for any stream — invariants, conservation laws,
  symmetries, the support and shape of an output;
- statistical properties, at the thresholds set in
  [error-analysis.md](error-analysis.md);
- exact agreement between two runs given the *same* explicitly constructed
  generator, which tests determinism without pinning any particular value.

## StableRNGs

`StableRNGs` provides a generator whose stream is guaranteed stable across Julia
versions. It is a **test dependency**, declared in the `test` target rather than
among the package's runtime dependencies.

It is used **only where a frozen stream is genuinely required** — because a
procedure must be bitwise reproducible across versions, or because a scientific
comparison depends on a fixed realisation. It is not a general substitute for
Julia's generators: reaching for a frozen stream to make a flaky statistical test
pass would hide the real problem, which is a test whose threshold is too tight or
whose sample is too small.

The scaffold test suite uses it only to confirm that the facility is available
and deterministic.

## Related documents

- [reproducibility.md](reproducibility.md) — what reproduction promises.
- [error-analysis.md](error-analysis.md) — statistical thresholds.
- [../decisions.md](../decisions.md) — decisions G1-D.15 and G1-D.16.
