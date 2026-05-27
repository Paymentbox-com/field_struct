# Changelog

All notable changes to FieldStruct are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
