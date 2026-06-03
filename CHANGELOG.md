# Changelog

All notable changes to FieldStruct are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.8.0] - 2026-06-03

Legibility for humans and agents, made a first-class design invariant and
delivered across the error, inspection, and option surfaces.

### Added

- **`FieldStruct::Errors#full_messages`** — renders each validation message as a complete sentence by prepending the humanized field name (`first_name` + `is required` → `"First name is required"`). Humanization is deliberately minimal (underscores to spaces, first character upcased — no inflector, no `_id` stripping, no i18n), so the transform stays predictable. Messages on `:base` (the cross-field convention) pass through unprefixed.
- **`Types::Base.option_schema`** — every type now declares its native field options in one place, as a frozen `{name => {type:, required:, presets:}}` hash, inherited via `super.merge` so subtypes pick up their parent's options (`:uuid` inherits `:string`'s `format:` / `enum:`). The type system can now answer "what options do I accept, of what shape, with what presets" at runtime, for both humans and agents, without reading source.
- **`Registry#type_classes`** — enumerates every distinct type class resolvable through the registry (local plus parent chain), backing the reserved-option-name computation and general discoverability.

### Changed

- **Field-option validation is now schema-driven and three-way** (validate-native, pass-through-foreign), replacing the scattered `format:`/`enum:`/`in:` applicability checks. A native option with a wrong-shaped value (`round: '2'`) raises at class load naming the expected shape; a known option used on the wrong type (`enum:` on `:integer`, a misplaced `of:`) raises naming the types it *does* apply to; an unknown option is left untouched on the `Field` so downstream tooling (e.g. an Avro schema exporter) can carry its own options. The wrong-family error *messages* changed (e.g. "enum: option does not apply to Integer fields. It applies to: String, Symbol.").
- **`Base#inspect` surfaces validity.** An invalid instance now appends its per-field errors — `#<User name: "" age: 30 errors: {name: ["is required"]}>` — so the most-read debug output no longer hides invalidity. Valid instances are unchanged, byte for byte. `inspect` reads the current errors and never re-runs validation, so printing an instance can't mutate it.

### Documentation

- Named **legibility for humans and agents** as design invariant 7 in `.claude/project_intent.md`, phrased operationally (the public surface must explain itself without source). Reconciled the source-of-truth docs with reality: `docs/origin/plan.md` is now framed as the frozen design-rationale record, `project_intent.md` carries a current Capabilities section, and `CLAUDE.md` re-points "source of truth" (current behavior → `USAGE.md`/`README.md`; rationale → `plan.md`). `USAGE.md` / `AGENTS.md` document the new runtime option discoverability and the inspect/error surfaces.

## [0.7.1] - 2026-05-28

Documentation: an adoption guide, an agent router, and clearer inheritance semantics.

### Added

- **`docs/getting_started.md`** — a getting-started / integration guide (general Ruby plus a Rails section) with a task→API map, an error→meaning→fix table, a worked end-to-end example, common mistakes, and an "agent toolbox". Its general-Ruby examples are executed by the doctest harness.
- **`AGENTS.md`** — a tool-agnostic router that points AI coding agents at the usage docs and the top gotchas (complements the Claude-specific skill; distinct from the contributor-facing `CLAUDE.md`).

### Documentation

- Documented class-macro inheritance: `coercion_policy` / `unknown_attributes` / `immutable!` / `frozen!` inherit to subclasses and a child overrides them in isolation from the parent — with the asymmetry that `immutable!` / `frozen!` are one-way (a child can add but not un-set them). Covered in the README (a doctested example + table), `USAGE.md`, and the guide's common-mistakes list.

## [0.7.0] - 2026-05-28

Two adoption-focused additions: a JSON-to-FieldStruct scaffolder for modeling existing APIs and webhooks, and a `FieldStruct.root` path helper.

### Added

- **`FieldStruct::Scaffold.from_json`** — generates starter FieldStruct class source from a JSON example, or an array of same-shape examples. A *prototype you refine*: it reconstructs nesting (nested objects → nested classes emitted before their parent), maps arrays to `:array, of: …`, and types real JSON booleans/numbers, while keeping all strings as `:string` (a numeric-looking `authorization_code` must not become an Integer) and surfacing guesses as trailing comments. With multiple samples it resolves empty fields from other samples, drives `required`/`optional` from presence, and flags small repeated vocabularies as enum candidates. Non-identifier keys are snake-cased with a `serialize :json` mapping emitted. The developer adds enums, descriptions, and final scalar types — the comments point at where.
- **`FieldStruct.root`** — returns a `Pathname` to the library's root directory (the parent of `lib/`), computed from the entry file's location so it resolves to the repo root in development and to the installed gem directory when packaged.

## [0.6.0] - 2026-05-28

Type accuracy at the call site and ergonomics for editors and AI assistants: accurate stdlib signatures (backed by an RBS collection), an RBS generator for *your* FieldStruct subclasses, a dense `USAGE.md`, a bundled Claude Code skill, a schema view on `Metadata`, and README/USAGE examples that are now executed as doctests.

### Added

- **`FieldStruct::RBS.generate(klass)`** — emits RBS for the per-field accessors the `field` DSL defines on a subclass: a typed reader (nullability follows `required?`) and a permissive `(untyped) -> untyped` writer (the type coerces loose input). Handles nested structs, `:array` (`::Array[elem]`), `:union` (`(::A | ::B)`), `:boolean` (`bool`), `:value` (`untyped`), namespaced classes (module nesting), and inheritance (emits only own fields with `< ::Parent`). This is the deferred **D13 track 2** — Sord can't see these methods because they don't exist until you declare the fields. See the README "Type signatures" section for a Rake-task wiring example.
- **`Metadata#to_h`** — a copy-pasteable schema view keyed by field name (`type`, `ruby_type`, `required`, `default`, `options`, `description`), rendered as primitives/short names so you can `pp Klass.metadata.to_h` to see a model's shape without reading its source. The block form still delegates to `Enumerable#to_h` (so `Base#attributes` is unchanged).
- **`USAGE.md`** — a dense, example-first reference covering every type, field option, and class macro, plus validation/coercion semantics, JSON, nesting, registries, and gotchas. Ships in the gem package (`bundle show field_struct`) and is included in the YARD docs.
- **Claude Code skill** — `skills/field-struct/SKILL.md` gives an assistant the DSL, the common mistakes, and how to debug an invalid instance. The repo doubles as a single-plugin marketplace via `.claude-plugin/{plugin.json,marketplace.json}` (`/plugin marketplace add Paymentbox-com/field_struct`); the skill also ships in the gem for a no-marketplace copy into `.claude/skills/`.
- **RBS collection** — `rbs_collection.yaml` vendors the stdlib `date` / `time` / `bigdecimal` signatures so `sigs:validate` can resolve fully-qualified stdlib types. CI installs it and now runs the sig guards (`sigs:check` + `sigs:validate`), which the default `rake` task never exercised.
- **Doctested examples** — `spec/docs_examples_spec.rb` executes every ` ```ruby ` block in README.md / USAGE.md that is preceded by an invisible `<!-- doctest -->` marker, asserting `# =>` expectations by value comparison.

### Changed

- **The generated sig now reports accurate stdlib return types.** `coerce` on the Date/Time/DateTime/BigDecimal types is typed `-> ::Date?` / `::Time?` / `::DateTime?` / `::BigDecimal?` instead of resolving to the FieldStruct *wrapper* classes. Core type names in the YARD docs are fully-qualified (`::String`, `::Symbol`, `::Integer`) so Sord resolves them cleanly — this clears 38 "wasn't able to be resolved to a constant" warnings.
- **`rake sigs:validate`** loads the RBS collection (and installs it on first run) instead of running `--no-collection`.

### Notes

- The bundled plugin/marketplace manifests intentionally omit a pinned `version` (git-SHA tracked) to avoid drift from `version.rb`.

## [0.5.5] - 2026-05-27

Documentation tooling: a `rake docs:generate` task that builds the YARD HTML, plus a `release:check` umbrella that runs the full pre-flight battery before every release.

### Added

- **`rake docs:generate`** — builds YARD HTML to `doc/` with `--fail-on-warning`, so broken `{#method}` links and malformed tags fail the build instead of slipping into a release.
- **`rake docs:stats`** — `yard stats --list-undoc`; quick view of remaining coverage gaps.
- **`rake release:check`** — umbrella task that runs `spec`, `rubocop`, `sigs:check`, `sigs:validate`, and `docs:generate`. The pre-flight ritual before each release commit.
- **`.yardopts`** pinning the source list (`lib/**/*.rb`) and including `CHANGELOG.md` as an extra doc.
- `yard` added to the Gemfile as a direct dev dependency (it was already present transitively via `sord`).

### Fixed

- A few YARD `{#field}` / `{#immutable!}` links inside `class << self` were unresolvable because the targets are class methods, not instance methods. Switched to the `{.field}` / `{.immutable!}` (class-method) link syntax so the strict YARD build is warning-free.

## [0.5.4] - 2026-05-27

IRB-friendly inspect across every public object, plus an opt-in `FS` alias.

### Changed

- **Custom `#inspect` / `#pretty_print` across every surface object.** The default reflection-based output dumped every ivar, making FieldStruct objects in IRB look like a wall of text. Each library object now renders concisely:

  ```
  # Field
  #<FieldStruct::Field :level String enum=["beginner", "pro"]>
  #<FieldStruct::Field :address Nested(Address) required>
  #<FieldStruct::Field :payload Union(String | Integer)>

  # Metadata — one-line inspect lists field names; pp fans out:
  #<FieldStruct::Metadata fields=[:name, :age, :email]>
  #<FieldStruct::Metadata
    #<FieldStruct::Field :name String required>
    #<FieldStruct::Field :age Integer default=0>
    #<FieldStruct::Field :email String required format=/@/>>

  # Type instances
  #<FieldStruct::Types::String>
  #<FieldStruct::Types::Nested struct_class=Address>
  #<FieldStruct::Types::Union of=String | Integer>

  # Errors / Registry
  #<FieldStruct::Errors empty>
  #<FieldStruct::Errors name=["can't be blank"]>
  #<FieldStruct::Registry types=[:string, :integer, ...]>
  ```

- **`field` / `required` / `optional` now return the class `Metadata`** instead of the just-added `Field`. The Field is still available as `metadata[name]`. This makes IRB DSL output show the running set of declared fields rather than just the last one, and feeds the new Metadata pretty-print directly. No FieldStruct internals depended on the previous return value.

### Added

- **`FieldStruct.use_alias!`** — opt-in shortcut that defines a top-level constant (default `FS`) pointing back at `FieldStruct`, *and* swaps the prefix used by every `#inspect` method in the library so output reads with the short name too. Off by default. Raises `NameError` if the chosen constant is already taken by something else.

  ```ruby
  FieldStruct.use_alias!
  FS::Base              # => FieldStruct::Base
  User.metadata
  # => #<FS::Metadata
  #      #<FS::Field :name String required>
  #      #<FS::Field :age Integer>
  #    >
  ```

### Changed (continued)

- **`Metadata#pretty_print` closes `>` on its own line** so multi-field metadata reads as a tidy block rather than trailing the last field.

## [0.5.3] - 2026-05-27

Sord-generated RBS signatures.

### Added

- **RBS signatures (`sig/field_struct.rbs`).** Generated from YARD comments via Sord and shipped in the gem. Downstream tools (Solargraph, Steep, RBS-aware editors) get type info for the public surface without configuring anything. Three new rake tasks:
  - `rake sigs:generate` — regenerate from current YARD
  - `rake sigs:validate` — parse-check the committed sig file
  - `rake sigs:check` — fail if the committed sigs are stale (CI guard)
- **`sord` and `rbs` as Gemfile development dependencies.** Both `require: false`.

The custom Metadata→RBS generator for *user-defined* FieldStruct subclasses (per D13 in the plan) remains deferred — Sord covers the library's hand-written classes; the user-class generator is its own future effort.

## [0.5.2] - 2026-05-27

Field-level documentation metadata.

### Added

- **Field-level `description:` (aliased as `desc:`).** Attach a human-readable description to any field for downstream documentation generators.

  ```ruby
  required :email, :string, description: 'Primary contact email'
  required :age,   :integer, desc: 'Age in years'
  ```

  Stored as a first-class attribute on `Field` (`field.description`, with `field.desc` as a reader alias) — not in `Field#options`. Documentation metadata only: does not appear in `attributes` / `as_json` / pattern matches. Passing both `description:` and `desc:` raises `ArgumentError`. Subclass re-declarations replace the inherited description (including back to `nil` if not provided).

## [0.5.1] - 2026-05-27

Two internal refactors that set the gem up for an eventual RBS generator
and improve IDE / Sord / Solargraph readings of the public surface. No
behavior change.

### Changed

- **`Type#coerce` signatures are now typed kwargs.** Each type's `coerce` method declares the options it consumes as named keyword arguments with a trailing `**` catch-all. The Hash-as-positional pattern is gone from the type contract; the loose base contract is `def coerce(value, **) = raise NotImplementedError` and each subclass narrows. Sets the gem up for an eventual RBS generator that emits useful per-type signatures.

  ```ruby
  # Before
  def coerce(value, options = {})
    fmt = options[:format] || self.class.default_format
  end

  # After
  def coerce(value, format: self.class.default_format, **)
    # fmt is bound directly
  end
  ```

  The setter pipeline splats `field.options` at the call site (`coerce(value, **field.options)`), so the Hash storage on `Field` is unchanged. Existing call sites that pass options as kwargs are unaffected; the rare positional Hash needs explicit braces (`type.coerce({key: 'val'})`) to be the value, not options.

- **Internal DSL helpers are now functional**, returning new Hashes instead of mutating in place. `apply_default_format!`, `resolve_array_options!`, `build_union_instance!` → `apply_default_format`, `resolve_array_options`, `build_union_instance`. Callers update via reassignment in `Base.field`.

- **YARD `@param` types tightened library-wide.** Type coerce methods, value-object attrs (Field/Metadata), DSL macros (`field`, `coercion_policy`, `unknown_attributes`, `validate`), and the Errors family all now declare the actual accepted union types instead of generic `[Object]` / `[Hash]`. Duck-typed inputs use `#to_x` interface notation (`[Date, #to_date, String, nil]`). Strictly-bounded types name the exact set (`Symbol#coerce` is `[Symbol, String, nil]`). Documentation-only — zero behavior change.

## [0.5.0] - 2026-05-27

Per-type field options + presets.

### Added

- **`round:` option on `:big_decimal` / `:decimal` / `:float`** — Integer that controls `.round(n)` after coercion.
- **`values:` option on `:boolean`** — Hash `{truthy: [...], falsy: [...]}` for explicit vocabularies, or a Symbol preset. Built-in presets: `:english_yes_no`, `:english`, `:numeric`.
- **`format:` option on `:date` / `:datetime` / `:time`** — strftime/strptime String (or Symbol preset), applied in both directions: input strings parse via `strptime`, output via `strftime`. Built-in presets: `:iso8601`, `:rfc2822`, `:db`, plus `:us` / `:eu` for `:date`.
- **`format:` Symbol-preset support on `:email` / `:uuid` / `:url`** — the existing Regexp option now also accepts named presets. `:email` → `:permissive`/`:default`/`:strict`; `:uuid` → `:any_version`/`:v4`/`:v7`; `:url` → `:http`/`:https_only`/`:any_scheme`.
- **`Types::Base.resolve_options(options)` hook** — a per-type seam for resolving Symbol presets at field-declaration time. Pass-through by default; subclasses override to interpret their own options.
- **`Types::PresetResolver`** and **`Types::TimeFormatResolver`** — small helpers used by the built-in types; downstream type subclasses can reuse them.

### Changed

- **`DEFAULT_FORMAT` / `TRUTHY_STRINGS` / `FALSEY_STRINGS` constants removed.** The defaults live on class methods (`default_format`, `default_truthy`, `default_falsy`) so subclasses can override with a one-line method instead of redeclaring a constant. Existing callers that reach for `Types::UUID::DEFAULT_FORMAT` etc. must call `Types::UUID.default_format` instead.
- **`format:` validator loosened** — previously restricted to string-shaped types. Time-shaped types (`:date`, `:time`, `:datetime`) are now also format-aware (with strftime/strptime semantics). Non-format-aware types still raise.

## [0.4.0] - 2026-05-27

Serialization-formats redesign. Aliases are no longer a per-field
attribute; they're a class-level mapping declared via the new
`serialize` macro and consulted only by JSON I/O.

### Added

- **`serialize` class macro.** Declares an import/export mapping for a named
  format, stored on `Metadata#serializations`:

  ```ruby
  class User < FieldStruct::Base
    required :first_name, :string
    serialize :json, first_name: 'firstName'
  end
  ```

  Internal-symbol on the left, external-string on the right; the same
  mapping applies to both directions. Fields not listed use their
  canonical name. Multi-format coexistence is allowed (`:json`, `:csv`,
  …); only `:json` is wired in-gem (downstream gems can read
  `Klass.metadata.serializations[:their_name]` for their own I/O).
  Mapping keys must be declared fields — undeclared keys raise
  `ArgumentError` at class load.

### Changed

- **`as_json` / `to_json`** apply the `:json` mapping when one is declared
  (identity otherwise). Round-trip via `Klass.from_json(instance.to_json)`
  preserves structural equality.
- **`from_json`** reverse-maps the parsed hash recursively (through nested
  FieldStructs and arrays of nested) before calling `.new`.

### Removed (breaking)

- **`aliases:` field option** — per-field alias declarations are gone.
  Lift them up to a `serialize :json, ...` block on the class.

  ```ruby
  # Before:
  required :first_name, :string, aliases: ['firstName']

  # After:
  required :first_name, :string
  serialize :json, first_name: 'firstName'
  ```

- **`aliased: true` kwarg** on `attributes` / `to_h` / `as_json` /
  `to_json` — no longer accepted. `to_json` already applies the
  declared mapping; `to_h` / `attributes` stay canonical.
- **`Field#aliases`**, **`Field#export_name`**, and **`Metadata#field_for`**
  removed from the public surface. `Metadata#[name]` is the canonical
  lookup; lookup by external name is the serializer's concern.

## [0.3.2] - 2026-05-27

Ruby pattern matching support.

### Added

- **Pattern matching** — every FieldStruct instance now works as a Ruby 3.0+ pattern target. `deconstruct_keys(keys)` returns the canonical-name attribute hash (sliced down when keys is given, full when keys is `nil`); `deconstruct` returns field values in declaration order. Nested FieldStructs recurse naturally because every subclass inherits the same protocol. Aliases and `errors` do not participate (patterns match data, not validity, and use canonical names — the Ruby-side convention). Frozen and immutable instances work identically.

## [0.3.1] - 2026-05-27

Two small ergonomics improvements on top of v0.3.0.

### Added

- **Callable defaults** — `default:` now accepts a literal OR a parameterless callable (Proc, Lambda, Method, anything that responds to `#call`). Callables are invoked once per instance during apply_defaults; the return value flows through the setter pipeline like any other default. Safe for per-instance values like timestamps or generated IDs.
- **`FieldStruct.new_registry`** — shorthand for building a namespace registry. Defaults the parent to `FieldStruct.types`; an explicit `nil` parent gives an unparented registry. The block (optional) is evaluated in the new registry's instance scope, so `register :money, Acme::Money` works without a receiver.

## [0.3.0] - 2026-05-27

Phase 2 wave two: union types, the `:binary` extended type, and the
`frozen!` class macro. All five Phase 2+ backlog items that belong
in-gem are now landed; RBS gen / format converters / docs generator
remain deferred to separate downstream gems.

### Added

- **`:binary` extended type** — Types::Binary subclasses Types::String and forces ASCII-8BIT encoding on the coerced value. `missing?` is nil-or-empty only (whitespace bytes are meaningful). Designed for raw bytes / BLOBs.
- **`frozen!` class macro** — instances are Ruby-frozen at the end of `initialize`; subsequent ivar mutations raise `FrozenError`. Inherited by descendants. Independent of `immutable!` (which uses our custom `ImmutableError`). The two can stack.
- **Union types** — `optional :payload, :union, of: [Payload, :boolean]`. Each member type is tried in declared order; the first that doesn't raise wins. Member-coercion errors are caught broadly (ArgumentError, TypeError, FieldStruct::Error); unrelated bugs still propagate. If every member rejects, the union raises `TypeError` and the parent's `coercion_policy` engages. `ruby_type` returns a flat, deduplicated `Array<Class>` across all members. Declaration-time guards require `of:` to be an Array with at least two members.

## [0.2.0] - 2026-05-27

Phase 2 first wave. Nested struct support, JSON import, field-name
aliases, cross-field validation, field-level coercion policy override,
extended scalar types (`:symbol`, `:uuid`, `:url`, `:email`), and
`enum:` / `in:` value-restriction field options.

### Added

- **Nested FieldStructs** — declare `field :address, Address` where `Address < FieldStruct::Base`. Coerce nil / instance / Hash; eager `'is invalid'` stamp on the parent at assignment time; inner construction errors (`UnknownAttributeError`, `CoercionError`) propagate to the caller rather than being caught by the parent's `coercion_policy`. Arrays of nested work via `of:` (class or symbol form). `as_json` deep-walks. `Types::Nested` is the wrapping type; `Field` accepts a pre-built `type_instance:` so parameterized types flow through the same plumbing as stock types.
- **`Klass.from_json(string)`** — JSON import driven off Metadata. Parses with Oj, feeds through `initialize`, so coercion / nested construction / `unknown_attributes` / `coercion_policy` engage as normal. Non-object JSON roots raise `ArgumentError`; malformed JSON propagates the underlying parse error. Round-trips structurally for every base type except `:value`.
- **Extended scalar types** — `:symbol`, `:uuid`, `:url`, `:email`. The string-shaped trio (`:uuid` / `:url` / `:email`) subclasses `Types::String` and pre-fills the field's `format:` option from a class-level `default_format`. Users can override with `format: /.../`.
- **`enum:` and `in:` field options** — two parallel "value must be one of these" options. `enum: [...]` works on string-like types (`:string`, `:symbol`, and subclasses including `:uuid` / `:url` / `:email`). `in: [...]` or `in: range` works on rangy types (`:integer`, `:float`, `:decimal`, `:date`, `:time`, `:datetime`); accepts an Array or any Range. Both run post-coercion. Mismatch is a `'is invalid'` validation error, mirroring `format:`. Declaration-time guards reject the wrong combination.
- **Field-level `coercion_policy:` override** — `field :x, :integer, coercion_policy: :raise` overrides the class default for a single field. Falls back to the class macro when not specified. Unknown values raise `ArgumentError` at class load.
- **Cross-field validation** — `validate { |record| ... }` blocks and `validate :method_name` symbol form (interchangeable, can be mixed and stacked). Validators run at the end of `initialize` and on every `valid?` call. Convention is `errors.add(:base, '...')`; `errors[:base]` is cleared between cross-field runs, while field-level setter errors are preserved. Validators are inherited by subclasses (the subclass receives a `dup` of the parent's list and appends its own). Classes with no `validate` declarations keep Phase 1's cheap `valid? = errors.empty?` behavior.
- **Field-name aliases** — declare `field :email, :string, aliases: ['EmailAddress', 'email_address']` to bridge external naming conventions. Import accepts any declared alias (canonical wins on conflict); export opts in via `as_json(aliased: true)` / `to_json(aliased: true)` / `to_h(aliased: true)` / `attributes(aliased: true)` using each field's first alias. `unknown_attributes :raise` treats aliases as known. Aliases propagate through nested FieldStructs. No Ruby-side getter/setter methods are auto-defined for alias names — Ruby code always uses the canonical name. `Field#aliases` is a first-class attribute and `Metadata#field_for(name)` looks up by canonical-or-alias.

## [0.1.0] - 2026-05-27

Initial release. Typed-PORO foundation: declared fields with enforced
types, presence checks, per-field validation, and an ActiveModel-shaped
public surface that reuses no ActiveModel code.

### Added

- **DSL macros** — `field`, `required`, `optional` for declaring
  attributes. Type is the second positional argument.
- **Class macros** — all inherited by descendants, all overridable:
  - `coercion_policy :keep_raw | :replace | :raise` (default `:keep_raw`)
  - `immutable!` — one-way switch; setters post-`initialize` raise
    `FieldStruct::ImmutableError`
  - `unknown_attributes :ignore | :raise` (default `:ignore`)
- **Base types** — `:string`, `:immutable_string`, `:integer`, `:float`,
  `:big_decimal` (with `:decimal` alias), `:boolean`, `:date`, `:time`,
  `:datetime`, `:value`, `:array` (with required `of:` element type).
- **Per-field validation on assignment** — every setter runs
  `coerce → store → presence-check → format-check`, and the setter owns
  its field's errors.
- **`format:` field option** for string-shaped fields; declaration-time
  guard against use on non-string types.
- **Registry** — `FieldStruct::Registry` with parent-chain lookup;
  `FieldStruct.types` is the seeded base. Namespaces extend by defining
  a module-level `field_types` method.
- **Inheritance** — subclasses inherit parent metadata, parent
  declarations are not mutated when a child adds or shadows a field.
- **AM-shaped public surface** (interface only, no AM code reuse):
  `valid?`, `invalid?`, `errors`, `attributes`, `attribute_names`,
  `assign_attributes`, `to_h`, `as_json`, `to_json` (via Oj), `inspect`,
  `model_name`, `to_model`.
- **Structural equality** — `==` / `eql?` / `hash` over
  `[class, attributes]`; errors ignored.
- **`FieldStruct::Errors`** value object — `[]`, `add`, `clear`,
  `empty?`, `to_h`, `messages`.
- **Error classes** — `FieldStruct::Error` (base),
  `FieldStruct::CoercionError`, `FieldStruct::ImmutableError`,
  `FieldStruct::UnknownAttributeError`.
- **YARD comments** on the public surface.

### Notes

- Boolean's `ruby_type` returns `[TrueClass, FalseClass]` because Ruby
  has no Boolean class — the contract is "Class or Array<Class>"
  (`Value#ruby_type` is `Object`).
- Array coercion is whole-value under `coercion_policy`: a single bad
  element causes the array to be treated as one uncoercible value, and
  the class's policy applies to that whole array. Per-element policy
  is a Phase 2 candidate.
