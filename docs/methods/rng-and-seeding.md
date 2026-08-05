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

Substreams are derived deterministically, by `derive_seeds` in the shared
package. A master stream is used to draw `UInt64` seeds, each of which then seeds
the generator for one replicate, one parameter point, or one independent chain.
Deriving substream seeds this way, rather than by adding an index to the master
seed, keeps the substreams independent in practice and keeps the whole derivation
a pure function of the single declared seed.

There are two methods, and both return a `Vector{UInt64}`:

```julia
using StochasticCaseStudies: derive_seeds

derive_seeds(master_seed::Integer, n::Integer)   # what a driver calls
derive_seeds(master::AbstractRNG, n::Integer)    # when a stream is already held
```

**The master seed a driver declares is a plain integer.** It is restricted to
`0 ≤ master_seed ≤ typemax(Int64)`, so that the value recorded in a README and in
a reference summary is an ordinary nonnegative integer, and it is converted to
`UInt64` before seeding, so that seeds of equal value agree whatever integer type
a driver happens to use. The integer method constructs `Xoshiro(master_seed)` and
delegates to the generic one, which is the method a case uses when it already
holds a stream and wants to divide it further.

`Xoshiro` is the **visible canonical generator**: the derivation names it rather
than reaching for whatever generator happens to be ambient, so that a reader can
see which stream a result came from. Naming it is not a stability promise — see
the caveat below.

### The prefix property

Seeds are drawn one at a time from the master stream, so that for every
`0 ≤ k ≤ n`

```julia
derive_seeds(seed, n)[1:k] == derive_seeds(seed, k)
```

Enlarging an experiment therefore **extends** its set of substreams rather than
replacing it: raising a replicate count from 32 to 64 leaves the first 32
replicates bitwise unchanged, so the longer run can be compared against the
shorter one.

This is why the scalar draw is used rather than the array form of `rand`. Julia
does not specify that the array form agrees with successive scalar draws, and for
`Xoshiro` it does not. The measured evidence is this: on Julia 1.12.6,
`rand(Xoshiro(2026), UInt64, 8)` does not reproduce eight successive scalar
`rand(rng, UInt64)` draws, and therefore does not preserve the prefix contract
above.

That observation is **version-specific engineering evidence**, obtained on the
canonical environment. It is not a claim about a threshold at which the array
form changes behaviour, and it is not a claim about the internal mechanism of
Julia's generator; neither is documented, and neither is asserted here. What
follows from it is only the implementation choice: the required prefix contract
is implemented with scalar draws, which makes the property hold for any
generator, at a cost that is irrelevant because the number of substreams is
small.

Consistently with the caveat below, **no test asserts a value of either stream.**
The evidence above is stated as the reason for a design choice, not encoded as an
expectation the test suite would have to defend across Julia releases.

No claim is made that derived seeds are distinct. They are draws from a 64-bit
stream, so a collision has probability of order `n²/2⁶⁵` — negligible at any
scale this repository runs, but a probabilistic statement rather than a
guarantee.

### The exact-stream caveat

Julia does not guarantee that a given seed yields the same `Xoshiro` stream
across minor releases. Exact reproduction is therefore claimed only for the
canonical Julia series together with the committed manifest, as ratified in
G1-D.16; on other supported versions, reproduction is statistical. Consequently
**no test asserts a particular derived seed value**. What the tests assert is the
structure on which reproducibility actually rests: the output type, determinism
given the same seed, the prefix property, and that the master stream advances by
exactly the number of seeds drawn.

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

The test suite uses it in two places, neither of which freezes a scientific
outcome: to confirm that the facility is available and deterministic, and to
exercise the generic `derive_seeds` method against a generator that is not
`Xoshiro`, which checks that the derivation depends on nothing beyond the
`AbstractRNG` interface.

## Related documents

- [reproducibility.md](reproducibility.md) — what reproduction promises.
- [error-analysis.md](error-analysis.md) — statistical thresholds.
- [../decisions.md](../decisions.md) — decisions G1-D.15, G1-D.16 and G3-D.5, and
  the scientific correction G3-CORR.2.
