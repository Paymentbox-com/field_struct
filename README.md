# FieldStruct

Typed POROs for Ruby — declare fields with enforced types, presence checks, and per-field validation. Mirrors the ActiveModel interface shape where it helps adoption, but reuses none of its code.

```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
  optional :tags, :array, of: :string
end

u = User.new(name: 'Alice', age: '30', tags: %w[admin staff])

u.name        # => "Alice"
u.age         # => 30           (coerced through the integer type)
u.tags        # => ["admin", "staff"]
u.valid?      # => true
u.attributes  # => { name: "Alice", age: 30, tags: ["admin", "staff"] }
u.to_json     # => '{"name":"Alice","age":30,"tags":["admin","staff"]}'

u.name = ''
u.valid?            # => false
u.errors[:name]     # => ["is required"]
```

## Installation

Add to your Gemfile:

```ruby
gem 'field_struct'
```

Or install directly:

```bash
gem install field_struct
```

Requires Ruby 3.0+.

## What FieldStruct is

- A typed-value-object foundation: declare attributes, get coercion + validation for free.
- A class-level `Metadata` collection per FieldStruct class, inspectable and introspectable.
- A pluggable type system, namespaced through a `Registry` that downstream code can extend or replace.
- ActiveModel-shaped at the public surface (`valid?`, `errors`, `attributes`, `as_json`, `to_json`, `model_name`, `to_model`) so Rails-adjacent code feels at home.

## What FieldStruct is not

- Not a database layer. It doesn't persist, query, or hold connections.
- Not a form object. It doesn't render or know about HTTP params.
- Not an ActiveModel replacement. Interface shape only — no AM code reuse.
- Not a hash-schema validator. Validation is per-field-on-assignment, not "check this hash against a schema."

## Declaring fields

Three macros declare fields; `field` is the primitive, `required` / `optional` are sugar that set the `required:` option.

```ruby
class Account < FieldStruct::Base
  field    :id,         :integer                    # neutral; defaults to optional
  required :email,      :string, format: /@/        # presence-checked + format
  optional :nickname,   :immutable_string           # coerced, then frozen
  optional :balance,    :decimal, default: '0'      # :decimal is an alias for :big_decimal
  optional :created_at, :datetime
  required :tags,       :array, of: :string         # element type is required
end
```

### Base types

`:string`, `:immutable_string`, `:integer`, `:float`, `:big_decimal` (aliased as `:decimal`), `:boolean`, `:date`, `:time`, `:datetime`, `:value`, and `:array` (parameterized via `of:`).

`:value` is a passthrough — useful when you want metadata for a field without committing to a shape.

### Nested FieldStructs

Pass a `FieldStruct::Base` subclass as the type to nest:

```ruby
class Address < FieldStruct::Base
  required :street, :string
  required :city,   :string
end

class Person < FieldStruct::Base
  required :name,      :string
  required :address,   Address
  optional :addresses, :array, of: Address     # arrays of nested too
end

Person.new(name: 'Alice', address: {street: '1', city: 'NYC'}).address
# => #<Address street: "1", city: "NYC">
```

- Accepts nil / a struct instance / a Hash (`Address.new(hash)` happens automatically).
- If the nested struct is invalid at assignment time, the parent gets `errors[:address] = ['is invalid']`. Drill into `parent.address.errors` for the per-field breakdown.
- Inner construction errors (e.g. `FieldStruct::UnknownAttributeError` from a nested class with `unknown_attributes :raise`) propagate to the caller rather than being caught by the parent's `coercion_policy`.
- `as_json` / `to_json` deep-walk nested structures.

### What "required" means

A required field is invalid when its **value** is missing after coercion — the *type* decides what "missing" means:

| Type | Missing if |
|---|---|
| `:string`, `:immutable_string` | nil, empty, or whitespace-only |
| `:integer`, `:float`, `:decimal` | nil only (`0` is valid) |
| `:boolean` | nil only (`false` is valid) |
| `:date`, `:time`, `:datetime` | nil only |
| `:array` | nil or empty |
| `:value` | nil only |

Defaults satisfy required — the value is what's checked, not whether the input hash contained the key.

## Class macros

Every macro is inherited by descendants and overridable.

### `coercion_policy`

What happens when a value can't be coerced into the declared type:

```ruby
class Strict < FieldStruct::Base
  coercion_policy :raise      # :keep_raw (default) | :replace | :raise
  required :age, :integer
end

Strict.new(age: 'abc')  # raises FieldStruct::CoercionError
```

- `:keep_raw` — store the raw uncoercible value, record `"could not be coerced: ..."`
- `:replace`  — store `nil`, record the same error
- `:raise`    — raise `FieldStruct::CoercionError` from the setter

### `immutable!`

Block reassignment after construction. Default mutable.

```ruby
class Config < FieldStruct::Base
  immutable!
  required :api_key, :string
end

c = Config.new(api_key: 'sk-...')
c.api_key = 'oops'   # raises FieldStruct::ImmutableError
```

### `unknown_attributes`

How `initialize` / `assign_attributes` respond to input keys that don't match any declared field:

```ruby
class Strict < FieldStruct::Base
  unknown_attributes :raise   # :ignore (default) | :raise
  required :name, :string
end

Strict.new(name: 'Alice', extra: 'x')  # raises FieldStruct::UnknownAttributeError
```

## Namespace registries

Each FieldStruct class resolves type names through a registry chain. Define a module-level `field_types` method to extend the default set inside a namespace:

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct::Registry.new(FieldStruct.types).tap do |r|
      r.register :money, Acme::Types::Money
    end
  end

  class Order < FieldStruct::Base
    required :price, :money     # resolved through Acme's registry, with FieldStruct.types as fallback
  end
end
```

Lookup walks the class's containing modules from innermost outward, then falls back to `FieldStruct.types`.

## ActiveModel-shaped surface

Mirroring AM's call sites so Rails-adjacent code feels at home:

```ruby
u = User.new(name: 'Alice')

u.valid?           # / u.invalid?
u.errors           # FieldStruct::Errors  ([] / add / clear / empty? / to_h / messages)
u.attributes       # / u.attribute_names
u.assign_attributes(name: 'Bob')
u.to_h             # alias of #attributes
u.as_json          # JSON-ready hash (Date/Time -> ISO-8601, BigDecimal -> string)
u.to_json          # via Oj
u.inspect          # #<User name: "Alice">
u.model_name       # FieldStruct::ModelName  (name / singular / plural / element)
u.to_model         # self
u == other         # structural equality (class + attributes)
```

## Development

```bash
bundle install
bin/rspec                          # run specs
COVERAGE=1 bin/rspec               # run specs with SimpleCov
bundle exec rubocop                # lint
bundle exec rake                   # all of the above
```

The plan-of-record for Phase 1 lives in [`docs/origin/plan.md`](docs/origin/plan.md).

## Contributing

Bug reports and pull requests are welcome at <https://github.com/Paymentbox-com/field_struct>. Contributors are expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
