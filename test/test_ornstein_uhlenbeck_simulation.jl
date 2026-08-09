using Test

using Random: AbstractRNG, Xoshiro
using Statistics: mean, var

using StableRNGs
using StochasticCaseStudies: nsigma
using StochasticCaseStudies.OrnsteinUhlenbeck:
    euler_stationary_variance,
    euler_step,
    exact_step,
    exact_transition_coefficients,
    sample_euler_stationary_step,
    sample_exact_terminal,
    sample_stationary,
    simulate_exact_path,
    simulate_exact_paths,
    stationary_standard_deviation,
    stationary_variance,
    transient_mean,
    transient_variance

# No test in this file asserts a particular value produced by Julia's `Xoshiro`
# generator, as docs/methods/rng-and-seeding.md requires. What is asserted is of
# three kinds: that two computations driven by the same seed agree with one
# another, that a sampler's output has the distribution it claims, to within four
# standard errors, and that a violated precondition throws. The seeds below are
# fixed so that the suite is deterministic; none was selected by trying several
# and keeping one that passed.

const OU_SIM_SEED = 20260806
const OU_SIM_SAMPLES = 20_000

@testset "Ornstein–Uhlenbeck simulation" begin
    @testset "exact one-step conditional behaviour" begin
        x, h, kappa, mu, sigma = 2.5, 0.3, 1.0, 1.0, 1.0
        coefficients = exact_transition_coefficients(kappa, sigma, h)
        expected_mean = mu + coefficients.decay * (x - mu)
        expected_variance = coefficients.innovation_std^2
        rng = Xoshiro(OU_SIM_SEED)
        draws = [exact_step(rng, x, h, kappa, mu, sigma) for _ in 1:OU_SIM_SAMPLES]
        @test all(isfinite, draws)
        mean_se = coefficients.innovation_std / sqrt(OU_SIM_SAMPLES)
        @test nsigma(mean(draws), expected_mean, mean_se) <= 4
        variance_se = expected_variance * sqrt(2 / (OU_SIM_SAMPLES - 1))
        @test nsigma(var(draws), expected_variance, variance_se) <= 4
        # The step is exact at every size, so a single long step lands in the
        # invariant law rather than in an approximation to it.
        far = Xoshiro(OU_SIM_SEED + 1)
        distant = [exact_step(far, x, 40.0, kappa, mu, sigma) for _ in 1:OU_SIM_SAMPLES]
        stationary_se =
            stationary_standard_deviation(kappa, sigma) / sqrt(OU_SIM_SAMPLES)
        @test nsigma(mean(distant), mu, stationary_se) <= 4
    end

    @testset "direct exact-terminal samples" begin
        t, kappa, mu, sigma, x0 = 0.75, 1.0, 1.0, 1.0, -1.0
        n = OU_SIM_SAMPLES
        sample = sample_exact_terminal(Xoshiro(OU_SIM_SEED), n, t, kappa, mu, sigma, x0)
        @test sample isa Vector{Float64}
        @test length(sample) == n
        @test all(isfinite, sample)
        analytic_mean = transient_mean(t, kappa, mu, x0)
        analytic_variance = transient_variance(t, kappa, sigma)
        @test nsigma(mean(sample), analytic_mean, sqrt(analytic_variance / n)) <= 4
        @test nsigma(
            var(sample),
            analytic_variance,
            analytic_variance * sqrt(2 / (n - 1)),
        ) <= 4
        # At t = 0 the marginal is the deterministic initial value.
        @test sample_exact_terminal(Xoshiro(1), 5, 0.0, kappa, mu, sigma, x0) ==
              fill(x0, 5)
    end

    @testset "exact stationary samples" begin
        kappa, mu, sigma = 1.0, 1.0, 1.0
        n = OU_SIM_SAMPLES
        sample = sample_stationary(Xoshiro(OU_SIM_SEED), n, kappa, mu, sigma)
        @test sample isa Vector{Float64}
        @test length(sample) == n
        @test all(isfinite, sample)
        analytic_variance = stationary_variance(kappa, sigma)
        @test nsigma(mean(sample), mu, sqrt(analytic_variance / n)) <= 4
        @test nsigma(
            var(sample),
            analytic_variance,
            analytic_variance * sqrt(2 / (n - 1)),
        ) <= 4
        # The invariant law is the long-time limit of the transient one, and the
        # two samplers agree there to within their sampling error.
        far = sample_exact_terminal(Xoshiro(7), n, 40.0, kappa, mu, sigma, -1.0)
        @test nsigma(mean(far), mu, sqrt(analytic_variance / n)) <= 4
    end

    @testset "exact path dimensions and initial value" begin
        path = simulate_exact_path(Xoshiro(3), 200, 0.05, 1.0, 1.0, 1.0, -1.0)
        @test path isa Vector{Float64}
        @test length(path) == 201
        @test path[1] === -1.0
        @test all(isfinite, path)
        # A hoisted loop and repeated single steps are the same computation, and
        # produce identical values from identical streams.
        stepwise = Vector{Float64}(undef, 201)
        stepwise[1] = -1.0
        rng = Xoshiro(3)
        for k in 1:200
            stepwise[k+1] = exact_step(rng, stepwise[k], 0.05, 1.0, 1.0, 1.0)
        end
        @test path == stepwise
    end

    @testset "exact multi-path dimensions" begin
        paths = simulate_exact_paths(Xoshiro(5), 6, 5.0, 0.02, 1.0, 1.0, 1.0, -1.0)
        @test paths isa Matrix{Float64}
        @test size(paths) == (251, 6)
        @test all(paths[1, :] .=== -1.0)
        @test all(isfinite, paths)
        # Each column is one path, generated in turn from the single generator,
        # so the first column agrees with the single-path routine on the same
        # seed and the columns differ from one another.
        @test paths[:, 1] == simulate_exact_path(Xoshiro(5), 250, 0.02, 1.0, 1.0, 1.0, -1.0)
        @test paths[:, 1] != paths[:, 2]
    end

    @testset "Euler step" begin
        x, h, kappa, mu, sigma = 2.5, 0.3, 1.0, 1.0, 1.0
        n = OU_SIM_SAMPLES
        expected_mean = x + kappa * (mu - x) * h
        expected_variance = sigma^2 * h
        rng = Xoshiro(OU_SIM_SEED)
        draws = [euler_step(rng, x, h, kappa, mu, sigma) for _ in 1:n]
        @test all(isfinite, draws)
        @test nsigma(mean(draws), expected_mean, sqrt(expected_variance / n)) <= 4
        @test nsigma(
            var(draws),
            expected_variance,
            expected_variance * sqrt(2 / (n - 1)),
        ) <= 4
        # The scheme is defined outside the stability interval for a single step.
        @test isfinite(euler_step(Xoshiro(1), 0.0, 3.0, 1.0, 1.0, 1.0))
    end

    @testset "discrete Euler invariant one-step preservation" begin
        # Starting in the Euler recursion's own invariant law and taking one step
        # must leave that law unchanged. This is the property the whole Euler
        # experiment rests on: the endpoint variance estimates v_EM(h) with
        # sampling error alone, and no burn-in and no horizon are involved.
        kappa, mu, sigma = 1.0, 1.0, 1.0
        n = 40_000
        for h in (0.4, 0.1, 0.025)
            rng = Xoshiro(OU_SIM_SEED)
            sample = sample_euler_stationary_step(rng, n, h, kappa, mu, sigma)
            @test sample isa Vector{Float64}
            @test length(sample) == n
            @test all(isfinite, sample)
            invariant = euler_stationary_variance(kappa, sigma, h)
            @test nsigma(mean(sample), mu, sqrt(invariant / n)) <= 4
            @test nsigma(var(sample), invariant, invariant * sqrt(2 / (n - 1))) <= 4
            # The endpoints exceed the exact stationary variance of the process:
            # the discrete chain is overdispersed at every admissible step.
            @test var(sample) > stationary_variance(kappa, sigma)
        end
        # The sampler applies exactly the recursion `euler_step` implements.
        h = 0.2
        initial_std = sqrt(euler_stationary_variance(1.0, 1.0, h))
        sample = sample_euler_stationary_step(Xoshiro(13), 8, h, 1.0, 1.0, 1.0)
        rng = Xoshiro(13)
        stepwise = Vector{Float64}(undef, 8)
        for i in 1:8
            state = 1.0 + initial_std * randn(rng)
            stepwise[i] = euler_step(rng, state, h, 1.0, 1.0, 1.0)
        end
        @test sample == stepwise
    end

    @testset "positive-count and grid guards" begin
        rng = Xoshiro(1)
        for bad in (0, -1, -100)
            @test_throws ArgumentError sample_exact_terminal(
                rng,
                bad,
                1.0,
                1.0,
                1.0,
                1.0,
                -1.0,
            )
            @test_throws ArgumentError sample_stationary(rng, bad, 1.0, 1.0, 1.0)
            @test_throws ArgumentError simulate_exact_path(
                rng,
                bad,
                0.1,
                1.0,
                1.0,
                1.0,
                -1.0,
            )
            @test_throws ArgumentError simulate_exact_paths(
                rng,
                bad,
                1.0,
                0.1,
                1.0,
                1.0,
                1.0,
                -1.0,
            )
            @test_throws ArgumentError sample_euler_stationary_step(
                rng,
                bad,
                0.1,
                1.0,
                1.0,
                1.0,
            )
        end

        # The horizon must be a whole number of steps. A ratio that is not an
        # integer is rejected by name rather than rounded into a grid nobody
        # asked for.
        @test_throws ArgumentError simulate_exact_paths(
            rng,
            2,
            5.0,
            0.3,
            1.0,
            1.0,
            1.0,
            -1.0,
        )
        @test_throws ArgumentError simulate_exact_paths(
            rng,
            2,
            1.0,
            3.0,
            1.0,
            1.0,
            1.0,
            -1.0,
        )
        # A decimal grid whose ratio is inexact in binary is still accepted: the
        # tolerance exists for exactly that, and 3.0 / 0.1 is 29.999999999999996.
        @test size(simulate_exact_paths(rng, 1, 3.0, 0.1, 1.0, 1.0, 1.0, -1.0), 1) == 31

        # The stationary Euler sampler inherits the stability restriction.
        @test_throws ArgumentError sample_euler_stationary_step(
            rng,
            10,
            2.5,
            1.0,
            1.0,
            1.0,
        )
        # Parameter domains are inherited from the model layer.
        @test_throws ArgumentError sample_stationary(rng, 10, 0.0, 1.0, 1.0)
        @test_throws ArgumentError sample_stationary(rng, 10, 1.0, 1.0, 0.0)
        @test_throws ArgumentError exact_step(rng, NaN, 0.1, 1.0, 1.0, 1.0)
        @test_throws ArgumentError euler_step(rng, 0.0, -0.1, 1.0, 1.0, 1.0)
        @test_throws ArgumentError simulate_exact_path(rng, 10, 0.1, 1.0, Inf, 1.0, -1.0)
    end

    @testset "explicit generators and generic RNG compatibility" begin
        @test Xoshiro(1) isa AbstractRNG
        @test StableRNG(1) isa AbstractRNG
        # Every sampler takes its randomness from the generator it is given. The
        # global stream is advanced between the two calls below, and the results
        # are unchanged; no function in `src/` seeds a generator.
        control = sample_stationary(Xoshiro(9), 16, 1.0, 1.0, 1.0)
        randn(64)
        @test sample_stationary(Xoshiro(9), 16, 1.0, 1.0, 1.0) == control

        # A generic `AbstractRNG` from a different package works throughout.
        @test sample_stationary(StableRNG(4), 32, 1.0, 1.0, 1.0) isa Vector{Float64}
        @test sample_exact_terminal(StableRNG(4), 32, 1.0, 1.0, 1.0, 1.0, -1.0) isa
              Vector{Float64}
        @test simulate_exact_path(StableRNG(4), 32, 0.1, 1.0, 1.0, 1.0, -1.0) isa
              Vector{Float64}
        @test simulate_exact_paths(StableRNG(4), 2, 1.0, 0.1, 1.0, 1.0, 1.0, -1.0) isa
              Matrix{Float64}
        @test sample_euler_stationary_step(StableRNG(4), 32, 0.1, 1.0, 1.0, 1.0) isa
              Vector{Float64}
        @test exact_step(StableRNG(4), 0.5, 0.1, 1.0, 1.0, 1.0) isa Float64
        @test euler_step(StableRNG(4), 0.5, 0.1, 1.0, 1.0, 1.0) isa Float64
    end

    @testset "deterministic same-seed behaviour" begin
        for maker in (Xoshiro, StableRNG)
            @test sample_stationary(maker(21), 64, 1.0, 1.0, 1.0) ==
                  sample_stationary(maker(21), 64, 1.0, 1.0, 1.0)
            @test sample_stationary(maker(21), 64, 1.0, 1.0, 1.0) !=
                  sample_stationary(maker(22), 64, 1.0, 1.0, 1.0)
            @test simulate_exact_path(maker(21), 64, 0.1, 1.0, 1.0, 1.0, -1.0) ==
                  simulate_exact_path(maker(21), 64, 0.1, 1.0, 1.0, 1.0, -1.0)
            @test sample_euler_stationary_step(maker(21), 64, 0.1, 1.0, 1.0, 1.0) ==
                  sample_euler_stationary_step(maker(21), 64, 0.1, 1.0, 1.0, 1.0)
        end
        # Drawing one scalar at a time makes a sample a prefix of a longer one,
        # so enlarging an experiment extends its draws rather than replacing them.
        long = sample_stationary(Xoshiro(31), 64, 1.0, 1.0, 1.0)
        @test sample_stationary(Xoshiro(31), 16, 1.0, 1.0, 1.0) == long[1:16]
    end

    @testset "type stability" begin
        @test @inferred(exact_step(Xoshiro(1), 0.5, 0.1, 1.0, 1.0, 1.0)) isa Float64
        @test @inferred(euler_step(Xoshiro(1), 0.5, 0.1, 1.0, 1.0, 1.0)) isa Float64
        @test @inferred(exact_step(Xoshiro(1), 1, 1 // 10, 1, 1, 1)) isa Float64
        @test @inferred(
            sample_exact_terminal(Xoshiro(1), 4, 1.0, 1.0, 1.0, 1.0, -1.0)
        ) isa Vector{Float64}
        @test @inferred(sample_stationary(Xoshiro(1), 4, 1.0, 1.0, 1.0)) isa
              Vector{Float64}
        @test @inferred(sample_stationary(Xoshiro(1), Int32(4), 1, 1, 1)) isa
              Vector{Float64}
        @test @inferred(simulate_exact_path(Xoshiro(1), 4, 0.1, 1.0, 1.0, 1.0, -1.0)) isa
              Vector{Float64}
        @test @inferred(
            simulate_exact_paths(Xoshiro(1), 2, 1.0, 0.1, 1.0, 1.0, 1.0, -1.0)
        ) isa Matrix{Float64}
        @test @inferred(sample_euler_stationary_step(Xoshiro(1), 4, 0.1, 1.0, 1.0, 1.0)) isa
              Vector{Float64}
    end
end
