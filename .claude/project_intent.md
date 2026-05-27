# FieldStruct — Project Intent

> What FieldStruct is, what it isn't, and the terminology used across the codebase. For the full design, decisions, and slice plan, see `docs/origin/plan.md`.

---

## What FieldStruct is

A Ruby library for building POROs ("Plain Old Ruby Objects") with declared attributes that have enforced types, presence checks, and validation.

A class collects its field declarations into a class-level **Metadata** object that can be inspected, introspected, and used downstream (e.g. to generate type signatures or documentation). Each field is backed by a **Type** class that knows how to coerce input values and decide what counts as a "missing" value. Types live in a **Registry** so different namespaces can extend or replace the base set.

## What FieldStruct isn't

- **Not a database layer.** It doesn't persist, query, or hold connections.
- **Not a form object.** It doesn't render or know about HTTP params.
- **Not an ActiveModel replacement.** It mirrors AM's *interface shape* in places, but reuses none of its code.
- **Not a schema validator.** Validation is per-field-on-assign, not "check this hash against a schema."

---

## Phase 1 scope (v0.1.0)

See `docs/origin/plan.md` for the in/out lists. At a glance:

**In:** DSL (`field` / `required` / `optional`), `Base`, `Metadata`, `Registry`, base types (string, immutable_string, integer, float, big_decimal+decimal alias, boolean, date, time, datetime, value, array-with-`of:`), per-field validation, class macros (`coercion_policy`, `immutable!`, `unknown_attributes`), `format:` option, AM-shaped surface, JSON output via Oj, structural equality.

**Out (deferred):** Nested FieldStructs, JSON import, aliases, cross-field validation, RBS generation, union types, CSV/XML/Avro conversion, docs generation, extended types.

---

## Domain models and terminology

| Term | Meaning |
|---|---|
| **Field** | A single declared attribute on a FieldStruct class. Holds name, type, required-ness, default, options. |
| **Metadata** | Class-level collection of all `Field` declarations. Inherited and merged via the class hierarchy. |
| **Type** | A class under `FieldStruct::Types::*` that knows how to coerce a value, decide what counts as "missing," and report its `ruby_type`. |
| **Registry** | `FieldStruct::Registry` — name-to-type-class map. Can have a parent for fallback lookup. |
| **Base registry** | `FieldStruct.types`. Seeded with v1 types. The default when no namespace declares its own. |
| **Namespace registry** | A `Registry` exposed by a module via `self.field_types`. Used by FieldStruct subclasses defined inside that namespace. Lookup walks the full Ruby nesting chain. |
| **Coercion policy** | Class macro (`:keep_raw` / `:replace` / `:raise`) controlling what happens when a value can't be coerced. Inherited by descendants. |
| **Missing** | A value-shaped emptiness defined per type (e.g. nil-only for integers, nil-or-empty for arrays). Used by `required` to decide validity. Distinct from "key absent in input hash." |
| **Mutability** | Class macro. Default mutable. `immutable!` blocks setters after `initialize`. |
| **Unknown attributes** | Input keys that don't match any declared field. Class macro: `unknown_attributes :ignore | :raise`. |
| **Slice** | An atomic, independently shippable unit of work in the Phase 1 plan. Maps to one or more conventional commits. |

---

## Design invariants

These hold across the codebase. Don't break them without surfacing.

1. **Tests ship with code.** No "tests in a follow-up commit" — every behavior change is a `feat:` or `fix:` commit that includes its specs.
2. **Class macros are inherited.** Any new configuration knob (coercion policy, mutability, etc.) walks the class-ancestry chain to resolve its value, and descendants can override.
3. **Setters own their field's errors.** Every assignment runs the full pipeline (coerce → store → presence → format) and rewrites that field's errors entry. `valid?` is a cheap read of `errors.empty?`.
4. **Explicit `require_relative`, no autoload.** New files under `lib/field_struct/` get a corresponding `require_relative` line in `lib/field_struct.rb`.
5. **Oj for JSON.** Never `JSON.parse` / `to_json` (built-in). Always `Oj.load` / `Oj.dump`.
6. **No code reuse from ActiveModel.** Mirroring the interface shape is fine; including modules or copying internals is not.

---

## When in doubt

- Re-read `docs/origin/plan.md`.
- Re-read `docs/origin/first_discussion.md` for the original intent.
- If the answer isn't in either, ask Adrian before guessing.
