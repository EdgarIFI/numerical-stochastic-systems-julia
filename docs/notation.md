# Notation

This document records only the **global collision policy**: the small number of
symbols that would otherwise mean different things in different case studies.

It is not a master symbol table, and it does not fix the notation of any
individual case. Per-case notation is settled in the case study itself, at the
gate that implements it.

## Local symbol tables

**Every case study opens with its own symbol table**, in the *Mathematical
formulation* section of its README. The table lists every symbol the case uses,
its meaning, and its units or scaling where these apply.

A symbol may be reused across cases with a different meaning, but only when it is
locally declared and locally unambiguous. The reader of one case study must never
have to consult another to learn what a symbol means.

## Reserved and disambiguated symbols

### $`\sigma`$ — reserved for probability

$`\sigma`$ denotes a standard deviation, and $`\sigma^2`$ a variance, unless it
carries an explicit subscript. Probability and statistics are the connective
tissue of this repository, so the probabilistic reading is the default and the
physical readings are the ones that must be marked.

### $`\sigma_{\mathrm{LJ}}`$ — the Lennard-Jones length scale

In CS-10 the Lennard-Jones interaction has a characteristic length that is
conventionally written $`\sigma`$. It is written $`\sigma_{\mathrm{LJ}}`$
throughout this repository, so that it can never be confused with a standard
deviation appearing in the same analysis — and CS-10 does report standard
deviations, since its observables are estimated from correlated samples.

### $`s_i`$ — Ising spins

The spins of the two-dimensional Ising model in CS-07 are written $`s_i`$, taking
values in $`\{-1, +1\}`$. They are **not** written $`\sigma_i`$, the common
textbook choice, for the same reason as above: $`\sigma`$ is reserved.

### $`T`$ — temperature, used directly in CS-07

CS-07 parametrises by temperature $`T`$ directly rather than by inverse
temperature $`\beta`$. The critical behaviour of the model is conventionally
described and tabulated in terms of $`T`$ and $`T_c`$, and using one variable
consistently avoids silent factors of $`k_B`$ in reported quantities. Where
$`\beta`$ appears in an intermediate derivation, it is defined at that point.

## Conventions that are declared, not assumed

Some quantities have more than one legitimate convention in the literature, and
differ between textbooks by a factor of the system size, the temperature, or
$`k_B`$. Such a quantity is **defined explicitly in the case study that reports
it**, with its normalisation written out, and is never treated as though one
universal convention existed.

The magnetic susceptibility of the Ising model in CS-07 is the immediate example:
its normalisation is stated in full where it is defined, so that a reported value
can be compared with an external source without ambiguity.

## Units

Each case states whether it works in physical or reduced units, and defines the
reduction it uses. Reported numerical values always carry their units, or an
explicit statement that the quantity is dimensionless.
