#!/usr/bin/env julia

# scripts/env_report.jl
#
# Print a concise environment report for the active project.
#
# The report collects exactly the information that a published numerical result
# must be accompanied by: the Julia version, the active project and manifest, the
# platform, the available thread count, and the state of the Git working tree.
#
# Usage, from the repository root:
#
#     julia --project=. scripts/env_report.jl
#
# The script uses only the Julia standard library, so it runs in any environment
# in which the project can be instantiated. Git metadata is reported when it is
# available and is never required: the script degrades gracefully when Git is
# absent, when the directory is not a repository, or when a command fails.

using Pkg
using TOML

const REPO_ROOT = dirname(@__DIR__)
const LABEL_WIDTH = 20

"""
    field(label, value)

Print one aligned `label: value` line, rendering `nothing` as `unavailable`.
"""
function field(label::AbstractString, value)
    println("  ", rpad(label * ":", LABEL_WIDTH), value === nothing ? "unavailable" : value)
    return nothing
end

"""
    git(args...) -> Union{String,Nothing}

Run `git` inside the repository and return its trimmed standard output, or
`nothing` when Git is unavailable, the directory is not a repository, or the
command exits with a non-zero status.
"""
function git(args::AbstractString...)
    try
        cmd = `git -C $REPO_ROOT $(collect(args))`
        return strip(read(pipeline(cmd; stderr = devnull), String))
    catch
        return nothing
    end
end

"""
    manifest_path(project_file) -> Union{String,Nothing}

Return the manifest Julia would use alongside `project_file`, preferring a
version-specific `Manifest-vX.Y.toml` over the generic `Manifest.toml`.
"""
function manifest_path(project_file)
    project_file === nothing && return nothing
    directory = dirname(project_file)
    versioned = joinpath(directory, "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
    isfile(versioned) && return versioned
    generic = joinpath(directory, "Manifest.toml")
    return isfile(generic) ? generic : nothing
end

"""
    manifest_julia_version(path) -> Union{String,Nothing}

Return the Julia version recorded in the manifest at `path`, or `nothing` when
the manifest is absent, unreadable, or does not record one.
"""
function manifest_julia_version(path)
    path === nothing && return nothing
    try
        return get(TOML.parsefile(path), "julia_version", nothing)
    catch
        return nothing
    end
end

"""
    direct_dependencies() -> Union{Vector{Pair{String,String}},Nothing}

Return the name and version of every direct dependency of the active project,
sorted by name, or `nothing` when the environment cannot be queried.
"""
function direct_dependencies()
    entries = Pair{String,String}[]
    try
        for (_, info) in Pkg.dependencies()
            (info.is_direct_dep && info.version !== nothing) || continue
            push!(entries, info.name => string(info.version))
        end
    catch
        return nothing
    end
    return sort!(entries; by = first)
end

println("Environment report — StochasticCaseStudies")
println()

println("Julia")
field("version", VERSION)
field("threads", Threads.nthreads())
field("CPU threads", Sys.CPU_THREADS)
field("word size", Sys.WORD_SIZE)
field("kernel", Sys.KERNEL)
field("architecture", Sys.ARCH)
field("machine", Sys.MACHINE)

project_file = Base.active_project()
manifest_file = manifest_path(project_file)

println()
println("Environment")
field("project", project_file)
field("manifest", manifest_file)
field("manifest julia", manifest_julia_version(manifest_file))
field("repository root", REPO_ROOT)

recorded = manifest_julia_version(manifest_file)
if recorded !== nothing && recorded != string(VERSION)
    println()
    println("  Note: the running Julia differs from the version recorded in the manifest.")
    println("  Reproduction is then statistical rather than bitwise; see")
    println("  docs/methods/reproducibility.md.")
end

println()
println("Direct dependencies")
dependencies = direct_dependencies()
if dependencies === nothing
    println("  unavailable (the active environment could not be queried)")
elseif isempty(dependencies)
    println("  none")
else
    for (name, version) in dependencies
        field(name, version)
    end
end

println()
println("Git")
tree_state = git("status", "--porcelain")
field("commit", git("rev-parse", "HEAD"))
field("short commit", git("rev-parse", "--short", "HEAD"))
field("branch", git("rev-parse", "--abbrev-ref", "HEAD"))
field(
    "working tree",
    tree_state === nothing ? nothing : (isempty(tree_state) ? "clean" : "dirty"),
)
