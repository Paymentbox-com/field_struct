---
name: field-struct
description: Author, edit, and debug FieldStruct value classes in projects that depend on the field_struct gem — choosing field types and options, wiring coercion and validation, reading errors, and generating RBS for the models.
when_to_use: Use when defining or modifying a class that inherits from FieldStruct::Base (any field / required / optional declaration), when picking a field type or option, when debugging why an instance is invalid or a value didn't coerce, or when wiring JSON serialization or cross-field validation with field_struct.
---

# Working with FieldStruct

FieldStruct builds typed POROs: declare fields on a `FieldStruct::Base` subclass and
get coerced, typed accessors plus presence/format validation. **Construction and
validity are separate** — you can build an invalid instance; ask `valid?`.

## Read the bundled reference first

The gem ships a dense, example-first reference covering *every* type, option, and
macro. Read it before answering a non-trivial question — it matches the installed
version:

- Run `bundle show field_struct` and open `USAGE.md` at that path, or
- https://github.com/Paymentbox-com/field_struct/blob/main/USAGE.md

This skill is the **workflow and the mistakes to avoid**; `USAGE.md` is the catalog.

## Defining a model

```ruby
class User < FieldStruct::Base
  required :name,  :string                 # presence-checked
  optional :age,   :integer                # not presence-checked
  optional :email, :email                  # format-validated string subtype
  optional :tags,  :array, of: :string     # arrays need `of:`
end

u = User.new(name: 'Alice', age: '30')     # Hash arg; Symbol or String keys both work
u.age           # => 30   (coerced from "30")
u.valid?        # => true
u.attributes    # => { name: "Alice", age: 30, email: nil, tags: nil }
```

Steps when asked to build one:
1. Subclass `FieldStruct::Base`.
2. Use `required` for presence-checked fields, `optional` (or bare `field`) otherwise.
3. Pick a **registered type symbol** — `:string :integer :float :big_decimal`
   (`:decimal`) `:boolean :date :time :datetime :symbol :uuid :url :email :binary
   :value :array :union` — or pass another `FieldStruct::Base` subclass for a nested
   struct.
4. Add options (see scoping below). Common: `default:` (literal or a callable like
   `-> { Time.now }`), `desc:`.
5. For composites: `:array` requires `of: <type>`; `:union` requires `of: [a, b, …]`
   with ≥2 members; nested = pass the class.

## Mistakes to avoid (these are the ones that bite)

1. **Setters are permissive — don't "fix" them.** `user.age = "30"` is *valid*; the
   type coerces. Readers are typed; writers accept anything coercible. `nil` passes
   through as `nil` for nearly every type.
2. **`required` does NOT guarantee non-nil at runtime.** A required field can hold
   `nil` (coercion failed, or `:replace` policy, or never assigned). Validity is
   separate from construction — gate on `valid?`, never assume a required reader is
   present.
3. **Whitespace-only strings count as "missing"** for `:string` and its subtypes
   (`:uuid :url :email :immutable_string`). So `required :name, :string` with
   `name: "   "` is **invalid**. `:binary` is the exception (its whitespace bytes are
   real data — only nil/empty are missing).
4. **`:array` needs `of:`; `:union` needs `of: [...]` (≥2).** Omitting raises
   `ArgumentError` at class-definition time.
5. **Option scoping is enforced at declaration** (misuse raises `ArgumentError`):
   - `format:` → string-shaped + `:date`/`:time`/`:datetime` (regex, strftime string, or preset Symbol)
   - `enum:` → `:string`/`:symbol` (and subtypes) only — an `Array` of allowed values
   - `in:` → `:integer`/`:float`/`:decimal`/`:date`/`:time`/`:datetime` — an `Array` or `Range`
   - `round:` → `:float`/`:decimal` (Integer places, half up; keeps the field's type)
   - `base:` → `:integer` (radix 2..36 for strings; default 10, so `"010"` is 10)
   - `values:` → `:boolean` (a `{truthy:, falsy:}` Hash or a preset Symbol)
   - `strict:` → `:string` (and subtypes) / `:integer` (Boolean — refuse loose input instead of `to_s` / truncating)
   - `zone:` → `:time`/`:datetime` (`"UTC"`, `"±HH:MM"` or an IANA name like `"America/Denver"` for zone-less strings; no Rails names or abbreviations)
   - `sensitive:` → any type (mask the value in `inspect`)
   - `element:` → `:array` (a Hash of the element type's own options, e.g.
     `of: :integer, element: {strict: true}`; bad elements are reported by index — every one, the first five listed)
6. **Cross-field rules use `validate` + `errors.add(:base, …)`**, run at `valid?`.
   `errors[:base]` is cleared each `valid?`; per-field errors are owned by the setter.
   ```ruby
   validate :ends_after_start
   def ends_after_start
     errors.add(:base, 'end before start') if start && finish && finish < start
   end
   ```
7. **JSON**: `serialize :json, internal: 'externalKey'` maps keys; `as_json`/`to_json`
   apply it forward, `Klass.from_json(str)` reverse-maps. Everything round-trips
   **except `:value`** (no type info to restore). Uses **Oj**, not stdlib JSON.
8. **Unknown input keys are dropped by default** (`unknown_attributes :ignore`); set
   `unknown_attributes :raise` on the class to reject them. Do this at payment/API
   boundaries, on **every** struct that reads input: nested classes don't inherit it
   from the struct that holds them.
9. **Messages never echo values** (payments data stays out of logs): errors and raised
   errors name the field, expected type and input *class*. `sensitive: true` (any
   type) shows `[FILTERED]` in `inspect`/`pp`; readers, `to_h`, `as_json`/`to_json`
   still return the real value.
10. **Validity is computed on assignment.** Mutating a nested struct or array element
    in place (`rec.address.city = nil`, `rec.tags << 5`) doesn't refresh the parent's
    errors, and an in-place push isn't coerced. Assign the field again (or use
    `rec.with(address: ...)`) to re-validate.
11. **Immutable/frozen instances change by copy**: `rec.with(field: value)` returns a
    new instance; changed fields run the setter pipeline. Shallow, like `dup`.

## Upgrading field_struct

When bumping the gem, follow `UPGRADING.md` (shipped with the gem, next to
`USAGE.md`; or https://github.com/Paymentbox-com/field_struct/blob/main/UPGRADING.md).
It lists every visible change since 0.10 as **Symptom / Find / Fix / Why**; don't
guess from memory.

1. Read your old version from `Gemfile.lock` (`field_struct (x.y.z)`) and the target
   tag. Open `UPGRADING.md` (repo root, or `bundle show field_struct` after bumping)
   and read every section from the one after your old version to the target.
2. Bump the Gemfile tag. If the project uses **actionable** >= 1.6, field_struct
   must be >= 0.12 (its gemspec says so); if `oj` is pinned below 3.11.2, loosen it.
   `bundle update field_struct`.
3. Run every **Find** command in those sections from the project root; read each hit.
4. Apply the matching **Fix** to each real hit. Don't change behaviour you weren't
   asked to — e.g. keep a renamed reserved field's wire name with `serialize :json`.
5. Run the full suite. Match each failure against UPGRADING.md's symptom index and
   fix it; if nothing matches, follow its "If something else breaks" section.
6. If the project generates RBS with `FieldStruct::RBS.generate`, regenerate it and
   run Steep if the project does.
7. Report: old → new version, each entry that applied (file:line, fix), each Find
   with no hits, and anything left unexplained.

## Debugging an invalid instance

```ruby
i = Thing.new(...)
i.valid?           # => false
i.errors.to_h      # => { name: ["is required"], email: ["is invalid"] }
```

- `"is required"` → field is `required` and the value is *missing* (nil/empty/whitespace
  per the type). Often a whitespace string or a failed coercion that stored nil.
- `"is invalid"` → present but fails `format:`/`enum:`/`in:`, or a nested struct/array
  element is itself invalid (validity propagates up).
- `"could not be coerced: …"` → coercion raised; under the default `:keep_raw` the raw
  value is kept, under `:replace` it's nilled. Check the field's/class's
  `coercion_policy`.

## Extending types (namespaces)

A module exposes `self.field_types` (a registry parented to `FieldStruct.types`);
classes inside it resolve names through it.

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry do
      register :money, Acme::Types::Money   # a FieldStruct::Types::Base subclass
      register :dec,   :big_decimal         # alias to an existing name
    end
  end
end
```

A custom type subclasses `FieldStruct::Types::Base` and implements `#coerce` and
`#ruby_type` (override `#missing?` for a broader-than-nil notion).

## Typing the models (RBS)

`FieldStruct::RBS.generate(Klass)` emits RBS for the per-field accessors so Steep /
Solargraph can check `user.name`:

```ruby
puts FieldStruct::RBS.generate(User)
# class User < ::FieldStruct::Base
#   attr_reader name: ::String
#   def name=: (::String? value) -> ::String?
#   ...
```

Reader = the field's Ruby type, nullable when `optional`; the setter takes and
returns that type, nilable (since 0.12 — pass loose input through `new` /
`assign_attributes`, whose values are `Object?`). `rbs_type:` overrides a field's type. Generate RBS for nested/element classes too so references resolve. See
the README "Type signatures" section for a Rake-task wiring example.
