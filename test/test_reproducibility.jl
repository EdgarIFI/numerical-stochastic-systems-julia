using Test
using TOML

using Dates: DateTime

using StochasticCaseStudies
using StochasticCaseStudies:
    capture_provenance, validate_reference_summary, write_reference_summary

# The atomic replacement primitive is reached by explicit import so that the
# branch active on this platform can be exercised directly. It is internal, and
# importing it here asserts nothing about the public interface.
using StochasticCaseStudies: _replace_atomically

# The reference-context detector and its alias key are imported for the same
# reason. Detection is deliberately broader than acceptance, and the difference
# between the two is a lexical property that is worth testing directly rather
# than only through the filesystem behaviour it produces on one platform. Both
# are internal, and importing them here asserts nothing about the public
# interface.
using StochasticCaseStudies: _logical_reference_path, _reference_context_alias_key

# The case slug used throughout these tests, `99-example-process`, is
# deliberately **fictitious**. It names no case study of this repository and
# corresponds to no directory in it: every fixture that appears to live under
# `case-studies/99-example-process/` is built inside a temporary directory and
# removed again. Using a slug that could never be mistaken for a real case is
# what keeps a test fixture from reading as evidence that a case exists.

# The verification script is exercised through a module of its own rather than by
# being included here, so that its top-level constants and functions cannot
# collide with anything in the test session and nothing global is modified. The
# script's `PROGRAM_FILE` guard does not fire under `include`, so loading it runs
# no verification and exits nothing.
const VERIFIER = Module(:VerifyReproducibilityScript)
Base.include(VERIFIER, joinpath(ROOT, "scripts", "verify_reproducibility.jl"))

# ---------------------------------------------------------------------------
# Record builders. Each returns a fresh mutable table, so that a test may edit
# one without affecting any other.
# ---------------------------------------------------------------------------

"""
    valid_provenance() -> Dict{String,Any}

A complete and valid schema version 1 provenance table.
"""
valid_provenance() = Dict{String,Any}(
    "case" => "99-example-process",
    "generated" => "2026-08-03T09:15:00Z",
    "generated_by" => "case-studies/99-example-process/driver.jl",
    "git_commit" => "0123456789abcdef0123456789abcdef01234567",
    "julia_version" => "1.12.6",
    "preset" => "production",
    "rng" => "Xoshiro",
    "seed" => 20260803,
)

"""
    valid_parameters() -> Dict{String,Any}

Resolved numerical parameters exercising every permitted payload shape: scalars,
a homogeneous array, and a nested table.
"""
valid_parameters() = Dict{String,Any}(
    "steps" => 10_000,
    "dt" => 1.0e-3,
    "antithetic" => false,
    "label" => "canonical",
    "radii" => [0.5, 1.0, 2.0],
    "integrator" => Dict{String,Any}("scheme" => "euler-maruyama", "order" => 1),
)

"""
    valid_values() -> Dict{String,Any}

One result of each admissible shape: exact, estimate with a standard error, and
estimate with a confidence interval.
"""
valid_values() = Dict{String,Any}(
    "displacement" => Dict{String,Any}("value" => 0.0, "kind" => "exact"),
    "variance" => Dict{String,Any}(
        "value" => 1.0,
        "kind" => "estimate",
        "se" => 0.01,
        "tolerance_abs" => 0.04,
        "units" => "dimensionless",
    ),
    "drift" => Dict{String,Any}(
        "value" => 0.5,
        "kind" => "estimate",
        "ci_lower" => 0.4,
        "ci_upper" => 0.6,
        "tolerance_rel" => 0.0,
        "method" => "Student-t interval",
        "note" => "",
    ),
)

"""
    valid_record(; provenance, parameters, values) -> Dict{String,Any}

Assemble a complete schema version 1 reference summary from its three tables.
"""
function valid_record(;
    provenance = valid_provenance(),
    parameters = valid_parameters(),
    values = valid_values(),
)
    return Dict{String,Any}(
        "schema_version" => 1,
        "provenance" => provenance,
        "parameters" => parameters,
        "values" => values,
    )
end

"""
    record_with_provenance(changes::Pair...) -> Dict{String,Any}

A valid record whose provenance carries `changes`. A value of `nothing` deletes
the field instead of setting it, which is how an absent required field is built.
"""
function record_with_provenance(changes::Pair...)
    provenance = valid_provenance()
    for (name, value) in changes
        value === nothing ? delete!(provenance, name) : (provenance[name] = value)
    end
    return valid_record(provenance = provenance)
end

"""
    record_with_value(fields::Pair...) -> Dict{String,Any}

A valid record holding exactly one result, named `quantity`, built from `fields`.
A value of `nothing` omits the field.
"""
function record_with_value(fields::Pair...)
    entry = Dict{String,Any}()
    for (name, value) in fields
        value === nothing || (entry[name] = value)
    end
    return valid_record(values = Dict{String,Any}("quantity" => entry))
end

"""
    mentions(problems, fragment) -> Bool

Whether some reported problem names `fragment`. A test asserts both that a
malformed record is rejected and that the report identifies the offending field,
so that a rejection for the wrong reason cannot pass.
"""
mentions(problems, fragment) = any(problem -> occursin(fragment, problem), problems)

"""
    rejected(record, fragment; source_path = nothing) -> Bool

Whether `record` is rejected with a problem naming `fragment`.
"""
function rejected(record, fragment; source_path = nothing)
    problems = validate_reference_summary(record; source_path = source_path)
    return !isempty(problems) && mentions(problems, fragment)
end

"""
    thrown_message(f) -> String

Run `f` and return the rendered message of the exception it throws, or the empty
string if it does not throw.
"""
function thrown_message(f)
    try
        f()
        return ""
    catch err
        return sprint(showerror, err)
    end
end

# ---------------------------------------------------------------------------
# Filesystem and Git fixtures. Every one of them works inside a temporary
# directory: no test reads or writes the repository under test, whose working
# tree is deliberately dirty while this gate is being implemented.
# ---------------------------------------------------------------------------

"""
    WRITER_PROVENANCE

A provenance table in the `NamedTuple` form the writer takes, with an injected
timestamp so that written bytes are reproducible.
"""
const WRITER_PROVENANCE = (
    case = "99-example-process",
    generated = "2026-08-03T09:15:00Z",
    generated_by = "case-studies/99-example-process/driver.jl",
    git_commit = "0123456789abcdef0123456789abcdef01234567",
    julia_version = "1.12.6",
    os = "linux",
    preset = "production",
    rng = "Xoshiro",
    seed = 20260803,
    threads = 1,
)

const WRITER_PARAMETERS = (steps = 10_000, dt = 1.0e-3)
const WRITER_VALUES = (variance = (value = 1.0, kind = "estimate", se = 0.01),)

"""
    with_reference_directory(f, case = "99-example-process")

Create a temporary repository-shaped tree containing an empty reference directory
for `case`, and call `f(root, directory)`.
"""
function with_reference_directory(f, case::AbstractString = "99-example-process")
    mktempdir() do root
        directory = joinpath(root, "case-studies", case, "reference")
        mkpath(directory)
        return f(root, directory)
    end
end

"""
    quiet(command::Cmd) -> Nothing

Run `command`, discarding both of its output streams.
"""
function quiet(command::Cmd)
    run(pipeline(command; stdout = devnull, stderr = devnull))
    return nothing
end

"""
    global_git_configuration() -> String

The user's global Git configuration, captured so that a test can prove it was not
modified. An absent global configuration is the empty string, which compares
equal to itself.
"""
function global_git_configuration()
    output = IOBuffer()
    try
        run(
            pipeline(
                ignorestatus(`git config --global --list`);
                stdout = output,
                stderr = devnull,
            ),
        )
    catch
        return ""
    end
    return String(take!(output))
end

"""
    with_temporary_repository(f; commit = true)

Create a temporary Git repository, call `f(root)`, and remove it.

Identity and line-ending settings are written with `--local` scope, so they live
in the temporary repository alone and no global or system configuration is read
into it or written from it. With `commit = false` the repository is initialised
but left without a commit, so that HEAD does not resolve.
"""
function with_temporary_repository(f; commit::Bool = true)
    mktempdir() do directory
        root = realpath(directory)
        quiet(`git -C $root init --quiet`)
        quiet(`git -C $root config --local user.name "Gate 3B-I.2"`)
        quiet(`git -C $root config --local user.email "gate@example.invalid"`)
        quiet(`git -C $root config --local commit.gpgsign false`)
        quiet(`git -C $root config --local core.autocrlf false`)
        if commit
            write(joinpath(root, "README.md"), "temporary repository\n")
            quiet(`git -C $root add README.md`)
            quiet(`git -C $root commit --quiet -m "initial"`)
        end
        return f(root)
    end
end

"""
    capture_in(root; keywords...) -> NamedTuple

Capture provenance from the repository at `root`, supplying valid defaults for
everything a test does not override.
"""
function capture_in(root; keywords...)
    defaults = (
        case = "99-example-process",
        seed = 20260803,
        preset = :production,
        generated_by = "case-studies/99-example-process/driver.jl",
        repo_root = root,
    )
    return capture_provenance(; merge(defaults, (; keywords...))...)
end

"""
    with_verifier_repository(f)

Create a temporary repository-shaped directory carrying the two environment files
the verification script checks, and call `f(root)`.
"""
function with_verifier_repository(f)
    mktempdir() do root
        write(joinpath(root, "Project.toml"), "name = \"Temporary\"\n")
        write(joinpath(root, "Manifest.toml"), "julia_version = \"$VERSION\"\n")
        return f(root)
    end
end

"""
    run_verifier(root) -> NamedTuple

Run the verification script against `root`, returning its exit status and the
report it printed. Output is captured through the script's `io` argument, so
nothing is redirected and no global stream is touched.
"""
function run_verifier(root)
    buffer = IOBuffer()
    status = VERIFIER.verify(buffer, root)
    return (status = status, output = String(take!(buffer)))
end

"""
    write_summary_at(root, case, name; values) -> String

Write a valid reference summary for `case` under `root` and return its path.
"""
function write_summary_at(
    root,
    case::AbstractString,
    name::AbstractString;
    values = WRITER_VALUES,
)
    directory = joinpath(root, "case-studies", case, "reference")
    mkpath(directory)
    path = joinpath(directory, name)
    provenance = merge(
        WRITER_PROVENANCE,
        (case = case, generated_by = "case-studies/$case/driver.jl"),
    )
    write_reference_summary(
        path;
        provenance = provenance,
        parameters = WRITER_PARAMETERS,
        values = values,
    )
    return path
end

@testset "reproducibility" begin
    # -----------------------------------------------------------------------
    # A. The validator accepts a complete and valid record.
    # -----------------------------------------------------------------------
    @testset "a valid record is accepted" begin
        @test validate_reference_summary(valid_record()) == String[]
        @test validate_reference_summary(valid_record()) isa Vector{String}

        # The three admissible result shapes, each on its own.
        @test isempty(
            validate_reference_summary(
                record_with_value("value" => 2.5, "kind" => "exact"),
            ),
        )
        @test isempty(
            validate_reference_summary(
                record_with_value("value" => 2.5, "kind" => "estimate", "se" => 0.1),
            ),
        )
        @test isempty(
            validate_reference_summary(
                record_with_value(
                    "value" => 2.5,
                    "kind" => "estimate",
                    "ci_lower" => 2.4,
                    "ci_upper" => 2.6,
                ),
            ),
        )
        # A zero standard error and a degenerate interval are admissible: they are
        # unusual results, not malformed records.
        @test isempty(
            validate_reference_summary(
                record_with_value("value" => 1.0, "kind" => "estimate", "se" => 0.0),
            ),
        )
        @test isempty(
            validate_reference_summary(
                record_with_value(
                    "value" => 1.0,
                    "kind" => "estimate",
                    "ci_lower" => 1.0,
                    "ci_upper" => 1.0,
                ),
            ),
        )
        # An integer value is a number like any other.
        @test isempty(
            validate_reference_summary(record_with_value("value" => 3, "kind" => "exact")),
        )

        # Optional provenance fields.
        @test isempty(
            validate_reference_summary(
                record_with_provenance("threads" => 8, "os" => "linux", "note" => ""),
            ),
        )

        # The committed location, agreeing with the declared case.
        @test isempty(
            validate_reference_summary(
                valid_record();
                source_path = "case-studies/99-example-process/reference/variance.toml",
            ),
        )
        @test isempty(
            validate_reference_summary(
                valid_record();
                source_path = "case-studies/99-example-process/reference/mean-square.toml",
            ),
        )
    end

    # -----------------------------------------------------------------------
    # B. Top-level structure.
    # -----------------------------------------------------------------------
    @testset "top-level structure" begin
        for name in ("schema_version", "provenance", "parameters", "values")
            record = valid_record()
            delete!(record, name)
            @test rejected(record, "$name is required and is absent")
        end

        record = valid_record()
        record["results"] = Dict{String,Any}()
        @test rejected(record, "results is not a top-level key")

        for version in (0, 2, "1", 1.0, true)
            record = valid_record()
            record["schema_version"] = version
            @test rejected(record, "schema_version must be the integer 1")
        end

        @test rejected(
            valid_record(provenance = "not a table"),
            "provenance must be a table",
        )
        @test rejected(
            valid_record(parameters = "not a table"),
            "parameters must be a table",
        )
        @test rejected(valid_record(values = "not a table"), "values must be a table")
        @test rejected(valid_record(values = [1, 2]), "values must be a table")

        @test rejected(
            valid_record(parameters = Dict{String,Any}()),
            "parameters must record every resolved numerical parameter",
        )
        @test rejected(
            valid_record(values = Dict{String,Any}()),
            "values must record at least one result",
        )

        # A malformed record is reported in full rather than at its first fault.
        record = valid_record(
            provenance = Dict{String,Any}(),
            parameters = Dict{String,Any}(),
            values = Dict{String,Any}(),
        )
        @test length(validate_reference_summary(record)) >= 8
    end

    # -----------------------------------------------------------------------
    # C. Provenance.
    # -----------------------------------------------------------------------
    @testset "provenance fields are required" begin
        for name in (
            "case",
            "generated",
            "generated_by",
            "git_commit",
            "julia_version",
            "preset",
            "rng",
            "seed",
        )
            @test rejected(
                record_with_provenance(name => nothing),
                "provenance.$name is required and is absent",
            )
        end
        @test rejected(
            record_with_provenance("machine" => "laptop"),
            "provenance.machine is not a field",
        )
        @test rejected(
            record_with_provenance("manifest_hash" => "0123"),
            "provenance.manifest_hash is not a field",
        )
    end

    @testset "the case slug" begin
        for case in ("6-brownian", "06-Brownian", "06brownian", "06-", "-06-brownian",
            "06-brownian--motion", "06-brownian-", "", "006-brownian")
            @test rejected(record_with_provenance("case" => case), "provenance.case")
        end
        @test rejected(
            record_with_provenance("case" => 6),
            "provenance.case must be a string",
        )
        # The driver path is checked against the case, so both move together.
        for case in ("00-a", "99-z9", "99-example-process-in-two-dimensions")
            record = record_with_provenance(
                "case" => case,
                "generated_by" => "case-studies/$case/driver.jl",
            )
            @test isempty(validate_reference_summary(record))
        end
    end

    @testset "the generation timestamp" begin
        for stamp in (
            "2026-08-03 09:15:00Z",     # space instead of T
            "2026-08-03T09:15:00",      # no zone
            "2026-08-03T09:15:00+00:00",# offset instead of Z
            "2026-08-03T09:15:00z",     # lowercase suffix
            "2026-08-03T09:15Z",        # minute precision
            "2026-08-03T09:15:00.000Z", # sub-second precision
            "26-08-03T09:15:00Z",       # two-digit year
            "",
        )
            @test rejected(
                record_with_provenance("generated" => stamp),
                "provenance.generated",
            )
        end
        # Syntactically well formed but not a real instant.
        for stamp in (
            "2026-02-30T00:00:00Z",
            "2026-13-01T00:00:00Z",
            "2026-00-01T00:00:00Z",
            "2026-01-32T00:00:00Z",
            "2026-01-01T09:60:00Z",
            "2026-01-01T09:00:60Z",
            "2025-02-29T00:00:00Z",
        )
            @test rejected(
                record_with_provenance("generated" => stamp),
                "provenance.generated",
            )
        end
        # Julia admits ISO 8601's end-of-day hour 24 and rolls it into the next
        # midnight. RFC 3339 does not, and one instant must have one spelling.
        @test rejected(
            record_with_provenance("generated" => "2026-01-01T24:00:00Z"),
            "provenance.generated",
        )
        # A leap day in a leap year is a real instant.
        @test isempty(
            validate_reference_summary(
                record_with_provenance("generated" => "2024-02-29T23:59:59Z"),
            ),
        )
        @test rejected(
            record_with_provenance("generated" => 20260803),
            "provenance.generated must be a string",
        )
    end

    @testset "the Git commit" begin
        full = "0123456789abcdef0123456789abcdef01234567"
        for commit in (
            full[1:7],                     # abbreviated
            full[1:39],                    # one short
            full * "0",                    # one long
            uppercase(full),               # upper case
            "0123456789abcdef0123456789abcdef0123456g",  # not hexadecimal
            "",
        )
            @test rejected(
                record_with_provenance("git_commit" => commit),
                "provenance.git_commit",
            )
        end
        @test rejected(
            record_with_provenance("git_commit" => 1234),
            "provenance.git_commit must be a string",
        )
    end

    @testset "the Julia version" begin
        for version in ("", "not a version", "1.2.3.4.5")
            @test rejected(
                record_with_provenance("julia_version" => version),
                "provenance.julia_version",
            )
        end
        @test rejected(
            record_with_provenance("julia_version" => 1.10),
            "provenance.julia_version",
        )
        # Structural validation accepts any well formed version, including one
        # that is not the running Julia: a record outlives the machine that
        # verifies it.
        for version in ("1.10.0", "1.12.6", "2.0.0-DEV", string(VERSION))
            @test isempty(
                validate_reference_summary(
                    record_with_provenance("julia_version" => version),
                ),
            )
        end
    end

    @testset "the preset, the generator, and the seed" begin
        for preset in ("Smoke", "draft", "", :production, 1)
            @test rejected(record_with_provenance("preset" => preset), "provenance.preset")
        end
        for preset in ("smoke", "figure", "production")
            @test isempty(
                validate_reference_summary(record_with_provenance("preset" => preset)),
            )
        end

        @test rejected(record_with_provenance("rng" => ""), "provenance.rng")
        @test rejected(record_with_provenance("rng" => 42), "provenance.rng")

        @test rejected(record_with_provenance("seed" => -1), "provenance.seed")
        @test rejected(
            record_with_provenance("seed" => big(typemax(Int64)) + 1),
            "provenance.seed",
        )
        @test rejected(record_with_provenance("seed" => 1.5), "provenance.seed")
        @test rejected(record_with_provenance("seed" => true), "provenance.seed")
        @test rejected(record_with_provenance("seed" => "20260803"), "provenance.seed")
        for seed in (0, 1, typemax(Int64))
            @test isempty(
                validate_reference_summary(record_with_provenance("seed" => seed)),
            )
        end
    end

    @testset "the optional machine-context fields" begin
        @test rejected(record_with_provenance("threads" => 0), "provenance.threads")
        @test rejected(record_with_provenance("threads" => -2), "provenance.threads")
        @test rejected(record_with_provenance("threads" => 1.0), "provenance.threads")
        @test rejected(record_with_provenance("threads" => true), "provenance.threads")
        @test rejected(record_with_provenance("os" => ""), "provenance.os")
        @test rejected(record_with_provenance("os" => 11), "provenance.os")
        @test rejected(record_with_provenance("note" => 3), "provenance.note")
        # A note may be empty; the others may not.
        @test isempty(validate_reference_summary(record_with_provenance("note" => "")))
    end

    @testset "the thread count is bounded by the TOML integer domain" begin
        # A thread count is a positive count that TOML can record. The upper bound
        # is the signed 64-bit maximum, so that a value outside the domain is
        # reported as a problem rather than raising when it is written.
        for threads in (1, 2, typemax(Int64))
            @test isempty(
                validate_reference_summary(
                    record_with_provenance("threads" => threads),
                ),
            )
        end
        for threads in (
            0,
            -1,
            big(typemax(Int64)) + 1,
            UInt64(typemax(Int64)) + UInt64(1),
            typemax(UInt64),
            true,
            false,
            1.0,
            "1",
        )
            @test rejected(
                record_with_provenance("threads" => threads),
                "provenance.threads",
            )
        end
        # An oversized count is reported, not thrown: the validator stays total.
        for threads in (big(typemax(Int64)) + 1, typemax(UInt64))
            problems = validate_reference_summary(
                record_with_provenance("threads" => threads),
            )
            @test problems isa Vector{String}
            @test !isempty(problems)
        end
        # What `capture_provenance` itself records is inside the bound.
        @test isempty(
            validate_reference_summary(
                record_with_provenance("threads" => Threads.nthreads()),
            ),
        )
    end

    @testset "a reserved note admits prose but not NUL" begin
        # A note is free prose. Several paragraphs, tabs, punctuation, and
        # non-ASCII letters are all legitimate in one.
        for note in (
            "",
            "one line",
            "first line\nsecond line",
            "a\tb",
            "first\n\nthird paragraph, with — punctuation and naïve accents",
            "100% of the samples",
        )
            @test isempty(
                validate_reference_summary(record_with_provenance("note" => note)),
            )
            @test isempty(
                validate_reference_summary(
                    record_with_value("value" => 1.0, "kind" => "exact", "note" => note),
                ),
            )
        end
        # NUL alone is refused, in both places a note may appear.
        for note in ("\0", "before\0after", "trailing\0")
            @test rejected(record_with_provenance("note" => note), "provenance.note")
            @test rejected(
                record_with_provenance("note" => note),
                "must not contain the NUL character U+0000",
            )
            @test rejected(
                record_with_value("value" => 1.0, "kind" => "exact", "note" => note),
                "values.quantity.note",
            )
        end
    end

    @testset "the generating driver path" begin
        for path in (
            "/case-studies/99-example-process/driver.jl",          # absolute POSIX
            "C:/case-studies/99-example-process/driver.jl",        # Windows drive
            "case-studies\\99-example-process\\driver.jl",         # backslashes
            "case-studies/99-example-process/../driver.jl",        # traversal
            "case-studies/./99-example-process/driver.jl",         # dot component
            "case-studies//99-example-process/driver.jl",          # empty component
            "case-studies/07-other-case/driver.jl",                # wrong case directory
            "case-studies/99-example-process/driver.py",           # wrong extension
            "scripts/driver.jl",                                   # outside case-studies
            "driver.jl",                                           # no directory at all
            "",
        )
            @test rejected(
                record_with_provenance("generated_by" => path),
                "provenance.generated_by",
            )
        end
        @test rejected(
            record_with_provenance("generated_by" => 7),
            "provenance.generated_by must be a string",
        )
        # A driver nested inside the case directory is acceptable.
        @test isempty(
            validate_reference_summary(
                record_with_provenance(
                    "generated_by" => "case-studies/99-example-process/src/driver.jl",
                ),
            ),
        )
    end

    # -----------------------------------------------------------------------
    # D. Values.
    # -----------------------------------------------------------------------
    @testset "the reported value and its kind" begin
        @test rejected(record_with_value("kind" => "exact"), "value is required")
        @test rejected(record_with_value("value" => 1.0), "kind is required")
        for value in (NaN, Inf, -Inf)
            @test rejected(
                record_with_value("value" => value, "kind" => "exact"),
                "values.quantity.value",
            )
        end
        for value in ("1.0", true, [1.0])
            @test rejected(
                record_with_value("value" => value, "kind" => "exact"),
                "values.quantity.value",
            )
        end
        for kind in ("Exact", "approximate", "", 1, :exact)
            @test rejected(record_with_value("value" => 1.0, "kind" => kind), "kind")
        end
        @test rejected(
            valid_record(values = Dict{String,Any}("quantity" => "not a table")),
            "values.quantity must be a table",
        )
        @test rejected(
            valid_record(values = Dict{String,Any}("" => Dict{String,Any}())),
            "empty name",
        )
    end

    @testset "the uncertainty contract" begin
        # An exact result carries no uncertainty at all.
        for (name, value) in ("se" => 0.1, "ci_lower" => 0.9, "ci_upper" => 1.1)
            @test rejected(
                record_with_value("value" => 1.0, "kind" => "exact", name => value),
                "must carry no uncertainty",
            )
        end
        # An estimate carries exactly one representation of it.
        @test rejected(
            record_with_value("value" => 1.0, "kind" => "estimate"),
            "must carry either se or both ci_lower and ci_upper",
        )
        @test rejected(
            record_with_value(
                "value" => 1.0,
                "kind" => "estimate",
                "se" => 0.1,
                "ci_lower" => 0.9,
                "ci_upper" => 1.1,
            ),
            "both a standard error and a confidence bound",
        )
        @test rejected(
            record_with_value(
                "value" => 1.0,
                "kind" => "estimate",
                "se" => 0.1,
                "ci_lower" => 0.9,
            ),
            "both a standard error and a confidence bound",
        )
        @test rejected(
            record_with_value("value" => 1.0, "kind" => "estimate", "ci_lower" => 0.9),
            "one confidence bound",
        )
        @test rejected(
            record_with_value("value" => 1.0, "kind" => "estimate", "ci_upper" => 1.1),
            "one confidence bound",
        )

        # The uncertainty itself must be a finite, sensible number.
        for standard_error in (-0.1, NaN, Inf, "0.1", true)
            @test rejected(
                record_with_value(
                    "value" => 1.0,
                    "kind" => "estimate",
                    "se" => standard_error,
                ),
                "values.quantity.se",
            )
        end
        @test rejected(
            record_with_value(
                "value" => 1.0,
                "kind" => "estimate",
                "ci_lower" => 1.1,
                "ci_upper" => 0.9,
            ),
            "reversed interval",
        )
        @test rejected(
            record_with_value(
                "value" => 2.0,
                "kind" => "estimate",
                "ci_lower" => 0.9,
                "ci_upper" => 1.1,
            ),
            "lies outside its recorded interval",
        )
        @test rejected(
            record_with_value(
                "value" => 0.5,
                "kind" => "estimate",
                "ci_lower" => 0.9,
                "ci_upper" => 1.1,
            ),
            "lies outside its recorded interval",
        )
        for bound in (NaN, Inf, "0.9")
            @test rejected(
                record_with_value(
                    "value" => 1.0,
                    "kind" => "estimate",
                    "ci_lower" => bound,
                    "ci_upper" => 1.1,
                ),
                "values.quantity.ci_lower",
            )
        end
    end

    @testset "the optional result fields" begin
        for name in ("tolerance_abs", "tolerance_rel")
            for tolerance in (-1.0e-8, NaN, Inf, "0.1", true)
                @test rejected(
                    record_with_value("value" => 1.0, "kind" => "exact", name => tolerance),
                    "values.quantity.$name",
                )
            end
            @test isempty(
                validate_reference_summary(
                    record_with_value("value" => 1.0, "kind" => "exact", name => 0.0),
                ),
            )
        end
        for name in ("units", "method", "note")
            @test rejected(
                record_with_value("value" => 1.0, "kind" => "exact", name => 42),
                "values.quantity.$name must be a string",
            )
        end
        # A case study may record fields of its own, provided they survive TOML.
        @test isempty(
            validate_reference_summary(
                record_with_value(
                    "value" => 1.0,
                    "kind" => "exact",
                    "reference_source" => "Kloeden and Platen, Theorem 10.2.2",
                    "replicates" => 256,
                    "window" => [1, 2, 4],
                ),
            ),
        )
        @test rejected(
            record_with_value("value" => 1.0, "kind" => "exact", "extra" => NaN),
            "values.quantity.extra",
        )
    end

    # -----------------------------------------------------------------------
    # Parameters, and the recursive durability rules that govern any payload.
    # -----------------------------------------------------------------------
    @testset "resolved parameters must be durable" begin
        durable = Dict{String,Any}(
            "steps" => 10_000,
            "dt" => 1.0e-3,
            "exact" => true,
            "scheme" => "euler-maruyama",
            "radii" => [0.5, 1.0],
            "counts" => [1, 2, 3],
            "labels" => ["a", "b"],
            "flags" => [true, false],
            "empty" => [],
            # Julia has already promoted this one to `Vector{Float64}`, so it is
            # homogeneous by the time it is recorded. Only an array that is still
            # heterogeneous at that point is refused.
            "promoted" => [1, 2.0],
            "nested" => Dict{String,Any}(
                "inner" => Dict{String,Any}("depth" => 2, "scale" => 0.5),
            ),
        )
        @test isempty(validate_reference_summary(valid_record(parameters = durable)))

        for (name, value) in (
            "broken" => NaN,
            "unbounded" => Inf,
            "huge" => big(typemax(Int64)) + 1,
            "tiny" => big(typemin(Int64)) - 1,
            "mixed" => Any[1, 2.0],
            "mixed_kind" => [1, "two"],
            "deep_array" => [[1, 2], [3, 4]],
            "symbolic" => :steps,
            "complex" => 1 + 2im,
        )
            @test rejected(
                valid_record(parameters = Dict{String,Any}(name => value)),
                "parameters.$name",
            )
        end

        @test rejected(
            valid_record(parameters = Dict{String,Any}("" => 1)),
            "empty key",
        )
        # An absolute local path is refused wherever its field name announces one.
        for (name, value) in (
            "output_path" => "/home/edgar/results",
            "data_file" => "C:\\Users\\edgar\\data.csv",
            "root" => "/opt/data",
            "input_files" => ["relative/one.csv", "/absolute/two.csv"],
        )
            @test rejected(
                valid_record(parameters = Dict{String,Any}(name => value)),
                "absolute local path",
            )
        end
        # A relative path under such a name is fine, and so is an absolute-looking
        # string under a name that does not denote a path.
        @test isempty(
            validate_reference_summary(
                valid_record(
                    parameters = Dict{String,Any}(
                        "driver_path" => "case-studies/99-example-process/driver.jl",
                        "expression" => "/x/y",
                    ),
                ),
            ),
        )
        # A self-referential table is reported rather than exhausting the stack.
        cyclic = Dict{String,Any}("steps" => 1)
        cyclic["self"] = cyclic
        @test rejected(valid_record(parameters = cyclic), "nests more than")
    end

    # -----------------------------------------------------------------------
    # E. Source-path-aware validation.
    # -----------------------------------------------------------------------
    @testset "the committed location" begin
        canonical = "case-studies/99-example-process/reference/variance.toml"
        @test isempty(validate_reference_summary(valid_record(); source_path = canonical))

        for path in (
            "/case-studies/99-example-process/reference/variance.toml",  # absolute POSIX
            "C:/case-studies/99-example-process/reference/variance.toml",  # drive prefix
            "case-studies\\99-example-process\\reference\\variance.toml",  # backslashes
            "case-studies/99-example-process/../06-x/reference/variance.toml",  # traversal
            "case-studies/./99-example-process/reference/variance.toml",  # dot component
            "case-studies//99-example-process/reference/variance.toml",  # empty component
            "",
        )
            @test rejected(valid_record(), "the source path"; source_path = path)
        end

        for path in (
            "case-studies/99-example-process/variance.toml",             # too shallow
            "case-studies/99-example-process/reference/sub/variance.toml",  # too deep
            "case-studies/99-example-process/results/variance.toml",     # wrong subdirectory
            "results/99-example-process/reference/variance.toml",        # wrong root
            "variance.toml",
        )
            @test rejected(
                valid_record(),
                "the source path must be case-studies/<case>/reference/<result-name>.toml";
                source_path = path,
            )
        end

        @test rejected(
            valid_record(),
            "declares the case";
            source_path = "case-studies/07-other-case/reference/variance.toml",
        )
        @test rejected(
            valid_record(),
            "not a slug";
            source_path = "case-studies/brownian/reference/variance.toml",
        )
        for name in ("Variance.toml", "variance_two.toml", ".toml", "-variance.toml")
            @test rejected(
                valid_record(),
                "the source path";
                source_path = "case-studies/99-example-process/reference/$name",
            )
        end
        @test rejected(
            valid_record(),
            "must name a .toml file";
            source_path = "case-studies/99-example-process/reference/variance.txt",
        )

        # A committed reference summary may not record a development preset.
        smoke = record_with_provenance("preset" => "smoke")
        @test rejected(smoke, "must not record the smoke preset"; source_path = canonical)
        # Structural validation alone still permits it, which is what a scratch
        # record written outside the committed tree needs.
        @test isempty(validate_reference_summary(smoke))
        @test isempty(
            validate_reference_summary(record_with_provenance("preset" => "figure")),
        )
        @test isempty(
            validate_reference_summary(
                record_with_provenance("preset" => "figure");
                source_path = canonical,
            ),
        )
        # The validator does not require the file, or its case, to exist.
        @test !ispath(joinpath(ROOT, "case-studies", "99-example-process"))
    end

    # -----------------------------------------------------------------------
    # The validator is total: malformed input is reported, never thrown.
    # -----------------------------------------------------------------------
    @testset "malformed input is reported rather than thrown" begin
        for record in (
            Dict{String,Any}(),
            Dict{String,Any}("schema_version" => nothing),
            Dict{Any,Any}(1 => 2),
            Dict{String,Any}(
                "schema_version" => "one",
                "provenance" => [1, 2],
                "parameters" => 3,
                "values" => Dict{String,Any}("q" => [1]),
            ),
            valid_record(provenance = Dict{String,Any}("case" => Dict{String,Any}())),
            valid_record(values = Dict{String,Any}("q" => Dict{String,Any}("value" => []))),
        )
            problems = validate_reference_summary(record)
            @test problems isa Vector{String}
            @test !isempty(problems)
        end
        for path in ("..", ".", "\\", "/", "case-studies")
            @test validate_reference_summary(valid_record(); source_path = path) isa
                  Vector{String}
        end
    end

    # -----------------------------------------------------------------------
    # Control characters in path-like fields.
    # -----------------------------------------------------------------------
    @testset "path-like fields refuse control characters" begin
        # One representative of each guarded region: C0, DEL, and C1.
        controls = ("\0" => "U+0000", "\n" => "U+000A", "\t" => "U+0009",
            "\x1f" => "U+001F", "\x7f" => "U+007F", "\u0085" => "U+0085",
            "\u009f" => "U+009F")

        for (character, name) in controls
            driver = "case-studies/99-example-process/dri$(character)ver.jl"
            @test rejected(
                record_with_provenance("generated_by" => driver),
                "provenance.generated_by",
            )
            @test rejected(record_with_provenance("generated_by" => driver), name)

            summary = "case-studies/99-example-process/reference/vari$(character)ance.toml"
            @test rejected(valid_record(), "the source path"; source_path = summary)
            @test rejected(valid_record(), name; source_path = summary)

            # A problem, never an exception: the validator stays total.
            @test validate_reference_summary(
                record_with_provenance("generated_by" => driver);
                source_path = summary,
            ) isa Vector{String}

            # A parameter whose name denotes a path is held to the same rule.
            @test rejected(
                valid_record(
                    parameters = Dict{String,Any}(
                        "output_path" => "results/run$(character)one",
                    ),
                ),
                "parameters.output_path",
            )
            @test rejected(
                valid_record(
                    parameters = Dict{String,Any}(
                        "input_files" => ["a.csv", "b$(character).csv"],
                    ),
                ),
                "parameters.input_files[2]",
            )
        end

        # A field that does not denote a path is prose and is left alone.
        @test isempty(
            validate_reference_summary(
                valid_record(
                    parameters = Dict{String,Any}("label" => "first\nsecond"),
                ),
            ),
        )

        # Percent-encoded text is literal: no URL decoding is performed, so `%2F`
        # is three ordinary characters and never a separator, and `%00` is not
        # NUL. Both records are therefore rejected for shape, not for content.
        encoded = "case-studies%2F99-example-process%2Freference%2Fvariance.toml"
        @test rejected(
            valid_record(),
            "the source path must be case-studies/<case>/reference/<result-name>.toml";
            source_path = encoded,
        )
        @test !rejected(valid_record(), "control character"; source_path = encoded)
        @test isempty(
            validate_reference_summary(
                valid_record(parameters = Dict{String,Any}("note_path" => "run%00one")),
            ),
        )

        # Unicode characters that resemble a solidus are ordinary characters
        # within one component, not separators.
        for slash in ('⁄', '∕', '／')
            path = "case-studies$(slash)99-example-process$(slash)reference$(slash)v.toml"
            @test rejected(
                valid_record(),
                "the source path must be case-studies/<case>/reference/<result-name>.toml";
                source_path = path,
            )
            @test !rejected(valid_record(), "control character"; source_path = path)
        end
    end

    # -----------------------------------------------------------------------
    # F. Provenance capture, against temporary repositories only.
    # -----------------------------------------------------------------------
    @testset "provenance capture" begin
        # Git is not optional here. `capture_provenance` requires it, this
        # repository is a Git repository, continuous integration provides one, and
        # the Gate 3 reproducibility contract is stated in terms of a commit. A
        # suite that quietly skipped these checks on a machine without Git would
        # report a pass for a contract it never examined, so an absent executable
        # is a failure of the suite rather than a reason to say less.
        git_path = Sys.which("git")
        @test git_path !== nothing
        git_path === nothing && error(
            "Git is required for provenance-capture tests.",
        )

        configuration = global_git_configuration()

        @testset "a clean committed repository" begin
            with_temporary_repository() do root
                provenance = capture_in(root)
                @test provenance isa NamedTuple
                @test isconcretetype(typeof(provenance))
                @test keys(provenance) == (
                    :case,
                    :generated,
                    :generated_by,
                    :git_commit,
                    :julia_version,
                    :os,
                    :preset,
                    :rng,
                    :seed,
                    :threads,
                )

                head = readchomp(`git -C $root rev-parse HEAD`)
                @test provenance.git_commit == head
                @test length(provenance.git_commit) == 40
                @test occursin(r"^[0-9a-f]{40}$", provenance.git_commit)

                @test provenance.case == "99-example-process"
                @test provenance.preset == "production"
                @test provenance.rng == "Xoshiro"
                @test provenance.seed === Int64(20260803)
                @test provenance.generated_by ==
                      "case-studies/99-example-process/driver.jl"

                @test provenance.julia_version == string(VERSION)
                @test provenance.threads == Threads.nthreads()
                @test provenance.os isa String
                @test !isempty(provenance.os)

                @test occursin(
                    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
                    provenance.generated,
                )

                # What capture produces is exactly what the validator accepts.
                table = Dict{String,Any}(
                    string(name) => value for (name, value) in pairs(provenance)
                )
                @test isempty(
                    validate_reference_summary(valid_record(provenance = table)),
                )
                @test isempty(
                    validate_reference_summary(
                        valid_record(provenance = table);
                        source_path = "case-studies/99-example-process/reference/variance.toml",
                    ),
                )
            end
        end

        @testset "an injected timestamp is recorded verbatim" begin
            with_temporary_repository() do root
                stamp = "2026-01-02T03:04:05Z"
                first = capture_in(root; generated = stamp)
                second = capture_in(root; generated = stamp)
                @test first.generated == stamp
                @test first == second
                for bad in ("2026-01-02 03:04:05Z", "2026-02-30T00:00:00Z", "now", "")
                    @test_throws ArgumentError capture_in(root; generated = bad)
                end
            end
        end

        @testset "a dirty working tree is refused" begin
            with_temporary_repository() do root
                # A modified tracked file.
                write(joinpath(root, "README.md"), "edited\n")
                @test_throws ArgumentError capture_in(root)
                message = thrown_message(() -> capture_in(root))
                @test occursin("not clean", message)
                # Restoring the committed content makes the tree clean again.
                write(joinpath(root, "README.md"), "temporary repository\n")
                @test capture_in(root) isa NamedTuple
            end

            with_temporary_repository() do root
                # An untracked file that is not ignored.
                write(joinpath(root, "scratch.jl"), "# scratch\n")
                @test_throws ArgumentError capture_in(root)
                @test occursin("not clean", thrown_message(() -> capture_in(root)))
                rm(joinpath(root, "scratch.jl"))
                @test capture_in(root) isa NamedTuple
            end

            with_temporary_repository() do root
                # An untracked file inside an untracked directory.
                mkpath(joinpath(root, "results"))
                write(joinpath(root, "results", "run.csv"), "1\n")
                @test_throws ArgumentError capture_in(root)
            end

            with_temporary_repository() do root
                # An ignored file is not dirtiness: the commit still says what
                # would be run.
                write(joinpath(root, ".gitignore"), "results/\n")
                quiet(`git -C $root add .gitignore`)
                quiet(`git -C $root commit --quiet -m "ignore results"`)
                mkpath(joinpath(root, "results"))
                write(joinpath(root, "results", "run.csv"), "1\n")
                @test capture_in(root) isa NamedTuple
            end
        end

        @testset "a repository without provenance is refused" begin
            with_temporary_repository(commit = false) do root
                @test_throws ArgumentError capture_in(root)
                @test occursin("HEAD", thrown_message(() -> capture_in(root)))
            end
            mktempdir() do root
                @test_throws ArgumentError capture_in(root)
                @test occursin(
                    "not inside a Git work tree",
                    thrown_message(() -> capture_in(root)),
                )
            end
            missing_root = joinpath(mktempdir(), "absent")
            @test_throws ArgumentError capture_in(missing_root)
            @test occursin(
                "not an existing directory",
                thrown_message(() -> capture_in(missing_root)),
            )
        end

        @testset "arguments are guarded before the repository is read" begin
            with_temporary_repository() do root
                for case in ("6-x", "06-X", "", "06_x")
                    @test_throws ArgumentError capture_in(
                        root;
                        case = case,
                        generated_by = "case-studies/$case/driver.jl",
                    )
                end
                for seed in (-1, big(typemax(Int64)) + 1)
                    @test_throws ArgumentError capture_in(root; seed = seed)
                end
                for preset in (:draft, :Smoke, :SMOKE)
                    @test_throws ArgumentError capture_in(root; preset = preset)
                end
                for preset in (:smoke, :figure, :production)
                    @test capture_in(root; preset = preset).preset == String(preset)
                end
                @test_throws ArgumentError capture_in(root; rng = "")
                @test capture_in(root; rng = "StableRNG").rng == "StableRNG"

                for path in (
                    "/case-studies/99-example-process/driver.jl",
                    "C:/case-studies/99-example-process/driver.jl",
                    "case-studies/99-example-process/../driver.jl",
                    "case-studies/./99-example-process/driver.jl",
                    "case-studies//99-example-process/driver.jl",
                    "case-studies/07-other-case/driver.jl",
                    "case-studies/99-example-process/driver.py",
                    "scripts/driver.jl",
                    "",
                )
                    @test_throws ArgumentError capture_in(root; generated_by = path)
                end

                # A Windows separator in an otherwise safe relative path is
                # normalised rather than refused.
                normalised = capture_in(
                    root;
                    generated_by = "case-studies\\99-example-process\\driver.jl",
                )
                @test normalised.generated_by ==
                      "case-studies/99-example-process/driver.jl"
                @test capture_in(root; seed = 0).seed == 0
                @test capture_in(root; seed = typemax(Int64)).seed == typemax(Int64)
            end
        end

        # Nothing outside the temporary repositories was configured.
        @test global_git_configuration() == configuration
    end

    # -----------------------------------------------------------------------
    # G. The atomic writer.
    # -----------------------------------------------------------------------
    @testset "the reference-summary writer" begin
        @testset "a valid record round-trips" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                ) === nothing
                @test isfile(path)

                parsed = TOML.parsefile(path)
                @test parsed["schema_version"] == 1
                @test sort(collect(keys(parsed))) ==
                      ["parameters", "provenance", "schema_version", "values"]
                @test parsed["provenance"]["case"] == "99-example-process"
                @test parsed["provenance"]["seed"] == 20260803
                @test parsed["parameters"]["steps"] == 10_000
                @test parsed["values"]["variance"]["kind"] == "estimate"
                @test isempty(
                    validate_reference_summary(
                        parsed;
                        source_path = "case-studies/99-example-process/reference/variance.toml",
                    ),
                )
                # The result identifier is the filename; it is not repeated inside.
                @test !occursin("variance.toml", read(path, String))

                # Only the summary is left behind: no temporary sibling survives.
                @test readdir(directory) == ["variance.toml"]
            end
        end

        @testset "the byte contract" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                bytes = read(path)
                @test !isempty(bytes)
                @test isvalid(String(copy(bytes)))                 # UTF-8
                @test count(==(UInt8('\r')), bytes) == 0           # LF endings only
                @test bytes[end] == UInt8('\n')                    # one terminal LF
                @test bytes[end-1] != UInt8('\n')                # and no blank line
                @test bytes[1:3] != UInt8[0xef, 0xbb, 0xbf]        # no byte-order mark
            end
        end

        @testset "identical input produces identical bytes" begin
            first = with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                read(path)
            end
            second = with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                read(path)
            end
            @test first == second

            # The order in which a caller lists its parameters is not recorded.
            shuffled = with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (dt = 1.0e-3, steps = 10_000),
                    values = WRITER_VALUES,
                )
                read(path)
            end
            @test shuffled == first
        end

        @testset "the parent directory must already exist" begin
            mktempdir() do root
                path = joinpath(
                    root,
                    "case-studies",
                    "99-example-process",
                    "reference",
                    "v.toml",
                )
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test occursin(
                    "does not exist",
                    thrown_message(
                        () -> write_reference_summary(
                            path;
                            provenance = WRITER_PROVENANCE,
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        ),
                    ),
                )
                @test !ispath(path)
                @test !isdir(joinpath(root, "case-studies"))
                @test isempty(readdir(root))
            end
        end

        @testset "an invalid record is refused and changes nothing" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                original = read(path)

                # Every rejected shape: a broken value, an impossible provenance,
                # an empty table, a payload TOML cannot hold, and a committed
                # smoke record.
                rejections = (
                    (
                        WRITER_PROVENANCE,
                        WRITER_PARAMETERS,
                        (variance = (value = NaN, kind = "exact"),),
                    ),
                    (
                        merge(WRITER_PROVENANCE, (git_commit = "abc",)),
                        WRITER_PARAMETERS,
                        WRITER_VALUES,
                    ),
                    (WRITER_PROVENANCE, NamedTuple(), WRITER_VALUES),
                    (WRITER_PROVENANCE, WRITER_PARAMETERS, NamedTuple()),
                    (
                        WRITER_PROVENANCE,
                        (callback = sin,),
                        WRITER_VALUES,
                    ),
                    (
                        WRITER_PROVENANCE,
                        (stamp = DateTime(2026, 8, 3),),
                        WRITER_VALUES,
                    ),
                    (
                        merge(WRITER_PROVENANCE, (preset = "smoke",)),
                        WRITER_PARAMETERS,
                        WRITER_VALUES,
                    ),
                )
                for (provenance, parameters, values) in rejections
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = provenance,
                        parameters = parameters,
                        values = values,
                    )
                end

                # The existing summary is neither truncated nor replaced, and no
                # temporary sibling is left behind by any of the failures.
                @test read(path) == original
                @test readdir(directory) == ["variance.toml"]
            end
        end

        @testset "a valid record replaces an existing target" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                original = read(path)
                write_reference_summary(
                    path;
                    provenance = merge(
                        WRITER_PROVENANCE,
                        (generated = "2026-08-04T10:00:00Z",),
                    ),
                    parameters = WRITER_PARAMETERS,
                    values = (variance = (value = 1.5, kind = "estimate", se = 0.02),),
                )
                replaced = read(path)
                @test replaced != original
                @test readdir(directory) == ["variance.toml"]
                parsed = TOML.parsefile(path)
                @test parsed["values"]["variance"]["value"] == 1.5
                @test parsed["provenance"]["generated"] == "2026-08-04T10:00:00Z"
            end
        end

        @testset "the committed-location rules follow the path" begin
            # Under case-studies/, a smoke record is refused.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end
            # A summary whose case directory disagrees with the record is refused.
            with_reference_directory("07-other-case") do root, directory
                path = joinpath(directory, "variance.toml")
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end
            # A result name that is not a slug is refused.
            with_reference_directory() do root, directory
                path = joinpath(directory, "Variance.toml")
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end
            # Outside case-studies/ the record is a development one, and smoke is
            # exactly what a development record carries.
            mktempdir() do root
                directory = joinpath(root, "development")
                mkpath(directory)
                path = joinpath(directory, "draft.toml")
                @test write_reference_summary(
                    path;
                    provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                ) === nothing
                @test isfile(path)
                @test readdir(directory) == ["draft.toml"]
                @test TOML.parsefile(path)["provenance"]["preset"] == "smoke"
            end
        end

        @testset "recursive parameters and case-specific result fields" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (
                        steps = 10_000,
                        dt = 1.0e-3,
                        antithetic = false,
                        radii = [0.5, 1.0, 2.0],
                        window = [1, 2, 4],
                        integrator = (
                            scheme = "euler-maruyama",
                            order = 1,
                            tolerances = (absolute = 1.0e-9, relative = 1.0e-6),
                        ),
                    ),
                    values = (
                        variance = (
                            value = 1.0,
                            kind = "estimate",
                            se = 0.01,
                            units = "dimensionless",
                            method = "blocking",
                            replicates = 256,
                            reference_source = "Kloeden and Platen, Theorem 10.2.2",
                        ),
                    ),
                )
                parsed = TOML.parsefile(path)
                @test parsed["parameters"]["integrator"]["tolerances"]["relative"] ==
                      1.0e-6
                @test parsed["parameters"]["window"] == [1, 2, 4]
                @test parsed["parameters"]["radii"] == [0.5, 1.0, 2.0]
                @test parsed["values"]["variance"]["replicates"] == 256
                @test isempty(
                    validate_reference_summary(
                        parsed;
                        source_path = "case-studies/99-example-process/reference/variance.toml",
                    ),
                )
            end
        end

        @testset "an unsupported payload is refused" begin
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                for parameters in (
                    (callback = sin,),                       # a function
                    (symbol = :steps,),                      # a symbol
                    (complex = 1 + 2im,),                    # not a real number
                    (huge = big(typemax(Int64)) + 1,),       # outside the TOML integer
                    (broken = NaN,),                         # not finite
                    (unbounded = Inf,),
                    (mixed = Any[1, 2.0],),                  # heterogeneous
                    (nested = [[1, 2]],),                    # an array of arrays
                    (output_path = "/home/edgar/results",),  # an absolute local path
                )
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = WRITER_PROVENANCE,
                        parameters = parameters,
                        values = WRITER_VALUES,
                    )
                end
                @test isempty(readdir(directory))
            end
        end

        # -------------------------------------------------------------------
        # G3-CORR.4. Replacement is atomic or it fails; there is no fallback.
        # -------------------------------------------------------------------
        @testset "replacement is atomic or it fails" begin
            # The primitive itself, in exactly the configuration the writer uses:
            # a source and a target that are siblings in one directory, and so on
            # one filesystem. Whichever branch this Julia selects, it returns
            # nothing on success and leaves only the target behind.
            mktempdir() do directory
                source = joinpath(directory, "source.tmp")
                target = joinpath(directory, "target.toml")
                write(source, "replacement bytes\n")
                @test _replace_atomically(source, target) === nothing
                @test read(target, String) == "replacement bytes\n"
                @test readdir(directory) == ["target.toml"]

                # Replacing an existing target succeeds and yields the new bytes
                # in full, with no residue.
                again = joinpath(directory, "again.tmp")
                write(again, "second generation\n")
                @test _replace_atomically(again, target) === nothing
                @test read(target, String) == "second generation\n"
                @test readdir(directory) == ["target.toml"]
            end

            # A first-time write and a replacement, through the writer.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                ) === nothing
                @test isfile(path)
                # No temporary sibling survives a success, and nothing was
                # written beside the destination directory either.
                @test readdir(directory) == ["variance.toml"]
                @test readdir(joinpath(root, "case-studies")) == ["99-example-process"]

                @test write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (steps = 20_000, dt = 5.0e-4),
                    values = (variance = (value = 2.0, kind = "estimate", se = 0.02),),
                ) === nothing
                @test readdir(directory) == ["variance.toml"]

                # The replacement is complete: the new record is present in full
                # and no fragment of the previous one survives inside the file.
                parsed = TOML.parsefile(path)
                @test parsed["parameters"]["steps"] == 20_000
                @test parsed["parameters"]["dt"] == 5.0e-4
                @test parsed["values"]["variance"]["value"] == 2.0
                @test !occursin("10000", read(path, String))
                @test isempty(
                    validate_reference_summary(
                        parsed;
                        source_path = "case-studies/99-example-process/reference/variance.toml",
                    ),
                )
            end

            # A directory standing where the target belongs cannot be replaced by
            # a file. The failure is of the I/O class rather than an
            # `ArgumentError`, which is what distinguishes a refused replacement
            # from a refused record: the original error is propagated, not
            # translated, and no fallback attempts the move by other means.
            with_reference_directory() do root, directory
                target = joinpath(directory, "variance.toml")
                mkpath(target)
                write(joinpath(target, "inner.txt"), "occupied\n")
                before = readdir(target)

                thrown = try
                    write_reference_summary(
                        target;
                        provenance = WRITER_PROVENANCE,
                        parameters = WRITER_PARAMETERS,
                        values = WRITER_VALUES,
                    )
                    nothing
                catch err
                    err
                end
                @test thrown !== nothing
                @test thrown isa Base.IOError || thrown isa Base.SystemError
                @test !(thrown isa ArgumentError)

                # The pre-existing directory is untouched, and the failure left
                # no temporary sibling in the parent.
                @test isdir(target)
                @test readdir(target) == before
                @test read(joinpath(target, "inner.txt"), String) == "occupied\n"
                @test readdir(directory) == ["variance.toml"]
            end

            # A pre-write validation failure never truncates a valid existing
            # target, because nothing is opened until the record has passed.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                original = read(path)
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = (variance = (value = NaN, kind = "exact"),),
                )
                @test read(path) == original
                @test readdir(directory) == ["variance.toml"]
            end
        end

        # -------------------------------------------------------------------
        # G3-CORR.5. Detection of the reference tree is case-insensitive;
        # acceptance of it is not. Case folding is necessary but not
        # sufficient: G3-CORR.7, exercised in the testset below, extends
        # detection to the Windows trailing-dot and trailing-space aliases that
        # case folding alone left open.
        # -------------------------------------------------------------------
        @testset "a case-twiddled reference path is detected and refused" begin
            spellings = ("CASE-STUDIES", "Case-Studies", "case-Studies", "CASE-studies")
            for spelling in spellings, preset in ("production", "smoke")
                mktempdir() do root
                    directory = joinpath(root, spelling, "99-example-process", "reference")
                    mkpath(directory)
                    path = joinpath(directory, "variance.toml")
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = merge(WRITER_PROVENANCE, (preset = preset,)),
                        parameters = WRITER_PARAMETERS,
                        values = WRITER_VALUES,
                    )
                    # The refusal names the canonical layout, so a case-folded
                    # spelling is rejected for not being canonical rather than
                    # slipping through as an unrestricted development path.
                    @test occursin(
                        "case-studies/<case>/reference/<result-name>.toml",
                        thrown_message(
                            () -> write_reference_summary(
                                path;
                                provenance = merge(
                                    WRITER_PROVENANCE,
                                    (preset = preset,),
                                ),
                                parameters = WRITER_PARAMETERS,
                                values = WRITER_VALUES,
                            ),
                        ),
                    )
                    # No bypass file was created.
                    @test isempty(readdir(directory))
                end
            end

            # The same rule, stated against the validator, for a
            # repository-relative path and for an absolute one.
            for spelling in spellings
                @test rejected(
                    valid_record(),
                    "the source path must be case-studies/<case>/reference/<result-name>.toml";
                    source_path = "$spelling/99-example-process/reference/variance.toml",
                )
                @test rejected(
                    valid_record(),
                    "the source path";
                    source_path = "/$spelling/99-example-process/reference/variance.toml",
                )
            end

            # A mixed-separator destination: the native separator that `joinpath`
            # produces, followed by an explicit forward slash. Both are
            # normalised, so the case-folded component is found either way.
            mktempdir() do root
                directory =
                    joinpath(root, "Case-Studies", "99-example-process", "reference")
                mkpath(directory)
                mixed =
                    joinpath(root, "Case-Studies") *
                    "/99-example-process/reference/variance.toml"
                @test_throws ArgumentError write_reference_summary(
                    mixed;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end

            # The canonical spelling is unaffected: a production record still
            # succeeds, and a smoke record still fails.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                ) === nothing
                @test isfile(path)
            end
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test occursin(
                    "must not record the smoke preset",
                    thrown_message(
                        () -> write_reference_summary(
                            path;
                            provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        ),
                    ),
                )
                @test isempty(readdir(directory))
            end
        end

        # -------------------------------------------------------------------
        # G3-CORR.7. Windows resolves a path component carrying trailing dots
        # or trailing spaces to the component without them, so `case-studies.`
        # opens the canonical committed reference directory. The Gate 3C-A.1
        # audit demonstrated the consequence on a Windows host: a smoke record
        # written through such an alias escaped detection and landed inside the
        # committed tree. Detection now removes those characters for comparison
        # only, so the spelling that reaches the strict validator is the one the
        # caller wrote, and it is refused for not being canonical.
        # -------------------------------------------------------------------
        @testset "a Windows-aliased reference path is detected and refused" begin
            # Spellings the filesystem may resolve to `case-studies`. None is
            # canonical, so every one of them must be refused.
            aliases = (
                "case-studies.",
                "CASE-STUDIES.",
                "case-studies...",
                "CASE-STUDIES...",
                "case-studies ",
                "case-studies   ",
                "Case-Studies.",
                "Case-Studies   ",
                "case-studies. .",
                "case-studies . . ",
                "CaSe-StUdIeS. . ",
            )

            # Spellings that are not the reference tree under any rule. The tab
            # and newline forms are refused as control characters at a higher
            # layer; what is asserted here is that the alias key does not
            # silently reinterpret them as Windows aliases.
            nonmatches = (
                ".case-studies",
                "case-studies-x",
                "x-case-studies",
                "case studies",
                "case_studies",
                "case-studiesx.",
                "case-studies\t",
                "case-studies\n",
                "case-studies-tab\t",
                "case-studies-newline\n",
                "case-studies\u00a0",
                "case-studies\u3002",
                "case-studies\uff0e",
                "case-studies\u2024",
                "case-studies%2e",
                "case%2dstudies",
            )

            tail = "99-example-process/reference/variance.toml"

            @testset "the alias key removes only trailing ASCII dots and spaces" begin
                # A component with nothing to remove is returned unchanged,
                # whatever its case.
                @test _reference_context_alias_key("case-studies") == "case-studies"
                @test _reference_context_alias_key("CASE-STUDIES") == "CASE-STUDIES"
                @test _reference_context_alias_key("Case-Studies") == "Case-Studies"

                # One dot, one space, repetitions of each, and the two
                # alternating.
                @test _reference_context_alias_key("case-studies.") == "case-studies"
                @test _reference_context_alias_key("case-studies ") == "case-studies"
                @test _reference_context_alias_key("case-studies...") == "case-studies"
                @test _reference_context_alias_key("case-studies   ") == "case-studies"
                @test _reference_context_alias_key("case-studies. .") == "case-studies"
                @test _reference_context_alias_key("case-studies . . ") == "case-studies"
                @test _reference_context_alias_key("CaSe-StUdIeS. . ") == "CaSe-StUdIeS"

                # Removal is from the end only. A leading dot and an internal
                # dot or space survive.
                @test _reference_context_alias_key(".case-studies") == ".case-studies"
                @test _reference_context_alias_key("..case-studies..") == "..case-studies"
                @test _reference_context_alias_key("case studies") == "case studies"
                @test _reference_context_alias_key("case. studies.") == "case. studies"

                # A component made only of the removed characters strips to
                # nothing, and an empty component is already empty.
                @test _reference_context_alias_key("...") == ""
                @test _reference_context_alias_key("   ") == ""
                @test _reference_context_alias_key(" . . ") == ""
                @test _reference_context_alias_key("") == ""

                # Nothing else is removed. A tab, a newline, a non-breaking
                # space, and the Unicode full stops are ordinary characters, and
                # percent-encoded text is literal.
                @test _reference_context_alias_key("case-studies\t") == "case-studies\t"
                @test _reference_context_alias_key("case-studies\n") == "case-studies\n"
                @test _reference_context_alias_key("case-studies\u00a0") ==
                      "case-studies\u00a0"
                @test _reference_context_alias_key("case-studies\u3002") ==
                      "case-studies\u3002"
                @test _reference_context_alias_key("case-studies\uff0e") ==
                      "case-studies\uff0e"
                @test _reference_context_alias_key("case-studies\u2024") ==
                      "case-studies\u2024"
                @test _reference_context_alias_key("case-studies%2e") == "case-studies%2e"
                @test _reference_context_alias_key("case%2dstudies") == "case%2dstudies"

                # Non-ASCII text outside the removed suffix is untouched.
                @test _reference_context_alias_key("études. ") == "études"

                # Detection folds case after the key is taken, which is the
                # comparison the writer makes.
                for alias in ("case-studies", aliases...)
                    @test lowercase(_reference_context_alias_key(alias)) == "case-studies"
                end
                for spelling in nonmatches
                    @test lowercase(_reference_context_alias_key(spelling)) !=
                          "case-studies"
                end
            end

            @testset "detection keeps the original spelling" begin
                for alias in aliases
                    # Repository-relative, forward slashes.
                    @test _logical_reference_path("$alias/$tail") == "$alias/$tail"
                    # Absolute, forward slashes.
                    @test _logical_reference_path("/host/root/$alias/$tail") ==
                          "$alias/$tail"
                    # Windows separators throughout, with a drive prefix.
                    @test _logical_reference_path(
                        "C:\\host\\root\\" * replace("$alias/$tail", '/' => '\\'),
                    ) == "$alias/$tail"
                    # Mixed separators, in both orders.
                    @test _logical_reference_path("C:\\host\\root\\$alias/$tail") ==
                          "$alias/$tail"
                    @test _logical_reference_path(
                        "/host/root/$alias\\" * replace(tail, '/' => '\\'),
                    ) == "$alias/$tail"
                end

                # The last matching component is selected, alias or canonical.
                @test _logical_reference_path("case-studies/x/case-studies./$tail") ==
                      "case-studies./$tail"
                @test _logical_reference_path("case-studies./x/case-studies/$tail") ==
                      "case-studies/$tail"

                # A spelling that is not the reference tree is not detected, and
                # a genuine component elsewhere in the path still is.
                for spelling in nonmatches
                    @test _logical_reference_path("/host/root/$spelling/$tail") === nothing
                    @test _logical_reference_path("case-studies/x/$spelling/$tail") ==
                          "case-studies/x/$spelling/$tail"
                end
            end

            @testset "the writer refuses every alias, smoke and production alike" begin
                for alias in aliases
                    mktempdir() do root
                        for preset in ("production", "smoke")
                            path = joinpath(
                                root,
                                alias,
                                "99-example-process",
                                "reference",
                                "variance.toml",
                            )
                            attempt =
                                () -> write_reference_summary(
                                    path;
                                    provenance = merge(
                                        WRITER_PROVENANCE,
                                        (preset = preset,),
                                    ),
                                    parameters = WRITER_PARAMETERS,
                                    values = WRITER_VALUES,
                                )
                            @test_throws ArgumentError attempt()
                            message = thrown_message(attempt)
                            # The refusal names the canonical layout, so the
                            # alias is rejected for being noncanonical rather
                            # than slipping through as a development path.
                            @test occursin(
                                "case-studies/<case>/reference/<result-name>.toml",
                                message,
                            )
                            # Nothing was created: no alias directory, no
                            # canonical directory, no file, no temporary
                            # residue.
                            @test isempty(readdir(root))
                            if preset == "production"
                                # A production record cannot be refused by the
                                # smoke prohibition, so its refusal rests on the
                                # path rule alone.
                                @test !occursin("smoke preset", message)
                            end
                        end
                    end
                end
            end

            @testset "a refused alias leaves the canonical tree untouched" begin
                for alias in ("case-studies.", "CASE-STUDIES.", "case-studies   ")
                    with_reference_directory() do root, directory
                        canonical = joinpath(directory, "variance.toml")
                        write_reference_summary(
                            canonical;
                            provenance = WRITER_PROVENANCE,
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        )
                        before = read(canonical)
                        # A deliberately different record, so that an unrefused
                        # write would be visible in the bytes below. On Windows
                        # the alias resolves to the canonical directory, which
                        # is exactly how the Gate 3C-A.1 bypass landed there.
                        for preset in ("production", "smoke")
                            aliased = joinpath(
                                root,
                                alias,
                                "99-example-process",
                                "reference",
                                "variance.toml",
                            )
                            @test_throws ArgumentError write_reference_summary(
                                aliased;
                                provenance = merge(WRITER_PROVENANCE, (preset = preset,)),
                                parameters = (steps = 1, dt = 0.5),
                                values = (variance = (value = 2.0, kind = "exact"),),
                            )
                        end
                        @test read(canonical) == before
                        @test readdir(directory) == ["variance.toml"]
                    end
                end
            end

            @testset "the canonical and development contracts are unchanged" begin
                # Canonical lowercase production still succeeds.
                with_reference_directory() do root, directory
                    path = joinpath(directory, "variance.toml")
                    @test write_reference_summary(
                        path;
                        provenance = WRITER_PROVENANCE,
                        parameters = WRITER_PARAMETERS,
                        values = WRITER_VALUES,
                    ) === nothing
                    @test isfile(path)
                end
                # Canonical lowercase smoke still fails, and for the smoke
                # reason rather than a path one.
                with_reference_directory() do root, directory
                    path = joinpath(directory, "variance.toml")
                    message = thrown_message(
                        () -> write_reference_summary(
                            path;
                            provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        ),
                    )
                    @test occursin("must not record the smoke preset", message)
                    @test !occursin("the source path must be", message)
                    @test isempty(readdir(directory))
                end
                # A development destination outside the reference tree still
                # takes a smoke record, and still must end in a lowercase
                # `.toml`. A trailing dot on a directory that is not
                # `case-studies` changes nothing: the correction widens the
                # recognition of one component and of nothing else.
                mktempdir() do root
                    for directory in ("development", "development.")
                        parent = joinpath(root, directory)
                        mkpath(parent)
                        path = joinpath(parent, "draft.toml")
                        @test write_reference_summary(
                            path;
                            provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        ) === nothing
                        @test isfile(path)
                        @test TOML.parsefile(path)["provenance"]["preset"] == "smoke"
                        @test_throws ArgumentError write_reference_summary(
                            joinpath(parent, "draft.TOML");
                            provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                            parameters = WRITER_PARAMETERS,
                            values = WRITER_VALUES,
                        )
                    end
                end
            end

            @testset "the physical Windows alias is refused" begin
                if Sys.iswindows()
                    for alias in ("case-studies.", "CASE-STUDIES.")
                        with_reference_directory() do root, directory
                            aliased =
                                joinpath(root, alias, "99-example-process", "reference")
                            if isdir(aliased)
                                # The alias resolves physically on this host, so
                                # this is the demonstrated bypass and not a
                                # hypothetical one. It must be refused.
                                for preset in ("production", "smoke")
                                    @test_throws ArgumentError write_reference_summary(
                                        joinpath(aliased, "variance.toml");
                                        provenance = merge(
                                            WRITER_PROVENANCE,
                                            (preset = preset,),
                                        ),
                                        parameters = WRITER_PARAMETERS,
                                        values = WRITER_VALUES,
                                    )
                                end
                                @test isempty(readdir(directory))
                            else
                                # Recorded rather than passed over in silence.
                                # The lexical tests above remain the contract.
                                @info "this Windows host does not resolve the " *
                                      "trailing-dot alias; only the lexical " *
                                      "protection is exercised" alias
                                @test !isdir(aliased)
                            end
                        end
                    end
                else
                    # The physical alias is a Windows filesystem behaviour, and
                    # nothing about it is asserted on another platform. What
                    # holds everywhere is the lexical refusal.
                    @test _logical_reference_path("case-studies./$tail") ==
                          "case-studies./$tail"
                end
            end
        end

        # -------------------------------------------------------------------
        # Every destination ends in a lowercase `.toml`, committed or not.
        # -------------------------------------------------------------------
        @testset "every destination must end in .toml" begin
            # A development record outside the reference tree: smoke is permitted
            # there, but the extension is not negotiable.
            mktempdir() do root
                directory = joinpath(root, "development", "path")
                mkpath(directory)
                @test write_reference_summary(
                    joinpath(directory, "draft.toml");
                    provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                ) === nothing
                @test readdir(directory) == ["draft.toml"]
                @test TOML.parsefile(joinpath(directory, "draft.toml"))["provenance"]["preset"] ==
                      "smoke"
            end

            for name in ("draft.json", "draft.txt", "draft", "draft.TOML", "draft.tom")
                mktempdir() do root
                    directory = joinpath(root, "development")
                    mkpath(directory)
                    path = joinpath(directory, name)
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                        parameters = WRITER_PARAMETERS,
                        values = WRITER_VALUES,
                    )
                    @test occursin(
                        "extension is exactly `.toml`",
                        thrown_message(
                            () -> write_reference_summary(
                                path;
                                provenance = merge(
                                    WRITER_PROVENANCE,
                                    (preset = "smoke",),
                                ),
                                parameters = WRITER_PARAMETERS,
                                values = WRITER_VALUES,
                            ),
                        ),
                    )
                    # Nothing was created. The directory listing is the test
                    # rather than `ispath`, because a case-insensitive filesystem
                    # would resolve `draft.TOML` onto a `draft.toml` beside it.
                    @test isempty(readdir(directory))
                end
            end

            # The rule binds inside the committed tree as well.
            with_reference_directory() do root, directory
                @test_throws ArgumentError write_reference_summary(
                    joinpath(directory, "variance.json");
                    provenance = WRITER_PROVENANCE,
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end
        end

        # -------------------------------------------------------------------
        # G3-CORR.6. A destination carrying a control character never reaches
        # the filesystem.
        # -------------------------------------------------------------------
        @testset "a destination refuses control characters before writing" begin
            for character in ("\0", "\n", "\t", "\x1f", "\x7f", "\u0085", "\u009f")
                mktempdir() do root
                    directory = joinpath(root, "development")
                    mkpath(directory)
                    path = joinpath(directory, "dra$(character)ft.toml")
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = merge(WRITER_PROVENANCE, (preset = "smoke",)),
                        parameters = WRITER_PARAMETERS,
                        values = WRITER_VALUES,
                    )
                    @test occursin(
                        "must not contain a control character",
                        thrown_message(
                            () -> write_reference_summary(
                                path;
                                provenance = merge(
                                    WRITER_PROVENANCE,
                                    (preset = "smoke",),
                                ),
                                parameters = WRITER_PARAMETERS,
                                values = WRITER_VALUES,
                            ),
                        ),
                    )
                    @test isempty(readdir(directory))
                end
            end

            # The same rule reaches the record, not only the destination: a
            # driver path or a path-denoting parameter carrying a control
            # character is refused, and the target directory stays empty.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = merge(
                        WRITER_PROVENANCE,
                        (generated_by = "case-studies/99-example-process/dri\nver.jl",),
                    ),
                    parameters = WRITER_PARAMETERS,
                    values = WRITER_VALUES,
                )
                @test_throws ArgumentError write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (output_path = "results/run\u0085one",),
                    values = WRITER_VALUES,
                )
                @test isempty(readdir(directory))
            end
        end

        # -------------------------------------------------------------------
        # Schema version 1 stores payload reals in the Float64 domain.
        # -------------------------------------------------------------------
        @testset "payload reals are stored in the Float64 domain" begin
            # A `Rational` and a `BigFloat` are accepted and converted. The
            # assertion is against `Float64(x)` rather than against a decimal
            # spelling, so nothing here depends on how a platform renders a
            # float; and it deliberately does not claim that the extra precision
            # of either input survived, because it does not.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                third = 1 // 3
                tenth = BigFloat("0.1")
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (steps = 10_000, ratio = third, offset = tenth),
                    values = (
                        variance = (
                            value = 3 // 4,
                            kind = "estimate",
                            se = BigFloat("0.01"),
                        ),
                    ),
                )
                parsed = TOML.parsefile(path)
                @test parsed["parameters"]["ratio"] isa Float64
                @test parsed["parameters"]["ratio"] == Float64(third)
                @test parsed["parameters"]["offset"] isa Float64
                @test parsed["parameters"]["offset"] == Float64(tenth)
                @test parsed["values"]["variance"]["value"] == Float64(3 // 4)
                @test parsed["values"]["variance"]["se"] == Float64(BigFloat("0.01"))

                # The stored value is the `Float64` conversion, and the recorded
                # rational is not recoverable from it: the conversion rounded,
                # which is the documented behaviour rather than a defect.
                @test parsed["parameters"]["ratio"] != third
                @test Rational(parsed["parameters"]["ratio"]) != third

                # A second pass over the written file reproduces the same bytes,
                # so the conversion is deterministic.
                first_bytes = read(path)
                write_reference_summary(
                    path;
                    provenance = WRITER_PROVENANCE,
                    parameters = (steps = 10_000, ratio = third, offset = tenth),
                    values = (
                        variance = (
                            value = 3 // 4,
                            kind = "estimate",
                            se = BigFloat("0.01"),
                        ),
                    ),
                )
                @test read(path) == first_bytes

                # The written record satisfies the schema it was written under.
                @test isempty(
                    validate_reference_summary(
                        parsed;
                        source_path = "case-studies/99-example-process/reference/variance.toml",
                    ),
                )
            end

            # A value whose conversion is not finite remains refused, whether it
            # is nonfinite already or becomes so in the Float64 domain.
            with_reference_directory() do root, directory
                path = joinpath(directory, "variance.toml")
                for parameters in (
                    (overflowing = big(10.0)^400,),
                    (nonfinite = BigFloat(Inf),),
                    (undefined = BigFloat(NaN),),
                    (ratio = 1 // 0,),
                )
                    @test_throws ArgumentError write_reference_summary(
                        path;
                        provenance = WRITER_PROVENANCE,
                        parameters = parameters,
                        values = WRITER_VALUES,
                    )
                end
                @test isempty(readdir(directory))
            end

            # The validator judges such values by the same rule, and reports
            # rather than raising.
            for value in (big(10.0)^400, BigFloat(Inf), BigFloat(NaN))
                @test rejected(
                    record_with_value("value" => value, "kind" => "exact"),
                    "values.quantity.value",
                )
            end
            @test isempty(
                validate_reference_summary(
                    record_with_value("value" => 1 // 3, "kind" => "exact"),
                ),
            )
        end
    end

    # -----------------------------------------------------------------------
    # H. The verification script.
    # -----------------------------------------------------------------------
    @testset "the verification script" begin
        @testset "an empty register passes" begin
            with_verifier_repository() do root
                result = run_verifier(root)
                @test result.status == 0
                @test occursin("registered:         none", result.output)
                @test occursin(
                    "Result: PASS — scaffold valid, no reference summaries registered yet.",
                    result.output,
                )
                @test occursin("is the expected state of the", result.output)
            end
        end

        @testset "a valid summary passes" begin
            with_verifier_repository() do root
                write_summary_at(root, "99-example-process", "variance.toml")
                result = run_verifier(root)
                @test result.status == 0
                @test occursin(
                    "case-studies/99-example-process/reference/variance.toml: valid",
                    result.output,
                )
                @test occursin("1 reference summary validated", result.output)
            end
        end

        @testset "an invalid summary fails" begin
            with_verifier_repository() do root
                directory =
                    joinpath(root, "case-studies", "99-example-process", "reference")
                mkpath(directory)
                write(
                    joinpath(directory, "variance.toml"),
                    "schema_version = 1\n[provenance]\ncase = \"99-example-process\"\n",
                )
                result = run_verifier(root)
                @test result.status == 1
                @test occursin("Result: FAIL", result.output)
                @test occursin(
                    "case-studies/99-example-process/reference/variance.toml: INVALID",
                    result.output,
                )
                @test occursin("parameters is required and is absent", result.output)
            end
        end

        @testset "unparseable TOML fails without stopping the run" begin
            with_verifier_repository() do root
                directory =
                    joinpath(root, "case-studies", "99-example-process", "reference")
                mkpath(directory)
                write(joinpath(directory, "broken.toml"), "this is not = = TOML\n")
                write_summary_at(root, "99-example-process", "variance.toml")
                result = run_verifier(root)
                @test result.status == 1
                @test occursin("broken.toml: INVALID TOML", result.output)
                # The valid summary after it was still reached and reported.
                @test occursin("variance.toml: valid", result.output)
            end
        end

        @testset "every invalid file is reported" begin
            with_verifier_repository() do root
                for case in ("99-example-process", "07-other-case")
                    directory = joinpath(root, "case-studies", case, "reference")
                    mkpath(directory)
                    write(joinpath(directory, "one.toml"), "schema_version = 2\n")
                    write(joinpath(directory, "two.toml"), "unexpected = true\n")
                end
                result = run_verifier(root)
                @test result.status == 1
                for case in ("99-example-process", "07-other-case")
                    for name in ("one.toml", "two.toml")
                        @test occursin(
                            "case-studies/$case/reference/$name: INVALID",
                            result.output,
                        )
                    end
                end
            end
        end

        @testset "discovery is lexical and deterministic" begin
            with_verifier_repository() do root
                for (case, name) in (
                    ("07-other-case", "zeta.toml"),
                    ("99-example-process", "variance.toml"),
                    ("07-other-case", "alpha.toml"),
                    ("99-example-process", "displacement.toml"),
                )
                    directory = joinpath(root, "case-studies", case, "reference")
                    mkpath(directory)
                    write(joinpath(directory, name), "schema_version = 1\n")
                end
                # A file that is not TOML, and a case without a reference
                # directory, are both passed over.
                write(
                    joinpath(
                        root,
                        "case-studies",
                        "99-example-process",
                        "reference",
                        "notes.md",
                    ),
                    "prose\n",
                )
                mkpath(joinpath(root, "case-studies", "08-unstarted"))

                # Lexical by case directory first, then by result name, whatever
                # order the fixtures were created in: `07-other-case` precedes
                # `99-example-process`.
                expected = [
                    "case-studies/07-other-case/reference/alpha.toml",
                    "case-studies/07-other-case/reference/zeta.toml",
                    "case-studies/99-example-process/reference/displacement.toml",
                    "case-studies/99-example-process/reference/variance.toml",
                ]
                found = [file.logical for file in VERIFIER.reference_files(root)]
                @test found == expected
                @test found == [file.logical for file in VERIFIER.reference_files(root)]
                @test all(isfile(file.path) for file in VERIFIER.reference_files(root))
            end
        end

        @testset "a missing environment file fails" begin
            mktempdir() do root
                result = run_verifier(root)
                @test result.status == 1
                @test occursin("Project.toml is missing", result.output)
                @test occursin("Manifest.toml is missing", result.output)
            end
        end

        @testset "the repository root is located from the script" begin
            @test realpath(VERIFIER.repository_root()) == realpath(ROOT)
            @test isfile(joinpath(VERIFIER.repository_root(), "Project.toml"))
            # The committed repository still verifies, and registers nothing.
            @test isempty(VERIFIER.reference_files(ROOT))
        end
    end
end
