# %% CS-06 — Ornstein–Uhlenbeck dynamics: identity and bounded scope
#
# Stochastic Systems in Julia — case study 06.
#
#     dX_t = κ (μ − X_t) dt + σ dW_t,     κ > 0,  σ > 0.
#
# The driver runs four experiments and prints their results. Everything
# numerical happens inside `StochasticCaseStudies.OrnsteinUhlenbeck`; this file
# resolves a preset, derives the substream seeds, calls one function per
# experiment, and reports. The experiments are called one at a time rather than
# through `run_case_study`, so that every intermediate result stays bound to a
# name and can be inspected in the REPL between cells.
#
# What the case establishes:
#
#   * the transient mean and variance of the process against their closed forms;
#   * the mean and variance of the invariant law against theirs;
#   * the temporal autocorrelation of the stationary process, its finite-window
#     integrated autocorrelation time, and the corrected uncertainty of a mean
#     estimated from a correlated series;
#   * the finite-step bias of the Euler–Maruyama invariant variance across a grid
#     of step sizes.
#
# What it deliberately does not establish: strong pathwise convergence, pathwise
# Brownian coupling between schemes, multilevel Monte Carlo, any claim that one
# scheme is universally superior to another, and any order of convergence outside
# the grid actually tested. The representative trajectories are illustrative and
# no reported value is estimated from them.
#
# Run it as
#
#     julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl
#     julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl smoke
#     julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl figure
#     julia --project=. case-studies/06-ornstein-uhlenbeck/driver.jl production
#
# The smoke preset is the default and writes nothing at all.

# %% Imports
#
# The package exports nothing, so every name is imported explicitly. CairoMakie is
# deliberately absent here: it is loaded inside the figure branch alone, so that
# the default run does not pay for a plotting stack it never uses.

using Random: Xoshiro

using StochasticCaseStudies:
    PRESETS, capture_provenance, derive_seeds,
    write_reference_summary
using StochasticCaseStudies.OrnsteinUhlenbeck: CASE_SLUG, MASTER_SEED, SEED_SLOTS,
    ou_parameters, reference_parameters, reference_values, relaxation_time,
    run_correlated_experiment, run_euler_experiment, run_representative_paths,
    run_stationary_experiment, run_transient_experiment, stationary_variance,
    transient_mean, transient_variance

# %% Preset selection from positional arguments
#
# The preset is chosen by one optional positional argument and by nothing else.
# No environment variable is read, no tracked file has to be edited, and there is
# no hidden fallback: an unrecognised name, or more than one argument, is an
# error naming what was given.

function select_preset(arguments::AbstractVector{<:AbstractString})
    isempty(arguments) && return :smoke
    length(arguments) == 1 || throw(
        ArgumentError(
            "the driver takes at most one positional argument, the preset name, " *
            "got $(length(arguments)): $(join(arguments, ", "))",
        ),
    )
    name = arguments[1]
    valid = String.(collect(PRESETS))
    name in valid || throw(
        ArgumentError(
            "\"$name\" is not a valid execution preset; the valid presets are " *
            "$(join(valid, ", "))",
        ),
    )
    return Symbol(name)
end

const PRESET = select_preset(ARGS)

println("CS-06 — Ornstein–Uhlenbeck dynamics")
println("preset: ", PRESET)

# %% Resolved parameters
#
# The preset fixes the scale of the evidence; the process itself is the same
# under all three.

parameters = ou_parameters(PRESET)

println("kappa = ", parameters.kappa, ",  mu = ", parameters.mu,
    ",  sigma = ", parameters.sigma, ",  x0 = ", parameters.x0)
println("relaxation time 1/kappa      = ",
    round(relaxation_time(parameters.kappa); sigdigits = 6))
println("stationary variance s2/(2k)  = ",
    round(stationary_variance(parameters.kappa, parameters.sigma); sigdigits = 6))

# %% Substream seeds
#
# One master seed, nine semantic substreams. All nine are derived under every
# preset, so a slot always means the same thing and a smoke run is a genuine
# prefix of a production one. Slots 1 to 4 drive the exact experiments; slots 5
# to 9 drive the Euler study, one per step size in the order of the grid.

seeds = derive_seeds(MASTER_SEED, SEED_SLOTS)
euler_seeds = seeds[5:(4+length(parameters.euler_steps))]

println("master seed: ", MASTER_SEED, ",  substreams: ", length(seeds))

# %% Transient ensemble from a deterministic start
#
# Independent draws of X_t at each transient time, taken directly from the exact
# marginal law rather than by integrating a path.

transient = run_transient_experiment(Xoshiro(seeds[1]), parameters)

# %% Stationary independent ensemble
#
# Independent draws from the exact invariant law. Nothing is discarded as
# burn-in, because the ensemble is in equilibrium by construction.

stationary = run_stationary_experiment(Xoshiro(seeds[2]), parameters)

# %% Stationary correlated path
#
# One long path started from a stationary draw, so it is stationary from its
# first point. This is the only correlated regime of the case, and the only place
# an integrated autocorrelation time or an effective sample size appears.

correlated = run_correlated_experiment(Xoshiro(seeds[3]), parameters)

# %% Euler discrete-stationary one-step study
#
# For each step size: start in the Euler recursion's own invariant law, take
# exactly one step, and measure the endpoint variance. There is no horizon and no
# burn-in — the design removes the need for both.

euler = run_euler_experiment(euler_seeds, parameters)

# %% Representative exact trajectories
#
# Illustrative only. Nothing is estimated from them.

representative = run_representative_paths(Xoshiro(seeds[4]), parameters)

# %% Console summary
#
# The results are gathered into one named tuple of the same shape
# `run_case_study` returns, so that the figure and reference branches below take
# exactly the object those functions document.

result = (
    preset = PRESET,
    parameters = parameters,
    seeds = seeds,
    transient = transient,
    stationary = stationary,
    correlated = correlated,
    euler = euler,
    representative = representative,
)

show6(x) = rpad(round(x; sigdigits = 6), 12)

println()
println("Transient moments, n = ", transient.n, " independent draws per time")
println("  t       mean         exact        nsigma   variance     exact        nsigma")
for i in eachindex(transient.times)
    println("  ", rpad(transient.times[i], 6),
        "  ", show6(transient.empirical_mean[i]),
        " ", show6(transient.analytic_mean[i]),
        " ", rpad(round(transient.mean_nsigma[i]; sigdigits = 3), 8),
        " ", show6(transient.empirical_variance[i]),
        " ", show6(transient.analytic_variance[i]),
        " ", round(transient.variance_nsigma[i]; sigdigits = 3))
end

println()
println("Stationary moments, n = ", stationary.n, " independent draws")
println("  mean      = ", show6(stationary.empirical_mean),
    " exact ", show6(stationary.analytic_mean),
    " sem ", show6(stationary.mean_sem),
    " nsigma ", round(stationary.mean_nsigma; sigdigits = 3))
println("  variance  = ", show6(stationary.empirical_variance),
    " exact ", show6(stationary.analytic_variance),
    " se  ", show6(stationary.variance_se),
    " nsigma ", round(stationary.variance_nsigma; sigdigits = 3))

println()
println("Correlated path, n = ", correlated.summary.n,
    " points at h = ", parameters.correlation_step,
    ", lag window = ", parameters.maxlag)
println("  tau_int measured        = ", round(correlated.summary.tau_int; sigdigits = 6))
println("  tau_int finite window   = ", round(correlated.tau_exact_window; sigdigits = 6))
println("  relative error          = ", round(correlated.tau_relative_error; sigdigits = 3))
println("  effective sample size   = ", round(correlated.summary.ess; sigdigits = 6))
println("  mean                    = ", round(correlated.summary.mean; sigdigits = 6),
    " +/- ", round(correlated.summary.sem; sigdigits = 3),
    " (correlated sem), nsigma ", round(correlated.mean_nsigma; sigdigits = 3))
println("  ACF RMSE over the window = ", round(correlated.acf_rmse; sigdigits = 3))

println()
println("Euler stationary-variance bias, n = ", euler.n, " endpoints per step")
println("  h        variance     v_EM(h)      nsigma   bias         exact bias")
for i in eachindex(euler.steps)
    println("  ", rpad(euler.steps[i], 7),
        "  ", show6(euler.empirical_variance[i]),
        " ", show6(euler.analytic_euler_variance[i]),
        " ", rpad(round(euler.variance_nsigma[i]; sigdigits = 3), 8),
        " ", show6(euler.empirical_bias[i]),
        " ", show6(euler.analytic_bias[i]))
end
println("  exact stationary variance = ", round(euler.exact_ou_variance; sigdigits = 6))
# The measured bias is signed, so the log-log fit of it exists only when every
# bias on the grid is strictly positive. A run in which one is not is a valid
# realisation whose fit is undefined, and it is reported as such rather than
# suppressed by an absolute value.
if euler.empirical_fit === nothing
    println("  log-log slope, measured   = unavailable: the measured bias is not ",
        "strictly positive at every step")
else
    println("  log-log slope, measured   = ",
        round(euler.empirical_fit.slope; sigdigits = 4),
        " +/- ", round(euler.empirical_fit.slope_se; sigdigits = 3),
        " (r2 ", round(euler.empirical_fit.r2; sigdigits = 4), ")")
end
println("  log-log slope, exact bias = ", round(euler.analytic_fit.slope; sigdigits = 4),
    " on the same grid")
println("  The slopes describe this grid only; no asymptotic order is claimed.")

println()
println("Representative trajectories: ", size(representative.paths, 2),
    " paths on ", length(representative.times), " grid points (illustrative only)")

# %% Figure branch
#
# Rendered only under the figure preset. CairoMakie is loaded here and nowhere
# else, so neither the package, nor the default run, nor the test suite pays for
# it. The panels are drawn from the arrays already computed above; no simulation
# is repeated in plotting code.
#
# The figure directory must already exist. Creating it implicitly is how a
# mistyped case slug becomes a second, silently empty case directory.

if PRESET === :figure
    using CairoMakie

    figure_directory = joinpath(@__DIR__, "figures")
    isdir(figure_directory) || throw(
        ArgumentError(
            "the directory `$figure_directory` does not exist; create the figure " *
            "directory deliberately before rendering into it",
        ),
    )
    figure_path = joinpath(figure_directory, "ornstein-uhlenbeck.png")

    CairoMakie.activate!(type = "png")
    fig = Figure(size = (1500, 850))

    # A — transient mean and representative trajectories.
    axis_a = Axis(fig[1, 1];
        title = "A. Mean reversion",
        xlabel = "time t",
        ylabel = "X(t)")
    for j in axes(representative.paths, 2)
        lines!(axis_a, representative.times, representative.paths[:, j];
            color = (:grey40, 0.35), linewidth = 0.8)
    end
    dense = collect(range(0.0, representative.times[end]; length = 400))
    lines!(axis_a, dense,
        [transient_mean(t, parameters.kappa, parameters.mu, parameters.x0) for t in dense];
        color = :black, linewidth = 2.5, label = "exact mean m(t)")
    scatter!(axis_a, transient.times, transient.empirical_mean;
        color = :firebrick, markersize = 11, label = "measured mean")
    errorbars!(axis_a, transient.times, transient.empirical_mean,
        4 .* transient.mean_sem; color = :firebrick, whiskerwidth = 10)
    hlines!(axis_a, [parameters.mu]; color = :steelblue, linestyle = :dash)
    axislegend(axis_a; position = :rb, framevisible = false)

    # B — transient variance.
    axis_b = Axis(fig[1, 2];
        title = "B. Growth of the variance",
        xlabel = "time t",
        ylabel = "Var X(t)")
    lines!(axis_b, dense,
        [transient_variance(t, parameters.kappa, parameters.sigma) for t in dense];
        color = :black, linewidth = 2.5, label = "exact v(t)")
    scatter!(axis_b, transient.times, transient.empirical_variance;
        color = :firebrick, markersize = 11, label = "measured")
    errorbars!(axis_b, transient.times, transient.empirical_variance,
        4 .* transient.variance_se; color = :firebrick, whiskerwidth = 10)
    hlines!(axis_b, [stationary_variance(parameters.kappa, parameters.sigma)];
        color = :steelblue, linestyle = :dash, label = "stationary variance")
    axislegend(axis_b; position = :rb, framevisible = false)

    # C — the stationary Gaussian marginal. The histogram is of the long
    # stationary path, whose points are correlated in time; every one of them is
    # nevertheless drawn from the invariant law, so the marginal is exactly the
    # density plotted over it. No goodness-of-fit claim is made here.
    stationary_var = stationary_variance(parameters.kappa, parameters.sigma)
    axis_c = Axis(fig[1, 3];
        title = "C. Stationary marginal",
        xlabel = "x",
        ylabel = "density")
    hist!(axis_c, correlated.path;
        bins = 80, normalization = :pdf, color = (:steelblue, 0.55))
    grid_c = collect(
        range(
            parameters.mu - 5 * sqrt(stationary_var),
            parameters.mu + 5 * sqrt(stationary_var);
            length = 400,
        ),
    )
    lines!(axis_c, grid_c,
        [
            exp(-(x - parameters.mu)^2 / (2 * stationary_var)) /
            sqrt(2 * pi * stationary_var) for x in grid_c
        ];
        color = :black, linewidth = 2.5, label = "exact invariant density")
    axislegend(axis_c; position = :rt, framevisible = false)

    # D — measured against exact autocorrelation.
    lag_times = correlated.lags .* parameters.correlation_step
    axis_d = Axis(fig[2, 1];
        title = "D. Autocorrelation",
        xlabel = "lag τ",
        ylabel = "ρ(τ)")
    lines!(axis_d, lag_times, correlated.acf_analytic;
        color = :black, linewidth = 2.5, label = "exp(-κτ)")
    scatter!(axis_d, lag_times, correlated.acf_empirical;
        color = :firebrick, markersize = 6, label = "measured")
    axislegend(axis_d; position = :rt, framevisible = false)

    # E — the integrated autocorrelation time as a function of the summation
    # window, measured against the finite-window analytical value. The running
    # sums below are partial sums of arrays already computed; nothing is
    # resimulated.
    windows = collect(0:parameters.maxlag)
    running_measured = [1 + 2 * sum(@view correlated.acf_empirical[2:(w+1)])
     for w in windows]
    running_exact = [1 + 2 * sum(@view correlated.acf_analytic[2:(w+1)]) for w in windows]
    axis_e = Axis(fig[2, 2];
        title = "E. Integrated autocorrelation time",
        xlabel = "summation window L",
        ylabel = "τ(L)")
    lines!(axis_e, windows, running_exact;
        color = :black, linewidth = 2.5, label = "exact, same window")
    lines!(axis_e, windows, running_measured;
        color = :firebrick, linewidth = 2, label = "measured")
    vlines!(axis_e, [parameters.maxlag]; color = :steelblue, linestyle = :dash)
    text!(axis_e, 0.03, 0.06;
        text = "ESS = $(round(correlated.summary.ess; sigdigits = 5)),  " *
               "sem = $(round(correlated.summary.sem; sigdigits = 3))",
        space = :relative)
    axislegend(axis_e; position = :rb, framevisible = false)

    # F — the finite-step bias of the Euler invariant variance. The step axis is
    # logarithmic, because the grid is geometric; the bias axis is **linear**,
    # because the measured bias is signed. A logarithmic bias axis cannot draw a
    # nonpositive value and would silently truncate the lower half of an
    # uncertainty interval that crosses zero, which is exactly what a four
    # standard-error interval does at the finer steps. Showing the complete
    # interval, and the zero it may cross, is the honest representation.
    axis_f = Axis(fig[2, 3];
        title = "F. Euler stationary-variance bias",
        xlabel = "step h",
        ylabel = "v_EM(h) − σ²/(2κ)",
        xscale = log10)
    hlines!(axis_f, [0.0];
        color = :grey40, linestyle = :dash, label = "zero bias")
    lines!(axis_f, euler.steps, euler.analytic_bias;
        color = :black, linewidth = 2.5, label = "exact bias")
    scatter!(axis_f, euler.steps, euler.empirical_bias;
        color = :firebrick, markersize = 11, label = "measured bias")
    errorbars!(axis_f, euler.steps, euler.empirical_bias,
        4 .* euler.variance_se; color = :firebrick, whiskerwidth = 10)
    # The signed bias is meaningful whether or not the log-log fit of it exists.
    # When it does not, the panel says so rather than omitting the remark.
    measured_slope_note = if euler.empirical_fit === nothing
        "measured slope unavailable:\nthe measured bias is not positive throughout"
    else
        "measured slope $(round(euler.empirical_fit.slope; sigdigits = 3))" *
        " ± $(round(euler.empirical_fit.slope_se; sigdigits = 2))"
    end
    text!(axis_f, 0.04, 0.9;
        text = measured_slope_note * "\nexact slope on this grid " *
               "$(round(euler.analytic_fit.slope; sigdigits = 3))",
        space = :relative)
    axislegend(axis_f; position = :rb, framevisible = false)

    Label(fig[0, :],
        "CS-06 — Ornstein–Uhlenbeck dynamics: mean reversion, stationary " *
        "correlations, and the finite-step bias of Euler–Maruyama";
        fontsize = 19, font = :bold)

    save(figure_path, fig; px_per_unit = 2)
    println()
    println("figure written to ", figure_path)
end

# %% Production reference branch
#
# Writes the committed numerical reference summary, and only under the production
# preset: the smoke and figure presets are not eligible, because their sample
# sizes do not support a reported value. Provenance capture requires a clean
# working tree, so the recorded commit alone identifies the code and the
# committed manifest. Only the master seed is recorded; the derived substream
# seeds are not a durable payload.

if PRESET === :production
    parameters.reference_eligible || throw(
        ArgumentError(
            "the `:$PRESET` preset is not eligible to write a reference summary",
        ),
    )
    reference_directory = joinpath(@__DIR__, "reference")
    isdir(reference_directory) || throw(
        ArgumentError(
            "the directory `$reference_directory` does not exist; create the " *
            "reference directory deliberately before writing a summary into it",
        ),
    )
    reference_path = joinpath(reference_directory, "ornstein-uhlenbeck.toml")

    provenance = capture_provenance(;
        case = CASE_SLUG,
        seed = MASTER_SEED,
        preset = PRESET,
        generated_by = "case-studies/$CASE_SLUG/driver.jl",
    )
    write_reference_summary(reference_path;
        provenance = provenance,
        parameters = reference_parameters(result),
        values = reference_values(result))
    println()
    println("reference summary written to ", reference_path)
end
