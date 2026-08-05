# Execution presets.
#
# The shared layer fixes the preset *vocabulary* and nothing else. What a preset
# means numerically — how many samples, how many time steps, how many replicates
# — is a scientific property of the case study that declares it, and differs
# between cases by orders of magnitude. Cases therefore own their preset values,
# and this file contributes only a constant and one validating lookup.
#
# There is deliberately no `Preset` type, no fallback preset, and no
# environment-variable override: a driver states which preset it runs, and an
# unrecognised name is an error rather than a silent substitution.

"""
    PRESETS

The three execution presets every driver exposes, in increasing order of cost:
`:smoke`, `:figure`, and `:production`.

Committed drivers default to `:smoke`, so that running one immediately after
cloning never starts an unexpectedly long computation. This tuple is the only
shared preset vocabulary; the numerical content of each preset belongs to the
case study that declares it. See `preset_parameters`.
"""
const PRESETS = (:smoke, :figure, :production)

"""
    _preset_list() -> String

Render the valid preset names for inclusion in an error message.
"""
_preset_list() = join(("`:$name`" for name in PRESETS), ", ")

"""
    _check_preset_table(table::NamedTuple) -> Nothing

Verify that `table` carries exactly one field per name in `PRESETS`, neither
fewer nor more. Field order is not significant. Any deviation throws an
`ArgumentError` naming the offending field.
"""
function _check_preset_table(table::NamedTuple)
    supplied = keys(table)
    for name in PRESETS
        name in supplied || throw(
            ArgumentError(
                "the preset table lacks the required field `$name`; it must carry " *
                "exactly one field per preset, namely $(_preset_list())",
            ),
        )
    end
    for name in supplied
        name in PRESETS || throw(
            ArgumentError(
                "the preset table carries the unrecognised field `$name`; it must " *
                "carry exactly one field per preset, namely $(_preset_list())",
            ),
        )
    end
    return nothing
end

"""
    preset_parameters(table::NamedTuple, preset::Symbol) -> NamedTuple

Select the parameter set that `table` declares for `preset`.

`table` maps preset names to parameter sets: it must carry exactly one field per
name in `PRESETS`, in any order, and the selected field must itself be a
`NamedTuple`. The returned value is that parameter set, unmodified.

The function validates the shape of a case study's preset table and nothing more.
It attaches no meaning to the parameter names a case chooses, supplies no default
values, and has no fallback: an unrecognised preset, a missing or surplus field,
or a selected value that is not a `NamedTuple` all throw an `ArgumentError`.

Inference returns a concrete type whenever the three parameter sets share one
`NamedTuple` type, which is the ordinary case.

# Examples

```julia
table = (
    smoke = (steps = 10, replicates = 4),
    figure = (steps = 1_000, replicates = 32),
    production = (steps = 100_000, replicates = 256),
)
preset_parameters(table, :smoke)  # (steps = 10, replicates = 4)
```
"""
function preset_parameters(table::NamedTuple, preset::Symbol)
    preset in PRESETS || throw(
        ArgumentError(
            "`:$preset` is not a valid execution preset; the valid presets are " *
            "$(_preset_list())",
        ),
    )
    _check_preset_table(table)
    parameters = table[preset]
    if parameters isa NamedTuple
        return parameters
    end
    throw(
        ArgumentError(
            "the parameter set declared for `:$preset` must be a `NamedTuple`, got " *
            "a value of type $(typeof(parameters))",
        ),
    )
end
