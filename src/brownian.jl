# Brownian increments and their coarsening.
#
# Two operations are shared by every case that integrates a stochastic
# differential equation: drawing the increments of a Wiener process on a uniform
# grid, and reducing a fine set of increments to a coarser one.
#
# Coarsening exists so that a convergence study can drive several step sizes with
# *the same* Brownian path. Comparing schemes on independently drawn paths
# confounds the discretisation error with the sampling error and destroys the
# strong order of convergence one is trying to measure; summing non-overlapping
# blocks of fine increments gives exactly the increments the same path makes on
# the coarse grid.
#
# There is no `BrownianPath` type. An increment vector and its step size carry
# all the information a caller needs, and a wrapper would only obscure that.

"""
    brownian_increments(rng::AbstractRNG, n::Integer, dt::Real) -> Vector{Float64}

Draw `n` independent increments of a standard Wiener process over steps of length
`dt`, that is `n` independent draws from `Normal(0, dt)` — mean zero and variance
`dt`, hence standard deviation `√dt`.

Randomness is taken from `rng` alone; no ambient or global generator is consulted.
The returned vector is the only allocation.

The computation is performed in the **`Float64` numerical domain**: `dt` is
converted to `Float64` and the contract is applied to the converted value, so a
`dt` that is mathematically finite but whose conversion is not — a `BigInt` of
order `10^400`, say — is rejected rather than admitted as an infinite step size.
The returned increments are checked to be finite, so no accepted input yields a
`NaN` or an `Inf`.

`1 ≤ n ≤ typemax(Int)` and a `dt` finite and strictly positive in `Float64` are
required; anything else throws an `ArgumentError`.
"""
function brownian_increments(rng::AbstractRNG, n::Integer, dt::Real)
    count = _checked_int(n, "the number of increments", 1)
    step = Float64(dt)
    (isfinite(step) && step > 0) || throw(
        ArgumentError(
            "the step size must be finite and > 0 in the Float64 numerical " *
            "domain, got dt = $dt",
        ),
    )
    scale = sqrt(step)
    dw = randn(rng, Float64, count)
    for i in eachindex(dw)
        scaled = dw[i] * scale
        isfinite(scaled) || throw(
            ArgumentError(
                "the increments must be finite; element $i overflows the Float64 " *
                "numerical domain at dt = $dt",
            ),
        )
        dw[i] = scaled
    end
    return dw
end

"""
    coarsen_increments(dw::AbstractVector{<:Real}, factor::Integer) -> Vector{Float64}

Sum non-overlapping consecutive blocks of `factor` increments, returning the
increments of the *same* Brownian path on a grid `factor` times coarser.

Element `j` of the result is the sum of elements `factor * (j - 1) + 1` through
`factor * j` of `dw`. Because the increments of a Wiener process over disjoint
intervals are independent and additive, the result is distributed exactly as
`brownian_increments` would produce at step size `factor * dt`, while remaining
the realisation of the very path `dw` describes. The total displacement is
preserved up to floating-point summation error.

The summation is performed in the **`Float64` numerical domain**. Each element is
converted before it is added, and the contract is applied to the converted value:
an element that is mathematically finite but whose conversion is not — a `BigInt`
of order `10^400`, say — is rejected rather than admitted as an infinite
increment. Each block sum is checked in turn, so a pair such as
`[1.7e308, 1.7e308]` is rejected rather than coarsened to `Inf`.

`length(dw)` must be a positive multiple of `factor`,
`1 ≤ factor ≤ typemax(Int)`, and every element and every block sum must be finite
in `Float64`; anything else throws an `ArgumentError`. Indexing is integral
throughout: no floating-point time grid is constructed, so no grid point is ever
reached by accumulating rounding error. `factor = 1` returns a value-equivalent
copy in independent storage.
"""
function coarsen_increments(dw::AbstractVector{<:Real}, factor::Integer)
    n = length(dw)
    n >= 1 || throw(ArgumentError("the increment vector must be nonempty"))
    block = _checked_int(factor, "the coarsening factor", 1)
    rem(n, block) == 0 || throw(
        ArgumentError(
            "the number of increments must be divisible by the coarsening factor, " *
            "got length(dw) = $n and factor = $block",
        ),
    )
    offset = firstindex(dw) - 1
    coarse = Vector{Float64}(undef, div(n, block))
    for j in eachindex(coarse)
        total = 0.0
        base = (j - 1) * block
        for k in 1:block
            i = base + k
            value = Float64(dw[offset+i])
            isfinite(value) || throw(
                ArgumentError(
                    "every increment must be finite in the Float64 numerical " *
                    "domain; element $i is $(dw[offset+i])",
                ),
            )
            total += value
        end
        isfinite(total) || throw(
            ArgumentError(
                "every block sum must be finite in the Float64 numerical domain; " *
                "block $j of $block increments overflows",
            ),
        )
        coarse[j] = total
    end
    return coarse
end
