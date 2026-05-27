# Changelog

All notable changes to FieldStruct are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
