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
# the provenance needed to regenerate them. The schema is version 1, and it is
# defined and enforced by the package, not here: this script discovers the files,
# parses them, and calls `StochasticCaseStudies.validate_reference_summary` with
# the repository-relative path of each, so that the committed-location rules apply
# as well as the schema. The contract is documented in
# docs/methods/reproducibility.md.
#
# Usage, from the repository root:
#
#     julia --project=. scripts/verify_reproducibility.jl
#
# No case study has reached its implementation gate, so no reference summary
# exists. An empty register is the expected state and is reported as a pass: the
# script still validates the environment files on which every later reproduction
# depends. Tolerance-based comparison of committed reference values against
# freshly computed results is introduced together with the first case study; this
# script makes no numerical comparison.
#
# The script reads. It writes nothing, creates nothing, and never invokes Git.
#
# Every check is run before a verdict is reached, so that a run reports all of its
# problems rather than only the first. The script exits with status 0 when every
# check passes and 1 otherwise, so that it can be used directly as a
# continuous-integration step.

using TOML

using StochasticCaseStudies
using StochasticCaseStudies: validate_reference_summary

const CASE_STUDIES_DIR = "case-studies"
const REFERENCE_SUBDIR = "reference"
const LABEL_WIDTH = 18

"""
    repository_root() -> String

Locate the repository root.

The script's own directory is the primary evidence, because it is correct however
the script was invoked and whatever the working directory is. The package root is
consulted only if that fails, which would mean the script had been copied out of
the repository.
"""
function repository_root()
    here = dirname(@__DIR__)
    isfile(joinpath(here, "Project.toml")) && return here
    package = pkgdir(StochasticCaseStudies)
    return package === nothing ? here : package
end

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
    check_environment(io::IO, root::AbstractString) -> Vector{String}

Validate the repository-level environment files on which every reproduction
depends, and report the Julia version recorded in the canonical manifest. A
mismatch between the running Julia and the manifest is reported as a note rather
than a failure, because supported-version reproduction is statistical rather than
bitwise.
"""
function check_environment(io::IO, root::AbstractString)
    problems = String[]
    println(io, "Environment files")
    for name in ("Project.toml", "Manifest.toml")
        path = joinpath(root, name)
        if !isfile(path)
            push!(problems, "$name is missing from the repository root")
            println(io, "  ", rpad(name, LABEL_WIDTH), "missing")
            continue
        end
        parsed = parse_toml(path)
        if parsed isa AbstractDict
            println(io, "  ", rpad(name, LABEL_WIDTH), "valid TOML")
        else
            push!(problems, "$name is not valid TOML: $parsed")
            println(io, "  ", rpad(name, LABEL_WIDTH), "INVALID TOML")
        end
    end

    manifest = joinpath(root, "Manifest.toml")
    parsed = isfile(manifest) ? parse_toml(manifest) : nothing
    recorded = parsed isa AbstractDict ? get(parsed, "julia_version", nothing) : nothing
    println(io, "  ", rpad("julia (running)", LABEL_WIDTH), VERSION)
    println(
        io,
        "  ",
        rpad("julia (manifest)", LABEL_WIDTH),
        something(recorded, "unrecorded"),
    )
    if recorded !== nothing && recorded != string(VERSION)
        println(io, "  note: the running Julia differs from the canonical manifest, so any")
        println(io, "        reproduction performed here is statistical, not bitwise.")
    end
    return problems
end

"""
    reference_files(root::AbstractString) -> Vector{NamedTuple}

Return every registered reference summary as a pair of its absolute `path` and
its repository-relative `logical` path, in deterministic lexical order.

The logical path uses forward slashes on every platform, because it is the value
the schema validates against the canonical location, not a filesystem path.
"""
function reference_files(root::AbstractString)
    files = NamedTuple{(:path, :logical),Tuple{String,String}}[]
    directory = joinpath(root, CASE_STUDIES_DIR)
    isdir(directory) || return files
    for case in sort(readdir(directory))
        subdirectory = joinpath(directory, case, REFERENCE_SUBDIR)
        isdir(subdirectory) || continue
        for name in sort(readdir(subdirectory))
            endswith(name, ".toml") || continue
            isfile(joinpath(subdirectory, name)) || continue
            push!(
                files,
                (
                    path = joinpath(subdirectory, name),
                    logical = join((CASE_STUDIES_DIR, case, REFERENCE_SUBDIR, name), "/"),
                ),
            )
        end
    end
    return files
end

"""
    check_reference_files(io::IO, files) -> Vector{String}

Parse and validate every registered reference summary against schema version 1
and its committed location. An empty register is not a failure.

Every file is processed and every problem of every file is reported: a run that
stopped at the first invalid summary would hide the rest behind it.
"""
function check_reference_files(io::IO, files::Vector{<:NamedTuple})
    problems = String[]
    println(io)
    println(io, "Numerical reference summaries")
    println(
        io,
        "  canonical location: $CASE_STUDIES_DIR/<slug>/$REFERENCE_SUBDIR/<name>.toml",
    )
    if isempty(files)
        println(io, "  registered:         none")
        println(io)
        println(io, "  No case study has reached its implementation gate, so no reference")
        println(io, "  values have been registered. This is the expected state of the")
        println(io, "  scaffold and is not a failure.")
        return problems
    end

    println(io, "  registered:         ", length(files))
    println(io)
    for file in files
        parsed = parse_toml(file.path)
        if !(parsed isa AbstractDict)
            push!(problems, "$(file.logical) is not valid TOML: $parsed")
            println(io, "  ", file.logical, ": INVALID TOML")
            continue
        end
        found = validate_reference_summary(parsed; source_path = file.logical)
        if isempty(found)
            println(io, "  ", file.logical, ": valid")
        else
            for problem in found
                push!(problems, "$(file.logical): $problem")
            end
            noun = length(found) == 1 ? "problem" : "problems"
            println(io, "  ", file.logical, ": INVALID — ", length(found), " ", noun)
        end
    end
    return problems
end

"""
    verify(io::IO, root::AbstractString) -> Int

Run every check against the repository at `root`, report to `io`, and return the
process exit status: 0 when everything passes and 1 otherwise.
"""
function verify(io::IO, root::AbstractString)
    println(io, "Reproducibility verification — StochasticCaseStudies")
    println(io)
    files = reference_files(root)
    problems = vcat(check_environment(io, root), check_reference_files(io, files))
    println(io)
    if isempty(problems)
        if isempty(files)
            println(
                io,
                "Result: PASS — scaffold valid, no reference summaries registered yet.",
            )
        else
            noun = length(files) == 1 ? "summary" : "summaries"
            println(
                io,
                "Result: PASS — scaffold valid, $(length(files)) reference $noun validated.",
            )
        end
        return 0
    end
    println(io, "Result: FAIL")
    for problem in problems
        println(io, "  - ", problem)
    end
    return 1
end

"""
    main() -> Int

Verify the repository this script belongs to, reporting to standard output.
"""
main() = verify(stdout, repository_root())

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
