# Changelog

All notable changes to FieldStruct are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Nested FieldStructs** — declare `field :address, Address` where `Address < FieldStruct::Base`. Coerce nil / instance / Hash; eager `'is invalid'` stamp on the parent at assignment time; inner construction errors (`UnknownAttributeError`, `CoercionError`) propagate to the caller rather than being caught by the parent's `coercion_policy`. Arrays of nested work via `of:` (class or symbol form). `as_json` deep-walks. `Types::Nested` is the wrapping type; `Field` accepts a pre-built `type_instance:` so parameterized types flow through the same plumbing as stock types.
- **`Klass.from_json(string)`** — JSON import driven off Metadata. Parses with Oj, feeds through `initialize`, so coercion / nested construction / `unknown_attributes` / `coercion_policy` engage as normal. Non-object JSON roots raise `ArgumentError`; malformed JSON propagates the underlying parse error. Round-trips structurally for every base type except `:value`.
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
