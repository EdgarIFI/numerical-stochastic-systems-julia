using Test

using StochasticCaseStudies.OrnsteinUhlenbeck:
    euler_decay,
    euler_stationary_bias,
    euler_stationary_variance,
    exact_autocorrelation,
    exact_transition_coefficients,
    finite_window_iat,
    relaxation_time,
    stationary_standard_deviation,
    stationary_variance,
    transient_mean,
    transient_variance

# The canonical scientific parameters of the case. They are stated here rather
# than imported from the preset table, so that a change to the presets cannot
# quietly change what these tests assert about the mathematics.
const OU_KAPPA = 1.0
const OU_MU = 1.0
const OU_SIGMA = 1.0
const OU_X0 = -1.0

"""
    ou_error_message(f) -> String

Run `f` and return the rendered message of the exception it throws, or the empty
string if it does not throw. Used to check that an error names the input that
violated the contract rather than merely having the right type.
"""
function ou_error_message(f)
    try
        f()
        return ""
    catch err
        return sprint(showerror, err)
    end
end

@testset "Ornstein–Uhlenbeck model" begin
    @testset "parameter and domain guards" begin
        # κ > 0 and σ > 0 are domain restrictions rather than conveniences: the
        # invariant law does not exist without the first, and the process is
        # deterministic without the second.
        for bad in (0.0, -1.0, -0.5, NaN, Inf, -Inf)
            @test_throws ArgumentError relaxation_time(bad)
            @test_throws ArgumentError stationary_variance(bad, OU_SIGMA)
            @test_throws ArgumentError stationary_standard_deviation(bad, OU_SIGMA)
            @test_throws ArgumentError stationary_variance(OU_KAPPA, bad)
            @test_throws ArgumentError stationary_standard_deviation(OU_KAPPA, bad)
            @test_throws ArgumentError transient_mean(1.0, bad, OU_MU, OU_X0)
            @test_throws ArgumentError transient_variance(1.0, bad, OU_SIGMA)
            @test_throws ArgumentError transient_variance(1.0, OU_KAPPA, bad)
            @test_throws ArgumentError exact_autocorrelation(1.0, bad)
            @test_throws ArgumentError finite_window_iat(bad, 0.1, 4)
            @test_throws ArgumentError euler_decay(bad, 0.1)
            @test_throws ArgumentError euler_stationary_variance(bad, OU_SIGMA, 0.1)
            @test_throws ArgumentError euler_stationary_bias(bad, OU_SIGMA, 0.1)
        end

        # Times and lags are nonnegative; steps are strictly positive.
        for bad in (-1.0e-12, -1.0, NaN, Inf, -Inf)
            @test_throws ArgumentError transient_mean(bad, OU_KAPPA, OU_MU, OU_X0)
            @test_throws ArgumentError transient_variance(bad, OU_KAPPA, OU_SIGMA)
            @test_throws ArgumentError exact_autocorrelation(bad, OU_KAPPA)
        end
        for bad in (0.0, -0.1, NaN, Inf, -Inf)
            @test_throws ArgumentError finite_window_iat(OU_KAPPA, bad, 4)
            @test_throws ArgumentError exact_transition_coefficients(
                OU_KAPPA,
                OU_SIGMA,
                bad,
            )
            @test_throws ArgumentError euler_decay(OU_KAPPA, bad)
            @test_throws ArgumentError euler_stationary_variance(OU_KAPPA, OU_SIGMA, bad)
            @test_throws ArgumentError euler_stationary_bias(OU_KAPPA, OU_SIGMA, bad)
        end

        # An unrestricted parameter must still be finite.
        for bad in (NaN, Inf, -Inf)
            @test_throws ArgumentError transient_mean(1.0, OU_KAPPA, bad, OU_X0)
            @test_throws ArgumentError transient_mean(1.0, OU_KAPPA, OU_MU, bad)
        end

        # A negative summation window is refused by name.
        @test_throws ArgumentError finite_window_iat(OU_KAPPA, 0.1, -1)

        message = ou_error_message(() -> relaxation_time(-2.5))
        @test occursin("-2.5", message)
        @test occursin("kappa", message)
    end

    @testset "relaxation time" begin
        @test relaxation_time(OU_KAPPA) == 1.0
        @test relaxation_time(2.0) == 0.5
        @test relaxation_time(0.25) == 4.0
        # An integer rate is admissible and yields a Float64.
        @test relaxation_time(4) === 0.25
    end

    @testset "transient mean" begin
        # At t = 0 the mean is exactly the initial value, and it approaches μ.
        @test transient_mean(0.0, OU_KAPPA, OU_MU, OU_X0) == OU_X0
        @test transient_mean(50.0, OU_KAPPA, OU_MU, OU_X0) ≈ OU_MU atol = 1.0e-15
        # m(t) = μ + (x₀ − μ) e^{−κt}, checked against the closed form directly.
        for t in (0.25, 0.5, 1.0, 2.0, 4.0)
            expected = OU_MU + (OU_X0 - OU_MU) * exp(-OU_KAPPA * t)
            @test transient_mean(t, OU_KAPPA, OU_MU, OU_X0) ≈ expected rtol = 1.0e-14
        end
        # The initial displacement has decayed by 1/e after one relaxation time.
        displacement =
            transient_mean(relaxation_time(OU_KAPPA), OU_KAPPA, OU_MU, OU_X0) - OU_MU
        @test displacement ≈ (OU_X0 - OU_MU) / ℯ rtol = 1.0e-14
        # A process started at its long-run mean has that mean at every time.
        @test transient_mean(3.0, OU_KAPPA, OU_MU, OU_MU) == OU_MU
        # The noise amplitude does not enter the mean, so no σ argument exists.
        @test transient_mean(1.0, 2.0, -3.0, 5.0) ≈ -3.0 + 8.0 * exp(-2.0) rtol = 1.0e-14
    end

    @testset "transient variance" begin
        @test transient_variance(0.0, OU_KAPPA, OU_SIGMA) == 0.0
        # The variance rises monotonically towards the stationary value.
        values = [transient_variance(t, OU_KAPPA, OU_SIGMA) for t in (0.25, 1.0, 4.0)]
        @test issorted(values)
        @test all(values .< stationary_variance(OU_KAPPA, OU_SIGMA))
        @test transient_variance(50.0, OU_KAPPA, OU_SIGMA) ≈
              stationary_variance(OU_KAPPA, OU_SIGMA) rtol = 1.0e-14
        for t in (0.25, 0.5, 1.0, 2.0, 4.0)
            expected = OU_SIGMA^2 * (1 - exp(-2 * OU_KAPPA * t)) / (2 * OU_KAPPA)
            @test transient_variance(t, OU_KAPPA, OU_SIGMA) ≈ expected rtol = 1.0e-12
        end
        # The variance scales with σ² and is independent of μ and x₀.
        @test transient_variance(1.0, OU_KAPPA, 3.0) ≈
              9 * transient_variance(1.0, OU_KAPPA, 1.0) rtol = 1.0e-14
    end

    @testset "stationary moments" begin
        @test stationary_variance(OU_KAPPA, OU_SIGMA) == 0.5
        @test stationary_variance(2.0, 1.0) == 0.25
        @test stationary_variance(1.0, 2.0) == 2.0
        @test stationary_standard_deviation(OU_KAPPA, OU_SIGMA) ≈ sqrt(0.5) rtol = 1.0e-15
        # The two agree with one another over a wide range of scales.
        for kappa in (0.01, 0.5, 1.0, 7.0, 250.0), sigma in (0.001, 1.0, 30.0)
            @test stationary_standard_deviation(kappa, sigma)^2 ≈
                  stationary_variance(kappa, sigma) rtol = 1.0e-14
        end
        # Forming the deviation directly rather than as a square root of the
        # variance keeps an amplitude near the top of the range representable.
        @test isfinite(stationary_standard_deviation(1.0, 1.0e170))
        @test_throws ArgumentError stationary_variance(1.0, 1.0e170)
    end

    @testset "exact autocorrelation" begin
        @test exact_autocorrelation(0.0, OU_KAPPA) == 1.0
        @test exact_autocorrelation(1.0, OU_KAPPA) ≈ exp(-1.0) rtol = 1.0e-15
        # ρ decays monotonically and depends on the lag only through κτ.
        lags = (0.0, 0.1, 0.5, 1.0, 5.0)
        @test issorted([exact_autocorrelation(t, OU_KAPPA) for t in lags]; rev = true)
        for t in lags
            @test exact_autocorrelation(t, 2.0) ≈ exact_autocorrelation(2 * t, 1.0) rtol =
                1.0e-14
        end
        @test exact_autocorrelation(1000.0, OU_KAPPA) ≈ 0.0 atol = 1.0e-15
    end

    @testset "finite-window integrated autocorrelation time" begin
        # An empty window is the independent-sample value.
        @test finite_window_iat(OU_KAPPA, 0.1, 0) == 1.0
        # The sum is checked against the closed-form geometric series, which the
        # implementation deliberately does not use.
        for kappa in (0.5, 1.0, 3.0), h in (0.05, 0.1, 0.5), window in (1, 5, 40, 80)
            q = exp(-kappa * h)
            expected = 1 + 2 * q * (1 - q^window) / (1 - q)
            @test finite_window_iat(kappa, h, window) ≈ expected rtol = 1.0e-12
        end
        # The window is explicit: a longer one gives a larger τ, and the sequence
        # converges to the infinite-window limit from below.
        q = exp(-OU_KAPPA * 0.1)
        limit = (1 + q) / (1 - q)
        windows = [finite_window_iat(OU_KAPPA, 0.1, w) for w in (1, 10, 40, 80)]
        @test issorted(windows)
        @test all(windows .< limit)
        @test finite_window_iat(OU_KAPPA, 0.1, 400) ≈ limit rtol = 1.0e-12
        # The finite-window value at the case's own settings is well below the
        # limit, which is why the comparator must be the truncated sum.
        @test finite_window_iat(OU_KAPPA, 0.1, 40) < 0.99 * limit
    end

    @testset "exact transition coefficients" begin
        coefficients = exact_transition_coefficients(OU_KAPPA, OU_SIGMA, 0.1)
        @test keys(coefficients) == (:decay, :innovation_std)
        @test coefficients.decay ≈ exp(-0.1) rtol = 1.0e-15
        # The conditional variance over a step equals the transient variance at
        # that time, both being the variance accumulated over an interval.
        for h in (0.02, 0.1, 0.4, 3.0)
            innovation = exact_transition_coefficients(OU_KAPPA, OU_SIGMA, h)
            @test innovation.innovation_std^2 ≈
                  transient_variance(h, OU_KAPPA, OU_SIGMA) rtol = 1.0e-13
        end
        # Over a long step the transition forgets its start and reduces to the
        # invariant law.
        far = exact_transition_coefficients(OU_KAPPA, OU_SIGMA, 60.0)
        @test far.decay ≈ 0.0 atol = 1.0e-15
        @test far.innovation_std ≈
              stationary_standard_deviation(OU_KAPPA, OU_SIGMA) rtol = 1.0e-14
    end

    @testset "small-step numerical stability" begin
        # At κ = σ = 1 the variance over a step is v(h) = h − h² + O(h³), so the
        # tolerance `4h` below both admits the true departure from `h` and stays
        # far tighter than the error the naive expression makes. Formed as the
        # subtraction `1 − e^{−2κh}`, the factor loses significant digits once 2κh
        # approaches the resolution of Float64 near one: its relative error is of
        # order 3e-5 at h = 1e-12, of order 3e-2 at h = 1e-15, and the subtraction
        # underflows to exactly zero below about h = 1e-17. The expm1 form used
        # instead is accurate throughout, and the last assertion of each pair
        # would fail outright for the subtraction.
        for h in (1.0e-6, 1.0e-9, 1.0e-12, 1.0e-15, 1.0e-17)
            variance = transient_variance(h, OU_KAPPA, OU_SIGMA)
            @test variance > 0
            @test variance ≈ h rtol = 4 * h + 1.0e-15
            innovation = exact_transition_coefficients(OU_KAPPA, OU_SIGMA, h)
            @test innovation.innovation_std > 0
            @test innovation.innovation_std ≈ sqrt(h) rtol = 4 * h + 1.0e-15
        end
        # The leading correction is resolved as well, not merely swamped: the
        # ratio v(h)/h approaches 1 like 1 − h.
        for h in (1.0e-4, 1.0e-6, 1.0e-8)
            @test transient_variance(h, OU_KAPPA, OU_SIGMA) / h ≈ 1 - h rtol = 1.0e-6
        end
    end

    @testset "Euler decay" begin
        @test euler_decay(OU_KAPPA, 0.1) ≈ 0.9 rtol = 1.0e-15
        @test euler_decay(2.0, 0.25) ≈ 0.5 rtol = 1.0e-15
        # a_h is the linearisation of the exact decay, and agrees with it to
        # first order in κh while differing at second order.
        for h in (1.0e-3, 1.0e-2, 0.1)
            exact = exact_transition_coefficients(OU_KAPPA, OU_SIGMA, h).decay
            @test euler_decay(OU_KAPPA, h) ≈ exact rtol = h
            @test exact - euler_decay(OU_KAPPA, h) ≈ h^2 / 2 rtol = 2 * h
        end
        # One step is defined beyond the stability interval; only the stationary
        # quantities are not.
        @test euler_decay(OU_KAPPA, 3.0) ≈ -2.0 rtol = 1.0e-15
    end

    @testset "Euler stability guard" begin
        # The recursion contracts precisely when |1 − κh| < 1, that is 0 < κh < 2.
        for h in (2.0, 2.5, 10.0)
            @test_throws ArgumentError euler_stationary_variance(OU_KAPPA, OU_SIGMA, h)
            @test_throws ArgumentError euler_stationary_bias(OU_KAPPA, OU_SIGMA, h)
        end
        @test_throws ArgumentError euler_stationary_variance(4.0, OU_SIGMA, 0.5)
        @test_throws ArgumentError euler_stationary_variance(2.0, OU_SIGMA, 1.0)
        # Just inside the interval the quantity exists, and |a_h| < 1 there.
        @test isfinite(euler_stationary_variance(OU_KAPPA, OU_SIGMA, 1.999))
        @test abs(euler_decay(OU_KAPPA, 1.999)) < 1
        message = ou_error_message(() -> euler_stationary_variance(1.0, 1.0, 2.5))
        @test occursin("2.5", message)
    end

    @testset "Euler invariant variance" begin
        # v_EM solves v = a_h² v + σ²h, the fixed point of the recursion.
        for kappa in (0.5, 1.0, 3.0), sigma in (0.5, 1.0, 2.0), h in (0.025, 0.1, 0.4)
            variance = euler_stationary_variance(kappa, sigma, h)
            decay = euler_decay(kappa, h)
            @test variance ≈ decay^2 * variance + sigma^2 * h rtol = 1.0e-12
            @test variance ≈ sigma^2 / (kappa * (2 - kappa * h)) rtol = 1.0e-14
        end
        # It exceeds the exact stationary variance and converges to it as h → 0:
        # the Euler chain is overdispersed at every admissible step.
        exact = stationary_variance(OU_KAPPA, OU_SIGMA)
        grid = [0.4, 0.2, 0.1, 0.05, 0.025]
        discrete = [euler_stationary_variance(OU_KAPPA, OU_SIGMA, h) for h in grid]
        @test all(discrete .> exact)
        @test issorted(discrete; rev = true)
        @test euler_stationary_variance(OU_KAPPA, OU_SIGMA, 1.0e-9) ≈ exact rtol = 1.0e-8
    end

    @testset "Euler stationary bias" begin
        exact = stationary_variance(OU_KAPPA, OU_SIGMA)
        for h in (0.4, 0.2, 0.1, 0.05, 0.025)
            bias = euler_stationary_bias(OU_KAPPA, OU_SIGMA, h)
            # The simplified form is the difference of the two variances; at these
            # steps the subtraction is still accurate enough to compare against.
            @test bias ≈ euler_stationary_variance(OU_KAPPA, OU_SIGMA, h) - exact rtol =
                1.0e-10
            @test bias > 0
        end
        # The simplification earns its place at small steps, where the difference
        # of the two variances cancels: the bias stays accurate and strictly
        # positive far below the point at which the subtraction would lose it.
        for h in (1.0e-9, 1.0e-13, 1.0e-16)
            bias = euler_stationary_bias(OU_KAPPA, OU_SIGMA, h)
            @test bias > 0
            @test bias ≈ OU_SIGMA^2 * h / 4 rtol = 1.0e-8
        end
        # On the tested grid the bias is not a pure power law: its log-log slope
        # exceeds one, which is why no asymptotic order is claimed from it.
        coarse = euler_stationary_bias(OU_KAPPA, OU_SIGMA, 0.4)
        fine = euler_stationary_bias(OU_KAPPA, OU_SIGMA, 0.2)
        @test log(coarse / fine) / log(2.0) > 1
    end

    @testset "type stability" begin
        @test @inferred(relaxation_time(OU_KAPPA)) isa Float64
        @test @inferred(stationary_variance(OU_KAPPA, OU_SIGMA)) isa Float64
        @test @inferred(stationary_standard_deviation(OU_KAPPA, OU_SIGMA)) isa Float64
        @test @inferred(transient_mean(1.0, OU_KAPPA, OU_MU, OU_X0)) isa Float64
        @test @inferred(transient_variance(1.0, OU_KAPPA, OU_SIGMA)) isa Float64
        @test @inferred(exact_autocorrelation(1.0, OU_KAPPA)) isa Float64
        @test @inferred(finite_window_iat(OU_KAPPA, 0.1, 40)) isa Float64
        @test @inferred(euler_decay(OU_KAPPA, 0.1)) isa Float64
        @test @inferred(euler_stationary_variance(OU_KAPPA, OU_SIGMA, 0.1)) isa Float64
        @test @inferred(euler_stationary_bias(OU_KAPPA, OU_SIGMA, 0.1)) isa Float64
        @test @inferred(exact_transition_coefficients(OU_KAPPA, OU_SIGMA, 0.1)) isa
              NamedTuple{(:decay, :innovation_std),Tuple{Float64,Float64}}
        # Integer and rational arguments are converted to the Float64 domain, so
        # the return type does not follow the argument type.
        @test @inferred(relaxation_time(2)) isa Float64
        @test @inferred(stationary_variance(1, 2)) isa Float64
        @test @inferred(transient_mean(1, 1, 1, -1)) isa Float64
        @test @inferred(finite_window_iat(1, 1 // 10, Int32(8))) isa Float64
    end
end
