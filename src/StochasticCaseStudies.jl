"""
    StochasticCaseStudies

Shared Julia package for *Stochastic Systems in Julia*, a collection of ten
reproducible numerical case studies in probability, stochastic processes, and
computational statistical physics.

The package is organised as one shared namespace into which a semantic submodule
is added for each case study as its implementation gate begins. Shared numerical,
statistical, and reproducibility utilities are placed here so that the individual
case-study drivers remain thin and readable.

This module is deliberately minimal at the scaffold stage: no scientific API has
been ratified for implementation yet, so the package intentionally defines and
exports nothing beyond the module itself. Loading it is therefore a check of the
environment rather than of any numerical functionality.

See `case-studies/README.md` for the planned case-study taxonomy and
`docs/decisions.md` for the governing architectural decision record.
"""
module StochasticCaseStudies

# Case-study submodules and shared numerical utilities are introduced at their
# respective implementation gates. Nothing is defined here in advance, so that
# the public surface of the package never promises functionality that does not
# yet exist.

end # module StochasticCaseStudies
