using Random: Xoshiro
using Test

using StableRNGs
using StochasticCaseStudies: derive_seeds

# No test below asserts a particular derived value. Julia does not promise a
# stable `Xoshiro` stream across minor releases, so pinning one would encode a
# guarantee the language does not make; see docs/methods/rng-and-seeding.md. What
# is asserted is the shape of the output and the structural properties on which
# reproducibility actually rests: determinism given the same seed, the prefix
# property, and normal advancement of the master stream.

@testset "randomness" begin
    @testset "output shape and type" begin
        seeds = derive_seeds(20260802, 5)
        @test seeds isa Vector{UInt64}
        @test length(seeds) == 5

        empty_seeds = derive_seeds(20260802, 0)
        @test empty_seeds isa Vector{UInt64}
        @test isempty(empty_seeds)
        @test derive_seeds(Xoshiro(1), 0) == UInt64[]

        @test @inferred(derive_seeds(20260802, 3)) isa Vector{UInt64}
        @test @inferred(derive_seeds(Xoshiro(20260802), 3)) isa Vector{UInt64}
    end

    @testset "invalid arguments" begin
        @test_throws ArgumentError derive_seeds(20260802, -1)
        @test_throws ArgumentError derive_seeds(Xoshiro(1), -1)
        @test_throws ArgumentError derive_seeds(-1, 4)
        @test_throws ArgumentError derive_seeds(big(typemax(Int64)) + 1, 4)
        # The two endpoints of the admissible range are themselves valid.
        @test length(derive_seeds(0, 2)) == 2
        @test length(derive_seeds(typemax(Int64), 2)) == 2

        # A count above `typemax(Int)` is rejected by name, before the conversion
        # and before any allocation, so the failure is an `ArgumentError` naming
        # the argument rather than an `InexactError` naming a machine type.
        # `UInt` and `Int` share a width on every platform Julia supports, so
        # `typemax(UInt)` always exceeds `typemax(Int)`.
        @test_throws ArgumentError derive_seeds(20260802, big(typemax(Int)) + 1)
        @test_throws ArgumentError derive_seeds(Xoshiro(1), big(typemax(Int)) + 1)
        @test_throws ArgumentError derive_seeds(20260802, typemax(UInt))
        @test_throws ArgumentError derive_seeds(Xoshiro(1), typemax(UInt))
    end

    @testset "determinism" begin
        @test derive_seeds(2026, 8) == derive_seeds(2026, 8)
        # Seeds of equal value agree whatever integer type carries them.
        @test derive_seeds(Int32(2026), 4) == derive_seeds(UInt64(2026), 4)
        @test derive_seeds(2026, 4) == derive_seeds(big(2026), 4)
        # A count inside the admissible range behaves identically whatever
        # integer type carries it: the range guard converts, it does not alter.
        @test derive_seeds(2026, UInt8(4)) == derive_seeds(2026, 4)
        @test derive_seeds(2026, big(4)) == derive_seeds(2026, 4)
        @test derive_seeds(Xoshiro(2026), Int32(4)) == derive_seeds(Xoshiro(2026), 4)
    end

    @testset "prefix property" begin
        n = 12
        full = derive_seeds(2026, n)
        for k in 0:n
            @test full[1:k] == derive_seeds(2026, k)
        end
    end

    @testset "distinct masters give distinct substreams" begin
        # A modest fixture, not a uniqueness guarantee: the derived seeds are
        # draws from a 64-bit stream, and no claim is made that two masters can
        # never collide.
        @test derive_seeds(2026, 4) != derive_seeds(2027, 4)
        @test derive_seeds(0, 4) != derive_seeds(1, 4)
        @test length(unique(derive_seeds(20260802, 64))) == 64
    end

    @testset "generic AbstractRNG method" begin
        # StableRNGs exercises the method against a generator that is not
        # `Xoshiro`, confirming that the derivation depends on nothing beyond the
        # `AbstractRNG` interface. It is used here for its independence from
        # `Xoshiro`, not to freeze a scientific outcome.
        @test derive_seeds(StableRNG(2026), 6) isa Vector{UInt64}
        @test derive_seeds(StableRNG(2026), 6) == derive_seeds(StableRNG(2026), 6)
        @test derive_seeds(StableRNG(2026), 6)[1:2] == derive_seeds(StableRNG(2026), 2)
        @test derive_seeds(StableRNG(1), 6) != derive_seeds(StableRNG(2), 6)
    end

    @testset "the master stream advances normally" begin
        rng = Xoshiro(20260802)
        first_batch = derive_seeds(rng, 4)
        second_batch = derive_seeds(rng, 4)
        @test first_batch != second_batch

        # Eight seeds drawn at once are exactly the two successive batches of
        # four, so a master stream can be consumed incrementally without changing
        # the substreams a run would otherwise have used.
        @test derive_seeds(Xoshiro(20260802), 8) == vcat(first_batch, second_batch)

        # Requesting zero seeds leaves the stream where it was.
        untouched = Xoshiro(20260802)
        @test isempty(derive_seeds(untouched, 0))
        @test derive_seeds(untouched, 4) == first_batch
    end
end
