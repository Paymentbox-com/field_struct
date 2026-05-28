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
   - `round:` → `:float`/`:decimal` (Integer places)
   - `values:` → `:boolean` (a `{truthy:, falsy:}` Hash or a preset Symbol)
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
   `unknown_attributes :raise` on the class to reject them.

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
#   def name=: (untyped value) -> untyped
#   ...
```

Reader = the field's Ruby type, nullable when `optional`; setter is `untyped`
(coercion). Generate RBS for nested/element classes too so references resolve. See
the README "Type signatures" section for a Rake-task wiring example.
