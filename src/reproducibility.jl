# Reproducibility records.
#
# A committed reference summary is the small TOML file that lets a reader confirm
# a rerun: a handful of scalar results, the resolved parameters that produced
# them, and the provenance needed to reconstruct the environment. This file
# implements the schema fixed by G3-D.9 — one version integer and three tables,
# and nothing else — together with the provenance capture, the atomic writer, and
# the validator that scripts/verify_reproducibility.jl calls. The contract is
# documented in docs/methods/reproducibility.md.
#
# Three properties shape the design.
#
# The schema is versioned, so that a later change to the required fields is a
# visible migration rather than a silent divergence between old files and new
# ones. Unknown keys are rejected for the same reason: a field nobody validates is
# a field nobody can trust.
#
# The validator is pure. It reads a parsed table and returns the problems it
# found; it writes nothing, inspects no repository, reads no environment variable,
# and raises no exception of its own for malformed input. That is what makes one
# implementation serve both the writer, before any file exists, and the
# verification script, on a file somebody else wrote.
#
# Provenance is captured only from a clean tree. A dirty-state flag would record
# that a result is unreproducible without preventing it; requiring the tree to be
# clean instead means the recorded commit alone identifies the code and the
# committed manifest, and therefore the environment. Nothing else about the local
# machine is recorded as identity: the Julia version, the thread count, and the
# operating system are context for a reader, not part of the contract, and no
# absolute local path is recorded at all.

const _SCHEMA_VERSION = 1

const _TOP_LEVEL_KEYS = ("parameters", "provenance", "schema_version", "values")

const _REQUIRED_PROVENANCE_KEYS = (
    "case",
    "generated",
    "generated_by",
    "git_commit",
    "julia_version",
    "preset",
    "rng",
    "seed",
)

const _OPTIONAL_PROVENANCE_KEYS = ("note", "os", "threads")

const _VALUE_KINDS = ("exact", "estimate")

const _UNCERTAINTY_KEYS = ("ci_lower", "ci_upper", "se")

# Reserved keys of a `[values.<name>]` table. A case study may add further fields
# of its own, but never one of these under a different meaning.
const _RESERVED_VALUE_KEYS = (
    "ci_lower",
    "ci_upper",
    "kind",
    "method",
    "note",
    "se",
    "tolerance_abs",
    "tolerance_rel",
    "units",
    "value",
)

const _CASE_PATTERN = r"^[0-9]{2}-[a-z0-9]+(?:-[a-z0-9]+)*$"
const _SLUG_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"
const _COMMIT_PATTERN = r"^[0-9a-f]{40}$"
const _TIMESTAMP_PATTERN =
    r"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$"

# A reference summary is a shallow record by design. The bound exists so that a
# self-referential table supplied by a caller is reported as a problem rather
# than exhausting the stack, which no `try` could catch.
const _MAX_TABLE_DEPTH = 8

# Field names under which an absolute filesystem path would be recorded as
# metadata. This is a guard against the commonest way a local path reaches a
# committed record, not a general path detector.
const _PATH_KEY_WORDS =
    ("dir", "directory", "file", "files", "folder", "path", "paths", "root")

# ---------------------------------------------------------------------------
# Small shared helpers.
# ---------------------------------------------------------------------------

"""
    _describe(value) -> String

Render the type of `value` for an error message, without rendering the value
itself, which may be arbitrarily large.
"""
_describe(value) = "a value of type $(typeof(value))"

"""
    _field(table::AbstractDict, name::AbstractString) -> Any

Return the entry of `table` whose key renders as `name`, or `nothing` if there is
none.

Keys are compared through `string` so that a table parsed from TOML and one built
by hand with `Symbol` keys are read alike. TOML never produces `nothing` as a
value, so the sentinel is unambiguous.
"""
function _field(table::AbstractDict, name::AbstractString)
    for (key, value) in table
        string(key) == name && return value
    end
    return nothing
end

"""
    _field_names(table::AbstractDict) -> Vector{String}

Return the keys of `table` as sorted strings, so that reported problems appear in
a deterministic order whatever the iteration order of the underlying dictionary.
"""
_field_names(table::AbstractDict) = sort!([string(key) for key in keys(table)])

"""
    _is_nonempty_string(value) -> Bool

Whether `value` is a string with at least one character.
"""
_is_nonempty_string(value) = value isa AbstractString && !isempty(value)

"""
    _is_control_character(character::AbstractChar) -> Bool

Whether `character` is a Unicode control character — `U+0000`–`U+001F` or
`U+007F`–`U+009F`.

Nothing else is singled out. Spaces, punctuation, percent signs, and letters
outside ASCII are ordinary text in a path and are treated as such; a control
character is not text at all, and one embedded in a string that later names a
file makes the rendered path disagree with the bytes that open it.
"""
function _is_control_character(character::AbstractChar)
    isvalid(character) || return false
    point = UInt32(character)
    return point <= 0x1f || (0x7f <= point <= 0x9f)
end

"""
    _control_character_problem(value) -> Union{Nothing,String}

Describe the first Unicode control character `value` carries, or return `nothing`
if it carries none.

The offending character is named by code point and never reproduced, so that a
problem report cannot itself be corrupted by what it describes. The clause is
phrased to follow the subject it qualifies, as in `"the source path " * problem`.
"""
function _control_character_problem(value)
    value isa AbstractString || return nothing
    for (position, character) in enumerate(value)
        _is_control_character(character) && return string(
            "must not contain a control character, but carries U+",
            uppercase(string(UInt32(character); base = 16, pad = 4)),
            " at character $position",
        )
    end
    return nothing
end

"""
    _note_problem(value) -> Union{Nothing,String}

Describe why `value` is not an acceptable reserved note, or return `nothing` if
it is one.

A note is free prose written for a reader. Tabs, newlines, and several paragraphs
are all legitimate in one, and no restriction is placed on ordinary Unicode. Only
`NUL` is refused: it terminates a string in every filesystem and process
interface the record will pass through, so a note carrying one is a note whose
committed form and rendered form need not agree.
"""
function _note_problem(value)
    value isa AbstractString || return "must be a string, got $(_describe(value))"
    occursin('\0', value) && return "must not contain the NUL character U+0000"
    return nothing
end

"""
    _real_problem(value) -> Union{Nothing,String}

Describe why `value` is not a finite real number in the `Float64` domain, or
return `nothing` if it is one.

`Bool` is excluded although it subtypes `Integer`: a flag recorded where a
measurement belongs is a mistake worth naming rather than a number worth
promoting.
"""
function _real_problem(value)
    (value isa Real && !(value isa Bool)) ||
        return "must be a number, got $(_describe(value))"
    isfinite(value) || return "must be finite, got $value"
    representable = try
        isfinite(Float64(value))
    catch
        false
    end
    representable || return "must be finite in the `Float64` domain, got $value"
    return nothing
end

"""
    _fits_int64(value::Integer) -> Bool

Whether `value` lies in the signed 64-bit range that TOML records as an integer.
The comparison is exact for every integer type, including `BigInt` and unsigned
values above `typemax(Int64)`.
"""
_fits_int64(value::Integer) = typemin(Int64) <= value <= typemax(Int64)

"""
    _denotes_path(name::AbstractString) -> Bool

Whether a field called `name` denotes a filesystem path, and so must not carry an
absolute local one.
"""
function _denotes_path(name::AbstractString)
    lowered = lowercase(name)
    return any(word -> lowered == word || endswith(lowered, "_" * word), _PATH_KEY_WORDS)
end

"""
    _is_absolute_path(value::AbstractString) -> Bool

Whether `value` is an absolute path in POSIX or Windows form, including a drive
prefix and a UNC share.
"""
function _is_absolute_path(value::AbstractString)
    isempty(value) && return false
    (startswith(value, '/') || startswith(value, '\\')) && return true
    return occursin(r"^[A-Za-z]:[\\/]", value)
end

"""
    _relative_path_problem(value) -> Union{Nothing,String}

Describe why `value` is not a safe repository-relative logical path, or return
`nothing` if it is one.

A logical path uses forward slashes, begins at the repository root, and names no
component that could escape it. The clause is phrased to follow the subject it
qualifies, as in `"the source path " * problem`.

A control character is refused before anything else is inspected, and reported
without being echoed. Percent-encoded text is read literally: `%2F` is three
ordinary characters and never a separator, because a record that had to be URL
decoded before it could be checked would be checked in a form nobody committed.
Unicode characters that merely look like a solidus — `U+2044`, `U+2215`,
`U+FF0F` — are likewise ordinary characters within a component.
"""
function _relative_path_problem(value)
    value isa AbstractString || return "must be a string, got $(_describe(value))"
    isempty(value) && return "must be nonempty"
    control = _control_character_problem(value)
    control === nothing || return control
    occursin('\\', value) && return "must use forward slashes, got \"$value\""
    occursin(r"^[A-Za-z]:", value) && return "must not carry a drive prefix, got \"$value\""
    startswith(value, '/') && return "must be repository-relative, got \"$value\""
    components = split(value, '/')
    any(isempty, components) && return "must not contain an empty component, got \"$value\""
    any(component -> component in (".", ".."), components) &&
        return "must not contain a `.` or `..` component, got \"$value\""
    return nothing
end

"""
    _timestamp_problem(value) -> Union{Nothing,String}

Describe why `value` is not a canonical RFC 3339 UTC timestamp of the form
`YYYY-MM-DDTHH:MM:SSZ`, or return `nothing` if it is one.

Both the syntax and the calendar are checked, so that `2026-02-30T00:00:00Z` and
`2026-01-01T24:00:00Z` are rejected although each matches the pattern. The `Z`
suffix is mandatory: a local offset, or a bare `DateTime` with no zone at all,
records an instant a reader cannot place.

Canonicity is decided by requiring the parsed instant to render back through
[`_utc_timestamp`](@ref) unchanged, so that the form has exactly one definition in
this file. That is what rejects hour `24`: Julia admits it as ISO 8601's
end-of-day and rolls it into the following midnight, but RFC 3339 does not, and
two spellings of one instant are two records that will not compare equal.
"""
function _timestamp_problem(value)
    value isa AbstractString || return "must be a string, got $(_describe(value))"
    matched = match(_TIMESTAMP_PATTERN, value)
    matched === nothing &&
        return "must have the canonical form YYYY-MM-DDTHH:MM:SSZ, got \"$value\""
    parts = map(part -> parse(Int, part), matched.captures)
    moment = try
        DateTime(parts[1], parts[2], parts[3], parts[4], parts[5], parts[6])
    catch
        return "names an impossible date or time, got \"$value\""
    end
    canonical = _utc_timestamp(moment)
    canonical == value ||
        return "must be canonical, and \"$value\" spells the instant \"$canonical\""
    return nothing
end

"""
    _utc_timestamp(moment::DateTime = now(UTC)) -> String

Render `moment`, truncated to the second, as a canonical RFC 3339 UTC timestamp.

The components are laid out explicitly rather than delegated to a display method,
so that the recorded form is fixed here and does not follow a change in how Julia
chooses to print a `DateTime`.
"""
function _utc_timestamp(moment::DateTime = now(UTC))
    truncated = trunc(moment, Second)
    return string(
        lpad(year(truncated), 4, '0'),
        "-",
        lpad(month(truncated), 2, '0'),
        "-",
        lpad(day(truncated), 2, '0'),
        "T",
        lpad(hour(truncated), 2, '0'),
        ":",
        lpad(minute(truncated), 2, '0'),
        ":",
        lpad(second(truncated), 2, '0'),
        "Z",
    )
end

"""
    _operating_system() -> String

A short stable identifier for the operating system the process runs on.

This is machine context recorded for a reader, not part of the scientific
contract: no result of this repository is claimed to depend on it.
"""
function _operating_system()
    Sys.iswindows() && return "windows"
    Sys.isapple() && return "macos"
    Sys.islinux() && return "linux"
    Sys.isbsd() && return "bsd"
    return lowercase(String(Sys.KERNEL))
end

# ---------------------------------------------------------------------------
# Recursive payload validation.
# ---------------------------------------------------------------------------

"""
    _check_payload!(problems::Vector{String}, value, label::AbstractString, depth::Int)

Append to `problems` every reason `value` cannot be recorded durably in TOML
under the name `label`.

The permitted payload is deliberately narrow: strings, booleans, integers inside
the signed 64-bit range, finite reals, homogeneous arrays of those scalars, and
nested tables with nonempty string keys. A heterogeneous array is rejected rather
than promoted, because promoting one would silently change the type a reader
later parses; a caller that wants a float array converts it and says so.
"""
function _check_payload!(problems::Vector{String}, value, label::AbstractString, depth::Int)
    if depth > _MAX_TABLE_DEPTH
        push!(problems, "$label nests more than $_MAX_TABLE_DEPTH tables deep")
        return nothing
    end
    if value isa AbstractString || value isa Bool
        return nothing
    elseif value isa Integer
        _fits_int64(value) || push!(
            problems,
            "$label is an integer outside the signed 64-bit range TOML records, got $value",
        )
        return nothing
    elseif value isa Real
        problem = _real_problem(value)
        problem === nothing || push!(problems, "$label $problem")
        return nothing
    elseif value isa AbstractArray
        _check_array!(problems, value, label)
        return nothing
    elseif value isa AbstractDict
        _check_table!(problems, value, label, depth)
        return nothing
    end
    push!(problems, "$label cannot be recorded in TOML, got $(_describe(value))")
    return nothing
end

"""
    _check_array!(problems::Vector{String}, value::AbstractArray, label::AbstractString)

Append to `problems` every reason `value` is not a homogeneous array of supported
scalars. An empty array is permitted and round-trips unchanged.
"""
function _check_array!(
    problems::Vector{String},
    value::AbstractArray,
    label::AbstractString,
)
    kinds = Set{Symbol}()
    for (position, element) in enumerate(value)
        name = "$label[$position]"
        if element isa AbstractString
            push!(kinds, :string)
        elseif element isa Bool
            push!(kinds, :boolean)
        elseif element isa Integer
            push!(kinds, :integer)
            _fits_int64(element) || push!(
                problems,
                "$name is an integer outside the signed 64-bit range TOML records, " *
                "got $element",
            )
        elseif element isa Real
            push!(kinds, :real)
            problem = _real_problem(element)
            problem === nothing || push!(problems, "$name $problem")
        else
            push!(kinds, :unsupported)
            push!(
                problems,
                "$name must be a string, a boolean, or a number, got $(_describe(element))",
            )
        end
    end
    length(kinds) <= 1 || push!(
        problems,
        "$label mixes element types and cannot be recorded durably; convert the " *
        "array to one element type before recording it",
    )
    return nothing
end

"""
    _check_table!(problems::Vector{String}, table::AbstractDict, label::AbstractString,
                  depth::Int)

Append to `problems` every reason `table` is not a durable TOML table, and
recurse into its entries.
"""
function _check_table!(
    problems::Vector{String},
    table::AbstractDict,
    label::AbstractString,
    depth::Int,
)
    for name in _field_names(table)
        child = isempty(label) ? name : "$label.$name"
        if isempty(name)
            push!(problems, "$label carries an entry with an empty key")
            continue
        end
        value = _field(table, name)
        _check_local_path!(problems, value, name, child)
        _check_payload!(problems, value, child, depth + 1)
    end
    return nothing
end

"""
    _check_local_path!(problems::Vector{String}, value, name::AbstractString,
                       label::AbstractString)

Append a problem when a field whose name denotes a path carries an absolute local
one, whether directly or as an element of an array.

A committed record names the repository, never the machine that produced it: an
absolute path is meaningless to every reader but its author, and frequently
discloses a home directory as well. A control character is refused in the same
place and for the same reason a destination path may not carry one: a field that
denotes a path is a field somebody will eventually open.
"""
function _check_local_path!(
    problems::Vector{String},
    value,
    name::AbstractString,
    label::AbstractString,
)
    _denotes_path(name) || return nothing
    if value isa AbstractString
        _is_absolute_path(value) &&
            push!(problems, "$label records the absolute local path \"$value\"")
        control = _control_character_problem(value)
        control === nothing || push!(problems, "$label $control")
    elseif value isa AbstractArray
        for (position, element) in enumerate(value)
            element isa AbstractString || continue
            _is_absolute_path(element) && push!(
                problems,
                "$label[$position] records the absolute local path \"$element\"",
            )
            control = _control_character_problem(element)
            control === nothing || push!(problems, "$label[$position] $control")
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Provenance validation.
# ---------------------------------------------------------------------------

"""
    _check_provenance!(problems::Vector{String}, provenance::AbstractDict)

Append to `problems` every violation of the schema version 1 provenance contract.
"""
function _check_provenance!(problems::Vector{String}, provenance::AbstractDict)
    for name in _REQUIRED_PROVENANCE_KEYS
        _field(provenance, name) === nothing &&
            push!(problems, "provenance.$name is required and is absent")
    end
    for name in _field_names(provenance)
        (name in _REQUIRED_PROVENANCE_KEYS || name in _OPTIONAL_PROVENANCE_KEYS) || push!(
            problems,
            "provenance.$name is not a field of reference-summary schema version " *
            "$_SCHEMA_VERSION",
        )
    end

    case = _field(provenance, "case")
    if case !== nothing
        if !(case isa AbstractString)
            push!(problems, "provenance.case must be a string, got $(_describe(case))")
        elseif !occursin(_CASE_PATTERN, case)
            push!(
                problems,
                "provenance.case must be a slug of the form NN-lowercase-hyphenated-name, " *
                "got \"$case\"",
            )
        end
    end

    generated = _field(provenance, "generated")
    if generated !== nothing
        problem = _timestamp_problem(generated)
        problem === nothing || push!(problems, "provenance.generated $problem")
    end

    _check_generated_by!(problems, _field(provenance, "generated_by"), case)

    commit = _field(provenance, "git_commit")
    if commit !== nothing
        if !(commit isa AbstractString)
            push!(
                problems,
                "provenance.git_commit must be a string, got $(_describe(commit))",
            )
        elseif !occursin(_COMMIT_PATTERN, commit)
            push!(
                problems,
                "provenance.git_commit must be a full forty-character lowercase " *
                "hexadecimal Git object identifier, got \"$commit\"",
            )
        end
    end

    version = _field(provenance, "julia_version")
    if version !== nothing
        if !_is_nonempty_string(version)
            push!(
                problems,
                "provenance.julia_version must be a nonempty string, got " *
                "$(_describe(version))",
            )
        else
            accepted = try
                VersionNumber(version)
                true
            catch
                false
            end
            accepted || push!(
                problems,
                "provenance.julia_version must be a version number, got \"$version\"",
            )
        end
    end

    preset = _field(provenance, "preset")
    if preset !== nothing && !any(name -> preset == String(name), PRESETS)
        push!(
            problems,
            "provenance.preset must be one of $(_preset_names()), got $(repr(preset))",
        )
    end

    rng = _field(provenance, "rng")
    rng === nothing ||
        _is_nonempty_string(rng) ||
        push!(problems, "provenance.rng must be a nonempty string, got $(_describe(rng))")

    seed = _field(provenance, "seed")
    if seed !== nothing
        if !(seed isa Integer) || seed isa Bool
            push!(problems, "provenance.seed must be an integer, got $(_describe(seed))")
        elseif !(0 <= seed <= typemax(Int64))
            push!(
                problems,
                "provenance.seed must satisfy 0 ≤ seed ≤ $(typemax(Int64)), got $seed",
            )
        end
    end

    threads = _field(provenance, "threads")
    if threads !== nothing
        if !(threads isa Integer) || threads isa Bool
            push!(
                problems,
                "provenance.threads must be an integer, got $(_describe(threads))",
            )
        elseif !(1 <= threads <= typemax(Int64))
            push!(
                problems,
                "provenance.threads must satisfy 1 ≤ threads ≤ $(typemax(Int64)), got " *
                "$threads",
            )
        end
    end

    operating_system = _field(provenance, "os")
    operating_system === nothing ||
        _is_nonempty_string(operating_system) ||
        push!(
            problems,
            "provenance.os must be a nonempty string, got $(_describe(operating_system))",
        )

    note = _field(provenance, "note")
    if note !== nothing
        problem = _note_problem(note)
        problem === nothing || push!(problems, "provenance.note $problem")
    end
    return nothing
end

"""
    _preset_names() -> String

Render the valid preset names as they appear in a reference summary, for
inclusion in an error message.
"""
_preset_names() = join(("\"$name\"" for name in PRESETS), ", ")

"""
    _check_generated_by!(problems::Vector{String}, value, case)

Append to `problems` every reason `value` is not an acceptable `generated_by`
path for the case `case`.

The driver is named by its repository-relative path, so that the record points at
a file a reader can open in their own checkout.
"""
function _check_generated_by!(problems::Vector{String}, value, case)
    value === nothing && return nothing
    problem = _relative_path_problem(value)
    if problem !== nothing
        push!(problems, "provenance.generated_by $problem")
        return nothing
    end
    endswith(value, ".jl") || push!(
        problems,
        "provenance.generated_by must name a Julia driver ending in .jl, got \"$value\"",
    )
    components = split(value, '/')
    if length(components) < 3 || components[1] != "case-studies"
        push!(
            problems,
            "provenance.generated_by must lie under case-studies/<case>/, got \"$value\"",
        )
        return nothing
    end
    case isa AbstractString && components[2] != case &&
        push!(
            problems,
            "provenance.generated_by lies under case-studies/$(components[2])/ but the " *
            "record declares the case \"$case\"",
        )
    return nothing
end

# ---------------------------------------------------------------------------
# Value validation.
# ---------------------------------------------------------------------------

"""
    _check_values!(problems::Vector{String}, values::AbstractDict)

Append to `problems` every violation of the schema version 1 values contract.
"""
function _check_values!(problems::Vector{String}, values::AbstractDict)
    for name in _field_names(values)
        if isempty(name)
            push!(problems, "values carries a result with an empty name")
            continue
        end
        entry = _field(values, name)
        if !(entry isa AbstractDict)
            push!(problems, "values.$name must be a table, got $(_describe(entry))")
            continue
        end
        _check_value_entry!(problems, entry, "values.$name")
    end
    return nothing
end

"""
    _check_value_entry!(problems::Vector{String}, entry::AbstractDict,
                        label::AbstractString)

Validate one `[values.<name>]` table: its reported number, its kind, its
uncertainty, its optional descriptive fields, and the durability of anything a
case study adds beyond them.
"""
function _check_value_entry!(
    problems::Vector{String},
    entry::AbstractDict,
    label::AbstractString,
)
    value = _field(entry, "value")
    if value === nothing
        push!(problems, "$label.value is required and is absent")
    else
        problem = _real_problem(value)
        problem === nothing || push!(problems, "$label.value $problem")
    end

    kind = _field(entry, "kind")
    if kind === nothing
        push!(problems, "$label.kind is required and is absent")
    elseif !(kind in _VALUE_KINDS)
        push!(
            problems,
            "$label.kind must be \"exact\" or \"estimate\", got $(repr(kind))",
        )
    end

    _check_uncertainty!(problems, entry, label, kind, value)

    for name in ("tolerance_abs", "tolerance_rel")
        tolerance = _field(entry, name)
        tolerance === nothing && continue
        problem = _real_problem(tolerance)
        if problem !== nothing
            push!(problems, "$label.$name $problem")
        elseif tolerance < 0
            push!(problems, "$label.$name must be nonnegative, got $tolerance")
        end
    end

    for name in ("method", "units")
        descriptive = _field(entry, name)
        descriptive === nothing && continue
        descriptive isa AbstractString ||
            push!(problems, "$label.$name must be a string, got $(_describe(descriptive))")
    end

    note = _field(entry, "note")
    if note !== nothing
        problem = _note_problem(note)
        problem === nothing || push!(problems, "$label.note $problem")
    end

    # A case study may record further fields of its own. They carry no reserved
    # meaning, so nothing is asserted about them beyond durability.
    for name in _field_names(entry)
        if isempty(name)
            push!(problems, "$label carries an entry with an empty key")
            continue
        end
        name in _RESERVED_VALUE_KEYS && continue
        child = "$label.$name"
        additional = _field(entry, name)
        _check_local_path!(problems, additional, name, child)
        _check_payload!(problems, additional, child, 3)
    end
    return nothing
end

"""
    _check_uncertainty!(problems::Vector{String}, entry::AbstractDict,
                        label::AbstractString, kind, value)

Enforce the uncertainty contract that `kind` selects.

An exact result carries no uncertainty at all. An estimate carries exactly one
representation of it — a standard error, or a confidence interval — because two
representations of the same uncertainty in one record are two things that can
disagree, and a reader would have no way to tell which was meant.
"""
function _check_uncertainty!(
    problems::Vector{String},
    entry::AbstractDict,
    label::AbstractString,
    kind,
    value,
)
    present = filter(name -> _field(entry, name) !== nothing, collect(_UNCERTAINTY_KEYS))

    if kind == "exact"
        isempty(present) || push!(
            problems,
            "$label is exact and must carry no uncertainty, but carries " *
            join(present, ", "),
        )
    elseif kind == "estimate"
        has_se = "se" in present
        bounds = count(name -> name in present, ("ci_lower", "ci_upper"))
        if has_se && bounds > 0
            push!(
                problems,
                "$label carries both a standard error and a confidence bound; an " *
                "estimate records exactly one representation of its uncertainty",
            )
        elseif !has_se && bounds == 0
            push!(
                problems,
                "$label is an estimate and must carry either se or both ci_lower and " *
                "ci_upper",
            )
        elseif !has_se && bounds == 1
            push!(
                problems,
                "$label carries one confidence bound; a confidence interval records " *
                "both ci_lower and ci_upper",
            )
        end
    end

    standard_error = _field(entry, "se")
    if standard_error !== nothing
        problem = _real_problem(standard_error)
        if problem !== nothing
            push!(problems, "$label.se $problem")
        elseif standard_error < 0
            push!(problems, "$label.se must be nonnegative, got $standard_error")
        end
    end

    lower = _field(entry, "ci_lower")
    upper = _field(entry, "ci_upper")
    lower_ok = lower === nothing || _real_problem(lower) === nothing
    upper_ok = upper === nothing || _real_problem(upper) === nothing
    lower === nothing ||
        lower_ok ||
        push!(problems, "$label.ci_lower $(_real_problem(lower))")
    upper === nothing ||
        upper_ok ||
        push!(problems, "$label.ci_upper $(_real_problem(upper))")

    if lower !== nothing && upper !== nothing && lower_ok && upper_ok
        lower <= upper || push!(
            problems,
            "$label records the reversed interval [$lower, $upper]; ci_lower must not " *
            "exceed ci_upper",
        )
        if value !== nothing && _real_problem(value) === nothing && lower <= upper
            lower <= value <= upper || push!(
                problems,
                "$label.value $value lies outside its recorded interval " *
                "[$lower, $upper]",
            )
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Source-path-aware validation.
# ---------------------------------------------------------------------------

"""
    _check_source_path!(problems::Vector{String}, source_path::AbstractString,
                        provenance)

Validate the committed location of a reference summary against the canonical
layout fixed by G2-D.4, and against the record it holds.

The path is logical: it is repository-relative and uses forward slashes whatever
the filesystem it came from. The file itself need not exist, so that a prospective
record can be validated before it is written.
"""
function _check_source_path!(
    problems::Vector{String},
    source_path::AbstractString,
    provenance,
)
    problem = _relative_path_problem(source_path)
    if problem !== nothing
        push!(problems, "the source path $problem")
        return nothing
    end

    components = split(source_path, '/')
    if length(components) != 4 || components[1] != "case-studies" ||
       components[3] != "reference"
        push!(
            problems,
            "the source path must be case-studies/<case>/reference/<result-name>.toml, " *
            "got \"$source_path\"",
        )
        return nothing
    end

    directory = components[2]
    occursin(_CASE_PATTERN, directory) || push!(
        problems,
        "the source path names the case directory \"$directory\", which is not a slug " *
        "of the form NN-lowercase-hyphenated-name",
    )

    file = components[4]
    if !endswith(file, ".toml")
        push!(problems, "the source path must name a .toml file, got \"$file\"")
    else
        result = chop(file; tail = length(".toml"))
        occursin(_SLUG_PATTERN, result) || push!(
            problems,
            "the source path names the result \"$result\", which is not a nonempty " *
            "lowercase-hyphenated slug",
        )
    end

    if provenance isa AbstractDict
        case = _field(provenance, "case")
        case isa AbstractString && case != directory &&
            push!(
                problems,
                "the source path lies under case-studies/$directory/ but the record " *
                "declares the case \"$case\"",
            )
        _field(provenance, "preset") == "smoke" && push!(
            problems,
            "a committed reference summary must not record the smoke preset; smoke is " *
            "the development preset and its values are not reportable",
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# The shared validator.
# ---------------------------------------------------------------------------

"""
    validate_reference_summary(data::AbstractDict;
                               source_path::Union{Nothing,AbstractString} = nothing)
        -> Vector{String}

Validate a parsed numerical reference summary against schema version 1, and
return the problems found. An empty vector means the record is valid.

`data` is a table as `TOML.parsefile` returns it. A valid summary carries exactly
four top-level entries — `schema_version`, and the tables `provenance`,
`parameters`, and `values` — and every field of each is checked: the case slug,
the RFC 3339 UTC timestamp, the repository-relative driver path, the full Git
commit, the Julia version, the preset, the generator name, and the seed; every
resolved parameter, recursively, for durable representation in TOML; and every
reported result, for a finite value, a declared kind, and exactly the uncertainty
that kind admits.

Pass `source_path` when the record is to live at a committed location. It is a
repository-relative logical path with forward slashes, and it is then required to
be exactly `case-studies/<case>/reference/<result-name>.toml`, to agree with the
case the record declares, and not to carry the `smoke` preset, whose values are a
development convenience rather than a reported result. The file need not exist:
the writer validates a prospective record this way before creating it. Without
`source_path` only the schema and the payload are checked, and `smoke` is
permitted, which is what a driver writing a scratch record under `results/`
needs.

The function is pure. It writes nothing, inspects no repository, reads no
environment variable, and reports malformed input as a problem rather than
raising: a reader must be able to run it on a file somebody else wrote.

# Examples

```julia
problems = validate_reference_summary(TOML.parsefile(path); source_path = logical)
isempty(problems) || foreach(println, problems)
```
"""
function validate_reference_summary(
    data::AbstractDict;
    source_path::Union{Nothing,AbstractString} = nothing,
)
    problems = String[]

    for name in _TOP_LEVEL_KEYS
        _field(data, name) === nothing &&
            push!(problems, "the top-level key $name is required and is absent")
    end
    for name in _field_names(data)
        name in _TOP_LEVEL_KEYS || push!(
            problems,
            "$name is not a top-level key of reference-summary schema version " *
            "$_SCHEMA_VERSION",
        )
    end

    version = _field(data, "schema_version")
    if version !== nothing &&
       !(version isa Integer && !(version isa Bool) && version == _SCHEMA_VERSION)
        push!(
            problems,
            "schema_version must be the integer $_SCHEMA_VERSION, got $(repr(version))",
        )
    end

    provenance = _field(data, "provenance")
    if provenance !== nothing
        if provenance isa AbstractDict
            _check_provenance!(problems, provenance)
        else
            push!(problems, "provenance must be a table, got $(_describe(provenance))")
        end
    end

    parameters = _field(data, "parameters")
    if parameters !== nothing
        if !(parameters isa AbstractDict)
            push!(problems, "parameters must be a table, got $(_describe(parameters))")
        elseif isempty(parameters)
            push!(
                problems,
                "parameters must record every resolved numerical parameter and must not " *
                "be empty",
            )
        else
            _check_table!(problems, parameters, "parameters", 1)
        end
    end

    values = _field(data, "values")
    if values !== nothing
        if !(values isa AbstractDict)
            push!(problems, "values must be a table, got $(_describe(values))")
        elseif isempty(values)
            push!(problems, "values must record at least one result and must not be empty")
        else
            _check_values!(problems, values)
        end
    end

    source_path === nothing || _check_source_path!(problems, source_path, provenance)
    return problems
end

# ---------------------------------------------------------------------------
# Provenance capture.
# ---------------------------------------------------------------------------

"""
    _default_repository_root() -> String

The root of this package's own checkout, resolved at run time so that a relocated
installation is still inspected in the right place.
"""
_default_repository_root() = something(pkgdir(@__MODULE__), dirname(@__DIR__))

"""
    _git(root::AbstractString, arguments::Cmd) -> Union{Nothing,NamedTuple}

Run `git` in `root` and return its exit success and trimmed standard output, or
`nothing` when no `git` executable could be spawned at all.

Standard error is discarded: a failing invocation is reported by the caller in the
vocabulary of this repository rather than in that of Git.
"""
function _git(root::AbstractString, arguments::Cmd)
    output = IOBuffer()
    command =
        pipeline(ignorestatus(`git -C $root $arguments`); stdout = output, stderr = devnull)
    process = try
        run(command)
    catch err
        (err isa Base.IOError || err isa Base.SystemError) || rethrow()
        return nothing
    end
    return (ok = process.exitcode == 0, text = String(strip(String(take!(output)))))
end

"""
    _clean_tree_commit(root::AbstractString) -> String

Return the full commit of `root`, requiring that the repository exist, that HEAD
resolve, and that the working tree be entirely clean.

Cleanliness includes untracked files that are not ignored, because a result
produced with an uncommitted driver is not reproducible from the recorded commit
however tidy the tracked files happen to be. The dirty state is refused rather
than recorded: a flag saying a record cannot be trusted is not a substitute for
not writing it.
"""
function _clean_tree_commit(root::AbstractString)
    isdir(root) ||
        throw(ArgumentError("the repository root `$root` is not an existing directory"))

    inside = _git(root, `rev-parse --is-inside-work-tree`)
    inside === nothing && throw(
        ArgumentError(
            "no `git` executable could be run; capturing provenance requires Git",
        ),
    )
    (inside.ok && inside.text == "true") || throw(
        ArgumentError("`$root` is not inside a Git work tree, so it has no provenance"),
    )

    head = _git(root, `rev-parse HEAD`)
    (head !== nothing && head.ok) || throw(
        ArgumentError(
            "the repository at `$root` has no resolvable HEAD; commit before capturing " *
            "provenance",
        ),
    )
    commit = head.text
    occursin(_COMMIT_PATTERN, commit) || throw(
        ArgumentError(
            "Git reported the unexpected HEAD `$commit`; a full forty-character " *
            "lowercase object identifier was expected",
        ),
    )

    status = _git(root, `status --porcelain --untracked-files=all`)
    (status !== nothing && status.ok) ||
        throw(ArgumentError("the working tree at `$root` could not be inspected"))
    isempty(status.text) || throw(
        ArgumentError(
            "the working tree at `$root` is not clean, so the commit `$commit` does not " *
            "identify what would be run; commit or remove the following before " *
            "capturing provenance:\n" * status.text,
        ),
    )
    return commit
end

"""
    _normalised_relative_path(raw::AbstractString, label::AbstractString) -> String

Return `raw` as a safe repository-relative logical path with forward slashes, or
throw an `ArgumentError` naming `label` and the reason it is not one.

A path already relative and free of traversal is normalised, so that a driver
written on Windows records the same string as one written on Linux. Anything
absolute, drive-qualified, or containing `.` or `..` is refused rather than
repaired: guessing which repository an absolute path was relative to is exactly
the kind of silent reconstruction this schema exists to prevent.
"""
function _normalised_relative_path(raw::AbstractString, label::AbstractString)
    isempty(raw) &&
        throw(ArgumentError("$label must be a nonempty repository-relative path"))
    control = _control_character_problem(raw)
    control === nothing || throw(ArgumentError("$label $control"))
    occursin(r"^[A-Za-z]:", raw) && throw(
        ArgumentError(
            "$label must be repository-relative, but `$raw` carries a drive prefix",
        ),
    )
    (startswith(raw, '/') || startswith(raw, '\\')) &&
        throw(ArgumentError("$label must be repository-relative, but `$raw` is absolute"))
    components = split(replace(raw, '\\' => '/'), '/')
    any(isempty, components) &&
        throw(ArgumentError("$label must not contain an empty component, got `$raw`"))
    any(component -> component in (".", ".."), components) && throw(
        ArgumentError("$label must not contain a `.` or `..` component, got `$raw`"),
    )
    return join(components, "/")
end

"""
    capture_provenance(; case, seed, preset, generated_by, rng = "Xoshiro",
                       generated = nothing, repo_root = <package root>)
        -> NamedTuple

Capture the provenance of a run as the schema version 1 `[provenance]` table,
returned as a `NamedTuple` a driver passes straight to
[`write_reference_summary`](@ref).

`case` is the case slug, `NN-lowercase-hyphenated-name`. `seed` is the single
master seed of the experiment, in `0 ≤ seed ≤ typemax(Int64)`. `preset` is one of
`PRESETS`. `generated_by` is the repository-relative path of the driver, under
`case-studies/<case>/` and ending in `.jl`; a Windows path separator is
normalised, and an absolute path or one containing `.` or `..` is refused. `rng`
names the generator family, `Xoshiro` by default. `generated` is the timestamp,
produced from the clock in canonical RFC 3339 UTC second precision when it is not
supplied, and validated against the same contract when it is — injecting one is
what makes a written record byte-reproducible in a test.

The Git repository at `repo_root` must exist, must have a resolvable HEAD, and
must be **entirely clean, including untracked files that are not ignored**. The
recorded commit then identifies the code and the committed manifest by itself,
which is why no manifest hash, no package path, and no dirty-state flag appears in
the schema. A dirty tree throws rather than being recorded.

The Julia version, the thread count, and the operating system are recorded as
context for a reader. They are not part of the scientific contract: no result of
this repository is claimed to depend on the thread count, and reproduction on a
supported but non-canonical Julia is statistical rather than bitwise, as
docs/methods/reproducibility.md sets out.

Every violated precondition throws an `ArgumentError` naming the offending input.
No network operation is performed and no repository state is modified.

# Examples

The slug `99-example-process` is **fictitious**. It names no case study of this
repository, and it is used throughout this file's examples precisely so that a
reader cannot mistake an illustration of the machinery for a case that exists.

```julia
provenance = capture_provenance(;
    case = "99-example-process",
    seed = 20260803,
    preset = :production,
    generated_by = "case-studies/99-example-process/driver.jl",
)
```
"""
function capture_provenance(;
    case::AbstractString,
    seed::Integer,
    preset::Symbol,
    generated_by::AbstractString,
    rng::AbstractString = "Xoshiro",
    generated::Union{Nothing,AbstractString} = nothing,
    repo_root::AbstractString = _default_repository_root(),
)
    occursin(_CASE_PATTERN, case) || throw(
        ArgumentError(
            "the case slug must have the form NN-lowercase-hyphenated-name, got \"$case\"",
        ),
    )
    preset in PRESETS || throw(
        ArgumentError(
            "`:$preset` is not a valid execution preset; the valid presets are " *
            "$(_preset_list())",
        ),
    )
    0 <= seed <= typemax(Int64) || throw(
        ArgumentError("the seed must satisfy 0 ≤ seed ≤ $(typemax(Int64)), got $seed"),
    )

    driver = _normalised_relative_path(generated_by, "the generating driver path")
    endswith(driver, ".jl") || throw(
        ArgumentError(
            "the generating driver path must name a Julia file ending in .jl, got " *
            "\"$driver\"",
        ),
    )
    startswith(driver, "case-studies/$case/") || throw(
        ArgumentError(
            "the generating driver path must lie under case-studies/$case/, got " *
            "\"$driver\"",
        ),
    )

    isempty(rng) && throw(ArgumentError("the generator name must be nonempty"))

    moment = generated === nothing ? _utc_timestamp() : String(generated)
    problem = _timestamp_problem(moment)
    problem === nothing ||
        throw(ArgumentError("the generation timestamp $problem"))

    commit = _clean_tree_commit(repo_root)

    return (
        case = String(case),
        generated = moment,
        generated_by = driver,
        git_commit = commit,
        julia_version = string(VERSION),
        os = _operating_system(),
        preset = String(preset),
        rng = String(rng),
        seed = Int64(seed),
        threads = Threads.nthreads(),
    )
end

# ---------------------------------------------------------------------------
# The atomic writer.
# ---------------------------------------------------------------------------

"""
    _toml_value(value, label::AbstractString, depth::Int) -> Any

Convert `value` into the TOML data model, or throw an `ArgumentError` naming
`label` and the reason it cannot be represented at all.

This conversion answers only *representability*: whether the object has a TOML
form at all. Whether the resulting record is *admissible* — finite, homogeneous,
free of absolute local paths — is decided afterwards by
[`validate_reference_summary`](@ref) on the assembled record, so that the
contract has one implementation and a file read from disk is judged by exactly
the rules a file about to be written is.

**Conversion is not claimed to be lossless.** Schema version 1 stores scientific
`Real` payload values in the `Float64` numerical domain, and a `Rational`, a
`BigFloat`, or any other `Real` carrying more precision than `Float64` holds is
**rounded** on the way in. That is intentional rather than incidental: one
numerical domain for the recorded payload is what makes two records comparable
and a round trip exact, and admitting arbitrary precision would put a number in
the file that the repository's own comparisons could not reproduce. A caller
needing more precision than `Float64` carries must not treat a schema version 1
record as preserving it; the correct course is to record the exact quantity in a
form of its own — the numerator and denominator as integers, say — and to say so.
A value whose conversion is `NaN` or `Inf` is still refused outright.
"""
function _toml_value(value, label::AbstractString, depth::Int)
    depth <= _MAX_TABLE_DEPTH || throw(
        ArgumentError("$label nests more than $_MAX_TABLE_DEPTH tables deep"),
    )
    value isa AbstractString && return String(value)
    value isa Bool && return value
    if value isa Integer
        _fits_int64(value) || throw(
            ArgumentError(
                "$label is the integer $value, which lies outside the signed 64-bit " *
                "range TOML records",
            ),
        )
        return Int64(value)
    end
    if value isa TimeType
        throw(
            ArgumentError(
                "$label is $(_describe(value)); a reference summary records a date only " *
                "as the RFC 3339 provenance timestamp, never as scientific payload",
            ),
        )
    end
    if value isa Real
        converted = try
            Float64(value)
        catch
            throw(
                ArgumentError(
                    "$label is $(_describe(value)) and cannot be converted to `Float64`",
                ),
            )
        end
        return converted
    end
    value isa AbstractArray && return Any[
        _toml_value(element, "$label[$position]", depth) for
        (position, element) in enumerate(value)
    ]
    (value isa NamedTuple || value isa AbstractDict) &&
        return _toml_table(value, label, depth)
    throw(ArgumentError("$label cannot be recorded in TOML, got $(_describe(value))"))
end

"""
    _toml_table(source, label::AbstractString, depth::Int) -> Dict{String,Any}

Convert a `NamedTuple` or dictionary into a TOML table with string keys.

A key that is neither a string nor a symbol, and two keys that would collapse onto
one name, are refused: silently dropping an entry would lose part of the record
the caller asked to commit.
"""
function _toml_table(source, label::AbstractString, depth::Int)
    table = Dict{String,Any}()
    for (key, value) in pairs(source)
        name = if key isa AbstractString
            String(key)
        elseif key isa Symbol
            String(key)
        else
            throw(
                ArgumentError(
                    "$label carries a key of type $(typeof(key)); a TOML table is keyed " *
                    "by strings",
                ),
            )
        end
        haskey(table, name) && throw(
            ArgumentError("$label carries the key `$name` twice under different key types"),
        )
        child = isempty(label) ? name : "$label.$name"
        table[name] = _toml_value(value, child, depth + 1)
    end
    return table
end

"""
    _reference_context_alias_key(component::AbstractString) -> String

Return `component` with every trailing ASCII full stop `U+002E` and ASCII space
`U+0020` removed, as the auxiliary form against which
[`_logical_reference_path`](@ref) compares. The result is used **only** to decide
whether a component denotes the reference tree; the component itself is never
rewritten.

Windows resolves a path component with trailing dots or trailing spaces to the
component without them, so `case-studies.`, `case-studies   `, and
`case-studies. .` all open the canonical `case-studies` directory. A detector
that compared the spelling as written would therefore miss a destination that the
filesystem places inside the committed tree.

The removal is deliberately narrow. Only those two ASCII characters are removed,
only from the end, and repeatedly: a leading dot, an internal dot or space, and
every other character survive untouched. A tab, a newline, a non-breaking space
`U+00A0`, and the Unicode full stops `U+3002`, `U+FF0E`, and `U+2024` are
ordinary characters here and are **not** removed — they are not Windows aliases,
and a detector that folded them would be inventing a filesystem rule rather than
following one. Percent-encoded text is read literally: `%2E` is three ordinary
characters. No filesystem is consulted, no URL is decoded, and no Unicode
normalisation is applied.

This helper is internal and unexported. It holds no state.
"""
function _reference_context_alias_key(component::AbstractString)
    start = firstindex(component)
    stop = lastindex(component)
    while stop >= start
        character = component[stop]
        (character == '.' || character == ' ') || break
        stop = prevind(component, stop)
    end
    return String(SubString(component, start, stop))
end

"""
    _logical_reference_path(path::AbstractString) -> Union{Nothing,String}

Derive the repository-relative logical path of `path` when it lies under a
directory a caller was evidently aiming at the committed reference tree, and
`nothing` otherwise.

A path under `case-studies/` is on its way to being committed, so it is held to
the canonical layout by [`validate_reference_summary`](@ref) — including the
prohibition on committing a `smoke` record. A path anywhere else is a development
record, and only the schema applies to it.

**Detection is deliberately broader than acceptance.** A component is recognised
as the reference root when its [`_reference_context_alias_key`](@ref) — the
component with trailing ASCII dots and spaces removed — equals `case-studies`
under case folding. `CASE-STUDIES`, `Case-Studies`, `case-Studies`,
`case-studies.`, `CASE-STUDIES...`, `case-studies   `, and `Case-Studies. .` are
therefore all recognised as attempts to write into the committed tree. The
component's *original* spelling is then carried into the logical path, and the
strict validator, which compares against `case-studies` exactly, rejects every
spelling but the canonical one.

Detecting narrowly would be the dangerous choice, because two distinct filesystem
behaviours each make a noncanonical spelling name the canonical directory.

- **Case folding.** On a case-insensitive filesystem — the default on both
  Windows and macOS — `CASE-STUDIES/99-x/reference/v.toml` and
  `case-studies/99-x/reference/v.toml` name the same file.
- **Trailing dots and spaces.** Windows strips them from a path component, so
  `case-studies./99-x/reference/v.toml` opens the canonical directory as well.
  This was demonstrated on a Windows host by the Gate 3C-A.1 audit, which wrote a
  smoke record through a trailing-dot alias and landed it inside the committed
  reference tree.

A spelling that escaped detection either way would be treated as an unrestricted
development record, and a `smoke` summary would be written straight into the
committed tree.

Separator normalisation covers `/` and `\\` only. Percent-encoded text is read
literally, and Unicode characters that resemble a solidus are ordinary characters
within a component; neither is decoded or split on. **No general Windows path
canonicalisation is performed**: no filesystem is consulted, and the correction is
lexical throughout. Windows 8.3 short-name aliases are **not** covered, and are
recorded as deferred platform-specific alias work rather than claimed.
"""
function _logical_reference_path(path::AbstractString)
    components = split(replace(path, '\\' => '/'), '/'; keepempty = false)
    index = findlast(
        component ->
            lowercase(_reference_context_alias_key(component)) == "case-studies",
        components,
    )
    index === nothing && return nothing
    return join(components[index:end], "/")
end

"""
    _replace_atomically(source::AbstractString, target::AbstractString) -> Nothing

Move `source` onto `target` in one filesystem operation, replacing any existing
target, and return `nothing`. Fail closed: if the operation cannot be performed
atomically it throws, and nothing else is attempted.

Both supported branches reduce to the platform primitive that replaces
atomically — `rename(2)` on POSIX, `MoveFileEx` with replacement on Windows — so
a reader never observes a missing or partial target.

- **Julia ≥ 1.12** calls `Base.rename`, which is the public entry point to that
  primitive.
- **Julia 1.10 and 1.11** call `jl_fs_rename` directly and raise the libuv error
  themselves. The direct call is deliberate: on those releases
  `Base.Filesystem.rename` falls back to copying the source and removing it when
  the primitive fails, and a copy followed by a remove is exactly the
  non-atomic sequence this function exists to exclude. Reaching the primitive
  without that wrapper is the only way to guarantee on the LTS release what the
  contract states on the canonical one.

**There is no fallback of any kind.** No `mv`, no `cp`, no removal of the
existing target before replacement, and no degradation to a non-atomic path when
the primitive is unavailable: the operation either replaces atomically or throws
the original I/O error. A failed replacement therefore leaves an existing target
exactly as it was, and the caller — which has already closed and flushed the
temporary stream — removes the temporary residue and rethrows.

This contract is established by construction and by the tests of the failure
path, which check that a refused replacement preserves the target and leaves no
temporary sibling. **No power-loss scenario has been experimentally tested**, and
none is claimed: the guarantee rests on the atomicity of the platform call, not
on an experiment this repository has run.
"""
function _replace_atomically(source::AbstractString, target::AbstractString)
    from = String(source)
    onto = String(target)
    @static if VERSION >= v"1.12"
        Base.rename(from, onto)
    else
        err = ccall(:jl_fs_rename, Int32, (Cstring, Cstring), from, onto)
        err < 0 && Base.uv_error("rename($(repr(from)), $(repr(onto)))", err)
    end
    return nothing
end

"""
    _check_destination_problem(path::AbstractString) -> Union{Nothing,String}

Describe why `path` is not an acceptable destination for a reference summary, or
return `nothing` if it is one.

Two rules bind every destination, inside the committed reference tree and outside
it alike.

A **control character** is refused, and refused first, because the destination is
a string that reaches the filesystem before any record has been validated: a path
whose rendered form disagrees with the bytes that open it must not get that far.

The **extension is exactly `.toml`**, in lower case. The file is TOML; the
verification script discovers `case-studies/*/reference/*.toml` and nothing else;
and a development record written as `draft.json`, `draft.txt`, `draft.TOML`, or
`draft` is a file that no tool in this repository will look at again. The
lowercase spelling is part of the durable contract rather than a convention,
because a case-insensitive filesystem would accept `.TOML` locally and a
case-sensitive one would then not find it.
"""
function _check_destination_problem(path::AbstractString)
    isempty(path) && return "must be nonempty"
    control = _control_character_problem(path)
    control === nothing || return control
    endswith(path, ".toml") || return string(
        "must name a file whose extension is exactly `.toml`, got \"",
        path,
        "\"",
    )
    return nothing
end

"""
    write_reference_summary(path::AbstractString; provenance::NamedTuple,
                            parameters::NamedTuple, values::NamedTuple) -> Nothing

Write a schema version 1 numerical reference summary to `path`, atomically.

`provenance` is the table [`capture_provenance`](@ref) returns. `parameters`
records every resolved numerical parameter needed to reproduce the results — the
values actually used, after a preset has been applied, not the preset name.
`values` maps each result name to its own table, carrying at least a finite
`value` and a `kind` of `"exact"` or `"estimate"`, with an estimate carrying
either `se` or both `ci_lower` and `ci_upper`. The optional `tolerance_abs`,
`tolerance_rel`, `units`, `method`, and `note` are permitted throughout, and a
case study may add fields of its own provided they survive a round trip through
TOML.

`path` must end in `.toml`, in lower case, and must carry no control character.
Both rules bind every destination, committed or not, and both are checked before
the filesystem is touched at all.

The complete prospective record is validated before anything is written, and a
violation throws an `ArgumentError` listing every problem found rather than the
first. When `path` lies under a directory that names the reference tree — after
trailing ASCII dots and spaces are removed for comparison, and under case
folding — the committed-location rules apply as well, so a summary in the wrong
place, or one carrying the `smoke` preset, is refused. Detection is broader than
acceptance: `CASE-STUDIES/...` and `case-studies./...` are each recognised as an
attempt to write into the committed tree and then rejected for not being spelt
canonically, rather than being mistaken for an unrestricted development path on a
filesystem that does not distinguish the two. A path genuinely elsewhere is a
development record and is held only to the schema, so `smoke` is permitted there.

The parent directory must already exist: creating one implicitly is how a
misspelt case slug becomes a second, silently empty case directory. The file is
written to a temporary sibling in that same directory, flushed, closed, and then
moved onto the target by [`_replace_atomically`](@ref), so that an interrupted
run leaves either the previous summary or the new one and never a truncated file,
and no temporary residue survives either outcome. The replacement is
atomic-or-error: there is no copy, no `mv`, and no removal of the target
beforehand, so a refused replacement leaves an existing summary untouched.

Output is UTF-8 with LF endings, no byte-order mark, and exactly one terminal
newline, with tables and keys sorted. Identical input, including an identical
injected timestamp, therefore produces byte-identical output.

# Examples

The slug `99-example-process` is **fictitious** and names no case study of this
repository.

```julia
write_reference_summary(
    joinpath(root, "case-studies", "99-example-process", "reference", "variance.toml");
    provenance = provenance,
    parameters = (steps = 10_000, replicates = 256, dt = 1.0e-3),
    values = (variance = (value = 0.998, kind = "estimate", se = 0.004),),
)
```
"""
function write_reference_summary(
    path::AbstractString;
    provenance::NamedTuple,
    parameters::NamedTuple,
    values::NamedTuple,
)
    problem = _check_destination_problem(path)
    problem === nothing ||
        throw(ArgumentError("the destination path for a reference summary $problem"))

    record = Dict{String,Any}(
        "schema_version" => _SCHEMA_VERSION,
        "provenance" => _toml_table(provenance, "provenance", 1),
        "parameters" => _toml_table(parameters, "parameters", 1),
        "values" => _toml_table(values, "values", 1),
    )

    target = abspath(path)
    problems = validate_reference_summary(
        record;
        source_path = _logical_reference_path(target),
    )
    isempty(problems) || throw(
        ArgumentError(
            "the reference summary for `$path` is invalid and was not written:\n" *
            join(("  - " * problem for problem in problems), "\n"),
        ),
    )

    parent = dirname(target)
    isdir(parent) || throw(
        ArgumentError(
            "the directory `$parent` does not exist; create the case directory " *
            "deliberately before writing a reference summary into it",
        ),
    )

    buffer = IOBuffer()
    TOML.print(buffer, record; sorted = true)
    content = rstrip(String(take!(buffer)), '\n') * "\n"

    temporary, stream = mktemp(parent)
    try
        write(stream, content)
        flush(stream)
        close(stream)
        _replace_atomically(temporary, target)
    catch
        close(stream)
        rm(temporary; force = true)
        rethrow()
    end
    return nothing
end
