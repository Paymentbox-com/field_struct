# FieldStruct — Phase 1 Plan

> Source-of-truth design and slice plan for FieldStruct v0.1.0. Lives alongside the original conversation in `docs/origin/`. Update this file when locked decisions change.

---

## Overview

**FieldStruct** is a Ruby library for building POROs ("Plain Old Ruby Objects") with declared attributes that have enforced types, presence checks, and validation. The class collects its field declarations into a class-level **Metadata** object that can be inspected, introspected, and used to generate type signatures later. Each field is backed by a **Type** class that knows how to coerce input values and decide what counts as a "missing" value. Types live in a **Registry** so that different namespaces can extend or replace the base set.

The library is consciously *not* a database layer, *not* a form object, *not* an ActiveModel replacement. It is a typed-value-object foundation that other layers can build on.

The name of the public module is `FieldStruct`. Users get features by subclassing `FieldStruct::Base`.

```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age, :integer
  optional :nicknames, :array, of: :string
end

u = User.new(name: "Alice", nicknames: ["Al", "Ally"])
u.valid?              # => true
u.attributes          # => { name: "Alice", age: nil, nicknames: ["Al", "Ally"] }

u.name = ""
u.valid?              # => false
u.errors[:name]       # => ["is required"]
```

---

## Phase 1 scope (v0.1.0)

### In scope

- `FieldStruct::Base` superclass; subclasses inherit field declarations
- DSL macros: `field`, `required`, `optional`
- Per-field metadata via `FieldStruct::Field` and `FieldStruct::Metadata`
- `FieldStruct::Registry` (formerly "TypeCollection" in the original discussion)
- Base registry at `FieldStruct.types`, seeded with all v1 types
- Namespace-level registries via a module-level `field_types` method, with parent-chain lookup
- Base types: `:string`, `:immutable_string`, `:integer`, `:float`, `:big_decimal` (alias `:decimal`), `:boolean`, `:date`, `:time`, `:datetime`, `:value`
- **Array type** (`:array`) with required `of:` option naming the element type
- Per-field validation on every assignment: coerce → store → presence → format
- Errors maintained incrementally; setter owns its field's errors
- Class macros, all inherited by descendants, all overridable:
  - `coercion_policy :keep_raw | :replace | :raise` (default `:keep_raw`)
  - `immutable!` (default mutable)
  - `unknown_attributes :ignore | :raise` (default `:ignore`)
- `format:` field option (regex check for string-shaped fields, applied to non-missing values)
- ActiveModel-shaped public surface (interface only — no ActiveModel code reuse): `valid?`, `invalid?`, `errors`, `attributes`, `attribute_names`, `assign_attributes`, `to_h`, `as_json`, `to_json`, `inspect`, `model_name`, `to_model`, `==`, `eql?`, `hash`
- JSON output via the **Oj** gem
- Structural equality across same-class instances (errors not considered)
- Types expose `ruby_type` to keep the door open for an RBS generator later
- YARD doc comments on the public surface
- RSpec test suite; Rubocop clean; SimpleCov coverage

### Out of scope (Phase 2+)

- Nested FieldStructs (FS-as-type)
- JSON *import* (only `as_json` / `to_json` for output in v1)
- Field-name and type aliases (e.g. `EmailAddress` → `:email`)
- Cross-field validation (`validate { ... }` blocks)
- Custom RBS / Sorbet generation off Metadata
- Union types (`as: [Payload, :boolean]`)
- Conversion to/from CSV, XML, Avro, JSON-schema
- Auto-generated Markdown / HTML documentation
- Field-level coercion-policy override (currently class-level only)
- Extended types: `:uuid`, `:url`, `:email`, `:symbol`, `:enum`
- ActiveModel persistence-shaped methods (`to_key`, `to_param`, `to_partial_path`, `persisted?`, `new_record?`)
- Frozen-on-construct sugar (users can call `.freeze` themselves)

---

## Locked design decisions

Each decision below was settled in design conversation. Where the *why* is non-obvious, it is recorded so future revisits have context.

### D1. Phase 1 cut: core only

DSL + Registry + base types + Metadata + per-field validation + class macros. **No nested FieldStructs**, JSON import, aliases, or RBS generation in v1. Each deferred feature is independent and benefits from being designed against a real Metadata.

### D2. DSL form: `field` + `required` / `optional`

```ruby
field :x, :string                  # neutral; defaults to optional behavior
required :x, :string               # explicit; presence-checked
optional :x, :string               # explicit; not presence-checked
```

`field` is the primitive. `required` and `optional` are thin wrappers that set the `required:` option. Type is the **second positional argument**.

### D3. Coercion-failure policy is a class macro

Three policies:

| Policy | Behavior |
|---|---|
| `:keep_raw` *(default)* | Collect a coercion error; leave the original uncoercible value on the instance |
| `:replace` | Collect a coercion error; replace the value with `nil` |
| `:raise` | Raise `FieldStruct::CoercionError` from the setter |

Set per-class, inherited by descendants:

```ruby
class Strict < FieldStruct::Base
  coercion_policy :raise
end
```

No per-field override in v1. `:replace` always inserts `nil` — not the type's "null/default value" — to keep the surface small.

### D4. Required = "value is not missing after coercion"

Required fields fail validation when the *value* (post-coercion) is "missing." The **type** decides what missing means — each type implements `missing?(value)`. The library follows ActiveModel guidance for defaults:

| Type | Missing if |
|---|---|
| `:string`, `:immutable_string` | nil, empty, or whitespace-only |
| `:integer`, `:float`, `:decimal`, `:big_decimal` | nil only (`0` is valid) |
| `:boolean` | nil only (`false` is valid) |
| `:date`, `:time`, `:datetime` | nil only |
| `:array` | nil or empty |
| `:value` | nil only |

Defaults satisfy required (the *value* is what's checked, not whether the input hash contained the key).

### D5. Validation lifecycle: per-field on assignment

Every setter runs the full pipeline: coerce → store → presence check → format check → update `errors[field]`. The setter owns its field's errors — assigning to a field always clears and rebuilds errors for *that field*, regardless of prior state.

`new(hash)` and `assign_attributes(hash)` are just bulk-invocations of the per-field setters.

`valid?` is a cheap read of `errors.empty?` — no recomputation. Lazy/eager distinction doesn't apply because validation is already a side effect of mutation.

**Cross-field validation is out of scope for v1.**

### D6. Mutability is a class macro

Default mutable. `immutable!` switches the class (and descendants) to immutable. Enforcement: `@_initialized` flag set at end of `initialize`; setters check it; raise `FieldStruct::ImmutableError` if set on an immutable class. Custom error chosen over `freeze`/`FrozenError` so we control the message and avoid blocking benign instance state.

### D7. Unknown attributes: class macro `unknown_attributes`

```ruby
unknown_attributes :ignore   # default
unknown_attributes :raise
```

`:raise` raises `FieldStruct::UnknownAttributeError`. A `:collect` mode (stash unknowns in an extras bucket) is deferred to Phase 2 — it has implications for export, equality, and aliases that we don't need to design yet.

### D8. ActiveModel-shaped public surface (interface only)

We mirror the shape so Rails-adjacent developers feel at home, but we do not reuse `ActiveModel::*` code. Methods in v1:

- `valid?`, `invalid?`, `errors`
- `attributes`, `attribute_names`, `assign_attributes`
- `to_h`, `as_json`, `to_json` (via Oj)
- `==`, `eql?`, `hash`
- `inspect`
- `model_name` (AM naming), `to_model` (returns self)

Skipped: `to_key`, `to_param`, `to_partial_path`, `persisted?`, `new_record?` — they encode a persistence/identity model FieldStruct does not have.

`errors` is a `FieldStruct::Errors` value object with `[]`, `add`, `clear(field)`, `empty?`, `to_h`, `messages`. Familiar at call-sites; no AM code reuse.

### D9. Structural equality

| Op | Behavior |
|---|---|
| `==` | Same class **and** same attribute values. Errors ignored. |
| `eql?` | Aliased to `==`. |
| `hash` | `[self.class, attributes].hash`. |
| `dup` / `clone` | Standard Ruby semantics; carries errors and immutable flag. |

### D10. Base type list

`:string`, `:immutable_string`, `:integer`, `:float`, `:big_decimal` (with `:decimal` as alias), `:boolean`, `:date`, `:time`, `:datetime`, `:value`, plus `:array` (parameterized via `of:`).

Each type class lives at `FieldStruct::Types::*` and exposes:

- `coerce(value, options = {})`
- `missing?(value)`
- `ruby_type` — used later by the RBS generator. Returns either a single `Class` (the typical case: `Types::String#ruby_type == ::String`) **or** an `Array<Class>` for types that span multiple Ruby classes. The only Phase 1 case is `Types::Boolean`, which returns `[TrueClass, FalseClass]` because Ruby has no Boolean class; the RBS generator can collapse that pair to the `bool` alias.

`:value` is a no-coercion passthrough — useful as an escape hatch. Its `ruby_type` is `Object`.

### D11. Array type

`:array` is parameterized via a **required** `of:` option naming the element type:

```ruby
required :tags, :array, of: :string
optional :ages, :array, of: :integer
```

- `of:` accepts a **symbol only** in v1 (must be a key registered in the resolving registry); class arguments are deferred.
- Element coercion: each value coerced via the element type. The class's `coercion_policy` applies to each element coercion attempt.
- `missing?` is nil-or-empty.
- The `of:` option name is reserved for parameterization broadly — future types (e.g. union) may reuse it.

### D12. Registry as namespace-level method

Registry class: `FieldStruct::Registry`. Base instance: `FieldStruct.types`, seeded with v1 types.

A namespace exposes its own registry by defining a module-level method:

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct::Registry.new(FieldStruct.types)  # parented to base
  end
  field_types.register :money, Acme::Types::Money
end

module Betamax
  def self.field_types
    @field_types ||= FieldStruct::Registry.new                     # empty / unparented
  end
  field_types.register :string, Betamax::Types::String
  # ...register every type the namespace needs
end
```

Lookup for a class like `Acme::Order < FieldStruct::Base` walks the **full** nesting chain in Ruby's natural order — `Acme::Order` → `Acme::Order`'s containing module `Acme` → … — until a module that responds to `field_types` is found. Falls back to `FieldStruct.types` if none.

`Registry` API:

- `register(name, type_class)` — add a type
- `register(alias_name, existing_name)` — register an alias to another registered name
- `lookup(name)` — return the type class; raises if not found (walks parent chain)
- `key?(name)` — boolean check (walks parent chain)
- `parent` — the parent registry, or `nil`

### D13. RBS generation strategy (deferred, but informs v1)

A custom Metadata→RBS generator is the intended approach, written against the in-memory `Metadata` of each subclass. Sord may be used for hand-written internal classes only. To keep the door open, every type exposes `ruby_type` in v1 even though no generator consumes it yet.

### D14. Source layout: standard, explicit requires

Standard `lib/field_struct.rb` entry point, but with **explicit `require_relative` for every file** — no autoload, no Zeitwerk. Predictable, reviewable, and fine for a library this size.

```
lib/
  field_struct.rb                  # entry: require_relative everything
  field_struct/
    version.rb
    errors.rb                      # FieldStruct::Errors value object
    error.rb                       # exception classes
    base.rb                        # FieldStruct::Base
    metadata.rb
    field.rb
    registry.rb
    types/
      base.rb
      string.rb
      immutable_string.rb
      integer.rb
      float.rb
      big_decimal.rb
      boolean.rb
      date.rb
      time.rb
      datetime.rb
      value.rb
      array.rb
```

### D15. Branching: `develop` + per-feature branches

`main` = released. `develop` = integration. Per-feature branches off `develop`, merged back into `develop`. Release = `develop` → `main` via PR. Conventional commits (`feat:` / `fix:` / `refactor:` / `test:` / `docs:` / `chore:`). Tests ship in the same commit as the code they prove (per `tdd_guidelines.md`).

---

## Slice plan

15 slices, ordered so each is independently testable and unblocks the next. Foundation first (types → registry → metadata → DSL), then the macros that ride on top, then ergonomics, then release prep.

Every slice produces one or more atomic commits. Every test ships in the same commit as the code it proves.

### Slice 1 — Type system foundation

Goal: the `Types::Base` contract and one concrete type, fully tested in isolation. No `Base` class yet.

- `FieldStruct::Types::Base` with `coerce(value, options = {})`, `missing?(value)`, `ruby_type`
- `FieldStruct::Types::String` (first concrete)
- Specs: coerce happy/sad path, `missing?` semantics (nil/empty/whitespace), `ruby_type` returns `String`

Commits: `feat: introduce type system foundation with string type`

### Slice 2 — Remaining scalar base types

One commit per type. Each ships with happy-path coerce, sad-path coerce, `missing?` spec, `ruby_type` spec.

Types to add: `ImmutableString`, `Integer`, `Float`, `BigDecimal` (with `:decimal` alias-style class reuse), `Boolean`, `Date`, `Time`, `DateTime`, `Value`.

Commits (one per): `feat: add immutable_string type`, `feat: add integer type`, `feat: add float type`, `feat: add big_decimal type`, `feat: add boolean type`, `feat: add date type`, `feat: add time type`, `feat: add datetime type`, `feat: add value type`.

### Slice 3 — Registry

Goal: the namespace-aware type registry.

- `FieldStruct::Registry` with `register`, `lookup` (walks parent), `key?`, `parent`
- Symbol aliases (`register(:decimal, :big_decimal)` makes `:decimal` resolve to `BigDecimal`)
- `FieldStruct.types` — the seeded base registry containing all v1 scalar types and `:decimal` alias
- Specs: register/lookup, alias resolution, parent fallback, unknown raises, lookup descends from base when no parent

Commits: `feat: add registry for type lookup with parent chain`

### Slice 4 — Field and Metadata

Goal: data structures behind the DSL, designed without the DSL itself.

- `FieldStruct::Field`: `name`, `type` (resolved class), `required?`, `default`, `options`
- `FieldStruct::Metadata`: per-class collection — `add(field)`, `[name]`, `names`, `each`, `merge(parent)`
- Specs: round-trip, merge keeps order, lookup by name, immutable from outside

Commits: `feat: add field and metadata value objects`

### Slice 5 — Base + `field` macro

Goal: minimum to write `class User < FieldStruct::Base; field :name, :string; end` and have it work.

- `FieldStruct::Base` class
- `.field(name, type, **options)` macro: resolves type via registry, builds `Field`, adds to `Metadata`, defines getter and setter
- Setter coerces via the resolved type
- `initialize(attrs = {})` calls each declared setter with the matching value
- `attributes` returns a new hash; `attribute_names` returns the list
- Subclass inheritance via `inherited` hook (merges parent's metadata)
- **Registry resolution walks the class's full nesting chain** (Ruby-style) at field-declaration time, looking for the first containing module that responds to `field_types`. Falls back to `FieldStruct.types`.
- Specs: declare → instantiate → read attrs; setter coerces; subclass adds to parent's fields; class in namespace uses namespace registry; deeply-nested namespace walks the chain.

Commits: `feat: introduce FieldStruct::Base with field macro`

### Slice 6 — `required` / `optional` + presence validation

Goal: required fields actually enforce presence.

- `.required(name, type, **opts)` and `.optional(name, type, **opts)` as sugar over `.field`
- `FieldStruct::Errors` value object: `[]`, `add`, `clear(field)`, `empty?`, `to_h`, `messages`
- Setter pipeline now: coerce → store → call `type.missing?` if required → update `errors[field]`
- `valid?`, `invalid?`, `errors` on `Base`
- Specs: required + nil → error; required + value → no error; mutate to nil → error appears; mutate to value → error clears; setter owns its field's errors

Commits: `feat: add required/optional macros and presence validation`

### Slice 7 — Array type

Goal: `:array` with `of:` option.

- `FieldStruct::Types::Array`:
  - `coerce(value, options)` — read `options[:of_type]` (pre-resolved), coerce each element through it
  - `missing?(value)` — `nil` or `empty?`
  - `ruby_type` — returns `Array`
- DSL change in `Base.field`: when type is `:array`, the `of:` option is **required**; the symbol named in `of:` is resolved (via the same registry-chain logic) into a type class and stashed as `options[:of_type]` for the type to consume
- Field-level error if `of:` is missing on an `:array` declaration (declaration-time error, raised at class load)
- Specs: declare array field; coerce mixed input; per-element coercion errors flow through class's coercion policy; required + nil/empty → error; missing `of:` raises at declaration

Commits: `feat: add array type with element coercion`

### Slice 8 — `coercion_policy` macro

Goal: the three policies wired in.

- `.coercion_policy(:keep_raw | :replace | :raise)` class macro
- `FieldStruct::CoercionError`
- Setter pipeline catches coercion failures and dispatches to the policy:
  - `:keep_raw` — store raw value, add error
  - `:replace` — store `nil`, add error
  - `:raise` — raise `FieldStruct::CoercionError`
- Default `:keep_raw` on `Base`
- Inherited by subclasses; subclass can override
- Specs: each policy under bad input; subclass inherits; subclass overrides

Commits: `feat: add coercion_policy macro with keep_raw, replace, raise modes`

### Slice 9 — `immutable!` macro

Goal: post-init assignment guard.

- `.immutable!` class macro (sets a class-level flag, inherited)
- `@_initialized` instance flag set at end of `initialize`
- Setters check flag and class setting; raise `FieldStruct::ImmutableError` if set and immutable
- Specs: default mutable; immutable subclass blocks post-init writes; subclass-of-mutable can opt in; subclass-of-immutable inherits

Commits: `feat: add immutable! macro`

### Slice 10 — `unknown_attributes` macro

Goal: unknown-key handling on input.

- `.unknown_attributes(:ignore | :raise)` macro
- `FieldStruct::UnknownAttributeError`
- `initialize` / `assign_attributes` consult policy when seeing keys not in `Metadata`
- Default `:ignore` on `Base`; inherited
- Specs: default ignores; `:raise` raises; subclass override

Commits: `feat: add unknown_attributes macro`

### Slice 11 — `assign_attributes`

Goal: expose the multi-attribute path as a public method; route `initialize` through it.

- Public `assign_attributes(hash)` method
- `initialize` becomes a thin wrapper that calls `assign_attributes` after setting defaults
- Specs: bulk update runs each setter; respects all policies; returns self

Commits: `refactor: route initialize through assign_attributes`

### Slice 12 — Equality, hash, dup

Goal: structural identity per D9.

- `==` / `eql?` / `hash` over `[class, attributes]`, ignoring errors
- `dup` / `clone` use Ruby defaults (verified by spec)
- Specs: equal across instances; different class → not equal; errors don't affect equality; works as `Set` member and `Hash` key; `dup` preserves immutable flag

Commits: `feat: add structural equality and hashing`

### Slice 13 — AM-shaped surface completion

Goal: finish the public API per D8.

- `to_h` (alias of `attributes`)
- `as_json` (hash, ready for Oj/`to_json` and any consumer)
- `to_json` via Oj
- `inspect` (readable per-field repr)
- `model_name` (AM-compatible naming, hand-rolled)
- `to_model` (returns self)
- Specs per method

Commits: `feat: complete ActiveModel-shaped public surface`

### Slice 14 — `format:` field option

Goal: the one specialized validation called out in the original discussion.

- `field :email, :string, format: /.../`
- Setter pipeline addition: after coerce + missing check, if value is non-missing and a `format:` option is set, run the regex match; add error on mismatch
- Applies to string-shaped fields (string, immutable_string) in v1; ignored or raises declaration-time error on others (TBD during implementation — prefer raise)
- Specs: match → no error; mismatch → error; optional + nil → no error (format only checks non-missing); error clears on next good assign

Commits: `feat: add format validation option`

### Slice 15 — Docs + release prep

Goal: ship v0.1.0.

- README rewrite (drop scaffold TODOs, add real usage examples)
- CHANGELOG entry
- gemspec metadata filled in (summary, description, homepage, source_code_uri, allowed_push_host)
- YARD comments on public surface
- Coverage report check via `COVERAGE=1 bin/rspec`
- Rubocop clean
- `bundle exec rake` clean
- Tag v0.1.0

Commits: `docs: add usage examples to README`, `chore: fill gemspec metadata`, `chore: release v0.1.0`

---

## Phase 2 — Field-name aliases (in flight)

Bridge external naming conventions to internal FieldStruct conventions. The original `first_discussion.md` notes call for this; the decisions below were locked during the design walkthrough on the `aliases` branch.

### A1. Declaration

```ruby
required :email, :string, aliases: ['EmailAddress', 'email_address']
```

Single keyword option `aliases:` taking an `Array<String|Symbol>`. Always an array — a single alias is `['Name']`. Empty array (`[]`) is the default. Aliases are normalized to symbols and stored on `Field#aliases` as a frozen array. Aliases are *not* present in `Field#options`.

### A2. Import — conflict resolution

When the same input hash carries both the canonical key and an alias key for the same field, **canonical wins**. The alias entry is silently ignored. This holds independent of Hash iteration order.

### A3. Export — opt-in via `aliased: true`

```ruby
person.as_json                    # canonical
person.as_json(aliased: true)     # uses each field's first alias
person.to_h(aliased: true)
person.to_json(aliased: true)
person.attributes(aliased: true)
```

The kwarg propagates through nested `FieldStruct::Base` values and through arrays of nested structs via `json_value`. For a field without aliases, the canonical name is used in aliased output too — no awkward gaps. Only the **first** alias from the declared `aliases:` array is used for export; the rest are import-only.

### A4. Ruby-side accessors

**No** Ruby methods are auto-defined for alias names. Aliases participate only in `Klass.new`/`from_json` (import) and `as_json(aliased: true)` etc. (export). Ruby code always uses the canonical name to read or write a field. This keeps the public surface clean of capitalized or camelCase method names that look out of place in idiomatic Ruby.

### A5. Unknown-attributes interaction

`unknown_attributes :raise` treats aliases as known. An input hash with `{'EmailAddress' => '...'}` does not raise for a field declared `aliases: ['EmailAddress']`. The check uses `Metadata#field_for(name)` which consults canonical names *and* aliases.

### A6. Storage

`Field#aliases` is a first-class attribute (alongside `name`, `type`, `required?`, `default`, `options`) — not stashed inside `options`. `Field#export_name` returns the first alias if present, otherwise the canonical name. `Metadata#field_for(name)` looks up by canonical or alias.

---

## Phase 2 — JSON import (in flight)

`Klass.from_json(json_string)` builds an instance.

### J1. Surface

A single class method on `Base`. No `from_hash` companion — `.new(hash)` already covers that case.

### J2. Pipeline

`Oj.load(string, mode: :compat)` → guard against non-object roots → `Klass.new(parsed_hash)`. The existing setter pipeline handles everything from there: scalar coercion (strings re-coerce to Date/Time/BigDecimal), nested-hash → `Types::Nested` instantiation, arrays-of-nested, `unknown_attributes` policy, `coercion_policy`.

### J3. Errors

- Invalid JSON → underlying parser error propagates (Oj raises `EncodingError` / `Oj::ParseError`).
- JSON root that isn't an object (`[...]`, `"hi"`, `42`, `null`) → `ArgumentError` with a clear message naming the actual class.
- `unknown_attributes :raise` → `FieldStruct::UnknownAttributeError` (from `initialize`).
- `coercion_policy :raise` → `FieldStruct::CoercionError` (from the setter pipeline).

### J4. Round-trip

`Klass.from_json(instance.to_json)` is structurally equal to `instance` for every base type except `:value` (which carries no type info beyond what JSON exposes natively — Symbols, for example, come back as Strings).

---

## Phase 2 — Nested FieldStructs (in flight)

Locked decisions for the first Phase 2 slice. See the design walkthrough notes in commits on the `nested-field-structs` branch.

### N1. Declaration accepts both class and symbol form

```ruby
required :address, Address       # class form (no registry involved)
required :address, :address      # symbol form (registry lookup); the
                                 # registered value may be a FieldStruct
                                 # subclass — DSL wraps it in Types::Nested
```

The class form is the documented path. No auto-registration.

### N2. Coercion inputs

- `nil` → `nil`
- An instance of the target struct (or subclass) → passthrough
- A `Hash` → `struct_class.new(hash)`
- Anything else → `TypeError`, handled by the parent's `coercion_policy`

### N3. Validity propagation — eager, single-message

When the setter sees an invalid nested struct at assignment time, it stamps `errors[:field] << "is invalid"` on the parent — matching Phase 1's "setter owns its field's errors" contract. Drill into `parent.field.errors` for the per-field breakdown. Nested mutations after assignment do **not** refresh the parent's view; callers must reassign or read the nested struct's own errors.

### N4. Inner construction errors propagate

`FieldStruct::UnknownAttributeError`, `FieldStruct::CoercionError`, etc. raised inside `struct_class.new(hash)` are *not* caught by the parent's `coercion_policy`. They surface to the caller as-is — they're structural rejections of the nested record, not parent-shape coercion failures. Only `TypeError` (the "you passed me something other than nil/instance/Hash" case) flows through the parent's policy.

### N5. Arrays of nested

`required :addresses, :array, of: Address` works — each Hash element coerces into an `Address` (and a single invalid element marks the array `'is invalid'` on the parent, eager). Symbol form `of: :address` also works when the symbol resolves to a FieldStruct subclass.

### N6. Implementation: wrapping type, not Base-as-type

`FieldStruct::Types::Nested.new(struct_class)` is a `Types::Base` subclass parameterized at construction. The DSL builds and holds one per nested Field (cached as `Field#type_instance`). `Field` accepts an optional pre-built `type_instance:` so parameterized types can flow through the same plumbing as stock scalar types.

---

## Phase 2+ backlog

Surfaced during design but explicitly deferred. Ordered roughly by likely value:

1. **Cross-field validation** — `validate { |record| ... }` blocks that run on `valid?` after per-field validation.
2. **Field-level coercion-policy override** — `field :x, :integer, coercion_policy: :raise` overrides the class default for one field.
3. **Custom RBS generator** — walks `Metadata`, emits `.rbs` files. Types' `ruby_type` consumed here.
4. **Union types** — `optional :payload, :union, of: [Payload, :boolean]`. Reuses `of:` as parameterization.
5. **Extended types** — `:uuid`, `:url`, `:email`, `:symbol`, `:enum`. Same plumbing, more types.
6. **Conversion to/from other formats** — CSV, XML, Avro, JSON-schema. Probably separate gems.
7. **Auto-generated documentation** — Markdown / HTML from Metadata. Probably a separate gem.
8. **`:binary` type** — if anyone asks.
9. **Frozen-on-construct sugar** — if `.freeze` proves insufficient.

---

## Glossary

| Term | Meaning |
|---|---|
| **Field** | A single declared attribute on a FieldStruct class. Holds name, type, required-ness, default, and options. |
| **Metadata** | The class-level collection of all `Field` declarations for a subclass. Inherited and merged via the class hierarchy. |
| **Type** | A class under `FieldStruct::Types::*` that knows how to coerce a value, decide what counts as "missing," and report its `ruby_type`. |
| **Registry** | `FieldStruct::Registry` — a name-to-type-class map, optionally parented to another registry. |
| **Base registry** | `FieldStruct.types`. Seeded with all v1 types. The default lookup target when no namespace declares its own. |
| **Namespace registry** | A `Registry` exposed by a module via `self.field_types`. Used by FieldStruct subclasses defined inside that namespace. |
| **Coercion policy** | Class-level setting (`:keep_raw` / `:replace` / `:raise`) controlling what happens when a value can't be coerced into the declared type. |
| **Missing** | A value-shaped emptiness defined per type. Used by `required` to decide validity. Distinct from "key absent in input." |
| **Mutability** | Class-level setting. Default mutable. `immutable!` blocks setters after construction. |
| **Unknown attributes** | Input keys that don't match any declared field. Handled per class via `unknown_attributes :ignore | :raise`. |
| **Slice** | An atomic, independently shippable unit of work in the Phase 1 plan. Maps to one or more conventional commits. |
