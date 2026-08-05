using Random: Xoshiro, randn
using Statistics: mean, var
using Test

using StochasticCaseStudies: integrated_autocorrelation_time, summarize_correlated

"""
    ar1_series(seed, n, phi) -> Vector{Float64}

Simulate `n` observations of a stationary Gaussian AR(1) process,
`x[t] = phi * x[t-1] + sqrt(1 - phi^2) * e[t]`, from an explicitly constructed
generator.

The innovation variance is chosen so that the marginal variance is 1, and the
first observation is drawn from the stationary distribution, so no burn-in is
required. The autocorrelation at lag `k` is then `phi^k` and the integrated
autocorrelation time is `(1 + phi) / (1 - phi)`.
"""
function ar1_series(seed::Integer, n::Integer, phi::Real)
    rng = Xoshiro(seed)
    x = Vector{Float64}(undef, n)
    innovation = sqrt(1 - phi^2)
    x[1] = randn(rng)
    for t in 2:n
        x[t] = phi * x[t-1] + innovation * randn(rng)
    end
    return x
end

"""
    ZeroBased(data)

A minimal zero-based vector, defined here so that the indexing contracts can be
exercised without extending the ratified dependency set. Its axis begins at zero,
so `firstindex` is `0` and `Base.require_one_based_indexing` rejects it.
"""
struct ZeroBased{T} <: AbstractVector{T}
    data::Vector{T}
end

Base.size(v::ZeroBased) = size(v.data)
Base.axes(v::ZeroBased) = (0:(length(v.data)-1),)
Base.IndexStyle(::Type{<:ZeroBased}) = IndexLinear()
Base.getindex(v::ZeroBased, i::Int) = v.data[i+1]

@testset "correlated statistics" begin
    @testset "integrated autocorrelation time, exact arithmetic" begin
        # The independent case: no lags are summed, so the correction is unity.
        @test integrated_autocorrelation_time([1.0]; maxlag = 0) == 1.0
        @test integrated_autocorrelation_time([1.0, 0.5, 0.25]; maxlag = 0) == 1.0

        # tau = 1 + 2 * sum(acf[2:maxlag+1]).
        @test integrated_autocorrelation_time([1.0, 0.5, 0.25]; maxlag = 1) == 2.0
        @test integrated_autocorrelation_time([1.0, 0.5, 0.25]; maxlag = 2) == 2.5
        @test integrated_autocorrelation_time([1.0, 0.25, 0.125, 0.0625]; maxlag = 3) ==
              1.875

        # A negative autocorrelation shortens the correlation time; the result is
        # still admissible while it stays strictly positive.
        @test integrated_autocorrelation_time([1.0, -0.2]; maxlag = 1) ≈ 0.6
        @test integrated_autocorrelation_time([1.0, -0.1, 0.05]; maxlag = 2) ≈ 0.9

        @test @inferred(integrated_autocorrelation_time([1.0, 0.5]; maxlag = 1)) isa Float64
        @test integrated_autocorrelation_time([1, 0]; maxlag = 1) == 1.0
    end

    @testset "only the summed window is inspected" begin
        # Values beyond `maxlag` take no part in the sum and are not validated,
        # so a caller may pass a longer autocorrelation function than it uses.
        @test integrated_autocorrelation_time([1.0, 0.5, NaN]; maxlag = 1) == 2.0
        @test integrated_autocorrelation_time([1.0, 0.5, Inf]; maxlag = 1) == 2.0
    end

    @testset "invalid autocorrelation input" begin
        @test_throws ArgumentError integrated_autocorrelation_time(Float64[]; maxlag = 0)
        @test_throws ArgumentError integrated_autocorrelation_time([1.0]; maxlag = 1)
        @test_throws ArgumentError integrated_autocorrelation_time([1.0, 0.5]; maxlag = 2)
        @test_throws ArgumentError integrated_autocorrelation_time([1.0, 0.5]; maxlag = -1)

        # The lag-zero value must be a normalised autocorrelation, not an
        # autocovariance or a truncated tail.
        @test_throws ArgumentError integrated_autocorrelation_time([0.9, 0.1]; maxlag = 1)
        @test_throws ArgumentError integrated_autocorrelation_time([1.5, 0.1]; maxlag = 1)
        @test_throws ArgumentError integrated_autocorrelation_time([0.0]; maxlag = 0)
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0 + 1.0e-6, 0.1];
            maxlag = 1,
        )
        # A departure well inside the tolerance is accepted.
        @test integrated_autocorrelation_time([1.0 + 1.0e-12, 0.5]; maxlag = 1) ≈ 2.0

        @test_throws ArgumentError integrated_autocorrelation_time([1.0, NaN]; maxlag = 1)
        @test_throws ArgumentError integrated_autocorrelation_time([1.0, Inf]; maxlag = 1)
        @test_throws ArgumentError integrated_autocorrelation_time([NaN, 0.5]; maxlag = 1)

        # A window reaching into an anticorrelated tail can cancel the lag-zero
        # term entirely; no effective sample size can be formed from that.
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0, -0.5];
            maxlag = 1,
        )
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0, -0.8];
            maxlag = 1,
        )
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0, -0.3, -0.3];
            maxlag = 2,
        )

        # A window above `typemax(Int)` is rejected by name, before the
        # conversion, so the failure is an `ArgumentError` rather than an
        # `InexactError`.
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0, 0.5];
            maxlag = big(typemax(Int)) + 1,
        )
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0, 0.5];
            maxlag = typemax(UInt),
        )

        # Values that are mathematically finite but whose conversion to Float64
        # is not: the contract applies in the Float64 numerical domain.
        @test_throws ArgumentError integrated_autocorrelation_time(
            [big(1), big(10)^400];
            maxlag = 1,
        )
        @test_throws ArgumentError integrated_autocorrelation_time(
            [big(10)^400, big(1)];
            maxlag = 1,
        )
    end

    @testset "the internal lag-zero acceptance tolerance" begin
        # 1e-8 decides whether an externally supplied sequence is a normalised
        # autocorrelation function. It is an acceptance tolerance on the
        # lag-zero value alone, and takes no part in choosing or truncating the
        # window: the summed lags are unaffected by it.
        @test integrated_autocorrelation_time([1.0 + 1.0e-9, 0.5]; maxlag = 1) ≈ 2.0
        @test integrated_autocorrelation_time([1.0 - 1.0e-9, 0.5]; maxlag = 1) ≈ 2.0
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0 + 1.0e-7, 0.5];
            maxlag = 1,
        )
        @test_throws ArgumentError integrated_autocorrelation_time(
            [1.0 - 1.0e-7, 0.5];
            maxlag = 1,
        )
        # A lag beyond zero is never tested against it, however far from 1.
        @test integrated_autocorrelation_time([1.0, 0.5, 0.25]; maxlag = 2) == 2.5
    end

    @testset "offset-indexed input" begin
        # The integrated autocorrelation time supports an offset-indexed
        # autocorrelation function: the lag-zero value is `acf[begin]`, not
        # `acf[1]`, and the result agrees with the one-based equivalent.
        offset_acf = ZeroBased([1.0, 0.5, 0.25])
        @test firstindex(offset_acf) == 0
        @test integrated_autocorrelation_time(offset_acf; maxlag = 0) == 1.0
        @test integrated_autocorrelation_time(offset_acf; maxlag = 1) == 2.0
        @test integrated_autocorrelation_time(offset_acf; maxlag = 2) == 2.5
        @test integrated_autocorrelation_time(offset_acf; maxlag = 2) ==
              integrated_autocorrelation_time([1.0, 0.5, 0.25]; maxlag = 2)

        # `summarize_correlated` passes the series to `StatsBase.autocor`, which
        # requires one-based indexing. An offset-indexed series is therefore
        # rejected explicitly through that contract rather than silently
        # misaligned against its own autocorrelations.
        @test_throws ArgumentError summarize_correlated(
            ZeroBased(collect(1.0:6.0));
            maxlag = 3,
        )
        @test_throws ArgumentError summarize_correlated(
            ZeroBased(collect(1.0:6.0));
            maxlag = 0,
        )
    end

    @testset "independent data gives a correlation time near one" begin
        # No assertion is made about the stream itself: the check is that an
        # independent sample yields a correction close to unity. With n = 50 000
        # and a window of 20 lags the standard error of the estimate is about
        # 0.04, so the tolerance below is roughly ten standard errors — loose on
        # purpose, because the test must not fail on a Julia release whose
        # default stream differs.
        x = randn(Xoshiro(20260802), 50_000)
        tau = summarize_correlated(x; maxlag = 20).tau_int
        @test abs(tau - 1) < 0.4
    end

    @testset "AR(1) fixture with a known correlation time" begin
        # For a stationary AR(1) process the autocorrelation at lag k is phi^k
        # and tau_int = (1 + phi) / (1 - phi). The estimator truncates the sum at
        # maxlag, so it cannot reproduce the infinite-series value exactly; the
        # neglected tail is 2 * phi^(maxlag+1) / (1 - phi), which is reported
        # below and is negligible beside the sampling uncertainty. The standard
        # error of the estimate is roughly tau * sqrt(2 * (2 * maxlag + 1) / n),
        # and each tolerance is about seven times that.
        n = 200_000

        phi = 0.5
        maxlag = 25
        x = ar1_series(20260802, n, phi)
        theory = (1 + phi) / (1 - phi)
        neglected = 2 * phi^(maxlag + 1) / (1 - phi)
        @test theory == 3.0
        @test neglected < 1.0e-6
        summary = summarize_correlated(x; maxlag = maxlag)
        @test abs(summary.tau_int - theory) < 0.5

        phi = 0.8
        maxlag = 60
        x = ar1_series(20260803, n, phi)
        theory = (1 + phi) / (1 - phi)
        neglected = 2 * phi^(maxlag + 1) / (1 - phi)
        @test theory ≈ 9.0
        @test neglected < 1.0e-4
        summary = summarize_correlated(x; maxlag = maxlag)
        @test abs(summary.tau_int - theory) < 2.0

        # Treating the same series as independent would understate the standard
        # error by about sqrt(tau_int), which is the entire point of the
        # correction.
        @test summary.sem > 2 * summary.sd / sqrt(n)
    end

    @testset "the summary is internally consistent" begin
        x = ar1_series(20260804, 20_000, 0.5)
        summary = summarize_correlated(x; maxlag = 25)
        @test summary isa NamedTuple
        @test keys(summary) == (
            :n,
            :mean,
            :sd,
            :tau_int,
            :ess,
            :sem,
            :lower,
            :upper,
            :level,
            :maxlag,
        )
        @test summary.n == 20_000
        @test summary.maxlag == 25
        @test summary.level == 0.95
        @test summary.mean == mean(x)
        @test summary.sd == sqrt(var(x))
        # The two defining identities, recomputed from the returned fields.
        @test summary.ess == summary.n / summary.tau_int
        @test summary.sem == summary.sd * sqrt(summary.tau_int / summary.n)
        @test summary.lower < summary.mean < summary.upper
        @test summary.upper - summary.lower > 0

        # A wider coverage gives a wider interval about the same centre.
        wide = summarize_correlated(x; maxlag = 25, level = 0.99)
        @test wide.mean == summary.mean
        @test wide.sem == summary.sem
        @test wide.lower < summary.lower
        @test wide.upper > summary.upper

        # With maxlag = 0 the summary reduces to the independent-sample one.
        independent = summarize_correlated(x; maxlag = 0)
        @test independent.tau_int == 1.0
        @test independent.ess == independent.n
        @test independent.sem ≈ independent.sd / sqrt(independent.n)
    end

    @testset "the window is always explicit" begin
        x = ar1_series(20260805, 1_000, 0.5)
        # There is no default window and no automatic selection: omitting the
        # keyword is an error rather than a silent choice.
        @test_throws UndefKeywordError summarize_correlated(x)
    end

    @testset "a hand-computable summary" begin
        # A short deterministic ramp, whose autocorrelations can be evaluated by
        # hand and which pins the normalisation StatsBase uses. With
        # d = x - mean(x), the sum of squared deviations is 17.5 and the
        # unnormalised lagged sums are 8.75, 1.0 and -4.75, so
        # tau = 1 + 2 * (8.75 + 1.0 - 4.75) / 17.5 = 1 + 10 / 17.5.
        ramp = collect(1.0:6.0)
        summary = summarize_correlated(ramp; maxlag = 3)
        @test summary.n == 6
        @test summary.mean == 3.5
        @test summary.sd == sqrt(3.5)
        @test summary.tau_int ≈ 1 + 10 / 17.5
        @test summary.ess ≈ 6 / (1 + 10 / 17.5)
    end

    @testset "invalid correlated summaries are rejected" begin
        x = ar1_series(20260806, 500, 0.5)
        @test_throws ArgumentError summarize_correlated([1.0, 2.0]; maxlag = 0)
        @test_throws ArgumentError summarize_correlated(x; maxlag = -1)
        @test_throws ArgumentError summarize_correlated(x; maxlag = 500)
        @test_throws ArgumentError summarize_correlated(x; maxlag = 600)

        # Too few lagged pairs remain at the largest retained lag. The boundary
        # is exercised on the deterministic ramp: three pairs are admissible,
        # two and one are not. A stochastic series is not used here, because at
        # a window that long the estimated correlation time is dominated by
        # lags estimated from a handful of products and its sign is not
        # determined by the implementation.
        ramp = collect(1.0:6.0)
        @test summarize_correlated(ramp; maxlag = 3) isa NamedTuple
        @test_throws ArgumentError summarize_correlated(ramp; maxlag = 4)
        @test_throws ArgumentError summarize_correlated(ramp; maxlag = 5)

        @test_throws ArgumentError summarize_correlated(fill(1.0, 50); maxlag = 5)
        @test_throws ArgumentError summarize_correlated([1.0, NaN, 3.0, 4.0]; maxlag = 1)
        @test_throws ArgumentError summarize_correlated([1.0, Inf, 3.0, 4.0]; maxlag = 1)
        @test_throws ArgumentError summarize_correlated(x; maxlag = 5, level = 0.0)
        @test_throws ArgumentError summarize_correlated(x; maxlag = 5, level = 1.0)
        @test_throws ArgumentError summarize_correlated(x; maxlag = 5, level = NaN)

        # A window above `typemax(Int)` is rejected by name rather than raising
        # an `InexactError` on the conversion.
        @test_throws ArgumentError summarize_correlated(x; maxlag = big(typemax(Int)) + 1)
        @test_throws ArgumentError summarize_correlated(x; maxlag = typemax(UInt))

        # Observations that are mathematically finite but whose conversion to
        # Float64 is not.
        huge = big(10)^400
        @test_throws ArgumentError summarize_correlated(
            [huge, huge + 1, huge + 2, huge + 3];
            maxlag = 1,
        )
        @test_throws ArgumentError summarize_correlated(
            [big(1), big(2), huge, big(4)];
            maxlag = 1,
        )

        # A coverage so close to one that the Student-t quantile is infinite
        # gives a nonfinite interval, which is an error rather than a report of
        # infinite width.
        @test_throws ArgumentError summarize_correlated(
            x;
            maxlag = 5,
            level = prevfloat(1.0),
        )
    end

    @testset "the minimum number of contributing pairs" begin
        # The floor excludes a degenerate estimate only. With n observations and
        # a window of maxlag, the autocorrelation at the largest retained lag is
        # formed from n - maxlag pairs, and three are required; the boundary
        # therefore tracks n - maxlag rather than any fixed window. Three pairs
        # are not evidence that the window is statistically sufficient, and
        # nothing here asserts that they are.
        ramp6 = collect(1.0:6.0)
        @test summarize_correlated(ramp6; maxlag = 3).maxlag == 3   # 3 pairs
        @test_throws ArgumentError summarize_correlated(ramp6; maxlag = 4)  # 2 pairs

        ramp8 = collect(1.0:8.0)
        @test summarize_correlated(ramp8; maxlag = 5).maxlag == 5   # 3 pairs
        @test_throws ArgumentError summarize_correlated(ramp8; maxlag = 6)  # 2 pairs
    end

    @testset "the effective sample size" begin
        # The effective sample size is not capped at n. An anticorrelated series
        # has tau_int < 1 and genuinely carries more information about its mean
        # than n independent observations would. For an AR(1) process with
        # phi = -0.5 the infinite-series value is (1 + phi) / (1 - phi) = 1/3;
        # the estimator truncates at maxlag and no claim is made that the two
        # agree, only that the estimate lies far below 1. The standard error of
        # the estimate is roughly tau * sqrt(2 * (2 * maxlag + 1) / n) ≈ 0.015,
        # so the assertion below is some forty standard errors from failing.
        x = ar1_series(20260808, 50_000, -0.5)
        summary = summarize_correlated(x; maxlag = 25)
        @test summary.tau_int < 1
        @test summary.ess > summary.n
        @test summary.ess == summary.n / summary.tau_int

        # The `ess > 1` guard is retained defensively. Under exact arithmetic,
        # and under the demeaned denominator-n autocorrelation convention
        # StatsBase currently uses, the guards on the variance and on tau_int
        # already imply it, so no admissible input is known that triggers it.
        # What is asserted here is the property the interval actually requires.
        @test summary.ess > 1
        @test summarize_correlated(collect(1.0:6.0); maxlag = 3).ess > 1
        @test summarize_correlated(ar1_series(20260809, 2_000, 0.8); maxlag = 40).ess > 1
    end

    @testset "the diagnostics are finite" begin
        # Every returned floating diagnostic and interval endpoint is required
        # to be finite, and is so for an ordinary fixture.
        for (phi, maxlag) in ((0.0, 0), (0.5, 20), (0.8, 40), (-0.5, 20))
            summary = summarize_correlated(
                ar1_series(20260810, 5_000, phi);
                maxlag = maxlag,
            )
            for field in (:mean, :sd, :tau_int, :ess, :sem, :lower, :upper, :level)
                @test isfinite(getfield(summary, field))
            end
        end
    end

    @testset "no automatic window selection" begin
        # Different windows give different correlation times on the same data,
        # and the window used is reported back unchanged: nothing is selected,
        # truncated, or adapted on the caller's behalf. The values are those of
        # the deterministic ramp, whose lagged sums are 8.75, 1.0 and -4.75 over
        # a sum of squared deviations of 17.5.
        ramp = collect(1.0:6.0)
        @test summarize_correlated(ramp; maxlag = 1).tau_int ≈ 1 + 2 * 8.75 / 17.5
        @test summarize_correlated(ramp; maxlag = 2).tau_int ≈ 1 + 2 * 9.75 / 17.5
        @test summarize_correlated(ramp; maxlag = 3).tau_int ≈ 1 + 2 * 5.0 / 17.5
        @test summarize_correlated(ramp; maxlag = 1).maxlag == 1
        @test summarize_correlated(ramp; maxlag = 2).maxlag == 2
    end

    @testset "type stability" begin
        x = ar1_series(20260807, 2_000, 0.5)
        @test @inferred(summarize_correlated(x; maxlag = 20)) isa NamedTuple
        @test @inferred(summarize_correlated(x; maxlag = 20, level = 0.99)) isa NamedTuple
        # Integer input infers to the same concrete summary type.
        @test @inferred(summarize_correlated(collect(1:2000); maxlag = 20)) isa NamedTuple
    end
end
