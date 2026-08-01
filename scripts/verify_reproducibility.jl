#!/usr/bin/env julia

# scripts/verify_reproducibility.jl
#
# Validate the reproducibility scaffold and every numerical reference summary
# registered with a case study.
#
# Canonical location of reference summaries:
#
#     case-studies/<slug>/reference/<name>.toml
#
# Each summary records a small number of committed scalar results together with
# the provenance needed to regenerate them. The contract is documented in
# docs/methods/reproducibility.md.
#
# Usage, from the repository root:
#
#     julia --project=. scripts/verify_reproducibility.jl
#
# At the present scaffold gate no case study has reached its implementation gate,
# so no reference summary exists. An empty register is the expected state and is
# reported as a pass: the script still validates the environment files on which
# every later reproduction depends. Tolerance-based comparison of committed
# reference values against freshly computed results is introduced together with
# the first case study.
#
# The script exits with status 0 when every check passes and 1 otherwise, so that
# it can be used directly as a continuous-integration step.

using TOML

const REPO_ROOT = dirname(@__DIR__)
const CASE_STUDIES_DIR = joinpath(REPO_ROOT, "case-studies")
const REFERENCE_SUBDIR = "reference"
const LABEL_WIDTH = 18

# Provisional provenance contract. Every reference summary must carry a
# `[provenance]` table containing at least these keys. The list is deliberately
# held in one place so that it can be extended by the gate that registers the
# first reference values.
const REQUIRED_PROVENANCE_KEYS =
    ("case", "seed", "julia_version", "git_commit", "generated_by")

"""
    parse_toml(path) -> Union{Dict{String,Any},String}

Parse the TOML file at `path`, returning the parsed table, or an error message
describing why parsing failed.
"""
function parse_toml(path::AbstractString)
    try
        return TOML.parsefile(path)
    catch err
        return sprint(showerror, err)
    end
end

"""
    check_environment() -> Vector{String}

Validate the repository-level environment files on which every reproduction
depends, and report the Julia version recorded in the canonical manifest. A
mismatch between the running Julia and the manifest is reported as a note rather
than a failure, because supported-version reproduction is statistical rather than
bitwise.
"""
function check_environment()
    problems = String[]
    println("Environment files")
    for name in ("Project.toml", "Manifest.toml")
        path = joinpath(REPO_ROOT, name)
        if !isfile(path)
            push!(problems, "$name is missing from the repository root")
            println("  ", rpad(name, LABEL_WIDTH), "missing")
            continue
        end
        parsed = parse_toml(path)
        if parsed isa AbstractDict
            println("  ", rpad(name, LABEL_WIDTH), "valid TOML")
        else
            push!(problems, "$name is not valid TOML: $parsed")
            println("  ", rpad(name, LABEL_WIDTH), "INVALID TOML")
        end
    end

    manifest = joinpath(REPO_ROOT, "Manifest.toml")
    parsed = isfile(manifest) ? parse_toml(manifest) : nothing
    recorded = parsed isa AbstractDict ? get(parsed, "julia_version", nothing) : nothing
    println("  ", rpad("julia (running)", LABEL_WIDTH), VERSION)
    println("  ", rpad("julia (manifest)", LABEL_WIDTH), something(recorded, "unrecorded"))
    if recorded !== nothing && recorded != string(VERSION)
        println("  note: the running Julia differs from the canonical manifest, so any")
        println("        reproduction performed here is statistical, not bitwise.")
    end
    return problems
end

"""
    reference_files() -> Vector{String}

Return every registered reference summary, in a deterministic order.
"""
function reference_files()
    files = String[]
    isdir(CASE_STUDIES_DIR) || return files
    for entry in sort(readdir(CASE_STUDIES_DIR))
        directory = joinpath(CASE_STUDIES_DIR, entry, REFERENCE_SUBDIR)
        isdir(directory) || continue
        for file in sort(readdir(directory))
            endswith(file, ".toml") && push!(files, joinpath(directory, file))
        end
    end
    return files
end

"""
    missing_provenance(data) -> Vector{String}

Return the required provenance keys absent from a parsed reference summary.
"""
function missing_provenance(data::AbstractDict)
    provenance = get(data, "provenance", nothing)
    provenance isa AbstractDict || return collect(REQUIRED_PROVENANCE_KEYS)
    return [key for key in REQUIRED_PROVENANCE_KEYS if !haskey(provenance, key)]
end

"""
    check_reference_files(files) -> Vector{String}

Validate the TOML syntax and the provenance metadata of every registered
reference summary. An empty register is not a failure.
"""
function check_reference_files(files::Vector{String})
    problems = String[]
    println()
    println("Numerical reference summaries")
    println("  canonical location: case-studies/<slug>/$REFERENCE_SUBDIR/<name>.toml")
    if isempty(files)
        println("  registered:         none")
        println()
        println("  No case study has reached its implementation gate, so no reference")
        println("  values have been registered. This is the expected state of the")
        println("  scaffold and is not a failure.")
        return problems
    end

    println("  registered:         ", length(files))
    println()
    for path in files
        relative = relpath(path, REPO_ROOT)
        parsed = parse_toml(path)
        if !(parsed isa AbstractDict)
            push!(problems, "$relative is not valid TOML: $parsed")
            println("  ", relative, ": INVALID TOML")
            continue
        end
        absent = missing_provenance(parsed)
        if isempty(absent)
            println("  ", relative, ": valid")
        else
            push!(problems, "$relative lacks provenance fields: " * join(absent, ", "))
            println("  ", relative, ": incomplete provenance")
        end
    end
    return problems
end

"""
    main() -> Int

Run every check and return the process exit status.
"""
function main()
    println("Reproducibility verification — StochasticCaseStudies")
    println()
    files = reference_files()
    problems = vcat(check_environment(), check_reference_files(files))
    println()
    if isempty(problems)
        if isempty(files)
            println("Result: PASS — scaffold valid, no reference summaries registered yet.")
        else
            noun = length(files) == 1 ? "summary" : "summaries"
            println(
                "Result: PASS — scaffold valid, $(length(files)) reference $noun validated.",
            )
        end
        return 0
    end
    println("Result: FAIL")
    for problem in problems
        println("  - ", problem)
    end
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
