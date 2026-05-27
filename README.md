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

Extended types: `:symbol`, `:uuid`, `:url`, `:email`, `:binary`. The first four serve string-shaped use cases — `:uuid`/`:url`/`:email` pre-fill a sensible `format:` regex (overrideable per-field), `:binary` forces ASCII-8BIT encoding and treats whitespace bytes as meaningful (not "missing").

`:value` is a passthrough — useful when you want metadata for a field without committing to a shape.

### Union types

A field that may hold any of several types — each tried in declared order, first success wins:

```ruby
class Event < FieldStruct::Base
  optional :payload, :union, of: [Payload, :boolean]
  optional :id,      :union, of: %i[integer string]
end

Event.new(payload: { kind: 'click', value: 1 }).payload  # => #<Payload ...>
Event.new(payload: true).payload                          # => true
Event.new(id: '42').id                                    # => "42"   (string first)
```

Members can be Symbols (registered scalars or FieldStruct subclasses) or Class arguments (FieldStruct subclasses). If every member rejects the value, the union raises and the parent's `coercion_policy` engages. Declared order matters — pick deliberately when types overlap (`Integer` accepts `"42"`, `String` accepts `"42"` — the one listed first wins).

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

`default:` accepts a literal or any callable (Proc, Lambda, Method) that takes no arguments. The callable is invoked once per instance, so it's safe to use for per-instance values like timestamps or generated IDs:

```ruby
optional :created_at, :datetime, default: Time.method(:now)
optional :token,      :string,   default: -> { "tok-#{SecureRandom.hex(4)}" }
```

### Restricting values — `enum:` and `in:`

Two parallel options for "the coerced value must be one of these":

```ruby
required :status,    :string,  enum: %w[on off]
required :position,  :symbol,  enum: %i[before after]
required :page_size, :integer, in: [10, 20, 30]
required :amount,    :float,   in: 1.0..10.0
required :height,    :integer, in: 10..
required :start_on,  :date,    in: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)
```

- `enum: [...]` — string-like types (`:string`, `:symbol`, `:uuid`, etc.). Array of allowed values.
- `in:` — rangy types (`:integer`, `:float`, `:decimal`, `:date`, `:time`, `:datetime`). Either an Array or a Range (closed, half-open — anything that responds to `include?`).
- Both run post-coercion (`'10'` becomes `10` before the check) and emit `'is invalid'` on mismatch.
- Passing `enum:` to a rangy field — or `in:` to a string-like field — raises `ArgumentError` at class load.

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

A single field can override the class-level policy via `coercion_policy:`:

```ruby
class Mixed < FieldStruct::Base
  coercion_policy :keep_raw                       # class default
  required :strict_id, :integer, coercion_policy: :raise
  optional :lenient_count, :integer               # inherits :keep_raw
end
```

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

### `frozen!`

Make instances Ruby-frozen at the end of construction. Stricter than `immutable!` — any ivar mutation raises `FrozenError` (Ruby's mechanism, not ours).

```ruby
class FrozenConfig < FieldStruct::Base
  frozen!
  required :api_key, :string
end

c = FrozenConfig.new(api_key: 'sk-...')
c.frozen?     # => true
c.api_key = 'x' # => raises FrozenError
```

Independent of `immutable!` — pick `immutable!` for our custom error and check, `frozen!` for Ruby's built-in freeze. Both can stack.

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
    @field_types ||= FieldStruct.new_registry do
      register :money, Acme::Types::Money
    end
  end

  class Order < FieldStruct::Base
    required :price, :money     # resolved through Acme's registry, with FieldStruct.types as fallback
  end
end
```

`FieldStruct.new_registry` builds a new registry parented to `FieldStruct.types` and evaluates the block in the new registry's instance scope, so `register` works without a receiver. Pass `nil` for an unparented registry, or a different parent for a custom chain.

Lookup walks the class's containing modules from innermost outward, then falls back to `FieldStruct.types`.

## Cross-field validation

For checks that span more than one field, declare a `validate` block or point to an instance method. Both forms can be mixed and stacked.

```ruby
class Schedule < FieldStruct::Base
  required :start_date, :date
  required :end_date,   :date

  validate :ensure_chronological
  validate do |record|
    record.errors.add(:base, 'must span at least one day') if record.end_date == record.start_date
  end

  def ensure_chronological
    return unless start_date && end_date

    errors.add(:base, 'end_date must not precede start_date') if start_date > end_date
  end
end

bad = Schedule.new(start_date: '2024-02-01', end_date: '2024-01-15')
bad.errors[:base]   # => ['end_date must not precede start_date', 'must span at least one day']
bad.valid?          # => false
```

- Validators run on `valid?` (and once at the end of `initialize`, so a fresh instance has `errors[:base]` populated for inspection).
- `errors[:base]` is cleared at the start of each cross-field run, so stale entries don't pile up.
- Field-level errors written by setters (Phase 1's "setter owns its field's errors") are **not** cleared by `valid?` — only `:base` is.
- Validators are inherited by subclasses (the subclass receives a `dup` of the parent's list and can append).
- Symbol form `validate :name, :other` registers each as its own validator.

## Aliases — bridging external naming conventions

When a payload arrives with names that don't match your Ruby conventions — `EmailAddress` from a vendor API, `email_address` from a legacy table — declare `aliases:` and the import side routes it for you. Export with `aliased: true` re-serializes back to the original convention for round-tripping.

```ruby
class User < FieldStruct::Base
  required :email,      :string, aliases: ['EmailAddress', 'email_address']
  required :first_name, :string, aliases: ['FirstName']
end

# Import: any alias is accepted, routed to the canonical field.
User.new('EmailAddress' => 'a@b.com', 'FirstName' => 'Alice')
# => #<User email: "a@b.com", first_name: "Alice">

# Conflict: if both canonical and alias are in the input, canonical wins.
User.new(email: 'a@b.com', EmailAddress: 'never@y.com').email
# => "a@b.com"

# Export: opt in via aliased: true. Uses each field's first alias.
user.as_json(aliased: true)
# => { EmailAddress: 'a@b.com', FirstName: 'Alice' }
user.to_json(aliased: true)
# => '{"EmailAddress":"a@b.com","FirstName":"Alice"}'
```

- Aliases are import-and-export only — they do **not** define Ruby methods. `user.email` works; `user.EmailAddress` doesn't.
- `unknown_attributes :raise` treats aliases as known; only truly unknown keys raise.
- Aliases propagate through nested FieldStructs and arrays of nested when you serialize with `aliased: true`.

## Parsing JSON

`Klass.from_json(string)` parses with Oj and feeds the resulting hash through `.new` — so coercion, nested construction, `unknown_attributes`, and `coercion_policy` all engage the same way they do for direct calls.

```ruby
person = Person.from_json('{"name":"Alice","address":{"street":"1","city":"NYC"}}')
person.address.city  # => "NYC"

# Round-trips for every base type except :value (no type info to preserve).
restored = Person.from_json(person.to_json)
restored == person   # => true
```

A non-object root (`[...]`, `"hi"`, `42`, `null`) raises `ArgumentError`; malformed JSON propagates the underlying Oj parse error.

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
