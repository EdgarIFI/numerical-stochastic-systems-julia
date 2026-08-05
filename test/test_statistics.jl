using Test

using Distributions: TDist, quantile
using StochasticCaseStudies: nsigma, relative_error, rmse, summarize_independent

@testset "independent statistics" begin
    # A hand-computable sample: mean 3, sum of squared deviations 10, so the
    # unbiased variance is 10 / 4 = 5/2 and the standard error sqrt(5/2 / 5).
    observations = [1.0, 2.0, 3.0, 4.0, 5.0]

    @testset "hand-computable summary" begin
        summary = summarize_independent(observations)
        @test summary isa NamedTuple
        @test keys(summary) == (:n, :mean, :sd, :sem, :lower, :upper, :level)
        @test summary.n == 5
        @test summary.mean == 3.0
        @test summary.sd ≈ sqrt(2.5)
        @test summary.sem ≈ sqrt(0.5)
        @test summary.sem ≈ summary.sd / sqrt(summary.n)
        @test summary.level == 0.95
    end

    @testset "interval against an independently assembled formula" begin
        for level in (0.68, 0.95, 0.99)
            summary = summarize_independent(observations; level = level)
            # Assembled from the two-sided tail probability rather than from the
            # midpoint expression the implementation uses.
            tail = (1 - level) / 2
            halfwidth = quantile(TDist(4), 1 - tail) * sqrt(0.5)
            @test summary.lower ≈ 3.0 - halfwidth
            @test summary.upper ≈ 3.0 + halfwidth
            @test summary.upper - summary.lower ≈ 2 * halfwidth
            @test summary.level == level
        end
        # A wider interval is nested outside a narrower one.
        narrow = summarize_independent(observations; level = 0.68)
        wide = summarize_independent(observations; level = 0.99)
        @test wide.lower < narrow.lower < narrow.upper < wide.upper
    end

    @testset "integer input is admissible" begin
        summary = summarize_independent([1, 2, 3, 4, 5])
        @test summary.mean == 3.0
        @test summary.sd ≈ sqrt(2.5)
        @test summary isa NamedTuple{
            (:n, :mean, :sd, :sem, :lower, :upper, :level),
            Tuple{Int,Float64,Float64,Float64,Float64,Float64,Float64},
        }
    end

    @testset "invalid summaries are rejected" begin
        @test_throws ArgumentError summarize_independent([1.0])
        @test_throws ArgumentError summarize_independent(Float64[])
        @test_throws ArgumentError summarize_independent(observations; level = 0.0)
        @test_throws ArgumentError summarize_independent(observations; level = 1.0)
        @test_throws ArgumentError summarize_independent(observations; level = -0.5)
        @test_throws ArgumentError summarize_independent(observations; level = 1.5)
        @test_throws ArgumentError summarize_independent(observations; level = NaN)
        @test_throws ArgumentError summarize_independent([1.0, NaN, 3.0])
        @test_throws ArgumentError summarize_independent([1.0, Inf, 3.0])
        @test_throws ArgumentError summarize_independent([1.0, -Inf, 3.0])
    end

    @testset "a constant sample is admissible" begin
        # A constant sample carries no information about dispersion, and the
        # correct report is a zero standard error and an interval of zero width
        # rather than a rejection.
        summary = summarize_independent(fill(2.5, 5))
        @test summary.n == 5
        @test summary.mean == 2.5
        @test summary.sd == 0.0
        @test summary.sem == 0.0
        @test summary.lower == 2.5
        @test summary.upper == 2.5
        @test summary.upper - summary.lower == 0.0
        # The same holds for a constant integer sample.
        @test summarize_independent(fill(3, 4)).sd == 0.0
    end

    @testset "the Float64 numerical domain" begin
        # The shared statistics compute in Float64, and the contracts are
        # enforced there. A value that is mathematically finite but whose
        # conversion is not is rejected on input, and a calculation that
        # overflows is rejected on output; neither returns NaN or Inf.
        huge = big(10)^400

        @test_throws ArgumentError summarize_independent([huge, huge, huge])
        @test_throws ArgumentError summarize_independent([1.0, huge, 3.0])
        # Finite Float64 observations whose mean overflows.
        @test_throws ArgumentError summarize_independent([1.7e308, 1.7e308, 1.7e308])
        # Finite Float64 observations whose standard deviation overflows.
        @test_throws ArgumentError summarize_independent([1.7e308, -1.7e308, 0.0])
        # A coverage so close to one that the Student-t quantile is infinite
        # gives a nonfinite interval, which is an error rather than a report of
        # infinite width.
        @test_throws ArgumentError summarize_independent(
            observations;
            level = prevfloat(1.0),
        )

        @test_throws ArgumentError nsigma(huge, 0.0, 1.0)
        @test_throws ArgumentError nsigma(0.0, huge, 1.0)
        @test_throws ArgumentError nsigma(1.0, 0.0, huge)
        # Finite operands whose discrepancy overflows: an unrepresentably small
        # standard error, and a difference that overflows the subtraction.
        @test_throws ArgumentError nsigma(1.0, 0.0, 5.0e-324)
        @test_throws ArgumentError nsigma(1.7e308, -1.7e308, 1.0)

        # rmse: conversion, squaring, and accumulation.
        @test_throws ArgumentError rmse([huge])
        @test_throws ArgumentError rmse([1.0, huge])
        @test_throws ArgumentError rmse([1.0e200, 1.0e200])
        @test_throws ArgumentError rmse([1.0e154, 1.0e154])
        # The squares below are individually finite and their sum is not.
        @test isfinite(abs2(1.0e154))
        @test rmse([1.0e150, 1.0e150]) == 1.0e150

        # Paired rmse: conversion, subtraction, squaring, and accumulation.
        @test_throws ArgumentError rmse([huge], [0.0])
        @test_throws ArgumentError rmse([0.0], [huge])
        @test_throws ArgumentError rmse([1.7e308], [-1.7e308])
        @test_throws ArgumentError rmse([1.0e200, 1.0], [0.0, 0.0])
        @test_throws ArgumentError rmse([1.0e154, 1.0e154], [0.0, 0.0])

        @test_throws ArgumentError relative_error(huge, 1.0)
        @test_throws ArgumentError relative_error(1.0, huge)
        # A ratio that overflows, and a reference that underflows to zero on
        # conversion and is therefore a zero reference at this precision.
        @test_throws ArgumentError relative_error(1.0, 5.0e-324)
        @test_throws ArgumentError relative_error(1.0, big(10.0)^-400)
    end

    @testset "discrepancy in standard errors" begin
        @test nsigma(1.0, 0.0, 0.5) == 2.0
        @test nsigma(0.0, 1.0, 0.5) == 2.0
        @test nsigma(-1.5, 0.5, 0.5) == 4.0
        @test nsigma(3.0, 3.0, 0.25) == 0.0
        @test nsigma(1, 0, 2) == 0.5

        @test_throws ArgumentError nsigma(1.0, 0.0, 0.0)
        @test_throws ArgumentError nsigma(1.0, 0.0, -0.5)
        @test_throws ArgumentError nsigma(NaN, 0.0, 0.5)
        @test_throws ArgumentError nsigma(1.0, Inf, 0.5)
        @test_throws ArgumentError nsigma(1.0, 0.0, NaN)
    end

    @testset "root mean squared error" begin
        @test rmse([3.0, 4.0]) == sqrt(12.5)
        @test rmse([0.0, 0.0, 0.0]) == 0.0
        @test rmse([2.0]) == 2.0
        @test rmse([-3.0, 4.0]) == sqrt(12.5)

        @test rmse([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]) == 0.0
        @test rmse([0.0, 0.0], [3.0, 4.0]) == sqrt(12.5)
        @test rmse([1.0, 2.0], [0.0, 0.0]) == rmse([1.0, 2.0])
        # The paired form agrees with the single-vector form on the differences.
        x = [1.5, -2.5, 3.5, 0.5]
        y = [1.0, -1.0, 5.0, 0.0]
        @test rmse(x, y) == rmse(x .- y)

        @test_throws ArgumentError rmse(Float64[])
        @test_throws ArgumentError rmse([1.0, NaN])
        @test_throws ArgumentError rmse([1.0, Inf])
        @test_throws ArgumentError rmse(Float64[], Float64[])
        @test_throws ArgumentError rmse([1.0, 2.0], [1.0])
        @test_throws ArgumentError rmse([1.0, 2.0, 3.0], [1.0, 2.0])
        @test_throws ArgumentError rmse([1.0, NaN], [1.0, 2.0])
        @test_throws ArgumentError rmse([1.0, 2.0], [1.0, Inf])
    end

    @testset "relative error" begin
        @test relative_error(3.0, 2.0) == 0.5
        @test relative_error(1.0, 2.0) == 0.5
        @test relative_error(2.0, 2.0) == 0.0
        @test relative_error(-4.0, 2.0) == 3.0
        @test relative_error(2.0, -4.0) == 1.5
        @test relative_error(3, 2) == 0.5

        # A zero reference is an error rather than Inf or NaN: the caller must
        # choose an absolute or mixed tolerance explicitly.
        @test_throws ArgumentError relative_error(1.0, 0.0)
        @test_throws ArgumentError relative_error(0.0, 0.0)
        @test_throws ArgumentError relative_error(NaN, 1.0)
        @test_throws ArgumentError relative_error(1.0, Inf)
    end

    @testset "type stability" begin
        @test @inferred(summarize_independent(observations)) isa NamedTuple
        @test @inferred(summarize_independent(observations; level = 0.99)) isa NamedTuple
        @test @inferred(summarize_independent([1, 2, 3])) isa NamedTuple
        @test @inferred(nsigma(1.0, 0.0, 0.5)) isa Float64
        @test @inferred(rmse([3.0, 4.0])) isa Float64
        @test @inferred(rmse([3.0, 4.0], [0.0, 0.0])) isa Float64
        @test @inferred(relative_error(3.0, 2.0)) isa Float64
    end
end
