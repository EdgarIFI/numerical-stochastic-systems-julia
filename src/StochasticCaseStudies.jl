"""
    StochasticCaseStudies

Shared Julia package for *Stochastic Systems in Julia*, a collection of ten
reproducible numerical case studies in probability, stochastic processes, and
computational statistical physics.

The package is organised as one shared namespace into which a semantic submodule
is added for each case study as its implementation gate begins. Shared numerical,
statistical, and reproducibility utilities are placed here so that the individual
case-study drivers remain thin and readable.

**The package exports nothing, deliberately.** Every shared function is reached by
an explicit import, so that a driver names what it depends on and no identifier
enters a caller's namespace unannounced:

```julia
using StochasticCaseStudies: derive_seeds, rmse, fit_loglog
```

The shared numerical layer currently provides execution presets, deterministic
substream seeding, Brownian increments and their coarsening, summaries of
independent and of correlated samples, and log-log convergence fitting. The
shared reproducibility layer provides provenance capture, the atomic writer for
versioned numerical reference summaries, and their validator. No case study has
been implemented, so no case submodule exists yet.

See `case-studies/README.md` for the planned case-study taxonomy and
`docs/decisions.md` for the governing architectural decision record.
"""
module StochasticCaseStudies

# Standard library. `Dates` and `TOML` are consumed only by the reproducibility
# layer: the first to stamp a record in UTC, the second to write and read one.
# `TOML` is imported rather than brought in by name, so that every use of it in
# this package reads as `TOML.print`.
using Dates: DateTime, Second, TimeType, UTC, day, hour, minute, month, now, second, year
using Random: AbstractRNG, Xoshiro
using Statistics: mean, quantile, std, var
import TOML

# Scientific dependencies. Distributions extends `Statistics.quantile`, so the
# Student-t quantiles used for confidence intervals are reached through the
# generic function imported above.
using Distributions: TDist
using StatsBase: autocor, sem

"""
    _checked_int(value::Integer, name::AbstractString, lower::Integer) -> Int

Validate `lower ≤ value ≤ typemax(Int)` and return `Int(value)`.

Several shared functions accept a count, a factor, or a summation window as an
`Integer` and then allocate or index with it, which requires an `Int`. Converting
first would raise an `InexactError` for a value too large to represent — an error
naming neither the argument nor the contract it violates, and raised only after
the value has already been used. The domain is therefore checked before the
conversion, and a violation throws an `ArgumentError` naming both.

`name` is the descriptive phrase that opens the message and `lower` the inclusive
lower bound the calling function requires; the upper bound is `typemax(Int)`,
which is what the conversion itself admits. Scientific restrictions beyond the
representable range — that a window lie below the length of a series, say — are
applied by the caller after the conversion.

This helper is internal and unexported. It holds no state.
"""
function _checked_int(value::Integer, name::AbstractString, lower::Integer)
    value >= lower || throw(ArgumentError("$name must be ≥ $lower, got $value"))
    value <= typemax(Int) ||
        throw(ArgumentError("$name must be ≤ $(typemax(Int)), got $value"))
    return Int(value)
end

# The shared numerical layer, in dependency order: each file may use the
# definitions of those above it and none of those below it.
include("presets.jl")
include("randomness.jl")
include("brownian.jl")
include("statistics.jl")
include("correlated_statistics.jl")
include("error_analysis.jl")

# The shared reproducibility layer. It follows the numerical files because it
# validates the preset vocabulary they fix, and nothing numerical depends on it.
include("reproducibility.jl")

# Case-study submodules are introduced at their respective implementation gates.
# Nothing is defined here in advance, so that the surface of the package never
# promises functionality that does not yet exist.

end # module StochasticCaseStudies
