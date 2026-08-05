using Test

using StochasticCaseStudies: PRESETS, preset_parameters

# The three preset tables below share one `NamedTuple` type across their fields,
# which is the ordinary case: a case study declares the same parameters at three
# costs. Inference then returns a concrete type, which the `@inferred` checks
# confirm.
const VALID_TABLE = (
    smoke = (steps = 10, replicates = 4),
    figure = (steps = 100, replicates = 16),
    production = (steps = 1000, replicates = 64),
)

"""
    error_message(f) -> String

Run `f` and return the rendered message of the exception it throws, or the empty
string if it does not throw. Used to check that an error names its offending
input rather than merely having the right type.
"""
function error_message(f)
    try
        f()
        return ""
    catch err
        return sprint(showerror, err)
    end
end

@testset "presets" begin
    @testset "vocabulary" begin
        @test PRESETS == (:smoke, :figure, :production)
        @test PRESETS isa NTuple{3,Symbol}
        @test length(unique(PRESETS)) == 3
    end

    @testset "resolution" begin
        @test preset_parameters(VALID_TABLE, :smoke) === (steps = 10, replicates = 4)
        @test preset_parameters(VALID_TABLE, :figure) === (steps = 100, replicates = 16)
        @test preset_parameters(VALID_TABLE, :production) ===
              (steps = 1000, replicates = 64)
        # The parameter set is returned unmodified: no default is supplied and no
        # field is renamed.
        @test keys(preset_parameters(VALID_TABLE, :smoke)) == (:steps, :replicates)
    end

    @testset "field order is not significant" begin
        reordered = (
            production = (steps = 1000, replicates = 64),
            smoke = (steps = 10, replicates = 4),
            figure = (steps = 100, replicates = 16),
        )
        for preset in PRESETS
            @test preset_parameters(reordered, preset) ===
                  preset_parameters(VALID_TABLE, preset)
        end
    end

    @testset "malformed tables and presets are rejected" begin
        missing_field = (smoke = (steps = 10,), figure = (steps = 100,))
        @test_throws ArgumentError preset_parameters(missing_field, :smoke)

        extra_field = (
            smoke = (steps = 10,),
            figure = (steps = 100,),
            production = (steps = 1000,),
            draft = (steps = 1,),
        )
        @test_throws ArgumentError preset_parameters(extra_field, :smoke)

        @test_throws ArgumentError preset_parameters(VALID_TABLE, :draft)
        @test_throws ArgumentError preset_parameters(VALID_TABLE, :Smoke)

        not_a_namedtuple =
            (smoke = 10, figure = (steps = 100,), production = (steps = 1000,))
        @test_throws ArgumentError preset_parameters(not_a_namedtuple, :smoke)
        # The other two fields of that table are well formed, so selecting one of
        # them must still succeed: only the selected value is required to be a
        # parameter set.
        @test preset_parameters(not_a_namedtuple, :figure) === (steps = 100,)
    end

    @testset "error messages identify the input and list the presets" begin
        message = error_message(() -> preset_parameters(VALID_TABLE, :draft))
        @test occursin("draft", message)
        for preset in PRESETS
            @test occursin(String(preset), message)
        end

        missing_field = (smoke = (steps = 10,), figure = (steps = 100,))
        message = error_message(() -> preset_parameters(missing_field, :smoke))
        @test occursin("production", message)

        extra_field = (
            smoke = (steps = 10,),
            figure = (steps = 100,),
            production = (steps = 1000,),
            draft = (steps = 1,),
        )
        message = error_message(() -> preset_parameters(extra_field, :smoke))
        @test occursin("draft", message)
    end

    @testset "type stability" begin
        for preset in PRESETS
            @test @inferred(preset_parameters(VALID_TABLE, preset)) isa
                  NamedTuple{(:steps, :replicates),Tuple{Int,Int}}
        end
    end
end
