using Random: Xoshiro
using Statistics: mean, var
using Test

using Distributions: Normal
using HypothesisTests: ApproximateOneSampleKSTest, pvalue
using StochasticCaseStudies: brownian_increments, coarsen_increments, nsigma

@testset "brownian" begin
    @testset "increment shape and type" begin
        dw = brownian_increments(Xoshiro(20260802), 16, 0.25)
        @test dw isa Vector{Float64}
        @test length(dw) == 16
        @test all(isfinite, dw)
        @test @inferred(brownian_increments(Xoshiro(1), 8, 0.25)) isa Vector{Float64}
        # The generator alone determines the output: the same generator state
        # yields the same increments, and no ambient stream is consulted.
        @test brownian_increments(Xoshiro(7), 32, 0.1) ==
              brownian_increments(Xoshiro(7), 32, 0.1)
        @test brownian_increments(Xoshiro(7), 32, 0.1) !=
              brownian_increments(Xoshiro(8), 32, 0.1)
    end

    @testset "invalid increment arguments" begin
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 0, 0.1)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), -3, 0.1)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, 0.0)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, -0.1)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, Inf)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, NaN)

        # A count above `typemax(Int)` is rejected by name, before the conversion
        # and before any allocation, so the failure is an `ArgumentError` rather
        # than an `InexactError`.
        @test_throws ArgumentError brownian_increments(
            Xoshiro(1),
            big(typemax(Int)) + 1,
            0.1,
        )
        @test_throws ArgumentError brownian_increments(Xoshiro(1), typemax(UInt), 0.1)

        # A step size that is mathematically finite but whose conversion to
        # Float64 is not: the contract applies in the Float64 numerical domain.
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, big(10)^400)
        @test_throws ArgumentError brownian_increments(Xoshiro(1), 4, big(10.0)^400)
    end

    @testset "the increments are finite" begin
        # Finiteness of the returned increments is checked rather than assumed,
        # over a wide range of admissible step sizes.
        for dt in (1.0e-300, 1.0e-6, 0.25, 1.0e6, 1.0e300)
            @test all(isfinite, brownian_increments(Xoshiro(11), 64, dt))
        end
    end

    @testset "coarsening is exact block summation" begin
        dw = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        @test coarsen_increments(dw, 1) == dw
        @test coarsen_increments(dw, 2) == [3.0, 7.0, 11.0]
        @test coarsen_increments(dw, 3) == [6.0, 15.0]
        @test coarsen_increments(dw, 6) == [21.0]
        @test coarsen_increments(dw, 2) isa Vector{Float64}
        @test @inferred(coarsen_increments(dw, 2)) isa Vector{Float64}

        # Integer input is admissible and returns Float64 storage.
        @test coarsen_increments([1, 2, 3, 4], 2) == [3.0, 7.0]
        @test coarsen_increments([1, 2, 3, 4], 2) isa Vector{Float64}

        # Ordinary finite coarsening is unchanged whatever integer type carries
        # the values or the factor.
        @test coarsen_increments([big(1), big(2), big(3), big(4)], 2) == [3.0, 7.0]
        @test coarsen_increments([1.0, 2.0, 3.0, 4.0], UInt8(2)) == [3.0, 7.0]
        @test coarsen_increments([1.0, 2.0, 3.0, 4.0], big(2)) == [3.0, 7.0]
    end

    @testset "factor one returns independent storage" begin
        dw = [1.0, 2.0, 3.0]
        copied = coarsen_increments(dw, 1)
        @test copied == dw
        @test copied !== dw
        copied[1] = -100.0
        @test dw[1] == 1.0
    end

    @testset "invalid coarsening arguments" begin
        @test_throws ArgumentError coarsen_increments(Float64[], 1)
        @test_throws ArgumentError coarsen_increments([1.0, 2.0], 0)
        @test_throws ArgumentError coarsen_increments([1.0, 2.0], -1)
        @test_throws ArgumentError coarsen_increments([1.0, 2.0, 3.0], 2)
        @test_throws ArgumentError coarsen_increments([1.0, 2.0, 3.0], 4)
        @test_throws ArgumentError coarsen_increments([1.0, NaN, 3.0, 4.0], 2)
        @test_throws ArgumentError coarsen_increments([1.0, Inf, 3.0, 4.0], 2)
        @test_throws ArgumentError coarsen_increments([1.0, -Inf, 3.0, 4.0], 2)

        # A factor above `typemax(Int)` is rejected by name rather than raising
        # an `InexactError` on the conversion.
        @test_throws ArgumentError coarsen_increments([1.0, 2.0], big(typemax(Int)) + 1)
        @test_throws ArgumentError coarsen_increments([1.0, 2.0], typemax(UInt))

        # Values that are mathematically finite but whose conversion to Float64
        # is not: the contract applies in the Float64 numerical domain, so these
        # are rejected rather than coarsened to Inf.
        @test_throws ArgumentError coarsen_increments([big(10)^400, big(10)^400], 2)
        @test_throws ArgumentError coarsen_increments([big(10)^400, big(1)], 1)

        # Finite input whose block sum overflows is rejected rather than
        # returned as Inf.
        @test_throws ArgumentError coarsen_increments([1.7e308, 1.7e308], 2)
        @test_throws ArgumentError coarsen_increments(fill(1.0e308, 4), 4)
        # The same values coarsen without overflow when the blocks are smaller,
        # so the rejection is a property of the sum and not of the input alone.
        @test coarsen_increments([1.7e308, 1.7e308], 1) == [1.7e308, 1.7e308]
    end

    @testset "coarsening preserves the total increment" begin
        # A Brownian path's displacement over the whole interval must not depend
        # on the grid it is described on. The two sums differ only by
        # floating-point rounding: `sum` accumulates pairwise over 4096 terms
        # while the coarse total is a sum of 256 naively accumulated blocks of
        # 16, so the discrepancy is bounded by a small multiple of
        # `4096 * eps() * maximum(abs, cumulative partial sums)`, which for
        # increments of standard deviation 0.1 bounds the discrepancy by about
        # 6e-12. The realised discrepancy on this fixture is a few units in the
        # last place, some three orders of magnitude smaller again; the tolerance
        # below is set against the bound rather than against the realisation, so
        # that it does not depend on the stream.
        dw = brownian_increments(Xoshiro(20260802), 4096, 0.01)
        total = sum(dw)
        for factor in (1, 2, 4, 16, 256, 4096)
            @test sum(coarsen_increments(dw, factor)) ≈ total atol = 1.0e-9
        end
        # Block sums are exactly the sums of their own blocks, not merely close.
        coarse = coarsen_increments(dw, 16)
        @test coarse[1] == sum(dw[1:16])
        @test coarse[end] == sum(dw[4081:4096])
        @test length(coarse) == 256
    end

    @testset "coarsening twice equals coarsening once" begin
        dw = brownian_increments(Xoshiro(1), 64, 0.5)
        once = coarsen_increments(dw, 8)
        twice = coarsen_increments(coarsen_increments(dw, 4), 2)
        @test length(once) == 8
        @test once ≈ twice atol = 1.0e-12
    end

    @testset "distribution of the increments" begin
        # A deterministic fixture with an explicitly constructed generator. The
        # thresholds are the ratified ones: four standard errors for a
        # statistical assertion, `alpha = 0.001` for a hypothesis test; see
        # docs/methods/error-analysis.md. With n = 200 000 the false-failure rate
        # of the two moment assertions is about 6e-5 each, and of the
        # Kolmogorov–Smirnov test 1e-3, for a correct implementation on any
        # stream.
        n = 200_000
        dt = 0.01
        dw = brownian_increments(Xoshiro(20260802), n, dt)

        # The sample mean has standard error sqrt(dt / n) under the null.
        se_mean = sqrt(dt / n)
        @test nsigma(mean(dw), 0.0, se_mean) < 4

        # The unbiased sample variance of n normal draws has standard error
        # dt * sqrt(2 / (n - 1)).
        se_var = dt * sqrt(2 / (n - 1))
        @test nsigma(var(dw), dt, se_var) < 4

        # Shape, not merely the first two moments. The approximate test is used
        # rather than the exact one because the asymptotic null distribution is
        # accurate and inexpensive at this sample size.
        standardised = dw ./ sqrt(dt)
        @test pvalue(ApproximateOneSampleKSTest(standardised, Normal())) > 0.001
    end

    @testset "coarsened increments carry the coarse variance" begin
        # Summing `factor` independent increments of variance dt gives an
        # increment of variance `factor * dt`, which is what makes a convergence
        # study over several step sizes able to reuse one path.
        n = 200_000
        dt = 0.01
        factor = 4
        dw = brownian_increments(Xoshiro(20260803), n, dt)
        coarse = coarsen_increments(dw, factor)
        m = length(coarse)
        coarse_dt = factor * dt
        @test nsigma(var(coarse), coarse_dt, coarse_dt * sqrt(2 / (m - 1))) < 4
    end
end
