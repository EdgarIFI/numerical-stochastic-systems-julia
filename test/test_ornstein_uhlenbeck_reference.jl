using Test
using TOML

using StochasticCaseStudies:
    integrated_autocorrelation_time,
    nsigma,
    relative_error,
    rmse,
    validate_reference_summary
using StochasticCaseStudies.OrnsteinUhlenbeck:
    CASE_SLUG,
    MASTER_SEED,
    euler_stationary_bias,
    euler_stationary_variance,
    exact_autocorrelation,
    finite_window_iat,
    ou_parameters,
    relaxation_time,
    stationary_variance,
    transient_mean,
    transient_variance

# This file validates the **persisted production reference** of CS-06: the record
# that already exists at the canonical repository path, not a record recomputed
# here. Nothing in it runs a simulation, at any preset; nothing renders a figure;
# nothing writes, creates, or removes anything. The production experiment behind
# the record draws 200 000 samples per ensemble and is not repeated in a test.
#
# What is protected is the **scientific contract** of the record, and not its byte
# serialisation. The SHA-256 digests and the byte lengths of the canonical
# reference and figure are governance identities, recorded in
# ../docs/decisions.md, and no artefact hash appears here as a runtime assertion:
# a test that pinned a digest would fail on any re-derivation of an equally valid
# record while saying nothing about whether its numbers are right.
#
# What is asserted instead is what a reader would otherwise have to redo by hand.
#
#   * the shared schema validator accepts the record at its canonical logical
#     path, with no problems at all;
#   * the provenance identifies the case, the preset, the generator, the master
#     seed, the driver, and — exactly — the Git commit of the accepted source
#     baseline, which is the semantic link between the evidence and the code that
#     produced it;
#   * the recorded parameters are the resolved production parameters the
#     implementation itself declares;
#   * every recorded analytical reference is recomputed here from the accepted
#     model functions and must agree to floating-point tolerance;
#   * every recorded discrepancy in standard errors is recomputed from the
#     record's own value, reference, and standard error, and must satisfy the
#     ratified four-standard-error criterion;
#   * the correlated, Euler, and fit contracts hold with the ratified thresholds.
#
# **No stochastic measured value is hard-coded.** No Monte Carlo mean, variance,
# standard error, autocorrelation, integrated autocorrelation time, effective
# sample size, or fitted slope appears here as a literal. Each is read from the
# record and judged against a quantity computed from the analytical model, so a
# re-derivation of the evidence under the ratified parameters is judged by the
# same contract rather than against the digits of one particular run.

const OU_REF_ROOT = dirname(@__DIR__)

# The canonical logical paths, repository-relative and with forward slashes on
# every platform. The reference path is the value the schema validator is given,
# because it is what the committed-location rules are written against; the
# filesystem paths below are derived from them rather than stated separately, so
# that the two cannot drift apart.
const OU_REF_LOGICAL_PATH = "case-studies/06-ornstein-uhlenbeck/reference/ornstein-uhlenbeck.toml"
const OU_REF_FIGURE_LOGICAL_PATH = "case-studies/06-ornstein-uhlenbeck/figures/ornstein-uhlenbeck.png"

const OU_REF_PATH = joinpath(OU_REF_ROOT, split(OU_REF_LOGICAL_PATH, '/')...)
const OU_REF_FIGURE_PATH =
    joinpath(OU_REF_ROOT, split(OU_REF_FIGURE_LOGICAL_PATH, '/')...)

# The commit of the accepted source baseline from which the canonical reference
# was produced. It is hard-coded deliberately, and it is the one identity in this
# file that is: the recorded commit alone identifies the code and the committed
# manifest, so a record whose provenance names a different commit is evidence for
# a different baseline whatever else is right about it.
const OU_REF_COMMIT = "3358fe8706866cd952cd80005dec1ee5b21a7710"
const OU_REF_DRIVER = "case-studies/06-ornstein-uhlenbeck/driver.jl"

# The eight bytes every PNG begins with, per the format's own specification. The
# figure is checked for structural presence and for this signature alone. Its
# dimensions are not asserted, its pixels are not compared, and it is not decoded:
# figures are validated through the numerical series behind them, which is exactly
# what the rest of this file does.
const OU_REF_PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

# Numerical acceptance tolerances for recomputed **derived identities** — an
# analytical reference, an n-sigma discrepancy, a relative error, a root mean
# squared difference. Each recomputation repeats an arithmetic the record already
# performed, so agreement is expected to the last few bits; these are internal
# numerical tolerances and are not scientific ones.
const OU_REF_RTOL = 1.0e-12
const OU_REF_ATOL = 1.0e-12

# The ratified scientific criteria. Four standard errors is the repository-wide
# threshold of ../docs/methods/error-analysis.md; the remaining four are the
# production acceptance criteria of the case.
const OU_REF_NSIGMA_LIMIT = 4
const OU_REF_IAT_TOLERANCE = 0.10
const OU_REF_ACF_RMSE_TOLERANCE = 0.015
const OU_REF_SLOPE_TOLERANCE = 0.20
const OU_REF_R2_FLOOR = 0.95

const OU_REF_RECORD = TOML.parsefile(OU_REF_PATH)
const OU_REF_PROVENANCE = OU_REF_RECORD["provenance"]
const OU_REF_PARAMETERS = OU_REF_RECORD["parameters"]
const OU_REF_VALUES = OU_REF_RECORD["values"]

# The resolved production parameter set, from the implementation's own resolver.
# The recorded parameters are compared against it rather than against a second
# copy of the same literals, so that a change to the production preset is a
# failure of this file rather than a silent divergence between the preset and the
# evidence.
const OU_REF_PRODUCTION = ou_parameters(:production)

# The complete expected key set of the `[values]` tables, sorted. There are
# **nineteen**: ten transient results at five times, two stationary results, one
# correlated result, five Euler endpoint variances, and one Euler fit. Asserting
# the whole set is what makes a missing table a legible failure rather than a
# check that quietly has nothing to run over.
const OU_REF_VALUE_KEYS = [
    "correlated_mean",
    "euler_fit_slope",
    "euler_variance_h0025",
    "euler_variance_h0050",
    "euler_variance_h0100",
    "euler_variance_h0200",
    "euler_variance_h0400",
    "stationary_mean",
    "stationary_variance",
    "transient_mean_t025",
    "transient_mean_t050",
    "transient_mean_t100",
    "transient_mean_t200",
    "transient_mean_t400",
    "transient_variance_t025",
    "transient_variance_t050",
    "transient_variance_t100",
    "transient_variance_t200",
    "transient_variance_t400",
]

# The transient grid, as the pairs of keys that encode each time. The tag is the
# time scaled by 100 in three digits, so the correspondence between a key and the
# time it reports is itself part of what is checked.
const OU_REF_TRANSIENT_GRID = [
    (0.25, "transient_mean_t025", "transient_variance_t025"),
    (0.5, "transient_mean_t050", "transient_variance_t050"),
    (1.0, "transient_mean_t100", "transient_variance_t100"),
    (2.0, "transient_mean_t200", "transient_variance_t200"),
    (4.0, "transient_mean_t400", "transient_variance_t400"),
]

# The five ratified Euler steps, in the order of the grid, with the keys that
# encode them at a factor of 1000 in four digits.
const OU_REF_EULER_STEPS = [0.4, 0.2, 0.1, 0.05, 0.025]
const OU_REF_EULER_KEYS = [
    "euler_variance_h0400",
    "euler_variance_h0200",
    "euler_variance_h0100",
    "euler_variance_h0050",
    "euler_variance_h0025",
]

# Every values table for which the accepted architecture defines an n-sigma
# comparison: the ten transient results, the two stationary results, the
# correlated mean, and the five Euler endpoint variances. `euler_fit_slope` is
# deliberately absent — a fitted slope is compared against the analytical
# finite-grid slope by an absolute discrepancy under G4A-D.10, not by a number of
# standard errors — so the criterion is applied where it is defined and nowhere
# else.
const OU_REF_NSIGMA_KEYS = sort!(filter(!isequal("euler_fit_slope"), OU_REF_VALUE_KEYS))

# Forms in which a machine-local absolute path reaches a committed record. The
# shared validator already checks the fields whose names denote a path; this is
# the broader net cast over every other string the record carries.
#
# The two groups are separate because a backslash is awkward inside a regular
# expression literal and needs none: a Windows separator anywhere in a string is
# rejected outright, which covers `C:\...` and `\Users\...` alike, and the
# patterns then handle only the forward-slash forms.
const OU_REF_LOCAL_PATH_SUBSTRINGS = ("\\", "/Users/", "/home/")
const OU_REF_LOCAL_PATH_PATTERNS = (
    r"^[A-Za-z]:/",     # a drive prefix in forward-slash form, as in C:/
    r"^/",              # a leading absolute POSIX path
)

"""
    ou_ref_reference_field(name) -> String

The name of the analytical reference field against which the entry `name` records
its discrepancy in standard errors.

An Euler endpoint variance is judged against the invariant variance of the
**discrete Euler chain**, which is what that experiment measures; every other
entry is judged against the closed form of the process. The two are different
quantities and the record names them differently, so the distinction is made here
rather than assumed away.
"""
ou_ref_reference_field(name::AbstractString) =
    startswith(name, "euler_variance_h") ? "analytic_euler_variance" : "analytic"

"""
    ou_ref_strings(value, found = String[]) -> Vector{String}

Collect every string the parsed record carries, recursively, keys included.

The traversal is exhaustive rather than field-directed, because the leakage this
guards against is by definition a string in a field nobody thought to check.
"""
function ou_ref_strings(value, found::Vector{String} = String[])
    if value isa AbstractString
        push!(found, String(value))
    elseif value isa AbstractDict
        for (key, child) in value
            push!(found, string(key))
            ou_ref_strings(child, found)
        end
    elseif value isa AbstractArray
        for child in value
            ou_ref_strings(child, found)
        end
    end
    return found
end

"""
    ou_ref_leaks_local_path(text) -> Bool

Whether `text` carries a machine-local absolute path in an obvious form.

The detector is deliberately narrow and lexical. It refuses a drive prefix, a
Windows separator, a leading POSIX separator, and the two commonest home-directory
roots; it consults no filesystem and decodes nothing. A repository-relative
logical path such as the recorded driver is not a leak and must not be reported as
one, which the tests below check in both directions.
"""
ou_ref_leaks_local_path(text::AbstractString) =
    any(fragment -> occursin(fragment, text), OU_REF_LOCAL_PATH_SUBSTRINGS) ||
    any(pattern -> occursin(pattern, text), OU_REF_LOCAL_PATH_PATTERNS)

@testset "Ornstein–Uhlenbeck production reference" begin
    @testset "the record is where it belongs and satisfies the shared schema" begin
        @test isfile(OU_REF_PATH)
        @test OU_REF_LOGICAL_PATH ==
              "case-studies/$CASE_SLUG/reference/ornstein-uhlenbeck.toml"
        # The whole schema contract is owned by the shared validator, which is
        # called here at the canonical logical path so that the committed-location
        # rules apply as well. It is not reimplemented, and nothing below repeats
        # a rule it already enforces.
        @test validate_reference_summary(
            OU_REF_RECORD;
            source_path = OU_REF_LOGICAL_PATH,
        ) == String[]
        @test OU_REF_RECORD["schema_version"] == 1
        @test sort(collect(keys(OU_REF_RECORD))) ==
              ["parameters", "provenance", "schema_version", "values"]
    end

    @testset "provenance identifies the accepted source baseline" begin
        @test OU_REF_PROVENANCE["case"] == "06-ornstein-uhlenbeck"
        @test OU_REF_PROVENANCE["case"] == CASE_SLUG
        @test OU_REF_PROVENANCE["preset"] == "production"
        @test OU_REF_PROVENANCE["rng"] == "Xoshiro"
        @test OU_REF_PROVENANCE["seed"] == 6_060_606
        @test OU_REF_PROVENANCE["seed"] == MASTER_SEED
        @test OU_REF_PROVENANCE["generated_by"] == OU_REF_DRIVER
        # The exact commit of the accepted source baseline. This is the semantic
        # link between the evidence and the code and manifest that produced it,
        # and it is the reason no artefact digest needs to be asserted here.
        @test OU_REF_PROVENANCE["git_commit"] == OU_REF_COMMIT

        # The remaining provenance is machine context recorded for a reader, not
        # part of the scientific contract. Its shape is checked; its values are
        # not required of the machine running these tests, which may be any
        # supported platform on any supported Julia.
        @test VersionNumber(OU_REF_PROVENANCE["julia_version"]) isa VersionNumber
        @test OU_REF_PROVENANCE["os"] isa String && !isempty(OU_REF_PROVENANCE["os"])
        @test OU_REF_PROVENANCE["threads"] isa Integer
        @test OU_REF_PROVENANCE["threads"] >= 1
        @test OU_REF_PROVENANCE["generated"] isa String
    end

    @testset "the recorded parameters are the resolved production parameters" begin
        @test sort(collect(keys(OU_REF_PARAMETERS))) == [
            "correlation_step",
            "euler_paths",
            "euler_steps",
            "kappa",
            "long_path_length",
            "maxlag",
            "mu",
            "relaxation_time",
            "representative_horizon",
            "representative_paths",
            "representative_step",
            "sigma",
            "stationary_samples",
            "stationary_variance",
            "transient_paths",
            "transient_times",
            "x0",
        ]

        # The process itself, and the scale of the evidence gathered about it,
        # compared against the implementation's own production resolver rather
        # than against a second copy of the same literals.
        for name in (
            "kappa",
            "mu",
            "sigma",
            "x0",
            "transient_times",
            "transient_paths",
            "stationary_samples",
            "long_path_length",
            "correlation_step",
            "maxlag",
            "euler_steps",
            "euler_paths",
            "representative_paths",
            "representative_horizon",
            "representative_step",
        )
            @test OU_REF_PARAMETERS[name] == getproperty(OU_REF_PRODUCTION, Symbol(name))
        end

        # The two derived scales a reader needs in order to interpret the rest.
        @test OU_REF_PARAMETERS["relaxation_time"] ≈
              relaxation_time(OU_REF_PARAMETERS["kappa"]) rtol = OU_REF_RTOL
        @test OU_REF_PARAMETERS["stationary_variance"] ≈ stationary_variance(
            OU_REF_PARAMETERS["kappa"],
            OU_REF_PARAMETERS["sigma"],
        ) rtol = OU_REF_RTOL

        # The Euler experiment takes one step from the scheme's own invariant law,
        # so it has no horizon, and there is no field for one.
        @test !haskey(OU_REF_PARAMETERS, "euler_horizon")
        # Reference eligibility controls the driver and is not a property of the
        # process, so it is not a persisted scientific parameter.
        @test !haskey(OU_REF_PARAMETERS, "reference_eligible")

        @test OU_REF_PARAMETERS["euler_steps"] == OU_REF_EULER_STEPS
        @test OU_REF_PARAMETERS["transient_times"] ==
              [time for (time, _, _) in OU_REF_TRANSIENT_GRID]
    end

    @testset "the nineteen values tables are all present" begin
        @test sort(collect(keys(OU_REF_VALUES))) == OU_REF_VALUE_KEYS
        @test length(OU_REF_VALUE_KEYS) == 19
        # Ten transient, two stationary, one correlated, five Euler variances, one
        # Euler fit.
        @test count(startswith("transient_"), OU_REF_VALUE_KEYS) == 10
        @test count(startswith("stationary_"), OU_REF_VALUE_KEYS) == 2
        @test count(startswith("correlated_"), OU_REF_VALUE_KEYS) == 1
        @test count(startswith("euler_variance_h"), OU_REF_VALUE_KEYS) == 5
        @test count(isequal("euler_fit_slope"), OU_REF_VALUE_KEYS) == 1

        for name in OU_REF_VALUE_KEYS
            entry = OU_REF_VALUES[name]
            @test entry isa AbstractDict
            @test entry["kind"] == "estimate"
            @test entry["value"] isa Float64
            @test isfinite(entry["value"])
            @test entry["se"] isa Float64
            @test entry["se"] > 0
            @test !haskey(entry, "ci_lower")
            @test !haskey(entry, "ci_upper")
        end
    end

    @testset "four standard errors, where an n-sigma comparison is defined" begin
        # The criterion is applied to the entries for which the architecture
        # defines an n-sigma comparison, and to those alone. The fitted slope is
        # judged by an absolute discrepancy instead, further below.
        carrying = sort([
            name for name in OU_REF_VALUE_KEYS if
            haskey(OU_REF_VALUES[name], "nsigma")
        ])
        @test carrying == OU_REF_NSIGMA_KEYS
        @test length(carrying) == 18
        @test !haskey(OU_REF_VALUES["euler_fit_slope"], "nsigma")

        for name in carrying
            entry = OU_REF_VALUES[name]
            reference = entry[ou_ref_reference_field(name)]
            @test entry["nsigma"] <= OU_REF_NSIGMA_LIMIT
            # The recorded discrepancy is the one the shared helper forms from the
            # record's own value, reference, and standard error. A record whose
            # nsigma disagreed with its own three fields would be internally
            # inconsistent whatever its magnitude.
            @test entry["nsigma"] ≈ nsigma(entry["value"], reference, entry["se"]) rtol =
                OU_REF_RTOL atol = OU_REF_ATOL
        end
    end

    @testset "transient evidence against the closed forms" begin
        kappa = OU_REF_PARAMETERS["kappa"]
        mu = OU_REF_PARAMETERS["mu"]
        sigma = OU_REF_PARAMETERS["sigma"]
        x0 = OU_REF_PARAMETERS["x0"]
        n = OU_REF_PARAMETERS["transient_paths"]

        for (time, mean_key, variance_key) in OU_REF_TRANSIENT_GRID
            mean_entry = OU_REF_VALUES[mean_key]
            variance_entry = OU_REF_VALUES[variance_key]

            # The key encodes the time it reports, and the entry records it.
            @test mean_entry["t"] == time
            @test variance_entry["t"] == time
            @test mean_entry["n"] == n
            @test variance_entry["n"] == n

            # The recorded analytical references, recomputed here from the
            # accepted model functions at the recorded times.
            @test mean_entry["analytic"] ≈ transient_mean(time, kappa, mu, x0) rtol =
                OU_REF_RTOL atol = OU_REF_ATOL
            @test variance_entry["analytic"] ≈ transient_variance(time, kappa, sigma) rtol =
                OU_REF_RTOL atol = OU_REF_ATOL

            # The variance is judged against the exact Gaussian standard error of
            # a sample variance, never against the standard error of a mean.
            @test variance_entry["se"] ≈
                  variance_entry["analytic"] * sqrt(2 / (n - 1)) rtol = OU_REF_RTOL
            @test variance_entry["se"] != mean_entry["se"]
        end

        # The transient variance grows monotonically towards the stationary value
        # and never reaches it, which the recorded references must reflect.
        analytic_variances =
            [OU_REF_VALUES[key]["analytic"] for (_, _, key) in OU_REF_TRANSIENT_GRID]
        @test issorted(analytic_variances)
        @test all(<(stationary_variance(kappa, sigma)), analytic_variances)
    end

    @testset "stationary evidence against the invariant law" begin
        kappa = OU_REF_PARAMETERS["kappa"]
        mu = OU_REF_PARAMETERS["mu"]
        sigma = OU_REF_PARAMETERS["sigma"]
        n = OU_REF_PARAMETERS["stationary_samples"]

        mean_entry = OU_REF_VALUES["stationary_mean"]
        variance_entry = OU_REF_VALUES["stationary_variance"]

        @test mean_entry["n"] == n
        @test variance_entry["n"] == n
        # The invariant law is Normal(mu, sigma^2 / (2 kappa)), exactly.
        @test mean_entry["analytic"] == mu
        @test variance_entry["analytic"] ≈ sigma^2 / (2 * kappa) rtol = OU_REF_RTOL
        @test variance_entry["analytic"] ≈ stationary_variance(kappa, sigma) rtol =
            OU_REF_RTOL
        @test variance_entry["se"] ≈ variance_entry["analytic"] * sqrt(2 / (n - 1)) rtol =
            OU_REF_RTOL
        # The stationary variance is also recorded among the parameters, as a
        # derived scale, and the two statements of it must agree.
        @test variance_entry["analytic"] ≈ OU_REF_PARAMETERS["stationary_variance"] rtol =
            OU_REF_RTOL
    end

    @testset "correlated evidence, on the finite-window convention" begin
        kappa = OU_REF_PARAMETERS["kappa"]
        mu = OU_REF_PARAMETERS["mu"]
        step = OU_REF_PARAMETERS["correlation_step"]
        maxlag = OU_REF_PARAMETERS["maxlag"]

        entry = OU_REF_VALUES["correlated_mean"]
        lags = entry["lags"]
        empirical = entry["acf_empirical"]
        analytic = entry["acf_analytic"]

        @test entry["n"] == OU_REF_PARAMETERS["long_path_length"]
        @test entry["maxlag"] == maxlag
        @test entry["analytic"] == mu
        @test length(lags) == maxlag + 1
        @test length(empirical) == maxlag + 1
        @test length(analytic) == maxlag + 1
        @test lags == collect(0:maxlag)

        # The analytical series is the exact stationary autocorrelation on the
        # observation grid: rho(k h) = exp(-kappa k h).
        for (i, lag) in enumerate(lags)
            @test analytic[i] ≈ exp(-kappa * (lag * step)) rtol = OU_REF_RTOL atol =
                OU_REF_ATOL
            @test analytic[i] ≈ exact_autocorrelation(lag * step, kappa) rtol =
                OU_REF_RTOL atol = OU_REF_ATOL
        end
        @test analytic[1] == 1.0
        @test issorted(analytic; rev = true)

        # The comparator is the analytical integrated autocorrelation time summed
        # over the **same** finite window, obtained through the same shared
        # estimator the measurement used. Comparing against the infinite-window
        # limit would charge the deliberate truncation of the sum to the estimate,
        # and the record must be on the truncated convention: the recorded
        # comparator lies strictly below that limit.
        @test entry["tau_exact_window"] ≈
              integrated_autocorrelation_time(analytic; maxlag = maxlag) rtol = OU_REF_RTOL
        @test entry["tau_exact_window"] ≈ finite_window_iat(kappa, step, maxlag) rtol =
            OU_REF_RTOL
        decay = exp(-kappa * step)
        @test entry["tau_exact_window"] < (1 + decay) / (1 - decay)
        @test entry["tau_exact_window"] > 1

        # The measured integrated autocorrelation time agrees with that
        # comparator to within the ratified production tolerance, and the recorded
        # relative error is the one the shared helper forms from the two.
        @test entry["tau_relative_error"] <= OU_REF_IAT_TOLERANCE
        @test entry["tau_relative_error"] ≈
              relative_error(entry["tau_int"], entry["tau_exact_window"]) rtol =
            OU_REF_RTOL atol = OU_REF_ATOL
        @test entry["tau_int"] > 1

        # The effective sample size is the raw count divided by the measured
        # integrated autocorrelation time, and a long correlated path carries far
        # less information about its mean than its length suggests.
        @test entry["ess"] ≈ entry["n"] / entry["tau_int"] rtol = OU_REF_RTOL
        @test 1 < entry["ess"] <= entry["n"]

        # The measured autocorrelation series agrees with the exact one over the
        # window, within the ratified production tolerance, and the recorded root
        # mean squared difference is the one the shared helper forms from the two
        # recorded series.
        @test entry["acf_rmse"] <= OU_REF_ACF_RMSE_TOLERANCE
        @test entry["acf_rmse"] ≈ rmse(empirical, analytic) rtol = OU_REF_RTOL atol =
            OU_REF_ATOL

        # The mean of a correlated series is judged against the
        # autocorrelation-corrected standard error, which exceeds the independent
        # one by a factor of about the square root of the correlation time.
        @test entry["se"] > 0
        @test entry["nsigma"] <= OU_REF_NSIGMA_LIMIT
    end

    @testset "the Euler grid, five steps, signed biases" begin
        kappa = OU_REF_PARAMETERS["kappa"]
        sigma = OU_REF_PARAMETERS["sigma"]
        n = OU_REF_PARAMETERS["euler_paths"]
        exact_variance = stationary_variance(kappa, sigma)

        @test length(OU_REF_EULER_KEYS) == 5
        @test length(OU_REF_EULER_STEPS) == 5

        for (i, key) in enumerate(OU_REF_EULER_KEYS)
            step = OU_REF_EULER_STEPS[i]
            entry = OU_REF_VALUES[key]

            @test entry["h"] == step
            @test entry["n"] == n

            # The invariant variance of the discrete Euler chain, which is what
            # this experiment measures, and the exact stationary variance of the
            # process, which is what the bias is taken against.
            @test entry["analytic_euler_variance"] ≈
                  euler_stationary_variance(kappa, sigma, step) rtol = OU_REF_RTOL
            @test entry["exact_ou_variance"] ≈ exact_variance rtol = OU_REF_RTOL
            @test entry["analytic_euler_variance"] > entry["exact_ou_variance"]

            # The analytical finite-step bias, and the empirical one, which is the
            # **signed** difference between the measured endpoint variance and the
            # exact stationary variance. No absolute value stands between them.
            @test entry["analytic_bias"] ≈ euler_stationary_bias(kappa, sigma, step) rtol =
                OU_REF_RTOL atol = OU_REF_ATOL
            @test entry["empirical_bias"] ≈ entry["value"] - entry["exact_ou_variance"] rtol =
                OU_REF_RTOL atol = OU_REF_ATOL

            # The endpoint variance is judged against the Euler chain's own
            # invariant variance, with the exact Gaussian standard error of a
            # sample variance.
            @test entry["se"] ≈
                  entry["analytic_euler_variance"] * sqrt(2 / (n - 1)) rtol = OU_REF_RTOL
            @test entry["nsigma"] ≈ nsigma(
                entry["value"],
                entry["analytic_euler_variance"],
                entry["se"],
            ) rtol = OU_REF_RTOL atol = OU_REF_ATOL
            @test entry["nsigma"] <= OU_REF_NSIGMA_LIMIT
        end

        # The Euler chain is overdispersed throughout the tested grid, and the
        # analytical bias decreases as the step is refined.
        analytic_biases = [OU_REF_VALUES[key]["analytic_bias"] for key in OU_REF_EULER_KEYS]
        @test all(>(0), analytic_biases)
        @test issorted(analytic_biases; rev = true)
    end

    @testset "the Euler log-log fit on the tested grid" begin
        entry = OU_REF_VALUES["euler_fit_slope"]
        for field in (
            "analytic_finite_grid_slope",
            "r2",
            "steps",
            "empirical_biases",
            "analytic_biases",
        )
            @test haskey(entry, field)
        end

        @test entry["steps"] == OU_REF_EULER_STEPS
        @test length(entry["steps"]) == 5
        @test length(entry["empirical_biases"]) == 5
        @test length(entry["analytic_biases"]) == 5

        # The fit's own bias arrays are the per-step recorded evidence, in the
        # order of the grid. Two records of one measurement that disagreed would
        # leave a reader with no way to tell which was meant.
        for (i, key) in enumerate(OU_REF_EULER_KEYS)
            @test entry["empirical_biases"][i] ≈
                  OU_REF_VALUES[key]["empirical_bias"] rtol = OU_REF_RTOL atol =
                OU_REF_ATOL
            @test entry["analytic_biases"][i] ≈ OU_REF_VALUES[key]["analytic_bias"] rtol =
                OU_REF_RTOL atol = OU_REF_ATOL
        end

        # The ratified full-grid acceptance criteria. The fitted slopes describe
        # the grid actually tested; no asymptotic order is asserted here or
        # anywhere else in this case.
        @test abs(entry["value"] - entry["analytic_finite_grid_slope"]) <=
              OU_REF_SLOPE_TOLERANCE
        @test entry["r2"] >= OU_REF_R2_FLOOR
        @test entry["r2"] <= 1
        @test entry["se"] > 0
    end

    @testset "no machine-local path reaches the record" begin
        # The detector recognises the forms it is written for, and does not
        # recognise a legitimate repository-relative logical path. Both directions
        # are checked, so that the traversal below cannot pass by being blind.
        for leaked in (
            "C:\\Users\\someone\\repo\\reference.toml",
            "C:/Users/someone/repo/reference.toml",
            "/Users/someone/repo/reference.toml",
            "/home/someone/repo/reference.toml",
            "\\Users\\someone\\repo",
            "/var/tmp/reference.toml",
        )
            @test ou_ref_leaks_local_path(leaked)
        end
        @test !ou_ref_leaks_local_path(OU_REF_DRIVER)
        @test !ou_ref_leaks_local_path(OU_REF_LOGICAL_PATH)

        strings = ou_ref_strings(OU_REF_RECORD)
        @test !isempty(strings)
        for text in strings
            @test !ou_ref_leaks_local_path(text)
        end
        # The record does name its driver, by the repository-relative path a
        # reader can open in their own checkout.
        @test OU_REF_DRIVER in strings
    end

    @testset "the canonical figure is present and is a PNG" begin
        # Structural presence and the format's own eight-byte signature. Nothing
        # here asserts a digest, the dimensions, or a pixel: the figure is
        # validated through the numerical series behind it, which is what the rest
        # of this file does.
        @test isfile(OU_REF_FIGURE_PATH)
        signature = open(OU_REF_FIGURE_PATH, "r") do stream
            read(stream, length(OU_REF_PNG_SIGNATURE))
        end
        @test signature == OU_REF_PNG_SIGNATURE
    end
end
