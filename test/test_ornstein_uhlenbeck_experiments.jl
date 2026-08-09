using Test

using Random: Xoshiro

using StochasticCaseStudies:
    PRESETS, derive_seeds, fit_loglog, preset_parameters, validate_reference_summary
using StochasticCaseStudies.OrnsteinUhlenbeck:
    CASE_SLUG,
    MASTER_SEED,
    OU_PRESETS,
    SEED_SLOTS,
    _fit_positive_empirical_bias,
    euler_stationary_bias,
    euler_stationary_variance,
    ou_parameters,
    reference_parameters,
    reference_values,
    run_case_study,
    run_euler_experiment,
    stationary_variance,
    transient_mean,
    transient_variance

# This file runs the case study at the **smoke preset only**. Neither the figure
# nor the production preset is executed here: they cost orders of magnitude more,
# and the canonical evidence they produce already exists at its fixed repository
# path. Nothing in this file writes a file, creates a directory, renders a figure,
# or loads CairoMakie, and the first testset checks that the run left the case
# directory exactly as it found it — the accepted canonical reference and figure
# byte for byte included.

const OU_ROOT = dirname(@__DIR__)
const OU_CASE_DIRECTORY = joinpath(OU_ROOT, "case-studies", CASE_SLUG)

# The accepted canonical evidence of this case, at the two fixed paths the driver
# writes to under the figure and production presets. Neither preset is run here,
# and the smoke computation must leave both files untouched.
const OU_EVIDENCE_PATHS = (
    joinpath(OU_CASE_DIRECTORY, "reference", "ornstein-uhlenbeck.toml"),
    joinpath(OU_CASE_DIRECTORY, "figures", "ornstein-uhlenbeck.png"),
)

"""
    ou_tree(directory) -> Vector{String}

List every file and subdirectory beneath `directory`, as sorted relative paths.
Used to establish that running the case study leaves the case directory
byte-identical in its contents.
"""
function ou_tree(directory::AbstractString)
    entries = String[]
    for (root, directories, files) in walkdir(directory)
        for name in Iterators.flatten((directories, files))
            push!(entries, relpath(joinpath(root, name), directory))
        end
    end
    return sort!(entries)
end

"""
    ou_evidence_bytes() -> Vector{Vector{UInt8}}

Read the accepted canonical evidence of this case — the production reference
summary and the figure — as raw byte vectors, in the fixed order of
`OU_EVIDENCE_PATHS`.

`run_case_study` computes and returns; it writes nothing at any preset, and
writing is the driver's business. Comparing these bytes before and after the
smoke run establishes that directly, on the two files themselves rather than on a
directory listing, which would report a rewritten file of the same name as no
change at all.
"""
ou_evidence_bytes() = [read(path) for path in OU_EVIDENCE_PATHS]

"""
    ou_carries_unsigned(value) -> Bool

Whether `value`, searched recursively through named tuples and arrays, carries an
unsigned integer anywhere.

The derived substream seeds are `UInt64`, and they must never reach a reference
summary: only the master seed is recorded, as the signed integer provenance seed.
A small `UInt64` would pass the schema validator as an ordinary integer, so it is
looked for explicitly.
"""
function ou_carries_unsigned(value)
    value isa Unsigned && return true
    value isa NamedTuple && return any(ou_carries_unsigned, values(value))
    value isa AbstractArray && return any(ou_carries_unsigned, value)
    return false
end

"""
    ou_to_table(value) -> Any

Convert a named tuple into the `Dict{String,Any}` form `validate_reference_summary`
reads, recursively, leaving scalars and arrays as they are.

This is a test fixture rather than a second implementation of the schema: the
contract is still judged by the shared validator, and this function only puts an
in-memory candidate into the shape a parsed TOML table would have.
"""
function ou_to_table(value::NamedTuple)
    return Dict{String,Any}(String(k) => ou_to_table(v) for (k, v) in pairs(value))
end
ou_to_table(value) = value

# A synthetic provenance table. It is deliberately not the provenance of any real
# run: `capture_provenance` requires a clean working tree and is the driver's
# business, and the all-zero object identifier below is plainly not a commit. It
# exists so that the assembled parameters and values can be judged by the shared
# validator in the shape a committed record would have.
const OU_FIXTURE_PROVENANCE = Dict{String,Any}(
    "case" => CASE_SLUG,
    "generated" => "2026-01-01T00:00:00Z",
    "generated_by" => "case-studies/$CASE_SLUG/driver.jl",
    "git_commit" => "0"^40,
    "julia_version" => string(VERSION),
    "preset" => "smoke",
    "rng" => "Xoshiro",
    "seed" => MASTER_SEED,
)

# The master seeds under which the Euler experiment is exercised, fixed in advance
# of running them and not revised afterwards. They establish that the case accepts
# any valid master seed rather than only the canonical one, and that a realisation
# whose measured bias is not strictly positive throughout the grid still yields a
# complete Euler result. The set is deliberately small, ordinary, and declared
# once: choosing seeds after seeing which of them produce a convenient outcome
# would turn a contract test into a search.
const OU_AUDIT_SEEDS = (0, 1, 2, 3, 4, 42, 2026, 6_060_606)

# A synthetic bias grid and its three cases. The steps are the smoke Euler grid;
# the first bias vector is the exact power law `0.3h`, and the other two differ
# from it only in the last ordinate, which is the one a noisy run can drive to
# zero or below.
const OU_SYNTHETIC_STEPS = [0.4, 0.2, 0.1]
const OU_SYNTHETIC_BIAS_POSITIVE = [0.12, 0.06, 0.03]
const OU_SYNTHETIC_BIAS_ZERO = [0.12, 0.06, 0.0]
const OU_SYNTHETIC_BIAS_NEGATIVE = [0.12, 0.06, -0.001]

const OU_TREE_BEFORE = ou_tree(OU_CASE_DIRECTORY)
const OU_EVIDENCE_BEFORE = ou_evidence_bytes()
const OU_SMOKE = run_case_study(:smoke)
const OU_TREE_AFTER = ou_tree(OU_CASE_DIRECTORY)
const OU_EVIDENCE_AFTER = ou_evidence_bytes()

@testset "Ornstein–Uhlenbeck experiments" begin
    @testset "the smoke run writes nothing" begin
        @test OU_TREE_AFTER == OU_TREE_BEFORE
        # The accepted canonical evidence exists at its two fixed paths, and the
        # smoke computation leaves both byte-identical. This is stronger than
        # asserting that the directories are absent, which they no longer are: a
        # file rewritten in place keeps its name and its position in the tree
        # listing, and only the bytes would show it.
        @test all(isfile, OU_EVIDENCE_PATHS)
        @test OU_EVIDENCE_AFTER == OU_EVIDENCE_BEFORE
        @test !isdir(joinpath(OU_ROOT, "results"))
        # The smoke preset is not eligible to write a reference summary at all;
        # only production is, and it is not run here.
        @test !ou_parameters(:smoke).reference_eligible
        @test !ou_parameters(:figure).reference_eligible
        @test ou_parameters(:production).reference_eligible
    end

    @testset "preset table" begin
        @test OU_PRESETS isa NamedTuple
        @test keys(OU_PRESETS) == PRESETS
        @test length(keys(OU_PRESETS)) == 3

        # All three parameter sets share one concrete `NamedTuple` type, which is
        # what makes the lookup type-stable and a driver's downstream code
        # inferable in the preset it was given.
        declared = unique(collect(typeof(entry) for entry in values(OU_PRESETS)))
        @test length(declared) == 1
        @test isconcretetype(only(declared))

        for preset in PRESETS
            parameters = preset_parameters(OU_PRESETS, preset)
            @test ou_parameters(preset) === parameters
            # A grid whose length varies by preset is a `Vector{Float64}` rather
            # than a tuple, so that the three parameter sets keep one type.
            @test parameters.euler_steps isa Vector{Float64}
            @test parameters.transient_times isa Vector{Float64}
            # The scientific parameters are identical across the presets: a
            # preset changes how much evidence is gathered, never which process
            # is studied.
            @test parameters.kappa == 1.0
            @test parameters.mu == 1.0
            @test parameters.sigma == 1.0
            @test parameters.x0 == -1.0
            @test parameters.transient_times == [0.25, 0.5, 1.0, 2.0, 4.0]
            @test parameters.correlation_step == 0.1
            @test parameters.representative_horizon == 5.0
            @test parameters.representative_step == 0.02
            @test parameters.reference_eligible isa Bool
        end

        # The ratified sample sizes and grids, asserted so that a silent change
        # to any of them is a failing test rather than a quiet change of the
        # evidence a run produces.
        @test OU_PRESETS.smoke.transient_paths == 4_000
        @test OU_PRESETS.smoke.stationary_samples == 4_000
        @test OU_PRESETS.smoke.long_path_length == 20_000
        @test OU_PRESETS.smoke.maxlag == 40
        @test OU_PRESETS.smoke.euler_steps == [0.4, 0.2, 0.1]
        @test OU_PRESETS.smoke.euler_paths == 4_000
        @test OU_PRESETS.smoke.representative_paths == 4
        @test OU_PRESETS.figure.transient_paths == 30_000
        @test OU_PRESETS.figure.stationary_samples == 30_000
        @test OU_PRESETS.figure.long_path_length == 100_000
        @test OU_PRESETS.figure.maxlag == 80
        @test OU_PRESETS.figure.euler_steps == [0.4, 0.2, 0.1, 0.05, 0.025]
        @test OU_PRESETS.figure.euler_paths == 30_000
        @test OU_PRESETS.figure.representative_paths == 12
        @test OU_PRESETS.production.transient_paths == 200_000
        @test OU_PRESETS.production.stationary_samples == 200_000
        @test OU_PRESETS.production.long_path_length == 250_000
        @test OU_PRESETS.production.maxlag == 80
        @test OU_PRESETS.production.euler_steps == [0.4, 0.2, 0.1, 0.05, 0.025]
        @test OU_PRESETS.production.euler_paths == 200_000
        @test OU_PRESETS.production.representative_paths == 12

        @test_throws ArgumentError ou_parameters(:draft)
    end

    @testset "preset lookup is type-stable" begin
        for preset in PRESETS
            @test @inferred(preset_parameters(OU_PRESETS, preset)) isa NamedTuple
            @test isconcretetype(typeof(preset_parameters(OU_PRESETS, preset)))
        end
    end

    @testset "seed derivation" begin
        @test SEED_SLOTS == 9
        @test MASTER_SEED == 6_060_606
        @test 0 <= MASTER_SEED <= typemax(Int64)
        @test CASE_SLUG == "06-ornstein-uhlenbeck"
        seeds = OU_SMOKE.seeds
        @test seeds isa Vector{UInt64}
        @test length(seeds) == SEED_SLOTS
        @test seeds == derive_seeds(MASTER_SEED, SEED_SLOTS)
        # All nine slots are derived under every preset, including the smoke
        # preset whose Euler grid uses only the first three of the five Euler
        # slots. Derivation is prefix-preserving, so slot k holds the same value
        # in every run of the case.
        @test derive_seeds(MASTER_SEED, 4) == seeds[1:4]
        @test derive_seeds(MASTER_SEED, SEED_SLOTS + 3)[1:SEED_SLOTS] == seeds
        # A different master seed gives a different experiment.
        @test derive_seeds(MASTER_SEED + 1, SEED_SLOTS) != seeds
    end

    @testset "result structure" begin
        @test keys(OU_SMOKE) == (
            :preset,
            :parameters,
            :seeds,
            :transient,
            :stationary,
            :correlated,
            :euler,
            :representative,
        )
        @test OU_SMOKE.preset === :smoke
        @test OU_SMOKE.parameters === ou_parameters(:smoke)

        @test keys(OU_SMOKE.transient) == (
            :times,
            :analytic_mean,
            :empirical_mean,
            :mean_sem,
            :mean_nsigma,
            :analytic_variance,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
            :n,
        )
        @test keys(OU_SMOKE.stationary) == (
            :analytic_mean,
            :empirical_mean,
            :mean_sem,
            :mean_nsigma,
            :analytic_variance,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
            :n,
        )
        @test keys(OU_SMOKE.correlated) == (
            :path,
            :lags,
            :acf_empirical,
            :acf_analytic,
            :summary,
            :tau_exact_window,
            :tau_relative_error,
            :acf_rmse,
            :mean_nsigma,
        )
        @test keys(OU_SMOKE.euler) == (
            :steps,
            :analytic_euler_variance,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
            :exact_ou_variance,
            :analytic_bias,
            :empirical_bias,
            :analytic_fit,
            :empirical_fit,
            :n,
        )
        @test keys(OU_SMOKE.representative) == (:times, :paths)
    end

    @testset "transient experiment" begin
        transient = OU_SMOKE.transient
        parameters = OU_SMOKE.parameters
        @test transient.n == parameters.transient_paths
        @test transient.times == parameters.transient_times
        # The result copies the grid rather than aliasing the preset constant.
        @test transient.times !== parameters.transient_times
        count = length(transient.times)
        for field in (
            :analytic_mean,
            :empirical_mean,
            :mean_sem,
            :mean_nsigma,
            :analytic_variance,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
        )
            column = getproperty(transient, field)
            @test column isa Vector{Float64}
            @test length(column) == count
            @test all(isfinite, column)
        end
        # The analytical references are the closed forms, evaluated afresh.
        for (i, t) in enumerate(transient.times)
            @test transient.analytic_mean[i] ==
                  transient_mean(t, parameters.kappa, parameters.mu, parameters.x0)
            @test transient.analytic_variance[i] ==
                  transient_variance(t, parameters.kappa, parameters.sigma)
        end
        # The variance standard error is the exact Gaussian one, formed from the
        # analytical variance and never from the standard error of the mean.
        for i in 1:count
            @test transient.variance_se[i] ≈
                  transient.analytic_variance[i] * sqrt(2 / (transient.n - 1)) rtol =
                1.0e-14
            @test transient.variance_se[i] != transient.mean_sem[i]
        end
        # Four standard errors, the repository-wide threshold.
        @test all(transient.mean_nsigma .<= 4)
        @test all(transient.variance_nsigma .<= 4)
        @test all(transient.mean_sem .> 0)
        @test all(transient.variance_se .> 0)
    end

    @testset "stationary experiment" begin
        stationary = OU_SMOKE.stationary
        parameters = OU_SMOKE.parameters
        @test stationary.n == parameters.stationary_samples
        @test stationary.analytic_mean == parameters.mu
        @test stationary.analytic_variance ==
              stationary_variance(parameters.kappa, parameters.sigma)
        for field in (
            :empirical_mean,
            :mean_sem,
            :mean_nsigma,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
        )
            @test getproperty(stationary, field) isa Float64
            @test isfinite(getproperty(stationary, field))
        end
        @test stationary.variance_se ≈
              stationary.analytic_variance * sqrt(2 / (stationary.n - 1)) rtol = 1.0e-14
        @test stationary.mean_sem > 0
        @test stationary.variance_se > 0
        @test stationary.mean_nsigma <= 4
        @test stationary.variance_nsigma <= 4
    end

    @testset "correlated experiment" begin
        correlated = OU_SMOKE.correlated
        parameters = OU_SMOKE.parameters
        maxlag = parameters.maxlag
        @test correlated.path isa Vector{Float64}
        @test length(correlated.path) == parameters.long_path_length
        @test all(isfinite, correlated.path)
        @test correlated.lags == collect(0:maxlag)
        @test correlated.lags isa Vector{Int}
        @test length(correlated.acf_empirical) == maxlag + 1
        @test length(correlated.acf_analytic) == maxlag + 1
        @test all(isfinite, correlated.acf_empirical)
        @test all(isfinite, correlated.acf_analytic)
        @test correlated.acf_empirical[1] ≈ 1.0 rtol = 1.0e-12
        @test correlated.acf_analytic[1] == 1.0
        # The analytical series is the exact autocorrelation on the observation
        # grid, decaying monotonically.
        @test issorted(correlated.acf_analytic; rev = true)

        summary = correlated.summary
        @test summary.n == parameters.long_path_length
        @test summary.maxlag == maxlag
        # The smoke preset checks structure, finiteness, and the properties an
        # effective sample size must have. It does not impose the production
        # precision contract: a path of 20 000 points is not the evidence that
        # contract is written for.
        @test isfinite(summary.mean)
        @test isfinite(summary.sd)
        @test summary.tau_int > 1
        @test 1 < summary.ess <= summary.n
        @test summary.ess ≈ summary.n / summary.tau_int rtol = 1.0e-12
        @test summary.sem > 0
        @test summary.lower < summary.upper
        # The mean of a correlated series is judged against the correlated
        # standard error, which is larger than the independent one.
        @test summary.sem > summary.sd / sqrt(summary.n)
        @test isfinite(correlated.mean_nsigma)
        @test isfinite(correlated.tau_exact_window)
        @test isfinite(correlated.tau_relative_error)
        @test isfinite(correlated.acf_rmse)
        @test correlated.acf_rmse >= 0
        # The comparator is the finite-window analytical value, summed over the
        # same window, and is therefore below the infinite-window limit.
        q = exp(-parameters.kappa * parameters.correlation_step)
        @test correlated.tau_exact_window > 1
        @test correlated.tau_exact_window < (1 + q) / (1 - q)
    end

    @testset "Euler experiment" begin
        euler = OU_SMOKE.euler
        parameters = OU_SMOKE.parameters
        @test euler.steps == parameters.euler_steps
        @test euler.steps !== parameters.euler_steps
        @test euler.n == parameters.euler_paths
        count = length(euler.steps)
        @test count == 3
        @test euler.exact_ou_variance ==
              stationary_variance(parameters.kappa, parameters.sigma)
        for field in (
            :analytic_euler_variance,
            :empirical_variance,
            :variance_se,
            :variance_nsigma,
            :analytic_bias,
            :empirical_bias,
        )
            column = getproperty(euler, field)
            @test column isa Vector{Float64}
            @test length(column) == count
            @test all(isfinite, column)
        end
        for (i, h) in enumerate(euler.steps)
            # The endpoint variance is judged against the invariant variance of
            # the discrete Euler chain, not against that of the process.
            @test euler.analytic_euler_variance[i] ==
                  euler_stationary_variance(parameters.kappa, parameters.sigma, h)
            @test euler.analytic_bias[i] ==
                  euler_stationary_bias(parameters.kappa, parameters.sigma, h)
            @test euler.variance_se[i] ≈
                  euler.analytic_euler_variance[i] * sqrt(2 / (euler.n - 1)) rtol =
                1.0e-14
            @test euler.empirical_bias[i] ==
                  euler.empirical_variance[i] - euler.exact_ou_variance
            @test euler.analytic_euler_variance[i] > euler.exact_ou_variance
        end
        @test all(euler.variance_nsigma .<= 4)
        @test all(euler.analytic_bias .> 0)
        # The analytical bias decreases with the step; so, at these sample sizes,
        # does the measured one.
        @test issorted(euler.analytic_bias; rev = true)

        # The analytical fit always exists, the analytical bias being strictly
        # positive throughout the admissible interval. The empirical fit is
        # optional under G4B-CORR.1: it exists exactly when every measured bias
        # is strictly positive, and is `nothing` otherwise. Whichever fits are
        # defined return finite diagnostics. The fitted slope of a three-point
        # grid has one residual degree of freedom, so its standard error is a
        # goodness-of-fit statistic and no order of convergence is asserted from
        # it here.
        @test euler.analytic_fit isa NamedTuple
        @test euler.empirical_fit isa NamedTuple || euler.empirical_fit === nothing
        defined_fits = Any[euler.analytic_fit]
        euler.empirical_fit === nothing || push!(defined_fits, euler.empirical_fit)
        for fit in defined_fits
            @test keys(fit) == (:slope, :intercept, :slope_se, :r2, :residuals)
            @test isfinite(fit.slope)
            @test isfinite(fit.intercept)
            @test isfinite(fit.slope_se)
            @test isfinite(fit.r2)
            @test fit.slope_se >= 0
            @test length(fit.residuals) == count
            @test all(isfinite, fit.residuals)
        end
        @test euler.analytic_fit.slope > 0
    end

    @testset "the empirical bias keeps its sign" begin
        # The reported observable is the signed difference between the measured
        # endpoint variance and the exact stationary variance of the process. No
        # absolute value, no clamp, and no floor stands between the two.
        euler = OU_SMOKE.euler
        @test euler.empirical_bias ==
              euler.empirical_variance .- euler.exact_ou_variance
        for i in eachindex(euler.steps)
            @test euler.empirical_bias[i] ===
                  euler.empirical_variance[i] - euler.exact_ou_variance
        end
        # A negative measured variance deviation would produce a negative bias,
        # not its magnitude. Verified on the definition rather than on a
        # realisation, so that the check does not depend on the luck of a seed.
        below = euler.exact_ou_variance - 0.001
        @test below - euler.exact_ou_variance < 0
        @test below - euler.exact_ou_variance != abs(below - euler.exact_ou_variance)
    end

    @testset "the empirical log-log fit is optional" begin
        # A. A strictly positive grid is fitted, and by the published shared
        # estimator rather than by a second implementation of it.
        positive = _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            OU_SYNTHETIC_BIAS_POSITIVE,
        )
        @test positive isa NamedTuple
        @test keys(positive) == (:slope, :intercept, :slope_se, :r2, :residuals)
        @test positive == fit_loglog(OU_SYNTHETIC_STEPS, OU_SYNTHETIC_BIAS_POSITIVE)
        @test isfinite(positive.slope)
        @test isfinite(positive.intercept)
        @test isfinite(positive.slope_se)
        @test isfinite(positive.r2)
        @test all(isfinite, positive.residuals)
        # The synthetic grid is the exact power law 0.3h.
        @test positive.slope ≈ 1.0 atol = 1.0e-12
        @test positive.r2 ≈ 1.0 atol = 1.0e-12

        # B. A zero ordinate leaves the fit undefined. It is reported as absent
        # and is not an error: the simulation that produced it is valid.
        zero_case = _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            OU_SYNTHETIC_BIAS_ZERO,
        )
        @test zero_case === nothing

        # C. So does a negative ordinate — and the point is neither made positive
        # nor removed, which the untouched input vector witnesses. Had the
        # magnitude been taken, the grid would have been strictly positive and a
        # fit would have been returned instead of `nothing`.
        negative_case = _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            OU_SYNTHETIC_BIAS_NEGATIVE,
        )
        @test negative_case === nothing
        @test OU_SYNTHETIC_BIAS_NEGATIVE == [0.12, 0.06, -0.001]
        @test OU_SYNTHETIC_BIAS_ZERO == [0.12, 0.06, 0.0]
        @test _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            abs.(OU_SYNTHETIC_BIAS_NEGATIVE),
        ) isa NamedTuple

        # A non-finite bias is a broken simulation rather than an unlucky one, and
        # remains an error under the existing validation discipline.
        @test_throws ArgumentError _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            [0.12, 0.06, NaN],
        )
        @test_throws ArgumentError _fit_positive_empirical_bias(
            OU_SYNTHETIC_STEPS,
            [0.12, 0.06, Inf],
        )
        # The shared contract is not weakened: a malformed grid still throws.
        @test_throws ArgumentError _fit_positive_empirical_bias([0.4, 0.2], [0.12, 0.06])

        # E. The canonical smoke run remains valid, and its fit — if defined — is
        # finite. No exact random value is asserted.
        smoke_fit = OU_SMOKE.euler.empirical_fit
        @test smoke_fit isa NamedTuple || smoke_fit === nothing
        if smoke_fit !== nothing
            @test isfinite(smoke_fit.slope)
            @test isfinite(smoke_fit.slope_se)
            @test isfinite(smoke_fit.r2)
            @test all(isfinite, smoke_fit.residuals)
        end
    end

    @testset "any valid master seed yields an Euler result" begin
        # F. The predetermined audit seeds, run through the minimum experiment
        # that establishes the contract: the Euler study alone, at the smoke
        # preset, rather than a whole case study each. Every one of them must
        # return a complete Euler result, whether or not its measured biases
        # happen to admit a log-log fit.
        parameters = ou_parameters(:smoke)
        count = length(parameters.euler_steps)
        for seed in OU_AUDIT_SEEDS
            seeds = derive_seeds(seed, SEED_SLOTS)
            euler = run_euler_experiment(seeds[5:(4+count)], parameters)
            @test length(euler.steps) == count
            @test all(isfinite, euler.empirical_variance)
            @test all(isfinite, euler.empirical_bias)
            # The signed definition holds under every seed.
            @test euler.empirical_bias ==
                  euler.empirical_variance .- euler.exact_ou_variance
            @test all(euler.analytic_bias .> 0)
            @test euler.analytic_fit isa NamedTuple
            # Either outcome is a valid statistical realisation.
            @test euler.empirical_fit isa NamedTuple || euler.empirical_fit === nothing
            if euler.empirical_fit === nothing
                @test any(euler.empirical_bias .<= 0)
            else
                @test all(euler.empirical_bias .> 0)
                @test isfinite(euler.empirical_fit.slope)
            end
        end
        # The canonical seed is one of the eight and is not privileged among them.
        @test MASTER_SEED in OU_AUDIT_SEEDS
    end

    @testset "representative paths" begin
        representative = OU_SMOKE.representative
        parameters = OU_SMOKE.parameters
        nsteps =
            round(Int, parameters.representative_horizon / parameters.representative_step)
        @test representative.paths isa Matrix{Float64}
        @test size(representative.paths) == (nsteps + 1, parameters.representative_paths)
        @test representative.times isa Vector{Float64}
        @test length(representative.times) == nsteps + 1
        @test representative.times[1] == 0.0
        @test representative.times[end] ≈ parameters.representative_horizon rtol = 1.0e-12
        @test issorted(representative.times)
        @test all(representative.paths[1, :] .== parameters.x0)
        @test all(isfinite, representative.paths)
    end

    @testset "determinism" begin
        # The whole run is a pure function of the single master seed.
        repeat = run_case_study(:smoke)
        @test repeat.seeds == OU_SMOKE.seeds
        @test repeat.transient.empirical_mean == OU_SMOKE.transient.empirical_mean
        @test repeat.stationary.empirical_variance ==
              OU_SMOKE.stationary.empirical_variance
        @test repeat.correlated.path == OU_SMOKE.correlated.path
        @test repeat.euler.empirical_variance == OU_SMOKE.euler.empirical_variance
        @test repeat.representative.paths == OU_SMOKE.representative.paths
        # A different master seed gives a different run of the same experiment.
        other = run_case_study(:smoke; master_seed = MASTER_SEED + 1)
        @test other.seeds != OU_SMOKE.seeds
        @test other.stationary.empirical_mean != OU_SMOKE.stationary.empirical_mean
        @test other.stationary.analytic_variance == OU_SMOKE.stationary.analytic_variance
        @test_throws ArgumentError run_case_study(:smoke; master_seed = -1)
    end

    @testset "reference parameters" begin
        parameters = reference_parameters(OU_SMOKE)
        @test keys(parameters) == (
            :kappa,
            :mu,
            :sigma,
            :x0,
            :relaxation_time,
            :stationary_variance,
            :transient_times,
            :transient_paths,
            :stationary_samples,
            :long_path_length,
            :correlation_step,
            :maxlag,
            :euler_steps,
            :euler_paths,
            :representative_paths,
            :representative_horizon,
            :representative_step,
        )
        @test parameters.relaxation_time == 1 / OU_SMOKE.parameters.kappa
        @test parameters.stationary_variance ==
              stationary_variance(OU_SMOKE.parameters.kappa, OU_SMOKE.parameters.sigma)
        # The Euler experiment has no horizon: it takes one step from the
        # scheme's own invariant law.
        @test !haskey(parameters, :euler_horizon)
        # The eligibility flag controls the driver and is not a parameter of the
        # process.
        @test !haskey(parameters, :reference_eligible)
        @test parameters.transient_times !== OU_SMOKE.parameters.transient_times
        @test parameters.euler_steps !== OU_SMOKE.parameters.euler_steps
        @test !ou_carries_unsigned(parameters)
    end

    @testset "reference values" begin
        # The canonical smoke run's measured bias is strictly positive throughout
        # its grid, so its empirical fit is defined and the values table can be
        # assembled at all. That is a property of the ratified seed and sample
        # sizes; it is asserted here so that a change to either fails legibly
        # rather than as a refusal further down.
        @test OU_SMOKE.euler.empirical_fit isa NamedTuple
        values_table = reference_values(OU_SMOKE)
        @test keys(values_table) == (
            :transient_mean_t025,
            :transient_variance_t025,
            :transient_mean_t050,
            :transient_variance_t050,
            :transient_mean_t100,
            :transient_variance_t100,
            :transient_mean_t200,
            :transient_variance_t200,
            :transient_mean_t400,
            :transient_variance_t400,
            :stationary_mean,
            :stationary_variance,
            :correlated_mean,
            :euler_variance_h0400,
            :euler_variance_h0200,
            :euler_variance_h0100,
            :euler_fit_slope,
        )
        for (name, entry) in pairs(values_table)
            @test entry isa NamedTuple
            @test haskey(entry, :value)
            @test haskey(entry, :kind)
            @test entry.kind == "estimate"
            @test entry.value isa Float64
            @test isfinite(entry.value)
            # Every result here is an estimate and carries a standard error, and
            # never a confidence bound alongside it.
            @test haskey(entry, :se)
            @test entry.se >= 0
            @test !haskey(entry, :ci_lower)
            @test !haskey(entry, :ci_upper)
            @test !ou_carries_unsigned(entry)
        end

        correlated = values_table.correlated_mean
        for field in (
            :analytic,
            :nsigma,
            :tau_int,
            :tau_exact_window,
            :tau_relative_error,
            :ess,
            :acf_rmse,
            :maxlag,
            :lags,
            :acf_empirical,
            :acf_analytic,
            :n,
        )
            @test haskey(correlated, field)
        end
        @test correlated.lags isa Vector{Int}
        @test correlated.acf_empirical isa Vector{Float64}
        @test correlated.acf_analytic isa Vector{Float64}
        @test length(correlated.lags) == correlated.maxlag + 1

        euler_entry = values_table.euler_variance_h0100
        for field in (
            :analytic_euler_variance,
            :exact_ou_variance,
            :empirical_bias,
            :analytic_bias,
            :nsigma,
            :h,
            :n,
        )
            @test haskey(euler_entry, field)
        end
        @test euler_entry.h == 0.1

        slope = values_table.euler_fit_slope
        for field in (
            :analytic_finite_grid_slope,
            :r2,
            :steps,
            :empirical_biases,
            :analytic_biases,
        )
            @test haskey(slope, field)
        end
        @test slope.value == OU_SMOKE.euler.empirical_fit.slope
        @test slope.se == OU_SMOKE.euler.empirical_fit.slope_se
        @test slope.analytic_finite_grid_slope == OU_SMOKE.euler.analytic_fit.slope
        @test slope.steps == OU_SMOKE.euler.steps
    end

    @testset "a reference summary requires a defined empirical fit" begin
        # G. An otherwise valid result whose empirical fit alone is absent,
        # assembled by ordinary named-tuple composition. Every measured quantity,
        # the signed biases among them, is carried over untouched.
        euler_without_fit = merge(OU_SMOKE.euler, (empirical_fit = nothing,))
        without_fit = merge(OU_SMOKE, (euler = euler_without_fit,))
        @test without_fit.euler.empirical_fit === nothing
        @test keys(without_fit) == keys(OU_SMOKE)
        @test keys(without_fit.euler) == keys(OU_SMOKE.euler)
        @test without_fit.euler.empirical_bias == OU_SMOKE.euler.empirical_bias
        @test without_fit.euler.empirical_variance == OU_SMOKE.euler.empirical_variance
        @test without_fit.euler.analytic_fit == OU_SMOKE.euler.analytic_fit
        @test without_fit.transient === OU_SMOKE.transient
        @test without_fit.correlated === OU_SMOKE.correlated

        # The assembly is refused with an explicit scientific error, and refused
        # before anything could be written. A committed record carries a fitted
        # empirical slope; no analytical substitute, `NaN`, zero, absolute bias,
        # or silent omission stands in for it.
        @test_throws ArgumentError reference_values(without_fit)
        # The parameters table does not depend on the fit and is unaffected: the
        # refusal is specific to the evidence the values table must carry.
        @test reference_parameters(without_fit) == reference_parameters(OU_SMOKE)

        # H. With the fit present the assembly succeeds and stays
        # schema-compatible, and I, it still carries no derived unsigned seed.
        if OU_SMOKE.euler.empirical_fit !== nothing
            with_fit = reference_values(OU_SMOKE)
            @test haskey(with_fit, :euler_fit_slope)
            @test isfinite(with_fit.euler_fit_slope.value)
            @test with_fit.euler_fit_slope.value == OU_SMOKE.euler.empirical_fit.slope
            @test !ou_carries_unsigned(with_fit)
        end

        # J. Neither branch writes a file or creates a directory, and neither
        # touches the accepted canonical evidence at its two fixed paths.
        @test OU_TREE_AFTER == ou_tree(OU_CASE_DIRECTORY)
        @test ou_evidence_bytes() == OU_EVIDENCE_BEFORE
        @test !isdir(joinpath(OU_ROOT, "results"))
    end

    @testset "the assembled record satisfies schema version 1" begin
        # The candidate is judged by the shared validator, in the shape a parsed
        # committed record would have. Nothing is written: the validator is pure,
        # and no source path is supplied, so the smoke preset is admissible here
        # as a development record while remaining forbidden in a committed one.
        record = Dict{String,Any}(
            "schema_version" => 1,
            "provenance" => OU_FIXTURE_PROVENANCE,
            "parameters" => ou_to_table(reference_parameters(OU_SMOKE)),
            "values" => ou_to_table(reference_values(OU_SMOKE)),
        )
        @test validate_reference_summary(record) == String[]
        @test OU_TREE_AFTER == ou_tree(OU_CASE_DIRECTORY)
        # A committed record may not carry the smoke preset, whatever else is
        # right about it. The production branch of the driver is what writes one,
        # and it is not exercised here.
        committed = validate_reference_summary(
            record;
            source_path = "case-studies/$CASE_SLUG/reference/ornstein-uhlenbeck.toml",
        )
        @test any(problem -> occursin("smoke", problem), committed)
    end
end
