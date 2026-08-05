using Test
using TOML

using StableRNGs
using StochasticCaseStudies

# Repository root: the directory that contains the package `Project.toml`.
const ROOT = pkgdir(StochasticCaseStudies)

@testset "StochasticCaseStudies scaffold" begin
    @testset "package loads" begin
        @test StochasticCaseStudies isa Module
        @test nameof(StochasticCaseStudies) === :StochasticCaseStudies
        @test ROOT !== nothing
        @test isdir(ROOT)
    end

    @testset "the package exports nothing" begin
        # Exporting nothing is settled policy rather than a scaffold artefact:
        # every shared function is reached through an explicit import, as in
        # `using StochasticCaseStudies: derive_seeds`, so that a driver names what
        # it depends on and no identifier enters a caller's namespace unannounced.
        # The public surface of the module is therefore exactly its own name, and
        # is expected to stay that way as case submodules are added.
        @test names(StochasticCaseStudies) == [:StochasticCaseStudies]
    end

    @testset "project metadata" begin
        project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
        @test project["name"] == "StochasticCaseStudies"
        @test Base.UUID(project["uuid"]) isa Base.UUID
        @test VersionNumber(project["version"]) isa VersionNumber
        @test project["compat"]["julia"] == "1.10"
        # The declared lower bound must actually admit the running Julia.
        @test VERSION >= v"1.10"
        # Every direct dependency carries a compat bound; none may be unbounded.
        for name in keys(project["deps"])
            @test haskey(project["compat"], name)
        end
    end

    @testset "governance and documentation scaffold" begin
        expected = [
            "README.md",
            "LICENSE",
            "LICENSE-CC-BY",
            "CITATION.cff",
            "CLAUDE.md",
            joinpath("case-studies", "README.md"),
            joinpath("docs", "decisions.md"),
            joinpath("docs", "notation.md"),
            joinpath("docs", "style-guide.md"),
            joinpath("docs", "references.bib"),
            joinpath("docs", "methods", "reproducibility.md"),
            joinpath("docs", "methods", "rng-and-seeding.md"),
            joinpath("docs", "methods", "error-analysis.md"),
            joinpath("scripts", "env_report.jl"),
            joinpath("scripts", "verify_reproducibility.jl"),
        ]
        for relative in expected
            @test isfile(joinpath(ROOT, relative))
        end
    end

    @testset "frozen-stream facility" begin
        # StableRNGs is the ratified mechanism for the rare cases in which a
        # frozen random stream is genuinely required; see
        # docs/methods/rng-and-seeding.md. The checks below confirm only that the
        # facility is available and deterministic, which is a property of the
        # tooling rather than of any scientific result. No assertion is made
        # about Julia's default random number generator.
        @test rand(StableRNG(20260731), 8) == rand(StableRNG(20260731), 8)
        @test rand(StableRNG(1), 8) != rand(StableRNG(2), 8)
    end
end

# The shared numerical layer. One file per source file, included in the same
# order; each declares its own imports and opens its own top-level testset, so
# that a later gate adds a line here rather than restructuring this file.
include("test_presets.jl")
include("test_randomness.jl")
include("test_brownian.jl")
include("test_statistics.jl")
include("test_correlated_statistics.jl")
include("test_error_analysis.jl")

# The shared reproducibility layer, in the same one-file-per-source-file pattern.
include("test_reproducibility.jl")
