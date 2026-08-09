# Deterministic derivation of substream seeds.
#
# Each experiment declares one master seed. Every replicate, parameter point, or
# independent chain then receives its own generator, seeded from a value drawn
# from the master stream, so that the whole experiment is a pure function of the
# single declared seed. See docs/methods/rng-and-seeding.md.
#
# The seeds are drawn one at a time rather than through the array form of `rand`.
# This is not stylistic. Julia does not specify that the array form of `rand`
# agrees with successive scalar draws, and for `Xoshiro` it does not: on Julia
# 1.12.6, `rand(Xoshiro(2026), UInt64, 8)` does not reproduce eight successive
# scalar `rand(rng, UInt64)` draws, and therefore does not preserve the prefix
# contract documented below.
#
# That is version-specific engineering evidence, measured on the canonical
# environment. It is not a claim about a threshold at which the array form changes
# behaviour, nor about the internal mechanism of Julia's generator: neither is
# documented, and neither is asserted here. Drawing scalars makes the prefix
# property hold for every generator, which is what makes a run reproducible when
# the number of substreams is later increased. No test asserts a value of either
# stream.

"""
    derive_seeds(master::AbstractRNG, n::Integer) -> Vector{UInt64}

Draw `n` substream seeds from the master stream `master`.

Each returned value is intended to seed the generator of one replicate, one
parameter point, or one independent chain. The master stream is advanced by
exactly `n` scalar draws, so that

    derive_seeds(master, n)[1:k] == derive_seeds(copy_of_master, k)

for every `0 ≤ k ≤ n`: enlarging an experiment extends its set of substreams
rather than replacing it. `n = 0` returns an empty vector and leaves the master
stream untouched.

No claim is made that the derived seeds are distinct. They are draws from a
64-bit stream, so a collision has probability of order `n²/2^65`; that is
negligible at any scale this repository runs, but it is a probabilistic statement
rather than a guarantee.

A negative `n`, or an `n` above `typemax(Int)`, throws an `ArgumentError`; the
domain is checked before the conversion to `Int`, so an unrepresentable count is
rejected by name rather than raising an `InexactError` or reaching the allocation.
"""
function derive_seeds(master::AbstractRNG, n::Integer)
    count = _checked_int(n, "the number of substreams", 0)
    seeds = Vector{UInt64}(undef, count)
    for i in eachindex(seeds)
        seeds[i] = rand(master, UInt64)
    end
    return seeds
end

"""
    derive_seeds(master_seed::Integer, n::Integer) -> Vector{UInt64}

Construct the canonical master generator `Xoshiro(master_seed)` and draw `n`
substream seeds from it.

This is the form a driver uses: an experiment declares one plain integer master
seed, recorded in its *Parameters* and *Reproduction* sections, and every
stochastic quantity in the experiment derives from it. The canonical master seed
is restricted to `0 ≤ master_seed ≤ typemax(Int64)`, so that the recorded value
is an ordinary nonnegative integer whatever integer type a driver happens to use;
it is converted to `UInt64` before seeding, so that seeds of equal value agree
whatever their type.

`Xoshiro` is the visible canonical generator, not a stability promise. Julia does
not guarantee that a given seed yields the same stream across minor releases, so
exact reproduction is claimed only for the canonical Julia series together with
the committed manifest; see docs/methods/reproducibility.md. Tests must therefore
never assert particular derived values.

A seed outside the admissible range, or an `n` outside `0 ≤ n ≤ typemax(Int)`,
throws an `ArgumentError`.
"""
function derive_seeds(master_seed::Integer, n::Integer)
    0 <= master_seed <= typemax(Int64) || throw(
        ArgumentError(
            "the master seed must satisfy 0 ≤ seed ≤ $(typemax(Int64)), got $master_seed",
        ),
    )
    return derive_seeds(Xoshiro(UInt64(master_seed)), n)
end
