using Statistics: mean
using Test

using StochasticCaseStudies: fit_loglog

@testset "error analysis" begin
    @testset "an exact power law is recovered" begin
        # y = 3 x^2, so log(y) = log(3) + 2 log(x) exactly. The residuals are not
        # bitwise zero, because log(3 * x^2) and log(3) + 2 * log(x) differ in
        # the last places, but they are at the rounding level of the logarithms
        # themselves.
        x = [1.0, 2.0, 4.0, 8.0, 16.0]
        y = 3 .* x .^ 2
        fit = fit_loglog(x, y)

        @test fit isa NamedTuple
        @test keys(fit) == (:slope, :intercept, :slope_se, :r2, :residuals)
        @test fit.slope ≈ 2.0 atol = 1.0e-12
        @test fit.intercept ≈ log(3) atol = 1.0e-12
        @test maximum(abs, fit.residuals) < 1.0e-12
        @test fit.slope_se ≈ 0.0 atol = 1.0e-12
        @test fit.r2 ≈ 1.0 atol = 1.0e-12
        @test length(fit.residuals) == length(x)
        @test fit.residuals isa Vector{Float64}

        # A different exponent and constant, on an unevenly spaced grid.
        x = [0.5, 1.0, 3.0, 7.0, 11.0, 20.0]
        y = 0.25 .* x .^ (-1.5)
        fit = fit_loglog(x, y)
        @test fit.slope ≈ -1.5 atol = 1.0e-12
        @test fit.intercept ≈ log(0.25) atol = 1.0e-12
        @test fit.r2 ≈ 1.0 atol = 1.0e-12
    end

    @testset "a deterministic perturbed fixture" begin
        # A power law of order 2 perturbed by fixed multiplicative factors of a
        # few per cent. No randomness is involved, so the expected values below
        # are properties of these numbers alone.
        x = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
        perturbation = [1.02, 0.98, 1.03, 0.97, 1.01, 0.99]
        y = 3 .* x .^ 2 .* perturbation
        fit = fit_loglog(x, y)

        @test isfinite(fit.slope)
        @test isfinite(fit.intercept)
        @test isfinite(fit.slope_se)
        @test isfinite(fit.r2)
        @test all(isfinite, fit.residuals)

        # The perturbation is small, so the recovered order stays close to 2 and
        # the fit remains nearly perfect; but the scatter is now genuine, so the
        # slope has a nonzero standard error and r2 falls short of 1.
        @test abs(fit.slope - 2.0) < 0.02
        @test fit.slope_se > 0
        @test 0.999 < fit.r2 < 1.0

        # The two ordinary-least-squares normal equations, which hold whatever
        # the data: the residuals sum to zero and are orthogonal to log(x).
        lx = log.(x)
        @test abs(sum(fit.residuals)) < 1.0e-12
        @test abs(sum(fit.residuals .* lx)) < 1.0e-12
        @test abs(mean(fit.residuals)) < 1.0e-12

        # The residuals are those of the reported line, not of some other one.
        ly = log.(y)
        @test fit.residuals ≈ ly .- (fit.intercept .+ fit.slope .* lx)
    end

    @testset "invalid input is rejected" begin
        x = [1.0, 2.0, 4.0, 8.0]
        y = 3 .* x .^ 2

        @test_throws ArgumentError fit_loglog(x, y[1:3])
        @test_throws ArgumentError fit_loglog(x[1:3], y)
        @test_throws ArgumentError fit_loglog([1.0, 2.0], [1.0, 4.0])
        @test_throws ArgumentError fit_loglog([1.0], [1.0])
        @test_throws ArgumentError fit_loglog(Float64[], Float64[])

        # Zero, negative, and non-finite values have no logarithm, or none that
        # a real-valued fit can use.
        @test_throws ArgumentError fit_loglog([0.0, 2.0, 4.0, 8.0], y)
        @test_throws ArgumentError fit_loglog([-1.0, 2.0, 4.0, 8.0], y)
        @test_throws ArgumentError fit_loglog([NaN, 2.0, 4.0, 8.0], y)
        @test_throws ArgumentError fit_loglog([Inf, 2.0, 4.0, 8.0], y)
        @test_throws ArgumentError fit_loglog(x, [0.0, 12.0, 48.0, 192.0])
        @test_throws ArgumentError fit_loglog(x, [-3.0, 12.0, 48.0, 192.0])
        @test_throws ArgumentError fit_loglog(x, [NaN, 12.0, 48.0, 192.0])
        @test_throws ArgumentError fit_loglog(x, [Inf, 12.0, 48.0, 192.0])

        # A constant log(x) leaves the slope undetermined; a constant log(y)
        # leaves r2 undefined, because the total sum of squares vanishes.
        @test_throws ArgumentError fit_loglog([2.0, 2.0, 2.0, 2.0], y)
        @test_throws ArgumentError fit_loglog(x, [5.0, 5.0, 5.0, 5.0])
    end

    @testset "the smallest admissible fit" begin
        # Three points are the fewest that admit a residual degree of freedom.
        x = [1.0, 2.0, 4.0]
        fit = fit_loglog(x, 5 .* x .^ 3)
        @test fit.slope ≈ 3.0 atol = 1.0e-12
        @test fit.intercept ≈ log(5) atol = 1.0e-12
        @test isfinite(fit.slope_se)
        @test isfinite(fit.r2)

        # Two distinct values of log(x) suffice, even with a repeated abscissa.
        repeated = [2.0, 2.0, 5.0]
        fit = fit_loglog(repeated, [1.0, 1.1, 4.0])
        @test isfinite(fit.slope)
        @test isfinite(fit.slope_se)
        @test fit.slope_se > 0
    end

    @testset "integer input is admissible" begin
        fit = fit_loglog([1, 2, 4, 8], [3, 12, 48, 192])
        @test fit.slope ≈ 2.0 atol = 1.0e-12
        @test fit.residuals isa Vector{Float64}
    end

    @testset "type stability" begin
        x = [1.0, 2.0, 4.0, 8.0]
        y = 3 .* x .^ 2
        @test @inferred(fit_loglog(x, y)) isa NamedTuple{
            (:slope, :intercept, :slope_se, :r2, :residuals),
            Tuple{Float64,Float64,Float64,Float64,Vector{Float64}},
        }
        @test @inferred(fit_loglog([1, 2, 4, 8], [3, 12, 48, 192])) isa NamedTuple
    end
end
