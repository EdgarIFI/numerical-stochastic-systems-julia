# Reproducibility

What this repository promises about reproducing its results, and what it
deliberately does not.

## Two kinds of reproduction

**Exact reproduction** uses Julia 1.12.x together with the committed
`Manifest.toml`, which pins every direct and transitive package version. This is
the canonical environment, and the one in which published results are produced.

**Supported-version reproduction** covers every Julia release from 1.10 onwards.
It is **statistical rather than bitwise**. Julia does not guarantee that its
default random number generator produces identical streams across minor releases,
and the algorithms behind `rand` and its relatives may change. Two runs on
different Julia minor versions will therefore generally produce different
sequences of random numbers, and so different values.

The correct expectation on a non-canonical version is that a result agrees with
the reported value **within its stated statistical uncertainty**, not that it
matches digit for digit. A study whose conclusion depended on the exact bits of a
random stream would not be a sound study.

The distinction is not a limitation to be apologised for; it is the honest
description of what a stochastic computation can promise.

## The canonical manifest and the LTS release

`Manifest.toml` is committed because this repository is an application rather
than a library. It records the exact package versions used, and instantiating it
reconstructs that environment.

Continuous integration deliberately serves two different purposes:

- The **canonical job** instantiates the committed manifest and runs the tests in
  the pinned environment.
- The **LTS job** removes the manifest inside its own ephemeral checkout and
  resolves afresh from `Project.toml`. This tests that the declared compatibility
  bounds are honest and that the package works on the supported floor. It makes
  no claim about bitwise reproduction, and it never modifies the committed
  manifest.

The two jobs answer different questions, and neither substitutes for the other.

## What every public result must record

A result is not publishable in this repository unless it is accompanied by:

- every **parameter** value, with units or scaling;
- the **seed** or seeds used;
- the **Julia version**;
- the **package state** — that is, the manifest against which it was produced;
- the **Git commit** of the repository.

The script [../../scripts/env_report.jl](../../scripts/env_report.jl) prints all
of this for the active environment, including whether the working tree was clean
at the time.

## Figures

Figures are committed as PNG. They are **verified through the numerical series
behind them, never by comparing pixels**. Rendered output depends on the plotting
backend, on font availability, and on rasterisation details, none of which bear
on whether a scientific result is correct. A figure is therefore accompanied by
the numerical data it draws, and it is that data which is checked.

## Heavy output is not tracked

Long production runs write to `results/`, which is ignored by Git. Such output is
regenerated from the committed drivers rather than stored. What is committed
instead is a small **reference summary** per case: the handful of numbers a
reader would need in order to confirm that a rerun agrees.

## Numerical reference summaries

The canonical location for a reference summary is:

```text
case-studies/<slug>/reference/<name>.toml
```

The **result identifier is the filename without its extension**, and it is not
repeated inside the file: one name in one place cannot drift out of agreement
with itself.

The schema, the writer, and the validator live in the shared package, in
[../../src/reproducibility.jl](../../src/reproducibility.jl). Three functions
make up the whole interface, and like everything else in the package they are
unexported and reached by explicit import:

```julia
using StochasticCaseStudies:
    capture_provenance, write_reference_summary, validate_reference_summary
```

### Schema version 1

A reference summary is a TOML file with exactly four top-level entries. An
unknown top-level key is an error, not an extension: a field nobody validates is
a field nobody can trust.

**The slug `99-example-process` used below is fictitious.** It names no case
study of this repository, and it appears in the examples here, in the package
docstrings, and in the test fixtures precisely so that an illustration of the
machinery cannot be mistaken for a case that exists. The slug
`06-ornstein-uhlenbeck` is deliberately *not* used for this purpose: it is
reserved for the scientific case gate that will define it.

```toml
schema_version = 1

[provenance]
case          = "99-example-process"
generated     = "2026-08-03T09:15:00Z"
generated_by  = "case-studies/99-example-process/driver.jl"
git_commit    = "0123456789abcdef0123456789abcdef01234567"
julia_version = "1.12.6"
preset        = "production"
rng           = "Xoshiro"
seed          = 20260803

[parameters]
steps = 10000
dt    = 0.001

[values.variance]
value = 1.0
kind  = "estimate"
se    = 0.01
```

`schema_version` must be exactly the integer `1`. Versioning the schema means
that a later change to the required fields is a **visible migration** rather than
a silent divergence between old files and new ones.

### The provenance table

Eight fields are required.

| Field | Contract |
| --- | --- |
| `case` | The case slug, `NN-lowercase-hyphenated-name`. |
| `generated` | An RFC 3339 UTC timestamp, `YYYY-MM-DDTHH:MM:SSZ`. |
| `generated_by` | The repository-relative path of the driver, under `case-studies/<case>/` and ending in `.jl`. |
| `git_commit` | The full forty-character lowercase hexadecimal Git object identifier. |
| `julia_version` | A version number, as a string. |
| `preset` | `"smoke"`, `"figure"`, or `"production"`. |
| `rng` | The generator family, normally `"Xoshiro"`. |
| `seed` | The master seed, an integer in `0 ≤ seed ≤ typemax(Int64)`. |

Three further fields are permitted and nothing else: `threads`, a positive
integer; `os`, a nonempty string; and `note`, a string that may be empty.

**`threads` is bounded by the signed 64-bit integer domain**, `1 ≤ threads ≤
typemax(Int64)`, and `Bool` is excluded although it subtypes `Integer`. The upper
bound is the range TOML records as an integer, so an oversized `BigInt` or an
unsigned value above `typemax(Int64)` is reported as a validation problem rather
than raising, and the writer refuses it before it reaches TOML output. What
`capture_provenance` itself records — `Threads.nthreads()` — is inside the bound
by construction.

**A `note` admits prose but not `NUL`.** Multiline text is permitted, and so are
tabs, newlines, punctuation, and non-ASCII letters: a note is written for a
reader. The single character `U+0000` is refused, in `provenance.note` and in
`values.<name>.note` alike, because it terminates a string in every filesystem
and process interface the record will pass through, so a note carrying one has a
committed form and a rendered form that need not agree.

**The timestamp is canonical.** The `Z` suffix is mandatory; a local offset, a
sub-second component, and a bare date-time with no zone at all are all refused.
So is hour `24`: Julia admits it as ISO 8601's end-of-day and rolls it into the
following midnight, but RFC 3339 does not, and two spellings of one instant are
two records that will not compare equal. Two consequences of the current policy
are recorded plainly rather than left to be discovered:

- **A leap second is rejected.** `2026-06-30T23:59:60Z` is a real RFC 3339
  instant, but second `60` is outside the calendar Julia's `DateTime` admits, so
  the record is refused as naming an impossible time. No result of this
  repository is timed to the second, so the restriction costs nothing; it is
  stated because a reader should not have to find it out from a failure.
- **Year `0000` is accepted.** The canonical form is four digits and the
  round-trip check passes, so `0000-01-01T00:00:00Z` is a valid timestamp under
  the current policy. It is not a plausible generation instant, and nothing in
  the schema pretends otherwise; no lower bound on the year is imposed, because
  an arbitrary one would be a rule invented to forbid a case nobody will write.

**Paths in the record are repository-relative and use forward slashes.** No
absolute local path is recorded anywhere in a summary — not in the provenance,
and not in a parameter whose name denotes a path. An absolute path is meaningless
to every reader but its author, and frequently discloses a home directory as
well. A driver path written with Windows separators is normalised when it is
captured; one that is absolute, drive-qualified, or contains `.` or `..` is
refused rather than repaired, because guessing which repository an absolute path
was relative to is exactly the silent reconstruction this schema exists to
prevent.

**A path-like field carries no control character.** The Unicode control ranges
`U+0000`–`U+001F` and `U+007F`–`U+009F` are refused in `generated_by`, in a
`source_path` supplied to the validator, in the destination handed to the writer,
and in any recursively validated payload field whose name denotes a path under
the existing path-key policy. A control character makes the rendered form of a
path disagree with the bytes that open it. In the destination the check runs
**before the filesystem is touched at all**; in the pure validator it is reported
as a problem and never raised, so a file somebody else wrote can still be
checked. Ordinary Unicode is not restricted: spaces, punctuation, percent signs,
and non-ASCII letters are all ordinary text in a path.

Two further conventions follow from reading paths literally:

- **Percent-encoded text is not decoded.** `%2F` is three ordinary characters and
  never a separator, and `%00` is not `NUL`. A record that had to be URL decoded
  before it could be checked would be checked in a form nobody committed.
- **Unicode characters that resemble a solidus are ordinary characters.**
  `U+2044`, `U+2215`, and `U+FF0F` do not separate components. Only `/` and `\`
  are separators.

**The machine-context fields are context, not contract.** `julia_version`,
`threads`, and `os` tell a reader what produced the numbers. No result of this
repository is claimed to depend on the thread count or the operating system, and
reproduction on a supported but non-canonical Julia is statistical rather than
bitwise, as set out above. Structural validation therefore accepts any well
formed version string and does not require it to equal the running one: a
committed record outlives the machine that verifies it.

**The schema records no manifest hash and no project hash.** It does not need
one. Provenance is captured only from a completely clean working tree, so the
recorded commit already pins the committed `Manifest.toml` along with everything
else. A second, redundant identity would be one more thing that could disagree
with the first. For the same reason the schema records no package path, no shell
command, and no dirty-state flag.

### The parameters table

`[parameters]` is required, must not be empty, and records **every resolved
numerical parameter** needed to reproduce the results — the values actually used
after a preset has been applied, not the name of the preset. A reader
reconstructs the run from this table alone.

Permitted, recursively: strings; booleans; integers inside the signed 64-bit
range TOML records; finite real numbers; homogeneous arrays of those scalars; and
nested tables with nonempty string keys. Refused: `NaN` and `Inf`; integers
outside the TOML integer domain; dates as scientific payload; absolute local
paths, and control characters, under a field name that denotes a path;
heterogeneous arrays; and anything that has no durable TOML form. A heterogeneous
array is refused rather than promoted, because promoting one would silently
change the type a reader later parses; a caller that wants a float array converts
it and says so.

**An empty array is permitted** and round-trips unchanged. A parameter that is
legitimately an empty collection — no coarsening windows, no excluded replicates
— is a fact about the run, and refusing to record it would force a driver either
to omit the parameter or to invent a placeholder.

### Precision: the payload lives in the Float64 domain

**Schema version 1 stores scientific `Real` payload values in the `Float64`
numerical domain, and conversion into it may round.** A `Rational`, a `BigFloat`,
or any other `Real` carrying more precision than `Float64` holds is accepted, and
is **rounded** on the way in. Nothing here is claimed to be lossless.

The rounding is intentional. One numerical domain for the recorded payload is
what makes two records comparable and a round trip exact; admitting arbitrary
precision would put a number in a committed file that this repository's own
comparisons could not reproduce.

The obligation this places on a caller is stated rather than hidden: **a caller
that needs more precision than `Float64` carries must not treat a schema version
1 record as preserving it.** The correct course is to record the exact quantity in
a form of its own — a numerator and a denominator as integers, say — and to say
what has been done. A value whose conversion is `NaN` or `Inf`, including a
finite `BigFloat` too large for `Float64`, remains refused outright.

### The values table

`[values]` is required and must not be empty. Each entry names one result and
carries at least a finite `value` and a `kind`:

- `kind = "exact"` — the value is exact, and the table carries **no** `se`,
  `ci_lower`, or `ci_upper`.
- `kind = "estimate"` — the table carries **exactly one** representation of the
  uncertainty: either `se` alone, or `ci_lower` and `ci_upper` together. A
  standard error alongside a confidence bound is refused, and so is a single
  bound, and so is an estimate with no uncertainty at all. Two representations of
  one uncertainty in one record are two things that can disagree, and a reader
  would have no way to tell which was meant.

A standard error is finite and nonnegative. A confidence interval satisfies
`ci_lower ≤ ci_upper`, and the reported `value` must lie inside it.

`tolerance_abs`, `tolerance_rel` — finite and nonnegative — and the descriptive
`units`, `method`, and `note` are permitted throughout. A case study may add
further fields of its own; they carry no reserved meaning, and nothing is
asserted about them beyond durable representation in TOML. The reserved fields
above are always enforced.

The uncertainty a summary reports is the one computed under
[error-analysis.md](error-analysis.md): correlated samples require blocking or an
integrated autocorrelation-time correction before a standard error means
anything, and the schema records the result of that analysis rather than
performing it.

### Capturing provenance requires a clean tree

`capture_provenance` reads the repository and refuses to describe a run it cannot
identify. The repository must exist, HEAD must resolve, and the working tree must
be **entirely clean, including untracked files that are not ignored**. Ignored
files do not count: they are not part of what would be run.

A dirty tree is **refused rather than recorded**. A flag saying that a record
cannot be trusted is not a substitute for not writing it, and a result produced
from an uncommitted driver is not reproducible from the recorded commit however
tidy the tracked files happen to be. The full Git commit of a clean tree is
therefore the entire environment identity.

No network operation is performed, and no repository state is modified.

**A `git` executable is required to test provenance capture, and the test suite
fails explicitly without one.** There is no skip path and no warning-only branch.
Git is required by `capture_provenance`, by this repository, by the continuous
integration environment, and by the Gate 3 reproducibility contract, which is
stated in terms of a commit; a suite that quietly passed over these checks on a
machine without Git would report a pass for a contract it never examined. The
provenance tests build temporary repositories, configure identity with `git
config --local` inside them alone, never touch global or system configuration,
and perform no network operation.

### Writing is atomic or it fails

`write_reference_summary` validates the complete prospective record **before it
writes anything**, and reports every problem it found rather than the first. It
then writes to a temporary file in the destination directory, flushes it, closes
it, and moves it onto the target in one filesystem operation. An interrupted run
therefore leaves either the previous summary or the new one and never a truncated
file, and no temporary residue survives either outcome.

**The replacement is atomic or it is an error.** Both supported branches reduce
to the platform primitive that replaces atomically — `rename(2)` on POSIX,
`MoveFileEx` with replacement on Windows:

| Julia | Mechanism |
| --- | --- |
| ≥ 1.12 | `Base.rename`, the public entry point to the primitive. |
| 1.10–1.11 | `jl_fs_rename` called directly, raising the libuv error itself. |

The direct call on the supported floor is deliberate. On those releases
`Base.Filesystem.rename` falls back to copying the source and removing it when
the primitive fails, and a copy followed by a remove is exactly the non-atomic
sequence this contract exists to exclude. Reaching the primitive without that
wrapper is the only way to guarantee on the LTS release what is promised on the
canonical one.

**There is no fallback of any kind**: no `cp` and `rm`, no `mv`, and no removal
of an existing target before the replacement. A refused replacement therefore
leaves an existing summary exactly as it was, removes only the temporary residue,
and propagates the original I/O error unchanged.

The guarantee rests on the atomicity of the platform call. **No power-loss
scenario has been experimentally tested**, and none is claimed; what the test
suite establishes is that a first write, a replacement, and a refused replacement
each behave as described, and that no temporary sibling survives any of them.

**Every destination ends in a lowercase `.toml`.** The rule binds inside the
committed reference tree and outside it alike, and it is checked before the
filesystem is touched. `draft.json`, `draft.txt`, `draft.TOML`, and an
extensionless `draft` are all refused. The file is TOML; the verification script
discovers `case-studies/*/reference/*.toml` and nothing else; and the lowercase
spelling is part of the durable contract rather than a convention, because a
case-insensitive filesystem would accept `.TOML` locally and a case-sensitive one
would then not find it. A development record outside `case-studies/` may still
carry `preset = "smoke"`, but its destination must still end in `.toml`.

The parent directory must already exist. Creating one implicitly is how a
misspelt case slug becomes a second, silently empty case directory.

Output is UTF-8 with LF line endings, no byte-order mark, and exactly one
terminal newline, with tables and keys sorted. Identical input — including an
identical injected timestamp — therefore produces byte-identical output.

### Validation follows the path

`validate_reference_summary` is a **pure** function: it returns the list of
problems it found, writes nothing, inspects no repository, reads no environment
variable, and reports malformed input as a problem rather than raising. That is
what lets one implementation serve both the writer, before any file exists, and
the verification script, on a file somebody else wrote. It does not require the
file to exist.

Given a `source_path`, it additionally holds the record to its **committed
location**: exactly `case-studies/<case>/reference/<result-name>.toml`, with a
repository-relative forward-slash path, a case directory equal to the `case` the
record declares, and a result name that is a lowercase-hyphenated slug.

**A committed reference summary may not record the `smoke` preset.** Smoke is the
development preset; its values exist to show that a driver runs, not to be
reported. Without a `source_path` the schema alone applies and `smoke` is
permitted, which is what a scratch record written outside the committed tree
needs.

### Detection is broader than acceptance

When the writer decides whether a destination is on its way into the committed
tree, it does **not** compare the path component as written. It first derives an
auxiliary comparison form — repeatedly removing trailing ASCII full stops
`U+002E` and ASCII spaces `U+0020` from the end of the component — and then
compares that form with `case-studies` **case-insensitively**. So `CASE-STUDIES`,
`Case-Studies`, `case-Studies`, `case-studies.`, `CASE-STUDIES...`,
`case-studies   `, and `Case-Studies. .` are all recognised as attempts to write
into the reference tree.

**The auxiliary form is used for comparison only.** The component's original
spelling is carried unchanged into the logical path, and the strict validator —
which requires exactly `case-studies/<case>/reference/<result-name>.toml`, in
lower case and with no trailing alias characters — then rejects every spelling
but the canonical one. Nothing is rewritten, repaired, or canonicalised on the
way through.

The asymmetry is the point, and detecting narrowly would be the dangerous choice,
because two distinct filesystem behaviours each make a noncanonical spelling name
the canonical directory.

- **Case folding.** On a case-insensitive filesystem, the default on both Windows
  and macOS, `CASE-STUDIES/99-x/reference/v.toml` and
  `case-studies/99-x/reference/v.toml` name the same file.
- **Trailing dots and spaces.** Windows strips them from a path component, so
  `case-studies./99-x/reference/v.toml` opens the canonical directory as well.
  The Gate 3C-A.1 audit demonstrated the consequence on a Windows host: a smoke
  reference record written through a trailing-dot alias escaped detection and
  landed inside the committed reference tree.

A spelling that escaped detection either way would be treated as an unrestricted
development record, and a `smoke` summary would be written straight into the
committed tree. Under the present rule such a path fails before anything is
written, whether the record carries `production` or `smoke`; no destination is
created, no existing canonical summary is altered, and no temporary residue
remains.

The rule applies to repository-relative paths, absolute paths, Windows paths, and
mixed-separator paths alike; `/` and `\` are both normalised.

**The removal is narrow, and deliberately so.** Only the two ASCII characters are
removed, only from the end of a component, and only for comparison. A leading
dot, an internal dot or space, and every other character survive: `.case-studies`
and `case-studiesx.` are not the reference tree. A tab, a newline, a non-breaking
space `U+00A0`, and the Unicode full stops `U+3002`, `U+FF0E`, and `U+2024` are
ordinary characters and are **not** removed — they are not Windows aliases, and
folding them would invent a filesystem rule rather than follow one.
Percent-encoded text stays literal: `%2E` is three ordinary characters and is
never decoded.

**No general Windows path canonicalisation is performed.** The rule is lexical
throughout: no filesystem is consulted, no short name is expanded, no symbolic
link or junction is resolved, and no Unicode normalisation is applied.

**Windows 8.3 short-name aliases are not covered, and no claim is made that they
are.** A path reaching the writer through a short-name alias such as `CASE-S~1`
would not be recognised as the reference tree. This is recorded as a deferred
platform-specific alias concern rather than repaired speculatively: the fix
belongs with a case study that actually exercises such a path.

More generally, **no claim is made that every possible Windows filesystem alias
is eliminated.** What is established is that the case-folded, trailing-dot, and
trailing-space forms are detected and refused, on the evidence of the regression
tests and of a live probe that runs on Windows hosts where the alias physically
resolves.

## The verification script

[../../scripts/verify_reproducibility.jl](../../scripts/verify_reproducibility.jl)
is a thin repository-level caller of the package validator. It checks the
environment files, discovers exactly `case-studies/*/reference/*.toml` in
deterministic lexical order, parses each one, and validates it against the schema
and its committed location. Every file is processed and every problem of every
file is reported: a run that stopped at the first invalid summary would hide the
rest behind it. It exits 0 when everything passes and 1 otherwise, reads only,
and never invokes Git.

**The script makes no numerical comparison.** Validating a reference summary
establishes that the record is well formed, complete, and in the right place. It
does **not** establish that the numbers in it are correct, that they were ever
reproduced, or that the case study behind them is finished. Tolerance-based
comparison of committed reference values against freshly computed results is not
implemented here, and `tolerance_abs` and `tolerance_rel` are recorded by the
schema so that it has something to compare against when it is.

**One reference summary is registered**, that of the CS-06 pilot, at
`case-studies/06-ornstein-uhlenbeck/reference/ornstein-uhlenbeck.toml`. The
script discovers it, parses it, and validates it against the schema and its
committed location, and reports a pass on that basis alone.

**Semantic regression checking of that record belongs to the case study, not to
this script.** `test/test_ornstein_uhlenbeck_reference.jl` reads the persisted
summary, recomputes every analytical reference in it from the case's own model
functions, recomputes every recorded discrepancy from the record's own value,
reference, and standard error, and applies the case's ratified acceptance
criteria. It runs no simulation and pins no artefact digest. The division of
labour is deliberate and neither half should be overstated: the script checks
schema, discovery, and reproducibility structure for every case; the reference
test checks that one case's persisted numbers still say what the case claims they
say. Neither reruns the production experiment, and neither is a fresh numerical
reproduction of it.

## What implementation does and does not establish

Everything this document describes is **implemented** — the schema, the
provenance capture, the atomic writer, the path-aware validator, the bounded
corrections of Gate 3C-C.1, and the Windows reference-alias correction G3-CORR.7
applied under Gate 3C-C.2. That is a statement about machinery, and it must not
be read as a statement about science.

**Implementation does not mean every scientific case is complete.** One case
directory exists, with its driver, its figure, and its reference summary: the
CS-06 pilot. The other nine cases have produced nothing, and for them no number
has been recorded, compared, or reproduced. Having a correct instrument is not
the same as having taken a measurement with it, and having taken one measurement
is not the same as having taken ten.

The tolerance comparison described above remains unimplemented for every case,
CS-06 included: its record is validated for structure by this script and for
scientific content by the case's own reference test, and neither of those is the
generic tolerance-based comparison this document reserves the schema fields for.

## Related documents

- [rng-and-seeding.md](rng-and-seeding.md) — how randomness is controlled.
- [error-analysis.md](error-analysis.md) — how uncertainty is quantified.
- [../decisions.md](../decisions.md) — the decisions behind these policies.
