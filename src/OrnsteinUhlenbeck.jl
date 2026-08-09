"""
    StochasticCaseStudies.OrnsteinUhlenbeck

CS-06 — *Ornstein–Uhlenbeck Dynamics: Mean Reversion and Numerical Convergence
Orders*, the pilot case study of this repository.

The submodule holds the closed-form quantities of the process, the exact and
Euler–Maruyama samplers, the four experiments the case runs, and the assembly of
the values a reference summary would record. It is organised as three files in
dependency order — the analytical model, the sampling algorithms built on it, and
the experiments built on those — following the flat include-based pattern of the
shared layer under G3-D.2.

**The submodule exports nothing**, as G3-D.3 requires through this pilot. Every
name is reached by an explicit import or by qualification:

```julia
using StochasticCaseStudies.OrnsteinUhlenbeck: run_case_study, CASE_SLUG
```

Shared infrastructure is likewise imported by name rather than brought in
wholesale, so that the dependence of this case on the frozen Gate 3 core is
visible in one place and is exactly as long as the list below.

Nothing here draws, renders, or writes anything. CairoMakie is not loaded by this
submodule and appears nowhere under `src/`: rendering belongs to the driver's
figure branch, and writing a reference summary to its production branch.

See `case-studies/06-ornstein-uhlenbeck/README.md` for the scientific account and
`docs/decisions.md` for the governing decisions.
"""
module OrnsteinUhlenbeck

using Random: AbstractRNG, Xoshiro
using Statistics: var
using StatsBase: autocor

# The shared Gate 3 layer, imported by name. `autocor` above is taken from
# StatsBase directly rather than through the shared correlated summary: this case
# reports and compares the autocorrelation series itself, which the shared summary
# does not return.
using ..StochasticCaseStudies:
    derive_seeds,
    fit_loglog,
    integrated_autocorrelation_time,
    nsigma,
    preset_parameters,
    relative_error,
    rmse,
    summarize_correlated,
    summarize_independent

# Dependency order: the model defines the closed forms and the domain guards, the
# simulation layer samples from them, and the experiments combine the two with the
# shared statistics.
include("ornstein_uhlenbeck/model.jl")
include("ornstein_uhlenbeck/simulation.jl")
include("ornstein_uhlenbeck/experiments.jl")

end # module OrnsteinUhlenbeck
